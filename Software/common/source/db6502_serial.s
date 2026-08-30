; ---------------------------------------------------------------------------
; LOAD "@" - a program arriving over the serial port
;
; The same trick the card uses: INLIN is diverted, so the lines coming off the
; ACIA go through the interpreter's own tokeniser and land in memory exactly as
; if they had been typed. Nothing in here knows about the tokenised format, and
; what travels down the wire is plain text - the very text LIST prints, and the
; very text a .BAS file on the card holds. A program can therefore be written
; on the Mac, sent here, edited, and saved to the card, with no conversion
; anywhere along the way.
;
;   LOAD "@"    replace the program with whatever the host sends
;   SAVE "@"    list the program out over the port
;
; tools/basicsend.py and tools/basicrecv.py are the other end of them.
;
; The protocol is one line at a time, paced by this end:
;
;   6502 -> host   ACK  ($06)   ready for a line
;   host -> 6502   text + CR    one BASIC line, at most 78 characters
;   6502 -> host   ACK          it is in memory, send the next
;   host -> 6502   EOT  ($04)   that was the last one
;   6502 -> host   CAN  ($18)   given up at this end - Ctrl+C, or an error
;
; Why an ACK per line rather than letting the bytes stream in: inserting a line
; means finding its place, moving everything behind it up and relinking the
; lot, which on a program of a few hundred lines takes far longer than the 16 ms
; a line spends on the wire at 19200 baud. The 256 byte RX ring would be run
; over inside the first second. Hardware handshaking would do instead, but that
; wants RTS wired through to the FTDI, and this way three wires are enough.
;
; While the receiver sits idle it repeats its ACK, so it does not matter which
; end is started first - a host that arrives late still hears one.
;
; SAVE "@" needs no handshake at all. The machine is the slow end there - LIST
; composes a line far slower than 19200 baud carries it away - and the host has
; nothing to keep up with. It ends with one EOT, the same byte LOAD "@" takes
; as "no more lines".
;
; Nothing here may ever block on the wire. The 6551 holds its transmitter off
; while /CTS is high, and /CTS comes from the far end's RTS - so for as long as
; nothing has the port open over there, not one byte leaves, and the driver's
; interrupt handler bails out early (its own "cts_high" branch). Meanwhile
; _acia_write_byte spins forever once the 256 byte transmit ring is full, with
; no way out. An idle receiver repeating its ACK fills that ring in about two
; minutes and hangs the machine past any Ctrl+C. ser_ack and ser_cancel below
; look at the ring first, and that is why.
; ---------------------------------------------------------------------------

        .segment "BASBUF"

; $00 only while the current line is still empty, which is the one moment at
; which repeating the ACK is safe - see ser_readbyte
ser_idle:       .res 1
ser_timer:      .res 2
ser_dropped:    .res 1          ; a save gave up - throw the rest of LIST away

        .segment "CODE"

SER_ACK = $06
SER_EOT = $04
SER_CAN = $18

; Command register bits, spelled out here because acia.s keeps its own copies
; to itself. Transmit interrupt enabled, RTS low - the same value
; _acia_write_byte writes, and the only thing it does that the ACIA can see.
ACIA_TX_ARM = %00000100
ACIA_TX_MASK = %11110011

; Poll loop iterations between one ACK and the next while idle. Something under
; a second at 1 MHz; the figure is not critical, it only decides how long a host
; that was started late waits before it sees the receiver.
SER_IDLE_RELOAD = 8000

; ---------------------------------------------------------------------------
; "LOAD @" statement, reached from LOAD in db6502_sdbasic.s
; ---------------------------------------------------------------------------
ser_load:
        jsr sd_ledon

        jsr ser_flush

        ; The status line is the card's own panel with a different name written
        ; into it, so the live line counter comes along for nothing
        lda #$00                        ; the LOAD panel, not the SAVE one
        jsr ser_panel

        stz ser_idle
        lda #SD_MODE_SERIAL
        sta sd_loadmode

        ; NEW. This also resets the stack to INIT_STACK, which is what is
        ; wanted here - the jump below never comes back.
        jsr SCRTCH

        ; Straight into the direct mode input loop. INLIN now takes its lines
        ; from the port, and ser_getline jumps to RESTART when the host is done.
        jmp L2351

; ---------------------------------------------------------------------------
; INLIN hook - the serial counterpart of sd_getline
;
; Hands back one line in INPUTBUFFER with X,Y pointing just in front of it,
; which is what INLIN promises its caller.
; ---------------------------------------------------------------------------
ser_getline:
        ; The ACK that acknowledges the line just inserted is the same one that
        ; asks for the next, so every line begins by sending it - the first one
        ; included, which is how the host learns the receiver is up.
        stz ser_idle
        jsr ser_ack

        ldx #$00
@char:
        jsr ser_readbyte
        bcs @cancelled
        cmp #SER_EOT
        beq @finished
        cmp #$1A                        ; DOS end of file, as on the card
        beq @finished
        cmp #$0D
        beq @endofline
        cmp #$0A
        beq @endofline
        cmp #$09
        bne @notab
        lda #' '
@notab:
        cmp #' '
        bcc @char                       ; drop any other control character
        cpx #78
        bcs @char                       ; overlong line - read it out, keep 78
        sta INPUTBUFFER,x
        inx
        stx ser_idle                    ; X can no longer be zero, so this says
        bra @char                       ; "line started" without a second store

@endofline:
        cpx #$00
        beq @char                       ; the LF of a CRLF, or an empty line
        lda #$00
        sta INPUTBUFFER,x
        jsr sd_lcdstep
        ldx #<(INPUTBUFFER-1)
        ldy #>(INPUTBUFFER-1)
        rts

@cancelled:
        ; Ctrl+C. Say so, rather than leaving the host to sit out its timeout
        ; with the rest of the program still to send.
        jsr ser_cancel
@finished:
        jmp sd_endload

; ---------------------------------------------------------------------------
; One byte off the serial port, blocking
;
; Carry set means Ctrl+C was pressed and the transfer is to be given up. That
; is the only way out, and deliberately so: a host that has gone away sends
; nothing ever again, and no timeout can tell one apart from a host that is
; merely slow.
;
; While the current line is still empty the ACK is repeated, which is what makes
; the order the two ends are started in not matter. Mid-line it is not repeated
; - an ACK there would put the host a line ahead of the receiver.
; ---------------------------------------------------------------------------
ser_readbyte:
        phx
        phy
@reload:
        lda #<SER_IDLE_RELOAD
        sta ser_timer
        lda #>SER_IDLE_RELOAD
        sta ser_timer+1
@poll:
        jsr _acia_is_data_available
        cmp #ACIA_DATA_AVAILABLE
        beq @arrived

        jsr ser_break
        bcs @abort

@tick:
        lda ser_timer
        bne @decrement
        lda ser_timer+1
        beq @expired
        dec ser_timer+1
@decrement:
        dec ser_timer
        bra @poll

@expired:
        lda ser_idle
        bne @reload                     ; mid-line: keep waiting, keep quiet
        jsr ser_ack
        bra @reload

@arrived:
        jsr _acia_read_byte
        ply
        plx
        clc
        rts

@abort:
        ply
        plx
        sec
        rts

; ---------------------------------------------------------------------------
; The only two bytes this end sends, and neither of them may block
;
; A repeated ACK is worth sending only when the ring is empty. A host waiting
; for one is served just as well by the ACK already queued, and one byte
; outstanding can never fill the ring - which is what keeps Ctrl+C reachable
; while the far end has the port closed and nothing can leave at all.
;
; In a transfer that is running the ring is always empty here: the host does
; not send a line until it has had the ACK for the one before, so that byte is
; long gone by the time the next one is due.
; ---------------------------------------------------------------------------
ser_ack:
        lda acia_tx_wptr
        cmp acia_tx_rptr
        beq @queue                      ; nothing waiting - a fresh ACK can go

        ; One is already waiting. Adding another would eventually fill the ring
        ; and block, but leaving it entirely alone is worse: the 6551 arms its
        ; transmit interrupt on the write to the command register, and a byte
        ; queued while /CTS was high has never been armed with a transmitter
        ; that could act on it. Nothing else re-arms it, so when /CTS finally
        ; drops the byte sits there for good and the transfer never starts.
        ;
        ; The command register write is the whole of what _acia_write_byte does
        ; that the ACIA can see, so this leaves the chip in the state the plain
        ; repeated write used to leave it in - with the ring held at one byte
        ; instead of filling up.
        jmp ser_arm

@queue:
        lda #SER_ACK
        jmp _acia_write_byte

; Tells the host the transfer is off. Called for Ctrl+C above, and from
; sd_finish when an error in a received line drops the interpreter back to the
; direct mode prompt with the load only half done. Room for it is all this
; needs - it does not have to be the only byte in flight.
ser_cancel:
        lda acia_tx_wptr
        sec
        sbc acia_tx_rptr
        cmp #$ff
        beq @full                       ; blocking here would hang the machine
        lda #SER_CAN
        jmp _acia_write_byte
@full:
        rts

; ---------------------------------------------------------------------------
; "SAVE @" statement, reached from SAVE in db6502_sdbasic.s
;
; Nothing here writes anything: it points MONCOUT at the wire and lets LIST run
; over the whole program, exactly the way a save to the card does. sd_putbyte
; sends every character on, sd_newline ends every line, and RESTART arrives at
; sd_finish, which comes back here for the EOT.
; ---------------------------------------------------------------------------
ser_save:
        jsr sd_ledon
        jsr ser_flush           ; a leftover ACK would be the first character
        lda #$01                ; the SAVE panel
        jsr ser_panel

        stz ser_dropped
        lda #SD_SAVE_SERIAL
        sta sd_savemode

        ; LIST ends in RESTART, where sd_finish sends the EOT and the prompt
        ; comes back - so drop the statement dispatcher's return address the
        ; way LIST itself does, instead of leaving it on the stack for good.
        pla
        pla

        lda TXTTAB
        sta LOWTRX
        lda TXTTAB+1
        sta LOWTRX+1
        lda #$FF
        sta LINNUM
        sta LINNUM+1
        jmp L25A6

; ---------------------------------------------------------------------------
; MONCOUT hook while a save to the wire is running
;
; Entered from sd_putbyte with X and Y already stacked and the byte waiting in
; sd_bytetmp, and it has to leave things the way that routine's own tail does.
; ---------------------------------------------------------------------------
ser_putbyte:
        lda ser_dropped
        bne @out                ; given up - let LIST run itself out unheard
        lda sd_bytetmp
        jsr ser_send
        bcc @out
        lda #$01                ; Ctrl+C during the wait
        sta ser_dropped
@out:
        ply
        plx
        lda sd_bytetmp
        rts

; ---------------------------------------------------------------------------
; sd_finish hook - the listing is over
; ---------------------------------------------------------------------------
ser_endsave:
        stz sd_savemode
        lda ser_dropped
        bne @gaveup
        lda #SER_EOT
        jmp ser_send            ; carry is nobody's business up here
@gaveup:
        ; A truncated listing is not a program. Say nothing and let the host
        ; time out rather than end it with the byte that means "all of it".
        rts

; ---------------------------------------------------------------------------
; One byte onto the wire, waiting for room in the transmit ring
;
; LIST composes characters faster than 19200 baud carries them, so this waits
; on nearly every one of them, and the wait has to stay interruptible: with
; nothing holding the port open at the other end the 6551 transmits nothing at
; all, and a plain _acia_write_byte would sit in its own spin loop for good.
;
; Carry set means Ctrl+C ended the wait and the byte was not sent.
; ---------------------------------------------------------------------------
ser_send:
        pha
@room:
        lda acia_tx_wptr
        sec
        sbc acia_tx_rptr
        cmp #$ff
        bcc @go
        jsr ser_arm             ; nothing moving - make sure it can
        jsr ser_break
        bcc @room
        pla
        sec
        rts
@go:
        pla
        jsr _acia_write_byte
        clc
        rts

; ---------------------------------------------------------------------------
; Arms the transmitter without putting anything in the ring
;
; The write to the command register is the whole of what _acia_write_byte does
; that the ACIA can see - the byte itself only ever reaches the chip from the
; interrupt handler. A byte queued while /CTS was high has never been armed
; with a transmitter that could act on it, and nothing else arms it again.
; ---------------------------------------------------------------------------
ser_arm:
        lda ACIA_COMMAND
        and #ACIA_TX_MASK
        ora #ACIA_TX_ARM
        sta ACIA_COMMAND
        rts

; ---------------------------------------------------------------------------
; Carry set if Ctrl+C is waiting on the keyboard
;
; Anything else typed is thrown away, which is what a transfer from the card
; does with it as well. May use X and Y - both callers have them stacked.
; ---------------------------------------------------------------------------
ser_break:
        jsr _keyboard_is_data_available
        cmp #KEYBOARD_DATA_AVAILABLE
        bne @none
        jsr _keyboard_read_char
        cmp #$03
        beq @yes
@none:
        clc
        rts
@yes:
        sec
        rts

; ---------------------------------------------------------------------------
; Empties both rings at the start of a transfer
;
; A transfer that was cut short leaves an ACK and a CAN in the transmit ring
; that never went out - the 6551 does not transmit while /CTS is high, and
; /CTS comes from the far end's RTS, so with nothing holding the port open over
; there not one byte leaves. Left alone they block every ACK the next transfer
; wants to send, and if they did go out, a CAN arriving late would tell the
; host that the transfer it has only just started is off. Anything in the
; receive ring would be read as the first line. None of it belongs to what is
; about to happen.
;
; Briefly with interrupts off: the handler moves the other end of both rings,
; and a write landing between the load and the store would leave a pointer one
; behind, which reads as 255 bytes outstanding.
; ---------------------------------------------------------------------------
ser_flush:
        sei
        lda acia_tx_rptr
        sta acia_tx_wptr
        lda acia_rx_wptr
        sta acia_rx_rptr
        cli
        rts

; ---------------------------------------------------------------------------
; Puts the card's own status panel up with SERIAL where the file name goes, so
; that the live line counter comes along for nothing. A = 0 for LOAD, 1 for
; SAVE, the same as sd_lcdbegin takes.
; ---------------------------------------------------------------------------
ser_panel:
        pha
        ldx #10
@name:
        lda ser_panelname,x
        sta sd_fatname,x
        dex
        bpl @name
        pla
        jmp sd_lcdbegin

; Eleven characters of raw FAT name, which is the form the status line expects
ser_panelname:
        .byte "SERIAL     "

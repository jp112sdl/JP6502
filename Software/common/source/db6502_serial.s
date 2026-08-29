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
;
; tools/basicsend.py is the other end of it.
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
; ---------------------------------------------------------------------------

        .segment "BASBUF"

; $00 only while the current line is still empty, which is the one moment at
; which repeating the ACK is safe - see ser_readbyte
ser_idle:       .res 1
ser_timer:      .res 2

        .segment "CODE"

SER_ACK = $06
SER_EOT = $04
SER_CAN = $18

; Poll loop iterations between one ACK and the next while idle. Something under
; a second at 1 MHz; the figure is not critical, it only decides how long a host
; that was started late waits before it sees the receiver.
SER_IDLE_RELOAD = 8000

; ---------------------------------------------------------------------------
; "LOAD @" statement, reached from LOAD in db6502_sdbasic.s
; ---------------------------------------------------------------------------
ser_load:
        jsr sd_ledon

        ; The status line is the card's own panel with a different name written
        ; into it, so the live line counter comes along for nothing
        ldx #10
@name:
        lda ser_panelname,x
        sta sd_fatname,x
        dex
        bpl @name
        lda #$00                        ; the LOAD panel, not the SAVE one
        jsr sd_lcdbegin

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
        lda #SER_ACK
        jsr _acia_write_byte

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

        jsr _keyboard_is_data_available
        cmp #KEYBOARD_DATA_AVAILABLE
        bne @tick
        jsr _keyboard_read_char
        cmp #$03
        beq @abort

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
        lda #SER_ACK
        jsr _acia_write_byte
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
; Tells the host the transfer is off. Called for Ctrl+C above, and from
; sd_finish when an error in a received line drops the interpreter back to the
; direct mode prompt with the load only half done.
; ---------------------------------------------------------------------------
ser_cancel:
        lda #SER_CAN
        jmp _acia_write_byte

; Eleven characters of raw FAT name, which is the form the status line expects
ser_panelname:
        .byte "SERIAL     "

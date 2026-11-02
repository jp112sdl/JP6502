; ---------------------------------------------------------------------------
; LOAD "NAME.BAS",8 - the floppy drive, device 8, the way a C64 has its 1541
;
; The drive is a PC floppy with a Raspberry Pi Pico of its own, on the ACIA
; through a switch that otherwise connects the FTDI - see
; Schematics/FLOPPY_PICO.md. It speaks the line protocol of LOAD "@" and
; SAVE "@" from db6502_serial.s, with a command in front of it:
;
;   LOAD "NAME.BAS",8   "L NAME    BAS"   then the lines of the file
;   SAVE "NAME.BAS",8   "S NAME    BAS"   then the listing
;   LOAD "$",8          "$"               then the directory, as program lines
;
; Each command is one line ending in CR, with the name in the raw FAT form
; sd_getname builds for the card anyway, and the drive answers it with one
; status line the way a 1541 does: "00,OK", "62,FILE NOT FOUND" and so on.
; Anything but 00 is shown as "?62,FILE NOT FOUND", on the screen and on the
; LCD. A SAVE is answered twice - once before the listing, once the file is
; on the disk.
;
; Everything after the answer is LOAD "@" or SAVE "@" as they stand, entered
; behind their own status panels so that the LCD shows the file name instead
; of SERIAL. The drive takes the part tools/basicsend.py and basicrecv.py
; play for the Mac, so tools/drivesim.py can stand in for it there.
; ---------------------------------------------------------------------------

        .segment "BASBUF"

disk_op:        .res 1          ; 'L', 'S' or '$' - the command for the drive
disk_saving:    .res 1          ; ser_endsave owes the drive's second answer -
                                ; ser_save clears it, BASBUF is not cleared at start
disk_timer:     .res 1          ; top byte of the wait, ser_timer has the rest

        .segment "CODE"

DISK_DEVICE     = 8

; The status line is put together in the card's sector buffer: the card is not
; in use while the drive is, and the line has to outlive the statement - an
; error returns to the interpreter, which still reads the rest of a direct mode
; line out of INPUTBUFFER.
DISK_MSG        = sd_sectorbuffer
DISK_MSG_LEN    = 30

; How long to wait for an answer - about ten seconds, which covers the motor
; spinning up, a seek, reading a disk that has just been put in, and writing a
; whole program after a SAVE. One round of the loop in disk_getc takes about
; ninety cycles; the figure is not critical.
.if clock_mhz > 0
DISK_WAIT       = 110000 * clock_mhz
.else
DISK_WAIT       = 28000
.endif

; ---------------------------------------------------------------------------
; Entered from LOAD and SAVE in db6502_sdbasic.s right after sd_getname. With
; no ",8" behind the name, carry and A come back exactly as sd_getname left
; them and the card goes on as before. With it, the statement is handled here
; to the end and this does not return to LOAD or SAVE.
; ---------------------------------------------------------------------------
disk_load:
        ldy #'L'
        .byte $2C
disk_save:
        ldy #'S'
        sty disk_op
        php
        pha
        jsr CHRGOT
        cmp #','
        beq @device
        pla
        plp
        rts

@device:
        jsr COMBYTE             ; the device number -> X
        cpx #DISK_DEVICE
        beq @eight
        jmp IQERR
@eight:
        pla                     ; sd_getname: carry set and '$' or '@' in A
        plp                     ; for an argument that is not a file name
        bcc @named
        cmp #'$'
        bne @syntax             ; "@",8 means nothing
        lda disk_op
        cmp #'L'
        bne @syntax             ; and neither does SAVE "$",8
        lda #'$'
        sta disk_op
        bra @go
@named:
        lda disk_op
        cmp #'S'
        bne @go
        jsr sd_checkname        ; a new entry needs a name FAT takes
        bcc @go
@syntax:
        jmp SYNERR

@go:
        ; LOAD and SAVE both end the statement, so from here on the way back
        ; is straight to the interpreter, as if this were LOAD or SAVE itself
        pla
        pla
        jsr sd_ledon
        jsr ser_flush           ; nothing left over may be taken for the answer

        lda disk_op
        jsr ser_send
        bcs @done               ; Ctrl+C
        lda disk_op
        cmp #'$'
        beq @endofcommand
        lda #' '
        jsr ser_send
        bcs @done
        ldx #$00
@name:
        lda sd_fatname,x
        phx                     ; ser_send may use X
        jsr ser_send
        plx
        bcs @done
        inx
        cpx #11
        bcc @name
@endofcommand:
        lda #$0D
        jsr ser_send
        bcs @done

        jsr disk_status
        bcs @done               ; and said so

        lda disk_op
        cmp #'S'
        beq @save
        cmp #'$'
        bne @load
        ; The panel shows sd_fatname, which "$" never filled in
        ldx #10
        lda #' '
@blank:
        sta sd_fatname,x
        dex
        bne @blank
        lda #'$'
        sta sd_fatname
@load:
        lda #$00                ; the LOAD panel
        jsr sd_lcdbegin
        jmp ser_loading

@save:
        lda #$01                ; the SAVE panel
        sta disk_saving
        jsr sd_lcdbegin
        jmp ser_saving

@done:
        rts

; ---------------------------------------------------------------------------
; The drive's answer, one line. Carry clear for "00". Anything else is shown
; with a question mark in front, silence as "?DEVICE NOT PRESENT" - carry set
; for both. Ctrl+C during the wait gives carry set and no message.
; ---------------------------------------------------------------------------
disk_status:
        lda #'?'
        sta DISK_MSG
        ldx #$01
@char:
        jsr disk_getc
        bcs @silent
        cmp #$0D
        beq @line
        cpx #DISK_MSG_LEN+1
        bcs @char               ; keep the first thirty, read the rest away
        sta DISK_MSG,x
        inx
        bra @char
@line:
        stz DISK_MSG,x
        lda DISK_MSG+1          ; "00" is the one good answer
        cmp #'0'
        bne @report
        lda DISK_MSG+2
        cmp #'0'
        bne @report
        clc
        rts

@silent:
        cmp #$03
        beq @quiet              ; Ctrl+C - nothing to explain
        lda #<disk_absent
        ldx #>disk_absent
        bra @show
@report:
        lda #<DISK_MSG
        ldx #>DISK_MSG
@show:
        sta sd_msgptr
        stx sd_msgptr+1
        jsr _tty_writeln
        lda sd_msgptr
        ldx sd_msgptr+1
        jsr sd_lcdmsg
@quiet:
        sec
        rts

; ---------------------------------------------------------------------------
; One byte from the drive. Carry set when none came within DISK_WAIT, A = 0,
; or Ctrl+C was pressed, A = 3. X and Y are kept.
;
; Every 256 rounds the transmitter is armed again. The command may still be
; sitting in the transmit ring: written while /CTS was high - over the FTDI,
; before tools/drivesim.py had the port open - it never reached a transmitter
; that could act on it, and nothing else arms it again (see ser_arm). This way
; it leaves as soon as /CTS drops, and it does not matter which end comes
; first. The Pico holds /CTS low for good, so there it changes nothing.
; ---------------------------------------------------------------------------
disk_getc:
        phx
        phy
        lda #<DISK_WAIT
        sta ser_timer
        lda #>DISK_WAIT
        sta ser_timer+1
        lda #^DISK_WAIT
        sta disk_timer
@poll:
        jsr _acia_is_data_available
        cmp #ACIA_DATA_AVAILABLE
        beq @arrived
        jsr ser_break
        bcs @break
        lda ser_timer
        bne @low
        jsr ser_arm
        lda ser_timer+1
        bne @middle
        lda disk_timer
        beq @timeout
        dec disk_timer
@middle:
        dec ser_timer+1
@low:
        dec ser_timer
        bra @poll

@arrived:
        jsr _acia_read_byte
        ply
        plx
        clc
        rts

@break:
        lda #$03
        .byte $2C
@timeout:
        lda #$00
        ply
        plx
        sec
        rts

disk_absent:
        .byte "?DEVICE NOT PRESENT", $00

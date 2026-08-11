; ---------------------------------------------------------------------------
; SD card support for BASIC: LOAD, SAVE and the "$" directory listing
;
; Programs live on the card as plain text, one BASIC line per text line,
; exactly the way LIST prints them. Nothing in here knows anything about the
; tokenised in-memory format:
;
;   LOAD  hands the file to INLIN one line at a time, so the normal direct
;         mode loop tokenises and inserts every line as if it had been typed.
;   SAVE  redirects MONCOUT into a sector buffer and runs LIST over the whole
;         program.
;
; Both directions therefore reuse the interpreter's own tokeniser, and a saved
; file can be edited on a PC.
;
;   LOAD              read BASIC.BAS
;   LOAD "NAME.BAS"   read NAME.BAS
;   LOAD "$"          replace the program with a listing of the card
;   SAVE              write BASIC.BAS
;   SAVE "NAME.BAS"   write NAME.BAS
;
; SAVE writes into the root directory. It creates the file if the card does not
; have it yet, and it rebuilds the cluster chain from scratch every time, so the
; result is exactly as long as the program - no matter what was there before.
;
; Both start by mounting the card from scratch, so it does not have to be in
; the slot at power-on and may be taken out and put back - or swapped - between
; commands.
;
; Three hooks in the interpreter drive all of this:
;   INLIN   (inline.s) calls sd_getline while a load is running
;   MONCOUT (db6502_extra.s) calls sd_putbyte while a save is running
;   CRDO    (print.s) calls sd_newline, which is the same for line ends
;   RESTART (program.s) calls sd_finish, which closes the file
; ---------------------------------------------------------------------------

.segment "CODE"

SD_MODE_OFF  = 0
SD_MODE_FILE = 1
SD_MODE_DIR  = 2

SD_NAME_COLUMN  = 13            ; width of the name field in a "$" line
SD_SIZE_COLUMN  = 5             ; width of the block count field
SD_DEC_DIGITS   = 5             ; digits rendered by sd_dec16

; Sector staging area for SAVE. It cannot share fat32_workspace, because
; fat32_writenextsector reads FAT sectors into that buffer while walking the
; cluster chain and would overwrite the data on its way out.
        .segment "SDBUF"
sd_sectorbuffer:
        .res 512

; These sit in the first page of BAS_RAM rather than in BSS. BSS is shared
; with every library module, so anything added here would push vdp_line and
; vdp_char_pos to new addresses. Only the top four bytes of this page belong
; to BASIC (INPUTBUFFER-4..-1, built by PUT_NEW_LINE), so the bottom is free.
        .segment "BASBUF"
sd_loadmode:    .res 1          ; SD_MODE_* - INLIN reads from the card while set
sd_savemode:    .res 1          ; non-zero while MONCOUT writes to the card
sd_fatname:     .res 11         ; target name in raw FAT form, no dot
sd_namelen:     .res 1
sd_bytetmp:     .res 1          ; byte in flight through sd_putbyte
sd_column:      .res 1          ; end of the current field while building a line
sd_eof:         .res 1          ; the file being loaded has run out
sd_wrindex:     .res 1          ; write position inside the current half page
sd_wrhalf:      .res 1          ; $00 = low half of sd_sectorbuffer, $80 = high
sd_wrcount:     .res 4          ; bytes handed to sd_putbyte so far
sd_wrerror:     .res 1          ; sticky - set by the first failed sector write
sd_lineno:      .res 2          ; line number for the next "$" line
sd_num:         .res 2          ; scratch for sd_dec16
sd_decbuf:      .res 5
sd_seen:        .res 1          ; leading zero suppression for sd_dec16
sd_lcdop:       .res 1          ; $00 = LOAD, non-zero = SAVE
sd_lcdcount:    .res 2          ; the number in the counter field
sd_lcdrow:      .res 1          ; row the panel routines are working on
sd_msgptr:      .res 2          ; message on its way to screen and LCD
sd_dirdone:     .res 1          ; the "$" listing has reached its last line
sd_decbuf32:    .res 10         ; sd_dec32 renders here

; libfat32.s keeps the variables of its allocating write path in here as well,
; for the same reason. The page is only free up to the four bytes below
; INPUTBUFFER, so make the linker say so if it ever fills up.
        .import __BASBUF_RUN__, __BASBUF_SIZE__
        .assert (__BASBUF_RUN__ + __BASBUF_SIZE__) <= (INPUTBUFFER-4), lderror, "BASBUF has grown into the BASIC line input buffer"

; The body lives in its own ROM block at $ec00 instead of in CODE. Appending
; ~1.1 KB to CODE moves every library module behind msbasic.o to a new
; address, and on this board that alone is enough to kill the VDP picture -
; a ROM built from unchanged sources plus 1110 dead filler bytes fails the
; same way. See MEMORY_MAP.md, section "SDCODE".
        .segment "SDCODE"

; ---------------------------------------------------------------------------
; "LOAD" statement
; ---------------------------------------------------------------------------
LOAD:
        jsr sd_getname
        bcs @directory

        ; The name is parsed first, so a bad one fails before the card is asked
        ; to do anything
        jsr sd_ledon
        jsr sd_mountpanel
        bcs @error

        ; Open before wiping the program - a missing file then leaves whatever
        ; is in memory alone
        lda #<sd_fatname
        ldx #>sd_fatname
        jsr _sd_openread
        bcs @error
        stz sd_eof
        lda #$00
        jsr sd_lcdbegin
        lda #SD_MODE_FILE
        bra @start

@directory:
        jsr sd_ledon
        jsr sd_mountpanel
        bcs @error
        jsr _sd_opendir
        bcs @error
        lda #<sd_lcddir
        ldx #>sd_lcddir
        jsr sd_lcdmsg
        stz sd_dirdone
        stz sd_lineno
        stz sd_lineno+1
        lda #SD_MODE_DIR

@start:
        sta sd_loadmode

        ; NEW. This also resets the stack to INIT_STACK, which is exactly what
        ; is wanted here - the jump below never comes back.
        jsr SCRTCH

        ; Straight into the direct mode input loop. INLIN now takes its lines
        ; from the card, and sd_getline jumps to RESTART once the file ends.
        jmp L2351

@error:
        jsr sd_reporterror
        rts

; ---------------------------------------------------------------------------
; "SAVE" statement
; ---------------------------------------------------------------------------
SAVE:
        jsr sd_getname
        bcs @syntax             ; SAVE "$" is not a thing

        ; A name that is about to bring a new entry into the directory has to
        ; be one that FAT accepts - see sd_checkname
        jsr sd_checkname
        bcs @syntax

        jsr sd_ledon
        jsr sd_mountpanel
        bcs @error

        lda #<sd_fatname
        ldx #>sd_fatname
        jsr _sd_beginsave
        bcs @error
        lda #$01
        jsr sd_lcdbegin

        stz sd_wrindex
        stz sd_wrhalf
        stz sd_wrerror
        stz sd_wrcount
        stz sd_wrcount+1
        stz sd_wrcount+2
        stz sd_wrcount+3
        lda #$01
        sta sd_savemode

        ; List the whole program with the output going to the card. LIST ends
        ; in RESTART, where sd_finish closes the file and prints OK - so drop
        ; the statement dispatcher's return address the way LIST itself does,
        ; instead of leaving it on the stack for good.
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

@syntax:
        jmp SYNERR

@error:
        jsr sd_reporterror
        rts

; ---------------------------------------------------------------------------
; Parses the name that follows LOAD or SAVE
;
; Accepts nothing at all (the default name), any string expression, or "$" for
; the directory. Returns carry clear with sd_fatname filled in, or carry set
; for "$".
; ---------------------------------------------------------------------------
sd_getname:
        jsr CHRGOT
        bne @expression

        ldx #10
@default:
        lda sd_defaultname,x
        sta sd_fatname,x
        dex
        bpl @default
        clc
        rts

@expression:
        jsr FRMEVL
        jsr FRESTR              ; A = length, INDEX points at the characters
        tax
        beq @syntax             ; LOAD "" has no file to open
        stx sd_namelen

        ldy #$00
        lda (INDEX),y
        cmp #'$'
        bne @convert
        cpx #$01
        beq @isdirectory

@convert:
        ; Space pad, then fill in the two halves separately - FAT stores the
        ; name and the extension as fixed length fields with no dot
        lda #' '
        ldy #10
@blank:
        sta sd_fatname,y
        dey
        bpl @blank

        ldy #$00                ; source index
        ldx #$00                ; destination index
@base:
        cpy sd_namelen
        beq @done
        lda (INDEX),y
        iny
        cmp #'.'
        beq @extension
        jsr sd_upcase
        cpx #8
        bcs @base               ; silently drop anything past eight characters
        sta sd_fatname,x
        inx
        bra @base

@extension:
        ldx #8
@extloop:
        cpy sd_namelen
        beq @done
        lda (INDEX),y
        iny
        jsr sd_upcase
        cpx #11
        bcs @extloop
        sta sd_fatname,x
        inx
        bra @extloop

@done:
        clc
        rts

@isdirectory:
        sec
        rts

@syntax:
        jmp SYNERR

sd_upcase:
        cmp #'a'
        bcc @out
        cmp #'z'+1
        bcs @out
        and #$DF
@out:
        rts

; ---------------------------------------------------------------------------
; Checks sd_fatname before it is used to create a directory entry
;
; LOAD takes whatever it is given - a file that is already on the card can be
; opened whatever it is called. SAVE cannot: an entry built from characters
; that FAT reserves would be unreadable on a PC, or worse, would look like
; something other than a file. Carry set means the name is unusable.
; ---------------------------------------------------------------------------
sd_checkname:
        lda sd_fatname
        cmp #' '
        beq @bad                ; nothing but padding is not a name

        ldy #10
@char:
        lda sd_fatname,y
        cmp #' '
        beq @next               ; padding, and only padding, may be a space
        cmp #'!'
        bcc @bad                ; control characters
        cmp #$7F
        bcs @bad                ; delete, and anything with the top bit set
        ldx #(sd_badchars_end - sd_badchars)-1
@scan:
        cmp sd_badchars,x
        beq @bad
        dex
        bpl @scan
@next:
        dey
        bpl @char
        clc
        rts

@bad:
        sec
        rts

; Wildcards, path separators and the characters DOS gave a meaning of their
; own. The dot never reaches sd_fatname - sd_getname takes it as the mark
; between name and extension - but it has no business in an entry either.
sd_badchars:
        .byte '"', '*', '+', ',', '.', '/', ':', ';'
        .byte '<', '=', '>', '?', '[', $5C, ']', '|'
sd_badchars_end:

; ---------------------------------------------------------------------------
; INLIN hook - produces the next line of the load into INPUTBUFFER
;
; Returns X/Y pointing at INPUTBUFFER-1, the way INLIN does. When the source
; runs out it closes the load and jumps to RESTART, which prints OK.
; ---------------------------------------------------------------------------
sd_getline:
        lda sd_loadmode
        cmp #SD_MODE_DIR
        beq @directory

        lda sd_eof
        bne sd_endload

        ldx #$00
@char:
        ; Reading a byte can pull in a whole sector, which destroys X and Y
        phx
        jsr _sd_readbyte
        plx                     ; leaves the carry from the read alone
        bcs @filedone
        cmp #$1A                ; DOS end of file marker
        beq @filedone
        cmp #$0D
        beq @endofline
        cmp #$0A
        beq @endofline
        cmp #$09
        bne @notab
        lda #' '
@notab:
        cmp #' '
        bcc @char               ; drop any other control character
        cpx #78
        bcs @char               ; overlong line - keep reading, drop the rest
        sta INPUTBUFFER,x
        inx
        bra @char

@endofline:
        lda #$00
        sta INPUTBUFFER,x
        bra @ready

@filedone:
        ; A file whose last line has no terminator still has to be handed over,
        ; so remember that this was the end and stop on the next call
        lda #$01
        sta sd_eof
        cpx #$00
        bne @endofline
        bra sd_endload

@directory:
        jsr sd_dirnextline
        bcs sd_endload

@ready:
        jsr sd_lcdstep
        ldx #<(INPUTBUFFER-1)
        ldy #>(INPUTBUFFER-1)
        rts

sd_endload:
        stz sd_loadmode
        jsr sd_ledoff
        ; The stack is at most a couple of levels deep here - every inserted
        ; line went through FIX_LINKS, which resets it - so dropping this
        ; frame and restarting the interpreter is safe.
        jmp RESTART

; ---------------------------------------------------------------------------
; Builds the next line of a "$" listing in INPUTBUFFER
;
; The whole entry is put inside one string literal so that nothing in it can
; ever be mistaken for a keyword by the tokeniser.
;
;   0 "SD CARD"
;   1 "HELLO.BAS        1"
;   2 "SUBFLDR        DIR"
;
; Carry set means the directory has been read to the end.
; ---------------------------------------------------------------------------
sd_dirnextline:
        lda sd_lineno
        ora sd_lineno+1
        beq @header

@skip:
        jsr _sd_nextdirent
        bcs @trailer
        lda sd_direntattr
        and #FAT32_ATTR_VOLUME
        bne @skip
        bra @entry

@trailer:
        ; The entries have run out, so one last line says how much room is left
        lda sd_dirdone
        bne @finished
        inc sd_dirdone
        jmp sd_dirfreeline

@finished:
        sec
        rts

@header:
        jsr sd_putlineno
        ldy #$00
@headerloop:
        lda sd_headertext,y
        sta INPUTBUFFER,x
        beq @headerdone
        inx
        iny
        bra @headerloop
@headerdone:
        jmp @emitted

@entry:
        jsr sd_putlineno

        lda #'"'
        sta INPUTBUFFER,x
        inx
        stx sd_column           ; remember where the name field starts

        ; Base name, trailing spaces dropped
        ldy #$00
@baseloop:
        lda sd_direntname,y
        cmp #' '
        beq @basedone
        sta INPUTBUFFER,x
        inx
        iny
        cpy #8
        bcc @baseloop
@basedone:

        ; Extension, only if there is one
        lda sd_direntname+8
        cmp #' '
        beq @nameready
        lda #'.'
        sta INPUTBUFFER,x
        inx
        ldy #8
@extloop:
        lda sd_direntname,y
        cmp #' '
        beq @nameready
        sta INPUTBUFFER,x
        inx
        iny
        cpy #11
        bcc @extloop

@nameready:
        ; Pad the name out to a fixed width so the numbers line up
        lda sd_column
        clc
        adc #SD_NAME_COLUMN
        sta sd_column
@padloop:
        cpx sd_column
        bcs @padded
        lda #' '
        sta INPUTBUFFER,x
        inx
        bra @padloop
@padded:

        lda sd_direntattr
        and #FAT32_ATTR_DIRECTORY
        bne @isdir

        jsr sd_blockcount       ; size in 512 byte blocks -> sd_num
        phx                     ; sd_dec16 needs X for itself
        jsr sd_dec16
        plx
        ldy #$00
@sizeloop:
        lda sd_decbuf,y
        sta INPUTBUFFER,x
        inx
        iny
        cpy #SD_SIZE_COLUMN
        bcc @sizeloop
        bra @closequote

@isdir:
        ldy #$00
@dirloop:
        lda sd_dirtext,y
        sta INPUTBUFFER,x
        inx
        iny
        cpy #SD_SIZE_COLUMN
        bcc @dirloop

@closequote:
        lda #'"'
        sta INPUTBUFFER,x
        inx
        lda #$00
        sta INPUTBUFFER,x

@emitted:
        inc sd_lineno
        bne @out
        inc sd_lineno+1
@out:
        clc
        rts

; Writes sd_lineno and a space at the start of INPUTBUFFER, leaving X on the
; next free column.
sd_putlineno:
        lda sd_lineno
        sta sd_num
        lda sd_lineno+1
        sta sd_num+1
        jsr sd_dec16

        ldx #$00
        ldy #$00
@leading:
        lda sd_decbuf,y
        iny
        cmp #' '
        beq @leading
@copy:
        sta INPUTBUFFER,x
        inx
        cpy #SD_DEC_DIGITS
        bcs @space
        lda sd_decbuf,y
        iny
        bra @copy
@space:
        lda #' '
        sta INPUTBUFFER,x
        inx
        rts

; Turns sd_direntsize into a count of 512 byte blocks in sd_num, rounded up
; and clamped to 65535.
sd_blockcount:
        clc
        lda sd_direntsize
        adc #$FF
        lda sd_direntsize+1
        adc #$01
        sta sd_num
        lda sd_direntsize+2
        adc #$00
        sta sd_num+1
        lda sd_direntsize+3
        adc #$00
        lsr                     ; >>9 in total: one whole byte, then one bit
        ror sd_num+1
        ror sd_num
        cmp #$00                ; the rors leave A alone - it holds bits 16 up
        beq @out
        lda #$FF                ; more blocks than will fit in the field
        sta sd_num
        sta sd_num+1
@out:
        rts

; Renders sd_num into sd_decbuf as five digits, leading zeros blanked.
; sd_num is destroyed.
; X indexes the digits and Y the power table, not the other way round - there
; is no "inc abs,y".
sd_dec16:
        stz sd_seen
        ldx #$00                ; index into sd_decbuf
        ldy #$00                ; index into sd_pow10
@digit:
        lda #'0'-1
        sta sd_decbuf,x
@subtract:
        inc sd_decbuf,x
        sec
        lda sd_num
        sbc sd_pow10,y
        sta sd_num
        lda sd_num+1
        sbc sd_pow10+1,y
        sta sd_num+1
        bcs @subtract
        ; One subtraction too many - put it back
        clc
        lda sd_num
        adc sd_pow10,y
        sta sd_num
        lda sd_num+1
        adc sd_pow10+1,y
        sta sd_num+1

        cpy #8
        beq @keep               ; the units digit is always printed
        lda sd_seen
        bne @keep
        lda sd_decbuf,x
        cmp #'0'
        bne @keep
        lda #' '
        sta sd_decbuf,x
        bra @next
@keep:
        lda #$01
        sta sd_seen
@next:
        inx
        iny
        iny
        cpy #10
        bne @digit
        rts

sd_pow10:
        .word 10000, 1000, 100, 10, 1

; ---------------------------------------------------------------------------
; MONCOUT hook - buffers one byte of the save
;
; A, X and Y all survive: this runs from the middle of the LIST loop, which
; keeps its position in the program line in Y.
; ---------------------------------------------------------------------------
sd_putbyte:
        sta sd_bytetmp
        phx
        phy

        ; OUTDO wraps the output whenever POSX reaches the terminal width, and
        ; that CRDO would land in the middle of a listed line. Keeping the
        ; column at zero turns the wrap off for as long as the save runs.
        stz POSX

        lda sd_wrerror
        bne @out

        ldy sd_wrindex
        lda sd_bytetmp
        bit sd_wrhalf
        bmi @high
        sta sd_sectorbuffer,y
        bra @advance
@high:
        sta sd_sectorbuffer+256,y
@advance:
        iny
        sty sd_wrindex
        bne @count

        ; The half page just filled up
        lda sd_wrhalf
        eor #$80
        sta sd_wrhalf
        bmi @count              ; only the low half is full so far
        jsr sd_flushsector

@count:
        inc sd_wrcount
        bne @out
        inc sd_wrcount+1
        bne @out
        inc sd_wrcount+2
        bne @out
        inc sd_wrcount+3

@out:
        ply
        plx
        lda sd_bytetmp
        rts

; ---------------------------------------------------------------------------
; CRDO hook - one line end, to the card or to the screen
; ---------------------------------------------------------------------------
sd_newline:
        lda sd_savemode
        bne @tocard
        jmp _tty_send_newline
@tocard:
        phx
        phy
        jsr sd_lcdstep
        ply
        plx
        lda #$0D
        jsr sd_putbyte
        lda #$0A
        jmp sd_putbyte

; ---------------------------------------------------------------------------
; Hands sd_sectorbuffer to the card. Failures are sticky, so the rest of the
; listing is simply thrown away instead of writing a torn file.
; ---------------------------------------------------------------------------
sd_flushsector:
        lda #<sd_sectorbuffer
        ldx #>sd_sectorbuffer
        jsr _sd_putnext
        bcc @out
        lda #$01
        sta sd_wrerror
@out:
        rts

; ---------------------------------------------------------------------------
; RESTART hook - closes whatever was in progress
;
; Reaching the direct mode prompt always means the transfer is over, whether
; LIST ran out of program or an error cut it short.
; ---------------------------------------------------------------------------
sd_finish:
        jsr sd_panelprompt
        lda sd_loadmode
        beq @checksave
        ; An error interrupted a load - back to the keyboard
        stz sd_loadmode

@checksave:
        lda sd_savemode
        bne @closefile
        rts

@closefile:
        ; Clear this first, so anything printed below goes to the screen
        stz sd_savemode

        lda sd_wrerror
        bne @failed

        ; Zero fill and write out whatever is left in the buffer
        lda sd_wrindex
        ora sd_wrhalf
        beq @sized

        ldy sd_wrindex
        lda sd_wrhalf
        bmi @fillhigh
        lda #$00
@filllow:
        sta sd_sectorbuffer,y
        iny
        bne @filllow
@fillhigh:
        lda #$00
@fillhighloop:
        sta sd_sectorbuffer+256,y
        iny
        bne @fillhighloop

        jsr sd_flushsector
        lda sd_wrerror
        bne @failed

@sized:
        lda sd_wrcount
        sta sd_length
        lda sd_wrcount+1
        sta sd_length+1
        lda sd_wrcount+2
        sta sd_length+2
        lda sd_wrcount+3
        sta sd_length+3
        jsr _sd_endsave
        bcs @failed
        jmp sd_ledoff

@failed:
        ; The chain built so far is incomplete and nothing points at it, so
        ; hand it back rather than leaving clusters that only a chkdsk on a PC
        ; would find again
        jsr _sd_abortsave
        jmp sd_reporterror

; ---------------------------------------------------------------------------
; The body and the message texts sit in the LCDCODE block further down, where
; there is room - see the comment there.
sd_reporterror:
        jmp sd_report

; ---------------------------------------------------------------------------
; The name used when LOAD or SAVE is given no argument. Raw FAT form: eight
; characters, three characters, space padded, no dot.
sd_defaultname:
        .byte "BASIC   BAS"

sd_headertext:
        .byte $22, "SD CARD", $22, $00

sd_dirtext:
        .byte "  DIR"

; ---------------------------------------------------------------------------
; Drive light and status line
;
; These live in EXTCODE, the second fixed ROM block at $e700, which is where
; anything added after the ROM layout was frozen goes - see MEMORY_MAP.md
; section 5.2. The area had never carried anything on this board; the status
; line was deliberately put there first, as something small and plainly visible
; that would show whether the block works. It does.
;
; The light behaves like the one on a 1541: on while the card is in use, out
; again when the command finished cleanly, still on if it did not.
;
; The status line is the bottom row of the display, which nothing writes to
; after the boot messages have scrolled off:
;
;   LOAD HELLO.BAS  012      (twelve lines so far)
;   SAVE PROG.BAS   003
;   ?NO SUCH FILE
;
; Column 19 is deliberately never written. Reaching the end of the last row
; makes lcd_wrap_line scroll the whole display up and wait 150 ms, which would
; both throw the line away and make every update painfully slow.
; ---------------------------------------------------------------------------
        .segment "EXTCODE"

; The four rows, top to bottom. The banner and the free memory line are
; repainted at every direct mode prompt, the card line whenever the card is
; mounted, and the status line as a transfer runs.
LCD_BANNER_ROW  = 0
LCD_CARD_ROW    = 1
LCD_FREE_ROW    = 2
LCD_STATUS_ROW  = LCD_ROWS-1

LCD_OP_WIDTH    = 5             ; "LOAD " / "SAVE "
LCD_NAME_WIDTH  = 11
LCD_COUNT_COL   = LCD_OP_WIDTH + LCD_NAME_WIDTH
LCD_COUNT_WIDTH = 3
SD_DEC32_DIGITS = 10

; ---------------------------------------------------------------------------
; Mounts the card and says on the panel how that went.
;
; The cursor is parked on the card row first: sd_init prints "SD not
; initialized" wherever the cursor happens to be, and that row is exactly what
; the message is about. From the status row it would run over the row boundary
; and scroll the panel away. sd_init is in CODE and cannot be changed, so this
; is the way round it.
; ---------------------------------------------------------------------------
sd_mountpanel:
        ldy #LCD_CARD_ROW
        ldx #$00
        jsr lcd_set_position

        jsr _sd_mount
        php
        bcc @ready
        lda #<sd_lcdnocard
        ldx #>sd_lcdnocard
        bra @show
@ready:
        lda #<sd_lcdready
        ldx #>sd_lcdready
@show:
        ldy #LCD_CARD_ROW
        jsr sd_lcdrowmsg
        plp
        rts

; ---------------------------------------------------------------------------
; Repaints the two rows that are not tied to an event. Called from sd_finish,
; which RESTART reaches on every return to the direct mode prompt - so the
; panel puts itself back together after anything that disturbed it.
; ---------------------------------------------------------------------------
sd_panelprompt:
        lda #<sd_lcdbanner
        ldx #>sd_lcdbanner
        ldy #LCD_BANNER_ROW
        jsr sd_lcdrowmsg

        ; The same figure PRINT FRE(0) gives: what is left between the top of
        ; the variables and the bottom of string space.
        sec
        lda FRETOP
        sbc STREND
        sta sd_num
        lda FRETOP+1
        sbc STREND+1
        sta sd_num+1
        jsr sd_dec16

        lda #LCD_FREE_ROW
        sta sd_lcdrow
        jsr sd_lcdblank
        ldy #$00                        ; the blanks sd_dec16 leaves right align it
@digit:
        lda sd_decbuf,y
        phy
        jsr _lcd_print_char
        ply
        iny
        cpy #SD_DEC_DIGITS
        bcc @digit
        lda #<sd_lcdbytes
        ldx #>sd_lcdbytes
        jmp _lcd_print

; ---------------------------------------------------------------------------
; Starts a transfer display. A is zero for LOAD, non-zero for SAVE.
; ---------------------------------------------------------------------------
sd_lcdbegin:
        sta sd_lcdop
        stz sd_lcdcount
        stz sd_lcdcount+1

        lda #LCD_STATUS_ROW
        sta sd_lcdrow
        jsr sd_lcdblank
        lda sd_lcdop
        beq @load
        lda #<sd_lcdsave
        ldx #>sd_lcdsave
        bra @op
@load:
        lda #<sd_lcdload
        ldx #>sd_lcdload
@op:
        jsr _lcd_print
        jsr sd_lcdname
        bra sd_lcdcounter

; ---------------------------------------------------------------------------
; Puts sd_fatname on the display as 8.3, padded out to the width of the field.
; A name that uses all eleven characters plus the dot loses its last character
; rather than pushing the counter along.
; ---------------------------------------------------------------------------
sd_lcdname:
        ldx #$00                        ; columns used so far
        ldy #$00
@base:
        lda sd_fatname,y
        cmp #' '
        beq @basedone
        jsr sd_lcdchar
        iny
        cpy #$08
        bcc @base
@basedone:
        lda sd_fatname+8
        cmp #' '
        beq @pad
        lda #'.'
        jsr sd_lcdchar
        ldy #$08
@ext:
        lda sd_fatname,y
        cmp #' '
        beq @pad
        cpx #LCD_NAME_WIDTH
        bcs @pad
        jsr sd_lcdchar
        iny
        cpy #$0B
        bcc @ext
@pad:
        cpx #LCD_NAME_WIDTH
        bcs @done
        lda #' '
        jsr sd_lcdchar
        bra @pad
@done:
        rts

; ---------------------------------------------------------------------------
; Redraws the counter field. LOAD counts the blocks still to come, SAVE the
; blocks written so far, so either way it is a number that keeps moving.
; ---------------------------------------------------------------------------
sd_lcdcounter:
        lda sd_lcdcount
        sta sd_num
        lda sd_lcdcount+1
        sta sd_num+1

        ; Three columns, so anything above 999 just sits there
        lda sd_num+1
        cmp #>1000
        bcc @fits
        bne @clamp
        lda sd_num
        cmp #<1000
        bcc @fits
@clamp:
        lda #<999
        sta sd_num
        lda #>999
        sta sd_num+1
@fits:
        jsr sd_dec16

        ldy #LCD_STATUS_ROW
        ldx #LCD_COUNT_COL
        jsr lcd_set_position
        ldy #(SD_DEC_DIGITS-LCD_COUNT_WIDTH)
@digit:
        lda sd_decbuf,y
        cmp #' '
        bne @print
        lda #'0'                        ; sd_dec16 blanks leading zeros
@print:
        phy
        jsr _lcd_print_char
        ply
        iny
        cpy #SD_DEC_DIGITS
        bcc @digit
        rts

; ---------------------------------------------------------------------------
; One more line went past: read from the card, written to it, or listed out of
; the directory.
;
; Lines rather than 512 byte blocks, because that is the unit these files come
; in - a BASIC program of a few hundred bytes is nought blocks all the way
; through, and a counter that never moves is worse than none.
; ---------------------------------------------------------------------------
sd_lcdstep:
        inc sd_lcdcount
        bne sd_lcdcounter
        inc sd_lcdcount+1
        bra sd_lcdcounter

; ---------------------------------------------------------------------------
; Replaces the status line with a message, blanking whatever was there
; ---------------------------------------------------------------------------
sd_lcdmsg:
        stz sd_lcdcount                 ; "LOAD $" counts entries from zero
        stz sd_lcdcount+1
        ldy #LCD_STATUS_ROW

; A/X = zero terminated text, Y = row. Blanks the row, then prints.
sd_lcdrowmsg:
        sta sd_msgptr
        stx sd_msgptr+1
        sty sd_lcdrow
        jsr sd_lcdblank
        lda sd_msgptr
        ldx sd_msgptr+1
        jmp _lcd_print

; Blanks the row in sd_lcdrow and leaves the cursor at its first column
sd_lcdblank:
        jsr @gohome
        ldx #(LCD_COLUMNS-1)            ; never the last column - see above
@blank:
        phx
        lda #' '
        jsr _lcd_print_char
        plx
        dex
        bne @blank
@gohome:
        ldy sd_lcdrow
        ldx #$00
        jmp lcd_set_position

; Prints one character and counts the column it used
sd_lcdchar:
        phy
        phx
        jsr _lcd_print_char
        plx
        ply
        inx
        rts

; ---------------------------------------------------------------------------
; The line LOAD "$" ends on, the way a C64 finishes a directory:
;
;   14 "7654321 BLOCKS FREE"
;
; A block is 512 bytes here, the same unit the size column uses. The figure
; comes out of the FSInfo block, which the write path keeps in step - counting
; the FAT itself would mean reading thousands of sectors. A card that carries
; no usable count gets "??? BLOCKS FREE" rather than a made up number.
; ---------------------------------------------------------------------------
sd_dirfreeline:
        ; Ask the card first. Both this and sd_dec32 go right through X, which
        ; is the column the line is being built at, so neither can run in the
        ; middle of building it.
        jsr _sd_freeblocks
        php

        jsr sd_putlineno                ; leaves X on the next column
        lda #'"'
        sta INPUTBUFFER,x
        inx

        plp
        bcs @unknown

        phx
        jsr sd_dec32
        plx
        ldy #$00
@lead:
        lda sd_decbuf32,y               ; skip the blanked leading zeros
        iny
        cmp #' '
        beq @lead
@copy:
        sta INPUTBUFFER,x
        inx
        cpy #SD_DEC32_DIGITS
        bcs @text
        lda sd_decbuf32,y
        iny
        bra @copy

@unknown:
        ldy #$03
@question:
        lda #'?'
        sta INPUTBUFFER,x
        inx
        dey
        bne @question

@text:
        ldy #$00
@append:
        lda sd_blocksfree,y
        beq @close
        sta INPUTBUFFER,x
        inx
        iny
        bra @append
@close:
        lda #'"'
        sta INPUTBUFFER,x
        inx
        lda #$00
        sta INPUTBUFFER,x
        clc
        rts

sd_blocksfree:
        .byte " BLOCKS FREE", $00

; ---------------------------------------------------------------------------
; Renders sd_freeblocks into sd_decbuf32 as ten digits with the leading zeros
; blanked. sd_freeblocks is destroyed.
;
; Same repeated subtraction as sd_dec16, over four bytes instead of two - the
; free space on a card runs well past what sixteen bits can hold.
; ---------------------------------------------------------------------------
sd_dec32:
        stz sd_seen
        ldx #$00                        ; index into sd_decbuf32
        ldy #$00                        ; index into sd_pow10_32
@digit:
        lda #'0'-1
        sta sd_decbuf32,x
@subtract:
        inc sd_decbuf32,x
        sec
        lda sd_freeblocks
        sbc sd_pow10_32,y
        sta sd_freeblocks
        lda sd_freeblocks+1
        sbc sd_pow10_32+1,y
        sta sd_freeblocks+1
        lda sd_freeblocks+2
        sbc sd_pow10_32+2,y
        sta sd_freeblocks+2
        lda sd_freeblocks+3
        sbc sd_pow10_32+3,y
        sta sd_freeblocks+3
        bcs @subtract

        ; One subtraction too many - put it back
        clc
        lda sd_freeblocks
        adc sd_pow10_32,y
        sta sd_freeblocks
        lda sd_freeblocks+1
        adc sd_pow10_32+1,y
        sta sd_freeblocks+1
        lda sd_freeblocks+2
        adc sd_pow10_32+2,y
        sta sd_freeblocks+2
        lda sd_freeblocks+3
        adc sd_pow10_32+3,y
        sta sd_freeblocks+3

        cpy #(4*(SD_DEC32_DIGITS-1))
        beq @keep                       ; the units digit is always printed
        lda sd_seen
        bne @keep
        lda sd_decbuf32,x
        cmp #'0'
        bne @keep
        lda #' '
        sta sd_decbuf32,x
        bra @next
@keep:
        lda #$01
        sta sd_seen
@next:
        inx
        iny
        iny
        iny
        iny
        cpy #(4*SD_DEC32_DIGITS)
        bne @digit
        rts

sd_pow10_32:
        .dword 1000000000, 100000000, 10000000, 1000000, 100000
        .dword 10000, 1000, 100, 10, 1

; ---------------------------------------------------------------------------
; The drive light
; ---------------------------------------------------------------------------
sd_ledon:
        lda #$01
        jmp _blink_led

sd_ledoff:
        lda #$00
        jmp _blink_led

; ---------------------------------------------------------------------------
; Reports whatever fat32_lasterror holds, on the screen as before and now on
; the status line as well, where it stays readable after the screen has
; scrolled on.
; ---------------------------------------------------------------------------
sd_report:
        ldx fat32_lasterror
        beq @unknown
        cpx #(SD_MSG_COUNT+1)
        bcs @unknown
        dex
        txa
        asl
        tax
        lda sd_msgtable,x
        ldy sd_msgtable+1,x
        bra @show
@unknown:
        lda #<sd_msgcard
        ldy #>sd_msgcard
@show:
        sta sd_msgptr
        sty sd_msgptr+1

        lda sd_msgptr
        ldx sd_msgptr+1
        jsr _tty_writeln

        lda sd_msgptr
        ldx sd_msgptr+1
        jmp sd_lcdmsg

; Indexed by fat32_lasterror minus one, so the order has to match the
; FAT32_ERROR_* codes in sd.inc
SD_MSG_COUNT = 7
sd_msgtable:
        .word sd_msgnofile              ; 1 NO_SUCH_FILE
        .word sd_msgtoosmall            ; 2 FILE_TOO_SMALL
        .word sd_msgwrite               ; 3 WRITE_FAILED
        .word sd_msgcard                ; 4 READ_FAILED
        .word sd_msgnocard              ; 5 NO_CARD
        .word sd_msgdiskfull            ; 6 DISK_FULL
        .word sd_msgdirfull             ; 7 DIR_FULL

sd_lcddir:
        .byte "LOAD $", $00
sd_lcdbanner:
        .byte "MICROSOFT BASIC", $00
sd_lcdready:
        .byte "SD READY", $00
sd_lcdnocard:
        .byte "SD NO CARD", $00
sd_lcdbytes:
        .byte " BYTES FREE", $00
sd_lcdload:
        .byte "LOAD ", $00
sd_lcdsave:
        .byte "SAVE ", $00

sd_msgnocard:
        .byte "?NO CARD", $00
sd_msgnofile:
        .byte "?NO SUCH FILE", $00
sd_msgtoosmall:
        .byte "?FILE TOO SMALL", $00
sd_msgdiskfull:
        .byte "?DISK FULL", $00
sd_msgdirfull:
        .byte "?DIRECTORY FULL", $00
sd_msgwrite:
        .byte "?WRITE ERROR", $00
sd_msgcard:
        .byte "?CARD ERROR", $00

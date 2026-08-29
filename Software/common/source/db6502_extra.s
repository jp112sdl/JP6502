      .include "acia.inc"
      .include "keyboard.inc"
      .include "sd.inc"
      .include "lcd.inc"
      .include "blink.inc"
      .include "sys_const.inc"
      .include "sound.inc"
      .include "utils.inc"
      ; tty.inc is already pulled in by inline.s, and these headers carry no
      ; include guards - pulling it a second time is a pile of "already
      ; defined" errors, not a no-op.
      .include "vdp_text_mode.inc"
      .include "vdp.inc"
      .include "vdp_const.inc"
      .import _tty_init
      .import text_screen_buffer
      .import sn_send
      .import ACIA_STATUS
      .import ACIA_DATA
;      .import ACIA_STATUS_RX_FULL
      .export _start_msbasic
      .export _modem_send
      .export _modem_receive
      .export gtx_tty_init
      .export gtx_write_char
      .export gtx_write_string
      .export gtx_newline
      .export gtx_backspace

.segment "CODE"

; ----------------------------------------------------------------------------
; SEE IF CONTROL-C TYPED
;
; Upstream gives every target its own ISCNTC and ends it by running into STOP -
; that fall-through is what turns a detected Ctrl+C into BREAK. This port
; replaced the routine with a jump to MONISCNTC, which only reports in the
; carry, and neither caller looks at the carry: NEWSTT in flow1.s goes straight
; on to TXTPTR, and the LIST loop in program.s does the same. So the key was
; read, recognised, thrown away, and nothing happened. That was the whole of
; "Ctrl+C never works" - the keyboard controller sends $03 for it correctly,
; and $18 for Ctrl+X, which the interrupt handler picks off separately as a
; system break, which is why that one always did work.
;
; STOP wants the carry set to take the break path and Z set for its
; end-of-statement test - exactly what a "cmp #3" that matched would leave
; behind, which is how the fall-through arrived upstream. It also drops the
; caller's return address itself, with two plas, so this jumps rather than
; calls.
; ----------------------------------------------------------------------------
ISCNTC:
          jsr MONISCNTC
          bcc @nothing_typed
          lda #$00                  ; Z set: STOP reads it as end of statement
          sec                       ; C set: STOP takes the break path
          jmp STOP
@nothing_typed:
          rts

init:
_start_msbasic:
      stz EXITFLAG

      ; BSS is not part of the ROM image, so at power-on these hold whatever
      ; the SRAM came up with. MONCOUT and INLIN both test them on every
      ; character and every line, so they have to be forced idle here - a
      ; stray non-zero value diverts the whole console to the SD card.
      stz sd_loadmode
      stz sd_savemode

      ; Ask the cold/warm question only when there is something to ask about -
      ; start_select in EXTCODE2 decides.
      jmp start_select

      ; Twenty-nine dead nops used to follow, holding the place the prompt had
      ; occupied so that no library module behind msbasic.o changed address.
      ; That mattered while the address decoder was glitching; it is fixed, so
      ; they are gone - MEMORY_MAP.md 5.5.

MONCOUT:
    ; Every character BASIC prints goes through here, which is what makes SAVE
    ; possible: while a save is running the stream is diverted to the card.
    pha
    lda sd_savemode
    bne @tocard
    pla
    pha
    jsr _tty_send_character
    ; _tty_send_character does not preserve A, but the LIST loop looks at the
    ; character it just printed to keep track of string literals
    pla
    RTS
@tocard:
    pla
    jmp sd_putbyte

MONRDKEY:
; 	LDA	ACIA_STATUS
; 	AND	#ACIA_STATUS_RX_FULL
; 	BEQ	@NoDataIn
; 	LDA	ACIA_DATA
; 	SEC		; Carry set if key available
; 	RTS
;@NoDataIn:
; 	CLC		; Carry clear if no key pressed
  jsr _acia_is_data_available
 ; skip, no data available at this point
  cmp #(ACIA_NO_DATA_AVAILABLE)
  beq isPS2KeyboardAvailable
  jsr _acia_read_byte
  jmp donereading  
  isPS2KeyboardAvailable:  
  jsr _keyboard_is_data_available
  cmp #(KEYBOARD_NO_DATA_AVAILABLE)
  beq NoDataIn
  jsr _keyboard_read_char
donereading:  
  sec
  rts
NoDataIn:
  clc
	RTS
	

MONISCNTC:
	JSR	MONRDKEY
	BCC	NotCTRLC ; If no key pressed then exit
	CMP	#3
	BNE	NotCTRLC ; if CTRL-C not pressed then exit
	SEC		; Carry set if control C pressed
	RTS
NotCTRLC:
	CLC		; Carry clear if control C not pressed
	RTS

StartupMessage:
;	.byte	"Cold [C] or warm [W] start?",$0D,$0A,$00
	.byte	"Cold start [C] or warm [W] start?",$00
	
; LOAD, SAVE and the "$" directory listing
.include "db6502_sdbasic.s"

.segment "EXTCODE"

; ----------------------------------------------------------------------------
; "SOUND" STATEMENT
;
;   SOUND frequency, duration
;
; frequency in Hz, duration in hundredths of a second. Plays on channel 1 of
; the SN76489 at full volume and returns once the note has finished.
;
; The chip is not given a frequency but a 10 bit divider, and the note it then
; produces is clock / (32 * divider). SOUND_CLOCK below is that clock divided
; by 32, so the divider is simply SOUND_CLOCK / frequency. Its value follows
; from the note table in sound.inc: A4 is listed as $0e,$08, a divider of 142,
; and 142 * 440 Hz = 62480 - a 2 MHz part.
;
; Anything outside a divider of 1..1023 is ILLEGAL QUANTITY, which puts the
; usable range at 62 Hz to about 4 kHz before the steps get audible.
;
; sound_init has already run out of _system_init by the time BASIC starts, so
; the port directions and the initial silence are taken care of.
; ----------------------------------------------------------------------------
SOUND:
        jsr     FRMNUM              ; frequency -> FAC
        lda     #<SOUND_CLOCK
        ldy     #>SOUND_CLOCK
        jsr     FDIV                ; FAC = SOUND_CLOCK / frequency
        jsr     GETADR              ; -> LINNUM
        lda     LINNUM+1
        cmp     #$04                ; divider has ten bits
        bcs     SOUND_RANGE
        ora     LINNUM
        beq     SOUND_RANGE         ; and zero is not one of them
        ; First byte latches the channel and the low four bits of the divider
        lda     LINNUM
        and     #$0f
        ora     #(FIRST|CHANNEL_1|TONE)
        jsr     sn_send
        ; Second byte carries the remaining six
        ldy     #$04
SOUND_SHIFT:
        lsr     LINNUM+1
        ror     LINNUM
        dey
        bne     SOUND_SHIFT
        lda     LINNUM
        jsr     sn_send
        ; The channel is still silent - every SOUND ends by muting it and
        ; sound_init leaves it muted - so the duration can be evaluated with
        ; the divider already loaded and nothing audible yet. A syntax error in
        ; it then leaves the machine quiet instead of ringing.
        jsr     COMBYTE             ; duration -> X
        lda     #(FIRST|CHANNEL_1|VOLUME|VOLUME_MAX)
        jsr     sn_send
        ; sn_send and _delay_ms both preserve X, so it can hold the count
SOUND_HOLD:
        dex                         ; counted down before the wait, so that a
        bmi     SOUND_OFF           ; duration of zero is a blip and not 256
        lda     #10                 ; steps the other way round
        jsr     _delay_ms
        bra     SOUND_HOLD
SOUND_OFF:
        lda     #(FIRST|CHANNEL_1|VOLUME|VOLUME_OFF)
        jmp     sn_send

SOUND_RANGE:
        jmp     IQERR

; 2000000 / 32, in the four byte float format CONFIG_SMALL selects: exponent
; biased by 128, then three mantissa bytes whose top bit carries the sign.
; 62500 = 0.95367431640625 * 2^16 -> $90, and $F42400 with bit 7 cleared.
SOUND_CLOCK:
        .byte   $90,$74,$24,$00

.segment "SDCODE"

; ----------------------------------------------------------------------------
; "CLS" STATEMENT
;
; Clears the screen and puts the cursor back in the top left corner. Takes no
; arguments, so there is nothing to parse.
;
; tty_config can have several outputs on at once, and each one needs its own
; treatment: the VDP has a routine for it, a serial terminal has to be told in
; ANSI. The escape sequence deliberately does not go through
; _tty_send_character - that would push the bracket and the letters onto the
; VDP as text as well.
;
; The LCD is left alone. It is the panel, not a console, and _tty_init in
; standalone.s does not put BASIC's output there in the first place.
;
; This sits in SDCODE rather than next to SOUND in EXTCODE for room only:
; EXTCODE was down to 24 free bytes, see MEMORY_MAP.md section 5.2.
; ----------------------------------------------------------------------------
CLS:
        lda     tty_config
        and     #(TTY_CONFIG_OUTPUT_VDP)
        beq     CLS_SERIAL
        jsr     vdp_clear_text_screen
CLS_SERIAL:
        lda     tty_config
        and     #(TTY_CONFIG_OUTPUT_SERIAL)
        beq     CLS_DONE
        ldx     #$00
CLS_LOOP:
        lda     CLS_ANSI,x
        beq     CLS_DONE
        jsr     _acia_write_byte
        inx
        bne     CLS_LOOP
CLS_DONE:
        rts

; Erase the whole display, then home the cursor
CLS_ANSI:
        .byte   $1b,"[2J",$1b,"[H",$00

; COLOR sits in EXTCODE2 rather than next to CLS in SDCODE, and it was put
; there the hard way: twenty-five bytes here pushed every module behind it in
; SDCODE to a new address, and the board came back with a screen full of the
; wrong glyphs - twice, the second time with every VDP access paced, which
; ruled out the microsecond and left nothing but the addresses. It was the
; address decoder, and it is fixed. This could move next to CLS now, and there
; is no reason to. See MEMORY_MAP.md 5.5.
.segment "EXTCODE2"

; ----------------------------------------------------------------------------
; "COLOR" STATEMENT
;
;   COLOR foreground, background
;
; Both 0 to 15 out of the TMS9918A palette - 1 black, 4 dark blue, 6 dark red,
; 7 cyan, 15 white and so on, the full list is in vdp_const.inc. Text mode has
; no colour table, so the background is the backdrop and these two are the only
; colours on the screen. Anything above 15 wraps.
;
; POKE cannot do this, which is worth knowing before someone tries: both halves
; of a register write go to the same control port, and POKE assembles to
; "sta (LINNUM),y". The dummy read that addressing mode performs on the target
; one cycle before the write is itself an access, and the chip wants about 8 us
; between two - so the write is lost and the pair never completes. It is the
; same access time that used to leave the screen dark at cold start, see
; vdp_boot_init. vdp_write_register gives both halves the wait they need.
; ----------------------------------------------------------------------------
COLOR:
        jsr     GETBYT              ; foreground -> X
        txa
        asl     a
        asl     a
        asl     a
        asl     a                   ; up into the high nibble
        pha
        jsr     COMBYTE             ; background -> X
        txa
        and     #$0f
        tsx                         ; reach the byte pushed above without
        ora     $0101,x             ; needing a variable to hold it
        plx                         ; and drop it again
        ldx     #$07                ; register 7 carries both colours
        jmp     vdp_write_register

; ----------------------------------------------------------------------------
; "SCREEN" STATEMENT
;
;   SCREEN 0    text, 40x24, the console
;   SCREEN 1    graphics, 256x192 bitmap (TMS9918A Graphics II)
;
; Graphics II puts the bitmap where the text font lives, so the two cannot be on
; at once: SCREEN 1 takes the VDP out of tty_config and leaves output going to
; the serial port and the LCD, SCREEN 0 puts the font back and switches it on
; again. Typing SCREEN 0 blind is the way home, and so is the reset button.
;
; The layout is the usual one for a full-screen bitmap. Register 3 is $FF and
; register 4 is $03 - in this mode both act as masks rather than plain base
; addresses, and those two values are what select "no masking at all", which is
; what makes every one of the 768 cells address its own pattern.
;
;   $0000-$17FF  bitmap        6144    one bit per pixel
;   $2000-$37FF  colour        6144    foreground/background per 8x1 group
;   $3800-$3AFF  name           768    filled 0..255 three times, so that each
;                                      cell maps to its own pattern
;   $3B00-$3B7F  sprite attributes, first Y byte set to $D0 so none are shown
;   $1800-$1FFF  free, and the only 2 KB hole a sprite pattern table can use
;
; Sprite patterns have to start on a 2 KB boundary, which rules out the space
; behind the name table: $3C00 is not a legal base and register 6 would round it
; down to $3800, on top of the name table. The gap between the bitmap and the
; colour table is the one that fits.
;
; Setting it up writes 13056 bytes into VRAM, about 260 ms. The wait between
; accesses is not optional - see vdp_write_address in vdp.s.
; ----------------------------------------------------------------------------
.segment "EXTCODE2"

GFX_BITMAP_HI   = $00                   ; bitmap at $0000
GFX_COLOR_HI    = $20                   ; colour table at $2000
GFX_NAME_HI     = $38                   ; name table at $3800
GFX_SPRATTR_HI  = $3B                   ; sprite attributes at $3B00
GFX_SPRPAT_HI   = $18                   ; sprite patterns at $1800
SPRITE_COUNT    = 32
SPRITE_PARKED_Y = $D1                   ; off the bottom without ending the list
SPRITE_END_Y    = $D0                   ; the value that would end it
GFX_DEFAULT_COL = $F1                   ; white on black, the whole screen

SCREEN:
        jsr     GETBYT                  ; mode -> X
        cpx     #$02
        bcc     @mode_ok
        jmp     IQERR
@mode_ok:
        txa
        bne     screen_gfx
        jmp     screen_text

; --- graphics ---------------------------------------------------------------
screen_gfx:
        ldx     #$00
@regs:
        lda     gfx_register_inits,x
        jsr     vdp_write_register
        inx
        cpx     #(gfx_register_inits_end - gfx_register_inits)
        bne     @regs

        ; bitmap: every pixel off
        lda     #$18                    ; 6144 bytes
        sta     gfx_count+1
        ldy     #$00
        lda     #GFX_BITMAP_HI | VDP_WRITE_VRAM_SELECT
        ldx     #$00
        jsr     gfx_fill

        ; colour: every group white on black
        lda     #$18
        sta     gfx_count+1
        ldy     #$00
        lda     #GFX_COLOR_HI | VDP_WRITE_VRAM_SELECT
        ldx     #GFX_DEFAULT_COL
        jsr     gfx_fill

        ; sprite patterns: blank, so a sprite placed before its shape has been
        ; defined shows nothing rather than whatever the VRAM came up with
        lda     #$08                    ; 2048 bytes
        sta     gfx_count+1
        ldy     #$00
        lda     #GFX_SPRPAT_HI | VDP_WRITE_VRAM_SELECT
        ldx     #$00
        jsr     gfx_fill

        ; name: 0..255, three times over, so each cell has its own pattern
        ldy     #$00
        lda     #GFX_NAME_HI | VDP_WRITE_VRAM_SELECT
        jsr     vdp_write_address
        ldx     #$03
@pass:
        ldy     #$00
@byte:
        tya
        sta     VDP_VRAM
        jsr     vdp_wait
        iny
        bne     @byte
        dex
        bne     @pass

        ; Every sprite parked off the bottom of the screen. The attribute table
        ; is above everything filled above, so left alone it holds whatever the
        ; VRAM came up with and the chip cheerfully draws 32 sprites at random
        ; positions - a black screen covered in debris, which is exactly how
        ; this looked before it was written.
        ;
        ; Parked, not ended. A Y of $D0 stops the chip reading any further down
        ; the table, so putting one in the first entry would turn every sprite
        ; off for good and SPRITE 5 would do nothing. $D1 is one line lower:
        ; off-screen, and the list carries on.
        ldy     #$00
        lda     #GFX_SPRATTR_HI | VDP_WRITE_VRAM_SELECT
        jsr     vdp_write_address
        ldx     #SPRITE_COUNT
@park:
        lda     #SPRITE_PARKED_Y
        sta     VDP_VRAM
        jsr     vdp_wait
        lda     #$00
        sta     VDP_VRAM                ; x
        jsr     vdp_wait
        sta     VDP_VRAM                ; pattern
        jsr     vdp_wait
        sta     VDP_VRAM                ; colour
        jsr     vdp_wait
        dex
        bne     @park

        ; Filling takes about a quarter of a second, and the register table
        ; above leaves the screen blanked so that quarter second is not spent
        ; showing whatever the VRAM happened to contain.
        lda     #(VDP_REG1_RAM_16K | VDP_REG1_SCREEN_ACTIVE)
        ldx     #VDP_REGISTER_1
        jsr     vdp_write_register

        ; The console stays on the VDP; gtx_write_char and its neighbours put
        ; characters into the bitmap for as long as this flag is set.
        lda     #$01
        sta     gtx_active
        stz     gtx_col
        stz     gtx_row
        rts

; --- back to text -----------------------------------------------------------
screen_text:
        stz     gtx_active
        jsr     vdp_boot_registers      ; the text mode register table
        jsr     vdp_boot_patterns       ; the font the bitmap overwrote
        jsr     vdp_boot_clear
        jsr     vdp_boot_enable
        stz     vdp_line
        stz     vdp_char_pos
        rts

; Y/A = start address including the write select, X = value, gfx_count+1 = how
; many 256 byte pages to write. The count is the idiom vdp_boot_clear uses,
; where the low byte runs out first and zero means a full 256.
gfx_fill:
        stx     gfx_value
        jsr     vdp_write_address
        stz     gfx_count
@loop:
        lda     gfx_value
        sta     VDP_VRAM
        jsr     vdp_wait
        dec     gfx_count
        bne     @loop
        dec     gfx_count+1
        bne     @loop
        rts

gfx_register_inits:
        .byte   VDP_REG_0_GRAPHICS_MODE_II_ENABLE
        .byte   VDP_REG1_RAM_16K | VDP_REG1_SCREEN_BLANK
        .byte   VDP_REG2_NAME_TABLE_BASE_3800
        .byte   $FF                     ; colour table $2000, nothing masked
        .byte   $03                     ; bitmap $0000, nothing masked
        .byte   $76                     ; sprite attributes $3B00
        .byte   $03                     ; sprite patterns $1800
        .byte   $01                     ; black backdrop
gfx_register_inits_end:

; ----------------------------------------------------------------------------
; "PLOT" STATEMENT
;
;   PLOT x, y, colour
;
; x is 0 to 255, y is 0 to 191, colour is 0 to 15 out of the same palette COLOR
; uses. Colour 0 clears the pixel and leaves it showing the background; 1 to 15
; set it and give the group it belongs to that foreground colour.
;
; "the group it belongs to" is the hardware talking: Graphics II stores one
; foreground and one background colour per eight horizontal pixels, so plotting
; a red pixel recolours whatever else is already lit in the same row of eight.
; There is no way around it short of a full off-screen buffer, which this
; machine has no RAM for.
;
; The address arithmetic is why this mode is worth using. Cell row is y>>3,
; cell column is x>>3, and each cell is eight bytes, so the byte holding the
; pixel is at (y>>3)*256 + (x>>3)*8 + (y&7) - a high byte that is just y>>3 and
; a low byte that is (x & $F8) with (y & 7) dropped into the three bits it
; leaves free. The colour byte for the same group sits at the same offset in
; the colour table, so the high byte only needs $20 added.
; ----------------------------------------------------------------------------

PLOT:
        jsr     GETBYT                  ; x -> X
        stx     plot_x
        jsr     COMBYTE                 ; y -> X
        cpx     #192
        bcc     @in_range
        jmp     IQERR
@in_range:
        stx     plot_y
        jsr     COMBYTE                 ; colour -> X
        txa
        and     #$0f
        sta     plot_col

; Draws the pixel at plot_x/plot_y in plot_col. LINE below drives this directly
; with the coordinates already in place, which is why it is a label of its own.
plot_pixel:
        lda     plot_y
        lsr     a
        lsr     a
        lsr     a
        sta     plot_hi                 ; cell row, 0 to 23
        lda     plot_x
        and     #$f8
        sta     plot_lo
        lda     plot_y
        and     #$07
        ora     plot_lo
        sta     plot_lo

        lda     plot_x                  ; mask = $80 >> (x & 7)
        and     #$07
        tax
        lda     #$80
@shift:
        dex
        bmi     @masked
        lsr     a
        bra     @shift
@masked:
        sta     plot_mask
        eor     #$ff
        sta     plot_nmask

        ldy     plot_lo                 ; read the byte the pixel is in
        lda     plot_hi
        jsr     vdp_write_address
        lda     VDP_VRAM
        jsr     vdp_wait

        ldx     plot_col
        beq     @clear
        ora     plot_mask
        bra     @store
@clear:
        and     plot_nmask
@store:
        pha
        ldy     plot_lo
        lda     plot_hi
        ora     #VDP_WRITE_VRAM_SELECT
        jsr     vdp_write_address
        pla
        sta     VDP_VRAM
        jsr     vdp_wait

        lda     plot_col                ; a cleared pixel keeps its colour
        beq     @done
        ldy     plot_lo
        lda     plot_hi
        ora     #GFX_COLOR_HI | VDP_WRITE_VRAM_SELECT
        jsr     vdp_write_address
        lda     plot_col
        asl     a
        asl     a
        asl     a
        asl     a
        ora     #$01                    ; black behind it, as SCREEN 1 left it
        sta     VDP_VRAM
        jmp     vdp_wait
@done:
        rts

; ----------------------------------------------------------------------------
; "LINE" STATEMENT
;
;   LINE x1, y1, x2, y2, colour
;
; Same ranges and the same colour rules as PLOT, endpoints included.
;
; Bresenham, in the form that keeps the error term in one byte. The axis that
; moves further becomes the one stepped every time round; the error starts at
; half that distance and has the shorter distance taken off it each step,
; borrowing a step on the other axis and adding the longer distance back
; whenever it goes negative. Because the error never leaves 0..dmajor and both
; distances fit in a byte, none of it needs 16-bit arithmetic.
;
; The two directions are written out separately rather than folded into one loop
; through a pair of "which coordinate am I stepping" variables. It costs about
; forty bytes and removes the indirection that would otherwise sit in the middle
; of the hot loop.
;
; Speed is whatever PLOT costs, once per pixel: about 250 us, so a full width
; line takes around 64 ms. Runs of eight pixels that fall inside one byte could
; be written whole - two VRAM addresses instead of twenty-four - which would be
; worth roughly a factor of thirteen on horizontal lines. That is not in here;
; the addresses of consecutive bytes in this mode are eight apart rather than
; adjacent, so it does not fall out of the auto-increment and needs its own
; path with masked ends.
; ----------------------------------------------------------------------------

LINE:
        jsr     GETBYT                  ; x1
        stx     plot_x
        jsr     COMBYTE                 ; y1
        cpx     #192
        bcc     @y1_ok
        jmp     IQERR
@y1_ok:
        stx     plot_y
        jsr     COMBYTE                 ; x2
        stx     line_x2
        jsr     COMBYTE                 ; y2
        cpx     #192
        bcc     @y2_ok
        jmp     IQERR
@y2_ok:
        stx     line_y2
        jsr     COMBYTE                 ; colour
        txa
        and     #$0f
        sta     plot_col

        sec                             ; dx and the direction to walk it
        lda     line_x2
        sbc     plot_x
        bcs     @x_forward
        eor     #$ff                    ; borrowed, so negate for the distance
        adc     #$01                    ; carry is clear here, this adds one
        ldy     #$ff
        bra     @x_done
@x_forward:
        ldy     #$01
@x_done:
        sta     line_dx
        sty     line_sx

        sec                             ; and the same for y
        lda     line_y2
        sbc     plot_y
        bcs     @y_forward
        eor     #$ff
        adc     #$01
        ldy     #$ff
        bra     @y_done
@y_forward:
        ldy     #$01
@y_done:
        sta     line_dy
        sty     line_sy

        lda     line_dx
        cmp     line_dy
        bcc     line_steep

; --- flatter than 45 degrees: x moves every step ----------------------------
        sta     line_count
        lsr     a
        sta     line_err
@shallow:
        jsr     plot_pixel
        lda     line_count
        beq     @shallow_done
        dec     line_count

        lda     line_err
        sec
        sbc     line_dy
        bcs     @no_y_step
        adc     line_dx                 ; carry clear, so this is plus dx
        pha
        lda     plot_y
        clc
        adc     line_sy
        sta     plot_y
        pla
@no_y_step:
        sta     line_err
        lda     plot_x
        clc
        adc     line_sx
        sta     plot_x
        bra     @shallow
@shallow_done:
        rts

; --- steeper than 45 degrees: y moves every step ----------------------------
line_steep:
        lda     line_dy
        sta     line_count
        lsr     a
        sta     line_err
@steep:
        jsr     plot_pixel
        lda     line_count
        beq     @steep_done
        dec     line_count

        lda     line_err
        sec
        sbc     line_dx
        bcs     @no_x_step
        adc     line_dy
        pha
        lda     plot_x
        clc
        adc     line_sx
        sta     plot_x
        pla
@no_x_step:
        sta     line_err
        lda     plot_y
        clc
        adc     line_sy
        sta     plot_y
        bra     @steep
@steep_done:
        rts

.segment "BASBUF"
line_x2:        .res 1
line_y2:        .res 1
line_dx:        .res 1
line_dy:        .res 1
line_sx:        .res 1
line_sy:        .res 1
line_err:       .res 1
line_count:     .res 1

gfx_value:      .res 1
gfx_count:      .res 2
plot_x:         .res 1
plot_y:         .res 1
plot_col:       .res 1
plot_hi:        .res 1
plot_lo:        .res 1
plot_mask:      .res 1
plot_nmask:     .res 1

; ----------------------------------------------------------------------------
; COLD OR WARM START
;
; The choice only means something when the RAM still holds a BASIC program, and
; after a power-on it does not - it holds whatever the SRAM came up with, and a
; warm start into that goes nowhere good. So the question is only worth asking
; when the RAM demonstrably survived, and that is what the signature below is
; for: it is stamped on the way into the first cold start and never cleared
; again, so finding it a second time means the machine was reset rather than
; switched on. It lives in BASBUF because nothing zeroes that page at boot -
; the same reason sd_loadmode and sd_savemode have to be forced idle by hand in
; _start_msbasic.
;
; Six bytes rather than two, and letters rather than a bit pattern: an SRAM does
; not come up uniformly random, it comes up in patterns, and a short signature
; made of the kind of bytes an SRAM likes is exactly the one that turns up by
; accident.
;
; In EXTCODE2 because when it was written, inserting into CODE moved every
; library module behind msbasic.o and killed the picture. Fixed since, in the
; decoder - MEMORY_MAP.md 5.5.
; ----------------------------------------------------------------------------
.segment "EXTCODE2"

START_MAGIC_LEN = 6

start_select:
        ; BASBUF holds whatever the SRAM came up with, and a stray value here
        ; would have the console drawing into a bitmap that is not there
        stz     gtx_active

        ldx     #START_MAGIC_LEN-1
@test:
        lda     start_magic,x
        cmp     start_magic_value,x
        bne     start_poweron
        dex
        bpl     @test

        ; RAM came through, so there may be a program in it worth keeping
        writeln_tty #StartupMessage
@wait:
        jsr     MONRDKEY
        bcc     @wait
        and     #$DF                ; make upper case
        cmp     #'W'
        beq     @warm
        cmp     #'C'
        bne     @wait
        jmp     sd_coldstart        ; cold start, with the busy light on
@warm:
        jmp     RESTART

; Nothing in RAM to lose, so no question either
start_poweron:
        ldx     #START_MAGIC_LEN-1
@stamp:
        lda     start_magic_value,x
        sta     start_magic,x
        dex
        bpl     @stamp
        jmp     sd_coldstart

start_magic_value:
        .byte   "DB6502"

; ----------------------------------------------------------------------------
; THE KEYWORD TABLE, READ WITH MORE THAN EIGHT BITS OF INDEX
;
; program.s walks BAS_KEY with Y alone, so the table could never exceed 256
; bytes: at 257 the terminating zero sits at offset 256, Y wraps to nought, the
; scan restarts at the first keyword and the machine hangs on the first ENTER.
; That is what adding LINE did, and with 253 of 256 bytes gone there was no room
; for another statement.
;
; The seven places that read the table now call in here instead. Every one of
; them was three bytes of absolute-indexed load, and a jsr is three bytes too,
; so CODE kept its exact length. That was not a nicety at the time; see
; MEMORY_MAP.md 5.5 for why it has stopped mattering.
;
; Y stays the index; what is added is a page. keyptr points at the start of the
; 256 byte page Y is currently in, and gets carried forward whenever Y wraps.
; Detecting that needs no cooperation from the caller, because Y only ever moves
; one step at a time and only ever forwards: an index lower than the one from
; the previous call can only mean it has just gone round. keylasty holds that
; previous value.
;
; The starting position is the trick that makes it uniform. Both callers begin
; with Y at $FF and step to nought before the first read, which by the rule
; above is a wrap. So the pointer starts one page *below* the table and that
; first wrap is what brings it onto it, and no special case is needed for entry.
;
; keyptrm1 trails keyptr by one, for the one caller that reads the byte before
; the index rather than at it. Working that out with dey/iny would read from the
; wrong page in exactly the case the whole exercise is about - the step where Y
; has just wrapped and the byte wanted is the last one of the page before.
;
; Cost is about 25 cycles per byte of table read. That is a few tens of
; milliseconds on a whole line of input, once, when ENTER is pressed.
; ----------------------------------------------------------------------------
.segment "EXTCODE2"

; Carries the pointer onto the page Y is now in. Flags are destroyed, A is not.
key_sync:
        cpy     keylasty
        bcs     @same_page
        inc     keyptr+1
        inc     keyptrm1+1
@same_page:
        sty     keylasty
        rts

key_reset:
        lda     #<(TOKEN_NAME_TABLE-$100)
        sta     keyptr
        sta     keyptrm1
        dec     keyptrm1
        lda     #>(TOKEN_NAME_TABLE-$100)
        sta     keyptr+1
        sta     keyptrm1+1
        lda     keyptrm1
        cmp     #$ff                    ; borrowed into the page below
        bne     @no_borrow
        dec     keyptrm1+1
@no_borrow:
        lda     #$ff                    ; so the first index is seen as a wrap
        sta     keylasty
        rts

; In place of "sty EOLPNTR / dey" in the tokenizer, with Y at zero. Both call
; sites had to give up a neighbouring byte to pay for the jsr, because storing
; to a zero page variable is two bytes and calling is three.
key_init:
        sty     EOLPNTR
        dey
        bra     key_reset

; In place of "tax / sty FORPNT" in LIST. The ldy #$FF that followed is left
; where it was; key_reset does not touch Y, so it still does its job.
key_init_list:
        tax
        sty     FORPNT
        bra     key_reset

; A = table[Y], flags from the load, as the absolute form left them
key_lda:
        jsr     key_sync
        lda     (keyptr),y
        rts

; A = table[Y-1], for the scan that steps over the keyword it just failed on
key_prev:
        jsr     key_sync
        lda     (keyptrm1),y
        rts

; A = A - table[Y], carry in from the caller's sec, flags from the subtraction.
; key_sync uses cpy, so the carry has to be carried across it by hand.
key_sbc:
        php
        jsr     key_sync
        plp
        sbc     (keyptr),y
        rts

.zeropage
keyptr:         .res 2
keyptrm1:       .res 2
keylasty:       .res 1

; ----------------------------------------------------------------------------
; "CIRCLE" STATEMENT
;
;   CIRCLE x, y, radius, colour
;
; Midpoint circle: start at the top, walk an eighth of the way round, and mirror
; every step into the other seven eighths. The decision variable only ever needs
; adding to - no multiplication and no square root anywhere - which is what
; makes it worth doing on this machine. The eighth ends at the diagonal, where
; x meets y. Radius 0 draws the centre point and nothing else.
;
; f, ddx and ddy are 16-bit signed: with a radius of 255, ddy starts at -510 and
; f swings a few hundred either way, so a byte will not hold them. x and y stay
; single bytes.
;
; Every point is clipped rather than the circle as a whole. One that runs off
; the screen has to be drawn as far as it fits, and off-screen coordinates are
; not merely invisible here: a y above 191 would put the colour byte up in the
; name table and take the display apart.
;
; Appended after the keyword table helpers, which at the time was how anything
; new got in without moving what was already there - MEMORY_MAP.md 5.5.
; ----------------------------------------------------------------------------
.segment "EXTCODE2"

CIRCLE:
        jsr     GETBYT                  ; centre x
        stx     circle_cx
        jsr     COMBYTE                 ; centre y
        cpx     #192
        bcc     @y_ok
        jmp     IQERR
@y_ok:
        stx     circle_cy
        jsr     COMBYTE                 ; radius
        stx     circle_r
        jsr     COMBYTE                 ; colour
        txa
        and     #$0f
        sta     plot_col

        sec                             ; f = 1 - r
        lda     #$01
        sbc     circle_r
        sta     cir_f
        lda     #$00
        sbc     #$00
        sta     cir_f+1

        lda     #$01                    ; ddx = 1
        sta     cir_ddx
        stz     cir_ddx+1

        lda     circle_r                ; ddy = -2r
        asl     a
        sta     cir_ddy
        lda     #$00
        rol     a
        sta     cir_ddy+1
        sec
        lda     #$00
        sbc     cir_ddy
        sta     cir_ddy
        lda     #$00
        sbc     cir_ddy+1
        sta     cir_ddy+1

        stz     cir_x
        lda     circle_r
        sta     cir_y

        stz     circle_ox               ; the four points on the axes
        lda     circle_r
        sta     circle_oy
        jsr     circle_four
        lda     circle_r
        sta     circle_ox
        stz     circle_oy
        jsr     circle_four

@step:
        lda     cir_x
        cmp     cir_y
        bcs     @done                   ; reached the diagonal

        lda     cir_f+1                 ; f >= 0 ?
        bmi     @f_negative
        dec     cir_y
        clc                             ; ddy += 2
        lda     cir_ddy
        adc     #$02
        sta     cir_ddy
        lda     cir_ddy+1
        adc     #$00
        sta     cir_ddy+1
        clc                             ; f += ddy
        lda     cir_f
        adc     cir_ddy
        sta     cir_f
        lda     cir_f+1
        adc     cir_ddy+1
        sta     cir_f+1
@f_negative:
        inc     cir_x
        clc                             ; ddx += 2
        lda     cir_ddx
        adc     #$02
        sta     cir_ddx
        lda     cir_ddx+1
        adc     #$00
        sta     cir_ddx+1
        clc                             ; f += ddx
        lda     cir_f
        adc     cir_ddx
        sta     cir_f
        lda     cir_f+1
        adc     cir_ddx+1
        sta     cir_f+1

        lda     cir_x                   ; the eight mirrored points
        sta     circle_ox
        lda     cir_y
        sta     circle_oy
        jsr     circle_four
        lda     cir_y
        sta     circle_ox
        lda     cir_x
        sta     circle_oy
        jsr     circle_four
        bra     @step
@done:
        rts

; Plots the centre offset by circle_ox/circle_oy in all four sign combinations,
; dropping any that leaves the screen. With an offset of zero the same point
; comes up twice, which costs a little time and does no harm.
circle_four:
        stz     circle_sign
@combination:
        lda     circle_sign
        and     #$01
        bne     @x_minus
        clc
        lda     circle_cx
        adc     circle_ox
        bcs     @next                   ; off the right edge
        bra     @x_ok
@x_minus:
        sec
        lda     circle_cx
        sbc     circle_ox
        bcc     @next                   ; off the left edge
@x_ok:
        sta     plot_x

        lda     circle_sign
        and     #$02
        bne     @y_minus
        clc
        lda     circle_cy
        adc     circle_oy
        bcs     @next
        bra     @y_ok
@y_minus:
        sec
        lda     circle_cy
        sbc     circle_oy
        bcc     @next
@y_ok:
        cmp     #192                    ; below the bottom line
        bcs     @next
        sta     plot_y
        jsr     plot_pixel
@next:
        inc     circle_sign
        lda     circle_sign
        cmp     #$04
        bne     @combination
        rts

; ----------------------------------------------------------------------------
; "SPRITE" AND "VPOKE" STATEMENTS
;
;   SPRITE n, x, y, pattern, colour
;   VPOKE address, value
;
; Sprites are 8x8 and unmagnified, which gives 256 patterns in the 2 KB at
; $1800 and keeps a shape down to eight bytes - few enough to type by hand.
; Register 1 bit 1 would make them 16x16 and bit 0 would double them in size;
; both cost four patterns per sprite instead of one, so that is a decision for
; whoever wants it rather than a default.
;
; n is 0 to 31, x and y are where the top left corner goes, pattern picks one of
; the 256 shapes and colour is the same palette COLOR uses. A y of 192 or more
; parks the sprite off the screen, which is how one is hidden.
;
; Two details of the chip leak through and are handled here rather than left to
; the caller. A sprite appears one line below the y in its attribute entry, so
; the stored value is one less than what was asked for - and y = 0 storing $FF
; is not a wraparound but the correct way to show a sprite hanging off the top.
; And a stored y of $D0 does not park a sprite, it tells the chip to stop
; reading the table there, which would silently turn off every sprite after it;
; that one value is pushed on by one.
;
; Only four sprites can share a scanline. The fifth and beyond simply are not
; drawn, and no amount of software here changes that.
;
; VPOKE is the way shapes get into VRAM at all: POKE cannot reach it, for the
; reason written up under COLOR. It writes one byte anywhere in the 16 KB, so it
; also reaches the bitmap, the colour table and the attributes - useful, and
; entirely capable of taking the display apart, exactly like POKE.
; ----------------------------------------------------------------------------
.segment "EXTCODE2"

SPRITE:
        jsr     GETBYT                  ; which sprite
        cpx     #SPRITE_COUNT
        bcc     @n_ok
        jmp     IQERR
@n_ok:
        stx     spr_n
        jsr     COMBYTE                 ; x
        stx     spr_x
        jsr     COMBYTE                 ; y
        stx     spr_y
        jsr     COMBYTE                 ; pattern
        stx     spr_pat
        jsr     COMBYTE                 ; colour
        txa
        and     #$0f
        sta     spr_col

        lda     spr_n                   ; four bytes per entry
        asl     a
        asl     a
        tay
        lda     #GFX_SPRATTR_HI | VDP_WRITE_VRAM_SELECT
        jsr     vdp_write_address

        sec                             ; the chip draws a sprite one line down
        lda     spr_y
        sbc     #$01
        cmp     #SPRITE_END_Y           ; and this one value ends the table
        bne     @y_ok
        lda     #SPRITE_END_Y+1
@y_ok:
        sta     VDP_VRAM
        jsr     vdp_wait
        lda     spr_x
        sta     VDP_VRAM
        jsr     vdp_wait
        lda     spr_pat
        sta     VDP_VRAM
        jsr     vdp_wait
        lda     spr_col
        sta     VDP_VRAM
        jmp     vdp_wait

VPOKE:
        jsr     FRMNUM                  ; address, 0 to 16383
        jsr     GETADR
        jsr     COMBYTE                 ; value
        stx     vpoke_value
        lda     LINNUM+1
        cmp     #$40                    ; past the end of the VRAM
        bcc     @addr_ok
        jmp     IQERR
@addr_ok:
        ldy     LINNUM
        ora     #VDP_WRITE_VRAM_SELECT
        jsr     vdp_write_address
        lda     vpoke_value
        sta     VDP_VRAM
        jmp     vdp_wait

; ----------------------------------------------------------------------------
; "KEY" FUNCTION
;
;   A = KEY(0)
;
; The code of a key if one is waiting, zero if none is. It does not wait, which
; is the entire point: INPUT holds the machine until ENTER, so without this
; nothing written in BASIC can steer a sprite, poll for a fire button or offer a
; way out of a loop.
;
; The argument is required by the way MS-BASIC dispatches functions and is
; ignored - KEY(0) reads the way RND(0) does.
;
; Upstream has GET for this, but CONFIG_SMALL leaves its routine out of the
; build entirely, so bringing the keyword back would mean compiling the routine
; and growing CODE. That was once the one change this board did not survive -
; MEMORY_MAP.md 5.5 - and even now MONRDKEY already returns carry clear when
; nothing is waiting, so doing it here costs ten bytes and is simply less code.
;
; A function rather than a GET-style statement because assigning to a variable
; needs PTRGET and the rest of the assignment path, which is a great deal more
; code for no more capability.
;
; The keyword goes in before LEFT$ on purpose. UNARY tells the string functions
; from the plain ones by whether the token is below TOKEN_LEFTSTR, so anything
; added after MID$ would be dispatched as if it took three arguments.
; ----------------------------------------------------------------------------
.segment "EXTCODE2"

KEYFN:
        jsr     MONRDKEY
        bcs     @waiting
        lda     #$00
@waiting:
        tay
        jmp     SNGFLT                  ; Y into FAC as 0 to 255

; ----------------------------------------------------------------------------
; TEXT IN GRAPHICS MODE
;
; SCREEN 1 used to take the VDP out of tty_config, which left the machine
; drawing pictures and typing blind. The bitmap occupies the VRAM the font lives
; in, so the two cannot both be the screen - but the font is still in the ROM,
; and drawing a character into the bitmap eight bytes at a time is cheap.
;
; The five places in tty.s that reached for the VDP now call in here. Each was a
; three byte jsr and still is, which kept CODE the same length - a requirement
; then, tidiness now, MEMORY_MAP.md 5.5. While gtx_active is clear every one of
; them hands straight back to the routine it used to call.
;
; A character cell falls out of the bitmap layout very neatly. The byte holding
; pixel (x,y) is at high = y>>3, low = (x & $F8) | (y & 7), so for a cell at
; column c and row r the eight rows are high = r, low = c*8 + 0..7 - eight
; consecutive addresses. One address written, eight bytes out, and the colour
; cell is the same offsets again with $20 added to the high byte.
;
; 32 columns by 24 rows, against 40 by 24 in text mode. The colour is written as
; well as the shape, so text stays readable over whatever was drawn there; that
; costs a second address and doubles the time, and it is worth it.
;
; It scrolls, and it is not cheap - see gtx_scroll at the end of this block for
; what that costs and why there is no way round it.
; ----------------------------------------------------------------------------
.segment "EXTCODE2"

GTX_COLUMNS     = 32
GTX_ROWS        = 24
GTX_COLOUR      = GFX_DEFAULT_COL       ; white on black, as SCREEN 1 leaves it

; How far the picture jumps when the cursor runs off the bottom. One row is
; what a terminal does and costs about a third of a second every time, because
; the bitmap has to go through the processor twice - see gtx_scroll. Jumping
; further moves nearly the same bytes but does it once every that many lines,
; so the cost per line falls with the jump: a third of a second at one row,
; about 90 ms at four, about 45 ms at eight. The screen jumps rather than
; slides, which is what slow terminals did.
GTX_SCROLL_ROWS = 1

; ----------------------------------------------------------------------------
; NO XMODEM IN THE BASIC ROM
;
; Nothing in MS-BASIC transfers files over the serial port - LOAD and SAVE go to
; the card - but modem.o was linked in anyway, because syscalls.s names
; _modem_send and _modem_receive in the syscall table and that is reference
; enough for ld65 to pull the whole module out of the library. It cost 345 bytes
; of CODE, 118 of RODATA, 512 of RODATA_PA and 147 bytes of RAM.
;
; The 512 were the expensive ones. They are the XMODEM CRC tables, page aligned,
; which is what put RODATA_PA on $E500 and boxed the keyword tables into the
; 39 bytes of run-up in front of it. Without them BAS_VEC, BAS_KEY and BAS_ERR
; have everything up to EXTCODE at $E700 to grow into.
;
; Defining the two entry points here is all it takes: ld65 resolves them against
; this object, which is on the command line, and never goes looking in the
; library. The syscall table keeps its exact layout and every other entry keeps
; its address, so nothing that calls into it needs rebuilding - a loadable that
; asked for XMODEM would get a carry back instead of a transfer, and no loadable
; in the tree asks.
;
; rom/modem_test and rom/minimal_bootloader define no such thing and link the
; real module, exactly as before.
; ----------------------------------------------------------------------------
.segment "EXTCODE2"

_modem_send:
_modem_receive:
        sec                             ; not in this ROM
        rts

; Called in place of _tty_init from standalone.s, which is the last moment
; before anything is printed.
;
; BASBUF is deliberately never zeroed - that is the whole reason start_magic can
; tell a reset from a power-on - so gtx_active holds whatever the SRAM came up
; with until something writes it, and in 255 cases out of 256 that is "graphics
; is on". The sign-on banner then went through the bitmap renderer while the
; machine was in text mode, straight across the font at $0800, and the first
; thing on the screen after a power-on was rubbish. SCREEN 1 followed by
; SCREEN 0 reloaded the font and cleared the flag, which is why it cured itself
; and stayed cured.
;
; start_select clears it too, but that runs after the banner.
gtx_tty_init:
        stz     gtx_active
        jmp     _tty_init

; A = character
gtx_write_char:
        pha
        lda     gtx_active
        bne     @graphics
        pla
        jmp     vdp_write_char
@graphics:
        pla
        cmp     #$0d                    ; carriage return
        beq     @carriage_return
        cmp     #$0a                    ; line feed
        beq     gtx_newline_active
        jsr     gtx_render
        ; and on to the next cell, or the next row if that was the last one.
        ; Wrapping used to put the column back to nought and leave the row
        ; alone, so a long line overwrote itself from the left.
        inc     gtx_col
        lda     gtx_col
        cmp     #GTX_COLUMNS
        bcc     @done
        bra     gtx_newline_active
@carriage_return:
        stz     gtx_col
@done:
        rts

; No arguments
gtx_newline:
        lda     gtx_active
        bne     gtx_newline_active
        jmp     vdp_newline
gtx_newline_active:
        stz     gtx_col
        inc     gtx_row
        lda     gtx_row
        cmp     #GTX_ROWS
        bcc     @done
        lda     #GTX_ROWS-GTX_SCROLL_ROWS
        sta     gtx_row                 ; land on the first row that came free
        jsr     gtx_scroll
@done:
        rts

; No arguments
gtx_backspace:
        lda     gtx_active
        bne     @graphics
        jmp     vdp_backspace
@graphics:
        lda     gtx_col
        beq     @done                   ; nothing to rub out on this row
        dec     gtx_col
        lda     #' '
        jsr     gtx_render
@done:
        rts

; A = low byte of the string, X = high byte
gtx_write_string:
        sta     vdp_buffer_address
        stx     vdp_buffer_address+1
        lda     gtx_active
        bne     @graphics
        lda     vdp_buffer_address
        ldx     vdp_buffer_address+1
        jmp     vdp_write_string
@graphics:
        phy                             ; the caller's index, same as above
        ldy     #$00
@next:
        lda     (vdp_buffer_address),y
        beq     @done
        jsr     gtx_write_char
        iny
        bne     @next
@done:
        ply
        rts

; ----------------------------------------------------------------------------
; gtx_scroll - move the picture up by one character row
;
; A character row is exactly one 256-byte page of the bitmap. The byte holding
; pixel (x,y) sits at high = y>>3, low = (x & $F8) | (y & 7), so across a row
; the high byte is the row number and the low byte runs the full 0..255.
; Scrolling is therefore 23 page moves in the shape table and 23 in the colour
; table, with the row that comes free cleared afterwards.
;
; That is 11776 bytes across the processor twice, and there is no way around
; it. The 9918 has no block move, and Graphics II gives every cell its own
; pattern, so the name table cannot be rotated the way a text mode screen can -
; a cell can only reach the 2 KB pattern block belonging to its third of the
; screen, and scrolling crosses those boundaries. It costs about a third of a
; second per line.
;
; The loops pace themselves. The chip asks for eight microseconds between
; accesses and the tightest loop here leaves thirteen, so there is no vdp_wait
; in them and the display can stay on. What that shows is the copy sweeping
; down the screen, which reads as the scroll it is.
;
; text_screen_buffer holds the page in transit. It belongs to the text mode
; scroll, which cannot be running while this is.
;
; Every register comes back untouched, and that is not politeness. This hangs
; off the newline path, where vdp_newline and the whole text mode scroll behind
; it save A, X and Y - tty_read_line is sitting there with its buffer index in
; Y, and the line being typed is built on it. Handing back a different X or Y
; corrupts the line, and because the prompt is part of that line the machine
; then prints rubbish and scrolls for ever. Same lesson as gtx_render, one
; routine further along.
; ----------------------------------------------------------------------------
gtx_scroll:
        pha
        phx
        phy

        lda     #GFX_BITMAP_HI
        jsr     gtx_scroll_table
        lda     #GFX_COLOR_HI
        jsr     gtx_scroll_table

        ; and the rows that just came free, blank and in the text colour
        lda     #GTX_SCROLL_ROWS
        sta     gfx_count+1
        ldy     #$00
        lda     #(GFX_BITMAP_HI + GTX_ROWS - GTX_SCROLL_ROWS) | VDP_WRITE_VRAM_SELECT
        ldx     #$00
        jsr     gfx_fill
        lda     #GTX_SCROLL_ROWS
        sta     gfx_count+1
        ldy     #$00
        lda     #(GFX_COLOR_HI + GTX_ROWS - GTX_SCROLL_ROWS) | VDP_WRITE_VRAM_SELECT
        ldx     #GTX_COLOUR
        jsr     gfx_fill

        ply
        plx
        pla
        rts

; A = high byte of the table. Moves pages 1..23 down onto 0..22.
gtx_scroll_table:
        sta     gtx_page
        ldx     #GTX_ROWS-GTX_SCROLL_ROWS
@page:
        ldy     #$00                    ; read the row that comes down here
        lda     gtx_page
        clc
        adc     #GTX_SCROLL_ROWS
        ora     #VDP_READ_VRAM_SELECT
        jsr     vdp_write_address
        ldy     #$00
@read:
        lda     VDP_VRAM
        sta     text_screen_buffer,y
        iny
        bne     @read

        ldy     #$00                    ; put it down one row
        lda     gtx_page
        ora     #VDP_WRITE_VRAM_SELECT
        jsr     vdp_write_address
        ldy     #$00
@write:
        lda     text_screen_buffer,y
        sta     VDP_VRAM
        iny
        bne     @write

        inc     gtx_page
        dex
        bne     @page
        rts

; ----------------------------------------------------------------------------
; Draws A into the cell at gtx_col/gtx_row without moving the cursor.
;
; Y has to come back untouched. tty_write_byte saves X around the echo and not
; Y, and tty_read_line is sitting there with its buffer index in Y - the
; routines this layer replaced happened to leave Y alone, so nothing ever said
; so out loud. Getting it wrong corrupts the line as it is typed and every
; input comes back as ?SN ERROR.
gtx_render:
        phy
        and     #$7f                    ; the font holds 128 shapes
        sta     gtx_src                 ; character * 8 into the font
        stz     gtx_src+1
        asl     gtx_src
        rol     gtx_src+1
        asl     gtx_src
        rol     gtx_src+1
        asl     gtx_src
        rol     gtx_src+1
        clc
        lda     gtx_src
        adc     #<VDP_TEXT_PATTERNS_START
        sta     gtx_src
        lda     gtx_src+1
        adc     #>VDP_TEXT_PATTERNS_START
        sta     gtx_src+1

        lda     gtx_col                 ; the shape
        asl     a
        asl     a
        asl     a
        tay                             ; low byte is column * 8
        lda     gtx_row                 ; high byte is the row itself
        ora     #GFX_BITMAP_HI | VDP_WRITE_VRAM_SELECT
        jsr     vdp_write_address
        ldy     #$00
@shape:
        lda     (gtx_src),y
        sta     VDP_VRAM
        jsr     vdp_wait
        iny
        cpy     #$08
        bne     @shape

        lda     gtx_col                 ; and the colour, same offsets
        asl     a
        asl     a
        asl     a
        tay
        lda     gtx_row
        ora     #GFX_COLOR_HI | VDP_WRITE_VRAM_SELECT
        jsr     vdp_write_address
        ldy     #$08
@colour:
        lda     #GTX_COLOUR
        sta     VDP_VRAM
        jsr     vdp_wait
        dey
        bne     @colour
        ply
        rts

.zeropage
gtx_src:        .res 2

.segment "BASBUF"
gtx_active:     .res 1                  ; non-zero while SCREEN 1 is up
gtx_col:        .res 1
gtx_row:        .res 1
gtx_page:       .res 1                  ; the row gtx_scroll is moving down to

.segment "BASBUF"
spr_n:          .res 1
spr_x:          .res 1
spr_y:          .res 1
spr_pat:        .res 1
spr_col:        .res 1
vpoke_value:    .res 1

.segment "BASBUF"
circle_cx:      .res 1
circle_cy:      .res 1
circle_r:       .res 1
circle_ox:      .res 1
circle_oy:      .res 1
circle_sign:    .res 1
cir_x:          .res 1
cir_y:          .res 1
cir_f:          .res 2
cir_ddx:        .res 2
cir_ddy:        .res 2


.segment "BASBUF"
start_magic:    .res START_MAGIC_LEN

.segment "STARTUP"
  jmp init

.segment "SYSRAM"
TXTBUFFER:
  .res 64
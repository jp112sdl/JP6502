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
      .import sn_send
      .import ACIA_STATUS
      .import ACIA_DATA
;      .import ACIA_STATUS_RX_FULL
      .export _start_msbasic

.segment "CODE"

ISCNTC:
          jmp MONISCNTC
;!!! *used*to* run into "STOP"

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
      ; start_select in EXTCODE2 decides. The jump keeps this call site the
      ; length the prompt had, because CODE must not change size:
      ; MEMORY_MAP.md section 5.2.3.
      jmp start_select

      ; The 29 bytes the prompt used to occupy here. Never executed; they are
      ; kept so that every library module behind msbasic.o stays on the address
      ; the working ROM has.
      .repeat 29
      nop
      .endrepeat

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

; COLOR lives in EXTCODE2 rather than next to CLS in SDCODE. Twenty-five bytes
; here would push every module behind it in SDCODE to a new address, and on
; this board that is the one change that has twice come back as a screen full
; of the wrong glyphs - see MEMORY_MAP.md 5.1.1 and 5.2.1. EXTCODE2 is 1.6 KB
; of empty ROM behind SYSCALLS, so a statement put here moves nothing at all.
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
GFX_DEFAULT_COL = $F1                   ; white on black, the whole screen

SCREEN:
        jsr     GETBYT                  ; mode -> X
        cpx     #$02
        bcs     SCREEN_RANGE
        txa
        beq     screen_text

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
        ldy     #$00
        lda     #GFX_BITMAP_HI | VDP_WRITE_VRAM_SELECT
        ldx     #$00
        jsr     gfx_fill

        ; colour: every group white on black
        ldy     #$00
        lda     #GFX_COLOR_HI | VDP_WRITE_VRAM_SELECT
        ldx     #GFX_DEFAULT_COL
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

        ; No sprites. The attribute table sits above everything filled above, so
        ; without this it holds whatever the VRAM came up with and the chip
        ; cheerfully displays 32 of them at random positions out of whatever the
        ; pattern base points at - which is what a black screen covered in
        ; debris looks like. $D0 in the first sprite's Y byte ends the list and
        ; turns all of them off.
        ldy     #$00
        lda     #$3B | VDP_WRITE_VRAM_SELECT
        jsr     vdp_write_address
        lda     #$D0
        sta     VDP_VRAM
        jsr     vdp_wait

        ; Filling takes about a quarter of a second, and the register table
        ; above leaves the screen blanked so that quarter second is not spent
        ; showing whatever the VRAM happened to contain.
        lda     #(VDP_REG1_RAM_16K | VDP_REG1_SCREEN_ACTIVE)
        ldx     #VDP_REGISTER_1
        jsr     vdp_write_register

        ; The console has nowhere to go now. gfx_tty_saved doubles as the flag
        ; for "graphics is on", so a second SCREEN 1 must not overwrite the
        ; setting it is holding with the one it already switched the VDP out of.
        lda     gfx_tty_saved
        bne     @already_saved
        lda     tty_config
        sta     gfx_tty_saved
@already_saved:
        lda     tty_config
        and     #<~(TTY_CONFIG_OUTPUT_VDP)
        sta     tty_config
        rts

; --- back to text -----------------------------------------------------------
screen_text:
        lda     gfx_tty_saved
        beq     @nothing_saved
        sta     tty_config
        stz     gfx_tty_saved
@nothing_saved:
        jsr     vdp_boot_registers      ; the text mode register table
        jsr     vdp_boot_patterns       ; the font the bitmap overwrote
        jsr     vdp_boot_clear
        jsr     vdp_boot_enable
        stz     vdp_line
        stz     vdp_char_pos
        rts

SCREEN_RANGE:
        jmp     IQERR

; Y/A = start address including the write select, X = value.
; 6144 bytes - the count is the same idiom vdp_boot_clear uses, where the low
; byte runs out first and 0 means a full 256.
gfx_fill:
        stx     gfx_value
        jsr     vdp_write_address
        stz     gfx_count
        lda     #$18
        sta     gfx_count+1
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

gfx_tty_saved:  .res 1                  ; tty_config as it was before SCREEN 1
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
; In EXTCODE2 because inserting into CODE moves every library module behind
; msbasic.o, which on this board kills the picture - MEMORY_MAP.md 5.2.3.
; ----------------------------------------------------------------------------
.segment "EXTCODE2"

START_MAGIC_LEN = 6

start_select:
        ; BASBUF holds whatever the SRAM came up with, and SCREEN 0 would write
        ; that straight into tty_config
        stz     gfx_tty_saved

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

.segment "BASBUF"
start_magic:    .res START_MAGIC_LEN

.segment "STARTUP"
  jmp init

.segment "SYSRAM"
TXTBUFFER:
  .res 64
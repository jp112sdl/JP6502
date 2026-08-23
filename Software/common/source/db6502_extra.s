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

; Display startup message
ShowStartMsg:
      writeln_tty #StartupMessage

; Wait for a cold/warm start selection
WaitForKeypress:
 ;   SEC
	JSR	MONRDKEY
	BCC	WaitForKeypress
	
	AND	#$DF			; Make upper case
	CMP	#'W'			; compare with [W]arm start
	BEQ	WarmStart

	CMP	#'C'			; compare with [C]old start
;	BNE	ShowStartMsg
    BNE WaitForKeypress
;    BEQ COLD_START

	JMP	sd_coldstart	; BASIC cold start, with the busy light on
;    JMP WaitForKeypress

WarmStart:
	JMP	RESTART		; BASIC warm start

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

.segment "STARTUP"
  jmp init

.segment "SYSRAM"
TXTBUFFER:
  .res 64
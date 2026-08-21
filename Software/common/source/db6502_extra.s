      .include "acia.inc"
      .include "keyboard.inc"
      .include "sd.inc"
      .include "lcd.inc"
      .include "blink.inc"
      .include "sys_const.inc"
      .include "sound.inc"
      .include "utils.inc"
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

.segment "STARTUP"
  jmp init

.segment "SYSRAM"
TXTBUFFER:
  .res 64
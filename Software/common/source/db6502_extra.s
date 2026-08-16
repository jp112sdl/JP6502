      .include "acia.inc"
      .include "keyboard.inc"
      .include "sd.inc"
      .include "lcd.inc"
      .include "blink.inc"
      .include "sys_const.inc"
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

.segment "STARTUP"
  jmp init

.segment "SYSRAM"
TXTBUFFER:
  .res 64
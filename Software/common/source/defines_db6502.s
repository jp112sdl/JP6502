.import __USERRAM_START__
.import __BAS_RAM_START__

; configuration
CONFIG_2C := 1

CONFIG_DATAFLG := 1
CONFIG_NULL := 1
CONFIG_PRINT_CR := 0 ; print CR when line end reached
CONFIG_SCRTCH_ORDER := 3
CONFIG_SMALL := 1

; zero page
ZP_START1 = $00
ZP_START2 = $0D
ZP_START3 = $5B
ZP_START4 = $65

;extra ZP variables
USR             := $000A

; inputbuffer
; Must stay an assembly-time constant: defines.s evaluates INPUTBUFFER in .if
; expressions and derives INPUTBUFFERX = INPUTBUFFER & $FF00, so a linker
; symbol cannot be used here. The pages are reserved by the BAS_RAM memory
; area in firmware.ext.cfg; the assert below makes a mismatch a link-time
; error. Was $0900, which sat inside the BSS segment (menu/modem/tty
; variables).
;
; It sits in the *second* page of BAS_RAM because PUT_NEW_LINE assembles the
; link pointer and the line number at INPUTBUFFER-4..INPUTBUFFER-1 - the page
; below has to belong to BASIC as well. At $0E00 those four bytes fell into
; the tail of the FAT32 sector buffer.
INPUTBUFFER     := $0F00
.assert INPUTBUFFER = __BAS_RAM_START__ + $0100, error, "INPUTBUFFER must be the second page of BAS_RAM in the linker config"
STACK2          := TXTBUFFER
; constants
; STACK_TOP		:= $FC
SPACE_FOR_GOSUB := $33
NULL_MAX		:= $0A
WIDTH			:= 72
WIDTH2			:= 56

; memory layout
RAMSTART2		:= __USERRAM_START__

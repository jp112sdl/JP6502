.import __USERRAM_START__

; configuration
CONFIG_2C := 1

CONFIG_DATAFLG := 1
CONFIG_NULL := 1
CONFIG_PRINT_CR := 0 ; print CR when line end reached
CONFIG_SCRTCH_ORDER := 3
CONFIG_SMALL := 1

; Skip the "MEMORY SIZE" and "TERMINAL WIDTH" questions at cold start. Both
; only make sense on a machine whose RAM size and terminal are unknown at build
; time; here the memory map is fixed and WIDTH/WIDTH2 below are the answer.
; BASIC behaves as if both had been confirmed with an empty line: the RAM probe
; runs and finds the top of USERRAM by itself.
CONFIG_NO_INIT_PROMPTS := 1

; Sign-on line, emitted at QT_BASIC in the shared common/source/init.s.
.define BASIC_BANNER "DB6502 BASIC VERSION 2C"

; zero page
ZP_START1 = $00
ZP_START2 = $0D
ZP_START3 = $5B
ZP_START4 = $65

;extra ZP variables
USR             := $000A

; inputbuffer
INPUTBUFFER     := $0900
STACK2          := TXTBUFFER
; constants
; STACK_TOP		:= $FC
SPACE_FOR_GOSUB := $33
NULL_MAX		:= $0A
WIDTH			:= 72
WIDTH2			:= 56

; memory layout
RAMSTART2		:= __USERRAM_START__

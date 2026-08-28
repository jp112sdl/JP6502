		init_token_tables

		keyword_rts "END", END
		keyword_rts "FOR", FOR
		keyword_rts "NEXT", NEXT
		keyword_rts "DATA", DATA
.ifdef CONFIG_FILE
		keyword_rts "INPUT#", INPUTH
.endif
		keyword_rts "INPUT", INPUT
		keyword_rts "DIM", DIM
		keyword_rts "READ", READ
.ifdef APPLE
		keyword_rts "PLT", PLT
.else
		keyword_rts "LET", LET
.endif
		keyword_rts "GOTO", GOTO, TOKEN_GOTO
.ifdef DB6502
    keyword_rts "EXIT", EXIT_BASIC
.endif
		keyword_rts "RUN", RUN
		keyword_rts "IF", IF
		keyword_rts "RESTORE", RESTORE
		keyword_rts "GOSUB", GOSUB, TOKEN_GOSUB
		keyword_rts "RETURN", POP
.ifdef APPLE
		keyword_rts "TEX", TEX, TOKEN_REM
.else
		keyword_rts "REM", REM, TOKEN_REM
.endif
		keyword_rts "STOP", STOP
		keyword_rts "ON", ON
; NULL is deliberately not in the table any more, while CONFIG_NULL stays
; defined so its routine keeps its place in CODE - the arrangement flow1.s
; already describes for CBM1. It set the count of null bytes sent after every
; carriage return, a timing crutch for mechanical teletypes, and it was costing
; six bytes of a table that had run out of them. See the assert at the end of
; this file.
.ifdef KBD
		keyword_rts "PLOD", PLOD
		keyword_rts "PSAV", PSAV
		keyword_rts "VLOD", VLOD
		keyword_rts "VSAV", VSAV
.endif
.ifndef CONFIG_NO_POKE
		keyword_rts "WAIT", WAIT
.endif
.ifndef KBD
		keyword_rts "LOAD", LOAD
		keyword_rts "SAVE", SAVE
.endif
.ifdef CONFIG_CBM_ALL
		keyword_rts "VERIFY", VERIFY
.endif
		keyword_rts "DEF", DEF
.ifdef KBD
		keyword_rts "SLOD", SLOD
.endif
.ifndef CONFIG_NO_POKE
		keyword_rts "POKE", POKE
.endif
.ifdef CONFIG_FILE
		keyword_rts "PRINT#", PRINTH
.endif
		keyword_rts "PRINT", PRINT, TOKEN_PRINT
		keyword_rts "CONT", CONT
		keyword_rts "LIST", LIST
.ifdef CONFIG_CBM_ALL
		keyword_rts "CLR", CLEAR
.else
		keyword_rts "CLEAR", CLEAR
.endif
.ifdef CONFIG_FILE
		keyword_rts "CMD", CMD
		keyword_rts "SYS", SYS
		keyword_rts "OPEN", OPEN
		keyword_rts "CLOSE", CLOSE
.endif
.ifndef CONFIG_SMALL
		keyword_rts "GET", GET
.endif
.ifdef KBD
		keyword_rts "PRT", PRT
.endif
		keyword_rts "NEW", NEW
.ifdef DB6502
; Appended after the last statement so that every token already in use keeps
; its number. The function and operator tokens counted after this point do move
; up by one, but those are immediates in the interpreter, not stored in
; programs - a listing saved on the SD card still reads back correctly.
		keyword_rts "SOUND", SOUND
		keyword_rts "CLS", CLS
		keyword_rts "COLOR", COLOR
		keyword_rts "SCREEN", SCREEN
		keyword_rts "PLOT", PLOT
		keyword_rts "LINE", LINE
.endif

		count_tokens

		keyword	"TAB(", TOKEN_TAB
		keyword	"TO", TOKEN_TO
		keyword	"FN", TOKEN_FN
		keyword	"SPC(", TOKEN_SPC
		keyword	"THEN", TOKEN_THEN
		keyword	"NOT", TOKEN_NOT
		keyword	"STEP", TOKEN_STEP
		keyword	"+", TOKEN_PLUS
		keyword	"-", TOKEN_MINUS
		keyword	"*"
		keyword	"/"
.ifdef KBD
		keyword	"#"
.else
		keyword	"^"
.endif
		keyword	"AND"
		keyword	"OR"
		keyword	">", TOKEN_GREATER
		keyword	"=", TOKEN_EQUAL
		keyword	"<"

.ifndef DB6502
        .segment "VECTORS"
.else
        .segment "BAS_VEC"
.endif
UNFNC:

		keyword_addr "SGN", SGN, TOKEN_SGN
		keyword_addr "INT", INT
		keyword_addr "ABS", ABS
.ifdef KBD
		keyword_addr "VER", VER
.endif
.ifndef CONFIG_NO_POKE
  .ifdef CONFIG_RAM
		keyword_addr "USR", IQERR
  .else
		keyword_addr "USR", USR, TOKEN_USR
  .endif
.endif
		keyword_addr "FRE", FRE
		keyword_addr "POS", POS
		keyword_addr "SQR", SQR
		keyword_addr "RND", RND
		keyword_addr "LOG", LOG
		keyword_addr "EXP", EXP
.ifndef DB6502
.segment "VECTORS"
.else
.segment "BAS_VEC"
.endif
UNFNC_COS:
		keyword_addr "COS", COS
.ifndef DB6502
.segment "VECTORS"
.else
.segment "BAS_VEC"
.endif
UNFNC_SIN:
		keyword_addr "SIN", SIN
.ifndef DB6502
.segment "VECTORS"
.else
.segment "BAS_VEC"
.endif
UNFNC_TAN:
		keyword_addr "TAN", TAN
.ifndef DB6502
.segment "VECTORS"
.else
.segment "BAS_VEC"
.endif
UNFNC_ATN:
		keyword_addr "ATN", ATN
.ifdef KBD
		keyword_addr "GETC", GETC
.endif
.ifndef CONFIG_NO_POKE
		keyword_addr "PEEK", PEEK
.endif
		keyword_addr "LEN", LEN
		keyword_addr "STR$", STR
		keyword_addr "VAL", VAL
		keyword_addr "ASC", ASC
		keyword_addr "CHR$", CHRSTR
		keyword_addr "LEFT$", LEFTSTR, TOKEN_LEFTSTR
		keyword_addr "RIGHT$", RIGHTSTR
		keyword_addr "MID$", MIDSTR
.ifdef CONFIG_2
		keyword	"GO", TOKEN_GO
.endif
.ifndef DB6502
        .segment "KEYWORDS"
.else
        .segment "BAS_KEY"
.endif
		.byte   0

.ifndef DB6502
        .segment "VECTORS"
.else
        .segment "BAS_VEC"
.endif
; The tokenizer walks this table with an 8-bit Y - the compare at L2498 in
; program.s and the scan at L24DB that steps over the keyword it just failed on.
; Every byte of it therefore has to be reachable from TOKEN_NAME_TABLE through
; one index register, the terminating zero included. At 257 bytes that zero sits
; at offset 256, Y wraps round to nought, the scan starts over from the first
; keyword and never finds an end: the machine hangs on the first ENTER. That is
; what adding LINE did on 2026-08-25, and nothing in the build said a word about
; it, so now something does.
.import __BAS_KEY_SIZE__
.assert __BAS_KEY_SIZE__ <= 256, lderror, "BAS_KEY is past 256 bytes and the tokenizer cannot index it - shorten or drop a keyword"

MATHTBL:
        .byte   $79
        .word   FADDT-1
        .byte   $79
        .word   FSUBT-1
        .byte   $7B
        .word   FMULTT-1
        .byte   $7B
        .word   FDIVT-1
        .byte   $7F
        .word   FPWRT-1
        .byte   $50
        .word   TAND-1
        .byte   $46
        .word   OR-1
        .byte   $7D
        .word   NEGOP-1
        .byte   $5A
        .word   EQUOP-1
        .byte   $64
        .word   RELOPS-1

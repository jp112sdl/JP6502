        .include "zeropage.inc"
        .import _main
        .import copydata
        .import zerobss

        .export   __STARTUP__ : absolute = 1

; The rest of the cc65 runtime zero page lives in zeropage.s, but regbank does
; not: it is only touched by compiled code using register variables (-Or), and
; putting it there would push every MS-BASIC zero page label six bytes up. That
; changes no segment size, yet it rewrites 1725 of the 15369 CODE bytes in the
; BASIC ROM - every absolute operand pointing into the zero page. On this board
; that is not a risk worth taking for a symbol pure assembler builds never use,
; see MEMORY_MAP.md section 5.2.1.
;
; crt0.o is pulled out of common.c.lib only by the .forceimport __STARTUP__ that
; cc65 puts into every compiled module, so assembler-only ROMs keep the zero
; page they have today, byte for byte. Without this definition ld65 goes looking
; in none.lib instead, drags in its zeropage.o and stops with
; "Duplicate external identifier: 'tmp4'".
        .exportzp regbank

        .zeropage

regbank:
        .res 6

        .segment "STARTUP"
init:
        jsr zerobss
        jsr copydata
        jsr _main
        rts

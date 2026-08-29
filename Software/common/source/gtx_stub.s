; ----------------------------------------------------------------------------
; Graphics-mode text: the plain version
;
; tty.s sends every VDP character through gtx_write_char and its neighbours
; rather than calling vdp_write_char and friends directly, so that a build which
; has a bitmap mode can put characters into the bitmap instead. That hook has to
; resolve in every ROM that uses tty.s, and most of them have no bitmap mode and
; no business carrying the renderer for one.
;
; So this is the version they get: four jumps straight back to where tty.s used
; to go. It is a library module, and ld65 only pulls a library module when a
; symbol is still unresolved - the MS-BASIC ROM defines the same four entry
; points in db6502_extra.s, which is an object on the command line rather than a
; library, so there this file is never pulled at all.
;
; The jumps live in EXTCODE2, which costs those ROMs twelve bytes of otherwise
; empty ROM and not one byte of CODE. That distinction used to be the whole
; game on this board; since the decoder was fixed it is only tidiness -
; MEMORY_MAP.md 5.5.
; ----------------------------------------------------------------------------

        .setcpu "65C02"

        .include "vdp_text_mode.inc"

        .export gtx_write_char
        .export gtx_write_string
        .export gtx_newline
        .export gtx_backspace

        .segment "EXTCODE2"

gtx_write_char:
        jmp vdp_write_char

gtx_write_string:
        jmp vdp_write_string

gtx_newline:
        jmp vdp_newline

gtx_backspace:
        jmp vdp_backspace

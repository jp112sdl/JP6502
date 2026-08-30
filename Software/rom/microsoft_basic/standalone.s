; Standalone wrapper around the shared MS-BASIC in common/source.
;
; common/source/msbasic.s is written to be entered as a subroutine from OS/1:
; it assumes the hardware is already initialised and it supplies no reset
; vectors. This file adds the bits a bootable ROM needs - the VECTORS segment
; and the power-on init sequence - so the same BASIC sources can also be
; flashed as a BASIC-only ROM.
;
; Note that VECTORS and SYSCALLS are optional=yes in firmware.ext.cfg, so a
; missing VECTORS segment would not be a link error, just a dead ROM.

        .include "core.inc"
        .include "tty.inc"
        .include "lcd.inc"
        .include "syscalls.inc"
        .include "banner.inc"

        .import _start_msbasic
        .import gtx_tty_init


        .segment "VECTORS"

        .word   $0000               ; NMI  - unused
        .word   reset               ; RESET
        .word   _interrupt_handler  ; IRQ / BRK

        .code

reset:
        ; Set up the stack before anything else - _start_msbasic records the
        ; current stack pointer in INIT_STACK and restores it on every warm
        ; start, so it has to be sane at this point.
        ldx #$ff
        txs
        ; Bring up blink LED, sound, LCD, ACIA, keyboard, VDP and SD
        jsr _system_init
        ; Banner on the LCD, then the same console configuration and the same
        ; banner on the VDP that the previous standalone ROM printed
        write_lcd #ms_basic
        lda #(TTY_CONFIG_INPUT_KEYBOARD | TTY_CONFIG_OUTPUT_VDP)
        ; gtx_tty_init is _tty_init with the graphics-text flag cleared first.
        ; A jsr for a jsr, so standalone.o kept its length and nothing behind it
        ; moved - which was the whole game once, see MEMORY_MAP.md 5.5.
        jsr gtx_tty_init
        writeln_tty #ms_basic
        ; Enter BASIC. It returns when the EXIT command is used; without an
        ; operating system to return to, start over.
        jsr _start_msbasic
        jmp reset

        .segment "RODATA"

ms_basic:
        .byte BASIC_BANNER, $00

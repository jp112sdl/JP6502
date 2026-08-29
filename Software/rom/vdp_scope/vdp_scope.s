;------------------------------------------------------------------------------
;
; vdp_scope - the failing access and the working one, side by side, for a
; logic analyser
;
; What is being looked for. The same probe, byte for byte, fails out of ROM at
; low byte $90 and passes at $40, over hundreds of rounds with no drift. When it
; fails, the two bytes read back are A5 20 where 5A A5 was written - that is
; the second value written followed by the contents of $0000, so the VRAM read
; pointer stood at $3FFF instead of $3FFE. Off by exactly one. See
; MEMORY_MAP.md 5.5 for how that was arrived at.
;
; Two causes fit, and an analyser can tell them apart in one capture:
;
;   1. The low address byte reached the control port as $FF instead of $FE.
;      That is one data line, D0, and it would point at bus contention - the
;      ROM still driving when the CPU writes to $8081.
;   2. There was one access too many on the data port, which stepped the
;      pointer once extra. That would show as a strobe nobody programmed.
;
; So this ROM makes the capture easy. It runs the good copy and the bad copy
; back to back inside one trigger window, with a marker on the LED line, and
; then waits long enough for the analyser to re-arm:
;
;   marker high   - the copy at low byte $40, which works
;   marker low    - short gap
;   marker high   - the copy at low byte $90, which does not
;   marker low    - about 20 ms of quiet
;
; Trigger on the first rising edge after the quiet stretch and both probes are
; in one window, the working one first. Everything the two do is identical; the
; only difference is the address they are fetched from.
;
; The marker is bit 7 of VIA2 port B, which is the LED line - already an output
; and easy to find on the board. The LED will flicker while this runs.
;
; The LCD keeps score, so it is possible to see that the bad copy really is
; failing during the capture:
;
;   VDP SCOPE
;   40 5A A5
;   90 A5 20
;   BAD=0123
;
;------------------------------------------------------------------------------

        .setcpu "65C02"

        .include "lcd.inc"
        .include "utils.inc"
        .include "blink.inc"
        .include "via.inc"
        .include "vdp.inc"
        .include "vdp_text_mode.inc"
        .include "vdp_const.inc"
        .include "zeropage.inc"

MARKER        = %10000000               ; bit 7 of VIA2 port B, the LED line

PROBE_LO      = $FE                     ; $3FFE, clear of every table
PROBE_HI      = $3F
PROBE_V1      = $5A
PROBE_V2      = $A5

        .segment "VECTORS"

        .word   $0000
        .word   init
        .word   $0000

        .zeropage

probe_r0:       .res 1
probe_r1:       .res 1

        .segment "BSS"

good_bytes:     .res 2
bad_bytes:      .res 2
bad_count:      .res 2

        .code

init:
        cld
        jsr _blink_init                 ; makes bit 7 of VIA2 port B an output
        jsr _lcd_init
        jsr _lcd_clear

        lda VDP_REG
        jsr vdp_boot_registers
        jsr vdp_boot_patterns
        jsr vdp_boot_clear
        jsr vdp_boot_enable

        stz bad_count
        stz bad_count+1

@loop:
        ; --- the copy that works, inside the first marker pulse -------------
        lda #MARKER
        sta VIA2_PORTB
        jsr probe_good
        stz VIA2_PORTB
        lda probe_r0
        sta good_bytes
        lda probe_r1
        sta good_bytes+1

        ; a short gap, so the two pulses are clearly two
        lda #$20
@gap:   dec a
        bne @gap

        ; --- the copy that does not, inside the second -----------------------
        lda #MARKER
        sta VIA2_PORTB
        jsr probe_bad
        stz VIA2_PORTB
        lda probe_r0
        sta bad_bytes
        lda probe_r1
        sta bad_bytes+1

        cmp #PROBE_V2                   ; probe_r1 is still in A
        bne @count
        lda bad_bytes
        cmp #PROBE_V1
        beq @report
@count:
        inc bad_count
        bne @report
        inc bad_count+1

@report:
        jsr report
        lda #20                         ; quiet, so the analyser can re-arm
        jsr _delay_ms
        bra @loop

;------------------------------------------------------------------------------
; report
;------------------------------------------------------------------------------
report:
        ldy #$00
        ldx #$00
        jsr lcd_set_position
        lda #<msg_title
        ldx #>msg_title
        jsr _lcd_print

        ldy #$01
        ldx #$00
        jsr lcd_set_position
        lda #<msg_good
        ldx #>msg_good
        jsr _lcd_print
        lda good_bytes
        jsr print_hex
        lda #' '
        jsr _lcd_print_char
        lda good_bytes+1
        jsr print_hex

        ldy #$02
        ldx #$00
        jsr lcd_set_position
        lda #<msg_bad
        ldx #>msg_bad
        jsr _lcd_print
        lda bad_bytes
        jsr print_hex
        lda #' '
        jsr _lcd_print_char
        lda bad_bytes+1
        jsr print_hex

        ldy #$03
        ldx #$00
        jsr lcd_set_position
        lda #<msg_count
        ldx #>msg_count
        jsr _lcd_print
        lda bad_count+1
        jsr print_hex
        lda bad_count
        jmp print_hex

;------------------------------------------------------------------------------
; print_hex - A as two hex digits. X and Y are destroyed.
;------------------------------------------------------------------------------
print_hex:
        pha
        lsr a
        lsr a
        lsr a
        lsr a
        jsr @nibble
        pla
        and #$0f
@nibble:
        cmp #10
        bcs @letter
        clc
        adc #'0'
        jmp _lcd_print_char
@letter:
        clc
        adc #('A'-10)
        jmp _lcd_print_char

        .segment "RODATA"

msg_title: .byte "VDP SCOPE", $00
msg_good:  .byte "40 ", $00
msg_bad:   .byte "90 ", $00
msg_count: .byte "BAD=", $00

;------------------------------------------------------------------------------
;
; The probe, twice. Nothing in it refers to itself, so the two copies are the
; same bytes at two addresses - checked against the built image. Four nops
; between accesses leave fourteen cycles, well over the eight the chip asks
; for; this is not a test of the pacing.
;
;------------------------------------------------------------------------------

.macro  vdp_scope_probe
        lda #PROBE_LO
        sta VDP_REG
        nop
        nop
        nop
        nop
        lda #(PROBE_HI | VDP_WRITE_VRAM_SELECT)
        sta VDP_REG
        nop
        nop
        nop
        nop

        lda #PROBE_V1
        sta VDP_VRAM
        nop
        nop
        nop
        nop
        lda #PROBE_V2
        sta VDP_VRAM
        nop
        nop
        nop
        nop

        lda #PROBE_LO
        sta VDP_REG
        nop
        nop
        nop
        nop
        lda #(PROBE_HI | VDP_READ_VRAM_SELECT)
        sta VDP_REG
        nop
        nop
        nop
        nop

        lda VDP_VRAM
        sta probe_r0
        nop
        nop
        nop
        nop
        lda VDP_VRAM
        sta probe_r1
        rts
.endmacro

        .segment "ROMP_4"               ; $C440, low byte $40 - this one works
probe_good:
        vdp_scope_probe

        .segment "ROMP_2"               ; $C290, low byte $90 - this one fails
probe_bad:
        vdp_scope_probe

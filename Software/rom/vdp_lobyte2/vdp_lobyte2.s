;------------------------------------------------------------------------------
;
; vdp_lobyte2 - the low byte again, without the two flaws in the first map
;
; rom/vdp_lobyte put sixteen copies of a control-port probe at low bytes $00 to
; $F0 and came back with this:
;
;   00+ 10+ 20+ 30+
;   40+ 50- 60+ 70+      ($40, $60 and $70 also failed on the first cold start)
;   80- 90- A0- B0-
;   C0+ D0+ E0+ F0+
;
; Sorted by the top two bits of the low byte that is a clean split. A7 and A6
; equal - $00-$30 and $C0-$F0 - always passes. A7 and A6 different - $40-$70
; and $80-$B0 - fails, solidly when A7 is the one set and unreliably when A6
; is. That is what two coupled neighbouring lines look like: when they agree no
; current flows between them, when they differ the weaker one is dragged.
;
; Two flaws in that burn, both mine, and this ROM fixes both.
;
; The first is that page and low byte were the same variable: probe k sat at
; $B0+k pages and low byte k*$10, so A11..A8 always equalled A7..A4 and the
; split could just as well be A11 against A10. Here each low byte is linked
; twice, once in page $D0+k and once in page $D0+((k+8) mod 16). If the two
; sets agree, the low byte decides. If they follow their pages instead, the
; page does.
;
; The second is that the probe is 62 bytes long, so a copy at $50 actually
; spends its time between $50 and $8D and straddles the split. Steps of 8
; instead of 16, over the interesting band $40 to $B8, sample it twice as
; finely.
;
; And because the first map was partly intermittent, each copy now runs fifteen
; times and the report is the number of failures, one hex digit:
;
;   LO 40-B8 STEP 8
;   000000F0FFFFFFFF     set A, low byte $40 $48 $50 ... $B8
;   000000F0FFFFFFFF     set B, same low bytes, different pages
;
; Two identical rows mean the low byte decides and the pages are innocent.
; Rows that differ mean the page is in it after all, and the digits say where.
;
;------------------------------------------------------------------------------

        .setcpu "65C02"

        .include "lcd.inc"
        .include "utils.inc"
        .include "blink.inc"
        .include "vdp.inc"
        .include "vdp_text_mode.inc"
        .include "vdp_const.inc"
        .include "zeropage.inc"

PROBE_LO      = $FE                     ; $3FFE, clear of every table
PROBE_HI      = $3F
PROBE_V1      = $5A
PROBE_V2      = $A5
RUNS          = 15                      ; so the failure count is one hex digit

        .segment "VECTORS"

        .word   $0000
        .word   init
        .word   $0000

        .zeropage

probe_r0:       .res 1
probe_r1:       .res 1
call_target:    .res 2

        .segment "BSS"

result:         .res 32
fail_count:     .res 1

        .code

init:
        cld
        jsr _blink_init
        jsr _lcd_init
        jsr _lcd_clear

        ; bring the chip up through the ordinary routines, which sit at their
        ; usual address, so every probe meets a VDP that is already running
        lda VDP_REG
        jsr vdp_boot_registers
        jsr vdp_boot_patterns
        jsr vdp_boot_clear
        jsr vdp_boot_enable

        ldx #$00
@next:
        phx
        txa
        asl a
        tax
        lda probe_addr,x
        sta call_target
        lda probe_addr+1,x
        sta call_target+1
        plx

        stz fail_count
        ldy #RUNS
@run:
        phx
        phy
        stz probe_r0
        stz probe_r1
        jsr call_probe
        ply
        plx
        lda probe_r0
        cmp #PROBE_V1
        bne @bad
        lda probe_r1
        cmp #PROBE_V2
        beq @good
@bad:
        inc fail_count
@good:
        dey
        bne @run

        lda fail_count
        sta result,x
        inx
        cpx #32
        bne @next

;--- report ------------------------------------------------------------------

        jsr _lcd_clear

        ldy #$00
        ldx #$00
        jsr lcd_set_position
        lda #<msg_lo
        ldx #>msg_lo
        jsr _lcd_print

        ldy #$01
        ldx #$00
        jsr lcd_set_position
        ldx #$00
        jsr print_row

        ldy #$02
        ldx #$00
        jsr lcd_set_position
        ldx #16
        jsr print_row

        lda #(BLINK_LED_OFF)
        jsr _blink_led
@halt:
        bra @halt

call_probe:
        jmp (call_target)

;------------------------------------------------------------------------------
; print_row - sixteen failure counts starting at result,X, one hex digit each
;------------------------------------------------------------------------------
print_row:
        phx
@cell:
        plx
        phx
        lda result,x
        jsr print_nibble
        plx
        inx
        phx
        txa
        and #$0f
        bne @cell
        plx
        rts

;------------------------------------------------------------------------------
; print_nibble - the low four bits of A as one hex digit. X and Y are destroyed.
;------------------------------------------------------------------------------
print_nibble:
        and #$0f
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

msg_lo:   .byte "LO 40-B8 STEP 8", $00

probe_addr:
        .word   pra_00, pra_01, pra_02, pra_03
        .word   pra_04, pra_05, pra_06, pra_07
        .word   pra_08, pra_09, pra_0A, pra_0B
        .word   pra_0C, pra_0D, pra_0E, pra_0F
        .word   prb_00, prb_01, prb_02, prb_03
        .word   prb_04, prb_05, prb_06, prb_07
        .word   prb_08, prb_09, prb_0A, prb_0B
        .word   prb_0C, prb_0D, prb_0E, prb_0F

;------------------------------------------------------------------------------
;
; The probe. Self-contained: the address write, the wait and the data accesses
; are all inside it, so every byte fetched between two control port accesses
; carries this copy's address.
;
;------------------------------------------------------------------------------

.macro  vdp_lobyte_probe
        ldy #PROBE_LO
        lda #(PROBE_HI | VDP_WRITE_VRAM_SELECT)
        jsr @waddr
        lda #PROBE_V1
        sta VDP_VRAM
        jsr @wait
        lda #PROBE_V2
        sta VDP_VRAM
        jsr @wait

        ldy #PROBE_LO
        lda #(PROBE_HI | VDP_READ_VRAM_SELECT)
        jsr @waddr
        lda VDP_VRAM
        sta probe_r0
        jsr @wait
        lda VDP_VRAM
        sta probe_r1
        rts

@waddr:
        pha
        tya
        sta VDP_REG
        jsr @wait
        pla
        sta VDP_REG
        jmp @wait

@wait:
        nop
        nop
        rts
.endmacro

        .segment "PRA_00"
pra_00:
        vdp_lobyte_probe

        .segment "PRA_01"
pra_01:
        vdp_lobyte_probe

        .segment "PRA_02"
pra_02:
        vdp_lobyte_probe

        .segment "PRA_03"
pra_03:
        vdp_lobyte_probe

        .segment "PRA_04"
pra_04:
        vdp_lobyte_probe

        .segment "PRA_05"
pra_05:
        vdp_lobyte_probe

        .segment "PRA_06"
pra_06:
        vdp_lobyte_probe

        .segment "PRA_07"
pra_07:
        vdp_lobyte_probe

        .segment "PRA_08"
pra_08:
        vdp_lobyte_probe

        .segment "PRA_09"
pra_09:
        vdp_lobyte_probe

        .segment "PRA_0A"
pra_0A:
        vdp_lobyte_probe

        .segment "PRA_0B"
pra_0B:
        vdp_lobyte_probe

        .segment "PRA_0C"
pra_0C:
        vdp_lobyte_probe

        .segment "PRA_0D"
pra_0D:
        vdp_lobyte_probe

        .segment "PRA_0E"
pra_0E:
        vdp_lobyte_probe

        .segment "PRA_0F"
pra_0F:
        vdp_lobyte_probe

        .segment "PRB_00"
prb_00:
        vdp_lobyte_probe

        .segment "PRB_01"
prb_01:
        vdp_lobyte_probe

        .segment "PRB_02"
prb_02:
        vdp_lobyte_probe

        .segment "PRB_03"
prb_03:
        vdp_lobyte_probe

        .segment "PRB_04"
prb_04:
        vdp_lobyte_probe

        .segment "PRB_05"
prb_05:
        vdp_lobyte_probe

        .segment "PRB_06"
prb_06:
        vdp_lobyte_probe

        .segment "PRB_07"
prb_07:
        vdp_lobyte_probe

        .segment "PRB_08"
prb_08:
        vdp_lobyte_probe

        .segment "PRB_09"
prb_09:
        vdp_lobyte_probe

        .segment "PRB_0A"
prb_0A:
        vdp_lobyte_probe

        .segment "PRB_0B"
prb_0B:
        vdp_lobyte_probe

        .segment "PRB_0C"
prb_0C:
        vdp_lobyte_probe

        .segment "PRB_0D"
prb_0D:
        vdp_lobyte_probe

        .segment "PRB_0E"
prb_0E:
        vdp_lobyte_probe

        .segment "PRB_0F"
prb_0F:
        vdp_lobyte_probe

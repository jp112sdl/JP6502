
;------------------------------------------------------------------------------
;
; vdp_lobyte2 - the low byte, averaged, because a single pass is noise
;
; rom/vdp_lobyte put sixteen copies of a control-port probe at low bytes $00 to
; $F0 and came back with a clean-looking split:
;
;   00+ 10+ 20+ 30+
;   40+ 50- 60+ 70+      ($40, $60 and $70 also failed on the first cold start)
;   80- 90- A0- B0-
;   C0+ D0+ E0+ F0+
;
; Sorted by the top two bits of the low byte that divides perfectly: A7 and A6
; equal always passed, A7 and A6 different always failed. That is the shape of
; two coupled neighbouring lines, and it is still the leading explanation.
;
; But the first version of this ROM - fifteen runs per copy, one report - came
; back with different numbers on every cold start. That is the real finding:
; the fault is not deterministic. Which means a single pass measures noise, and
; the tidy map above was partly luck.
;
; So this does not report once. It runs the whole set over and over, counts
; failures per copy, and refreshes the display every sixteen rounds. The
; numbers settle as the rounds add up, and the round counter says how much
; evidence is behind them. Leave it running for a minute before reading it.
;
; Each low byte is linked twice, once in page $D0+k and once in page
; $D0+((k+8) mod 16), so identical low bytes sit in different pages. If the two
; rows converge to the same shape, the low byte decides and the pages are
; innocent. If they stay apart, the page is in it too.
;
; The display:
;
;   N=0140            rounds completed, in hex
;   .....*A.*******   set A, low bytes $40 $48 $50 ... $B8
;   .....*A.*******   set B, same low bytes, different pages
;   LO 40-B8 ST 8
;
; A dot is no failures at all. A digit or letter is that many. A star is
; sixteen or more, so a star means "fails often" and a dot means "never seen to
; fail" - and with the rounds counter beside them, both are worth something.
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
rounds:         .res 2

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

        ldx #31
@clear:
        stz result,x
        dex
        bpl @clear
        stz rounds
        stz rounds+1

;--- round after round, until the power goes off -----------------------------

@round:
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

        stz probe_r0
        stz probe_r1
        phx
        jsr call_probe
        plx

        lda probe_r0
        cmp #PROBE_V1
        bne @bad
        lda probe_r1
        cmp #PROBE_V2
        beq @good
@bad:
        lda result,x
        cmp #$FF                        ; saturate rather than wrap
        beq @good
        inc result,x
@good:
        inx
        cpx #32
        bne @next

        inc rounds
        bne @no_carry
        inc rounds+1
@no_carry:
        lda rounds
        and #$0f                        ; the LCD is slow, so not every round
        bne @round
        jsr report
        bra @round

;------------------------------------------------------------------------------
; report - the round counter and the two rows
;------------------------------------------------------------------------------
report:
        ldy #$00
        ldx #$00
        jsr lcd_set_position
        lda #<msg_n
        ldx #>msg_n
        jsr _lcd_print
        lda rounds+1
        jsr print_hex
        lda rounds
        jsr print_hex

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

        ldy #$03
        ldx #$00
        jsr lcd_set_position
        lda #<msg_lo
        ldx #>msg_lo
        jmp _lcd_print

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
        jsr print_count
        plx
        inx
        phx
        txa
        and #$0f
        bne @cell
        plx
        rts

;------------------------------------------------------------------------------
; print_count - one counter as one character: a dot for none, a hex digit up to
; fifteen, a star for sixteen or more. X and Y are destroyed.
;------------------------------------------------------------------------------
print_count:
        cmp #$00
        bne @some
        lda #'.'
        jmp _lcd_print_char
@some:
        cmp #16
        bcc @digit
        lda #'*'
        jmp _lcd_print_char
@digit:
        cmp #10
        bcs @letter
        clc
        adc #'0'
        jmp _lcd_print_char
@letter:
        clc
        adc #('A'-10)
        jmp _lcd_print_char

;------------------------------------------------------------------------------
; print_hex - A as two hex digits on the LCD. X and Y are destroyed.
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

msg_n:    .byte "N=", $00
msg_lo:   .byte "LO 40-B8 ST 8", $00

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

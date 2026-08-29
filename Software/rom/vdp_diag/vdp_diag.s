;------------------------------------------------------------------------------
;
; vdp_diag - what does the VDP actually do at a cold start?
;
; The BASIC ROM comes up with a font that is wrong in VRAM while the same font
; in ROM is provably intact, and the read-back check added on 24.08.2026 does
; not make it come out right either. Every explanation left standing needs a
; measurement that this board cannot give through its own screen, because the
; screen is the broken part. So the report goes to the LCD.
;
; What it does, once, in the order the cold start does it:
;
;   PRB  the two bytes read back from $3FFE/$3FFF after writing $5A/$A5 there.
;        $5A $A5 means VRAM takes a byte, gives it back, and auto-increments.
;        Anything else means the read path or the write path is not working
;        and every other line below is worthless.
;   ST   the status register a frame time after the display was enabled.
;        Bit 7 set ($80 or higher) means the chip is putting out frames.
;   PAT  the first five bytes read back from the pattern table at $0800.
;        The font starts $00 $00 $00 $FF $FF.
;   M1   index of the first byte of the pattern table that does not match the
;        ROM, on the cold copy. $FFFF means all 1024 matched.
;   G/W  the byte read there and the byte that belongs there.
;   M2   the same index for a second copy, run after the chip has been up for
;        a while. $FFFF here with M1 not $FFFF means the fault is the cold
;        start alone; the same value twice means it is systematic.
;   SH   the offset into the ROM font at which the eight bytes read from the
;        start of the pattern table appear. $0000 means the copy landed where
;        it was sent. Anything else is the shift, in bytes. $FFFF means those
;        eight bytes are not in the font at all.
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

PATTERN_HI    = $08                     ; pattern table at $0800
PROBE_LO      = $FE                     ; probe address $3FFE
PROBE_HI      = $3F
PROBE_V1      = $5A
PROBE_V2      = $A5
LINE_FEED     = $0A

        .segment "VECTORS"

        .word   $0000
        .word   init
        .word   $0000

        .segment "BSS"

diag_prb:       .res 2
diag_status:    .res 1
diag_head:      .res 8
diag_mis:       .res 2
diag_mis2:      .res 2
diag_got:       .res 1
diag_want:      .res 1
diag_shift:     .res 2
diag_txt:       .res 2
diag_scr:       .res 2
diag_lines:     .res 1
diag_enb:       .res 2
diag_step:      .res 1

        .code

init:
        cld
        jsr _blink_init
        jsr _lcd_init
        jsr _lcd_clear

        ; A trail on the top line, one letter per step as it completes. The
        ; report clears the display before printing, so on a good run none of
        ; this survives - it is here for the run that never reaches the report.
        stz diag_step
        lda #'.'
        jsr step_mark

;--- the cold start, step by step -------------------------------------------

        lda VDP_REG                     ; clears the control port flip-flop
        jsr vdp_boot_registers
        lda #'R'
        jsr step_mark

        jsr probe                       ; -> diag_prb
        lda #'P'
        jsr step_mark

        jsr vdp_boot_patterns
        lda #'F'
        jsr step_mark

        ; the first eight bytes as they actually sit in VRAM
        jsr read_pattern_start
        ldx #$00
@head:
        lda VDP_VRAM
        sta diag_head,x
        jsr vdp_wait
        inx
        cpx #$08
        bne @head

        ; where does the copy first disagree with the ROM?
        jsr compare_patterns
        lda diag_mis
        sta diag_mis2
        lda diag_mis+1
        sta diag_mis2+1
        lda #'1'
        jsr step_mark

;--- and now with a chip that has been up for a while ------------------------

        jsr vdp_boot_clear
        lda #'C'
        jsr step_mark
        jsr vdp_boot_enable
        lda #'E'
        jsr step_mark

        lda #30                         ; longer than one frame at 50 Hz
        jsr _delay_ms
        lda VDP_REG
        sta diag_status

        ; still intact after the name table was cleared and the screen came on?
        jsr compare_patterns
        lda diag_mis
        sta diag_enb
        lda diag_mis+1
        sta diag_enb+1

        lda #'2'
        jsr step_mark

;--- is what landed in VRAM the font, just from the wrong place? -------------

        jsr find_shift
        lda #'S'
        jsr step_mark

;--- and now the part the cold start never exercises: printing ---------------
;
; The BASIC ROM comes up with a font that vdp_diag says was written correctly,
; so whatever destroys it happens later, and the only thing that runs later is
; text output. Twenty lines fit on the screen without scrolling; forty more
; force vdp_scroll_line, which reads and writes VRAM in bulk through a
; different pair of routines. Both are checked separately.
;
        stz vdp_line
        stz vdp_char_pos

        lda #20
        sta diag_lines
@fill:
        lda #<msg_line
        ldx #>msg_line
        jsr vdp_write_string
        lda #LINE_FEED
        jsr vdp_write_char
        dec diag_lines
        bne @fill

        jsr compare_patterns
        lda diag_mis
        sta diag_txt
        lda diag_mis+1
        sta diag_txt+1

        lda #40                         ; past the bottom, so it scrolls
        sta diag_lines
@scroll:
        lda #<msg_line
        ldx #>msg_line
        jsr vdp_write_string
        lda #LINE_FEED
        jsr vdp_write_char
        dec diag_lines
        bne @scroll

        jsr compare_patterns
        lda diag_mis
        sta diag_scr
        lda diag_mis+1
        sta diag_scr+1

;--- report ------------------------------------------------------------------

        jsr _lcd_clear

        ldy #$00
        ldx #$00
        jsr lcd_set_position
        lda #<msg_prb
        ldx #>msg_prb
        jsr _lcd_print
        lda diag_prb
        jsr print_hex
        lda #' '
        jsr _lcd_print_char
        lda diag_prb+1
        jsr print_hex
        lda #<msg_st
        ldx #>msg_st
        jsr _lcd_print
        lda diag_status
        jsr print_hex

        ldy #$01
        ldx #$00
        jsr lcd_set_position
        lda #<msg_m1
        ldx #>msg_m1
        jsr _lcd_print
        lda diag_mis2+1
        jsr print_hex
        lda diag_mis2
        jsr print_hex
        lda #<msg_enb
        ldx #>msg_enb
        jsr _lcd_print
        lda diag_enb+1
        jsr print_hex
        lda diag_enb
        jsr print_hex

        ldy #$02
        ldx #$00
        jsr lcd_set_position
        lda #<msg_txt
        ldx #>msg_txt
        jsr _lcd_print
        lda diag_txt+1
        jsr print_hex
        lda diag_txt
        jsr print_hex
        lda #<msg_sh
        ldx #>msg_sh
        jsr _lcd_print
        lda diag_shift+1
        jsr print_hex
        lda diag_shift
        jsr print_hex

        ldy #$03
        ldx #$00
        jsr lcd_set_position
        lda #<msg_scr
        ldx #>msg_scr
        jsr _lcd_print
        lda diag_scr+1
        jsr print_hex
        lda diag_scr
        jsr print_hex

        lda #(BLINK_LED_OFF)
        jsr _blink_led
@halt:
        bra @halt

;------------------------------------------------------------------------------
; probe - write two different bytes to the top of VRAM and read them back
;------------------------------------------------------------------------------
probe:
        ldy #PROBE_LO
        lda #PROBE_HI | VDP_WRITE_VRAM_SELECT
        jsr vdp_write_address
        lda #PROBE_V1
        sta VDP_VRAM
        jsr vdp_wait
        lda #PROBE_V2
        sta VDP_VRAM                    ; auto-incremented to the next address
        jsr vdp_wait

        ldy #PROBE_LO
        lda #PROBE_HI | VDP_READ_VRAM_SELECT
        jsr vdp_write_address
        lda VDP_VRAM
        sta diag_prb
        jsr vdp_wait
        lda VDP_VRAM
        sta diag_prb+1
        rts

;------------------------------------------------------------------------------
; read_pattern_start - point the VDP at $0800 for reading
;------------------------------------------------------------------------------
read_pattern_start:
        ldy #$00
        lda #PATTERN_HI | VDP_READ_VRAM_SELECT
        jmp vdp_write_address

;------------------------------------------------------------------------------
; compare_patterns - first byte of the pattern table that is not the font
; diag_mis = index, $FFFF when every byte matched. diag_got / diag_want hold
; the pair at that index.
;------------------------------------------------------------------------------
compare_patterns:
        jsr read_pattern_start

        stz diag_mis
        stz diag_mis+1
        lda #<VDP_TEXT_PATTERNS_START
        sta vdp_vram_address
        lda #>VDP_TEXT_PATTERNS_START
        sta vdp_vram_address+1
@loop:
        lda VDP_VRAM
        sta diag_got
        cmp (vdp_vram_address)
        bne @found
        jsr vdp_wait

        inc diag_mis
        bne @src
        inc diag_mis+1
@src:
        inc vdp_vram_address
        bne @same
        inc vdp_vram_address+1
@same:
        lda vdp_vram_address+1
        cmp #>VDP_TEXT_PATTERNS_END
        bne @loop
        lda vdp_vram_address
        cmp #<VDP_TEXT_PATTERNS_END
        bne @loop

        lda #$ff                        ; nothing to report
        sta diag_mis
        sta diag_mis+1
        stz diag_got
        stz diag_want
        rts
@found:
        lda (vdp_vram_address)
        sta diag_want
        rts

;------------------------------------------------------------------------------
; find_shift - where in the ROM font do the eight bytes at the start of the
; pattern table come from? diag_shift = that offset, $FFFF when they are not
; in the font at all.
;------------------------------------------------------------------------------
find_shift:
        stz diag_shift
        stz diag_shift+1
        lda #<VDP_TEXT_PATTERNS_START
        sta vdp_vram_address
        lda #>VDP_TEXT_PATTERNS_START
        sta vdp_vram_address+1
@candidate:
        ldy #$00
@byte:
        lda (vdp_vram_address),y
        cmp diag_head,y
        bne @next
        iny
        cpy #$08
        bne @byte
        rts                             ; diag_shift holds the offset
@next:
        inc diag_shift
        bne @src
        inc diag_shift+1
@src:
        inc vdp_vram_address
        bne @same
        inc vdp_vram_address+1
@same:
        lda vdp_vram_address+1
        cmp #>VDP_TEXT_PATTERNS_END
        bne @candidate
        lda vdp_vram_address
        cmp #<VDP_TEXT_PATTERNS_END
        bne @candidate

        lda #$ff                        ; not the font at all
        sta diag_shift
        sta diag_shift+1
        rts

;------------------------------------------------------------------------------
; step_mark - put A on the top line at the next free column. Every register is
; kept, because this sits between the steps of a measurement.
;------------------------------------------------------------------------------
step_mark:
        pha
        phx
        phy
        pha
        ldx diag_step
        ldy #$00
        jsr lcd_set_position
        pla
        jsr _lcd_print_char
        inc diag_step
        ply
        plx
        pla
        rts

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

msg_prb:  .byte "PRB ", $00
msg_st:   .byte "  ST ", $00
msg_pat:  .byte "PAT ", $00
msg_m1:   .byte "M1 ", $00
msg_m2:   .byte "M2 ", $00
msg_g:    .byte " G", $00
msg_w:    .byte " W", $00
msg_sh:   .byte "  SH ", $00
msg_enb:  .byte " ENB ", $00
msg_txt:  .byte "TXT ", $00
msg_scr:  .byte "SCR ", $00
msg_line: .byte "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+-*", $00

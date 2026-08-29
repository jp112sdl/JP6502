;------------------------------------------------------------------------------
;
; vdp_sweep - every low byte, one at a time, out of RAM
;
; Where this stands. With a vertical retrace before every probe, so that a
; probe's position in the round can no longer decide its phase, rom/vdp_lobyte2
; converged over 141 rounds and both of its rows agree:
;
;   ..**.1.1****.1..     set A, low bytes $40 $48 $50 ... $B8
;   ..**....****.1..     set B, same low bytes, different pages
;
; Failing: $50, $58, $80, $88, $90, $98. Passing: everything else, with at most
; one failure in 141. The pages are innocent - two different pages give the same
; answer - so the low byte decides, and it decides reliably.
;
; But it is not a bit pattern. No single address bit and no pair of bits, at any
; offset into the probe, separates the failing low bytes from the passing ones,
; and neither does the number of address lines that switch. What the map looks
; like is two bands, roughly $50-$5F and $80-$9F, and sampling every eight bytes
; cannot say where their edges are.
;
; So: every low byte, not every eighth. That needs a probe that can be moved,
; which this one can - it contains no call to itself, only absolute references
; to the VDP ports and to two zero page bytes, so it runs correctly wherever it
; is put. It is copied to $2000+LO and called there, for LO from $40 to $FF.
;
; Running it from RAM asks a second question for free. If the same low bytes
; fail out of RAM as failed out of ROM, then this is the address bus and not
; the ROM. If RAM is clean everywhere, it is something about the ROM's own
; timing, and that is a different search.
;
; Each probe still waits for a vertical retrace first, so all of them meet the
; chip at the same point in the frame. A round is therefore about four seconds.
; Give it a minute.
;
; The display is the map itself, four low bytes to a character:
;
;   N=000C 40-FF
;   ....****........     $40-$7F
;   ****............     $80-$BF
;   ................     $C0-$FF
;
; A dot is four low bytes that pass, a star is four that fail, a plus is a
; character with the edge of a band inside it - which is the thing worth
; finding.
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

PROBE_RAM     = $2000                   ; the probe is copied to PROBE_RAM+LO
COUNTS        = $3000                   ; one failure counter per low byte
PROBE_LEN     = probe_template_end - probe_template
FIRST_LO      = $40

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
copy_src:       .res 2
copy_dst:       .res 2

        .segment "BSS"

lo_byte:        .res 1
rounds:         .res 2

        .code

init:
        cld
        jsr _blink_init
        jsr _lcd_init
        jsr _lcd_clear

        lda VDP_REG
        jsr vdp_boot_registers
        jsr vdp_boot_patterns
        jsr vdp_boot_clear
        jsr vdp_boot_enable

        ; clear the counters
        lda #<COUNTS
        sta copy_dst
        lda #>COUNTS
        sta copy_dst+1
        ldy #$00
@clear:
        lda #$00
        sta (copy_dst),y
        iny
        bne @clear
        stz rounds
        stz rounds+1

;--- round after round -------------------------------------------------------

@round:
        lda #FIRST_LO
        sta lo_byte
@sweep:
        jsr place_probe
        jsr wait_frame
        stz probe_r0
        stz probe_r1
        jsr call_probe

        lda probe_r0
        cmp #PROBE_V1
        bne @bad
        lda probe_r1
        cmp #PROBE_V2
        beq @good
@bad:
        ldx lo_byte
        lda COUNTS,x
        cmp #$FF
        beq @good
        inc COUNTS,x
@good:
        inc lo_byte
        bne @sweep                      ; stops after $FF

        inc rounds
        bne @no_carry
        inc rounds+1
@no_carry:
        jsr report
        bra @round

;------------------------------------------------------------------------------
; place_probe - copy the template to PROBE_RAM + lo_byte
;------------------------------------------------------------------------------
place_probe:
        lda #<probe_template
        sta copy_src
        lda #>probe_template
        sta copy_src+1
        lda #<PROBE_RAM
        clc
        adc lo_byte
        sta copy_dst
        sta call_target
        lda #>PROBE_RAM
        adc #$00
        sta copy_dst+1
        sta call_target+1
        ldy #$00
@copy:
        lda (copy_src),y
        sta (copy_dst),y
        iny
        cpy #PROBE_LEN
        bne @copy
        rts

call_probe:
        jmp (call_target)

;------------------------------------------------------------------------------
; wait_frame - return just after a vertical retrace, so that every probe meets
; the chip at the same point in the frame. Reading the status register clears
; the flag and the control port flip-flop with it. The poll is padded, because
; a tight read loop would hit the chip more often than eight microseconds.
;------------------------------------------------------------------------------
wait_frame:
        lda VDP_REG
@poll:
        nop
        nop
        nop
        nop
        lda VDP_REG
        bpl @poll
        rts

;------------------------------------------------------------------------------
; report - the round counter and the map, four low bytes to a character
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
        lda #<msg_range
        ldx #>msg_range
        jsr _lcd_print

        lda #$40
        ldy #$01
        jsr print_map_line
        lda #$80
        ldy #$02
        jsr print_map_line
        lda #$C0
        ldy #$03
        jsr print_map_line
        rts

;------------------------------------------------------------------------------
; print_map_line - sixteen characters, four low bytes each, starting at A on
; LCD line Y
;------------------------------------------------------------------------------
print_map_line:
        sta map_lo
        sty map_line
        ldy map_line
        ldx #$00
        jsr lcd_set_position
@cell:
        ldx map_lo
        lda #$00
        sta map_bad
        ldy #$04
@four:
        lda COUNTS,x
        beq @next_byte
        inc map_bad
@next_byte:
        inx
        dey
        bne @four
        stx map_lo

        lda map_bad
        beq @none
        cmp #$04
        beq @all
        lda #'+'
        bra @put
@none:
        lda #'.'
        bra @put
@all:
        lda #'*'
@put:
        jsr _lcd_print_char
        lda map_lo
        and #$3f
        bne @cell
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

        .segment "BSS"

map_lo:         .res 1
map_line:       .res 1
map_bad:        .res 1

        .segment "RODATA"

msg_n:    .byte "N=", $00
msg_range:.byte " 40-FF", $00

;------------------------------------------------------------------------------
;
; The probe template. Nothing in it refers to itself, so it runs correctly
; wherever it is copied. The pacing is four nops between two accesses, which
; leaves fourteen cycles - comfortably more than the eight the chip asks for,
; because this is not a test of the pacing.
;
;------------------------------------------------------------------------------

probe_template:
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
probe_template_end:

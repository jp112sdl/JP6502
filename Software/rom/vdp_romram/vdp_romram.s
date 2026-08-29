;------------------------------------------------------------------------------
;
; vdp_romram - the same probe in ROM and in RAM, at the same low bytes
;
; rom/vdp_sweep copied a relocatable probe to $2000+LO and ran it for every LO
; from $40 to $FF. After 21 rounds - N=0015 - not one low byte had failed. Out
; of ROM, $50, $58, $80, $88, $90 and $98 fail every time.
;
; That looks like ROM against RAM, but it cannot be read that way yet, because
; two things changed between the two ROMs and both changes are mine. The sweep
; runs out of RAM, and it also uses a different probe: straight-line code with
; nops for pacing, where rom/vdp_lobyte2 called two subroutines inside itself.
; Either difference could be what matters.
;
; So this burn changes one thing only. The relocatable probe - the sweep's
; probe, the straight-line one - is used for both. Six copies of it sit in ROM
; at low bytes $50, $80, $90 and $98, which fail, and $40 and $60, which pass.
; The same six low bytes are also driven from RAM, from a copy at $2000+LO.
; Same instructions, same pacing, same order, same frame synchronisation; the
; only difference between the two rows is which part the bytes are fetched
; from.
;
;   ROM fails, RAM clean  -> it is the memory part or its timing, not the
;                            address bus. The bus carries the same addresses in
;                            both rows.
;   both clean            -> the straight-line probe is simply not enough to
;                            provoke it, and what matters is the jsr and rts
;                            that rom/vdp_lobyte2 had.
;   both fail             -> the address bus after all, and the sweep's silence
;                            needs another explanation.
;
; The display, with a dot for never failed, a hex digit for that many failures
; and a star for sixteen or more:
;
;   N=0020
;   R ****..
;   M ......
;   90 EF CB 40 5A A5
;
; The last line is what actually came back, from one ROM copy that fails and
; one that does not, in the order $50 $80 $90 $98 $40 $60 for the columns above
; it. $5A $A5 is what was written. Anything else says how it went wrong - two
; swapped bytes are a slipped flip-flop, a bit or two out is the data bus, and
; arbitrary rubbish is a read from somewhere else in VRAM entirely.
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

PROBE_RAM     = $2000
PROBE_LEN     = probe_template_end - probe_template

; $3FF0-$3FFF, clear of every table. Each byte is written with its own low
; address, so what comes back says where the read pointer actually stood.
PROBE_LO      = $F0
PROBE_HI      = $3F

        .segment "VECTORS"

        .word   $0000
        .word   init
        .word   $0000

        .zeropage

probe_r0:       .res 1
probe_r1:       .res 1
probe_r2:       .res 1
probe_r3:       .res 1
call_target:    .res 2
copy_src:       .res 2
copy_dst:       .res 2

        .segment "BSS"

result:         .res 12                 ; six in ROM, then the same six in RAM
rounds:         .res 2
slot:           .res 1
six_idx:        .res 1
six_left:       .res 1
bad_lo:         .res 1
bad_bytes:      .res 4
good_bytes:     .res 4

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

        ldx #11
@clear:
        stz result,x
        dex
        bpl @clear
        stz rounds
        stz rounds+1

@round:
        ldx #$00
@next:
        stx slot
        cpx #$06
        bcs @from_ram

        ; --- out of ROM: the copy that was linked at this low byte ----------
        txa
        asl a
        tax
        lda rom_probe,x
        sta call_target
        lda rom_probe+1,x
        sta call_target+1
        bra @go

        ; --- out of RAM: copy the template to $2000 + the same low byte -----
@from_ram:
        txa
        sec
        sbc #$06
        tax
        lda probe_low,x
        jsr place_probe

@go:
        stz probe_r0
        stz probe_r1
        jsr wait_frame
        jsr call_probe

        ldx slot
        cpx #$04                        ; ROM $40, which has always passed
        bne @not_good_slot
        jsr keep_good
@not_good_slot:
        lda probe_r0
        cmp #(PROBE_LO+0)
        bne @bad
        lda probe_r1
        cmp #(PROBE_LO+1)
        bne @bad
        lda probe_r2
        cmp #(PROBE_LO+2)
        bne @bad
        lda probe_r3
        cmp #(PROBE_LO+3)
        beq @good
@bad:
        cpx #$06                        ; only ROM slots are worth showing
        bcs @count
        lda bad_lo
        bne @count                      ; the first one this round is enough
        jsr keep_bad
@count:
        lda result,x
        cmp #$FF
        beq @good
        inc result,x
@good:
        inx
        cpx #12
        bne @next

        stz bad_lo                      ; a fresh look next round
        inc rounds
        bne @no_carry
        inc rounds+1
@no_carry:
        jsr report
        bra @round

;------------------------------------------------------------------------------
; keep_bad / keep_good - remember what a copy read back, so that the report can
; show the bytes and not only a verdict. X is the slot and is preserved.
;------------------------------------------------------------------------------
keep_bad:
        lda probe_low,x
        sta bad_lo
        lda probe_r0
        sta bad_bytes
        lda probe_r1
        sta bad_bytes+1
        lda probe_r2
        sta bad_bytes+2
        lda probe_r3
        sta bad_bytes+3
        rts

keep_good:
        lda probe_r0
        sta good_bytes
        lda probe_r1
        sta good_bytes+1
        lda probe_r2
        sta good_bytes+2
        lda probe_r3
        sta good_bytes+3
        rts

;------------------------------------------------------------------------------
; place_probe - copy the template to PROBE_RAM + A, and aim call_target at it
;------------------------------------------------------------------------------
place_probe:
        clc
        adc #<PROBE_RAM
        sta copy_dst
        sta call_target
        lda #>PROBE_RAM
        adc #$00
        sta copy_dst+1
        sta call_target+1
        lda #<probe_template
        sta copy_src
        lda #>probe_template
        sta copy_src+1
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
; wait_frame - return just after a vertical retrace, so that a probe's position
; in the round cannot decide its phase. Reading the status register clears the
; flag and the control port flip-flop with it, and the poll is padded so that
; it does not hit the chip faster than eight microseconds.
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
; report
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
        lda #<msg_rom
        ldx #>msg_rom
        jsr _lcd_print
        ldx #$00
        jsr print_six

        lda #' '
        jsr _lcd_print_char
        lda #<msg_ram
        ldx #>msg_ram
        jsr _lcd_print
        ldx #$06
        jsr print_six

        ldy #$02
        ldx #$00
        jsr lcd_set_position
        lda #<msg_bad
        ldx #>msg_bad
        jsr _lcd_print
        lda bad_lo
        jsr print_hex
        lda #' '
        jsr _lcd_print_char
        ldx #$00
@bad_row:
        phx
        lda bad_bytes,x
        jsr print_hex
        plx
        inx
        cpx #$04
        bne @bad_row

        ldy #$03
        ldx #$00
        jsr lcd_set_position
        lda #<msg_good
        ldx #>msg_good
        jsr _lcd_print
        ldx #$00
@good_row:
        phx
        lda good_bytes,x
        jsr print_hex
        plx
        inx
        cpx #$04
        bne @good_row
        rts

print_six:
        stx six_idx
        lda #$06
        sta six_left
@cell:
        ldx six_idx
        lda result,x
        jsr print_count                 ; destroys X, so the index lives in RAM
        inc six_idx
        dec six_left
        bne @cell
        rts

;------------------------------------------------------------------------------
; print_count - a dot for none, a hex digit up to fifteen, a star beyond
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

msg_n:    .byte "N=", $00
msg_rom:  .byte "R ", $00
msg_ram:  .byte "M ", $00
msg_bad:  .byte "B ", $00
msg_good: .byte "G 40 ", $00

rom_probe:
        .word   romp_0, romp_1, romp_2, romp_3, romp_4, romp_5
probe_low:
        .byte   $50, $80, $90, $98, $40, $60

;------------------------------------------------------------------------------
;
; The probe. Nothing in it refers to itself, so the very same bytes run
; correctly whether they are linked into ROM or copied into RAM. Four nops
; between accesses leave fourteen cycles, comfortably more than the eight the
; chip asks for - this is not a test of the pacing.
;
;------------------------------------------------------------------------------

.macro  vdp_romram_probe
        ; point the chip at $3FF0 for writing
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

        ; sixteen bytes, each one equal to the address it belongs at
        ldx #PROBE_LO
@fill:
        txa
        sta VDP_VRAM
        nop
        nop
        nop
        nop
        inx
        bne @fill

        ; and back from $3FF0
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
        nop
        nop
        nop
        nop
        lda VDP_VRAM
        sta probe_r2
        nop
        nop
        nop
        nop
        lda VDP_VRAM
        sta probe_r3
        rts
.endmacro

        .segment "RODATA"
probe_template:
        vdp_romram_probe
probe_template_end:

        .segment "ROMP_0"
romp_0: vdp_romram_probe
        .segment "ROMP_1"
romp_1: vdp_romram_probe
        .segment "ROMP_2"
romp_2: vdp_romram_probe
        .segment "ROMP_3"
romp_3: vdp_romram_probe
        .segment "ROMP_4"
romp_4: vdp_romram_probe
        .segment "ROMP_5"
romp_5: vdp_romram_probe

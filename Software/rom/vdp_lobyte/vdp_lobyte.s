;------------------------------------------------------------------------------
;
; vdp_lobyte - which low address bytes can drive the VDP control port?
;
; The picture so far. The 231 bytes of VDP routines have been burnt at five
; addresses, and what decides is the low byte and nothing else: $5D and $60
; work, $B7 fails, in whichever page. The ROM has been cleared as a cause -
; rom_check read every one of those addresses back correctly and rom_exec
; executed at all of them through two hundred thousand fetches without a slip.
; And vdp_diag, built with its own VDP routines at $E3B7, reproduces the whole
; failure away from BASIC:
;
;   PRB EF CB   the two bytes written to $3FFE come back as rubbish
;   ST  DA      bit 7 set, so the chip is clocked and producing frames
;   M1  0000    the font copy is wrong from its very first byte
;   SH  FFFF    and what is in VRAM is not the font shifted, it is not the font
;
; So the chip is alive and the very first address written to it does not take.
; That is the control port at $8081 and its write flip-flop, which is the one
; part of this board that has been the suspect from the beginning.
;
; This ROM maps the parameter in a single burn. The same self-contained probe
; is linked sixteen times, at low bytes $00 through $F0, each in a page of its
; own. Each copy carries its own address-write and its own wait, so every byte
; fetched while the control port is being driven comes from that copy and
; carries that low byte.
;
; A probe writes $5A and $A5 to $3FFE, reads them back, and passes only if both
; come back. The VDP is brought up first through the ROM's ordinary routines,
; so every probe meets a chip that is already running.
;
; The report is the sixteen low bytes with a + or a -:
;
;   00+ 10+ 20+ 30+
;   40+ 50+ 60+ 70+
;   80+ 90+ A0+ B0-
;   C0+ D0+ E0+ F0+
;
; All + means the low byte alone does not decide it after all and the failing
; ingredient is something these probes still do not do. A pattern of minus
; signs is the map of the fault, and where its edges fall says what it is:
; a single value is one bit of one line, a contiguous range is a timing
; threshold, every other one is a single address line.
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

result:         .res 16

        .code

init:
        cld
        jsr _blink_init
        jsr _lcd_init
        jsr _lcd_clear

        ; bring the chip up through the ordinary routines, so that every probe
        ; meets a VDP that is already running
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

        stz probe_r0
        stz probe_r1
        phx
        jsr call_probe
        plx

        lda #'-'
        ldy probe_r0
        cpy #PROBE_V1
        bne @store
        ldy probe_r1
        cpy #PROBE_V2
        bne @store
        lda #'+'
@store:
        sta result,x
        inx
        cpx #16
        bne @next

;--- report ------------------------------------------------------------------

        jsr _lcd_clear
        ldx #$00
@row:
        phx
        txa
        lsr a
        lsr a
        tay                             ; Y = line number
        ldx #$00
        jsr lcd_set_position
        plx
        phx
@cell:
        phx
        txa
        asl a
        asl a
        asl a
        asl a
        jsr print_hex_low               ; the low byte this probe sits on
        plx
        lda result,x
        jsr _lcd_print_char
        lda #' '
        jsr _lcd_print_char
        inx
        txa
        and #$03
        bne @cell
        plx
        txa
        clc
        adc #$04
        tax
        cpx #16
        bne @row

        lda #(BLINK_LED_OFF)
        jsr _blink_led
@halt:
        bra @halt

call_probe:
        jmp (call_target)

;------------------------------------------------------------------------------
; print_hex_low - A as two hex digits. X and Y are destroyed.
;------------------------------------------------------------------------------
print_hex_low:
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

probe_addr:
        .word   probe_00, probe_01, probe_02, probe_03
        .word   probe_04, probe_05, probe_06, probe_07
        .word   probe_08, probe_09, probe_0A, probe_0B
        .word   probe_0C, probe_0D, probe_0E, probe_0F

;------------------------------------------------------------------------------
;
; The probe. Self-contained on purpose: the address write, the wait and the
; data accesses are all inside it, so every byte fetched between two control
; port accesses carries this copy's low address byte.
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

        .segment "PROBE_00"
probe_00:
        vdp_lobyte_probe

        .segment "PROBE_01"
probe_01:
        vdp_lobyte_probe

        .segment "PROBE_02"
probe_02:
        vdp_lobyte_probe

        .segment "PROBE_03"
probe_03:
        vdp_lobyte_probe

        .segment "PROBE_04"
probe_04:
        vdp_lobyte_probe

        .segment "PROBE_05"
probe_05:
        vdp_lobyte_probe

        .segment "PROBE_06"
probe_06:
        vdp_lobyte_probe

        .segment "PROBE_07"
probe_07:
        vdp_lobyte_probe

        .segment "PROBE_08"
probe_08:
        vdp_lobyte_probe

        .segment "PROBE_09"
probe_09:
        vdp_lobyte_probe

        .segment "PROBE_0A"
probe_0A:
        vdp_lobyte_probe

        .segment "PROBE_0B"
probe_0B:
        vdp_lobyte_probe

        .segment "PROBE_0C"
probe_0C:
        vdp_lobyte_probe

        .segment "PROBE_0D"
probe_0D:
        vdp_lobyte_probe

        .segment "PROBE_0E"
probe_0E:
        vdp_lobyte_probe

        .segment "PROBE_0F"
probe_0F:
        vdp_lobyte_probe

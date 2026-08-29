;------------------------------------------------------------------------------
;
; rom_exec - does the board execute correctly at the addresses that fail?
;
; rom_check reads 64 bytes back from each suspect address and counts what does
; not match. That is a sedate loop: (zp),y walking forwards, one byte per five
; cycles, the address bus changing in the simplest pattern there is. A marginal
; low-order address line can sail through that and still fail a running program,
; where the bus changes every single cycle and the patterns are arbitrary.
;
; So this ROM stops reading and starts executing. The same 21-byte routine is
; linked at the five addresses the VDP routines have been burnt at:
;
;   $F05D  low byte $5D  worked
;   $E360  low byte $60  worked
;   $E3B7  low byte $B7  black screen
;   $E45D  low byte $5D  worked
;   $FEB7  low byte $B7  garbled
;
; The routine uses nothing but immediates and a relative branch, so all five
; copies are byte for byte identical and must produce byte for byte identical
; results. It runs 256 iterations of a short arithmetic chain, which is some
; three thousand instruction fetches per call, and it is called 64 times per
; address.
;
; Two numbers come out of that, and they catch different faults:
;
;   R  the result of the last call, one byte per address. All five have to be
;      the same value. One that differs is an address at which the CPU does not
;      execute what was burnt - a fault that is there every time.
;   I  the 64 results XORed together. Sixty-four is even, so a routine that
;      returns the same value every time gives $00 whatever that value is.
;      Anything else means the address is unreliable rather than wrong - it
;      returned different things on different calls.
;
; R all equal and I all $00 means the board fetches and executes correctly at
; every one of these addresses under this load, and the fault is not in getting
; the bytes out of the ROM.
;
; The report goes to the LCD, in the order $F05D $E360 $E3B7 $E45D $FEB7.
;
;------------------------------------------------------------------------------

        .setcpu "65C02"

        .include "lcd.inc"
        .include "utils.inc"
        .include "blink.inc"
        .include "zeropage.inc"

CALLS_PER_PROBE = 64                    ; even, so a stable result XORs to zero

        .segment "VECTORS"

        .word   $0000
        .word   init
        .word   $0000

        .zeropage

exec_ptr:       .res 2

        .segment "BSS"

last_result:    .res 5
instability:    .res 5

        .code

init:
        cld
        jsr _blink_init
        jsr _lcd_init
        jsr _lcd_clear

        ldx #$00
@next:
        phx
        jsr run_probe
        plx
        inx
        cpx #$05
        bne @next

;--- report ------------------------------------------------------------------

        jsr _lcd_clear

        ldy #$00
        ldx #$00
        jsr lcd_set_position
        lda #<msg_r
        ldx #>msg_r
        jsr _lcd_print
        ldx #$00
@row_r:
        phx
        lda last_result,x
        jsr print_hex
        plx
        inx
        cpx #$05
        bne @row_r

        ldy #$01
        ldx #$00
        jsr lcd_set_position
        lda #<msg_i
        ldx #>msg_i
        jsr _lcd_print
        ldx #$00
@row_i:
        phx
        lda instability,x
        jsr print_hex
        plx
        inx
        cpx #$05
        bne @row_i

        lda #(BLINK_LED_OFF)
        jsr _blink_led
@halt:
        bra @halt

;------------------------------------------------------------------------------
; run_probe - call probe X sixty-four times. Keeps the last result and the XOR
; of all of them.
;------------------------------------------------------------------------------
run_probe:
        phx
        txa
        asl a
        tax
        lda probe_addr,x
        sta exec_ptr
        lda probe_addr+1,x
        sta exec_ptr+1
        plx

        stz xor_acc
        ldy #CALLS_PER_PROBE
@call:
        phy
        phx
        jsr call_probe                  ; -> A
        plx
        ply
        sta last_call
        eor xor_acc
        sta xor_acc
        dey
        bne @call

        lda last_call
        sta last_result,x
        lda xor_acc
        sta instability,x
        rts

call_probe:
        jmp (exec_ptr)

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

xor_acc:        .res 1
last_call:      .res 1

        .segment "RODATA"

msg_r:    .byte "R ", $00
msg_i:    .byte "I ", $00

probe_addr:
        .word   probe_f05d, probe_e360, probe_e3b7, probe_e45d, probe_feb7

;------------------------------------------------------------------------------
;
; The probe. Immediates and one relative branch only, so every copy is the same
; 21 bytes and every copy must return the same value.
;
;------------------------------------------------------------------------------

.macro  rom_exec_probe
        lda #$00
        ldx #$00
@loop:
        clc
        adc #$5B
        eor #$3C
        asl a
        adc #$A7
        eor #$D2
        rol a
        adc #$1F
        inx
        bne @loop
        rts
.endmacro

        .segment "PAT_F05D"
probe_f05d:
        rom_exec_probe

        .segment "PAT_E360"
probe_e360:
        rom_exec_probe

        .segment "PAT_E3B7"
probe_e3b7:
        rom_exec_probe

        .segment "PAT_E45D"
probe_e45d:
        rom_exec_probe

        .segment "PAT_FEB7"
probe_feb7:
        rom_exec_probe

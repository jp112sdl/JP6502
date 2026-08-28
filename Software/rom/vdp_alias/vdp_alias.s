;------------------------------------------------------------------------------
;
; vdp_alias - does the address a store is fetched from change what the VDP sees?
;
; Six burns of the BASIC ROM have established that moving the VDP routines to
; some addresses wrecks the display and to others does not, and that cycle
; counts do not explain it - see MEMORY_MAP.md 5.5. A static decoding fault is
; ruled out too: the working layout $F05D-$F143 and the failing one
; $F076-$F15C share 206 of their 231 bytes, so it cannot be that those
; addresses are poisoned.
;
; What is left is a decoder that reacts to the address bus without being
; properly qualified by the clock. The 6502 drives the next opcode fetch onto
; the bus in the cycle after a store, and if the select for $8080 is produced
; by gates alone, that transition can put a short spurious pulse on it. Whether
; it does depends on the bit pattern of the address being fetched - which is to
; say, on where the code sits.
;
; That is measurable without a scope. Write 256 known bytes to VRAM from a
; probe placed at a given ROM address, read them back, and count how many came
; back wrong. A phantom access advances the chip's VRAM pointer, so it shows up
; as everything after it being shifted.
;
; The same 14-byte probe is linked five times, at the five addresses the VDP
; routines have actually been burnt at:
;
;   $F05D  worked      the address in the running ROM
;   $F076  failed      the first burn that ever failed
;   $E360  worked
;   $E45D  worked
;   $FEB7  failed
;
; A count of 00 everywhere means the store's own address is not what the chip
; reacts to, and the fault is somewhere this test does not reach. Counts that
; line up with the burns - 00 for the three that worked and something else for
; the two that did not - means the mechanism is found.
;
; The report goes to the LCD, because the screen is the part under suspicion
; and cannot be its own instrument.
;
;   PRB     the two bytes read back from $3FFE/$3FFF after writing $5A/$A5.
;           $5A $A5 means the VRAM path works and the rest of the report is
;           worth reading. Anything else and it is not.
;   rows   the five probe addresses, each with its mismatch count.
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

SCRATCH_LO    = $00                     ; 256 bytes of VRAM nothing else uses
SCRATCH_HI    = $3E
PROBE_LO      = $FE                     ; $3FFE, for the sanity check
PROBE_HI      = $3F
PROBE_V1      = $5A
PROBE_V2      = $A5

        .segment "VECTORS"

        .word   $0000
        .word   init
        .word   $0000

        .segment "BSS"

diag_prb:       .res 2
diag_count:     .res 5                  ; one mismatch count per probe

        .code

init:
        cld
        jsr _blink_init
        jsr _lcd_init
        jsr _lcd_clear

        lda VDP_REG                     ; clears the control port flip-flop
        jsr vdp_boot_registers
        jsr vdp_boot_patterns
        jsr vdp_boot_clear
        jsr vdp_boot_enable             ; the display has to be on: the 8 us
                                        ; the chip asks for is about its own
                                        ; fetches during an active screen

        jsr sanity                      ; -> diag_prb

;--- the five probes ---------------------------------------------------------

        ldx #$00
@next:
        phx
        jsr set_scratch_write
        plx
        phx
        jsr call_probe
        plx
        phx
        jsr count_mismatches            ; -> A
        plx
        sta diag_count,x
        inx
        cpx #$05
        bne @next

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

        ldy #$01
        ldx #$00
        jsr lcd_set_position
        ldx #$00
        jsr print_result
        lda #' '
        jsr _lcd_print_char
        ldx #$01
        jsr print_result

        ldy #$02
        ldx #$00
        jsr lcd_set_position
        ldx #$02
        jsr print_result
        lda #' '
        jsr _lcd_print_char
        ldx #$03
        jsr print_result

        ldy #$03
        ldx #$00
        jsr lcd_set_position
        ldx #$04
        jsr print_result

        lda #(BLINK_LED_OFF)
        jsr _blink_led
@halt:
        bra @halt

;------------------------------------------------------------------------------
; print_result - probe X as "F05D 00". A, X and Y are destroyed.
;------------------------------------------------------------------------------
print_result:
        phx                             ; print_hex destroys X, so the index and
        txa                             ; the second half of the address both
        asl a                           ; have to wait on the stack
        tax
        lda probe_names,x
        pha
        lda probe_names+1,x
        jsr print_hex
        pla
        jsr print_hex
        lda #' '
        jsr _lcd_print_char
        plx
        lda diag_count,x
        jmp print_hex

;------------------------------------------------------------------------------
; call_probe - run probe X. It writes 256 bytes to wherever the VRAM write
; address currently points.
;------------------------------------------------------------------------------
call_probe:
        txa
        asl a
        tax
        lda probe_vectors,x
        sta call_target
        lda probe_vectors+1,x
        sta call_target+1
        jmp (call_target)

;------------------------------------------------------------------------------
; set_scratch_write / set_scratch_read - point the chip at the scratch page
;------------------------------------------------------------------------------
set_scratch_write:
        ldy #SCRATCH_LO
        lda #SCRATCH_HI | VDP_WRITE_VRAM_SELECT
        jmp vdp_write_address

set_scratch_read:
        ldy #SCRATCH_LO
        lda #SCRATCH_HI | VDP_READ_VRAM_SELECT
        jmp vdp_write_address

;------------------------------------------------------------------------------
; count_mismatches - read the scratch page back and count the bytes that are
; not what the probe wrote. Returns the count in A, capped at $FF.
;------------------------------------------------------------------------------
count_mismatches:
        jsr set_scratch_read
        stz mismatch_count
        ldx #$00
@loop:
        lda VDP_VRAM
        jsr vdp_wait
        stx compare_tmp
        cmp compare_tmp
        beq @same
        inc mismatch_count
        beq @full                       ; wrapped - leave it at $FF
@same:
        inx
        bne @loop
        lda mismatch_count
        rts
@full:
        dec mismatch_count
        lda mismatch_count
        rts

;------------------------------------------------------------------------------
; sanity - two different bytes to the top of VRAM and back, so that a dead
; VRAM path cannot masquerade as five clean probes
;------------------------------------------------------------------------------
sanity:
        ldy #PROBE_LO
        lda #PROBE_HI | VDP_WRITE_VRAM_SELECT
        jsr vdp_write_address
        lda #PROBE_V1
        sta VDP_VRAM
        jsr vdp_wait
        lda #PROBE_V2
        sta VDP_VRAM
        jsr vdp_wait

        ldy #PROBE_LO
        lda #PROBE_HI | VDP_READ_VRAM_SELECT
        jsr vdp_write_address
        lda VDP_VRAM
        sta diag_prb
        jsr vdp_wait
        lda VDP_VRAM
        sta diag_prb+1
        jmp vdp_wait

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

call_target:    .res 2
mismatch_count: .res 1
compare_tmp:    .res 1

        .segment "RODATA"

msg_prb:  .byte "PRB ", $00

probe_vectors:
        .word   probe_f05d, probe_f076, probe_e360, probe_e45d, probe_feb7
probe_names:
        .word   $F05D, $F076, $E360, $E45D, $FEB7

;------------------------------------------------------------------------------
;
; The probe itself, five times over. Deliberately self-contained: after the
; store, every byte the CPU fetches comes from inside the probe, so the only
; address under test is the probe's own.
;
; The four nops give the chip 19 cycles between two stores, which is more than
; twice what it asks for - this test is not about the eight microseconds.
;
;------------------------------------------------------------------------------

.macro  vdp_alias_probe
        ldx #$00
@loop:
        txa
        sta VDP_VRAM
        nop
        nop
        nop
        nop
        inx
        bne @loop
        rts
.endmacro

        .segment "PROBE_F05D"
probe_f05d:
        vdp_alias_probe

        .segment "PROBE_F076"
probe_f076:
        vdp_alias_probe

        .segment "PROBE_E360"
probe_e360:
        vdp_alias_probe

        .segment "PROBE_E45D"
probe_e45d:
        vdp_alias_probe

        .segment "PROBE_FEB7"
probe_feb7:
        vdp_alias_probe

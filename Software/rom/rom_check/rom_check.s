;------------------------------------------------------------------------------
;
; rom_check - does the board read back what was burnt into the ROM?
;
; Seven burns of the BASIC ROM have narrowed the fault that wrecks the display
; down to one parameter, and it is not the one anybody expected. The 231 bytes
; of VDP routines have been placed at five addresses:
;
;   $F05D  low byte $5D  worked
;   $E45D  low byte $5D  worked
;   $E360  low byte $60  worked
;   $E3B7  low byte $B7  black screen
;   $FEB7  low byte $B7  garbled
;
; Two completely different pages with the same low byte both fail; three
; different pages with other low bytes all work. Cycle counts are ruled out
; (MEMORY_MAP.md 5.5) and so is a spurious VDP select on the storing
; instruction's own address, which rom/vdp_alias measured as zero.
;
; What behaves exactly like that is a sick low-order address line. A0..A7 pick
; the byte inside a page, so a line that is marginal - too slow, too much
; capacitance, a cracked joint - misbehaves at the same offsets in every page,
; whichever page it is. Code burnt at such an offset would be read back wrong,
; and wrong instructions in the routine that copies the font produce a wrecked
; font, while wrong instructions in the boot loop produce no picture at all.
;
; This ROM asks the question directly. Sixty-four bytes of known pattern are
; burnt at each of the five addresses, and the board is asked to read them back
; and count the bytes that do not match. Each block carries its own tag, so a
; read that lands in the wrong block cannot pass by accident.
;
; It also sums the whole 24 KB of ROM. That number can be compared against the
; same sum taken from the .bin file on the host: if they differ, the board is
; not reading the image it was given, wherever that happens.
;
; The report goes to the LCD, which is the one output this board has that does
; not depend on the part under suspicion.
;
;   SUM   16-bit sum of every byte from $A000 to $FFFF, low byte last.
;   rows  the five addresses, each with the number of the 64 bytes that came
;         back wrong. 00 everywhere means the ROM reads back correctly and the
;         fault is not in the reading of it.
;
;------------------------------------------------------------------------------

        .setcpu "65C02"

        .include "lcd.inc"
        .include "utils.inc"
        .include "blink.inc"
        .include "zeropage.inc"

PATTERN_LEN   = 64

        .segment "VECTORS"

        .word   $0000
        .word   init
        .word   $0000

        .zeropage

rom_ptr:        .res 2                  ; both are walked with (zp),y
pat_ptr:        .res 2

        .segment "BSS"

sum_lo:         .res 1
sum_hi:         .res 1
bad_count:      .res 1
result:         .res 5

        .code

init:
        cld
        jsr _blink_init
        jsr _lcd_init
        jsr _lcd_clear

        jsr sum_rom

        ldx #$00
@next:
        phx
        jsr check_pattern               ; -> A
        plx
        sta result,x
        inx
        cpx #$05
        bne @next

;--- report ------------------------------------------------------------------

        jsr _lcd_clear

        ldy #$00
        ldx #$00
        jsr lcd_set_position
        lda #<msg_sum
        ldx #>msg_sum
        jsr _lcd_print
        lda sum_hi
        jsr print_hex
        lda sum_lo
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
; sum_rom - add up every byte of ROM, $A000 to $FFFF, into sum_hi:sum_lo
;------------------------------------------------------------------------------
sum_rom:
        stz sum_lo
        stz sum_hi
        stz rom_ptr
        lda #$A0
        sta rom_ptr+1
        ldx #$60                        ; 96 pages of 256 bytes = 24576
@page:
        ldy #$00
@byte:
        lda (rom_ptr),y
        clc
        adc sum_lo
        sta sum_lo
        bcc @no_carry
        inc sum_hi
@no_carry:
        iny
        bne @byte
        inc rom_ptr+1
        dex
        bne @page
        rts

;------------------------------------------------------------------------------
; check_pattern - read block X back and count the bytes that are not what was
; burnt there. The pattern is tag+index, so a read landing in a neighbouring
; block shows up rather than matching by luck. Returns the count in A.
;------------------------------------------------------------------------------
check_pattern:
        phx
        txa
        asl a
        tax
        lda pattern_addr,x
        sta pat_ptr
        lda pattern_addr+1,x
        sta pat_ptr+1
        plx
        lda pattern_tag,x               ; A counts up from the tag as Y walks

        stz bad_count
        ldy #$00
@loop:
        cmp (pat_ptr),y                 ; A holds tag+Y all the way round
        beq @same
        inc bad_count
@same:
        inc a
        iny
        cpy #PATTERN_LEN
        bne @loop
        lda bad_count
        rts

;------------------------------------------------------------------------------
; print_result - block X as "E3B7 00". A, X and Y are destroyed.
;------------------------------------------------------------------------------
print_result:
        phx                             ; print_hex destroys X, so the index and
        txa                             ; the second half of the address both
        asl a                           ; have to wait on the stack
        tax
        lda pattern_addr,x
        pha
        lda pattern_addr+1,x
        jsr print_hex
        pla
        jsr print_hex
        lda #' '
        jsr _lcd_print_char
        plx
        lda result,x
        jmp print_hex

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

msg_sum:  .byte "SUM ", $00

pattern_addr:
        .word   pat_f05d, pat_e360, pat_e3b7, pat_e45d, pat_feb7
pattern_tag:
        .byte   $11, $33, $55, $77, $99

;------------------------------------------------------------------------------
;
; The patterns themselves. Each is 64 bytes of tag+index, and every tag is
; different, so a byte that comes from the wrong block is a mismatch rather
; than a coincidence.
;
;------------------------------------------------------------------------------

.macro  rom_check_pattern Tag
        .repeat PATTERN_LEN, i
        .byte   (Tag + i) & $FF
        .endrepeat
.endmacro

        .segment "PAT_F05D"
pat_f05d:
        rom_check_pattern $11

        .segment "PAT_E360"
pat_e360:
        rom_check_pattern $33

        .segment "PAT_E3B7"
pat_e3b7:
        rom_check_pattern $55

        .segment "PAT_E45D"
pat_e45d:
        rom_check_pattern $77

        .segment "PAT_FEB7"
pat_feb7:
        rom_check_pattern $99

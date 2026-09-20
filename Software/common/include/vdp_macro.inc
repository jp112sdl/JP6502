;------------------------------------------------------------------------------
;
; Utility Macros
;
;------------------------------------------------------------------------------
; Two stores straight at the control port put the halves of the address about
; two microseconds apart and the chip asks for eight - the worst of the
; unpaced accesses that were left, and the same fault that scattered characters
; across the screen until load_vram_char_position was paced. See MEMORY_MAP.md
; 5.5. Y is saved because the callers did not have to think about it before.
.macro  vdp_set_vram_addr Address
    phy
    ldy #<Address
    lda #>Address | VDP_WRITE_VRAM_SELECT
    jsr vdp_write_address
    ply
.endmacro

; Stretch a loop that talks to the VDP out to the 8 us the chip wants between
; two accesses - vdp_wait says where the figure comes from. Cycles is what the
; loop already spends from one access to the next; the nops make up whatever
; the clock the ROM is built for leaves short, and there are none at all where
; the loop is slow enough on its own. Put it straight after the access, so the
; last pass pays it too and the gap to whatever follows the loop is covered.
; Needs clock.inc in the unit that uses it.
.macro  vdp_pace Cycles
    .if 8 * clock_mhz > (Cycles)
        .repeat (8 * clock_mhz - (Cycles) + 1) / 2
            nop
        .endrepeat
    .endif
.endmacro

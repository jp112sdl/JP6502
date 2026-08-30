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
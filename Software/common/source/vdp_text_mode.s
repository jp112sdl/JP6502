    .include "sys_const.inc"
    .include "sysram_map.inc"
    .include "vdp.inc"
    .include "vdp_const.inc"
    .include "vdp_macro.inc"
    .include "sysram_map.inc"
    .include "zeropage.inc"
    .include "blink.inc"
    .include "utils.inc"

    .export vdp_text_init
    .export vdp_boot_init
    .export vdp_scroll_line
    .export vdp_line
    .export vdp_char_pos

    .export vdp_advance_char_position
    .export vdp_newline
    .export vdp_clear_line
    .export vdp_clear_text_screen

    .export vdp_backspace
    .export vdp_set_prompt

    .export vdp_out_char
    .export vdp_write_char
    .export vdp_write_string

PROMPT = '>'
SPACE = ' '
LINE_FEED = $0A
CARRIAGE_RETURN = $0D



      .segment "BSS"
vdp_line:              .byte $00
vdp_char_pos:          .byte $00 


    .code

;------------------------------------------------------------------------------
;
; VDPReset
; Set Text Mode / Typical Settings
;
;------------------------------------------------------------------------------
vdp_text_init:
  jsr vdp_init_text_mode
  jsr vdp_initialize_text_pattern_table
  jsr vdp_clear_screen
  jsr vdp_enable_display

  lda #0
  sta vdp_line
  sta vdp_char_pos

  rts


;------------------------------------------------------------------------------
;
; AdvanceChar
; Move to the next character position
; TODO: future - scroll line right to allow longer lines
;
;------------------------------------------------------------------------------
vdp_advance_char_position:
      pha

      lda vdp_char_pos
      cmp #VDP_TEXT_MODE_LINE_LENGTH - 1

      beq @do_not_advance_char

      inc vdp_char_pos
@do_not_advance_char:      
      pla
      rts

;------------------------------------------------------------------------------
;
; AdvanceLine
; Move to the next line on the screen and set position to the first character
;
;------------------------------------------------------------------------------
vdp_newline:
      pha

      lda vdp_line
      cmp #VDP_TEXT_MODE_LINE_COUNT-1
      beq @scroll_required

      inc
      sta vdp_line
      bra @done

@scroll_required:
      jsr vdp_scroll_line
      jsr vdp_clear_line

@done:
      lda #0        
      sta vdp_char_pos

      pla
      rts





;------------------------------------------------------------------------------
;
; VDPWriteChar
; Write the charater in acc to the active position on the screen and advance
;
;------------------------------------------------------------------------------
vdp_write_char:
      ; Only a character that was actually drawn moves the cursor. A carriage
      ; return and a line feed both leave vdp_out_char with the column already
      ; at nought, so advancing afterwards put it at one - which is where the
      ; console then started the next line. BASIC sends both for every newline,
      ; so everything after the sign-on came out indented until something reset
      ; the column another way, and tty_read_line does exactly that on ENTER:
      ; hence an indent that appeared, survived one typed line and vanished.
      cmp #LINE_FEED
      beq @control
      cmp #CARRIAGE_RETURN
      beq @control
      jsr vdp_out_char
      jmp vdp_advance_char_position
@control:
      jmp vdp_out_char

;------------------------------------------------------------------------------
;
; VDPOutChar
; Write the charater in acc to the active position on the screen
;
;------------------------------------------------------------------------------
vdp_out_char:
    cmp #LINE_FEED
    bne @not_line_feed        
    jsr vdp_newline
    bra @done

@not_line_feed:
    cmp #CARRIAGE_RETURN
    bne @not_carriage_return   
    lda #0
    sta vdp_char_pos
    bra @done

@not_carriage_return:
      jsr load_vram_char_position
      sta VDP_VRAM
@done:
      rts      

;------------------------------------------------------------------------------
;
; VDPWriteString
; Write null terminated string at ADDR LSB = Acc, MSB = X and advance
; Currently limited to 256 char string; use vdp_vram_write_buffer for long blocks
;
;------------------------------------------------------------------------------
vdp_write_string:
    sta vdp_buffer_address
    stx vdp_buffer_address + 1
    jsr load_vram_char_position

    phy
    ldy #0
@write_loop:
    lda (vdp_buffer_address),y
    beq @done
    jsr vdp_write_char    ; note inefficiency of rewriting VDP RAM Address here
  
    iny
    bra @write_loop  

@done:
    ; No advance here: every character went through vdp_write_char, which has
    ; already moved the cursor past it. The extra step left every string one
    ; column further along than it had printed.
    ply
    rts



;------------------------------------------------------------------------------
;
; LoadVRAMCharPosition
; Loads the VDP VRAM address that corresponds to (vdp_line, vdp_char_pos)
;
;------------------------------------------------------------------------------
load_vram_char_position:
      .scope
      pha
      phx
      phy

      lda #0
      sta vdp_vram_address+1

      lda vdp_char_pos                    ; keep LSB of VRAM Address here
      ldx vdp_line
      beq done

next_line:
      clc
      adc #VDP_TEXT_MODE_LINE_LENGTH
      bcc no_carry     
      inc vdp_vram_address+1

no_carry:      
      dex
      bne next_line

done:
      ; Through the paced path rather than two stores at the control port. Those
      ; put the two halves of the address nine cycles apart and the chip asks
      ; for eight - one microsecond of margin, on the hottest path in the
      ; machine, and it is set up again for every single character. When the
      ; second half is not taken the character lands somewhere else, and when a
      ; data write is not taken it does not land at all: single letters missing
      ; or displaced out of an otherwise correct line. vdp_write_address leaves
      ; sixteen microseconds.
      ;
      ; The three bytes it costs come out of the two stores it replaces, which
      ; kept CODE the same length. That was a requirement once - MEMORY_MAP.md
      ; 5.5 - and is now just a tidy accident.
      tay
      lda vdp_vram_address+1
      ora #VDP_WRITE_VRAM_SELECT
      jsr vdp_write_address

      ply
      plx
      pla
      rts
      .endscope



;------------------------------------------------------------------------------
;
; VDPClearLine
; Clear current line - does not change the character position
;
;------------------------------------------------------------------------------
vdp_clear_line:
      .scope
      pha
      phx

      ldx #0
      stx vdp_char_pos

      lda #' '
      jsr load_vram_char_position

loop:
      sta VDP_VRAM
      inx
      cpx #VDP_TEXT_MODE_LINE_LENGTH
      bne loop      
 
      plx  
      pla
      rts
      .endscope


;------------------------------------------------------------------------------
;
; VDPClearScreen
;
;------------------------------------------------------------------------------
vdp_clear_text_screen:
      pha

    jsr vdp_clear_screen

    lda #0
    sta vdp_char_pos
    sta vdp_line
 
      pla
      rts

;------------------------------------------------------------------------------
;
; DoBackspace
; Back up to the last character, replace it with a space, and stay there
;
;------------------------------------------------------------------------------
vdp_backspace:
      .scope
      ; Only column nought has nothing in front of it. There used to be a
      ; second test here that refused at column one as well, which left the
      ; first character of a line on the screen for ever - tty_read_line had
      ; already taken it out of the buffer by then, so what stayed behind was
      ; not even part of the line any more. Nothing needs protecting at column
      ; nought either: vdp_set_prompt would put a character there, and nothing
      ; calls it.
      lda vdp_char_pos
      beq dont_backspace

      dec vdp_char_pos
      lda #SPACE
      jsr vdp_out_char

dont_backspace:
      rts
      .endscope


;------------------------------------------------------------------------------
;
; SetupPrompt
; Move to beginning of line; output a prompt, and advance
;
;------------------------------------------------------------------------------
vdp_set_prompt:
      .scope
      pha

      lda #0
      sta vdp_char_pos

      lda #PROMPT
      jsr vdp_out_char      
;      jsr load_vram_char_position
;      sta VDP_VRAM

      jsr vdp_advance_char_position

      pla
      rts
      .endscope



;------------------------------------------------------------------------------
;
; ScrollLine
; Shift Text on Screen Up one line; does not alter current char position
;
;------------------------------------------------------------------------------
vdp_scroll_line:
    .scope
    pha

    lda #VDP_TEXT_MODE_LINE_LENGTH    ; Start read one line in
    sta vdp_vram_address 
    lda #0
    sta vdp_vram_address+1

    lda #<text_screen_buffer          ; Read into the start of the buffer  
    sta vdp_buffer_address
    lda #>text_screen_buffer
    sta vdp_buffer_address+1

    ; how much to read?               ; 23 lines of text  
    lda #<((VDP_TEXT_MODE_LINE_COUNT - 1) * VDP_TEXT_MODE_LINE_LENGTH)
    sta vdp_char_count
    lda #>((VDP_TEXT_MODE_LINE_COUNT - 1) * VDP_TEXT_MODE_LINE_LENGTH)
    sta vdp_char_count+1

    jsr vdp_vram_read_buffer

    ; TODO: add blank line at bottom so junk is not duplicated

    lda #0                              ; now write it to the first line
    sta vdp_vram_address
    sta vdp_vram_address+1

    lda #<text_screen_buffer
    sta vdp_buffer_address
    lda #>text_screen_buffer
    sta vdp_buffer_address+1

    ; how much to write? 
    lda #<((VDP_TEXT_MODE_LINE_COUNT - 1) * VDP_TEXT_MODE_LINE_LENGTH)
    sta vdp_char_count
    lda #>((VDP_TEXT_MODE_LINE_COUNT - 1) * VDP_TEXT_MODE_LINE_LENGTH)
    sta vdp_char_count+1

    jsr vdp_vram_write_buffer

    pla
    rts
    .endscope

;------------------------------------------------------------------------------
;
; vdp_boot_init - bring the VDP up at power-on
;
; Two things go wrong on a cold start that never go wrong afterwards, and both
; are handled here rather than in the routines above, which have to stay fast.
;
; The control port carries a flip-flop that decides whether the next write is
; the first or the second half of a pair. Its power-on state is undefined, and
; nothing in this project ever read the status register, which is what clears
; it. While it stands wrong, all eight registers land shifted by one. They
; cannot be read back, so this is prevented, not detected.
;
; The chip also wants about 8 us between two accesses. vdp_init_text_mode gives
; it 4, vdp_set_vram_addr and vdp_enable_display give it 2 - enough once it is
; warm, not enough at power-on. The vdp_boot_* routines in vdp.s are the same
; set-up with a wait between every access.
;
; What is left after that is the chip simply not being ready yet, so the whole
; thing is retried until VRAM holds what was written to it and the status
; register shows frames going out.
;
; This sits in SDCODE because CODE had to keep its byte count when it was
; written and EXTCODE was nearly full. The first half of that reason is gone -
; MEMORY_MAP.md 5.5 - and it stays here because it works, not because it must.
;
;------------------------------------------------------------------------------

VDP_BOOT_TRIES    = 20
VDP_BOOT_WAIT_MS  = 50

; Longer than one frame at both 60 Hz and 50 Hz
VDP_FRAME_WAIT_MS = 30

; Two addresses at the top of VRAM, clear of the name, pattern and colour
; tables. Two different values, because an unclocked VDP tends to return the
; byte last on the bus and a single probe would pass on bus capacitance alone
VDP_PROBE_LO      = $3FFE
VDP_PROBE_VALUE1  = $5A
VDP_PROBE_VALUE2  = $A5

      .segment "SDCODE"

vdp_boot_init:
      phx
      ldx #VDP_BOOT_TRIES
@attempt:
      lda VDP_REG                       ; clears the control port flip-flop
      jsr vdp_boot_registers
      jsr vdp_boot_patterns
      jsr vdp_boot_clear
      jsr vdp_boot_enable
      stz vdp_line
      stz vdp_char_pos

      jsr vdp_alive
      bcc @up
      lda #VDP_BOOT_WAIT_MS
      jsr _delay_ms
      dex
      bne @attempt
      ; Out of tries. Carry on regardless - a machine that reaches the prompt
      ; with a dead screen is still worth more than one that hangs here
@up:
      plx
      rts

;------------------------------------------------------------------------------
;
; vdp_alive - is the chip up, and did what was written to it stick?
; Carry clear when it is. A is destroyed, X and Y are kept.
;
;------------------------------------------------------------------------------
vdp_alive:
      ldy #<VDP_PROBE_LO
      lda #(>VDP_PROBE_LO) | VDP_WRITE_VRAM_SELECT
      jsr vdp_write_address
      lda #VDP_PROBE_VALUE1
      sta VDP_VRAM
      jsr vdp_wait
      lda #VDP_PROBE_VALUE2
      sta VDP_VRAM                      ; auto-incremented to the next address
      jsr vdp_wait

      ldy #<VDP_PROBE_LO
      lda #(>VDP_PROBE_LO) | VDP_READ_VRAM_SELECT
      jsr vdp_write_address

      lda VDP_VRAM
      cmp #VDP_PROBE_VALUE1
      bne @dead
      jsr vdp_wait
      lda VDP_VRAM
      cmp #VDP_PROBE_VALUE2
      bne @dead

      ; Working VRAM does not prove the chip is producing video. F in the
      ; status register is set at every vertical retrace, so after more than a
      ; frame time it has to be there. Reading it clears it for the next round.
      lda #VDP_FRAME_WAIT_MS
      jsr _delay_ms
      lda VDP_REG
      bpl @dead

      clc
      rts
@dead:
      sec
      rts

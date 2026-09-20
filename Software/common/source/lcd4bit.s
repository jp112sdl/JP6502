        .include "zeropage.inc"
        .include "utils.inc"
        .include "via.inc"
        .include "clock.inc"

; The panel needs a moment after E rises before it drives the data bus, and the
; HD44780 datasheet allows it 360 ns. The read below lands four cycles after
; the edge, which is a microsecond at 4 MHz but only 500 ns at 8 MHz - too
; close to the limit to rely on, so at 8 MHz it is padded back out to a
; microsecond. Below that nothing is emitted.
LCD_READ_SETTLE_CYCLES = clock_mhz
.if LCD_READ_SETTLE_CYCLES > 4
LCD_READ_SETTLE_NOPS = (LCD_READ_SETTLE_CYCLES - 4 + 1) / 2
.else
LCD_READ_SETTLE_NOPS = 0
.endif

.macro  lcd_read_settle
        .repeat LCD_READ_SETTLE_NOPS
        nop
        .endrepeat
.endmacro

        .export _lcd_init
        .export lcd_read_byte
        .export lcd_write_byte

; LCD Commands list
LCD_CMD_CLEAR           = %00000001
LCD_CMD_HOME            = %00000010
LCD_CMD_ENTRY_MODE      = %00000100
LCD_CMD_DISPLAY_MODE    = %00001000
LCD_CMD_CURSOR_SHIFT    = %00010000
LCD_CMD_FUNCTION_SET    = %00100000
LCD_CMD_CGRAM_SET       = %01000000
LCD_CMD_DDRAM_SET       = %10000000

; Entry mode command parameters
LCD_EM_SHIFT_CURSOR     = %00000000
LCD_EM_SHIFT_DISPLAY    = %00000001
LCD_EM_DECREMENT        = %00000000
LCD_EM_INCREMENT        = %00000010

; Display mode command parameters
LCD_DM_CURSOR_NOBLINK   = %00000000
LCD_DM_CURSOR_BLINK     = %00000001
LCD_DM_CURSOR_OFF       = %00000000
LCD_DM_CURSOR_ON        = %00000010
LCD_DM_DISPLAY_OFF      = %00000000
LCD_DM_DISPLAY_ON       = %00000100

; Function set command parameters
LCD_FS_FONT5x7          = %00000000
LCD_FS_FONT5x10         = %00000100
LCD_FS_ONE_LINE         = %00000000
LCD_FS_TWO_LINE         = %00001000
LCD_FS_4_BIT            = %00000000
LCD_FS_8_BIT            = %00010000

; Control bits for the LCD
LCD_COMMAND_MODE        = %00000000
LCD_DATA_MODE           = %00000010
LCD_WRITE_MODE          = %00000000
LCD_READ_MODE           = %00000100
LCD_ENABLE_FLAG         = %00001000

; Default setting compatible with PCB Rev. 001
LCD_PORT                = VIA1_PORTB
LCD_DDR                 = VIA1_DDRB

LCD_DDR_WRITE_MASK      = %11111110
LCD_DDR_READ_MASK       = %00001110

BLINK_PORT_MASK         = %00000001 
UPPER_NIBBLE_MASK       = %11110000
LOWER_NIBBLE_MASK       = %00001111
BUSY_FLAG_MASK          = %10000000

        .code

; POSITIVE C COMPLIANT
_lcd_init:
        ; store registers A and X
        pha
        phx
        ; Initialize DDRB
        lda LCD_DDR
        ora #(LCD_DDR_WRITE_MASK)
        sta LCD_DDR
        ; Initialization by instruction
        ldx #$00
@lcd_force_reset_loop:
        lda lcd_force_reset_sequence,x
        jsr _delay_ms
        inx
        ; Read next byte of force reset sequence data
        lda lcd_force_reset_sequence,x
        ; Exit loop if $00 read
        beq @lcd_force_reset_end

        lda LCD_PORT
        and #(BLINK_PORT_MASK)
        ora lcd_force_reset_sequence, x
        sta LCD_PORT
        ora #(LCD_ENABLE_FLAG)
        sta LCD_PORT
        eor #(LCD_ENABLE_FLAG)
        sta LCD_PORT

        inx 
        bra @lcd_force_reset_loop

@lcd_force_reset_end:
        ; initialize index
        ldx #$00

@lcd_init_loop:
        ; Perform actual init operation
        lda lcd_init_sequence_data,x
        beq @lcd_init_end
        ; Clear carry for command operation
        clc 
        jsr lcd_write_byte
        inx
        bra @lcd_init_loop
@lcd_init_end:
        plx
        pla
        rts

; INTERNAL
; lcd_write_byte - send one byte to LCD
; byte in A
; carry clear - command
; carry set - data
; internal variables
; lcd_temp_char1 - buffer for mode and blink flag
; lcd_temp_char2 - buffer for data
lcd_write_byte:
        pha
        php
        jsr lcd_wait_bf_clear
        plp
        pla
        sta lcd_temp_char2
        bcs @lcd_write_data
        ; Set flags
        lda #(LCD_WRITE_MODE | LCD_COMMAND_MODE)
        sta lcd_temp_char1
        bra @lcd_write_mode_set
@lcd_write_data:
        ; Set flags
        lda #(LCD_WRITE_MODE | LCD_DATA_MODE)
        sta lcd_temp_char1
@lcd_write_mode_set:
        ; Get current value of blink led
        lda LCD_PORT
        and #(BLINK_PORT_MASK)
        ; Concatenate with current buffer and store it there
        ora lcd_temp_char1
        sta lcd_temp_char1
        ; Set port direction (output)
        lda LCD_DDR
        ora #(LCD_DDR_WRITE_MASK)
        sta LCD_DDR
        ; Process actual data
        lda lcd_temp_char2
        ; Most significant bits first
        ; Apply mask
        and #(UPPER_NIBBLE_MASK)
        ; Fetch current status from lcd_temp_char1
        ora lcd_temp_char1
        ; Send first 4 bits
        sta LCD_PORT
        ; Set enable flag
        ora #(LCD_ENABLE_FLAG)
        ; send command
        sta LCD_PORT
        ; Toggle pulse
        eor #(LCD_ENABLE_FLAG)
        sta LCD_PORT
        ; Follow the same process with least significant bits
        lda lcd_temp_char2
        and #(LOWER_NIBBLE_MASK)
        asl
        asl
        asl
        asl
        ; Get current status
        ora lcd_temp_char1
        ; Send first 4 bits
        sta LCD_PORT
        ; Set write command flags
        ora #(LCD_ENABLE_FLAG)
        ; Send command
        sta LCD_PORT
        ; Toggle pulse
        eor #(LCD_ENABLE_FLAG)
        sta LCD_PORT
        rts

; INTERNAL
; lcd_read_byte - read one byte from LCD
; result in A
; carry clear - command
; carry set - data
; internal variables
; lcd_temp_char1 - buffer for data MSB
; lcd_temp_char2 - buffer for data LSB
; lcd_temp_char3 - buffer for operation mode
lcd_read_byte:
        ; Wait for BF flag to clear before running
        php
        jsr lcd_wait_bf_clear
        plp
        bcs @lcd_read_data
        ; Set flags
        lda #(LCD_READ_MODE | LCD_COMMAND_MODE)
        sta lcd_temp_char3
        bra @lcd_read_mode_set
@lcd_read_data:
        ; Set flags
        lda #(LCD_READ_MODE | LCD_DATA_MODE)
        sta lcd_temp_char3
@lcd_read_mode_set:
        ; Preserve direction of last four bits of DDRB
        ; but toggle LCD data lines to input
        lda LCD_DDR
        and #(BLINK_PORT_MASK)
        ora #(LCD_DDR_READ_MASK)
        sta LCD_DDR
        ; Preserve status of blink led
        lda LCD_PORT
        and #(BLINK_PORT_MASK)
        ora lcd_temp_char3
        sta LCD_PORT
        ora #(LCD_ENABLE_FLAG)
        sta LCD_PORT
        lcd_read_settle
        lda LCD_PORT
        and #(UPPER_NIBBLE_MASK)
        ; Store result from LCD data lines
        sta lcd_temp_char1
        ; Toggle enable
        lda LCD_PORT
        eor #(LCD_ENABLE_FLAG)
        sta LCD_PORT
        and #(BLINK_PORT_MASK)
        ora lcd_temp_char3
        sta LCD_PORT
        ora #(LCD_ENABLE_FLAG)
        sta LCD_PORT
        lcd_read_settle
        lda LCD_PORT
        sta lcd_temp_char2
        ; Toggle enable flag
        eor #(LCD_ENABLE_FLAG)
        sta LCD_PORT
        ; Combine results
        lda lcd_temp_char2
        and #(UPPER_NIBBLE_MASK)
        lsr
        lsr
        lsr
        lsr
        ora lcd_temp_char1
        rts

; How long to poll the busy flag before giving up on it. The slowest
; instructions, CLEAR and HOME, take 1.52 ms at the usual 270 kHz and about
; 2.2 ms at the slowest oscillator the HD44780 allows. One poll below takes 53
; cycles while the flag is set, so a page of 256 is 13.6 ms at 1 MHz - and one
; page per MHz keeps it there at every CLOCK_MODE, six times the slowest
; instruction.
.if clock_mhz > 1
LCD_BUSY_TIMEOUT_PAGES = clock_mhz
.else
LCD_BUSY_TIMEOUT_PAGES = 1
.endif

; Wait for the controller to finish what it was last given. A controller that
; never lets go of the flag - none plugged in, DB7 stuck high, the two nibbles
; out of step after a reset that went wrong - used to hang the machine here,
; early in _system_init with the BLINK LED still on. It is given up on after
; the timeout above instead, and the caller goes ahead: a garbled LCD, but a
; machine that starts.
; A is destroyed, X and Y are kept - _lcd_init carries its index in X.
lcd_wait_bf_clear:
        phx
        phy
        ; Preserve direction of last four bits of DDRB
        ; but toggle LCD data lines to input
        lda LCD_DDR
        and #(BLINK_PORT_MASK)
        ora #(LCD_DDR_READ_MASK)
        sta LCD_DDR
        ldy #$00
        ldx #LCD_BUSY_TIMEOUT_PAGES
        ; Preserve status of blink led
@wait_loop:
        lda LCD_PORT
        and #(BLINK_PORT_MASK)
        ora #(LCD_READ_MODE | LCD_COMMAND_MODE)
        sta LCD_PORT
        ora #(LCD_ENABLE_FLAG)
        sta LCD_PORT
        lcd_read_settle
        lda LCD_PORT
        ; Store result from LCD data lines
        sta lcd_temp_char1
        ; Toggle enable
        eor #(LCD_ENABLE_FLAG)
        sta LCD_PORT
        eor #(LCD_ENABLE_FLAG)
        sta LCD_PORT
        eor #(LCD_ENABLE_FLAG)
        sta LCD_PORT
        lda lcd_temp_char1
        bpl @done
        dey
        bne @wait_loop
        dex
        bne @wait_loop
@done:
        ply
        plx
        rts

        .SEGMENT "RODATA"

lcd_force_reset_sequence:
        .byte 20
        .byte LCD_CMD_FUNCTION_SET | LCD_FS_8_BIT | LCD_COMMAND_MODE | LCD_WRITE_MODE
        .byte 5
        .byte LCD_CMD_FUNCTION_SET | LCD_FS_8_BIT | LCD_COMMAND_MODE | LCD_WRITE_MODE
        .byte 1
        .byte LCD_CMD_FUNCTION_SET | LCD_FS_8_BIT | LCD_COMMAND_MODE | LCD_WRITE_MODE
        .byte 1
        .byte LCD_CMD_FUNCTION_SET | LCD_FS_4_BIT | LCD_COMMAND_MODE | LCD_WRITE_MODE
        .byte 1
        .byte $00

lcd_init_sequence_data:
        .byte LCD_CMD_FUNCTION_SET | LCD_FS_FONT5x7 | LCD_FS_TWO_LINE | LCD_FS_4_BIT
        .byte LCD_CMD_DISPLAY_MODE | LCD_DM_DISPLAY_OFF | LCD_DM_CURSOR_OFF | LCD_DM_CURSOR_NOBLINK
        .byte LCD_CMD_CLEAR
        .byte LCD_CMD_ENTRY_MODE | LCD_EM_SHIFT_CURSOR | LCD_EM_INCREMENT
        .byte LCD_CMD_DISPLAY_MODE | LCD_DM_DISPLAY_ON | LCD_DM_CURSOR_OFF | LCD_DM_CURSOR_NOBLINK
        .byte $00

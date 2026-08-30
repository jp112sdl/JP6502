      .include "via.inc"
      .include "lcd.inc"
      .include "tty.inc"
      .include "libfat32.s"
      .include "zeropage.inc"
      .include "utils.inc"
      .include "keyboard.inc"
      .include "sysram_map.inc"
      .include "sys_const.inc"
      .include "acia.inc"
;      .import TXTPTR
;      .import INPUTBUFFER
      
      .import __USERRAM_START__

      .export _sd_init
      .export _sd_load
      .export _sd_save
      .export sd_address
      .export sd_length
      .export fat32_lasterror

; Streaming interface, used by the BASIC LOAD / SAVE / "$" commands. These let
; a caller work through a file a byte or a sector at a time instead of moving
; the whole thing in one go.
      .export _sd_openread
      .export _sd_openwrite
      .export _sd_readbyte
      .export _sd_putsector
      .export _sd_close
      .export _sd_opendir
      .export _sd_nextdirent
      .export sd_direntname
      .export sd_direntattr
      .export sd_direntsize

; Allocating write interface - creates the file if it is not on the card yet
; and takes clusters off the free list as the data comes in. Lives in the
; SDCODE block at the end of libfat32.s.
      .export _sd_mount
      .export _sd_freeblocks
      .export sd_freeblocks
      .export _sd_beginsave
      .export _sd_putnext
      .export _sd_endsave
      .export _sd_abortsave

SD_PORTB = $8200
SD_PORTA = $8201
SD_DDRB = $8202
SD_DDRA = $8203


SD_CS   = %00000010
SD_SCK  = %00000100
SD_MOSI = %00001000
SD_MISO = %00010000      

PORTA_OUTPUTPINS = SD_CS | SD_SCK | SD_MOSI

; FAT32 sector workspace - 512 bytes, page aligned.
; Placed by the linker in FAT_RAM ($0c00) instead of a fixed $0200, which
; used to sit on top of acia_rx_buffer and acia_tx_buffer.
        .segment "FATBUF"
fat32_workspace:
        .res 512

        .code

; Destination for fat32_file_read. The whole file is read here, rounded up to
; whole sectors, so this has to be user RAM - it used to be $0400, which is
; keyboard_buffer / lcd_line_buffer / text_screen_buffer.
buffer = __USERRAM_START__



; Parameters for _sd_load / _sd_save
        .segment "BSS"
sd_address:
        .res 2          ; memory address to load into / save from
sd_length:
        .res 4          ; byte count
sd_nameptr:
        .res 2          ; pointer to the caller's 11 character FAT name
sd_ready:
        .res 1          ; non-zero once the card has been initialised
sd_timeout:
        .res 2          ; countdown used by sd_waitresult / sd_waitbusy

; Directory entry handed back by _sd_nextdirent. It is copied out of the
; sector buffer because the caller normally does other work - and other card
; accesses - before asking for the next entry.
sd_direntname:
        .res 11         ; raw FAT name, eight plus three, space padded
sd_direntattr:
        .res 1
sd_direntsize:
        .res 4

        .zeropage
memory_pointer:   .res 2
  
      
      .code 
      
_sd_init:
  write_lcd #SD_initializing
  jsr sd_init
  ; Act on the result immediately - _lcd_newline below clobbers the carry flag
  bcc @cardok

  ; Carry on booting without a card - _sd_load / _sd_save refuse to run
  stz sd_ready
  jsr _lcd_newline
  rts

@cardok:
  lda #$01
  sta sd_ready
  jsr _lcd_newline
  jsr fat32_init
  rts

sd_openfile:
  ; Internal. Opens the root directory and locates the file whose 11 character
  ; FAT name is pointed at by A/X.
  ;
  ; On success carry is clear, the entry sits in the buffer, zp_sd_address
  ; points at it and fat32_markdirent has recorded where to write it back.
  sta sd_nameptr
  stx sd_nameptr+1

  ; Refuse to talk to a card that never initialised
  lda sd_ready
  beq @nocard

  jsr fat32_openroot

  ldx sd_nameptr
  ldy sd_nameptr+1
  jsr fat32_finddirent
  bcs @notfound

  jsr fat32_markdirent
  clc
  rts

@nocard:
  lda #FAT32_ERROR_NO_CARD
  sta fat32_lasterror
  sec
  rts

@notfound:
  lda #FAT32_ERROR_NO_SUCH_FILE
  sta fat32_lasterror
  sec
  rts


; ---------------------------------------------------------------------------
; Streaming interface
; ---------------------------------------------------------------------------

_sd_openread:
  ; Open the file whose 11 character FAT name is pointed at by A/X for
  ; sequential reading with _sd_readbyte.
  ;
  ; On success carry is clear and sd_length holds the file size.
  jsr sd_openfile
  bcs @fail

  jsr fat32_opendirent

  lda fat32_bytesremaining
  sta sd_length
  lda fat32_bytesremaining+1
  sta sd_length+1
  lda fat32_bytesremaining+2
  sta sd_length+2
  lda fat32_bytesremaining+3
  sta sd_length+3

  clc
  rts

@fail:
  sec
  rts


_sd_openwrite:
  ; Open the file whose 11 character FAT name is pointed at by A/X for
  ; sequential writing with _sd_putsector, finished off by _sd_close.
  ;
  ; The file has to exist already and keeps the cluster chain it has, so this
  ; can overwrite it but never create or extend it. For the version that does,
  ; use _sd_beginsave / _sd_putnext / _sd_endsave instead.
  jsr sd_openfile
  bcs @fail

  ; A file with no cluster chain at all has nowhere to put the data, and
  ; fat32_opendirent would seek to cluster zero. Stop before that happens.
  ldy #26
  lda (zp_sd_address),y
  iny
  ora (zp_sd_address),y
  ldy #20
  ora (zp_sd_address),y
  iny
  ora (zp_sd_address),y
  beq @toosmall

  jsr fat32_opendirent
  clc
  rts

@toosmall:
  lda #FAT32_ERROR_FILE_TOO_SMALL
  sta fat32_lasterror
@fail:
  sec
  rts


_sd_readbyte:
  ; Returns the next byte of the open file in A with carry clear, or sets
  ; carry at end of file.
  jmp fat32_file_readbyte


_sd_putsector:
  ; Writes the 512 bytes at A/X as the next sector of the open file.
  ;
  ; On failure carry is set and fat32_lasterror says what went wrong.
  sta fat32_address
  stx fat32_address+1
  jmp fat32_writenextsector


_sd_close:
  ; Stores sd_length as the new size of the file opened by _sd_openwrite.
  lda sd_length
  sta fat32_newsize
  lda sd_length+1
  sta fat32_newsize+1
  lda sd_length+2
  sta fat32_newsize+2
  lda sd_length+3
  sta fat32_newsize+3
  jmp fat32_writedirent


_sd_opendir:
  ; Prepares the root directory for iteration with _sd_nextdirent.
  lda sd_ready
  beq @nocard
  jsr fat32_openroot
  clc
  rts

@nocard:
  lda #FAT32_ERROR_NO_CARD
  sta fat32_lasterror
  sec
  rts


_sd_nextdirent:
  ; Copies the next directory entry into sd_direntname / sd_direntattr /
  ; sd_direntsize. Carry is set once there are no entries left.
  jsr fat32_readdirent
  bcs @end

  ldy #10
@copyname:
  lda (zp_sd_address),y
  sta sd_direntname,y
  dey
  bpl @copyname

  ldy #11
  lda (zp_sd_address),y
  sta sd_direntattr

  ldy #28
  lda (zp_sd_address),y
  sta sd_direntsize
  iny
  lda (zp_sd_address),y
  sta sd_direntsize+1
  iny
  lda (zp_sd_address),y
  sta sd_direntsize+2
  iny
  lda (zp_sd_address),y
  sta sd_direntsize+3

  clc
  rts

@end:
  sec
  rts


_sd_load:
  ; Load a whole file from the root directory into memory.
  ;
  ; Parameters:
  ;    A/X        pointer to the 11 character FAT name (no dot, space padded)
  ;    sd_address destination
  ;
  ; On success carry is clear and sd_length holds the file size. On failure
  ; carry is set and fat32_lasterror says what went wrong.
  jsr sd_openfile
  bcs @fail

  ; Reads the size and the first cluster out of the entry, then seeks
  jsr fat32_opendirent

  ; Hand the size back to the caller before fat32_file_read consumes it
  lda fat32_bytesremaining
  sta sd_length
  lda fat32_bytesremaining+1
  sta sd_length+1
  lda fat32_bytesremaining+2
  sta sd_length+2
  lda fat32_bytesremaining+3
  sta sd_length+3

  lda sd_address
  sta fat32_address
  lda sd_address+1
  sta fat32_address+1

  jsr fat32_file_read

  clc
  rts

@fail:
  sec
  rts


_sd_save:
  ; Write memory back into a file that already exists in the root directory.
  ;
  ; Parameters:
  ;    A/X        pointer to the 11 character FAT name (no dot, space padded)
  ;    sd_address source
  ;    sd_length  number of bytes to write
  ;
  ; The file is overwritten in place. Its existing cluster chain is never
  ; extended, so the file has to have been created large enough beforehand -
  ; otherwise this fails with FAT32_ERROR_FILE_TOO_SMALL and the file is left
  ; partly overwritten.
  ;
  ; On success carry is clear. On failure carry is set and fat32_lasterror
  ; says what went wrong.
  jsr sd_openfile
  bcs @fail

  ; Sets up the cluster chain. This overwrites the buffer holding the entry,
  ; which is why fat32_writedirent re-reads it later on.
  jsr fat32_opendirent

  lda sd_address
  sta fat32_address
  lda sd_address+1
  sta fat32_address+1

  lda sd_length
  sta fat32_bytesremaining
  lda sd_length+1
  sta fat32_bytesremaining+1
  lda sd_length+2
  sta fat32_bytesremaining+2
  lda sd_length+3
  sta fat32_bytesremaining+3

  jsr fat32_file_write
  bcs @fail

  ; Only now record the new length in the directory entry, so a failed data
  ; write does not leave a size that claims more than was actually stored
  lda sd_length
  sta fat32_newsize
  lda sd_length+1
  sta fat32_newsize+1
  lda sd_length+2
  sta fat32_newsize+2
  lda sd_length+3
  sta fat32_newsize+3

  jsr fat32_writedirent
  bcs @fail

  clc
  rts

@fail:
  sec
  rts


sd_init:
;  lda #%11111111          ; Set all pins on port B to output
;  sta SD_DDRA
  lda #PORTA_OUTPUTPINS   ; Set various pins on port B to output
  sta SD_DDRB
  
  ; Let the SD card boot up, by pumping the clock with SD CS disabled

  ; We need to apply around 80 clock pulses with CS and MOSI high.
  ; Normally MOSI doesn't matter when CS is high, but the card is
  ; not yet is SPI mode, and in this non-SPI state it does care.
;  pha 
  lda #(SD_CS | SD_MOSI)
  ldx #160               ; toggle the clock 160 times, so 80 low-high transitions
@preinitloop:
  eor #SD_SCK
  sta SD_PORTB
  dex
  bne @preinitloop
  
  
cmd0: ; GO_IDLE_STATE - resets card to idle state, and SPI mode
  lda #<sd_cmd0_bytes
  sta zp_sd_address
  lda #>sd_cmd0_bytes
  sta zp_sd_address+1

  jsr sd_sendcommand

  ; Expect status response $01 (not initialized)
  cmp #$01
  bne initfailed

cmd8: ; SEND_IF_COND - tell the card how we want it to operate (3.3V, etc)
  lda #<sd_cmd8_bytes
  sta zp_sd_address
  lda #>sd_cmd8_bytes
  sta zp_sd_address+1

  jsr sd_sendcommand

  ; Expect status response $01 (not initialized)
  cmp #$01
  bne initfailed

  ; Read 32-bit return value, but ignore it
  jsr sd_readbyte
  jsr sd_readbyte
  jsr sd_readbyte
  jsr sd_readbyte 


cmd55: ; APP_CMD - required prefix for ACMD commands
  lda #<sd_cmd55_bytes
  sta zp_sd_address
  lda #>sd_cmd55_bytes
  sta zp_sd_address+1

  jsr sd_sendcommand

  ; Expect status response $01 (not initialized)
  cmp #$01
  bne initfailed

cmd41: ; APP_SEND_OP_COND - send operating conditions, initialize card
  lda #<sd_cmd41_bytes
  sta zp_sd_address
  lda #>sd_cmd41_bytes
  sta zp_sd_address+1

  jsr sd_sendcommand

  ; Status response $00 means initialised
  cmp #$00
  beq initialized

  ; Otherwise expect status response $01 (not initialized)
  cmp #$01
  bne initfailed

  ; Not initialized yet, so wait a while then try again.
  ; This retry is important, to give the card time to initialize.
    
  jsr delay

  jmp cmd55

initialized:
;  lda #'Y'
;  jsr _lcd_print_char
;  write_lcd #SD_initialized
;  jsr _lcd_newline
;  lda #02
;  jsr _delay_sec
;  jsr _lcd_clear
  clc
  rts

initfailed:
;  lda #'X'
;  jsr _lcd_print_char
  write_lcd #SD_not_initialized
  jsr _lcd_newline
  ; Report the failure instead of hanging here. _sd_init runs from
  ; _system_init on every boot, so a missing or faulty card used to stop the
  ; machine from starting at all.
  sec
  rts


sd_readbyte:
  ; Enable the card and tick the clock 8 times with MOSI high, 
  ; capturing bits from MISO and returning them

  ldx #$fe    ; Preloaded with seven ones and a zero, so we stop after eight bits

read_loop:

  lda #SD_MOSI                ; enable card (CS low), set MOSI (resting state), SCK low
  sta SD_PORTB

  lda #(SD_MOSI | SD_SCK)       ; toggle the clock high
  sta SD_PORTB

  lda SD_PORTB                  ; read next bit
  and #SD_MISO

  clc                         ; default to clearing the bottom bit
  beq @bitnotset              ; unless MISO was set
  sec                         ; in which case get ready to set the bottom bit
@bitnotset:

  txa                         ; transfer partial result from X
  rol                         ; rotate carry bit into read result, and loop bit into carry
  tax                         ; save partial result back to X
  
  bcs read_loop                   ; loop if we need to read more bits

  rts
   
sd_writebyte:
  ; Tick the clock 8 times with descending bits on MOSI
  ; SD communication is mostly half-duplex so we ignore anything it sends back here
;  jsr print_hex
  ldx #8                      ; send 8 bits

write_loop:
  asl                         ; shift next bit into carry
  tay                         ; save remaining bits for later

  lda #0
  bcc sendbit                ; if carry clear, don't set MOSI for this bit
  ora #SD_MOSI

sendbit:
  sta SD_PORTB                   ; set MOSI (or not) first with SCK low
  eor #SD_SCK
  sta SD_PORTB                   ; raise SCK keeping MOSI the same, to send the bit

  tya                         ; restore remaining bits to send

  dex
  bne write_loop                   ; loop if there are more bits to send

  rts

; Timeouts, counted in sd_readbyte calls. One call is roughly 200 cycles, so
; at 1MHz these are in the region of 200ms and 1.6s.
SD_RESPONSE_TIMEOUT = 1024
SD_BUSY_TIMEOUT     = 8192

sd_waitresult:
  ; Wait for the SD card to return something other than $ff.
  ;
  ; Gives up after SD_RESPONSE_TIMEOUT attempts rather than hanging forever.
  ; With no card in the slot MISO reads back as $ff for good, which used to
  ; lock the machine up inside sd_init during boot.
  ;
  ; On timeout A is $ff and carry is set. $ff is never a valid response, so
  ; every existing "cmp #expected" at the call sites fails on its own and
  ; takes its normal error path.
  lda #<SD_RESPONSE_TIMEOUT
  sta sd_timeout
  lda #>SD_RESPONSE_TIMEOUT
  sta sd_timeout+1
@wait:
  jsr sd_readbyte
  cmp #$ff
  bne @got
  jsr sd_counttimeout
  bcc @wait
  lda #$ff
  sec
  rts
@got:
  clc
  rts


sd_counttimeout:
  ; 16 bit decrement of sd_timeout. Returns carry set once it has run out.
  lda sd_timeout
  ora sd_timeout+1
  beq @expired
  lda sd_timeout
  bne @nohigh
  dec sd_timeout+1
@nohigh:
  dec sd_timeout
  clc
  rts
@expired:
  sec
  rts
    
sd_sendcommand:
  ; Debug print which command is being executed
;  jsr lcd_cleardisplay

;  lda #'c'
;  jsr _lcd_print_char
  ldx #0
  lda (zp_sd_address,x)
;  jsr print_hex

  lda #SD_MOSI           ; pull CS low to begin command
  sta SD_PORTB

  ldy #0
  lda (zp_sd_address),y    ; command byte
  jsr sd_writebyte
  ldy #1
  lda (zp_sd_address),y    ; data 1
  jsr sd_writebyte
  ldy #2
  lda (zp_sd_address),y    ; data 2
  jsr sd_writebyte
  ldy #3
  lda (zp_sd_address),y    ; data 3
  jsr sd_writebyte
  ldy #4
  lda (zp_sd_address),y    ; data 4
  jsr sd_writebyte
  ldy #5
  lda (zp_sd_address),y    ; crc
  jsr sd_writebyte

  jsr sd_waitresult
  pha

  ; Debug print the result code
 ; jsr print_hex

  ; End command
  lda #(SD_CS | SD_MOSI)   ; set CS high again
  sta SD_PORTB

  pla   ; restore result code
  rts

sd_readsector:
  ; Read a sector from the SD card.  A sector is 512 bytes.
  ;
  ; Parameters:
  ;    zp_sd_currentsector   32-bit sector number
  ;    zp_sd_address     address of buffer to receive data
  
  lda #SD_MOSI
  sta SD_PORTB

  ; Command 17, arg is sector number, crc not checked
  lda #$51                    ; CMD17 - READ_SINGLE_BLOCK
  jsr sd_writebyte
  lda zp_sd_currentsector+3   ; sector 24:31
  jsr sd_writebyte
  lda zp_sd_currentsector+2   ; sector 16:23
  jsr sd_writebyte
  lda zp_sd_currentsector+1   ; sector 8:15
  jsr sd_writebyte
  lda zp_sd_currentsector     ; sector 0:7
  jsr sd_writebyte
  lda #$01                    ; crc (not checked)
  jsr sd_writebyte

  jsr sd_waitresult
  cmp #$00
  bne @fail

  ; wait for data
  jsr sd_waitresult
  cmp #$fe
  bne @fail

  ; Need to read 512 bytes - two pages of 256 bytes each
  jsr readpage
  inc zp_sd_address+1
  jsr readpage
  dec zp_sd_address+1

  ; End command
  lda #(SD_CS | SD_MOSI)
  sta SD_PORTB

  clc
  rts

@fail:
  ; Release the card and report the failure. This used to spin in an endless
  ; loop, which locked the machine up on any read error.
  lda #(SD_CS | SD_MOSI)
  sta SD_PORTB

  lda #FAT32_ERROR_READ_FAILED
  sta fat32_lasterror

  sec
  rts


readpage:
  ; Read 256 bytes to the address at zp_sd_address
  ldy #0
readloop:
  jsr sd_readbyte
  sta (zp_sd_address),y
  iny
  bne readloop
  rts


sd_writesector:
  ; Write a sector to the SD card.  A sector is 512 bytes.
  ;
  ; Parameters:
  ;    zp_sd_currentsector   32-bit sector number
  ;    zp_sd_address         address of the 512 byte buffer to send
  ;
  ; Returns carry clear on success, carry set on failure.

  lda #SD_MOSI
  sta SD_PORTB

  ; Command 24, arg is sector number, crc not checked
  lda #$58                    ; CMD24 - WRITE_BLOCK
  jsr sd_writebyte
  lda zp_sd_currentsector+3   ; sector 24:31
  jsr sd_writebyte
  lda zp_sd_currentsector+2   ; sector 16:23
  jsr sd_writebyte
  lda zp_sd_currentsector+1   ; sector 8:15
  jsr sd_writebyte
  lda zp_sd_currentsector     ; sector 0:7
  jsr sd_writebyte
  lda #$01                    ; crc (not checked)
  jsr sd_writebyte

  jsr sd_waitresult
  cmp #$00
  bne @fail

  ; At least one idle byte between the response and the data token
  lda #$ff
  jsr sd_writebyte

  ; Data token for a single block write
  lda #$fe
  jsr sd_writebyte

  ; Need to write 512 bytes - two pages of 256 bytes each
  jsr writepage
  inc zp_sd_address+1
  jsr writepage
  dec zp_sd_address+1

  ; Dummy CRC, the card is not checking it
  lda #$ff
  jsr sd_writebyte
  lda #$ff
  jsr sd_writebyte

  ; Data response token is xxx0sss1, where sss = 010 means accepted
  jsr sd_waitresult
  and #$1f
  cmp #$05
  bne @fail

  ; The card holds MISO low for as long as it is programming the block
  jsr sd_waitbusy
  bcs @fail

  ; End command
  lda #(SD_CS | SD_MOSI)
  sta SD_PORTB

  clc
  rts

@fail:
  ; Release the card and report the failure to the caller - unlike the read
  ; path there is no error loop here, the caller decides what to do
  lda #(SD_CS | SD_MOSI)
  sta SD_PORTB

  sec
  rts


writepage:
  ; Write 256 bytes from the address at zp_sd_address
  ; sd_writebyte destroys X and Y, so the index has to be preserved here
  ldy #0
writeloop:
  lda (zp_sd_address),y
  phy
  jsr sd_writebyte
  ply
  iny
  bne writeloop
  rts


sd_waitbusy:
  ; While the card is programming it holds MISO low, so it reads back as $00.
  ; Programming a block takes a while, hence the longer timeout.
  ;
  ; On timeout carry is set.
  lda #<SD_BUSY_TIMEOUT
  sta sd_timeout
  lda #>SD_BUSY_TIMEOUT
  sta sd_timeout+1
@wait:
  jsr sd_readbyte
  cmp #$00
  bne @done
  jsr sd_counttimeout
  bcc @wait
  sec
  rts
@done:
  clc
  rts


print_hex:
  pha
  ror
  ror
  ror
  ror
  jsr print_nybble
  pla
  pha
  jsr print_nybble
  pla
  rts
print_nybble:
  and #15
  cmp #10
  bmi @skipletter
  adc #6
@skipletter:
  adc #48
  jsr _lcd_print_char
  rts

delay:
  ldx #0
  ldy #0
delay_loop:
  dey
  bne delay_loop
  dex
  bne delay_loop
  rts

longdelay:
  jsr mediumdelay
  jsr mediumdelay
  jsr mediumdelay
mediumdelay:
  jsr delay
  jsr delay
  jsr delay
  jmp delay    
  
     .segment "RODATA"
     
sd_cmd0_bytes:
  .byte $40, $00, $00, $00, $00, $95
sd_cmd8_bytes:
  .byte $48, $00, $00, $01, $aa, $87
sd_cmd55_bytes:
  .byte $77, $00, $00, $00, $00, $01
sd_cmd41_bytes:
  .byte $69, $40, $00, $00, $00, $01
  
       
   
SD_initializing:
    .asciiz "Initializing SD..."      
SD_initialized:
    .asciiz "SD initialized"    
SD_not_initialized:
    .asciiz "SD not initialized"       
;FAT32_initializing:
;    .asciiz "Initializing FAT32..."   
        
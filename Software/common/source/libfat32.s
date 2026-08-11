; FAT32/SD interface library
;
; This module requires some RAM workspace to be defined elsewhere:
; 
; fat32_workspace    - a large page-aligned 512-byte workspace
; zp_fat32_variables - 26 bytes of zero-page storage for variables etc



fat32_readbuffer = fat32_workspace

fat32_fatstart          = zp_fat32_variables + $00  ; 4 bytes
fat32_datastart         = zp_fat32_variables + $04  ; 4 bytes
fat32_rootcluster       = zp_fat32_variables + $08  ; 4 bytes
fat32_sectorspercluster = zp_fat32_variables + $0c  ; 1 byte
fat32_pendingsectors    = zp_fat32_variables + $0d  ; 1 byte
fat32_address           = zp_fat32_variables + $0e  ; 2 bytes
fat32_nextcluster       = zp_fat32_variables + $10  ; 4 bytes
fat32_bytesremaining    = zp_fat32_variables + $14  ; 4 bytes
fat32_direntptr         = zp_fat32_variables + $18  ; 2 bytes - needs to be on
                                                    ; the zero page for the
                                                    ; indirect indexed writes
                                                    ; in fat32_writedirent

fat32_errorstage        = fat32_bytesremaining  ; only used during initializatio
fat32_filenamepointer   = fat32_bytesremaining  ; only used when searching for a file

; Error codes reported in fat32_lasterror whenever a routine returns carry set.
; Kept out of the zero page - it is only read after an operation has finished.
FAT32_ERROR_NONE           = 0
FAT32_ERROR_NO_SUCH_FILE   = 1
FAT32_ERROR_FILE_TOO_SMALL = 2
FAT32_ERROR_WRITE_FAILED   = 3
FAT32_ERROR_READ_FAILED    = 4
FAT32_ERROR_NO_CARD        = 5
FAT32_ERROR_DISK_FULL      = 6
FAT32_ERROR_DIR_FULL       = 7

        .segment "BSS"
fat32_lasterror:
        .res 1
fat32_direntsector:
        .res 4          ; sector the remembered directory entry lives in
fat32_newsize:
        .res 4          ; file size to store into that entry

        .code


fat32_init:
  ; Initialize the module - read the MBR etc, find the partition,
  ; and set up the variables ready for navigating the filesystem

  ; Read the MBR and extract pertinent information

  lda #0
  sta fat32_errorstage

  ; Sector 0
  lda #0
  sta zp_sd_currentsector
  sta zp_sd_currentsector+1
  sta zp_sd_currentsector+2
  sta zp_sd_currentsector+3

  ; Target buffer
  lda #<fat32_readbuffer
  sta zp_sd_address
  lda #>fat32_readbuffer
  sta zp_sd_address+1

  ; Do the read
  jsr sd_readsector


  inc fat32_errorstage ; stage 1 = boot sector signature check

  ; Check some things
  lda fat32_readbuffer+510 ; Boot sector signature 55
  cmp #$55
  bne fail
  lda fat32_readbuffer+511 ; Boot sector signature aa
  cmp #$aa
  bne fail


  inc fat32_errorstage ; stage 2 = finding partition

  ; Find a FAT32 partition
FSTYPE_FAT32 = 12
  ldx #0
  lda fat32_readbuffer+$1c2,x
  cmp #FSTYPE_FAT32
  beq foundpart
  ldx #16
  lda fat32_readbuffer+$1c2,x
  cmp #FSTYPE_FAT32
  beq foundpart
  ldx #32
  lda fat32_readbuffer+$1c2,x
  cmp #FSTYPE_FAT32
  beq foundpart
  ldx #48
  lda fat32_readbuffer+$1c2,x
  cmp #FSTYPE_FAT32
  beq foundpart

fail:
  jmp error

foundpart:

  ; Read the FAT32 BPB
  lda fat32_readbuffer+$1c6,x
  sta zp_sd_currentsector
  lda fat32_readbuffer+$1c7,x
  sta zp_sd_currentsector+1
  lda fat32_readbuffer+$1c8,x
  sta zp_sd_currentsector+2
  lda fat32_readbuffer+$1c9,x
  sta zp_sd_currentsector+3

  jsr sd_readsector


  inc fat32_errorstage ; stage 3 = BPB signature check

  ; Check some things
  lda fat32_readbuffer+510 ; BPB sector signature 55
  cmp #$55
  bne fail
  lda fat32_readbuffer+511 ; BPB sector signature aa
  cmp #$aa
  bne fail

  inc fat32_errorstage ; stage 4 = RootEntCnt check

  lda fat32_readbuffer+17 ; RootEntCnt should be 0 for FAT32
  ora fat32_readbuffer+18
  bne fail

  inc fat32_errorstage ; stage 5 = TotSec16 check

  lda fat32_readbuffer+19 ; TotSec16 should be 0 for FAT32
  ora fat32_readbuffer+20
  bne fail

  inc fat32_errorstage ; stage 6 = SectorsPerCluster check

  ; Check bytes per filesystem sector, it should be 512 for any SD card that supports FAT32
  lda fat32_readbuffer+11 ; low byte should be zero
  bne fail
  lda fat32_readbuffer+12 ; high byte is 2 (512), 4, 8, or 16
  cmp #2
  bne fail


  ; Calculate the starting sector of the FAT
  clc
  lda zp_sd_currentsector
  adc fat32_readbuffer+14    ; reserved sectors lo
  sta fat32_fatstart
  sta fat32_datastart
  lda zp_sd_currentsector+1
  adc fat32_readbuffer+15    ; reserved sectors hi
  sta fat32_fatstart+1
  sta fat32_datastart+1
  lda zp_sd_currentsector+2
  adc #0
  sta fat32_fatstart+2
  sta fat32_datastart+2
  lda zp_sd_currentsector+3
  adc #0
  sta fat32_fatstart+3
  sta fat32_datastart+3

  ; Calculate the starting sector of the data area
  ldx fat32_readbuffer+16   ; number of FATs
skipfatsloop:
  clc
  lda fat32_datastart
  adc fat32_readbuffer+36 ; fatsize 0
  sta fat32_datastart
  lda fat32_datastart+1
  adc fat32_readbuffer+37 ; fatsize 1
  sta fat32_datastart+1
  lda fat32_datastart+2
  adc fat32_readbuffer+38 ; fatsize 2
  sta fat32_datastart+2
  lda fat32_datastart+3
  adc fat32_readbuffer+39 ; fatsize 3
  sta fat32_datastart+3
  dex
  bne skipfatsloop

  ; Sectors-per-cluster is a power of two from 1 to 128
  lda fat32_readbuffer+13
  sta fat32_sectorspercluster

  ; Remember the root cluster
  lda fat32_readbuffer+44
  sta fat32_rootcluster
  lda fat32_readbuffer+45
  sta fat32_rootcluster+1
  lda fat32_readbuffer+46
  sta fat32_rootcluster+2
  lda fat32_readbuffer+47
  sta fat32_rootcluster+3

  clc
  rts

error:
  sec
  rts


fat32_seekcluster:
  ; Gets ready to read fat32_nextcluster, and advances it according to the FAT
  
  ; FAT sector = (cluster*4) / 512 = (cluster*2) / 256
  lda fat32_nextcluster
  asl
  lda fat32_nextcluster+1
  rol
  sta zp_sd_currentsector
  lda fat32_nextcluster+2
  rol
  sta zp_sd_currentsector+1
  lda fat32_nextcluster+3
  rol
  sta zp_sd_currentsector+2
  ; note: cluster numbers never have the top bit set, so no carry can occur

  ; Add FAT starting sector
  lda zp_sd_currentsector
  adc fat32_fatstart
  sta zp_sd_currentsector
  lda zp_sd_currentsector+1
  adc fat32_fatstart+1
  sta zp_sd_currentsector+1
  lda zp_sd_currentsector+2
  adc fat32_fatstart+2
  sta zp_sd_currentsector+2
  lda #0
  adc fat32_fatstart+3
  sta zp_sd_currentsector+3

  ; Target buffer
  lda #<fat32_readbuffer
  sta zp_sd_address
  lda #>fat32_readbuffer
  sta zp_sd_address+1

  ; Read the sector from the FAT
  jsr sd_readsector

  ; Before using this FAT data, set currentsector ready to read the cluster itself
  ; We need to multiply the cluster number minus two by the number of sectors per 
  ; cluster, then add the data region start sector

  ; Subtract two from cluster number
  sec
  lda fat32_nextcluster
  sbc #2
  sta zp_sd_currentsector
  lda fat32_nextcluster+1
  sbc #0
  sta zp_sd_currentsector+1
  lda fat32_nextcluster+2
  sbc #0
  sta zp_sd_currentsector+2
  lda fat32_nextcluster+3
  sbc #0
  sta zp_sd_currentsector+3
  
  ; Multiply by sectors-per-cluster which is a power of two between 1 and 128
  lda fat32_sectorspercluster
spcshiftloop:
  lsr
  bcs spcshiftloopdone
  asl zp_sd_currentsector
  rol zp_sd_currentsector+1
  rol zp_sd_currentsector+2
  rol zp_sd_currentsector+3
  jmp spcshiftloop
spcshiftloopdone:

  ; Add the data region start sector
  clc
  lda zp_sd_currentsector
  adc fat32_datastart
  sta zp_sd_currentsector
  lda zp_sd_currentsector+1
  adc fat32_datastart+1
  sta zp_sd_currentsector+1
  lda zp_sd_currentsector+2
  adc fat32_datastart+2
  sta zp_sd_currentsector+2
  lda zp_sd_currentsector+3
  adc fat32_datastart+3
  sta zp_sd_currentsector+3

  ; That's now ready for later code to read this sector in - tell it how many consecutive
  ; sectors it can now read
  lda fat32_sectorspercluster
  sta fat32_pendingsectors

  ; Now go back to looking up the next cluster in the chain
  ; Find the offset to this cluster's entry in the FAT sector we loaded earlier

  ; Offset = (cluster*4) & 511 = (cluster & 127) * 4
  lda fat32_nextcluster
  and #$7f
  asl
  asl
  tay ; Y = low byte of offset

  ; Add the potentially carried bit to the high byte of the address
  lda zp_sd_address+1
  adc #0
  sta zp_sd_address+1

  ; Copy out the next cluster in the chain for later use
  lda (zp_sd_address),y
  sta fat32_nextcluster
  iny
  lda (zp_sd_address),y
  sta fat32_nextcluster+1
  iny
  lda (zp_sd_address),y
  sta fat32_nextcluster+2
  iny
  lda (zp_sd_address),y
  and #$0f
  sta fat32_nextcluster+3

  ; See if it's the end of the chain
  ora #$f0
  and fat32_nextcluster+2
  and fat32_nextcluster+1
  cmp #$ff
  bne notendofchain
  lda fat32_nextcluster
  cmp #$f8
  bcc notendofchain

  ; It's the end of the chain, set the top bits so that we can tell this later on
  sta fat32_nextcluster+3
notendofchain:

  rts


fat32_readnextsector:
  ; Reads the next sector from a cluster chain into the buffer at fat32_address.
  ;
  ; Advances the current sector ready for the next read and looks up the next cluster
  ; in the chain when necessary.
  ;
  ; On return, carry is clear if data was read, or set if the cluster chain has ended.

  ; Maybe there are pending sectors in the current cluster
  lda fat32_pendingsectors
  bne readsector

  ; No pending sectors, check for end of cluster chain
  lda fat32_nextcluster+3
  bmi endofchain

  ; Prepare to read the next cluster
  jsr fat32_seekcluster

readsector:
  dec fat32_pendingsectors

  ; Set up target address  
  lda fat32_address
  sta zp_sd_address
  lda fat32_address+1
  sta zp_sd_address+1

  ; Read the sector
  jsr sd_readsector

  ; Advance to next sector
  inc zp_sd_currentsector
  bne sectorincrementdone
  inc zp_sd_currentsector+1
  bne sectorincrementdone
  inc zp_sd_currentsector+2
  bne sectorincrementdone
  inc zp_sd_currentsector+3
sectorincrementdone:

  ; Success - clear carry and return
  clc
  rts

endofchain:
  ; End of chain - set carry and return
  sec
  rts


fat32_openroot:
  ; Prepare to read the root directory

  lda fat32_rootcluster
  sta fat32_nextcluster
  lda fat32_rootcluster+1
  sta fat32_nextcluster+1
  lda fat32_rootcluster+2
  sta fat32_nextcluster+2
  lda fat32_rootcluster+3
  sta fat32_nextcluster+3

  jsr fat32_seekcluster

  ; Set the pointer to a large value so we always read a sector the first time through
  lda #$ff
  sta zp_sd_address+1

  rts


fat32_opendirent:
  ; Prepare to read from a file or directory based on a dirent
  ;
  ; Point zp_sd_address at the dirent

  ; Remember file size in bytes remaining
  ldy #28
  lda (zp_sd_address),y
  sta fat32_bytesremaining
  iny
  lda (zp_sd_address),y
  sta fat32_bytesremaining+1
  iny
  lda (zp_sd_address),y
  sta fat32_bytesremaining+2
  iny
  lda (zp_sd_address),y
  sta fat32_bytesremaining+3

  ; Seek to first cluster
  ldy #26
  lda (zp_sd_address),y
  sta fat32_nextcluster
  iny
  lda (zp_sd_address),y
  sta fat32_nextcluster+1
  ldy #20
  lda (zp_sd_address),y
  sta fat32_nextcluster+2
  iny
  lda (zp_sd_address),y
  sta fat32_nextcluster+3

  jsr fat32_seekcluster

  ; Set the pointer to a large value so we always read a sector the first time through
  lda #$ff
  sta zp_sd_address+1

  rts


fat32_readdirent:
  ; Read a directory entry from the open directory
  ;
  ; On exit the carry is set if there were no more directory entries.
  ;
  ; Otherwise, A is set to the file's attribute byte and
  ; zp_sd_address points at the returned directory entry.
  ; LFNs and empty entries are ignored automatically.

  ; Increment pointer by 32 to point to next entry
  clc
  lda zp_sd_address
  adc #32
  sta zp_sd_address
  lda zp_sd_address+1
  adc #0
  sta zp_sd_address+1

  ; If it's not at the end of the buffer, we have data already
  cmp #>(fat32_readbuffer+$200)
  bcc gotdata1

  ; Read another sector
  lda #<fat32_readbuffer
  sta fat32_address
  lda #>fat32_readbuffer
  sta fat32_address+1

  jsr fat32_readnextsector
  bcc gotdata1

endofdirectory:
  sec
  rts

gotdata1:
  ; Check first character
  ldy #0
  lda (zp_sd_address),y

  ; End of directory => abort
  beq endofdirectory

  ; Empty entry => start again
  cmp #$e5
  beq fat32_readdirent

  ; Check attributes
  ldy #11
  lda (zp_sd_address),y
  and #$3f
  cmp #$0f ; LFN => start again
  beq fat32_readdirent

  ; Yield this result
  clc
  rts


fat32_finddirent:
  ; Finds a particular directory entry.  X,Y point to the 11-character filename to seek.
  ; The directory should already be open for iteration.

  ; Form ZP pointer to user's filename
  stx fat32_filenamepointer
  sty fat32_filenamepointer+1
  
  ; Iterate until name is found or end of directory
direntloop:
  jsr fat32_readdirent
  ldy #10
  bcc comparenameloop
  rts ; with carry set

comparenameloop:
  lda (zp_sd_address),y
  cmp (fat32_filenamepointer),y
  bne direntloop ; no match
  dey
  bpl comparenameloop

  ; Found it
  clc
  rts


fat32_file_readbyte:
  ; Read a byte from an open file
  ;
  ; The byte is returned in A with C clear; or if end-of-file was reached, C is set instead

  sec

  ; Is there any data to read at all?
  lda fat32_bytesremaining
  ora fat32_bytesremaining+1
  ora fat32_bytesremaining+2
  ora fat32_bytesremaining+3
  beq _rts

  ; Decrement the remaining byte count
  lda fat32_bytesremaining
  sbc #1
  sta fat32_bytesremaining
  lda fat32_bytesremaining+1
  sbc #0
  sta fat32_bytesremaining+1
  lda fat32_bytesremaining+2
  sbc #0
  sta fat32_bytesremaining+2
  lda fat32_bytesremaining+3
  sbc #0
  sta fat32_bytesremaining+3
  
  ; Need to read a new sector?
  lda zp_sd_address+1
  cmp #>(fat32_readbuffer+$200)
  bcc gotdata2

  ; Read another sector
  lda #<fat32_readbuffer
  sta fat32_address
  lda #>fat32_readbuffer
  sta fat32_address+1

  jsr fat32_readnextsector
  bcs _rts                    ; this shouldn't happen

gotdata2:
  ldy #0
  lda (zp_sd_address),y

  inc zp_sd_address
  bne _rts
  inc zp_sd_address+1
  bne _rts
  inc zp_sd_address+2
  bne _rts
  inc zp_sd_address+3

_rts:
  rts


fat32_file_read:
  ; Read a whole file into memory.  It's assumed the file has just been opened 
  ; and no data has been read yet.
  ;
  ; Also we read whole sectors, so data in the target region beyond the end of the 
  ; file may get overwritten, up to the next 512-byte boundary.
  ;
  ; And we don't properly support 64k+ files, as it's unnecessary complication given
  ; the 6502's small address space

  ; Round the size up to the next whole sector
  lda fat32_bytesremaining
  cmp #1                      ; set carry if bottom 8 bits not zero
  lda fat32_bytesremaining+1
  adc #0                      ; add carry, if any
  lsr                         ; divide by 2
  adc #0                      ; round up

  ; No data?
  beq _done

  ; Store sector count - not a byte count any more
  sta fat32_bytesremaining

  ; Read entire sectors to the user-supplied buffer
wholesectorreadloop:
  ; Read a sector to fat32_address
  jsr fat32_readnextsector

  ; Advance fat32_address by 512 bytes
  lda fat32_address+1
  adc #2                      ; carry already clear
  sta fat32_address+1

  ldx fat32_bytesremaining    ; note - actually loads sectors remaining
  dex
  stx fat32_bytesremaining    ; note - actually stores sectors remaining

  bne wholesectorreadloop

_done:
  rts


; ---------------------------------------------------------------------------
; Write support, in place
;
; These routines only ever write into clusters that are already allocated to
; the file - they never touch the FAT and never create directory entries. A
; bug in here can therefore damage the target file, but not the filesystem
; structure.
;
; Creating and growing files is a separate, later addition and lives at the
; end of this file, in the SDCODE block.
; ---------------------------------------------------------------------------

fat32_writenextsector:
  ; Writes the next sector of a cluster chain from the buffer at fat32_address.
  ;
  ; Mirror of fat32_readnextsector: it walks the chain that is already
  ; allocated to the file and stops when that chain ends.
  ;
  ; On return, carry is clear if the sector was written. Carry set means the
  ; write failed; fat32_lasterror says which case it was.

  ; Maybe there are pending sectors in the current cluster
  lda fat32_pendingsectors
  bne @writesector

  ; No pending sectors, check for end of cluster chain
  lda fat32_nextcluster+3
  bmi @endofchain

  ; Prepare to write to the next cluster
  jsr fat32_seekcluster

@writesector:
  dec fat32_pendingsectors

  ; Set up source address
  lda fat32_address
  sta zp_sd_address
  lda fat32_address+1
  sta zp_sd_address+1

  ; Write the sector
  jsr sd_writesector
  bcs @cardfailed

  ; Advance to next sector
  inc zp_sd_currentsector
  bne @sectorincrementdone
  inc zp_sd_currentsector+1
  bne @sectorincrementdone
  inc zp_sd_currentsector+2
  bne @sectorincrementdone
  inc zp_sd_currentsector+3
@sectorincrementdone:

  ; Success - clear carry and return
  clc
  rts

@endofchain:
  ; The file is not big enough to hold what the caller wants to write
  lda #FAT32_ERROR_FILE_TOO_SMALL
  sta fat32_lasterror
  sec
  rts

@cardfailed:
  lda #FAT32_ERROR_WRITE_FAILED
  sta fat32_lasterror
  sec
  rts


fat32_markdirent:
  ; Remembers where the directory entry currently pointed at by zp_sd_address
  ; lives, so that fat32_writedirent can update it later.
  ;
  ; Call this straight after fat32_finddirent succeeds, before anything else
  ; touches the buffer or the current sector.

  lda zp_sd_address
  sta fat32_direntptr
  lda zp_sd_address+1
  sta fat32_direntptr+1

  ; fat32_readnextsector has already advanced past the sector the entry was
  ; read from, so step back one
  sec
  lda zp_sd_currentsector
  sbc #1
  sta fat32_direntsector
  lda zp_sd_currentsector+1
  sbc #0
  sta fat32_direntsector+1
  lda zp_sd_currentsector+2
  sbc #0
  sta fat32_direntsector+2
  lda zp_sd_currentsector+3
  sbc #0
  sta fat32_direntsector+3

  rts


fat32_writedirent:
  ; Stores fat32_newsize into the size field of the remembered directory entry
  ; and writes that sector back to the card.
  ;
  ; On return, carry is clear on success.

  ; Re-read the sector holding the entry. By the time this is called the buffer
  ; normally holds FAT data instead, because fat32_seekcluster reuses it.
  ; Reading it back to the same buffer puts the entry at the same address, so
  ; fat32_direntptr stays valid.
  lda #<fat32_readbuffer
  sta zp_sd_address
  lda #>fat32_readbuffer
  sta zp_sd_address+1

  lda fat32_direntsector
  sta zp_sd_currentsector
  lda fat32_direntsector+1
  sta zp_sd_currentsector+1
  lda fat32_direntsector+2
  sta zp_sd_currentsector+2
  lda fat32_direntsector+3
  sta zp_sd_currentsector+3

  jsr sd_readsector

  ldy #28
  lda fat32_newsize
  sta (fat32_direntptr),y
  iny
  lda fat32_newsize+1
  sta (fat32_direntptr),y
  iny
  lda fat32_newsize+2
  sta (fat32_direntptr),y
  iny
  lda fat32_newsize+3
  sta (fat32_direntptr),y

  ; Write the whole sector back. sd_readsector left zp_sd_address and
  ; zp_sd_currentsector untouched, so they still point at the right place.
  jsr sd_writesector
  bcc @ok
  lda #FAT32_ERROR_WRITE_FAILED
  sta fat32_lasterror
  sec
  rts
@ok:
  clc
  rts


fat32_file_write:
  ; Write a whole file from memory into the clusters already allocated to it.
  ;
  ; Parameters:
  ;    fat32_address        source buffer
  ;    fat32_bytesremaining number of bytes to write
  ;
  ; Whole sectors are written, so up to 511 bytes past the end of the data are
  ; written out as well - the size stored in the directory entry is what makes
  ; the file the right length.
  ;
  ; On return, carry is clear on success.

  ; Round the size up to the next whole sector
  lda fat32_bytesremaining
  cmp #1                      ; set carry if bottom 8 bits not zero
  lda fat32_bytesremaining+1
  adc #0                      ; add carry, if any
  lsr                         ; divide by 2
  adc #0                      ; round up

  ; No data?
  beq @done

  ; Store sector count - not a byte count any more
  sta fat32_bytesremaining

@wholesectorwriteloop:
  ; Write a sector from fat32_address
  jsr fat32_writenextsector
  bcs @failed

  ; Advance fat32_address by 512 bytes
  clc
  lda fat32_address+1
  adc #2
  sta fat32_address+1

  ldx fat32_bytesremaining    ; note - actually loads sectors remaining
  dex
  stx fat32_bytesremaining    ; note - actually stores sectors remaining

  bne @wholesectorwriteloop

@done:
  clc
  rts

@failed:
  ; fat32_lasterror was set by fat32_writenextsector
  sec
  rts


; ---------------------------------------------------------------------------
; Write support, allocating
;
; Everything below can create a directory entry and hand out clusters, so it
; writes to the FAT itself and a bug in here can damage the filesystem, not
; just one file.
;
; It sits in the SDCODE block rather than in CODE. This board loses the VDP
; picture as soon as the library modules behind msbasic.o move, so CODE has to
; stay byte for byte where it is - see MEMORY_MAP.md, section "SDCODE". That is
; also why nothing above this line is touched: fat32_init keeps only what
; reading needs, and fat32_readbpb below picks the missing fields out of the
; MBR and the BPB again instead of having fat32_init remember them.
;
; The machine has no clock, so entries get a fixed but valid timestamp rather
; than the all-zero field that some tools flag.
; ---------------------------------------------------------------------------

; Midday rather than midnight: a PC in a timezone west of here would otherwise
; show the entry as the day before.
FAT32_DATE = ((2026 - 1980) << 9) | (1 << 5) | 1        ; 2026-01-01
FAT32_TIME = (12 << 11)                                 ; 12:00:00

.macro  f32copy dst, src
        lda src
        sta dst
        lda src+1
        sta dst+1
        lda src+2
        sta dst+2
        lda src+3
        sta dst+3
.endmacro

.macro  f32zero dst
        stz dst
        stz dst+1
        stz dst+2
        stz dst+3
.endmacro

; Not in BSS, for the same reason the body is not in CODE. Adding to BSS moves
; every variable behind it, and this module is the last one that contributes -
; so all of sd.s's variables would shift and the code that reads them would be
; assembled with different operands. BASBUF is the bottom of the page below
; INPUTBUFFER, which nothing else uses; it already holds the BASIC side of this
; and has well over a hundred bytes to spare.
        .segment "BASBUF"
fat32_partstart:        .res 4  ; first sector of the FAT32 partition
fat32_fatsize:          .res 4  ; sectors in one copy of the FAT
fat32_fsinfosector:     .res 4  ; absolute sector holding the FSInfo block
fat32_maxcluster:       .res 4  ; highest cluster number the volume really has
fat32_numfats:          .res 1  ; number of copies of the FAT
fat32_fatcluster:       .res 4  ; cluster whose FAT entry is being worked on
fat32_fatvalue:         .res 4  ; value read from or written to that entry
fat32_fatoffset:        .res 1  ; offset of the entry in its sector, low byte
fat32_fatoffhigh:       .res 1  ; ... and its 256 byte page
fat32_scancluster:      .res 4  ; where the search for a free cluster carries on
fat32_firstcluster:     .res 4  ; first cluster of the file being written
fat32_currentcluster:   .res 4  ; cluster the last sector went into
fat32_chainnext:        .res 4  ; scratch for a cluster number in transit
fat32_nameptr:          .res 2  ; caller's 11 character FAT name
fat32_freeclusters:     .res 4  ; free cluster count, kept in step as we go
fat32_freevalid:        .res 1  ; ... but only if the card had a usable one
sd_freeblocks:          .res 4  ; free space in 512 byte blocks, for LOAD "$"

        .segment "SDCODE"

; Several routines below index into the workspace with an 8 bit Y plus a page
; carry, exactly the way fat32_seekcluster does. That only lands on the right
; byte if the buffer starts on a page boundary.
        .assert (<fat32_readbuffer) = 0, lderror, "fat32_workspace must be page aligned"

; ---------------------------------------------------------------------------
; Public entry points
; ---------------------------------------------------------------------------

_sd_mount:
        ; Brings the card up from nothing: the same sequence _sd_init runs at
        ; power-on, without the LCD progress line.
        ;
        ; LOAD and SAVE call this every time instead of trusting what the last
        ; access saw. A card put in after the machine was switched on then
        ; simply works, one that was taken out and put back comes straight
        ; back, and - the reason this is not just an "if it failed last time"
        ; check - a card that was swapped for a different one cannot have its
        ; predecessor's layout applied to it. For SAVE that would mean writing
        ; over whatever happens to live at those sector numbers.
        ;
        ; sd_init resets the card to idle and SPI mode, so running it on a card
        ; that is already up is exactly the same sequence, not a special case.
        stz sd_ready
        jsr sd_init
        bcs @nocard
        jsr fat32_init
        bcs @nocard
        lda #$01
        sta sd_ready
        clc
        rts

@nocard:
        lda #FAT32_ERROR_NO_CARD
        sta fat32_lasterror
        sec
        rts


_sd_beginsave:
        ; Opens the file whose 11 character FAT name is pointed at by A/X for
        ; writing, creating it in the root directory if it is not there yet.
        ;
        ; Whatever clusters the file had are released first, so the write that
        ; follows always builds a fresh chain and the file ends up exactly as
        ; long as what was written - no leftover tail, no size that disagrees
        ; with the chain.
        ;
        ; On return carry is clear. Carry set means nothing was changed on the
        ; card, apart from the empty entry a creation may have left behind.
        sta fat32_nameptr
        stx fat32_nameptr+1

        lda sd_ready
        beq @nocard

        ; Re-reads the MBR and the BPB, which _sd_mount has just been through
        ; as well. Two sectors twice over is not worth another flag: fat32_init
        ; is in CODE and cannot be extended to keep the extra fields.
        jsr fat32_readbpb
        bcs @fail
        jsr fat32_readfsinfo

        jsr fat32_openroot

        ldx fat32_nameptr
        ldy fat32_nameptr+1
        jsr fat32_finddirent
        bcs @create

        jsr fat32_markdirent

        ; Release the clusters the old contents were using
        ldy #26
        lda (zp_sd_address),y
        sta fat32_fatcluster
        iny
        lda (zp_sd_address),y
        sta fat32_fatcluster+1
        ldy #20
        lda (zp_sd_address),y
        sta fat32_fatcluster+2
        iny
        lda (zp_sd_address),y
        and #$0f
        sta fat32_fatcluster+3
        jsr fat32_freechain
        bcs @fail
        bra @ready

@create:
        jsr fat32_createdirent
        bcs @fail

@ready:
        f32zero fat32_firstcluster
        f32zero fat32_currentcluster
        stz fat32_pendingsectors

        ; Cluster numbering starts at two - nothing below that exists
        lda #$02
        sta fat32_scancluster
        stz fat32_scancluster+1
        stz fat32_scancluster+2
        stz fat32_scancluster+3

        clc
        rts

@nocard:
        lda #FAT32_ERROR_NO_CARD
        sta fat32_lasterror
@fail:
        sec
        rts


_sd_putnext:
        ; Writes the 512 bytes at A/X as the next sector of the file opened by
        ; _sd_beginsave, taking another cluster off the free list whenever the
        ; current one is used up.
        sta fat32_address
        stx fat32_address+1

        lda fat32_pendingsectors
        bne @write
        jsr fat32_growfile
        bcs @fail

@write:
        dec fat32_pendingsectors

        lda fat32_address
        sta zp_sd_address
        lda fat32_address+1
        sta zp_sd_address+1
        jsr sd_writesector
        bcs @cardfailed

        inc zp_sd_currentsector
        bne @done
        inc zp_sd_currentsector+1
        bne @done
        inc zp_sd_currentsector+2
        bne @done
        inc zp_sd_currentsector+3
@done:
        clc
        rts

@cardfailed:
        lda #FAT32_ERROR_WRITE_FAILED
        sta fat32_lasterror
@fail:
        sec
        rts


_sd_endsave:
        ; Finishes the file off: sd_length becomes its size, the chain that was
        ; built along the way becomes its contents.
        f32copy fat32_newsize, sd_length
        jmp fat32_writeentry


_sd_abortsave:
        ; Called instead of _sd_endsave when the transfer failed. The chain
        ; written so far is incomplete and nothing references it yet, so give
        ; it back and leave an empty file behind rather than clusters that only
        ; a chkdsk would find again.
        ;
        ; Whatever went wrong is what the caller is about to report, so the
        ; error code survives this.
        lda fat32_lasterror
        pha

        f32copy fat32_fatcluster, fat32_firstcluster
        jsr fat32_freechain
        f32zero fat32_firstcluster
        f32zero fat32_newsize
        jsr fat32_writeentry

        pla
        sta fat32_lasterror
        rts


; ---------------------------------------------------------------------------
; Stores the first cluster, the size and a write timestamp in the directory
; entry that _sd_beginsave remembered, then brings the FSInfo block back in
; line.
;
; The entry's sector is read back in first: by now the workspace holds FAT data
; instead, because everything in between reuses it. It lands at the same
; address, so fat32_direntptr still points at the right entry.
; ---------------------------------------------------------------------------
fat32_writeentry:
        jsr fat32_bufferaddress
        f32copy zp_sd_currentsector, fat32_direntsector
        jsr sd_readsector
        bcs @fail

        ldy #20                         ; first cluster, high word
        lda fat32_firstcluster+2
        sta (fat32_direntptr),y
        iny
        lda fat32_firstcluster+3
        sta (fat32_direntptr),y

        ldy #22                         ; last write time and date
        lda #<FAT32_TIME
        sta (fat32_direntptr),y
        iny
        lda #>FAT32_TIME
        sta (fat32_direntptr),y
        iny
        lda #<FAT32_DATE
        sta (fat32_direntptr),y
        iny
        lda #>FAT32_DATE
        sta (fat32_direntptr),y

        ldy #26                         ; first cluster, low word
        lda fat32_firstcluster
        sta (fat32_direntptr),y
        iny
        lda fat32_firstcluster+1
        sta (fat32_direntptr),y

        ldy #28                         ; size in bytes
        lda fat32_newsize
        sta (fat32_direntptr),y
        iny
        lda fat32_newsize+1
        sta (fat32_direntptr),y
        iny
        lda fat32_newsize+2
        sta (fat32_direntptr),y
        iny
        lda fat32_newsize+3
        sta (fat32_direntptr),y

        jsr fat32_bufferaddress
        jsr sd_writesector
        bcs @writefail

        jmp fat32_fsinfowrite

@writefail:
        lda #FAT32_ERROR_WRITE_FAILED
        sta fat32_lasterror
@fail:
        sec
        rts


        .segment "EXTCODE"

; ---------------------------------------------------------------------------
; Puts the free cluster count back into the FSInfo block.
;
; The count is carried along by fat32_freedown and fat32_freeup as clusters are
; taken and given back, so what goes in here is the real figure - which is what
; lets LOAD "$" end with a BLOCKS FREE line without reading the whole FAT. If
; the card did not arrive with a usable count, both fields go back as the
; "unknown" marker the specification provides, and a PC works them out again.
;
; A block that does not carry both signatures is left alone - its sector number
; came out of the BPB and may well be pointing at something else. A card that
; refuses the update is not worth failing the save over either: the file itself
; is already complete and correct at this point.
; ---------------------------------------------------------------------------
fat32_fsinfowrite:
        jsr fat32_fsinfoload
        bcs @out

        lda fat32_freevalid
        beq @unknown

        f32copy fat32_readbuffer+488, fat32_freeclusters
        lda #$ff                        ; the search hint stays unknown
        ldx #$03
@hint:
        sta fat32_readbuffer+492,x
        dex
        bpl @hint
        bra @put

@unknown:
        lda #$ff
        ldx #$07
@both:
        sta fat32_readbuffer+488,x
        dex
        bpl @both

@put:
        jsr fat32_bufferaddress
        jsr sd_writesector

@out:
        clc
        rts


; ---------------------------------------------------------------------------
; Reads the FSInfo block into the workspace. Carry set if it is not there or
; does not look like one.
; ---------------------------------------------------------------------------
fat32_fsinfoload:
        jsr fat32_bufferaddress
        f32copy zp_sd_currentsector, fat32_fsinfosector
        jsr sd_readsector
        bcs @no

        ldy #$03                        ; "RRaA"
@lead:
        lda fat32_readbuffer,y
        cmp fat32_fsinfolead,y
        bne @no
        dey
        bpl @lead

        ldy #$03                        ; "rrAa"
@struct:
        lda fat32_readbuffer+484,y
        cmp fat32_fsinfostruct,y
        bne @no
        dey
        bpl @struct

        clc
        rts
@no:
        sec
        rts


; ---------------------------------------------------------------------------
; Picks up the free cluster count so it can be kept in step from here on.
;
; A count of $ffffffff means nobody has worked it out, and one larger than the
; volume has clusters means it cannot be trusted. Either way fat32_freevalid
; stays clear, nothing is maintained, and what goes back at the end is the
; "unknown" marker again.
; ---------------------------------------------------------------------------
fat32_readfsinfo:
        stz fat32_freevalid
        jsr fat32_fsinfoload
        bcs @out

        f32copy fat32_freeclusters, fat32_readbuffer+488

        lda fat32_freeclusters
        and fat32_freeclusters+1
        and fat32_freeclusters+2
        and fat32_freeclusters+3
        cmp #$ff
        beq @out                        ; the "not known" marker

        sec
        lda fat32_maxcluster
        sbc fat32_freeclusters
        lda fat32_maxcluster+1
        sbc fat32_freeclusters+1
        lda fat32_maxcluster+2
        sbc fat32_freeclusters+2
        lda fat32_maxcluster+3
        sbc fat32_freeclusters+3
        bcc @out                        ; more free than the volume holds

        lda #$01
        sta fat32_freevalid
@out:
        clc
        rts


; One cluster fewer, one cluster more. Both do nothing while the count is not
; being maintained, so the callers need no special case.
fat32_freedown:
        lda fat32_freevalid
        beq @out
        lda fat32_freeclusters
        bne @low
        lda fat32_freeclusters+1
        bne @mid
        lda fat32_freeclusters+2
        bne @high
        dec fat32_freeclusters+3
@high:
        dec fat32_freeclusters+2
@mid:
        dec fat32_freeclusters+1
@low:
        dec fat32_freeclusters
@out:
        rts

fat32_freeup:
        lda fat32_freevalid
        beq @out
        inc fat32_freeclusters
        bne @out
        inc fat32_freeclusters+1
        bne @out
        inc fat32_freeclusters+2
        bne @out
        inc fat32_freeclusters+3
@out:
        rts


; ---------------------------------------------------------------------------
; Free space in 512 byte blocks, in sd_freeblocks, for the line LOAD "$" ends
; on. Carry set means the card keeps no count worth printing.
; ---------------------------------------------------------------------------
_sd_freeblocks:
        lda sd_ready
        beq @unknown
        jsr fat32_readbpb
        bcs @unknown
        jsr fat32_readfsinfo
        lda fat32_freevalid
        beq @unknown

        f32copy sd_freeblocks, fat32_freeclusters
        lda fat32_sectorspercluster
@shift:
        lsr
        bcs @done
        asl sd_freeblocks
        rol sd_freeblocks+1
        rol sd_freeblocks+2
        rol sd_freeblocks+3
        bra @shift
@done:
        clc
        rts

@unknown:
        sec
        rts

fat32_fsinfolead:
        .byte $52, $52, $61, $41
fat32_fsinfostruct:
        .byte $72, $72, $41, $61

        .segment "SDCODE"

; ---------------------------------------------------------------------------
; Re-reads the MBR and the BPB and works out what allocation needs and
; fat32_init does not keep: where the partition starts, how big and how many
; the FATs are, where the FSInfo block is, and the highest cluster number the
; volume actually has.
;
; That last one matters: the tail of the FAT past the last real cluster reads
; back as free, and handing one of those out would put file data beyond the end
; of the partition.
; ---------------------------------------------------------------------------
fat32_readbpb:
        f32zero zp_sd_currentsector
        jsr fat32_bufferaddress
        jsr sd_readsector
        bcs @fail
        jsr fat32_checkbootsig
        bcs @bad

        ; The same four partition slots fat32_init looks at
        ldx #0
        lda fat32_readbuffer+$1c2,x
        cmp #FSTYPE_FAT32
        beq @found
        ldx #16
        lda fat32_readbuffer+$1c2,x
        cmp #FSTYPE_FAT32
        beq @found
        ldx #32
        lda fat32_readbuffer+$1c2,x
        cmp #FSTYPE_FAT32
        beq @found
        ldx #48
        lda fat32_readbuffer+$1c2,x
        cmp #FSTYPE_FAT32
        bne @bad

@found:
        lda fat32_readbuffer+$1c6,x
        sta fat32_partstart
        sta zp_sd_currentsector
        lda fat32_readbuffer+$1c7,x
        sta fat32_partstart+1
        sta zp_sd_currentsector+1
        lda fat32_readbuffer+$1c8,x
        sta fat32_partstart+2
        sta zp_sd_currentsector+2
        lda fat32_readbuffer+$1c9,x
        sta fat32_partstart+3
        sta zp_sd_currentsector+3

        jsr fat32_bufferaddress
        jsr sd_readsector
        bcs @fail
        jsr fat32_checkbootsig
        bcs @bad

        lda fat32_readbuffer+16         ; number of FATs
        bne @bpbok

        ; The two exits sit here, in the middle of the routine, so that every
        ; branch above can still reach them
@bad:
        lda #FAT32_ERROR_READ_FAILED
        sta fat32_lasterror
@fail:
        sec
        rts

@bpbok:
        sta fat32_numfats

        f32copy fat32_fatsize, fat32_readbuffer+36

        ; FSInfo sector, counted from the start of the partition
        clc
        lda fat32_partstart
        adc fat32_readbuffer+48
        sta fat32_fsinfosector
        lda fat32_partstart+1
        adc fat32_readbuffer+49
        sta fat32_fsinfosector+1
        lda fat32_partstart+2
        adc #0
        sta fat32_fsinfosector+2
        lda fat32_partstart+3
        adc #0
        sta fat32_fsinfosector+3

        ; Highest valid cluster number. fat32_datastart is absolute, the total
        ; sector count is not, hence the detour through fat32_partstart:
        ;   (total sectors - sectors ahead of the data area) / sectors per
        ;   cluster, plus one, because the first cluster is number two.
        f32copy fat32_maxcluster, fat32_readbuffer+32
        sec
        lda fat32_maxcluster
        sbc fat32_datastart
        sta fat32_maxcluster
        lda fat32_maxcluster+1
        sbc fat32_datastart+1
        sta fat32_maxcluster+1
        lda fat32_maxcluster+2
        sbc fat32_datastart+2
        sta fat32_maxcluster+2
        lda fat32_maxcluster+3
        sbc fat32_datastart+3
        sta fat32_maxcluster+3
        clc
        lda fat32_maxcluster
        adc fat32_partstart
        sta fat32_maxcluster
        lda fat32_maxcluster+1
        adc fat32_partstart+1
        sta fat32_maxcluster+1
        lda fat32_maxcluster+2
        adc fat32_partstart+2
        sta fat32_maxcluster+2
        lda fat32_maxcluster+3
        adc fat32_partstart+3
        sta fat32_maxcluster+3

        ; Sectors-per-cluster is a power of two, so the division is a shift
        lda fat32_sectorspercluster
@spcshift:
        lsr
        bcs @spcdone
        lsr fat32_maxcluster+3
        ror fat32_maxcluster+2
        ror fat32_maxcluster+1
        ror fat32_maxcluster
        bra @spcshift
@spcdone:
        inc fat32_maxcluster
        bne @done
        inc fat32_maxcluster+1
        bne @done
        inc fat32_maxcluster+2
        bne @done
        inc fat32_maxcluster+3
@done:
        clc
        rts


fat32_checkbootsig:
        ; Carry clear if the sector in the workspace ends in the $aa55 marker
        ; that both the MBR and the BPB carry
        lda fat32_readbuffer+510
        cmp #$55
        bne @no
        lda fat32_readbuffer+511
        cmp #$aa
        bne @no
        clc
        rts
@no:
        sec
        rts


; ---------------------------------------------------------------------------
; Fills in the free slot the failed directory search stopped on, and writes it
; out straight away - so the file exists as an empty one even if the data that
; was meant to go in it never makes it to the card.
;
; fat32_readdirent stops on the first entry whose name starts with a zero byte
; and leaves zp_sd_address pointing at it, which is exactly the slot wanted
; here. If it ran off the end of the directory instead, that pointer is past
; the workspace - which is what the range check below is looking for.
;
; The name comes from fat32_filenamepointer, still set up by fat32_finddirent.
; ---------------------------------------------------------------------------
fat32_createdirent:
        lda zp_sd_address+1
        cmp #>fat32_readbuffer
        bcc @full
        cmp #(>fat32_readbuffer)+2
        bcs @full

        jsr fat32_markdirent

        ldy #$00
@name:
        lda (fat32_filenamepointer),y
        sta (fat32_direntptr),y
        iny
        cpy #11
        bcc @name

        lda #$20                        ; archive - a plain file
        sta (fat32_direntptr),y
        iny
        lda #$00
@blank:
        sta (fat32_direntptr),y
        iny
        cpy #32
        bcc @blank

        ldy #14                         ; created
        jsr @stamp
        ldy #18                         ; last access, date only
        lda #<FAT32_DATE
        sta (fat32_direntptr),y
        iny
        lda #>FAT32_DATE
        sta (fat32_direntptr),y
        ldy #22                         ; last write
        jsr @stamp

        jsr fat32_bufferaddress
        f32copy zp_sd_currentsector, fat32_direntsector
        jsr sd_writesector
        bcs @writefail
        clc
        rts

@stamp:
        lda #<FAT32_TIME
        sta (fat32_direntptr),y
        iny
        lda #>FAT32_TIME
        sta (fat32_direntptr),y
        iny
        lda #<FAT32_DATE
        sta (fat32_direntptr),y
        iny
        lda #>FAT32_DATE
        sta (fat32_direntptr),y
        rts

@full:
        lda #FAT32_ERROR_DIR_FULL
        sta fat32_lasterror
        sec
        rts

@writefail:
        lda #FAT32_ERROR_WRITE_FAILED
        sta fat32_lasterror
        sec
        rts


; ---------------------------------------------------------------------------
; Puts another cluster on the end of the file and points the write at its
; first sector.
; ---------------------------------------------------------------------------
fat32_growfile:
        jsr fat32_allocatecluster
        bcc @got
        rts                             ; carry is already set
@got:
        f32copy fat32_chainnext, fat32_fatcluster

        lda fat32_firstcluster
        ora fat32_firstcluster+1
        ora fat32_firstcluster+2
        ora fat32_firstcluster+3
        bne @link

        ; The first cluster of the file, so there is nothing to hang it off
        f32copy fat32_firstcluster, fat32_chainnext
        bra @use

@link:
        f32copy fat32_fatcluster, fat32_currentcluster
        f32copy fat32_fatvalue, fat32_chainnext
        jsr fat32_setfatentry
        bcc @use
        rts                             ; carry is already set

@use:
        f32copy fat32_currentcluster, fat32_chainnext
        jsr fat32_clustersector
        clc
        rts


; ---------------------------------------------------------------------------
; Finds a free cluster, marks it as the end of a chain and leaves its number in
; fat32_fatcluster.
;
; The search carries on from fat32_scancluster instead of starting over, so a
; file that needs several clusters does not rescan the front of the FAT every
; time.
; ---------------------------------------------------------------------------
fat32_allocatecluster:
        bra @sector

        ; Up here, where both range checks below can still reach it
@full:
        lda #FAT32_ERROR_DISK_FULL
        sta fat32_lasterror
        sec
        rts

@sector:
        jsr fat32_scaninrange
        bcc @full

        f32copy fat32_fatcluster, fat32_scancluster
        jsr fat32_fatsector
        jsr fat32_bufferaddress
        jsr sd_readsector
        bcc @gotsector
        rts                             ; carry is already set
@gotsector:
        jsr fat32_fatpointer

@entry:
        lda (zp_sd_address),y
        sta fat32_fatvalue
        iny
        lda (zp_sd_address),y
        ora fat32_fatvalue
        sta fat32_fatvalue
        iny
        lda (zp_sd_address),y
        ora fat32_fatvalue
        sta fat32_fatvalue
        iny
        lda (zp_sd_address),y
        and #$0f                        ; the top nibble is not part of the entry
        ora fat32_fatvalue
        beq @found

        jsr fat32_bumpscan
        jsr fat32_scaninrange
        bcc @full

        iny
        bne @entry
        inc zp_sd_address+1
        lda zp_sd_address+1
        cmp #(>fat32_readbuffer)+2
        bcc @entry
        bra @sector

@found:
        f32copy fat32_fatcluster, fat32_scancluster
        lda #$ff
        sta fat32_fatvalue
        sta fat32_fatvalue+1
        sta fat32_fatvalue+2
        lda #$0f                        ; $0fffffff - end of a chain
        sta fat32_fatvalue+3
        jsr fat32_setfatentry
        bcc @taken
        rts                             ; carry is already set

@taken:
        ; fat32_setfatentry works off fat32_fatcluster, so the number is still
        ; there for the caller
        jsr fat32_bumpscan
        jsr fat32_freedown
        clc
        rts


; ---------------------------------------------------------------------------
; Releases the whole cluster chain that starts at fat32_fatcluster.
;
; Every entry is zeroed as it is passed, so even a chain that loops back on
; itself runs into a cluster that is already free and stops there.
; ---------------------------------------------------------------------------
fat32_freechain:
@loop:
        jsr fat32_clustervalid
        bcc @done

        jsr fat32_getfatentry
        bcs @fail
        f32copy fat32_chainnext, fat32_fatvalue

        f32zero fat32_fatvalue
        jsr fat32_setfatentry
        bcs @fail
        jsr fat32_freeup

        f32copy fat32_fatcluster, fat32_chainnext
        bra @loop

@done:
        clc
        rts

@fail:
        sec
        rts


; ---------------------------------------------------------------------------
; Carry set if fat32_fatcluster is a cluster a chain can carry on into: two or
; above, no higher than the volume goes, and not one of the end markers.
; ---------------------------------------------------------------------------
fat32_clustervalid:
        lda fat32_fatcluster+1
        ora fat32_fatcluster+2
        ora fat32_fatcluster+3
        bne @notlow
        lda fat32_fatcluster
        cmp #$02
        bcc @no
@notlow:

        ; $0ffffff8 and up mark the end of a chain
        lda fat32_fatcluster+3
        cmp #$0f
        bne @inrange
        lda fat32_fatcluster+2
        cmp #$ff
        bne @inrange
        lda fat32_fatcluster+1
        cmp #$ff
        bne @inrange
        lda fat32_fatcluster
        cmp #$f8
        bcs @no
@inrange:

        ; A number past the end of the volume means the chain is damaged -
        ; treat it as the end rather than following it out of the partition
        sec
        lda fat32_maxcluster
        sbc fat32_fatcluster
        lda fat32_maxcluster+1
        sbc fat32_fatcluster+1
        lda fat32_maxcluster+2
        sbc fat32_fatcluster+2
        lda fat32_maxcluster+3
        sbc fat32_fatcluster+3
        bcc @no

        sec
        rts

@no:
        clc
        rts


; ---------------------------------------------------------------------------
; Carry set while fat32_scancluster is still a cluster the volume has.
; ---------------------------------------------------------------------------
fat32_scaninrange:
        sec
        lda fat32_maxcluster
        sbc fat32_scancluster
        lda fat32_maxcluster+1
        sbc fat32_scancluster+1
        lda fat32_maxcluster+2
        sbc fat32_scancluster+2
        lda fat32_maxcluster+3
        sbc fat32_scancluster+3
        rts


fat32_bumpscan:
        inc fat32_scancluster
        bne @out
        inc fat32_scancluster+1
        bne @out
        inc fat32_scancluster+2
        bne @out
        inc fat32_scancluster+3
@out:
        rts


; ---------------------------------------------------------------------------
; Reads the FAT entry of fat32_fatcluster into fat32_fatvalue.
; ---------------------------------------------------------------------------
fat32_getfatentry:
        jsr fat32_fatsector
        jsr fat32_bufferaddress
        jsr sd_readsector
        bcs @fail

        jsr fat32_fatpointer
        lda (zp_sd_address),y
        sta fat32_fatvalue
        iny
        lda (zp_sd_address),y
        sta fat32_fatvalue+1
        iny
        lda (zp_sd_address),y
        sta fat32_fatvalue+2
        iny
        lda (zp_sd_address),y
        and #$0f
        sta fat32_fatvalue+3
        clc
        rts

@fail:
        sec
        rts


; ---------------------------------------------------------------------------
; Stores fat32_fatvalue in the FAT entry of fat32_fatcluster - in every copy of
; the FAT, so the spares stay in step with the one that is actually used.
; ---------------------------------------------------------------------------
fat32_setfatentry:
        jsr fat32_fatsector
        ldx fat32_numfats

@fat:
        phx
        jsr fat32_bufferaddress
        jsr sd_readsector
        bcs @fail

        jsr fat32_fatpointer
        lda fat32_fatvalue
        sta (zp_sd_address),y
        iny
        lda fat32_fatvalue+1
        sta (zp_sd_address),y
        iny
        lda fat32_fatvalue+2
        sta (zp_sd_address),y
        iny
        lda (zp_sd_address),y           ; the top nibble is reserved
        and #$f0
        ora fat32_fatvalue+3
        sta (zp_sd_address),y

        jsr fat32_bufferaddress
        jsr sd_writesector
        bcs @writefail

        plx
        dex
        beq @done

        ; The next copy of the FAT is fat32_fatsize sectors further on
        clc
        lda zp_sd_currentsector
        adc fat32_fatsize
        sta zp_sd_currentsector
        lda zp_sd_currentsector+1
        adc fat32_fatsize+1
        sta zp_sd_currentsector+1
        lda zp_sd_currentsector+2
        adc fat32_fatsize+2
        sta zp_sd_currentsector+2
        lda zp_sd_currentsector+3
        adc fat32_fatsize+3
        sta zp_sd_currentsector+3
        bra @fat

@done:
        clc
        rts

@writefail:
        lda #FAT32_ERROR_WRITE_FAILED
        sta fat32_lasterror
@fail:
        plx
        sec
        rts


; ---------------------------------------------------------------------------
; Turns fat32_fatcluster into the FAT sector that holds its entry
; (zp_sd_currentsector) and the offset of the entry inside that sector
; (fat32_fatoffset plus fat32_fatoffhigh, because it does not fit in a byte).
; ---------------------------------------------------------------------------
fat32_fatsector:
        ; FAT sector = (cluster*4) / 512 = (cluster*2) / 256
        lda fat32_fatcluster
        asl
        lda fat32_fatcluster+1
        rol
        sta zp_sd_currentsector
        lda fat32_fatcluster+2
        rol
        sta zp_sd_currentsector+1
        lda fat32_fatcluster+3
        rol
        sta zp_sd_currentsector+2
        stz zp_sd_currentsector+3

        clc
        lda zp_sd_currentsector
        adc fat32_fatstart
        sta zp_sd_currentsector
        lda zp_sd_currentsector+1
        adc fat32_fatstart+1
        sta zp_sd_currentsector+1
        lda zp_sd_currentsector+2
        adc fat32_fatstart+2
        sta zp_sd_currentsector+2
        lda zp_sd_currentsector+3
        adc fat32_fatstart+3
        sta zp_sd_currentsector+3

        ; Offset = (cluster & 127) * 4, which needs nine bits
        lda fat32_fatcluster
        and #$7f
        asl
        asl
        sta fat32_fatoffset
        lda #$00
        rol
        sta fat32_fatoffhigh
        rts


; ---------------------------------------------------------------------------
; Points zp_sd_address and Y at the FAT entry inside the workspace, ready for
; the indirect indexed accesses that follow. The three that come after it stay
; inside the page, because the offset is always a multiple of four.
; ---------------------------------------------------------------------------
fat32_fatpointer:
        lda #<fat32_readbuffer
        sta zp_sd_address
        lda #>fat32_readbuffer
        clc
        adc fat32_fatoffhigh
        sta zp_sd_address+1
        ldy fat32_fatoffset
        rts


; ---------------------------------------------------------------------------
; First sector of fat32_currentcluster, plus the number of sectors that follow
; it in the same cluster.
;
; Same arithmetic as fat32_seekcluster, without the part that follows the chain
; - during a write the chain is still being built.
; ---------------------------------------------------------------------------
fat32_clustersector:
        sec
        lda fat32_currentcluster
        sbc #$02
        sta zp_sd_currentsector
        lda fat32_currentcluster+1
        sbc #$00
        sta zp_sd_currentsector+1
        lda fat32_currentcluster+2
        sbc #$00
        sta zp_sd_currentsector+2
        lda fat32_currentcluster+3
        sbc #$00
        sta zp_sd_currentsector+3

        lda fat32_sectorspercluster
@shift:
        lsr
        bcs @shifted
        asl zp_sd_currentsector
        rol zp_sd_currentsector+1
        rol zp_sd_currentsector+2
        rol zp_sd_currentsector+3
        bra @shift
@shifted:

        clc
        lda zp_sd_currentsector
        adc fat32_datastart
        sta zp_sd_currentsector
        lda zp_sd_currentsector+1
        adc fat32_datastart+1
        sta zp_sd_currentsector+1
        lda zp_sd_currentsector+2
        adc fat32_datastart+2
        sta zp_sd_currentsector+2
        lda zp_sd_currentsector+3
        adc fat32_datastart+3
        sta zp_sd_currentsector+3

        lda fat32_sectorspercluster
        sta fat32_pendingsectors
        rts


fat32_bufferaddress:
        lda #<fat32_readbuffer
        sta zp_sd_address
        lda #>fat32_readbuffer
        sta zp_sd_address+1
        rts

        .code


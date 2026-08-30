      .import _sd_init
      .import _sd_load
      .import _sd_save
      .import sd_address
      .import sd_length
      .import fat32_lasterror

; Streaming interface - see source/sd.s
      .import _sd_openread
      .import _sd_openwrite
      .import _sd_readbyte
      .import _sd_putsector
      .import _sd_close
      .import _sd_opendir
      .import _sd_nextdirent
      .import sd_direntname
      .import sd_direntattr
      .import sd_direntsize

; Allocating write interface. Unlike _sd_openwrite / _sd_putsector / _sd_close
; these create the file when it is missing and take clusters off the free list
; as they go, so the file ends up exactly as long as what was written.
;
;   _sd_mount       (re)initialise the card and read its layout
;   _sd_beginsave   A/X = 11 character FAT name
;   _sd_putnext     A/X = 512 byte buffer holding the next sector
;   _sd_endsave     sd_length = the finished file's size
;   _sd_abortsave   give back what was allocated, leave an empty file
      .import _sd_mount
; Free space in 512 byte blocks, for the line LOAD "$" ends on
      .import _sd_freeblocks
      .import sd_freeblocks
      .import _sd_beginsave
      .import _sd_putnext
      .import _sd_endsave
      .import _sd_abortsave

; Error codes reported in fat32_lasterror when one of the above returns with
; carry set. Mirrors the definitions in source/libfat32.s.
FAT32_ERROR_NONE           = 0
FAT32_ERROR_NO_SUCH_FILE   = 1
FAT32_ERROR_FILE_TOO_SMALL = 2
FAT32_ERROR_WRITE_FAILED   = 3
FAT32_ERROR_READ_FAILED    = 4
FAT32_ERROR_NO_CARD        = 5
FAT32_ERROR_DISK_FULL      = 6
FAT32_ERROR_DIR_FULL       = 7

; Directory entry attribute bits
FAT32_ATTR_DIRECTORY       = $10
FAT32_ATTR_VOLUME          = $08

SD_PORTB = $8200
SD_PORTA = $8201
SD_DDRB = $8202
SD_DDRA = $8203

SD_CS   = %00000010
SD_SCK  = %00000100
SD_MOSI = %00001000
SD_MISO = %00010000


; ----------------------------------------------------------------------------
; Twenty-five dead bytes at the end of SDCODE
;
; A test, not a feature. COLOR put next to CLS wrecks the font on the first
; boot, twice over and once with every VDP access paced, and nobody knows why -
; MEMORY_MAP.md 5.5. Two things happen when those twenty-five bytes go in at the
; front of the block: the body of SDCODE moves up, and the block gets longer.
; This separates them.
;
; The same twenty-five bytes go in behind everything else instead. The block ends
; on $F7F3 exactly as it did when it failed, and not one byte of what is in it
; has moved. If that runs, it is the body moving; if it fails, it is the length
; of the block and the addresses its end reaches.
;
; It is a library module and only the BASIC ROM force-imports it, so no other
; ROM carries it. Delete the file, the line in common/makefile and the
; .forceimport in db6502_extra.s once the answer is written down.
; ----------------------------------------------------------------------------

        .setcpu "65C02"

        .export sdcode_pad

        .segment "SDCODE"

sdcode_pad:
        .repeat 25
        nop
        .endrepeat

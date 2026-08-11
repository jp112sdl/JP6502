; Microsoft BASIC for 6502
;
; (first revision of this distribution, 20 Oct 2008, Michael Steil www.pagetable.com)
;
; This is a single integrated assembly source tree that can generate seven different versions of
; Microsoft BASIC for 6502.
;
; By running ./make.sh, this will generate all versions and compare them to the original files
; byte by byte. The CC65 compiler suite is need to build this project.
;
; These are the first eight (known) versions of Microsoft BASIC for 6502:
;
; Name                 Release   MS Version    ROM   9digit  INPUTBUFFER   extensions   .define
;---------------------------------------------------------------------------------------------------
; Commodore BASIC 1     1977                    Y      Y          ZP          CBM
; OSI BASIC             1977     1.0 REV 3.2    Y      N          ZP            -        CONFIG_10A
; AppleSoft I           1977     1.1            N      Y        $0200         Apple      CONFIG_11
; KIM BASIC             1977     1.1            N      Y          ZP            -        CONFIG_11A
; AppleSoft II          1978                    Y      Y        $0200         Apple      CONFIG_2
; Commodore BASIC 2     1979                    Y      Y        $0200          CBM       CONFIG_2A
; KBD BASIC             1982                    Y      N        $0700          KBD       CONFIG_2B
; MicroTAN              1980                    Y      Y          ZP            -        CONFIG_2C
;
; (Note that this assembly source cannot (yet) build AppleSoft II.)
;
; This lists the versions in the order in which they were forked from the Microsoft source base.
; Commodore BASIC 1, as used on the original PET is the oldest known version of Microsoft BASIC
; for 6502. It contains some additions to Microsoft's version, like Commodore-style file I/O.
;
; The CONFIG_n defines specify what Microsoft-version the OEM version is based on. If CONFIG_2B
; is defined, for example, CONFIG_2A, CONFIG_2, CONFIG_11A, CONFIG_11 and CONFIG_10A will be
; defined as well, and all bugfixes up to version 2B will be enabled.
;
; The following symbols can be defined in addition:
;
; CONFIG_CBM1_PATCHES				jump out into CBM1's binary patches instead of doing the right thing inline
; CONFIG_CBM_ALL					add all Commodore-specific additions except file I/O
; CONFIG_DATAFLG					?
; CONFIG_EASTER_EGG					include the CBM2 "WAIT 6502" easter egg
; CONFIG_FILE						support Commodore PRINT#, INPUT#, GET#, CMD
; CONFIG_IO_MSB						all I/O has bit #7 set
; CONFIG_MONCOUT_DESTROYS_Y			Y needs to be preserved when calling MONCOUT 	
; CONFIG_NO_CR						terminal doesn't need explicit CRs on line ends
; CONFIG_NO_LINE_EDITING			disable support for Microsoft-style "@", "_", BEL etc.
; CONFIG_NO_POKE					don't support PEEK, POKE and WAIT
; CONFIG_NO_READ_Y_IS_ZERO_HACK		don't do a very volatile trick that saves one byte
; CONFIG_NULL						support for the NULL statement
; CONFIG_PEEK_SAVE_LINNUM			preserve LINNUM on a PEEK
; CONFIG_PRINTNULLS					whether PRINTNULLS does anything
; CONFIG_PRINT_CR					print CR when line end reached
; CONFIG_RAM						optimizations for RAM version of BASIC, only use on 1.x
; CONFIG_ROR_WORKAROUND				use workaround for buggy 6502s from 1975/1976; not safe for CONFIG_SMALL!
; CONFIG_SAFE_NAMENOTFOUND			check both bytes of the caller's address in NAMENOTFOUND
; CONFIG_SCRTCH_ORDER				where in the init code to call SCRTCH
; CONFIG_SMALL						use 6 digit FP instead of 9 digit, use 2 character error messages, don't have GET
;
; Changing symbol definitions can alter an existing base configuration, but it not guaranteed to assemble
; or work correctly.
;
; Credits:
; * main work by Michael Steil
; * function names and all uppercase comments taken from Bob Sander-Cederlof's excellent AppleSoft II disassembly:
;   http://www.txbobsc.com/scsc/scdocumentor/
; * Applesoft lite by Tom Greene http://cowgod.org/replica1/applesoft/ helped a lot, too.
; * Thanks to Joe Zbicak for help with Intellision Keyboard BASIC
; * This work is dedicated to the memory of my dear hacking pal Michael "acidity" Kollmann.

;.debuginfo +

.setcpu "65C02"
.macpack longbranch

; Everything pulled in with a "../../common/source/" path is shared verbatim
; with the ROM build - these used to be byte-identical copies in this directory,
; and keeping them in two places is how the local init.s silently ended up
; without the DB6502 RAM probe limit. A plain file name is a deliberately local
; file; the reason is noted next to it.
;
; ca65 resolves a nested .include relative to the directory of the file doing
; the including, so the shared files pull in their own neighbours from
; common/source automatically - flow1.s picks up iscntc.s that way.

; Local: selects and pulls in defines_db6502.s by bare name, which differs
; between the two builds.
.include "defines.s"
.include "../../common/source/macros.s"
; Local: exports INPUTBUFFER as an absolute symbol, the ROM build does not.
.include "basic_zp.s"

.include "../../common/source/header.s"
.include "../../common/source/token.s"
.include "../../common/source/error.s"
.include "../../common/source/message.s"
.include "../../common/source/memory.s"
; Local: no SD card LOAD/SAVE in the loadable build, so no sd_finish/inline.s
; hooks.
.include "program.s"
.include "../../common/source/flow1.s"
.include "../../common/source/loadsave.s"
.include "../../common/source/flow2.s"
.include "../../common/source/misc1.s"
; Local: line ends go straight to the TTY instead of through sd_newline.
.include "print.s"
.include "../../common/source/input.s"
.include "../../common/source/eval.s"
.include "../../common/source/var.s"
.include "../../common/source/array.s"
.include "../../common/source/misc2.s"
; Same file as the local string.s used to be, it is just named ms_string.s in
; common/source.
.include "../../common/source/ms_string.s"
.include "../../common/source/misc3.s"
.include "../../common/source/poke.s"
.include "../../common/source/float.s"
.include "../../common/source/chrget.s"
.include "../../common/source/rnd.s"
.include "../../common/source/trig.s"
; The only build-specific bit in here is the sign-on line, which comes from
; BASIC_BANNER in defines_db6502.s.
.include "../../common/source/init.s"
; Local: pulls in db6502_extra.s by bare name, which differs between the builds.
.include "extra.s"


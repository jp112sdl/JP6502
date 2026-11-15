# floppy_pico.ino on the Mac, against the real MS-BASIC and the real GeckOS in
# the GeckOS emulator. The sketch is built as it is, with the SdFat and the MFM
# code of the Pico build. Only the drive is a mock, which keeps the flux of
# every track written - so what a test reads and writes is a FAT12 disk. The
# 6551 is a pipe (the emulator's -A).
#
#   make           picohost, run as "picohost FOLDER": its disk starts with the
#                  files of FOLDER, and FOLDER gets what is on it at the end
#   make test      every scenario in tests/, side by side, about a minute
#
# A scenario is an emulator script. Its comments say
#
#   # rom: geckos    GeckOS with its card, a copy of boot/sd.img, in place of
#                    MS-BASIC
#   # disk: geckos   the disk starts with the programs of GeckOS, with "empty"
#                    blank, in place of the programs of Software/basic
#   # pico: none     no drive on the line: the 6551 goes to the emulator's
#                    standard output, as a terminal on the host would get it
#   # emu: ...       more options for the emulator
#   # env: ...       how the drive behaves, the variables of main.cpp and
#                    mock/Adafruit_Floppy.h
#   # expect: ...    what the screen, the LCD or the log must show
#   # check: ...     what must hold in the disk folder afterwards, a shell
#                    command run there
#
# out/ keeps the folder, the screen and the log of each. GeckOS is built for
# them into out/geckos.bin, boot/geckos.bin stays as it is.

ROOT = ../../..
SKETCH = ../floppy_pico.ino
ROM = $(ROOT)/Software/build/rom/microsoft_basic.ext.bin
BASIC = $(ROOT)/Software/basic
GECKOS = $(ROOT)/GeckOS-V2/arch/jp6502
EMU = $(GECKOS)/emu/jp6502emu
TESTS = $(patsubst tests/%.scr,%,$(wildcard tests/*.scr))

# the libraries of the Pico build, where arduino-cli puts them
LIBS = $(HOME)/Documents/Arduino/libraries
SDFAT = $(LIBS)/SdFat_-_Adafruit_Fork/src
MFM = $(LIBS)/Adafruit_Floppy/src

FLAGS = -std=c++17 -O1 -include $(CURDIR)/prelude.h -I $(CURDIR)/mock \
	-isystem $(SDFAT) -isystem $(MFM) -DENABLE_ARDUINO_FEATURES=0 \
	-DENABLE_ARDUINO_SERIAL=0 -DENABLE_ARDUINO_STRING=0 -DSPI_DRIVER_SELECT=3

picohost: $(SKETCH) main.cpp prelude.h mock/Adafruit_Floppy.h mock/mfm_impl.h build/sdfat.a
	$(CXX) $(FLAGS) -Wall -Wextra -Wno-unused-parameter main.cpp build/sdfat.a -o $@

# FAT of SdFat without its SD cards - those want SPI
build/sdfat.a: $(wildcard $(SDFAT)/FatLib/*.cpp $(SDFAT)/common/*.cpp) prelude.h
	@test -f $(SDFAT)/SdFat_Adafruit_Fork.h -a -f $(MFM)/mfm_impl.h || \
		{ echo "no SdFat - Adafruit Fork and Adafruit Floppy in $(LIBS)"; exit 1; }
	rm -rf build && mkdir build
	cd build && $(CXX) $(FLAGS) -w -c $(SDFAT)/FatLib/*.cpp $(SDFAT)/common/*.cpp && \
		ar rcs sdfat.a *.o

$(EMU): $(EMU).c
	$(MAKE) -C $(GECKOS) emu

test: picohost $(EMU)
	@test -f $(ROM) || { echo "no $(ROM) - build it with make all in Software"; exit 1; }
	@mkdir -p out
	@$(MAKE) -C $(GECKOS) TRG=$(CURDIR)/out/geckos.bin sdimg all >out/geckos.log 2>&1 || \
		{ echo "GeckOS does not build, see out/geckos.log"; exit 1; }
	@$(MAKE) -s -k --no-print-directory -j $(words $(TESTS)) $(TESTS:%=test-%)

$(TESTS:%=test-%): test-%: tests/%.scr
	@rm -rf out/$* out/$*.img && mkdir -p out/$*
	@case "$$(sed -n 's/^# disk: //p' $<)" in \
		geckos) cp $(GECKOS)/boot/sdcard/* out/$*;; \
		empty) ;; \
		*) cp $(BASIC)/*.BAS out/$*;; \
	esac
	@rom="$(ROM)"; \
	if [ "$$(sed -n 's/^# rom: //p' $<)" = geckos ]; then \
		cp -c $(GECKOS)/boot/sd.img out/$*.img 2>/dev/null || cp $(GECKOS)/boot/sd.img out/$*.img; \
		rom="-s out/$*.img out/geckos.bin"; \
	fi; \
	set -- -A "./picohost out/$*"; \
	if [ "$$(sed -n 's/^# pico: //p' $<)" = none ]; then set --; fi; \
	env $$(sed -n 's/^# env: //p' $<) $(EMU) $$(sed -n 's/^# emu: //p' $<) \
		"$$@" -x $< $$rom >out/$*.out 2>out/$*.log
	@rm -f out/$*.img
	@sed -n 's/^# expect: //p' $< | while read -r text; do \
		grep -qF -- "$$text" out/$*.out out/$*.log || { echo "$*: missing $$text (out/$*.out, out/$*.log)"; exit 1; }; \
	done
	@sed -n 's/^# check: //p' $< | while read -r check; do \
		(cd out/$* && sh -c "$$check") || { echo "$*: failed in out/$*: $$check"; exit 1; }; \
	done
	@echo "$*: ok"

clean:
	rm -rf picohost build out

.PHONY: test clean $(TESTS:%=test-%)

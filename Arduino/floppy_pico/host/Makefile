# floppy_pico.ino on the Mac, against the real MS-BASIC in the GeckOS emulator.
# The mocks stand in for the Arduino core, Adafruit Floppy and SdFat; the 6551
# is a pipe (the emulator's -A) and the disk a folder.
#
#   make           picohost, run as "picohost FOLDER"
#   make test      every scenario in tests/, side by side, about a minute
#
# A scenario is an emulator script. Its comments say how the drive behaves
# (# env:, the variables of main.cpp and mock/Adafruit_Floppy.h), what the
# screen, the LCD or the log must show (# expect:) and what must hold in the
# disk folder afterwards (# check:, a shell command run there). The disk starts
# with the programs of Software/basic; out/ keeps it, the screen and the log.

ROOT = ../../..
SKETCH = ../floppy_pico.ino
ROM = $(ROOT)/Software/build/rom/microsoft_basic.ext.bin
GECKOS = $(ROOT)/GeckOS-V2/arch/jp6502
EMU = $(GECKOS)/emu/jp6502emu
TESTS = $(patsubst tests/%.scr,%,$(wildcard tests/*.scr))

picohost: $(SKETCH) main.cpp prelude.h mock/SdFat.h mock/Adafruit_Floppy.h mock/mfm_impl.h
	$(CXX) -std=c++17 -Wall -Wextra -Wno-unused-parameter -I mock -include prelude.h \
		-x c++ $(SKETCH) -x none main.cpp -o $@

$(EMU): $(EMU).c
	$(MAKE) -C $(GECKOS) emu

test: picohost $(EMU)
	@test -f $(ROM) || { echo "no $(ROM) - build it with make all in Software"; exit 1; }
	@$(MAKE) -s -k --no-print-directory -j $(words $(TESTS)) $(TESTS:%=test-%)

$(TESTS:%=test-%): test-%: tests/%.scr
	@rm -rf out/$* && mkdir -p out/$* && cp $(ROOT)/Software/basic/*.BAS out/$*
	@env $$(sed -n 's/^# env: //p' $<) $(EMU) -A "./picohost out/$*" -x $< $(ROM) \
		>out/$*.out 2>out/$*.log
	@sed -n 's/^# expect: //p' $< | while read -r text; do \
		grep -qF -- "$$text" out/$*.out out/$*.log || { echo "$*: missing $$text (out/$*.out, out/$*.log)"; exit 1; }; \
	done
	@sed -n 's/^# check: //p' $< | while read -r check; do \
		(cd out/$* && sh -c "$$check") || { echo "$*: failed in out/$*: $$check"; exit 1; }; \
	done
	@echo "$*: ok"

clean:
	rm -rf picohost out

.PHONY: test clean $(TESTS:%=test-%)

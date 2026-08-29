RM_BINARY=rm
RM_FLAGS=-rf

MD5_BINARY=md5sum

PYTHON_BINARY=python

BUILD_FOLDER=build
ROM_FOLDER=$(BUILD_FOLDER)/rom
LOAD_FOLDER=$(BUILD_FOLDER)/load
FIRMWARE_PROJECTS_FOLDER=rom
LOADABLE_PROJECTS_FOLDER=load

ADDRESS_MODE=ext

FIRMWARE_PROJECTS = blink_c				\
					blink_s				\
					blink_test			\
					d_pad_test			\
					keyboard_test		\
					lcd_test			\
					microsoft_basic		\
					minimal_bootloader	\
					modem_test			\
					nop_fill			\
					os1					\
					play_song			\
					serial_load_test	\
					serial_test			\
					serial_wdc			\
					serial_wdc_irq		\
					vdp_diag			\

LOADABLE_PROJECTS = d_pad_test			\
					hello_world			\
					hello_world_c		\
					monitor				\
					play_song			\
					sysinfo
					


FIRMWARE_BINARIES=$(FIRMWARE_PROJECTS:%=$(ROM_FOLDER)/%.$(ADDRESS_MODE).bin)

LOADABLE_BINARIES=$(LOADABLE_PROJECTS:%=$(LOAD_FOLDER)/%.load.bin)

# FORCE makes these run every time. Without it make sees the .bin already on
# disk, and since the rule names no prerequisites it declares the target up to
# date and never enters the project - so an edit to anything under
# common/source/ produced no rebuild at all, silently. The project makefiles do
# track their sources properly, they just have to be asked
$(ROM_FOLDER)/%.$(ADDRESS_MODE).bin: FORCE
	@$(MAKE) --no-print-directory -C $(@:$(ROM_FOLDER)/%.$(ADDRESS_MODE).bin=$(FIRMWARE_PROJECTS_FOLDER)/%) ADDRESS_MODE=$(ADDRESS_MODE) all

$(LOAD_FOLDER)/%.bin: FORCE
	@$(MAKE) --no-print-directory -C $(@:$(LOAD_FOLDER)/%.load.bin=$(LOADABLE_PROJECTS_FOLDER)/%) all

FORCE:

.PHONY: all test mapdoc clean FORCE

all: $(FIRMWARE_BINARIES) $(LOADABLE_BINARIES)

test: $(FIRMWARE_BINARIES) $(LOADABLE_BINARIES)
	@$(MD5_BINARY) $^ 

# Projects whose layout MEMORY_MAP.md describes. The mapdoc: comments in the
# document name the same ones - keep the two in step
MAPDOC_PROJECTS = os1 microsoft_basic

# Check that the address tables in MEMORY_MAP.md still describe what the linker
# actually produces
mapdoc: $(MAPDOC_PROJECTS:%=$(ROM_FOLDER)/%.$(ADDRESS_MODE).bin)
	@$(PYTHON_BINARY) common/mapdoc.py --doc MEMORY_MAP.md \
		--config common/firmware.$(ADDRESS_MODE).cfg \
		--build $(ROM_FOLDER) --address-mode $(ADDRESS_MODE)

clean:
	$(RM_BINARY) $(RM_FLAGS) $(BUILD_FOLDER)

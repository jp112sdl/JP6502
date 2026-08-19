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
					keyboard_test		\
					lcd_test			\
					microsoft_basic		\
					minimal_bootloader	\
					modem_test			\
					nop_fill			\
					os1					\
					serial_load_test	\
					serial_test			\
					serial_wdc			\
					serial_wdc_irq		\

LOADABLE_PROJECTS = d_pad_test			\
					hello_world			\
					hello_world_c		\
					monitor				\
					play_song			\
					sysinfo
					


FIRMWARE_BINARIES=$(FIRMWARE_PROJECTS:%=$(ROM_FOLDER)/%.$(ADDRESS_MODE).bin)

LOADABLE_BINARIES=$(LOADABLE_PROJECTS:%=$(LOAD_FOLDER)/%.load.bin)

$(ROM_FOLDER)/%.$(ADDRESS_MODE).bin:
	$(MAKE) -C $(@:$(ROM_FOLDER)/%.$(ADDRESS_MODE).bin=$(FIRMWARE_PROJECTS_FOLDER)/%) ADDRESS_MODE=$(ADDRESS_MODE) all

$(LOAD_FOLDER)/%.bin:
	$(MAKE) -C $(@:$(LOAD_FOLDER)/%.load.bin=$(LOADABLE_PROJECTS_FOLDER)/%) all

all: $(FIRMWARE_BINARIES) $(LOADABLE_BINARIES)

test: $(FIRMWARE_BINARIES) $(LOADABLE_BINARIES)
	@$(MD5_BINARY) $^ 

# Projects whose layout MEMORY_MAP.md describes. The mapdoc: comments in the
# document name the same ones - keep the two in step
MAPDOC_PROJECTS = os1 microsoft_basic

# Check that the address tables in MEMORY_MAP.md still describe what the linker
# actually produces. The sub-makes are invoked rather than depended on, because
# the .bin rules here have no prerequisites and would not notice a stale build
mapdoc:
	@for project in $(MAPDOC_PROJECTS); do \
		$(MAKE) -s -C $(FIRMWARE_PROJECTS_FOLDER)/$$project \
			ADDRESS_MODE=$(ADDRESS_MODE) all || exit 1; \
	done
	@$(PYTHON_BINARY) common/mapdoc.py --doc MEMORY_MAP.md \
		--config common/firmware.$(ADDRESS_MODE).cfg \
		--build $(ROM_FOLDER) --address-mode $(ADDRESS_MODE)

clean:
	$(RM_BINARY) $(RM_FLAGS) $(BUILD_FOLDER)

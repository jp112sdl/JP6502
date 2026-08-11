PROJECT_NAME=microsoft_basic
BUILD_TYPE=rom

# msbasic.s lives in common/source and is shared with the OS/1 integration.
# standalone.s is local and adds the reset vectors and the power-on init that
# a bootable BASIC-only ROM needs.
ASM_SOURCES=msbasic.s standalone.s
C_SOURCES=

include ../../common/makefile

# Resolve msbasic.s from the shared source folder (standalone.s is found here)
vpath %.s $(COMMON_SOURCE_FOLDER)

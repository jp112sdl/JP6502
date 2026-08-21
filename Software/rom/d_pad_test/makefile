PROJECT_NAME=d_pad_test
BUILD_TYPE=rom

# Same program load/d_pad_test builds - it already carries its own VECTORS
# block, so only the linker config differs between the two. The source stays in
# one place rather than being copied, so the two builds cannot drift apart.
vpath d_pad_test.s ../../load/d_pad_test

ASM_SOURCES=d_pad_test.s
C_SOURCES=

include ../../common/makefile

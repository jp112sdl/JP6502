PROJECT_NAME=play_song
BUILD_TYPE=rom

# Same program load/play_song builds - see rom/d_pad_test/makefile. song.inc
# sits next to song.s and ca65 finds it from there, so no extra -I is needed.
vpath song.s ../../load/play_song

ASM_SOURCES=song.s
C_SOURCES=

include ../../common/makefile

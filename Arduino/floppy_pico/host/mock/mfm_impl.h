// The MFM encoder of Adafruit Floppy as far as floppy_pico.ino sets it up. It
// only fills the pulses: the drive of the mocks keeps no track it is given.
#pragma once
#include <cstddef>
#include <cstdint>
#include <cstring>

typedef struct mfm_io_settings {
  uint16_t gap_1, gap_2;
  uint16_t gap_3[8];
  uint16_t gap_4a;
  uint16_t gap_presync;
  uint8_t gap_byte;
  bool is_fm;
} mfm_io_settings_t;

static const mfm_io_settings_t standard_mfm = {
    50, 22, {32, 54, 84, 116, 255, 255, 255, 255}, 80, 12, 0x4e, false,
};

typedef struct mfm_io {
  bool encode_compact;
  uint16_t T2_max, T3_max, T1_nom;
  uint8_t *pulses;
  size_t n_pulses, pos;
  uint8_t *sectors;
  size_t n_sectors;
  uint8_t *sector_validity;
  uint8_t head, cylinder, n;
  const mfm_io_settings_t *settings;
} mfm_io_t;

static inline size_t encode_track_mfm(mfm_io_t *io) {
  memset(io->pulses, 2 * io->T1_nom, io->n_pulses);
  io->pos = io->n_pulses;
  return io->pos;
}

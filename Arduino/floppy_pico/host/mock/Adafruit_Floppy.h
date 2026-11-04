// The drive, played by environment variables: PICO_NODISK, PICO_WP (write
// protect), PICO_SPT (sectors per track, 9 for 720 KB), PICO_SPINUP_MS,
// PICO_MOUNT_MS and PICO_WRITE_MS (how long the motor, the first read and the
// write of a track take). Its disk reads at the bit rate of its format only: a
// boot sector on track 0, zeros elsewhere. Written tracks are not kept.
#pragma once
#include "SdFat.h"

class Adafruit_Floppy {
public:
  Adafruit_Floppy(int8_t, int8_t, int8_t, int8_t, int8_t, int8_t, int8_t, int8_t,
                  int8_t, int8_t, int8_t, int8_t, int8_t) {}
  bool begin() { return true; }
  void select(bool) {}
  bool spin_motor(bool on) {
    fprintf(stderr, "mock: motor %s\n", on ? "on" : "off");
    if (on) {
      delay(envInt("PICO_SPINUP_MS", 0));
      return !envInt("PICO_NODISK", 0);
    }
    return true;
  }
  bool goto_track(int track) {
    at = track;
    return true;
  }
  bool side(int head) {
    onSide = head;
    return true;
  }
  bool get_ready_sense() { return envInt("PICO_NODISK", 0); }
  bool get_write_protect() { return envInt("PICO_WP", 0); }
  uint32_t getSampleFrequency() { return 24000000; }

  size_t capture_track(volatile uint8_t *, size_t max, int32_t *index, bool, uint32_t) {
    if (!captured++) {
      fprintf(stderr, "mock: disk read in\n");
      delay(envInt("PICO_MOUNT_MS", 0));
    }
    *index = 0;
    return max;
  }

  size_t decode_track_mfm(uint8_t *sectors, size_t count, uint8_t *validity,
                          const uint8_t *, size_t, float bitUs, bool clear,
                          uint8_t *track = nullptr) {
    int perTrack = envInt("PICO_SPT", 18);
    if ((perTrack == 9) != (bitUs > 1.5f)) {
      if (clear) {
        memset(validity, 0, count);
      }
      return 0;
    }
    memset(sectors, 0, count * 512);
    if (at == 0 && onSide == 0) {
      int total = 80 * 2 * perTrack;
      sectors[0] = 0xEB;                  // the jump
      sectors[1] = 0x3C;
      sectors[2] = 0x90;
      sectors[0x0C] = 2;                  // 512 bytes a sector
      sectors[0x0D] = 1;                  // a cluster
      sectors[0x10] = 2;                  // FATs
      sectors[0x13] = total;
      sectors[0x14] = total >> 8;
      sectors[0x18] = perTrack;
      sectors[0x1A] = 2;                  // heads
    }
    memset(validity, 1, count);
    if (track) {
      *track = at;
    }
    return count;
  }

  bool write_track(uint8_t *, size_t, bool) {
    fprintf(stderr, "mock: track %d, side %d written\n", at, onSide);
    delay(envInt("PICO_WRITE_MS", 0));
    return true;
  }

  Stream *debug_serial = nullptr;
  uint16_t step_delay_us = 10000;

private:
  int at = 0, onSide = 0, captured = 0;
};

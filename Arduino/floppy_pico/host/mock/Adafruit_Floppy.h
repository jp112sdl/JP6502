// The drive, played by environment variables: PICO_NODISK, PICO_WP (write
// protect), PICO_SPT (sectors per track, 9 for 720 KB), PICO_SPINUP_MS and
// PICO_MOUNT_MS (how long the motor and the first read take).
#pragma once
#include "SdFat.h"

#define MFM_IBMPC1440K_SECTORS_PER_TRACK 18
enum adafruit_floppy_disk_t { IBMPC360K, IBMPC720K, IBMPC720K_360RPM, IBMPC1200K,
                              IBMPC1440K, IBMPC1440K_360RPM, AUTODETECT };

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
  bool goto_track(int) { return true; }
  bool get_ready_sense() { return envInt("PICO_NODISK", 0); }
  bool get_write_protect() { return envInt("PICO_WP", 0); }
  Stream *debug_serial = nullptr;
};

class Adafruit_MFM_Floppy {
public:
  Adafruit_MFM_Floppy(Adafruit_Floppy *, adafruit_floppy_disk_t = AUTODETECT) {}
  void removed() {}
  bool inserted(adafruit_floppy_disk_t) {
    fprintf(stderr, "mock: disk read in\n");
    delay(envInt("PICO_MOUNT_MS", 0));
    return true;
  }
  uint8_t tracks_per_side() const { return 80; }
  uint8_t sectors_per_track() const { return envInt("PICO_SPT", 18); }
  bool syncDevice() { return true; }
};

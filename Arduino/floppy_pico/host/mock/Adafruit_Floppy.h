// The drive, as far as floppy_pico.ino uses Adafruit_Floppy: it keeps the flux
// of every track written, a revolution each, and decodes with the MFM code of
// the library itself. Environment variables say how it behaves: PICO_NODISK,
// PICO_WP (write protect), PICO_SPINUP_MS, PICO_MOUNT_MS and PICO_WRITE_MS
// (how long the motor, the first read and the write of a track take).
#pragma once
#include <cmath>
#include <map>
#include <vector>
#include <mfm_impl.h>

class Adafruit_Floppy {
public:
  Adafruit_Floppy(int8_t, int8_t, int8_t, int8_t, int8_t, int8_t, int8_t, int8_t,
                  int8_t, int8_t, int8_t, int8_t, int8_t) {}
  bool begin() { return true; }
  void select(bool) {}
  bool spin_motor(bool on) {
    if (driveLive) {
      fprintf(stderr, "mock: motor %s\n", on ? "on" : "off");
    }
    if (on) {
      delay(motor_delay_ms + driveEnv("PICO_SPINUP_MS"));
      return !driveEnv("PICO_NODISK");
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
  bool get_ready_sense() { return driveEnv("PICO_NODISK"); }
  bool get_write_protect() { return driveEnv("PICO_WP"); }
  uint32_t getSampleFrequency() { return SAMPLES; }

  // The pulses of a revolution and the start of the next, like the 220 ms of
  // a capture
  size_t capture_track(volatile uint8_t *pulses, size_t max, int32_t *index, bool, uint32_t) {
    if (driveLive && !captured++) {
      fprintf(stderr, "mock: disk read in\n");
      delay(envInt("PICO_MOUNT_MS", 0));
    }
    const std::vector<uint8_t> &track = tracks[at * 2 + onSide];
    size_t count = 0;
    for (size_t i = 0; count < max && !track.empty() && i < track.size() * 11 / 10; i++) {
      pulses[count++] = track[i % track.size()];
    }
    *index = 0;
    return count;
  }

  // As Adafruit_FloppyBase::decode_track_mfm does it
  size_t decode_track_mfm(uint8_t *sectors, size_t count, uint8_t *validity,
                          const uint8_t *pulses, size_t length, float bitUs, bool clear,
                          uint8_t *track = nullptr) {
    if (clear) {
      memset(validity, 0, count);
    }
    mfm_io_t io;
    io.T1_nom = lround(SAMPLES * bitUs * 1e-6);
    io.T2_max = lround(SAMPLES * bitUs * 2.5e-6);
    io.T3_max = lround(SAMPLES * bitUs * 3.5e-6);
    io.pulses = const_cast<uint8_t *>(pulses);
    io.n_pulses = length;
    io.sectors = sectors;
    io.n_sectors = count;
    io.n = 2;
    io.head = onSide;
    io.cylinder_ptr = track;
    io.sector_validity = validity;
    return ::decode_track_mfm(&io);
  }

  // The write stops at the index: a revolution of 200 ms
  bool write_track(uint8_t *pulses, size_t length, bool) {
    std::vector<uint8_t> &track = tracks[at * 2 + onSide];
    track.clear();
    uint64_t time = 0;
    for (size_t i = 0; i < length && time < SAMPLES / 5; i++) {
      track.push_back(pulses[i]);
      time += pulses[i];
    }
    if (driveLive) {
      fprintf(stderr, "mock: track %d, side %d written\n", at, onSide);
      delay(envInt("PICO_WRITE_MS", 0));
    }
    return true;
  }

  Stream *debug_serial = nullptr;
  uint16_t step_delay_us = 10000;
  uint16_t motor_delay_ms = 1000;

private:
  static constexpr uint32_t SAMPLES = 24000000;   // a second, as on the RP2040
  std::map<int, std::vector<uint8_t>> tracks;
  int at = 0, onSide = 0, captured = 0;
};

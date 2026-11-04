// Just enough Arduino for floppy_pico.ino to run on the Mac: the 6551 is
// standard input and output (the emulator's -A), the USB log is stderr.
#pragma once
#include <cctype>
#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <fcntl.h>
#include <poll.h>
#include <string>
#include <unistd.h>

#define HIGH 1
#define LOW 0
#define OUTPUT 1
#define LED_BUILTIN 25

inline uint32_t millis() {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint32_t)(ts.tv_sec * 1000ULL + ts.tv_nsec / 1000000);
}
inline uint32_t micros() {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint32_t)(ts.tv_sec * 1000000ULL + ts.tv_nsec / 1000);
}
inline void delay(uint32_t ms) { usleep(ms * 1000); }
inline void pinMode(int, int) {}
inline void digitalWrite(int, int) {}

inline int envInt(const char *name, int fallback) {
  const char *value = getenv(name);
  return value ? atoi(value) : fallback;
}

// The sketch reads only READ, and that toggles - flux - unless PICO_NOFLUX.
inline int digitalRead(int) {
  static int level;
  return envInt("PICO_NOFLUX", 0) ? HIGH : (level ^= 1);
}

class Stream {};

// PICO_USB is a line typed on the USB port right at the start, '_' for a space.
class UsbLog : public Stream {
public:
  UsbLog() {
    if (const char *line = getenv("PICO_USB")) {
      typed = line;
      for (char &c : typed) {
        if (c == '_') {
          c = ' ';
        }
      }
      typed += '\r';
    }
  }
  void begin(unsigned long) {}
  int available() { return at < typed.size(); }
  int read() { return at < typed.size() ? (unsigned char)typed[at++] : -1; }
  __attribute__((format(printf, 2, 3))) void printf(const char *format, ...) {
    va_list args;
    va_start(args, format);
    vfprintf(stderr, format, args);
    va_end(args);
  }

private:
  std::string typed;
  size_t at = 0;
};

class AciaLink {
public:
  void setTX(int) {}
  void setRX(int) {}
  void setFIFOSize(size_t) {}
  void begin(unsigned long) {}
  int available() {
    struct pollfd p = {0, POLLIN, 0};
    if (poll(&p, 1, 0) > 0) {
      return 1;
    }
    usleep(200);
    return 0;
  }
  int read() {
    unsigned char byte;
    if (::read(0, &byte, 1) != 1) {
      exit(0);                  // the emulator ended
    }
    return byte;
  }
  size_t write(uint8_t byte) { return ::write(1, &byte, 1) == 1; }
};

extern UsbLog Serial;
extern AciaLink Serial1;
void setup();
void loop();

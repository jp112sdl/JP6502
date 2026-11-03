// picohost FOLDER: floppy_pico.ino on the Mac, with FOLDER as the disk. The
// 6502 is at the other end of standard input and output, see the Makefile.
#include "prelude.h"
#include <string>

std::string mockFolder;
UsbLog Serial;
AciaLink Serial1;

int main(int argc, char **argv) {
  if (argc < 2) {
    fprintf(stderr, "usage: picohost FOLDER\n");
    return 1;
  }
  mockFolder = argv[1];
  // PICO_BOOT_MS: the Pico comes up late, and what the 6502 sends meanwhile
  // is lost.
  uint32_t until = millis() + envInt("PICO_BOOT_MS", 0);
  while ((int32_t)(until - millis()) > 0) {
    struct pollfd p = {0, POLLIN, 0};
    if (poll(&p, 1, 10) > 0) {
      unsigned char byte;
      if (read(0, &byte, 1) != 1) {
        return 0;
      }
      fprintf(stderr, "mock: lost $%02X while booting\n", byte);
    }
  }
  setup();
  for (;;) {
    loop();
  }
}

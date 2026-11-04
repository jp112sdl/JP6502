// The floppy drive behind LOAD "NAME.BAS",8, SAVE "NAME.BAS",8 and LOAD "$",8
//
// A Raspberry Pi Pico is the drive's own controller, the way a 1541 has its
// own 6502: it sits on the 6551 behind a switch that otherwise connects the
// FTDI, and runs a 3.5" PC drive through Adafruit_Floppy. Schematics/
// FLOPPY_PICO.md has the wiring and the protocol, common/source/db6502_disk.s
// is the other end, and tools/drivesim.py plays the same part from a folder on
// the Mac - this follows it step for step, with a disk in place of the folder.
//
// Build (core rp2040:rp2040, libraries "Adafruit Floppy" and "SdFat - Adafruit
// Fork"):
//
//   arduino-cli compile -b rp2040:rp2040:rpipico
//                       --output-dir Arduino/floppy_pico/build Arduino/floppy_pico
//
// Test on the Mac, with mocks for the drive, against MS-BASIC in the emulator:
//
//   make -C Arduino/floppy_pico/host test
//
// Flash: plug the Pico in with BOOTSEL held and drag build/floppy_pico.ino.uf2
// onto the RPI-RP2 drive - with the pull-ups of FLOPPY_PICO.md in place, or
// with the floppy drive switched off: until the firmware runs, every pin is
// pulled low, which without them selects the drive and opens its write gate.
//
// The USB port carries a log of every command (any terminal, any baud rate)
// and takes commands of its own, a line each:
//
//   v                     every byte on the wire and the steps of the head, or not
//   format [720] [NAME]   a blank disk, 1.44 MB or 720 KB, named NAME: every
//                         track written afresh and read back, what was on it gone
//   dump SECTOR           a sector of the disk in the drive, in hex

#include <stdarg.h>
// Not plain SdFat.h: the RP2040 core brings an SdFat of its own, which
// arduino-cli prefers, and that one reads no FAT12 and wants a partition
// table - no floppy disk has either. This header only the fork has, and with
// it first, Adafruit_Floppy's SdFat.h is the fork's too.
#include <SdFat_Adafruit_Fork.h>
#include <Adafruit_Floppy.h>
#include <mfm_impl.h>

// Pico pins, the ones of the Adafruit_Floppy examples; the pin on the 34-way
// cable in brackets. The drive is a "drive B" as it comes from the factory,
// on a straight cable.
#define DENSITY_PIN 2   // [2]  to the drive
#define INDEX_PIN 3     // [8]  from the drive
#define SELECT_PIN 4    // [12] to the drive
#define MOTOR_PIN 5     // [16] to the drive
#define DIR_PIN 6       // [18] to the drive
#define STEP_PIN 7      // [20] to the drive
#define WRDATA_PIN 8    // [22] to the drive
#define WRGATE_PIN 9    // [24] to the drive
#define TRK0_PIN 10     // [26] from the drive
#define PROT_PIN 11     // [28] from the drive
#define READ_PIN 12     // [30] from the drive
#define SIDE_PIN 13     // [32] to the drive
#define DSKCHG_PIN 14   // [34] from the drive
#define ACIA_TX_PIN 0   // UART0 TX to the 6551's RxD, through the switch
#define ACIA_RX_PIN 1   // UART0 RX from the 6551's TxD, through a divider

static constexpr uint8_t EOT = 0x04;
static constexpr uint8_t ENQ = 0x05;
static constexpr uint8_t ACK = 0x06;
static constexpr uint8_t CAN = 0x18;
static constexpr uint8_t LF = 0x0A;
static constexpr uint8_t CR = 0x0D;

static constexpr uint32_t BAUD = 19200;
static constexpr size_t MAX_LINE = 78;               // what ser_getline keeps of a line
static constexpr uint32_t FIRST_ACK_TIMEOUT = 30000; // ms; the machine sends one at once
static constexpr uint32_t LINE_ACK_TIMEOUT = 10000;  // inserting a line in front of a long program
static constexpr uint32_t SAVE_IDLE_TIMEOUT = 60000; // LIST is slow, but not that slow
static constexpr uint32_t MOTOR_IDLE = 3000;         // motor off after this long without a command
static constexpr size_t TEXT_SIZE = 64 * 1024;       // a program, as its file or as its lines

static constexpr uint8_t HEADS = 2;
static constexpr size_t SECTOR = 512;
static constexpr uint8_t READ_TRIES = 5;             // revolutions before a sector counts as unreadable
static constexpr uint32_t CAPTURE_MS = 220;          // a revolution, and some for a sector on the index

Adafruit_Floppy floppy(DENSITY_PIN, INDEX_PIN, SELECT_PIN, MOTOR_PIN, DIR_PIN,
                       STEP_PIN, WRDATA_PIN, WRGATE_PIN, TRK0_PIN, PROT_PIN,
                       READ_PIN, SIDE_PIN, DSKCHG_PIN);

// One program at a time, whole: the lines of a LOAD or a "$", each ending in
// a NUL, or the file a SAVE writes. Nothing comes from the 6502 while the
// drive works - reading a track keeps interrupts off for a revolution, which
// the UART would not survive - so every transfer runs from or into here.
static char text[TEXT_SIZE];
static size_t textUsed;
static unsigned lineCount;

static bool motorOn;        // motor line on, drive selected
static bool mounted;        // fat holds the disk that is in the drive
static bool keepSpinning;   // a listing is coming in that goes to disk next
static uint32_t lastUse;    // millis() of the last drive access
static bool saving;         // a SAVE's file is going to disk, BASIC waits for the answer
static uint32_t lastSign;   // millis() of the last ENQ that kept it waiting
static bool verbose;        // every byte on the wire to the log

// A line typed on the USB port: v at once, anything else once the drive is
// free - between two commands of the machine.
static char usbLine[40];
static size_t usbLength;
static char usbCommand[sizeof usbLine];

// --- the log on USB ----------------------------------------------------------

static void say(const char *format, ...) {
  char line[160];
  va_list args;
  va_start(args, format);
  vsnprintf(line, sizeof line, format, args);
  va_end(args);
  Serial.printf("drive: %s\r\n", line);
}

static int trace(char direction, int byte) {
  if (verbose) {
    if (byte >= 0x20 && byte < 0x7F) {
      Serial.printf("drive: %c %c\r\n", direction, byte);
    } else {
      Serial.printf("drive: %c $%02X\r\n", direction, byte);
    }
  }
  return byte;
}

static void pollUsb() {
  while (Serial.available()) {
    int c = Serial.read();
    if (c == '\r' || c == '\n') {
      usbLine[usbLength] = 0;
      usbLength = 0;
      if (strcmp(usbLine, "v") == 0) {
        verbose = !verbose;
        floppy.debug_serial = verbose ? &Serial : nullptr;
        say("byte log %s", verbose ? "on" : "off");
      } else if (usbLine[0]) {
        strcpy(usbCommand, usbLine);
      }
    } else if (c >= 0x20 && c < 0x7F && usbLength < sizeof usbLine - 1) {
      usbLine[usbLength++] = c;
    }
  }
}

// --- the disk surface --------------------------------------------------------

// Sectors for FatVolume, in place of Adafruit_MFM_Floppy. Its version 0.6.1
// hands the track encoder uninitialised settings - gap sizes and filler come
// from wherever the stack points - and writes a 720 KB disk at the bit rate of
// a 1.44 MB one. So reading still goes through the library's capture and
// decoder, and writing through the encoder of its mfm_impl.h, set up here.
// Three tracks are held. Track 0 has a place for each side - the boot sector,
// the FATs and the directory live there, on 720 KB disks as on 1.44 MB ones -
// and every other track shares the third. Sectors written go into them, and a
// track goes back to the disk whole when its place is needed, or at
// syncDevice(). What it has not been given it reads only then, or when a read
// asks for it - a SAVE fills most of its tracks whole, and so writes them
// without reading them first. Track 0 stays held from one command to the next,
// until the disk comes out.
static void stillBusy();   // the wire: keeps BASIC waiting during a SAVE

class Disk : public FsBlockDeviceInterface {
public:
  // The format of the disk in the drive, from its boot sector: nullptr, or
  // the status line that says why there is none.
  const char *mount();
  // The disk came out, or is about to be formatted: nothing held counts.
  void forget() {
    for (Track &t : held) {
      t.number = NONE;
      t.dirty = false;
    }
    sectors = 0;
  }
  const char *format(bool dd, const char *label);
  uint8_t tracksPerSide() const { return tracks; }
  uint8_t sectorsPerTrack() const { return sectors; }

  bool isBusy() override { return false; }
  Sector_t sectorCount() override { return (Sector_t)tracks * HEADS * sectors; }
  bool syncDevice() override;
  bool readSector(Sector_t sector, uint8_t *dst) override;
  bool readSectors(Sector_t sector, uint8_t *dst, size_t count) override;
  bool writeSector(Sector_t sector, const uint8_t *src) override;
  bool writeSectors(Sector_t sector, const uint8_t *src, size_t count) override;

private:
  static constexpr int NONE = -1;

  // A track held: its sectors as far as they are known, from the disk or
  // written
  struct Track {
    int number = NONE;         // track * HEADS + head
    bool filled = false;       // the disk has given what it has of it
    bool dirty = false;        // a sector written that is not on the disk yet
    uint8_t valid[18];
    uint8_t data[18 * SECTOR];
  };

  bool locate(Sector_t sector, uint8_t &track, uint8_t &head, uint8_t &index) const;
  bool seek(uint8_t track, uint8_t head);
  bool hasFlux();
  unsigned marked(const Track &t) const;
  unsigned readTrack(Track &t);
  Track *hold(uint8_t track, uint8_t head);
  void fill(Track &t);
  bool flush(Track &t);
  bool writeTrack(uint8_t track, uint8_t head, uint8_t *data);

  uint8_t flux[125000];        // a revolution and a bit of pulses, read or to be written
  Track held[3];               // track 0, sides 0 and 1, and any other
  uint8_t tracks = 0, sectors = 0;
  uint16_t bitNs = 1000;       // the MFM cell: 1000 ns on 1.44 MB, 2000 on 720 KB
};

Disk disk;
FatVolume fat;

static uint16_t le16(const uint8_t *p) { return p[0] | p[1] << 8; }

static void put16(uint8_t *p, uint16_t value) {
  p[0] = value;
  p[1] = value >> 8;
}

// Sector lba of a blank FAT12 disk: the boot sector, two FATs and the root
// directory - with the name as the volume label, if there is one - and after
// them the filler FORMAT has always used.
static void blankSector(Sector_t lba, uint8_t *s, bool dd, const char *label,
                        uint32_t serial) {
  const uint8_t perFat = dd ? 3 : 9, media = dd ? 0xF9 : 0xF0;
  const uint16_t rootEntries = dd ? 112 : 224;
  const Sector_t root = 1 + 2 * perFat, files = root + rootEntries * 32 / SECTOR;
  char name[11];
  memset(name, ' ', sizeof name);
  memcpy(name, label, strlen(label));
  memset(s, lba < files ? 0 : 0xF6, SECTOR);
  if (lba == 0) {
    memcpy(s, "\xEB\x3C\x90" "JP6502  ", 11);   // a jump to 0x3E, and who formatted it
    put16(s + 0x0B, SECTOR);
    s[0x0D] = dd ? 2 : 1;                        // sectors a cluster
    put16(s + 0x0E, 1);                          // reserved sectors: this one
    s[0x10] = 2;                                 // FATs
    put16(s + 0x11, rootEntries);
    put16(s + 0x13, dd ? 1440 : 2880);           // sectors
    s[0x15] = media;
    put16(s + 0x16, perFat);
    put16(s + 0x18, dd ? 9 : 18);                // sectors a track
    put16(s + 0x1A, HEADS);
    s[0x26] = 0x29;                              // serial, label and type follow
    put16(s + 0x27, serial);
    put16(s + 0x29, serial >> 16);
    memcpy(s + 0x2B, label[0] ? name : "NO NAME    ", 11);
    memcpy(s + 0x36, "FAT12   ", 8);
    s[0x3E] = 0xCD;                              // int 18h: a PC booting from it moves on
    s[0x3F] = 0x18;
    s[0x1FE] = 0x55;
    s[0x1FF] = 0xAA;
  } else if (lba == 1 || lba == 1u + perFat) {
    s[0] = media;                                // FAT entries 0 and 1
    s[1] = 0xFF;
    s[2] = 0xFF;
  } else if (lba == root && label[0]) {
    memcpy(s, name, sizeof name);
    s[11] = 0x08;                                // the volume label
  }
}

bool Disk::locate(Sector_t sector, uint8_t &track, uint8_t &head,
                  uint8_t &index) const {
  if (!sectors || sector >= (Sector_t)tracks * HEADS * sectors) {
    return false;
  }
  track = sector / (HEADS * sectors);
  head = sector / sectors % HEADS;
  index = sector % sectors;
  return true;
}

bool Disk::seek(uint8_t track, uint8_t head) {
  if (!floppy.goto_track(track)) {
    say("cannot get to track %u - no TRK0 from the drive", track);
    return false;
  }
  floppy.side(head);
  return true;
}

// Any flux on READ at all? The library's capture waits for it with the
// interrupts off and no time limit: a track with nothing on it, or a READ line
// without its pull-up, would hang the Pico for good. A written track has an
// edge every 2 to 8 us.
bool Disk::hasFlux() {
  uint32_t start = micros();
  unsigned edges = 0;
  int last = digitalRead(READ_PIN);
  while (edges < 16 && micros() - start < 2000) {
    int now = digitalRead(READ_PIN);
    edges += last && !now;
    last = now;
  }
  return edges >= 16;
}

// The sectors of a track held that valid[] marks
unsigned Disk::marked(const Track &t) const {
  unsigned count = 0;
  for (uint8_t i = 0; i < sectors; i++) {
    count += t.valid[i];
  }
  return count;
}

// The sectors of a track held that valid[] does not mark yet, from the disk -
// as many as READ_TRIES revolutions give; the decoder leaves the marked ones
// alone. The count marked then.
unsigned Disk::readTrack(Track &t) {
  uint8_t track = t.number / HEADS, head = t.number % HEADS;
  if (!seek(track, head)) {
    return marked(t);
  }
  if (!hasFlux()) {
    say("no flux on track %u, side %u - nothing written there, or READ without "
        "its pull-up", track, head);
    return marked(t);
  }
  unsigned got = marked(t);
  for (uint8_t i = 0; i < READ_TRIES && got < sectors; i++) {
    stillBusy();
    int32_t index;
    size_t count = floppy.capture_track(flux, sizeof flux, &index, false, CAPTURE_MS);
    uint8_t before[sizeof t.valid], found = track;
    memcpy(before, t.valid, sizeof t.valid);
    got = floppy.decode_track_mfm(t.data, sectors, t.valid, flux, count,
                                  bitNs / 1000.f, false, &found);
    if (found != track) {
      say("track %u, side %u holds the sectors of track %u", track, head, found);
      memcpy(t.valid, before, sizeof t.valid);
      return marked(t);
    }
  }
  return got;
}

// The place for a track, once what was in it is back on the disk. Of a track
// new there nothing is read yet: a write brings its sector along.
Disk::Track *Disk::hold(uint8_t track, uint8_t head) {
  Track &t = held[track ? 2 : head];
  int want = track * HEADS + head;
  if (t.number != want) {
    if (!flush(t)) {
      return nullptr;
    }
    t.number = want;
    t.filled = false;
    memset(t.valid, 0, sizeof t.valid);
  }
  return &t;
}

// The rest of a track held, from the disk - once. If none of it reads, the
// disk is asked again next time.
void Disk::fill(Track &t) {
  if (t.filled) {
    return;
  }
  t.filled = true;
  unsigned got = readTrack(t);
  if (got < sectors) {
    say("track %u, side %u: %u of %u sectors read", t.number / HEADS,
        t.number % HEADS, got, sectors);
  }
  if (!got) {
    t.number = NONE;
  }
}

bool Disk::readSector(Sector_t sector, uint8_t *dst) {
  uint8_t track, head, index;
  Track *t = locate(sector, track, head, index) ? hold(track, head) : nullptr;
  if (!t) {
    return false;
  }
  if (!t->valid[index]) {
    fill(*t);
  }
  if (!t->valid[index]) {
    return false;
  }
  memcpy(dst, t->data + index * SECTOR, SECTOR);
  return true;
}

bool Disk::readSectors(Sector_t sector, uint8_t *dst, size_t count) {
  for (size_t i = 0; i < count; i++) {
    if (!readSector(sector + i, dst + i * SECTOR)) {
      return false;
    }
  }
  return true;
}

bool Disk::writeSector(Sector_t sector, const uint8_t *src) {
  uint8_t track, head, index;
  Track *t = locate(sector, track, head, index) ? hold(track, head) : nullptr;
  if (!t) {
    return false;
  }
  memcpy(t->data + index * SECTOR, src, SECTOR);
  t->valid[index] = 1;
  t->dirty = true;
  return true;
}

bool Disk::writeSectors(Sector_t sector, const uint8_t *src, size_t count) {
  for (size_t i = 0; i < count; i++) {
    if (!writeSector(sector + i, src + i * SECTOR)) {
      return false;
    }
  }
  return true;
}

// A track held goes back to the disk if a sector of it was written. It goes
// whole, so the sectors not written come from the disk first - none if all
// were. Not with one of them unreadable, though: it would come out as
// whatever its place has there.
bool Disk::flush(Track &t) {
  if (!t.dirty) {
    return true;
  }
  t.dirty = false;
  uint8_t track = t.number / HEADS, head = t.number % HEADS;
  if (memchr(t.valid, 0, sectors)) {
    fill(t);
  }
  if (memchr(t.valid, 0, sectors)) {
    say("track %u, side %u not written back - a sector of it did not read",
        track, head);
    return false;
  }
  return writeTrack(track, head, t.data);
}

// Everything written onto the disk: the data first, then FAT and directory -
// cut short in between, the disk only loses room.
bool Disk::syncDevice() {
  bool ok = flush(held[2]);
  ok = flush(held[0]) && ok;
  return flush(held[1]) && ok;
}

// Sectors onto a track, headers and all: a revolution from the index on. The
// library's write_track waits for the index with no time limit, so only with a
// disk in the drive.
bool Disk::writeTrack(uint8_t track, uint8_t head, uint8_t *data) {
  if (floppy.get_ready_sense()) {
    say("the disk came out");
    return false;
  }
  if (!seek(track, head)) {
    return false;
  }
  stillBusy();
  mfm_io_t io = {};
  io.settings = &standard_mfm;
  io.T1_nom = floppy.getSampleFrequency() / 1000000 * bitNs / 1000;   // samples a cell
  io.pulses = flux;
  io.n_pulses = sizeof flux;
  io.sectors = data;
  io.n_sectors = sectors;
  io.n = 2;   // 128 << 2 = 512 bytes a sector
  io.head = head;
  io.cylinder = track;
  encode_track_mfm(&io);   // gap after the sectors up to the end: the write stops at the index
  return floppy.write_track(flux, sizeof flux, false);
}

// A PC format at the bit rate of 1.44 MB, else of 720 KB, by its boot sector -
// as the library's autodetect does, but only what a 3.5" drive holds.
const char *Disk::mount() {
  forget();
  if (!seek(0, 0)) {
    return "74,DRIVE NOT READY";
  }
  if (!hasFlux()) {
    say("no flux on track 0 - an empty disk, or READ (GP12) without its pull-up");
    return "21,READ ERROR";
  }
  int32_t index;
  size_t count = floppy.capture_track(flux, sizeof flux, &index, false, CAPTURE_MS);
  // The boot sector stays held - FatVolume asks for it next.
  Track &t = held[0];
  const uint8_t *boot = t.data;
  memset(t.valid, 0, sizeof t.valid);
  static const uint16_t cells[] = {1000, 2000};
  for (uint16_t ns : cells) {
    if (!floppy.decode_track_mfm(t.data, 1, t.valid, flux, count, ns / 1000.f, true)) {
      continue;
    }
    uint16_t perTrack = le16(boot + 0x18), total = le16(boot + 0x13);
    if (le16(boot + 0x0B) != SECTOR || le16(boot + 0x1A) != HEADS ||
        (perTrack != 9 && perTrack != 18) || total % (HEADS * perTrack)) {
      say("boot sector: %u bytes a sector, %u sectors a track, %u heads - not "
          "a 3.5\" format", le16(boot + 0x0B), perTrack, le16(boot + 0x1A));
      return "20,READ ERROR";
    }
    sectors = perTrack;
    tracks = total / (HEADS * perTrack);
    bitNs = ns;
    t.number = 0;
    t.filled = false;
    say("boot sector: %u sectors a track, %u a cluster, %u FATs of %u, %u root "
        "entries, media %02X", perTrack, boot[0x0D], boot[0x10], le16(boot + 0x16),
        le16(boot + 0x11), boot[0x15]);
    return nullptr;
  }
  say("no PC format on this disk");
  return "20,READ ERROR";
}

// A blank FAT12 disk, as FORMAT A: leaves one: every track written afresh,
// sector headers and all, and read back. 720 KB with dd, else 1.44 MB.
const char *Disk::format(bool dd, const char *label) {
  forget();
  tracks = 80;
  sectors = dd ? 9 : 18;
  bitNs = dd ? 2000 : 1000;
  uint32_t serial = micros();   // the volume serial only has to differ from disk to disk
  Track &t = held[2];           // to build each track in, and read it back
  for (uint8_t track = 0; track < tracks; track++) {
    for (uint8_t head = 0; head < HEADS; head++) {
      Sector_t first = ((Sector_t)track * HEADS + head) * sectors;
      for (uint8_t i = 0; i < sectors; i++) {
        blankSector(first + i, t.data + i * SECTOR, dd, label, serial);
      }
      if (!writeTrack(track, head, t.data)) {
        say("cannot write track %u, side %u", track, head);
        forget();
        return "25,WRITE ERROR";
      }
      t.number = track * HEADS + head;
      memset(t.valid, 0, sizeof t.valid);
      unsigned got = readTrack(t);
      if (got < sectors) {
        say("track %u, side %u: %u of %u sectors read back", track, head, got, sectors);
        forget();
        return "25,WRITE ERROR";
      }
    }
    say("track %u of %u", track + 1, tracks);
  }
  forget();
  return nullptr;
}

// --- the drive ---------------------------------------------------------------

static void driveOff() {
  floppy.spin_motor(false);
  floppy.select(false);
  motorOn = false;
  digitalWrite(LED_BUILTIN, LOW);
}

// Selects the drive and spins it up: nullptr, or the status line that says
// why not.
static const char *driveSpin() {
  lastUse = millis();
  digitalWrite(LED_BUILTIN, HIGH);
  floppy.select(true);
  if (!motorOn) {
    motorOn = true;
    if (!floppy.spin_motor(true)) {
      say("no index pulse - no disk in the drive, or no drive");
      driveOff();
      return "74,DRIVE NOT READY";
    }
  }
  return nullptr;
}

// A step out and back, which clears DSKCHG if there is a disk in the drive:
// nullptr, or the status line for an empty one. Whatever was read of the disk
// before counts no more.
static const char *diskIn() {
  mounted = false;
  disk.forget();
  floppy.goto_track(1);
  floppy.goto_track(0);
  if (floppy.get_ready_sense()) {
    say("DSKCHG stays active - no disk in the drive");
    driveOff();
    return "74,DRIVE NOT READY";
  }
  return nullptr;
}

// Selects the drive, spins it up and makes sure fat holds the disk that is in
// it. nullptr when it does, else the status line that says why not.
static const char *driveOpen() {
  const char *error = driveSpin();
  if (error) {
    return error;
  }

  // DSKCHG goes active when the disk comes out and stays so until the head
  // steps with a disk in - a swap while the motor was off still shows. Only
  // while the drive is selected, though.
  if (mounted && !floppy.get_ready_sense()) {
    return nullptr;
  }
  uint32_t started = millis();
  error = diskIn();
  if (!error) {
    error = disk.mount();
  }
  if (error) {
    return error;
  }
  if (!fat.begin(&disk)) {
    say("no FAT file system on this disk");
    return "20,READ ERROR";
  }
  mounted = true;
  say("disk in: %u tracks of %u sectors, read in %lu ms", disk.tracksPerSide(),
      disk.sectorsPerTrack(), (unsigned long)(millis() - started));
  return nullptr;
}

// Between commands and while waiting on the wire: the motor goes off once the
// drive has been left alone for a while.
static void idle() {
  pollUsb();
  if (motorOn && !keepSpinning && millis() - lastUse >= MOTOR_IDLE) {
    driveOff();
  }
}

// --- the wire ----------------------------------------------------------------

// One byte from the 6502, or -1 after timeout ms - at once for 0
static int linkRead(uint32_t timeout) {
  uint32_t start = millis();
  for (;;) {
    if (Serial1.available()) {
      return trace('<', Serial1.read());
    }
    if (millis() - start >= timeout) {
      return -1;
    }
    idle();
  }
}

static void linkByte(uint8_t byte) {
  trace('>', byte);
  Serial1.write(byte);
}

// While the file of a SAVE goes to disk, BASIC waits for the second answer
// ten seconds from the last byte it got, and an ENQ there it passes over. So
// between two tracks the drive sends one every two seconds: a long program
// takes longer than ten to write.
static void stillBusy() {
  if (saving && millis() - lastSign >= 2000) {
    linkByte(ENQ);
    lastSign = millis();
  }
}

static void linkLine(const char *line) {
  for (const char *c = line; *c; c++) {
    linkByte(*c);
  }
  linkByte(CR);
}

static void status(const char *line) {
  say("-> %s", line);
  linkLine(line);
}

// The next command line - false after a second of quiet with none begun. Bytes
// outside a line - an ACK left over, a CAN from a transfer given up - are not
// commands and are dropped.
static bool readCommand(char *line, size_t size) {
  size_t length = 0;
  for (;;) {
    int byte = linkRead(1000);
    if (byte < 0) {
      if (!length) {
        return false;
      }
      continue;
    }
    if (byte == CR) {
      if (length) {
        line[length] = 0;
        return true;
      }
      continue;
    }
    if (byte < 0x20 || byte > 0x7E) {
      continue;
    }
    if (length < size - 1) {
      line[length++] = byte;
    }
  }
}

// True on ACK, false on timeout or CAN
static bool waitAck(uint32_t timeout) {
  uint32_t start = millis();
  for (;;) {
    uint32_t waited = millis() - start;
    if (waited >= timeout) {
      say("no ACK from the machine");
      return false;
    }
    int byte = linkRead(timeout - waited);
    if (byte == ACK) {
      return true;
    }
    if (byte == CAN) {
      say("<- CAN, the machine gave up");
      return false;
    }
  }
}

// Throws away the ACKs that pile up while BASIC waits - it repeats its ACK
// when nothing comes. False if a CAN is among them.
static bool drain() {
  for (;;) {
    int byte = linkRead(0);
    if (byte < 0) {
      return true;
    }
    if (byte == CAN) {
      say("<- CAN, the machine gave up");
      return false;
    }
  }
}

// LOAD "@" from this end: a line for every ACK, EOT after the last
static void sendLines() {
  if (!waitAck(FIRST_ACK_TIMEOUT)) {
    return;
  }
  const char *line = text;
  for (unsigned index = 1; index <= lineCount; index++) {
    if (!drain()) {
      return;
    }
    linkLine(line);
    line += strlen(line) + 1;
    if (!waitAck(LINE_ACK_TIMEOUT)) {
      say("stopped after line %u of %u", index, lineCount);
      return;
    }
  }
  if (drain()) {
    linkByte(EOT);
    say("sent %u lines", lineCount);
  }
}

static bool put(char c) {
  if (textUsed >= TEXT_SIZE) {
    return false;
  }
  text[textUsed++] = c;
  return true;
}

// SAVE "@" from this end: the listing up to the EOT, kept as the file it
// becomes - every line ending in CR LF. False if the machine sent CAN instead,
// or stopped; tooLarge if it did not fit.
static bool receiveListing(bool &tooLarge) {
  textUsed = 0;
  lineCount = 0;
  tooLarge = false;
  size_t lineStart = 0;
  for (;;) {
    int byte = linkRead(SAVE_IDLE_TIMEOUT);
    if (byte < 0) {
      say("the listing stopped without an EOT");
      return false;
    }
    if (byte == EOT) {
      break;
    }
    if (byte == CAN) {
      say("<- CAN, the save was given up");
      return false;
    }
    if (byte == LF) {
      tooLarge |= !put('\r') || !put('\n');
      lineCount++;
      lineStart = textUsed;
    } else if (byte >= 0x20 && byte < 0x7F) {
      tooLarge |= !put(byte);
    }
  }
  if (textUsed > lineStart) {
    tooLarge |= !put('\r') || !put('\n');
    lineCount++;
  }
  return true;
}

// --- the disk ----------------------------------------------------------------

// "HELLO   BAS" -> "HELLO.BAS"
static void fatToName(const char *raw, char *name) {
  size_t base = 8, ext = 3;
  while (base && raw[base - 1] == ' ') {
    base--;
  }
  while (ext && raw[8 + ext - 1] == ' ') {
    ext--;
  }
  memcpy(name, raw, base);
  name[base] = 0;
  if (ext) {
    name[base] = '.';
    memcpy(name + base + 1, raw + 8, ext);
    name[base + 1 + ext] = 0;
  }
}

static bool fits83(const char *name) {
  const char *dot = strchr(name, '.');
  size_t base = dot ? (size_t)(dot - name) : strlen(name);
  size_t ext = dot ? strlen(dot + 1) : 0;
  if (!base || base > 8 || ext > 3 || (dot && strchr(dot + 1, '.'))) {
    return false;
  }
  for (const char *c = name; *c; c++) {
    if (c != dot && !isalnum((unsigned char)*c) &&
        !strchr("!#$%&'()-@^_`{}~", *c)) {
      return false;
    }
  }
  return true;
}

static unsigned blocks(uint32_t size) {
  uint32_t count = (size + 511) / 512;
  return count > 65535 ? 65535 : count;
}

static void addLine(const char *format, ...) {
  va_list args;
  va_start(args, format);
  int length = vsnprintf(text + textUsed, TEXT_SIZE - textUsed, format, args);
  va_end(args);
  if (length >= 0 && textUsed + length + 1 <= TEXT_SIZE) {
    textUsed += length + 1;
    lineCount++;
  }
}

// The volume label, the way a 1541 heads its directory with the disk name;
// "FLOPPY" on a disk without one.
static void readLabel(char *label) {
  strcpy(label, "FLOPPY");
  File32 root;
  if (!root.openRoot(&fat)) {
    return;
  }
  DirFat_t entry;
  while (root.read(&entry, sizeof entry) == (int)sizeof entry &&
         entry.name[0] != FAT_NAME_FREE) {
    if (entry.name[0] == FAT_NAME_DELETED ||
        entry.attributes == FAT_ATTRIB_LONG_NAME ||
        !(entry.attributes & FAT_ATTRIB_LABEL)) {
      continue;
    }
    size_t length = 11;
    while (length && entry.name[length - 1] == ' ') {
      length--;
    }
    for (size_t i = 0; i < length; i++) {
      char c = entry.name[i];
      label[i] = (c >= 0x20 && c < 0x7F && c != '"') ? toupper(c) : '?';
    }
    if (length) {
      label[length] = 0;
    }
    break;
  }
  root.close();
}

// The directory as program lines, in the format LOAD "$" uses for the card.
// In the order of the disk, as on a 1541 - drivesim.py sorts, a folder on the
// Mac having no order of its own. Names that do not fit 8.3 are left out, and
// so are the dot files a Mac leaves behind.
static bool directoryLines() {
  textUsed = 0;
  lineCount = 0;
  char label[12];
  readLabel(label);
  addLine("0 \"%s\"", label);

  unsigned number = 1;
  File32 root, file;
  if (!root.openRoot(&fat)) {
    return false;
  }
  while (file.openNext(&root, O_RDONLY)) {
    char name[64];
    size_t got = file.getName(name, sizeof name);
    bool isDir = file.isDir();
    uint32_t size = file.fileSize();
    file.close();
    if (!got || name[0] == '.' || !fits83(name)) {
      continue;
    }
    for (char *c = name; *c; c++) {
      *c = toupper(*c);
    }
    if (isDir) {
      addLine("%u \"%-13s  DIR\"", number++, name);
    } else {
      addLine("%u \"%-13s%5u\"", number++, name, blocks(size));
    }
  }
  bool ok = !root.getError();
  root.close();

  int32_t free = fat.freeClusterCount();
  if (free < 0) {
    addLine("%u \"??? BLOCKS FREE\"", number);
  } else {
    addLine("%u \"%lu BLOCKS FREE\"", number,
            (unsigned long)free * fat.sectorsPerCluster());
  }
  return ok;
}

// The lines of a .BAS file the way the card hands them over: control
// characters dropped, tabs made spaces, empty lines left out - BASIC sends no
// ACK for an empty line, so one would stop the transfer. In place: no line
// comes out longer than it went in, and its NUL takes the place of its CR or
// LF - the last one needs the byte after the file.
static void fileLines(size_t size) {
  const char *stop = (const char *)memchr(text, 0x1A, size);  // DOS end of file
  if (stop) {
    size = stop - text;
  }
  size_t out = 0, start = 0;
  lineCount = 0;
  for (size_t in = 0; in <= size; in++) {
    char c = in < size ? text[in] : '\n';
    if (c == '\r' || c == '\n') {
      size_t length = out - start;
      while (length && text[start + length - 1] == ' ') {
        length--;
      }
      if (length) {
        text[start + length] = 0;
        if (length > MAX_LINE) {
          say("line longer than %u characters, BASIC keeps the start: %s",
              (unsigned)MAX_LINE, text + start);
        }
        start += length + 1;
        lineCount++;
      }
      out = start;
      continue;
    }
    if (c == '\t') {
      c = ' ';
    }
    if (c >= ' ' && c <= '~') {
      text[out++] = c;
    }
  }
  textUsed = out;
}

// The file as the listing came in. A file that is there already gives back
// its room; a SAVE that still does not fit leaves it alone.
static const char *writeFile(const char *name) {
  const char *error = driveOpen();
  if (error) {
    return error;
  }
  if (floppy.get_write_protect()) {
    return "26,WRITE PROTECT ON";
  }
  uint32_t started = millis();
  int32_t free = fat.freeClusterCount();
  if (free < 0) {
    return "20,READ ERROR";
  }
  uint32_t cluster = fat.bytesPerCluster();
  File32 old = fat.open(name, O_RDONLY);
  if (old) {
    if (!old.isDir()) {
      free += (old.fileSize() + cluster - 1) / cluster;
    }
    old.close();
  }
  if ((textUsed + cluster - 1) / cluster > (uint32_t)free) {
    return "72,DISK FULL";
  }

  File32 file = fat.open(name, O_WRONLY | O_CREAT | O_TRUNC);
  bool ok = (bool)file;
  if (ok) {
    ok = file.write(text, textUsed) == textUsed;
    ok = file.close() && ok;
  }
  ok = disk.syncDevice() && ok;
  lastUse = millis();
  if (!ok) {
    // Whatever is left in the caches is not to be trusted any more - read
    // the disk afresh next time.
    mounted = false;
    say("cannot write %s", name);
    return "25,WRITE ERROR";
  }
  say("wrote %s, %u lines in %lu ms", name, lineCount,
      (unsigned long)(millis() - started));
  return "00,OK";
}

// The disk name of format: up to 11 letters, digits, spaces and the signs FAT
// allows, in capitals. False for anything else.
static bool makeLabel(const char *from, char *label) {
  size_t length = strlen(from);
  while (length && from[length - 1] == ' ') {
    length--;
  }
  if (length > 11) {
    return false;
  }
  for (size_t i = 0; i < length; i++) {
    char c = toupper((unsigned char)from[i]);
    if (!isalnum((unsigned char)c) && !strchr(" !#$%&'()-@^_`{}~", c)) {
      return false;
    }
    label[i] = c;
  }
  label[length] = 0;
  return true;
}

// --- the commands ------------------------------------------------------------

static void doLoad(const char *raw) {
  char name[13];
  fatToName(raw, name);
  const char *error = driveOpen();
  if (error) {
    status(error);
    return;
  }
  uint32_t started = millis();
  File32 file = fat.open(name, O_RDONLY);
  if (!file || file.isDir()) {
    file.close();
    status("62,FILE NOT FOUND");
    return;
  }
  uint32_t size = file.fileSize();
  if (size >= TEXT_SIZE) {
    file.close();
    status("52,FILE TOO LARGE");
    return;
  }
  int got = file.read(text, size);
  file.close();
  lastUse = millis();
  if (got != (int)size) {
    status("20,READ ERROR");
    return;
  }
  say("read %s, %lu bytes in %lu ms", name, (unsigned long)size,
      (unsigned long)(millis() - started));
  fileLines(size);
  status("00,OK");
  sendLines();
}

static void doDirectory() {
  const char *error = driveOpen();
  if (error) {
    status(error);
    return;
  }
  bool ok = directoryLines();
  lastUse = millis();
  if (!ok) {
    status("20,READ ERROR");
    return;
  }
  status("00,OK");
  sendLines();
}

static void doSave(const char *raw) {
  char name[13];
  fatToName(raw, name);
  if (!fits83(name)) {
    status("33,SYNTAX ERROR");
    return;
  }
  const char *error = driveOpen();
  if (error) {
    status(error);
    return;
  }
  if (floppy.get_write_protect()) {
    status("26,WRITE PROTECT ON");
    return;
  }
  status("00,OK");

  // The motor stays on while the listing comes in: the file goes to disk
  // right after it.
  keepSpinning = true;
  bool tooLarge;
  bool complete = receiveListing(tooLarge);
  keepSpinning = false;
  lastUse = millis();
  if (!complete) {
    return;
  }
  if (tooLarge) {
    status("52,FILE TOO LARGE");
    return;
  }
  saving = true;
  lastSign = millis();
  const char *result = writeFile(name);
  saving = false;
  status(result);
}

// format [720] [NAME], typed on the USB port
static void doFormat(const char *args) {
  while (*args == ' ') {
    args++;
  }
  bool dd = strncmp(args, "720", 3) == 0 && (!args[3] || args[3] == ' ');
  if (dd) {
    args += 3;
    while (*args == ' ') {
      args++;
    }
  }
  char label[12];
  if (!makeLabel(args, label)) {
    say("a disk name is up to 11 letters, digits, spaces and !#$%%&'()-@^_`{}~");
    return;
  }
  const char *error = driveSpin();
  if (!error) {
    error = diskIn();
  }
  if (!error && floppy.get_write_protect()) {
    error = "26,WRITE PROTECT ON";
  }
  uint32_t started = millis();
  if (!error) {
    say("formatting as %s, named \"%s\" - what is on the disk is lost",
        dd ? "720 KB" : "1.44 MB", label);
    error = disk.format(dd, label);
  }
  lastUse = millis();
  if (error) {
    say("format: %s", error);
  } else {
    say("formatted in %lu s", (unsigned long)(millis() - started) / 1000);
  }
  // What the machine sent meanwhile, it has long given up waiting for.
  while (Serial1.available()) {
    trace('<', Serial1.read());
  }
}

// dump SECTOR, typed on the USB port: 16 bytes a line, and as text
static void doDump(const char *args) {
  char *end;
  unsigned long sector = strtoul(args, &end, 0);
  if (end == args) {
    say("dump which sector?");
    return;
  }
  const char *error = driveSpin();
  if (!error && (!mounted || floppy.get_ready_sense())) {
    error = diskIn();
    if (!error) {
      error = disk.mount();
    }
  }
  uint8_t s[SECTOR];
  if (!error && !disk.readSector(sector, s)) {
    error = "20,READ ERROR";
  }
  lastUse = millis();
  if (error) {
    say("dump: %s", error);
    return;
  }
  for (size_t row = 0; row < SECTOR; row += 16) {
    char line[80];
    int n = snprintf(line, sizeof line, "%03X:", (unsigned)row);
    for (size_t i = 0; i < 16; i++) {
      n += snprintf(line + n, sizeof line - n, " %02X", s[row + i]);
    }
    line[n++] = ' ';
    for (size_t i = 0; i < 16; i++) {
      uint8_t c = s[row + i];
      line[n++] = c >= 0x20 && c < 0x7F ? c : '.';
    }
    line[n] = 0;
    say("%s", line);
  }
}

// A line typed on the USB port, run between two commands of the machine: a
// format keeps the drive for minutes.
static void runUsbCommand() {
  if (!usbCommand[0]) {
    return;
  }
  char line[sizeof usbCommand];
  strcpy(line, usbCommand);
  usbCommand[0] = 0;
  say("usb: %s", line);
  if (strncmp(line, "format", 6) == 0 && (!line[6] || line[6] == ' ')) {
    doFormat(line + 6);
  } else if (strncmp(line, "dump ", 5) == 0) {
    doDump(line + 5);
  } else {
    say("commands: v, format [720] [NAME], dump SECTOR");
  }
}

void setup() {
  // The drive lines first: deselected, motor off, write gate shut.
  floppy.begin();
  // A step every 4 ms instead of 22: step() waits step_delay_us / 1000 + 1 ms
  // twice for each, and a 3.5" drive takes one every 3 ms.
  floppy.step_delay_us = 1000;
  pinMode(LED_BUILTIN, OUTPUT);
  digitalWrite(LED_BUILTIN, LOW);

  Serial.begin(115200);
  Serial1.setTX(ACIA_TX_PIN);
  Serial1.setRX(ACIA_RX_PIN);
  Serial1.setFIFOSize(4096);
  Serial1.begin(BAUD);

  // A command BASIC sent while this was starting never arrived. If it is
  // still waiting for the answer, ENQ makes it send the command again; at
  // the prompt it is ignored like every control character.
  linkByte(ENQ);
  say("ready");
}

void loop() {
  char command[41];
  if (!readCommand(command, sizeof command)) {
    runUsbCommand();
    return;
  }
  say("<- %s", command);
  if (strcmp(command, "$") == 0) {
    doDirectory();
  } else if ((command[0] == 'L' || command[0] == 'S') && command[1] == ' ') {
    char raw[12];
    size_t length = strlen(command + 2);
    if (length > 11) {
      length = 11;
    }
    memcpy(raw, command + 2, length);
    memset(raw + length, ' ', 11 - length);
    raw[11] = 0;
    if (command[0] == 'L') {
      doLoad(raw);
    } else {
      doSave(raw);
    }
  } else {
    status("31,SYNTAX ERROR");
  }
}

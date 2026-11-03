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
// The USB port carries a log of every command (any terminal, any baud rate).
// Typing v there adds every byte on the wire and the steps of the head.

#include <stdarg.h>
#include <SdFat.h>
#include <Adafruit_Floppy.h>

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

Adafruit_Floppy floppy(DENSITY_PIN, INDEX_PIN, SELECT_PIN, MOTOR_PIN, DIR_PIN,
                       STEP_PIN, WRDATA_PIN, WRGATE_PIN, TRK0_PIN, PROT_PIN,
                       READ_PIN, SIDE_PIN, DSKCHG_PIN);
Adafruit_MFM_Floppy mfm(&floppy);   // detects 720 KB and 1.44 MB from the boot sector
FatVolume fat;

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
static bool verbose;        // every byte on the wire to the log

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
    if (Serial.read() == 'v') {
      verbose = !verbose;
      floppy.debug_serial = verbose ? &Serial : nullptr;
      say("byte log %s", verbose ? "on" : "off");
    }
  }
}

// --- the drive ---------------------------------------------------------------

static void driveOff() {
  floppy.spin_motor(false);
  floppy.select(false);
  motorOn = false;
  digitalWrite(LED_BUILTIN, LOW);
}

// Selects the drive, spins it up and makes sure fat holds the disk that is in
// it. nullptr when it does, else the status line that says why not.
static const char *driveOpen() {
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

  // DSKCHG goes active when the disk comes out and stays so until the head
  // steps with a disk in - a swap while the motor was off still shows. Only
  // while the drive is selected, though.
  if (mounted && !floppy.get_ready_sense()) {
    return nullptr;
  }
  mounted = false;
  mfm.removed();
  uint32_t started = millis();
  floppy.goto_track(1);
  floppy.goto_track(0);
  if (floppy.get_ready_sense()) {
    say("DSKCHG stays active - no disk in the drive");
    driveOff();
    return "74,DRIVE NOT READY";
  }
  if (!mfm.inserted(AUTODETECT)) {
    say("no PC format on this disk");
    return "20,READ ERROR";
  }
  if (!fat.begin(&mfm)) {
    say("no FAT file system on this disk");
    return "20,READ ERROR";
  }
  mounted = true;
  say("disk in: %u tracks of %u sectors, read in %lu ms",
      mfm.tracks_per_side(), mfm.sectors_per_track(),
      (unsigned long)(millis() - started));
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

// The next command line. Bytes outside a line - an ACK left over, a CAN from a
// transfer given up - are not commands and are dropped.
static void readCommand(char *line, size_t size) {
  size_t length = 0;
  for (;;) {
    int byte = linkRead(1000);
    if (byte < 0) {
      continue;
    }
    if (byte == CR) {
      if (length) {
        line[length] = 0;
        return;
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
  ok = mfm.syncDevice() && ok;
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
  if (mfm.sectors_per_track() != MFM_IBMPC1440K_SECTORS_PER_TRACK) {
    // Adafruit_MFM_Floppy writes a disk it detected for itself at the bit
    // rate of a 1.44 MB one, whatever it read it at - a 720 KB disk would be
    // left unreadable.
    status("26,720 KB READ ONLY");
    return;
  }
  status("00,OK");

  // The motor stays on while the listing comes in: the file goes to disk
  // right after it, and BASIC gives the second answer only ten seconds.
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
  status(writeFile(name));
}

void setup() {
  // The drive lines first: deselected, motor off, write gate shut.
  floppy.begin();
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
  readCommand(command, sizeof command);
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

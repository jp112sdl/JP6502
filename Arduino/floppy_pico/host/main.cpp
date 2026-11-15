// picohost FOLDER: floppy_pico.ino on the Mac. The sketch runs as it is, on the
// SdFat and the MFM code of the Pico build; what is missing is the drive, and
// mock/Adafruit_Floppy.h stands in for that. Its disk starts blank, formatted
// by the sketch, with the files of FOLDER on it. The 6502 is at the other end
// of standard input and output, see the Makefile - and when it is gone, FOLDER
// gets what is on the disk then.
#include <csignal>
#include <dirent.h>
#include <set>
#include <sys/stat.h>

bool driveLive;

#include "../floppy_pico.ino"

UsbLog Serial;
AciaLink Serial1;

static std::string folder;
static std::set<std::string> brought;   // the files that came from the folder

// FAT does not tell capitals from small letters, and neither does the Mac
static std::string plain(std::string name) {
  for (char &c : name) {
    c = tolower((unsigned char)c);
  }
  return name;
}

// A blank disk - of 720 KB with PICO_SPT=9 - with the files of the folder on it
static void toDisk() {
  std::set<std::string> names;
  if (DIR *dir = opendir(folder.c_str())) {
    while (dirent *entry = readdir(dir)) {
      struct stat st;
      if (entry->d_name[0] != '.' && !stat((folder + "/" + entry->d_name).c_str(), &st) &&
          S_ISREG(st.st_mode)) {
        names.insert(entry->d_name);
      }
    }
    closedir(dir);
  }

  Serial.quiet = true;
  bool ok = !disk.format(envInt("PICO_SPT", 18) == 9, "") && !disk.mount() && fat.begin(&disk);
  for (const std::string &name : names) {
    FILE *from = fopen((folder + "/" + name).c_str(), "rb");
    File32 to = fat.open(name.c_str(), O_WRONLY | O_CREAT | O_TRUNC);
    char buffer[512];
    size_t count;
    while (from && to && (count = fread(buffer, 1, sizeof buffer, from)) > 0) {
      ok = to.write(buffer, count) == count && ok;
    }
    ok = from && to && to.close() && ok;
    if (from) {
      fclose(from);
    }
    brought.insert(plain(name));
  }
  ok = disk.syncDevice() && ok;
  disk.forget();
  Serial.quiet = false;
  if (!ok) {
    fprintf(stderr, "mock: the files of %s do not go onto the disk\n", folder.c_str());
    exit(1);
  }
}

// A directory of the disk into one of the Mac; names gets what it holds
static void copyOut(File32 &dir, const std::string &to, std::set<std::string> *names) {
  File32 file;
  while (file.openNext(&dir, O_RDONLY)) {
    char name[256];
    file.getName(name, sizeof name);
    std::string path = to + "/" + name;
    if (file.isDir()) {
      mkdir(path.c_str(), 0777);
      copyOut(file, path, nullptr);
    } else if (FILE *out = fopen(path.c_str(), "wb")) {
      char buffer[512];
      int count;
      while ((count = file.read(buffer, sizeof buffer)) > 0) {
        fwrite(buffer, 1, count, out);
      }
      fclose(out);
    }
    if (names) {
      names->insert(plain(name));
    }
    file.close();
  }
}

// What is on the disk now, into the folder. A file that came from there and
// is gone from the disk is gone from the folder too.
static void toFolder() {
  driveLive = false;
  Serial.quiet = true;
  disk.forget();
  File32 root;
  if (disk.mount() || !fat.begin(&disk) || !root.openRoot(&fat)) {
    return;
  }
  std::set<std::string> there;
  copyOut(root, folder, &there);
  for (const std::string &name : brought) {
    if (!there.count(name)) {
      unlink((folder + "/" + name).c_str());
    }
  }
}

int main(int argc, char **argv) {
  if (argc < 2) {
    fprintf(stderr, "usage: picohost FOLDER\n");
    return 1;
  }
  folder = argv[1];
  signal(SIGPIPE, SIG_IGN);     // the machine may go while the sketch still talks
  toDisk();
  atexit(toFolder);
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
  driveLive = true;
  setup();
  for (;;) {
    loop();
  }
}

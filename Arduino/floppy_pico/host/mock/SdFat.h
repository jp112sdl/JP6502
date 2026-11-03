// SdFat as far as floppy_pico.ino uses it, over a folder on the Mac - the way
// drivesim.py treats one, a 1.44 MB disk of 2847 blocks.
#pragma once
#include <dirent.h>
#include <string>
#include <strings.h>
#include <sys/stat.h>

extern std::string mockFolder;

typedef struct {
  uint8_t name[11];
  uint8_t attributes;
  uint8_t rest[20];
} DirFat_t;
const uint8_t FAT_NAME_FREE = 0x00;
const uint8_t FAT_NAME_DELETED = 0xE5;
const uint8_t FAT_ATTRIB_LABEL = 0x08;
const uint8_t FAT_ATTRIB_LONG_NAME = 0x0F;

class Adafruit_MFM_Floppy;
class FatVolume;

class File32 {
public:
  explicit operator bool() const { return isOpen; }
  bool openRoot(FatVolume *) {
    dp = opendir(mockFolder.c_str());
    isOpen = isdir = dp != nullptr;
    return isOpen;
  }
  bool openNext(File32 *dir, int) {
    while (dirent *e = readdir(dir->dp)) {
      if (!strcmp(e->d_name, ".") || !strcmp(e->d_name, "..")) {
        continue;
      }
      struct stat st;
      if (stat((mockFolder + "/" + e->d_name).c_str(), &st)) {
        continue;
      }
      name = e->d_name;
      isdir = S_ISDIR(st.st_mode);
      size = isdir ? 0 : st.st_size;
      isOpen = true;
      return true;
    }
    return false;
  }
  size_t getName(char *buffer, size_t space) {
    if (name.size() + 1 > space) {
      return 0;
    }
    strcpy(buffer, name.c_str());
    return name.size();
  }
  bool isDir() const { return isdir; }
  uint32_t fileSize() const { return size; }
  int getError() const { return 0; }
  int read(void *buffer, size_t count) {
    return fp ? (int)fread(buffer, 1, count, fp) : 0;   // a directory has no raw entries here
  }
  size_t write(const void *buffer, size_t count) {
    return fp ? fwrite(buffer, 1, count, fp) : 0;
  }
  bool close() {
    bool ok = true;
    if (fp) {
      ok = fclose(fp) == 0;
    }
    if (dp) {
      closedir(dp);
    }
    fp = nullptr;
    dp = nullptr;
    isOpen = isdir = false;
    return ok;
  }

  FILE *fp = nullptr;
  DIR *dp = nullptr;
  bool isOpen = false, isdir = false;
  std::string name;
  uint32_t size = 0;
};

class FatVolume {
public:
  bool begin(Adafruit_MFM_Floppy *) { return true; }
  uint8_t sectorsPerCluster() const { return 1; }
  uint16_t bytesPerCluster() const { return 512; }

  // FAT names match whatever the case
  static std::string find(const char *name) {
    std::string hit;
    if (DIR *d = opendir(mockFolder.c_str())) {
      while (dirent *e = readdir(d)) {
        if (!strcasecmp(e->d_name, name)) {
          hit = e->d_name;
          break;
        }
      }
      closedir(d);
    }
    return hit;
  }

  File32 open(const char *path, int oflag) {
    File32 file;
    std::string hit = *path ? find(path) : "";
    struct stat st;
    if ((oflag & O_ACCMODE) == O_RDONLY) {
      if (hit.empty() || stat((mockFolder + "/" + hit).c_str(), &st)) {
        return file;
      }
      file.name = hit;
      file.isdir = S_ISDIR(st.st_mode);
      if (!file.isdir) {
        file.fp = fopen((mockFolder + "/" + hit).c_str(), "rb");
        file.size = st.st_size;
      }
      file.isOpen = file.isdir || file.fp;
      return file;
    }
    std::string upper = path;
    for (char &c : upper) {
      c = toupper(c);
    }
    std::string full = mockFolder + "/" + (hit.empty() ? upper : hit);
    if (!stat(full.c_str(), &st) && S_ISDIR(st.st_mode)) {
      return file;
    }
    file.fp = fopen(full.c_str(), "wb");
    file.isOpen = file.fp != nullptr;
    return file;
  }

  int32_t freeClusterCount() {
    int32_t used = 0;
    if (DIR *d = opendir(mockFolder.c_str())) {
      while (dirent *e = readdir(d)) {
        struct stat st;
        if (!stat((mockFolder + "/" + e->d_name).c_str(), &st) && S_ISREG(st.st_mode)) {
          used += (st.st_size + 511) / 512;
        }
      }
      closedir(d);
    }
    return used > 2847 ? 0 : 2847 - used;
  }
};

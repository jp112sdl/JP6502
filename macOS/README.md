# JP6502 Control

A macOS front end for the three things this project is normally driven with
from a Terminal: `make`, the FlashPROMv2 programmer, and the two BASIC transfer
tools. It does not reimplement any of them - it runs the same `make` and the
same Python scripts that are in the repository, so what happens here and what
happens in a Terminal cannot drift apart.

Open `JP6502Control.xcodeproj` in Xcode and run it. Requires macOS 14.

A built copy is in `dist/JP6502Control.app`, universal and signed to run
locally, so the app can be started without opening Xcode at all. It is signed
ad hoc, which means it runs on the machine that built it: another Mac will hold
it at Gatekeeper until it is opened once from the context menu, or rebuilt
there. It is a committed build rather than a released one, so it is only as
current as the last time somebody remembered to refresh it:

    xcodebuild -project JP6502Control.xcodeproj -scheme JP6502Control \
        -configuration Release -derivedDataPath build/DerivedData build
    rm -rf dist/JP6502Control.app
    cp -R build/DerivedData/Build/Products/Release/JP6502Control.app dist/

The app looks for the checkout at the path it was built from. If that is not
where it is, Settings is where to point it.

## What each tab does

**Build** runs `make` in `Software`. Everything, everything with checksums
(`test`), the memory map check (`mapdoc`), `clean`, or one ROM project or
loadable program on its own - those are built by naming the file the makefile
produces, so a single project goes through the same rule as a full build.
The project lists come from `Software/makefile`, so adding one there is enough
for it to appear in the picker.

The clock the ROM is timed for is picked here too, and handed to make as
`CLOCK_MODE`. The modes come from the conditional in `Software/common/makefile`
that turns each one into a `clock_mode_flag`, so the picker offers exactly what
the makefile accepts. Leaving it on "as the makefile has it" passes nothing and
takes its default. Changing it rebuilds everything, which is the makefile's
doing rather than this app's: every object depends on a file holding the flags
it was built with, so a 2 MHz ROM cannot end up with 1 MHz delay loops linked
into it.

**GeckOS** runs `make` in `GeckOS-V2/arch/jp6502`, which is its own makefile
with its own way of naming things: the clock is whole MHz passed as `CLOCK`,
not a `CLOCK_MODE` name, and `SHELLS` decides whether the OS comes up with a
shell on the VDP console, on the serial line, or on both. `FG` and `BG` are
the colours of the text screen, picked from the sixteen of the TMS9918 with a
preview of the boot screen next to them. It builds the ROM image
(`boot/geckos.bin`), or the programs for the card (`make sdcard`), or cleans.
The ROM is reassembled on every build, so the switches take effect without
anything being edited. `make run`, which puts the emulator's serial
line on a terminal, is the one target the tab leaves out - it needs a Terminal.

The same tab copies the programs onto the card. Removable volumes are offered
with the filesystem macOS reports, so a card that is not FAT32 says so before
anything is written, and any folder can be picked instead. The copy goes into
the root of the card over anything of the same name and leaves the rest of the
card alone.

Then it removes the `._` files. macOS attaches a `com.apple.provenance`
attribute to every file it writes, and on a FAT card an extended attribute is
stored in an AppleDouble beside the file - `._lsh` next to `lsh`. `cp -X` does
not prevent it, clearing the attribute on the source does not either, and a
plain `dd` write produces one too, so they are deleted afterwards instead. That
sticks: on FAT the `._` file is the only place the attribute lives. Without it
GeckOS lists thirty entries where it should list fifteen.

GeckOS-V2 is a submodule, so the tab says so rather than failing if the
checkout was cloned without `--recursive`. Building it needs `xa` 2.4.1 or
later with `file65` and `reloc65` from the same package; the tab shows where it
found each of them.

**Flash** runs `FlashPROMv2/tools/flashtool.py`: write, verify, read, erase,
blank check, chip info, device selection and data protection, with the
programmer's port, baud rate, bootloader wait and chip override. The file to
write is picked from what is in `Software/build/rom`, from the GeckOS ROM, or
from anywhere on disk - and the GeckOS tab can hand its ROM straight over. The
chip names come from `FlashPROMv2/Device.h`.

**BASIC** runs `Software/tools/basicsend.py` and `basicrecv.py` against the
6502's own 6551 port - a different cable and a different baud rate from the
programmer, which is why the two tabs remember their ports separately. Sending
offers the programs in `Software/basic`; receiving writes a file or just shows
the listing. Both wait two minutes for the machine, so `LOAD "@"` or `SAVE "@"`
can be typed before or after pressing the button.

**Settings** is where the checkout lives, and which `python` and `make` to use.

## The four things that are not obvious

**PATH.** An app launched from the Finder inherits `/usr/bin:/bin:/usr/sbin:/sbin`
and nothing else, and `ca65` is not there. Every tool is started with the PATH a
login shell reports instead, which is what makes a build from here behave like a
build from a Terminal.

**Which python.** Machines tend to have several, and only some of them have
pyserial installed. The first launch picks the first python on PATH that can
import it rather than the first one it finds; Settings says which was chosen and
whether it has the module.

`make` is also handed `PYTHON_BINARY` and `MD5_BINARY`, because the makefile
defaults to `python` and `md5sum` and a stock macOS has neither.

**CC65_HOME.** `ca65` is meant to fall back on a search path compiled into it,
and on some installs it has none that works: every `.s` cc65 generates begins
with `.macpack longbranch`, and without the variable that stops at

    Cannot open include file 'longbranch.mac': No such file or directory

which is what the C projects die on. The same install cannot find its own
`stdlib.h` either. The app detects the prefix - next to the `bin` that holds the
`ca65` actually being used, then the usual places - checks that
`asminc/longbranch.mac` is under it, and hands it to `make` as `CC65_HOME`.
That one variable covers `asminc`, `include`, `lib` and `cfg`, where `CA65_INC`
would only cover the first. Settings shows what was found and says so when
nothing was.

Nothing else in the build changes: the makefile passes its own `-I` and `-C`
explicitly, and those come first. A build from a Terminal needs the same
variable, so it is worth exporting from a shell profile as well.

**Why the output is live.** A C program line-buffers to a terminal and
block-buffers to anything else, so `make` on a pipe says nothing at all until it
exits. Every tool is given a pseudo terminal as its stdout instead, which is
what makes the log fill in as the build works. stderr stays an ordinary pipe -
it is unbuffered anyway, and keeping it separate is what lets errors be shown in
red.

## Cancelling

The tools are started through `/usr/bin/env`, which execs them, so the process
the app can signal really is `make` or `python`. Cancel sends SIGINT - the same
thing Ctrl+C sends - and the transfer tools handle it and leave the port tidy.
A cancelled transfer still needs Ctrl+C on the 6502 to get it out of `LOAD` or
`SAVE`.

## The icon

`Icon/RenderIcon.swift` draws it - a ceramic 40 pin DIP, which is the package
the 6502 came in - and writes the PNGs that go into
`JP6502Control/Assets.xcassets/AppIcon.appiconset`. It is not part of the app
target; run it by hand if the icon is ever to be changed:

    swiftc -O -o /tmp/rendericon Icon/RenderIcon.swift
    /tmp/rendericon JP6502Control/Assets.xcassets/AppIcon.appiconset

The drawing is in fractions of the canvas and is run once per size rather than
shrunk from one large rendering, which is why the pin count and the lettering
drop away at the sizes too small to hold them.

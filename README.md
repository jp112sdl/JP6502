![Image of JP6502 Monitor](/images/monitor.jpeg "JP6502 Computer Monitor")
![Image of JP6502 Breadboard](/images/breadboard_full.jpeg "JP6502 Computer Breadboard")

# JP6502 - a 6502-based breadboard computer inspired by EUNICE

## Specifications
```
WDC 65C02 CPU @1MHz
Winbond W29C020 Flash PROM
HMS62256A SRAM 32K
WDC 65C22 VIA
Rockwell R6551 ACIA
TI SN76489 PSG
FTDI FT232R USB UART
2004 LCD display
PS2 Keyboard with German Layout
D-pad
SD Card slot
```
## Memory Map
```
RAM  $0000 - $7FFF
VDP  $8080
VIA3 $8200
ACIA $8400
VIA2 $8800
VIA1 $9000
ROM  $A000 - $FFFF
```
See [Software/MEMORY_MAP.md](Software/MEMORY_MAP.md) for the detailed layout of
zero page, system RAM buffers, BSS, the loadable module area and the ROM segments.
## IO
```
VIA1 - LCD
VIA2 - Sound and LED
VIA3 - Keyboard and SD card
ACIA - Serial
```
## TO-DO

- [x] Load/save Basic program from SD
- [x] Load/save Basic program via Serial (FTDI)
- [x] BASIC in ROM
- [x] TMS9918 VDP
- [x] SD card FAT32 support
- [x] SD card program storage
- [x] SN76489 PSG in OS1
- [x] Handle IRQ
- [x] PS/2 keyboard interface
- [x] Add the 3rd 6522 VIA
- [x] Install OS/1
- [x] On-board LEDs connect to VIA
- [x] use Graphics Mode in Microsoft BASIC
- [x] use DPAD in Microsoft BASIC

## Getting the sources

`FlashPROMv2` is a submodule, so a plain `git clone` leaves it empty:

```
git clone --recurse-submodules https://github.com/jp112sdl/JP6502.git
```

For a checkout that is already there:

```
git submodule update --init --recursive
```

## What's in the repo

### `Software`

The programs the machine runs, and the toolchain that builds them. `rom` holds
the ROM projects - among them `os1`, `microsoft_basic` and `minimal_bootloader`
- and `load` the loadable modules that a running machine can be sent without
reflashing. `common` has the shared sources, include files and linker configs,
`basic` a few example BASIC listings, `tools` the Python scripts that talk to
the machine over the serial port, and `build` is where everything lands.

One `makefile` in `Software` builds all of it:

```
cd Software
make all        # every ROM image and every loadable program
make test       # the same, then an md5 of each binary
make mapdoc     # check the addresses in MEMORY_MAP.md against the linker output
make clean
```

`ADDRESS_MODE` picks the address decoder and defaults to `ext`.

`tools/basicsend.py` and `tools/basicrecv.py` move a BASIC listing over the
6551's serial port, with `LOAD "@"` or `SAVE "@"` typed on the machine at the
other end:

```
./tools/basicsend.py SNAKE.BAS
./tools/basicrecv.py SNAKE.BAS
```

[Software/README.md](Software/README.md) is the long version, and
[Software/MEMORY_MAP.md](Software/MEMORY_MAP.md) has the layout down to the
individual zero page byte.

### `FlashPROMv2`

Submodule, from [jp112sdl/FlashPROMv2](https://github.com/jp112sdl/FlashPROMv2).
An ATmega128 sketch that drives a parallel flash device, plus
`tools/flashtool.py`, which is what writes a ROM image to the chip:

```
./FlashPROMv2/tools/flashtool.py write Software/build/rom/os1.ext.bin
```

It also verifies, dumps, erases whole chips or single sectors, and reports what
is in the socket. The chip names it knows come from `FlashPROMv2/Device.h`.

### `macOS`

A macOS front end for the three things above - `make`, the flash tool and the
two BASIC transfer scripts. It does not reimplement any of them; it runs the
same `make` and the same Python scripts that are in this repository. A built
copy is committed at `macOS/dist/JP6502Control.app`, so it can be started
without opening Xcode. See [macOS/README.md](macOS/README.md).

### `Schematics`

KiCAD projects for the board:

- `65C02_Computer` - the main schematic and PCB,
- `DB6502_v002` - the earlier revision it grew out of,

plus the bills of material. There is a dedicated
[README](Schematics/README.md) in the folder with the build-related details.

### `Arduino`

`keyboard_168P` - the sketch behind the PS/2 keyboard port, which turns the
keyboard into something the 6502 can read over a VIA. It is built for an
ATmega168P; the KiCAD schematic in `Schematics/65C02_Computer` still carries the
ATtiny4313 the upstream design used, so the board and the sketch disagree about
that chip until the schematic is redrawn.

### `Datasheets`

Every datasheet used while designing the machine, kept here so a pinout is
never more than one folder away.


# DB6502 - Dawid Buchwald's 6502 Computer

JP6502 is built on Dawid Buchwald's DB6502, and what follows is his own README,
kept because it is where the design and the reasoning behind it are explained.
It is written in his voice and describes his repository: for what is actually in
*this* one, see [What's in the repo](#whats-in-the-repo) above.

This repository contains all the work in progress during my build of Ben Eater's inspired 6502 8-bit computer similar to typical machines of the early 1980s. If you haven't seen Ben's videos, I would strongly suggest you start there:

[Ben Eater's 6502 project](https://eater.net/6502)

As stated above, this build is not 100% compatible with what Ben had done - and for a reason, described in next section.

If I had to explain shortly "what it is", the answer would be: simple, yet easy to expand, 8-bit CPU based computer designed and built with one goal only: to use it as a learning and tinkering platform to understand how computers really work. You can use it for simple things like understanding buses, clock cycles, instruction execution, but it also demonstrates more complex concepts like interrupts, interfaces to external components and device handling. More on that below. Everything, hopefully, is simple enough to wrap your head around by one person in couple of weeks.

## Why build something different

[Ben's videos](https://www.youtube.com/playlist?list=PLowKtXNTBypFbtuVMUVXNR0z1mu7dp7eH) on 6502 computer are absolutely awesome - it's one of the best sources in the whole Internet explaining how any computer works. The build he introduced is probably sufficient for most of the things you might ever want to build, and yet I decided to deviate from his design.

The rationale behind this project is pretty simple - the best way to test your understanding of certain subject is to try to expand on what you have learned. You never know if you understood something until you test it by introducing changes to original design - and I used this approach in this project to learn a lot. It was my first proper electronics project, so I would like to apologize for any mistakes. If you think something is off or could have been done differently - please go ahead and raise issue for the repo! All improvements are welcome!

## Why would you bother using DB6502 instead of BE6502

Basically, it gives you almost all the flexibility of Ben's buid without the hassle of breadboard connections for the critical components. You can still run all of Ben's programs (using second VIA port), but the days of looking for loose wire between RAM and CPU are over :) You can, obviously, still experiment with peripherals and breadboard connections using extension port and second VIA.

On top of that you get additional features like extra screen (via onboard connector), keyboard for more versatile input and finally all-in-one serial over USB terminal. You also get easy to use software ready to be installed on the machine to jumpstart your tinkering. When using bootloader you don't even have to flash the EEPROM more than once!

**Important note:** All of the content here is, and always will be open source and free to use, and I don't intend to make any profit out of it. The only way I get anything at all (and it's only small commission to be used for future PCBWay orders) is when you order my boards from PCBWay using the links posted below, but you are welcome to grab these gerber files and order the boards from another provider, or even from PCBWay, just by uploading gerbers to your account, if you don't want me to get the commission :)

## What is different

Compared to Ben's 6502 build I introduced the following changes:

1. Added [automatic power-up reset circuitry](Schematics/README.md#automatic-power-on-reset),
2. Changed [address decoder logic](Schematics/README.md#address-decoder-change) (**very important from compatibility perspective**),
3. Changed [LCD interface](Schematics/README.md#lcd-interface-change) from 8-bit to 4-bit (**very important from compatibility perspective**),
4. Added [additional VIA chip](Schematics/README.md#extra-via-chip) to provide easy expansion of the system,
5. Added [ACIA chip for serial communication](Schematics/README.md#extra-acia-chip-for-serial-communication),
6. Added (**optional - more on that later**) [USB-UART interface](Schematics/README.md#extra-usb-uart-interface-chip) for easy connectivity with PC,
7. Added [PS/2 keyboard port and keyboard controller with German Keyboard Layout](Schematics/README.md#ps2-keyboard-interface-and-attiny4313-based-controller) to provide proper replacement for five pushbuttons in Ben's design

You might be wondering if this means that you can't run Ben's programs on DB6502 - and the answer is **YES YOU CAN**. Indeed, some changes to the code are necessary, but thanks to the additional VIA chip and with some changes to the addressing mode you can run any program from Ben's videos. If you want to use LCD in 8-bit mode, you can also use the additional VIA for it, ignoring the built-in LCD connector.

By the way, the opposite is also true - **you can compile and run my programs on Ben's computer**. There are special compilation flags that enable usage of Ben's address decoder. I will describe this in more detail in software section.

Detailed description and rationale for each change is discussed in [Schematics README](Schematics/README.md).

## Getting started

Okay, so it should be pretty clear what this project is about, so how to start playing with it? That really depends on what you decide to do:

- Stick with BE6502 and just use subset of provided software (either to install it in EEPROM, or just use it as reference for your own hacking),
- Build your own breadboard design based on this one with any modifications you can think of,
- Order PCBs of DB6502, solder the components and run provided software to see how it works and get started with your own designs.

To start from scratch it's actually easiest to select last option - after some waiting you will end up having pretty solid base to extend your design on.

### Using provided software with BE6502

If you decide to go down that route, head straight to the `Software` folder, where you will find several programs either identical or similar to what Ben has shown in his videos, but built with much more versatile toolchain.

If you want to read more, go ahead and read [Software folder](Software/README.md) section. Make sure to check out the [building software](Software/README.md#building-software) subsection, as it explains how to compile programs to run on BE6502 directly.

### Build your own breadboard design

Maybe you have already started expanding on Ben's build, or maybe you are just considering it now. If you want to check out how I did certain things, jump right into `Schematics` [folder](Schematics/README.md), where you will find KiCAD projects for all the components used in this project. Obviously the most important one is the `65C02_Computer` project, but there are some additional goodies there.

**Please note:** This part is not very well documented, I have assumed that anybody willing to dig into these schematics already knows how to read them.

Most of the decisions made during the schematic design were explained above. Justification for anything not covered here can be probably found in the [invaluable 6502 primer](http://wilsonminesco.com/6502primer/).

### Using my PCB design

This will be explained in the most detail, obviously. Start with getting [the PCBs](Schematics/README.md#ordering-pcb). **Please note:** clock module is entirely optional, but really useful for single stepping or slow clocking required by Ben Eater's design of Arduino Mega based bus analyzer. As explained in number of places here, you can either order PCBs from PCBWay directly or use your manufacturer of choice - it should have no impact on the final result.


## Credits

This project would not be possible if not inspiration, support and help from many, many people:

- [Ben Eater](https://eater.net) - his videos inspired me to learn all this,
- [Dawid Buchwald](https://github.com/dbuchwald) - DB6502, the design and the software JP6502 is built on,
- [Dirk Grappendorf](https://grappendorf.net) - awesome documentation of his own 6502 project,
- [Wilson Mines Co.](http://wilsonminesco.com) - the best source of 6502-related information,
- [Dane Creek Photography](https://github.com/danecreekphotography) - for all his support and test driving the project,
- [u/transistorykris](https://www.reddit.com/user/transitorykris/) - his [KrisOS](https://github.com/transitorykris/krisos) is a great inspiration for my own OS development,
- [r/beneater community](https://www.reddit.com/r/beneater/) - for all the great ideas, feedback, creative spirit and exceptional support.

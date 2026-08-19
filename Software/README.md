# 6502 system software

This documentation provides necessary insight into software provided in the repository, and it is organized in the following sections:

- [Getting started with provided software](#getting-started-with-provided-software),
- [Building software](#building-software),
- [Detailed description of modules in software folder](#detailed-description-of-modules-in-software-folder).

## Getting started with provided software

Before discussing the details of the contents, I will show how to use sample programs for smoke testing of the soldered board.

I recommend running first couple of programs in slow clock mode, so with external clock module, with Arduino Mega based bus analyzer.

### Connecting Arduino Mega

First, make sure you have the 6502-monitor program installed on your Arduino Mega board. You will find it in `Arduino/6502-monitor` folder.

Connect pins as per following table:

| Expansion port pins   | Arduino Mega pins |
| --------------------- | ----------------- |
| D0-D7 (data bus)      | 53-39             |
| A00-A15 (address bus) | 52-22             |
| CLK (system clock)    | 2                 |
| R/W (read/write)      | 3                 |
| GND                   | GND               |
| +5V                   | +5V               |

**PLEASE NOTE: Connections are reversed for convenience. D0 is connected to pin 53, D1 to pin 51, A00 to pin 52 and A15 to pin 22.**

Also, connect clock module as follows:

| Computer connection          | Clock module connection |
| ---------------------------- | ----------------------- |
| CLK input (middle pin on J1) | CLK output              |
| UART +5V                     | +5V                     |
| UART GND                     | GND                     |

It might seem strange that the clock module is powered from UART port, but in fact it doesn't matter which of the power outputs you choose. I use this one, since this one is closes to the clock connector (J1). This is one thing I didn't consider when designing the PCB - I provided GND reference in J1, but the power is missing...

The whole thing will be powered from Arduino via USB - don't worry, the load will not be too high.

### Setting up development environment

Development environment requires the following tools:

- `make` to invoke all the below,
- `cc65` compiler, available [here](https://github.com/cc65/cc65),
- `minipro` software to upload ROM image to EEPROM, available [here](https://gitlab.com/DavidGriffith/minipro/),
- `hexdump` for testing the contents of the binaries,
- `md5sum` to generate binary checksum,
- `rm` and `mkdir` for folder/file manipulation,
- `picocom` for serial communication with the computer (Linux/MacOS),
- `ExtraPuTTy` for serial communication and upload (Windows specific),
- `sz` for loadable module upload via `picocom` (Linux/MacOS),
- `python` to run small utility written in Python to trim loadable modules and add start vector,
- `x6502` to run computer emulator (enables execution of generated binaries on PC), available [here](https://github.com/dbuchwald/x6502) - **please note: this one is optional, still in development, and lagging behind the actual computer.** Simple programs can be executed, but anything more complex than LCD operation (including ACIA/keyboard) don't work just yet.

One important thing to note is that you might need to install FTDI Virtual COM Port drivers, and it applies to all operating systems.

#### Setting up development environment under Linux

By default, Linux distro should contain most of the needed tools. You might need to install `git` to clone `cc65` and `minipro` repositories to build them. The latter requires also `pkg-config` package in Debian/Ubuntu. `sz` might not be available, so check your distro manual for details.

#### Setting up development environment under MacOS

You will probably need `brew` to install `make` and `git`. Tricky part is missing `md5sum` utility, which can be installed using:

```shell
brew install md5sha1sum
```

Other than that, `sz` will probably be missing, so you might need to install this one as well.

#### Setting up development environment under Windows

This one seems to cause most issues, while it's not really that difficult. You need to install [Cygwin](https://cygwin.com/), but while installing, make sure you add the following packages: `python2`, `pkg-config`, `git`, `make`. This should be enough to clone `cc65` and `minipro` repositories, and after building them make sure to issue `make avail` and `make install` respectively to enable invocation from command line.

For serial communication you can use regular PuTTy, but it doesn't have the feature of sending files using XModem protocol, required for loadable module support. Since this is important feature of this hardware/software stack, it's really recommended to use ExtraPuTTy instead.

**PLEASE NOTE:** You might be able to use virtual machines or Windows Subsystem for Linux (WSL) - but neither of the two worked correctly with `make install` target that uses TL866II+ programmer to flash the ROM. YMMV.

### Running the simplest possible program

Now you need to build the first program. Go to `Software/rom/nop_fill` folder and run:

```shell
make clean all test
```

You expect output similar to the following:

```text
$ make clean all test
rm -f ../../build/rom/*.bin \
	rm -f ../../build/rom/*.raw \
	../../build/rom/nop_fill/*.o \
	../../build/rom/nop_fill/*.lst \
	../../build/rom/nop_fill/*.s \
	../../build/rom/nop_fill/*.map \
	../../build/rom/nop_fill/*.d \
	../../build/rom/nop_fill/*.cdep \
	../../build/common/*.o \
	../../build/common/*.lst \
	../../build/common/*.s \
	../../build/common/*.d \
	../../build/common/*.cdep \
	../../build/lib/*.lib
ca65 --cpu 65C02 -Dclock_mode_flag=2  -Dacia_tx_irq=1  -Ddb6502 -I ../../common/include --create-dep ../../build/common/zeropage.d -o ../../build/common/zeropage.o -l ../../build/common/zeropage.lst ../../common/source/zeropage.s
ca65 --cpu 65C02 -Dclock_mode_flag=2  -Dacia_tx_irq=1  -Ddb6502 -I ../../common/include --create-dep ../../build/common/sysram_map.d -o ../../build/common/sysram_map.o -l ../../build/common/sysram_map.lst ../../common/source/sysram_map.s
ca65 --cpu 65C02 -Dclock_mode_flag=2  -Dacia_tx_irq=1  -Ddb6502 -I ../../common/include --create-dep ../../build/rom/nop_fill/nop_fill.d -o ../../build/rom/nop_fill/nop_fill.o -l ../../build/rom/nop_fill/nop_fill.lst nop_fill.s
ca65 --cpu 65C02 -Dclock_mode_flag=2  -Dacia_tx_irq=1  -Ddb6502 -I ../../common/include --create-dep ../../build/common/syscalls.d -o ../../build/common/syscalls.o -l ../../build/common/syscalls.lst ../../common/source/syscalls.s
ca65 --cpu 65C02 -Dclock_mode_flag=2  -Dacia_tx_irq=1  -Ddb6502 -I ../../common/include --create-dep ../../build/common/acia.d -o ../../build/common/acia.o -l ../../build/common/acia.lst ../../common/source/acia.s
ca65 --cpu 65C02 -Dclock_mode_flag=2  -Dacia_tx_irq=1  -Ddb6502 -I ../../common/include --create-dep ../../build/common/blink.d -o ../../build/common/blink.o -l ../../build/common/blink.lst ../../common/source/blink.s
ca65 --cpu 65C02 -Dclock_mode_flag=2  -Dacia_tx_irq=1  -Ddb6502 -I ../../common/include --create-dep ../../build/common/dpad.d -o ../../build/common/dpad.o -l ../../build/common/dpad.lst ../../common/source/dpad.s
ca65 --cpu 65C02 -Dclock_mode_flag=2  -Dacia_tx_irq=1  -Ddb6502 -I ../../common/include --create-dep ../../build/common/core.d -o ../../build/common/core.o -l ../../build/common/core.lst ../../common/source/core.s
ca65 --cpu 65C02 -Dclock_mode_flag=2  -Dacia_tx_irq=1  -Ddb6502 -I ../../common/include --create-dep ../../build/common/keyboard.d -o ../../build/common/keyboard.o -l ../../build/common/keyboard.lst ../../common/source/keyboard.s
ca65 --cpu 65C02 -Dclock_mode_flag=2  -Dacia_tx_irq=1  -Ddb6502 -I ../../common/include --create-dep ../../build/common/lcd.d -o ../../build/common/lcd.o -l ../../build/common/lcd.lst ../../common/source/lcd.s
ca65 --cpu 65C02 -Dclock_mode_flag=2  -Dacia_tx_irq=1  -Ddb6502 -I ../../common/include --create-dep ../../build/common/lcd8bit.d -o ../../build/common/lcd8bit.o -l ../../build/common/lcd8bit.lst ../../common/source/lcd8bit.s
ca65 --cpu 65C02 -Dclock_mode_flag=2  -Dacia_tx_irq=1  -Ddb6502 -I ../../common/include --create-dep ../../build/common/modem.d -o ../../build/common/modem.o -l ../../build/common/modem.lst ../../common/source/modem.s
ca65 --cpu 65C02 -Dclock_mode_flag=2  -Dacia_tx_irq=1  -Ddb6502 -I ../../common/include --create-dep ../../build/common/string.d -o ../../build/common/string.o -l ../../build/common/string.lst ../../common/source/string.s
ca65 --cpu 65C02 -Dclock_mode_flag=2  -Dacia_tx_irq=1  -Ddb6502 -I ../../common/include --create-dep ../../build/common/utils.d -o ../../build/common/utils.o -l ../../build/common/utils.lst ../../common/source/utils.s
ca65 --cpu 65C02 -Dclock_mode_flag=2  -Dacia_tx_irq=1  -Ddb6502 -I ../../common/include --create-dep ../../build/common/via.d -o ../../build/common/via.o -l ../../build/common/via.lst ../../common/source/via.s
ca65 --cpu 65C02 -Dclock_mode_flag=2  -Dacia_tx_irq=1  -Ddb6502 -I ../../common/include --create-dep ../../build/common/via_utils.d -o ../../build/common/via_utils.o -l ../../build/common/via_utils.lst ../../common/source/via_utils.s
ca65 --cpu 65C02 -Dclock_mode_flag=2  -Dacia_tx_irq=1  -Ddb6502 -I ../../common/include --create-dep ../../build/common/vdp.d -o ../../build/common/vdp.o -l ../../build/common/vdp.lst ../../common/source/vdp.s
ca65 --cpu 65C02 -Dclock_mode_flag=2  -Dacia_tx_irq=1  -Ddb6502 -I ../../common/include --create-dep ../../build/common/vdp_text_mode.d -o ../../build/common/vdp_text_mode.o -l ../../build/common/vdp_text_mode.lst ../../common/source/vdp_text_mode.s
ca65 --cpu 65C02 -Dclock_mode_flag=2  -Dacia_tx_irq=1  -Ddb6502 -I ../../common/include --create-dep ../../build/common/sound.d -o ../../build/common/sound.o -l ../../build/common/sound.lst ../../common/source/sound.s
ca65 --cpu 65C02 -Dclock_mode_flag=2  -Dacia_tx_irq=1  -Ddb6502 -I ../../common/include --create-dep ../../build/common/tty.d -o ../../build/common/tty.o -l ../../build/common/tty.lst ../../common/source/tty.s
ca65 --cpu 65C02 -Dclock_mode_flag=2  -Dacia_tx_irq=1  -Ddb6502 -I ../../common/include --create-dep ../../build/common/parse.d -o ../../build/common/parse.o -l ../../build/common/parse.lst ../../common/source/parse.s
ca65 --cpu 65C02 -Dclock_mode_flag=2  -Dacia_tx_irq=1  -Ddb6502 -I ../../common/include --create-dep ../../build/common/menu.d -o ../../build/common/menu.o -l ../../build/common/menu.lst ../../common/source/menu.s
ca65 --cpu 65C02 -Dclock_mode_flag=2  -Dacia_tx_irq=1  -Ddb6502 -I ../../common/include --create-dep ../../build/common/sd.d -o ../../build/common/sd.o -l ../../build/common/sd.lst ../../common/source/sd.s
ar65 r ../../build/lib/common.lib ../../build/common/syscalls.o ../../build/common/acia.o ../../build/common/blink.o ../../build/common/dpad.o ../../build/common/core.o ../../build/common/keyboard.o ../../build/common/lcd.o ../../build/common/lcd8bit.o ../../build/common/modem.o ../../build/common/string.o ../../build/common/utils.o ../../build/common/via.o ../../build/common/via_utils.o ../../build/common/vdp.o ../../build/common/vdp_text_mode.o ../../build/common/sound.o ../../build/common/tty.o ../../build/common/parse.o ../../build/common/menu.o ../../build/common/sd.o
ca65 --cpu 65C02 -Dclock_mode_flag=2  -Dacia_tx_irq=1  -Ddb6502 -I ../../common/include --create-dep ../../build/common/crt0.d -o ../../build/common/crt0.o -l ../../build/common/crt0.lst ../../common/source/crt0.s
cp -f ../../common/none.lib ../../build/lib/common.c.lib
ar65 r ../../build/lib/common.c.lib ../../build/common/crt0.o
ld65  -C ../../common/firmware.ext.cfg -m ../../build/rom/nop_fill/nop_fill.ext.map -o ../../build/rom/nop_fill.ext.bin ../../build/common/zeropage.o ../../build/common/sysram_map.o ../../build/rom/nop_fill/nop_fill.o ../../build/lib/common.lib ../../build/lib/common.c.lib
hexdump -C ../../build/rom/nop_fill.ext.bin
00000000  ea ea ea ea ea ea ea ea  ea ea ea ea ea ea ea ea  |................|
*
00008000
49d01fd92a6a02370364f8eef2ee2c93  ../../build/rom/nop_fill.ext.bin
```

If you remember Ben's video - this is the first program he uploads to ROM. Now, run `make install` to upload the binary to your EEPROM - I assume you put the ROM chip in TL866II+ programmer and it is connected to your machine.

```shell
make install
```

You expect the following output:

```text
minipro -p AT28C256 -w ../../build/rom/nop_fill.ext.bin
Found TL866II+ 04.2.109 (0x26d)
Erasing... 0.02Sec OK
Protect off...OK
Writing Code...  6.78Sec  OK
Reading Code...  0.49Sec  OK
Verification OK
Protect on...OK
```

Plug the ROM back in your board, connect the Arduino to your PC, toggle clock module to manual mode, reset 6502 computer and start serial monitor. Go a few cycles step by step and you should see something similar to the below in serial monitor:

```text
10:13:51.707 -> 000000   1110101011110010   11101010   eaf2  r ea
10:13:52.315 -> 000001   1111111111111111   11101010   ffff  r ea
10:13:52.776 -> 000002   1110101011110010   11101010   eaf2  r ea
10:13:53.201 -> 000003   0000000111111101   10111101   01fd  r bd
10:13:53.585 -> 000004   0000000111111100   10111001   01fc  r b9
10:13:54.074 -> 000005   0000000111111011   10000001   01fb  r 81
10:13:54.576 -> 000006   1111111111111100   11101010   fffc  r ea
10:13:55.562 -> 000007   1111111111111101   11101010   fffd  r ea
10:13:56.020 -> 000008   1110101011101010   11101010   eaea  r ea
10:13:56.511 -> 000009   1110101011101011   11101010   eaeb  r ea
10:13:56.982 -> 000010   1110101011101011   11101010   eaeb  r ea
10:13:57.337 -> 000011   1110101011101100   11101010   eaec  r ea
10:13:57.659 -> 000012   1110101011101100   11101010   eaec  r ea
10:13:57.940 -> 000013   1110101011101101   11101010   eaed  r ea
10:13:58.253 -> 000014   1110101011101101   11101010   eaed  r ea
10:13:58.658 -> 000015   1110101011101110   11101010   eaee  r ea
```

First six lines might be different, but starting from line 7 you should see identical output. If this works, it means your CPU and ROM are working just fine, your clock module and Arduino Mega bus analyzer are attached correctly. Congratulations!

If you have any problems during build, installation or execution - check instructions above again, maybe you missed something.

### More complex programs

After having ran the first one, you can try connecting peripherals to your computer. If you want to follow Ben's videos, keep reading this section, otherwise, skip to [next one](#initiate-warp-speed).

First, let's play with some LEDs. Using the connectors in bottom left corner of the PCB, connect 8 LEDs to VIA2 PORTB lines PB0-PB7, and then, using current limiting resistors of 220Ohm, connect these to ground (also from the VIA2 PORTB connector).

Having these connected, upload `Software/rom/blink_s` to your ROM. After powering on, you should see LEDs blinking in a way similar to what Ben did in his videos. If it works correctly, you can move on to connecting LCD. For now, use it in 8-bit mode with slow clock - just as in Ben's videos.

To do this, connect LCD to breadboard (not to the dedicated LCD port on PCB), and then connect each line as listed below:

| VIA2 Pin | LCD Pin |
| -------- | ------- |
| PA5      | RS      |
| PA6      | R/W     |
| PA7      | E       |
| PB0      | DB0     |
| PB1      | DB1     |
| PB2      | DB2     |
| PB3      | DB3     |
| PB4      | DB4     |
| PB5      | DB5     |
| PB6      | DB6     |
| PB7      | DB7     |

Also, connect A and VDD connectors to +5V, K and VSS to GND and connect V0 to a middle pin of 10KOhm potentiometer plugged between GND and +5V.

Now upload program `Software/rom/lcd_test` to ROM - when executed, it should display "Merry Christmas!" message on the LCD.

If it works correctly, you have a working CPU, ROM, VIA and address decoder.

### Initiate warp speed

Now it's time to go a bit faster and test the more complex features. Please note: you could keep using the analyzer and external clock with these programs, you just have to remember to build them with `CLOCK_MODE=slow` flag. More details can be found in [building software section](#building-software).

For now let's assume we move to 1MHz clock. To do it, put jumper on two leftmost pins of clock connector (J1). Disconnect external clock and bus analyzer - first one is not needed, second one will not work with high frequencies anyway. Connect your LCD to the onboard LCD port.

First one to test will be serial connection, so upload `Software/rom/serial_wdc_irq`. Now, depending on whether you soldered on FT230X chip or not, connect your board using USB cable to PC (using either MicroUSB or USB-B port), or use external USB->UART connector. Connect to your board using `picocom` with baud rate of 19200.

```shell
picocom -b 19200 /dev/tty.usbserial-HANF88HD
```

When you get "Terminal ready" message, you should see "Hello from WDC65C51 (irq), press any key...". This means that two things are working correctly: interrupt handling and serial communication. The polling counterpart is `Software/rom/serial_wdc`, useful when you want to take the interrupt path out of the picture. Congratulations, you are almost ready to go.

### Keyboard connection

Even if you don't intend to use keyboard just yet, you still need to upload the controller sketch to ATtiny4313. Recommended way of doing that is to use onboard AVR-ISP connector and some kind of AVR programmer. I used USBasp programmer and it works lovely directly from Arduino IDE. The sketch to upload is in `Arduino/keyboard-4313` folder. **PLEASE NOTE:** by default, Arduino IDE will not set fuses of your ATtiny4313 to reflect your clock settings. This can result in unpredictable behavior and/or failure of keyboard connection. Make sure you invoke "Tools->Burn bootloader" before uploading the sketch to ensure correct operation. See [issue #50](https://github.com/dbuchwald/6502/issues/50) for additional details.

After successful sketch upload, flash your rom with `Software/rom/keyboard_test`. Connect your PS/2 keyboard to the port and try pressing some keys - you should see messages on the LCD with confirmation.

### Using the bootloader

Currently only the minimal bootloader is provided, but it should be sufficient for software development without constant need to reflash the EEPROM. To use it, build ROM image in `Software/rom/minimal_bootloader` folder and flash it to EEPROM. To test this functionality, you have to build an example loadable program in `Software/load/hello_world`.

**PLEASE NOTE:** Both the bootloader and sample programs will be built automatically when invoking `make all` directly in `Software` folder.

Upon boot you will be prompted to connect to the PC via serial connection and press Enter key - either in terminal window if keyboard is not connected, or on the keyboard otherwise. Connection details will be displayed on the LCD:

- 19200 baud,
- 8-bit, no parity, 1 stop bit,
- CTS/RTS hardware flow control.

In MacOS/Linux you can use `picocom` for this operation, under Windows I have successfully used [ExtraPuTTy](https://www.extraputty.com/).

After connection is established you need to press enter as prompted (either on PS/2 keyboard or terminal window) and you will be prompted to initiate file transfer. In `picocom` this requires that your send command is set to `sz -X` (see `make terminal` target in `Software/common/makefile`) and you initiate transfer with Ctrl+A followed by Ctrl+S. Enter load file path (i.e. `Software/build/load/hello_world.load.bin`) and press enter. If the transfer fails, try again. `picocom` seems to fail every now and then, while ExtraPuTTy hardly ever has any issues.

In ExtraPuTTy open "Files Transfer" menu item, then "Xmodem" and "Send". Point to loadable module (i.e. `Software/build/load/hello_world.load.bin`) and click "Open" button.

Program should load and be automatically executed. Congratulations, you got yourself working bootloader!

### Installing OS/1

OS/1 is simple operating system, currently being developed for the machine. It already provides bootloader functionality and more is coming every day. **THIS IS WORK IN PROGRESS, SO EXPECT STABILITY ISSUES**

After installing to ROM and booting, it will display basic startup messages on onboard LCD and prompt you to connect via serial port (19200 baud, no parity, 8 data bits, 1 stop bit, CTS/RTS hardware flow control) and confirm connection by sending single char via serial, if no keyboard is connected to PS/2 port or by pressing Enter key on attached PS/2 keyboard otherwise.

Simple prompt will be displayed, and the following commands are currently supported:

- `HELP` - will display simple help message with basic description of the commands,
- `LOAD` - will initiate XModem file receive operation to enable loading loadable modules (see [Using the bootloader](#using-the-bootloader) section for details),
- `RUN` - will run the loaded program,
- `MONITOR` - will run monitor application that can be used to check/alter contents of computer memory,
- `BLINK` - with parameter `ON` or `OFF` will toggle onboard blink LED state,
- `EXIT` - will exit the shell - and go back to it after soft reset.

Loaded programs might fail or fall into infinite loop. To prevent having to reset them, you can press CTRL+X key combination on attached PS/2 keyboard - this will initiate system break operation and should return you back into the shell.

#### Using built-in monitor application

Currently monitor application is fairly limited, but it should provide sufficient functionality for basic troubleshooting. The following commands are supported:

- `GET` with single address (in format `XX` or `XXXX`) will display data from this address and 15 following bytes,
- `GET` with address range (in format `XXXX:XXXX`, zeropage addresses can be substituted with `XX`) will display all the data within given range,
- `PUT` will store provided value (in format `XXXX=XX`) under given address.

Standard commands like `HELP` and `EXIT` are obviously also supported.

## Building software

General rule is simple: `make` should be sufficient for all the build/installation. The following `make` targets are to be used for building software:

- `all` - build the project,
- `clean` - delete all temporary files,
- `test` - dump the contents and checksum of generated binary file,
- `install` - upload generated binary to AT28C256 chip using `minipro` tool,
- `terminal` - connect to the 6502 computer using serial port, please note - currently uses my own device ID as visible under MacOS and most likely needs to be adapted to your build/OS,
- `emu` - run the generated binary in system emulator. Again: suitable for simple programs, more complex ones are not yet supported. So far I needed it only for simple debugging and that's why it is so limited.

Beside the targets, there are three very important build flags:

- `ADDRESS_MODE` - drives the target addressing model by selecting `common/firmware.$(ADDRESS_MODE).cfg`. The only value shipped today is `ext` (also the default if omitted). The `basic` mode for Ben Eater's machine has been **removed**: `common/source/via.s` unconditionally references the third VIA, and the VDP is mapped as well, so `firmware.basic.cfg` had not linked for a long time. If you want to support your own model, create an additional configuration file, as explained in the common sources section below,
- `CLOCK_MODE` - used to control internal delay routines to work with different clock setups. The following modes are supported:
  - `slow` - to be used with external clock module, all delays are basically disabled,
  - `250k` - to be used with Arduino Mega Debugger (my own variant running at approx. 275kHz),
  - `1m` - to be used with 1MHz oscillator,
  - `2m` - to be used with 2MHz oscillator,
  - `4m` - to be used with 4MHz oscillator,
  - `8m` - to be used with 8MHz oscillator.
- `LCD_MODE` - with acceptable values `8bit` and `4bit` (the latter being default if omitted) enables build time selection of LCD interface. If your own build of 6502 computer uses 8-bit interface towards LCD, this will let you use provided software with it. The only thing you might want to check is the LCD data and port definitions at the beginning of `common/source/lcd8bit.s` (or, if you are using your own build with 4-bit mode `common/source/lcd4bit.s`) for symbols `LCD_DATA_PORT` and `LCD_CONTROL_PORT`, as well as their DDR counterparts. The same is possible with 4-bit mode, but there is just one symbol - `LCD_PORT` accompanied by DDR counterpart. Default configuration is obviously immediately compatible with 4-bit onboard LCD connector, and 8-bit interface connected to VIA2 PA for control and PB for data (like in BE6502),
- `ACIA_TX_IRQ` - flag was introduced to enable compatibility with WDC65C51 ACIA chip and acceptable values are `0` and `1`. It controls usage of IRQ request to indicate that transmit operation was completed. When disabled (value `0`), fixed time delay is used to wait for the transmit operation to complete. Rockwell R6551 chips can work with both settings, but `1` is recommended.

Build examples:

```shell
make CLOCK_MODE=slow clean all test install
```

This will build sources with support for slow clocking - any delay routines will be skipped. First, all the binaries will be removed, then built from scratch, hexdump of the resulting binary will be displayed and the binary uploaded to the EEPROM, assuming it's connected via minipro-compatible programmer.

```shell
make CLOCK_MODE=1m all test
```

This command will rebuild only modified modules with support for my own addressing scheme (32K RAM, 24K ROM, VIA at 0x9000) and suitable for 1MHz execution - all delays will be enabled.

## Detailed description of modules in `Software` folder

There are quite many programs in the `Software` folder, making the navigation a bit difficult. This section should support you in navigating provided software library.

### ROM images in `rom` folder

In the `rom` folder you will find the following ROM images:

- `nop_fill` - simplest possible program, composed of 32K of NOP (0xea) instructions. The source itself seems empty, because default fill is defined in the firmware configuration file (`common/firmware.ext.cfg`),
- `blink_s` - first example of a program interfacing with external world, using VIA2 to drive LEDs, as in Ben's videos,
- `blink_c` - modification of `blink_s`, but mixing low-level ASM code for hardware handling and C code for "business logic", shows how to use software stack to write code in C,
- `blink_test` - another blink program, but this one drives the onboard LED through the common library functions instead of touching the VIA directly. The same source is also built as a loadable module, so it doubles as an illustration of what the `BUILD_TYPE=` flag in the `makefile` changes,
- `lcd_test` - modified version of Ben Eater's first LCD program. Modification involves using loops, but runs without RAM, only ROM is used. This program will work only on slow clock (not 1MHz), and will not work with onboard LCD connector. To execute this one, you need to connect LCD via breadboard to VIA2 connectors on the PCB,
- `keyboard_test` - more complex program presenting integration with onboard keyboard controller, with IRQ driven data transmission, hardware state change detection and pretty interface on the onboard LCD port,
- `serial_test` - simplest possible ACIA/serial testing program, using blocking send/receive operation to send simple message in response to each input on serial terminal,
- `serial_wdc` - ACIA test using polled send and receive, prints "Hello from WDC65C51, press any key...",
- `serial_wdc_irq` - the same test driven by interrupts, prints "Hello from WDC65C51 (irq), press any key...",
- `serial_load_test` - attempt to implement testing program for high serial load, counting incoming characters,
- `modem_test` - barebone modem testing application, sort of bootloader without user interface,
- `microsoft_basic` - standalone version of MS Basic interpreter working over serial connection. Loads and saves programs on the SD card - see [BASIC on the SD card](#basic-on-the-sd-card) below,
- `minimal_bootloader` - simplest possible bootloader application that can be used to simplify software development thanks to making ROM flashing unnecessary for each code change,
- `os1` - **work in progress** - basic operating system.

The following table summarizes how each program behaves on this machine. The
`BE6502` column that used to stand next to it is gone with `ADDRESS_MODE=basic`,
which the build no longer supports.

| Program                  | Execution notes                                                |
| ------------------------ | -------------------------------------------------------------- |
| `rom/nop_fill`           | Works out of the box, slow clock and bus analyzer recommended  |
| `rom/blink_s`            | Works out of the box, attach LEDs to VIA2, needs slow clock    |
| `rom/blink_c`            | Works out of the box, attach LEDs to VIA2, needs slow clock    |
| `rom/blink_test`         | Works out of the box                                           |
| `rom/lcd_test`           | Works out of the box, attach LCD to VIA2, needs slow clock     |
| `rom/keyboard_test`      | Works out of the box                                           |
| `rom/serial_test`        | Works out of the box with R6551, WDC65C51 needs slow clock     |
| `rom/serial_wdc`         | Works out of the box                                           |
| `rom/serial_wdc_irq`     | Works out of the box                                           |
| `rom/serial_load_test`   | Works out of the box                                           |
| `rom/modem_test`         | Works out of the box                                           |
| `rom/microsoft_basic`    | Works out of the box                                           |
| `rom/minimal_bootloader` | Works out of the box                                           |
| `rom/os1`                | Works out of the box                                           |

### BASIC on the SD card

`rom/microsoft_basic` keeps programs on the card as **plain text**, one BASIC line per text
line, exactly the way `LIST` prints them. There is no tokenised file format: `LOAD` feeds the
file through the interpreter's own line input, and `SAVE` runs `LIST` with the output
redirected. A saved program can therefore be edited on a PC, and it survives changes to the
token table or to the load address.

| Command | Effect |
| --- | --- |
| `LOAD` | read `BASIC.BAS` |
| `LOAD "NAME.BAS"` | read `NAME.BAS` from the root directory |
| `LOAD "$"` | replace the program with a listing of the card, then `LIST` it |
| `SAVE` | write `BASIC.BAS` |
| `SAVE "NAME.BAS"` | write `NAME.BAS` |

Both accept any string expression, so `LOAD F$` works too. Names are folded to upper case and
cut down to 8.3; long file names on the card are ignored, only the short name matches.

`LOAD` clears the program first, then inserts every line as if it had been typed - so a text
line without a line number is *executed* rather than stored, and a syntax error stops the load
with the usual message.

`SAVE` creates the file if the card does not have it yet, and it rebuilds the cluster chain
from scratch every time: the old chain is released first, then clusters are taken off the free
list as the listing comes in. The file therefore always ends up exactly as long as the program,
with no leftover tail and no size that disagrees with the chain. Both copies of the FAT are
kept in step, and the free-space fields in the FSInfo block are marked "unknown" afterwards so
a PC counts them again rather than trusting a stale number. A save that fails part way through
gives its clusters back and leaves an empty file rather than something a `chkdsk` would have to
find.

Names that are about to create a new entry are checked first: control characters and the
characters FAT reserves (`" * + , . / : ; < = > ? [ \ ] |`) are refused with `?SYNTAX ERROR`
rather than written into the directory.

Two things the card could do but this does not, on purpose - a 1541 does not do them either,
and the point of `LOAD`/`SAVE`/`LOAD "$"` here is to feel like a C64:

- **one flat directory.** Files live in the root and nowhere else; a subdirectory on the card
  shows up in `LOAD "$"` as `DIR` and cannot be entered,
- **no timestamps.** There is no clock in the machine, and CBM DOS has no date field at all, so
  every entry gets the same fixed stamp of 2026-01-01 12:00. It is there only because a blank
  date field makes some tools on a PC complain.

Actual limitations:

- **the root directory cannot grow.** Once its slots are used up, `SAVE` reports
  `?DIRECTORY FULL` - the same wall a 1541 hits at 144 entries, just at a different number.
  How many depends on how the card was formatted: one entry per 32 bytes of the root
  directory's clusters, and long file names written by a PC eat several entries each.

The card does **not** have to be in the slot when the machine is switched on. `LOAD` and `SAVE`
each bring it up from scratch first - the same sequence that runs at power-on - so a card can
be put in later, taken out and put back, or swapped for a different one between commands. The
swap is the reason this happens every time rather than only after a failure: carrying one
card's layout over to another would have `SAVE` writing over whatever lives at those sector
numbers. It costs roughly 0.4 s per command at 1 MHz, and about twice that for `SAVE`, which
reads the BPB again for the fields the boot-time init does not keep.

Error messages: `?NO CARD`, `?NO SUCH FILE`, `?FILE TOO SMALL`, `?DISK FULL`,
`?DIRECTORY FULL`, `?WRITE ERROR`, `?CARD ERROR`.

**If you extend this code, read [section 5.2 of MEMORY_MAP.md](MEMORY_MAP.md) first.** The body
of `common/source/db6502_sdbasic.s` and the allocating write path at the end of
`common/source/libfat32.s` are deliberately linked into their own ROM block `SDCODE` at `$ec00`
instead of into `CODE`, and their variables into `BASBUF` instead of `BSS`. Growing `CODE` past
roughly `$dc50` moves every library module behind `msbasic.o` to a new address, and on this
board that alone kills the VDP picture - a ROM built from unchanged sources plus 1110 dead
filler bytes reproduces it. That is a hardware-level effect, not a bug in this code, so new code
belongs in `SDCODE` (305 bytes left) or in another fixed-offset block. `EXTCODE` at `$e700` is
exactly that: an additional block in what used to be filler, holding the panel, the drive light,
the error texts, the free space bookkeeping and the `BLOCKS FREE` line, with 118 bytes still
free. It has been confirmed working on the hardware.

`LOAD "$"` ends the way a C64 directory does, with a line saying how much room is left:

```text
0 "SD CARD"
1 "HELLO.BAS        1"
2 "PROG.BAS         6"
3 "78566 BLOCKS FREE"
```

A block is 512 bytes, the same unit the size column uses. The figure comes out of the FSInfo
block rather than from counting the FAT - on an 8 GB card that count would mean reading some
eight thousand sectors, about thirteen minutes. `SAVE` therefore keeps the FSInfo count in step
as it takes and returns clusters, instead of marking it unknown; `fsck_msdos` confirms the
number afterwards. A card that arrives without a usable count is told apart from one with a
real zero: the line then reads `??? BLOCKS FREE`.

### The panel

The 20x4 LCD is a four line panel, and the LED behaves like the one on a 1541 - lit while the
card is in use, out again when the command finished, still lit if it did not:

```text
MICROSOFT BASIC
SD READY
21817 BYTES FREE
SAVE PROG.BAS   120
```

The banner and the free memory line are repainted at every direct mode prompt, so the panel
puts itself back together after anything that disturbs it; the card line follows each mount,
and the bottom line follows the transfer. `BYTES FREE` is the figure `PRINT FRE(0)` gives.

The counter is lines: read for `LOAD`, written for `SAVE`, listed for `LOAD "$"`. Lines rather
than 512 byte blocks because that is the unit these files come in - a BASIC program of a few
hundred bytes is nought blocks from beginning to end, and a counter that never moves is worse
than no counter. It sticks at 999. Column 19 is
never written: reaching the end of the last row makes `lcd_wrap_line` scroll the whole display
and wait 150 ms, which would throw the line away and make every update slow. For the same
reason the cursor is parked at the top of the display before the card is touched - `sd_init`
prints `SD not initialized` wherever the cursor happens to be.

### Loadable programs in `load` folder

All the programs in the `load` folder are to be uploaded to the 6502 computer over serial port with XMODEM protocol and require ROM to be flashed with software capable of receiving them. Currently this is `rom/modem_test` and `rom/minimal_bootloader`. Following list describes them in more detail:

- `load/d_pad_test` - exercises the D-pad through the common `dpad` library and reports what it reads on the onboard LCD,
- `load/hello_world` - simple program to illustrate difference between assembly and C code,
- `load/hello_world_c` - as above, but written in C,
- `load/monitor` - work in progress implementation of the monitor program (moved to OS/1 image),
- `load/play_song` - plays a tune on the SN76489 through the common `sound` library,
- `load/sysinfo` - simple program to display system information, now embedded in OS/1 image.

As for software compatibility - all the loadable modules require bootloader, and this one, in turn, requires ACIA for operation, so by design these are not compatible with vanilla BE6502.

### Loadable modules explained

There is one thing important to consider when working with loadable modules. The idea behind them is to have the possibility to run the same code from RAM and ROM, preferably preserving the former if possible and reducing the loadable file size. The idea is to be able to execute common functions stored in ROM from the code running in RAM.

The naive approach is to bundle every function the module calls into the module
itself. It works, and it is what you get without doing anything special, but the
binary then carries its own copy of code that already sits in ROM, and a ROM
update leaves that copy behind.

The alternative is what `load/hello_world` does. It calls `writeln_tty`, so it
uses `_tty_writeln` from the common library - and the whole binary is 286 bytes,
nowhere near enough to contain it. None of the common code is bundled. The
references are satisfied by stub functions defined in `common/source/loadlib.s`,
each of which is a jump through a vector in the dedicated range in ROM
(0xf800-0xfff9). This indirection layer enables updates to ROM without needing
to recompile all the loadable modules. The only requirement is to keep the order
of the calls intact and to add new functions to `common/source/syscalls.s` at the
end, so that previously defined addresses stay where they are.

Defining new shared function requires the following:

- implementation of the code in `common/source` folder,
- implementation of the interface include in `common/include` folder,
- adding this new function to `common/source/syscalls.s` module,
- adding stub function to `common/source/loadlib.s` module,
- adding new objects to `rom/minimal_bootloader/makefile` and `rom/modem_test/makefile`.

The list above should help you understand how this code reusability has been achieved.

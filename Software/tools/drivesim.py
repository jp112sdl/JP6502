#!/usr/bin/env python3
"""Play the floppy drive behind LOAD "NAME.BAS",8 - from a folder on the Mac.

The real drive is a PC floppy with a Raspberry Pi Pico of its own, on the
6551 through a switch that otherwise connects the FTDI; Schematics/FLOPPY_PICO.md
has the wiring and the protocol, and common/source/db6502_disk.s is the other
end. This serves a folder instead of a disk, so the BASIC side can be tried
before the drive exists: over the serial port with the switch on "Mac", or
over standard input and output for the emulator.

    drivesim.py                          # Software/basic, the only USB port
    drivesim.py -p /dev/cu.usbserial-XX  ~/floppy
    drivesim.py -v                       # log every byte on the wire
    jp6502emu -A "drivesim.py --stdio DIR" microsoft_basic.ext.bin

Over the FTDI the 6551 sends nothing until this has the port open, so start it
first - or at least within the ten seconds BASIC waits for an answer.

Commands from the machine, one line each, ending in CR, the name in the raw
FAT form the card uses - eight characters, three, space padded, no dot:

    L NAME    BAS     LOAD "NAME.BAS",8
    S NAME    BAS     SAVE "NAME.BAS",8
    $                 LOAD "$",8

Each is answered with a status line the way a 1541 answers ("00,OK",
"62,FILE NOT FOUND"), then come the lines of LOAD "@" or SAVE "@" - the parts
basicsend.py and basicrecv.py play. A SAVE is answered a second time once the
file is written. The folder is treated as a 1.44 MB disk: the directory says
how much of that is left, and a SAVE that does not fit gets 72,DISK FULL.
"""

import argparse
import math
import os
import select
import sys
import time

EOT = 0x04
ACK = 0x06
CAN = 0x18
CR = 0x0D
LF = 0x0A

DEFAULT_BAUD = 19200
MAX_LINE = 78                   # what ser_getline keeps of a line
DISK_BLOCKS = 2847              # data area of a 1.44 MB FAT12 disk, 512 bytes each
FIRST_ACK_TIMEOUT = 30.0        # the machine sends one at once; this is generous
LINE_ACK_TIMEOUT = 10.0         # inserting a line in front of a long program
SAVE_IDLE_TIMEOUT = 60.0        # LIST is slow, but not that slow

BASIC_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "basic")

log_enabled = True
verbose = False


def log(text):
    if log_enabled:
        sys.stderr.write("drivesim: %s\n" % text)
        sys.stderr.flush()


class Gone(Exception):
    """The other end closed - the emulator ended."""


class SerialLink:
    def __init__(self, name, baud):
        try:
            import serial
        except ImportError:
            sys.exit("pyserial is missing - install it with: pip3 install pyserial")
        self.serial = serial
        self.name = name
        self.baud = baud
        try:
            self.port = self.open()
        except serial.SerialException as error:
            sys.exit("Cannot open %s: %s" % (name, error))
        except Exception as error:
            # A wedged USB serial driver refuses every tcsetattr, and pyserial
            # passes that up as a bare termios error - see open_port in
            # basicsend.py, which says the same.
            sys.exit(
                "%s will not take its settings (%s).\n"
                "The driver, not this tool - `stty -f %s %d` fails the same way.\n"
                "Unplug the adapter and plug it back in, ideally into a different "
                "USB port and without a hub. If it keeps failing, try another USB "
                "cable, and try the adapter with nothing wired to the 6502 - a "
                "board fighting it for power can knock its USB side over."
                % (name, error, name, baud)
            )
        self.report()

    def open(self):
        port = self.serial.Serial(self.name, self.baud, timeout=0.1)
        port.reset_input_buffer()
        # The 6551 sends nothing while its /CTS is high, and /CTS is this end's
        # RTS. pyserial raises RTS when it opens the port - this only makes sure.
        try:
            port.rts = True
            port.dtr = True
        except (self.serial.SerialException, OSError):
            pass                # a pseudo terminal has no modem lines
        return port

    def report(self):
        try:
            log("RTS %s - the 6551's /CTS - and DTR %s; from the board: CTS %s, DSR %s, CD %s"
                % (on(self.port.rts), on(self.port.dtr),
                   on(self.port.cts), on(self.port.dsr), on(self.port.cd)))
        except Exception as error:
            log("cannot read the modem lines (%s)" % error)

    def lost(self, error):
        """The adapter went away - unplugged, or knocked off the bus. A drive
        does not give up over that, so this waits for it to come back: the FTDI
        names its port after its serial number, so it comes back as the same."""
        log("lost %s (%s) - waiting for it to come back" % (self.name, error))
        try:
            self.port.close()
        except Exception:
            pass
        refused = None
        while True:
            time.sleep(0.5)
            if not os.path.exists(self.name):
                continue
            try:
                self.port = self.open()
            except Exception as error:
                if str(error) != refused:
                    refused = str(error)
                    log("%s is there but will not open yet (%s)" % (self.name, error))
                continue
            log("%s is back" % self.name)
            self.report()
            return

    def read(self, timeout):
        """One byte, or None after timeout seconds - at once for 0."""
        try:
            if timeout <= 0:
                if not self.port.in_waiting:
                    return None
                return trace("<", self.port.read(1)[0])
            deadline = time.time() + timeout
            while True:
                chunk = self.port.read(1)
                if chunk:
                    return trace("<", chunk[0])
                if time.time() >= deadline:
                    return None
        except (self.serial.SerialException, OSError) as error:
            self.lost(error)
            return None

    def write(self, data):
        for byte in data:
            trace(">", byte)
        try:
            self.port.write(data)
            self.port.flush()
        except (self.serial.SerialException, OSError) as error:
            self.lost(error)


def on(flag):
    return "on" if flag else "off"


def trace(direction, byte):
    """With -v every byte on the wire goes to the log."""
    if verbose:
        shown = chr(byte) if 0x20 <= byte < 0x7F else "$%02X" % byte
        sys.stderr.write("drivesim: %s %s\n" % (direction, shown))
        sys.stderr.flush()
    return byte


class StdioLink:
    def read(self, timeout):
        ready, _, _ = select.select([0], [], [], timeout)
        if not ready:
            return None
        chunk = os.read(0, 1)
        if not chunk:
            raise Gone()
        return trace("<", chunk[0])

    def write(self, data):
        for byte in data:
            trace(">", byte)
        os.write(1, data)


def pick_port():
    """The only USB serial port, if there is exactly one."""
    try:
        from serial.tools import list_ports
    except ImportError:
        sys.exit("pyserial is missing - install it with: pip3 install pyserial")
    ports = [p for p in list_ports.comports() if "usb" in p.device.lower() or p.vid]
    if len(ports) == 1:
        return ports[0].device
    if not ports:
        sys.exit("No USB serial port found - pass one with -p")
    print("Several serial ports found, pick one with -p:", file=sys.stderr)
    for port in ports:
        print("  %-28s %s" % (port.device, port.description), file=sys.stderr)
    sys.exit(1)


# --- the disk --------------------------------------------------------------

def fat_to_name(raw):
    """'HELLO   BAS' -> 'HELLO.BAS'."""
    raw = raw.ljust(11)
    base, ext = raw[:8].rstrip(), raw[8:11].rstrip()
    return base + ("." + ext if ext else "")


def fits_83(name):
    base, dot, ext = name.partition(".")
    if not base or len(base) > 8 or len(ext) > 3 or "." in ext:
        return False
    return all(c.isalnum() or c in "!#$%&'()-@^_`{}~" for c in base + ext)


class Disk:
    def __init__(self, folder, label):
        self.folder = folder
        self.label = label

    def entries(self):
        """(NAME, size or None for a directory), 8.3 names only, sorted."""
        found = []
        for name in sorted(os.listdir(self.folder), key=str.upper):
            if name.startswith(".") or not fits_83(name):
                continue
            path = os.path.join(self.folder, name)
            if os.path.isdir(path):
                found.append((name.upper(), None))
            elif os.path.isfile(path):
                found.append((name.upper(), os.path.getsize(path)))
        return found

    def find(self, name):
        for entry in os.listdir(self.folder):
            if entry.upper() == name.upper() and os.path.isfile(os.path.join(self.folder, entry)):
                return os.path.join(self.folder, entry)
        return None

    def used_blocks(self, leaving_out=None):
        return sum(blocks(size) for name, size in self.entries()
                   if size is not None and name != leaving_out)

    def free_blocks(self):
        return max(0, DISK_BLOCKS - self.used_blocks())


def blocks(size):
    return min(65535, math.ceil(size / 512))


def directory_lines(disk):
    """The directory as program lines, in the format LOAD "$" uses for the card."""
    lines = ['0 "%s"' % disk.label]
    number = 1
    for name, size in disk.entries():
        field = "  DIR" if size is None else "%5d" % blocks(size)
        lines.append('%d "%-13s%s"' % (number, name, field))
        number += 1
    lines.append('%d "%d BLOCKS FREE"' % (number, disk.free_blocks()))
    return lines


def file_lines(path):
    """The lines of a .BAS file the way the card hands them over: control
    characters dropped, tabs made spaces, empty lines left out - BASIC sends no
    ACK for an empty line, so one would stop the transfer."""
    with open(path, "rb") as handle:
        raw = handle.read()
    text = raw.split(b"\x1a")[0].decode("latin-1")
    lines = []
    for line in text.splitlines():
        line = line.replace("\t", " ")
        line = "".join(c for c in line if " " <= c <= "~").rstrip()
        if line:
            if len(line) > MAX_LINE:
                log("line longer than %d characters, BASIC keeps the start: %s"
                    % (MAX_LINE, line))
            lines.append(line)
    return lines


# --- the protocol ----------------------------------------------------------

def status(link, text):
    log("-> %s" % text)
    link.write(text.encode("ascii") + b"\r")


def read_command(link):
    """The next command line. Bytes outside a line - an ACK left over, a CAN
    from a transfer given up - are not commands and are dropped."""
    line = bytearray()
    while True:
        byte = link.read(3600)
        if byte is None:
            continue
        if byte == CR:
            if line:
                return line.decode("latin-1")
            continue
        if byte < 0x20 or byte > 0x7E:
            continue
        if len(line) < 40:
            line.append(byte)


def wait_ack(link, timeout):
    """True on ACK, False on timeout or CAN."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        byte = link.read(max(0.01, deadline - time.time()))
        if byte == ACK:
            return True
        if byte == CAN:
            log("<- CAN, the machine gave up")
            return False
    log("no ACK from the machine")
    return False


def drain(link):
    """Throws away the ACKs that pile up while BASIC waits - it repeats its
    ACK when nothing comes. False if a CAN is among them."""
    while True:
        byte = link.read(0)
        if byte is None:
            return True
        if byte == CAN:
            log("<- CAN, the machine gave up")
            return False


def send_lines(link, lines):
    """LOAD "@" from this end: a line for every ACK, EOT after the last."""
    if not wait_ack(link, FIRST_ACK_TIMEOUT):
        return
    for index, line in enumerate(lines, start=1):
        if not drain(link):
            return
        link.write(line.encode("ascii") + b"\r")
        if not wait_ack(link, LINE_ACK_TIMEOUT):
            log("stopped after line %d of %d" % (index, len(lines)))
            return
    if drain(link):
        link.write(bytes([EOT]))
        log("sent %d lines" % len(lines))


def receive_listing(link):
    """SAVE "@" from this end: the listing up to the EOT, as lines. None if
    the machine sent CAN instead, or stopped."""
    text = bytearray()
    while True:
        byte = link.read(SAVE_IDLE_TIMEOUT)
        if byte is None:
            log("the listing stopped without an EOT")
            return None
        if byte == EOT:
            return text.decode("ascii", "replace").splitlines()
        if byte == CAN:
            log("<- CAN, the save was given up")
            return None
        if byte == LF:
            text.append(byte)
        elif 0x20 <= byte < 0x7F:
            text.append(byte)


def do_load(link, disk, raw):
    name = fat_to_name(raw)
    path = disk.find(name)
    if path is None:
        status(link, "62,FILE NOT FOUND")
        return
    lines = file_lines(path)
    status(link, "00,OK")
    send_lines(link, lines)


def do_directory(link, disk):
    status(link, "00,OK")
    send_lines(link, directory_lines(disk))


def do_save(link, disk, raw):
    name = fat_to_name(raw)
    if not fits_83(name):
        status(link, "33,SYNTAX ERROR")
        return
    if not os.access(disk.folder, os.W_OK):
        status(link, "26,WRITE PROTECT ON")
        return
    status(link, "00,OK")
    lines = receive_listing(link)
    if lines is None:
        return
    body = "".join(line + "\r\n" for line in lines).encode("ascii", "replace")
    if disk.used_blocks(leaving_out=name.upper()) + blocks(len(body)) > DISK_BLOCKS:
        status(link, "72,DISK FULL")
        return
    path = disk.find(name) or os.path.join(disk.folder, name.upper())
    try:
        with open(path, "wb") as handle:
            handle.write(body)
    except OSError as error:
        log("cannot write %s: %s" % (path, error))
        status(link, "25,WRITE ERROR")
        return
    log("wrote %s, %d lines" % (os.path.basename(path), len(lines)))
    status(link, "00,OK")


def serve(link, disk):
    log("serving %s" % os.path.normpath(disk.folder))
    while True:
        command = read_command(link)
        log("<- %s" % command)
        if command == "$":
            do_directory(link, disk)
        elif len(command) >= 2 and command[0] in "LS" and command[1] == " ":
            raw = command[2:13]
            if command[0] == "L":
                do_load(link, disk, raw)
            else:
                do_save(link, disk, raw)
        else:
            status(link, "31,SYNTAX ERROR")


def main():
    global log_enabled, verbose
    parser = argparse.ArgumentParser(
        description='Play the floppy drive of LOAD "NAME.BAS",8 from a folder.')
    parser.add_argument("folder", nargs="?", default=BASIC_DIR,
                        help="the folder that is the disk (default: Software/basic)")
    parser.add_argument("-p", "--port", help="serial port (default: the only USB one)")
    parser.add_argument("-b", "--baud", type=int, default=DEFAULT_BAUD,
                        help="baud rate (default: %d)" % DEFAULT_BAUD)
    parser.add_argument("--stdio", action="store_true",
                        help="talk over standard input and output - for the emulator")
    parser.add_argument("--label", help="the disk name the directory starts with")
    parser.add_argument("-q", "--quiet", action="store_true", help="no log on stderr")
    parser.add_argument("-v", "--verbose", action="store_true",
                        help="log every byte on the wire, for when nothing seems to arrive")
    args = parser.parse_args()
    log_enabled = not args.quiet
    verbose = args.verbose

    folder = os.path.abspath(args.folder)
    if not os.path.isdir(folder):
        sys.exit("%s is not a folder" % folder)
    label = (args.label or os.path.basename(folder) or "FLOPPY").upper()[:16]
    disk = Disk(folder, label)

    if args.stdio:
        link = StdioLink()
    else:
        port = args.port or pick_port()
        log("%s at %d baud" % (port, args.baud))
        link = SerialLink(port, args.baud)

    try:
        serve(link, disk)
    except Gone:
        pass
    except KeyboardInterrupt:
        sys.exit("\nStopped.")


if __name__ == "__main__":
    main()

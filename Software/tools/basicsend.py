#!/usr/bin/env python3
"""Send a BASIC program to the 6502 over the serial port.

The receiving end is ser_getline in common/source/db6502_serial.s, reached by
typing LOAD "@" on the machine. What travels down the wire is plain text - one
BASIC line per line, exactly what LIST prints and exactly what a .BAS file on
the SD card holds - so a program can be written here, sent over, edited on the
machine and saved to the card with no conversion anywhere.

The protocol is one line at a time, paced by the receiver:

    6502 -> here   ACK ($06)    ready for a line
    here -> 6502   text + CR    one BASIC line, at most 78 characters
    6502 -> here   ACK          it is in memory, send the next
    here -> 6502   EOT ($04)    that was the last one
    6502 -> here   CAN ($18)    given up over there - Ctrl+C, or a bad line

Either end may be started first. While the receiver is idle it repeats its ACK,
so this tool drains whatever ACKs have piled up before each line and only needs
to see one.

Usage:
    basicsend.py SNAKE.BAS              # a file, or a name in Software/basic
    basicsend.py -p /dev/tty.usbserial-A5XK3RJT hello.bas
    basicsend.py --as-is mixedcase.bas  # send the text exactly as written
    basicsend.py --list

LOAD "@" runs NEW first, so what arrives replaces the program in memory.
"""

import argparse
import os
import sys
import time

try:
    import serial
    from serial.tools import list_ports
except ImportError:
    sys.exit("pyserial is missing - install it with: pip3 install pyserial")

EOT = 0x04
ACK = 0x06
CAN = 0x18

DEFAULT_BAUD = 19200

# ser_getline keeps 78 characters of a line and reads the rest away, which
# would corrupt the program silently. Refuse to send one instead.
MAX_LINE = 78

# How long to wait for the first ACK. The machine only starts sending them once
# LOAD "@" has been typed, so this is really "how long to hold the door open".
HANDSHAKE_TIMEOUT = 120.0
# How long to wait for the ACK that follows a line. Inserting one in front of a
# long program is the slow case, and it is nowhere near this.
LINE_TIMEOUT = 10.0

BASIC_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "basic")


def available_programs():
    """Every .BAS in Software/basic, sorted by name."""
    if not os.path.isdir(BASIC_DIR):
        return []
    names = [f for f in os.listdir(BASIC_DIR) if f.upper().endswith(".BAS")]
    return sorted(os.path.join(BASIC_DIR, f) for f in names)


def resolve_program(name):
    """Accept a path, a file name in Software/basic, or a bare name."""
    if os.path.isfile(name):
        return name
    for candidate in (name, name + ".BAS", name.upper() + ".BAS"):
        path = os.path.join(BASIC_DIR, candidate)
        if os.path.isfile(path):
            return path
    sys.exit("No such program: %s (try --list)" % name)


def print_program_list():
    programs = available_programs()
    if not programs:
        sys.exit("No .BAS files in %s" % os.path.normpath(BASIC_DIR))
    print("%-16s %6s  %s" % ("PROGRAM", "LINES", "BYTES"))
    for path in programs:
        with open(path, "r", errors="replace") as handle:
            text = handle.read()
        lines = [line for line in text.splitlines() if line.strip()]
        print("%-16s %6d  %5d" % (os.path.basename(path), len(lines), len(text)))


def pick_port():
    """Use the only USB serial port if there is exactly one."""
    ports = [p for p in list_ports.comports() if "usb" in p.device.lower() or p.vid]
    if len(ports) == 1:
        return ports[0].device
    if not ports:
        sys.exit("No USB serial port found - pass one with -p")
    print("Several serial ports found, pick one with -p:", file=sys.stderr)
    for port in ports:
        print("  %-28s %s" % (port.device, port.description), file=sys.stderr)
    sys.exit(1)


def open_port(port_name, baud):
    """Open the port, and say something useful when macOS will not have it.

    A wedged USB serial driver refuses every tcsetattr, including one that
    writes back exactly what it just read, and pyserial passes that up as a
    bare termios error from inside its constructor. It is not a bad argument
    and it is not this tool - `stty -f <port> 19200` fails the same way - so
    say so, and say what actually clears it.
    """
    try:
        return serial.Serial(port_name, baud, timeout=0.1)
    except serial.SerialException as error:
        sys.exit("Cannot open %s: %s" % (port_name, error))
    except Exception as error:
        sys.exit(
            "%s will not take its settings (%s).\n"
            "The driver, not this tool - `stty -f %s %d` fails the same way.\n"
            "Unplug the adapter and plug it back in, ideally into a different "
            "USB port and without a hub. If it keeps failing, try another USB "
            "cable, and try the adapter with nothing wired to the 6502 - a "
            "board fighting it for power can knock its USB side over."
            % (port_name, error, port_name, baud)
        )


def upcase_outside_quotes(line):
    """Uppercase everything that is not inside a string literal.

    The tokeniser only knows uppercase keywords, so a lowercase program is a
    pile of syntax errors on arrival. Text inside quotes is left alone, because
    that is the one place where the case was meant.
    """
    out = []
    in_string = False
    for char in line:
        if char == '"':
            in_string = not in_string
        out.append(char if in_string else char.upper())
    return "".join(out)


def read_program(path, as_is):
    """The lines to send, in order, already cleaned up.

    Blank lines are dropped: the receiver treats an empty line as nothing at
    all and sends no ACK for one, which would leave this end waiting.
    """
    with open(path, "r", errors="replace") as handle:
        raw = handle.read()

    lines = []
    changed = 0
    for number, text in enumerate(raw.splitlines(), start=1):
        text = text.rstrip()
        if not text.strip():
            continue
        if not as_is:
            upper = upcase_outside_quotes(text)
            if upper != text:
                changed += 1
            text = upper
        if len(text) > MAX_LINE:
            sys.exit(
                "%s line %d is %d characters, and the receiver keeps only %d:\n  %s"
                % (os.path.basename(path), number, len(text), MAX_LINE, text)
            )
        if any(ord(c) < 0x20 or ord(c) > 0x7E for c in text):
            sys.exit(
                "%s line %d has characters the machine has no way to read:\n  %s"
                % (os.path.basename(path), number, text)
            )
        lines.append(text)

    if not lines:
        sys.exit("%s has nothing in it to send" % os.path.basename(path))
    return lines, changed


def check_for_cancel(chunk, what):
    if CAN in chunk:
        sys.exit("\nThe machine cancelled the transfer %s." % what)


def drain(port, what):
    """Throw away whatever has piled up, so the next ACK is a fresh one.

    An idle receiver repeats its ACK, so between typing LOAD "@" and this tool
    getting to the port there can be any number of them waiting. Clearing them
    before every line is what keeps one ACK meaning one line.
    """
    pending = port.in_waiting
    if pending:
        check_for_cancel(port.read(pending), what)


def wait_for_ack(port, timeout, what, stale_ok=False):
    """Wait for one ACK. True on ACK, False on timeout, exits on CAN.

    Read one byte at a time: read(n) waits for all n or for the timeout, and
    spending the timeout on every line would cost more than the transfer does.

    With stale_ok a CAN is ignored rather than fatal. That is right before the
    first line has been sent: there is nothing for the machine to be cancelling
    yet, so a CAN at that point is left over from an earlier run and says
    nothing about this one.
    """
    deadline = time.time() + timeout
    while time.time() < deadline:
        chunk = port.read(1)
        if not chunk:
            continue
        if not stale_ok:
            check_for_cancel(chunk, what)
        if chunk[0] == ACK:
            return True
    return False


def send_program(port, lines, quiet):
    if not wait_for_ack(port, HANDSHAKE_TIMEOUT, "before it started", stale_ok=True):
        sys.exit(
            "No ACK from the machine. Type LOAD \"@\" on it, and check the "
            "port and that nothing else has it open."
        )

    total = len(lines)
    for index, text in enumerate(lines, start=1):
        drain(port, "at line %d" % index)
        port.write(text.encode("ascii") + b"\r")
        port.flush()
        if not wait_for_ack(port, LINE_TIMEOUT, "at line %d" % index):
            sys.exit(
                "\nNo ACK after line %d of %d:\n  %s" % (index, total, text)
            )
        if not quiet:
            sys.stdout.write("\r  %d/%d lines" % (index, total))
            sys.stdout.flush()

    drain(port, "at the end")
    port.write(bytes([EOT]))
    port.flush()
    if not quiet:
        sys.stdout.write("\r  %d/%d lines - sent\n" % (total, total))


def main():
    parser = argparse.ArgumentParser(
        description="Send a BASIC program to the 6502 over the serial port.",
        epilog='Type LOAD "@" on the machine, at either end of starting this.',
    )
    parser.add_argument("program", nargs="?", help="file, or a name in Software/basic")
    parser.add_argument("-p", "--port", help="serial port (default: the only USB one)")
    parser.add_argument(
        "-b", "--baud", type=int, default=DEFAULT_BAUD,
        help="baud rate (default: %d, which is what _acia_init sets)" % DEFAULT_BAUD,
    )
    parser.add_argument(
        "--as-is", action="store_true",
        help="send the text exactly as written, without uppercasing keywords",
    )
    parser.add_argument("-q", "--quiet", action="store_true", help="no progress line")
    parser.add_argument("--list", action="store_true", help="list Software/basic and stop")
    args = parser.parse_args()

    if args.list:
        print_program_list()
        return

    if not args.program:
        parser.error("give a program to send, or --list")

    path = resolve_program(args.program)
    lines, changed = read_program(path, args.as_is)

    if changed and not args.quiet:
        print("Uppercased %d line%s outside their string literals (--as-is to "
              "keep them)" % (changed, "" if changed == 1 else "s"))

    port_name = args.port or pick_port()
    if not args.quiet:
        print("%s -> %s at %d baud, %d lines"
              % (os.path.basename(path), port_name, args.baud, len(lines)))
        print('  waiting for the machine - type LOAD "@" on it')

    with open_port(port_name, args.baud) as port:
        port.reset_input_buffer()
        port.reset_output_buffer()
        send_program(port, lines, args.quiet)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit("\nStopped. Press Ctrl+C on the machine to get it out of LOAD.")

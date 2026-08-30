#!/usr/bin/env python3
"""Fetch a BASIC program from the 6502 over the serial port.

The sending end is ser_save in common/source/db6502_serial.s, reached by typing
SAVE "@" on the machine. What arrives is plain text - one BASIC line per line,
exactly what LIST prints and exactly what a .BAS file on the SD card holds - so
what this writes can be edited here and sent straight back with basicsend.py.

There is no handshake in this direction and none is needed: the machine is the
slow end, composing a line takes it far longer than 19200 baud takes to carry
one away, and this end has nothing to keep up with. The listing ends with one
EOT ($04), which is the same byte LOAD "@" takes as "no more lines".

Usage:
    basicrecv.py SNAKE.BAS              # write it, refusing to clobber
    basicrecv.py -f SNAKE.BAS           # overwrite if it is already there
    basicrecv.py -                      # print it instead of writing a file
    basicrecv.py -p /dev/tty.usbserial-A5XK3RJT prog.bas

Start this first, then type SAVE "@" on the machine - the 6551 will not
transmit at all until something has the port open at this end. Ctrl+C on the
machine gets it out of a save that has nowhere to go.
"""

import argparse
import os
import sys
import time

try:
    import serial  # noqa: F401  - imported for the error message it gives
except ImportError:
    sys.exit("pyserial is missing - install it with: pip3 install pyserial")

from basicsend import DEFAULT_BAUD, open_port, pick_port

EOT = 0x04

# How long to wait for the listing to start. The machine sends nothing until
# SAVE "@" has been typed, so this is really "how long to hold the door open".
START_TIMEOUT = 120.0
# How long a gap inside a listing may be. LIST pauses for as long as it takes
# to compose a line, which is nothing like this.
IDLE_TIMEOUT = 10.0


def receive(port, quiet):
    """Everything up to the EOT, as a list of lines.

    Anything that is not printable text is dropped: a stale ACK or CAN left in
    a buffer from an earlier transfer has nothing to do with this listing.
    """
    deadline = time.time() + START_TIMEOUT
    text = bytearray()
    lines = 0
    started = False

    while time.time() < deadline:
        chunk = port.read(64)
        if not chunk:
            continue
        deadline = time.time() + IDLE_TIMEOUT
        for byte in chunk:
            if byte == EOT:
                return bytes(text).decode("ascii", "replace").splitlines(), True
            if byte == 0x0A:
                text.append(byte)
                lines += 1
                if not quiet:
                    sys.stdout.write("\r  %d lines" % lines)
                    sys.stdout.flush()
                continue
            if byte == 0x0D:
                continue                        # the CR of the machine's CRLF
            if 0x20 <= byte < 0x7F:
                if not started:
                    started = True
                text.append(byte)

    return bytes(text).decode("ascii", "replace").splitlines(), False


def main():
    parser = argparse.ArgumentParser(
        description="Fetch a BASIC program from the 6502 over the serial port.",
        epilog='Start this first, then type SAVE "@" on the machine.',
    )
    parser.add_argument("output", help='file to write, or "-" for standard output')
    parser.add_argument("-p", "--port", help="serial port (default: the only USB one)")
    parser.add_argument(
        "-b", "--baud", type=int, default=DEFAULT_BAUD,
        help="baud rate (default: %d, which is what _acia_init sets)" % DEFAULT_BAUD,
    )
    parser.add_argument("-f", "--force", action="store_true", help="overwrite the file")
    parser.add_argument("-q", "--quiet", action="store_true", help="no progress line")
    args = parser.parse_args()

    to_stdout = args.output == "-"
    if not to_stdout and os.path.exists(args.output) and not args.force:
        sys.exit("%s is already there - pass -f to overwrite it" % args.output)

    port_name = args.port or pick_port()
    if not args.quiet:
        print("%s <- %s at %d baud" % (args.output, port_name, args.baud))
        print('  waiting for the machine - type SAVE "@" on it')

    with open_port(port_name, args.baud) as port:
        port.reset_input_buffer()
        port.reset_output_buffer()
        lines, complete = receive(port, args.quiet)

    if not lines:
        sys.exit("\nNothing came back. Was SAVE \"@\" typed, and is the program empty?")

    if not complete:
        # No EOT: the machine gave up, or the cable did. Half a program looks
        # exactly like a whole one, so do not leave one lying about under the
        # name of the real thing.
        sys.exit(
            "\nThe listing stopped after %d line%s without ending properly, so "
            "nothing was written. Ctrl+C on the machine does that, and so does "
            "a cable coming loose." % (len(lines), "" if len(lines) == 1 else "s")
        )

    body = "\n".join(lines) + "\n"
    if to_stdout:
        if not args.quiet:
            sys.stdout.write("\r  %d lines\n" % len(lines))
        sys.stdout.write(body)
    else:
        with open(args.output, "w") as handle:
            handle.write(body)
        if not args.quiet:
            sys.stdout.write("\r  %d lines - written to %s\n" % (len(lines), args.output))


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit("\nStopped. Press Ctrl+C on the machine to get it out of SAVE.")

#!/usr/bin/env python3
"""Upload a loadable program to the 6502 through the minimal bootloader.

The receiving end is _modem_receive in common/source/modem.s. It speaks
XMODEM/CRC with 128 byte blocks and two peculiarities worth knowing about:

  * The first two payload bytes of block 1 are the load address, little
    endian, and the copy loop starts after them. loadtrim.py already puts
    those two bytes in front of every .load.bin, so the file is sent as it
    is - do not strip anything.
  * There is no CAN support. Sending CAN would be read as a corrupt block.
    ESC is what aborts a transfer, so that is what this tool sends.

Usage:
    xmodem_send.py --list
    xmodem_send.py 22_msbasic
    xmodem_send.py -p /dev/tty.usbserial-A5XK3RJT 22_msbasic
    xmodem_send.py ../build/load/09_monitor.load.bin

Start this tool first, then press Enter on the PS/2 keyboard - the bootloader
only prints its serial prompt once the transfer has been triggered there.
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

SOH = 0x01
EOT = 0x04
ACK = 0x06
NAK = 0x15
ESC = 0x1B
CRC_REQUEST = ord("C")

BLOCK_SIZE = 128
MAX_BLOCK_RETRIES = 10

# Mirrors the range check in modem.s - the receiver refuses anything else.
USERRAM_START = 0x1000
USERRAM_END = 0x8000

DEFAULT_BAUD = 19200

LOAD_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build", "load")
LOAD_SUFFIX = ".load.bin"


def crc16_xmodem(data):
    """CRC-16/XMODEM - the same value the tables in modem.s produce."""
    crc = 0
    for byte in data:
        crc ^= byte << 8
        for _ in range(8):
            if crc & 0x8000:
                crc = ((crc << 1) ^ 0x1021) & 0xFFFF
            else:
                crc = (crc << 1) & 0xFFFF
    return crc


def available_programs():
    """Every .load.bin in the build directory, sorted by name."""
    if not os.path.isdir(LOAD_DIR):
        return []
    names = [f for f in os.listdir(LOAD_DIR) if f.endswith(LOAD_SUFFIX)]
    return sorted(os.path.join(LOAD_DIR, f) for f in names)


def resolve_program(name):
    """Accept a bare project name, a file name or a path."""
    if os.path.isfile(name):
        return name
    candidate = os.path.join(LOAD_DIR, name)
    if os.path.isfile(candidate):
        return candidate
    candidate = os.path.join(LOAD_DIR, name + LOAD_SUFFIX)
    if os.path.isfile(candidate):
        return candidate
    sys.exit("No such program: %s (try --list)" % name)


def load_address(payload):
    return payload[0] | (payload[1] << 8)


def print_program_list():
    programs = available_programs()
    if not programs:
        sys.exit("No .load.bin files in %s - run 'make all' in Software/ first." % LOAD_DIR)
    print("%-24s %8s %7s  %s" % ("PROGRAM", "BYTES", "BLOCKS", "LOAD ADDR"))
    for path in programs:
        with open(path, "rb") as handle:
            payload = handle.read()
        name = os.path.basename(path)[: -len(LOAD_SUFFIX)]
        blocks = (len(payload) + BLOCK_SIZE - 1) // BLOCK_SIZE
        print("%-24s %8d %7d  $%04X" % (name, len(payload), blocks, load_address(payload)))


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


def show_receiver_text(chunk, prefix="  6502: "):
    """Print whatever human readable text the receiver sent.

    The success message in modem.s starts with an EOT byte, and stray
    protocol bytes can end up in here too, so drop anything unprintable.
    """
    printable = bytes(b for b in chunk if b in (0x0A, 0x0D) or 0x20 <= b < 0x7F)
    text = printable.decode("ascii", "replace").replace("\r\n", "\n")
    for line in text.splitlines():
        if line.strip():
            print(prefix + line.strip())


def wait_for_handshake(port, timeout):
    """Wait until the receiver asks for CRC mode.

    The prompt in modem.s contains the letter C twice ("XMODEM/CRC"), so
    waiting for a bare 'C' would start the transfer in the middle of the
    prompt. The real request is the 'C' right after the prompt's CRLF.
    As a fallback - useful when the prompt was printed before this tool
    opened the port - a 'C' followed by a second of silence also counts.
    """
    deadline = time.time() + timeout
    seen = bytearray()
    last_byte_at = None

    while time.time() < deadline:
        chunk = port.read(64)
        if chunk:
            seen += chunk
            last_byte_at = time.time()
            if b"\r\nC" in seen:
                show_receiver_text(seen[: seen.index(b"\r\nC")])
                return True
        elif last_byte_at and CRC_REQUEST in seen and time.time() - last_byte_at > 1.0:
            show_receiver_text(seen)
            return True

    if seen:
        show_receiver_text(seen)
    return False


def read_response(port, timeout):
    """Read one meaningful protocol byte, collecting anything else as text."""
    deadline = time.time() + timeout
    noise = bytearray()
    while time.time() < deadline:
        chunk = port.read(1)
        if not chunk:
            continue
        byte = chunk[0]
        if byte in (ACK, NAK, ESC):
            return byte, bytes(noise)
        # A stale 'C' is the receiver still repeating its CRC request.
        if byte != CRC_REQUEST:
            noise.append(byte)
        if b"Error" in noise or b"Abort" in noise:
            return None, bytes(noise)
    return None, bytes(noise)


def send_block(port, number, chunk, verbose):
    """Send one block and wait for it to be acknowledged."""
    crc = crc16_xmodem(chunk)
    frame = bytearray([SOH, number & 0xFF, (~number) & 0xFF])
    frame += chunk
    frame.append((crc >> 8) & 0xFF)  # high byte first, as modem.s expects
    frame.append(crc & 0xFF)

    for attempt in range(1, MAX_BLOCK_RETRIES + 1):
        if attempt > 1:
            port.reset_input_buffer()
        port.write(frame)
        port.flush()
        # The receiver drains its input for a second before it sends NAK,
        # so give it more than its own three second per-character timeout.
        response, noise = read_response(port, timeout=6.0)
        if noise:
            show_receiver_text(noise)
        if response == ACK:
            return True
        if response == ESC:
            return False
        if response == NAK:
            if verbose:
                print("  block %d: NAK, retry %d/%d" % (number, attempt, MAX_BLOCK_RETRIES))
            continue
        if verbose:
            print("  block %d: no answer, retry %d/%d" % (number, attempt, MAX_BLOCK_RETRIES))
    return False


def send_file(port, payload, pad, verbose):
    total = (len(payload) + BLOCK_SIZE - 1) // BLOCK_SIZE
    for index in range(total):
        chunk = payload[index * BLOCK_SIZE:(index + 1) * BLOCK_SIZE]
        chunk = chunk.ljust(BLOCK_SIZE, bytes([pad]))
        # XMODEM block numbers start at 1 and wrap around at 256.
        number = (index + 1) & 0xFF
        if not send_block(port, number, chunk, verbose):
            print("\nTransfer failed at block %d of %d." % (index + 1, total))
            return False
        done = index + 1
        sys.stdout.write("\r  %d/%d blocks (%d%%)" % (done, total, done * 100 // total))
        sys.stdout.flush()
    print()

    for attempt in range(1, 4):
        port.write(bytes([EOT]))
        port.flush()
        response, noise = read_response(port, timeout=6.0)
        if noise:
            show_receiver_text(noise)
        if response == ACK:
            return True
        if verbose:
            print("  EOT not acknowledged, retry %d/3" % attempt)
    print("Receiver did not acknowledge the end of transmission.")
    return False


def main():
    parser = argparse.ArgumentParser(
        description="Send a loadable program to the 6502 over XMODEM/CRC.",
        epilog="Start this tool first, then press Enter on the PS/2 keyboard.",
    )
    parser.add_argument("program", nargs="?", help="project name, file name or path")
    parser.add_argument("-p", "--port", help="serial port (autodetected if omitted)")
    parser.add_argument("-b", "--baud", type=int, default=DEFAULT_BAUD,
                        help="baud rate (default: %d)" % DEFAULT_BAUD)
    parser.add_argument("-l", "--list", action="store_true",
                        help="list the programs in build/load and exit")
    parser.add_argument("--no-rtscts", action="store_true",
                        help="disable hardware flow control (the bootloader asks for CTS/RTS)")
    parser.add_argument("--pad", default="0x00",
                        help="filler for the last block (default: 0x00, classic XMODEM uses 0x1a)")
    parser.add_argument("--wait", type=float, default=120.0,
                        help="seconds to wait for the receiver (default: 120)")
    parser.add_argument("-v", "--verbose", action="store_true", help="report retries")
    args = parser.parse_args()

    if args.list:
        print_program_list()
        return 0
    if not args.program:
        parser.error("give a program name, or --list to see what is available")

    path = resolve_program(args.program)
    with open(path, "rb") as handle:
        payload = handle.read()
    if len(payload) < 3:
        sys.exit("%s is too short to contain a load address and data." % path)

    address = load_address(payload)
    if not USERRAM_START <= address < USERRAM_END:
        sys.exit("Load address $%04X is outside user RAM ($%04X-$%04X) - the receiver "
                 "would reject it." % (address, USERRAM_START, USERRAM_END - 1))

    pad = int(args.pad, 0)
    blocks = (len(payload) + BLOCK_SIZE - 1) // BLOCK_SIZE
    port_name = args.port or pick_port()

    print("File   : %s" % path)
    print("Size   : %d bytes, %d blocks, loads at $%04X" % (len(payload), blocks, address))
    print("Port   : %s, %d baud, 8N1, %s" %
          (port_name, args.baud, "no flow control" if args.no_rtscts else "CTS/RTS"))

    with serial.Serial(port=port_name, baudrate=args.baud, bytesize=8,
                       parity="N", stopbits=1, rtscts=not args.no_rtscts,
                       timeout=0.1) as port:
        port.reset_input_buffer()
        print("Waiting for the bootloader - press Enter on the PS/2 keyboard now.")
        try:
            if not wait_for_handshake(port, args.wait):
                print("No CRC request from the receiver.")
                return 1
            print("Sending...")
            success = send_file(port, payload, pad, args.verbose)
        except KeyboardInterrupt:
            # ESC is what modem.s watches for - CAN would look like a bad block.
            port.write(bytes([ESC]))
            port.flush()
            print("\nAborted, told the receiver to stop.")
            return 130

        time.sleep(1.5)  # the receiver drains its input before reporting
        pending = port.read(port.in_waiting or 1)
        if pending:
            show_receiver_text(pending)

    if success:
        print("Done - the bootloader jumps to $%04X." % address)
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())

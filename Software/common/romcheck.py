#!/usr/bin/env python3
"""Compare a freshly built ROM against the one confirmed on the hardware.

This board does not tolerate relocated code in the BASIC ROM: moving the
library modules to new addresses leaves the display dead, whether the shift
comes from code being added or removed. MEMORY_MAP.md section 5.2.1 has the
evidence. The rule that follows is that a segment which is not pinned to a
fixed offset must keep its start and its end, so a change may alter operands
but must never move a byte.

That is what this checks, before the EEPROM is burned rather than after:

  * every ROM segment present in the reference must still be there, with the
    same start and end - unless the linker config pins it with "offset=", in
    which case it owns its own block and may grow into the gap behind it
  * a segment whose start and end match but whose contents have largely
    changed is reported too. Two modules swapping a few bytes between them
    keeps the totals intact and still relocates everything in between.

Usage:
    romcheck.py --config ../../common/firmware.ext.cfg \\
                --reference reference.ext.bin \\
                --segments  reference.ext.segments \\
                --binary    ../../build/rom/microsoft_basic.ext.bin \\
                --map       ../../build/rom/microsoft_basic/microsoft_basic.ext.map

    romcheck.py --freeze ...same arguments...

--freeze records the current build as the new reference. Only do that once the
image has actually been run on the hardware - the reference is a claim that
this ROM works.
"""

import argparse
import os
import re
import shutil
import sys

# Fraction of a frozen segment that may differ before the change stops looking
# like an operand edit. The measured cases are far apart: a relocation touched
# 47% of CODE, swapping one jump target touched 0.03%.
REWRITE_LIMIT = 0.02


def parse_config(path):
    """ROM window and the segments the linker pins to a fixed offset."""
    text = open(path).read()

    match = re.search(r"^\s*ROM:\s*start=\$([0-9a-fA-F]+),\s*size=\$([0-9a-fA-F]+)",
                      text, re.M)
    if not match:
        sys.exit("No ROM memory area in %s" % path)
    rom_start = int(match.group(1), 16)
    rom_size = int(match.group(2), 16)

    pinned = set(re.findall(r"^\s*(\w+):[^;]*offset=\$[0-9a-fA-F]+", text, re.M))
    return rom_start, rom_size, pinned


def parse_segments(text, rom_start):
    """The map file's segment list, cut down to what lives in the ROM."""
    block = re.search(r"^Segment list:\s*\n.*?\n-+\n(.*?)\n\s*\n", text, re.M | re.S)
    if not block:
        sys.exit("No segment list found - is that a ld65 map file?")

    segments = {}
    for line in block.group(1).splitlines():
        fields = line.split()
        if len(fields) < 4:
            continue
        name, start, end = fields[0], int(fields[1], 16), int(fields[2], 16)
        # Everything below the ROM window is RAM and moves around freely
        if start >= rom_start:
            segments[name] = (start, end)
    return segments


def load_image(path, rom_start, rom_size):
    """The image and the address its first byte stands for.

    The build pads the linker output up to the size of the EEPROM, so the file
    can start below the ROM window.
    """
    data = open(path, "rb").read()
    return data, rom_start - (len(data) - rom_size)


def diff_count(a, a_base, b, b_base, start, end):
    return sum(1 for x in range(start, end + 1)
               if a[x - a_base] != b[x - b_base])


def diff_addresses(a, a_base, b, b_base, start, end, limit=8):
    found = []
    for x in range(start, end + 1):
        if a[x - a_base] != b[x - b_base]:
            found.append(x)
            if len(found) == limit:
                break
    return found


def freeze(args, segment_text):
    shutil.copyfile(args.binary, args.reference)
    with open(args.segments, "w") as handle:
        handle.write(segment_text)
    print("Reference updated from %s" % args.binary)
    print("  %s" % args.reference)
    print("  %s" % args.segments)
    print("Commit both only if this image has been run on the hardware.")
    return 0


def main():
    parser = argparse.ArgumentParser(
        description="Check a built ROM against the reference for relocated code.")
    parser.add_argument("--config", required=True, help="ld65 configuration file")
    parser.add_argument("--reference", required=True, help="reference ROM image")
    parser.add_argument("--segments", required=True, help="reference segment list")
    parser.add_argument("--binary", required=True, help="freshly built ROM image")
    parser.add_argument("--map", required=True, help="map file of the fresh build")
    parser.add_argument("--freeze", action="store_true",
                        help="record the fresh build as the new reference")
    parser.add_argument("--allow-rewrite", action="store_true",
                        help="accept a frozen segment whose contents largely changed")
    args = parser.parse_args()

    rom_start, rom_size, pinned = parse_config(args.config)

    if not os.path.isfile(args.map):
        sys.exit("No map file at %s - build first." % args.map)
    map_text = open(args.map).read()
    new_segments = parse_segments(map_text, rom_start)

    # The reference keeps the segment list on its own rather than a copy of the
    # whole map, so a re-freeze shows up as a readable diff in git
    segment_text = "".join("%-12s %06X %06X\n" % (n, s, e)
                           for n, (s, e) in sorted(new_segments.items()))

    if args.freeze:
        return freeze(args, segment_text)

    if not (os.path.isfile(args.reference) and os.path.isfile(args.segments)):
        print("No reference for this project yet.")
        print("Run 'make romfreeze' once an image has been confirmed on the board.")
        return 0

    old_segments = {}
    for line in open(args.segments):
        fields = line.split()
        if len(fields) == 3:
            old_segments[fields[0]] = (int(fields[1], 16), int(fields[2], 16))

    old, old_base = load_image(args.reference, rom_start, rom_size)
    new, new_base = load_image(args.binary, rom_start, rom_size)

    failures = []

    gone = sorted(set(old_segments) - set(new_segments))
    added = sorted(set(new_segments) - set(old_segments))
    for name in gone:
        failures.append("segment %s has disappeared" % name)
    for name in added:
        print("note: segment %s is new" % name)

    print("%-12s %-15s %-15s %8s  %s" %
          ("SEGMENT", "REFERENCE", "NOW", "DIFFER", "VERDICT"))

    for name in sorted(set(old_segments) & set(new_segments)):
        o_start, o_end = old_segments[name]
        n_start, n_end = new_segments[name]
        is_pinned = name in pinned

        # Only compare the part both images have
        overlap_end = min(o_end, n_end)
        differ = (diff_count(old, old_base, new, new_base, n_start, overlap_end)
                  if n_start == o_start else -1)

        if n_start != o_start:
            verdict = "MOVED"
            failures.append("%s starts at $%04X instead of $%04X"
                            % (name, n_start, o_start))
        elif n_end != o_end:
            if is_pinned:
                verdict = "resized %+d (pinned)" % (n_end - o_end)
            else:
                verdict = "RESIZED %+d" % (n_end - o_end)
                failures.append(
                    "%s ends at $%04X instead of $%04X - everything linked after "
                    "it has moved" % (name, n_end, o_end))
        elif differ == 0:
            verdict = "identical"
        elif differ > (o_end - o_start + 1) * REWRITE_LIMIT and not is_pinned:
            verdict = "REWRITTEN"
            failures.append(
                "%s keeps its size but %d of %d bytes changed - that is not an "
                "operand edit, check whether two modules swapped length"
                % (name, differ, o_end - o_start + 1))
        else:
            verdict = "operands only"

        print("%-12s $%04X-$%04X   $%04X-$%04X   %8s  %s"
              % (name, o_start, o_end, n_start, n_end,
                 "-" if differ < 0 else differ, verdict))

        if 0 < differ <= 8 or (differ > 0 and verdict == "operands only"):
            where = diff_addresses(old, old_base, new, new_base, n_start, overlap_end)
            print("%-12s   at %s%s" % ("", " ".join("$%04X" % a for a in where),
                                       " ..." if differ > len(where) else ""))

    print()
    if failures:
        print("FAIL - do not burn this image:")
        for line in failures:
            print("  * %s" % line)
        print("See MEMORY_MAP.md section 5.2.1 for why, and for the ways around it.")
        return 1

    print("OK - nothing has moved, safe to burn.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

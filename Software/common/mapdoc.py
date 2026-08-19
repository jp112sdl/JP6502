#!/usr/bin/env python3
"""Check the address tables in MEMORY_MAP.md against the ld65 mapfiles.

The tables in that document are the thing people reach for before deciding
where new code or new variables go, and they drift silently - by 2026-08-19
the OS/1 ROM table was missing two whole segments and was overstating the
free space by nearly 2.5 KB. This makes the drift a build error instead.

Tables opt in with an HTML comment on the line above them, so the checker
does not have to guess at section numbers or headings:

    <!-- mapdoc: os1 rom -->          full ROM table for build rom/os1
    <!-- mapdoc: os1 BSS -->          per module breakdown of one segment

What a ROM table has to satisfy:

  * it covers the whole ROM window from the linker config, without a gap,
    and the sizes add up to the size of that window
  * every row is either one segment from the mapfile, or an exact run of
    neighbouring segments (so BAS_VEC/BAS_KEY/BAS_ERR may share a row), or
    a stretch no segment occupies - which then has to say "frei"

A segment table is checked more loosely: every module contribution in the
mapfile has to appear as a row. Extra rows are allowed, because those tables
also describe space that no module claims. A stale "unused" row is therefore
not caught here - the ROM tables are the rigorous ones.

Usage:
    mapdoc.py --doc MEMORY_MAP.md --config common/firmware.ext.cfg \\
              --build build/rom --address-mode ext
"""

import argparse
import os
import re
import sys

ROW = re.compile(r"\|\s*`\$([0-9A-Fa-f]{4})`\s*\|\s*`\$([0-9A-Fa-f]{4})`\s*\|"
                 r"\s*(\d+)\s*\|\s*(.*?)\s*\|")
MARKER = re.compile(r"<!--\s*mapdoc:\s*(\S+)\s+(\S+)\s*-->")


def rom_window(path):
    text = open(path).read()
    match = re.search(r"^\s*ROM:\s*start=\$([0-9a-fA-F]+),\s*size=\$([0-9a-fA-F]+)",
                      text, re.M)
    if not match:
        sys.exit("No ROM memory area in %s" % path)
    start = int(match.group(1), 16)
    return start, int(match.group(2), 16)


def read_map(path):
    """Segments and per module contributions out of one ld65 map file."""
    text = open(path).read()

    segments = {}
    block = re.search(r"^Segment list:\s*\n.*?\n-+\n(.*?)\n\s*\n", text, re.M | re.S)
    if not block:
        sys.exit("No segment list in %s" % path)
    for line in block.group(1).splitlines():
        fields = line.split()
        if len(fields) >= 4:
            segments[fields[0]] = (int(fields[1], 16), int(fields[2], 16))

    modules = []
    block = re.search(r"^Modules list:\s*\n-+\n(.*?)\n\s*\nSegment list:", text,
                      re.M | re.S)
    name = None
    for line in block.group(1).splitlines() if block else []:
        if not line.startswith(" "):
            name = re.sub(r".*\(([^)]+)\)$", r"\1", line.strip().rstrip(":"))
        else:
            fields = line.split()
            modules.append((name, fields[0],
                            int(fields[1].split("=")[1], 16),
                            int(fields[2].split("=")[1], 16)))
    return segments, modules


def table_after(doc, index):
    """The rows of the markdown table following a marker."""
    rows = []
    for line in doc[index:].splitlines()[1:]:
        match = ROW.match(line.strip())
        if match:
            rows.append((int(match.group(1), 16), int(match.group(2), 16),
                         int(match.group(3)), match.group(4)))
        elif rows and not line.strip().startswith("|"):
            break
    return rows


def check_rom_table(project, rows, segments, window, problems):
    start, size = window
    end = start + size - 1
    placed = sorted((s, e, n) for n, (s, e) in segments.items() if s >= start)

    if not rows:
        problems.append("%s: no table under the marker" % project)
        return

    cursor = start
    for a, b, declared, text in rows:
        if a != cursor:
            problems.append("%s: row $%04X-$%04X starts at $%04X, expected $%04X"
                            % (project, a, b, a, cursor))
        if b - a + 1 != declared:
            problems.append("%s: row $%04X-$%04X says %d bytes, spans %d"
                            % (project, a, b, declared, b - a + 1))
        inside = [x for x in placed if x[0] <= b and x[1] >= a]
        if not inside:
            if "frei" not in text:
                problems.append("%s: $%04X-$%04X holds no segment but is not "
                                "marked frei" % (project, a, b))
        else:
            covered = min(x[0] for x in inside), max(x[1] for x in inside)
            if covered != (a, b):
                problems.append(
                    "%s: row $%04X-$%04X does not line up with the segments in it "
                    "(%s spans $%04X-$%04X)"
                    % (project, a, b, "/".join(x[2] for x in inside),
                       covered[0], covered[1]))
            gaps = sorted(inside)
            for first, second in zip(gaps, gaps[1:]):
                if second[0] != first[1] + 1:
                    problems.append("%s: row $%04X-$%04X spans a gap between %s "
                                    "and %s" % (project, a, b, first[2], second[2]))
        cursor = b + 1

    if cursor - 1 != end:
        problems.append("%s: table ends at $%04X, the ROM ends at $%04X"
                        % (project, cursor - 1, end))

    total = sum(r[2] for r in rows)
    if total != size:
        problems.append("%s: rows add up to %d bytes, the ROM window is %d"
                        % (project, total, size))


def check_segment_table(project, segment, rows, segments, modules, problems):
    if segment not in segments:
        problems.append("%s: no segment %s in the map file" % (project, segment))
        return
    base = segments[segment][0]
    have = {(a, b): size for a, b, size, _ in rows}
    for name, seg, offset, size in modules:
        if seg != segment or not size:
            continue
        a, b = base + offset, base + offset + size - 1
        if (a, b) not in have:
            problems.append("%s/%s: %s occupies $%04X-$%04X (%d bytes), no such row"
                            % (project, segment, name, a, b, size))
        elif have[(a, b)] != size:
            problems.append("%s/%s: row $%04X-$%04X says %d bytes, %s occupies %d"
                            % (project, segment, a, b, have[(a, b)], name, size))


def main():
    parser = argparse.ArgumentParser(
        description="Check MEMORY_MAP.md against the ld65 map files.")
    parser.add_argument("--doc", required=True)
    parser.add_argument("--config", required=True)
    parser.add_argument("--build", required=True, help="folder holding the ROM builds")
    parser.add_argument("--address-mode", default="ext")
    args = parser.parse_args()

    doc = open(args.doc).read()
    window = rom_window(args.config)

    markers = list(MARKER.finditer(doc))
    if not markers:
        print("No mapdoc markers in %s - nothing to check." % args.doc)
        return 0

    problems = []
    cache = {}
    checked = 0
    for marker in markers:
        project, what = marker.group(1), marker.group(2)
        if project not in cache:
            path = os.path.join(args.build, project,
                                "%s.%s.map" % (project, args.address_mode))
            if not os.path.isfile(path):
                problems.append("%s: no map file at %s - build it first"
                                % (project, path))
                cache[project] = None
            else:
                cache[project] = read_map(path)
        if cache[project] is None:
            continue
        segments, modules = cache[project]
        rows = table_after(doc, marker.end())
        checked += 1
        if what == "rom":
            check_rom_table(project, rows, segments, window, problems)
        else:
            check_segment_table(project, what, rows, segments, modules, problems)

    print("%s: %d table(s) checked against %s" % (args.doc, checked, args.build))
    if problems:
        print("\nFAIL - the document no longer matches the build:")
        for line in problems:
            print("  * %s" % line)
        return 1
    print("OK - every table matches the map files.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

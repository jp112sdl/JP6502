#!/usr/bin/env python3
"""Look for spurious VDP strobes in a sigrok capture taken with rom/vdp_scope.

The channel order is the one MEMORY_MAP.md 5.5 asks for:

    1 phi2   2 D0   3 /CSW   4 /CSR   5 MODE   6 ROM /CE   7 ROM /OE   8 marker

vdp_scope drives the marker high for the copy that works, then again for the
copy that does not, and leaves a long quiet stretch between rounds. This script
finds those pairs, counts the strobes inside each, and separates real accesses
from glitches by width - the two populations are nowhere near each other.

    python3 common/srglitch.py capture.sr
"""

import collections
import sys
import zipfile

import numpy as np

CH_CSW = 2
CH_CSR = 3
CH_MARK = 7
GLITCH_NS = 500                 # anything shorter than this is not an access


def load(path):
    with zipfile.ZipFile(path) as z:
        meta = z.read("metadata").decode()
        rate = 0
        for line in meta.splitlines():
            if line.startswith("samplerate"):
                value = line.split("=", 1)[1].strip()
                mult = {"MHz": 1e6, "kHz": 1e3, "Hz": 1}
                for suffix, factor in mult.items():
                    if value.endswith(suffix):
                        rate = float(value[: -len(suffix)]) * factor
                        break
        names = [n for n in z.namelist() if n.startswith("logic-1-")]
        names.sort(key=lambda n: int(n.rsplit("-", 1)[1]))
        data = np.concatenate([np.frombuffer(z.read(n), dtype=np.uint8) for n in names])
    return data, rate


def pulses(data, bit, lo, hi):
    """Active-low pulses in [lo, hi) as (start, width) in samples."""
    ch = ((data[lo:hi] >> bit) & 1).astype(np.int8)
    starts = np.flatnonzero(np.diff(ch) == -1) + 1
    ends = np.flatnonzero(np.diff(ch) == 1) + 1
    out = []
    for s in starts:
        e = ends[ends > s]
        if len(e):
            out.append((s, e[0] - s))
    return out


def windows(data, rate):
    """Marker pulse pairs, skipping stretches that are obviously noise."""
    mark = ((data >> CH_MARK) & 1).astype(np.int8)
    d = np.diff(mark)
    rise = np.flatnonzero(d == 1) + 1
    fall = np.flatnonzero(d == -1) + 1
    if len(fall) and len(rise) and fall[0] < rise[0]:
        fall = fall[1:]
    n = min(len(rise), len(fall))
    rise, fall = rise[:n], fall[:n]
    quiet = np.flatnonzero((rise[1:] - fall[:-1]) > rate / 1000)   # 1 ms
    starts = np.concatenate([[0], quiet + 1])
    ends = np.concatenate([quiet + 1, [n]])
    return [(rise[s], fall[s], rise[s + 1], fall[s + 1])
            for s, e in zip(starts, ends) if e - s == 2]


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 1
    data, rate = load(sys.argv[1])
    if not rate:
        print("no samplerate in the capture")
        return 1
    ns = 1e9 / rate
    print(f"{len(data)} samples at {rate/1e6:g} MHz = {len(data)/rate*1e3:.0f} ms, "
          f"resolution {ns:.0f} ns")
    if rate < 20e6:
        print("WARNING: below 20 MHz nothing here can be trusted - a write strobe "
              "is about 450 ns wide at a 1 MHz bus")

    pairs = windows(data, rate)
    print(f"{len(pairs)} usable marker pairs\n")

    limit = GLITCH_NS / ns
    for column, label in ((0, "works"), (2, "fails")):
        writes = collections.Counter()
        reads = collections.Counter()
        glitches = collections.Counter()
        offsets = []
        for w in pairs:
            lo, hi = w[column], w[column + 1]
            writes[len(pulses(data, CH_CSW, lo, hi))] += 1
            ends = np.array([s + n for s, n in pulses(data, CH_CSW, lo, hi)])
            real = short = 0
            for start, width in pulses(data, CH_CSR, lo, hi):
                if width >= limit:
                    real += 1
                else:
                    short += 1
                    near = ends[np.abs(ends - start) < limit]
                    if len(near):
                        offsets.append((start - near[0]) * ns)
            reads[real] += 1
            glitches[short] += 1
        print(f"the copy that {label}:")
        print(f"  /CSW           {dict(sorted(writes.items()))}")
        print(f"  /CSR, real     {dict(sorted(reads.items()))}")
        print(f"  /CSR, glitches {dict(sorted(glitches.items()))}")
        if offsets:
            print(f"  glitch sits {np.median(offsets):+.0f} ns from the end of a write strobe")
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""build store/apps/srb2.app/TITLE.wad from srb2's real title screen graphics.

srb2 2.2 ships SOC_TITL with "TitlePicsMode = Alacroix", so the title screen is
the alacroix artwork: the emblem, the unfurling ribbon with the SONIC text, the
ROBO BLAST 2 line, the dropping TWO, and sonic/tails/knuckles idling.  the T2*
lumps are the smallest of the three shipped scales.

everything is box-downsampled to the picture the opencomputers cell grid can
show, re-quantised to the game's own PLAYPAL, and written into a wad so the app
can decode one frame at a time instead of holding every frame in ram.
"""
import sys, os, struct
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from srb2lib import Pk3, playpal, decode_patch, to_rgb, downsample

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "store", "apps", "srb2.app", "TITLE.wad")

# the picture the app composes onto, and the scale from srb2's 320x200 space
TW, TH = 112, 70
BASE_SCALE = TW / 320.0
SRC_SCALE = 2.0            # T2 lumps are drawn at FRACUNIT/2

pk3 = Pk3("srb2.pk3")
PAL = playpal(pk3)

# name in the wad -> (lump prefix, frame count, base x, base y)
GROUPS = [
    ("EMBL", "T2EMBL", 1, 40, 20),
    ("RIBB", "T2RIBB", 25, 39, 88),
    ("SONT", "T2SONT", 29, 89, 92),
    ("ROBO", "T2ROBO", 1, 79, 132),
    ("TWOT", "T2TWOT", 16, 106, 118),
    ("SOIB", "T2SOIB", 17, 89, 13),
    ("TAIB", "T2TAIB", 17, 35, 19),
    ("KNIB", "T2KNIB", 20, 167, 7),
]

_cache = {}


def nearest(r, g, b):
    key = (r, g, b)
    hit = _cache.get(key)
    if hit is not None:
        return hit
    best, bd = 0, 1 << 30
    for i, (pr, pg, pb) in enumerate(PAL):
        d = (pr - r) ** 2 + (pg - g) ** 2 + (pb - b) ** 2
        if d < bd:
            bd, best = d, i
    _cache[key] = best
    return best


def lump_names(prefix, count):
    if count == 1:
        return [prefix]
    return ["%s%02d" % (prefix, i + 1) for i in range(count)]


def build():
    lumps = []
    # PALETTE: the game's playpal, so the app never invents a colour
    pal = bytearray()
    for r, g, b in PAL:
        pal += bytes((r, g, b))
    lumps.append(("PALETTE", bytes(pal)))

    total = 0
    for name, prefix, count, bx, by in GROUPS:
        srcs = lump_names(prefix, count)
        for i, src in enumerate(srcs):
            if not pk3.has(src):
                print("  missing", src, file=sys.stderr)
                continue
            w, h, xo, yo, idx = decode_patch(pk3.get(src))
            rgb = to_rgb(idx, PAL, w, h)
            factor = SRC_SCALE / BASE_SCALE          # 640x400 space -> TWxTH
            small = downsample(rgb, factor)
            sh = len(small)
            sw = len(small[0])
            data = bytearray()
            for row in small:
                for v in row:
                    data.append(0 if v < 0 else nearest((v >> 16) & 255, (v >> 8) & 255, v & 255))
            px = round(bx * BASE_SCALE)
            py = round(by * BASE_SCALE)
            head = struct.pack("<HHhh", sw, sh, px, py)
            nm = name if count == 1 else "%s%02d" % (name, i + 1)
            lumps.append((nm, bytes(head) + bytes(data)))
            total += sw * sh

    # a plain wad: header, payloads, directory
    payload = bytearray()
    entries = []
    for nm, data in lumps:
        entries.append((len(payload) + 12, len(data), nm))
        payload += data
    directory = bytearray()
    for pos, size, nm in entries:
        directory += struct.pack("<ii", pos, size) + nm.encode().ljust(8, b"\0")
    out = struct.pack("<4sii", b"PWAD", len(entries), 12 + len(payload)) + bytes(payload) + bytes(directory)
    with open(os.path.abspath(OUT), "wb") as f:
        f.write(out)
    print("wrote %s: %d lumps, %d pixels, %.0f KB"
          % (OUT, len(entries), total, len(out) / 1024.0))


if __name__ == "__main__":
    build()

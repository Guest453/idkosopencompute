#!/usr/bin/env python3
"""build store/apps/srb2.app/sprites.lua from the real srb2 sprite lumps.

every frame here is decoded out of srb2.pk3 / characters.pk3, translated with
the game's own skincolor ramp where the engine would, box-downsampled to a size
the opencomputers cell grid can actually show, and re-quantised to PLAYPAL so
the output only ever contains colors the game itself uses.

output format keeps opencomputers ram in mind: one shared palette plus one byte
per pixel packed into strings (0 = transparent).
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from srb2lib import Pk3, playpal, decode_patch, to_rgb, trim, downsample

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..",
                   "store", "apps", "srb2.app", "sprites.lua")

pk3 = Pk3("srb2.pk3")
chars = Pk3("characters.pk3")
PAL = playpal(pk3)

# SKINCOLOR_BLUE ramp, info.c: sonic's sprites store skin pixels at 96..111 and
# the engine remaps them per skincolor. blue is sonic's prefcolor.
BLUE_RAMP = [0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99,
             0x9a, 0x9b, 0x9c, 0x9d, 0x9e, 0x9f, 0xfd, 0xfe]
SKIN_START = 96


def translate_skin(idx_img):
    for row in idx_img:
        for x, v in enumerate(row):
            if SKIN_START <= v < SKIN_START + 16:
                row[x] = BLUE_RAMP[v - SKIN_START]
    return idx_img


# name -> (source pk3, lump, max dimension after downsample, translate?)
SPRITES = [
    # sonic, rotation 5 = seen from behind, which is the chase camera's view
    ("sonic1",   chars, "STNDA5", 30, True),
    ("sonic2",   chars, "STNDB5", 30, True),
    ("sonic3",   chars, "STNDC5", 30, True),
    ("sonic4",   chars, "STNDD5", 30, True),
    ("walk1",    chars, "WALKA5", 30, True),
    ("walk2",    chars, "WALKB5", 30, True),
    ("walk3",    chars, "WALKC5", 30, True),
    ("walk4",    chars, "WALKD5", 30, True),
    ("walk5",    chars, "WALKE5", 30, True),
    ("walk6",    chars, "WALKF5", 30, True),
    ("walk7",    chars, "WALKG5", 30, True),
    ("walk8",    chars, "WALKH5", 30, True),
    ("roll1",    chars, "ROLLA5", 24, True),
    ("roll2",    chars, "ROLLB5", 24, True),
    ("roll3",    chars, "ROLLD5", 24, True),
    ("roll4",    chars, "ROLLE5", 24, True),
    ("spring",   chars, "SPNGA5", 30, True),
    ("fall1",    chars, "FALLA5", 30, True),
    ("fall2",    chars, "FALLB5", 30, True),
    # collectibles and level furniture
    ("ring1",    pk3, "RINGA0", 16, False),
    ("ring2",    pk3, "RINGC0W0", 16, False),
    ("ring3",    pk3, "RINGE0U0", 16, False),
    ("ring4",    pk3, "RINGG0S0", 16, False),
    ("crawla1",  pk3, "POSSA1", 26, False),
    ("crawla2",  pk3, "POSSB1", 26, False),
    ("crawla3",  pk3, "POSSC1", 26, False),
    ("crawla4",  pk3, "POSSD1", 26, False),
    ("crawlaR1", pk3, "SPOSA1", 26, False),
    ("crawlaR2", pk3, "SPOSB1", 26, False),
    ("fish1",    pk3, "FISHA0", 24, False),
    ("fish2",    pk3, "FISHB0", 24, False),
    ("springY1", pk3, "SPRYA0", 24, False),
    ("springY2", pk3, "SPRYC0", 24, False),
    ("springR1", pk3, "SPRRA0", 24, False),
    ("springR2", pk3, "SPRRC0", 24, False),
    ("springD",  pk3, "YSPRA1", 24, False),
    ("springDR", pk3, "RSPRA1", 24, False),
    ("springH",  pk3, "SSWYA1", 24, False),
    ("springHR", pk3, "SSWRA1", 24, False),
    ("monRing",  pk3, "TVRIA0", 24, False),
    ("monInv",   pk3, "TVIVA0", 24, False),
    ("monLife",  pk3, "TV1UA0", 24, False),
    ("monSneak", pk3, "TVSSA0", 24, False),
    ("monAttr",  pk3, "TVATA0", 24, False),
    ("monForce", pk3, "TVFOA0", 24, False),
    ("monArma",  pk3, "TVARA0", 24, False),
    ("monWhirl", pk3, "TVWWA0", 24, False),
    ("monElem",  pk3, "TVELA0", 24, False),
    ("monEgg",   pk3, "TVEGA0", 24, False),
    ("goal",     pk3, "SIGND0", 30, False),
    ("star1",    pk3, "STPTA0M0", 34, False),
    ("star2",    pk3, "STPTG0", 34, False),
    ("spike",    pk3, "USPKA0", 22, False),
    ("bubble",   pk3, "BUBLE0", 14, False),
    ("token",    pk3, "TOKEA0", 18, False),
    ("emblem",   pk3, "EMBMA0", 18, False),
    ("flower1",  pk3, "FWR1A0", 20, False),
    ("flower2",  pk3, "FWR2A0", 20, False),
    ("flower3",  pk3, "FWR3A0", 20, False),
    ("bush1",    pk3, "BUS1A0", 26, False),
    ("bush2",    pk3, "BUS2A0", 26, False),
    ("tree1",    pk3, "TRE1A0", 44, False),
    ("tree2",    pk3, "TRE1B0", 44, False),
]


def nearest(pal, r, g, b, cache={}):
    key = (r, g, b)
    hit = cache.get(key)
    if hit is not None:
        return hit
    best, bd = 0, 1 << 30
    for i, (pr, pg, pb) in enumerate(pal):
        d = (pr - r) ** 2 + (pg - g) ** 2 + (pb - b) ** 2
        if d < bd:
            bd, best = d, i
    cache[key] = best
    return best


def build():
    used = {}          # playpal index -> shared palette slot
    order = []
    out = []
    total_px = 0
    for name, src, lump, maxdim, tr in SPRITES:
        if not src.has(lump):
            print("  missing:", name, lump, file=sys.stderr)
            continue
        w, h, xo, yo, idx = decode_patch(src.get(lump))
        if tr:
            idx = translate_skin(idx)
        rgb, _, _ = trim(to_rgb(idx, PAL, w, h))
        sh = len(rgb)
        sw = len(rgb[0])
        factor = max(1.0, max(sw, sh) / float(maxdim))
        small = downsample(rgb, factor)
        rows = []
        for row in small:
            bs = bytearray()
            for v in row:
                if v < 0:
                    bs.append(0)
                else:
                    pi = nearest(PAL, (v >> 16) & 255, (v >> 8) & 255, v & 255)
                    slot = used.get(pi)
                    if slot is None:
                        order.append(pi)
                        slot = used[pi] = len(order)   # 1-based, 0 = transparent
                    bs.append(slot)
            rows.append(bytes(bs))
        total_px += len(rows) * len(rows[0])
        # sw/sh are the lump's own pixel size: doom draws sprites at one texel
        # per map unit, so these are the object's world size.
        out.append((name, lump, len(rows[0]), len(rows), rows, sw, sh))

    if len(order) > 255:
        raise SystemExit("shared palette overflow: %d colors" % len(order))

    def esc(bs):
        return "".join("\\%d" % b for b in bs)

    lines = [
        "-- sprites.lua - real srb2 sprite art, generated by tools/srb2/make_sprites.py",
        "-- every frame is decoded from srb2.pk3 / characters.pk3 (doom picture lumps),",
        "-- sonic is translated through the engine's SKINCOLOR_BLUE ramp, frames are",
        "-- box-downsampled for the cell grid and re-quantised to the game's PLAYPAL.",
        "-- storage is one shared palette plus one byte per pixel (0 = transparent).",
        "local S = {}",
        "S.pal = {" + ",".join(str((PAL[i][0] << 16) | (PAL[i][1] << 8) | PAL[i][2])
                               for i in order) + "}",
    ]
    for name, lump, w, h, rows, sw, sh in out:
        lines.append("-- %s (%s)" % (lump, name))
        lines.append("S.%s = {bw=%d,bh=%d,w=%d,h=%d,rows={" % (name, w, h, sw, sh))
        lines.append(",\n".join('"%s"' % esc(r) for r in rows))
        lines.append("}}")
    lines.append("return S")
    text = "\n".join(lines) + "\n"
    with open(os.path.abspath(OUT), "w") as f:
        f.write(text)
    print("wrote %s: %d sprites, %d palette colors, %d pixels, %.0f KB source"
          % (OUT, len(out), len(order), total_px, len(text) / 1024.0))


if __name__ == "__main__":
    build()

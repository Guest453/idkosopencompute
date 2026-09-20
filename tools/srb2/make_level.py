#!/usr/bin/env python3
"""build store/apps/srb2.app/GFZ1.wad from srb2's own MAP01.

zones.pk3 carries Greenflower Zone Act 1 as a plain doom-format map wad.  the
geometry lumps are copied through byte for byte; what changes is that the
sidedefs and the sector flat names are resolved here into small colour lumps,
using the average colour of the real texture or flat the map asks for.  that
keeps the wad under the app store's 256 KiB per-file limit and means the app
never has to carry a texture-name table.

lumps written:
  MAP01 THINGS LINEDEFS VERTEXES SEGS SSECTORS NODES SECTORS
  SIDECOL   s16 sector, u8 wall colour slot, per sidedef
  WALLPAL   rgb per wall colour slot
  SECTCOL   floor rgb, ceiling rgb, flags, per sector
"""
import sys, os, struct
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from srb2lib import Pk3, playpal, decode_patch

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "store", "apps", "srb2.app", "GFZ1.wad")
MAP_IN_PK3 = "Maps/Singleplayer/Campaign/01 Greenflower Zone/MAP01.wad"

pk3 = Pk3("srb2.pk3")
zones = Pk3("zones.pk3")
PAL = playpal(pk3)
ROCK = (0x89, 0x4C, 0x1C)


def lumps_of(data):
    magic, n, off = struct.unpack("<4sii", data[:12])
    out = []
    for i in range(n):
        p, s, nm = struct.unpack("<ii8s", data[off + i * 16:off + i * 16 + 16])
        out.append((nm.rstrip(b"\0").decode(), p, s))
    return out


def avg_patch(name):
    """average colour of a doom picture lump's opaque pixels"""
    try:
        b = pk3.get(name)
    except KeyError:
        return None
    try:
        w, h, xo, yo, idx = decode_patch(b)
    except Exception:
        return None
    if w * h > 4096 * 4096:
        return None
    r = g = bl = n = 0
    for row in idx:
        for v in row:
            if v >= 0:
                r += PAL[v][0]; g += PAL[v][1]; bl += PAL[v][2]; n += 1
    if not n:
        return None
    return (r // n, g // n, bl // n)


def avg_flat(name):
    """flats are raw palette bytes; srb2 uses 64x64 and 128x128"""
    try:
        b = pk3.get(name)
    except KeyError:
        return None
    if len(b) not in (64 * 64, 128 * 128, 256 * 256, 32 * 32):
        # some "flats" are really pictures
        return avg_patch(name)
    r = g = bl = 0
    for v in b:
        r += PAL[v][0]; g += PAL[v][1]; bl += PAL[v][2]
    n = len(b)
    return (r // n, g // n, bl // n)


def load_texture_defs():
    """parse every TEXTURES.* lump: texture name -> list of patch names"""
    defs = {}
    for key in pk3.index:
        if not key.startswith("TEXTURES"):
            continue
        text = pk3.get(key).decode("latin-1")
        cur = None
        for line in text.splitlines():
            line = line.strip()
            if line.startswith("//"):
                continue
            if line.lower().startswith(("walltexture", "texture", "sprite", "graphic", "flat")) and '"' in line:
                cur = line.split('"')[1].upper()
                defs.setdefault(cur, [])
            elif line.lower().startswith("patch") and '"' in line and cur:
                defs[cur].append(line.split('"')[1].upper())
    return defs


TEXDEFS = load_texture_defs()
_texcache = {}


def texture_color(name):
    name = name.upper().strip()
    if not name or name == "-":
        return None
    if name in _texcache:
        return _texcache[name]
    col = None
    patches = TEXDEFS.get(name)
    if patches:
        acc = [0, 0, 0]
        n = 0
        for p in patches:
            c = avg_patch(p)
            if c:
                acc[0] += c[0]; acc[1] += c[1]; acc[2] += c[2]; n += 1
        if n:
            col = (acc[0] // n, acc[1] // n, acc[2] // n)
    if col is None:
        col = avg_patch(name)
    if col is None:
        col = ROCK
    _texcache[name] = col
    return col


def flat_color(name):
    name = name.upper().strip()
    if not name or name == "-":
        return None
    if name in _texcache:
        return _texcache[name]
    col = avg_flat(name) or texture_color(name) or (0x8A, 0x8A, 0x8A)
    _texcache[name] = col
    return col


def build():
    data = zones.z.read(MAP_IN_PK3)
    src = {nm: (p, s) for nm, p, s in lumps_of(data)}
    for need in ("THINGS", "LINEDEFS", "SIDEDEFS", "VERTEXES", "SEGS", "SSECTORS", "NODES", "SECTORS"):
        if need not in src:
            raise SystemExit("MAP01.wad is missing " + need)

    def raw(nm):
        p, s = src[nm]
        return data[p:p + s]

    # ---- sidedefs -> sector + wall colour slot -----------------------------
    sd = raw("SIDEDEFS")
    nsides = len(sd) // 30
    slots, slot_of = [], {}

    def slot(col):
        k = slot_of.get(col)
        if k is None:
            slots.append(col)
            k = slot_of[col] = len(slots) - 1
            if k > 254:
                raise SystemExit("too many distinct wall colours")
        return k

    slot(ROCK)
    sidecol = bytearray()
    for i in range(nsides):
        o = i * 30
        sec = struct.unpack("<h", sd[o + 28:o + 30])[0]
        upper = sd[o + 4:o + 12].rstrip(b"\0").decode("latin-1")
        lower = sd[o + 12:o + 20].rstrip(b"\0").decode("latin-1")
        mid = sd[o + 20:o + 28].rstrip(b"\0").decode("latin-1")
        col = None
        for name in (mid, lower, upper):
            col = texture_color(name)
            if col:
                break
        sidecol += struct.pack("<hB", sec, slot(col or ROCK))

    wallpal = bytearray()
    for r, g, b in slots:
        wallpal += bytes((r, g, b))

    # ---- sectors -> floor/ceiling colour and flags --------------------------
    sc = raw("SECTORS")
    nsec = len(sc) // 26
    sectcol = bytearray()
    for i in range(nsec):
        o = i * 26
        fl = sc[o + 4:o + 12].rstrip(b"\0").decode("latin-1")
        ce = sc[o + 12:o + 20].rstrip(b"\0").decode("latin-1")
        fc = flat_color(fl) or (0x8A, 0x8A, 0x8A)
        cc = flat_color(ce) or (0x8A, 0x8A, 0x8A)
        flags = 0
        if "SKY" in ce.upper():
            flags |= 1
        if "WATER" in ce.upper():
            flags |= 2
        if "WATER" in fl.upper():
            flags |= 4
        sectcol += bytes(fc) + bytes(cc) + bytes((flags,))

    order = [
        ("MAP01", b""),
        ("THINGS", raw("THINGS")),
        ("LINEDEFS", raw("LINEDEFS")),
        ("VERTEXES", raw("VERTEXES")),
        ("SEGS", raw("SEGS")),
        ("SSECTORS", raw("SSECTORS")),
        ("NODES", raw("NODES")),
        ("SECTORS", raw("SECTORS")),
        ("SIDECOL", bytes(sidecol)),
        ("WALLPAL", bytes(wallpal)),
        ("SECTCOL", bytes(sectcol)),
    ]
    payload = bytearray()
    entries = []
    for nm, b in order:
        entries.append((len(payload) + 12, len(b), nm))
        payload += b
    directory = bytearray()
    for pos, size, nm in entries:
        directory += struct.pack("<ii", pos, size) + nm.encode().ljust(8, b"\0")
    out = struct.pack("<4sii", b"PWAD", len(entries), 12 + len(payload)) + bytes(payload) + bytes(directory)
    with open(os.path.abspath(OUT), "wb") as f:
        f.write(out)
    print("wrote %s: %d lumps, %d sidedefs, %d sectors, %d wall colours, %.0f KiB"
          % (OUT, len(entries), nsides, nsec, len(slots), len(out) / 1024.0))


if __name__ == "__main__":
    build()

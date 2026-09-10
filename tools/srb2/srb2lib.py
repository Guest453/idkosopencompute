"""shared helpers for converting real srb2 assets into idk os app data.

these read the game's own files (srb2.pk3 / characters.pk3 / zones.pk3) and
decode doom picture lumps exactly as the engine does, including the padding
bytes around every post.  nothing here invents artwork.
"""
import zipfile, struct, os

SRB2 = os.environ.get("SRB2_DIR", "/tmp/opencode/srb2/extracted")


class Pk3:
    def __init__(self, name):
        self.z = zipfile.ZipFile(os.path.join(SRB2, name))
        self.index = {}
        for n in self.z.namelist():
            if n.endswith("/"):
                continue
            base = n.split("/")[-1]
            base = base[:-4] if base.lower().endswith(".lmp") else base
            self.index.setdefault(base.upper(), n)

    def get(self, lump):
        n = self.index.get(lump.upper())
        if n is None:
            raise KeyError(lump)
        return self.z.read(n)

    def has(self, lump):
        return lump.upper() in self.index

    def match(self, prefix):
        p = prefix.upper()
        return sorted(k for k in self.index if k.startswith(p))


def playpal(pk3):
    raw = pk3.get("PLAYPAL")
    return [(raw[i * 3], raw[i * 3 + 1], raw[i * 3 + 2]) for i in range(256)]


def decode_patch(b):
    """decode a doom picture lump -> (w, h, xoff, yoff, index grid, -1 = transparent)"""
    if len(b) < 8:
        raise ValueError("lump too small for a picture")
    w, h, xo, yo = struct.unpack("<HHhh", b[:8])
    # guard against reading a flat or a sound as if it were a picture
    if w < 1 or h < 1 or w > 4096 or h > 4096 or 8 + 4 * w > len(b):
        raise ValueError("not a doom picture lump")
    cols = struct.unpack("<%dI" % w, b[8:8 + 4 * w])
    if any(c >= len(b) for c in cols):
        raise ValueError("not a doom picture lump")
    img = [[-1] * w for _ in range(h)]
    for x in range(w):
        off = cols[x]
        prev = -1
        while off < len(b):
            top = b[off]
            if top == 0xFF:
                break
            ln = b[off + 1]
            # tall-patch support: deltas smaller than the previous one are relative
            if top <= prev:
                top = prev + top
            prev = top
            # b[off+2] is a padding byte, pixels start at off+3, then one more pad
            for i in range(ln):
                y = top + i
                if 0 <= y < h:
                    img[y][x] = b[off + 3 + i]
            off += ln + 4
    return w, h, xo, yo, img


def to_rgb(img, pal, w, h):
    return [[(-1 if img[y][x] < 0 else
              (pal[img[y][x]][0] << 16) | (pal[img[y][x]][1] << 8) | pal[img[y][x]][2])
             for x in range(w)] for y in range(h)]


def trim(rgb):
    h = len(rgb)
    w = len(rgb[0]) if h else 0
    x0, y0, x1, y1 = w, h, -1, -1
    for y in range(h):
        for x in range(w):
            if rgb[y][x] >= 0:
                x0 = min(x0, x); x1 = max(x1, x)
                y0 = min(y0, y); y1 = max(y1, y)
    if x1 < 0:
        return [[-1]], 0, 0
    return [row[x0:x1 + 1] for row in rgb[y0:y1 + 1]], x0, y0


def downsample(rgb, factor):
    """box-average the opaque samples in each factor x factor block."""
    h = len(rgb)
    w = len(rgb[0]) if h else 0
    nw, nh = max(1, round(w / factor)), max(1, round(h / factor))
    out = []
    for ny in range(nh):
        row = []
        for nx in range(nw):
            r = g = b = n = 0
            total = 0
            for sy in range(int(ny * h / nh), max(int(ny * h / nh) + 1, int((ny + 1) * h / nh))):
                for sx in range(int(nx * w / nw), max(int(nx * w / nw) + 1, int((nx + 1) * w / nw))):
                    if sy < h and sx < w:
                        total += 1
                        v = rgb[sy][sx]
                        if v >= 0:
                            r += (v >> 16) & 255; g += (v >> 8) & 255; b += v & 255
                            n += 1
            # a block that is mostly transparent stays transparent
            row.append(-1 if n == 0 or n * 2 < total else
                       ((r // n) << 16) | ((g // n) << 8) | (b // n))
        out.append(row)
    return out


def lua_sprite(rgb):
    h = len(rgb)
    w = len(rgb[0]) if h else 0
    rows = ",\n".join("{" + ",".join(str(v) for v in row) + "}" for row in rgb)
    return "{ bw=%d, bh=%d, data={\n%s\n}}" % (w, h, rows)

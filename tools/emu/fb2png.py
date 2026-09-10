#!/usr/bin/env python3
"""render an emu .fb cell dump to a png, the way an opencomputers screen looks.

each cell is drawn as an 8x16 block: background fill, then the glyph in the
foreground color. half-block glyphs are drawn as solid rectangles so semi-pixel
artwork comes out exactly as the gpu would show it.
"""
import sys, os
from PIL import Image, ImageDraw, ImageFont

CW, CH = 8, 16
FONT = None
for cand in ("/usr/share/fonts/google-noto/NotoSansMono-Regular.ttf",
             "/usr/share/fonts/dejavu-sans-mono-fonts/DejaVuSansMono.ttf",
             "/usr/share/fonts/adwaita-mono-fonts/AdwaitaMono-Regular.ttf"):
    if os.path.exists(cand):
        FONT = ImageFont.truetype(cand, 13)
        break
if FONT is None:
    FONT = ImageFont.load_default()


def render(path, out):
    with open(path) as f:
        head = f.readline().split()
        w, h = int(head[0]), int(head[1])
        rows = [ln.rstrip("\n").split("\t") for ln in f]
    img = Image.new("RGB", (w * CW, h * CH), (0, 0, 0))
    d = ImageDraw.Draw(img)
    for y in range(min(h, len(rows))):
        for x in range(min(w, len(rows[y]))):
            cell = rows[y][x]
            fg, bg, ch = cell.split(",", 2)
            fg, bg = int(fg, 16), int(bg, 16)
            fgc = ((fg >> 16) & 255, (fg >> 8) & 255, fg & 255)
            bgc = ((bg >> 16) & 255, (bg >> 8) & 255, bg & 255)
            px, py = x * CW, y * CH
            d.rectangle([px, py, px + CW - 1, py + CH - 1], fill=bgc)
            if ch == "▀":      # upper half block
                d.rectangle([px, py, px + CW - 1, py + CH // 2 - 1], fill=fgc)
            elif ch == "▄":    # lower half block
                d.rectangle([px, py + CH // 2, px + CW - 1, py + CH - 1], fill=fgc)
            elif ch == "█":
                d.rectangle([px, py, px + CW - 1, py + CH - 1], fill=fgc)
            elif ch not in (" ", ""):
                d.text((px, py), ch, font=FONT, fill=fgc)
    img.save(out)
    print(out, img.size)


if __name__ == "__main__":
    for p in sys.argv[1:]:
        render(p, p.rsplit(".", 1)[0] + ".png")

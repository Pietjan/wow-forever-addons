#!/usr/bin/env python3
"""Write ForeverQuests' backdrop texture: a white square that is solid in
the middle and fades to nothing towards every side, round at the corners,
as a 64x64 uncompressed 32-bit TGA. The game tints it black and draws it
in nine pieces: the solid middle stretched behind the quest tracker, the
soft band around it.

    make-backdrop-tga.py <out.tga>
"""
import struct
import sys

SIZE = 64
EDGE = 24  # width of the soft band; Backdrop.lua cuts the pieces here


def alpha(px, py):
    # Distance from the pixel centre to the solid middle, 0 inside it.
    x, y = px + 0.5, py + 0.5
    dx = max(EDGE - x, 0, x - (SIZE - EDGE))
    dy = max(EDGE - y, 0, y - (SIZE - EDGE))
    t = min((dx * dx + dy * dy) ** 0.5 / (EDGE - 1), 1)  # 1 a pixel before the border
    return 1 - t * t * (3 - 2 * t)  # smoothstep: no visible start or end of the fade


def main():
    out = sys.argv[1]
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 8 | 0x20)
    body = bytearray()
    for py in range(SIZE):  # top-left origin (descriptor bit 5)
        for px in range(SIZE):
            body += bytes((255, 255, 255, round(255 * alpha(px, py))))
    with open(out, "wb") as f:
        f.write(header + body)


if __name__ == "__main__":
    main()

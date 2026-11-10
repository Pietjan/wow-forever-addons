#!/usr/bin/env python3
"""Write ForeverQuests' dot texture: a white disc with a dark rim, smooth
edges, as a 64x64 uncompressed 32-bit TGA. The game tints it per quest
(the rim stays dark because tinting multiplies).

    make-dot-tga.py <out.tga>
"""
import struct
import sys

SIZE = 64
SAMPLES = 4  # per axis, for smooth edges
RADIUS = SIZE / 2 - 1  # leave a pixel free so mipmaps do not clip
RIM = RADIUS * 0.24  # rim width
RIM_SHADE = 0.12


def pixel(px, py):
    covered = rim = 0
    for sy in range(SAMPLES):
        for sx in range(SAMPLES):
            x = px + (sx + 0.5) / SAMPLES - SIZE / 2
            y = py + (sy + 0.5) / SAMPLES - SIZE / 2
            d = (x * x + y * y) ** 0.5
            if d <= RADIUS:
                covered += 1
                if d > RADIUS - RIM:
                    rim += 1
    n = SAMPLES * SAMPLES
    alpha = covered / n
    if covered == 0:
        return 0, 0, 0, 0
    shade = (covered - rim + rim * RIM_SHADE) / covered
    v = round(255 * shade)
    return v, v, v, round(255 * alpha)


def main():
    out = sys.argv[1]
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 8 | 0x20)
    body = bytearray()
    for py in range(SIZE):  # top-left origin (descriptor bit 5)
        for px in range(SIZE):
            r, g, b, a = pixel(px, py)
            body += bytes((b, g, r, a))
    with open(out, "wb") as f:
        f.write(header + body)


if __name__ == "__main__":
    main()

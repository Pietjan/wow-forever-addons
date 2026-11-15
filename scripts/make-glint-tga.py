#!/usr/bin/env python3
"""Write ForeverSparkles' glint texture: a white four-pointed star with a
soft round core, as a 64x64 uncompressed 32-bit TGA. Only the alpha channel
has a shape; the game tints the white and blends it additively.

    make-glint-tga.py <out.tga>
"""
import math
import struct
import sys

SIZE = 64
SAMPLES = 3  # per axis, for smooth edges
REACH = SIZE / 2 - 2  # ray length; leaves room so mipmaps do not clip
CORE = 5.0  # radius of the round glow in the middle
RAY = 1.3  # half width of a ray at the centre


def ray(along, across):
    """One ray: thin across, fading and narrowing to a point along."""
    t = abs(along) / REACH
    if t >= 1:
        return 0.0
    width = RAY * (1 - t) + 0.25
    return (1 - t) ** 2 * math.exp(-((across / width) ** 2))


def alpha(x, y):
    d = math.hypot(x, y)
    glow = math.exp(-((d / CORE) ** 2))
    halo = 0.25 * math.exp(-((d / (CORE * 2.6)) ** 2))
    return min(1.0, glow + halo + ray(x, y) + ray(y, x))


def pixel(px, py):
    total = 0.0
    for sy in range(SAMPLES):
        for sx in range(SAMPLES):
            x = px + (sx + 0.5) / SAMPLES - SIZE / 2
            y = py + (sy + 0.5) / SAMPLES - SIZE / 2
            total += alpha(x, y)
    return round(255 * total / (SAMPLES * SAMPLES))


def main():
    out = sys.argv[1]
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 8 | 0x20)
    body = bytearray()
    for py in range(SIZE):  # top-left origin (descriptor bit 5)
        for px in range(SIZE):
            body += bytes((255, 255, 255, pixel(px, py)))
    with open(out, "wb") as f:
        f.write(header + body)


if __name__ == "__main__":
    main()

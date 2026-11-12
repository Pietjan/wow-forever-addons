#!/usr/bin/env python3
"""Build SimpleRaidTargetIcons' Icon1.tga .. Icon8.tga.

Which raid icon a unit has is secret to addon code: the number can only be
handed to the game, for instance to pick a cell of a sprite sheet. So every
icon of the menu gets its own 4x4 sheet: cell k is that icon, except cell i
of icon i, which is the "pass" sign of the loot roll window. Cell 9 is the
icon again, for a unit with no mark. Picking the cell with the unit's number
turns exactly the icon it already has into the sign.

usage: icon_sheets.py <dir holding atlas.py> <blp cache dir> <addon dir> <preview.png>
The BLP reader is scratchpad/foreverchat/atlas.py; the art is downloaded
from wago.tools once.
"""
import sys, math, struct, types

atlas = types.ModuleType("atlas")
code = open(sys.argv[1] + "/atlas.py").read().rsplit("main()", 1)[0]  # it runs main() on import
exec(compile(code, "atlas.py", "exec"), atlas.__dict__)
blpdir, outdir, preview = sys.argv[2], sys.argv[3], sys.argv[4]

def load(fdid):
    data = atlas.fetch(fdid, blpdir)
    w, h = struct.unpack_from("<II", data, 12)
    return w, h, atlas.decode_region(data, 0, 0, w, h)

CELL = 64
iw, ih, icons = load(137009)   # interface/targetingframe/ui-raidtargetingicons: 4x4 cells
pw, ph, sign = load(130775)    # interface/buttons/ui-grouploot-pass-up
assert iw // 4 == CELL and ih // 4 == CELL, (iw, ih)

def icon_cell(i):
    ox, oy = ((i - 1) % 4) * CELL, ((i - 1) // 4) * CELL
    return [[icons.get((ox + x, oy + y), (0, 0, 0, 0)) for x in range(CELL)] for y in range(CELL)]

def sample(src, w, h, u, v):  # bilinear, alpha-weighted
    x, y = u * w - 0.5, v * h - 0.5
    x0, y0 = math.floor(x), math.floor(y)
    acc = [0.0] * 4
    for dy in (0, 1):
        for dx in (0, 1):
            wt = (1 - abs(x - (x0 + dx))) * (1 - abs(y - (y0 + dy)))
            r, g, b, a = src.get((x0 + dx, y0 + dy), (0, 0, 0, 0))
            acc[0] += wt * r * a; acc[1] += wt * g * a; acc[2] += wt * b * a; acc[3] += wt * a
    if acc[3] <= 0:
        return (0, 0, 0, 0)
    return (round(acc[0] / acc[3]), round(acc[1] / acc[3]), round(acc[2] / acc[3]), round(acc[3]))

# The sign, scaled so that its solid part (the texture has a wide faint
# shadow around it) is about as large as the icons' art.
solid = [(x, y) for (x, y), p in sign.items() if p[3] > 128]
x0, x1 = min(x for x, _ in solid), max(x for x, _ in solid) + 1
y0, y1 = min(y for _, y in solid), max(y for _, y in solid) + 1
print("sign: solid part", x0, y0, x1, y1, "of", pw, ph)
SIGN = 56  # size of the solid part in the cell
scale = SIGN / max(x1 - x0, y1 - y0)
sign_cell = [[(0, 0, 0, 0)] * CELL for _ in range(CELL)]
for y in range(CELL):
    for x in range(CELL):
        u = ((x0 + x1) / 2 + (x + 0.5 - CELL / 2) / scale) / pw
        v = ((y0 + y1) / 2 + (y + 0.5 - CELL / 2) / scale) / ph
        if 0 <= u <= 1 and 0 <= v <= 1:
            sign_cell[y][x] = sample(sign, pw, ph, u, v)

N = 4 * CELL
strip = []
for i in range(1, 9):
    own = icon_cell(i)
    px = [[(0, 0, 0, 0)] * N for _ in range(N)]
    for k in range(1, 10):
        cell = sign_cell if k == i else own
        ox, oy = ((k - 1) % 4) * CELL, ((k - 1) // 4) * CELL
        for y in range(CELL):
            px[oy + y][ox:ox + CELL] = cell[y]
    body = bytearray()
    for row in px:
        for r, g, b, a in row:
            body += bytes((b, g, r, a))
    hdr = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, N, N, 32, 0x28)
    open(f"{outdir}/Icon{i}.tga", "wb").write(hdr + body)
    if i in (1, 8):
        strip.append(px[:3 * CELL])

bg = (150, 70, 40)
rows = [a + b for a, b in zip(*strip)]
atlas.png(preview, 2 * N, 3 * CELL, [[tuple((c * p[3] + k * (255 - p[3])) // 255 for c, k in zip(p[:3], bg)) for p in row] for row in rows])

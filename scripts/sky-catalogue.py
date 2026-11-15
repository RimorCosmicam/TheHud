#!/usr/bin/env python3
"""Rebuilds Sources/HudCore/Resources/Sky/sky.json from d3-celestial's data.

Stars and star names are kept from the current sky.json (d3-celestial's stars.6.json cut to
magnitude 5.5, and its starnames.json). Constellation figures and labels are rebuilt with their
three-letter ids so the zodiac can be picked out, and the Milky Way is added as dots graded
by how many of its outline levels cover them.

    scripts/sky-catalogue.py <dir with mw.json, constellations.lines.json, constellations.json>

The data is BSD-licensed; see LICENSE-d3-celestial.txt beside sky.json.
"""
import json
import math
import sys

source = sys.argv[1]
out_path = "Sources/HudCore/Resources/Sky/sky.json"
current = json.load(open(out_path))


def ra(value):
    return round(value % 360, 3)


def thin(ring, step):
    """Keeps a point once it is `step` degrees from the last one kept."""
    kept = [ring[0]]
    for point in ring[1:]:
        last = kept[-1]
        d = math.hypot((point[0] - last[0] + 180) % 360 - 180, point[1] - last[1])
        if d >= step:
            kept.append(point)
    return kept if len(kept) >= 3 else []


figures = []
for feature in json.load(open(f"{source}/constellations.lines.json"))["features"]:
    for line in feature["geometry"]["coordinates"]:
        figures.append({"c": feature["id"],
                        "p": [[ra(p[0]), round(p[1], 3)] for p in line]})

labels = []
for feature in json.load(open(f"{source}/constellations.json"))["features"]:
    lon, lat = feature["geometry"]["coordinates"]
    labels.append([ra(lon), round(lat, 3), feature["properties"]["name"].upper(), feature["id"]])

# The Milky Way as dots on a near-even grid, each tagged with how many of the five outline
# levels it is inside: brighter where more of them overlap. Rings are tested in a plane
# projected from the south galactic pole, which no level reaches, so even-odd containment
# is the real thing there (a ring round the whole sky would fool a test done in RA and Dec).
def vec(lon, lat):
    a, d = math.radians(lon), math.radians(lat)
    return (math.cos(d) * math.cos(a), math.cos(d) * math.sin(a), math.sin(d))


pole = vec(12.86, -27.13)
helper = (0.0, 0.0, 1.0)
ux, uy, uz = (pole[1] * helper[2] - pole[2] * helper[1], pole[2] * helper[0] - pole[0] * helper[2],
              pole[0] * helper[1] - pole[1] * helper[0])
norm = math.sqrt(ux * ux + uy * uy + uz * uz)
u = (ux / norm, uy / norm, uz / norm)
w = (pole[1] * u[2] - pole[2] * u[1], pole[2] * u[0] - pole[0] * u[2], pole[0] * u[1] - pole[1] * u[0])


def flat(lon, lat):
    x, y, z = vec(lon, lat)
    k = max(1 - (x * pole[0] + y * pole[1] + z * pole[2]), 1e-9)
    return ((x * u[0] + y * u[1] + z * u[2]) / k, (x * w[0] + y * w[1] + z * w[2]) / k)


levels = {}
for feature in json.load(open(f"{source}/mw.json"))["features"]:
    rings = []
    for polygon in feature["geometry"]["coordinates"]:
        for ring in polygon:
            points = thin(ring, 0.5)
            if points:
                pts = [flat(*p) for p in points]
                xs, ys = [p[0] for p in pts], [p[1] for p in pts]
                rings.append((min(xs), max(xs), min(ys), max(ys), pts))
    levels[int(feature["id"][-1])] = rings


def inside(point, rings):
    x, y = point
    count = 0
    for x0, x1, y0, y1, pts in rings:
        if not (x0 <= x <= x1 and y0 <= y <= y1):
            continue
        n = len(pts)
        for i in range(n):
            ax, ay = pts[i]
            bx, by = pts[(i + 1) % n]
            if (ay > y) != (by > y) and x < ax + (y - ay) * (bx - ax) / (by - ay):
                count += 1
    return count % 2 == 1


step = 1.4
total = int(4 * math.pi / math.radians(step) ** 2)
golden = math.pi * (3 - math.sqrt(5))
dots = {level: [] for level in levels}
for i in range(total):
    z = 1 - 2 * (i + 0.5) / total
    lon = math.degrees((i * golden) % (2 * math.pi))
    lat = math.degrees(math.asin(z))
    point = flat(lon, lat)
    depth = sum(1 for level in levels if inside(point, levels[level]))
    if depth:
        dots[depth].append([ra(lon), round(lat, 2)])
milky_way = [[level, points] for level, points in sorted(dots.items()) if points]

result = {"stars": current["stars"], "names": current["names"],
          "lines": figures, "labels": labels, "milkyWay": milky_way}
with open(out_path, "w") as f:
    json.dump(result, f, separators=(",", ":"))
print(f"{len(figures)} figure lines, {len(labels)} labels, {len(milky_way)} milky way levels,",
      sum(len(r[1]) for r in milky_way), "points")

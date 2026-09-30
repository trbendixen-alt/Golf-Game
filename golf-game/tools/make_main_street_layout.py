#!/usr/bin/env python3
"""Writes data/holes/main_street_opener.json.

This is a one-off helper, not something the game needs: it lays out the street
(buildings, parked cars, lamps, trees, cones) with a fixed random seed, so the
result is always the same, and writes it out as plain, editable hole data.
After it has run, the JSON file is the source of truth: edit THAT by hand if you
want to move things. (Re-running this script overwrites your edits.)

Coordinates are metres on the ground as [x, z]. The hole plays toward -Z.
"""
import json
import random

rng = random.Random(20260929)

STREET_HALF = 5.0      # kerb to kerb is 10 m
PLANTER = (5.0, 6.4)   # grass strip between the kerb and the sidewalk (rough)
WALK = (6.4, 8.5)      # sidewalk
FACADE = 8.5           # where the building fronts stand
STREET_TOP = 26.0      # first building behind the tee
STREET_END = -82.0     # the street opens into the park here
TEE = [0, 0, 0]
CUP = [1.5, 0, -96]

# Saturated pastels, like the reference image (golden-hour light warms them a little).
WALL = ["#f0a3c8", "#b59ae6", "#f7d45e", "#8ec9f2", "#f79c86", "#9fe0b4", "#f3ead2", "#7fb5e6", "#e8a0b0"]
TRIM = ["#ede8d9", "#334d40", "#d9ccb3"]
CAR = ["#e0251b", "#2459e6", "#f4f4ef", "#1a1a22", "#1fae85", "#ffc61a", "#9aa3b0", "#e8702a"]


def hexish(c):
    return c


def buildings():
    out = []
    for side in (-1, 1):
        z = STREET_TOP
        while z > STREET_END + 6.0:
            if rng.random() < 0.14:  # an alley
                z -= rng.uniform(2.5, 4.0)
                continue
            width = min(rng.uniform(7.0, 14.0), z - STREET_END)
            depth = rng.uniform(10.0, 15.0)
            stories = rng.randint(1, 4)
            height = 3.8 + (stories - 1) * 3.2 + 1.0
            out.append({
                "type": "building",
                "at": [round(side * (FACADE + depth / 2), 2), round(z - width / 2, 2)],
                "size": [round(depth, 2), round(width, 2), round(height, 2)],
                "color": rng.choice(WALL), "trim": rng.choice(TRIM), "seed": round(rng.random() * 100, 2),
            })
            z -= width
    return out


def cars():
    out = []
    for side in (-1, 1):
        z = 20.0
        while z > -74.0:
            if rng.random() < 0.55 and abs(z + 31.0) > 5.0:  # leave the crosswalk clear
                out.append({"type": "car", "at": [round(side * 4.1, 2), round(z, 2)],
                            "angle": 0 if side > 0 else 180, "color": rng.choice(CAR)})
            z -= 6.5
    return out


def lamps_and_trees():
    out = []
    for side in (-1, 1):
        z = 22.0
        i = 0
        while z > -80.0:
            kind = "lamp" if i % 2 == 0 else "tree"
            entry = {"type": kind, "at": [round(side * 5.7, 2), round(z, 2)]}
            if kind == "lamp":
                entry["angle"] = 0 if side > 0 else 180  # which way the arm points (toward the street)
            else:
                entry["scale"] = round(rng.uniform(0.8, 1.0), 2)
            out.append(entry)
            z -= 8.0
            i += 1
    return out


cones = [{"type": "cone", "at": [x, -80.0]} for x in (-4.4, -3.4, 3.4, 4.4)]

fairway = [[-2.2, 14], [2.2, 14], [2.9, -20], [3.0, -60], [3.0, -84], [-3.0, -84], [-3.0, -60], [-2.9, -20]]
length = 14 + 82
hole = {
    "name": "Main Street Opener",
    "par": 3,
    "tee": TEE,
    "cup": CUP,
    "wind_mph": [2, 9],
    "look": "golden_hour",
    "camera": {"back": 9.0, "height": 3.2, "look_ahead": 6.0, "look_height": 0.2, "fov": 62, "far": 2500},
    "scenery": {
        "scene": "res://scenes/holes/main_street_opener/scenery.tscn",
        "sun_mask": "res://scenes/holes/main_street_opener/sun_mask.png",
        "theme": "small_town",
        "seed": 20260929,
        "street_half": STREET_HALF,
        "street_end": STREET_END,
        "crosswalks": [-31.0, -78.0],
        "stakes": False,
    },
    "ground": "street",
    "bounds": {"polygon": [[-8.4, 14], [8.4, 14], [8.4, -82], [30, -82], [30, -118], [-30, -118], [-30, -82], [-8.4, -82]]},
    "surfaces": [
        {"type": "sidewalk", "rect": [-7.45, -34], "size": [2.1, length]},
        {"type": "sidewalk", "rect": [7.45, -34], "size": [2.1, length]},
        {"type": "rough", "rect": [-5.7, -34], "size": [1.4, length]},
        {"type": "rough", "rect": [5.7, -34], "size": [1.4, length]},
        {"type": "rough", "rect": [0, -100], "size": [60, 36]},
        {"type": "fairway", "polygon": fairway},
        {"type": "tee", "rect": [0, 0], "size": [4, 6]},
        {"type": "fairway", "circle": [1.5, -96], "radius": 11},
        {"type": "green", "circle": [1.5, -96], "radius": 9},
    ],
    "obstacles": buildings() + cars() + lamps_and_trees() + cones,
}

# One obstacle per line keeps the file readable and the diffs small.
text = json.dumps(hole, indent="\t")
def compact(match):
    return json.dumps(json.loads(match.group(0)))
import re
text = re.sub(r'\{\s*"type":[^{}]*?(?:\[[^\]]*\][^{}]*?)*\}', lambda m: json.dumps(json.loads(m.group(0))), text)
text = re.sub(r'\[\s*(-?[\d.]+),\s*(-?[\d.]+)\s*\]', r'[\1, \2]', text)
text = re.sub(r'\[\s*(-?[\d.]+),\s*(-?[\d.]+),\s*(-?[\d.]+)\s*\]', r'[\1, \2, \3]', text)
with open("data/holes/main_street_opener.json", "w") as f:
    f.write(text + "\n")
print("buildings", len(hole["obstacles"]), "obstacles written")

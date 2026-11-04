#!/usr/bin/env python3
"""geometry.py -- the crop-box reader and gate for scripts/demo_media.sh.

Reads the log of ONE `wow-sim ... screenshot --dump-tree` run whose --exec-lua
chunk ran scripts/scenarios/fxdemo_lib.lua, and answers:

  box <dt.log>    print "<x> <y> <w> <h>" (device px, even-sized) = the union
                  of the scene's published crop boxes, and PROVE it:
                    * every box's owner frame is visible and its own dump-tree
                      rect lies inside the printed crop (a miss means the
                      UI-unit-to-pixel scale is wrong -- the v2 failure)
                    * the crop fits the canvas
                    * no visible Blizzard frame overlaps the crop
  facts <dt.log>  print the scene's proof facts

The scene publishes boxes and facts as inert marker frames (see fxdemo_lib's
header): `FXDB_<owner>` carries the crop rect in its geometry, `FXDM_<fact>`
carries text in its name. The dump prints both in device pixels, which is
exactly what the screenshot subcommand's --crop takes.
"""
import re
import sys

FRAME = re.compile(
    r"^(?P<ind> *)(?P<name>(?!\[)[^ ].*?) \[(?P<type>[A-Za-z_]+)\] "
    r"\((?P<w>\d+)x(?P<h>\d+)\)(?: \[stored=\d+x\d+\])? (?P<vis>visible|hidden) "
    r"(?:[^x\n]* )?x=(?P<x>-?\d+), y=(?P<y>-?\d+)")

BOX_PREFIX = "FXDB_"
FACT_PREFIX = "FXDM_"
OURS = ("Forte", "FXDB_", "FXDM_", "FXDPROBE")
NEUTRAL = ("UIParent", "WorldFrame")
MIN_FOREIGN_AREA = 300


def frames(text):
    out = []
    for line in text.split("\n"):
        m = FRAME.match(line)
        if not m:
            continue
        d = dict(name=m.group("name").strip(), typ=m.group("type"),
                 w=int(m.group("w")), h=int(m.group("h")),
                 x=int(m.group("x")), y=int(m.group("y")),
                 vis=m.group("vis"), top=not m.group("ind"))
        # A marker is anchored TOPLEFT, and the dump prints such a rect's
        # distance below the canvas top as a NEGATIVE y.
        if d["name"].startswith((BOX_PREFIX, FACT_PREFIX)) and d["y"] < 0:
            d["y"] = -d["y"]
        out.append(d)
    return out


def overlap(a, b):
    ox = min(a["x"] + a["w"], b["x"] + b["w"]) - max(a["x"], b["x"])
    oy = min(a["y"] + a["h"], b["y"] + b["h"]) - max(a["y"], b["y"])
    return ox > 0 and oy > 0


def inside(outer, inner, slack=1):
    return (inner["x"] >= outer["x"] - slack
            and inner["y"] >= outer["y"] - slack
            and inner["x"] + inner["w"] <= outer["x"] + outer["w"] + slack
            and inner["y"] + inner["h"] <= outer["y"] + outer["h"] + slack)


def facts(all_frames):
    return sorted(f["name"][len(FACT_PREFIX):] for f in all_frames
                   if f["name"].startswith(FACT_PREFIX))


def main(argv):
    mode = argv[1]
    text = open(argv[2], encoding="utf8", errors="replace").read()
    all_frames = frames(text)
    if not all_frames:
        sys.stderr.write("  no frames parsed from the dump-tree log\n")
        return 1
    if mode == "facts":
        for f in facts(all_frames):
            print("  fact " + f.replace("_", " ", 1))
        return 0
    boxes = [f for f in all_frames if f["name"].startswith(BOX_PREFIX)]
    if not boxes:
        sys.stderr.write("  the scene published no FXDB_ boxes\n")
        return 1
    x0 = min(b["x"] for b in boxes)
    y0 = min(b["y"] for b in boxes)
    x1 = max(b["x"] + b["w"] for b in boxes)
    y1 = max(b["y"] + b["h"] for b in boxes)
    w, h = x1 - x0, y1 - y0
    w -= w % 2
    h -= h % 2
    box = dict(name="CROP", x=x0, y=y0, w=w, h=h)
    owners = {b["name"][len(BOX_PREFIX):] for b in boxes}

    print("%d %d %d %d" % (x0, y0, w, h))
    sys.stderr.write("  crop %d,%d %dx%d from %d box(es): %s\n"
                     % (x0, y0, w, h, len(boxes), ", ".join(sorted(owners))))
    for f in facts(all_frames):
        sys.stderr.write("  fact " + f.replace("_", " ", 1) + "\n")

    fails = []
    by_name = {}
    for f in all_frames:
        by_name.setdefault(f["name"], f)
    for o in sorted(owners):
        r = by_name.get(o)
        if r is None:
            fails.append("owner %s is not in the frame tree" % o)
        elif r["vis"] != "visible":
            fails.append("owner %s is %s" % (o, r["vis"]))
        elif not inside(box, r):
            fails.append("owner %s dump rect (%d,%d,%dx%d) is outside the crop "
                         "(%d,%d,%dx%d) -- the UI-unit scale is wrong"
                         % (o, r["x"], r["y"], r["w"], r["h"], x0, y0, w, h))
    canvas = [f for f in facts(all_frames) if f.startswith("FXDM_canvas")]
    for c in canvas:
        m = re.search(r"canvas_(\d+)x(\d+)", c)
        if m:
            cw, ch = int(m.group(1)), int(m.group(2))
            if x0 < 0 or y0 < 0 or x0 + w > cw or y0 + h > ch:
                fails.append("crop does not fit the %dx%d canvas" % (cw, ch))
    for f in all_frames:
        if not f["top"] or f["vis"] != "visible" or not f["name"]:
            continue
        if f["name"].startswith(OURS) or f["name"] in NEUTRAL:
            continue
        if f["w"] * f["h"] < MIN_FOREIGN_AREA:
            continue
        if overlap(f, box):
            fails.append("visible Blizzard frame overlaps the crop: %s "
                         "%dx%d@%d,%d" % (f["name"], f["w"], f["h"],
                                           f["x"], f["y"]))
    for m in fails:
        sys.stderr.write("  GEOMETRY FAIL " + m + "\n")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

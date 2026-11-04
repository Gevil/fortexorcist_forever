#!/usr/bin/env python3
"""Measure ForteXorcist's swing-bar palette signals on the Aluminium art.

The swing bar's fill texture is `addon/Forte_Core/Textures/Aluminium.tga`,
drawn ARTWORK-style: the vertex colour multiplies the texel, and the region /
stripe / line signals ride a sub-1 alpha over that. Every signal the bar
presents is therefore a colour on a *textured* ground, and the pairings that
a player has to tell apart are fixed by the layout (the fill against the
right-end markers, the line over the fill, the flight over everything).

This tool composites each signal the way the client draws it and prints the
WCAG relative-luminance contrast matrix (all pairs) plus the smallest pair,
for each palette. Both palettes are READ OUT OF THE SHIPPED LUA (`FX.Hunter
.SwingSkin` is the base every `FX.Hunter.SwingPalettes` entry paints over --
`swing_contrast.read_palettes`), so the numbers in this report are the
shipped pixels, and the compositing is shared with `swing_contrast.py`
(`swing_contrast.signals`) so the two reports can not disagree.

    python3 tools/swing_palette_matrix.py          # matrices
    python3 tools/swing_palette_matrix.py --json    # machine-readable

White over Aluminium is the bare art at full alpha, so the
`flight white | bare Aluminium` pair is 1.00 by arithmetic and no palette can
move it; the bar is the pair the palette is *about*, and the per-palette
minimum excluding that pair is printed as `min (excl. white|art)`.

    python3 tools/swing_palette_matrix.py          # both matrices
    python3 tools/swing_palette_matrix.py --json    # machine-readable
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import swing_contrast as sc  # noqa: E402

# The two palettes, READ OUT OF `UI/Swing.lua`: `FX.Hunter.SwingSkin` is the
# base and each `FX.Hunter.SwingPalettes` entry paints over it (`default`
# names nothing, so it IS the shipped art). Nothing here is transcribed --
# the printed numbers are the shipped pixels.
#
# The ladder search (`sc.signals` over the Okabe-Ito family x the alphas)
# tops out at a 1.44 minimum adjacency pair on this art -- the shipped art's
# ceiling, and the shipped `colourblind` entry sits 0.13 under it in exchange
# for keeping the design's hue story (the vermillion warning, the blue
# interlock band, the olive bar) and the biggest pair of the set, the fill
# against the live aim slice at 3.64:1.
def PALETTES():
    return sc.read_palettes()


def signals(pal, art):
    """Each signal as the colour it presents on the Aluminium art (the
    compositing is `swing_contrast.signals`, shared by both tools so the two
    reports can not disagree)."""
    sig = sc.signals(pal, art)
    return {
        "fill": sig["fill (reload)"],
        "aim slice": sig["aim slice (live)"],
        "aim region": sig["aim zone (standing)"],
        "clip stripe": sig["clip mark"],
        "interlock": sig["clip mark (interlock)"],
        "weave line": sig["weave line"],
        "retry slice": sig["retry slice"],
        "flight white": sig["safe-to-move (white)"],
        "bare Aluminium": sig["aluminium (bare art)"],
    }



def matrix(pal):
    art = sc.aluminium_mean()
    sig = signals(pal, art)
    keys = list(sig)
    out = {}
    for i, a in enumerate(keys):
        for b in keys[i + 1:]:
            out[(a, b)] = sc.contrast(sig[a], sig[b])
    return sig, out


def main():
    as_json = "--json" in sys.argv
    report = {}
    for name, pal in PALETTES().items():
        sig, pairs = matrix(pal)
        ranked = sorted(pairs.items(), key=lambda kv: kv[1])
        lowest = ranked[0]
        work = min((kv for kv in ranked
                    if {"flight white", "bare Aluminium"} != set(kv[0])),
                   key=lambda kv: kv[1])
        report[name] = {
            "luminances": {k: round(sc.luminance(v), 4)
                           for k, v in sig.items()},
            "pairs": [["%s | %s" % k, round(v, 3)] for k, v in ranked],
            "minimum": {"pair": "%s | %s" % lowest[0],
                        "contrast": round(lowest[1], 2)},
            "minimum_excluding_white_on_art": {
                "pair": "%s | %s" % work[0], "contrast": round(work[1], 2)},
        }
        if not as_json:
            print("== palette `%s` ==" % name)
            print("   luminances: " + ", ".join(
                "%s %.3f" % (k, sc.luminance(v)) for k, v in sig.items()))
            for (a, b), c in ranked:
                flag = "   <-- under 1.5" if c < 1.5 else ""
                print("   %-38s %5.2f:1%s" % ("%s | %s" % (a, b), c, flag))
            print("   minimum %s = %.2f:1" % ("%s | %s" % lowest[0], lowest[1]))
            print("   min excluding white|art (1.00 by arithmetic) "
                  "%s = %.2f:1\n" % ("%s | %s" % work[0], work[1]))
    if as_json:
        print(json.dumps(report, indent=1))


if __name__ == "__main__":
    main()

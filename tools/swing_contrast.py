#!/usr/bin/env python3
"""WCAG relative-luminance contrast matrix for the swing bar's signals.

Part B of Iteration K (PLAN §11.4 row K4): the `colourblind` palette must
separate the swing bar's signals in BRIGHTNESS and position, not only in
hue. This tool measures that: it reads the palette table out of
`addon/Forte_Hunter/UI/Swing.lua`, composites every signal over the
Aluminium art the fill rides (the mean of `Forte_Core/Textures/
Aluminium.tga`, the texture the ARTWORK blend multiplies), and prints the
pairwise WCAG contrast ratios ((L1 + 0.05) / (L2 + 0.05), the relative
luminance of the linearised sRGB channels) plus the minimum.

Usage:  python3 tools/swing_contrast.py            # both palettes
        python3 tools/swing_contrast.py --json     # machine-readable
"""
import math
import os
import re
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SWING = os.path.join(ROOT, "addon", "Forte_Hunter", "UI", "Swing.lua")
ALUMINIUM = os.path.join(ROOT, "addon", "Forte_Core", "Textures", "Aluminium.tga")


# ------------------------------------------------------------- Aluminium --
def aluminium_mean(path=ALUMINIUM):
    """The (r, g, b) mean of the Aluminium.tga art in 0..1 (TGA type 10)."""
    d = open(path, "rb").read()
    w = struct.unpack("<H", d[12:14])[0]
    h = struct.unpack("<H", d[14:16])[0]
    bpp = d[16]
    n = bpp // 8
    total, px, i = w * h, [], 18
    while len(px) < total:
        hdr = d[i]
        i += 1
        cnt = (hdr & 0x7F) + 1
        if hdr & 0x80:
            chunk = d[i:i + n]
            i += n
            for _ in range(cnt):
                px.append(chunk)
        else:
            for _ in range(cnt):
                px.append(d[i:i + n])
                i += n
    ch = [0.0, 0.0, 0.0]
    for c in px:
        for k in range(3):
            ch[k] += c[k] / 255.0
    return tuple(v / len(px) for v in ch)


# --------------------------------------------------------- palette reader --
TRIPLE = re.compile(r"\{\s*([-\d.]+)\s*,\s*([-\d.]+)\s*,\s*([-\d.]+)"
                    r"(?:\s*,\s*([-\d.]+))?\s*\}")
NUM = re.compile(r"=\s*([-\d.]+)\s*,")
BLOCK = re.compile(r"^FX\.Hunter\.SwingPalettes\s*=\s*\{(.*?)^\}",
                   re.M | re.S)
PAL = re.compile(r"^\s{4}(\w+)\s*=\s*\{(.*?)^\s{4}\},", re.M | re.S)
SKIN = re.compile(r"^FX\.Hunter\.SwingSkin\s*=\s*\{(.*?)^\}", re.M | re.S)

# The keys `Swing.lua`'s PALETTE_KEYS names. The shipped skin is the BASE a
# palette paints over (`default` names NOTHING and is the shipped art), so
# the measurement reads both blocks out of the one Lua file: the numbers
# below are the numbers the client draws, nothing transcribed.
PALETTE_KEYS = ("BarColor", "AimColor", "AimRegionColor", "AimRegionAlpha",
                "AimRegionRetryAlpha", "ClipColor", "ClipRegionAlpha",
                "ClipInterlockColor", "ClipInterlockAlpha", "WeaveColor",
                "RetryColor", "FlyingColor")
# The skin's BarColor is `spellBarColor()` (the Forte_Cooldown timeline's
# Spell category colour), i.e. a function call the regex can not evaluate;
# that function's verbatim fallback triple is the shipped value.
SHIPPED_BAR = (1.0, 0.5, 0.0, 1.0)


def _value(blob):
    if blob.startswith("{"):
        t = TRIPLE.search(blob)
        a = float(t.group(4) if t.group(4) else "1")
        return (eval_frac(t.group(1)), eval_frac(t.group(2)),
                 eval_frac(t.group(3)), a)
    return float(blob)


def read_palettes(path=SWING):
    """The palettes as the bar SEES them: the shipped skin, with each
    palette's named keys painted over it (a key it does not name keeps the
    shipped value -- `Swing.lua`'s BASE / palette overlay law)."""
    src = open(path, encoding="utf-8", errors="replace").read()
    body = BLOCK.search(src)
    if not body:
        raise SystemExit("no FX.Hunter.SwingPalettes block in " + path)
    base = read_skin_defaults(src)
    out = {}
    for name, block in PAL.findall(body.group(1)):
        pal = dict(base)
        for key, blob in re.findall(r"(\w+)\s*=\s*(\{[^}]*\}|[-\d.]+|nil)",
                                     block):
            if blob == "nil":
                pal[key] = None
            else:
                pal[key] = _value(blob)
        out[name] = pal
    return out


def read_skin_defaults(src=None, path=SWING):
    """The shipped `FX.Hunter.SwingSkin` values of the palette-able keys.
    The three keys the skin DERIVES (it sets them from the aim hue / the
    clip alpha, one truth) are derived here the same way."""
    if src is None:
        src = open(path, encoding="utf-8", errors="replace").read()
    body = SKIN.search(src)
    if not body:
        raise SystemExit("no FX.Hunter.SwingSkin block in " + path)
    out = {}
    for key, blob in re.findall(r"(\w+)\s*=\s*(\{[^}]*\}|[-\d.]+|nil)",
                                body.group(1)):
        if key not in PALETTE_KEYS or blob == "nil":
            continue
        out[key] = _value(blob)
    out.setdefault("BarColor", SHIPPED_BAR)
    for derived, source in (("AimRegionColor", "AimColor"),
                            ("ClipColor", "AimColor"),
                            ("ClipInterlockAlpha", "ClipRegionAlpha")):
        out.setdefault(derived, out[source])
    return out


def eval_frac(text):
    """Accepts '0.9' and the hex form '0xE6/255' used by the palette."""
    text = text.strip()
    if "/" in text:
        num, den = text.split("/")
        return float(eval(num.strip().replace("0x", "0x"))) / float(den)
    return float(text)


# ------------------------------------------------------------------ WCAG --
def lin(c):
    c = max(0.0, min(1.0, c))
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def luminance(rgb):
    r, g, b = (lin(c) for c in rgb[:3])
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    if la < lb:
        la, lb = lb, la
    return (la + 0.05) / (lb + 0.05)


def over(colour, art):
    """An ARTWORK blend: the vertex colour rides the Aluminium texture."""
    return tuple(c * a for c, a in zip(colour[:3], art[:3]))


def over_a(colour, art):
    """The ARTWORK multiply that KEEPS the alpha: the vertex colour rides
    the texel and the alpha survives down to the blend over what is under
    the marker (`swing_palette_matrix.py`'s helper; the signals that ride a
    sub-1 alpha -- the aim region, the clip mark, the weave line -- must be
    composited with this one, `over` above drops the alpha and the blend
    then has nothing to blend by)."""
    return (colour[0] * art[0], colour[1] * art[1], colour[2] * art[2],
             colour[3])


def alpha_blend(top, bottom):
    a = top[3]
    return tuple(a * t + (1 - a) * b for t, b in zip(top[:3], bottom[:3]))


# ------------------------------------------------------------------ pairs --
def signals(pal, art, default_bar=None):
    """Every signal the bar draws, as the colour it RENDERS on the art."""
    bar = pal.get("BarColor") or default_bar or SHIPPED_BAR
    aim = pal["AimColor"]
    region = pal.get("AimRegionColor") or aim
    region = (region[0], region[1], region[2], pal["AimRegionAlpha"])
    interlock = (pal["ClipInterlockColor"][0], pal["ClipInterlockColor"][1],
                 pal["ClipInterlockColor"][2],
                 pal.get("ClipInterlockAlpha") or pal["ClipRegionAlpha"])
    clip = (pal["ClipColor"][0], pal["ClipColor"][1], pal["ClipColor"][2],
            pal["ClipRegionAlpha"])
    flying = pal["FlyingColor"]
    retry = pal["RetryColor"]
    weave = pal["WeaveColor"]
    surface = over(bar, art)                       # the Aluminium fill
    base = over((1, 1, 1, 1), art)                 # bare Aluminium art
    return {
        "aluminium (bare art)": base,
        "fill (reload)": over(bar, art),
        "aim slice (live)": over(aim, art),
        "aim zone (standing)": alpha_blend(over_a(region, art), surface),
        "clip mark": alpha_blend(over_a(clip, art), surface),
        # Under the interlock the marker rides the tinted band INSIDE the
        # frozen full-width aim slice (`castW = W`), so its ground is the
        # aim slice, not the fill -- the colour it is read against.
        "clip mark (interlock)": alpha_blend(over_a(interlock, art),
                                             over(aim, art)),
        "weave line": alpha_blend(over_a(weave, art), surface),
        "retry slice": over(retry, art),
        "safe-to-move (white)": over(flying, art),
    }


# Pairs that are ADJACENT on the bar: neighbours in space (the right-end
# stack, the fill edge under the markers, the white state over the art).
ADJACENT = [
    ("fill (reload)", "aim zone (standing)"),
    ("fill (reload)", "aim slice (live)"),
    ("aim zone (standing)", "aim slice (live)"),
    ("fill (reload)", "clip mark"),
    ("clip mark", "aim zone (standing)"),
    ("clip mark", "aim slice (live)"),
    ("fill (reload)", "weave line"),
    ("aluminium (bare art)", "weave line"),
    ("aim slice (live)", "aluminium (bare art)"),
    ("fill (reload)", "aluminium (bare art)"),
    ("safe-to-move (white)", "aluminium (bare art)"),
    ("safe-to-move (white)", "aim zone (standing)"),
    ("retry slice", "aluminium (bare art)"),
    ("retry slice", "aim slice (live)"),
    ("clip mark (interlock)", "aim slice (live)"),
]


def main(as_json=False):
    art = aluminium_mean()
    pals = read_palettes()
    default = pals["default"]
    report = {}
    for name, pal in sorted(pals.items()):
        sig = signals(pal, art, (1.0, 0.5, 0.0, 1.0))
        pairs = []
        for a, b in ADJACENT:
            pairs.append((a, b, contrast(sig[a], sig[b])))
        pairs.sort(key=lambda p: p[2])
        report[name] = {
            "aluminium_mean": [round(v, 4) for v in art],
            "signals": {k: [round(v, 4) for v in v_] for k, v_ in
                        ((k, sig[k]) for k in sorted(sig))},
            "luminances": {k: round(luminance(sig[k]), 4) for k in sorted(sig)},
            "pairs": [[a, b, round(c, 3)] for a, b, c in pairs],
            "minimum": round(pairs[0][2], 3),
        }
        if not as_json:
            print(f"\n== palette `{name}` ==  (Aluminium mean "
                  f"{[round(v, 3) for v in art]})")
            print(f"{'pair':<46} {'contrast':>9}")
            for a, b, c in pairs:
                flag = "  <-- under 1.5" if c < 1.5 else ""
                print(f"{a + ' | ' + b:<46} {c:>8.2f}:1{flag}")
            print(f"minimum pair contrast: {pairs[0][2]:.2f}:1")
    if as_json:
        import json
        print(json.dumps(report, indent=1, sort_keys=True))
    return report


if __name__ == "__main__":
    main(as_json="--json" in sys.argv)

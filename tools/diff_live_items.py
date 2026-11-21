#!/usr/bin/env python3
"""Diff the live item data (wowsims/forever `db.json`) against what our generated item files emit.

READ-ONLY, stdlib only, deterministic (no clock, no network, no randomness; every list is sorted
by item id). It writes nothing; the live-layer edits it motivates are made by hand in
tools/item_lists/live_items.json and then `python3 tools/gen_item_data.py` regenerates the files.

Inputs
    --db        wowsims db.json   (default /tmp/wowsims-forever/assets/database/db.json)
                camelCase keys: items[].itemEffects[].onUse.{cooldownMs,categoryId,categoryCooldownMs},
                .proc.{icdMs,ppm,procChance}, effectDurationMs, buffId, buffName; a `consumables` list
    --first-seen  item_first_seen.json next to the db (optional; used to date the candidates)
    --live-jsonl  mythicsim data/forever-live-items.jsonl (optional second cross-check; snake_case
                `item_effects`; only used to annotate "gone" rows and to count agreement)
    --items-lua / --procs-lua   our generated files (default addon/Forte_Items/Data/Items.lua and
                addon/Forte_ItemProcs/Data/Procs.lua). They are PARSED, not imported: rows are one
                `{ name = "...", itemId = N, ... }` record per line, in the sections `onUse`,
                `consumables`, `enchantProcs` (Items.lua) and `procs` (Procs.lua).

The relevance policy is the generator's (tools/gen_item_data.py), restated here:
  * an item effect with `onUse` that states a `cooldownMs`  -> an on-use row (trackable "cooldown");
  * an item effect with `proc` (and no `onUse`)             -> a proc row (trackable "buff-window");
  * an effect with neither (passive / equip aura)           -> out of scope, counted, never listed;
  * the on-use `categoryId` / `categoryCooldownMs` of an ITEM are not emitted (shared-category
    lockouts stay out), so categories are compared for consumables only, which do carry them;
  * `icdMs` is emitted whenever the source states a non-zero ICD. Sub-second values (< 1000 ms) are
    debounces, not cooldowns: they stay in the data (Forte_Cooldown/Core/Procs.lua draws no bar for
    them, `Procs.MIN_ICD`), so they are flagged `debounce` here and never counted as an action item.
  * a consumable is a db `consumables` row with any cooldown (item cooldown or category cooldown).
    A consumable is "emitted" if it is in our consumables OR on-use list (the live layer puts the
    item-cooldown-only ones, e.g. Flame Deflector, on the on-use path).

Categories printed (letters match the task):
  a  live on-use items missing from our data
  b  on-use / consumable mismatches in cooldown, duration, buff id or (consumables) category
  c  live proc items (effects) missing
  d  proc ICD mismatches (sub-second ones flagged `debounce`)
  e  live consumables with a cooldown missing from our consumables / on-use rows
  f  rows we emit whose item is no longer in the live db, or that lost their effect / changed kind
  g  name collisions the ByName index would hit if the missing rows (a, c) were added

Usage:
    python3 tools/diff_live_items.py                 # compact tables + counts
    python3 tools/diff_live_items.py --json          # the same report as one JSON document
    python3 tools/diff_live_items.py --category a,c  # only some categories
Exit code: 0 always when the inputs parse (it is a report, not a gate); 2 on unreadable input.
"""
import argparse
import json
import pathlib
import re
import sys
from datetime import datetime, timezone

HERE = pathlib.Path(__file__).resolve().parent
REPO_ROOT = HERE.parent
DEFAULT_DB = pathlib.Path("/tmp/wowsims-forever/assets/database/db.json")
ITEMS_LUA = REPO_ROOT / "addon" / "Forte_Items" / "Data" / "Items.lua"
PROCS_LUA = REPO_ROOT / "addon" / "Forte_ItemProcs" / "Data" / "Procs.lua"
DEFAULT_LIVE_JSONL = REPO_ROOT.parent / "mythicsim-forever-engine" / "data" / "forever-live-items.jsonl"

LAYER_JSON = HERE / "item_lists" / "live_items.json"
SUBSECOND_MS = 1000  # gen_item_data / Procs.MIN_ICD law: below this an ICD is a debounce
# Forte_Cooldown/Core/Items.lua Items.MIN_CATEGORY_CD: the consumable tracker reads only rows
# whose categoryCooldownMs is >= 60 s (1-3 s elixir/flask lockouts and 1-1.5 s item cooldowns
# are the GCD band); an item-cooldown-only row of that length rides the on-use path.
MIN_TRACKED_MS = 60000

# proto/common.proto enums, in the field order of gen_item_data.SLOT_FIELDS. A zero (Unknown)
# value is absent from db.json, so it is absent from the composed slotType too.
SLOT_FIELDS = (("type", "ItemType"), ("handType", "HandType"), ("weaponType", "WeaponType"),
               ("rangedWeaponType", "RangedWeaponType"), ("armorType", "ArmorType"))
ENUMS = {
    "ItemType": ["Unknown", "Head", "Neck", "Shoulder", "Back", "Chest", "Wrist", "Hands", "Waist",
                 "Legs", "Feet", "Finger", "Trinket", "Weapon", "Ranged"],
    "HandType": ["Unknown", "MainHand", "OneHand", "OffHand", "TwoHand"],
    "WeaponType": ["Unknown", "Axe", "Dagger", "Fist", "Mace", "OffHand", "Polearm", "Shield",
                   "Staff", "Sword"],
    "RangedWeaponType": ["Unknown", "Bow", "Crossbow", "Gun", "Thrown", "Wand", "Idol", "Libram",
                         "Totem", "Sigil"],
    "ArmorType": ["Unknown", "Cloth", "Leather", "Mail", "Plate"],
}


CATEGORIES = "abcdefg"


# --------------------------------------------------------------------------- parsing
_FIELD_RE = re.compile(r'(\w+) = ("(?:[^"\\]|\\.)*"|-?\d+|\{[^}]*\})')
_SECTION_RE = re.compile(r"^  (\w+) = \{$")


def _lua_value(tok: str):
    if tok.startswith('"'):
        return tok[1:-1].replace('\\"', '"').replace("\\\\", "\\")
    if tok.startswith("{"):
        return [t[1:-1] for t in re.findall(r'"(?:[^"\\]|\\.)*"', tok)]
    return int(tok)


def parse_rows(path: pathlib.Path, wanted: tuple) -> dict:
    """{section: [row dict, ...]} for the sections named in `wanted` (file order kept)."""
    out = {w: [] for w in wanted}
    cur = None
    for line in path.read_text(encoding="utf-8").splitlines():
        m = _SECTION_RE.match(line)
        if m:
            cur = m.group(1) if m.group(1) in out else None
            continue
        if cur is None:
            continue
        s = line.strip()
        if s == "},":
            cur = None
            continue
        if s.startswith("{ ") and s.endswith(" },"):
            out[cur].append({k: _lua_value(v) for k, v in _FIELD_RE.findall(s)})
    return out


def load_ours(items_lua: pathlib.Path, procs_lua: pathlib.Path) -> dict:
    a = parse_rows(items_lua, ("onUse", "consumables", "enchantProcs"))
    b = parse_rows(procs_lua, ("procs",))
    return {"onUse": a["onUse"], "consumables": a["consumables"],
            "enchantProcs": a["enchantProcs"], "procs": b["procs"]}


def slot_type(item: dict) -> str | None:
    parts = []
    for key, enum in SLOT_FIELDS:
        v = item.get(key)
        if isinstance(v, int) and 0 < v < len(ENUMS[enum]):
            parts.append(enum + ENUMS[enum][v])
    return " / ".join(parts) if parts else None


def iso_date(ts) -> str | None:
    if not isinstance(ts, int):
        return None
    return datetime.fromtimestamp(ts, timezone.utc).strftime("%Y-%m-%d")


def _ms(v):
    """A stated cooldown / duration / ICD in ms, or None. db.json and the mythicsim rows use -1
    for 'no cooldown'; 0 and negatives are not durations."""
    return v if isinstance(v, int) and not isinstance(v, bool) and v > 0 else None


def live_effects(db: dict) -> dict:
    """Walk db items + consumables and classify every effect by the generator's relevance policy:
    onUse (an `onUse` with a positive `cooldownMs`), procs (a `proc`, no `onUse`), consumables
    (any positive item or category cooldown). Everything else is passive / category-only and is
    only counted. Returns the effect rows plus the id -> raw item maps."""
    onuse, procs, cons = [], [], []
    passive = 0
    present_items = {}
    for it in db.get("items", []):
        present_items[it["id"]] = it
        for e in it.get("itemEffects", []) or []:
            row = {"itemId": it["id"], "name": it["name"], "buffId": e.get("buffId"),
                   "buffName": e.get("buffName"), "durationMs": _ms(e.get("effectDurationMs"))}
            on_use, proc = e.get("onUse"), e.get("proc")
            if on_use is not None and _ms(on_use.get("cooldownMs")):
                row.update(kind="onUse", cooldownMs=_ms(on_use["cooldownMs"]),
                           categoryId=on_use.get("categoryId"),
                           categoryCooldownMs=_ms(on_use.get("categoryCooldownMs")))
                onuse.append(row)
            elif on_use is not None:
                passive += 1  # a shared-category lockout only: the generator emits no cooldown
            elif proc is not None:
                row.update(kind="proc", icdMs=_ms(proc.get("icdMs")), ppm=proc.get("ppm"),
                           procChance=proc.get("procChance"))
                procs.append(row)
            else:
                passive += 1
    present_cons = {}
    for c in db.get("consumables", []):
        present_cons[c["id"]] = c
        for e in c.get("itemEffects", []) or []:
            u = e.get("onUse") or {}
            cd, cat = _ms(u.get("cooldownMs")), _ms(u.get("categoryCooldownMs"))
            if cd is None and cat is None:
                continue
            cons.append({"itemId": c["id"], "name": c["name"], "kind": "consumable",
                         "buffId": e.get("buffId"), "buffName": e.get("buffName"),
                         "durationMs": _ms(e.get("effectDurationMs")), "cooldownMs": cd,
                         "categoryId": u.get("categoryId", c.get("categoryId")),
                         "categoryCooldownMs": cat,
                         "tracked": max(cd or 0, cat or 0) >= MIN_TRACKED_MS})
    key = lambda r: (r["itemId"], r["buffId"] or 0)
    return {"onUse": sorted(onuse, key=key), "procs": sorted(procs, key=key),
            "consumables": sorted(cons, key=key), "passive": passive,
            "items": present_items, "consumableRows": present_cons}


# --------------------------------------------------------------------------- the diff
def _by_id(rows: list, source: str | None = "item") -> dict:
    out: dict = {}
    for r in rows:
        if source is None or r.get("source") == source:
            out.setdefault(r["itemId"], []).append(r)
    return out


def _pair(live_rows: list, our_rows: list) -> list:
    """Pair the effect rows of ONE item: by buffId first, then in order. Returns
    [(live_or_None, ours_or_None)]."""
    ours = list(our_rows)
    pairs = []
    rest = []
    for lr in live_rows:
        hit = next((o for o in ours if o.get("buffId") == lr["buffId"]), None)
        if hit is None:
            rest.append(lr)
        else:
            ours.remove(hit)
            pairs.append((lr, hit))
    for lr in rest:
        pairs.append((lr, ours.pop(0) if ours else None))
    for o in ours:
        pairs.append((None, o))
    return pairs


def annotate(row: dict, live: dict, first_seen: dict, jsonl: dict | None) -> dict:
    """Candidate-row context for the by-hand review: slot, phase, expansion, source kinds,
    first-seen date, class allowlist, and whether mythicsim's live jsonl carries the item."""
    it = live["items"].get(row["itemId"]) or live["consumableRows"].get(row["itemId"]) or {}
    out = dict(row)
    out["slotType"] = slot_type(it) if it else None
    out["phase"] = it.get("phase")
    out["expansion"] = it.get("expansion")
    out["quality"] = it.get("quality")
    out["reqLvl"] = it.get("reqLvl")
    out["sources"] = sorted({k for s in it.get("sources", []) or [] for k in s})
    if it.get("classAllowlist"):
        out["classAllowlist"] = it["classAllowlist"]
    out["firstSeen"] = iso_date(first_seen.get(row["itemId"]))
    if jsonl is not None:
        out["liveJsonl"] = ("effects" if jsonl[row["itemId"]] else "row") if row["itemId"] in jsonl else None
    return out


def compute(db: dict, ours: dict, first_seen: dict | None = None,
            live_jsonl_ids: dict | None = None, layer: dict | None = None) -> dict:
    """The whole report as plain data. `ours` = {onUse, consumables, enchantProcs, procs} row lists
    as parse_rows returns them; `first_seen` = {itemId: epoch}; `live_jsonl_ids` =
    {itemId: has_effects} from mythicsim's forever-live-items.jsonl; `layer` = the parsed
    tools/item_lists/live_items.json (its onUseOverride ids mark known, intended divergences)."""
    first_seen = first_seen or {}
    overrides = (layer or {}).get("onUseOverride") or {}
    live = live_effects(db)
    our_on = _by_id(ours["onUse"])
    our_cons = _by_id(ours["consumables"], "consumable")
    our_proc = _by_id(ours["procs"])
    rep = {k: [] for k in CATEGORIES}
    ann = lambda r: annotate(r, live, first_seen, live_jsonl_ids)

    def mismatch(iid, lr, lst, field, ov, lv):
        row = {"itemId": iid, "name": lr["name"], "list": lst, "field": field,
               "ours": ov, "live": lv, "buffName": lr.get("buffName")}
        ovr = overrides.get(str(iid))
        if lst == "onUse" and ovr and field in ovr and ovr[field] == ov:
            row["known"] = "onUseOverride"  # the layer deliberately keeps this value
        rep["b"].append(row)

    # a / b: on-use items
    live_on_by = {}
    for r in live["onUse"]:
        live_on_by.setdefault(r["itemId"], []).append(r)
    for iid in sorted(live_on_by):
        for lr, o in _pair(live_on_by[iid], our_on.get(iid, [])):
            if lr is None:
                continue
            if o is None:
                rep["a"].append(ann(lr))
                continue
            for f in ("cooldownMs", "durationMs", "buffId", "buffName"):
                lv, ov = lr.get(f), o.get(f)
                if f not in ("buffId", "buffName"):
                    ov = _ms(ov)
                if lv != ov:
                    mismatch(iid, lr, "onUse", f, ov, lv)

    # e / b: consumables. A db consumable states no effect duration, so duration is not compared.
    live_cons_by = {}
    for r in live["consumables"]:
        live_cons_by.setdefault(r["itemId"], []).append(r)
    for iid in sorted(live_cons_by):
        have = our_cons.get(iid) or our_on.get(iid)
        for lr in live_cons_by[iid]:
            if not have:
                if lr["tracked"]:
                    rep["e"].append(ann(lr))
                continue
            o = have[0]
            if o.get("source") == "consumable":
                for f in ("cooldownMs", "categoryCooldownMs", "categoryId"):
                    lv, ov = lr.get(f), o.get(f)
                    if f != "categoryId":
                        ov = _ms(ov)
                    if lv != ov:
                        mismatch(iid, lr, "consumables", f, ov, lv)
            elif lr.get("cooldownMs") is not None and lr["cooldownMs"] != _ms(o.get("cooldownMs")):
                mismatch(iid, lr, "onUse", "cooldownMs", _ms(o.get("cooldownMs")), lr["cooldownMs"])

    # c / d: procs
    live_proc_by = {}
    for r in live["procs"]:
        live_proc_by.setdefault(r["itemId"], []).append(r)
    for iid in sorted(live_proc_by):
        for lr, o in _pair(live_proc_by[iid], our_proc.get(iid, [])):
            if lr is None:
                continue
            if o is None:
                row = ann(lr)
                row["partial"] = iid in our_proc  # the item is tracked, this effect is not
                rep["c"].append(row)
                continue
            li, oi = lr.get("icdMs"), _ms(o.get("icdMs"))
            if li != oi:
                rep["d"].append({"itemId": iid, "name": lr["name"], "ours": oi, "live": li,
                                 "buffName": lr.get("buffName"),
                                 "debounce": min(x for x in (li, oi) if x) < SUBSECOND_MS})
            for f in ("durationMs", "buffId", "buffName"):
                ov = o.get(f) if f in ("buffId", "buffName") else _ms(o.get(f))
                if lr.get(f) != ov:
                    mismatch(iid, lr, "procs", f, ov, lr.get(f))

    # f: rows we emit whose item is gone or lost its effect. ABSENCE from the db is not evidence:
    # wowsims drops items below its item-effect floor and phase-filters (2026-11-09 report s1.1),
    # so `absent` rows are listed for the reviewer and never acted on by themselves.
    live_on_ids = {r["itemId"] for r in live["onUse"]}
    live_proc_ids = {r["itemId"] for r in live["procs"]}
    live_cons_ids = {r["itemId"] for r in live["consumables"]}
    for lst, ids in (("onUse", live_on_ids | live_cons_ids), ("procs", live_proc_ids),
                     ("consumables", live_cons_ids | live_on_ids)):
        for r in sorted(ours[lst], key=lambda r: (r["itemId"], r.get("buffId", 0))):
            if r.get("source") not in ("item", "consumable") or r["itemId"] in ids:
                continue
            iid = r["itemId"]
            it = live["items"].get(iid) or live["consumableRows"].get(iid)
            if it is not None:
                kinds = sorted({("onUse" if "onUse" in e else "proc" if "proc" in e else "passive")
                                for e in it.get("itemEffects", []) or []})
                state = ("changed kind: " + "/".join(kinds)) if kinds else "lost its effect"
                evidence = True
            else:
                state = "absent from db"
                if live_jsonl_ids is not None:
                    state += " (in mythicsim live jsonl)" if iid in live_jsonl_ids else ""
                evidence = False
            rep["f"].append({"itemId": iid, "name": r["name"], "list": lst,
                             "buffId": r.get("buffId"), "state": state, "evidence": evidence})

    # g: ByName collisions the missing rows would hit
    names_on: dict = {}
    for r in ours["onUse"]:
        names_on.setdefault(r["name"], set()).add(r["itemId"])
    names_pr: dict = {}
    for r in ours["procs"]:
        if r.get("source") == "item":
            names_pr.setdefault(r["name"], set()).add(r["itemId"])
    on_cands = rep["a"] + [c for c in rep["e"] if not c.get("categoryCooldownMs")]
    for label, cands, names in (("onUse", on_cands, names_on), ("procs", rep["c"], names_pr)):
        by_new: dict = {}
        for c in cands:
            by_new.setdefault(c["name"], set()).add(c["itemId"])
        for name in sorted(by_new):
            ids = by_new[name] | names.get(name, set())
            if len(ids) > 1:
                have = sorted(names.get(name, set()))
                rep["g"].append({"name": name, "list": label, "existing": have,
                                 "new": sorted(by_new[name] - set(have)),
                                 "winner": min(ids),
                                 "flips": bool(have) and min(ids) != min(have)})
    rep["g"].sort(key=lambda r: (r["name"].casefold(), r["list"]))

    counts = {k: len(v) for k, v in rep.items()}
    meta = {"liveOnUseEffects": len(live["onUse"]), "liveProcEffects": len(live["procs"]),
            "liveConsumableEffects": len(live["consumables"]),
            "liveConsumableEffectsTracked": sum(1 for r in live["consumables"] if r["tracked"]),
            "livePassiveOrCategoryOnly": live["passive"],
            "liveItems": len(live["items"]), "liveConsumables": len(live["consumableRows"]),
            "oursOnUse": len(ours["onUse"]), "oursProcs": len(ours["procs"]),
            "oursConsumables": len(ours["consumables"]),
            "oursEnchantProcs": len(ours["enchantProcs"])}
    return {"meta": meta, "counts": counts, "rows": rep}


# --------------------------------------------------------------------------- rendering
TITLES = {
    "a": "live on-use items missing from our data",
    "b": "cooldown / duration / buff / category mismatches (known = the layer keeps our value)",
    "c": "live proc effects missing",
    "d": "proc ICD mismatches (debounce = sub-second, generator keeps them)",
    "e": "live consumables with a >= 60 s cooldown missing from our data",
    "f": "rows we emit that are gone / lost their effect / changed kind (absent = no evidence)",
    "g": "ByName collisions if the missing rows were added",
}
COLUMNS = {
    "a": ("itemId", "name", "slotType", "cooldownMs", "durationMs", "categoryId", "categoryCooldownMs",
          "phase", "expansion", "sources", "firstSeen", "liveJsonl"),
    "b": ("itemId", "name", "list", "field", "ours", "live", "known"),
    "c": ("itemId", "name", "buffName", "durationMs", "icdMs", "ppm", "partial", "slotType", "phase",
          "expansion", "sources", "firstSeen", "liveJsonl"),
    "d": ("itemId", "name", "ours", "live", "debounce", "buffName"),
    "e": ("itemId", "name", "cooldownMs", "categoryId", "categoryCooldownMs", "phase", "sources",
          "firstSeen", "liveJsonl"),
    "f": ("itemId", "name", "list", "buffId", "state"),
    "g": ("name", "list", "existing", "new", "winner", "flips"),
}


def _cell(v) -> str:
    if v is None:
        return "-"
    if isinstance(v, bool):
        return "y" if v else "n"
    if isinstance(v, list):
        return ",".join(str(x) for x in v) or "-"
    return str(v)


def render(rep: dict, categories: str) -> str:
    out = []
    m = rep["meta"]
    out.append(f"live: {m['liveItems']} items, {m['liveConsumables']} consumables; effects: "
               f"{m['liveOnUseEffects']} on-use, {m['liveProcEffects']} proc, "
               f"{m['liveConsumableEffects']} consumable with cooldown, "
               f"{m['livePassiveOrCategoryOnly']} passive/category-only (out of scope)")
    out.append(f"ours: onUse={m['oursOnUse']} procs={m['oursProcs']} "
               f"consumables={m['oursConsumables']} enchantProcs={m['oursEnchantProcs']}")
    for k in CATEGORIES:
        if k not in categories:
            continue
        rows = rep["rows"][k]
        out.append("")
        out.append(f"({k}) {TITLES[k]}: {len(rows)}")
        if not rows:
            continue
        cols = COLUMNS[k]
        table = [[_cell(r.get(c)) for c in cols] for r in rows]
        widths = [max(len(c), *(len(t[i]) for t in table)) for i, c in enumerate(cols)]
        out.append("  " + "  ".join(c.ljust(w) for c, w in zip(cols, widths)).rstrip())
        for t in table:
            out.append("  " + "  ".join(x.ljust(w) for x, w in zip(t, widths)).rstrip())
    out.append("")
    out.append("counts: " + " ".join(f"{k}={rep['counts'][k]}" for k in CATEGORIES if k in categories))
    return "\n".join(out)


# --------------------------------------------------------------------------- main
def _load_json(path: pathlib.Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as ex:
        print(f"error: cannot read {path}: {ex}", file=sys.stderr)
        raise SystemExit(2)


def load_first_seen(path: pathlib.Path) -> dict:
    if not path.exists():
        return {}
    return {r["id"]: r["firstSeen"] for r in _load_json(path)}


def load_live_jsonl(path: pathlib.Path) -> dict | None:
    if not path or not path.exists():
        return None
    out = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            if line.strip():
                r = json.loads(line)
                out[r["id"]] = bool(r.get("item_effects"))
    return out


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--db", type=pathlib.Path, default=DEFAULT_DB)
    ap.add_argument("--first-seen", type=pathlib.Path, default=None,
                    help="item_first_seen.json (default: next to --db)")
    ap.add_argument("--live-jsonl", type=pathlib.Path, default=DEFAULT_LIVE_JSONL)
    ap.add_argument("--items-lua", type=pathlib.Path, default=ITEMS_LUA)
    ap.add_argument("--procs-lua", type=pathlib.Path, default=PROCS_LUA)
    ap.add_argument("--layer", type=pathlib.Path, default=LAYER_JSON,
                    help="live_items.json: its onUseOverride rows mark known divergences")
    ap.add_argument("--category", default=CATEGORIES, help="comma list of a..g (default all)")
    ap.add_argument("--json", action="store_true", help="print the report as JSON")
    args = ap.parse_args(argv)

    cats = "".join(c for c in args.category.replace(",", "") if c in CATEGORIES)
    db = _load_json(args.db)
    fs_path = args.first_seen or args.db.with_name("item_first_seen.json")
    ours = load_ours(args.items_lua, args.procs_lua)
    layer = _load_json(args.layer) if args.layer and args.layer.exists() else None
    rep = compute(db, ours, load_first_seen(fs_path), load_live_jsonl(args.live_jsonl), layer)
    if args.json:
        rep = {"meta": rep["meta"], "counts": {k: v for k, v in rep["counts"].items() if k in cats},
               "rows": {k: v for k, v in rep["rows"].items() if k in cats}}
        print(json.dumps(rep, indent=1, sort_keys=True, ensure_ascii=False))
    else:
        print(render(rep, cats))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

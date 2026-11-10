#!/usr/bin/env python3
"""Generate the two item data files from mythicsim-forever-engine item data:

    addon/Forte_Items/Data/Items.lua        -- ALWAYS LOADED (the Forte_Items add-on)
        ForteXorcist.Data.Items = { onUse, consumables, enchantProcs } + OnUseByName
    addon/Forte_ItemProcs/Data/Procs.lua    -- LOAD-ON-DEMAND (the Forte_ItemProcs add-on)
        ForteXorcist.Data.ItemProcs = { procs } + ProcsByName + ProcsByBuffName

THE SPLIT (2026-11-02, agent `Procs`, PLAN.md §11.1 H7 / docs/perf.md §4 fix 1). The proc
list is 60 % of the old single file (measured: procs rows 90,464 B + ProcsByName
23,117 B + ProcsByBuffName 23,137 B of a 227,510 B file) and until H7 NOTHING read it: every
session paid ~0.4 MB of resident Lua for data no feature touched. The proc display rides
`Cooldown.Procs` (default OFF), so the proc rows + their two indexes now live in a
`## LoadOnDemand: 1` add-on that `Forte_Cooldown/Core/Procs.lua` pulls in through
`FX.LoadAddOnOnDemand("Forte_ItemProcs")` at the first enable -- off ⇒ never parsed.
The 5 weapon-ENCHANT proc rows (source == "enchant") stay in Forte_Items under
`enchantProcs`: the always-loaded `Forte_Cooldown/Core/Enchants.lua` resolves an enchant's
display name from them at login (its effect_id -> name fallback), and an always-loaded
consumer must not lean on a load-on-demand data set (the same law gate.py's toc check
enforces for Dependencies). The rows are identical in both lists; only the container moved.

Sources (sibling clone, MIT-licensed, pinned by manifest.json to one client build):
    ../mythicsim-forever-engine/data/items.jsonl        -- 12,042 items; `item_effects` on 1,108
    ../mythicsim-forever-engine/data/enchants.jsonl     -- 260 enchants; `enchant_effects` on 5
    ../mythicsim-forever-engine/data/consumables.jsonl  -- 106 consumables with cooldowns
    ../mythicsim-forever-engine/data/manifest.json      -- build pin (client_build, file sha256)

An item_effect is one of (measured on this build, disjoint):
  * `on_use`  (238)  -- item-use spell: `on_use.cooldown_ms` (+ optional `category_id`,
                        `category_cooldown_ms` shared-category cd -- NOT emitted, see below),
                        the applied buff as `buff_id`/`buff_name`, window as `effect_duration_ms`.
  * `proc`    (400)  -- proccing aura: same buff fields; `proc.proc_chance`; `proc.icd_ms`
                        -> `icdMs` (the proc ICD, emitted -- see the ICDs law below);
                        `max_cumulative_stacks` -> `maxStacks`.
  * neither   (517)  -- passive/equip auras with a buff_id: out of scope, not emitted.

An `enchant_effect` (Crusader and the four Grand-* enchants) has the same shape; the ones with
`proc` join the procs list marked `source = "enchant"` (their `itemId` is the enchant's
`effect_id`, NOT an inventory item id). Consumables (potions/elixirs, seconds-based
`cooldown_duration`/`category_cooldown_duration`/`buff_duration`, converted to ms) go to a
separate `consumables` list; records without any cooldown are skipped and counted.

**ICDs (2026-11-02, agent `DataRefresh`, D2 G2 / D3; audit restated 2026-11-10)**: proc rows
carry `icdMs` from the source's `proc.icd_ms` -- the internal cooldown a trinket/enchant proc
rides (51 rows on this build: 49 in items.jsonl + 2 in enchants.jsonl, the Grand
Arcanist/Sorcerer enchants). F15/F16 size the proc windows from it; without it the bar
re-lights a proc window early on the second proc. THE STORE AUDIT joins on the AURA id the
row's `buffName` carries ("Sear (1291568)" -> 1291568), NOT on `buff_id`: `buff_id` is often
the damage spell the aura triggers, and that spell has no `AuraOptions` row (the old
`buff_id` join found 10 rows, all reading 0, hence the earlier, wrong, "the store confirms
NONE" line). The store readings live in tools/item_lists/live_items.json (`icdStoreAudit`,
captured from the spell store the overlay is stamped from); this generator computes the
counts (equal / reads 0 / contradicts / no store row) and writes them into the Forte_ItemProcs
header, listing every row the store reads 0 on (those keep mythicsim's number). The live
tooltip confirmation (29 of 37 ICD items) is quoted from
docs/research/live-items-procs-2026-11-09.md section 1.2 and cannot be regenerated from the pinned
files. Sub-second values (10/100/200 ms) are debounces, not cooldowns:
Forte_Cooldown/Core/Procs.lua draws no bar for them (its own 1 s floor, `Procs.MIN_ICD`).

**Live layer (2026-11-10, tools/item_lists/live_items.json)**: the mythicsim item rows are
pinned at 1.60.1.70425 and the game moved afterwards (ItemEffect hotfixes never show in the
spell store: wave M5's "707 of 707 equal" was true of the store and missed three on-use
cooldowns). The list file carries, each row with its source: `onUseOverride` (a value change
to a mythicsim on-use row, with the value it replaces -- a stale or redundant override is an
error), `onUseAdd` (live on-use items mythicsim does not have), `procAdd` / `procPreferId`
(a live proc row, and the ByName pick for a duplicated name), `consumablesAdd` (live
consumables with a cooldown that the 106-row sim list omits) and the ICD audit readings.
The 64 wowsims-side on-use category additions stay unemitted, matching the
`category_cooldown_ms` "NOT emitted" law above.

**Relevance policy**: no hand filtering by class -- most items are class-agnostic. `classAllowlist`
is emitted ONLY where the source row has `class_allowlist` (e.g. trinkets restricted to one class
family); 331 of the effect-bearing items have one. `slotType` is composed exactly from the fields
the data states (`type`, `hand_type`, `weapon_type`, `ranged_weapon_type`, `armor_type`, joined by
" / "); nothing is inferred. Each entry is tagged `trackable`:
  * `cooldown`     -- onUse/consumables: readable through the item-cooldown API path
                      (`C_Item`/`C_Container` GetItemCooldown -- unannotated-secret at this pin,
                      PLAN.md §8: probe before relying).
  * `buff-window`  -- procs: a proc has NO cast to predict from (no self `UNIT_SPELLCAST_SUCCEEDED`
                      anchor; it fires off a hit), so the window cannot be cast-predicted like a
                      class spell. Forever aura reads are SecretWhenCombatRestricted (PLAN.md §8),
                      so the ONLY source for the full window is an OUT-OF-COMBAT aura read
                      (C_UnitAuras via Compat.PlainOrNil); in combat the addon can only watch the
                      aura appearing/disappearing via unit-aura events, never read the timer.

Name handling: Forever keys by NAME at runtime; ids are informational. Same item name with
multiple ids exists (PvP rank variants, e.g. "Insignia of the Horde" x16): every entry is kept in
the lists, and ByName keys resolve deterministically to the LOWEST itemId (or the
`procPreferId` pick); every such collision is printed by this generator and listed in the
generated file header. Two refinements:
  * CLASS-VARIANT names (every row of the name has its own `classAllowlist`, e.g. the 16
    Insignia rows, one per class and effect): Core/Items.lua gates the ByName row on the
    player's class, and the lowest-id row is ONE class's row, so every other class would never
    track it. `OnUseByName[name]` is then a merged row (name, lowest id, cooldown,
    `classAllowlist` = the union; buff/duration fields only where every variant agrees) and
    `OnUseByNameClass[name][ClassToken]` is each class's own row (lowest id per class).
  * `ProcsByBuffName` keeps the first row per buff name; the buff names shared by DIFFERENT
    items are also listed in `ProcsByBuffNameAll[buffName]` (one row per item name).
An on-use/consumable name equal to a class spell name is checked against
addon/Forte_*/Data/*.lua: Engine.entries is keyed by plain name, so a class spell row that
carries a `cooldownMs` would share its key with the item (error); rows without one (the
Warlock Healthstone use-spells) are only reported.

Usage:
    python3 tools/gen_item_data.py            # write + report
    python3 tools/gen_item_data.py --dry      # report only, write nothing
Exit code 0 iff 0 errors.
"""
import argparse
import hashlib
import json
import pathlib
import re
import sys
from datetime import datetime, timezone

# The live store overlay lives in ONE place -- gen_spell_data.py's
# LIVE_OVERLAY constant -- so a data refresh (extract_store.py --build
# <stamp>, point that constant at the new file) moves both generators at
# once; the item header stamps its provenance from the overlay's _meta.
from gen_spell_data import LIVE_OVERLAY

HERE = pathlib.Path(__file__).resolve().parent
REPO_ROOT = HERE.parent
DEFAULT_DATA_DIR = REPO_ROOT.parent / "mythicsim-forever-engine" / "data"
OUT_PATH = REPO_ROOT / "addon" / "Forte_Items" / "Data" / "Items.lua"
PROCS_OUT_PATH = REPO_ROOT / "addon" / "Forte_ItemProcs" / "Data" / "Procs.lua"
LIVE_ITEMS = HERE / "item_lists" / "live_items.json"

# Fixed composition order for slotType: only fields the row actually states.
SLOT_FIELDS = ("type", "hand_type", "weapon_type", "ranged_weapon_type", "armor_type")


def lua_escape(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"')


def lua_str(s: str) -> str:
    return f'"{lua_escape(s)}"'


def load_jsonl(path: pathlib.Path) -> list[dict]:
    with open(path, encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]


def slot_type(row: dict, extra_field: str | None = None) -> str | None:
    parts = [row[k] for k in SLOT_FIELDS if isinstance(row.get(k), str)]
    if extra_field and isinstance(row.get(extra_field), str):
        parts.append(row[extra_field])
    return " / ".join(parts) if parts else None


def entry_fields(e: dict) -> list[str]:
    """Render one entry dict as a Lua record body (stable field order)."""
    out = [f'name = {lua_str(e["name"])}', f'itemId = {e["itemId"]}', f'source = {lua_str(e["source"])}']
    if "cooldownMs" in e:
        out.append(f'cooldownMs = {e["cooldownMs"]}')
    if "categoryCooldownMs" in e:
        out.append(f'categoryCooldownMs = {e["categoryCooldownMs"]}')
    if "categoryId" in e:
        out.append(f'categoryId = {e["categoryId"]}')
    if "buffId" in e:
        out.append(f'buffId = {e["buffId"]}')
    if "buffName" in e:
        out.append(f'buffName = {lua_str(e["buffName"])}')
    if "durationMs" in e:
        out.append(f'durationMs = {e["durationMs"]}')
    if "maxStacks" in e:
        out.append(f'maxStacks = {e["maxStacks"]}')
    if "icdMs" in e:
        out.append(f'icdMs = {e["icdMs"]}')
    if "slotType" in e:
        out.append(f'slotType = {lua_str(e["slotType"])}')
    if "consumableType" in e:
        out.append(f'consumableType = {lua_str(e["consumableType"])}')
    if "classAllowlist" in e:
        out.append("classAllowlist = { " + ", ".join(lua_str(c) for c in e["classAllowlist"]) + " }")
    out.append(f'trackable = {lua_str(e["trackable"])}')
    return out


def emit_entries(entries: list[dict], indent: str) -> list[str]:
    lines = []
    for e in entries:
        lines.append(f"{indent}{{ " + ", ".join(entry_fields(e)) + " },")
    return lines


def by_name_keyed(entries: list[dict], key_field: str, prefer: dict | None = None) -> tuple:
    """(pairs [(key, list_index_0based)], collisions [(key, [itemIds...])]).
    The lowest id wins a key unless `prefer` {key: itemId} names another row of that key."""
    members: dict[str, list[int]] = {}
    for i, e in enumerate(entries):
        members.setdefault(e[key_field], []).append(i)
    pairs: list[tuple[str, int]] = []
    collide: list[tuple[str, list[int]]] = []
    for k, idxs in members.items():
        win = idxs[0]
        want = (prefer or {}).get(k)
        if want is not None:
            for i in idxs:
                if entries[i]["itemId"] == want:
                    win = i
                    break
        pairs.append((k, win))
        if len(idxs) > 1:
            collide.append((k, [entries[win]["itemId"]]
                            + [entries[i]["itemId"] for i in idxs if i != win]))
    return pairs, sorted(collide)


def class_variant_groups(entries: list[dict]) -> dict:
    """{name: [rows]} for the names with several rows where EVERY row has its own
    classAllowlist (the Insignia family)."""
    by: dict[str, list[dict]] = {}
    for e in entries:
        by.setdefault(e["name"], []).append(e)
    return {n: rows for n, rows in by.items()
            if len(rows) > 1 and all("classAllowlist" in r for r in rows)}


def merged_class_row(rows: list[dict]) -> tuple:
    """The name-level ByName row of a class-variant name: lowest id, the union of the
    class allowlists, and a field only where every variant states the same value.
    Returns (row, problems); the cooldown must agree or the merge is refused."""
    first = rows[0]
    row = {"name": first["name"], "itemId": first["itemId"], "source": first["source"]}
    problems = []
    for f in ("cooldownMs", "buffId", "buffName", "durationMs", "maxStacks", "slotType"):
        vals = {json.dumps(r.get(f)) for r in rows}
        if len(vals) == 1 and f in first:
            row[f] = first[f]
        elif f == "cooldownMs":
            problems.append(f"class-variant {first['name']!r}: cooldownMs differs across variants")
    row["classAllowlist"] = sorted({c for r in rows for c in r["classAllowlist"]})
    row["trackable"] = first["trackable"]
    return row, problems


def load_live_items(path: pathlib.Path) -> dict | None:
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def class_spell_rows() -> dict:
    """{spell name: [has_cooldownMs, ...]} and {spell id: name} over the generated class
    data (addon/Forte_*/Data/*.lua except the two item files); comment lines are skipped."""
    names: dict[str, list[bool]] = {}
    ids: dict[int, str] = {}
    row_re = re.compile(r'\{ id = (\d+), name = "((?:[^"\\]|\\.)*)"([^}]*)\}')
    for f in sorted((REPO_ROOT / "addon").glob("Forte_*/Data/*.lua")):
        if f.name in ("Items.lua", "Procs.lua"):
            continue
        for line in f.read_text(encoding="utf-8").splitlines():
            if line.lstrip().startswith("--"):
                continue
            for m in row_re.finditer(line):
                cd = re.search(r"\bcooldownMs = (\d+)", m.group(3))
                names.setdefault(m.group(2), []).append(bool(cd and int(cd.group(1)) > 0))
                ids[int(m.group(1))] = m.group(2)
    return {"names": names, "ids": ids}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--data-dir", type=pathlib.Path, default=DEFAULT_DATA_DIR)
    ap.add_argument("--dry", action="store_true", help="report only; write nothing")
    args = ap.parse_args()

    data: pathlib.Path = args.data_dir
    missing = [n for n in ("items.jsonl", "enchants.jsonl", "consumables.jsonl", "manifest.json")
               if not (data / n).exists()]
    if missing:
        print(f"missing under {data}: {', '.join(missing)}", file=sys.stderr)
        return 1

    manifest = json.loads((data / "manifest.json").read_text(encoding="utf-8"))
    build = manifest.get("client_build", "unknown")
    engine_rev = manifest.get("engine_revision", "unknown")
    pins = {n: manifest.get("files", {}).get(n, "")[:12]
            for n in ("items.jsonl", "enchants.jsonl", "consumables.jsonl")}
    # sanity: the manifest's pin matches the file bytes we read
    for name, sha in pins.items():
        digest = hashlib.sha256((data / name).read_bytes()).hexdigest()
        if sha and not digest.startswith(sha):
            print(f"ERROR: {name} sha256 {digest[:12]} != manifest pin {sha} "
                  f"(data dir out of sync with manifest.json)", file=sys.stderr)
            return 1

    items = load_jsonl(data / "items.jsonl")
    enchants = load_jsonl(data / "enchants.jsonl")
    consumables = load_jsonl(data / "consumables.jsonl")

    live = load_live_items(LIVE_ITEMS)
    errors: list[str] = []
    if live is None:
        errors.append(f"missing {LIVE_ITEMS}: the live layer (value overrides, live on-use items, "
                      f"consumables, ICD audit readings) is part of this generator's input")
        live = {}

    on_use: list[dict] = []
    procs: list[dict] = []
    skipped_passive_effects = 0

    for item in sorted(items, key=lambda r: r["id"]):
        st = slot_type(item)
        cal = item.get("class_allowlist")
        for e in item.get("item_effects", []):
            base = {"name": item["name"], "itemId": item["id"], "source": "item"}
            if st:
                base["slotType"] = st
            if cal:
                base["classAllowlist"] = cal
            on_use_part = e.get("on_use")
            proc_part = e.get("proc")
            if on_use_part is not None:
                d = dict(base)
                cd = on_use_part.get("cooldown_ms")
                if cd is None:
                    errors.append(f"on_use {item['name']} ({item['id']}) has no cooldown_ms")
                    continue
                d["cooldownMs"] = cd
                if "buff_id" in e:
                    d["buffId"] = e["buff_id"]
                    d["buffName"] = e["buff_name"]
                if "effect_duration_ms" in e:
                    d["durationMs"] = e["effect_duration_ms"]
                if "max_cumulative_stacks" in e:
                    d["maxStacks"] = e["max_cumulative_stacks"]
                d["trackable"] = "cooldown"
                on_use.append(d)
            elif proc_part is not None:
                d = dict(base)
                if "buff_id" in e:
                    d["buffId"] = e["buff_id"]
                    d["buffName"] = e["buff_name"]
                if "effect_duration_ms" in e:
                    d["durationMs"] = e["effect_duration_ms"]
                if "max_cumulative_stacks" in e:
                    d["maxStacks"] = e["max_cumulative_stacks"]
                icd = proc_part.get("icd_ms")
                if icd:
                    d["icdMs"] = int(icd)  # the proc ICD (D2 G2, F15/F16 windows)
                d["trackable"] = "buff-window"
                procs.append(d)
            else:
                skipped_passive_effects += 1

    enchant_procs = 0
    for en in sorted(enchants, key=lambda r: r["effect_id"]):
        for e in en.get("enchant_effects", []):
            base = {"name": en["name"], "itemId": en["effect_id"], "source": "enchant"}
            st = slot_type(en, extra_field="enchant_type")
            if st:
                base["slotType"] = st
            if en.get("class_allowlist"):
                base["classAllowlist"] = en["class_allowlist"]
            if "on_use" in e:
                cd = e["on_use"].get("cooldown_ms")
                base["cooldownMs"] = cd
                if "buff_id" in e:
                    base["buffId"] = e["buff_id"]
                    base["buffName"] = e["buff_name"]
                if "effect_duration_ms" in e:
                    base["durationMs"] = e["effect_duration_ms"]
                base["trackable"] = "cooldown"
                on_use.append(base)
            elif "proc" in e:
                if "buff_id" in e:
                    base["buffId"] = e["buff_id"]
                    base["buffName"] = e["buff_name"]
                if "effect_duration_ms" in e:
                    base["durationMs"] = e["effect_duration_ms"]
                icd = (e.get("proc") or {}).get("icd_ms")
                if icd:
                    base["icdMs"] = int(icd)
                base["trackable"] = "buff-window"
                procs.append(base)
                enchant_procs += 1

    consumable_out: list[dict] = []
    consumable_no_cd = 0
    for c in sorted(consumables, key=lambda r: r["id"]):
        cd_s = c.get("cooldown_duration")
        cat_s = c.get("category_cooldown_duration")
        if cd_s is None and cat_s is None:
            consumable_no_cd += 1
            continue
        d = {"name": c["name"], "itemId": c["id"], "source": "consumable"}
        if cd_s is not None:
            d["cooldownMs"] = int(cd_s * 1000)
        if cat_s is not None:
            d["categoryCooldownMs"] = int(cat_s * 1000)
        if "category_id" in c:
            d["categoryId"] = c["category_id"]
        if "buff_duration" in c:
            d["durationMs"] = int(c["buff_duration"] * 1000)
        if isinstance(c.get("type"), str):
            d["consumableType"] = c["type"]
        d["trackable"] = "cooldown"
        consumable_out.append(d)

    # ---- the live layer (tools/item_lists/live_items.json; see the module docstring) ----
    ov_applied: list[str] = []
    for sid, ov in sorted((live.get("onUseOverride") or {}).items(), key=lambda kv: int(kv[0])):
        iid = int(sid)
        hit = [d for d in on_use if d["itemId"] == iid and d["source"] == "item"]
        fields = [f for f in ("cooldownMs", "durationMs") if f in ov]
        if len(hit) != 1 or len(fields) != 1 or "was" not in ov:
            errors.append(f"onUseOverride {sid}: needs exactly one mythicsim on-use row, ONE of "
                          f"cooldownMs/durationMs and `was`")
            continue
        f, row = fields[0], hit[0]
        if ov.get("name") != row["name"]:
            errors.append(f"onUseOverride {sid}: names {row['name']!r}, the list says {ov.get('name')!r}")
        elif row.get(f) == ov[f]:
            errors.append(f"onUseOverride {sid} ({row['name']}): the source row already says "
                          f"{f} = {ov[f]} -- remove the override from live_items.json")
        elif row.get(f) != ov["was"]:
            errors.append(f"onUseOverride {sid} ({row['name']}): the source row's {f} is "
                          f"{row.get(f)}, the list expects {ov['was']} -- the pinned data moved, "
                          f"re-check the override")
        else:
            row[f] = ov[f]
            ov_applied.append(f"{row['name']} ({iid}) {f} {ov['was']} -> {ov[f]}")

    have_on_use = {d["itemId"] for d in on_use if d["source"] == "item"}
    n_add_on_use = 0
    for a in live.get("onUseAdd") or []:
        if a["itemId"] in have_on_use:
            errors.append(f"onUseAdd {a['itemId']} ({a['name']}) is already in the mythicsim data -- "
                          f"remove it from live_items.json")
            continue
        d = {"name": a["name"], "itemId": a["itemId"], "source": "item"}
        for f in ("slotType", "cooldownMs", "buffId", "buffName", "durationMs", "maxStacks",
                  "classAllowlist"):
            if f in a:
                d[f] = a[f]
        d["trackable"] = "cooldown"
        on_use.append(d)
        have_on_use.add(a["itemId"])
        n_add_on_use += 1

    have_procs = {d["itemId"] for d in procs if d["source"] == "item"}
    n_add_proc = 0
    for a in live.get("procAdd") or []:
        if a["itemId"] in have_procs:
            errors.append(f"procAdd {a['itemId']} ({a['name']}) is already in the mythicsim data -- "
                          f"remove it from live_items.json")
            continue
        d = {"name": a["name"], "itemId": a["itemId"], "source": "item"}
        for f in ("slotType", "buffId", "buffName", "durationMs", "maxStacks", "icdMs",
                  "classAllowlist"):
            if f in a:
                d[f] = a[f]
        d["trackable"] = "buff-window"
        procs.append(d)
        have_procs.add(a["itemId"])
        n_add_proc += 1

    have_cons = {d["itemId"] for d in consumable_out}
    n_add_cons = 0
    for grp in live.get("consumablesAdd") or []:
        for a in grp["rows"]:
            if a["itemId"] in have_cons or a["itemId"] in have_on_use:
                errors.append(f"consumablesAdd {a['itemId']} ({a['name']}) is already emitted -- "
                              f"remove it from live_items.json")
                continue
            d = {"name": a["name"], "itemId": a["itemId"], "source": "consumable"}
            for f in ("cooldownMs", "categoryCooldownMs", "categoryId", "durationMs",
                      "consumableType"):
                if f in a:
                    d[f] = a[f]
            d["trackable"] = "cooldown"
            consumable_out.append(d)
            have_cons.add(a["itemId"])
            n_add_cons += 1

    # Deterministic order: name (casefold), itemId, buffId.
    def order(e: dict):
        return (e["name"].casefold(), e["itemId"], e.get("buffId", 0))
    on_use.sort(key=order)
    procs.sort(key=order)
    consumable_out.sort(key=order)

    prefer_ids = {n: v["itemId"] for n, v in (live.get("procPreferId") or {}).items()}
    onuse_by, onuse_collide = by_name_keyed(on_use, "name")
    procs_by, procs_collide = by_name_keyed(procs, "name", prefer_ids)

    # Class-variant names (the Insignia family): a merged ByName row + a per-class index.
    on_use_pos = {id(e): i for i, e in enumerate(on_use)}
    variant_rows = class_variant_groups(on_use)
    merged_by_name: dict[str, dict] = {}
    class_rows: dict[str, dict[str, int]] = {}
    for vname, vrows in sorted(variant_rows.items()):
        mrow, probs = merged_class_row(vrows)
        errors.extend(probs)
        merged_by_name[vname] = mrow
        per_class: dict[str, list[dict]] = {}
        for r in vrows:
            for c in r["classAllowlist"]:
                per_class.setdefault(c, []).append(r)
        class_rows[vname] = {c: on_use_pos[id(rs[0])] for c, rs in sorted(per_class.items())}
        for c, rs in sorted(per_class.items()):
            if len({r.get("buffId") for r in rs}) > 1:
                print(f"report: class-variant {vname!r} {c}: rows {[r['itemId'] for r in rs]} "
                      f"disagree on buffId; OnUseByNameClass takes the lowest id")
    proc_buff_pairs: list[tuple[str, int]] = []
    proc_buff_seen: dict[str, int] = {}
    proc_buff_collide: list[tuple[str, list[int]]] = []
    for i, e in enumerate(procs):
        k = e.get("buffName")
        if k is None:
            continue
        if k in proc_buff_seen:
            proc_buff_collide.append((k, [procs[proc_buff_seen[k]]["itemId"], e["itemId"]]))
            continue
        proc_buff_seen[k] = i
        proc_buff_pairs.append((k, i))

    nodur_onuse = sum(1 for e in on_use if "buffName" in e and "durationMs" not in e)
    nodur_procs = sum(1 for e in procs if "buffName" in e and "durationMs" not in e)
    n_proc_items = sum(1 for e in procs if e["source"] == "item")
    n_proc_ench = enchant_procs

    # ---- the ICD audit (module docstring "ICDs"): readings from live_items.json, joined on
    # the aura id in buffName; counted here, written into the Forte_ItemProcs header ----
    audit_src = live.get("icdStoreAudit") or {}
    by_aura = audit_src.get("byBuffNameAuraId") or {}
    by_buff = audit_src.get("byBuffId") or {}
    audit = {"equal": 0, "norow": 0, "zero": [], "diff": [], "buff_rows": 0, "buff_nonzero": 0}
    icd_all = [e for e in procs if "icdMs" in e]
    for e in icd_all:
        m = re.search(r"\((\d+)\)\s*$", e.get("buffName", ""))
        key = m.group(1) if m else None
        if key not in by_aura or str(e["buffId"]) not in by_buff:
            errors.append(f"icdStoreAudit has no reading for {e['name']} ({e['itemId']}) "
                          f"aura {key} / buffId {e['buffId']}: re-capture the readings")
            continue
        v = by_aura[key]
        if v is None:
            audit["norow"] += 1
        elif v == e["icdMs"]:
            audit["equal"] += 1
        elif v == 0:
            audit["zero"].append((e, key))
        else:
            audit["diff"].append((e, key, v))
        bv = by_buff[str(e["buffId"])]
        if bv is not None:
            audit["buff_rows"] += 1
            if bv:
                audit["buff_nonzero"] += 1
    n_subsec = sum(1 for e in icd_all if e["icdMs"] < 1000)

    # ---- item names / buff ids against the generated class data (docstring "Name handling") ----
    cls = class_spell_rows()
    benign_clash: list[str] = []
    for cname in sorted({e["name"] for e in on_use + consumable_out}):
        flags = cls["names"].get(cname)
        if not flags:
            continue
        if any(flags):
            errors.append(f"item name {cname!r} equals a class spell name whose row carries a "
                          f"cooldownMs: both would key Engine.entries[{cname!r}]")
        else:
            benign_clash.append(cname)
    seen_id_clash: set[tuple[int, str]] = set()
    id_clash: list[str] = []
    for e in on_use + procs:
        bid = e.get("buffId")
        if bid in cls["ids"] and (bid, e["name"]) not in seen_id_clash:
            seen_id_clash.add((bid, e["name"]))
            id_clash.append(f"{e['name']} ({e['itemId']}) buffId {bid} = class spell {cls['ids'][bid]!r}")

    print(f"counts: onUse={len(on_use)} procs={len(procs)} "
          f"(item={n_proc_items} enchant={n_proc_ench}) consumables={len(consumable_out)} "
          f"(skipped no-cooldown consumables={consumable_no_cd}) "
          f"[build {build}, source items.jsonl {len(items)} items; "
          f"passive buff-only effects not emitted: {skipped_passive_effects}]")
    print(f"report: entries with a buff but no duration: onUse={nodur_onuse} procs={nodur_procs}")
    for label, coll in (("onUse", onuse_collide), ("procs", procs_collide)):
        for name, ids in coll:
            print(f"report: {label} name collision {name!r} ids={ids} -> ByName resolves to the "
                  f"first id listed (lowest, or the procPreferId pick)")
    for name, ids in proc_buff_collide:
        print(f"report: proc buffName collision {name!r} ids={ids} -> ByBuffName resolves to first")
    for line in id_clash:
        print(f"report: item buff id == class spell id (no name shadowing: buff names carry their "
              f"id, class rows key by plain name): {line}")
    for cname in benign_clash:
        print(f"report: item name {cname!r} equals a class spell name whose rows carry no "
              f"cooldownMs (not tracked by name): benign")
    print(f"report: live layer: overrides applied={len(ov_applied)} onUse added={n_add_on_use} "
          f"procs added={n_add_proc} consumables added={n_add_cons}")
    print(f"report: ICD audit (join on the buffName aura id): equal={audit['equal']} "
          f"store-reads-0={len(audit['zero'])} contradicts={len(audit['diff'])} "
          f"no-store-row={audit['norow']} of {len(icd_all)}; the old buff_id join: "
          f"{audit['buff_rows']} rows, {audit['buff_nonzero']} non-zero; sub-second rows={n_subsec}")
    print(f"errors: {len(errors)}")
    for e in errors:
        print(f"  error: {e}", file=sys.stderr)
    if errors:
        return 1
    if args.dry:
        print("dry: wrote nothing")
        return 0

    # ---------------- the H7 split (see the module docstring) ----------------
    # The item proc rows + their two index tables go to the load-on-demand file;
    # the enchant proc rows stay in Forte_Items (the always-loaded Enchants
    # module's name fallback reads them) under the name `enchantProcs`.
    proc_item_rows = [e for e in procs if e["source"] == "item"]
    enchant_proc_rows = [e for e in procs if e["source"] != "item"]
    proc_items_by, proc_items_collide = by_name_keyed(proc_item_rows, "name", prefer_ids)
    proc_buff_pairs = []
    proc_buff_seen = {}
    for i, e in enumerate(proc_item_rows):
        k = e.get("buffName")
        if k is None:
            continue
        if k in proc_buff_seen:
            continue
        proc_buff_seen[k] = i
        proc_buff_pairs.append((k, i))
    # Buff names shared by DIFFERENT items: ProcsByBuffName keeps the first, this lists all.
    buff_items: dict[str, list[int]] = {}
    buff_item_names: dict[str, set[str]] = {}
    for i, e in enumerate(proc_item_rows):
        k = e.get("buffName")
        if k is None or e["name"] in buff_item_names.setdefault(k, set()):
            continue
        buff_item_names[k].add(e["name"])
        buff_items.setdefault(k, []).append(i)
    buff_all = [(k, idxs) for k, idxs in sorted(buff_items.items()) if len(idxs) > 1]
    nodur_proc_items = sum(1 for e in proc_item_rows
                           if "buffName" in e and "durationMs" not in e)
    nodur_proc_ench = sum(1 for e in enchant_proc_rows
                          if "buffName" in e and "durationMs" not in e)
    icd_rows = [e for e in procs if "icdMs" in e]
    icd_rows_items = [e for e in proc_item_rows if "icdMs" in e]
    icd_rows_ench = [e for e in enchant_proc_rows if "icdMs" in e]

    ts = datetime.now(timezone.utc).isoformat(timespec="seconds")

    def common_header() -> list[str]:
        """The provenance block every emitted file carries (same lines, both files)."""
        h: list[str] = []
        h.append("-- GENERATED by tools/gen_item_data.py -- do not hand-edit.")
        h.append("-- Source: mythicsim-forever-engine/data/{items,enchants,consumables}.jsonl")
        h.append(f"-- Build pin: client_build {build}, engine_revision {engine_rev}")
        ov_meta = None
        if LIVE_OVERLAY.exists():
            ov_meta = json.loads(LIVE_OVERLAY.read_text(encoding="utf-8")).get("_meta")
        if ov_meta:
            # The store's item leg rides its own build (the capture stamps
            # per input group); spell it out so the header never reads as if
            # the item numbers came from the spell build.
            items_leg = (f"; item leg {ov_meta['items_build']} "
                         f"@ hotfix {ov_meta['items_hotfix_push']}"
                         if ov_meta.get("items_build") else "")
            ov_build_short = str(ov_meta["build"]).rsplit(".", 1)[-1]
            h.append(f"-- Overlay: wowsims/forever {ov_meta['commit']} build {ov_meta['build']} (MIT)"
                     f"{items_leg}")
            h.append(f"--   (hotfix push {ov_meta['hotfix_push']}; {ov_meta.get('store_inputs', 'spell-store capture')}; "
                     f"built by {ov_meta.get('generated_by', 'tools/extract_store.py')}; "
                     f"spell-store cross-check, "
                     f"docs/research/data-diff-70707.md §3 + "
                     f"docs/research/data-diff-live-2026-11-10.md §4: where the store "
                     f"carries a row for a consumed buff id its duration equals the "
                     f"{build} pull except the divergences that report lists, and the "
                     f"item/consumable cooldowns and shared categories carry no spell "
                     f"id in the pull to join on; the store applies no value overlay "
                     f"to this file -- the live item layer is tools/item_lists/live_items.json)")
        else:
            h.append(f"-- Overlay: NONE (tools/{LIVE_OVERLAY.name} missing) -- values are pure {build}")
        lmeta = live.get("_meta") or {}
        h.append(f"-- Live item layer: tools/item_lists/live_items.json ({lmeta.get('source_db', 'source unknown')};")
        h.append(f"--   {lmeta.get('report', 'report unknown')})")
        h.append("-- File pins (sha256 prefix, manifest.json): "
                 f"items={pins['items.jsonl']} "
                 f"enchants={pins['enchants.jsonl']} consumables={pins['consumables.jsonl']}")
        h.append(f"-- Regenerated: {ts}")
        h.append("-- SPLIT (H7, docs/perf.md §4 fix 1): the item proc list lives in")
        h.append("--   addon/Forte_ItemProcs/Data/Procs.lua (`ForteXorcist.Data.ItemProcs`), a")
        h.append("--   `## LoadOnDemand: 1` add-on loaded only when `Cooldown.Procs` is on")
        h.append("--   (addon/Forte_Cooldown/Core/Procs.lua). The 5 weapon-enchant proc rows are")
        h.append("--   the exception: the always-loaded Forte_Cooldown/Core/Enchants.lua names an")
        h.append("--   enchant from them, so they stay here as Data.Items.enchantProcs.")
        h.append(f"-- Entries with a buff but no duration: onUse={nodur_onuse} "
                 f"procs={nodur_procs} (window unknown from data; show as '?' until measured)")
        h.append("-- IDs are informational (drift between builds, PLAN.md §8); runtime keys by NAME.")
        h.append("-- source=\"enchant\" entries: itemId is the enchant effect_id, not an inventory item id.")
        return h

    def collisions_leg(lines: list[str]) -> None:
        lines.append("-- Name collisions (same name, multiple ids -- ByName keys resolve to the LOWEST id,")
        lines.append("--   or the procPreferId pick; all variants remain in the lists): "
                     f"{len(onuse_collide) + len(procs_collide)}")
        for label, coll in (("onUse", onuse_collide), ("procs", procs_collide)):
            for name, ids in coll:
                note = ""
                if label == "onUse" and name in merged_by_name:
                    note = " (class variants: merged ByName row + OnUseByNameClass)"
                elif label == "procs" and name in prefer_ids:
                    note = f" (ProcsByName pick {prefer_ids[name]}, procPreferId)"
                lines.append(f"--   {label}: {name} ids={','.join(str(i) for i in ids)}{note}")

    # ------------------------------------------------ Forte_Items/Items.lua --
    L: list[str] = common_header()
    A = L.append
    A(f"-- Counts: onUse={len(on_use)} consumables={len(consumable_out)} "
      f"enchantProcs={len(enchant_proc_rows)}")
    A("-- Live layer (tools/item_lists/live_items.json): value overrides applied to mythicsim rows:")
    for s in ov_applied:
        A(f"--   {s}")
    A(f"--   rows added: onUse={n_add_on_use} procs={n_add_proc} consumables={n_add_cons} "
      f"(each row's source is in the list file)")
    collisions_leg(L)
    A("-- trackable = \"cooldown\"    -- item-use/consumable: the item cooldown API path")
    A("-- trackable = \"buff-window\" -- procs: NO cast to predict from (a proc fires off a hit, no")
    A("--   UNIT_SPELLCAST_SUCCEEDED anchor). Forever aura reads are secret in combat")
    A("--   (PLAN.md §8), so the window can ONLY be read OUT OF COMBAT (C_UnitAuras via")
    A("--   Compat.PlainOrNil); in combat watch aura appear/disappear events only.")
    A("")
    A("ForteXorcist = ForteXorcist or {}")
    A("ForteXorcist.Data = ForteXorcist.Data or {}")
    A("ForteXorcist.Data.Items = {")
    A("  onUse = {")
    L.extend(emit_entries(on_use, "    "))
    A("  },")
    A("  consumables = {")
    L.extend(emit_entries(consumable_out, "    "))
    A("  },")
    A("  enchantProcs = {")
    L.extend(emit_entries(enchant_proc_rows, "    "))
    A("  },")
    A("}")
    A("")
    A("-- ByName lookups (runtime keys by name; values reference the list entries above).")
    A("do")
    A("  local items = ForteXorcist.Data.Items")
    A("  items.OnUseByName = {}")
    for k, i in onuse_by:
        if k in merged_by_name:
            A("  -- class-variant name: merged row (lowest id, union allowlist), not a list entry")
            A(f"  items.OnUseByName[{lua_str(k)}] = {{ " + ", ".join(entry_fields(merged_by_name[k])) + " }")
        else:
            A(f"  items.OnUseByName[{lua_str(k)}] = items.onUse[{i + 1}]")
    A("  -- class-variant names: each class's own row (lowest id per class)")
    A("  items.OnUseByNameClass = {}")
    for vname, per in class_rows.items():
        A(f"  items.OnUseByNameClass[{lua_str(vname)}] = {{")
        for c, i in per.items():
            A(f"    [{lua_str(c)}] = items.onUse[{i + 1}],")
        A("  }")
    A("end")
    A("")

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text("\n".join(L) + "\n", encoding="utf-8")
    print(f"wrote {OUT_PATH} ({OUT_PATH.stat().st_size} bytes, build {build})")

    # ---------------------------------------------- Forte_ItemProcs/Procs.lua --
    P: list[str] = common_header()
    B = P.append
    B(f"-- Counts: procs={len(proc_item_rows)} (item source only; the {len(enchant_proc_rows)}")
    B(f"--   enchant rows are in Forte_Items/Data/Items.lua, key enchantProcs)")
    B(f"-- Entries with a buff but no duration: procs={nodur_proc_items} (the {nodur_proc_ench}")
    B("--   enchant rows of Forte_Items carry the rest)")
    B(f"-- ICDs (proc.icd_ms, D2 G2 / F15-F16): {len(icd_rows)} rows carry icdMs")
    B(f"--   ({len(icd_rows_items)} here + {len(icd_rows_ench)} in Forte_Items enchantProcs).")
    B("--   Store audit (tools/item_lists/live_items.json icdStoreAudit = AuraOptions.ICDMs read from")
    B("--   the spell store), joined on the AURA id each row's buffName carries -- buffId is often")
    B("--   the damage spell the aura triggers and has no AuraOptions row:")
    B(f"--   {audit['equal']} of {len(icd_all)} rows equal the store, {len(audit['zero'])} read 0 there, "
      f"{len(audit['diff'])} contradict it, {audit['norow']} have no store row.")
    B(f"--   (The old buffId join found {audit['buff_rows']} rows, {audit['buff_nonzero']} non-zero.)")
    for e, key in audit["zero"]:
        B(f"--   store reads 0, mythicsim number kept: {e['name']} ({e['itemId']}) "
          f"icdMs = {e['icdMs']} (aura {key})")
    for e, key, v in audit["diff"]:
        B(f"--   CONTRADICTED by the store: {e['name']} ({e['itemId']}) icdMs = {e['icdMs']}, "
          f"aura {key} reads {v}")
    tip = live.get("icdTooltipAudit")
    if tip:
        B(f"--   Live tooltips (quoted, not regenerated -- {tip['source']}): "
          f"{tip['itemsMatchingTooltip']} of {tip['itemsChecked']} ICD items state the same number, "
          f"{tip['itemsWithoutCooldownLine']} show no cooldown line, {tip['itemsNotOnWowhead']} are not on "
          f"Wowhead; ambiguous: {', '.join(tip['ambiguous'])}.")
    B(f"--   {n_subsec} of {len(icd_rows)} rows are sub-second (< 1000 ms) debounces, not cooldowns:")
    B("--   Forte_Cooldown/Core/Procs.lua draws no bar for them (Procs.MIN_ICD).")
    B("--   Forte_Cooldown/Core/Procs.lua sizes the proc ICD window from icdMs:")
    for e in icd_rows:
        B(f"--   {e['name']} ({e['itemId']}) icdMs = {e['icdMs']}")
    collisions_leg(P)
    B(f"-- Live layer: {n_add_proc} proc row(s) added from tools/item_lists/live_items.json (procAdd).")
    B(f"-- Proc buff names shared by DIFFERENT items: {len(buff_all)} (ProcsByBuffName keeps the first;")
    B("--   ProcsByBuffNameAll lists one row per item name, first = the ProcsByBuffName row)")
    for k, idxs in buff_all:
        B(f"--   {k}: " + ", ".join(f"{proc_item_rows[i]['name']} ({proc_item_rows[i]['itemId']})"
                                    for i in idxs))
    B("-- trackable = \"buff-window\" -- procs: NO cast to predict from (a proc fires off a hit, no")
    B("--   UNIT_SPELLCAST_SUCCEEDED anchor). Forever aura reads are secret in combat")
    B("--   (PLAN.md §8), so the window can ONLY be read OUT OF COMBAT (C_UnitAuras via")
    B("--   Compat.PlainOrNil); in combat watch aura appear/disappear events only.")
    B("")
    B("ForteXorcist = ForteXorcist or {}")
    B("ForteXorcist.Data = ForteXorcist.Data or {}")
    B("ForteXorcist.Data.ItemProcs = {")
    B("  procs = {")
    P.extend(emit_entries(proc_item_rows, "    "))
    B("  },")
    B("}")
    B("")
    B("-- ByName lookups (runtime keys by name; values reference the list entries above).")
    B("do")
    B("  local procs = ForteXorcist.Data.ItemProcs")
    B("  procs.ProcsByName = {}")
    for k, i in proc_items_by:
        B(f"  procs.ProcsByName[{lua_str(k)}] = procs.procs[{i + 1}]")
    B("  procs.ProcsByBuffName = {}")
    for k, i in proc_buff_pairs:
        B(f"  procs.ProcsByBuffName[{lua_str(k)}] = procs.procs[{i + 1}]")
    B("  -- buff names shared by different items: every item (ProcsByBuffName keeps the first only)")
    B("  procs.ProcsByBuffNameAll = {}")
    for k, idxs in buff_all:
        B(f"  procs.ProcsByBuffNameAll[{lua_str(k)}] = {{ "
          + ", ".join(f"procs.procs[{i + 1}]" for i in idxs) + " }")
    B("end")
    B("")

    PROCS_OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    PROCS_OUT_PATH.write_text("\n".join(P) + "\n", encoding="utf-8")
    print(f"wrote {PROCS_OUT_PATH} ({PROCS_OUT_PATH.stat().st_size} bytes, build {build})")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())

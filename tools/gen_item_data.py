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

**ICDs (2026-11-02, agent `DataRefresh`, D2 G2 / D3)**: proc rows carry `icdMs` from the
source's `proc.icd_ms` -- the internal cooldown a trinket/enchant proc rides (51 rows on
this build: 49 in items.jsonl + 2 in enchants.jsonl, the Grand Arcanist/Sorcerer enchants;
D2's G2 table counted the enchant leg as 0 because it censused the top-level `ICDMs` key,
not nested `proc.icd_ms`). F15/F16 size the proc windows from it; without it the bar
re-lights a proc window early on the second proc. The live spell store (wowsims, MIT --
stamped in the generated header) answers the aura side of this through the proc buff
spell's `AuraOptions.ICDMs`: 7 of the 51 emitted `icdMs` rows have such a row at all (on
1.60.1.70707 AND on 1.60.1.70790, both times reading `0`), so the store confirms NONE of
them and contradicts none -- every one of the 51 stays mythicsim's hand/measured number,
launch-day probe material (docs/research/forever-data-gaps.md G2). The earlier "confirms
9 of the 49" line in this file's history is not reproducible on this join; the
measured counts are restated in docs/research/data-diff-live-2026-11-07.md §4. The store's item side
carries NO consumed-field deltas: every item/consumable cooldown, shared category and
duration this generator consumes is identical 70425 -> 70707 (D1 §3) and again
70425 -> 70790 spells / 70862 items (wave M5, 2026-11-07: 707 compared consumed values --
184 on-use cooldowns, 364 item effect durations, 13 item proc ICDs, 4 consumable
cooldowns, 71 consumable category cooldowns, 71 category ids -- ALL 707 equal, 0 deltas;
coverage, not readings, for the rest: 82 consumable buff durations, 6 `maxStacks`, 479
item rows, 10 consumable rows and the 5 enchant rows carry no row in the capture),
so the item leg applies no
value overlays (and the 64 wowsims-side on-use category additions stay unemitted, matching
the existing `category_cooldown_ms` "NOT emitted" law above).

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
the lists, and ByName keys resolve deterministically to the LOWEST itemId; every such collision
is printed by this generator and listed in the generated file header.

Usage:
    python3 tools/gen_item_data.py            # write + report
    python3 tools/gen_item_data.py --dry      # report only, write nothing
Exit code 0 iff 0 errors.
"""
import argparse
import hashlib
import json
import pathlib
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


def by_name_keyed(entries: list[dict], key_field: str) -> tuple:
    """(pairs [(key, list_index_1based)], collisions [(key, [itemIds...])]) -- first (lowest id) wins."""
    seen: dict[str, int] = {}
    pairs: list[tuple[str, int]] = []
    collide: dict[str, list[int]] = {}
    for i, e in enumerate(entries):
        k = e[key_field]
        if k in seen:
            collide.setdefault(k, []).append(e["itemId"])
            continue
        seen[k] = i
        pairs.append((k, i))
    for k in collide:
        # include the winner's id in the reported id list
        collide[k].insert(0, entries[seen[k]]["itemId"])
    return pairs, sorted(collide.items())


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

    errors: list[str] = []
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

    # Deterministic order: name (casefold), itemId, buffId.
    def order(e: dict):
        return (e["name"].casefold(), e["itemId"], e.get("buffId", 0))
    on_use.sort(key=order)
    procs.sort(key=order)
    consumable_out.sort(key=order)

    onuse_by, onuse_collide = by_name_keyed(on_use, "name")
    procs_by, procs_collide = by_name_keyed(procs, "name")
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

    print(f"counts: onUse={len(on_use)} procs={len(procs)} "
          f"(item={n_proc_items} enchant={n_proc_ench}) consumables={len(consumable_out)} "
          f"(skipped no-cooldown consumables={consumable_no_cd}) "
          f"[build {build}, source items.jsonl {len(items)} items; "
          f"passive buff-only effects not emitted: {skipped_passive_effects}]")
    print(f"report: entries with a buff but no duration: onUse={nodur_onuse} procs={nodur_procs}")
    for label, coll in (("onUse", onuse_collide), ("procs", procs_collide)):
        for name, ids in coll:
            print(f"report: {label} name collision {name!r} ids={ids} -> ByName resolves to lowest id")
    for name, ids in proc_buff_collide:
        print(f"report: proc buffName collision {name!r} ids={ids} -> ByBuffName resolves to first")
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
    proc_items_by, proc_items_collide = by_name_keyed(proc_item_rows, "name")
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
                     f"docs/research/data-diff-live-2026-11-07.md §4: every item/consumable "
                     f"cooldown, shared category and duration consumed here is identical "
                     f"{build} -> {ov_meta['build']}, so no value "
                     f"overlays are applied to this file)")
        else:
            h.append(f"-- Overlay: NONE (tools/{LIVE_OVERLAY.name} missing) -- values are pure {build}")
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
        lines.append("-- Name collisions (same name, multiple ids -- ByName keys resolve to the LOWEST id;")
        lines.append("--   all rank variants remain in the lists): "
                     f"{len(onuse_collide) + len(procs_collide)}")
        for label, coll in (("onUse", onuse_collide), ("procs", procs_collide)):
            for name, ids in coll:
                lines.append(f"--   {label}: {name} ids={','.join(str(i) for i in ids)}")

    # ------------------------------------------------ Forte_Items/Items.lua --
    L: list[str] = common_header()
    A = L.append
    A(f"-- Counts: onUse={len(on_use)} consumables={len(consumable_out)} "
      f"enchantProcs={len(enchant_proc_rows)}")
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
        A(f"  items.OnUseByName[{lua_str(k)}] = items.onUse[{i + 1}]")
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
    B(f"--   ({len(icd_rows_items)} here + {len(icd_rows_ench)} in Forte_Items enchantProcs); the store's")
    B("--   AuraOptions.ICDMs cover 125 of the 405 proc-buff auras on the 70790 capture and")
    B("--   read 0 on every one (7 of the 51 emitted rows have a store row, all of them 0),")
    B("--   so the store confirms NONE of these numbers and contradicts none -- the rest are")
    B("--   launch-day probe")
    B("--   material (docs/research/forever-data-gaps.md G2). Forte_Cooldown/Core/Procs.lua")
    B("--   sizes the proc ICD window from it:")
    for e in icd_rows:
        B(f"--   {e['name']} ({e['itemId']}) icdMs = {e['icdMs']}")
    collisions_leg(P)
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
    B("end")
    B("")

    PROCS_OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    PROCS_OUT_PATH.write_text("\n".join(P) + "\n", encoding="utf-8")
    print(f"wrote {PROCS_OUT_PATH} ({PROCS_OUT_PATH.stat().st_size} bytes, build {build})")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Build tools/overrides_<build>.json -- a live-store value overlay for the generators.

Successor of `tools/extract_70707.py` (wave M5, 2026-11-07): the same capture, the same
rows, the same byte law, with the build stamp taken from the store itself (and
verifiable against an expected `--build`) instead of being welded to 70707.

Source: the wowsims/forever clone (MIT licence, "Copyright (c) 2022 wowsims
team"), whose spell-store capture `assets/db_inputs/spell_store_inputs.json`
(gzip JSON) is stamped with the live client build per input group. The stamp
moves every few days (70707 -> 70755 -> 70790; the 2026-11-07 pin carries spells
on 1.60.1.70790 / hotfix push 113715 and the ITEMS group on 1.60.1.70862 / hotfix
push 113763 -- the build-wide `Builds`/`Hotfixes` map), so this tool reads it
from `Builds`/`Hotfixes` and stamps the output with it. The **spell** leg is
what the overlay carries, so the build consistency check spans every group
except `items`; the item leg is recorded alongside it (`items_build` /
`items_hotfix_push`) for the item generator's header (the build stamp
`docs/research/data-diff-live-2026-11-07.md` reports).

This file is the checked-in, deterministic bridge between that capture and
`gen_spell_data.py` / `gen_item_data.py`: the generators never read the store
directly, so the generated `Data/*.lua` stay reproducible from this repo +
the mythicsim pull + the pinned wowsims commit. Re-run this extractor after
`git -C /tmp/wowsims-forever pull --ff-only`; commit its output with the
regenerated data.

What goes in, per the H10/D3 contract:
  * EVERY spell id the addon currently uses (the `[<id>]` keys of the
    generated `addon/Forte_*/Data/*.lua`), and
  * for every name in `tools/spell_lists/*.json`, EVERY id of the store's
    `Names` table that carries that name (the store's Names is the
    build-wide SpellName universe -- not the sim-reached value scope; see
    data-diff-70707.md §1).
  * the store's value tables `Cooldowns` (CooldownMs/CategoryCooldownMs/GCDMs),
    `Misc` (CastTimeMs/DurationMs), `Categories` (Category), `Subtexts`
    (rank text), `Levels` (SpellLevel/BaseLevel/MaxLevel),
    `ClassOptions` (Family) and `AuraOptions` (ICDMs) -- a field is written
    only where the store HAS a row for the id (an absent row is "not in this
    export", never "0", per forever-data-gaps.md G5).
  * the feed columns (wave I-2b, 2026-11-03, upstream-data note §7.5): the
    store's `Effects[].PeriodMs` (captured as `periodMs` = the SMALLEST
    positive period of the id, the gen_spell_data tick law), the scalar
    target category `Targets` (captured as `targetCode`; the client's
    SpellEffectTargetingCategory code of the unit the spell lands on, 1 =
    the caster -- gen_spell_data's `noTarget` law) and
    `AuraOptions.MaxStack` (captured as `maxStack`, only when above 1 --
    the emit law "a cap of 1 says no stacking, the absence already says
    it"). Before this, a store-picked row (a store-rank pick like Primal
    Bite, a store-sourced row like Oath of Light) structurally dropped the
    Timer's feed columns; the captures + the generator's same-id base-feed
    law (gen_spell_data "feed sources") stop the drop.
  * charges: the store carries NO charges column (MaxStack is aura
    stacking, ProcCharges proc uses -- data-diff-70707.md §1); the addon's
    charge model is runtime (`DetectCharges`), so `charges` is never emitted.
  * `removed`: every mythicsim-side id of a tracked spell name that has no row
    at all in the store's `Names` table -- i.e. the id is gone from the live
    build (the 5 Paladin rows of data-diff-70707.md §2.3 and G5). The
    generator DROPS such rows and lists them in the generated header.
  * `bookRanks`: the AQ20 class-book rank ids from the clone's
    `sim/core/spelldata/book_ranks.go` ("The class books may not be there at
    launch, so nothing should need them by default", wowsims b6657d38). The
    generator excludes them from the default rank pick (trainer-rank
    preference, data-diff-70707.md §4).

Output JSON is canonically sorted (numeric ids ascending, keys sorted) so the
file is byte-stable for identical inputs.

Usage:
    python3 tools/extract_store.py                        # stamp from the store
    python3 tools/extract_store.py --build 70790          # assert the stamp
    python3 tools/extract_store.py --wowsims /tmp/wowsims-forever --dry
    python3 tools/extract_store.py --wowsims /tmp/wowsims-old \\
        --commit 6e69a7f4... --out /tmp/overrides_70707.json   # a replay of a pin
"""
import argparse
import gzip
import json
import pathlib
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO_ROOT = HERE.parent
DEFAULT_WOWSIMS = pathlib.Path("/tmp/wowsims-forever")
DEFAULT_MYTHICSIM = REPO_ROOT.parent / "mythicsim-forever-engine" / "data"

# The store's `Builds`/`Hotfixes` maps key one row per input group. The item
# group is the item-side capture (it rides the same file on its own cadence);
# the overlay carries the SPELL legs, so the build-consistency span is every
# group except this one, and the item leg is recorded for the header.
ITEM_GROUP = "items"


def short_build(build: str) -> str:
    """`1.60.1.70790` -> `70790` (the stamp the overlay file is named by)."""
    return build.rsplit(".", 1)[-1]


# The store's per-id value tables, mapped to the flat field names the
# generators consume. Table presence is recorded per row as `v` (the id
# carries at least one value row) so the overlay can tell "no values
# captured" from "captured zeros".
VALUE_FIELDS = {
    "Misc": {"CastTimeMs": "castMs", "DurationMs": "durationMs"},
    "Cooldowns": {"CooldownMs": "cooldownMs", "CategoryCooldownMs": "categoryCooldownMs",
                  "GCDMs": "gcdMs"},
    "Categories": {"Category": "category"},
    "AuraOptions": {"ICDMs": "icdMs"},
}

# The feed captures (wave I-2b): the store's `Targets` scalar is the client's
# SpellEffectTargetingCategory code of the unit the spell lands on -- the
# gen_spell_data feed law reads it as `targetCode` (1 = the caster, the
# CASTER_TARGET_CODE of the base-data `Target[0]` pair law). `periodMs` rides
# the smallest positive Effects[].PeriodMs (the fastest cadence the player
# sees, the generator's tick law); `maxStack` is captured only above 1 (a cap
# of 1 says "no stacking", which the absence already says).
EFFECT_PERIOD_COL = "PeriodMs"
TARGET_CATEGORY_COL = "Target"
MAXSTACK_COL = "MaxStack"
MAXSTACK_EMIT_FLOOR = 1


def effect_period_ms(eff_rows) -> int | None:
    """The smallest positive Effects[].PeriodMs of the id, ms; None = the
    store carries no periodic effect row (absence, never a zero reading)."""
    periods = [row[EFFECT_PERIOD_COL] for row in (eff_rows or [])
               if isinstance(row, dict) and isinstance(row.get(EFFECT_PERIOD_COL), (int, float))
               and not isinstance(row.get(EFFECT_PERIOD_COL), bool)
               and row[EFFECT_PERIOD_COL] > 0]
    return int(min(periods)) if periods else None


# The proc flag (AuraOptions.ProcFlags[0]) is captured only when non-zero:
# a captured flag = the row is a proc-carrying aura (the store's own
# words), the shape gen_spell_data's strict ICD join demands (Main's 2026-11-02
# ruling: borrow rides a same-family sibling rank, or a family-less pair of
# PROC rows). ProcChance/ProcFlags zeros carry no signal over the field's
# absence, so the presence-of-row capture law does not extend to them.
PROC_FLAG_COL = "ProcFlags"


def parse_book_ranks(go_path: pathlib.Path) -> list[int]:
    """The hand-kept bookRank id list of wowsims' book_ranks.go."""
    ids = []
    for line in go_path.read_text(encoding="utf-8").splitlines():
        m = re.match(r"\s*(\d+):\s*true,", line)
        if m:
            ids.append(int(m.group(1)))
    if not ids:
        raise SystemExit(f"no bookRanks ids parsed from {go_path}")
    return sorted(ids)


def used_spell_ids() -> set[int]:
    """Every [id] key the generated class data files carry today."""
    ids: set[int] = set()
    for lua in sorted((REPO_ROOT / "addon").glob("Forte_*/Data/*.lua")):
        if lua.name == "Items.lua":
            continue
        for m in re.finditer(r"^  \[(\d+)\] =", lua.read_text(encoding="utf-8"), re.M):
            ids.add(int(m.group(1)))
    return ids


def list_names() -> list[str]:
    names: set[str] = set()
    for spec_path in sorted((HERE / "spell_lists").glob("*.json")):
        spec = json.loads(spec_path.read_text(encoding="utf-8"))
        for group, val in spec.items():
            if group.startswith("_"):
                continue
            if isinstance(val, list):
                names.update(val)
            elif isinstance(val, dict):
                for sub in val.values():
                    names.update(sub)
    return sorted(names)


def mythicsim_ids_for(names: set[str], spells_jsonl: pathlib.Path) -> dict[str, list[int]]:
    """name -> every mythicsim row id of that name (the base-data side of `removed`)."""
    out: dict[str, list[int]] = {}
    with open(spells_jsonl, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            row = json.loads(line)
            n = row.get("Name")
            if n in names and row.get("ID"):
                out.setdefault(n, []).append(int(row["ID"]))
    return out


def group_stamp(stamps: dict, label: str, out) -> tuple[str, int]:
    """The single (build, hotfix) of a set of store input groups; refuse a mix.

    `stamps` is the store's `Builds` or `Hotfixes` map; `out` is the group list
    the caller's data spans. One value across the span is the law (a capture
    that moved only some classes is not one overlay)."""
    vals = {stamps.get(g) for g in out}
    if len(vals) != 1 or None in vals:
        print(f"store carries mixed {label} {stamps} for {sorted(out)}; refusing",
              file=sys.stderr)
        return None, None
    v = vals.pop()
    return (v if isinstance(v, str) else str(v)), v


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--wowsims", type=pathlib.Path, default=DEFAULT_WOWSIMS,
                    help="wowsims/forever clone (MIT)")
    ap.add_argument("--mythicsim", type=pathlib.Path, default=DEFAULT_MYTHICSIM,
                    help="mythicsim-forever-engine data dir (for the removed-id census)")
    ap.add_argument("--build", default=None,
                    help="expected short build stamp (e.g. 70790); the store's own "
                         "Builds map is the default and names the output file")
    ap.add_argument("--commit", default=None,
                    help="pin the source commit (a git archive export has no HEAD)")
    ap.add_argument("--out", type=pathlib.Path, default=None,
                    help="output path; default tools/overrides_<build>.json")
    ap.add_argument("--dry", action="store_true", help="report counts, write nothing")
    args = ap.parse_args()

    store_path = args.wowsims / "assets" / "db_inputs" / "spell_store_inputs.json"
    book_go = args.wowsims / "sim" / "core" / "spelldata" / "book_ranks.go"
    spells_jsonl = args.mythicsim / "spells.jsonl"
    for p in (store_path, book_go, spells_jsonl):
        if not p.exists():
            print(f"missing input: {p}", file=sys.stderr)
            return 1

    if args.commit is not None:
        commit = args.commit
    else:
        commit = subprocess.run(["git", "-C", str(args.wowsims), "rev-parse", "HEAD"],
                                capture_output=True, text=True).stdout.strip()
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        print(f"cannot read the wowsims clone HEAD from {args.wowsims} "
              f"(pass --commit for a git archive export)", file=sys.stderr)
        return 1

    with gzip.open(store_path, "rt", encoding="utf-8") as f:
        store = json.load(f)
    groups = sorted(store["Builds"])
    spell_groups = [g for g in groups if g != ITEM_GROUP]
    build, hotfix = None, None
    build, hotfix = group_stamp(store["Builds"], "builds", spell_groups)
    if build is None:
        return 1
    _, hotfix = group_stamp(store["Hotfixes"], "hotfixes", spell_groups)
    if hotfix is None:
        return 1
    items_build, items_hotfix = group_stamp(store["Builds"], "builds", [ITEM_GROUP])
    _, items_hotfix = group_stamp(store["Hotfixes"], "hotfixes", [ITEM_GROUP])
    stamp = short_build(build)
    if args.build is not None and args.build != stamp:
        print(f"--build {args.build} is not the store's spell build {stamp} "
              f"({build}); refusing to stamp the file with the expected value",
              file=sys.stderr)
        return 1
    out_path = args.out or HERE / f"overrides_{stamp}.json"

    names, subtexts, levels, class_opts = (store["Names"], store["Subtexts"],
                                           store["Levels"], store["ClassOptions"])
    # table name -> (store table, field mapping) for the value tables.
    tables = {real: (store[real], fields) for real, fields in VALUE_FIELDS.items()}

    used = used_spell_ids()
    list_names_sorted = list_names()
    name_set = set(list_names_sorted)

    # name -> ids: the build-wide Names universe for every tracked name.
    name_index: dict[str, list[int]] = {n: [] for n in list_names_sorted}
    for sid, n in names.items():
        if n in name_set:
            name_index[n].append(int(sid))
    for ids in name_index.values():
        ids.sort()

    wanted_ids: set[int] = set(used)
    for ids in name_index.values():
        wanted_ids.update(ids)
    names_universe = {int(k) for k in names}

    spells: dict[str, dict] = {}
    for sid in sorted(wanted_ids & names_universe):
        s = str(sid)
        row: dict = {"name": names[s]}
        c = class_opts.get(s)
        if c is not None and c.get("Family"):
            row["family"] = int(c["Family"])
        st = subtexts.get(s)
        if st:
            row["subtext"] = st
        lv = levels.get(s)
        if lv is not None:
            for k_out, k_in in (("spellLevel", "SpellLevel"), ("baseLevel", "BaseLevel"),
                                ("maxLevel", "MaxLevel")):
                if lv.get(k_in):
                    row[k_out] = int(lv[k_in])
        has_values = False
        for _table, (stable, fields) in tables.items():
            trow = stable.get(s)
            if trow is None:
                continue
            has_values = True
            for k_in, k_out in fields.items():
                # PRESENCE of the column is the capture (captured zeros are
                # facts: Swift Judgement durationMs -1 -> 0, the Intimidation
                # CategoryCooldownMs 0 with Category 1132); a table with no
                # row for the id stays absent (coverage, never a reading).
                if k_in in trow:
                    row[k_out] = int(trow[k_in])
        ao = store["AuraOptions"].get(s)
        if ao is not None:
            pf = ao.get(PROC_FLAG_COL)
            low = pf[0] if isinstance(pf, (list, tuple)) and pf else pf
            if low:
                row["procFlag"] = int(low)
        # Feed captures (wave I-2b, §7.5): they ride the same presence law
        # as the value tables and do not set `v` -- `v` marks the WINDOW
        # tables (the overlay's value merge gate); a feed never folds a
        # cooldown.
        period = effect_period_ms(store["Effects"].get(s))
        if period is not None:
            row["periodMs"] = period
        tc = store["Targets"].get(s)
        if isinstance(tc, int) and not isinstance(tc, bool):
            row["targetCode"] = int(tc)
        if ao is not None:
            ms = ao.get(MAXSTACK_COL)
            if (isinstance(ms, (int, float)) and not isinstance(ms, bool)
                    and ms > MAXSTACK_EMIT_FLOOR):
                row["maxStack"] = int(ms)
        if has_values:
            row["v"] = 1
        spells[s] = row

    # removed: mythicsim ids of tracked names with no store Names row at all.
    my_ids = mythicsim_ids_for(name_set, spells_jsonl)
    names_universe = {int(k) for k in names}
    removed: dict[str, str] = {}
    for n, ids in sorted(my_ids.items()):
        for i in sorted(ids):
            if i not in names_universe:
                removed[str(i)] = n

    out = {
        "_meta": {
            "generated_by": "tools/extract_store.py",
            "source": "wowsims/forever (github.com/wowsims/forever)",
            "source_licence": "MIT (Copyright (c) 2022 wowsims team)",
            "commit": commit,
            "build": build,
            "hotfix_push": hotfix,
            "spell_groups": spell_groups,
            "items_build": items_build,
            "items_hotfix_push": items_hotfix,
            "store_inputs": "assets/db_inputs/spell_store_inputs.json (gzip JSON)",
            "field_semantics": "times in ms; an absent field = the store carries no row "
                              "for it (absence, never a reading; data-diff-70707.md §1); "
                              "v=1 marks ids with at least one value row; charges: the "
                              "store has no charges column (data-diff-70707.md §1); "
                              "feeds (wave I-2b): periodMs = the smallest positive "
                              "Effects[].PeriodMs, targetCode = the Targets scalar "
                              "(client SpellEffectTargetingCategory code, 1 = the caster), "
                              "maxStack = AuraOptions.MaxStack above 1; "
                              f"build: spells {build} @ hotfix {hotfix}, item leg "
                              f"{items_build} @ hotfix {items_hotfix} "
                              "(data-diff-live-2026-11-07.md)",
        },
        "bookRanks": parse_book_ranks(book_go),
        "nameIndex": {n: ids for n, ids in sorted(name_index.items()) if ids},
        "removed": {k: removed[k] for k in sorted(removed, key=int)},
        "spells": {k: spells[k] for k in sorted(spells, key=int)},
    }

    text = json.dumps(out, indent=1, sort_keys=True) + "\n"
    print(f"extract {build} hotfix {hotfix} commit {commit[:8]}: "
          f"spells={len(spells)} nameIndex={len(out['nameIndex'])} "
          f"removed={len(out['removed'])} bookRanks={len(out['bookRanks'])} "
          f"-> {len(text)} bytes")
    for i, n in sorted(out["removed"].items(), key=lambda kv: int(kv[0])):
        print(f"  removed: {n} ({i})")
    if args.dry:
        print("dry: wrote nothing")
        return 0
    out_path.write_text(text, encoding="utf-8")
    print(f"wrote {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

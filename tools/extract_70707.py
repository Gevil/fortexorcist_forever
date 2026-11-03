#!/usr/bin/env python3
"""Build tools/overrides_70707.json -- the 1.60.1.70707 value overlay for the generators.

Source: the wowsims/forever clone (MIT licence, "Copyright (c) 2022 wowsims
team"), whose spell-store capture `assets/db_inputs/spell_store_inputs.json`
(gzip JSON) is stamped **build 1.60.1.70707** for all twelve input groups
(hotfix push 113562) -- the live client build (PLAN §11.1 H10; the 70425 ->
70707 delta analysis is docs/research/data-diff-70707.md, the gap analysis
docs/research/forever-data-gaps.md).

This file is the checked-in, deterministic bridge between that capture and
`gen_spell_data.py` / `gen_item_data.py`: the generators never read the store
directly, so the generated `Data/*.lua` stay reproducible from this repo +
the mythicsim pull alone. Re-run this extractor when a newer wowsims clone is
checked out; commit its output with the regenerated data.

What goes in, per the H10/D3 contract:
  * EVERY spell id the addon currently uses (the `[<id>]` keys of the
    generated `addon/Forte_*/Data/*.lua`), and
  * for every name in `tools/spell_lists/*.json`, EVERY id of the store's
    `Names` table that carries that name (the store's Names is the
    build-wide SpellName universe, 32,052 rows -- not the 8,001 sim-reached
    value scope; see data-diff-70707.md §1).
  * the 70707 value tables `Cooldowns` (CooldownMs/CategoryCooldownMs/GCDMs),
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
    it"). Before this, a 70707-picked row (a store-rank pick like Primal
    Bite, a store-sourced row like Oath of Light) structurally dropped the
    Timer's feed columns; the captures + the generator's same-id base-feed
    law (gen_spell_data "feed sources") stop the drop.
  * charges: the 70707 store carries NO charges column (MaxStack is aura
    stacking, ProcCharges proc uses -- data-diff-70707.md §1); the addon's
    charge model is runtime (`DetectCharges`), so `charges` is never emitted.
  * `removed`: every mythicsim-side id of a tracked spell name that has no
    row at all in the 70707 `Names` table -- i.e. the id is gone from the
    launch build (the 5 Paladin rows of data-diff-70707.md §2.3 and G5). The
    generator DROPS such rows and lists them in the generated header.
  * `bookRanks`: the AQ20 class-book rank ids from the clone's
    `sim/core/spelldata/book_ranks.go` ("The class books may not be there at
    launch, so nothing should need them by default", wowsims b6657d38). The
    generator excludes them from the default rank pick (trainer-rank
    preference, data-diff-70707.md §4).

Output JSON is canonically sorted (numeric ids ascending, keys sorted) so the
file is byte-stable for identical inputs.

Usage:
    python3 tools/extract_70707.py                       # default paths
    python3 tools/extract_70707.py --wowsims /tmp/wowsims-forever --dry
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
OUT_PATH = HERE / "overrides_70707.json"

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
# a captured flag = the row is a proc-carrying aura (the 70707 store's own
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
    """name -> every mythicsim row id of that name (the 70425 side of `removed`)."""
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


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--wowsims", type=pathlib.Path, default=DEFAULT_WOWSIMS,
                    help="wowsims/forever clone (MIT)")
    ap.add_argument("--mythicsim", type=pathlib.Path, default=DEFAULT_MYTHICSIM,
                    help="mythicsim-forever-engine data dir (for the removed-id census)")
    ap.add_argument("--out", type=pathlib.Path, default=OUT_PATH)
    ap.add_argument("--dry", action="store_true", help="report counts, write nothing")
    args = ap.parse_args()

    store_path = args.wowsims / "assets" / "db_inputs" / "spell_store_inputs.json"
    book_go = args.wowsims / "sim" / "core" / "spelldata" / "book_ranks.go"
    spells_jsonl = args.mythicsim / "spells.jsonl"
    for p in (store_path, book_go, spells_jsonl):
        if not p.exists():
            print(f"missing input: {p}", file=sys.stderr)
            return 1

    commit = subprocess.run(["git", "-C", str(args.wowsims), "rev-parse", "HEAD"],
                            capture_output=True, text=True).stdout.strip()
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        print(f"cannot read the wowsims clone HEAD from {args.wowsims}", file=sys.stderr)
        return 1

    with gzip.open(store_path, "rt", encoding="utf-8") as f:
        store = json.load(f)
    builds = set(store["Builds"].values())
    hotfixes = set(store["Hotfixes"].values())
    if len(builds) != 1:
        print(f"store carries mixed builds {builds}; refusing", file=sys.stderr)
        return 1
    build = builds.pop()
    hotfix = sorted(hotfixes)[-1]

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

    # removed: mythicsim ids of tracked names with no 70707 Names row at all.
    my_ids = mythicsim_ids_for(name_set, spells_jsonl)
    names_universe = {int(k) for k in names}
    removed: dict[str, str] = {}
    for n, ids in sorted(my_ids.items()):
        for i in sorted(ids):
            if i not in names_universe:
                removed[str(i)] = n

    out = {
        "_meta": {
            "generated_by": "tools/extract_70707.py",
            "source": "wowsims/forever (github.com/wowsims/forever)",
            "source_licence": "MIT (Copyright (c) 2022 wowsims team)",
            "commit": commit,
            "build": build,
            "hotfix_push": hotfix,
            "store_inputs": "assets/db_inputs/spell_store_inputs.json (gzip JSON)",
            "field_semantics": "times in ms; an absent field = the store carries no row "
                              "for it (absence, never a reading; data-diff-70707.md §1); "
                              "v=1 marks ids with at least one value row; charges: the "
                              "70707 store has no charges column (data-diff-70707.md §1); "
                              "feeds (wave I-2b): periodMs = the smallest positive "
                              "Effects[].PeriodMs, targetCode = the Targets scalar "
                              "(client SpellEffectTargetingCategory code, 1 = the caster), "
                              "maxStack = AuraOptions.MaxStack above 1",
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
    args.out.write_text(text, encoding="utf-8")
    print(f"wrote {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

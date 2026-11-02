#!/usr/bin/env python3
"""Generate addon/Forte_<Class>/Data/<Class>.lua from mythicsim-forever-engine's spell data.

Source of truth for spell IDs/durations/cooldowns: the data checked out at
`../mythicsim-forever-engine/data/spells.jsonl` (a sibling clone, MIT-licensed,
pinned to a WoW Forever client build). This script never hand-types a spell ID;
re-run it after pulling a newer mythicsim-forever-engine checkout to pick up
Forever balance/rename changes (e.g. Curse of Agony -> Bane of Agony).

Rank resolution is **family-scoped with an uncoded fallback**: several spell
names exist in more than one class's row set in this build (set-bonus/mirror
rows share the name, e.g. "Circle of Healing" is Priest *and* Mage, "Rebuke" is
Rogue *and* Paladin, "Divine Protection" is Paladin *and* Priest). Candidate
rows are filtered to rows whose `ClassFlags.Family` equals the requested
class's family code (see CLASS_FAMILY; WoW Forever has no Death Knight class)
**before** a rank is picked, so a class's list can never resolve to a foreign
class's row. A **foreign-family row is never taken** -- if a listed name has
rows *only* in foreign families the generator prints an explicit gap line
"<name> resolves only to foreign class(es) ..." -- a data-integrity signal,
never a silent drop.

**Uncoded-family fallback** (2026-11-01, agent `DataWave`): many real class
spells carry no class family at all in this build -- their rows'
`ClassFlags.Family` is 0/absent (Scare Beast, Eagle Eye, Tame Beast, Call/
Dismiss/Feed Pet, Black Arrow, Far Sight; the Warlock stone-use family Use
Soulstone/Firestone/Spellstone). Resolution order is therefore:
in-family row carrying a window > uncoded row carrying a window >
in-family bare row > uncoded bare row > gap. Every name resolved by an uncoded
row is reported as an info line "<name> -> <id> (uncoded fallback)" so the
resolution is auditable, never silent.

**Companion-row shadows** (2026-11-01, agent `DataWave`): a *companion row* is a
trigger row whose only effect applies the real spell's aura (single Effect
Type=6, Aura=332, BasePoints = the real spell's ID) and which carries **no**
CooldownMs/CategoryCooldownMs/DurationMs of its own -- e.g. Summon Felguard
431754 mirrors 427733, Metamorphosis 403873 mirrors 403789, Immolation Aura
431757 mirrors 427726, Shadowflame 426454 mirrors 426320. Ranked on
level/ID alone such a bare row can outrank the real row (the real rows sit on
lower levels/IDs), which hid these spells from the class lists. Rank picking
therefore ranks by **(carries a window (cooldown or duration), carries a
cooldown, MaxLevel/SpellLevel, ID)**: rows carrying CooldownMs/
CategoryCooldownMs/DurationMs always beat bare companion rows; among carriers
the CD-carrier rule applies first (Forever-original spells put the cooldown on
the low hero row, e.g. Evocation 12051 has 480000 ms while the level-60 row
28763 carries none -- the max-ID/max-level row alone would emit an entry with
no cooldownMs), then the highest level, then the highest ID. Every name whose
pick changed from a bare row to a data-carrying row is reported as an info line
"<name> -> <id> (companion-row shadow: ...)".

Usage:
    python3 tools/gen_spell_data.py warlock
    python3 tools/gen_spell_data.py warlock --spells-jsonl /path/to/spells.jsonl
    python3 tools/gen_spell_data.py mage --dry    # resolve+report, writes NOTHING

`--dry` prints "N spells, M gaps" plus every gap line (and the resolved row for
the known cooldown-carrier sample names) and exits without touching addon/.

For each name in tools/spell_lists/<class>.json, the winning row ("current at
level 60" representative) is emitted to:

    addon/Forte_<Class>/Data/<Class>.lua

A name with no match in the source data is printed to stderr as a gap, never
silently dropped -- the Lua output only contains what was actually found.
"""
import argparse
import json
import pathlib
import sys
from datetime import datetime, timezone

HERE = pathlib.Path(__file__).resolve().parent
REPO_ROOT = HERE.parent
DEFAULT_SPELLS_JSONL = REPO_ROOT.parent / "mythicsim-forever-engine" / "data" / "spells.jsonl"
DEFAULT_MANIFEST = REPO_ROOT.parent / "mythicsim-forever-engine" / "data" / "manifest.json"

# ClassFamily codes as used in spells.jsonl ClassFlags.Family in the current
# Forever build. WoW Forever has no Death Knight class, so there is no entry
# (and no Forte_Deathknight addon). Codes 13+ in the data are non-class
# families (13 = consumables), never requested here.
CLASS_FAMILY: dict[str, int | None] = {
    "mage": 3,
    "warrior": 4,
    "warlock": 5,
    "priest": 6,
    "druid": 7,
    "rogue": 8,
    "hunter": 9,
    "paladin": 10,
    "shaman": 11,
}
FAMILY_NAMES = {code: name.capitalize() for name, code in CLASS_FAMILY.items() if code is not None}

# Names known to carry their cooldown on a lower rank row in this build;
# --dry prints the resolved row for each so the CD-carrier pick is verifiable.
CD_SAMPLE_NAMES = {
    "Avenging Wrath", "Judgement", "Shadowfiend", "Displacement",
    "Arcane Surge", "Shadow Word: Death", "Evocation",
}


def load_spells(jsonl_path: pathlib.Path) -> dict[str, list[dict]]:
    by_name: dict[str, list[dict]] = {}
    with open(jsonl_path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            row = json.loads(line)
            by_name.setdefault(row.get("Name", ""), []).append(row)
    return by_name


def row_family(row: dict) -> int | None:
    return (row.get("ClassFlags") or {}).get("Family")


def family_label(fam: int) -> str:
    return FAMILY_NAMES.get(fam, f"family{fam}")


def row_carries(row: dict) -> bool:
    """A row carries a real window: a (category) cooldown **or** a duration.

    A companion row -- the trigger whose sole Effect applies the real spell's
    aura (Type=6, Aura=332, BasePoints=<real spell ID>) -- carries none. The
    Effects list cannot disambiguate (every row in this build has >=1 effect
    entry), CooldownMs/CategoryCooldownMs/DurationMs can."""
    return bool(row.get("CooldownMs") or row.get("CategoryCooldownMs")
                or row.get("DurationMs"))


def pick_current_rank(rows: list[dict]) -> dict:
    """Rank by (carries a window, carries a cooldown, MaxLevel/SpellLevel, ID).

    Rows carrying CooldownMs/CategoryCooldownMs/DurationMs beat bare companion
    rows; among carriers the CD-carrier rule wins, then level, then ID."""
    def key(r: dict):
        has_cd = bool(r.get("CooldownMs") or r.get("CategoryCooldownMs"))
        level = r.get("MaxLevel") or r.get("SpellLevel") or 0
        return (row_carries(r), has_cd, level, r.get("ID", 0))
    return max(rows, key=key)


def pre_shadow_pick(rows: list[dict]) -> dict:
    """The rank rule before the companion-shadow fix: (carries a cooldown,
    MaxLevel/SpellLevel, ID). Kept only to detect/ report shadow resolutions."""
    def key(r: dict):
        has_cd = bool(r.get("CooldownMs") or r.get("CategoryCooldownMs"))
        level = r.get("MaxLevel") or r.get("SpellLevel") or 0
        return (has_cd, level, r.get("ID", 0))
    return max(rows, key=key)


def lua_escape(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"')


def emit_entry(row: dict) -> str:
    fields = [f'id = {row["ID"]}', f'name = "{lua_escape(row.get("Name",""))}"']
    if row.get("DurationMs"):
        fields.append(f'durationMs = {row["DurationMs"]}')
    cd = row.get("CooldownMs") or row.get("CategoryCooldownMs")
    if cd:
        fields.append(f'cooldownMs = {cd}')
    if row.get("CategoryCooldownMs") and row.get("Category"):
        fields.append(f'cooldownCategory = {row["Category"]}')
    if row.get("GCDMs"):
        fields.append(f'gcdMs = {row["GCDMs"]}')
    if row.get("CastTimeMs"):
        fields.append(f'castMs = {row["CastTimeMs"]}')
    if row.get("Rank"):
        fields.append(f'rank = "{lua_escape(row["Rank"])}"')
    return "{ " + ", ".join(fields) + " }"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("klass", help="class name, matching tools/spell_lists/<klass>.json")
    ap.add_argument("--spells-jsonl", type=pathlib.Path, default=DEFAULT_SPELLS_JSONL)
    ap.add_argument("--manifest", type=pathlib.Path, default=DEFAULT_MANIFEST)
    ap.add_argument("--dry", action="store_true",
                    help="resolve + report ('N spells, M gaps' + gap lines); write nothing")
    args = ap.parse_args()

    klass = args.klass.lower()
    if klass not in CLASS_FAMILY:
        print(f"unknown class {klass!r}; known: {', '.join(sorted(CLASS_FAMILY))}", file=sys.stderr)
        return 1

    list_path = HERE / "spell_lists" / f"{klass}.json"
    if not list_path.exists():
        print(f"no spell list at {list_path}", file=sys.stderr)
        return 1
    spec = json.loads(list_path.read_text())

    if not args.spells_jsonl.exists():
        print(f"spells.jsonl not found at {args.spells_jsonl} "
              f"(expected a sibling clone of mythicsim-forever-engine)", file=sys.stderr)
        return 1
    by_name = load_spells(args.spells_jsonl)

    family = CLASS_FAMILY[klass]
    if family is None:
        print(f"class {klass} not in this client build")

    build = "unknown"
    if args.manifest.exists():
        build = json.loads(args.manifest.read_text()).get("client_build", "unknown")

    groups: dict[str, list[tuple[str, dict]]] = {}
    gaps: list[str] = []
    fallbacks: list[str] = []  # names resolved onto uncoded (Family 0/absent) rows
    shadows: list[str] = []    # names whose pick moved from a bare companion to a data row

    def collect(group: str, names: list[str]):
        for n in names:
            rows = by_name.get(n)
            if not rows:
                gaps.append(f"{group}: {n!r} has no row in this build")
                continue
            if family is None:
                own, uncoded = rows, []
            else:
                own = [r for r in rows if row_family(r) == family]
                uncoded = [r for r in rows if not row_family(r)]  # Family 0 / absent
            # Resolution order: in-family row carrying a window > uncoded row
            # carrying a window (reported as an uncode fallback) > in-family
            # bare row > uncoded bare row (reported). Foreign-family rows are
            # never candidates; a name that resolves only to them is a gap.
            picked = None
            is_fallback = False
            own_carriers = [r for r in own if row_carries(r)]
            uncoded_carriers = [r for r in uncoded if row_carries(r)]
            if own_carriers:
                picked = pick_current_rank(own_carriers)
            elif uncoded_carriers:
                picked = pick_current_rank(uncoded_carriers)
                is_fallback = True
            elif own:  # all in-family rows are bare: the family row still wins
                picked = pick_current_rank(own)
            elif uncoded:
                picked = pick_current_rank(uncoded)
                is_fallback = True
            if picked is None:
                # Name exists only outside this class's family: report the
                # foreign families explicitly (data-integrity signal), never
                # silently drop.
                foreign = sorted({row_family(r) for r in rows} - {None, 0})
                if foreign:
                    gaps.append(f"{group}: {n!r} resolves only to foreign class(es) "
                                + ", ".join(family_label(f) for f in foreign))
                else:
                    gaps.append(f"{group}: {n!r} has rows with no class family in this build")
                continue
            if is_fallback:
                fallbacks.append(f"{n} -> {picked['ID']} (uncoded fallback)")
            elif own:
                prev = pre_shadow_pick(own)
                if not row_carries(prev) and row_carries(picked) and prev.get("ID") != picked.get("ID"):
                    shadows.append(f"{n} -> {picked['ID']} (companion-row shadow: bare "
                                   f"{prev.get('ID')} ranked above it on level/ID)")
            groups.setdefault(group, []).append((n, picked))

    for group, val in spec.items():
        if group.startswith("_"):
            continue
        if isinstance(val, list):
            collect(group, val)
        elif isinstance(val, dict):
            for subgroup, names in val.items():
                collect(f"{group}.{subgroup}", names)

    total = sum(len(v) for v in groups.values())

    if args.dry:
        print(f"dry {klass}: {total} spells, {len(gaps)} gaps (build {build})")
        for g in gaps:
            print(f"  gap: {g}", file=sys.stderr)
        for f in fallbacks:
            print(f"  info: {f}")
        for s in shadows:
            print(f"  info: {s}")
        for entries in groups.values():
            for name, row in entries:
                if name in CD_SAMPLE_NAMES:
                    print(f"  sample [{row['ID']}] {name}: {emit_entry(row)}")
        return 0

    class_title = klass.capitalize()
    out_dir = REPO_ROOT / "addon" / f"Forte_{class_title}" / "Data"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / f"{class_title}.lua"

    lines = []
    lines.append(f"-- GENERATED by tools/gen_spell_data.py -- do not hand-edit.")
    lines.append(f"-- Source: mythicsim-forever-engine/data/spells.jsonl, client_build {build}")
    lines.append(f"-- Regenerated: {datetime.now(timezone.utc).isoformat(timespec='seconds')}")
    if gaps:
        lines.append(f"-- {len(gaps)} name(s) in tools/spell_lists/{klass}.json were unresolved "
                      f"in this build (see generator stderr output):")
        for g in gaps:
            lines.append(f"--   {g}")
    lines.append("")
    lines.append("ForteXorcist = ForteXorcist or {}")
    lines.append("ForteXorcist.Data = ForteXorcist.Data or {}")
    lines.append(f"ForteXorcist.Data.{class_title} = {{")
    for group, entries in groups.items():
        lines.append(f"  -- {group}")
        for name, row in entries:
            lines.append(f"  [{row['ID']}] = {emit_entry(row)},")
    lines.append("}")
    lines.append("")
    # name -> id lookup, needed by the cast-predict pattern (a cast's spellID and the
    # buff/debuff it applies can differ by rank; CooldownMaster's _buffByName/_cooldownByName
    # solve this by matching on name instead of ID).
    lines.append(f"ForteXorcist.Data.{class_title}ByName = {{")
    for group, entries in groups.items():
        for name, row in entries:
            lines.append(f'  ["{lua_escape(name)}"] = {row["ID"]},')
    lines.append("}")
    lines.append("")

    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(f"wrote {out_path} ({total} spells, {len(gaps)} gaps, build {build})")
    for f in fallbacks:
        print(f"  info: {f}")
    for s in shadows:
        print(f"  info: {s}")
    if gaps:
        print(f"{len(gaps)} name(s) unresolved in this build's data:", file=sys.stderr)
        for g in gaps:
            print(f"  {g}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

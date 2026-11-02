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

**70707 overlay + trainer-rank pick** (2026-11-02, agent `DataRefresh`, D3):
the base rows stay the mythicsim 70425 pull; `tools/overrides_70707.json`
(check in; rebuilt from a wowsims/forever clone by `tools/extract_70707.py`)
carries the live 1.60.1.70707 store's per-id values. For the picked row the
overlay WINS on every field it captured (cooldownMs = max(CooldownMs,
CategoryCooldownMs) as in the store's own reading rule, gcdMs, castMs,
durationMs, cooldownCategory = Categories.Category, rank = Subtexts) --
absence from the overlay is coverage, not zero (data-diff-70707.md §1). An
id the census marks `removed` (the name has no row in the 70707 build-wide
Names table at all -- the 5 Paladin rows of §2.3 / G5) is DROPPED and listed
in the generated header; a tracked name whose mythicsim rows are all gone
re-lands on the 70707-only id of the same name when the store has one
(Blessing of Light 19979 -> bare 26650, values need the live probe).

The default rank is the top TRAINER rank: the 35 AQ20 class-book rank ids of
wowsims' `sim/core/spelldata/book_ranks.go` (carried in the overlay's
`bookRanks`) are excluded from the candidate pool before the pick -- "the
class books may not be there at launch, so nothing should need them by
default" (wowsims b6657d38; data-diff-70707.md §4). This re-picks 13 spells
(Revenge, Battle Shout, Immolate, Flame Shock, Aspect of the Hawk,
Rejuvenation, Feint, Strength of Earth, Grace of Air, Blessing of
Might/Wisdom, Greater Blessing of Might/Wisdom) from a book rank onto the
trainer rank the bookless level-60 default character knows. The same rule
drops holiday/variant rank rows (rank text that is neither `Rank N` nor a
known label like `Summon`) from the pool, which kills the Polymorph ->
"Odd Melon" pick hazard (§2.4).

Store-captured rows of a tracked name (the overlay's `nameIndex`) join the
same tier ladder: same-family store rows ride the in-family tier, family-less
store rows the uncoded tier, so new 70707 rank rows (Charge Rank 6 27685,
Cower Rank 6 16697) compete under the same rules. Pet-kit names that exist
ONLY in the 70707 store (the Warlock Succubus/Felhunter/Voidwalker kit,
forever-data-gaps.md G6: Seduction 6358, Spell Lock 19244, Devour Magic
19505, ... -- no row at all in the 70425 pull, so the family filter cannot
see them) are emitted FROM the overlay and reported as info lines
"<name> -> <id> (70707-sourced row ...)"; the generated header lists them.

`icdMs` (D2 G2, the strict join per Main's D3 review 2026-11-02): the
internal cooldown a proc/proc-like spell rides, from mythicsim `ICDMs`
rows and the store's `AuraOptions.ICDMs` (carried per id). A picked row
carries icdMs ONLY when (a) its own id captured ICDMs (paladin Rebuke
1302716's 60000, Seal of Command 20920's 1000, Shadowguard 19312's 3500), or
(b) a sibling RANK row of the same name carries them and the pair shares
the SAME family (Lightning Shield's 3500 over the family-11 rank rows;
Windfury Weapon 16361 over Rank 1 439431; Taste for Blood 426969 over
426953), or both rows are uncoded AND both are store-proc rows (captured
ProcFlags -- the overrides file's `procFlag`). The borrow NEVER rides a
row that is an active cast with a cooldown of its own: Rogue Rebuke
425609 (family 8, 15 s) does not borrow paladin family-10 1302716's
capture, and Divine Protection 5573 (300 s) does not borrow uncoded
27778's -- the pre-review name+family max-borrow lit both. Emitted as
`icdMs` when non-zero. F15/F16 size trinket/proc windows from it.

Usage:
    python3 tools/gen_spell_data.py warlock
    python3 tools/gen_spell_data.py warlock --spells-jsonl /path/to/spells.jsonl
    python3 tools/gen_spell_data.py mage --dry    # resolve+report, writes NOTHING
    python3 tools/gen_spell_data.py druid --no-overlays   # pure 70425 run (debug)

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
import re
import sys
from datetime import datetime, timezone

HERE = pathlib.Path(__file__).resolve().parent
REPO_ROOT = HERE.parent
DEFAULT_SPELLS_JSONL = REPO_ROOT.parent / "mythicsim-forever-engine" / "data" / "spells.jsonl"
DEFAULT_MANIFEST = REPO_ROOT.parent / "mythicsim-forever-engine" / "data" / "manifest.json"
# The checked-in 70707 overlay (tools/extract_70707.py output; wowsims/forever,
# MIT). Absent file = pure 70425 run, with the header saying so.
DEFAULT_OVERRIDES = HERE / "overrides_70707.json"

# Rank texts that are ranks, not skins: `Rank N` plus the known unnumbered
# labels the store uses. Anything else ("Odd Melon", "Racial") is a
# variant/holiday rank row and stays out of the 70707 rank pool
# (data-diff-70707.md §2.4/§4: the Polymorph -> "Odd Melon" pick hazard).
RANK_LABEL_RE = re.compile(r"^Rank \d+$")
KNOWN_RANK_LABELS = {"Summon"}

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


def load_overrides(path: pathlib.Path) -> dict | None:
    """tools/overrides_70707.json with numeric ids, or None (pure 70425 run)."""
    if not path.exists():
        return None
    raw = json.loads(path.read_text(encoding="utf-8"))
    return {
        "meta": raw["_meta"],
        "book": set(raw["bookRanks"]),
        "removed": {int(k): v for k, v in raw["removed"].items()},
        "spells": {int(k): v for k, v in raw["spells"].items()},
        "names": raw["nameIndex"],
    }


def is_variant_rank(subtext: str | None) -> bool:
    """A rank text that is a skin, not a rank (Odd Melon, Racial, ...)."""
    if not subtext:
        return False
    return not RANK_LABEL_RE.match(subtext) and subtext not in KNOWN_RANK_LABELS


def overlay_rows(ov: dict, name: str, family: int | None,
                 pool_empty: bool = False) -> list[dict]:
    """The 70707 store rows of a tracked name as mythicsim-shaped rows.

    Rows the store codes to a FOREIGN family are excluded (same law as for
    mythicsim rows); same-family and family-less rows join the in-family
    rank pool (data-diff-70707.md §2: the store rows without a ClassOptions
    row count as Family 0, the generator's own fallback code -- the Charge
    Rank 6 row 27685 is one). Variant rank texts stay out (§2.4).

    An **index shell** -- a store row capturing no window at all (no
    cooldown, duration, gcd, cast, category, ICD, rank text) -- rides the
    pool ONLY when the mythicsim pull left the name with no other
    candidate (the 70707-sourced rows: Blessing of Light 26650, Mesmerize
    24594). A shell is the build's index placeholder for the id, not a
    playable row: the Dispel Magic 16908 shell (no family, no cast data,
    name + level only) must not out-rank the family-6 cast line it indexes
    (988, the priest row the live game casts) -- D3 review, Main 2026-11-02."""
    out = []
    for sid in ov["names"].get(name, []):
        row = ov["spells"].get(sid)
        if row is None:
            continue
        if sid in ov["book"]:  # AQ20 book rank: out of the default pool,
            continue           # the same rule as for the mythicsim rows
        fam = row.get("family")
        if family is not None and fam not in (None, 0, family):
            continue
        if is_variant_rank(row.get("subtext")):
            continue
        if not pool_empty and not any(
                row.get(key) for key in ("durationMs", "cooldownMs",
                                         "categoryCooldownMs", "gcdMs",
                                         "castMs", "category", "icdMs")) \
                and not row.get("subtext"):
            continue  # the index-shell law above (captured zeros are the
                      # store confirming NO window: 16908 is all-zero)
        out.append({
            "ID": sid,
            "Name": row.get("name", name),
            "Rank": row.get("subtext"),
            "DurationMs": row.get("durationMs"),
            "CooldownMs": row.get("cooldownMs"),
            "CategoryCooldownMs": row.get("categoryCooldownMs"),
            "GCDMs": row.get("gcdMs"),
            "CastTimeMs": row.get("castMs"),
            "Category": row.get("category"),
            "ICDMs": row.get("icdMs"),
            "SpellLevel": row.get("spellLevel"),
            "MaxLevel": row.get("maxLevel"),
            "_fam": fam,
            "_store": True,
        })
    return out


def _icd_fam(row: dict) -> int | None:
    """The family a row rides: the store's own ClassOptions code for store
    rows, the mythicsim ClassFlags for pull rows."""
    return row.get("_fam") if row.get("_store") else row_family(row)


def _own_icd(row: dict) -> int:
    return row.get("ICDMs") or 0


def _is_cast(row: dict) -> bool:
    """A row the player casts on a shared cooldown: its own (category)
    cooldown. Passive proc auras ride no cooldown of their own."""
    return bool(row.get("CooldownMs") or row.get("CategoryCooldownMs"))


def _is_proc(row: dict, ov: dict | None) -> bool:
    """The build's word that a row is a proc-carrying aura: the store's
    AuraOptions.ProcFlags (captured as procFlag). Mythicsim rows carry no
    proc flag: the uncoded-pair branch never fires for them."""
    if not row.get("_store") or ov is None:
        return False
    return bool((ov["spells"].get(row.get("ID")) or {}).get("procFlag"))


def spell_icd(picked: dict, merged: dict, ov: dict | None,
              siblings: list[dict]) -> int:
    """The strict ICD join (Main's 2026-11-02 ruling on the D3 review).

    A spell row carries icdMs only when
      (a) its own id captured AuraOptions ICDMs, or
      (b) a sibling RANK row of the same spell line carries them and the
          pair shares the SAME family, or BOTH rows are uncoded AND both
          are proc rows (store procFlag on both).
    The borrow NEVER rides a row that is an active cast with a cooldown of
    its own -- the live rows that make the law:
      Rogue Rebuke 425609 (family 8, 15 s cast) must NOT ride paladin
      Rebuke 1302716's proc ICD (family 10) -- cross-family;
      paladin Divine Protection 5573 (300 s cast) must NOT ride uncoded
      27778 (a separate proc-carrying aura, ProcFlags 139944) -- active
      cast + cross-family;
      paladin Rebuke 1302716 keeps its OWN captured 60000 (its own
      AuraOptions ICDMs) -- branch (a)."""
    own = _own_icd(picked)
    if own == 0 and ov is not None:
        own = (ov["spells"].get(picked.get("ID")) or {}).get("icdMs") or 0
    if own:
        return own
    if _is_cast(merged):  # the active-cast guard
        return 0
    fam = _icd_fam(picked)
    best = 0
    for s in siblings:
        if s.get("ID") == picked.get("ID"):
            continue
        icd = _own_icd(s)
        if icd == 0 and ov is not None and s.get("_store"):
            icd = (ov["spells"].get(s.get("ID")) or {}).get("icdMs") or 0
        if not icd:
            continue
        sfam = _icd_fam(s)
        same_family = fam is not None and fam != 0 and sfam == fam
        uncoded_pair = (fam in (None, 0) and sfam in (None, 0)
                        and _is_proc(picked, ov) and _is_proc(s, ov))
        if same_family or uncoded_pair:
            best = max(best, icd)
    return best


def overlay_apply(row: dict, ov: dict | None) -> dict:
    """Return the row with 70707 captured values overlaid (value precedence
    70707). A captured field wins even when 0 (Swift Judgement durationMs
    -1 -> 0); the store's cooldown is folded to max(CooldownMs,
    CategoryCooldownMs) (reading-by-hand.md). Rows the store carries
    name-only (no value rows) keep the 70425 values (absence, not zero).
    `_cat_any` marks rows whose Categories row was captured: their
    cooldownCategory rides Categories.Category alone (Intimidation 1132
    rides CategoryCooldownMs 0 -- data-diff-70707.md §2.1)."""
    out = dict(row)
    out.setdefault("_cat_any", bool(out.get("_store")))
    if ov is None or out.get("_store"):
        return out
    srow = ov["spells"].get(out.get("ID"))
    if not srow or not srow.get("v"):
        return out
    cd, catcd = srow.get("cooldownMs"), srow.get("categoryCooldownMs")
    if cd is not None or catcd is not None:
        out["CooldownMs"] = max(cd or 0, catcd or 0)
        out["CategoryCooldownMs"] = None
    for key_in, key_out in (("durationMs", "DurationMs"), ("gcdMs", "GCDMs"),
                            ("castMs", "CastTimeMs"), ("category", "Category")):
        if key_in in srow:
            out[key_out] = srow[key_in]
    if srow.get("subtext"):
        out["Rank"] = srow["subtext"]
    out["_cat_any"] = True
    return out


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


def pick_current_rank(rows: list[dict], cast_aware: bool = False) -> dict:
    """Rank by (carries a window, carries a cooldown, MaxLevel/SpellLevel,
    [casts on a cast time], ID).

    Rows carrying CooldownMs/CategoryCooldownMs/DurationMs beat bare companion
    rows; among carriers the CD-carrier rule wins, then level, then -- with
    cast_aware (the overlay run) -- rows that CAPTURE a cast time: a summon
    line's real cast row (Summon Felhunter 691: fam 5, 10 s cast, permanent)
    outranks an equal-level family-less no-cast shell (8176: 10-minute
    duration, no family -- the D3 review pick), then ID."""
    def key(r: dict):
        has_cd = bool(r.get("CooldownMs") or r.get("CategoryCooldownMs"))
        level = r.get("MaxLevel") or r.get("SpellLevel") or 0
        has_cast = bool(r.get("CastTimeMs")) if cast_aware else False
        return (row_carries(r), has_cd, level, has_cast, r.get("ID", 0))
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


def emit_entry(row: dict, icd: int = 0) -> str:
    fields = [f'id = {row["ID"]}', f'name = "{lua_escape(row.get("Name",""))}"']
    if row.get("DurationMs"):
        fields.append(f'durationMs = {row["DurationMs"]}')
    cd = row.get("CooldownMs") or row.get("CategoryCooldownMs")
    if cd:
        fields.append(f'cooldownMs = {cd}')
    if row.get("_cat_any"):
        # The 70707 Categories row was captured: the shared-category id
        # rides Categories.Category, with or without a CategoryCooldownMs
        # of its own (Intimidation 1132, Healthstone 30).
        if row.get("Category"):
            fields.append(f'cooldownCategory = {row["Category"]}')
    elif row.get("CategoryCooldownMs") and row.get("Category"):
        fields.append(f'cooldownCategory = {row["Category"]}')
    if row.get("GCDMs"):
        fields.append(f'gcdMs = {row["GCDMs"]}')
    if row.get("CastTimeMs"):
        fields.append(f'castMs = {row["CastTimeMs"]}')
    if icd:
        fields.append(f'icdMs = {icd}')
    if row.get("Rank"):
        fields.append(f'rank = "{lua_escape(row["Rank"])}"')
    return "{ " + ", ".join(fields) + " }"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("klass", help="class name, matching tools/spell_lists/<klass>.json")
    ap.add_argument("--spells-jsonl", type=pathlib.Path, default=DEFAULT_SPELLS_JSONL)
    ap.add_argument("--manifest", type=pathlib.Path, default=DEFAULT_MANIFEST)
    ap.add_argument("--overrides", type=pathlib.Path, default=DEFAULT_OVERRIDES,
                    help="the checked-in 70707 overlay (tools/extract_70707.py)")
    ap.add_argument("--no-overlays", action="store_true",
                    help="pure 70425 run: ignore the 70707 overlay (debug)")
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

    ov = None if args.no_overlays else load_overrides(args.overrides)

    groups: dict[str, list[tuple[str, dict, int]]] = {}
    gaps: list[str] = []
    fallbacks: list[str] = []  # names resolved onto uncoded (Family 0/absent) rows
    shadows: list[str] = []    # names whose pick moved from a bare companion to a data row
    changes: list[str] = []    # per-name emitted-row diffs vs the pure-70425 baseline
    removed_report: list[str] = []  # rows dropped because 70707 removed the id
    sourced: list[str] = []    # rows with no 70425 base (70707-sourced, pet kit)

    def rank_pick(rows_in: list[dict], store_aware: bool):
        """The tier ladder: in-family carrier > uncoded carrier (fallback) >
        in-family bare > uncoded bare. With store_aware, 70707 rows carry the
        family law on the store's own code: a family-less store row rides the
        in-family pool (it is the build's capture of THIS name, not a foreign
        twin -- the Charge Rank 6 row 27685 has no ClassOptions row)."""
        def own_pred(r: dict) -> bool:
            fam = row_family(r)
            if store_aware and r.get("_store") and not fam:
                return True
            return family is not None and fam == family
        if family is None:
            own, uncoded = list(rows_in), []
        else:
            own = [r for r in rows_in if own_pred(r)]
            uncoded = [r for r in rows_in
                       if not own_pred(r) and not row_family(r)]  # Family 0 / absent
        own_carriers = [r for r in own if row_carries(r)]
        uncoded_carriers = [r for r in uncoded if row_carries(r)]
        if own_carriers:
            return pick_current_rank(own_carriers, store_aware), False
        if uncoded_carriers:
            return pick_current_rank(uncoded_carriers, store_aware), True
        if own:  # all in-family rows are bare: the family row still wins
            return pick_current_rank(own, store_aware), False
        if uncoded:
            return pick_current_rank(uncoded, store_aware), True
        return None, False

    def collect(group: str, names: list[str]):
        for n in names:
            rows = by_name.get(n) or []
            book = ov["book"] if ov is not None else set()
            removed_ids = ov["removed"] if ov is not None else {}
            removed_here = [r for r in rows if r.get("ID") in removed_ids]
            pool = [r for r in rows
                    if r.get("ID") not in book and r.get("ID") not in removed_ids]
            ov_rows = (overlay_rows(ov, n, family, pool_empty=not pool)
                       if ov is not None else [])
            # Baseline: the row the pre-70707 pipeline emitted (pure mythicsim,
            # no book/removed filter, no overlay) -- the header change list is
            # the diff of the final row against this.
            base, _ = rank_pick(rows, store_aware=False)
            base_text = emit_entry(base) if base is not None else None

            picked, is_fallback = rank_pick(pool + ov_rows, store_aware=True)
            if picked is None:
                if removed_here:
                    # The name is gone from the 70707 build: reported once as
                    # removed, never as a family/coverage gap.
                    ids_s = ", ".join(str(r.get("ID")) for r in removed_here)
                    removed_report.append(
                        f"{n}: id(s) {ids_s} removed on 70707 -- the name is gone "
                        f"from the build's Names table, row dropped")
                    continue
                if not rows:
                    gaps.append(f"{group}: {n!r} has no row in this build")
                    continue
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
            if removed_here:  # the name survived on a 70707-only id (Blessing of Light)
                ids_s = ", ".join(str(r.get("ID")) for r in removed_here)
                note = "" if (ov["spells"].get(picked.get("ID")) or {}).get("v") \
                    else " -- no captured 70707 values, live probe needed"
                removed_report.append(
                    f"{n}: id(s) {ids_s} removed on 70707 -> re-picked {picked.get('ID')}"
                    f"{note}")
            if is_fallback:
                fallbacks.append(f"{n} -> {picked['ID']} (uncoded fallback)")
            elif not picked.get("_store"):
                own_myth = [r for r in pool
                            if family is None or row_family(r) == family]
                if own_myth:
                    prev = pre_shadow_pick(own_myth)
                    if not row_carries(prev) and row_carries(picked) and prev.get("ID") != picked.get("ID"):
                        shadows.append(f"{n} -> {picked['ID']} (companion-row shadow: bare "
                                       f"{prev.get('ID')} ranked above it on level/ID)")
            out_row = overlay_apply(picked, ov)
            icd = spell_icd(picked, out_row, ov, rows + ov_rows)
            if base_text is None:
                sourced.append(f"{n} ({picked['ID']})")
            else:
                entry = emit_entry(out_row, icd)
                if entry != base_text:
                    changes.append(f"{n}: {base_text} -> {entry}")
            groups.setdefault(group, []).append((n, out_row, icd))

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
        print(f"dry {klass}: {total} spells, {len(gaps)} gaps (build {build}"
              + (f" + overlay {ov['meta']['build']})" if ov is not None else ")") + ")")
        for g in gaps:
            print(f"  gap: {g}", file=sys.stderr)
        for f in fallbacks:
            print(f"  info: {f}")
        for s in shadows:
            print(f"  info: {s}")
        for c in changes:
            print(f"  70707: {c}")
        for r in removed_report:
            print(f"  removed: {r}")
        for s in sourced:
            print(f"  70707-sourced: {s}")
        for entries in groups.values():
            for name, row, icd in entries:
                if name in CD_SAMPLE_NAMES:
                    print(f"  sample [{row['ID']}] {name}: {emit_entry(row, icd)}")
        return 0

    class_title = klass.capitalize()
    out_dir = REPO_ROOT / "addon" / f"Forte_{class_title}" / "Data"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / f"{class_title}.lua"

    lines = []
    lines.append(f"-- GENERATED by tools/gen_spell_data.py -- do not hand-edit.")
    lines.append(f"-- Source: mythicsim-forever-engine/data/spells.jsonl, client_build {build}")
    if ov is not None:
        m = ov["meta"]
        lines.append(f"-- Overlay: wowsims/forever {m['commit']} build {m['build']} (MIT)")
        lines.append(f"--   (hotfix push {m['hotfix_push']}; {m['store_inputs']}; built by "
                      f"tools/extract_70707.py -- 70707 values win; absent fields = the store "
                      f"carries no row, mythicsim stands)")
    else:
        lines.append("-- Overlay: NONE (tools/overrides_70707.json missing) -- values are pure "
                      f"{build}")
    lines.append(f"-- Regenerated: {datetime.now(timezone.utc).isoformat(timespec='seconds')}")
    if changes:
        lines.append(f"-- 70707 overlay changes in this file ({len(changes)}):")
        for c in changes:
            lines.append(f"--   {c}")
    if removed_report:
        lines.append(f"-- Rows dropped on 70707 ({len(removed_report)}):")
        for r in removed_report:
            lines.append(f"--   {r}")
    if sourced:
        lines.append(f"-- 70707-sourced rows: no row in the {build} pull, the row is the "
                      f"70707 store's capture of the name ({len(sourced)}; Warlock pet kit, "
                      f"docs/research/forever-data-gaps.md G6):")
        for s in sourced:
            lines.append(f"--   {s}")
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
        for name, row, icd in entries:
            lines.append(f"  [{row['ID']}] = {emit_entry(row, icd)},")
    lines.append("}")
    lines.append("")
    # name -> id lookup, needed by the cast-predict pattern (a cast's spellID and the
    # buff/debuff it applies can differ by rank; CooldownMaster's _buffByName/_cooldownByName
    # solve this by matching on name instead of ID).
    lines.append(f"ForteXorcist.Data.{class_title}ByName = {{")
    for group, entries in groups.items():
        for name, row, _icd in entries:
            lines.append(f'  ["{lua_escape(name)}"] = {row["ID"]},')
    lines.append("}")
    lines.append("")

    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(f"wrote {out_path} ({total} spells, {len(gaps)} gaps, build {build}"
          + (f", overlay {ov['meta']['build']}: {len(changes)} changed, "
             f"{len(removed_report)} removed-rows, {len(sourced)} sourced)"
             if ov is not None else ")"))
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

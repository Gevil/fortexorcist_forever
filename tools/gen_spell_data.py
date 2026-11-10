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

**Rank law: store coverage beats a value-less top** (wave I-2b,
2026-11-03, upstream-data §7.7): when the live store covers a tracked name
(its `Names` table has rows for it), the pick key carries a
`store-coverage` leg ABOVE the id tiebreak: a candidate the store covers
with a value row or a Levels capture outranks a candidate the store names
value-less. The hazard this kills: Primal Bite shipped Rank 4 (`1238073`,
value-less in the live store -- the 2026-11-03 notes reduce the ladder to 3
ranks) while the store's ranked top is Rank 3 (`1238070`, L60, the 6 s
category 971) -- the same shape as the `Polymorph` -> "Odd Melon" hazard of
data-diff-70707.md §2.4, now closed for the value-less-top family.

**Post-9 dev-notes overrides** (wave I-2b): `tools/overrides_devnotes_2026-11-
03.json` (hand-kept, every row cites the 2026-11-03 Blizzard development
notes, post 9) carries the few values NO data source has captured yet (Slam
cooldown 15 s, Stormstrike 6 s, Riptide 12 s, Orc Blood Fury 120 s). The
generator applies it AFTER the live-store overlay (a post-9 note is fresher
than an older store capture); the file's name and every applied row are
listed in the generated header. It is a pin, not a hand edit: the generated
file stays a pure function of (spell lists + base data + the two overlay
files), so `scripts/gate.py`'s determinism law stands. Delete a row the day
a store capture carries the value (hotfix-watch, upstream-data §7 item 6;
wave M5 2026-11-07 retired the nine Slam/Stormstrike/Riptide rows the
1.60.1.70790 capture absorbed -- only the Blood Fury pin outlives it,
docs/research/data-diff-live-2026-11-07.md §6).

**Rename aliases** (wave I-2b): a spell-list file may carry `_renames` =
{data name: the build's other spelling} (Totemic Projection <-> Totemic
Call, Elemental Mastery <-> Lightning Mastery, dev notes post 9). The
generator resolves the DATA name only and adds the alias spelling as an
extra `ByName` key (both spellings find the same row); the runtime twin of
the pair list is `Forte_Core/Core/Locale.lua`'s `Locale.RenameAliases`,
which folds the alias through `CanonicalName` for name-keyed consumers.

**Pinned picks, shared cooldowns and the racials group** (wave M3a,
2026-11-07, review-10 M2/m4 + docs/research/data-diff-live-2026-11-07.md §5.2):
a spell-list file may carry two more meta keys next to `_renames`.
`_pins` = {data name: {"id": N, "reason": "..."} } forces the picked row to
the store/base row of that id — the rank ladder stands for every other
name, and every pin rides its cited reason into the generated header
("Pinned picks"). The mechanism exists for the measured pick hazards the
ladder cannot see: the Mage `Arcane Blast` pin to the 18 s self-buff
`400573` (the live ladder carries NO cooldown at all; the only cooldown-
carrying row of the name, mythicsim's weapon-proc row 18091, is the item
proc the `Archeus` row already rides in Forte_ItemProcs — the Arcane Blast
bar was a fake 8 s window; docs/research/data-diff-live-2026-11-07.md §5.2),
and the `Berserking` pin to `20554` (all four store rows are value-less
shells, so the bare-row tiebreak would ride the arbitrary max-id shell;
20554 is the id the owner measured 180 s against on the live client).
`_shares` = {name: the partner data name} emits `shares = "partner"` on the
row: the runtime twin is `Forte_Cooldown/Core/Engine.lua`'s OnCast partner
walk — a cast of either starts both bars (Summon Hawk ↔ Arcane Shot, the
store's shared category 1173 with the 6 s CategoryCooldownMs). A top-level
group named `racials` marks its rows with `racial = true`: they ride the
same family/rank law as every class row (so Locale's alias walk covers their
names on every client), and `Engine:Build` SKIPS them while
`Engine:AddExtras` tracks them — the generated twin of the hand-kept
`Engine.RACIALS` the review flagged (M2: English keys break the deDE path;
m4: ids bypassing the generator bypass the refresh).

**Feed overrides** (2026-11-10, docs/research/live-paladin-2026-11-09.md §1.1):
a spell-list file may carry `_feeds` = {data name: {"noTarget": bool,
"reason": "..."}}. It forces the row's `noTarget` feed for the few
store-sourced rows whose captured shape cannot speak (no base `Effects`;
the overlay's `Targets` scalar says "caster" for the ally-cast Oath of
Light and says nothing for the caster-side Echoes / Shieldsworn). Applied
after `row_feeds`; every forced row rides the generated header
("Feed overrides"). Only `noTarget` is overridable.

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

**Live-store overlay + trainer-rank pick** (2026-11-02, agent `DataRefresh`,
D3; the live pin refreshed to 1.60.1.70790 by wave M5, 2026-11-07): the base
rows stay the mythicsim 70425 pull; `LIVE_OVERLAY`
(`tools/overrides_<build>.json`; check in; rebuilt from a wowsims/forever
clone by `tools/extract_store.py --build <stamp>`) carries the live store's
per-id values. For the picked row the
overlay WINS on every field it captured (cooldownMs = max(CooldownMs,
CategoryCooldownMs) as in the store's own reading rule, gcdMs, castMs,
durationMs, cooldownCategory = Categories.Category, rank = Subtexts) --
absence from the overlay is coverage, not zero (data-diff-70707.md §1). An
id the census marks `removed` (the name has no row in the store's build-wide
Names table at all -- the 5 Paladin rows of §2.3 / G5) is DROPPED and listed
in the generated header; a tracked name whose mythicsim rows are all gone
re-lands on the store-only id of the same name when the store has one
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
store rows the uncoded tier, so new live-build rank rows (Charge Rank 6 27685,
Cower Rank 6 16697; the 70790 capture adds Shank Rank 1/2 1329283/1329549)
compete under the same rules. Pet-kit names that exist
ONLY in the live store (the Warlock Succubus/Felhunter/Voidwalker kit,
forever-data-gaps.md G6: Seduction 6358, Spell Lock 19244, Devour Magic
19505, ... -- no row at all in the 70425 pull, so the family filter cannot
see them) are emitted FROM the overlay and reported as info lines
"<name> -> <id> (store-sourced row ...)"; the generated header lists them.

**The Spell Timer's feed columns** (2026-11-03, agent `Feeds`, wave 4; the
four data fields docs/design-spell-timer.md §3.4 asks for, of which the Timer
reads three today -- `Registry:Build`):

* `tickEvery` -- SECONDS, the period of the row's periodic effect: the
  smallest positive `Effects[].PeriodMs` in the base row divided by 1000. A
  DoT/HoT/channel rows on a periodic aura carries it (Corruption 172 and
  Serpent Sting 1978: `PeriodMs` 3000 -> `tickEvery = 3`); the Timer's tick
  marks are spaced by it (`Forte_Timer/UI/Rows.lua`'s `row.tickEvery` branch,
  delta D6). The smallest, not the first: a row can carry a periodic damage
  effect and a periodic heal, and the marks show the fastest cadence the
  player sees.
* `maxStack` -- the aura's stack cap, emitted only when it is above 1 (a
  cap of 1 says "no stacking", which the absence already says): Sunder
  Armor 7386's 5, Deadly Poison 2818's 5, Scorpid Poison 24583's 5, Lacerate
  414644's 5. The `Stacks` cap the row draws (design §3.4). **The live
  store's cap wins over the base row's** (2026-11-10, the LIVE-WINS law,
  `row_feeds`): the base `MaxStack` is the frozen 70425 value, the store's
  `AuraOptions.MaxStack` (captured above 1) is the live one -- Paladin
  Vengeance 20050 is 3 in the base pull and 5 live (Nov 3 notes).
* `noTarget` -- `true` when EVERY effect of the row lands on the caster: the
  effect `Target` pair's first code is `1` (the client's
  `SpellEffectTargetingCategory` code of the caster: Fade 586 / Inner Fire
  588 / Divine Protection 498 / Dash 1850 / Defensive Stance 71 all ride
  `[1, 0]`, while a window on the used target rides `[6, 0]` (Corruption), a
  party-wide one `[21, 0]` (Mark of the Wild, Blessing of Might) and a
  raid/battleground one `[22, 15]`/`[87, 16]`). The original's
  `Track[spell][1] == 1` column (`notTarget`, Forte_Timer.lua:606-617): such a
  cast is exactly ONE row (design §3.3's targetKey "none"), so a window with
  any non-caster effect -- and a row with no captured effect at all -- is
  never marked (absence is not evidence).

**These feeds ride the BASE rows and the live store's feed captures** (wave
I-2b, 2026-11-03, upstream-data note §7.5; was "base-data-only" through wave
4): the live-store overlay captures per id `periodMs` (smallest positive
`Effects[].PeriodMs`), `targetCode` (the `Targets` scalar, the client
SpellEffectTargetingCategory code, 1 = the caster) and `maxStack`
(`AuraOptions.MaxStack` above 1). A row that HAS captured base `Effects`
answers for itself (the base data stays authoritative for its own shape);
the store captures fill the fields the picked row cannot speak to, and a
store-picked row (a store-rank pick like Primal Bite 1238070, a store-sourced
row like Oath of Light 1328548) also inherits the same-id base row's feed
shape -- that is what stops a store pick from dropping a feed (the five drops
measured in upstream-data §2.2: Dash, Pounce Bleed, Reckoning, Dismantle,
Heroism). **Rank-sibling inheritance** (wave M3a): when a store-picked row
has NO base row of its own id (the store's Rank-4 capture of a name the
70425 pull knows only at lower ranks -- Holy Shield 1239570, the
data-diff-live §3 re-pick), the base feed shape is inherited from the name's
base row in the SAME class family (Holy Shield 20928's caster-Target shape,
the `[1, 0]` pair, carries the `noTarget` flag across the rank move); a
family-less store row inherits nothing (no family evidence, absence is not
evidence). The generated header states the law per file.

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
# THE LIVE STORE OVERLAY -- the one place the newest checked-in capture is
# named (gen_item_data.py imports this constant, so a refresh points both
# generators at once). Built by `tools/extract_store.py --build <stamp>` from
# the pinned wowsims/forever clone (MIT); the file is named by the build stamp
# the store itself carries, so a refresh = run the extractor, point this one
# line at its output, regenerate. Absent file = pure 70425 run, header says so.
# History: 1.60.1.70707 (waves 2a..I-2b, tools/overrides_70707.json, still
# checked in as the record of that pin), 1.60.1.70790 (wave M5, 2026-11-07,
# tools/overrides_70790.json, kept as history), 1.60.1.70862 (2026-11-10).
LIVE_OVERLAY = HERE / "overrides_70888.json"
DEFAULT_OVERRIDES = LIVE_OVERLAY
# The post-9 dev-notes layer (hand-kept, wave I-2b): the values NO captured
# data source carries yet, applied after the live-store layer. A row is
# retired the day the live store carries its value (the file's HOTFIX-WATCH
# law; the retirement report is docs/research/data-diff-live-2026-11-07.md §6).
# Absent file = the layer is out, with the header saying so.
DEFAULT_DEVNOTES = HERE / "overrides_devnotes_2026-11-03.json"

# Rank texts that are ranks, not skins: `Rank N` plus the known unnumbered
# labels the store uses. Anything else ("Odd Melon", "Racial") is a
# variant/holiday rank row and stays out of the live store's rank pool
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

# The first number of an effect row's `Target` pair is the client's
# `SpellEffectTargetingCategory` code of the unit the effect lands on; 1 is
# THE CASTER (see the docstring: Fade 586, Inner Fire 588, Dash 1850, Defensive
# Stance 71 all ride `[1, 0]`, a window on the used target `[6, 0]`, a
# party-wide one `[21, 0]`). Only used for the `noTarget` feed.
CASTER_TARGET_CODE = 1

# Names known to carry their cooldown on a lower rank row in this build;
# --dry prints the resolved row for each so the CD-carrier pick is verifiable.
CD_SAMPLE_NAMES = {
    "Avenging Wrath", "Judgement", "Shadowfiend", "Displacement",
    "Arcane Surge", "Shadow Word: Death", "Evocation",
}


def load_overrides(path: pathlib.Path) -> dict | None:
    """A checked-in live-store overlay (`tools/overrides_<build>.json`) with
    numeric ids, or None (pure 70425 run)."""
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


def overlay_label(ov: dict) -> str:
    """The short build stamp of the overlay the run uses (`1.60.1.70790` ->
    `70790`): every build word in the generated header rides it, so the file
    names the capture it was built from and nothing here is welded to one
    build (wave M5)."""
    return str(ov["meta"]["build"]).rsplit(".", 1)[-1]


def load_devnotes(path: pathlib.Path) -> dict | None:
    """tools/overrides_devnotes_2026-11-03.json with numeric ids, or None."""
    if not path.exists():
        return None
    raw = json.loads(path.read_text(encoding="utf-8"))
    return {
        "meta": raw["_meta"],
        "file": path.name,
        "spells": {int(k): v for k, v in raw["spells"].items()},
    }


# The dev-notes fields the layer may set, mapped to the row field they win.
_DEVNOTES_FIELDS = {
    "cooldownMs": "CooldownMs", "categoryCooldownMs": "CategoryCooldownMs",
    "gcdMs": "GCDMs", "castMs": "CastTimeMs", "durationMs": "DurationMs",
    "category": "Category",
}


def devnotes_apply(row: dict, dn: dict | None) -> tuple[dict, list[str]]:
    """Apply the post-9 dev-notes values AFTER the 70707 layer (the notes
    are a 2026-11-03 delta the store capture has not absorbed; upstream-data
    §5). A cooldown field folds like the overlay's reading rule: the pair's
    max is the cooldown. Returns (row, applied-descriptions)."""
    if dn is None:
        return row, []
    drow = dn["spells"].get(row.get("ID"))
    if not drow:
        return row, []
    out = dict(row)
    applied: list[str] = []
    cd, catcd = drow.get("cooldownMs"), drow.get("categoryCooldownMs")
    if cd is not None or catcd is not None:
        old = out.get("CooldownMs") or out.get("CategoryCooldownMs")
        out["CooldownMs"] = max(cd or 0, catcd or 0)
        out["CategoryCooldownMs"] = None
        applied.append(f"cooldownMs {old} -> {out['CooldownMs']}")
    for key_in, key_out in ((k, v) for k, v in _DEVNOTES_FIELDS.items()
                            if k not in ("cooldownMs", "categoryCooldownMs")):
        if key_in in drow:
            applied.append(f"{key_in} {out.get(key_out)} -> {drow[key_in]}")
            out[key_out] = drow[key_in]
    return out, applied


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
            # The store's own feed captures (I-2b, §7.5): a store row carries
            # the shape the store saw, and row_feeds reads them when the row
            # has no base Effects to answer from.
            "_periodMs": row.get("periodMs"),
            "_maxStack": row.get("maxStack"),
            "_targetCode": row.get("targetCode"),
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
    # Feed captures ride the merged row (I-2b, §7.5): they are the store's
    # word on the periodic/target/stack SHAPE, read only by row_feeds and
    # only where the row's own base Effects can not answer.
    for feed_in, feed_out in (("periodMs", "_periodMs"), ("maxStack", "_maxStack"),
                              ("targetCode", "_targetCode")):
        if feed_in in srow:
            out[feed_out] = srow[feed_in]
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


def pick_current_rank(rows: list[dict], cast_aware: bool = False,
                      store_covered: set[int] | None = None) -> dict:
    """Rank by (carries a window, carries a cooldown, MaxLevel/SpellLevel,
    [casts on a cast time], [store coverage], ID).

    Rows carrying CooldownMs/CategoryCooldownMs/DurationMs beat bare companion
    rows; among carriers the CD-carrier rule wins, then level, then -- with
    cast_aware (the overlay run) -- rows that CAPTURE a cast time: a summon
    line's real cast row (Summon Felhunter 691: fam 5, 10 s cast, permanent)
    outranks an equal-level family-less no-cast shell (8176: 10-minute
    duration, no family -- the D3 review pick), then -- with store_covered
    (the wave I-2b rank law, upstream-data §7.7) -- rows the store covers
    with a value row or a Levels capture beat a value-less name shell (the
    Primal Bite Rank 4 1238073 over the store's ranked top 1238070), then ID.
    store_covered is passed only when the store covers the name, so a name
    the store does not cover is bit-identical to the pre-I-2b pick."""
    def key(r: dict):
        has_cd = bool(r.get("CooldownMs") or r.get("CategoryCooldownMs"))
        level = r.get("MaxLevel") or r.get("SpellLevel") or 0
        has_cast = bool(r.get("CastTimeMs")) if cast_aware else False
        cover = 1
        if store_covered is not None:
            cover = 1 if r.get("ID", 0) in store_covered else 0
        return (row_carries(r), has_cd, level, has_cast, cover, r.get("ID", 0))
    return max(rows, key=key)


def pre_shadow_pick(rows: list[dict]) -> dict:
    """The rank rule before the companion-shadow fix: (carries a cooldown,
    MaxLevel/SpellLevel, ID). Kept only to detect/ report shadow resolutions."""
    def key(r: dict):
        has_cd = bool(r.get("CooldownMs") or r.get("CategoryCooldownMs"))
        level = r.get("MaxLevel") or r.get("SpellLevel") or 0
        return (has_cd, level, r.get("ID", 0))
    return max(rows, key=key)


def row_effects(row: dict) -> list[dict]:
    """The row's captured effect rows (base data; the 70707 overlay captures
    none, and a store row this generator synthesises has no `Effects` key)."""
    return [e for e in (row.get("Effects") or []) if isinstance(e, dict)]


def _num(value) -> float | None:
    """A JSON number, or None (a string/None/nested value is no number)."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return value


def _seconds(ms: float) -> str:
    """Milliseconds as seconds for the Lua literal: `3`, not `3.0`; `1.5`,
    not `1.5000000000000002` (the emitted bytes must be stable)."""
    sec = ms / 1000
    if float(sec).is_integer():
        return str(int(sec))
    return ("%.4f" % sec).rstrip("0").rstrip(".")


def row_feeds(row: dict, base_row: dict | None = None) -> tuple[int, int, bool]:
    """The row's (tickMs, maxStack, casterOnly) feed triple.

    Sources for the periodic and caster shape, in order (the I-2b law,
    upstream-data §7.5): the row's OWN captured base `Effects`; for a row
    picked out of the store (no base `Effects` of its own) the SAME-ID base
    data row (`base_row`); then the live-store feed captures the row carries
    (`_periodMs`, `_targetCode` from the overlay). For those two a capture
    fills a field the earlier source can not speak to -- it never overwrites
    a base answer.

    **maxStack is the exception -- the LIVE-WINS law** (2026-11-10, the
    Paladin Vengeance finding, docs/research/live-paladin-2026-11-09.md
    §1.1): the stack cap is a number live balance patches move (Nov 3:
    Vengeance "stacking up to 5 times (Was 3)"), and the 70425 base pull is
    a frozen older build, so on the cap the store's capture is the NEWER
    word. When the live store carries `AuraOptions.MaxStack` above 1 for the
    picked id (the overlay's `_maxStack`; the extractor captures it only
    above 1 -- a cap of 1 says "no stacking" and the store's 0 on a
    ProcCharges aura such as Holy Shield is no reading), it WINS over the
    base row's `MaxStack`, whether the base said more, less or nothing.
    Without a store capture the base cap stands, as before: a name the
    store does not speak to is bit-identical to the pre-law pick. The law
    touches ONLY this column; the header's "changes in this file" list shows
    every row whose emitted maxStack moved against the pure-70425 baseline.

    tickMs: the smallest positive `PeriodMs` (0 = no periodic effect, so no
    tick schedule). maxStack: the cap when it is above 1, else 0.
    casterOnly: every captured effect lands on `CASTER_TARGET_CODE`; with no
    captured effect at all the store's `targetCode` capture answers (1 = the
    caster); no answer is False (absence is not evidence)."""
    effects = row_effects(row)
    max_stack_owner = row
    if not effects and base_row is not None:
        effects = row_effects(base_row)
        max_stack_owner = base_row
    tick_ms = 0
    caster_only = bool(effects)
    for eff in effects:
        period = _num(eff.get("PeriodMs"))
        if period is not None and period > 0 and (tick_ms == 0 or period < tick_ms):
            tick_ms = int(period)
        target = eff.get("Target")
        if not (isinstance(target, list) and target
                and target[0] == CASTER_TARGET_CODE):
            caster_only = False
    if tick_ms == 0:
        cap = _num(row.get("_periodMs"))
        if cap is not None and cap > 0:
            tick_ms = int(cap)
    stacks = _num(row.get("_maxStack"))                  # the live store's cap wins ...
    if stacks is None or stacks <= 1:
        stacks = _num(max_stack_owner.get("MaxStack"))   # ... else the base row's
    if not caster_only and not effects:
        code = _num(row.get("_targetCode"))
        caster_only = code is not None and int(code) == CASTER_TARGET_CODE
    return tick_ms, (int(stacks) if stacks is not None and stacks > 1 else 0), caster_only


def lua_escape(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"')


def emit_entry(row: dict, icd: int = 0,
               feeds: tuple[int, int, bool] | None = None) -> str:
    fields = [f'id = {row["ID"]}', f'name = "{lua_escape(row.get("Name",""))}"']
    if row.get("_racial"):
        # The Engine:AddExtras half of the racials law (wave M3a): Engine:
        # Build skips these rows, AddExtras tracks them from the same data.
        fields.append('racial = true')
    tick_ms, max_stack, caster_only = feeds if feeds is not None else row_feeds(row)
    if tick_ms:
        fields.append(f'tickEvery = {_seconds(tick_ms)}')
    if max_stack:
        fields.append(f'maxStack = {max_stack}')
    if caster_only:
        fields.append('noTarget = true')
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
    if row.get("_shares"):
        # The Engine's OnCast partner walk keys by this NAME (the runtime
        # `shares` link; the store's own fact for Summon Hawk <-> Arcane
        # Shot is the shared category 1173 with the 6 s CategoryCooldownMs).
        fields.append(f'shares = "{lua_escape(row["_shares"])}"')
    return "{ " + ", ".join(fields) + " }"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("klass", help="class name, matching tools/spell_lists/<klass>.json")
    ap.add_argument("--spells-jsonl", type=pathlib.Path, default=DEFAULT_SPELLS_JSONL)
    ap.add_argument("--manifest", type=pathlib.Path, default=DEFAULT_MANIFEST)
    ap.add_argument("--overrides", type=pathlib.Path, default=DEFAULT_OVERRIDES,
                    help=f"the checked-in live-store overlay (default: {DEFAULT_OVERRIDES.name}, "
                         "built by tools/extract_store.py)")
    ap.add_argument("--devnotes", type=pathlib.Path, default=DEFAULT_DEVNOTES,
                    help="the post-9 dev-notes layer (Blizzard dev notes post 9, "
                         "2026-11-03; applied after the live-store overlay)")
    ap.add_argument("--no-overlays", action="store_true",
                    help="pure 70425 run: ignore the live-store overlay (debug)")
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
    dn = None if args.no_overlays else load_devnotes(args.devnotes)
    # The short stamp of the overlay in use (70790 for wave M5): every build
    # word the run prints/emits rides it, so a refresh needs no text edit.
    label = overlay_label(ov) if ov is not None else "store"
    # Rename aliases (wave I-2b): {data name: the build's other spelling}.
    renames = dict(spec.get("_renames") or {})
    # Pinned picks / shared cooldowns (wave M3a, see the module docstring):
    # the pins force the picked id, the shares emit the row's `shares` link.
    pins: dict[str, dict] = dict(spec.get("_pins") or {})
    shares: dict[str, str] = dict(spec.get("_shares") or {})
    # Feed overrides (2026-11-10, live-paladin-2026-11-09.md §1.1 rows 2/5/6):
    # {data name: {"noTarget": bool, "reason": "..."}} forces the row's
    # `noTarget` feed where the captured shape cannot speak (a store-sourced
    # row with no base Effects carries only the overlay's `Targets` scalar,
    # which says caster for the ally-cast Oath of Light and says nothing for
    # the caster-side Echoes / Shieldsworn). Only `noTarget` is overridable.
    feed_overrides: dict[str, dict] = dict(spec.get("_feeds") or {})
    feeds_report: list[str] = []      # names the spell list's `_feeds` forced
    RACIAL_GROUPS = {"racials"}

    groups: dict[str, list[tuple[str, dict, int, tuple[int, int, bool]]]] = {}
    gaps: list[str] = []
    fallbacks: list[str] = []  # names resolved onto uncoded (Family 0/absent) rows
    shadows: list[str] = []    # names whose pick moved from a bare companion to a data row
    changes: list[str] = []    # per-name emitted-row diffs vs the pure-70425 baseline
    removed_report: list[str] = []  # rows dropped because 70707 removed the id
    sourced: list[str] = []    # rows with no 70425 base (70707-sourced, pet kit)
    devnotes_applied: list[str] = []  # rows a post-9 dev-notes value moved
    pins_report: list[str] = []       # names the spell list's `_pins` forced
    shares_report: list[str] = []     # rows carrying a `_shares` link
    racials_report: list[str] = []    # rows of the `racials` group (M3a)
    resolved_ids: dict[str, int] = {}  # name -> picked id (the rename alias join)

    def _row_duration(r: dict) -> int:
        d = r.get("DurationMs")
        return d if type(d) == int else 0

    def rank_pick(rows_in: list[dict], store_aware: bool,
                  store_covered: set[int] | None = None,
                  totem_window: bool = False):
        """The tier ladder: in-family carrier > uncoded carrier (fallback) >
        in-family bare > uncoded bare. With store_aware, 70707 rows carry the
        family law on the store's own code: a family-less store row rides the
        in-family pool (it is the build's capture of THIS name, not a foreign
        twin -- the Charge Rank 6 row 27685 has no ClassOptions row). With
        store_covered (the I-2b rank law) the pick also requires the store's
        Levels/value coverage where the store covers the name. With
        totem_window (the I-2b totem-window law, a `... Totem` CAST name):
        carriers whose DurationMs is below the largest captured window drop
        out of the pick -- the short rows sharing a totem's name are its
        proc/trigger auras (Windfury Totem's 1000 ms Rank-3 twin 10610, the
        PF-captured family), and the row that stands is the summon window
        the element slot draws (the store's 10613/10614 300 000, upstream-data
        §4.2; Forte_Shaman/Core/Totems.lua:SlotSpellNames reads the slots
        under the same name shape)."""
        if totem_window:
            carriers = [r for r in rows_in if row_carries(r)]
            if carriers:
                top = max(_row_duration(r) for r in carriers)
                rows_in = [r for r in rows_in
                           if not row_carries(r)
                           or _row_duration(r) >= top]
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
            return pick_current_rank(own_carriers, store_aware, store_covered), False
        if uncoded_carriers:
            return pick_current_rank(uncoded_carriers, store_aware, store_covered), True
        if own:  # all in-family rows are bare: the family row still wins
            return pick_current_rank(own, store_aware, store_covered), False
        if uncoded:
            return pick_current_rank(uncoded, store_aware, store_covered), True
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
            # The I-2b rank law's coverage set: ids the store covers with a
            # value row or a Levels capture (upstream-data §7.7). The law is
            # armed only when the store covers the name AND at least one of
            # its rows is covered -- every name the store names value-less
            # (a pure shell family, e.g. Blessing of Light 26650) keeps the
            # pre-I-2b ladder bit-identical.
            store_covered: set[int] | None = None
            if ov is not None and n in ov["names"]:
                covered = set()
                for sid in ov["names"][n]:
                    srow = ov["spells"].get(sid) or {}
                    if (srow.get("v") or srow.get("spellLevel")
                            or srow.get("baseLevel") or srow.get("maxLevel")):
                        covered.add(sid)
                if covered:
                    store_covered = covered
            # Baseline: the row the pre-70707 pipeline emitted (pure mythicsim,
            # no book/removed filter, no overlay) -- the header change list is
            # the diff of the final row against this.
            # The totem-window law rides the name shape Totems.lua uses
            # (`Totem%d*$`): a `... Totem` cast name picks its summon window.
            totem_cast = n.endswith("Totem")
            base, _ = rank_pick(rows, store_aware=False, totem_window=totem_cast)
            base_text = emit_entry(base) if base is not None else None

            pin = pins.get(n)
            if pin is not None:
                # The `_pins` law (wave M3a): the listed id IS the pick, the
                # rank ladder is overridden, the reason rides the header.
                pid = int(pin["id"])
                cands = [r for r in pool + ov_rows if r.get("ID") == pid]
                if not cands:
                    gaps.append(f"{group}: {n!r} _pins id {pid} has no row of "
                                f"this name in this build")
                    continue
                picked, is_fallback = cands[0], False
                pins_report.append(
                    f"{n} -> {pid} ({pin.get('reason', 'no reason given')})")
            else:
                picked, is_fallback = rank_pick(pool + ov_rows, store_aware=True,
                                                store_covered=store_covered,
                                                totem_window=totem_cast)
            if picked is None:
                if removed_here:
                    # The name is gone from the overlay's build: reported once
                    # as removed, never as a family/coverage gap.
                    ids_s = ", ".join(str(r.get("ID")) for r in removed_here)
                    removed_report.append(
                        f"{n}: id(s) {ids_s} removed on {label} -- the name is gone "
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
            if removed_here:  # the name survived on a store-only id (Blessing of Light)
                ids_s = ", ".join(str(r.get("ID")) for r in removed_here)
                note = "" if (ov["spells"].get(picked.get("ID")) or {}).get("v") \
                    else f" -- no captured {label} values, live probe needed"
                removed_report.append(
                    f"{n}: id(s) {ids_s} removed on {label} -> re-picked {picked.get('ID')}"
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
            out_row, applied = devnotes_apply(out_row, dn)
            if applied:
                cite = (dn["spells"].get(out_row.get("ID")) or {}).get("cite", "")
                devnotes_applied.append(
                    f"{n}: " + ", ".join(applied)
                    + (f" -- post 9: {cite!r}" if cite else ""))
            icd = spell_icd(picked, out_row, ov, rows + ov_rows)
            if shares.get(n):
                out_row["_shares"] = shares[n]
                shares_report.append(f"{n} starts the cooldown of {shares[n]} too")
            if group in RACIAL_GROUPS:
                out_row["_racial"] = True
                racials_report.append(f"{n} ({out_row['ID']})")
            base_by_id = {r.get("ID"): r for r in rows}
            base_row = base_by_id.get(out_row.get("ID"))
            if base_row is None and out_row.get("_store"):
                # Rank-sibling feed inheritance (wave M3a, the docstring law):
                # the store's rank capture of a name the base pull knows only
                # at lower ranks inherits the base feed shape of the SAME-
                # FAMILY sibling (Holy Shield 1239570 <- 20928); a family-less
                # store row inherits nothing.
                sfam = _icd_fam(out_row)
                sibs = ([r for r in rows if row_family(r) == sfam]
                        if sfam is not None and sfam != 0 else [])
                if sibs:
                    base_row = max(sibs, key=lambda r: r.get("MaxLevel")
                                   or r.get("SpellLevel") or 0)
            feeds = row_feeds(out_row, base_row)
            fo = feed_overrides.get(n)
            if fo is not None and "noTarget" in fo:
                feeds = (feeds[0], feeds[1], bool(fo["noTarget"]))
                feeds_report.append(
                    f"{n} ({out_row['ID']}) noTarget = {str(bool(fo['noTarget'])).lower()}"
                    f" ({fo.get('reason', 'no reason given')})")
            if base_text is None:
                sourced.append(f"{n} ({picked['ID']})")
            else:
                entry = emit_entry(out_row, icd, feeds)
                if entry != base_text:
                    changes.append(f"{n}: {base_text} -> {entry}")
            resolved_ids[n] = out_row["ID"]
            groups.setdefault(group, []).append((n, out_row, icd, feeds))

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
        print(f"dry {klass}: {total} spells, {len(gaps)} gaps (base {build}"
              + (f" + overlay {ov['meta']['build']} @ hotfix {ov['meta']['hotfix_push']})"
                 if ov is not None else ")"))
        for g in gaps:
            print(f"  gap: {g}", file=sys.stderr)
        for f in fallbacks:
            print(f"  info: {f}")
        for s in shadows:
            print(f"  info: {s}")
        for c in changes:
            print(f"  {label}: {c}")
        for r in removed_report:
            print(f"  removed: {r}")
        for s in sourced:
            print(f"  {label}-sourced: {s}")
        for entries in groups.values():
            for name, row, icd, feeds in entries:
                if name in CD_SAMPLE_NAMES:
                    print(f"  sample [{row['ID']}] {name}: {emit_entry(row, icd, feeds)}")
        for d in devnotes_applied:
            print(f"  devnotes: {d}")
        for p in pins_report:
            print(f"  pin: {p}")
        for p in feeds_report:
            print(f"  feed override: {p}")
        for s in shares_report:
            print(f"  shares: {s}")
        for r in racials_report:
            print(f"  racial: {r}")
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
                      f"{m.get('generated_by', 'tools/extract_store.py')} -- {label} values win; "
                      f"absent fields = the store "
                      f"carries no row, mythicsim stands)")
        if m.get("mixed"):
            stamps_s = ", ".join(f"{g} {s['build'].rsplit('.', 1)[-1]}@{s['hotfix_push']}"
                                 for g, s in sorted(m["group_stamps"].items()))
            lines.append(f"--   MIXED per-group stamps (extract_store.py --allow-mixed; the "
                         f"headline is the newest): {stamps_s}")
    else:
        lines.append(f"-- Overlay: NONE (tools/{DEFAULT_OVERRIDES.name} missing) "
                      f"-- values are pure {build}")
    if dn is not None:
        dm = dn["meta"]
        lines.append(f"-- Dev notes: tools/{dn['file']} ({dm['source']}; "
                      f"{dm['source_url']}) -- post-9 values the captured data does not "
                      f"carry, applied AFTER the {label} layer; delete a row the day a "
                      f"store capture carries the value (hotfix-watch)")
    else:
        lines.append(f"-- Dev notes: NONE (tools/{DEFAULT_DEVNOTES.name} missing)")
    lines.append(f"-- Regenerated: {datetime.now(timezone.utc).isoformat(timespec='seconds')}")
    if changes:
        lines.append(f"-- {label} overlay changes in this file ({len(changes)}):")
        for c in changes:
            lines.append(f"--   {c}")
    if devnotes_applied:
        lines.append(f"-- Post-9 dev-notes values applied ({len(devnotes_applied)}):")
        for d in devnotes_applied:
            lines.append(f"--   {d}")
    if pins_report:
        lines.append(f"-- Pinned picks ({len(pins_report)}); the spell list's `_pins` "
                      f"force the picked row -- the rank law stands for every "
                      f"other name (wave M3a law, see the generator docstring):")
        for p in pins_report:
            lines.append(f"--   {p}")
    if feeds_report:
        lines.append(f"-- Feed overrides ({len(feeds_report)}); the spell list's `_feeds` "
                      f"force the `noTarget` feed where the captured effect shape "
                      f"cannot speak (tools/gen_spell_data.py, 2026-11-10):")
        for p in feeds_report:
            lines.append(f"--   {p}")
    if shares_report:
        lines.append(f"-- Shared cooldowns (`_shares`: a cast of either starts "
                      f"both bars, Forte_Cooldown/Core/Engine.lua's partner walk):")
        for s in shares_report:
            lines.append(f"--   {s}")
    if racials_report:
        lines.append(f"-- Racial rows ({len(racials_report)}); the `racials` group -- "
                      f"`racial = true` rows are skipped by Engine:Build and "
                      f"tracked by Engine:AddExtras from this data, so the Locale "
                      f"alias walk covers their names on localized clients "
                      f"(review-10 M2/m4):")
        for r in racials_report:
            lines.append(f"--   {r}")
    if removed_report:
        lines.append(f"-- Rows dropped on {label} ({len(removed_report)}):")
        for r in removed_report:
            lines.append(f"--   {r}")
    if sourced:
        lines.append(f"-- {label}-sourced rows: no row in the {build} pull, the row is the "
                      f"{label} store's capture of the name ({len(sourced)}; the "
                      f"source-eligible rows are the Warlock pet kit "
                      f"(docs/research/forever-data-gaps.md G6) and the M3a "
                      f"racials group (the racial shells the 70425 pull names "
                      f"under other keys):")
        for s in sourced:
            lines.append(f"--   {s}")
    all_rows = [(name, row, feeds) for entries in groups.values()
                for name, row, _i, feeds in entries]
    ticked = [(n, r) for n, r, f in all_rows if f[0]]
    stacked = [(n, r) for n, r, f in all_rows if f[1]]
    self_only = [(n, r) for n, r, f in all_rows if f[2]]
    lines.append("-- Feed columns (docs/design-spell-timer.md §3.4; read by "
                  "Forte_Timer/Core/Registry.lua `Build`): `tickEvery` = the periodic "
                  "effect's period in SECONDS (`Effects[].PeriodMs`), `maxStack` = the "
                  "aura's stack cap when above 1 (the live store's `MaxStack` WINS over "
                  "the base row's -- the LIVE-WINS law, tools/gen_spell_data.py "
                  "`row_feeds`), `noTarget` = every captured effect "
                  "targets the CASTER (effect `Target[0]` == 1). Feed sources (wave "
                  f"I-2b, docs/research/upstream-data-2026-11-03.md §7.5): the row's own "
                  f"base `Effects` answer first, a {label}-picked row inherits "
                  f"the same-id base row's shape, and the {label} overlay's own feed "
                  "captures (per-id `periodMs`/`targetCode`) fill what neither can "
                  f"speak to (tools/{args.overrides.name}). "
                  f"This file: {len(ticked)} tickEvery, {len(stacked)} maxStack, "
                  f"{len(self_only)} noTarget.")
    for group, entries in groups.items():
        for name, row, _icd, (t_ms, m_stack, caster) in entries:
            tags = []
            if t_ms:
                tags.append(f"tickEvery = {_seconds(t_ms)}")
            if m_stack:
                tags.append(f"maxStack = {m_stack}")
            if caster:
                tags.append("noTarget")
            if tags:
                lines.append(f"--   feeds [{row['ID']}] {name}: " + ", ".join(tags))
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
        for name, row, icd, feeds in entries:
            lines.append(f"  [{row['ID']}] = {emit_entry(row, icd, feeds)},")
    lines.append("}")
    lines.append("")
    # name -> id lookup, needed by the cast-predict pattern (a cast's spellID and the
    # buff/debuff it applies can differ by rank; CooldownMaster's _buffByName/_cooldownByName
    # solve this by matching on name instead of ID).
    lines.append(f"ForteXorcist.Data.{class_title}ByName = {{")
    for group, entries in groups.items():
        for name, row, _icd, _f in entries:
            lines.append(f'  ["{lua_escape(name)}"] = {row["ID"]},')
    alias_notes = []
    for canon, alias in renames.items():  # spell-list order, deterministic
        if canon in resolved_ids:
            lines.append(f'  ["{lua_escape(alias)}"] = {resolved_ids[canon]},')
            alias_notes.append(f"{alias} -> {canon} ({resolved_ids[canon]})")
    lines.append("}")
    if alias_notes:
        lines.insert(len(lines) - 1, "  -- rename aliases (spell-list `_renames`; the runtime "
                                     "twin is Forte_Core/Core/Locale.lua RenameAliases): "
                                     + ", ".join(alias_notes))
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

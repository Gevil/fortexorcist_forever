# Data refresh: 70790 -> 70862 / push 113890, the LIVE-WINS maxStack law (2026-11-10)

Agent `StageA1Data` (pd-sonnet-builder), 2026-11-10. Follows `docs/research/data-diff-live-2026-11-07.md`
and the Paladin finding `docs/research/live-paladin-2026-11-09.md`. Working tree, uncommitted; no git
command that changes anything was run.

## Answer first

1. **Refreshed.** `tools/overrides_70862.json` (new; `overrides_70790.json` and `overrides_70707.json` stay as
   history) is the live overlay. `LIVE_OVERLAY` in `tools/gen_spell_data.py` points at it, and that is the only
   place (`gen_item_data.py` imports the constant; `scripts/gate.py` parses the pointer, so the gate needed no edit).
2. **Three tracked rows moved in the nine class files; one of the three is the intended fix, two are decoy
   re-picks that the spell lists must pin.**
   - Paladin `Vengeance` 20050: `maxStack` 3 -> 5. This is the LIVE-WINS law working as designed (section 4).
   - Druid `Thorns` 9910 -> **15438** and Warlock `Summon Voidwalker` 697 -> **25112**. Both are the known
     "generator picks a decoy row for a name" class (skill `fx-parallel-research-refresh` step 4): the 70862
     store gained value rows for the decoy ids, which lifts them over the real spells. **Thorns is a
     player-visible regression** (a permanent self buff, `durationMs = -1`, instead of the 600 s ally buff).
     No test of the six suites catches either (section 7). The fix is two `_pins` lines in files outside my
     scope; they are written out and verified in section 3.3 (`OUT-OF-SCOPE:` in the final report).
3. **Per-group stamps.** `tools/extract_store.py` now reads every group's build and push. A store whose spell
   groups disagree is refused unless `--allow-mixed`; the accepted overlay records every group in
   `_meta.group_stamps` (section 1). Eight scenarios tested.
4. **Dev-notes: 0 rows retired, 0 disagree.** The three remaining rows (Blood Fury, Berserking, Rapid
   Regeneration) have no store row at all on 70862, so nothing can retire or disagree (section 5).
5. **Items: all item/proc/consumable bodies byte-identical; headers only.** One divergence found in the item leg:
   `Items.lua:75` Counterattack Lodestone `durationMs = 8000` against the store's and mythicsim's own spell row
   10000 (section 6).
6. **Tests: 0 red.** Six requested suites 856/856 green, the other two addons with tests 194/194 green, on the
   old addon tree with only the 11 regenerated data files swapped in. "Tests to re-pin" is empty (section 7).
7. Determinism double-run identical, overlay re-extract is a fixpoint, luajit `loadfile` 11/11 (section 8).

## 0. Inputs

| clone | before (the pin the checked-in data came from) | after (this run) |
| --- | --- | --- |
| `/tmp/wowsims-forever` | `138964222220ad3f01634a7cc116c329a630a65e` (2026-11-07) | `5f766b07af5f140a2e3c357b7a655eff2c4d53e4` (2026-11-10 13:31 +0100), 206 commits later |
| `mythicsim-forever-engine` | `b998bbaba48f3126faffc066f95730d04ff01142` (2026-11-07) | `0bae6e2148cdc81fcc8a1151753667d990504b1a` (2026-11-10 22:04 +1100), 100 commits later |
| `wow-fortexorcist` HEAD at start | `f45e49a` (working tree carried PLAN.md edits and, during the run, sibling edits to Forte_Cooldown/Core/Engine.lua, tocs, release scripts) | unchanged by this slice |

Neither clone was pulled by me. The mythicsim **base pull did not move**: between the two commits `git diff --stat`
over `data/` lists only three new files (`forever-client-item-bonuses.jsonl`, `forever-client-items.jsonl`,
`forever-live-items.jsonl`, 735 added lines) that no generator of ours reads. `spells.jsonl`, `items.jsonl`,
`consumables.jsonl`, `enchants.jsonl` and `manifest.json` are unchanged, and the item-file pins in the generated
headers (`items=79e1e471a9bc enchants=0fc9751d4532 consumables=ba7451d78154`) are identical before and after.
Every value delta below is therefore a live-store delta (or a generator-law delta, section 4).

Store stamps (`assets/db_inputs/spell_store_inputs.json`):

| leg | 70790 pin (2026-11-07) | now |
| --- | --- | --- |
| spell groups: druid, hunter, mage, paladin, priest, racials, rogue, shaman, shared, warlock, warrior | `1.60.1.70790` / `113715` | `1.60.1.70862` / `113890` |
| `items` group | `1.60.1.70862` / `113763` | `1.60.1.70862` / `113890` |
| mythicsim base (`manifest.json` `client_build`) | `1.60.1.70425` | `1.60.1.70425` |

The store is unified: all 12 groups carry one build and one push, so `mixed` is false in the new overlay.

## 1. The extractor: per-group stamps

`tools/extract_store.py` (`resolve_stamps`, `build_key`, `--allow-mixed`):

- Every spell group (every `Builds`/`Hotfixes` group except `items`) must carry a build AND a push; an unstamped
  group refuses even with `--allow-mixed` (an unstamped group is unprovable).
- All spell groups on one build and one push: the headline `_meta.build` / `_meta.hotfix_push` is that pair,
  `mixed: false`.
- Spell groups that disagree: **refused by default** (the message prints every group's build and push); with
  `--allow-mixed` the overlay is accepted, the headline is the NEWEST build (numeric compare, `1.60.1.100000` >
  `1.60.1.70862`) and the NEWEST push, `mixed: true`, the file is named by the headline, and
  `_meta.group_stamps` = `{group: {build, hotfix_push}}` records EVERY group, items included. The generated
  headers print a `MIXED per-group stamps` line from it (`gen_spell_data.py`), and the extractor prints the stamps.
- The `items` leg stays tolerated and recorded (`items_build` / `items_hotfix_push`), as before.
- `--build` still asserts the headline stamp.

Scenarios run (`/tmp/fx_mixed_test.py`, a synthetic store copy per case, all as expected):

| scenario | result |
| --- | --- |
| unified store, `--dry` | accepted, `mixed: false` |
| one class group (hunter) on 70790 / 113715, default | refused, rc 1 |
| same, `--allow-mixed` | accepted, `mixed: true`, `group_stamps.hunter = 70790@113715`, headline 70862@113890 |
| same, `--allow-mixed --build 70862` / `--build 70790` | accepted / refused ("not the store's spell build") |
| `items` group alone on 70790 | accepted (item leg tolerated), `items_build` 70790 recorded |
| mage group with no hotfix push, `--allow-mixed` | refused (no stamp) |
| mage group on `1.60.1.100000`, `--allow-mixed` | headline `1.60.1.100000` (numeric ordering) |

The real overlay: `python3 tools/extract_store.py` -> `extract 1.60.1.70862 hotfix 113890 commit 5f766b07: spells=3961
nameIndex=601 removed=1 bookRanks=35 -> 651230 bytes`; two runs are byte-identical, and a re-extract after
regenerating the data is byte-identical to the checked-in file (the overlay depends on the ids the generated data
uses, so this fixpoint matters; it holds).

## 2. Store census: 70790 -> 70862 (overlay level)

- ids 3961 -> 3961 (+0 / -0). `bookRanks` (35) and `removed` (Greater Blessing of Light 25890) identical;
  `nameIndex` identical (601 names, same ids).
- 22 common ids carry a changed field (113 field changes, Appendix A). 21 are **coverage gains**: a field the 70790
  capture had no row for now has one (`v` 1, `castMs`, `durationMs`, `spellLevel`, `family` ...). One is a value
  change: Consecration 1280353 lost `procFlag` 8.
- **5 of the 22 ids are ids the addon uses**: Pounce Bleed 9826, Howling Blade 13490, Searing Blast 16454,
  Thorns 15438, Summon Voidwalker 25112. The first three change nothing in the emitted rows (the base row already
  carried the same values). The last two are the decoy re-picks (3.3).

## 3. The generated class data: every row that moved

Old = the checked-in files at the start of the run, new = regenerated (`/tmp/fx_rowdiff.py`). 628 rows before and
after, **3 rows changed, 1 field changed in place, 2 rows re-picked**.

### 3.1 Table of changed fields

| class | name | file:line (new; old line) | old | new | cause |
| --- | --- | --- | --- | --- | --- |
| Paladin | Vengeance | `Paladin.lua:113` (was 112) | `maxStack = 3` | `maxStack = 5` (id 20050 unchanged; dur 30000, `noTarget` unchanged) | LIVE-WINS law (section 4) |
| Druid | Thorns | `Druid.lua:98` | id 9910 `durationMs = 600000, gcdMs = 1500, rank = "Rank 6"` | id 15438 `noTarget = true, durationMs = -1, rank = "Rank 1"` | DECOY re-pick, needs a pin (3.3) |
| Warlock | Summon Voidwalker | `Warlock.lua:171` | id 697 `durationMs = -1, gcdMs = 1500, castMs = 10000, rank = "Summon"` | id 25112, same field values | DECOY re-pick, needs a pin (3.3) |

All other 625 rows are identical field for field, including every duration, cooldown, cast time, category, ICD,
tick, `noTarget` and rank text. Hunter, Mage, Priest, Rogue, Shaman, Warrior: no row moved. Header-level changes
are the `hotfix push`, `Overlay`, `Regenerated` and `Feed columns` lines, and the "70862 overlay changes in this
file" counts: Druid 11 -> 12 (+Thorns), Paladin 11 -> 12 (+Vengeance), Warlock 9 -> 8 (the pure-70425 baseline
pick for Summon Voidwalker is 25112, so the 70790 pick 697 was listed as a change and the 70862 pick 25112 equals
the baseline and drops out of the list), Hunter 5, Mage 5, Priest 1, Rogue 3, Shaman 14, Warrior 7 unchanged.

### 3.2 Why the two re-picks happen

The pick key is (carries a window, carries a cooldown, level, cast, store coverage, id) inside the family tiers.
At 70790 the store knew ids 15438 and 25112 only as `Names` shells, so the index-shell law
(`overlay_rows`) kept them out of the pool. At 70862 the store carries value rows for them
(Appendix A: 15438 `durationMs -1, spellLevel 55, subtext Rank 1`; 25112 `castMs 10000, family 5, spellLevel 10,
subtext Summon`), so they join the pool as store rows:

- **Thorns 15438** is not the druid spell: its store description is "When struck in combat inflicts $s1 Arcane
  damage to the attacker" (the item-proc aura, no family, caster target code 1). 9910 is the real Rank 6 ("Thorns
  sprout from the friendly target ... Lasts $d", family 7, 600000 ms, target 21). A family-less store row rides the
  in-family tier (`own_pred`, the Charge Rank 6 rule) and its level 55 beats 54.
- **Summon Voidwalker 25112** is "Casts your Summon Voidwalker spell with no mana or Soul Shard requirements"
  (the Abyss Shard summon); 697 is the spell. Every value is identical, both are level 10 with the same cast data,
  so the tie falls to the larger id. The id matters because the real client casts 697.

### 3.3 The fix is a pin each (OUT-OF-SCOPE for me, verified in a scratch copy)

`tools/spell_lists/druid.json` and `warlock.json` are outside this slice. The skill's rule is `_pins`; I verified
the exact fragments in a scratch copy of `tools/` (`/tmp/fxrepo`, spell lists patched there only): with the two pins
the regenerated Druid and Warlock bodies are **line-for-line identical to the pre-refresh files** (only the
header changes). Proposed fragments:

```json
// tools/spell_lists/druid.json  -> "_pins" (next to Berserking)
"Thorns": { "id": 9910, "reason": "the 70862 store gained value rows for the item-proc aura 15438 (Arcane damage when struck, no family, permanent), which out-ranks the real Rank 6 ally buff (family 7, 600 s)" }
// tools/spell_lists/warlock.json -> "_pins"
"Summon Voidwalker": { "id": 697, "reason": "25112 is the Abyss Shard no-reagent summon; the same values, but the spell the client casts is 697" }
```

Until those land the checked-in Druid.lua draws Thorns as a permanent self buff. Stage B (the per-class
spell-list patches) is the natural owner.

Rows that are coverage-only at 70862 (the store row grew, the emitted row did not): Pounce Bleed 9826 (store
`family` 7), Howling Blade 13490 (store `v` 1, `durationMs 30000`, `family 4`, `spellLevel 35`, `Rank 1`),
Searing Blast 16454 (store `v` 1, `durationMs 30000`, `family 3`, `spellLevel 30`).

## 4. The maxStack law (task 3)

### 4.1 Mechanism

`row_feeds` (`tools/gen_spell_data.py`) took the base row's `MaxStack` first and used the store capture
(`_maxStack`) only when the base had NO answer. Vengeance 20050's base row says 3 (a frozen 70425 value), the live
store says 5 (and Blizzard's Nov 3 note: "stacking up to 5 times (Was 3)"), so the stale value won. The lawful
change, stated in the `row_feeds` docstring and the module docstring (feed-columns bullet):

> **LIVE-WINS law.** When the live store carries `AuraOptions.MaxStack` above 1 for the picked id (the overlay's
> `_maxStack`; the extractor captures it only above 1), it wins over the base row's `MaxStack`, whether the base
> said more, less or nothing. Without a store capture the base cap stands, bit-identical to before. The law
> touches only this column; `tickEvery` and `noTarget` keep their base-first source order.

Code: `stacks = _num(row.get("_maxStack"))`, and only when that is missing or <= 1 fall back to the base owner's
`MaxStack`. The generated header's "Feed columns" paragraph now says so, and the header's change list (the diff
against the pure-70425 baseline) carries the row.

Limit, stated openly: the store's `MaxStack` of 0 or 1 is never captured (0 is "not set", Holy Shield's 0 sits next to
`ProcCharges 4`; 1 is "no stacking"), so the store cannot LOWER a base cap to 1. The audit below finds no tracked
row that needs that.

### 4.2 Every row whose maxStack changes in the diff: exactly one

| row | file:line | old | new | justification |
| --- | --- | --- | --- | --- |
| Paladin Vengeance 20050 | `Paladin.lua:113` | 3 | 5 | store `AuraOptions.MaxStack 5` on 70790 and 70862; wowsims `sim/paladin/talents_retribution.go:239` ("Stacks up to 5 times") and `:258` (`MaxStacks: int32(rank.MaxStack)`); Blizzard Nov 3 ("Was 3") |

No other row changes. Method: I regenerated once with only the overlay pointer moved (refresh-only, snapshot
`/tmp/fx-stepA`), then again with the law; the diff between the two is the Vengeance row and the header
bullets that describe it, nothing else. A second, independent audit of the final files
(`/tmp/fx_maxstack_audit.py`): 628 emitted rows, 25 with a `maxStack`; 232 rows have a store `AuraOptions` row and
all 232 agree with the store (`MaxStack` above 1 -> emitted equal, else emitted 0); 396 rows have no store
`AuraOptions` row (the base cap, or none, stands); **0 mismatches**, and none of the 25 emitted caps lacks a store
row. So the law touches no tracked row beyond Vengeance, and no tracked row has a base cap above 1 against a store
value of 0 or 1.

Not changed here, per the finding: `ProcCharges` as a stack cap (Holy Shield 1239570 `ProcCharges 4`) is a feed
column the generator does not read; it needs a separate decision.

## 5. Dev-notes rows (task 2, HOTFIX-WATCH)

Compared against the 70862 / push 113890 store (`/tmp/fx_devnotes_check.py`):

| row | note value | store on 70862 | verdict |
| --- | --- | --- | --- |
| Blood Fury 20572 | `cooldownMs 120000` | no `Cooldowns` row for 20572 or 24571 (24571 has only a `Categories` row, category 0) | kept: nothing to equal; inert by design (no list tracks it) |
| Berserking 20554 | `cooldownMs 180000` (owner-measured) | no `Cooldowns` row for 20554, 23505, 24378 or 1286304 | kept: nothing to equal; rides the racials group |
| Rapid Regeneration 1260270 | `cooldownMs 180000` (owner-measured) | no `Cooldowns` row for 401460 or 1260270 | kept: nothing to equal; rides the racials group |

**Retired: 0. Disagreeing: 0.** (The nine Slam/Stormstrike/Riptide rows were retired on 2026-11-07; the
generated Warrior and Shaman data is unchanged by this refresh, which re-confirms the store still carries those
numbers.) The file got a `checked_2026-11-10` meta note and its `law` text no longer names `overrides_70790.json`.
The generator output is unchanged by the file edit (it reads `source` and `source_url` only).

## 6. Items, enchants, consumables, procs

- `Items.lua` and `Procs.lua`: bodies byte-identical to the pre-refresh files; only the header's `Overlay` /
  hotfix-push stamp lines, the cross-check sentence, the `Regenerated` stamp and the ICD audit counts differ. Counts
  unchanged: onUse 238, procs 405 (400 item + 5 enchant), consumables 79, "buff with no duration" 54 / 205.
- Store vs the pinned base, where the store has a row for a consumed buff id (`/tmp/fx_item_check2.py`): 468
  durations compared, 449 equal. 18 differ as base `-1` against store `0` (a no-duration marker spelled two ways; the
  generators keep the base `-1`). **1 real divergence: `Items.lua:75` Counterattack Lodestone (itemId 18537, buff
  Magnetize 1302356) `durationMs = 8000`; the store row says 10000, and so does mythicsim's own `spells.jsonl` row
  (the item effect's 8000 disagrees with the spell row)**; the store had no row for it on 70790, so this is a coverage
  gain that exposes it. Not mine to change (item builders); the item header no longer claims the numbers are all
  identical, it says "except the divergences that report lists".
- 769 consumed spell ids; 413 table-row deltas on 143 of them, all `None -> row` (new store coverage, mostly
  `Misc.DurationMs`), 304 value-field deltas, all `None -> X`. The item on-use cooldowns and shared categories
  carry no spell id in the pull, so they can not be joined to the store by id; the 70790 wave's 707-value
  comparison was against the previous generated file, and that comparison is trivially unchanged here
  (byte-identical bodies).
- Proc ICD audit re-measured: store `AuraOptions.ICDMs` columns cover **154** of the 405 proc-buff auras (125 on
  70790); every one reads 0; **10** of the 51 emitted `icdMs` rows have a store row (7 on 70790), all 0. The store still
  confirms none and contradicts none. The counts in the `Procs.lua`/`Items.lua` header were updated.
- `gen_item_data.py` edits are the stamp/provenance lines only: the cross-check sentence (lines 417-424) and the
  two ICD count lines (499-500). The module docstring (lines 50-61) still narrates the 70790 measurements; it is
  left for the item builders.

## 7. Tests (task 4): 0 red; tests to re-pin: none

Run with `flock /tmp/fx-wowsim.lock`, via `/tmp/fx_runtests.py` -> `run.sh wow-sim --allow-ui-version-mismatch
--no-saved-vars --addons-path <tree> run-tests <Addon>`. **Tree = the pre-refresh addon tree (`/tmp/fx-old/addon`)
with only the 11 regenerated data files swapped in** (`/tmp/fx-new/addon`), because siblings were editing
`Forte_Cooldown/Core/Engine.lua` and the tocs in the live tree during this run; a failure there could not be told
from the data. The old tree was run first as the baseline.

| suite | baseline (old data) | new data | red |
| --- | --- | --- | --- |
| Forte_Cooldown | 232 / 232 | 232 / 232 | 0 |
| Forte_Timer | 186 / 186 | 186 / 186 | 0 |
| Forte_Hunter | 168 / 168 | 168 / 168 | 0 |
| Forte_Shaman | 23 / 23 | 23 / 23 | 0 |
| Forte_Warlock | 103 / 103 | 103 / 103 | 0 |
| Forte_Core | 144 / 144 | 144 / 144 | 0 |
| Forte_Messages (extra) | - | 85 / 85 | 0 |
| Forte_Options (extra) | - | 109 / 109 | 0 |

The other addons (Items, ItemProcs, Druid, Mage, Paladin, Priest, Rogue, Warrior) have no `tests/` directory.

### Tests to re-pin

**None.** No test in the repo asserts Vengeance's `maxStack` (`Forte_Cooldown/tests/test_tracked_set.lua:315` only
lists the *names* `Vengeance`, `Vindication`, ...), Thorns' id or Summon Voidwalker's id, so there is no old-vs-new
value to re-pin. The two decoy re-picks (3.2) are therefore **not caught by any test**; that is a gap for sibling
stage C: a census row per name pinning the picked id (Thorns 9910, Summon Voidwalker 697) would have gone red on
this refresh. Until the pins of 3.3 land those rows are wrong and untested.

## 8. Verification

```
python3 tools/extract_store.py --dry   -> extract 1.60.1.70862 hotfix 113890 commit 5f766b07: spells=3961 nameIndex=601 removed=1 bookRanks=35
python3 tools/extract_store.py          -> wrote tools/overrides_70862.json (651230 bytes); second run byte-identical (cmp)
python3 tools/gen_spell_data.py <class> x9 ; python3 tools/gen_item_data.py   (twice, /tmp/fx_determinism.py)
  -> 11 data files, double-run identical ignoring the "-- Regenerated:" line (the gate law)
  -> re-extract after regenerate == checked-in overlay (fixpoint)
luajit -e "assert(loadfile('<file>'))" on all 11 Data/*.lua -> 11/11 ok
replica of scripts/gate.py data_provenance (/tmp/fx_provenance.py): pointer -> overrides_70862.json, 11 files, 0 failures
```

`scripts/gate.py` was not run (the manager's) and not edited: it parses the `LIVE_OVERLAY` pointer, the stamp
and the push from the overlay, so the new pointer moved its check by itself.

Files changed by this slice: `tools/extract_store.py`, `tools/overrides_70862.json` (new), `tools/gen_spell_data.py`
(pointer, `row_feeds` law, docstrings, header wording), `tools/gen_item_data.py` (stamp lines only),
`tools/overrides_devnotes_2026-11-03.json` (meta only), the 9 class `Data/*.lua`, `Forte_Items/Data/Items.lua`,
`Forte_ItemProcs/Data/Procs.lua`, this report. `scripts/gate.py`: no change needed.

## Appendix A: overlay field changes on common ids, 70790 -> 70862 (22 ids, 113 field changes)

`*` marks an id the addon uses. "x -> y": `None` = the capture had no field.

| id | name | changes |
| --- | --- | --- |
| 9007, 9824 | Pounce Bleed | family None -> 7 |
| 9826 * | Pounce Bleed | family None -> 7 |
| 13490 * | Howling Blade | castMs, durationMs None -> 0, 30000; family None -> 4; spellLevel None -> 35; subtext None -> Rank 1; v None -> 1 |
| 13532 | Thunder Clap | castMs, category None -> 0; durationMs None -> 10000; spellLevel None -> 50; targetCode None -> 4; v None -> 1 |
| 15438 * | Thorns | castMs None -> 0; durationMs None -> -1; icdMs None -> 0; spellLevel None -> 55; subtext None -> Rank 1; v None -> 1 |
| 16414, 18084 | Drain Life | castMs, category None -> 0; durationMs None -> 0; spellLevel None -> 45; v None -> 1 |
| 16454 * | Searing Blast | castMs, category None -> 0; durationMs None -> 30000; family None -> 3; icdMs None -> 0; spellLevel None -> 30; v None -> 1 |
| 18088 | Corruption | castMs, category None -> 0; durationMs None -> 3000; icdMs None -> 0; periodMs None -> 1000; spellLevel None -> 40; v None -> 1 |
| 18798 | Freeze | castMs, category None -> 0; durationMs None -> 5000; spellLevel None -> 50; v None -> 1 |
| 18799 | Freeze | castMs, durationMs None -> 0; icdMs None -> 0; procFlag None -> 40; spellLevel None -> 50; v None -> 1 |
| 24854 | Mana Spring Totem | baseLevel/spellLevel None -> 50; castMs, category, categoryCooldownMs, cooldownMs None -> 0; durationMs None -> 24000; family None -> 11; gcdMs None -> 1500; v None -> 1 |
| 25112 * | Summon Voidwalker | baseLevel/spellLevel None -> 10; castMs None -> 10000; category, categoryCooldownMs, cooldownMs None -> 0; durationMs None -> -1; family None -> 5; gcdMs None -> 1500; subtext None -> Summon; v None -> 1 |
| 29644, 1314069 | Fire Blast | castMs, category, durationMs None -> 0 (+ spellLevel None -> 1 on 29644); v None -> 1 |
| 414647 | Lacerate | baseLevel/spellLevel None -> 1; castMs, category, durationMs None -> 0; family None -> 7; icdMs None -> 0; v None -> 1 |
| 1280353 | Consecration | procFlag 8 -> None (the only value change) |
| 1293654 | Silence | castMs, category None -> 0; durationMs None -> 6000; spellLevel None -> 60; v None -> 1 |
| 1300667 | Mana Spring Totem | castMs, durationMs None -> 0; v None -> 1 |
| 1316319 | Hurricane | castMs, durationMs None -> 0; icdMs None -> 0; procFlag None -> 64; v None -> 1 |
| 1324687 | Dismember | castMs, category, durationMs None -> 0; spellLevel None -> 1; v None -> 1 |

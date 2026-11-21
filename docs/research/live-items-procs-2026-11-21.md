# Live items and procs on client 1.60.1.71037 (items hotfix push 114326): the 2026-11-21 pass

Written 2026-11-21. Follows `docs/research/live-items-procs-2026-11-09.md` (the first live layer, `tools/item_lists/live_items.json` of 2026-11-10). Values come from the live db and the spell store at the commit cited; `docs/research/forever-changes-2026-11-21.md` was used only as a cross-check (section 5).

Claim labels: **[D]** derived by `tools/diff_live_items.py` or a script over local files; **[I]** inference; **[UNVERIFIED]** not checkable from files.

## 1. Inputs and method

| input | pin |
| --- | --- |
| wowsims/forever `/tmp/wowsims-forever` | HEAD `d0ba78b81e1e302392cacf5c7d5e7eecb05cf6a0` (2026-11-21 11:13 +0100). `db.json`: 7,415 items, 435 consumables, 888 items with `itemEffects`. Items leg 1.60.1.71037 @ hotfix push **114326** (`assets/db_inputs/spell_store_inputs.json` `Builds.items` / `Hotfixes.items`); item import = wowsims `42cb97b037`. The spell groups of the same store file are still 1.60.1.70959 @ 114286 (overlay `tools/overrides_70959.json`, unchanged this pass). |
| mythicsim `data/` | `items.jsonl` / `consumables.jsonl` / `enchants.jsonl` pinned at 1.60.1.70425 (generator input, unchanged). `forever-live-items.jsonl` 1,721 rows and `forever-client-items.jsonl`, used as cross-checks only. |
| our generated data before | `Items.lua` 110,334 B (onUse 250, consumables 174, enchantProcs 5), `Procs.lua` 147,483 B (401 item proc rows). |

**The tool.** `tools/diff_live_items.py` (stdlib, read-only, deterministic; `--json`; tests in `scripts/test_diff_live_items.py`, 13 tests) parses our two generated Lua files and walks the live db with the generator's relevance policy:

- an item effect with `onUse` and a positive `cooldownMs` is an on-use row; a `proc` effect without `onUse` is a proc row; anything else (equip auras, category-only lockouts) is out of scope [D];
- `-1` means "no cooldown" in the db and in mythicsim and is normalised to absent on both sides;
- on-use `categoryId` / `categoryCooldownMs` of items are not emitted (generator law), so categories are compared for consumables only;
- consumables qualify when their category cooldown (or an item-only cooldown) is at least 60 s, the tracker floor `Items.MIN_CATEGORY_CD` of `Forte_Cooldown/Core/Items.lua`; the 1-3 s elixir lockouts and 1-1.5 s item cooldowns are the GCD band;
- sub-second ICDs (10 / 100 / 200 ms) stay in the data, as the generator keeps them (`Procs.MIN_ICD` hides them at runtime); the tool only flags them `debounce`;
- absence of an item from the db is **not** evidence it is gone (wowsims drops items below its item-effect floor, 2026-11-09 report s1.1): category (f) separates `absent` (no evidence, never acted on) from `lost its effect` / `changed kind` (evidence).

The generator gained two keys because two findings had no way to be expressed: `onUseRemove` (a mythicsim on-use row the live item lost) and `procOverride` (value changes to a proc row over buffId / buffName / durationMs / icdMs, `set` + `was`, stale or redundant = error, like `onUseOverride`). Every ICD row needs an `icdStoreAudit` reading; the audit was re-captured in full against the current store (57 ICD rows, was 51; 4 rows that read "no store row" on 70862 now have one, all equal to ours; 0 contradictions).

## 2. Counts per category

First run against the pre-pass data, then the same tool after the layer edit and regeneration.

| cat | what | found | accepted | rejected / not acted on | after |
| --- | --- | --- | --- | --- | --- |
| a | live on-use items missing | 4 | 4 | 0 | 0 |
| b | cooldown / duration / buff mismatches | 6 rows on 4 items (see below) | 3 items | 1 known (Counterattack Lodestone, intended override) | 1 (the known one) |
| c | live proc effects missing | 27 | 27 | 0 | 0 |
| d | proc ICD mismatches | 2 (both non-debounce) | 2 (via `procOverride`) | 0 | 0 |
| e | live consumables, cooldown >= 60 s, missing | 3 | 0 | 3 (2026-11-09 exclusion) | 3 |
| f | emitted rows gone / lost effect | 125: 1 with evidence, 124 `absent` | 1 (removal) | 124 absent = no evidence | 124 absent |
| g | ByName collisions the missing rows would hit | 1 (Earthshaker) | n/a | does not flip the winner | 0 |

Raw tool output before the pass: `a=4 b=4 c=27 d=2 e=3 f=125 g=1` (the first draft of the tool compared fewer fields and had no 60 s floor: it listed 82 duration rows and 257 consumables, almost all `-1` representation noise and food; both were fixed in the tool, not by hand).

Category (b) rows: Traveler's Symbols 221315 (live window 60000, ours none), Counterattack Lodestone 18537 (live 8000, ours 10000), Gloves of Holy Might 867 (aura name moved 1325229 -> 1330855), Howling Hide 284262 (buffId 1315767 -> 1330916, 30 s window gone, buff name moved).

Row counts, `python3 tools/gen_item_data.py` exit code **0** (errors 0):

| list | before | after | delta |
| --- | --- | --- | --- |
| `Items.onUse` | 250 | 253 | +4 added, -1 removed |
| `Items.consumables` | 174 | 174 | 0 |
| `Items.enchantProcs` | 5 | 5 | 0 |
| `ItemProcs.procs` (item rows) | 401 | 428 | +27 |
| procs incl. enchant rows | 406 | 433 | +27 |

Layer: onUseOverride 4 -> 5, onUseRemove 0 -> 1, onUseAdd 12 -> 16, procAdd 1 -> 28, procOverride 0 -> 2, consumablesAdd unchanged (95 rows).

## 3. Accepted rows

All rows cite `wowsims/forever d0ba78b81e1e302392cacf5c7d5e7eecb05cf6a0` + item id in their `source` field. Items marked **first seen** use `item_first_seen.json`; 2022-11-19 is that file's date for items with no recorded first sighting, not a release date.

### 3.1 New on-use rows (`onUseAdd`)

| item | slot | cooldown | window | buff | first seen |
| --- | --- | --- | --- | --- | --- |
| 276744 Zarla's Snack Pouch | trinket | 900 s | 15 s | Zarla's Snack Pouch 1315190 | 2026-11-10 |
| 284231 Sayaad Charm | trinket | 900 s | 15 s | Charm 1315557 | 2026-11-10 |
| 286612 Sand-Covered Silk Sash | cloth belt | 1800 s | 5 s | Immune Root 9774 | 2026-11-11 (2026-11-09 report had it from a tooltip only) |
| 287045 Ancient Mattock | 1h axe | 120 s | none stated | Sift Soil 1325180 | 2026-11-11 |

Shared category lockouts (Zarla's: category 94, 15 s) are not emitted.

### 3.2 New proc rows (`procAdd`, 27)

ICD rows (the only ones the proc watcher can use; it needs a plain buffId and an ICD of at least 1 s): 219326 Seed of Renewal (buff 443678, aura name 443278, ICD 120 s, window 30 s; store `AuraOptions.ICDMs` of aura 443278 = 120000), 274651 Zealot Plate (15 s), 274608 Maw of Min'loth (3 s), 274647 Farraki Kris (100 ms debounce, window 6 s). The other 23 carry no ICD (weapon ppm / on-block procs): 7726 Aegis of the Scarlet Commander, 23004 Idol of Longevity, 23005 Totem of Flowing Water, 273293 Bandsaw Wristbands, 274265 Brush Cutter, 274270 Weed Whacker, 274271 Deadhead Blade, 274484 Axe of Inevitable Ruin, 274603 Dreadfrost Saber, 274952 Jom-jom's Gabbar, 276419 Lightcrest Hammer, 276632 Wit's Edge (`ClassMage`, window 15 s), 276742 Girdle of Extracted Answers, 279480 Bigger Rock on Bigger Stick (20 s), 279852 Rock on Stick (20 s), 282632 Scalding Staff, 282700 Shadow Scalper, 284050 High Elf's Recurve (9 s), 284587 Ankle Slicers (6 s), 286430 Toofbreaker, 286650 Pyromancer's Baton (9 s), 287005 Sword of Dismemberment, 288900 Earthshaker (3 s, name shared with 17073: `ProcsByName` keeps the lowest id 17073). They resolve by name and buff name; they are inert for the watcher today, like 205 of the 400 mythicsim proc rows. Proc rates (`ppm`, `procChance`) are not emitted (generator law).

### 3.3 Overrides and removals

| item | change | evidence |
| --- | --- | --- |
| 221315 Traveler's Symbols | `onUseOverride` durationMs null -> 60000 | db effect `effectDurationMs 60000` |
| 867 Gloves of Holy Might | `procOverride` buffName `(1325229)` -> `(1330855)`, icdMs none -> 20000 | db proc `icdMs 20000` / `procChance 0.15`; store aura 1330855 ICDMs 20000 |
| 284262 Howling Hide | `procOverride` buffId 1315767 -> 1330916, buffName `(1315767)` -> `(1330916)`, durationMs 30000 -> none, icdMs none -> 20000 | db proc `icdMs 20000` / `procChance 0.1`, no window; store aura 1330916 ICDMs 20000 |
| 18406 Onyxia Blood Talisman | `onUseRemove` (was 300000) | the db item has no `itemEffects` (stats only); mythicsim GH:35f2faf reports the use lost in push 114115 |
| 18537 Counterattack Lodestone | kept (the 2026-11-10 override stays) | db and mythicsim say 8000, the store's aura Magnetize says 10000 (`data-diff-live-2026-11-10.md` s6); the tool prints it as `known` |

Every earlier layer row (the 3 cooldown overrides, the 12 earlier on-use rows, the 95 consumables, Fist of Stone) was re-diffed against `d0ba78b8` and still matches (tool categories a, b, c, d, e empty apart from the rows above).

## 4. Exclusions, and the rule

1. **Dev / test / placeholder items.** An item is excluded only on positive evidence: a name pattern (`test`, `dnt`, `deprecated`, `placeholder`, `nyi`, `unused`, `obsolete`, `debug`, `temp`, a leading `[`, `zz`, `PH`) on an item with effects, or an item that is not in the live db. The pattern matches **no** effect-bearing item of the 7,415. Ten of the 31 candidates (Brush Cutter, Weed Whacker, Deadhead Blade, Dreadfrost Saber, Wit's Edge, Zarla's Snack Pouch, Sayaad Charm, Toofbreaker, Sand-Covered Silk Sash, Ancient Mattock) are also in mythicsim's `forever-client-items.jsonl` (client item tables of 1.60.1.70959) [D]. 18 candidates have no `sources` in the db, so obtainability is not shown by the file (Seed of Renewal, first seen 2026-11-21, and Shadow Scalper, 2026-11-16, post-date the mythicsim pull); they stay because db.json is itself built from the client's item cache and the policy has no source filter [I]. Quest rewards (Jom-jom's Gabbar, the two Rock-on-Stick maces) and world drops (Earthshaker) are obtainable and accepted.
2. **Phase.** No phase filter: 60 rows already in our data sit on phase-2 items (Thunderfury, Ashbringer and others), `phase` records Classic content gating, and the generator has no such rule. Idol of Longevity and Totem of Flowing Water are phase-2 Naxxramas drops and are accepted on that basis; see open question 4.
3. **The four 2026-11-09 "dropped" procs** (7726, 23004, 23005, 273293, `live-items-procs-2026-11-09.md` s5 row 5, rated "low: block-damage / mana-refund procs with no aura") are now **accepted**: the 11-09 decision was about mythicsim carrying them as passive; the live db carries them as procs and the generator policy for this pass is "every proc effect". They are inert for the watcher. Owner call: drop them from `procAdd` if inert rows are unwanted.
4. **Category cooldowns are not emitted** (generator law). Zarla's Snack Pouch's category 94 and every trinket family lockout stay out.
5. **PvP rank variants.** None among the candidates. The existing Insignia rows are untouched.
6. **Class allowlists.** Wit's Edge carries `classAllowlist [8]` in the db and is emitted `ClassMage`; no other candidate has one.
7. **Consumables, 3 rejected (category e).** Full Moonshine 1072 and Mug of Shimmer Stout 3087 (category 4 / 120 s) and Fishliver Oil 1322 (category 1153 / 120 s): rows with an explicit item cooldown of -1 that the 2026-11-09 report (P4 "Skip for now") left out as not bar-worthy. They qualify by the 60 s floor, so the tool lists them each run; adding three `consumablesAdd` rows is a one-line change if wanted.
8. **Well Fed foods and the Clam family** (5525, 5526, 16766, 250081, 3663, 5527): every effect states `cooldownMs -1` and `categoryCooldownMs -1`, so they are no consumable with a cooldown and not tracked. The 250932-250955 potions (Spellblasting, Frenzy, Mender's ...) are category 4 with a category cooldown of -1: not tracked, see open question 2.
9. **Items absent from the db** (124 rows, category f `absent`): not acted on. Five of them (Totem of Infliction 1131, Grand Marshal's Aegis 234588, High Warlord's Shield Wall 234562, the two Satchels of Bombs 285275 / 285276) are in mythicsim's live jsonl. Absence is not evidence.
10. **Set bonuses.** Our data models item effects only; there is no set-bonus row anywhere in `addon/` or the generator (grep: no `Stormshroud`, `Revitalize`, `setBonus`). The Stormshroud Armor 3pc change (3% / 18 energy, spells 23863 / 23864) therefore changes nothing here.
11. **The 68 crafted set pieces 273884-273951.** All 68 ids are in the db; **none carries an item effect** (no on-use, no proc, no passive), so nothing for our policy to track. (The manager report counts 69; the id range holds 68.)
12. **Enchant effects.** `enchantProcs` (5 rows) were not diffed: the tool reads items and consumables only.

## 5. Cross-check against `forever-changes-2026-11-21.md`

| item the manager asked about | found by the tool | handled |
| --- | --- | --- |
| Seed of Renewal 219326 | yes, category c | `procAdd`: buff 443678, aura name 443278, ICD 120000, window 30000; store reads ICDMs 120000 on 443278 |
| Stormshroud 3pc | no (set bonus, not an item effect) | none needed, not modelled |
| Onyxia Blood Talisman | yes, category f `lost its effect` (db item has no effects) | `onUseRemove`; the old row was `cooldownMs 300000`, buff Blood of the Broodmother 1287808 |
| new Well Fed foods and changed Murloc Fin Soup / Goblin Deviled Clams | not listed: no cooldown | policy exclusion, section 4 item 8 |
| Gloves of Holy Might text change | yes, categories b and d | `procOverride` (aura 1330855, ICD 20000) |
| 273884-273951 crafted sets | checked separately | no effects, section 4 item 11 |

Also: all 96 on-use / proc effect rows of mythicsim `forever-live-items.jsonl` (1,721 rows) are present in our data after this pass, with 0 cooldown or ICD differences [D]. I could not reproduce the task's "1,433 -> 1,721, 288 added, 45 with effects" delta: against commit `4e1bbb5e` (2026-11-11) the file has 1,627 rows and gains 94 (22 with effects, all already tracked). None of the 31 candidates is in that jsonl; it carries items for which the client tooltip had no effect line, which is why it cannot see them.

## 6. Size effect

| file | before | after | delta |
| --- | --- | --- | --- |
| `addon/Forte_Items/Data/Items.lua` (always loaded) | 110,334 B | 111,797 B | **+1,463 B** (+1.3 %), far under the 25 KB stop |
| `addon/Forte_ItemProcs/Data/Procs.lua` (load on demand) | 147,483 B | 157,331 B | +9,848 B (+6.7 %) |

The `Items.lua` growth is 4 on-use rows less 1 removed and the longer header. The `Procs.lua` growth is the 27 proc rows plus their name and buff-name index lines and the 6 extra ICD audit lines.

## 7. Open questions only the live client can answer

1. **Seed of Renewal.** Tooltip: "40% chance, 120 s cooldown"? The row's `buffId 443678` is the 30 s seed aura it places on the enemy; the watcher joins on a plain aura on the player, so whether the proc is visible as a player aura at all is unknown [UNVERIFIED]. If not, the ICD bar never starts for this row.
2. **Forever potions** 250932-250955 (Spellblasting, Frenzy, Mender's, ...): category 4 but a category cooldown of -1 in the db. Does the 2-minute potion lockout apply (tooltip "Cooldown")?
3. **Gloves of Holy Might and Howling Hide.** Tooltips: "15% / 10% proc chance, 20 s cooldown"? Does Howling Hide still grant a 30 s buff, or is the effect now instantaneous?
4. **Phase-2 items** (Idol of Longevity, Totem of Flowing Water, Naxxramas): are they obtainable on the live realm today?
5. **Ancient Mattock** 120 s use ("Sift Soil"): tooltip window? The row states none.
6. **Onyxia Blood Talisman**: confirm the tooltip has no "Use:" line.
7. **Sayaad Charm / Zarla's Snack Pouch**: 15 min cooldown and 15 s window on the tooltip?

## 8. Tests

- `python3 scripts/test_diff_live_items.py`: 13 tests, OK.
- wow-ui-sim: Forte_Cooldown 313 / 313 (`test_items_live.lua` went from 11 to 14 tests), Forte_Core 179 / 179, Forte_Timer 228 / 228, Forte_Options 116 / 116, Forte_Messages 87 / 87.
- `python3 scripts/api_lint.py`: OK (65 files).
- The only existing pin the new data legitimately moved: `test_procs.lua` `HUNTER_ROWS` 13 -> 18 (the five new ICD rows of at least 3 s), commented with this pass. No count of rows is pinned elsewhere. The first Forte_Cooldown run failed that pin and also 11 `test_tiers_wand.lua` tests (`Engine.stats` nil) [I: a knock-on of the aborted test]; both cleared on the re-run after the pin was updated.
- New Lua tests in `addon/Forte_Cooldown/tests/test_items_live.lua` (each commented with this pass): the four new on-use items track through the real `Items:Rescan` with their live cooldowns; Traveler's Symbols window 60 s and Onyxia Blood Talisman untracked; new proc items resolve by name and buff name and feed `Procs:Build` / `Procs:OnProcSeen`.

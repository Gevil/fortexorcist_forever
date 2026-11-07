# D1b — Data refresh: our 70425-pinned data on the live store 70790 / 70862 (wave M5)

Agent `DataRefreshM5`, 2026-11-07. Follows `docs/research/data-diff-70707.md` (D1) and
`docs/research/upstream-data-2026-11-03.md`. Upstream clones pulled `--ff-only` and pinned:

| clone | before | after |
| --- | --- | --- |
| `/tmp/wowsims-forever` (the live store) | `6e69a7f4f239c591e9dec4124a93fca6329c240f` | `138964222220ad3f01634a7cc116c329a630a65e` |
| `mythicsim-forever-engine` (the base pull) | `14b1a693b64684afba660bc6c398d4e97430eb9a` | `b998bbaba48f3126faffc066f95730d04ff01142` |
| `wow-fortexorcist` (this repo, HEAD at wave start) | `4d1650e0f2c15508f894643b268cc832fbf12adc` | (unchanged: this wave writes `tools/` and generated data only) |

Live-store stamps (`assets/db_inputs/spell_store_inputs.json`, `manifest.json`):

| leg | build | hotfix push |
| --- | --- | --- |
| spell / class / racial / shared groups | `1.60.1.70790` | `113715` |
| `items` group (the item / enchant / consumable leg) | `1.60.1.70862` | `113763` |
| mythicsim base pull (`manifest.json` `client_build`) | `1.60.1.70425` | — |

The base pull **did not move**: `data/spells.jsonl`, `data/items.jsonl`,
`data/consumables.jsonl`, `data/enchants.jsonl`, `data/manifest.json` are byte-identical
between the two mythicsim commits (that wave merged sim code, fixtures, and two new
`data/forever-*-items.jsonl` files no generator of ours reads). Every value delta below is
therefore a **live-store** delta, and the generated files stay pure functions of the pinned
base pull plus the pinned overlay.

## Answer first

1. **The nine class files regenerated; six tracked rows moved.** Druid `Abolish Poison`
   2893 → 14253, Paladin `Holy Shield` 20928 → 1239570, Rogue `Shank` 15617 → 1329549 (a new 10 s
   cooldown), Rogue `Death Mark` 1325758 (bare row → full: 10 s cd, 6 s mark, 6 s tick,
   `Rank 4`), Shaman `Chain Lightning` 10605 cast 2000 → 2500 ms, Shaman `Totemic Projection`
   437009 cd 60000 → 30000 ms. Hunter, Mage, Priest, Warlock, Warrior: **zero** row and value
   deltas.
2. **`Items.lua` and `Procs.lua`: zero value deltas.** All 707 consumed item/consumable
   cooldowns, shared categories and durations are identical 70425 → 70862 (§4). The proc ICD
   columns stay probe-kept: the store's `AuraOptions.ICDMs` covers 125 of the 405 proc-buff auras
   on this capture and reads 0 on every one, so it confirms none and contradicts none.
3. **Nine dev-notes rows retired** (`Slam` 1464/8820/11604/11605/1310200, `Stormstrike` 17364,
   `Riptide` 408521/1239242/1239243) — the live capture carries exactly those post-9 values now.
   `Blood Fury` 20572 stays (the store carries no row for the id). No dev-notes row disagrees
   with the store (§6).
4. **The three live-session suspicions are answered in §5.** Shank: confirmed, and the refresh
   fixes it through the rank law with no hand-edit. Arcane Blast: the pick rides the
   weapon-proc row 18091 (the client gives *that* row an 8 s self-recovery); the mage ladder
   carries no cooldown and the real 18 s / 4-stack buff (400573) rides no row — a tracked-set
   call for the owner, flagged not applied. The 70840-era NPC-ish rows: all 30 are name-only
   shells, and exactly one of the 33 ids that joined the capture reached the data — the
   intended Shank `Rank 2`.
5. **Determinism law holds.** Two full generator runs (nine classes + items) are byte-identical
   modulo the `-- Regenerated:` stamp on all 11 data files, and `luajit` loads all 11.

## 1. The inputs, and where the live store is pointed (one place)

- `tools/extract_store.py` (new) generalises `tools/extract_70707.py`: `--build` names any store
  build, `--wowsims` the clone, `--commit` the stamp, `--out` the overlay. It validates that the
  spell-side groups (`druid … shared`, `racials`) all carry one build and one hotfix push and
  records the item leg separately in `_meta` — that is what lets a store whose item group runs
  ahead of its spell groups (70790 / 70862) be extracted at all. Replay proof: pointed at the
  pre-pull clone (`6e69a7f4`) it reproduces the checked-in `tools/overrides_70707.json`
  byte-for-byte in every data section (`spells`, `nameIndex`, `bookRanks`, `removed`).
- `tools/overrides_70790.json` (new) is the live overlay: 3948 ids,
  598 tracked-name keys, 35 book ranks,
  1 `removed` id. `_meta` stamps both legs (`build` / `hotfix_push` for the
  spell side, `items_build` / `items_hotfix_push` for the item leg) plus `generated_by`,
  `spell_groups`, `store_inputs` and the field-semantics line.
- **One place names the live store**: `LIVE_OVERLAY` in `tools/gen_spell_data.py`
  (`DEFAULT_OVERRIDES = LIVE_OVERLAY`), and `tools/gen_item_data.py` imports that constant. No
  build word is welded to a generator any more — a generated header derives every build word
  from the overlay `_meta` through `overlay_label()`, so dropping in a 70862-era overlay
  re-stamps the whole data set by itself. `tools/overrides_70707.json` stays checked in as D1's
  historical capture and is read by nothing.

## 2. Store census: 70707 → 70790

- ids: 3915 → 3948 (+33 / −0); field changes on common ids:
  **170** (153 value fields + 17 coverage bits, Appendix A).
- `nameIndex` keys: 600 → 598;
  `bookRanks`: 35 → 35 (identical);
  `removed` map unchanged (['25890'] in both).
- The 33 ids that joined the capture are Appendix B. 30 of them are **name-only
  shells**: the store carries a `Names` row and no `ClassOptions`, `Cooldowns`, `Misc`, `Levels`,
  `Subtexts` or `AuraOptions` row at all (checked table by table in the raw
  `spell_store_inputs.json`). The three that carry values are the Shank pair and one
  Ghostly Strike row (§5.1, §5.3).

### 2.1 Every value change on a common id

| name | id | field | 70707 | 70790 |
| --- | --- | --- | --- | --- |
| Chain Lightning | 421 | `castMs` | `2000` | `2500` |
| Chain Lightning | 930 | `castMs` | `2000` | `2500` |
| Slam | 1464 | `categoryCooldownMs` | `18000` | `15000` |
| Chain Lightning | 2860 | `castMs` | `2000` | `2500` |
| Use Soulstone | 3026 | `icdMs` | `0` | `None` |
| Curse of Weakness | 8552 | `castMs` | `None` | `1000` |
| Curse of Weakness | 8552 | `category` | `None` | `0` |
| Curse of Weakness | 8552 | `durationMs` | `None` | `120000` |
| Curse of Weakness | 8552 | `spellLevel` | `None` | `14` |
| Slam | 8820 | `categoryCooldownMs` | `18000` | `15000` |
| Chain Lightning | 10605 | `castMs` | `2000` | `2500` |
| Slam | 11604 | `categoryCooldownMs` | `18000` | `15000` |
| Slam | 11605 | `categoryCooldownMs` | `18000` | `15000` |
| Disarm | 11879 | `castMs` | `None` | `0` |
| Disarm | 11879 | `category` | `None` | `0` |
| Disarm | 11879 | `durationMs` | `None` | `5000` |
| Disarm | 11879 | `spellLevel` | `None` | `30` |
| Fade | 12685 | `castMs` | `None` | `0` |
| Fade | 12685 | `category` | `None` | `0` |
| Fade | 12685 | `durationMs` | `None` | `10000` |
| Fade | 12685 | `spellLevel` | `None` | `40` |
| Pummel | 13491 | `castMs` | `None` | `0` |
| Pummel | 13491 | `category` | `None` | `0` |
| Pummel | 13491 | `durationMs` | `None` | `5000` |
| Pummel | 13491 | `spellLevel` | `None` | `6` |
| Corruption | 13530 | `castMs` | `None` | `0` |
| Corruption | 13530 | `category` | `None` | `0` |
| Corruption | 13530 | `durationMs` | `None` | `3000` |
| Corruption | 13530 | `periodMs` | `None` | `1000` |
| Corruption | 13530 | `spellLevel` | `None` | `40` |
| Faerie Fire | 13752 | `castMs` | `None` | `0` |
| Faerie Fire | 13752 | `category` | `None` | `0` |
| Faerie Fire | 13752 | `durationMs` | `None` | `30000` |
| Faerie Fire | 13752 | `icdMs` | `None` | `0` |
| Faerie Fire | 13752 | `spellLevel` | `None` | `45` |
| Faerie Fire | 13752 | `subtext` | `None` | `Rank 2` |
| Abolish Poison | 14253 | `castMs` | `None` | `0` |
| Abolish Poison | 14253 | `category` | `None` | `0` |
| Abolish Poison | 14253 | `categoryCooldownMs` | `None` | `0` |
| Abolish Poison | 14253 | `cooldownMs` | `None` | `0` |
| Abolish Poison | 14253 | `durationMs` | `None` | `8000` |
| Abolish Poison | 14253 | `gcdMs` | `None` | `1500` |
| Abolish Poison | 14253 | `icdMs` | `None` | `0` |
| Abolish Poison | 14253 | `periodMs` | `None` | `2000` |
| Abolish Poison | 14253 | `spellLevel` | `None` | `26` |
| Abolish Poison | 14253 | `subtext` | `None` | `Rank 1` |
| Lightning Mastery | 16166 | `name` | `Elemental Mastery` | `Lightning Mastery` |
| Stormstrike | 17364 | `cooldownMs` | `8000` | `6000` |
| Corruption | 17510 | `castMs` | `None` | `2000` |
| Corruption | 17510 | `category` | `None` | `0` |
| Corruption | 17510 | `durationMs` | `None` | `3000` |
| Corruption | 17510 | `icdMs` | `None` | `0` |
| Corruption | 17510 | `periodMs` | `None` | `1000` |
| Corruption | 17510 | `spellLevel` | `None` | `30` |
| Cripple | 18381 | `castMs` | `None` | `0` |
| Cripple | 18381 | `category` | `None` | `0` |
| Cripple | 18381 | `durationMs` | `None` | `30000` |
| Cripple | 18381 | `family` | `None` | `4` |
| Cripple | 18381 | `spellLevel` | `None` | `18` |
| Vengeance | 20050 | `maxStack` | `3` | `5` |
| Use Soulstone | 20758 | `icdMs` | `0` | `None` |
| Use Soulstone | 20759 | `icdMs` | `0` | `None` |
| Use Soulstone | 20760 | `icdMs` | `0` | `None` |
| Use Soulstone | 20761 | `icdMs` | `0` | `None` |
| Riptide | 408521 | `categoryCooldownMs` | `6000` | `12000` |
| Totemic Call | 437009 | `cooldownMs` | `60000` | `30000` |
| Totemic Call | 437009 | `name` | `Totemic Projection` | `Totemic Call` |
| Totemic Call | 437009 | `targetCode` | `0` | `None` |
| Riptide | 1239242 | `categoryCooldownMs` | `6000` | `12000` |
| Riptide | 1239243 | `categoryCooldownMs` | `6000` | `12000` |
| Holy Shield | 1239570 | `baseLevel` | `None` | `60` |
| Holy Shield | 1239570 | `castMs` | `None` | `0` |
| Holy Shield | 1239570 | `category` | `None` | `931` |
| Holy Shield | 1239570 | `categoryCooldownMs` | `None` | `10000` |
| Holy Shield | 1239570 | `cooldownMs` | `None` | `0` |
| Holy Shield | 1239570 | `durationMs` | `None` | `10000` |
| Holy Shield | 1239570 | `family` | `None` | `10` |
| Holy Shield | 1239570 | `gcdMs` | `None` | `1500` |
| Holy Shield | 1239570 | `icdMs` | `None` | `0` |
| Holy Shield | 1239570 | `procFlag` | `None` | `131752` |
| Holy Shield | 1239570 | `spellLevel` | `None` | `60` |
| Holy Shield | 1239570 | `subtext` | `None` | `Rank 4` |
| Slam | 1240193 | `categoryCooldownMs` | `18000` | `15000` |
| Fade | 1292765 | `castMs` | `None` | `0` |
| Fade | 1292765 | `category` | `None` | `0` |
| Fade | 1292765 | `durationMs` | `None` | `0` |
| Fade | 1292765 | `icdMs` | `None` | `0` |
| Fade | 1292765 | `procFlag` | `None` | `139944` |
| Fade | 1292765 | `spellLevel` | `None` | `40` |
| Slam | 1310196 | `categoryCooldownMs` | `18000` | `15000` |
| Slam | 1310197 | `categoryCooldownMs` | `18000` | `15000` |
| Slam | 1310198 | `categoryCooldownMs` | `18000` | `15000` |
| Slam | 1310199 | `categoryCooldownMs` | `18000` | `15000` |
| Slam | 1310200 | `categoryCooldownMs` | `18000` | `15000` |
| Fire Blast | 1316039 | `castMs` | `None` | `0` |
| Fire Blast | 1316039 | `category` | `None` | `0` |
| Fire Blast | 1316039 | `durationMs` | `None` | `0` |
| Fire Blast | 1316039 | `spellLevel` | `None` | `1` |
| Death Mark | 1316709 | `baseLevel` | `None` | `40` |
| Death Mark | 1316709 | `castMs` | `None` | `0` |
| Death Mark | 1316709 | `category` | `None` | `0` |
| Death Mark | 1316709 | `categoryCooldownMs` | `None` | `0` |
| Death Mark | 1316709 | `cooldownMs` | `None` | `10000` |
| Death Mark | 1316709 | `durationMs` | `None` | `6000` |
| Death Mark | 1316709 | `family` | `None` | `8` |
| Death Mark | 1316709 | `gcdMs` | `None` | `1000` |
| Death Mark | 1316709 | `icdMs` | `None` | `0` |
| Death Mark | 1316709 | `periodMs` | `None` | `6000` |
| Death Mark | 1316709 | `procFlag` | `None` | `2148182696` |
| Death Mark | 1316709 | `spellLevel` | `None` | `40` |
| Death Mark | 1316709 | `subtext` | `None` | `Rank 1` |
| Thunderstomp | 1320498 | `castMs` | `None` | `0` |
| Thunderstomp | 1320498 | `category` | `None` | `0` |
| Thunderstomp | 1320498 | `durationMs` | `None` | `0` |
| Death Mark | 1325756 | `baseLevel` | `None` | `48` |
| Death Mark | 1325756 | `castMs` | `None` | `0` |
| Death Mark | 1325756 | `category` | `None` | `0` |
| Death Mark | 1325756 | `categoryCooldownMs` | `None` | `0` |
| Death Mark | 1325756 | `cooldownMs` | `None` | `10000` |
| Death Mark | 1325756 | `durationMs` | `None` | `6000` |
| Death Mark | 1325756 | `family` | `None` | `8` |
| Death Mark | 1325756 | `gcdMs` | `None` | `1000` |
| Death Mark | 1325756 | `icdMs` | `None` | `0` |
| Death Mark | 1325756 | `periodMs` | `None` | `6000` |
| Death Mark | 1325756 | `procFlag` | `None` | `2148182696` |
| Death Mark | 1325756 | `spellLevel` | `None` | `48` |
| Death Mark | 1325756 | `subtext` | `None` | `Rank 2` |
| Death Mark | 1325757 | `baseLevel` | `None` | `56` |
| Death Mark | 1325757 | `castMs` | `None` | `0` |
| Death Mark | 1325757 | `category` | `None` | `0` |
| Death Mark | 1325757 | `categoryCooldownMs` | `None` | `0` |
| Death Mark | 1325757 | `cooldownMs` | `None` | `10000` |
| Death Mark | 1325757 | `durationMs` | `None` | `6000` |
| Death Mark | 1325757 | `family` | `None` | `8` |
| Death Mark | 1325757 | `gcdMs` | `None` | `1000` |
| Death Mark | 1325757 | `icdMs` | `None` | `0` |
| Death Mark | 1325757 | `periodMs` | `None` | `6000` |
| Death Mark | 1325757 | `procFlag` | `None` | `2148182696` |
| Death Mark | 1325757 | `spellLevel` | `None` | `56` |
| Death Mark | 1325757 | `subtext` | `None` | `Rank 3` |
| Death Mark | 1325758 | `baseLevel` | `None` | `60` |
| Death Mark | 1325758 | `castMs` | `None` | `0` |
| Death Mark | 1325758 | `category` | `None` | `0` |
| Death Mark | 1325758 | `categoryCooldownMs` | `None` | `0` |
| Death Mark | 1325758 | `cooldownMs` | `None` | `10000` |
| Death Mark | 1325758 | `durationMs` | `None` | `6000` |
| Death Mark | 1325758 | `family` | `None` | `8` |
| Death Mark | 1325758 | `gcdMs` | `None` | `1000` |
| Death Mark | 1325758 | `icdMs` | `None` | `0` |
| Death Mark | 1325758 | `periodMs` | `None` | `6000` |
| Death Mark | 1325758 | `procFlag` | `None` | `2148182696` |
| Death Mark | 1325758 | `spellLevel` | `None` | `60` |
| Death Mark | 1325758 | `subtext` | `None` | `Rank 4` |

Read the cooldown pair the way the generator does: the emitted `cooldownMs` is
`max(CooldownMs, CategoryCooldownMs)` and the `cooldownCategory` id rides
`Categories.Category` alone (D1 §2.1). Only four names touch the pair: `Slam` (five rows,
18000 → 15000), `Stormstrike` (8000 → 6000), `Riptide` (three rows, 6000 → 12000) and
`Totemic Projection` (60000 → 30000). The first three are exactly the post-9 dev-notes values
the store has now absorbed (§6). The `Use Soulstone` rows (3026, 20758-61) lost their captured
`icdMs: 0`: the store carries no `AuraOptions` row for them at 70790, absence is never a
reading (D1 §1), and the emitted ICD numbers ride the strict join, which keeps a probe value
when the store has no row. The `name` changes are the store's renames (§2.3).

### 2.2 Ids that gained store coverage (the `v` bit)

A coverage bit is not a value: it marks the ids the capture now reaches with at least one
value row (D1 §1). Tracked names it touches: `Abolish Poison` 14253, `Holy Shield` 1239570,
the four `Death Mark` ranks, `Cripple` 18381 (which also gains `family 4`), `Vengeance` 20050,
`Fade` 12685/1292765, `Fire Blast` 1316039, `Thunderstomp` 1320498, `Curse of Weakness` 8552,
`Corruption` 13530/17510, `Faerie Fire` 13752, `Disarm` 11879, `Pummel` 13491.

| id | name |
| --- | --- |
| 14253 | Abolish Poison |
| 13530 | Corruption |
| 17510 | Corruption |
| 18381 | Cripple |
| 8552 | Curse of Weakness |
| 1316709 | Death Mark |
| 1325756 | Death Mark |
| 1325757 | Death Mark |
| 1325758 | Death Mark |
| 11879 | Disarm |
| 12685 | Fade |
| 1292765 | Fade |
| 13752 | Faerie Fire |
| 1316039 | Fire Blast |
| 1239570 | Holy Shield |
| 13491 | Pummel |
| 1320498 | Thunderstomp |

### 2.3 `nameIndex` deltas (the store rows that ride a tracked name)

| tracked name | 70707 | 70790 |
| --- | --- | --- |
| `Blast Wave` | `[11113, 13018, 13019, 13020, 13021, 15091, 15744, 16046, 17145, 17277, 20229, 22424, 23039, 23113, 23331, 25049, 30092, 469161, 1231538, 1235318]` | `[11113, 13018, 13019, 13020, 13021, 15091, 15744, 16046, 17145, 17277, 20229, 22424, 23039, 23113, 23331, 25049, 30092, 469161, 1231538, 1235318, 1291176]` |
| `Blizzard` | `[10, 3068, 6141, 8364, 8427, 8428, 10185, 10186, 10187, 15783, 19099, 20680, 21096, 21367, 25019, 26607, 27618, 30093, 1213279, 1220862, 1279949, 1279976, 1279977, 1279978, 1279979, 1279980]` | `[10, 3068, 6141, 8364, 8427, 8428, 10185, 10186, 10187, 15783, 19099, 20680, 21096, 21367, 25019, 26607, 27618, 30093, 1213279, 1220862, 1271375, 1271394, 1279949, 1279976, 1279977, 1279978, 1279979, 1279980, 1291167, 1291168]` |
| `Chain Lightning` | `[421, 930, 1340, 2860, 10605, 12058, 15117, 15305, 15659, 16006, 16033, 16921, 20831, 21179, 22355, 23106, 23206, 24680, 25021, 27567, 28167, 28293, 408479, 408481, 408482, 408484, 429825, 446338, 450601, 461686, 461687, 463641, 463946, 465700, 468670, 468671, 1213477, 1244396, 1245324, 1257106, 1269904, 1270201, 1303551, 1321196]` | `[421, 930, 1340, 2860, 10605, 12058, 15117, 15305, 15659, 16006, 16033, 16921, 20831, 21179, 22355, 23106, 23206, 24680, 25021, 27567, 28167, 28293, 408479, 408481, 408482, 408484, 429825, 446338, 450601, 461686, 461687, 463641, 463946, 465700, 468670, 468671, 1213477, 1244396, 1245324, 1257106, 1269904, 1270201, 1283681, 1291380, 1303551, 1310513, 1321196, 1328034]` |
| `Charge` | `[100, 6178, 7370, 7371, 11578, 20508, 22120, 22911, 24023, 24193, 24315, 24408, 25821, 26177, 26178, 26179, 26184, 26185, 26186, 26201, 26202, 27685, 28343, 368127, 368368, 411684, 438538, 438540, 438541, 446367, 446369, 462937, 468500, 1213463, 1235538, 1240287, 1240288, 1240289]` | `[100, 6178, 7370, 7371, 11578, 20508, 22120, 22911, 24023, 24193, 24315, 24408, 25821, 26177, 26178, 26179, 26184, 26185, 26186, 26201, 26202, 27685, 28343, 368127, 368368, 411684, 438538, 438540, 438541, 446367, 446369, 462937, 468500, 1213463, 1235538, 1240287, 1240288, 1240289, 1283073, 1328028]` |
| `Curse of Tongues` | `[1714, 11719, 12889, 13338, 15470, 25195, 402794, 444046]` | `[1714, 11719, 12889, 13338, 15470, 25195, 402794, 444046, 1302039]` |
| `Curse of Weakness` | `[702, 1108, 1109, 6205, 7646, 8552, 11707, 11708, 11980, 12493, 12741, 17227, 18267, 21007]` | `[702, 1108, 1109, 6205, 7646, 8552, 11707, 11708, 11980, 12493, 12741, 17227, 18267, 21007, 1283361]` |
| `Demoralizing Roar` | `[99, 1735, 9490, 9747, 9898, 10968, 15727, 15971, 20753, 27551]` | `[99, 1735, 9490, 9747, 9898, 10968, 15727, 15971, 20753, 27551, 1310515]` |
| `Elemental Mastery` | `[16166]` | `None` |
| `Fear` | `[663, 5782, 6213, 6215, 12096, 12542, 22678, 26070, 26580, 27641, 27990, 29168, 30002, 411959, 469521, 469793, 469879, 1213452, 1222563, 1247087, 1271593, 1323802, 1324448, 1324451, 1324453]` | `[663, 5782, 6213, 6215, 12096, 12542, 22678, 26070, 26580, 27641, 27990, 29168, 30002, 411959, 469521, 469793, 469879, 1213452, 1222563, 1247087, 1271593, 1283934, 1313471, 1323802, 1324448, 1324451, 1324453]` |
| `Frost Armor` | `[168, 1200, 7300, 7301, 12544, 12556, 15784, 18100]` | `[168, 1200, 7300, 7301, 12544, 12556, 15784, 18100, 1283419]` |
| `Frost Nova` | `[122, 865, 6131, 9915, 10230, 11831, 12674, 12748, 14907, 15063, 15531, 15532, 22645, 29849, 30094, 463448, 1220855, 1289447]` | `[122, 865, 6131, 9915, 10230, 11831, 12674, 12748, 14907, 15063, 15531, 15532, 22645, 29849, 30094, 463448, 1220855, 1289447, 1300716, 1301016, 1310354]` |
| `Ghostly Strike` | `[14278]` | `[14278, 1329326]` |
| `Hurricane` | `[16914, 17401, 17402, 27530, 1278759, 1278965, 1278968, 1289129, 1289130, 1316319]` | `[16914, 17401, 17402, 27530, 1278759, 1278965, 1278968, 1289129, 1289130, 1316319, 1328040, 1328041]` |
| `Mortal Strike` | `[9347, 12294, 13737, 15708, 16856, 17547, 19643, 21551, 21552, 21553, 24573, 27580]` | `[9347, 12294, 13737, 15708, 16856, 17547, 19643, 21551, 21552, 21553, 24573, 27580, 1283414, 1294310, 1328019]` |
| `Shadowstep` | `[400029, 400037, 406722, 406754, 1231386]` | `[400029, 400037, 406722, 406754, 1231386, 1271753]` |
| `Shank` | `[15248, 15617]` | `[15248, 15617, 1329283, 1329549]` |
| `Shield Slam` | `[8242, 15655, 23922, 23923, 23924, 23925, 446354, 1213462, 1236179]` | `[8242, 15655, 23922, 23923, 23924, 23925, 446354, 1213462, 1236179, 1283081]` |
| `Stealth` | `[1784, 1785, 1786, 1787, 1791, 8822, 420536, 450667, 460228, 468879, 1234823, 1256867, 1270035, 1286462, 1287162, 1290708, 1300180, 1318151, 1326175]` | `[1784, 1785, 1786, 1787, 1791, 8822, 420536, 450667, 460228, 468879, 1234823, 1256867, 1270035, 1286462, 1287162, 1287444, 1290708, 1300180, 1318151, 1326175]` |
| `Sunder Armor` | `[7386, 7405, 8380, 11596, 11597, 11971, 13444, 15502, 15572, 16145, 21081, 24317, 25051, 27991, 365663]` | `[7386, 7405, 8380, 11596, 11597, 11971, 13444, 15502, 15572, 16145, 21081, 24317, 25051, 27991, 365663, 1283390]` |
| `Thrash` | `[3391, 3417, 8876, 12787, 21919, 369079]` | `[3391, 3417, 8876, 12787, 21919, 369079, 1290533]` |
| `Totemic Projection` | `[437009]` | `None` |

The two names that go empty are the store's own **renames**: 16166 is named
"Lightning Mastery" and 437009 "Totemic Call" at 70790. The generated data rides the
`_renames` alias law (D1 §7 item 4), so the class ByName table carries both spellings
(`["Elemental Mastery"] = 16166` plus `["Lightning Mastery"] = 16166`;
`["Totemic Projection"] = 437009` plus `["Totemic Call"] = 437009`) and the runtime twin in
`Forte_Core/Core/Locale.lua` stays right. The value flow is id-keyed, so a renamed row keeps
feeding its row — 437009's 30 s cooldown is in §3. The rest of the deltas are the new shells
joining a tracked name (§5.3).

## 3. The generated spell data: every row that moved

Before = the checked-in files at wave start, after = the regenerated files. "re-pick" = the
rank law resolved the tracked name to a different id; "coverage" = the same id, new fields.

| class | row | the change | player-visible |
| --- | --- | --- | --- |
| Druid | `Abolish Poison` | re-pick 2893 (rank-less base row) → 14253 `Rank 1`; every value identical (8000 ms window, 2 s tick, 1500 gcd) | no |
| Paladin | `Holy Shield` | re-pick 20928 `Rank 3` → 1239570 `Rank 4` (`SpellLevel` 60; the store's full Rank 4 row joined the capture). cd 10000 / cat 931 / dur 10000 / gcd 1500 unchanged; **the `noTarget = true` flag drops off** | yes — Forte_Timer's per-target row law now applies to the Holy Shield window (the flag is a base-row `RequiresPoint` capture a store row can not speak to; feeds law, upstream-data §7.5) |
| Rogue | `Shank` | re-pick 15617 (value-less Classic shell) → 1329549 `Rank 2`; new `cooldownMs = 10000`, `gcdMs = 1000` | yes — a 10 s bar where the row had none (§5.1) |
| Rogue | `Death Mark` 1325758 | coverage: bare row → `cooldownMs = 10000`, `durationMs = 6000`, `gcdMs = 1000`, `tickEvery = 6`, `rank = "Rank 4"` | yes — a 10 s bar plus a 6 s mark window on a 6 s tick |
| Shaman | `Chain Lightning` 10605 | `castMs` 2000 → 2500 | yes — the cast bar runs 2.5 s |
| Shaman | `Totemic Projection` 437009 | `cooldownMs` 60000 → 30000 | yes — the bar halves |
| Hunter, Mage, Priest, Warlock, Warrior | — | no row moved, no field moved | — |

Two header-level notes so the per-file counts are not read as extra value moves:

- `Shaman`'s header lists 14 overlay-applied rows: the two above plus the Shield trio
  (`Lightning Shield` 28821, `Earth Shield` 408514, `Water Shield` 408510 at `icdMs = 3500`),
  `Flurry` 16257 (`icdMs = 500`) and a rank-text move (`Flame Shock` `Rank 6` 29228 →
  `Rank 5` 10448). Those four ICD numbers were **already** in the shipped data from the probe
  era, so the capture re-confirms them. `Flame Shock` is rank text only: the store's Rank 6 row
  carries no cooldown at 70790 while Rank 5 carries the 6 s pair, and the pick's "carries the
  cooldown" leg ranks above the level leg. Emitted values (6000 cd, cat 19, 12000 dur, 1500 gcd,
  3 s tick) are unchanged.
- `Warrior`'s 7 changes are the `Slam` ladder (18000 → 15000, shipped from dev-notes since wave
  I-2b and now store-sourced) plus `Cripple` 18381 gaining `family 4`: 18381 leaves the Warrior
  pool, the pick stays **89** (the pin in `test_70707_overlay.lua`), and the emitted row is
  unchanged.

## 4. Items, enchants, consumables, procs (the 70862 leg)

- Counts byte-stable: on-use 238, procs 405 (400 item + 5 enchant), consumables 79, skipped
  no-cooldown consumables 27, "buff with no duration" onUse 54 / procs 205.
- Every consumed number is identical to the pre-refresh file: 707 of 707 item/consumable
  `cooldownMs` / `cooldownCategory` / `durationMs` values equal, **0 deltas**. That is D1 §3's
  finding restated on the new capture: the store's item-side deltas are wowsims-side category
  additions this file does not consume.
- Proc ICD claim, re-measured on 70790 for `Procs.lua`'s header: the store's `AuraOptions`
  covers 405 proc-buff auras, 125 of them carry an `ICDMs` column and every one reads 0; of the
  51 emitted `icdMs` rows only 7 have a store row, all 0. The capture therefore **confirms**
  **none** of the ICD windows and **contradicts none** — they stay launch-day probe material
  (`docs/research/forever-data-gaps.md` G2).
- Net deltas in `Items.lua` / `Procs.lua`: the header provenance lines (2 and 6 lines) and the
  ICD audit block. No data row moved.

## 5. The three live-session suspicions

### 5.1 Shank — confirmed; the refresh fixes it through the rank law

The shipped row was `[15617] = { id = 15617, name = "Shank" }`: a bare Classic shell with no
cooldown field at all. The capture's rogue rows:

```
[1329283] 70790  {"castMs": 0, "category": 0, "categoryCooldownMs": 0, "cooldownMs": 10000, "durationMs": 0, "family": 8, "gcdMs": 1000, "name": "Shank", "spellLevel": 24, "subtext": "Rank 1", "v": 1}
[1329549] 70790  {"castMs": 0, "category": 0, "categoryCooldownMs": 0, "cooldownMs": 10000, "durationMs": 0, "family": 8, "gcdMs": 1000, "name": "Shank", "spellLevel": 44, "subtext": "Rank 2", "v": 1}
[1329326] 70790  {"castMs": 0, "category": 0, "durationMs": 7000, "family": 8, "icdMs": 0, "name": "Ghostly Strike", "procFlag": 4112, "v": 1}
[  15617] 70790  {"name": "Shank"}
[  15248] 70790  {"name": "Shank"}
```

`15248`/`15617` are still value-less shells, so the name now resolves inside family 8 and the
pick lands on **1329549 (`Rank 2`, `SpellLevel` 44)** over 1329283 (`Rank 1`, `SpellLevel` 24) —
the level leg of the pick key — emitting
`{ id = 1329549, name = "Shank", cooldownMs = 10000, gcdMs = 1000, rank = "Rank 2" }`: the live
10 s cooldown with the 1000 ms off-global gcd, both straight out of the store's `Cooldowns`
(`CooldownMs: 10000, GCDMs: 1000`). `Forte_Timer/Core/Registry.lua` already bands `^Shank` in
the Cooldown band ("the post-9 rogue active (10 s cadence)") — that band now rides a real data
row instead of a bare name row. No hand-edit anywhere: the rank/family law picked it.

Report-side consequence: `Forte_Cooldown/tests/test_tracked_set.lua`'s `H7_UNTRACKED` note for
`Shank` ("the store's Shank rows (15248/15617) are value-less Classic name shells … the
launch-day probe row") and its `Death Mark` twin are now stale readings of the store: the
store carries rank rows with values for both. Tests are the owner's; untouched here (§8).

### 5.2 Arcane Blast — the pick rides the weapon-proc row; the 18 s buff rides no row

The store's "Arcane Blast" census at 70790 is 20 ids; the six that matter:

```
[  18091] 70790  {"castMs": 0, "category": 0, "categoryCooldownMs": 8000, "cooldownMs": 0, "durationMs": 0, "family": 3, "gcdMs": 1500, "icdMs": 0, "name": "Arcane Blast", "spellLevel": 35, "v": 1}
[ 400573] 70790  {"baseLevel": 1, "castMs": 0, "durationMs": 18000, "family": 3, "icdMs": 0, "maxStack": 4, "name": "Arcane Blast", "spellLevel": 1, "v": 1}
[ 400574] 70790  {"baseLevel": 20, "castMs": 1500, "category": 0, "categoryCooldownMs": 0, "cooldownMs": 0, "durationMs": 0, "family": 3, "gcdMs": 1500, "maxLevel": 28, "name": "Arcane Blast", "spellLevel": 20, "subtext": "Rank 1", "v": 1}
[1239697] 70790  {"baseLevel": 40, "castMs": 1500, "category": 0, "categoryCooldownMs": 0, "cooldownMs": 0, "durationMs": 0, "family": 3, "gcdMs": 1500, "maxLevel": 48, "name": "Arcane Blast", "spellLevel": 40, "subtext": "Rank 3", "v": 1}
[1239700] 70790  {"baseLevel": 60, "castMs": 1500, "category": 0, "categoryCooldownMs": 0, "cooldownMs": 0, "durationMs": 0, "family": 3, "gcdMs": 1500, "maxLevel": 68, "name": "Arcane Blast", "spellLevel": 60, "subtext": "Rank 5", "v": 1}
[ 401729] 70790  {"castMs": 0, "durationMs": 0, "family": 3, "name": "Arcane Blast", "spellLevel": 1, "v": 1}
```

- **The mage ladder the live build casts** is
  `400574 / 1239696 / 1239697 / 1239699 / 1239700` (`Rank 1`…`Rank 5`, `SpellLevel`
  20/30/40/50/60, `castMs 1500`, `gcdMs 1500`) and it carries **no cooldown at all**
  (`cooldownMs 0`, `categoryCooldownMs 0`, `category 0`). The manager's premise is the
  store's own word. mythicsim's live-audit code agrees exactly:
  `src/classes/mage/prepare/spell_data.rs:106-108` — `arcane_blast:`
  `Ladder::ranked(&[400574, 1239696, 1239697, 1239699, 1239700])`, and
  `arcane_blast_triggered: Ladder::ranked(&[400573])`. Hotfix push 113531 patched the buff to
  **18 s** (`src/prepare/hotfix_113554.rs:389-395`, "and 18 sec (was 15)"), and the store's
  `400573` carries `durationMs 18000` plus `maxStack 4` (the 4-stack window, `Labels [17]`).
- **18091 is the item-proc-style row.** mythicsim registers it as a **weapon proc**
  (`src/prepare/forever_items_generated.rs:176`:
  `buff_spell_id: 18091, is_weapon_proc: true, trigger_spell_id: 18091`). It has no rank label
  and no `baseLevel`/`maxLevel` ladder — the shape of the proc/consumable rows that carry a
  `CategoryCooldownMs` with `Category: 0`. The 70425 base carries 22 such rows (`Firebolt`
  13441, `Frost Blast` 16407, `Flame Wrath` 16559, `Mana Infusion` 28760, the `Food`/`Drink`
  rows …) and 18091 is the only class-coded one among them.
- **What our generator picks: 18091.** The pick key is (carries a window, carries a cooldown,
  MaxLevel/SpellLevel, casts, coverage, id); 18091 is the only Arcane Blast row that carries a
  cooldown, so the CD-carrier leg ranks it above the `Rank 5` L60 cast row (which carries no
  window at all) and above the 18 s buff row (a window, no cooldown). Measured on the live
  pool, not inferred.
- **How a fake cooldown shows on the bar.** `Engine.MIN_COOLDOWN = 2.99`, and `Engine:Build`
  reads `spell.cooldownMs / 1000` straight into `tracked[name].baseDuration`
  (`addon/Forte_Cooldown/Core/Engine.lua:178, 200`). An 8 s `cooldownMs` clears the gate, so the
  mage gets a tracked "Arcane Blast" with an 8 s base window: every cast draws an 8 s bar the
  client does not enforce. The learned-duration leg (`Engine.lua:229-230`, `:298`) replaces a
  base duration only once the client reports a recovery of its own — the real cast reports
  none, so the 8 s base stands for the session. On the Timer side `Registry.lua` bands
  `^Arcane Blast` in the **SelfDebuff** band (the 2012 original's `AddSelfDebuff(36032)`,
  `Mage.lua:67`), and SelfDebuff windows come from `durationMs`, which this row has none of:
  the 18 s / 4-stack window the client *does* run (400573) paints nothing.
- **This is not a refresh delta** — the row is byte-identical before and after (the store
  confirms the 8000), and the fix is a tracked-set call, not a data one: point the tracked name
  at the ladder (`Rank 5` = a 1.5 s cast plus a gcd row, no cooldown bar) and give `400573` its
  own row for the 18 s / 4-stack window. `ByName` is name-keyed, so the ladder and the buff can
  not both ride one name key — that is the alias / `_renames` law, i.e. the owner's
  tracked-set domain (D1 §1, §7 item 4). Flagged, deliberately not applied.

### 5.3 The 70840-era rows that share tracked names — the law holds

The manager's three: **Frost Armor 1283419**, **Blast Wave 1291176**, **Charge 1283073**. In the
70790 spell-store capture each carries a `Names` row and **no** `ClassOptions` row — no family
tag, no `Cooldowns`, no `Misc`, no `Levels`, no `Subtexts`, no `AuraOptions` (checked table by
table in the raw `spell_store_inputs.json`; 0 of the 30 new shells carries any row beyond
`Names`). They are the **index-shell** shape, not family-tagged cast rows: the family gate
never sees a family on them, so what protects the pick is the value tier — a value-less row
rides the bottom tier of the pick key, under every mythicsim rank row. The picked rows stay
the real ladder, and the 30 shells ride these 17 tracked names:

| tracked name | the picked row | new shells that joined its name |
| --- | --- | --- |
| `Frost Armor` | `7301` | 1283419 |
| `Blast Wave` | `13021` | 1291176 |
| `Charge` | `27685` | 1283073, 1328028 |
| `Blizzard` | `10187` | 1271375, 1271394, 1291167, 1291168 |
| `Shield Slam` | `23925` | 1283081 |
| `Curse of Weakness` | `11708` | 1283361 |
| `Sunder Armor` | `11597` | 1283390 |
| `Mortal Strike` | `21553` | 1283414, 1294310, 1328019 |
| `Chain Lightning` | `10605` | 1283681, 1291380, 1310513, 1328034 |
| `Fear` | `6215` | 1283934, 1313471 |
| `Stealth` | `1787` | 1287444 |
| `Thrash` | `21919` | 1290533 |
| `Frost Nova` | `10230` | 1300716, 1301016, 1310354 |
| `Curse of Tongues` | `11719` | 1302039 |
| `Demoralizing Roar` | `9898` | 1310515 |
| `Hurricane` | `1278759` | 1328040, 1328041 |
| `Shadowstep` | `400029` | 1271753 |

(`Ghostly Strike 1329326` is not a shell: it is a family-8 row with a 7 s duration and a proc
flag; it rides no cooldown, so the carrier leg leaves the pick on 14278.)

Mechanical proof: of the 33 ids that joined the capture, **exactly one** appears in
the generated data — `1329549`, the intended Shank `Rank 2` (§5.1). Appendix B marks the column.

**Forward risk, stated plainly**: these rows ride the *value* tier, not the family gate. A
capture that gives one of them a `Categories`/`Cooldowns` row would move it into the carrier
tier, where its own `SpellLevel` could win the level leg. The law that answers that is the
rank-label leg of the rank law (`KNOWN_RANK_LABELS` / `_renames`), which needs the real ladder
to carry rank text; a family check would not help, since these rows carry no family.

## 6. Dev-notes overlay: retired and kept rows

The HOTFIX-WATCH law: a row goes the day a store capture carries its value. Measured row by row
against the 70790 capture (`EQUALS-STORE` is the retirement condition; a disagreement blocks the
delete and is reported):

| id | the note | field | note value | 70790 | verdict |
| --- | --- | --- | --- | --- | --- |
| 1464 | Slam Rank 1 | `cooldownMs` | 15000 | 15000 | **retired** |
| 8820 | Slam Rank 2 | `cooldownMs` | 15000 | 15000 | **retired** |
| 11604 | Slam Rank 3 | `cooldownMs` | 15000 | 15000 | **retired** |
| 11605 | Slam Rank 4 | `cooldownMs` | 15000 | 15000 | **retired** |
| 1310200 | Slam Rank 5 (the picked row) | `cooldownMs` | 15000 | 15000 | **retired** |
| 17364 | Stormstrike | `cooldownMs` | 6000 | 6000 | **retired** |
| 408521 | Riptide Rank 1 | `cooldownMs` | 12000 | 12000 | **retired** |
| 1239242 | Riptide Rank 2 | `cooldownMs` | 12000 | 12000 | **retired** |
| 1239243 | Riptide Rank 3 | `cooldownMs` | 12000 | 12000 | **retired** |
| 20572 | Blood Fury (Orc racial) | `cooldownMs` | 120000 | *no store row* | **kept** |

- 10 rows → 1. **No row disagreed with the store**, so the retire-only-on-equality rule never
  blocked a delete. The report the law asks for: 9 retired, 0 disagreeing, 1 kept for absence.
- Retiring them moves **no emitted value** — the capture's value equals the note's, which is
  the precondition for the delete. The file deltas after the retire are the header bookkeeping
  lines (the dev-notes law line and the per-file overlay-change counts).
- `Blood Fury` 20572: the store carries no `Cooldowns` row for the id (24571, the other rank, has
  `Misc`/`Categories` rows and no `Cooldowns` row either) on either capture, so the field the note
  answers is one the capture can not answer and the 120 s measured value stays hand-kept. No spell
  list tracks the racial, so the row is inert by design and is the launch-day racial probe's pin.
- The overlay's `_meta` records the retirement, the 2026-11-07 date, and points at this section.

## 7. Player-visible changes (what the bars and timers will do differently)

| change | class | row | what the player sees |
| --- | --- | --- | --- |
| cast 2.0 s → 2.5 s | Shaman | `Chain Lightning` 10605 | the cast bar runs half a second longer |
| cooldown 60 s → 30 s | Shaman | `Totemic Projection` 437009 | the bar halves |
| new 10 s cooldown + 1 s gcd | Rogue | `Shank` 1329549 | Shank gets a cooldown bar where it had none |
| new 10 s cd, 6 s window, 6 s tick | Rogue | `Death Mark` 1325758 | a bar plus a 6 s mark window carrying a tick feed |
| rank re-pick (Rank 3 → Rank 4) | Paladin | `Holy Shield` 1239570 | the row loses `noTarget = true`, so the Timer keys the Holy Shield window per target instead of as one caster row |
| rank ladder inside the family | Rogue | 1329283 / 1329549 | `Shank` resolves to a rogue-family row (family 8) instead of a Classic shell |
| client renames | Shaman | 16166, 437009 | the live client spells them "Lightning Mastery" and "Totemic Call"; the alias rows carry both spellings, so a bar keeps working on either reading |
| nothing | Hunter, Mage, Priest, Warlock, Warrior; every item, enchant, consumable and proc row | — | zero value deltas |

Store deltas the pick law keeps **out** of the shipped data — reported, not shipped:

- `Vengeance` 20050 `maxStack` 3 → 5: the capture raised the paladin's Vengeance aura cap, and
  the row keeps `maxStack = 3` because the feeds law answers a stack count off the picked row's
  base `MaxStack` first, and a store capture "fills a field the earlier source can not speak to"
  (`tools/gen_spell_data.py`, `row_feeds`; upstream-data §7.5). The Timer's stack count for Vengeance
  therefore reads 3 where the client runs 5. A **feeds-law question** for the owner, not a
  refresh delta: the value *is* captured, the law declines it.
- The `Slam` / `Stormstrike` / `Riptide` pairs, which the data has carried since dev-notes and
  now carries from the store (§6).
- The `Use Soulstone` `icdMs` capture loss (§2.1): the strict join keeps the probe number.
- The 30 new name-only shells (§5.3) and the 22 coverage-bit rows (§2.2): captured shape, no
  emitted delta.

## 8. Verification run in this wave

```
python3 tools/extract_store.py --build 1.60.1.70707 --wowsims /tmp/wowsims-old \
        --commit 6e69a7f4f239c591e9dec4124a93fca6329c240f --out /tmp/replay_70707.json
#   -> spells / nameIndex / bookRanks / removed byte-identical to tools/overrides_70707.json

for c in druid hunter mage paladin priest rogue shaman warlock warrior; do
    python3 tools/gen_spell_data.py $c; done
python3 tools/gen_item_data.py            # Items.lua + Procs.lua
#   (both run twice; stamp-stripped byte compare of all 11 data files)
#   gate-law determinism (stamp-stripped bytes, all 11 data files): True

for f in addon/Forte_*/Data/*.lua; do luajit -e "assert(loadfile(\"$f\"))"; done   # 11/11 load
python3 -m py_compile -q tools/gen_spell_data.py tools/gen_item_data.py tools/extract_store.py
```

Deliberately **not** run in this wave: `scripts/gate.py` and the simulator suite (the manager
owns the one simulator). The places the suite will want the owner's hand, from the moves
above: `Forte_Cooldown/tests/test_tracked_set.lua` (the `H7_UNTRACKED` readings for `Shank`
and `Death Mark`, §5.1), `Forte_Cooldown/tests/test_70707_overlay.lua` (the `Cripple → 89` pin
stays true; the file's 70707 provenance wording is now historical), and `Forte_Timer`'s
feed / `noTarget` pins around the `Holy Shield` re-pick (§3).

## 9. Gate coupling the owner must decide (not changed in this wave)

`scripts/gate.py` (out of this wave's allowed scope) pins three **literal wave strings** in the
generated headers, so the refreshed headers as they now stand do not satisfy them:

| gate check | the literal it pins | what the refreshed headers say |
| --- | --- | --- |
| `check_70707_overlay` stamp | `^-- Store capture: 1\.60\.1\.70707 @ hotfix push 113562` | `-- Overlay: wowsims/forever 138964222220ad3f01634a7cc116c329a630a65e build 1.60.1.70790 (MIT)` + the next line's `(hotfix push 113715; assets/db_inputs/spell_store_inputs.json (gzip JSON); built by tools/extract_store.py …)` |
| `check_70707_overlay` change list | `-- 70707 overlay changes:` | `-- 70790 overlay changes in this file (N):` |
| `check_data_provenance` window | a `docs/research/*.md` cite inside the first 1800 characters | the cite lines ride below the per-file change list, so files with a long list (`Druid`, `Hunter`, `Mage`, `Paladin`, `Shaman`, `Warlock`, `Warrior`) push them out of the window |

The dev-notes pin (`-- Dev notes: tools/overrides_devnotes_2026-11-03.json`) is satisfied on all
nine class files, the provenance cite is inside the window on `Priest`, `Rogue`, `Items`, `Procs`,
and the item/procs headers carry the store-capture and `_meta` provenance lines.

Two lawful fixes, owner's call — they are the same decision the generator stamp generalisation is:
1. generalise the two pins to the live capture (`-- Overlay: … build <build>` + `hotfix push
   <push>`, and `overlay changes in this file`), and widen the provenance window (or move the
   cite lines above the change list, one generator line);
2. keep the wave-70707 pins as the historical gate and add a parallel live-capture check.

This wave deliberately did neither: the gate is the acceptance gate and is not a file this wave may
write. The refresh is byte-deterministic and syntactically clean under the generator law; the gate
wording is the one open hand.

## 10. Wave M3a: the §9 decision landed, and what M3a moved on the data side

Agent `DataFixM3a`, 2026-11-07 (working tree, uncommitted). §9's option 1 (generalise) is the one
taken; the data-side moves are the racials, the two pinned rows and the pins' disagreements.

**Gate provenance generalisation.** `scripts/gate.py` carries `data_provenance()`: it reads the
generator's `LIVE_OVERLAY = HERE / "overrides_<build>.json"` pointer and the referenced overlay's
`_meta`, then audits all 11 generated data headers against the meta itself — the
`-- Overlay: wowsims/forever <commit> build <build>` stamp, the `hotfix push <push>` line, the
`built by tools/extract_store.py` builder line (the capture, not a hand list), the mythicsim base
source line, and the `-- Dev notes: tools/overrides_devnotes_*.json` pointer on the nine class
files. The header's live `-- <label> overlay changes in this file (N):` line rides the same audit:
the label must name the live build (a stale `70707 overlay changes` header is exactly the §9 drift)
and its `(N)` must equal the bullet count. No literal wave string survives in the gate; the next
store capture moves one overlay file + the pointer and the provenance legs follow. The gate line
reads `[provenance] 11 generated data files audited against tools/overrides_70790.json (build
1.60.1.70790, all stamped)`.

**Holy Shield's `noTarget` (§3's 20928 → 1239570 re-pick).** The 70790 Rank-4 row (L60) carries the
durations (`durationMs 10000`, `categoryCooldownMs 10000`, category 931) but the capture speaks no
`Effects`/`Target` for it, and the 70425 base pull has no row under the picked id: the feed shape
(§3.4, the Registry's `noTarget` column) had no lawful source. M3a extended the generator's feed
law: for a picked row with no base row of its own, the SAME-FAMILY RANK SIBLING's base shape answers
— base row 20928 (Rank 3, family 10) has every captured effect targeting the caster, so the row
rides `noTarget = true` (header `feeds [1239570] Holy Shield: noTarget`). The CC-window registry
shape needs it: the self-proc window draws as one self row, not per-target rows.

**Arcane Blast → 400573, and how the bar stays clear.** §5.2's suspect resolved as a `_pins` row
(`tools/spell_lists/mage.json`): the tracked name now pins 400573 — the 18 s Arcane Focus self-buff
the player's cast applies (`durationMs 18000`, `maxStack 4`, `noTarget`, family 3). The live 70790
ladder carries NO cooldown for the name at all, and the only cooldown-carrying row of the name is
mythicsim's weapon-proc row 18091 — the item proc the Forte_ItemProcs Archeus row already rides;
tracking it was the fake 8 s cooldown bar. The bar stays clear by shape: 400573 carries no
`cooldownMs`, so `Engine:Build`'s `cd and cd >= MIN_COOLDOWN` gate never enlists it — there is no
Cooldown row to fade, nothing to pin away. The Timer side is the row's whole point: the Registry
moved `^Arcane Blast` from the SelfDebuff family (the T1 note: the original keyed the 18091 proc)
to SelfBuff, and the noTarget shape draws exactly one self row keyed `none` — the bulk-sweep
leg `Forte_Timer/tests/test_rows.lua` "a player Arcane Blast self-buff aura draws its Mage row"
pins the 18 s window and the 3-stack count riding the row.

**The racials moved into the generated data (review-10 M2/m4).** `Engine.RACIALS` — the hand-kept,
ID-keyed table — is retired; the rows ride the class data as the `racials` group (`racial = true`):
druid Berserking 20554 (`cooldownMs 180000`), hunter + paladin Rapid Regeneration 1260270
(`180000`), hunter Summon Hawk 1293527 (`cooldownMs 6000` off category 1173, `shares = "Arcane
Shot"`). `Engine:Build` skips the group (`not spell.racial` — the class-kit count contract
untouched); `Engine:AddExtras` walks the same generated rows with the id-aware known gate
(`isKnown(name)` OR `IsPlayerSpell(id)` — a racial is known by race, not by class spells). The
locale law is why the hand table had to go: its English `name` keys compared against canonicalised
client names and never matched on a deDE client (the racial tracked for nobody); the generated rows
feed `Locale.BuildSpellAliases` and the name keys are the data's. Runtime pins:
`test_locale_cooldown.lua` (German Berserken rides tracked and its cast lands) and
`test_m3a_engine_racials.lua` (the AddExtras half on the live engine). Registry kinds follow:
`^Rapid Regeneration` joins the SelfBuff family (the `^Regeneration` term start-anchored, the
dwarf's window starts with "Rapid").

**Id/cooldown disagreements on the record.**
- Summon Hawk: the retired hand table froze **1293241** — the 70425-era id slot. The 70790 capture's
  Rank 4 (the rank the class book carries) is **1293527**; id slots move between builds and the pin
  records the capture's, the `_pins` law.
- Summon Hawk's 6 s is NOT a spell cooldown: the pet-control (family-9) ladder carries
  `cooldownMs 0`; the shared 6 s lives on the Arcane Shot family-5 ladder as category 1173
  (`cooldownCategory 1173`, `CategoryCooldownMs 6000`). The row's `cooldownMs 6000` + `shares`
  encode the shared-category fact so a cast of either starts both — the M2 fact the pin records.
- Berserking: all four 70790 rows (20554/23505/24378/1286304) are value-less name shells — the store
  says NOTHING about a Berserking cooldown. The 180000 ms is NOT a store value: it is the dev-notes
  overlay row, hand-measured on the live client (owner session 2026-11-06), pinned to 20554 so the
  measured subject carries a stable id while the bare-row tiebreak would pick an arbitrary shell.
- Rapid Regeneration: 180000 agrees the hand table's owner number; the hand table's "channel" note
  rides nothing — the generated row is one 180 s window, no channel shape exists in the data law.
- The paladin roster carries Rapid Regeneration (Dwarf) but NOT Berserking, the hunter carries both
  the Dwarf window and Summon Hawk; the rosters are the class JSONs', the `_pins` reasons record
  the roster law per id.

Test-side moves in the same wave (the data-scope legs the refresh moves): `test_engine.lua`,
`test_tracked_set.lua`, `test_70707_overlay.lua`, `test_locale_cooldown.lua`,
`test_data_feeds.lua` (the Abolish Poison 2893 → 14253 feed line), `test_kinds.lua` (the Arcane
Blast SelfBuff band) — all fixtures following the regenerated rows, no law softened.

## Appendix A — every field change on a common id (170 rows)

The `v` rows are the coverage bit (§2.2); the rest are value fields.

| name | id | field | 70707 | 70790 |
| --- | --- | --- | --- | --- |
| Chain Lightning | 421 | `castMs` | `2000` | `2500` |
| Chain Lightning | 930 | `castMs` | `2000` | `2500` |
| Slam | 1464 | `categoryCooldownMs` | `18000` | `15000` |
| Chain Lightning | 2860 | `castMs` | `2000` | `2500` |
| Use Soulstone | 3026 | `icdMs` | `0` | `None` |
| Curse of Weakness | 8552 | `castMs` | `None` | `1000` |
| Curse of Weakness | 8552 | `category` | `None` | `0` |
| Curse of Weakness | 8552 | `durationMs` | `None` | `120000` |
| Curse of Weakness | 8552 | `spellLevel` | `None` | `14` |
| Curse of Weakness | 8552 | `v` | `None` | `1` |
| Slam | 8820 | `categoryCooldownMs` | `18000` | `15000` |
| Chain Lightning | 10605 | `castMs` | `2000` | `2500` |
| Slam | 11604 | `categoryCooldownMs` | `18000` | `15000` |
| Slam | 11605 | `categoryCooldownMs` | `18000` | `15000` |
| Disarm | 11879 | `castMs` | `None` | `0` |
| Disarm | 11879 | `category` | `None` | `0` |
| Disarm | 11879 | `durationMs` | `None` | `5000` |
| Disarm | 11879 | `spellLevel` | `None` | `30` |
| Disarm | 11879 | `v` | `None` | `1` |
| Fade | 12685 | `castMs` | `None` | `0` |
| Fade | 12685 | `category` | `None` | `0` |
| Fade | 12685 | `durationMs` | `None` | `10000` |
| Fade | 12685 | `spellLevel` | `None` | `40` |
| Fade | 12685 | `v` | `None` | `1` |
| Pummel | 13491 | `castMs` | `None` | `0` |
| Pummel | 13491 | `category` | `None` | `0` |
| Pummel | 13491 | `durationMs` | `None` | `5000` |
| Pummel | 13491 | `spellLevel` | `None` | `6` |
| Pummel | 13491 | `v` | `None` | `1` |
| Corruption | 13530 | `castMs` | `None` | `0` |
| Corruption | 13530 | `category` | `None` | `0` |
| Corruption | 13530 | `durationMs` | `None` | `3000` |
| Corruption | 13530 | `periodMs` | `None` | `1000` |
| Corruption | 13530 | `spellLevel` | `None` | `40` |
| Corruption | 13530 | `v` | `None` | `1` |
| Faerie Fire | 13752 | `castMs` | `None` | `0` |
| Faerie Fire | 13752 | `category` | `None` | `0` |
| Faerie Fire | 13752 | `durationMs` | `None` | `30000` |
| Faerie Fire | 13752 | `icdMs` | `None` | `0` |
| Faerie Fire | 13752 | `spellLevel` | `None` | `45` |
| Faerie Fire | 13752 | `subtext` | `None` | `Rank 2` |
| Faerie Fire | 13752 | `v` | `None` | `1` |
| Abolish Poison | 14253 | `castMs` | `None` | `0` |
| Abolish Poison | 14253 | `category` | `None` | `0` |
| Abolish Poison | 14253 | `categoryCooldownMs` | `None` | `0` |
| Abolish Poison | 14253 | `cooldownMs` | `None` | `0` |
| Abolish Poison | 14253 | `durationMs` | `None` | `8000` |
| Abolish Poison | 14253 | `gcdMs` | `None` | `1500` |
| Abolish Poison | 14253 | `icdMs` | `None` | `0` |
| Abolish Poison | 14253 | `periodMs` | `None` | `2000` |
| Abolish Poison | 14253 | `spellLevel` | `None` | `26` |
| Abolish Poison | 14253 | `subtext` | `None` | `Rank 1` |
| Abolish Poison | 14253 | `v` | `None` | `1` |
| Lightning Mastery | 16166 | `name` | `Elemental Mastery` | `Lightning Mastery` |
| Stormstrike | 17364 | `cooldownMs` | `8000` | `6000` |
| Corruption | 17510 | `castMs` | `None` | `2000` |
| Corruption | 17510 | `category` | `None` | `0` |
| Corruption | 17510 | `durationMs` | `None` | `3000` |
| Corruption | 17510 | `icdMs` | `None` | `0` |
| Corruption | 17510 | `periodMs` | `None` | `1000` |
| Corruption | 17510 | `spellLevel` | `None` | `30` |
| Corruption | 17510 | `v` | `None` | `1` |
| Cripple | 18381 | `castMs` | `None` | `0` |
| Cripple | 18381 | `category` | `None` | `0` |
| Cripple | 18381 | `durationMs` | `None` | `30000` |
| Cripple | 18381 | `family` | `None` | `4` |
| Cripple | 18381 | `spellLevel` | `None` | `18` |
| Cripple | 18381 | `v` | `None` | `1` |
| Vengeance | 20050 | `maxStack` | `3` | `5` |
| Use Soulstone | 20758 | `icdMs` | `0` | `None` |
| Use Soulstone | 20759 | `icdMs` | `0` | `None` |
| Use Soulstone | 20760 | `icdMs` | `0` | `None` |
| Use Soulstone | 20761 | `icdMs` | `0` | `None` |
| Riptide | 408521 | `categoryCooldownMs` | `6000` | `12000` |
| Totemic Call | 437009 | `cooldownMs` | `60000` | `30000` |
| Totemic Call | 437009 | `name` | `Totemic Projection` | `Totemic Call` |
| Totemic Call | 437009 | `targetCode` | `0` | `None` |
| Riptide | 1239242 | `categoryCooldownMs` | `6000` | `12000` |
| Riptide | 1239243 | `categoryCooldownMs` | `6000` | `12000` |
| Holy Shield | 1239570 | `baseLevel` | `None` | `60` |
| Holy Shield | 1239570 | `castMs` | `None` | `0` |
| Holy Shield | 1239570 | `category` | `None` | `931` |
| Holy Shield | 1239570 | `categoryCooldownMs` | `None` | `10000` |
| Holy Shield | 1239570 | `cooldownMs` | `None` | `0` |
| Holy Shield | 1239570 | `durationMs` | `None` | `10000` |
| Holy Shield | 1239570 | `family` | `None` | `10` |
| Holy Shield | 1239570 | `gcdMs` | `None` | `1500` |
| Holy Shield | 1239570 | `icdMs` | `None` | `0` |
| Holy Shield | 1239570 | `procFlag` | `None` | `131752` |
| Holy Shield | 1239570 | `spellLevel` | `None` | `60` |
| Holy Shield | 1239570 | `subtext` | `None` | `Rank 4` |
| Holy Shield | 1239570 | `v` | `None` | `1` |
| Slam | 1240193 | `categoryCooldownMs` | `18000` | `15000` |
| Fade | 1292765 | `castMs` | `None` | `0` |
| Fade | 1292765 | `category` | `None` | `0` |
| Fade | 1292765 | `durationMs` | `None` | `0` |
| Fade | 1292765 | `icdMs` | `None` | `0` |
| Fade | 1292765 | `procFlag` | `None` | `139944` |
| Fade | 1292765 | `spellLevel` | `None` | `40` |
| Fade | 1292765 | `v` | `None` | `1` |
| Slam | 1310196 | `categoryCooldownMs` | `18000` | `15000` |
| Slam | 1310197 | `categoryCooldownMs` | `18000` | `15000` |
| Slam | 1310198 | `categoryCooldownMs` | `18000` | `15000` |
| Slam | 1310199 | `categoryCooldownMs` | `18000` | `15000` |
| Slam | 1310200 | `categoryCooldownMs` | `18000` | `15000` |
| Fire Blast | 1316039 | `castMs` | `None` | `0` |
| Fire Blast | 1316039 | `category` | `None` | `0` |
| Fire Blast | 1316039 | `durationMs` | `None` | `0` |
| Fire Blast | 1316039 | `spellLevel` | `None` | `1` |
| Fire Blast | 1316039 | `v` | `None` | `1` |
| Death Mark | 1316709 | `baseLevel` | `None` | `40` |
| Death Mark | 1316709 | `castMs` | `None` | `0` |
| Death Mark | 1316709 | `category` | `None` | `0` |
| Death Mark | 1316709 | `categoryCooldownMs` | `None` | `0` |
| Death Mark | 1316709 | `cooldownMs` | `None` | `10000` |
| Death Mark | 1316709 | `durationMs` | `None` | `6000` |
| Death Mark | 1316709 | `family` | `None` | `8` |
| Death Mark | 1316709 | `gcdMs` | `None` | `1000` |
| Death Mark | 1316709 | `icdMs` | `None` | `0` |
| Death Mark | 1316709 | `periodMs` | `None` | `6000` |
| Death Mark | 1316709 | `procFlag` | `None` | `2148182696` |
| Death Mark | 1316709 | `spellLevel` | `None` | `40` |
| Death Mark | 1316709 | `subtext` | `None` | `Rank 1` |
| Death Mark | 1316709 | `v` | `None` | `1` |
| Thunderstomp | 1320498 | `castMs` | `None` | `0` |
| Thunderstomp | 1320498 | `category` | `None` | `0` |
| Thunderstomp | 1320498 | `durationMs` | `None` | `0` |
| Thunderstomp | 1320498 | `v` | `None` | `1` |
| Death Mark | 1325756 | `baseLevel` | `None` | `48` |
| Death Mark | 1325756 | `castMs` | `None` | `0` |
| Death Mark | 1325756 | `category` | `None` | `0` |
| Death Mark | 1325756 | `categoryCooldownMs` | `None` | `0` |
| Death Mark | 1325756 | `cooldownMs` | `None` | `10000` |
| Death Mark | 1325756 | `durationMs` | `None` | `6000` |
| Death Mark | 1325756 | `family` | `None` | `8` |
| Death Mark | 1325756 | `gcdMs` | `None` | `1000` |
| Death Mark | 1325756 | `icdMs` | `None` | `0` |
| Death Mark | 1325756 | `periodMs` | `None` | `6000` |
| Death Mark | 1325756 | `procFlag` | `None` | `2148182696` |
| Death Mark | 1325756 | `spellLevel` | `None` | `48` |
| Death Mark | 1325756 | `subtext` | `None` | `Rank 2` |
| Death Mark | 1325756 | `v` | `None` | `1` |
| Death Mark | 1325757 | `baseLevel` | `None` | `56` |
| Death Mark | 1325757 | `castMs` | `None` | `0` |
| Death Mark | 1325757 | `category` | `None` | `0` |
| Death Mark | 1325757 | `categoryCooldownMs` | `None` | `0` |
| Death Mark | 1325757 | `cooldownMs` | `None` | `10000` |
| Death Mark | 1325757 | `durationMs` | `None` | `6000` |
| Death Mark | 1325757 | `family` | `None` | `8` |
| Death Mark | 1325757 | `gcdMs` | `None` | `1000` |
| Death Mark | 1325757 | `icdMs` | `None` | `0` |
| Death Mark | 1325757 | `periodMs` | `None` | `6000` |
| Death Mark | 1325757 | `procFlag` | `None` | `2148182696` |
| Death Mark | 1325757 | `spellLevel` | `None` | `56` |
| Death Mark | 1325757 | `subtext` | `None` | `Rank 3` |
| Death Mark | 1325757 | `v` | `None` | `1` |
| Death Mark | 1325758 | `baseLevel` | `None` | `60` |
| Death Mark | 1325758 | `castMs` | `None` | `0` |
| Death Mark | 1325758 | `category` | `None` | `0` |
| Death Mark | 1325758 | `categoryCooldownMs` | `None` | `0` |
| Death Mark | 1325758 | `cooldownMs` | `None` | `10000` |
| Death Mark | 1325758 | `durationMs` | `None` | `6000` |
| Death Mark | 1325758 | `family` | `None` | `8` |
| Death Mark | 1325758 | `gcdMs` | `None` | `1000` |
| Death Mark | 1325758 | `icdMs` | `None` | `0` |
| Death Mark | 1325758 | `periodMs` | `None` | `6000` |
| Death Mark | 1325758 | `procFlag` | `None` | `2148182696` |
| Death Mark | 1325758 | `spellLevel` | `None` | `60` |
| Death Mark | 1325758 | `subtext` | `None` | `Rank 4` |
| Death Mark | 1325758 | `v` | `None` | `1` |

## Appendix B — the 33 ids that joined the capture

| id | name | store rows beyond `Names` | picked into the generated data |
| --- | --- | --- | --- |
| 1271375 | Blizzard | *none — name-only shell* | no |
| 1271394 | Blizzard | *none — name-only shell* | no |
| 1271753 | Shadowstep | *none — name-only shell* | no |
| 1283073 | Charge | *none — name-only shell* | no |
| 1283081 | Shield Slam | *none — name-only shell* | no |
| 1283361 | Curse of Weakness | *none — name-only shell* | no |
| 1283390 | Sunder Armor | *none — name-only shell* | no |
| 1283414 | Mortal Strike | *none — name-only shell* | no |
| 1283419 | Frost Armor | *none — name-only shell* | no |
| 1283681 | Chain Lightning | *none — name-only shell* | no |
| 1283934 | Fear | *none — name-only shell* | no |
| 1287444 | Stealth | *none — name-only shell* | no |
| 1290533 | Thrash | *none — name-only shell* | no |
| 1291167 | Blizzard | *none — name-only shell* | no |
| 1291168 | Blizzard | *none — name-only shell* | no |
| 1291176 | Blast Wave | *none — name-only shell* | no |
| 1291380 | Chain Lightning | *none — name-only shell* | no |
| 1294310 | Mortal Strike | *none — name-only shell* | no |
| 1300716 | Frost Nova | *none — name-only shell* | no |
| 1301016 | Frost Nova | *none — name-only shell* | no |
| 1302039 | Curse of Tongues | *none — name-only shell* | no |
| 1310354 | Frost Nova | *none — name-only shell* | no |
| 1310513 | Chain Lightning | *none — name-only shell* | no |
| 1310515 | Demoralizing Roar | *none — name-only shell* | no |
| 1313471 | Fear | *none — name-only shell* | no |
| 1328019 | Mortal Strike | *none — name-only shell* | no |
| 1328028 | Charge | *none — name-only shell* | no |
| 1328034 | Chain Lightning | *none — name-only shell* | no |
| 1328040 | Hurricane | *none — name-only shell* | no |
| 1328041 | Hurricane | *none — name-only shell* | no |
| 1329283 | Shank | `castMs`, `category`, `categoryCooldownMs`, `cooldownMs`, `durationMs`, `family`, `gcdMs`, `spellLevel`, `subtext` | no |
| 1329326 | Ghostly Strike | `castMs`, `category`, `durationMs`, `family`, `icdMs`, `procFlag` | no |
| 1329549 | Shank | `castMs`, `category`, `categoryCooldownMs`, `cooldownMs`, `durationMs`, `family`, `gcdMs`, `spellLevel`, `subtext` | **yes** |


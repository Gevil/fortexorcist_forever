# D1 — Data diff: our 70425-pinned data vs wowsims 70707 (H10)

Agent `DataDiff`, 2026-11-02. wowsims clone: `/tmp/wowsims-forever` @ `164d1cf6`.
Our side: `addon/Forte_<Class>/Data/<Class>.lua` + `addon/Forte_Items/Data/Items.lua`,
pinned to client **1.60.1.70425** (`mythicsim-forever-engine/data/manifest.json` `client_build`).

## Answer first

1. **The two builds agree on our 530 spells.** 505 rows byte-equal on every consumed field
   (cooldown, category, GCD, cast, duration, rank text). 16 rows differ, 5 exist in 70707's
   name table but carry no values in the wowsims store, 5 Paladin ids are **gone** in 70707
   (4 of them the name itself is gone), 34 best-rank drifts, 2 genuinely new ranks (Warrior
   Charge Rank 6, Druid Cower Rank 6). Items: **every item/consumable cooldown, category
   and duration that both sides carry is identical**; the only item-side deltas are
   wowsims-side category additions (not consumed by the addon), one maxStacks column,
   2 enchant spellId drifts, and coverage gaps in each direction.
2. **Rank model**: the default level-60 player at launch has the **trainer** ranks; the AQ20
   class-book ranks need book items ("The class books may not be there at launch, so nothing
   should need them by default" — wowsims `b6657d38`). Our pick lands on a **book rank for 13
   spells** (Revenge, Battle Shout, Immolate, Flame Shock, Aspect of the Hawk, Rejuvenation,
   Feint, Strength of Earth, Grace of Air, Blessing of Might/Wisdom, Greater Blessing of
   Might/Wisdom). "Current at level 60" is right *for a book owner*; for launch it should
   prefer the trainer rank (exclude wowsims' `bookRanks` ids).
3. **Recommendation: overlay, do not switch.** wowsims' store captures values for the 8,001
   ids its sims reach (32,052 names) — it is silent on 5 of our spell rows, on 261 of 405 proc
   buff spells, and on 72 of 238 on-use items; mythicsim carries the full item/consumable
   universe. Both sources are **MIT** (compatible with this repo's GPL-3.0). Apply the
   "must regenerate" table below as a per-id 70707 override stamped into the generated
   headers; keep mythicsim as the base; add the 99 wowsims consumable items as name coverage.

Schema, evidence, caveats below. All numbers reproducible from
`/tmp/fx_diff.py` + `/tmp/fx_items.py` (JSON dumps `/tmp/fx_diff.json`, `/tmp/fx_items.json`).

---

## 1. The wowsims 70707 store schema (how to read a row)

Source files: `assets/db_inputs/spell_store_inputs.json` (gzip JSON), readers
`tools/database/spelldata_inputs.go`, row model `sim/core/spelldata/spelldata.go`,
docs `docs/spell_data/store.md`, `docs/spell_data/reading-by-hand.md`.

The capture is raw game-file rows ("copied as the loaders in `spelldata_store.go` read
them" — `tools/database/spelldata_inputs.go:14`). **Scope law**
(`spelldata_inputs.go:16-24`, `captureStoreInputs` `:84-115`): every table is **cut to the
8,001 ids the sim's closure reaches** — *except* `Names`, which carries **every SpellName
row of the build (32,052)**. Consequence: "the id exists" is build-wide truth; "the value
is 0" from a missing table row is **absence, not a reading**. All times are ms, percentages
are integers (`store.md:3-8`).

| Store key | Row → field (game-file column) | Evidence |
|---|---|---|
| `Names[id]` | spell name (`Spell.Name_lang`) | `spelldata_inputs.go:89` |
| `Subtexts[id]` | rank text "Rank N" (`NameSubtext_lang`; empty ⇒ unranked) | `spelldata.go:26-27` |
| `Misc.CastTimeMs` | cast time (`SpellCastTimes.Base` via `CastingTimeIndex`) | `spelldata.go:49-50` |
| `Misc.DurationMs` | aura/DoT length; `-1` = permanent (kept as-is) | `spelldata.go:52-54` |
| `Cooldowns.CooldownMs` | own cooldown (`SpellCooldowns.RecoveryTime`) | `spelldata.go:56-58` |
| `Cooldowns.CategoryCooldownMs` | **shared-category cooldown** (`CategoryRecoveryTime`) — "the shared one Fire Blast and Cone of Cold run off" | `spelldata.go:56-58` |
| `Cooldowns.GCDMs` | GCD | `spelldata.go:58` |
| `Categories.Category` | category id (`SpellCategories.Category`; +`StartRecoveryCategory`, `ChargeCategory`) | `spelldata.go:60-61` |
| `AuraOptions.MaxStack` | aura stacks (`CumulativeAura`; 0 = one application) — NOT charges | `spelldata.go:70-71` |
| `AuraOptions.ProcCharges/ProcFlags/ICDMs` | proc rate/charges/internal CD (`ProcCategoryRecovery` = ICD) | `spelldata.go:79-88` |
| `Levels.{SpellLevel,BaseLevel,MaxLevel}` | rank's taught/scale levels; **no row ⇒ 60/60/0** ("no level scaling") | `spelldata.go:51-54` |
| `ClassOptions.{Family,Mask}` | class family (Mage 3 … Shaman 11 — same codes as our `gen_spell_data.py CLASS_FAMILY`) + class mask | `spelldata.go:97-99` |
| `Effects`, `Powers`, … | effects/costs | `spelldata_inputs.go:100-113` |

- The cooldown a player experiences is **`max(CooldownMs, CategoryCooldownMs)`**
  (`reading-by-hand.md` table: `max(rank.Cooldown(), rank.CategoryCooldown())`) — matching
  our generator's merged `cooldownMs` (`tools/gen_spell_data.py emit_entry`).
- **Charges:** the 70707 store row has *no* charges column (`MaxStack` is aura stacking,
  `ProcCharges` is proc uses; charges exist only in the legacy classic loader
  `tools/database/tables.go:1896,1978`). `spells.jsonl` carries no `Charges` key either
  (key census of first 3,000 rows). **Charges are not in either build's data** — our
  engine's charge model is runtime (`DetectCharges`/`entry.charges`, PLAN §9 `Reconcile`).
- Instant-cast sentinel: both builds use `CastTimeMs = -1000000` (e.g. store row 400009
  Between the Eyes; our `[14287] castMs = -1000000`); `-1` duration = permanent.
- Builds: all 12 input groups stamped `1.60.1.70707`, hotfix ≈ 113562
  (`spell_store_inputs.json` `Builds`/`Hotfixes`; groups: druid, hunter, items, mage,
  paladin, priest, racials, rogue, shaman, shared, warlock, warrior).

## 2. Spell diff, nine classes

Universe: names from `tools/spell_lists/*.json`; our row = the generated entry
(`[id] = {…}` line). 70707 match: by **id** in `Names` first; when absent, by **name** over
rows in the class's family (rows without a `ClassOptions` row count as uncoded Family 0,
the generator's own fallback rule, `gen_spell_data.py:186-206`). Field compare normalises
the sentinels (§1) and our merged `cooldownMs` vs `max(cd, catCd)`.

| class | names | unchanged | value-changed | present, no store row | id gone (name gone) | best-rank drift (new rank carries data) | new resolvable names (store-scoped) |
|---|--|--|--|--|--|--|--|
| Druid | 52 | 46 | 5 | 1 | 0 | 4 (Cower; +3 bare) | 30 |
| Hunter | 73 | 70 | 3 | 0 | 0 | 3 (all bare swaps) | 23 |
| Mage | 52 | 50 | 1 | 1 | 0 | 6 (Polymorph*, Slow Fall; +4 bare) | 43 |
| Paladin | 56 | 49 | 2 | 0 | 5 (4) | 3 (all bare swaps) | 33 |
| Priest | 47 | 47 | 0 | 0 | 0 | 3 (all bare swaps) | 41 |
| Rogue | 50 | 50 | 0 | 0 | 0 | 0 | 26 |
| Shaman | 61 | 61 | 0 | 0 | 0 | 6 (Shield Mastery; +5 bare) | 15 |
| Warlock | 76 | 70 | 5 | 1 | 0 | 8 (healthstone family; +7 bare) | 21 |
| Warrior | 64 | 62 | 0 | 2 | 0 | 1 (Charge) | 8 |
| **Σ** | **530** | **505** | **16** | **5** | **5 (4)** | **34** | **240** |

### 2.1 Value-changed rows (both builds carry the id) — full list

| class | spell | field | 70425 → 70707 | consumed by addon? |
|---|---|---|---|---|
| Druid | Shifting Power `1322605` | cooldownMs | **16000 → 8000** | yes — `Engine.lua:142-144` bar length |
| Druid | Wild Growth `1238215` | castMs | **None → 3000** | yes — Timer cast slice `Forte_Timer/UI/Rows.lua:709-712` |
| Druid | Lacerate `1235827` | rank | Rank 3 → Rank 5 | text only (no consumer) |
| Druid | Hurricane `1278759` | category | None → 571 | no (no consumer of `cooldownCategory`) |
| Druid | Faerie Fire `9907` | category | None → 1133 | no |
| Hunter | Intimidation `19577` | category | None → 1132 | no |
| Hunter | Freezing Trap `14311` | category | 2183 → 411 | no |
| Hunter | Frost Trap `13809` | category | 2183 → 411 | no |
| Mage | Arcane Wrath `1326082` | category | None → 2601 | no |
| Paladin | Swift Judgement `1310994` | durationMs | -1 (perm) → 0 | neutral — Timer gate is `dur > 0` either way (`Registry.lua:340-343`) |
| Paladin | Blessing of Sacrifice `20729` | category | None → 25 | no |
| Warlock | Healthstone `5720` | category | None → 30 | no |
| Warlock | Minor Healthstone `6262` | category | None → 30 | no |
| Warlock | Lesser Healthstone `6263` | category | None → 30 | no |
| Warlock | Greater Healthstone `5723` | category | None → 30 | no |
| Warlock | Major Healthstone `11732` | category | None → 30 | no |

Runtime consumption census (`grep` over `addon/`): `cooldownMs` →
`Forte_Cooldown/Core/Engine.lua:142-144`; `durationMs` → `Forte_Timer/Core/Registry.lua:14,339-343`;
`castMs` → `Forte_Timer/UI/Rows.lua:706-712`; on items `cooldownMs`+`categoryCooldownMs`+
`categoryId` → `Forte_Cooldown/Core/Items.lua:16-23,110-111`. `gcdMs`, spell
`cooldownCategory`, `rank`, `maxStacks`: **no consumers** ⇒ display-neutral.

### 2.2 Present in 70707, no value in the store (wowsims-silent)

Id is in the 70707 `Names` table (build-wide) but outside the sim-reached 8,001 ⇒ wowsims
carries no numbers; mythicsim 70425 values stand.
Primal Bite `1238073` (Druid), Searing Blast `16454` (Mage), Summon Voidwalker `25112`
(Warlock), Cripple `18381`, Howling Blade `13490` (Warrior). [INFERENCE] the sims never
touch these casts (pet/summon/offspec rows) — presence of the name proves the spell
exists on 70707.

### 2.3 Ids that no longer exist in 70707 — all Paladin

| spell | our id | 70707 |
|---|---|---|
| Salvation | 1038 | **name absent from all 32,052 names** |
| Mass Salvation | 25895 | name absent |
| Greater Blessing of Light | 25890 | name absent |
| Revoke | 1325499 | name absent |
| Blessing of Light | 19979 | id absent; the name survives on **26650** (bare row, no store values) |

[INFERENCE] the 70707 blessing/aggro-reduction rework removed or renamed these. Runtime is
name-keyed (`Module.lua:69-73`, `Engine.lua:17-19`), so the four dead rows simply stop
being `isKnown` — no crash, dead data weight. The Blessing of Light move needs a
live-client read (launch-day `/fx probe`).

### 2.4 Best-rank drifts (re-picking over 70707 with our own rule)

**Genuine rank moves** (the new best row carries numbers ours lacks):

| class | spell | our pick | 70707 pick | what it carries |
|---|---|---|---|---|
| Warrior | Charge | 1240289 "Rank 3" | **27685 "Rank 6"** | cd 25000, dur 4000, cat 44, SpellLevel 66 |
| Druid | Cower | 9892 "Rank 3" | **16697 "Rank 6"** | cd 5000, cat 82, SpellLevel 65 |
| Mage | Polymorph | 12826 "Rank 4" | 434754 **"Odd Melon"** | cd 5000, cast 2500, dur 20000, lvl 16 |
| Mage | Slow Fall | 130 | 12438 | dur 10000 |
| Shaman | Shield Mastery | 408525 | 426981 | dur 3000, lvl 1 |
| Warlock | Grimoire of Synergy | 426301 | 426303 | dur 15000 |
| Warlock | Minor/Lesser/Greater/Major Healthstone | 6262/6263/5723/11732 | 23469/23471/23475/23477 | category 30 (no consumed-field change) |

- Charge/Cower: **Rank 6 rows exist on 70707 with SpellLevel 66** — level-scaled rows above
  the 60 cap, [INFERENCE] a 70425→70707 ladder deepening (they are not the 70425 pick).
  Charge's tracked cooldown moves 15000 → 25000.
- **Polymorph is a pick-rule hazard**: at 70707 the (carries, cd, level, id) rule lands on
  the holiday "Odd Melon" cosmetic. The rule must exclude holiday/variant ranks
  (rank text not matching `Rank N`/known labels) — keep 12826.
- The remaining 24 drifts are **bare-row id ties** among value-less rows (Teleports,
  Cure Poison, Feed/Dismiss/Revive Pet, Resurrection, Purge, Purify, Dispel Magic,
  healthstone "use" rows, …): max-id tie-break shuffles which name-only twin is picked.
  No consumed value moves. One cosmetic: Hunter Black Arrow 14296 → 20734 (tie, both bare).

### 2.5 Names resolvable in 70707 that our lists lack (candidates)

Filter: store id, `ClassOptions.Family` = the class, `max(cd,catCd) ≥ 3000` **or**
duration > 0, name not in our list, name not `(OLD)`/`(TEST)`. Scope caveat: the value
tables exist only for the 8,001 sim-reached ids, so this is the **sim-visible slice of
70707**, not the client; Family-0 (uncoded) spells are untaggable and absent here.

240 distinct names (Druid 30 · Hunter 23 · Mage 43 · Paladin 33 · Priest 41 · Rogue 26 ·
Shaman 15 · Warlock 21 · Warrior 8; per-id row lists in `/tmp/fx_diff.json`). Genuine
missing class tools, examples: Mage **Arcane Blast** 18091 (8 s), **Blast Wave**,
**Combustion** 11129 (180 s), **Cone of Cold**, **Deep Freeze** 428739 (30 s), **Fire
Blast**; Priest **Contingency Plan**, **Dark Sacrifice**, **Desperate Prayer** (all 600 s);
Hunter **Savage Rend**, **Summon Hawk**, Battle Standard; Druid **Berserk** 417141 (180 s),
**Feral Charge (Bear/Cat)**, **Skull Bash** (bear/pet rows), **Starfall**, **Starsurge**.
These are candidates for `tools/spell_lists/*` (owner call), not defects.

## 3. Forte_Items: on-use 238 / procs 405 / consumables 79 vs 70707

Compared against `assets/database/db.json` (`items` 5,226 + `consumables` ~430 arrays; the
item-side counterpart of the store, same 70707 build) and the spell store for buff spells.
db.json is **sim-reach scope** — it carries full `itemEffects` on 501 of 5,226 items;
mythicsim's universe (12,042 items) is wider. Key law in our runtime: items match **by
name, never id** (`Forte_Cooldown/Core/Items.lua:11`).

| group | matched | value-equal | changed | wowsims-silent (id/name absent from its scope) |
|---|--|--|--|--|
| onUse 238 | 166 by itemId | 102 | **64 — category-only** (`categoryCooldownMs`+`categoryId` present in db.json, e.g. Defiler's Talisman 20072 cat 1155 180000 ms; category 1141 = the shared 10–20 s active-use band) | 72 (Abyss Shard, Ankh of Life, Lifestone, …) |
| procs 405 | **405 buffIds all exist in 70707 Names** | 143 of 144 comparable (261 buff spells outside the sim store) | 1 — Idol of the Huntress 227444 maxStacks 200 → 0 (MaxStack = CumulativeAura; no runtime consumer) | — |
| consumables 79 | 73 by itemId+name | **73 (every cooldown, category, duration identical)** | 0 | 6 (Conjured Crystal Water, Hyjal Nectar, Mountain Spring Water, Elixir of Wicked Regeneration, Greater Dreamless Sleep Potion, Major Discolored Healing Potion) |
| enchant procs 5 | 5 by effectId (1900, 7940–7943) | — | spellId drifts: Grand Arcanist db 1231152 vs our buffId 1231138; Grand Sorcerer db 1231163 vs our 1231162 (1-off id pairs) | — |

- Consumed impact of the 64 on-use "changes": **none** — the addon deliberately ignores
  on-use categories: onUse rows use "name, cooldownMs, slotType, classAllowlist" and the
  shared-category model is consumable-side (`Forte_Cooldown/Core/Items.lua:16-23`;
  `tools/gen_item_data.py:8` — `category_cooldown_ms` "NOT emitted" by design).
- **Coverage gaps in wowsims' favour**: 99 db.json items with a ≥2.99 s use cd or ≥60 s
  shared category are **not in our data** — the low-rank potion ladder (Minor/Lesser
  Healing & Mana Potions cat 4 120 s), Healing/Mana **Draughts** (300 s), the
  **Healthstone family items** (5509–5512, 19004–19006 cat 1153 120 s — we track the
  family via `Major Healthstone 9421` only, `Items.lua` data line 750), Swiftfeather
  Token (cat 28, 300 s), drinks (cat 59, 1 s — below MIN). Items are name-keyed at
  runtime, so a bag Minor Healing Potion is currently untracked. **Additive win, source
  = db.json consumables array.**
- **53 imbues** (oils/weightstones/spellstones; `temporaryEnchant`): none in our data; use
  cd = 1000 ms (GCD band, below `Engine.MIN_COOLDOWN 2.99`); the weapon-enchant window
  rides the live `C_Item.GetWeaponEnchantInfo` Enchants module (PLAN §9 Iteration C) ⇒
  display-neutral.
- **The 70707 "new items":** *Oil of Immolation 8956* is in **no** local data export — not
  wowsims db.json, not mythicsim's items/consumables jsonl. It is **mythicsim Rust-only**
  (`src/prepare/oil_of_immolation.rs:24-31`: item 8956, use spell 11350, 15 s aura, 3 s
  period, flat 50 Fire, 5 yds; README.md:542-545) — and its use spell is **in the 70707
  store**: `11350 "Fire Shield"` DurationMs 15000, periodic-trigger effect (period 3000,
  trigger 11351), `11351 "Fire Shield"` 50 Fire school damage — the Rust constants are the
  client rows'. *Shadow Oil* (item 3824, **enchant effectId 25**): present in wowsims data
  (db.json consumables 3824: use cd 1000, temp enchant 25 → proc buff 350026; ICD 10 s is a
  measured **override**, `tools/database/overrides/spell_overrides.go:226-231`), **absent**
  from mythicsim data and from our `Forte_Items`.
- **Proc ICDs** (context for D2): the store carries `ICDMs` per buff row, so the 144
  in-store proc buffs are ICD-comparable; wowsims' hand ICDs for the rest live in
  `spell_overrides.go`.

## 4. The rank model (trainer vs book) and our pick

wowsims' rank work (`git log --oneline`, `164d1cf6`):

- `b6657d38 [Core] Register every class book rank beside the trainer's, and let raid buffs
  pick a rank` — **"The class books may not be there at launch, so nothing should need
  them by default."** All class presets cast the **trainer** rank; book ranks register
  beside them and need a SIML suffix / opt-in toggle (off by default).
- `7535c880` (Hunter/Shaman): Serpent Sting IX, Aspect of the Hawk VII, Strength of Earth
  V, Grace of Air III "knew only the ranks the Ruins of Ahn'Qiraj class books teach, which
  may not be available at launch. Each trainer rank now registers beside its book rank,
  and … cast it."
- `93df312e`, `3163e1dc`, `031bed41`, `2cff8e92`: the trainer rank is the checked default;
  manifest rank pins compare "the rank below the top"; totem ranks share one meta.
- The book ranks are a **hand-kept 35-id list**, because "a book rank's SkillLineAbility
  row states it like a trained one" — the data itself does not mark them
  (`sim/core/spelldata/book_ranks.go:1-38`).

**Default at launch:** the top **trainer** rank (books are AQ20 loot — 25286 Heroic
Strike IX … 31016 Eviscerate IX). Group buffs (Gift of the Wild, Prayer of Fortitude,
Arcane Brilliance, Prayer of Shadow Protection) stay out of the list: books teach every
rank of those, no trained rank exists (`book_ranks.go:4-6`).

**Our pick** ("current at level 60": carries-window, carries-cd, level, id —
`gen_spell_data.py pick_current_rank`) re-selects the same row on 70707 in every case the
store lets us re-pick (24 of 34 drifts are value-free id ties) — **except** it lands on
**book ranks for 13 spells**: Rejuvenation 25299 XI, Aspect of the Hawk 25296 VII,
Blessing of Might 25291 VII, Blessing of Wisdom 25290 VI, Greater Blessing of
Might 25916 / Wisdom 25918 rank 2, Feint 25302 V, Flame Shock 29228 VI, Strength of Earth
25361 V, Grace of Air 25359 III, Immolate 25309 VIII, Revenge 25288 VI, Battle Shout 25289
VII. A bookless player's known rank is the trainer's (lower) rank; the runtime resolves the
**name** to what the character knows (`Module.lua:69-73`, `Engine.lua:17-19`), so the
tracked **number** is the only casualty: it comes from a rank they do not have
[e.g. Flame Shock rank 6 12000 ms duration vs the trainer rank's shorter one — the delta
per spell not measured here, [INFERENCE] it is the rank ladder's normal step].

**Verdict:** the pick is *right for a book owner, wrong-by-default for launch*. Fix in the
generator (D3): exclude `book_ranks.go` ids from the default pick (prefer trainer top);
book ranks behind an opt-in. This also kills the Polymorph→Odd Melon hazard (rank-text
filter).

## 5. Must regenerate (rows whose values change what the addon shows)

1. **Shifting Power 1322605** cooldownMs 16000 → **8000** (bar length).
2. **Wild Growth 1238215** castMs absent → **3000** (Timer cast slice).
3. **Charge (Warrior)** — adopt Rank 6 `27685` (cd **25000**, dur 4000, cat 44): tracked cd
   15000 → 25000.
4. **Cower (Druid)** — adopt Rank 6 `16697` (cd **5000**, cat 82): 10000 → 5000.
5. **Paladin structural:** drop/mark-for-probe Salvation 1038, Mass Salvation 25895,
   Greater Blessing of Light 25890, Revoke 1325499 (names gone in 70707); Blessing of
   Light id → 26650, values need the live read.
6. **Rank pick:** regenerate the 13 book-rank spells on trainer-preferred ranks (§4);
   keep Polymorph at 12826 by filtering variant rank texts.
7. **Coverage adds (not value changes):** the 99 db.json consumables (low-rank potions,
   draughts, healthstone items, Swiftfeather Token) into the consumable lists; the 240
   class-spell candidates (§2.5) into `tools/spell_lists/*` at the owner's call.

Display-neutral on 70707 (regenerate at leisure, not before launch): trap categories
2183→411, the 8 category additions, Lacerate rank text, Swift Judgement -1→0,
Idol of the Huntress maxStacks, the 64 on-use category additions, both enchant spellId
drifts, imbue 1 s uses, the 24 bare-row rank ties, 5 wowsims-silent spells.
**Every item/consumable cooldown, shared category and duration we consume is identical
between 70425 and 70707** (73/73 consumables, 100/100 comparable onUse) — the 120 s potion
family (cat 4), 120 s stone family (cat 1153) and Zanza-style tokens need no change.

## 6. Recommendation: overlay a 70707 override table, keep mythicsim as base

Measured reasons not to switch the generator wholesale to wowsims 70707:

- The store/values are **sim-scope, not build-scope**: our rows lose numbers on Primal
  Bite, Searing Blast, Summon Voidwalker, Cripple, Howling Blade (§2.2), on **261 of 405**
  proc buff durations and on **72 of 238** on-use items (§3) — wowsims simply never
  imports the spells its rotations do not cast.
- The item/consumable/enchant universe is mythicsim's (12,042 items, `consumables.jsonl`
  with the seconds-based category model our `gen_item_data.py` consumes).
- The 70425→70707 spell delta is tiny (§2.1: 16 rows; §2.3: 5; §2.4: 2 new ranks) — it fits
  a small override table; the D3 header "70425 → 70707 change list" is exactly that table.
- wowsims' own per-build drift tooling is `wowsims/gamedata` (`patches/1.60.1.70707/…`,
  PLAN §4) — not cloned here; clone it at D3 as the third leg of the cross-check.
- Licence fit (read from the files): wowsims/forever `LICENSE` = **MIT**
  ("Copyright (c) 2022 wowsims team"); mythicsim-forever-engine `LICENSE` = **MIT**
  ("Copyright (c) 2026 MythicSim contributors / Copyright (c) 2022 wowsims team");
  this repo `LICENSE` = **GPL-3.0**. MIT→GPL-3.0 data ingestion is compatible; the
  generated files already carry source+build stamps — extend the stamp to
  `mythicsim 70425 + wowsims 70707 overrides`.

Concretely for D3: `--wowsims-store assets/db_inputs/spell_store_inputs.json`
(gzip JSON, licence MIT, stamp 70707/hotfix 113562): after the mythicsim pick, for each
row whose id is in the store's value tables, re-read CooldownMs/CategoryCooldownMs/
GCD/Cast/Duration/Category/Subtext (instant sentinels normalised), print the per-row
change list; drop rows whose name vanished from `Names`; re-pick ranks with the
book-ids+variant-text exclusions; overlay the store's category fields onto on-use item
rows for data hygiene (unconsumed).

## 7. Open questions

1. **Salvation / Mass Salvation / Greater Blessing of Light / Revoke / Blessing of
   Light** — removed, renamed, or hotfix-hidden on live? Only the 70707 client can answer
   (`/fx probe` by name, `docs/launch-day.md`).
2. Are AQ20 book items obtainable at launch? (Owner call on the trainer-vs-book default.)
3. Charge Rank 6 / Cower Rank 6 (`SpellLevel` 66/65): trainer ranks, book ranks, or
   hotfix-only? Not in `bookRanks` [INFERENCE trainer], verify live.
4. The 5 wowsims-silent spells + 261 silent proc buffs: the live client's
   `C_Spell.GetSpellInfo` is the only remaining oracle for them.
5. `wowsims/gamedata` 70425→70707 patch set not examined locally (not cloned) — expected
   to corroborate §2/§3; clone at D3.
6. Enchant spellId drifts (Grand Arcanist 1231152, Grand Sorcerer 1231163 vs our
   1231138/1231162): our buffId is the *applied aura* id, wowsims' `spellId` is the
   *enchanting* spell — same number family, not evidence of drift; confirm at D3 when
   regenerating `enchants.jsonl`-sourced rows.

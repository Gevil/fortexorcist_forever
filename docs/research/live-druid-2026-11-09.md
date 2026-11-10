# Druid live check, 2026-11-09

Agent `RsrchDruid`, 2026-11-09. Read-only research. This file is the only thing I wrote in the repo.
Scope: `tools/spell_lists/druid.json` -> `addon/Forte_Druid/Data/Druid.lua` against the live client (1.60.1.70862) and the
Nov 6-10 Blizzard notes. What is already known (and not repeated): `docs/research/data-diff-live-2026-11-07.md`,
`docs/research/forever-postlaunch-2026-11-07.md`, `docs/class-port.md` §4.1.

**Labels.** [V] verified: a quote or value from a page or file I fetched, with URL/path and date. [D] derived: I computed it
from fetched data or read it in code; the method is next to it. [I] inference: my reading, nobody has tested it in the
game. [UNVERIFIED]: I could not check it.

## 0. Bottom line (ranked)

1. **[D] Three druid rows ride the wrong spell id; two of them put a wrong cooldown on the bar.**
   - `Dash` = 23110 (30 s). That is the **Hunter pet's Dash**. The druid's Dash is 1850/9821: Cat Form only, 15 s, **300 s** cooldown.
   - `Cower` = 16697 (5 s). That is the **Hunter pet's Cower**. The druid's Cower is 8998/9000/9892: Cat Form only, **10 s**, GCD 1 s.
   - `Abolish Poison` = 14253. That is the **on-use spell of the item Black Husk Shield** (item 4444). The druid spell is 2893.
     Duration and tick are identical (8 s, 2 s), so only the id is wrong.
   Cause: the generator lets a family-less store row join the in-family pool (§4). Three `_pins` fix it (§10).
2. **[D]/[I] Twelve names in the lists are not druid casts: four are set-bonus or talent procs, one is an item proc, and seven are
   Season-of-Discovery rune spells that Forever has no way to teach.** Astral Power, Force of Nature, Wild Rejuvenation and Fury of
   Stormrage are set/talent proc auras. Thrash is the Thrash Blade proc. Lifebloom, Skull Bash, Starfall, Savage Roar, Sunfire,
   Survival Instincts and Tree of Life are rune-era rows (Tiger's Fury has no list row; see §5). The runtime cost is near zero (Cooldown `Build` drops
   unknown names; a Timer row needs a cast event). It is a data-hygiene and test-pin problem (§5).
3. **[D] Every other generated druid row matches the live client.** I checked all 63 rows of `Data/Druid.lua` against the wago.tools
   DB2 exports for build 70862 (duration, cooldown, GCD, tick period). Differences: only Berserking's missing 15 s duration (§3).
4. **[D] The Nov 6 hotfix did not move a tracked value.** Between builds 70790 and 70862, exactly **one** druid-class client row
   changed: `Bear Form (Passive2)` 21178, threat 50 -> 115. FX tracks nothing from it (§8).
5. **[V] Nothing druid-specific is announced for Tuesday Nov 10.** The Nov 10 class tuning covers Hunter pets, Voidwalker,
   Affliction Warlock and Enhancement Shaman (§8).
6. **[D] The default-off druid cast announces carry 2012 durations that are wrong now:** Barkskin "(10 sec)" vs 15 s live,
   Frenzied Regeneration "(20 sec)" vs 10 s, Survival Instincts "(12 sec)" vs 20 s (§6).

## 1. Sources and method

| id | source | state when I read it |
|---|---|---|
| S1 | wago.tools DB2 CSV exports, `https://wago.tools/db2/<Table>/csv?build=1.60.1.70862` and `...70790` (SpellName, SpellMisc, SpellDuration, SpellCooldowns, SpellEffect, SpellClassOptions, SpellAuraOptions, SpellCategories, SkillLineAbility) | fetched 2026-11-09 (local copies `/tmp/w_*.csv`, `/tmp/sla_70862.csv`) |
| S2 | `/tmp/wowsims-forever` @ `9ca4d977` (2026-11-09): `assets/db_inputs/spell_store_inputs.json`, `sim/druid/**`, `sim/hunter/spell_data_auto_gen.go`, `sim/core/spelldata/spells_auto_gen.go` | pulled today; the pin in our data is `13896422` |
| S3 | `mythicsim-forever-engine` @ `ff6a43cf`: `data/spells.jsonl`, `src/classes/druid/**`, README Forever rules | local |
| S4 | https://foreverdb.net/class/Druid/abilities ("build 1.60.1.70862, extracted 2026-11-09") | fetched 2026-11-09 |
| S5 | https://wowforever.news/changes.html (datamined class changelog, "logged through 8 Nov", page stamp 9 Nov 18:20) | fetched 2026-11-09 |
| S6 | Blizzard: https://news.blizzard.com/en-us/article/24315281/wow-forever-hotfixes-november-6-2026 ; forum topics 2404092 (Class Tuning Nov 10), 2406595 (Nov 8 XP hotfix), 2403040 (hotfix thread) | fetched 2026-11-09 |
| S7 | https://foreverdiff.com/spells/skull-bash/ (Oct 22 build 70532) | fetched 2026-11-09 |

Method. (a) Parsed every row of `Data/Druid.lua` and compared duration, `max(RecoveryTime, CategoryRecoveryTime)`, GCD
(`StartRecoveryTime`) and the smallest positive `EffectAuraPeriod` with S1 at 70862. (b) Diffed S1 70790 vs 70862 for all 693 spells
with `SpellClassSet = 7` and for every id/name the druid sim or our data names (675 ids). (c) Diffed the live store pinned
by our overlay (`13896422`) against S2 `HEAD`. (d) Resolved each questionable pick against the sim's per-class rank ladders (S2),
`SkillLineAbility` (S1) and the ForeverDB trainer list (S4).

## 2. The items you listed

| item | verdict | evidence |
|---|---|---|
| Abolish Poison 2893 -> 14253 | **Wrong.** 14253 is Black Husk Shield's on-use spell. Pin 2893. | [D] 14253 has no `SkillLineAbility` row; `Forte_Items/Data/Items.lua:60` already lists item 4444 with `buffId = 14253, buffName = "Abolish Poison (14253)", cooldownMs = 300000`; 2893 has `ClassOptions` family 7, `StanceMask 1073741826`, and the sim uses `Abolish Poison = Ranked(2893)` (`sim/druid/spell_data_auto_gen.go:155`). [V] ForeverDB lists "Abolish Poison /spell/2893 (level 26)". |
| Thrash 21919 (uncoded fallback) | **Not a druid spell.** It is the Thrash Blade (item 17705) extra-attack proc. | [D] `sim/common/forever/stat_bonus_procs_auto_gen.go:3752-3757` ("trigger 21919 ... ItemName: Thrash Blade"); `Forte_ItemProcs/Data/Procs.lua:462` already tracks it as an item buff. No `thrash.go` in `sim/druid/`; none in the ForeverDB druid list. The 70862 client added a second Thrash row 1290533 (extra-attack effect, no family): also not druid [I]. |
| Lifebloom companion row 408124 | **Pick is right; learnability is doubtful.** | [D] 408124 = the ability: 7 s, tick 1 s, 3 stacks, GCD 1 s, ICD 2000 (store). 408245 = bare "Heals the target over 7 sec" (heal effect only). 409824 = the granting aura (aura 332 -> 408124, -0.5 s GCD on Rejuvenation and Lifebloom). Only 408124 carries a window, so the companion-shadow law picks it (`gen_spell_data.py:96-107`). `SkillLineAbility` marks 408124/408245 `AcquireMethod 3` (granted, not trained). Not in the ForeverDB list, not a trait node. [I] a rune spell (§5). |
| Bloom 1328621 | Correct as an announce row, not a bar. | [D] store: two dummy effects (100 and 50), no duration, no heal spell; description "healed for an amount equal to $s1% of your Spirit ... dispelled -> $s2%". Trait node, `TaughtBySkillLine = false` (Resto talent). [V] Nov 6: "Bloom will now correctly heal the target." No client row changed. |
| Bear Form / Swiftmend / Ravage / Pounce hotfixes (Nov 6) | **Tooltip or server-side only; no tracked value moved.** | [V] S6 text, §8. [D] S1 diff: no tracked id differs between 70790 and 70862 (§8). Pounce: the only Pounce line is the Shadowmeld exploit fix; Pounce 9827 (stun 2 s) and Pounce Bleed 9826 (18 s, 3 s tick) match the client. |
| Ravage numbers | Tooltip 343 -> 426 flat, 435% weapon; no damage change. | [V] S5 "Ravage: 4 ranks changed. Rank 4 ... 435% damage plus 426 (343 -> 426)"; Blizzard: "There was no change made to damage done." Not a tracked spell. |
| Primal Bite | Correct (1238070, Rank 3, 6 s, category 971). | [D] client 70862; sim `PrimalBite = Ranked(407995, 1238069, 1238070)` (`sim/druid/spell_data_auto_gen.go:252`). Talent, trait node, level 60 in store. |
| Feral Charge | Correct (1238122, 15 s, category 2182). | [D] client 70862. Trait node (tier 3, level 20). [V] foreverdiff: Skull Bash "Shares a cooldown with Feral Charge" (category 2182 on both). Skull Bash is not learnable (§5), so Feral Charge shares only with itself. |
| Starfall | Rune-era row; not learnable. | §5. |
| Astral Power 467088 | **Not a cooldown.** It is the proc aura of the T2 Balance 6-piece bonus. | [D] `sim/core/spelldata/spells_auto_gen.go:28837-28843`: "S03 - Item - T2 - Druid - Balance 6P Bonus" (467090, 50% on crit) triggers 467088 (15 s, 3 stacks, +10% modifier). The 180 s "cooldown" is the proc ICD. No SkillLine, no GCD, no cast time. |
| Eclipse | Real Forever talent (408248, 3 ranks); the aura 408255 (15 s, 4 stacks) is a proc. Keep it out of the bars. | [D] trait node 408248 (`TaughtBySkillLine = false`); 408255 `MaxStack 4`, 15 s. [V] mythicsim commit `28cf4043` (2026-11-05): "Wrath gives two charges unless it misses"; the aura's `ProcTypeMask_0 = 65536` (harmful spell damage). [I] cast-predict on Wrath would draw a bar for a Wrath that missed. `docs/class-port.md` rows `Druid.lua:95-96` look up "eclipse (solar)" / "eclipse (lunar)" and correctly find none; the plain name `Eclipse` exists with a different mechanic (Wrath -> cheaper Starfire). |
| Lacerate stacks (wowsims) | 5 stacks, 15 s, 3 s tick; matches our row. | [D] store `MaxStack 5`; `sim/druid/lacerate.go`: each landed cast adds a stack (cap `dot.MaxStacks`), refreshes the dot, ticks scale by stack count. Five ranks: 1328617 (L25), 1328616 (L34), 414644 (L42), 1235826 (L50), 1235827 (L58) (`spell_data_auto_gen.go:218`). The weapon hit is a separate row 414647 that is never the cast id (`lacerate.go:9`: "every SPELL_MISSED in the log names the rank, never 414647"). |

## 3. Durations, ticks, cooldowns against the live client

All values [D] from S1 (build 70862) and the live store (S2); both agree with the generated row unless marked.

| spell (row id) | duration | tick | cooldown / GCD | note |
|---|---|---|---|---|
| Rejuvenation (9841, R10) | 12 s | 3 s | GCD 1.5 s | R11 25299 is an AQ20 book rank, excluded by `bookRanks` (`sim/core/spelldata/book_ranks.go`, unchanged since 2026-11-01); same 12 s / 3 s |
| Regrowth (9858, R9) | 21 s | 3 s | cast 2 s | |
| Lifebloom (408124) | 7 s | 1 s | GCD 1 s; 3 stacks; ICD 2 s | §5 |
| Rip (9896, R6) | 12 s | 2 s | GCD 1 s | [V] S5: "damage over 12 sec" |
| Rake (9904, R4) | 9 s | 3 s | GCD 1 s | [V] S5: "additional 126 damage over 9 sec" |
| Moonfire (9835, R10) | 12 s | 3 s | | |
| Insect Swarm (24977, R5) | 12 s | 2 s | | Balance talent in Forever |
| Sunfire (414684) | 12 s | 3 s | | rune row (§5) |
| Pounce Bleed (9826, R3) | 18 s | 3 s | | stun 2 s on Pounce 9827 |
| Lacerate (1235827, R5) | 15 s | 3 s | 5 stacks | |
| Entangling Roots (19970 / 9853, R6) | 27 s | 3 s | cast 1.5 s | the two ids are byte-identical rows; 19970 is Nature's Grasp's trigger row (`sim/druid/spell_data_auto_gen.go:239`), harmless (§4) |
| Wild Growth (1238215, R3) | 7 s | 1 s | cd 6 s, cast 3 s | |
| Tranquility (9863, R4) | 10 s | 2 s | category cd 300 s (cat 46) | |
| **Innervate** (29166) | 20 s | | **cd 360 s**, GCD 1.5 s | |
| **Barkskin** (22812) | 15 s | | **cd 60 s** | duplicate row 428713, same values |
| **Frenzied Regeneration** (22842) | 10 s | 1 s | **category cd 180 s** (cat 1011), GCD 1.5 s | Bear Form |
| **Enrage** (5229) | 10 s | | **cd 60 s**, off-GCD | Bear Form |
| **Dash** (9821, R2; 1850 R1) | 15 s | | **category cd 300 s** (cat 44), off-GCD | Cat Form only; our data says 30 s (§4) |
| **Tiger's Fury** | no grant found | | | §5 |
| Nature's Swiftness (17116) | until used | | cd 180 s | |
| Nature's Grasp (17329, R6) | 45 s | | cd 60 s (cat 531) | |
| Swiftmend (18562) | | | cd 15 s | |
| Primal Bite (1238070) | | | cd 6 s (cat 971) | |
| Feral Charge (1238122) | | | cd 15 s (cat 2182) | |
| Shifting Power (1322605) | | | cd 8 s, GCD 1 s | store 8 s (the 70425 base said 16 s; "Improved Shifting Power" was folded in, S5 70755) |
| Challenging Roar / Growl / Bash (R3) / Prowl / Rebirth | 6 s / 3 s / 4 s / - / - | | 600 s / 8 s / 60 s / 10 s (cat 38) / 1800 s (cat 26) | |
| Clearcasting (16870) | 15 s | | proc aura | Omen of Clarity 16864 is a level-20 trainer passive; the sim's comment: 2.0 procs per minute, Maul rolls at half (`sim/druid/omen_of_clarity.go`) |
| Eclipse aura (408255) | 15 s | | 4 stacks | proc (§2) |
| Berserking (20554) | **15 s** | | cd 180 s | our row has the cd, **no `durationMs`** (§9 last bullet, §10 F) |

[D] The client carries cooldown 180000 for Berserking 20554 in both 70790 and 70862 (`SpellCooldowns` row 55527). That
independently replicates the owner's hand measurement; the store has no row for it.

## 4. Why the wrong ids were picked (mechanism)

[D] `gen_spell_data.py:819-823` (`own_pred`): in the store-aware run, a store row with **no family** counts as in-family. Rows
14253, 16697 and 23110 are store rows with no `ClassOptions` row (`tools/overrides_70790.json`: no `family` key), so they
compete with the real druid rows. The pick key is (window, cooldown, level, cast, store-coverage, id):

| name | real druid row | wrong row that won | why it won |
|---|---|---|---|
| Abolish Poison | 2893 (family 7, L26) | 14253 (family-less, L26) | level tie, higher id |
| Cower | 9892 (family 7, L52) | 16697 (family-less, L55) | higher level |
| Dash | 9821 (family-less, L46) | 23110 (family-less, L50) | higher level; no family-7 Dash row exists at all |
| Entangling Roots | 9853 | 19970 | identical rows, higher id (cosmetic) |
| Hurricane | 17402 (cast row, tick 1 s) | 1278759 (triggered row) | same level, higher id; costs the 1 s tick feed (cosmetic) |

Proof of identity [D]:
- Dash. `sim/hunter/spell_data_auto_gen.go:279`: `DashTriggered = Ranked(23099, 23109, 23110)`; the hunter pet's Dash.
  `sim/druid/spell_data_auto_gen.go:174`: `Dash = Ranked(1850, 9821)`. Core spell data (`spells_auto_gen.go:1503-1506`): 1850 has
  `StanceMask 0x1`, `CategoryCooldownMs 300000`, `SpellLevel 26`; the store's `Shapeshift` row for 1850/9821 is mask 1; 23099/23109/23110
  have no stance and GCD 1500. `SkillLineAbility` (70862) puts 23099/23109/23110 in pet skill lines (208-251) and 1850/9821 in
  skill line 134 (Druid Feral). [V] ForeverDB: "Dash /spell/1850 (level 26)".
- Cower. `sim/hunter/spell_data_auto_gen.go:277`: `CowerTriggered = Ranked(1742, ..., 16697)`; `sim/druid/spell_data_auto_gen.go:172`:
  `Cower = Ranked(8998, 9000, 9892)`. `SkillLineAbility`: 16697 in pet skill line 270; 8998/9892 in line 134. [V] ForeverDB: "Cower /spell/8998 (level 28)".
- Abolish Poison. 14253 has no `SkillLineAbility` row and its client text is the item-use text.
- `docs/research/data-diff-70707.md:159,285,338-339` adopted Cower 16697 as "a 70425->70707 ladder deepening" with the question
  "trainer ranks, book ranks, or hotfix-only? ... verify live". **This answers it: it is none of those; it is the pet's spell.**
  [I] The Warrior row `Charge 27685` from the same table is probably the same kind of mistake: `sim/core/spelldata/spells_auto_gen.go:22393`
  shows 27685 is taught by a pet-targeted learn effect (28343). I did not check it further; it is outside this class.

What it does on the bar [D]/[I]. `Engine:Build` (`Forte_Cooldown/Core/Engine.lua:159-167`) keys the tracked set on the **name** and
takes `baseDuration` from the picked row's `cooldownMs`. So on a druid that knows Dash, a cast predicts **30 s** where the real
cooldown is 300 s, and a Cower cast predicts **5 s** where the real one is 10 s. In combat a cooldown read is secret
(`AGENTS.md`), so the prediction stands until the out-of-combat read corrects it: a false "Dash ready" at 30 s. The Timer rows are
name-keyed, so Abolish Poison, Dash and Cower timers still draw; only icon and rank labels follow the wrong id.

**Re-extraction watch (not a defect today).** [D] The druid store group is still stamped 70790 / hotfix 113715 in S2 `HEAD`, so the next
re-extraction will not move a druid value (§8). It will turn the Lacerate hit row 414647 from a name-only row into a value row (family 7,
no rank, duration 0, no cooldown). It does not carry a window, so the window-first key keeps 1235827. Four same-name rows gained
client values between 70790 and 70862: Thrash 1290533, Demoralizing Roar 1310515, Hurricane 1328040/1328041. All family-less, no level;
the level key protects the current picks (Thrash 21919 has level 50; the others lose to the level-52/60 rank rows). Re-read those
names after the next store capture.

## 5. Rows that are not druid casts on Forever

Evidence for "no way to learn it" [D]/[I]: ForeverDB's complete druid ability list for client 70862 (trainer + class-quest abilities)
has none of them [V]; none is a druid trait node [D] (52 druid nodes in the store; Eclipse, Bloom, Feral Charge, Primal Bite, Shifting Power
are nodes); the pinned API catalog classifies `C_Engraving` as **classic only** (`docs/api/.../NAMESPACE-LOOKUP.md:99`) and the Forever
item data has no "Rune of ..." item (0 of the `items.jsonl` rows) [D]. `SkillLineAbility` lists them with `AcquireMethod 3`
(granted by another spell), the same value as the rune spells Nourish, Efflorescence, Starsurge, Swipe (411128) [D].
foreverdiff says Skull Bash "is the Skull Bash rune for the Gloves, applied by Engrave Gloves - Skull Bash ... taught by Rune of Skull Bash"
(Oct 22 build; [V]).

| name | id | what it is | confidence | basis |
|---|---|---|---|---|
| Astral Power | 467088 | proc aura of T2 Balance 6P bonus (467090) | **high** | [D] `spells_auto_gen.go:28837-28843` |
| Force of Nature | 467079 | summon from T2 Balance 4P bonus (467084, 10%, ICD 15 s) | **high** | [D] `spells_auto_gen.go:28833` |
| Wild Rejuvenation | 1226046 | proc of the Scarlet Enclave Resto 6P bonus (1226044) | **high** | [D] `spells_auto_gen.go:32145` |
| Fury of Stormrage | 414800 | triggered by talent proc 414799 (12% on damage) | **high** | [D] `spells_auto_gen.go:25345-25348` |
| Thrash | 21919 | Thrash Blade proc | **high** | §2 |
| Lifebloom | 408124 | rune spell (granted by 409824) | med | S4, SkillLineAbility, no node |
| Skull Bash | 410176 | rune spell (Gloves) | med-high | S7 text, S4 |
| Starfall | 439748 | rune row (SkillLine 574, acq 3); Forever's Balance list has no Starfall | med | S4 |
| Sunfire | 414684 | rune row (SkillLine 574, acq 3) | med | S4 |
| Savage Roar | 407988 | not in S4; no node | med | S4 |
| Survival Instincts | 408024 | rune row (SkillLine 134, acq 3) | med | S4 |
| Tree of Life | 439745 | form-style rune row; not in S4; no node | med | S4 |
| Tiger's Fury | 5217, 417045, 1289238, 1312152 | the client carries four rows: 5217 (6 s, cd 30 s), 417045 (rune version, energize 60), 1289238 (10 s, +25% damage), 1312152 (permanent +15%); the store has them as name-only shells; 5217 and 417045 are `AcquireMethod 3`; not in S4; the sim has no Tiger's Fury | med | **[UNVERIFIED] whether anything grants it.** The two 12892xx/13121xx ids are Forever-era rows, so something was built; I could not tell what. Keep it out until a live probe. |
| Living Seed, Savage Defense (the `_deferred_H7` names) | 414680, 410144 | rune rows (`SkillLineAbility` 414683 acq 3 is the Living Seed grant); not in S4 | med | |

[I] None of the rows in this table can cost us a wrong number today, because they only draw if the player casts them. The risk is
that someone later reads "tracked" as "castable". One live check closes the whole table: on a druid, run `C_SpellBook.IsSpellKnown(id)`
/ `IsPlayerSpell(id)` for 408124, 410176, 439748, 414684, 407988, 408024, 439745, 5217 and 417045.

## 6. Form-specific spells and the announce rows

[D] Raw store `Shapeshift` masks of the tracked castables (only the bits the evidence supports are decoded):

| mask | meaning | spells |
|---|---|---|
| 1 | Cat Form only (Shifting Power's `CasterAura = 768` and `StanceMask 1`) | Rip, Rake, Ferocious Bite, Pounce, Prowl, **Dash**, Shifting Power, **Cower** |
| 144 | Bear / Dire Bear [I] | Bash, Growl, Challenging Roar, Enrage, Frenzied Regeneration, Lacerate, Demoralizing Roar, Primal Bite |
| 145 | Cat + Bear + Dire Bear [I] | Feral Charge, Skull Bash (the Feral Charge tooltip text says "Requires Bear Form, Dire Bear Form") |
| other (2, 2^30, 1073741826, ...) | not decoded | the caster spells; [UNVERIFIED] what bit 1 and bit 30 mean |

[D] `AGENTS.md`/class-port A10: the client has no form getter, so FX learns forms from events only. That fits the table: Dash and Cower can
only be cast in Cat Form, so a cast-predict of either implies Cat Form.

[D] `Forte_Messages/Pages/RaidMsg.lua:168-182` and `tests/test_cast_announce.lua:268-270` hold the 2012 texts: Barkskin "(10 sec)",
Survival Instincts "(12 sec)", Frenzied Regeneration "(20 sec)". Live: 15 s, 20 s (and the spell is a rune row), 10 s. The rows are default-off,
so no one sees them yet.

## 7. Forever-specific druid spells (confirmed from the client or ForeverDB)

- [V] S4: "Forever adds a real bear toolkit, and the new talent tree adds Lacerate, Feral Charge and Primal Bite for Feral and Wild Growth
  for Restoration, plus the out-of-combat Revive. Insect Swarm is now a Balance talent, and Omen of Clarity a trainer ability at 20."
- [V] S5 and dev notes: Primal Bite is Mangle renamed (level 40 capstone, 6 s cd); Lacerate is a 5-rank Feral talent that stacks 5 times;
  Wild Growth 3 s cast; Shifting Power is a 1-point talent (8 s cd, converts mana to 40 energy, `Descriptions` 1322605); Bloom replaced Gift of
  the Earthmother; Swiftmend is a talent that now requires your own Rejuvenation or Regrowth; Poised (1328829, level 32); Revive (437138 and 4 ranks).
- [D] Ferocious Bite has 6 ids: 1328618 (R1, L24) ... 22829 (R5, L56), 31018 (R6, L60). Our pick 22829 is the top **non-book** rank (31018 is an AQ20
  book id, `bookRanks`). The ranks sit 8 levels apart (24, 32, 40, 48, 56); 31018 at 60 breaks the pattern. [I] consistent.
- [D] Class-port rows `Druid.lua:95-96` ("eclipse (solar)" / "(lunar)", absent) stay right for those two names; the Forever `Eclipse` is a different spell (§2).

## 8. Blizzard notes, Nov 6-10

**Nov 6 hotfix list** [V] https://news.blizzard.com/en-us/article/24315281/wow-forever-hotfixes-november-6-2026 (re-fetched 2026-11-09; unchanged since Nov 7):
"Druid - Bloom will now correctly heal the target. Fixed a bug where the tooltip of Bear Form claimed an incorrect health value increase. The functionality
was correct, but the wrong value was reported. The tooltip for Ravage reported an incorrect value for its damage, and the tooltip has been corrected.
There was no change made to damage done. Fixed the tooltip for Swiftmend to no longer incorrectly mention consuming the effect." And under Races:
"Night Elf - Fixed a bug granting Shadowmelded Druids access to Ravage and Pounce."

**Nov 7-9** [V] forum search `@Kaivax after:2026-11-06` (us.forums.blizzard.com, 2026-11-09) returned three topics: 2404092 (the Nov 10 plan, post 1 only
by Kaivax), 2406595 ("Dungeon Enemy XP Increased - November 8": +50% kill XP in dungeons, deployed ~11:05 PST) and 2403040 (hotfix thread, last post 2026-11-07
01:07 UTC). **No druid line.** S5 logs no druid change after the Nov 6 hotfix and no build above 70862 (builds named: 70755, 70790, 70840, 70862).

**Nov 10 plan** [V] topic 2404092 post 1: Hunter pets and Warlock Voidwalkers sturdier; Affliction Warlock DoTs worth casting with Wrack; Enhancement Shaman
stat priority. "Our plan is to make class balance changes on Tuesday, and then on future Tuesdays if necessary." Nothing for druids, although player posts in
the thread ask about druid tanks (replies from players, not Blizzard). Druid threads on the forum (2407126 hit rate, 2407572 feedback, 2404808 Balance) are player
reports with no tracked values.

**Client diff, builds 70790 -> 70862** [D] S1: of 693 class-set-7 spells and 675 name/id matches, the only changed rows are:
- 21178 `Bear Form (Passive2)`: threat effect base points 50 -> 115 (matches the dev note "Threat bonus increased further to compensate for Blessing of Salvation removal (50% -> 115%)"). Not tracked.
- Four new family-less rows on existing names: Thrash 1290533, Demoralizing Roar 1310515, Hurricane 1328040 and 1328041 (§4 watch).
The Bear Form health text change (180 -> 560) and the Ravage text (343 -> 426) are `$`-variable text, not a changed spell row. The Bloom fix is server-side.
**Swiftmend [UNVERIFIED]:** the fix reads as tooltip-only. mythicsim models "one Swiftmend consumes" (`README.md:751`, `src/classes/druid/agent.rs:82`)
but that is the Go reference's model, not a live log. FX must not remove a Rejuvenation/Regrowth row on a Swiftmend cast-predict; let the out-of-combat reconcile decide.

**Wowsims since our pin** [D] 155 commits; druid: Enrage armor penalty 27% (Bear) / 16% (Dire), Maul rolls Omen of Clarity at half rate, Ferocious Bite refunds 80% of its
base energy on a miss, Lacerate's hit crits outside Natural Instinct, Pounce Bleed takes attack power, Rake/Rip/Swipe attack-power shares measured. None changes a
duration, cooldown or tick. The store's druid group did not move (70790 / 113715); only paladin and items did.

## 9. Evidence quality

- Everything in §3 is client data (wago DB2 70862) cross-read with the live store and two independent sims (wowsims, mythicsim). **Not** replicated by an in-game
  cooldown read: no one has timed Dash, Cower or Abolish Poison on a druid in the game. The identity argument in §4 is replicated by four independent sources
  (sim ladders, `SkillLineAbility` skill lines, ForeverDB list, the item row already in our own data), so I rate it high.
- §5 "not learnable" rests on absence evidence (ForeverDB list, no trait node, no engraving system). High for the four set/talent procs and Thrash (positive code
  evidence); medium for the rune rows. Reported by ForeverDB/foreverdiff, not independently replicated in the game.
- ForeverDB, foreverdiff and wowforever.news are third-party sites reading the client. I fetched them; I did not log in or play. Wowhead returned HTTP 403 (not read).
- Sample period, out-of-sample, look-ahead and cost questions: **not applicable** (no performance, backtest or strategy claim in this report).
- Berserking: the `Berserking` row lacks a 15 s duration although the client has it (§3). [D] Dev notes 2026-11-02 (`docs/research/forever-dev-notes-2026-11-03.md:20`) say "Troll Berserking 15 s".
  This is not fixable from `druid.json` (the generator takes durations from the store and base pull); it needs one row in `tools/overrides_devnotes_*.json`. Flagged for the main agent.

## 10. Implications for our setup

1. **The Dash and Cower cooldown rows are wrong on the live client today.** Fix by the three pins below. The next regeneration will change the Cooldown tracked set for
   Dash (30 s -> 300 s) and Cower (5 s -> 10 s). Two tests pin the old values and will fail by design: `Forte_Cooldown/tests/test_70707_overlay.lua:75-79`
   (Cower 16697 / 5000 ms) and `Forte_Cooldown/tests/test_tracked_set.lua:143-144,164` (Dash, Thrash in the DRUID lists; Thrash's name-only note).
2. The pinned rows keep the same names, so Timer rows (`Registry` bands `^Dash`, `^Cower`, `^Abolish`) and `Locale` aliases are unaffected.
3. Dropping the not-castable names (below) removes dead rows and one false "tracked by neither" test entry. It changes no runtime output because `Engine:Build`
   gates on `isKnown(name)`. If the owner prefers a hedge until the live probe in §5 is done, keep them and only apply the pins.
4. Cast announces: either strip the duration from the text or read it from the data row (Barkskin 15, Frenzied Regeneration 10). The 2012 numbers are verbatim by
   owner ruling (T2), so this needs a decision, not a patch.
5. Do not build a Swiftmend consume rule or an Eclipse bar until a live log exists (§8, §2).
6. Cross-class flag: Warrior `Charge 27685` has the same smell (§4). Worth a look in that class's report.

### Proposed patch (`tools/spell_lists/druid.json`)

JSON has no comments, so the reasoning is in the table. Apply in this order, regenerate with `python3 tools/gen_spell_data.py druid`, then expect the listed output rows.

**A. Add to `_pins` (high confidence; fixes the wrong picks).**

```json
"Abolish Poison": {
  "id": 2893,
  "reason": "14253 is Black Husk Shield's on-use spell (no SkillLineAbility; Forte_Items row 4444). 2893 is the druid spell: family 7, stance mask 1073741826, sim Ranked(2893), ForeverDB level 26. The family-less store row 14253 joined the in-family pool and won the level tie on id"
},
"Cower": {
  "id": 9892,
  "reason": "16697 is the Hunter pet's Cower Rank 6 (sim hunter CowerTriggered, pet skill line 270). The druid ladder is 8998/9000/9892 (cat form, cd 10 s cat 84, GCD 1 s). The family-less store row won on level 55 vs 52"
},
"Dash": {
  "id": 9821,
  "reason": "23110 is the Hunter pet's Dash Rank 3 (sim hunter DashTriggered 23099/23109/23110, pet skill lines, 30 s, GCD 1.5 s). The druid Dash is 1850/9821 (cat form, 15 s, category cd 300 s, off-GCD; sim Ranked(1850, 9821); ForeverDB level 26). No family-7 Dash row exists, so the family-less pet row won on level 50 vs 46"
}
```
Expected rows: `Abolish Poison {id=2893, tickEvery=2, durationMs=8000, gcdMs=1500}` (no rank text);
`Cower {id=9892, cooldownMs=10000, cooldownCategory=84, gcdMs=1000, rank="Rank 3"}`;
`Dash {id=9821, durationMs=15000, cooldownMs=300000, cooldownCategory=44, rank="Rank 2"}` (no `gcdMs`; `noTarget` follows the base effect target, [UNVERIFIED]). Confidence **high** for Dash and Cower, **high** for the Abolish Poison id.

**B. Optional pins (low; cosmetic).** `"Hurricane": {"id": 17402, ...}` gives the 1 s tick feed (the picked row 1278759 has no period); `"Entangling Roots": {"id": 9853, ...}`
uses the real cast row instead of Nature's Grasp's identical trigger row. Confidence **low** (no value changes except `tickEvery = 1` on Hurricane).

**C. Remove from the lists (set/talent/item procs; high).**

```json
"cooldowns": remove "Astral Power", "Wild Rejuvenation"
"buffs":     remove "Fury of Stormrage", "Force of Nature", "Thrash"
```
Also update `Forte_Cooldown/tests/test_tracked_set.lua` (the DRUID `Thrash` entry and its `["Thrash"] = "21919 is a name-only row ..."` note).

**D. Remove from the lists (rune-era rows; medium; do after the one live probe in §5, or keep as a hedge).**

```json
"cooldowns": remove "Skull Bash", "Starfall", "Survival Instincts"
"buffs":     remove "Lifebloom", "Savage Roar", "Sunfire"
"forms":     remove "Tree of Life"
```

**E. `_deferred_H7` (medium).**

```json
"_deferred_H7": ["Nature's Grace", "Eclipse"]
```
Drop "Living Seed" and "Savage Defense" (rune rows); add "Eclipse" (a real talent whose aura is a proc that does not fire on a missed Wrath). Nature's Grace is a real Balance talent (node 16880) and stays.

**F. Not a spell-list change.** Add a Berserking `durationMs = 15000` row to `tools/overrides_devnotes_2026-11-03.json` (client 70862 `SpellMisc`; dev notes "Troll Berserking 15 s"). Confidence **high**.

## 11. Open questions

1. On a druid in the game: do `IsPlayerSpell`/`IsSpellKnown` return true for 408124, 410176, 439748, 414684, 407988, 408024, 439745, 5217, 417045? (§5; one command each)
2. What is the real Dash cooldown on a druid: does a cast of 9821 put category 44 on 300 s? (read `C_Spell.GetSpellCooldown(9821)` out of combat after one cast; this confirms §4)
3. Does Swiftmend remove the Rejuvenation/Regrowth it heals? (§8) And does a recast of Rejuvenation on the same target bloom the old one? (mythicsim README:751 assumes yes, "an assumption until the logs hold them")
4. Are the AQ20 class books (Rejuvenation R11 25299, Ferocious Bite R6 31018) obtainable on Forever? They change the cast id, not any value (`bookRanks` law; open since `data-diff-70707.md:337`).
5. What do the Forever-era Tiger's Fury rows 1289238 (10 s, +25%) and 1312152 (permanent +15%) belong to? A race, a set, an NPC?
6. After Tuesday's Nov 10 hotfix: re-run §1(a) and (b) against the new build; the druid store group will move only when wowsims re-captures it.
7. Does the `UNIT_SPELLCAST_SUCCEEDED` spell id for a Lacerate cast ever equal 414647 (the hit row)? The sim says no (`lacerate.go:9`); `Locale.RankIDsForName("Lacerate")` should still include all five ranks and the hunter-pet rows with the same name (24118-24120, 1299332, family 9).
8. Does mask bit 1 / bit 30 in the stance masks mean "Tree of Life" and "Moonkin"? I did not need it; a form-gated design would.

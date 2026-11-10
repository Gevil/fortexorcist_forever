# Paladin: live data audit, 2026-11-09 (builds 70862 / push 113823)

Author: RsrchPaladin (read-only research subagent). Written 2026-11-09. Only this file was written.
Inputs read: `tools/spell_lists/paladin.json`, `addon/Forte_Paladin/Data/Paladin.lua` (generated 2026-11-07 from the
70790 overlay), `AGENTS.md`, `docs/class-port.md`, `docs/research/data-diff-live-2026-11-07.md`,
`docs/research/forever-postlaunch-2026-11-07.md`, `docs/research/forever-dev-notes-2026-11-03.md`.

**Claim labels.** [V] verified: a quote or value from a page I fetched today (URL given). [D] derived: from local
data or code (file or row given) or a computation I ran on it. [I] inference: my reading, untested in game.
Nothing here was tested in a running client. The simulator and the gate were not run.

**Sources and their state** [D]
- `/tmp/wowsims-forever` at `9ca4d977` (2026-11-09). Its `assets/db_inputs/spell_store_inputs.json` has
  `Builds.paladin = 1.60.1.70862`, `Hotfixes.paladin = 113823`. Our overlay `tools/overrides_70790.json` is
  `1.60.1.70790` at push `113715`.
- Commit `314d0e36` in that clone says the 70790 -> 70862 paladin spell data changed in exactly one row: Unsealed
  Wrath 1310735 now requires a weapon (`SpellEquippedItems 257179`, push 113772). I confirmed the row:
  `Equipped = {Class 2, Subclass 0}`.
- `mythicsim-forever-engine` at `ff6a43cf` (2026-11-10 AEDT). Its paladin hotfix file
  `src/classes/paladin/prepare/hotfix_113554.rs` holds the live talent trees.
- Blizzard forum JSON for threads 2406595 (Nov 8), 2404092 (Nov 6) and 2403040 (hotfixes), fetched today.
  wow-forever.gg, wowforevertalents.com and wowforever.news pages, fetched today. Wowhead returned HTTP 403, so I
  cite none of it.

---

## 0. Answer first

1. **One tracked value is wrong against the live store.** Vengeance `maxStack` is 3 in our data. The live store,
   the sim and Blizzard's Nov 3 notes all say 5. The cause is a generator rule that lets the stale 70425 base row beat
   the overlay (§1.1). Every other duration, cooldown, cast time and ICD in `Paladin.lua` equals the live store.
2. **Five rows carry wrong feed flags or ids.**
   - Oath of Light: `noTarget = true` is wrong (it is cast on an ally) and `tickEvery = 1.5` draws a spark clump.
   - Echo of Fury, Echo of Command and Shieldsworn: `noTarget` is missing (they sit on the paladin).
   - Cleanse: the row is the set-bonus passive 28787, not the spell 4987.
   - Exorcism: the row is the Season-of-Discovery ladder (415073), not the client's rank 6 (10314). The numbers are
     identical, only the id is off.
3. **Eleven list entries are stale.** Voice of Truth was removed by Blizzard on Nov 3. Ten more
   (Avenging Wrath, Divine Storm, Divine Light, Hand of Sacrifice, Ancestral Guidance, Shield of Righteousness,
   Beacon of Light, Aura Mastery, Crusader Strike, Righteous Judgement) are Season-of-Discovery rune rows that
   exist in the database but not in Forever's spellbook, talent trees or the sim. The entry "Rebuke" (an item-proc
   row) and the already-dropped "Greater Blessing of Light" are also dead weight, and "Unsealed Wrath" draws no
   bar. §3 grades the evidence per entry.
4. **Six untracked rows are worth adding.** The strongest are Holy Strike (10 s cooldown, the Retribution and
   Protection core button), the Judgement debuff family (40 s, refreshed by melee strikes), the four missing
   Unsealed Wrath Echoes, Light's Vigil (6 s cooldown, 30 s ally buff) and Holy Wrath (60 s). §4 ranks them.
5. **No Blizzard class note touches the paladin between Nov 6 and Nov 10.** The Nov 6 hotfix list has no paladin
   line, the Nov 8 post is a dungeon-XP change, and the announced Nov 10 tuning is Hunter pets, Voidwalker,
   Affliction and Enhancement stats. The paladin's own changes landed in the Nov 3 notes and the data already
   carries them, except the items in §1 and §3 (§5).

---

## 1. Wrong or changed tracked values

### 1.1 Table

Method [D]: I parsed every `[id] = { ... }` row of `Data/Paladin.lua` and compared `durationMs`, `cooldownMs`, `castMs`
and `maxStack` to the live store's `Misc`, `Cooldowns` (max of cooldown and category cooldown), `AuraOptions`. I then
compared `noTarget` to the store's `Effects[].Target[0]` (1 = caster). Rows not listed below matched.

| # | Row (`Paladin.lua` line) | Our value | Live store (70862 / push 113823) | Evidence | Conf. |
|---|---|---|---|---|---|
| 1 | Vengeance 20050 (`:112`) | `maxStack = 3` | `AuraOptions.MaxStack = 5` | [D] `tools/overrides_70790.json` already carries `maxStack 5` for 20050; the base row `mythicsim .../data/spells.jsonl` `ID 20050` has `MaxStack 3`. The generator keeps the base answer (`gen_spell_data.py` `row_feeds` docstring: "A capture fills a field the earlier source can not speak to -- it never overwrites a base answer"). [D] wowsims `sim/paladin/talents_retribution.go:238-240`: "Stacks up to 5 times", `MaxStacks: int32(rank.MaxStack)`. [V] https://wow-forever.gg/changes/paladin (fetched 2026-11-09), Blizzard excerpt: "Vengeance changed to stacking up to 5 times (Was stacking up to 3 times)." | high |
| 2 | Oath of Light 1328548 (`:108`) `noTarget` | `true` | Effects target code 21 (ally) on all three effects | [D] store `Effects['1328548']` = three effects, `Target[0] = 21`. [D] wowsims `sim/paladin/oath_of_light.go`: the Oath aura is an ally aura array, one per ally, "One Oath per paladin". Our flag came from the overlay `targetCode 1` (the store's `Targets` scalar), not from the effects. A `noTarget` row keys on the player, so the Timer would not show who carries the Oath. | high |
| 3 | Oath of Light `tickEvery` | `1.5` | Effect 0 is aura 226 (periodic dummy), `PeriodMs 1500` | [D] store `Effects['1328548'][0]`. [D] `Forte_Timer/UI/Rows.lua:1253-1256` draws `min(12, floor(maxTime/every))` marks spaced `every/maxTime*width`. 300 s / 1.5 s gives 12 marks inside the first 6% of the bar. [I] A dummy ping is not a visible tick, so the marks mean nothing. | med |
| 4 | Blessing of Wisdom 19854 (`:98`) and Greater Blessing of Wisdom 25894 (`:101`) `tickEvery = 5` | `5` | mana per 5 s over 3600 s | [D] same renderer path: 3600 s / 5 s capped at 12 marks inside the first 1.7% of the bar. [I] Same clump. | med |
| 5 | Echo of Fury 1311701 (`:128`), Echo of Command 1311703 (`:129`) | no `noTarget` | all three effects `Target[0] = 1` (caster) | [D] store `Effects`. [D] wowsims `talents_retribution.go:305-313`: each Echo is `paladin.RegisterAura`, an aura on the paladin. Without `noTarget` the Timer keys it to the current target. | high |
| 6 | Shieldsworn 1328551 (`:109`) | no `noTarget`, and Registry band `TargetDebuff` | effect `Target[0] = 1`, text "Able to Block spells for $d." | [D] store row. [D] `Forte_Timer/Core/Registry.lua:270` puts `"^Shieldsworn"` in `TargetDebuff` with the comment "the paladin Judgement echo's window ON THE TARGET". That comment is wrong: the store text is a self block window. The talent text (1328544) says Holy Strike with a shield "allow[s] you to Block spells for 6 sec". | high |
| 7 | Cleanse (`:133`) = 28787, `durationMs = -1` | id 28787 | The spell is 4987 (level 42, no duration, no cooldown). 28787 is "Your Cleanse spell also heals the target for 200." | [D] store `Names/Descriptions` for both ids. [V] https://wow-forever.gg/db/spells/browse/class/paladin (2026-11-09) lists "Cleanse /db/spells/4987-cleanse/" at level 42. Neither id has a rank subtext, so the generator's highest-id tie-break picked the passive. | high |
| 8 | Exorcism (`:137`) = 415073 | `cooldownMs 15000`, cat 19 | Identical values on 10314 (the client's rank 6 of ladder 879/5614/5615/10312/10313/10314) | [D] store: both ids level 60, `CategoryCooldownMs 15000`, `Category 19`. [D] wowsims `spell_data_auto_gen.go:194` `Exorcism: Ranked(879, 5614, 5615, 10312, 10313, 10314)`, `Exorcist: Ranked(415076)` is the separate rune ladder. [V] the browse page above lists "Exorcism (Rank 6) /db/spells/10314-exorcism/". Numbers match, so only the id is off. Harmless if the engine resolves by name. | med |
| 9 | Holy Shield 1239570 (`:91`) | no stack column | `ProcCharges = 4`, `MaxStack = 0`; text "Each block expends a charge. 4 charges." | [D] store `AuraOptions['1239570']`. [D] wowsims `holy_shield.go`: `MaxStacks: charges`, `RemoveStack` per block. [V] https://wowforevertalents.com/patch-notes (2026-11-09), 3 Nov entry: "Each block expends a charge. 4 charges." The generator only reads `MaxStack`, so the charge counter is not fed. Same gap for Divine Favor (1 charge), Infusion of Light (1 charge) and Reckoning (1 charge on a 4-stack aura). | high |
| 10 | Seal of Fury 20423 (`:115`) | no `noTarget` while the other six seals have it | effects `(0: Target 1)`, `(1: Type 0, Target 0)`, `(2: Target 1)` | [D] store. The empty effect slot (Type 0) breaks the "every effect targets the caster" test. [I] Generator quirk; the aura is on the paladin. | med |
| 11 | Swift Judgement 1310994 (`:85`) | `noTarget = true` | effect `Target[0] = 6` (enemy) | [D] store. Cooldown-only row, so no visible effect today. | low |

Checked and fine [D]: Judgement 10 s, Holy Shock 10 s (cat 892), Divine Shield / Divine Protection 300 s shared cat 37,
Blessing of Protection 300 s cat 20 (10 s), Lay on Hands 1200 s cat 56, Hammer of Justice 60 s cat 32 (6 s stun),
Hammer of Wrath 6 s (1 s cast), Hammer of the Righteous 6 s cat 2404, Consecration 8 s / 8 s cat 932, Repentance 60 s
(6 s), Blessing of Freedom 20 s (10 s), Divine Favor 120 s, Swift Judgement 60 s, Templar's Bulwark 8 s / 300 s,
Reckoning ICD 1.5 s and 4 stacks, Seal of Command ICD 1 s, Seal durations 30 s, blessing durations 3600 s, Righteous
Fury 1800 s, Forbearance 60 s, Vindication 30 s, Infusion of Light 15 s, Echo durations 15 s with 3 stacks, Shieldsworn
6 s, Oath of Light 300 s.

### 1.2 Rank picks (deliberate, no action) [D]

Blessing of Might 19838 (R6), Blessing of Wisdom 19854 (R5), Greater Blessing of Might 25782 (R1) and Greater Blessing
of Wisdom 25894 (R1) are the trainer ranks. Rank 7 / 6 / 2 / 2 are the AQ20 book ranks in wowsims
`sim/core/spelldata/book_ranks.go` (25291, 25290, 25916, 25918), so the generator drops them by design
(`gen_spell_data.py` docstring, "trainer-rank pick"). Durations are 3600 s either way. [V]
https://wowforevertalents.com/abilities/paladin lists R7 / R6 as level-60 spells because the client's skill table does
not mark them as book-only; the sim file says they come from a Libram. Cast events with the book id resolve by name.

### 1.3 Values the talents and sets modify, which the data cannot hold [D]

These move a tracked number and only the learned-duration path can see them.
- Sacred Duty (Nov 3 notes): cooldown of Divine Shield, Divine Protection and Templar's Bulwark 30 s / 60 s lower,
  and Forbearance 5 s / 10 s shorter. [V] wow-forever.gg/changes/paladin, Blizzard excerpt: "...it now also reduces
  the duration of your Forbearance effect by 5/10 seconds." Sim: `forbearance.go` uses `forbearanceReduction`.
- Improved Hammer of Justice (cooldown), Improved Judgement (cooldown), Shieldsworn (Holy Strike cooldown -4 s,
  `1328544` text), Lasting Judgement (Judgement of Light / Wisdom duration).
- Tier-set rows in the store: 1301036 (Hammer of Justice cooldown), 1301702 (Judgement cooldown), 1301697
  (Forbearance duration). These are in the item/set leg, not the spell list.

---

## 2. Changes in the wowsims and mythicsim logs that touch tracked rows [D]

| Change (commit) | What it says | Effect on our data |
|---|---|---|
| Unsealed Wrath requires a weapon (wowsims `314d0e36` 2026-11-09, `c0bfde5e` 2026-11-09) | `SpellEquippedItems 257179` (any weapon), push 113772. Swapping the main-hand weapon removes every Echo. | Row 1310735 has no duration, so it never draws (§3.4). The Echoes are what to show, and they vanish on a weapon swap. A plain-read reconcile must not treat that as expiry. |
| Seal of Command ICD (mythicsim `c3ebd0ed` 2026-11-05) | The 1 s cooldown is the seal aura's `ProcCategoryRecovery` (client 70790). Echo of Command copies roll without it. | Our `icdMs = 1000` on 20920 is right for the seal. Do not apply it to Echo of Command. |
| Seal of Righteousness rank 1 hits proc as 25741 (wowsims `7fab8eb0` 2026-11-06) | Logs show 641 hits of 25741 and 145 of 25742; 20154 never procs. | No tracked row. Our pick is 20293 (R8). |
| Judgement of the Crusader off damage-shield hits (wowsims `cfedf1cc` 2026-11-06) | Damage detail only. | None. |
| Holy Power's heal crit covers Lay on Hands (mythicsim `67a1701c` 2026-11-06) | Passive 5923 raises the crit healing bonus. | None; no duration or cooldown. |
| Oath of Light (wowsims `oath_of_light.go`) | 5 min, one Oath per paladin, replaces the previous one. | §1 rows 2-3. A new cast must evict the old row (the `F.UNIQUE` role). |
| Holy Shield rank 4 (mythicsim `2d413bce` 2026-11-04) | 1239570, four charges. | Already our id. Charges: §1 row 9. |
| Vengeance 5 stacks (mythicsim `ce5d4bf6` 2026-11-04) | From the Nov 2 dev notes. | §1 row 1. |

---

## 3. Stale entries in `paladin.json` / `Paladin.lua`

Test applied [D]: an entry is stale when its spell is absent from all of (a) the 70862 client spellbook as read by two
sites, (b) the live store's paladin group (`SpellDataGroupRoots.paladin`, 262 ids) or the sim ladders, and (c) the
Forever talent trees in `hotfix_113554.rs`. Sources for (a): [V] https://wowforevertalents.com/abilities/paladin
("44 trainer spells ... read from the Forever client, build 1.60.1.70862") and
https://wow-forever.gg/db/spells/browse/class/paladin ("The Paladin learns 46 abilities in WoW Forever, 158 spell
pages", build 1.60.1.70862).

### 3.1 Removed by Blizzard

| Entry (`Paladin.lua` line) | Evidence | Conf. |
|---|---|---|
| **Voice of Truth** 1310897 (`:80`) | [V] wow-forever.gg/changes/paladin lists Blizzard's Nov 3 line "Voice of Truth removed." [V] https://wowforever.news/changes/paladin.html: "Voice of Truth ... Talent removed ... Source excerpt: 'Voice of Truth removed.'" [D] `hotfix_113554.rs:35`: "Voice of Truth (1310897) is removed" from the Holy tree, with Oath of Light new. [D] `docs/research/forever-data-gaps.md:372` already records "Voice of Truth -> Oath of Light". Mixed signal: [V] wowforevertalents.com/abilities/paladin still lists "Voice of Truth ... Level 20" because it reads the client table without the server hotfix, and the store row (cd 180 s, 6 s) is still present. The browse page above does not list it. | med-high |
| **Greater Blessing of Light** (`paladin.json:22`) | [D] generator header `Paladin.lua:25-26` already drops it: "id(s) 25890 removed on 70790". [V] wowforevertalents spellbook marks "Greater Blessing of Light ... Not in Forever". The JSON entry only produces a generator notice. | high |

### 3.2 Season-of-Discovery rune rows that exist only in the database

None of these is in the 46-ability spellbook, in the store's paladin root group (they sit outside it as bare name
rows), in the sim's `spellData` ladders (`spell_data_auto_gen.go` has Exorcist, Hammer of the Righteous, no others)
or in the Holy / Protection / Retribution tree lists.

| Entry (line) | What the row is [D] | Conf. |
|---|---|---|
| Avenging Wrath 407788 (`:79`) | Store effect 2 triggers 25771 Forbearance, 20 s / 180 s. The Nov 3 notes and both spellbooks have no such spell. The comment "Divine Wrath->Avenging Wrath" in `paladin.json` `_comment` is a guess. Our Registry also files it under `Heal` (`Registry.lua:155`). | high |
| Divine Storm 407778 (`:88`) | cd 10 s, no spellbook or tree entry. | high |
| Divine Light 458856 (`:89`) | cast 2.5 s, cd 8 s; Forever heals are Holy Light / Flash of Light. | high |
| Hand of Sacrifice 462853 (`:82`) | 12 s / 120 s. The spellbook has Blessing of Sacrifice (6940, 20729) instead. Registry has `^Hand of Sacrifice` in `SelfDebuff` (`:206`). | high |
| Ancestral Guidance 409324 (`:84`) | Shaman-style rune row flagged family 10. No spellbook entry. Registry `Buff` has `^Ancestral Guidance` (`:222`). | high |
| Shield of Righteousness 440658 (`:90`) | No spellbook or tree entry. Registry `SelfBuff` has it (`:353`). | high |
| Beacon of Light 409906 (`:105`) and Aura Mastery 409932 (`:107`) | The ids are the "Gain the ... ability" teacher rows (`$@spelldesc407613`, `$@spelldesc407624`); no ability row exists to cast. Registry `Cooldown` has `^Beacon of Light` (`:203`). | high |
| Crusader Strike 409914 (`:140`) | Teacher row ("Gain the Crusader Strike ability", `407676`). The ability id 407676 has no store row at all. | high |
| Righteous Judgement 440675 (`:144`) | Aura 226 with a 2 s period, 8 s. [I] It is a Season-of-Discovery talent aura; it is in none of the three Forever trees. Registry `TargetDebuff` has it (`:250`). | med-high |
| Rebuke 1302716 (`:138`) | Item-style proc: "When struck by a harmful spell, has a $h% chance of Silencing the caster for 1302715d", family none. The paladin has no Rebuke in either spellbook. | high |

### 3.3 Note on the confidence

The risk of deleting a live spell is low. These rows never match a cast event, so they never draw anything now. The cost
of keeping them is colour-band clutter and false "tracked" counts. If the main agent wants one more safety check,
a one-time in-game `C_SpellBook.IsSpellKnown(<id>)` probe on a level-60 paladin settles all of §3.1-3.2 [I].

### 3.4 Dead row that is not stale but draws nothing

Unsealed Wrath 1310735 (`:130`) has no duration, no cooldown and no stack column [D] (`Registry:Build` needs
`durationMs > 0`, `Registry.lua` data gate). The talent is a passive proc trigger; the six Echo auras are its bars (§4).
[V] Blizzard's Nov 3 line, via wow-forever.gg/changes/paladin: "Unsealed Wrath now requires Repentance."

---

## 4. Untracked rows worth a bar or timer (ranked)

All values from the store at push 113823 [D] unless stated. "Row" means what the generator should emit.

| Rank | Thing | Ids and values | Why | Engine notes |
|---|---|---|---|---|
| 1 | **Holy Strike** (cooldown) | R8 10333 (R1 679 ... R8); `CategoryCooldownMs 10000`, category **2404**, no GCD column read | The new core button of Retribution and Protection. [V] https://wowforevertalents.com/abilities/paladin: "Holy Strike ★ ... An instant strike ... 10 sec cooldown". It shares category 2404 with Hammer of the Righteous (6 s). Shieldsworn takes 4 s off it. | Cooldown row. The category link works only if both are tracked; today only Hammer of the Righteous is. |
| 2 | **Judgement debuffs** on the target | Judgement of Light R4 20346 (40 s), of Wisdom R3 20355 (40 s), of the Crusader R6 20303 (40 s), of Justice R1 20184 (10 s), of Fury 20232 (taunt, 3 s) | [V] wowforevertalents spellbook, Seal of the Crusader R6: "judge an enemy for 40 sec ... Your melee strikes will refresh the spell's duration. Only one Judgement per Paladin can be active at any one time." [V] Blizzard (via wow-forever.gg): "Judgement of Fury's duration reduced to 3 seconds (Was 4 seconds)." | Needs a seal tracker: the cast is always Judgement 20271 and the debuff is chosen by the active seal. Precedent: Hunter AspectTracker (`Forte_Hunter/Core/Tools.lua`). Melee refresh is invisible to a cast-predicted bar [I]. Treat the bar as "at least"; do not draw a hard expiry flash. Eviction: a new Judgement replaces the old one on any target. Name collision to watch: 28775 "Judgement of Light" is a set-bonus passive with `DurationMs -1`; the pick must be 20346. |
| 3 | **Echo of Righteousness 1311704, Echo of Justice 1311705, Echo of Light 1328198, Echo of Wisdom 1328206** | 15 s, 3 stacks, all effects on the caster | Same shape as the two Echoes already tracked. [V] wowsims `seals.go`: six Echo ids, Seal of the Crusader has none. Without the four, Unsealed Wrath shows only for Fury and Command seals. | Self rows. Need a Registry term `"^Echo of"` (now only `Echo of Fury` and `Echo of Command`, `Registry.lua:369`). They vanish on a main-hand swap (§2). |
| 4 | **Light's Vigil** (cooldown) | R3 1311595: cast 1.5 s, cd 6 s, cat 2576. Ally aura R3 1311597 (also 1310909, 1311593), 30 s | New Holy button. [V] browse page: "Applies Light's Vigil to a friendly target for 30 sec. The caster's next Holy Shock on..." Blizzard Nov 3: "now only usable on friendly targets". Spending it removes the Holy Shock cooldown. | The 30 s aura shares its name with the cast, so a name-keyed row gets only one of them. Emit the cooldown; the aura needs a name collision fix in the generator [I]. |
| 5 | **Holy Wrath** (cooldown) | R2 10318: cast 2 s, cd 60 s, cat 35 | AoE damage and stun against Undead / Demons. [V] browse page lists Holy Wrath R1 / R2. | Cooldown row. Registry would colour it `SelfBuff` through the substring `"Wrath"`; add a `^Holy Wrath` term to `Cooldown`. |
| 6 | **Holy Shield charges** | `ProcCharges 4` on 1239570 | The block counter is the useful readout of the Protection kit. | Generator column, §1 row 9. |
| 7 | **Judgement of Light heal and Judgement of Wisdom mana procs** | not a row | Show nothing: the procs have no aura of their own. | n/a |
| 8 | **Divine Favor charge** | `ProcCharges 1`, duration -1 | Already tracked as a 120 s cooldown. A "ready" badge until the next heal would need the charge feed. | Same generator column. |
| 9 | **Lay on Hands, Divine Shield, Divine Protection, Hammer of Justice, Templar's Bulwark** | already tracked | No new row. Forbearance (60 s) is tracked and covers the shared lockout. | Sacred Duty and set bonuses change the numbers (§1.3). |

Requested names and their status [D]:
- Unsealed Wrath: §3.4 and rank 3.
- Oath of Light: tracked, two feed fixes (§1 rows 2-3).
- Holy Shield: tracked, stacks missing (rank 6).
- Crusader / Seal of the Crusader: seal tracked; its judgement is in rank 2. The "Crusader Strike" entry is stale (§3.2).
- Judgement family: rank 2.
- Lay on Hands, Divine Shield, Divine Protection, Hammer of Justice: tracked and correct.
- Avenging Wrath: **not in Forever** (§3.2).

---

## 5. Blizzard notes, Nov 6 to Nov 10, for the paladin

- **Nov 6 hotfixes** [V] https://us.forums.blizzard.com/en/wow/t/wow-forever-hotfixes-november-6-2026/2403040 (post 4,
  2026-11-07T01:07:59Z; thread edited 01:08:16Z). The class section lists Druid, Mage, Rogue, Warlock and Warrior
  lines and one Legacy Talent line. **No paladin line.** This matches `forever-postlaunch-2026-11-07.md` §1.2.
- **Nov 8** [V] https://us.forums.blizzard.com/en/wow/t/2406595 (Kaivax, 2026-11-08T19:47Z): "At about 11:05 PST today, we
  deployed a hotfix that increased kill experience in dungeons by 50%..." No class content.
- **Nov 10 plan** [V] https://us.forums.blizzard.com/en/wow/t/2404092 (2026-11-06T21:11Z, not edited since): Hunter pets and
  Voidwalker durability, Affliction Wrath versus DoTs, Enhancement Strength. **No paladin line.** These are not live
  on 2026-11-09.
- **Forum search** for Kaivax posts after 2026-11-06 returned only those three threads (JSON search, 2026-11-09). I did not
  search the EU forum or Reddit. [UNVERIFIED] for those.
- **Paladin changes already in our data** (Nov 3 post 9, mirrored by wow-forever.gg/changes/paladin, all [V] as
  Blizzard excerpts there): Righteous Fury level 10 (store level 10 [D]); Judgement of Fury 3 s (store 3000 [D]);
  Voice of Truth removed (§3.1); Holy Power rework (passive); Light's Vigil friendly only; Reckoning stack fix;
  Sacred Duty (§1.3); Templar's Bulwark a dispellable Magic effect; Swift Judgement unleashes the seal with no shared
  cooldown (store 60 s [D]); Vindication loses its Attack Power buff (our row is the 30 s target debuff 440667, which
  stays [D]); Vengeance 5 stacks (§1 row 1) and "now requires Seal of Command"; Unsealed Wrath "now requires
  Repentance".
- **Server pushes** [D]: push 113772 (weapon requirement on Unsealed Wrath) and push 113823 (the store capture).
  The sources give no dates for them; they fall between the 7 Nov client cache (push 113763) and the 9 Nov store
  capture. No Blizzard note names either.

---

## 6. Registry colour bands the paladin names hit [D]

`Forte_Timer/Core/Registry.lua` `KIND_RULES` (first band that matches wins). I read the terms; I did not run `kindFor`.

| Name | Band today | Should be | Line |
|---|---|---|---|
| Shieldsworn | `TargetDebuff` | `SelfBuff` | `:270` |
| Echo of Righteousness / Justice / Light / Wisdom | no term matches, so `Default` | `SelfBuff` (add `"^Echo of"`) | `:369` |
| Holy Strike | no term matches, so `Default` | `Cooldown` | none |
| Light's Vigil | no term matches, so `Default` | `Cooldown` | none |
| Holy Wrath, Unsealed Wrath | `SelfBuff` via `"Wrath"` | Holy Wrath: `Cooldown` | none |
| Judgement of Light / Wisdom / the Crusader / Justice / Fury | `TargetDebuff` via `"Judgement"` | correct | n/a |
| Voice of Truth, Avenging Wrath, Hand of Sacrifice, Ancestral Guidance, Beacon of Light, Shield of Righteousness, Righteous Judgement | terms at `:155`, `:206`, `:222`, `:203`, `:353`, `:250` | delete with the list entries | |

`tests/test_kinds.lua` asserts zero `Default` rows [D] (`PLAN.md` around lines 456-458), so adding Holy Strike and the four Echoes
without these terms fails the gate.

---

## 7. Implications for our setup

1. Edit `tools/spell_lists/paladin.json` as in the **Proposed patch** below, then regenerate. This removes 14 dead
   entries and adds 3 cooldowns, 4 Echoes and 4 Judgement debuffs (plus one optional).
2. **Two generator changes are needed that no JSON line can do.** (a) `row_feeds` must let an overlay `maxStack` beat a
   stale base `MaxStack` (Vengeance). (b) The `noTarget` feed should come from `Effects[].Target[0]` of the picked row,
   ignoring empty (Type 0) effects, not from the store's `Targets` scalar (Oath of Light, Echo rows, Shieldsworn, Seal of
   Fury). A third, optional: read `ProcCharges` as a stack cap when `MaxStack` is 0 (Holy Shield).
3. **Timer display.** Suppress `tickEvery` for periodic dummy auras (aura 226) or cap the mark count by minimum spacing
   (Oath of Light, both Blessings of Wisdom).
4. **Seal tracker.** Judgement debuff rows and Echo bookkeeping both need the active seal. Follow the Hunter aspect
   tracker: predict on own `UNIT_SPELLCAST_SUCCEEDED` of a seal cast, reconcile with out-of-combat aura reads, never
   overwrite with a secret read. A main-hand swap clears all Echoes (§2).
5. **Registry.lua** cleanup lines in §6. Not in my write scope, so not made.

### Open questions

- Is Voice of Truth castable on the live server despite the Nov 3 removal? The 70862 client table still lists it. A
  `C_SpellBook.IsSpellKnown(1310897)` probe on a level-60 Holy paladin answers it.
- Does the Judgement debuff refresh on every landed melee hit show up through `PLAYER_SWING` for paladins, as it does
  for the Hunter rail? If not, the bar needs the "at least" treatment.
- Does `Locale.RankIDsForName("Exorcism")` resolve 10314 on a localized client? Pinning 10314 matches the client book.
- What is the exact rank of Holy Shield and Light's Vigil that the live server grants at level 60? The store has
  R4 and R3; no in-game check.
- The Seal of Fury absorb shield (sim `seal_of_fury.go`, `ActionID.WithTag(1)`, 30 s) has no row of its own in the
  store that I could find. [UNVERIFIED] whether it is a visible buff.

---

## Proposed patch

Target: `tools/spell_lists/paladin.json`. Each line has a confidence and a one-line reason a builder can act on.
Regenerate with `python3 tools/gen_spell_data.py paladin`. After regeneration, check the `Judgement of Light` pick is
20346 (not the set passive 28775) and `Cleanse` is 4987.

**Remove** (`"cooldowns"`):
```json
"Avenging Wrath", "Voice of Truth", "Hand of Sacrifice", "Ancestral Guidance", "Divine Storm", "Divine Light", "Shield of Righteousness"
```
- `Voice of Truth`: med-high. Blizzard Nov 3 "Voice of Truth removed"; `hotfix_113554.rs:35`.
- `Avenging Wrath`, `Divine Storm`, `Divine Light`, `Hand of Sacrifice`, `Ancestral Guidance`, `Shield of Righteousness`: high.
  Not in either 70862 spellbook, the paladin store group, the sim ladders or the talent trees.

**Remove** (`"buffs"`):
```json
"Beacon of Light", "Aura Mastery", "Greater Blessing of Light"
```
- `Beacon of Light`, `Aura Mastery`: high. The ids are "Gain the ... ability" teacher rows.
- `Greater Blessing of Light`: high. Already dropped by the generator (`Paladin.lua:26`).

**Remove** (`"auras"`):
```json
"Unsealed Wrath"
```
- high. The row has no duration and never draws. The Echoes below replace it.

**Remove** (`"utility"`):
```json
"Rebuke", "Crusader Strike", "Righteous Judgement"
```
- `Rebuke`: high (item-proc row 1302716, no paladin Rebuke). `Crusader Strike`: high (teacher row, ability 407676 has no
  store row). `Righteous Judgement`: med-high (rune talent in no tree).

**Add** (`"cooldowns"`):
```json
"Holy Strike", "Holy Wrath", "Light's Vigil"
```
- `Holy Strike`: high. 10 s, category 2404 shared with Hammer of the Righteous. `Holy Wrath`: high. 60 s, category 35.
  `Light's Vigil`: med. 6 s, category 2576. Cooldown only; the 30 s ally aura shares the name.

**Add** (`"auras"`):
```json
"Echo of Righteousness", "Echo of Justice", "Echo of Light", "Echo of Wisdom"
```
- high. 15 s, 3 stacks, caster-side, same as the two Echoes already tracked.

**Add** (`"buffs"`, target-side windows):
```json
"Judgement of Light", "Judgement of Wisdom", "Judgement of the Crusader", "Judgement of Justice"
```
- med. Rows are correct; the cast mapping needs the seal tracker (§7 item 4). Optional low-value extra:
  `"Judgement of Fury"` (3 s taunt, 20232), low.

**Add** (`"_pins"`, entries to merge into the existing object):
```json
"Cleanse": {
  "id": 4987,
  "reason": "28787 is the set-bonus passive 'Your Cleanse spell also heals the target for 200'; the castable Cleanse is 4987 (level 42, wow-forever.gg browse 2026-11-09). Neither id has a rank subtext, so the highest-id tie-break picks the passive."
},
"Exorcism": {
  "id": 10314,
  "reason": "415068-415073 are the Season-of-Discovery Exorcist ladder; the Forever client ladder is 879/5614/5615/10312/10313/10314 (wowsims spell_data_auto_gen.go:194, wow-forever.gg browse). Same 15 s / category 19."
}
```
- `Cleanse`: high. `Exorcism`: med (numbers identical, id only).

**Rewrite** the `_comment` sentence "Forever renames vs Cata: Divine Protection(defensive)->Templar's Bulwark, Divine
Wrath->Avenging Wrath, Hammer of Justice->Voice of Truth ..." [D]: all three renames are wrong on 70862 (Voice of Truth
is removed, Avenging Wrath does not exist, Templar's Bulwark is a Protection talent beside Divine Protection).

**Outside the JSON (generator and registry, listed so nothing is lost):**
- `tools/gen_spell_data.py` `row_feeds`: overlay `maxStack` wins over base `MaxStack`. Fixes Vengeance 3 -> 5. high.
- `tools/extract_store.py`: emit `targetCode` from `Effects[].Target[0]` and skip Type 0 effects. Fixes Oath of Light
  (true -> false) and adds `noTarget` to Echo of Fury / Command, Shieldsworn, Seal of Fury. high.
- `tools/gen_spell_data.py`: treat `ProcCharges` as `maxStack` when `MaxStack` is 0. Adds Holy Shield 4. med.
- `Forte_Timer/Core/Registry.lua`: `"^Echo of"` to `SelfBuff`; `"^Shieldsworn"` from `TargetDebuff` to `SelfBuff`;
  `"^Holy Strike"`, `"^Holy Wrath"`, `"^Light's Vigil"` to `Cooldown`; delete the dead terms listed in §6. high.

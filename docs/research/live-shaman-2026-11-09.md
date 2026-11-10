# Shaman: live check of our data, totem tool and spell list (2026-11-09)

Agent `RsrchShaman`, 2026-11-09. Read-only research. This file is the only thing written.
Scope: `tools/spell_lists/shaman.json`, `addon/Forte_Shaman/Data/Shaman.lua`, `addon/Forte_Shaman/Core/Totems.lua`.
Builds in play: client **1.60.1.70862** (newest Forever build on wago.tools today), live store **70790 @ hotfix 113715**.

Labels on every claim:

- **[V]** verified: quote or value from a page I fetched today (URL given).
- **[D]** derived from local data or code, or from a client DB2 export I fetched (file/row or table/id given).
- **[INFERENCE]** my reading of what the evidence means; nobody has tested it in game.
- **[UNVERIFIED]** I could not confirm it from tools or repo context.

Evidence quality, stated once. This report has no statistical claims, so sample period, look-ahead and trading costs do not
apply. Mana costs are listed only for completeness; FX has no cost field. Three independent table sources agree on every
value below: the wowsims live store (`spell_store_inputs.json`, commit `9ca4d977`), the Forever client DB2 exports
(wago.tools, build 70862, fetched today) and the generated `Data/Shaman.lua`. In-game behaviour was not observed by me.
Anything about runtime behaviour (events, secrecy, relocation) is marked [INFERENCE] or [UNVERIFIED].

---

## 0. Answer first

1. **[D] Two generated Shaman rows are the wrong spell, and both are fixable with `_pins`.**
   - `Earth Shock` is `408690` (category **2171**, named `S03 - Earth Shock - Way of Earth` in the client `SpellCategory`
     table). That is a Season-of-Discovery leftover; it is not in any shaman skill line. The row the player actually learns is
     `10414`, category **19**, which is the category Flame Shock and Frost Shock use. FX therefore carries a wrong category on
     Earth Shock and no shared shock cooldown at all (§4.1).
   - `Lightning Shield` is `28821`, a level-60 set-bonus passive ("Your Lightning Shield spell also grants you … mana per 5
     sec", `durationMs = -1`). The real cast is `10432`: 10 min, 3 charges, 3.5 s ICD, GCD 1.5 s. Because
     `Registry.lua:473-478` registers only rows with `durationMs > 0`, **no Lightning Shield timer row is registered today** (§4.5).
2. **[D] Every value change you listed is live and our data already carries it.** Chain Lightning 2.5 s cast, Totemic Call
   30 s, Riptide 12 s / 150-180-230 mana, Stormstrike 6 s, Maelstrom Weapon 30 s / 5 stacks, Natural Alignment Crystal 300 s /
   20 s window. The client DB2 (70862) and the live store (70790 @113715) agree on all of them (§2).
3. **[D] The shaman side of the store has not moved.** 0 field diffs between the store and our pinned `overrides_70790.json` on
   the 143 overlay-covered root ids (of 256). 0 shaman diffs between the 70790 and 70862 client tables (SpellCooldowns, SpellMisc,
   SpellName, SpellCategories). No shaman line in any Blizzard hotfix since launch (§6).
4. **[D] Twelve tracked names are not obtainable on Forever.** Earth Shield, Lava Lash, Molten Blast, Healing Rain,
   Decoy Totem, Feral Spirit, Ancestral Guidance, Tidal Waves, Way of Earth, Power Surge, Shield Mastery and `Heroism` are SoD rune
   leftovers or an item proc. They are absent from the 50-node live talent tree, absent from the live spellbook, and absent from
   wowsims' compiled Forever shaman code. They are inert in FX (no cast, no row), so this is clean-up, not a bug (§7).
5. **[D] The only Bloodlust-equivalent is Rage of the Farseer** (`425336`): +30% attack speed, 25 s, 180 s cooldown, self only.
   There is no Heroism or Bloodlust shaman spell (§4.4).
6. **[V] Planned Tuesday 2026-11-10, not live:** Enhancement stat-priority change ("Strength is always their strongest stat").
   No spell timer, cooldown or duration is named. Blizzard's own words say talents are revisited "early next year" (§6).
7. **[INFERENCE] Biggest real timing risks that need no data change:** unmodeled talent/set modifiers (Call of Flame +9 s Flame
   Shock, Trial by Fire +20 s Magma Totem, Improved Reincarnation −10 min …), proc resets (Stormstrike on dodge/parry, Molten
   Blast off Flame Shock ticks), and the Stormstrike debuff being consumed by our own next Lightning Bolt or Chain Lightning (§5).

---

## 1. Evidence base and freshness

| Source | What | State today |
|---|---|---|
| wowsims/forever clone `/tmp/wowsims-forever` @ `9ca4d977` (2026-11-09) | `assets/db_inputs/spell_store_inputs.json`, `sim/shaman/**` | shaman leg `1.60.1.70790`, hotfix push **113715** (same as our pin). Items leg moved to 113823, Paladin spells to 70862 @113823. [D] `Builds`/`Hotfixes` keys |
| mythicsim `/var/home/gevil/Work/Personal/mythicsim-forever-engine` @ `ff6a43cf` | `data/spells.jsonl` (client 70425 base), `src/classes/shaman/**` | base not moved |
| wago.tools DB2 CSV, build **1.60.1.70862** and **70790** | SkillLineAbility, SpellName, SpellMisc, SpellCooldowns, SpellCategories, SpellCategory, SpellItemEnchantment, ItemEffect, ItemXItemEffect, ItemSparse | fetched 2026-11-09. `https://wago.tools/api/builds` lists 70862 as the newest `wowf` build [V] |
| Blizzard forums (Discourse JSON) | dev notes 2360696, class tuning 2404092, hotfix thread 2403040, Known Issues 2402363, dungeon XP post 2406595 | fetched 2026-11-09 |
| wowforevertalents.com | client-table readout of shaman spellbook and patch notes (build 70862) | page dated 7 Nov; fetched 2026-11-09 |

Method for the row audit [D]: parsed all 68 rows of `Data/Shaman.lua`, compared `durationMs`, `cooldownMs` (= max of
CooldownMs and CategoryCooldownMs, the generator's rule), `gcdMs`, `castMs`, `icdMs`, `maxStack` to the live store. Result: **4
rows differ, all expected**: `Lightning Shield` icd 3500 and `Windfury Weapon` icd 1500 (kept probe values; the store has no
AuraOptions ICD on those exact ids, the sibling rows carry 3500 and 1500), and `Berserking` / `Rapid Regeneration` 180000
(owner-measured dev-notes pins, ids not in the store). Then compared the same fields to the client tables for 70862: the only
difference is the DB2 encoding of "no duration" as empty versus the store's `0`.

---

## 2. The known live changes, verified

| Change | Store (70790 @113715) | Client DB2 70862 | Our `Data/Shaman.lua` | Verdict |
|---|---|---|---|---|
| **Chain Lightning cast 2.5 s** | `421/930/2860/10605` castMs 2500, category 85, category cd 6000, cost 245/360/425/495 | cast 2500, cat cd 6000, category 85 | `[10605]` line 69: castMs 2500, cd 6000, cat 85 | match |
| **Totemic Projection cd 30 s** | `437009` named **Totemic Call**, cd 30000, dur 1000, GCD 1500, cost 25% base mana | cd 30000, GCD 1500, name `Totemic Call`; no `Totemic Projection` name row exists | `[437009]` line 83: name "Totemic Projection", cd 30000 (alias `Totemic Call` in `ShamanByName`) | match; alias law covers the rename |
| **Riptide costs / cd** | `408521/1239242/1239243` cost **150/180/230**, cd **12000**, category 1228 | category cd 12000, cat 1228 | `[1239243]` line 68: cd 12000, dur 15000, tick 3 | match |
| **Stormstrike** | `17364` cd **6000**, dur 12000, `ProcCharges 1`, effect 3 = 150% weapon damage | cd 6000 | `[17364]` line 85: dur 12000, cd 6000 | match |
| **Maelstrom Weapon** | aura `408505` dur 30000, `MaxStack 5`, effects −20% cast time / −20% mana cost per stack on Lightning Bolt; talent `408498` 5 ranks | dur 30000 | `[408505]` dur 30000, maxStack 5 | match |
| **Natural Alignment Crystal** | item 19344, on-use 300000, shared category 1141 / 20000, aura `23734` "Nature Aligned" 20000 | ItemEffect 103537: cd 300000, category cd 20000, SpellDuration 20000; `AllowableClass 64` (Shaman) | `Forte_Items/Data/Items.lua:202` cd 300000, dur 20000, classAllowlist `ClassShaman` | match |
| **Totems cast at Self** | not a store field | n/a | n/a | see below |
| Lava Burst removed | store keeps rows `408490/408491/1238373` | client name rows exist; spellbook says "No longer trained" | not tracked | correct |
| Elemental Mastery renamed | `16166` = `Lightning Mastery` | `SpellName 16166` = `Lightning Mastery`, no `Elemental Mastery` rows | `[16166]` key `Elemental Mastery` + alias | match; alias law covers it |

All values above are [D]. Blizzard's own statement of these changes is [V]: dev notes post 9, 2026-11-03,
https://us.forums.blizzard.com/en/wow/t/2360696 (fetched 2026-11-09):

> "Totemic Projection renamed Totemic Call. It now teleports the Shaman's totems to the Shaman's own location, and its cooldown is reduced to 30 seconds."
> "Chain Lightning cast time increased to 2.5 seconds."
> "Elemental Mastery renamed Lightning Mastery."
> "Elemental Reach no longer reduces the cooldown of Totemic Projection."
> "Maelstrom Weapon: Chance to trigger doubled."
> "Stormstrike: Now deals 150% normalized weapon damage, up from 100%. Cooldown reduced to 6 seconds from 8 seconds."
> "Riptide: Mana cost reduced by about 40%. Cooldown increased to 12 seconds from 6 seconds. Riptide no longer deals any initial healing, just healing over time."

The client-side rendering of the same changes, [V] https://wowforevertalents.com/patch-notes (3 Nov 2026 entry): Chain Lightning "495 Mana
(was 315 Mana). 2.5 sec cast (was 2 sec cast)"; Riptide "230 Mana (was 385 Mana). 12 sec cooldown (was 6 sec cooldown)".

Notes per row:

- **Chain Lightning.** The 70425 base rows say 145/…/315 mana and 2000 ms. The store and DB2 say 245/360/425/495 and 2500. FX does not
  read costs. Elemental Alacrity (`16578`) takes up to 0.5 s off Lightning Bolt and Chain Lightning cast time [V]
  wowforevertalents ("0.17/0.33/0.5 sec"); FX's `castMs` is the untalented 2500.
- **Totemic Call.** Learnable: SkillLineAbility row 49892, skill line 373, ClassMask 64, level 22 [D]. The Elemental Reach
  store row (`28999`) still carries a dummy effect with base points −20000 (effect index 2, aura 4), but the tooltip no longer
  mentions it and Blizzard says the reduction is gone. Whether the dummy still does anything server-side is [UNVERIFIED]; see
  open question 3.
- **Riptide cost columns.** The 70425 base pull (what mythicsim carries) still has 245/300/385. The "Riptide costs" change is a
  store/DB2 fact, not in our data because no cost column exists. Resto Tier 1 5-piece (`1301713`) takes 1 s off Riptide's
  cooldown [D]; set modifiers are not modeled (class-port A4).
- **Stormstrike.** Improved Stormstrike (`1223031`, talent, 2 ranks): "you have a $m1% chance to gain … mana regeneration …, and
  Stormstrike's cooldown has a $m2% chance to reset each time you Dodge or Parry" [D store description; both effects 20 at
  rank 1]. Tier 1 Enhancement 5-piece (`1301709`) takes 0.5 s off the cooldown [D]. The 6 s bar can end early; see §5.
- **Maelstrom Weapon.** The wowforevertalents 4 Nov entry says the "higher trigger chance … no table shows yet". I could not
  tell from the store which of the talent's three effects (20, 50, 5) is the chance. The live proc rate is [UNVERIFIED]; FX does not
  use it (the proc is unobservable in combat). Tier 1 helper `1291078` makes Lightning Bolt able to proc it "with a 50% reduced
  chance" [D].
- **Totems at Self.** mythicsim `src/classes/shaman/prepared/coverage.rs` [D]: "A totem that only places its aura takes no
  target, so a cast on the player drops it as a cast at the target does (a healer's Mana Spring Totem cast at Self, 4 November
  2026)." with `self_spells: &["basic_totem"]`. So a basic totem cast has the player as its target. Effect on FX: §8.

---

## 3. Totems: durations, cooldowns, GCD (client 70862, equal to the store)

| Totem | Data id | Duration | Cooldown (category) | GCD | Match |
|---|---|---|---|---|---|
| Stoneskin R6 | 10408 | 300 s | none | 1.0 s | yes |
| Strength of Earth R4 | 10442 | 300 s | none | 1.0 s | yes (R5 `25361` is tablet-taught; sim comment `totems.go:12-14`) |
| Grace of Air R2 | 10627 | 300 s | none | 1.0 s | yes (R3 `25359` tablet-taught) |
| Healing Stream R5 | 10463 | 300 s | none | 1.0 s | yes |
| Mana Spring R4 | 10497 | 300 s | none | 1.0 s | yes |
| Fire / Frost / Nature Resistance | 10538 / 10479 / 10601 | 300 s | none | 1.0 s | yes |
| Poison / Disease Cleansing | 8166 / 8170 | 300 s | none | 1.0 s | yes; Blizzard fixed Disease Cleansing to 5 min on 2026-10-01 [V] dev notes post 4 |
| Flametongue R4 | 16387 | 300 s | none | 1.0 s | yes |
| Windfury R3 | 10614 | 300 s | none | 1.0 s | yes |
| Windwall R3 | 15112 | 300 s | none | 1.0 s | yes |
| Tremor | 8143 | 300 s | none | 1.0 s | yes |
| Magma R4 | 10587 | **20 s** | none | 1.0 s | yes; Trial by Fire row shows +20 s (§5) |
| Searing R6 | 10438 | **55 s** (R1 30 s … R6 55 s) | none | 1.0 s | yes |
| Stoneclaw R6 | 10428 | **15 s** | **30 s** (cat 45) | 1.0 s | yes |
| Grounding | 8177 | **45 s** | **15 s** (cat 230) | 1.0 s | yes; Guardian Totems row shows −1 s |
| Earthbind | 2484 | **45 s** | **15 s** | 1.0 s | yes; Tier 1 Elemental 3-piece (`1301053`) −2 s |
| Mana Tide R4 | 1325256 | **13 s** (12 s of pulses) | **300 s** (cat 591) | 1.0 s | yes; the 38th-level rank was added 2026-10-16 [V] dev notes post 6 |
| Totemic Call | 437009 | 1 s | **30 s** | 1.5 s | yes |
| Fire Nova (not a totem) | 408345 R5 | none | **10 s** (cat 35) | 1.5 s | yes; Trial by Fire −2 s |

[D] for every number (SpellMisc, SpellCooldowns, SpellCategories, build 70862; the cooldown and totem rows of `Data/Shaman.lua`, lines 64-139).

Beta-era totem rules still on record [V] https://us.forums.blizzard.com/en/wow/t/2360696:

- post 1: "Rage of the Far Seer (Row 7) no longer increases the Shaman's Spell Casting Speed."
- post 1 and 6: Windfury Totem and Flametongue Totem keep exclusivity; Grace of Air is not exclusive with them; the four
  buff totems are raid wide; "Tranquil Air Totem, Windfury Totem, and Grace of Air Totem no longer stack together".
- post 1 also says "Flametongue Totem no longer has a duration" (2026-09-24). The 70862 table has `16387` at 300000 ms [D], so
  that line is stale or was reverted. The tracker reads the real window from `GetTotemInfo`, so it is not affected.

Forever-specific: `Tranquil Air Totem` and `Fire Nova Totem` are gone [D wowforevertalents spellbook, "Not in Forever"]. `Sentry Totem`
(`6495`, 300 s) is in the spellbook and is not tracked (§9, low).
`Call of the Elements / Ancestors / Spirits` (`66842/66843/66844`) are **multi-totem casts**, not a Far Sight line: "Simultaneously
places up to 4 totems specified in the Totem Bar", cast 3 s, GCD 1.5 s [D store description + Misc]. The `_comment` in
`shaman.json` describes them wrongly.

---

## 4. Shocks, Lightning Mastery, Bloodlust-equivalent, shields, imbues

### 4.1 Shocks and the shared cooldown (bug)

[D] Client `SpellCategories` (70862): `10414` (Earth Shock R7), `10448` (Flame Shock R5) and `10473` (Frost Shock R4) are all
category **19** ("Quick Damage - Spell"), 6 s category cooldown. The store and the client also hold a **second Earth Shock ladder**
`408681 / 408683 / 408685 / 408687 / 408688 / 408689 / 408690` in category **2171**, which `SpellCategory` names
`S03 - Earth Shock - Way of Earth` (the Season-of-Discovery rune version). SkillLineAbility has `8042` and `10414` in the
shaman skill line (375) and **none** of the `4086xx` ids. wowsims' compiled shaman code also uses the classic ladder
(`shocks.go:9-11`, comment "The three shocks share category 19").

Our generator picked `408690` by the ID tiebreak (`Data/Shaman.lua:65`, `cooldownCategory = 2171`). Consequences [D/INFERENCE]:

- The Earth Shock row carries category 2171 while Flame Shock (line 66) and Frost Shock (line 67) carry 19.
- `shaman.json` has no `_shares`, and `Engine:OnCast` (`Forte_Cooldown/Core/Engine.lua:265-269`) only starts partner bars through a
  one-level `shares` link. So a cast of any shock leaves the other two bars un-started. Out of combat the next cooldown read
  corrects it; in combat the reads can be secret [INFERENCE], so the other two shocks would look ready while on cooldown.
- A data-only fix cannot cover a three-member group with the single-partner `_shares` seam (§10 item 3 explains why). The clean fix is
  an engine rule: rows with the same non-zero `cooldownCategory` start each other. The data already carries the category.

Earth Shock also takes the Stormstrike bonus; see §5.

### 4.2 Lightning Mastery (was Elemental Mastery)

[D] `16166`: 15 s, 180 s cooldown, SkillLineAbility row 8838 (skill line 375). Effects: −0.5 s cast time (Lightning Bolt) and
−100% cooldown (Chain Lightning). Description: "reducing the cast time of your Lightning Bolt spell by 0.5 sec, and removing the
cooldown from your Chain Lightning spell. Lasts 15 sec." The store row has `ProcCharges 1`; whether a cast consumes the buff is
[UNVERIFIED] (the description says "Lasts $d" and mythicsim does not consume it). Our row `[16166]` (line 79) matches
(15 s, 180 s, `noTarget`). The tracker name is `Elemental Mastery` with alias `Lightning Mastery`; the client has no
`Elemental Mastery` rows [D SpellName], so the alias is what a client lookup will hit.

### 4.3 Nature's Swiftness, Reincarnation, Far Sight, Ancestral Spirit

[D] Nature's Swiftness `16188` cd 180 s (talent); Reincarnation `21169` category cd 3 600 000 ms (cat 1161);
Far Sight `6196` 60 s, cast 2 s; Ancestral Spirit R5 `20777` cast 10 s. All match Data.

### 4.4 Bloodlust-equivalent

[D] `Rage of the Farseer` `425336`: SkillLineAbility 49547 (skill line 373, ClassMask 64), talent node (1 rank). Description:
"Increases your attack speed by $s1% for $d." Effect 0 is aura 342 with 30; target self (`[1,0]`). Duration 25 s, cooldown 180 s.
Our row (line 82): 25 s / 180 s / `noTarget` is correct.
[V] dev notes post 1: "Rage of the Far Seer (Row 7) no longer increases the Shaman's Spell Casting Speed." So it is a melee/ranged
attack-speed buff, self only, not a raid-wide haste.

`Heroism` and `Bloodlust` are **not** shaman spells here: no skill-line row with ClassMask 64 exists for any `Heroism` or
`Bloodlust` id [D]. `23689` "Heroism" ("Sometimes heals bearer of … damage when damaging an enemy in melee") is the Darkmoon Card:
Heroism proc, already carried as buff 23682 / "Heroism (23689)" in `Forte_ItemProcs/Data/Procs.lua:177`. Our shaman row
`[23689]` (line 87) has `durationMs = -1` and no cooldown, so it draws nothing. `Time Warp` has no spell name in the store.
[INFERENCE] The `Forte_Casting.lua` haste table of the 2012 reference (Heroism/Bloodlust/Time Warp 1.30) has no shaman source
on Forever.

### 4.5 Shields: charges, ICD, duration

| Shield | Cast id | Duration | Charges | ICD | Cost | Source |
|---|---|---|---|---|---|---|
| Lightning Shield R1-R7 | `324…10432` | **600 s** | **3** | **3500 ms** | 45…370 mana | store AuraOptions `ProcCharges 3`, `ICDMs 3500`; wowforevertalents "surrounded by 3 balls of lightning … Lasts 10 min" |
| Water Shield (talent) | `408510` | 600 s | **3** | **3500 ms** | n/a | AuraOptions; "restores 2% of maximum mana" per globe (`408511`, base points 2); Blizzard: "no longer says it has a 15 second cooldown (it didn't have one)" [V] dev notes post 5 |
| Earth Shield | `408514` | 600 s | **9** | **3500 ms** | 5% base mana | AuraOptions; **not obtainable** (§7) |

[D] for the table. [V] dev notes post 6 (2026-10-16): "Water Shield: Can now trigger from any critical spell cast by the
Shaman (was only critical heals)." One elemental shield at a time on the shaman (store description of `408510`).
FX's generated data has no charge column: `maxStack` is the only count the generator emits, and Water/Lightning/Earth Shield
charges live in `ProcCharges`. Shield charges are consumed by hits taken, which FX cannot see in combat
[INFERENCE: no combat log, aura reads secret].

### 4.6 Weapon imbues

- [D] Shaman imbue enchants last **3600 s**: SpellItemEnchantment (70862), every Rockbiter / Frostbrand / Flametongue / Windfury
  row I sampled (ids 1, 2, 3, 5, 29, 283, 284, 503, 523, 524, 525, 1664-1669) has `Duration 3600`. The imbue spells themselves
  carry `DurationMs 0` in the store.
- FX tracks the imbue window through `C_Item.GetWeaponEnchantInfo`, not through spell data
  (`Forte_Cooldown/Core/Enchants.lua:1-63`). Nothing in that file is shaman-specific, and it parks windows over 300 s at the bar's end.
- Windfury Weapon: passive `439431` has 20% proc chance, ICD **1500 ms**, proc flags 20; aura `16361` Rank 4 has `ProcCharges 3`,
  dur 1500 ms, 2 extra attacks, +333 attack power. The 3600 s duration is not in either row [D].
- Flametongue Weapon: cast `16342`; no proc roll (passive `436519`); the hit is a fire spell with damage per weapon speed (`weapon_imbues.go`).
- Frostbrand: `16353` slow (aura 33, −25%) with **8 s** duration, rolled as procs per minute. Rockbiter: `16313` attack power + threat.
- Stamp rows in `Data/Shaman.lua` lines 101-104: only `Windfury Weapon` (1.5 s) and `Frostbrand Attack` (8 s) have windows, and both are
  procs the cast spine cannot see. [INFERENCE] The only way `Windfury Weapon` draws is when the player casts the imbue, which
  would put up a false 1.5 s bar.

---

## 5. What our timers cannot know (modifiers, procs, consumption)

All [D] from store effect rows and descriptions; the FX consequence is [INFERENCE].

| Row | Talent / set effect | Effect on the real window | Our row |
|---|---|---|---|
| Flame Shock | Call of Flame (`16038`, 3 ranks): "increases the duration of your Flame Shock spell by 3/6/9 sec" [V wowforevertalents]; Tier 1 helper `1291077` +3 s | 12 s → up to 21 s (24 s with the helper) | 12 s |
| Magma Totem | Trial by Fire (`16086`, 2 ranks): the store row shows +20 s; Fire Nova cd −2 s | 20 s → up to 40 s | 20 s (tracker reads the real window) |
| Reincarnation | Improved Reincarnation (`16184`, 2 ranks): the store row shows −600000 ms (10 min) | 60 min → 50 min or less [INFERENCE: per-rank values not read] | 60 min |
| Grounding Totem | Guardian Totems (`16258`, 2 ranks): the store row shows −1000 ms | 15 s → 14 s or less [INFERENCE] | 15 s |
| Earthbind Totem | Tier 1 Elemental 3-piece: −2 s | 15 s → 13 s | 15 s |
| Stormstrike | Tier 1 Enhancement 5-piece −0.5 s; Improved Stormstrike 20% reset on Dodge/Parry | 6 s, can end early | 6 s |
| Riptide | Tier 1 Resto 5-piece −1 s | 12 s → 11 s | 12 s |
| Molten Blast | "Flame Shock periodic damage has a 5% chance to reset the cooldown" (`425339`) | can end early; not obtainable (§7) | 6 s |
| Chain Lightning | Lightning Mastery removes the cooldown for 15 s; Elemental Alacrity −0.5 s cast | 6 s cooldown absent for 15 s | 6 s, 2.5 s |

The cooldown engine's `learned` durations (`Engine.lua:BestDuration`) correct a **cooldown** from a plain out-of-combat read; the
Timer's `learned[name]` (`Registry.lua:13-17`) does the same for aura windows read out of combat. Neither sees a mid-fight reset.

**Stormstrike consumption.** [D] The aura effect's class mask on `17364` effect index 1 is `1048579` = bits 0, 1, 20 = Lightning Bolt,
Chain Lightning, Earth Shock. `ProcCharges 1`. wowsims' Go code reads that mask as the consumer set
(`stormstrike.go:21-29`, "the next of them to hit spends" the charge). mythicsim patch 140, from in-game beta testing on
2026-10-16, says the opposite for Earth Shock: "Earth Shock takes Stormstrike's bonus without spending a charge; only Lightning
Bolt, Chain Lightning and their overloads spend it" ([D] `mythicsim-forever-engine/UPSTREAM.md:462`, `masks.rs:38-39`). Blizzard
also fixed it on 2026-10-16 [V] dev notes post 6: "Your Stormstrike debuff is no longer consumed if your spell does not land."
The 12 s bar can therefore overrun the real debuff. An own-cast prediction (retire the target row on the player's next
`UNIT_SPELLCAST_SUCCEEDED` of Lightning Bolt or Chain Lightning) would be approximate because "does not land" is unobservable.
The Earth Shock rule is in conflict between two sources; see open question 4.

---

## 6. Blizzard notes, 2026-11-06 to 2026-11-10

All fetched 2026-11-09.

| Date | Post | Shaman content |
|---|---|---|
| 11-06 | Hotfixes, https://us.forums.blizzard.com/en/wow/t/wow-forever-hotfixes-november-6-2026/2403040 | **None.** The Classes list names Druid, Mage, Rogue, Warlock, Warrior, a Cooldown Manager CC line and the Quick and the Dead legacy talent. Items: "Searing Dagger is now only activated by spells that have a damaging component." |
| 11-06 | Class Tuning Incoming, https://us.forums.blizzard.com/en/wow/t/2404092 (post 1, Kaivax, 21:11 UTC) | planned for Tue 11-10: "Enhancement Shamans are finding that Intellect and Spellpower are superior stats compared to Strength and Attack Power. We plan to make changes so that Strength is always their strongest stat, and Enhancement Shamans will not prefer gear intended for Mages and Warlocks. Ideally, Enhancement's best items have Strength or Attack Power, along with some Intellect and/or Spell Power." And: "Our plan is to make class balance changes on Tuesday, and then on future Tuesdays if necessary." |
| 11-07 | same thread and hotfix thread | the Nov 6 list was re-posted without the Nov 5 section; no new entry |
| 11-08 | Dungeon Enemy XP Increased, https://us.forums.blizzard.com/en/wow/t/2406595 | not class content ("increased kill experience in dungeons by 50%") |
| 11-06 | seramate mirror of Wowhead, https://seramate.com/news/forever/2026/11/06/forever-shaman-talents-revisit-next-year-ccab8e0c | quotes Kris Zierhut (Crix interview): "I wouldn't be surprised if early next year we revisit Shaman talents a little bit. It's not going to be sooner than that. It's going to be a Patch." Second-hand |
| 11-05 | Known Issues thread 2402363 (edited 11-05 22:07) | no class, spell or addon entries |

[D] Nothing between 11-06 and 11-09 touches a shaman spell in the client tables: zero shaman diffs between builds 70790 and 70862 and
between the store and our overlay. The "Tuesday" changes concern gear stat priority; the likely carrier is Mental Dexterity
(`415140`, "Increases your Attack Power by … Intellect", talent) or itemization [INFERENCE]. FX tracks no row for either.
The ground truth for "does 11-10 move our data" is the first store pull after it (§ Open questions 6).

---

## 7. Forever-specific spells and what is dead

Live Forever shaman spellbook, 51 trainer spells, build 70862 [V] https://wowforevertalents.com/abilities/shaman/ (fetched
2026-11-09): **new in Forever** `Totemic Call`, `Riptide`, `Fire Nova` (now an instant, 10 s cd, "within 10 yd of your active Fire
totem"), `Call of the Elements`, `Totemic Recall`, `Call of the Ancestors`, `Call of the Spirits`; **gone** `Tranquil Air Totem`,
`Fire Nova Totem`, `Lava Burst` ("No longer trained").

Talent tree [D]: `TraitNodes` for class `shaman` in the live store has **50 nodes**. Present among our tracked names: Riptide,
Water Shield, Stormstrike, Rage of the Farseer, Nature's Swiftness, Mana Tide Totem, Lightning Mastery, Maelstrom Weapon,
Elemental Focus (Clearcasting), Elemental Devastation, Flurry, Call of Flame, Call of Thunder, Lightning Overload, Improved
Stormstrike, Mental Dexterity.

**Not in the tree, not in the spellbook, not in wowsims' compiled shaman package** [D] (`sim/shaman/spell_data_auto_gen.go` has
no ladder for any of them; the only mention of Earth Shield is the build-ignored `_heals.go` with Wrath id 49284):

| Tracked name | Id | What it is |
|---|---|---|
| Earth Shield | 408514 | SoD rune (`Engrave Pants - Earth Shield`, skill line 2851) |
| Lava Lash | 408507 | SoD rune |
| Molten Blast | 425339 | SoD rune |
| Healing Rain | 415236 | SoD rune |
| Decoy Totem | 425874 | SoD rune |
| Feral Spirit | 440580 | SoD rune |
| Ancestral Guidance | 409944 (real ability `409324`, 60 s cd, 10 s) | SoD rune |
| Tidal Waves / Way of Earth / Power Surge / Shield Mastery | 432041 / 408680 / 468526 / 426981 | SoD rune effects |
| Heroism | 23689 | Darkmoon Card proc (§4.4) |

Also untracked SoD rune spell that exists in the files: Spirit of the Alpha (`408696`, 30 min aura, 8% base mana). Confidence: high that a Forever player cannot learn the tracked ones above (three independent sources). The
cheap live proof is `IsPlayerSpell(408514)` / `(408507)` on a shaman; see open question 1.
`Energized Shield` (`24499`, "Increases the damage dealt by your Lightning Shield spell by $s1% for $d") is Classic-era text; I could
not confirm whether anything grants it on Forever: [UNVERIFIED], left alone.

All of these are inert in FX: cooldown rows need a known spell (`Engine:AddExtras`/`Build` gate) and timer rows need a cast.
`Forte_Cooldown/tests/test_tracked_set.lua` currently asserts rows for `Ancestral Guidance` and `Heroism`, so removing them
is a test edit too.

---

## 8. The totem tool (`Core/Totems.lua`), read only

Verdict: the design fits the live rules. Points, none a blocker:

1. **One slot per element.** `ELEMENTS = {Fire, Earth, Water, Air}` and MAX_TOTEMS 4. Forever keeps that model: "Shaman totems no
   longer stack in a group" (dev notes, Sept-Oct) [V], and each basic totem still sits in its element slot [D sim `totems.go` `dropTotem`].
2. **Casts at Self.** A totem cast targets the player (mythicsim `coverage.rs`, §2). The cast spine keys a prediction row by the
   cast target; the F-B dedupe `Casts:RetireOwnedRows(name, keepKey, now)` retires every predicted row of that name whose `targetKey`
   is not the element key (`Forte_Timer/Core/Casts.lua:284-296`). It is key-agnostic, so Self versus "none" does not break it
   [D]. The remaining exposure: when the slot read is sealed, the spine's prediction row stays and is keyed to the player
   name rather than an element [INFERENCE]. Data cannot express `noTarget` for totems: the generator derives it from effect
   `Target[0] == 1`, and totem effects are summons (type 28).
3. **Call of the Elements / Ancestors / Spirits.** One cast, up to four totems. The player gets one `UNIT_SPELLCAST_SUCCEEDED` (the
   call spell) and up to four `PLAYER_TOTEM_UPDATE`s. In a sealed state the cast spine has no per-totem prediction at all
   [INFERENCE]. Out of the sealed state each slot read draws its own row.
4. **Totemic Call (relocate).** "Relocates your active totems to your location." Whether this fires `PLAYER_TOTEM_UPDATE` per slot,
   and whether it resets each totem's window or keeps its remaining time, is [UNVERIFIED]. If it destroys and re-creates the
   slot, the tracker's `REMOVE` fade law would paint a red removal for a totem that is still up. Needs one live probe
   (open question 2).
5. **Totemic Recall** (`36936`): returns totems to the earth with 25% mana. The tracker sees empty slots and fades with the
   red `REMOVE` band unless within 0.75 s of expiry. That is the right band for an early removal.
6. **Fire Nova** needs an active Fire totem ("within 10 yd of your active Fire totem" [V] wowforevertalents). The Fire slot
   state is the natural gate for a Fire Nova ready hint, and the tracker already owns it. No work requested; noting the
   dependency.
7. **Totem durations are read, not predicted,** so the base-duration modifiers in §5 (Trial by Fire) do not affect the rows
   when the read is plain. They matter only for the cast prediction in a sealed read.
8. `SlotSpellNames()` matches data names ending in `Totem`. After the §11.3 clean-up it still finds the live 16 totems plus
   `Sentry Totem` if added (§11.4); `Decoy Totem` drops out.

---

## 9. Class-report questions

The assignment says "same class-report questions" without listing them; I used the frame of the repo's data-diff and class
reports. Answers:

1. *What changed live versus our pinned data?* Nothing in the shaman data (§1, §2). All six named changes are already in `Data/Shaman.lua`.
2. *Are our rows the right rows?* Two are not: Earth Shock and Lightning Shield (§4.1, §4.5). Windfury Weapon is questionable (§4.6).
3. *What is dead or missing?* Dead: §7. Missing and cheap: `Sentry Totem` (`6495`, 300 s) and `Astral Recall` (`556`, 900000 ms
   category cd, cast 10 s); low value.
4. *What do our timers mis-report?* Talent/set modifiers, proc resets and Stormstrike consumption (§5), plus the missing shared shock
   cooldown (§4.1).
5. *What comes on Tuesday?* Enhancement stat priority only; no spell-data change is announced (§6).
6. *Which Forever-only spells exist?* §7.

---

## 10. Implications for our setup

1. The data pipeline is current for the shaman. A regeneration against today's clones would change **nothing** in values;
   the 70790 header stamp is still the live one for this class.
2. The two pins (Earth Shock, Lightning Shield) are the only changes that alter emitted rows. After them, Earth Shock reads
   `cooldownCategory = 19`, and Lightning Shield gains `durationMs = 600000`, `gcdMs = 1500`, `icdMs = 3500` and a registered
   timer row. The Registry's colour bands already list `^Lightning Shield` (`Registry.lua:349-350`), so it lands in a
   band; confirm in the sim.
3. A single-partner `_shares` cannot express the three-shock group. The seam is `shares = "partner"` and the walk starts only
   direct partners (`Engine.lua:265-269`). Hub model with Flame Shock: casting Flame Shock starts Earth and Frost; casting
   Earth or Frost starts only Flame. Two of three casts leave one partner stale. The real fix is an engine rule by equal
   non-zero `cooldownCategory`. That is an engine change, not a data edit; I list it separately.
4. Do not widen the haste model for the shaman: Rage of the Farseer is attack speed only (§4.4).
5. Keep reading durations for totems from `GetTotemInfo`; keep base durations for the cast prediction only.
6. Talent modifiers (§5) are the largest remaining accuracy gap for Flame Shock, Magma Totem, Reincarnation and Grounding Totem. They
   need a `C_Traits` rank read; they are not in data. This is the class-port A4 decision, not a shaman-specific one.
7. Re-pull the wowsims store after Tuesday's hotfix and diff the shaman root ids plus `415140`, `30812`, `408498` before trusting any
   post-11-10 value.

---

## 11. Proposed patch

Mechanically applicable. Evidence for each line is in the cited section. "Confidence" is mine.

### 11.1 `tools/spell_lists/shaman.json`: add to the existing `_pins` object (alongside `Berserking`, `Rapid Regeneration`)

```json
"Earth Shock": {
  "id": 10414,
  "reason": "408690 is the S03 Way-of-Earth ladder (category 2171, not in any shaman skill line); 10414 Rank 7 is the learnable row, category 19 shared with Flame Shock and Frost Shock (client SpellCategories 70862; SkillLineAbility 5578)"
},
"Lightning Shield": {
  "id": 10432,
  "reason": "28821 is a level-60 set-bonus passive (durationMs -1); 10432 Rank 7 is the cast: 600000 ms, 3 charges, 3500 ms ICD, GCD 1500 (store AuraOptions, SkillLineAbility 5589)"
}
```

- Earth Shock pin: confidence **high**. One-line reason: wrong category row; fixes the 19 vs 2171 mismatch.
- Lightning Shield pin: confidence **high**. One-line reason: today no timer row is registered for it at all.

Expected generated rows after the pins (for the builder to confirm, not to hand-edit):

```lua
[10414] = { id = 10414, name = "Earth Shock", durationMs = 2000, cooldownMs = 6000, cooldownCategory = 19, gcdMs = 1500, rank = "Rank 7" },
[10432] = { id = 10432, name = "Lightning Shield", noTarget = true, durationMs = 600000, gcdMs = 1500, icdMs = 3500, rank = "Rank 7" },
```

### 11.2 Same file: shared shock cooldown (interim only)

```json
"_shares": {
  "Earth Shock": "Flame Shock",
  "Frost Shock": "Flame Shock"
}
```

- Confidence **low** as a fix: covers Flame Shock casts fully and Earth/Frost casts only half (§10 item 3). Prefer the engine rule
  (equal non-zero `cooldownCategory` starts each other, tracked rows only). Confidence **medium** that the engine rule is the right
  design (the category is in the data).

### 11.3 Same file: remove dead names (inert today, so clean-up; update `test_tracked_set.lua` and `test_00_class_data.lua` accordingly)

```json
"cooldowns": remove  ["Molten Blast", "Lava Lash", "Healing Rain", "Decoy Totem", "Feral Spirit", "Ancestral Guidance", "Heroism"],
"buffs":     remove  ["Earth Shield", "Power Surge", "Shield Mastery", "Tidal Waves", "Way of Earth"],
"utility":   remove  ["Call of Flame", "Call of Thunder"]
```

- Confidence **high** that none of the cooldown/buff names is learnable on Forever (§7), **medium** that removing is better than
  keeping (owner ruling Q6 added `Heroism` and others on 2026-11-02; keeping them costs nothing).
- `Call of Flame` / `Call of Thunder` are talents with no cast and no window (`durationMs` absent): confidence **medium**, zero value.
- Leave `Energized Shield` alone: **[UNVERIFIED]**.

### 11.4 Same file: stamps and additions (low value)

```json
"_pins": { "Windfury Weapon": { "id": 16362, "reason": "16361 is the proc aura (1500 ms, 3 charges); 16362 Rank 4 is the imbue cast, no window, so casting the imbue draws no false 1.5 s bar" } },
"totems": add ["Sentry Totem"],
"cooldowns": add ["Astral Recall"]
```

- Windfury Weapon pin: confidence **low** (rests on [INFERENCE] about a false bar; test with one imbue cast).
- `Sentry Totem` (`6495`, 300 s, spellbook): confidence **medium** it exists and the duration is right; value low.
- `Astral Recall` (`556`, category cd 900000, cast 10 s): confidence **high** on the values, value low.

### 11.5 Comment fix in `shaman.json` `_comment`

Replace "the Far Sight scry line is split into Call of the Elements/Spirits/Ancestors (L20/30/40) and Call of Flame/Thunder (L60)" with:
"Call of the Elements/Ancestors/Spirits (L20/30/40) place up to four totems from the totem bar; Call of Flame and Call of Thunder are
talents." Confidence **high**.

### 11.6 Not a data patch, for the builder to decide

- Engine: category-based shared cooldown in `Forte_Cooldown/Core/Engine.lua` `OnCast` (replaces `_shares` for groups).
- Generator: emit `procCharges` from `AuraOptions.ProcCharges` (3 / 3 / 9 for the shields, 3 for Flurry, 1 for Stormstrike) if shield
  or charge badges are wanted. Confidence **low**: charges drain on hits the addon cannot see in combat.

---

## 12. Open questions

1. **Learnability of the SoD leftovers.** Run `IsPlayerSpell(408514)`, `(408507)`, `(425339)`, `(415236)`, `(440580)`, `(409324)` on a
   level-60 shaman. Predicted all false.
2. **Totemic Call and `PLAYER_TOTEM_UPDATE`.** Does one cast fire one event per slot, and does each totem keep its remaining window?
   Probe with `/fx probe` or a scratch frame on an active Fire and Earth totem.
3. **Elemental Reach dummy.** With 2/2 Elemental Reach, is the Totemic Call cooldown 30 s or 10 s after a cast?
   (`C_Spell.GetSpellCooldown(437009)`.) Blizzard's note and the tooltip say 30 s; the store row keeps a −20000 dummy.
4. **Does Earth Shock consume Stormstrike?** wowsims' mask says yes; mythicsim patch 140 (beta, 2026-10-16) says no. One test:
   Stormstrike, then Earth Shock, then read the debuff stacks on the target out of combat.
5. **Lightning Mastery consumption.** The store row has `ProcCharges 1`; is the 15 s buff spent by the next Chain Lightning?
6. **Post-11-10 diff.** Re-pull wowsims/forever after the Tuesday hotfix and re-run the row audit of §1 on the shaman roots
   plus `415140`, `30812`, `408498`, `1223031`. Expected: no timer-relevant change.
7. **Maelstrom Weapon trigger chance.** Which of the talent's effects (20 / 50 / 5) is the proc chance, and is the live value the
   doubled one? Not needed for any FX row, but the 4 Nov tracker entry says "no table shows yet".
8. **Is `Windfury Weapon` imbue-cast really drawing a 1.5 s row?** One imbue cast on a shaman with the Timer open.
9. **`Energized Shield` (`24499`).** Does anything grant it on Forever?

---

## Sources

- Blizzard forums, dev notes (posts 1, 4, 5, 6, 9): https://us.forums.blizzard.com/en/wow/t/2360696 (JSON fetched 2026-11-09)
- Blizzard forums, Class Tuning Incoming - November 10: https://us.forums.blizzard.com/en/wow/t/2404092
- Blizzard forums, hotfix thread: https://us.forums.blizzard.com/en/wow/t/wow-forever-hotfixes-november-6-2026/2403040
- Blizzard forums, Known Issues: https://us.forums.blizzard.com/en/wow/t/2402363
- Blizzard forums, Dungeon Enemy XP Increased - November 8: https://us.forums.blizzard.com/en/wow/t/2406595
- wowforevertalents patch notes: https://wowforevertalents.com/patch-notes ; shaman spellbook: https://wowforevertalents.com/abilities/shaman/
- seramate (Wowhead mirror): https://seramate.com/news/forever/2026/11/06/forever-shaman-talents-revisit-next-year-ccab8e0c
- wago.tools DB2 CSV, build 1.60.1.70862 and 70790: `https://wago.tools/db2/<Table>/csv?build=<build>` for SkillLineAbility, SpellName, SpellMisc,
  SpellCooldowns, SpellCategories, SpellCategory, SpellCastTimes, SpellDuration, SpellItemEnchantment, ItemEffect, ItemXItemEffect, ItemSparse;
  build list `https://wago.tools/api/builds`
- Local: `/tmp/wowsims-forever` @ `9ca4d977` (`assets/db_inputs/spell_store_inputs.json`, `sim/shaman/*.go`);
  `mythicsim-forever-engine` @ `ff6a43cf` (`data/spells.jsonl`, `src/classes/shaman/**`, `UPSTREAM.md`);
  repo `addon/Forte_Shaman/Data/Shaman.lua`, `addon/Forte_Shaman/Core/Totems.lua`, `addon/Forte_Timer/Core/{Registry,Casts}.lua`,
  `addon/Forte_Cooldown/Core/{Engine,Enchants}.lua`, `tools/gen_spell_data.py`, `tools/overrides_70790.json`.

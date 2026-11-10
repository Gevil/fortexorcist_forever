# Rogue live report: what is real on Forever, 2026-11-06 to 2026-11-10

Written 2026-11-09 by RsrchRogue (read-only research subagent). Scope: `tools/spell_lists/rogue.json` and the generated
`addon/Forte_Rogue/Data/Rogue.lua`. No repo file other than this one was touched. Scratch tables went to `/tmp` only.

**Labels.** Every claim carries one.

- **[V]** Verified. A quote or value from a page I fetched on 2026-11-09, with the URL.
- **[D]** Derived from local data or code (file:line, store key or jsonl row), or from a DB2 diff I computed. The method is stated.
- **[I]** Inference. My reading of what the evidence means for ForteXorcist (FX). Nobody has tested it.
- **[UNVERIFIED]** I could not verify it from tools or fetched pages.

**Local sources used** (all read-only, all dated today):

| Source | Pin |
|---|---|
| `/tmp/wowsims-forever` live store | HEAD `9ca4d977` (2026-11-09). Rogue group of `assets/db_inputs/spell_store_inputs.json` is `1.60.1.70790` at hotfix push `113715`. Items group and paladin group are `70862` at push `113823`. |
| `mythicsim-forever-engine` | HEAD `ff6a43cf` (2026-11-10 01:54 +1100). `data/spells.jsonl` is the 70425 base pull (7,503 rows). |
| wago.tools DB2 CSV exports | `https://wago.tools/db2/<Table>/csv?build=1.60.1.70790` against `...70862`. I diffed SpellCooldowns, SpellCategories, SpellLevels, SpellPower, SpellMisc, SpellEffect, SpellClassOptions, SpellAuraOptions, Spell (text), SpellName and SkillLineAbility for the 342 rogue-family ids (store `Family == 8`) plus 1324481, 343 in all, and for the new rows. |

---

## 0. Answers first

1. **[D] Nothing in the rogue's numbers moved between client builds 70790 and 70862, except one Gouge row.** In the wago DB2 diff,
   0 of 343 rogue-family spells changed in SpellEffect, SpellAuraOptions or SpellClassOptions. SpellMisc, SpellCooldowns,
   SpellCategories, SpellLevels, SpellPower and Spell-text each changed for only these:
   - the new Gouge parent row **1324481**;
   - the Shank and Boot Knife text fixes.
   `Rogue.lua` (generated from the 70790 store at push 113715) is therefore still value-correct for every row it carries.
2. **[D] The "Gouge got a cooldown in 70862" lead needs a correction.** The rank rows (1776/1777/8629/11285/11286) already carry
   `CategoryRecoveryTime 10000` in 70790 and in the 70425 base pull. The 70862 change is that the **parent row 1324481** became
   a castable-looking spell: cooldown row (cat 10000, GCD 1000), category 33, spell level 60, 45 Energy cost, and a rank-aware
   description (`$?s11286[$@spelldesc11286]?s11285[...]`). FX's Gouge data (`Rogue.lua:66`) is unchanged and right. The risk is
   name-to-id resolution (§3.3).
3. **[D] The Shank row is already correct.** `Rogue.lua:83` maps `Shank` to 1329549 (Rank 2, 10 s). Rank 1 is 1329283. Both have a
   10 s cooldown, 1 s GCD and 5 Energy cost. FX keys by name, so a level 24-43 rogue who knows only Rank 1 still tracks.
4. **[D] Death Mark is already correct.** `Rogue.lua:84`: 1325758 (Rank 4), 10 s cooldown, 6 s mark, single tick at 6 s. Ranks 1-3
   are 1316709 / 1325756 / 1325757 at levels 40 / 48 / 56. All four rows are identical in 70790 and 70862.
5. **[V] Blizzard's Nov 6 to Nov 9 posts contain two rogue lines, both tooltip-only** (Shank rank labels; Shank's Boot Knife
   combo-point text). **[V]** The only forward-looking post, "Class Tuning Incoming - November 10", names no rogue change.
6. **[D] The biggest real problems are in FX's tracked set, not in a Blizzard change.**
   - (a) Combo-point finishers draw the wrong window length: Slice and Dice, Rupture, Kidney Shot (§4.2).
   - (b) Poison weapon-enchant timers resolve the enchant id as a *spell id*. For poisons that is a different spell (§4.1).
   - (c) About 20 tracked names are not in Forever's rogue spellbook. They are Season-of-Discovery rune leftovers (§5).
   - (d) The Blood Splatter spell row (4 s / 6 s) disagrees with Blizzard's notes and the talent curve (6 s / 9 s) (§4.2).
7. **Proposed patch** (end of file): add `Venom`, `Deadly Poison II/III/IV`, `Mind-numbing Poison II` and pin Venom. Optionally prune
   the rune leftovers. **No `_pins` are needed for Shank, Death Mark or Gouge.**

---

## 1. Blizzard posts, 2026-11-06 to 2026-11-10 (what exists on 2026-11-09)

Index source: `https://wow-forever.gg/official/` (a mirror, used as an index only; "Last checked 2026-11-09", newest entry
2026-11-08). Every item below was also fetched at Blizzard.

| Date (UTC) | Post | Rogue content |
|---|---|---|
| 2026-11-06 / 11-07 | Hotfixes, November 6, 2026, `https://worldofwarcraft.blizzard.com/en-us/news/24315281/wow-forever-hotfixes-november-6-2026` (fetched 2026-11-09; the page holds only a Nov 5 and a Nov 6 section) | 2 lines, below |
| 2026-11-06 21:11 | Class Tuning Incoming - November 10, `https://us.forums.blizzard.com/en/wow/t/class-tuning-incoming-november-10/2404092/1` | **None.** Names Hunter pets, Warlock Voidwalker, Affliction (Wrack vs DoTs) and Enhancement stat priority only. |
| 2026-11-08 19:47 | Dungeon Enemy XP Increased - November 8, `https://us.forums.blizzard.com/en/wow/t/dungeon-enemy-xp-increased-november-8/2406595` | None. |

**[V] Rogue lines, verbatim** (hotfix page, "November 6, 2026"):

> - **Rogue**
>   * Shank will now display Rank 1 and Rank 2 in the tooltips.
>   * While Boot Knife is talented, Shank will now correctly display the number of Combo Points it grants.

**[V]** Other lines on the same page that could touch a rogue's bar (none touch spell data):

- "The Cooldown Manager will now correctly display the duration of crowd control spells at all times, even when diminishing returns or mechanic reductions ... are factors."
- "Searing Dagger is now only activated by spells that have a damaging component." (Item proc, `Forte_ItemProcs/Data/Procs.lua`; no data change needed.)

**[V]** Nov 10 plan, quoted: "Our plan is to make class balance changes on Tuesday, and then on future Tuesdays if necessary." No rogue is named. **[UNVERIFIED]**
Nov 10 itself has not happened as of this report, so any hotfix list published on or after 2026-11-10 (UTC) is not covered here.

**[D] Where the two rogue hotfix lines show up in the client files.** `Spell` text diff 70790 to 70862:

| Row | Change |
|---|---|
| 1329283 Shank | `NameSubtext_lang` empty to `Rank 1`; description `1 Combo Point` to `2 Combo Points` |
| 1329549 Shank | `NameSubtext_lang` empty to `Rank 2`; same description change |

Both land in DB2 at 70862 and were already in the store's rogue group at push 113715 (the store carries `Subtexts["1329549"] = "Rank 2"` and the
"2 Combo Points" text). So the Nov 6 server hotfix preceded the 70862 client and the store captured it.
**[I]** Both are text-only. No timing or value field moved.

---

## 2. Client-file diff 70790 to 70862, rogue family only

Method **[D]**: `SpellName`, `SpellCooldowns`, `SpellCategories`, `SpellLevels`, `SpellPower`, `SpellMisc`, `SpellEffect`,
`SpellAuraOptions`, `SpellClassOptions`, `SpellEquippedItems`, `SpellInterrupts`, `SpellXSpellVisual`, `Spell` pulled for both builds.
"Rogue family" = the 342 ids whose store `ClassOptions.Family == 8`, plus 1324481 (343 in all).

| Table | Rogue-family changes |
|---|---|
| SpellEffect (581 changes overall) | 0 |
| SpellMisc (416 overall) | 1324481 (attribute word `Attributes_13` 33554560 to 128) |
| SpellAuraOptions, SpellClassOptions, SpellEquippedItems, SpellInterrupts, SpellXSpellVisual | 0 |
| SpellLevels | 1324481 (BaseLevel/SpellLevel 0 to 60) |
| SpellCategories | 1324481 new (Category 33, StartRecoveryCategory 133) |
| SpellCooldowns (4513 to 4543 rows) | 1324481 new row `ID 102498`: CategoryRecoveryTime 10000, RecoveryTime 0, StartRecoveryTime 1000 |
| SpellPower | 1324481 new (45 Energy) |
| Spell text | 1324481 (rank-aware description), 1329283 and 1329549 (Shank labels, Boot Knife text) |

**[D] New name-only rows in 70862 that reuse rogue names** (from the 395 new `SpellName` ids):

| Id | Name | What it is |
|---|---|---|
| 1271753 | Shadowstep | No class options, no skill line. Effect type 252, creature-style. |
| 1287444 | Stealth | No class options. Aura 16 with `BasePoints 9999`, `DurationIndex 21`. Creature-style. |
| 1271761 | Grievous Garrote | Hemorrhage-style creature bleed, GCD 1500. Different name from `Garrote`. |

**[I]** None of these three can displace a tracked row, because the generator's rank law prefers an in-family row (`gen_spell_data.py` docstring,
quoted in `docs/class-port.md` §2 A1: "in-family row carrying a cooldown/duration > uncoded"). I did not run the generator (hard rule).

**[D] Coverage gap.** The rogue group of the live store is still the 70790 capture at push 113715. The wowsims commit
`314d0e36` (2026-11-09) regenerated **paladin only** against a 70862 extraction at push 113823. DB2 shows no rogue numeric change
70790 to 70862, but pushes 113763 / 113772 / 113823 are not checked for rogue spells by any source I could reach (see §7, open question 6).
**[V]** `wowforevertalents.com/patch-notes` (updated 2026-11-07) states its 70862 read used the client cache "of 7 November (pushes up to 113763)" and
lists the rogue changes as only "Shank's two ranks are labelled".

---

## 3. The four items you already knew, checked

### 3.1 Shank

| Field | Value | Source |
|---|---|---|
| Rank 1 | id 1329283, level 24, 5 Energy, +15 Energy, 10 s cooldown, GCD 1 s | **[V]** Dev notes post 9, `https://us.forums.blizzard.com/en/wow/t/wow-forever-beta-development-notes-%E2%80%93-updated-november-2/2360696/9` (2026-11-03): "New Spell Added: Shank. Learned at level 24. 5 Energy cost. 10 second cooldown. Melee range. ... generating 15 Energy. ... Rank 2 learned at level 44 and generates 25 Energy." **[D]** store `Cooldowns["1329283"] = {CooldownMs 10000, CategoryCooldownMs 0, GCDMs 1000}`; same in wago 70790 and 70862 (`SpellCooldowns` ids 102426 and 102441). |
| Rank 2 | id 1329549, level 44, +25 Energy | same; `Rogue.lua:83` |
| Rank labels | "Rank 1" / "Rank 2" appear in 70862 DB2 and in the store at push 113715 | **[D]** §1 |
| Flash of Steel cooldown cut | **0.4 / 0.8 / 1.2 / 1.6 / 2.0 s** by rank, so Shank is 8 s at 5/5 | **[V]** dev notes post 9: "reduces its cooldown by 0.4/0.8/1.2/1.6/2.0 seconds." **[D]** The store's spell row (`1329284` effect 1) reads `-2500`; mythicsim says the curve, not the row, is right (`mythicsim .../rogue/prepare/rework.rs:56-60`, "the spell row's own -2500 is not what the curve and Wowhead's tooltip state"). |
| Venom | The talent (1329328) makes Shank cast aura **1310703**, a 6 s buff (+30% poison damage, +20% poison chance) | **[D]** store `Effects["1329328"]`, `Misc["1310703"].DurationMs = 6000`; **[V]** dev notes: "Venom is now a Passive that causes your Shank ability to increase your Poison damage by 30% and your chance to apply Poisons by 20% for 6 seconds." |

**[D]** `Rogue.lua:83` has Shank at `cooldownMs = 10000`. The cooldown engine learns the real value from the first plain out-of-combat read and keys by name
(`Forte_Cooldown/Core/Engine.lua:12-16, 125, 231-237`), so Flash of Steel talent points are covered with no data change.
**[D]** Old note in `forever-postlaunch-2026-11-07.md` §0.1 said `Rogue.lua` mapped Shank to 15617. That is fixed (regenerated 2026-11-07).

### 3.2 Death Mark

**[D]** Store `Cooldowns["1325758"] = {CooldownMs 10000, GCDMs 1000}`, `Misc.DurationMs 6000`, `Effects[0].PeriodMs 6000`, `Categories.DispelType 2` (Curse). Same four
rows in wago 70790 and 70862 (`SpellCooldowns` ids 101448, 102199-102201).
**[V]** Dev notes post 9: "New Talent: Death Mark. Active. 1 point talent in Row 7. 25 Energy cost. 20-yard range. 10 second cooldown. Curse. ... After 6 sec, the stored damage is dealt."
**[V]** `https://talentsforever.com/rogue/abilities` (client 70755): "Death Mark ... Learned at level 40, ranks to 60" (the four ranks 40/48/56/60 of the store). `wowforevertalents.com` (Nov 3 entry) instead says "learned at level 48" for the spell; the store and talentsforever agree on 40, so I use 40.
**[D]** What "values moved" means in our repo: `docs/research/data-diff-live-2026-11-07.md` §2.1 lists the four Death Mark ranks gaining full values (10 s cooldown, 6 s duration, 6 s period, GCD 1 s) when the store went 70707 to 70790. Nothing has moved since.
**[D]** `Rogue.lua:84` is consistent: `tickEvery = 6` on a 6 s duration is one payout tick at the end.

### 3.3 Gouge

**[D]** Rank rows 1776 / 1777 / 8629 / 11285 / 11286: `CategoryRecoveryTime 10000` and `Category 33` in wago 70790 and 70862 (`SpellCooldowns` ids 53182, 53312, 54062, 54772, 54770). The 70425 base pull
already carries `"CategoryCooldownMs":10000,"Category":33` for them. **[V]** `https://talentsforever.com/rogue/abilities` (client 70755 spellbook): Gouge rank 5 "45 Energy, Melee Range, Instant, 10 sec cooldown".
So the cooldown is **not new**; `Rogue.lua:66` has carried it since the first generation.

**[D]** What is new at 70862: spell **1324481** "Gouge" gains category 33, a 10 s category cooldown, spell level 60, a 45 Energy cost and a rank-aware description. At 70790 the row existed but its description simply pointed at rank 1 (`$@spelldesc1776`).
It has no `SpellClassOptions` row and no `SkillLineAbility` row.

**[I]** It is a rank-collapsing parent: a single "Gouge" that shows the highest known rank's text. Blizzard's own dev notes say "The Cooldown Manager does not yet support spell ranks" (post 9), so this may be groundwork for that. Unverified.

**[I] Risk for FX.** If `C_Spell.GetSpellInfo("Gouge").spellID` or a player `UNIT_SPELLCAST_SUCCEEDED` now reports 1324481:
- Cast to name resolution is fine. Everything is keyed by the localized name, and 1324481's name is `Gouge`.
- `isKnown("Gouge")` (`Forte_Cooldown/Module.lua`: IsPlayerSpell over `Locale.RankIDsForName` first, then `C_Spell.GetSpellInfo(name)` then `IsPlayerSpell`) is a **different story**.
  `RankIDsForName("Gouge")` holds only `{11286}`. A rogue below level 60 knows rank 1-4, so the id path fails. The fallback `IsPlayerSpell(<id the name resolves to>)` fails too if that id is 1324481 and a parent row is never "player spell".
  The result would be Gouge silently dropped below level 60, which is where almost every Forever character is today.
- **Probe, one line in game**: `/dump C_Spell.GetSpellInfo("Gouge").spellID, IsPlayerSpell(1324481), IsPlayerSpell(1777)` on a level 18-59 rogue.

### 3.4 Boot Knife combo points

**[V]** Hotfix line above. **[D]** The store row is 100%-scaled: `Effects["1329286"]` has `eff0 BasePoints 100` (the chance curve is per rank) and `eff1 BasePoints 2`; 70790 and 70862 SpellEffect rows are identical, so the **behaviour was always 2 combo points, only the tooltip said 1**.
**[D]** Corroborated by mythicsim `rework.rs:62-65`: "the spell's tooltip says one; its rows and Wowhead's talent text say two" (`BOOT_KNIFE_COMBO_POINTS = 2`).
**[I]** No FX timer reads combo points, so no effect.

---

## 4. Row-by-row audit of `Rogue.lua` against live evidence

### 4.1 Poisons and weapon-enchant timers

Facts (store 70790 @ 113715 unless noted):

| Item | Value | Source |
|---|---|---|
| Coat spell (e.g. 25351 Deadly Poison V) | 3 s cast, effect type 360 ("apply weapon enchant"), `BasePoints 1800`, `Misc 2630` | **[D]** `Effects["25351"]` |
| Enchant duration | 30 min (tooltips: "lasts for 30 minutes") | **[V]** `https://wowforevertalents.com/patch-notes` Nov 3 entry |
| Charges (server hotfix of Nov 3, not in Blizzard's notes) | Deadly V 240, Instant VI 250, Mind-numbing III 225, Wound IV 240 | **[V]** `https://wowforevertalents.com/patch-notes` ("The hotfixes also do things the notes never mentioned: ... rogue poisons hold more charges") and `https://talentsforever.com/rogue/abilities` (tooltip lines at 70755 plus the 2026-11-03 hotfix). The two sites disagree on the *old* counts (180/175/150/160 vs 120/115/100/105), so I give no "was" values. |
| Proc chances | Deadly 30%, Wound 30%, Crippling 30%, Instant 20%, Mind-numbing 20% | **[D]** store `EnchantChances`. **[D]** `/tmp/wowsims-forever/sim/rogue/poisons.go`: "Confirmed in game 9/30/2026" for Instant 20% |
| Attack-power shares | Deadly 0.009 (was 0.0045), Instant 0.01 (was 0.005) | **[V]** dev notes post 9 |
| Target debuff windows (the rows we track) | Deadly 12 s / 5 stacks / 3 s tick; Wound 15 s / 5 stacks; Crippling 12 s; Mind-numbing 10 / 12 / 14 s by rank | **[D]** `Rogue.lua:88-91, 108-109` and store `Misc` |
| Cooldown Manager | "Item enhancements (such as Windfury or rogue poisons) cannot be tracked" | **[V]** dev notes post 9, "Known Issues". No later post says this is fixed. |

**Finding A (weapon-enchant name law) [D].** `Forte_Cooldown/Core/Enchants.lua:66-67` and `:235` name a poison window by `C_Spell.GetSpellInfo(enchantID).name`, on the
stated premise "the classic enchant ids ARE spell ids". For poisons that premise looks false. **[D]** The coat spell's effect carries a **SpellItemEnchantment id** (`Effects["25351"][0].Misc = 2630`), and `EnchantChances` lists those ids per poison. **[UNVERIFIED]** whether `C_Item.GetWeaponEnchantInfo` returns that same id. If it does, reading it as a spell id gives the following (join of store `EnchantChances` against the base pull and store names):

| Poison (coat spell) | Enchant id | Id read as a *spell* resolves to |
|---|---|---|
| Deadly Poison V (25349/25351) | 2630 | "Dagger Strike IV (Disabled)" (store name; no base row) |
| Deadly Poison IV (11354) | 627 | Mind Control |
| Deadly Poison III (11353) | 626 | Seal of Might |
| Deadly Poison I / II (2818 / 2819) | 7 / 8 | Suicide / no name |
| Wound Poison IV / III / II / I (13224 / 13223 / 13222 / 13218) | 706 / 705 / 704 / 703 | Demon Armor / Shadow Bolt / Curse of Recklessness / Garrote |
| Crippling Poison II (11201) | 603 | Bane of Doom |
| Mind-numbing Poison III (11398) | 643, 8696 | Devotion Aura / Sprint |
| Instant Poison II / III (8685 / 8689) | 324 / 325 | Lightning Shield (both) |
| Instant Poison V / VI (11336 / 11337) | 624 / 625 | Inner Fire / Curse of Archimonde |
| Occult Poison II (1214170) | 7651 | Drain Life |
| Venomhide Poison (14795) | 1003 | Shadow Word: Befuddle |

**[I]** A coated weapon would show a window named e.g. "Demon Armor" instead of "Wound Poison". The fallback (`Forte_Items` `enchantProcs`, `row.itemId == enchantID`) holds only five enchant proc rows. This only matters if FX's `enchantID` is the enchantment id; the
catalog describes the field only as `enchantID number` (`Enchants.lua:20-26`). **[UNVERIFIED]** in game. Probe: coat a poison, `/dump C_Item.GetWeaponEnchantInfo(0)`; expect `enchantID = 2630` for Deadly V.
Fix is code, not JSON: emit a `poisonEnchant = { [enchantId] = name }` table from `EnchantChances` in the generator. Out of scope for this report.

**Finding B (do poison procs raise a cast event?) [UNVERIFIED].** The target-debuff rows (`Deadly Poison V` etc.) can only be cast-predicted if a proc raises a plain `UNIT_SPELLCAST_SUCCEEDED("player")`. No source I found says whether it does. Without it they fill only from out-of-combat aura reconcile. See open question 2.

**Finding C (lower-rank poison names have no row) [D].** A rogue below 60 uses a lower rank whose **name** differs: `Deadly Poison II/III/IV` (debuff rows 2819, 11353, 11354, 12 s), `Mind-numbing Poison II` (8692, 12 s). `Rogue.lua` tracks only `Deadly Poison` (rank 1), `Deadly Poison V`, `Mind-numbing Poison` (rank 1) and `III`. `Wound Poison` and `Crippling Poison` share one name across ranks, so they are fine.
Forever's leveling population is the current population. See the patch.

### 4.2 Slice and Dice, Rupture, Garrote, Kidney Shot, Crimson Tempest

| Row | `Rogue.lua` durationMs | Real window | Source |
|---|---|---|---|
| Slice and Dice (6774) | 6000 (line 101) | **9 / 12 / 15 / 18 / 21 s** for 1-5 combo points, then times the Improved Slice and Dice multiplier (store row 14165 is +15% at one rank; the sim scales it per rank) | **[D]** store `Descriptions["6774"]` ("1 point : ${9*$<mult>} seconds ... 5 points: ${21*$<mult>} seconds"); sim `slice_and_dice.go:18-22`: `(baseDuration + 3.0*CP) * talentModifier`, base = the row's 6 s |
| Rupture (11275) | 6000 (line 100) | **8 / 10 / 12 / 14 / 16 s** by combo point, **+ Blood Splatter** | **[D]** store `Descriptions["11275"]`; sim `rupture.go:22-26,38` (`baseTicks + CP`, 2 s tick) |
| Garrote (11290) | 18000 (line 98) | 18 s, **+ Blood Splatter** | **[D]** store `Misc.DurationMs 18000` |
| Kidney Shot (8643) | 1000 (line 68) | **2 / 3 / 4 / 5 / 6 s** (rank 2) | **[D]** store `Descriptions["8643"]` |
| Crimson Tempest (412096) | 2000 (line 107) | 4-12 s by combo point (n/a: not in the Forever spellbook, §5) | **[D]** store `Descriptions["412096"]` |
| Expose Armor (11198) | 30000 | 30 s fixed | **[D]**, **[V]** `https://talentsforever.com/rogue/abilities` ("exposes the target for 30 sec") |
| Death Mark (1325758) | 6000 | 6 s fixed | §3.2 |

**[D] Why this matters here.** `Forte_Timer/Core/Registry.lua:52,531-546` keeps **one learned duration per name**, written by any plain aura read. A rogue who casts Slice and Dice at 1 combo point and then at 5 will have the stored length flip with whichever plain read came last, and the prediction between reads uses `data.durationMs / 1000` = 6 s. The 6 s, 6 s and 1 s figures in the table are the **base** (zero-point) values of the rows, not the windows a player sees.
This is not JSON-fixable. It needs a combo-point input at cast time (see open question 5).

**Blood Splatter conflict.**
- **[V]** Dev notes post 9: "New Talent: Blood Splatter. Passive. 1 point talent in Row 3. Increases the duration of your Rupture ability by 6 seconds and your Garrote ability by 9 seconds." The Nov 3 entry of `https://wowforevertalents.com/patch-notes` carries the same text.
- **[D]** The **spell row** says otherwise in both 70790 and 70862 DB2 and in the store: `Effects["1329256"]` `eff0 BasePoints 4000`, `eff1 BasePoints 6000`; description "Rupture ... by ${$s1/1000} sec and ... Garrote ... by ${$s2/1000} sec" = **4 s / 6 s**.
- **[D]** mythicsim resolves it for 6 / 9: "Blood Splatter (1329256, one rank): Rupture lasts 6 sec longer and Garrote 9 sec, the TraitDefinition curve (6000 and 9000 ms)" (`rework.rs:67-70`), and "Wowhead's ... same numbers, except Blood Splatter's spell row, which reads 4 and 6 sec where its curve (and the calculator) read 6 and 9" (`rework.rs:8-9`).
- **[I]** 6 / 9 is the effective value (Blizzard notes plus the talent curve; the tooltip spell row is the outlier). The wowsims sim parses the spell row (`talents_assassination.go:94-101`), so its Blood Splatter Rupture/Garrote lengths are probably 2-3 s short. **[UNVERIFIED]** in game. Test: Rupture at 5 combo points with the talent should last 22 s if 6 s is real, 20 s if 4 s.

### 4.3 Defensive and utility cooldowns

All values **[D]** from store and wago DB2, identical in 70790 and 70862. "Match" = `Rogue.lua` agrees.

| Spell | Cooldown / window | Match | Notes |
|---|---|---|---|
| Evasion (5277) | 300 s (category 66), 15 s | yes | Row 5277 is the single rank. Set bonus row 26112 "Deathdealer Evasion Bonus" cuts 60 s (set row, **[I]**). |
| Vanish (1857) | 300 s (category 39) | yes | The 10 s stealth aura lives on separate rows 11327 / 11329 (Rank 1/2) and 457437 (10 s, -50% magic damage). `Rogue.lua:113` has no `durationMs`, so only the cooldown is drawn. **[I]** Pinned by the generator to the cooldown row. Elusiveness (13981) cuts the Vanish and Blind cooldowns (store effect -90000 ms). |
| Sprint (11305) | 300 s (category 44), 15 s | yes | Set row 23049 adds 3 s (**[I]**). Improved Sprint is a 100% proc that clears movement impairment (trigger 30918). |
| Blade Flurry (13877) | 120 s, 15 s | yes | **[V]** `https://talentsforever.com/rogue/abilities` ("2 min cooldown ... Lasts 15 sec"). It is a talent (Combat row 5). |
| Adrenaline Rush (13750) | 300 s, 15 s | yes | Talent; requires 1 point in Blade Flurry (**[V]** wowforevertalents Nov 3). |
| Cold Blood (14177) | 180 s | yes | Now also consumed by Mutilate crits (**[V]** dev notes). |
| Premeditation (14183) | 120 s, 20 s window | yes | No Stealth requirement any more. |
| Preparation (14185) | 600 s | yes | |
| Riposte (14251) | 6 s cooldown, 6 s disarm | yes | Talent. `cooldownCategory = 133` is the global-cooldown category, so `shares` logic could pair it with other category-133 rows. **[I]** Harmless; I found no other tracked rogue row in 133. |
| Kick (1769) | 10 s (category 88), 5 s lockout | yes | |
| Kidney Shot (8643) | 20 s (category 270) | cooldown yes; window **no** (§4.2) | |
| Gouge (11286) | 10 s (category 33), 4 s (+1.5 s Improved Gouge, row 13741) | yes | §3.3 |
| Blind (2094) | 300 s, 10 s | yes | Improved Blind (24469) -20 s; Elusiveness. |
| Sap (11297) | 45 s | yes | Does not break Stealth any more (**[V]** talentsforever). |
| Feint (11303) | 10 s (category 82) | yes | Rank 4; rank 5 is 25302. Name-keyed, fine. |
| Distract (1725) | 30 s (category 22), 10 s | yes | |
| Ghostly Strike (14278) | 20 s, 7 s | yes | Also raises aura 1329326 (7 s, next Ambush/Garrote needs no Stealth); same name, not a separate row. |
| Stealth (1787) | 10 s (category 38) | yes | Camouflage takes 2 / 4 / 6 s off (row 13975, three ranks). |
| Shadowstep (400029) | 30 s | n/a | Not in the Forever spellbook (§5). |

Talent cooldown changes (Flash of Steel -2 s, Camouflage, Elusiveness, Improved Blind) are absorbed by the Engine's learned durations; no data change is needed.

### 4.4 Forever-specific rogue spells (none of these exist in the 2012 module)

| Spell | Ids | Timing relevant to us | Tracked now? |
|---|---|---|---|
| Shank | 1329283 (R1, L24) / 1329549 (R2, L44) | 10 s cooldown (-0.4 s per Flash of Steel rank) | yes |
| Death Mark | 1316709 / 1325756 / 1325757 / 1325758 | 10 s cooldown, 6 s mark, 25 Energy | yes |
| Venom (aura) | 1310703 (aura, 6 s), 1329328 (talent) | 6 s buff after each Shank | **no** (patch adds it) |
| Poised | 1328825 (passive, L18), 1328826 (aura, no duration, -10 Energy) | none | no. `_deferred_H7` in `rogue.json`. |
| Quick Getaway | 1310728 (talent), 1329282 (aura, 3 s speed after Sap) | 3 s buff | no. Low value, optional. |
| Mutilate | 399956 / 1241582 / 1241584 | no cooldown, no duration | no, nothing to time |
| Blood Splatter, Boot Knife, Flash of Steel, Composure, Coup de Grace, Efficient Strikes | 1329256 / 1329286 / 1329284 / 1329265 / 14162 / 13732 | passive | no |

---

## 5. Tracked names that are not in Forever's rogue spellbook

**[V]** `https://talentsforever.com/rogue/abilities` (client 1.60.1.70755 spellbook, last checked 2026-11-03): "**42** spells in the Rogue spellbook ... Assassination (10), Combat (11), Subtlety (15), Poisons (6)" with the full list; **[V]** `wowforevertalents.com` 70862 entry lists no rogue spellbook change except the Shank labels.
Poisons tab = Crippling, Instant, Mind-numbing, Deadly, Wound, Blinding Powder. **[V]** Dev notes post 9: "Fixed an issue that made a Season of Discovery rune ability visible."

**[D]** `SkillLineAbility` at 70862 for the same ids: a normal taught spell has `AcquireMethod 0`. Rune-style rows have `AcquireMethod 3` or no row at all.

| Tracked name (`Rogue.lua` line) | In Forever spellbook? | `SkillLineAbility` 70862 | Verdict |
|---|---|---|---|
| Between the Eyes (69) | no | Combat, method 3 | rune leftover |
| Main Gauche (70) | no | Combat, method 3 | rune leftover |
| Rebuke (73) | no (and it is a Paladin spell) | skill line **Holy**, method 3 | wrong class |
| Redirect (74) | no | Subtlety, method 0 | **conflict**, see below |
| Shadowstep (77) | no | none | rune leftover |
| Tease (79) | no | none | rune leftover |
| Dismantle (81) | no | none (enchant grant 442206) | rune leftover |
| Blade Dance (86), Cheating Death (87) | no | none | rune leftover |
| Numbing Poison (91), Atrophic Poison (93), Sebacious Poison (94) | no (Poisons tab has 6 spells) | none | rune leftover |
| Venomhide Poison (95), Occult Poison II (96) | no | none | not in spellbook |
| Punch Harder (102), Glimpse of Madness (103), Resilient (105), Blood Corruption (106), Crimson Tempest (107), Envenom (110) | no | none | not in spellbook |
| Revealed Flaw (75) | no (aura of passive 28814, a set-style proc) | none | not a spell the player casts |
| Vigor (80) | passive talent only (row 21975 is an aura, `-1` duration) | none | inert row, no cooldown and no duration |

**[D]** Redirect has a `SkillLineAbility` row (Subtlety, method 0), but the spellbook lists 15 Subtlety spells and Redirect is not one of them. **[UNVERIFIED]** which is true on a live level 60 rogue. Leave it in.

**[D]** The practical cost of these is low: `Forte_Cooldown/Module.lua` gates tracking on `isKnown(name)`, and `IsPlayerSpell` "filters out name-squatters" (module comment, `Module.lua:76-79`). **[I]** This is cleanup and honest data, not a bug fix.
Removal needs `Forte_Cooldown/tests/test_tracked_set.lua:152` (`ROGUE = { "Dismantle", "Crimson Tempest", "Mind-numbing Poison", "Deadly Poison", "Envenom" }`) edited in the same change.

---

## 6. Evidence quality

- **Sample period.** Blizzard posts 2026-11-02 to 2026-11-09. Client files: wago.tools DB2 for builds 70755, 70790, 70862. Store: push 113715. All of it is from the four days since launch plus the beta notes.
- **Replication.**
  - Shank/Death Mark/Gouge cooldown and duration values: **independently replicated** across the wowsims store, wago.tools DB2 (two builds), the 70425 base pull, `talentsforever.com`, and Blizzard's dev notes. No source disagrees.
  - Blood Splatter 6 s / 9 s: **two sources agree** (Blizzard notes, TraitDefinition curve via mythicsim) against **one outlier** (the DB2 spell row, also what the store carries). No in-game measurement.
  - The enchant-id collision (Finding A): **derived from joins, not observed in game.**
- **Look-ahead / out-of-sample.** Not applicable (no model). The Nov 10 notes are unpublished; anything about them is a forecast.
- **Costs / execution.** Not applicable.
- **Reported vs replicated.** Rogue community reports about FX-relevant behaviour post-launch are thin. The only rogue addon report I found is `https://github.com/kaminaris/MaxDps-Rogue/issues/19` (2026-11-06, one author): level 13 rogue sees Sinister Strike = 1758, Eviscerate = 6760, Backstab = 2589, Slice and Dice = 5171; `C_Spell.GetSpellInfo(name).spellID` returns the rank the player knows; `C_Spell.IsSpellUsable` returns true for never-learned ids; aura reads return nil; `MaxDps.Power("energy")` is secret. **Single-source, unreplicated.** Consistent with FX's name-keyed design and with the existing `PlainOrNil` rules.
- **Fetch failures.** `https://www.wowhead.com/forever/spell=1325758/death-mark` returned HTTP 403 (not read). Wowhead values appear here only as quoted by mythicsim comments (`rework.rs:42-45`, dated 2026-11-04), marked as second-hand. Blizzard's forum search endpoint (`/search.json`) returned 404, so I used the `wow-forever.gg/official` mirror as an index.
- **Method caveat.** wago.tools "build" exports are the DB2 files. The store's rogue rows carry the Nov 6 text hotfix that the 70790 DB2 lacks (Shank "Rank 2", "2 Combo Points"), so the store does include a hotfix layer. Numeric rogue fields agree between store and DB2 everywhere I compared, except Blood Splatter, where both carry the 4 s / 6 s spell row and neither carries the 6 s / 9 s curve. **[I]** that is as far as I can say.

---

## 7. Implications for our setup

1. **No data regeneration is needed for the rogue today.** The 70790 overlay in `tools/overrides_70790.json` still matches the current store row for row on every rogue id it carries (342 rogue-family ids compared; 0 value diffs on the 129 present in the overlay; 213 are simply not in the overlay).
2. **The one thing to watch on the next pull of `/tmp/wowsims-forever`** is the Gouge parent 1324481 (§3.3). It carries no family, so the generator's family-scoped law ignores it, and the existing in-family ranks win. I expect no pick change, but I did not run the generator.
3. **Fix before the next owner session:** run the one-line probes in §3.3 and §4.1 on a rogue below level 60. They decide whether Gouge is silently untracked and whether poison windows are named correctly.
4. **Design gap:** combo-point finishers (Slice and Dice, Rupture, Kidney Shot) need a combo-point value at cast time to draw the right length. Without it the 6 s / 6 s / 1 s base values are shown for windows that are really 9-21 s, 8-22 s and 2-6 s. Per-name `learned` (`Registry.lua:52`) cannot hold a combo-dependent length.
5. **Cooldown talents are covered by the learned-duration law** (Flash of Steel, Camouflage, Elusiveness). No spell-list change.
6. **Nothing rogue-specific for the Nov 10 hotfix** is announced. Re-check the Blizzard hotfix page and forum thread after the 10th. The page URL above is the one that gets updated.

### Open questions

1. Does `C_Spell.GetSpellInfo("Gouge").spellID` (or `UNIT_SPELLCAST_SUCCEEDED`) return **1324481** on 70862, and does `isKnown("Gouge")` stay true for a level 18-59 rogue?
2. Does a poison proc raise a plain `UNIT_SPELLCAST_SUCCEEDED("player", ..., spellID)`? If not, poison debuff rows are reconcile-only.
3. What `enchantID` does `C_Item.GetWeaponEnchantInfo` return for a coated poison? Expected 2630 for Deadly Poison V; if it is a spell id, Finding A is moot.
4. Blood Splatter: is Rupture at 5 combo points 22 s (6 s) or 20 s (4 s)? Garrote 27 s or 24 s?
5. Are combo points readable (plain) at `UNIT_SPELLCAST_SENT` in combat? Power is reported secret in combat (`gryphonFrames` PR #10 in `forever-postlaunch-2026-11-07.md` §2.2), so probably not.
6. Rogue rows at pushes 113763 / 113772 / 113823 are unchecked. The owner can re-run `tools/extract_store.py` against the 70862 extraction (the one used by wowsims commit `314d0e36`) to refresh the rogue group.
7. Redirect: does a live level 60 rogue have it (§5)?

---

## 8. Proposed patch

Target: `tools/spell_lists/rogue.json`. Names only; ids appear in `reason` strings as evidence. Run `python3 tools/gen_spell_data.py rogue` afterwards (owner step).
Nothing below changes a value. Values come from the store; the patch only decides which names the generator looks up.

**Add (value for leveling rogues):**

```json
{
  "buffs": {
    "add": [
      "Deadly Poison II",
      "Deadly Poison III",
      "Deadly Poison IV",
      "Mind-numbing Poison II",
      "Venom"
    ]
  },
  "_pins": {
    "Venom": {
      "id": 1310703,
      "reason": "two family-8 rows share the name: 1329328 is the level-30 passive talent (no duration), 1310703 is the 6 s aura Shank casts with the talent; the rank law prefers the higher level, so it would pick the passive (store Misc['1310703'].DurationMs = 6000, Misc['1329328'].DurationMs = 0)"
    }
  }
}
```

| Line | Confidence | One-line reason |
|---|---|---|
| add `Deadly Poison II` / `III` / `IV` | **high** | Debuff rows 2819 / 11353 / 11354 exist in the store with 12 s duration and family 8 (`Names` / `Misc`). `Rogue.lua` has only `Deadly Poison` (rank 1) and `V`, so a level 38-59 rogue gets no timer. |
| add `Mind-numbing Poison II` | **high** | Row 8692 is 12 s (rank 1 is 10 s, rank 3 is 14 s); only 1 and 3 are tracked. |
| add `Venom` | **med** | Aura 1310703 is a 6 s +30% poison damage buff after Shank. It is a real, always-on rhythm for Assassination. |
| `_pins.Venom` → 1310703 | **med** | Needed because both rows are in family 8 and carry no cooldown; I did not run the generator, so the pick is **[I]**. |
| **no pin** for Shank (1329549), Death Mark (1325758), Gouge (11286) | **high** | The generator already picks these; checked against `Rogue.lua:66,83,84` and the store. |

**Optional prune** (rune leftovers; cleanup only, see §5). Mark each as a single `remove`, then update `Forte_Cooldown/tests/test_tracked_set.lua:152` so the test lists names still tracked:

```json
{
  "cooldowns": {
    "remove": ["Between the Eyes", "Main Gauche", "Rebuke", "Shadowstep", "Tease", "Dismantle"]
  },
  "buffs": {
    "remove": ["Blade Dance", "Cheating Death", "Numbing Poison", "Atrophic Poison",
               "Sebacious Poison", "Venomhide Poison", "Occult Poison II", "Punch Harder",
               "Glimpse of Madness", "Resilient", "Blood Corruption", "Crimson Tempest", "Envenom"]
  }
}
```

| Line | Confidence | One-line reason |
|---|---|---|
| remove `Between the Eyes`, `Main Gauche` | **med** | Not in the 42-spell Forever rogue spellbook (talentsforever, 70755); `SkillLineAbility` method 3 (rune style). |
| remove `Rebuke` | **med** | `SkillLineAbility` skill line is Holy (Paladin) at 70862; it is also absent from the rogue spellbook. Belongs to `paladin.json` if anywhere. |
| remove `Shadowstep`, `Tease`, `Dismantle`, `Blade Dance`, `Cheating Death`, `Punch Harder`, `Glimpse of Madness`, `Resilient`, `Blood Corruption`, `Envenom` | **med** | No `SkillLineAbility` row at 70862 and not in the spellbook. |
| remove `Crimson Tempest` | **med** | Same. Would also drop its feeds in `Rogue.lua:48` and the colour rule `Registry.lua:261`, which are harmless to leave. |
| remove `Numbing Poison`, `Atrophic Poison`, `Sebacious Poison`, `Venomhide Poison`, `Occult Poison II` | **low** | Not in the Poisons tab, but I did not check whether Forever items still teach these coats. Probe before removing. |
| **keep** `Redirect`, `Revealed Flaw`, `Vigor` | **low** (not removing) | Conflicting or inert evidence (§5). |

**Cannot be fixed by JSON** (left as findings, §4.1 / §4.2): combo-point window lengths; Blood Splatter extra seconds; the poison enchant-id name resolution; 1324481 id resolution.

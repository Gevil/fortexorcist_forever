# Warrior: tracked data vs the live game, 2026-11-09 (agent RsrchWarrior)

Scope: `tools/spell_lists/warrior.json` and the generated `addon/Forte_Warrior/Data/Warrior.lua` (68 rows) against the live
spell store, wowsims/gamedata (per-hotfix spell cards), wowsims/forever and mythicsim, and Blizzard's notes. Read-only
research. The only file written is this one. Scratch extracts live in `/tmp` (`/tmp/warrior_store.tsv`, `/tmp/warrior_cards.tsv`).

**Labels.** **[V]** = verified in a fetched page or file (source named). **[D]** = derived: I computed it from fetched data and
state the method. **[I]** = inference. **[UNVERIFIED]** = could not be checked from here. Nothing was probed on the live client.

## 0. Answer first

1. **The `Charge` row is the wrong spell. It is the hunter boar's pet Charge, not the warrior's.** `Warrior.lua:70` carries id
   **27685**, 25 s cooldown, 4 s duration, GCD 1.5 s. The store's own text for 27685 says "adds $s2 melee attack power to the **boar's**
   next attack", it costs focus, it has no class family and its max level is 66 (above the 60 cap). The warrior's Charge is **11578** (Rank 3, L46, 15 s,
   category 44, **GCD 0**, 1 s stun via 7922). Under a talent it is 1240289 (Vanguard copy). The sim uses 11578. Fix: pin 11578. A unit
   test currently asserts the wrong value (§2.1).
2. **`Rend` is not tracked at all.** It is the warrior's main target DoT: 21 s, 3 s ticks, 7 ticks at Rank 7 (11574). The Forever
   talent Bloodthrill needs Rend on the target. The bar and timer registry already have a `^Rend` colour band (`Registry.lua:252`).
   Add `Rend` to `buffs` (§3.1).
3. **`Reckless Swings` (the open H7 item) now resolves and is a complete row:** 1329555, cooldown 15 s, buff 8 s, 4 charges, GCD 1 s,
   25% of base health. Move it from `_deferred_H7` to `cooldowns`. Its follow-on buff **Gore Drinker** (1323969, 8 s, 3 charges) is not
   tracked either (§3.1).
4. **Everything else we ship matches the live data.** I compared cooldown, duration and GCD of 63 rows against the latest gamedata
   cards (export of 2026-11-09 19:01Z, build 70862). All equal. The only 3 non-racial rows with no card are `Charge` 27685,
   `Cripple` 89 and `Enrage` 440483. Slam is 15 s (§2.5).
5. **`Slam` is keyed to the talent-override copy (1310200), not the spellbook rank (11605).** Same values. It can break the
   id-based "is known" gate on non-English clients, and on enUS for warriors without Improved Slam [I] (§2.2).
6. **Static cooldowns ignore talents and the Forever T1 set.** Improved Slam (−5 s), Improved Whirlwind (−2 s), Improved Intercept
   (−10 s), Improved Disarm (−20 s), T1 3P Intimidating Shout (−30 s), T1 5P Recklessness (−30 s), T1 5P Shield Wall (−30 s). The engine
   learns the real number from the first plain read, so only the first predicted bar is off (§2.3).
7. **About 27 non-racial rows are not in the warrior's spellbook or trigger closure.** Some are provably not warrior spells (§4.1).
   About 20 are Season-of-Discovery rune and set rows. Whether a player can learn those on Forever is **[UNVERIFIED]**; the evidence
   points to no (§4.2). `Intervene` has no spell body at all (§4.3).
8. **Blizzard notes touching warriors, Nov 6–10: one line, and it is tooltip-only.** Nov 6: "Fixed the tooltip for Reckless Swings to
   mention that it activates Gore Drinker." The Nov 10 plan (Hunter pets, Voidwalker, Affliction, Enhancement) has no warrior item.
   The post-launch gamedata hotfixes changed warrior damage ranges only (§5).

## 1. Sources and pins

| Source | Pin | Used for |
|---|---|---|
| Live spell store `wowsims/forever` `assets/db_inputs/spell_store_inputs.json` (checkout `/tmp/wowsims-forever`) | `9ca4d977c9d4cfa60522aa2d69eeb4412608a567` (2026-11-09). Warrior group still `1.60.1.70790` @ push `113715` | ids, ranks, cooldown/duration/GCD/ticks/charges, talents (53 warrior trait nodes), spellbook roots (193 ids) |
| wowsims/gamedata (checkout `/tmp/gamedata`) | `693ee0312e84de39221a9765f9de9633eb8f1994`, 2026-11-09T19:01:57Z, `state.json`: build 70862, 5313 pushes | latest per-hotfix spell cards, `git show` diffs per commit |
| wowsims sim `sim/warrior/*.go`, `sim/siml/names.json` | same `9ca4d977` | what the sim registers (trainer ids, book ranks, override aura ids) |
| mythicsim-forever-engine | `ff6a43cf451af0ad9884f16e21300c30468cd93d` (2026-11-10 AEDT) | `src/classes/warrior/**` behaviour, `docs/levels-logs-2026-11-09.md` |
| Our data | `Warrior.lua` generated 2026-11-07 from mythicsim `b998bbab` + overlay `138964222…` (70790) | the thing being audited |
| Blizzard | forum JSON of topics 2403040 and 2404092; forum search `Kaivax after:2026-11-07` | §5 |

The store clone is **not** newer than our overlay for warriors (both 70790 @ 113715). The newer truth is gamedata (70862 plus
daily hotfix pushes). I therefore compared our rows to the **gamedata cards**, not only to the store.

Method for the comparison **[D]**: parse every card in `spells/warrior/{arms,fury,protection,other}.txt` (492 cards: id, name,
cooldown, duration, GCD, cost, stance). Parse each `[id] = {…}` row of `Warrior.lua` and compare `cooldownMs`, `durationMs`, `gcdMs`.

## 2. Tracked rows that are wrong, drifted, or fragile

### 2.1 Wrong rows (fix)

| Row (`Warrior.lua`) | We ship | Live truth | Evidence | Fix |
|---|---|---|---|---|
| `Charge` line 70, id 27685 | cd 25 s, dur 4 s, GCD 1.5 s, cat 44, "Rank 6" | Warrior Charge ids 100 / 6178 / **11578**, each cd 15 s, cat 44, **GCD 0**, family 4. Stun is 7922, 1 s. Vanguard copies 1240287/8/9 (same values) | **[V]** store row 27685: `Description` "Charges an enemy, immobilizes it for $7922d, and adds $s2 melee attack power to the boar's next attack"; `Powers` type 2 (focus), cost 35; `Levels` 60/60/66; no `ClassOptions`. **[V]** 11578: `Powers` type 1 cost 0, `GCDMs` 0, family 4. **[V]** `sim/warrior/charge.go:9` `spellData.Charge.ByID(11578)`; `sim/warrior/spell_data_auto_gen.go` `Charge: Ranked(100, 6178, 11578)`. **[V]** gamedata card 1240289 "cooldown 15 s (category) … stance Battle, Defensive". **[D]** 27685 is in no warrior card, in none of the 193 spellbook roots, and in no trigger closure | `_pins` `"Charge": 11578` (§8). Update the unit test below |
| Test `Forte_Cooldown/tests/test_70707_overlay.lua:68-74` | asserts `27685`, `"Rank 6"`, `25000`, category 44 | n/a | **[V]** the test comment says "Charge: the pick moved off the book-rank ladder to Rank VI 27685 … the store's 25 s charge-stun cooldown". `docs/research/data-diff-70707.md:158,283` adopted it because it was a family-less "Rank 6 above the 60 cap" row | assert 11578 / 15000 / 44. `data-diff-70707.md §2.4` Charge conclusion is superseded. The same pattern, **Druid Cower 16697 "Rank 6" (L65, cd 5 s)**, is outside my class and is worth the Druid researcher's check |
| `Enrage` line 123, id 440483 | dur 12 s, cat 21, no cooldown | The Fury talent proc buff is **12880** (family 4, 12 s, cat 21). 440483 is the Fresh Meat rune's own "Enrage" buff (family none) | **[V]** store 12880 family 4, dur 12000. **[V]** `sim/siml/names.json` warrior aura `enrage: 12880`. **[V]** store 440484 "Fresh Meat … cause you to deal $440483s1% increased Physical damage for $440483d" | same numbers, so no visible effect today. Pin 12880 so the id points at the talent |
| `Cripple` line 106, id 89 | dur 20 s, cd 30 s, GCD 1.5 s ("Rank 1", L60) | not a warrior spell | **[V]** store 89 description: "Cripples the target, reducing movement speed … increasing time between melee attacks … ranged attacks". No `ClassOptions`. Not among the 193 warrior roots and in no gamedata card. The related 18381 ("Reduces target enemy's attack power") sits in `other.txt` (the leftover/NPC file) | remove from `buffs` (§4.1). Test `test_70707_overlay.lua` has a `Cripple -> 89` pin that goes with it |

### 2.2 Slam: id choice and the talent copy

- **[V]** The base Slam ladder (the spellbook) is 1240193 / 1464 / 8820 / 11604 / **11605** (R1–R5, levels 20/30/38/46/54), 1.5 s cast,
  GCD 1.5 s, **15 s category cooldown (cat 2412)**. The sim registers `slam: 11605` and the generated ladder
  `Slam: Ranked(1240193, 1464, 8820, 11604, 11605)`.
- **[V]** `Improved Slam` (12862, gamedata `arms.txt` card): cast time −0.5 s, global cooldown −0.5 s, **cooldown −5 s** (rank 2;
  dev notes post 9: "Improved Slam 2.5/5 s"), and it **overrides the action-bar spell** with 1310196–1310200 (effects 4–8: base
  1310196→misc 1240193 … base 1310200→misc 11605). So 1310196–1310200 are the talented copies, not new ranks.
- **We key Slam to 1310200** (`Warrior.lua:94`). The generator's rank law took the highest id of the Rank 5 rows. 1310200 is not in the
  warrior's spellbook roots; 11605 is. `isKnown(name)` tests `IsPlayerSpell` on the data row's own ids first, and on a
  non-English client `readKey` uses the id as well (`Forte_Cooldown/Module.lua:79-96` `isKnown`, `:125-150` `readKey`). **[I]** A warrior without Improved Slam knows 11605,
  not 1310200, so on a non-English client the Slam bar may be dropped. Whether `IsPlayerSpell(1310200)` is true for an
  Improved-Slam warrior is **[UNVERIFIED]**.
- Fix: pin `Slam` to **11605** (identical values). Probe first: `/run print(IsPlayerSpell(11605), IsPlayerSpell(1310200))` on a
  warrior with and without Improved Slam.
- Same pattern for **Vanguard** (1310317): Charge becomes 1240289/8/7 on the bar **[V]** (gamedata `protection.txt` Vanguard card,
  effects 1–3). The pin to 11578 covers it.

### 2.3 Cooldowns and durations that talents or the T1 set change (static data is the base)

`Engine:BestDuration` prefers a learned duration over `baseDuration`, and `OnRead` learns from the first plain read
(`Engine.lua:231-236` `BestDuration`, `:278-303` `OnRead`, learned at `:302`). **[D]** So these only affect the first predicted cast before a readable cooldown exists.

| Row | Data (base, correct) | Modifier **[V]** (store/gamedata) | Real cooldown |
|---|---|---|---|
| Slam | 15 s | Improved Slam, effect 3 `−5000` ms, plus cast and GCD −0.5 s | 10 s at 2/2; 12.5 s at 1/2 **[I]** from the "2.5/5 s" dev note |
| Whirlwind | 10 s | Improved Whirlwind (1310315): effect 0 `−2000` ms, +15/30% damage to the closest target | 8 s at 2/2 |
| Intercept | 30 s | Improved Intercept (20504): `−10000` ms | 20 s at 2/2 |
| Disarm | 60 s | Improved Disarm (12313): `−20000` ms | 40 s at 3/3 |
| Intimidating Shout | 180 s | Forever T1 Arms/Fury 3P (1301069): `−30000` ms | 150 s with the set |
| Recklessness | 1800 s | Forever T1 Arms/Fury 5P (1301721): `−30000` ms | 1770 s with the set |
| Shield Wall | 900 s | Forever T1 Protection 5P (1301722): `−30000` ms. Improved Shield Wall (12312) also cuts it; the magnitude in the store text is odd, so **[UNVERIFIED]** | — |
| Pummel duration | 4 s | Improved Pummel (12288/12707): +1/+2 s | 5–6 s |

### 2.4 Rows whose real duration lives on a same-named companion aura

| Row | We ship | Companion | Effect on the player |
|---|---|---|---|
| `Bloodrage` (`Warrior.lua:67`, 2687) | cd 60 s, **no duration** | 29131 "Bloodrage", family 4, **10 s**, 1 s tick (10 rage ticks) **[V]** | no 10 s bar. It matters because Gore Drinker and "Enrage" gating key off the Bloodrage window |
| `Last Stand` (`:77`, 12975) | cd 180 s, **no duration** | 12976 "Last Stand", **20 s**, family none **[V]** | no 20 s bar. The 2012 reference tracked 12976 for 20 s |

The generator's companion rule only fires for bare rows (`gen_spell_data.py:91-107`). A cast row that carries a cooldown wins, so
the aura duration is dropped. **[I]** Needs a generator feature (a per-name duration source) or a second row; it is not a spell-list
edit.

### 2.5 Rows verified equal to the live cards

All other rows match. This includes the user's named items:

- **Slam**: 15 s (was 18), cast 1.5 s, GCD 1.5 s, cat 2412 **[V]** store 1310200/11605 and gamedata cards. The post-9 dev-notes row retired correctly.
- **Stances**: Battle 2457 (L1), Defensive 71 (L10), Berserker 2458 (L30): permanent, 1 s shared category 47, GCD 0. Stance rage retention
  is Tactical Mastery (1310185) with Improved Tactical Mastery; no timers.
- **Shield Block 2565**: cd 5 s, dur 7 s, **2 charges**, Defensive Stance only. **Shield Wall 871**: 12 s / 900 s. **Berserker Rage 18499**: 10 s / 30 s.
  **Bloodrage 2687**: cd 60 s, costs 20% of base health. **Mortal Strike / Bloodthirst / Shield Slam**: 6 s, shared category 971. **Revenge /
  Overpower**: 5 s, shared category 65. **Pummel / Shield Bash**: shared category 88, 10 s / 12 s. **Thunder Clap R6 11581**: 6 s cd, 30 s debuff. **Demoralizing
  Shout R5 11556**: 45 s. **Sunder Armor R5 11597**: 30 s, 5 stacks. **Hamstring R3 7373**: 15 s. **Taunt 355**: cd 8 s, 3 s. **Mocking Blow R5**: 6 s / 120 s.
  **Sweeping Strikes 12292**: 20 s / 30 s. **Spearing Strike 1310222** (Forever talent): cd 20 s, Battle Stance. **Victory Rush 402927**: cd 30 s, window 402975 20 s.
  **Deep Wound 412609**: 12 s, 3 s ticks.
- **Reckless Swings**: see §3.1 (it is not shipped yet).
- Cards are the 2026-11-09 19:01Z export. Cast time was compared only for Slam (card `cast 1.5 s`).

### 2.6 Rank law and book ranks

- **[V]** `sim/core/spelldata/book_ranks.go`: Heroic Strike IX (25286), Battle Shout VII (25289) and Revenge VI (25288) are **book ranks** taught by
  Manuals, not by the trainer. Trainer tops are Battle Shout R6 **11551**, Revenge R5 **11601**, Heroic Strike R8 11567 (`battle_shout.go:15-17`,
  `revenge.go:10-12`). Our overlay moved Battle Shout 25289→11551 and Revenge 25288→11601 (`Warrior.lua` header lines 8-14). That is correct.
- **[I]** A warrior with Manual of Battle Shout VII casts 25289. Cast events resolve by name, so the row still lands. The 180 s duration is the same.
- **Charge ranks**: the three trainer ranks are 100 (L4), 6178 (L26), 11578 (L46). There is no Rank 4–6 for warriors. Rank 6 only exists on the pet row.

## 3. Missing: spells, auras and procs a warrior would want

Rule used **[D]**: spellbook roots (193 ids) plus the talents and trigger auras the sim registers, with a cooldown ≥ 3 s or a positive duration,
minus what we track by name. This yields exactly three spellbook spells: **Rend, Long Daze, Reckless Swings**. The aura/trigger rows below come from
reading the sim and the cards.

### 3.1 Add (ranked)

| # | Spell | id (pick) | Data | Why / how | Conf. |
|---|---|---|---|---|---|
| 1 | **Rend** (target DoT) | 11574 (R7); R1–R6: 772, 6546, 6547, 6548, 11572, 11573 | 21 s (R1 9, R2 12, R3 15, R4 18, R5–R7 21), tick 3 s, 7 ticks, GCD 1.5 s, 10 rage, **Battle/Defensive only** | The warrior bleed. Bloodthrill (Arms talent 1289682) gives main-hand hits on a Rend-afflicted target a 15% chance to open Overpower. Registry band exists (`Registry.lua:252`). Cast-predict is the only way (no aura reads in combat) | high |
| 2 | **Reckless Swings** | 1329555 (proc 1329554) | cd 15 s, dur 8 s, 4 charges, GCD 1 s, cost 25% of base health; each landed white swing gives 5 rage and spends a charge | In `_deferred_H7` since wave I-2b as "net-new, not in Names". The store now has the row (L0, root). Charges are `ProcCharges`, which the generator's `maxStack` feed does not read (§3.3) | high |
| 3 | **Gore Drinker** (self buff) | 1323969 (talent 1323967, trigger 1323968) | dur 8 s, 3 charges, restores a % of max health per melee hit | Triggered by the casts of Berserker Rage, Bloodrage, Death Wish, **Reckless Swings** and Bloodthirst (and the Enrage proc). Five of those are our own casts, so cast-predict works. The Nov 6 note fixed its tooltip | med |
| 4 | **Blood Fury** (Orc racial) | 20572 | cd 120 s (dev notes post 9: "Orc Blood Fury cd 2 min (was 3)") | The store has no row; the dev-notes layer already carries the value, "inert by design" (`overrides_devnotes_2026-11-03.json` row 20572). No spell list names it. Add to `racials` | med |
| 5 | **Eureka!** (Gnome racial, warrior copy) | 1259813 | cd 120 s, dur 8 s: "non-periodic damaging abilities have their Rage cost reduced … and deal more damage" | **[V]** store has a full row per class (1259812 fam 8, **1259813 fam 4**, 1259817, 1259821, 1259823). None is tracked for any class | med |
| 6 | **Bloodrage** window / **Last Stand** window | 29131 / 12976 | 10 s (1 s tick) / 20 s | See §2.4: needs a generator feature | med |
| 7 | **Troll Berserking duration** | 20554 | 15 s per dev notes ("Troll Berserking 15 s") | Our row has a cooldown only | low |

### 3.2 Procs and windows that matter but cannot be tracked reliably in combat

No combat log and no in-combat aura reads (`AGENTS.md`). These are listed so nobody re-researches them:

| Window | id | Data | Note |
|---|---|---|---|
| **Overpower** usable | 1282733 (opened by dodge via Offensive State 1282735, or by Bloodthrill 1289682 at 15%) | 5 s; marker aura 1289681 "Overpower recently activated by Bloodthrill" 5 s | the Forever analogue of the "Stormstrike-like" rows: no extra spell, only a proc window |
| **Revenge** usable | 5302 Defensive State | 5 s, 1 charge, after block/dodge/parry | |
| Flurry | 12966 | 15 s, 3 charges (on crit) | proc |
| Blood Craze | 16488 | 6 s (after being crit) | proc |
| Enrage | 12880 | 12 s (after being crit) | proc, already a row (§2.1) |
| Improved Hamstring root | 23694 | 5 s | proc debuff |
| Charge Stun 7922 | | 1 s | cast-predictable but sub-GCD, low value |
| Intercept Stun 20615 | | 3 s | cast-predictable |
| Improved Shield Bash silence 18498 / Long Daze 12705 (Improved Pummel) | | 3 s / 6 s | proc debuffs |

**[I]** Whether `C_Spell.IsSpellUsable` is readable in combat for Overpower/Revenge is **[UNVERIFIED]**. It is the only candidate to show "usable" without auras.

### 3.3 Feed gap: charges

`maxStack` is fed from `AuraOptions.MaxStack` only (`Warrior.lua` header, feed columns). Charge-style auras use `ProcCharges`.
**[V]** store: Shield Block 2565 = 2, Sweeping Strikes 12292 = 5, Reckless Swings 1329555 = 4, Gore Drinker 1323969 = 3, Flurry 12966 = 3.
None can show a charge badge. The generator has no column for it (`docs/research/data-diff-70707.md:69-73` says charges are not in the store at all;
`ProcCharges` is, so this is a one-column add). Runtime `DetectCharges` covers true recharge spells only.

### 3.4 What the user asked for, resolved

| Ask | Warrior answer |
|---|---|
| Rend, Sunder, Demo Shout, Thunder Clap, Hamstring, Taunt | Sunder (5 stacks, 30 s), Demo Shout (45 s), Thunder Clap (30 s), Hamstring (15 s), Taunt (3 s), Mocking Blow (6 s), Piercing Howl (6 s), Concussion Blow (5 s), Challenging Shout (6 s), Intimidating Shout (8 s), Disarm (10 s), Mortal Strike (10 s) **already tracked**. **Rend is the one missing** |
| Expose Armor | **Not a warrior spell.** `sim/siml/names.json` carries `expose_armor: 11198` as a target aura only (rogue). Warriors apply Sunder Armor |
| Stormstrike-like rows | None exist for warriors. The Forever-original warrior rows are Spearing Strike (tracked), Vanguard (passive), Bloodthrill (proc window), Reckless Swings and Gore Drinker (§3.1), Improved Whirlwind (renamed from "Raging Blows", id 1310315) |
| Reckless Swings | §3.1 row 2 |
| Charge ranks | §2.1 |
| Shield / Bloodrage / Berserker | §2.4, §2.5. Berserker Rage 10 s / 30 s is right. Improved Berserker Rage gives instant rage. Bloodrage costs 20% of base health |

## 4. Stale, non-warrior, or unverifiable rows

### 4.1 Provably not warrior class spells (high confidence, recommend removal)

**[V]** gamedata README: `other.txt` = "set bonuses, item procs, NPC and leftover spells". **[V]** Each of these is in `other.txt` and not in the
193 warrior roots.

| Row (`Warrior.lua`) | id | What it is |
|---|---|---|
| Cripple (106) | 89 | NPC/leftover Cripple (and 18381); see §2.1 |
| Spell Vulnerability (117) | 23605 | "Spell damage taken by target increased by $s1% for $d", 5 s. A weapon-proc debuff (the Warlock axe family) **[I]** |
| Howling Blade (112) | 13490 | "Reduces target's attack power by $s1 for $d", 30 s; a weapon-proc debuff **[I]** |
| Cheat Death (105) | 28846 | "Increases healing received by up to $s1", 5 s; an item/set proc **[I]** |
| Retaliate (114) | 468071 | no description; 468xxx is the SoD tier range **[I]** |
| Deep Wounds (124) | 12834 | the **passive talent** row: no duration, no cooldown, so the registry's `durationMs > 0` gate drops it. It never draws. The real timer is Deep Wound 412609 |

### 4.2 Season-of-Discovery rune and set rows: **[UNVERIFIED]** whether learnable on Forever

Rows not in the warrior roots and not in a trigger closure: Enraged Regeneration 402913, Meathook 403228, Raging Blow 402911, Rallying Cry 426490,
Rampage 426940, Shockwave 440488, Battle/Berserker/Defensive Forecast 457816/7/4, Echoes of Defensive Stance 457699, Blood Surge 413399,
Gladiator's Cunning 1234067, Single-Minded Fury 430472, Slammin' 1234005, Sudden Death 440114, Sword and Board 426979, Taste for Blood 426969, Gladiator
Stance 412513, Commanding Shout 403215.

Evidence **against** being live:
- **[V]** wowsims `docs/spell_data/regenerating.md:28-33`: "A Season of Discovery rune ability is left out … with no trainer or level row
  outside the rune lines and no talent reaching it … A rune ability that a trainer also teaches, such as Victory Rush … stays."
- **[V]** `sim/siml/names.json` warrior spell/aura sets (119 / 93 entries) contain none of them. `Victory Rush` and `Victorious` are in.
- **[V]** The vendored API catalog lists `C_Engraving` as flavour **classic** only, not forever
  (`docs/api/wow-addon-api-agents/skills/wow-api-index/references/NAMESPACE-LOOKUP.md:99`). **[D]** The 29 vendored `forever.json` files contain 0 "Engraving" symbols.
- **[V]** The Forever T1 set is the `1.60.0 - Item - Tier 1` family (1300968…1301722). The forecast/echo rows come from `S03 - Item - T1 -`, a SoD set.
- **[V]** mythicsim's warrior spell modules (`src/classes/warrior/spells/*.rs`, 31 files) contain none of them; its Forever fury tree is `src/classes/warrior/prepare/talent_ranks.rs` ("Raging Blows gone").

Evidence **for**: gamedata places Meathook, Shockwave (arms.txt), Raging Blow, Enraged Regeneration (fury.txt) and Rallying Cry (protection.txt) in spec
files, and spec files are "the spec skill line that teaches it". Engrave spells exist as cards (427081 "Engrave Bracers - Rampage", 427078 "Engrave Helm -
Vigilance"). Client data carrying a row is not the same as a player being able to learn it.

These rows are harmless dead weight if unlearned: `isKnown(name)` fails and nothing draws. Do not delete on this evidence alone. **Probe on a live
warrior:** `/run for _,id in ipairs{402911,403228,426940,440488,402913,426490,412513,403215} do print(id, IsPlayerSpell(id)) end`. Park the names
until that answers (§8).

### 4.3 Dead by construction

- **Intervene 403437 (`Warrior.lua:134`, `utility`)**: **[V]** the card is only "Gain the Intervene ability: `$@spellicon403338`" and an action-bar override
  to base 403338. **There is no spell 403338** in the store or any card, so there is nothing to cast or time. The Forever T1 Protection 3P (1301071)
  still names Intervene, so **[I]** it was planned and cut.
- **Vigilance 426972** (still in `_deferred_H7`): a rune row in `other.txt` with a 30 min duration. Same status as §4.2.

### 4.4 Renames and removals in Forever (warrior)

No warrior spell was renamed or removed in the post-launch hotfix history I can see. **[D]** `git log -- spells/warrior` in gamedata after the Nov 4
rebaseline shows only: Nov 5 added NPC shells Charge 1283073 and Shield Charge 1283407; Nov 6 Gore Drinker tooltip; Nov 8 damage ranges; Nov 9
Charge 1283073 weapon damage +20→+10 (§5.2). The "Raging Blows" talent became Improved Whirlwind (id 1310315) before launch
(mythicsim `docs/prepared-v2.md`, `talent_ranks.rs`); the **ability** Raging Blow (402911) is a different spell, see §4.2.

**Risk for the next regeneration [D]:** Charge 1283073 and 1328028 are name-only rows with no cooldown, so the CD-carrier rule should not pick them.
The `Charge` pin (§8) removes the risk entirely.

## 5. Blizzard notes, Nov 6–10, and what changed in the data

### 5.1 Blizzard posts

| Date | Source | Warrior content |
|---|---|---|
| Nov 5 | Hotfixes thread 2403040 | "Plainsrunning can no longer stack and stacks will be cancelled when carrying a flag in a battleground." Tauren racial, relevant to Tauren warriors, not tracked. **[V]** forum JSON, post 1 |
| **Nov 6** (posted 2026-11-07T01:07Z, post edited 01:08Z) | "WoW: Forever Hotfixes – November 6, 2026", us.forums.blizzard.com/en/wow/t/wow-forever-hotfixes-november-6-2026/2403040 | **Warrior:** "Fixed the tooltip for Reckless Swings to mention that it activates Gore Drinker." (tooltip only). Neighbouring class-wide lines: "Fixed an issue with the Quick and the Dead Legacy Talent …"; Cooldown Manager "will now correctly display the duration of crowd control spells at all times, even when diminishing returns or mechanic reductions … are factors" (FX does not use CDM). **[V]** |
| Nov 6 21:11Z | "Class Tuning Incoming – November 10", topic 2404092 post 1 | Plans hotfixes on **Tue Nov 10** for Hunter pets and Voidwalkers, Affliction Warlock DoTs, Enhancement Shaman stats. **No warrior item.** Not live yet. **[V]** |
| Nov 8 | "Dungeon Enemy XP Increased - November 8", topic 2406595 | Dungeon kill XP +50%. Not class content. **[V]** forum search excerpt |
| Nov 9–10 | none found | Coverage limit **[UNVERIFIED]**: I searched us.forums only (`Kaivax after:2026-11-07`, `warrior hotfix Forever after:2026-11-06`). I did not reach the EU forum, Wowhead's blue tracker or Reddit |

### 5.2 Data hotfixes in gamedata (not posted by Blizzard)

**[D]** by id-level diff of the warrior spell cards at each commit:

| Commit / date | Build | Warrior change | Timer impact |
|---|---|---|---|
| `8edc445` 2026-11-04 | 70755 | A `protection.txt` threat modifier "+30% threat → +80% threat" (sim commit `862c69f4` attributes hotfix push 113605 to Defensive Stance and Defiance threat) | none |
| `877819c` 2026-11-05 | 70790 | + NPC shells Charge 1283073, Shield Charge 1283407 | none (see §4.4 risk) |
| `490f299` 2026-11-06 | 70790 | Gore Drinker tooltip adds Reckless Swings (the blue note) | none |
| `a7aa8b5` 2026-11-08 | 70862 | Revenge R1–R6 and Shield Slam R1–R4 damage ranges tightened (e.g. Revenge R6 122–184 → 138–168; Shield Slam R4 625–685 → 640–670); Quick Strike 25–45 → 30–40; NPC rows | none (damage only). Matches mythicsim's "A physical school damage hit rolls a whole number" |
| `520dc58` 2026-11-09 | 70862 | Charge 1283073 weapon damage +20 → +10 (NPC row) | none |

No change to any cooldown, duration, tick or charge column of any tracked warrior row since our overlay. Our data is current for 70862 as of
`693ee03`.

### 5.3 Earlier notes still in force

Dev notes post 9 (2026-11-03), warrior line: "Slam cooldown 15 s (was 18); Improved Slam 2.5/5 s; new talent Reckless Swings (15 s cd)". Slam and Improved Slam are
in the store and the cards now; Reckless Swings is §3.1. Also: Orc Blood Fury cd 2 min; Troll Berserking 15 s (`docs/research/forever-dev-notes-2026-11-03.md` §1).

## 6. Implications for our setup

1. **Charge**: with 27685 a non-English client gets no Charge bar (`IsPlayerSpell(27685)` is false for warriors, §2.2 mechanism **[I]**), and an English
   client predicts 25 s until the first plain read. Charge is out-of-combat only, so the read arrives quickly, but the pre-pull first cast is mis-timed.
2. **Rend** is the single most useful addition for the Timer module: it is cast-predictable (own `UNIT_SPELLCAST_SUCCEEDED`), has a fixed
   duration per rank, and Arms warriors want to know when it is down. Lower ranks (levelling) use shorter windows (R1 9 s … R5 21 s); the name-keyed
   row carries the R7 number. Same limitation as every ranked DoT we ship.
3. **Slam / Whirlwind / Intercept / Disarm** first-cast predictions are long for talented warriors (§2.3). The learned duration fixes it after one read.
4. **Reckless Swings** costs 25% of base health and has a 1 s GCD. Our GCD band logic (`Engine.lua:364-388`, `MIN_COOLDOWN = 2.99`) is unaffected, because the cooldown is 15 s.
5. **Probe list for the next live warrior session** (cheap, one paste each): `IsPlayerSpell` for 11605 vs 1310200 (±Improved Slam); for 11578 vs 27685;
   for the rune ids in §4.2; read `C_Spell.GetSpellCooldown` for Charge and confirm 15 s and GCD 0; and check `C_Spell.IsSpellUsable` for Overpower/Revenge in combat.

## 7. Open questions

- Are SoD rune abilities (Raging Blow, Rampage, Meathook, Shockwave, Enraged Regeneration, Rallying Cry, Gladiator Stance, Commanding Shout) learnable in
  Forever? Evidence says no; a one-line probe settles it (§4.2).
- Does `IsPlayerSpell` return true for the override ids (1310200 Slam; 1240289 Charge under Vanguard)?
- Improved Shield Wall's real magnitude (store text gives `−660000` ms, which does not fit a 15 min base).
- Is the SoD tuning passive 446658 (Thunder Clap 6 s → 4 s via copies 461810/26–30) active on Forever? Store, cards and the sim all say 6 s; a plain cooldown read on a warrior settles it.
- Do Cleave and Heroic Strike matter as cooldown-bar entries? They have no cooldown and are rage dumps; I left them out on purpose.
- Which racials other than Berserking, Rapid Regeneration, Blood Fury and Eureka! belong on a warrior bar? Stoneform 20594, War Stomp 20549, Will of the
  Forsaken 7744, Escape Artist 20589, Perception 20600, Cannibalize 20577 are **value-less name shells** in the store (no cooldown rows), so values must be measured.

## 8. Proposed patch

Applies to `tools/spell_lists/warrior.json`, then `python3 tools/gen_spell_data.py warrior`. Confidence per line: **high / med / low**.
The generator reads the keys `_deferred_H7`, `_pins`, `cooldowns`, `buffs`, `stances`, `utility`, `racials`; the fragments below use those keys and
show the **resulting arrays**, so a builder replaces the key's value.

**8.1 `_pins`: add three entries (keep the two existing ones)**

```json
"Charge": { "id": 11578, "reason": "warrior Charge R3 L46: cd 15 s, cat 44, GCD 0 (store, gamedata card 1240289, sim charge.go ByID(11578)); 27685 is the hunter boar's Charge (focus cost, 'the boar's next attack')" },
"Slam":   { "id": 11605, "reason": "spellbook Rank 5; 1310200 is the Improved Slam action-bar copy (gamedata Improved Slam card effects 4-8); same values" },
"Enrage": { "id": 12880, "reason": "Fury Enrage talent proc buff, family 4, 12 s, cat 21 (sim names.json aura enrage); 440483 is Fresh Meat's rune buff" },
"Blood Fury": { "id": 20572, "reason": "Orc racial; the store row is a value-less shell, the 120 s cooldown rides the dev-notes layer row 20572 (dev notes post 9: Orc Blood Fury cd 2 min)" }
```

Confidence: Charge **high**; Slam **med** (probe `IsPlayerSpell` first, §2.2); Enrage **med**; Blood Fury **med**.

**8.2 `cooldowns`: add `"Reckless Swings"`** (**high**). Resulting array, alphabetical like the file:

```json
"cooldowns": [
  "Berserker Rage", "Bloodrage", "Bloodthirst", "Challenging Shout", "Charge",
  "Concussion Blow", "Death Wish", "Disarm", "Enraged Regeneration", "Intercept",
  "Intimidating Shout", "Last Stand", "Meathook", "Mocking Blow", "Mortal Strike",
  "Overpower", "Pummel", "Raging Blow", "Rallying Cry", "Rampage", "Recklessness",
  "Reckless Swings", "Retaliation", "Revenge", "Shield Bash", "Shield Block", "Shield Slam",
  "Shield Wall", "Shockwave", "Slam", "Spearing Strike", "Sweeping Strikes",
  "Taunt", "Thunder Clap", "Victory Rush", "Whirlwind"
]
```

The six SoD-rune names (`Enraged Regeneration`, `Meathook`, `Raging Blow`, `Rallying Cry`, `Rampage`, `Shockwave`) stay until the §4.2 probe answers
(**med**: remove them if `IsPlayerSpell` is false for all of 402911, 403228, 426940, 440488, 402913, 426490).

**8.3 `buffs`:** add `Rend` (**high**) and `Gore Drinker` (**med**); remove `Cripple` and `Deep Wounds` (**high**) and `Cheat Death`, `Howling Blade`, `Retaliate`,
`Spell Vulnerability` (**med-high**, §4.1). Resulting array with the probe-gated rune names kept:

```json
"buffs": [
  "Battle Forecast", "Berserker Forecast", "Blood Surge", "Deep Wound", "Defensive Forecast",
  "Echoes of Defensive Stance", "Enrage", "Gladiator's Cunning", "Gore Drinker", "Hamstring",
  "Piercing Howl", "Rend", "Single-Minded Fury", "Slammin'", "Sudden Death", "Sunder Armor",
  "Sword and Board", "Taste for Blood", "Victorious"
]
```

**8.4 `utility`: remove the key** (`Intervene` has no spell body, §4.3) (**high**). **`stances`:** keep as is; `Gladiator Stance` and `Commanding Shout` are
probe-gated with §4.2 (**med**).

**8.5 `_deferred_H7`:** `["Vigilance"]` (`Reckless Swings` resolved, **high**; `Vigilance` is a rune row, **low** to keep).

**8.6 `racials`:** `["Berserking", "Rapid Regeneration", "Blood Fury", "Eureka!"]` (**med**). Eureka! resolves by family (1259813 is the family-4 row).

Companion changes for the same patch (not spell-list edits):

- `Forte_Cooldown/tests/test_70707_overlay.lua:68-74`: assert `11578`, `15000`, category `44`, `gcdMs` 0 (high).
- Generator (optional, low): feed `ProcCharges` to a charge badge for Shield Block (2), Sweeping Strikes (5), Reckless Swings (4), Gore Drinker (3).
- Generator (optional, low): a per-name aura duration source for Bloodrage (29131, 10 s) and Last Stand (12976, 20 s).
- Hotfix-watch: re-diff `spells/warrior/` in gamedata after the Nov 10 tuning push. Nothing warrior-specific is announced.

## Appendix A: id tables

| Name | Ranks / ids (store) |
|---|---|
| Rend | R1 772 (L4, 9 s), R2 6546 (10, 12 s), R3 6547 (20, 15 s), R4 6548 (30, 18 s), R5 11572 (40, 21 s), R6 11573 (50, 21 s), R7 **11574** (60, 21 s); tick 3 s |
| Charge | 100 (L4), 6178 (L26), **11578** (L46); Vanguard copies 1240287, 1240288, 1240289; stun 7922 (1 s); **not warrior:** 27685, 28343 (boar), 1283073, 1328028 (NPC shells) |
| Slam | 1240193 (L20), 1464 (30), 8820 (38), 11604 (46), **11605** (54); Improved Slam copies 1310196–1310200; "Slam!" SoD rows 462893–462897 |
| Revenge | 6572, 6574, 7379, 11600, **11601** (trainer, L54), 25288 (book, L60) |
| Battle Shout | 6673, 5242, 6192, 11549, 11550, **11551** (trainer, L52), 25289 (book) |
| Thunder Clap | 6343, 8198, 8204, 8205, 11580, **11581**; all 6 s category cd. The 4 s copies 461810/26–30 are action-bar overrides granted by the SoD `S03 - Tuning and Overrides Passive - Warrior` (446658, `other.txt`: a −70% cooldown on a family-4 spell); the sim and the store keep 6 s, so I treat them as not live **[UNVERIFIED]** |
| Overpower | 7384, 7887, 11584, **11585**; windows 1282733 (5 s), 1289681 (marker) |

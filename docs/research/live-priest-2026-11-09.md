# Priest: live data and Blizzard notes check, 2026-11-09

Author: RsrchPriest (read-only research subagent). Written and fetched 2026-11-09. Scope: the Priest class on WoW Forever
(live 1.60.1.70862), our `tools/spell_lists/priest.json` and generated `addon/Forte_Priest/Data/Priest.lua`, and Blizzard
posts for Nov 6 to Nov 10. This is the only file written. The only shell side effects were scratch files under `/tmp`.

**Labels.** `[V]` = a verbatim quote or value from a page I fetched (URL and date given). `[D]` = derived from local
data or code (`file:line` or row id). `[I]` = my inference. `[UNVERIFIED]` = I could not check it.
`[LOCAL]` below means a file in our repo or the pinned sibling clones.

## 0. Answer first

1. **Nothing in our Priest data is stale.** All 58 generated rows were compared field by field (duration, cooldown or
   category cooldown, cast time, GCD) against the current live store. 56 match. The 2 differences are the documented
   racial pins (Berserking and Rapid Regeneration, 180 s each, owner-measured), which the store has no row for [D] (§2).
2. **The live store did not move for Priest.** The current `wowsims/forever` checkout (`9ca4d977`, 2026-11-09) still stamps
   the `priest` group at build `1.60.1.70790`, hotfix push `113715`. That is exactly our overlay pin. Only `paladin` and
   `items` advanced to `70862` / push `113823` [D] (§1).
3. **No Priest line appears in any Blizzard post for Nov 6 to Nov 10.** The Nov 6 hotfix list has no Priest section. The
   Nov 10 "Class Tuning Incoming" post names Hunter pets, Voidwalker, Affliction Warlock and Enhancement Shaman only.
   The Nov 8 post is dungeon XP. Staff made no later post in the Class Tuning thread through 2026-11-09T20:26Z [V] (§3).
4. **One Priest data change did ship, but it does not touch our timers.** gamedata shows Fear Ward changed twice in
   70862 hotfixes: pushes `113775` and `113789`, both landed 2026-11-07. The net effect is that "stance exclude
   Shadowform" was removed, so Fear Ward is now castable in Shadowform. Duration and cooldown are unchanged (180 s / 180 s)
   [D] (§3.3).
5. **Mind Sear is correct.** The generator picks `413259`, which is the 6 s aura with a 1 s period. `413260` (bare, higher
   id) is the per-tick damage trigger spell. The shadowing is the intended "companion-row" law. No pin is needed (§4).
6. **Weakened Soul is not "absent on Forever"** as `docs/class-port.md` §4.4 says. Spell `6788` exists, family 6,
   15 s. The class-port table looked up an id-only registration (`Priest.lua:87`, no name comment) by name and got a
   false "absent" [D] (§5.1). It still should not go into the list as a plain name (§5.1, §7).
7. **Three Forever mechanics make a pure cast-predict timer wrong for some Priests.** They are Improved Shadow Word: Pain
   (+6 s), Pain and Suffering (rune refresh of SW:P / Void Plague / Vampiric Touch), and Weakened Soul reductions from
   heals. `Registry.Learn` and the out-of-combat reconcile already repair the first one after the first reconcile [D]
   (§5.3).

## 1. Sources and what each one proves

| Source | Version / date | Used for |
|---|---|---|
| `wowsims/forever` clone `/tmp/wowsims-forever` | `9ca4d977c9d4cfa60522aa2d69eeb4412608a567`, 2026-11-09T16:02:52+01:00 | `assets/db_inputs/spell_store_inputs.json` (gzip; tables `Names`, `Misc`, `Cooldowns`, `Levels`, `ClassOptions`, `AuraOptions`, `Effects`, `Builds`, `Hotfixes`, `SpellDataGroupRoots`) and `sim/priest/*.go` |
| `wowsims/gamedata` (fetched via `git clone` into `/tmp`) | HEAD `4e580e73` 2026-11-09T17:12:04Z, `state.json` = build 70862, 5305 pushes | readable per-spell text in `spells/priest/{shadow,discipline,holy,other}.txt`, and the per-hotfix `patches/1.60.1.70862/*/CHANGES.md` + `spells.diff` |
| `mythicsim-forever-engine` | `ff6a43cf` (2026-11-10T01:54+11) | `data/spells.jsonl`. `git diff --stat b998bbab..ff6a43cf -- data` shows only item jsonl changed, so our 70425 base is unchanged [D] |
| Our overlay | `tools/overrides_70790.json`, commit stamp `138964222`, build 70790, push 113715 | what `Priest.lua` was generated from |
| Blizzard news, Nov 6 hotfixes | https://worldofwarcraft.blizzard.com/en-us/news/24315281/wow-forever-hotfixes-november-6-2026 ("WoW: Forever Hotfixes - November 6, 2026", byline Nov 7, 2026), fetched 2026-11-09 | Nov 6 hotfix text. The page still ends at the Nov 5 section [V] |
| Blizzard forum, Class Tuning | https://us.forums.blizzard.com/en/wow/t/2404092 ("Class Tuning Incoming - November 10", Kaivax, 2026-11-06T21:11Z); all 551 post ids scanned via the Discourse JSON API | Nov 10 plan. Only post 1 is by staff [V] |
| Blizzard forum, Nov 8 | https://us.forums.blizzard.com/en/wow/t/2406595 ("Dungeon Enemy XP Increased - November 8", Kaivax, 2026-11-08T19:47Z) | no class content [V] |
| Hotfix thread | https://us.forums.blizzard.com/en/wow/t/wow-forever-hotfixes-november-6-2026/2403040 | search index shows its last post at 2026-11-07T01:07Z; no Nov 7 to 9 list [V] |
| Wowhead news | https://www.wowhead.com/forever/news/wow-forever-official-development-notes-and-class-tuning-383704 ("WoW: Forever Official Development Notes and Class Tuning", published 2026-11-02T21:51-06:00) | the Nov 2 Priest dev-note lines [V] |
| Third-party tracker | https://wowforever.news/changes.html (page header "Updated 9 Nov 2026, 22:05") | cross-check only. Its 15 Priest entries are all stamped live build 70755 / 70790 or the Nov 2 notes [V] |

Scope limit [UNVERIFIED]: I have no live client and no in-game probe. Every "live" value here is the store or the gamedata
dump of the live CDN, not an observed cast. The EU forum mirrors were not fetched (the US threads carry the same staff text).

## 2. Spell-by-spell check (the assigned spells first)

"Ours" is `addon/Forte_Priest/Data/Priest.lua` at the line shown. "Live" is the store row
(`/tmp/wowsims-forever/assets/db_inputs/spell_store_inputs.json`) plus the gamedata text. Periods come from
gamedata `period=…ms` and the mythicsim `Effects[].PeriodMs` (the store `Effects.Amplitude` field is not a period; it
reads 0 for Shadow Word: Pain and 1 for Devouring Plague, so I did not use it) [D].

| Spell (id ours) | Ours (`Priest.lua`) | Live | Match | Notes |
|---|---|---|---|---|
| Shadow Word: Pain `10894` R8 | `:65` dur 18000, tick 3 | `shadow.txt:2063` "127 shadow damage every 3 s … (6 ticks)", dur 18 s, GCD 1.5 s, 470 mana | yes [D] | Improved Shadow Word: Pain `15275` adds +6 s (`shadow.txt:742`, §5.3) |
| Devouring Plague `19280` R6 | `:57` dur 24000, cd 24000 cat 691, tick 3 | `shadow.txt:305` dur 24 s, cooldown 24 s (category), "leeches 106 every 3 s (8 ticks)" | yes [D] | the Tier 1 Shadow 5P bonus is a -60 s cooldown modifier (`SPELLMOD_COOLDOWN base=-60000`) on a 24 s cooldown (§6 Q1) |
| Vampiric Touch `402668` | `:90` dur 15000, cast 1500, tick 3 | `shadow.txt:2728` dur 15 s, cast 1.5 s, "65 shadow damage every 3 s (5 ticks)" | yes [D] | fam-3 row `402841` is a Mage-family companion (aura 332), never taken (family law) |
| Power Word: Shield `10901` R10 | `:63` dur 30000, cd 4000 cat 56 | `discipline.txt:1767` dur 30 s, "cooldown 4 s (category)", refs `6788` | yes [D] | |
| Weakened Soul `6788` | not tracked | `other.txt:2321` dur 15 s, mechanic immunity "Cannot benefit from Power Word: Shield", family 6 | n/a | §5.1 |
| Renew `425277` R10 | `:91` dur 15000, tick 3 | `holy.txt:2162` "194 healing every 3 s (5 ticks)" | yes [D] | two ladders exist, `139…25315` (166 base) and `425268…425277` (194 base). Both 15 s / 3 s. Both are in the priest root set [D] |
| Inner Fire `10952` R6 | `:81` noTarget, dur 600000 | `discipline.txt:908` dur 600 s, "charges 20", +1395 armor | yes [D] | the 20 charges are `AuraOptions.ProcCharges`, not `MaxStack`, so no stack feed (§7) |
| Fade `10942` R6 | `:87` dur 10000, cd 30000 cat 82, noTarget | `shadow.txt:496` dur 10 s, cooldown 30 s (category) | yes [D] | non-family rows `12685` and `1292765` ignored by the family law |
| Psychic Scream `10890` R4 | `:101` dur 8000, cd 30000 cat 43 | `shadow.txt:1631` dur 8 s, cooldown 30 s (category) | yes [D] | Improved Psychic Scream `15392` is `SPELLMOD_COOLDOWN -4 s` (`shadow.txt:731`), so a talented cooldown is shorter than 30 s |
| Shadowfiend `401977` | `:49` dur 15000, cd 300000 | `shadow.txt:2125` dur 15 s, cooldown 300 s, summons creature 202079, refs `401988` Mana Leech | yes [D] | the Classic `34433` row has no family and is not picked |
| Prayer of Mending `1240827` R3 | `:58` cd 10000 cat 1181, no duration | `holy.txt:1689` cooldown 10 s (category), GCD 1.5 s | yes [D] | the aura is `401877`: 30 s per jump, `MaxStack 5` (`holy.txt:1638`, store `AuraOptions`). It is not a row (§5.4) |
| Mind Sear `413259` | `:94` dur 6000, tick 1 | `shadow.txt:1333` dur 6 s, "casts 413260 Mind Sear every 1 s (6 ticks)", attrs channeled | yes [D] | §4 |
| Touch of Weakness `19266` R6 | `:86` noTarget, dur 600000 | `shadow.txt:2630` dur 600 s, "casts 28598 on its trigger", refs `19254` | yes [D] | the debuff on the attacker is `19254` (120 s, -204 AP, `shadow.txt:2543`). It comes from being hit, so no cast of ours creates it |

The other 45 generated rows, compared by the same script, also match. Forever-specific spells (all rows in `Priest.lua`):

| Spell | Ours | Live (gamedata) | Match |
|---|---|---|---|
| Void Plague `425204` | `:56` dur 18000, cd 6000, tick 3 | `shadow.txt:2750` dur 18 s, cooldown 6 s, 129 every 3 s (6 ticks) | yes [D] |
| Void Zone `431681` | `:52` dur 10000, cd 30000, cast 2000, tick 1 | `other.txt:2255` dur 10 s, cast 2 s, cooldown 30 s, "40 every 1 s (10 ticks)" | yes [D] |
| Eye of the Void `402789` | dur 30000, cd 180000 | `shadow.txt:397` dur 30 s, cooldown 180 s | yes [D] |
| Homunculi `402799` | dur 120000, cd 120000 | `shadow.txt:656` dur 120 s, cooldown 120 s | yes [D] |
| Dispersion `425294` | `:72` dur 6000, cd 120000, tick 1 | `shadow.txt:350` dur 6 s, cooldown 120 s, mana "every 1 s" | yes [D] |
| Power Word: Barrier `425207` | dur 10000, cd 180000 | `discipline.txt:1434` dur 10 s, cooldown 180 s | yes [D] |
| Confounding Flash `1277455` | dur 3000, cd 120000, cast 500 | `discipline.txt:1` dur 3 s, cast 0.5 s, cooldown 120 s | yes [D] |
| Circle of Healing `401946` | cd 6000 | `holy.txt:152` cooldown 6 s | yes [D] |
| Pain Suppression `402004` | dur 8000, cd 180000 | `discipline.txt:1073` dur 8 s, cooldown 180 s | yes [D] |
| Shadow Word: Death `1309636` R4 | `:66` cd 18000 cat 1169 | `shadow.txt:1917` cooldown 18 s (category) | yes [D] |
| Mind Flay `18807` R6 | `:93` dur 3000, tick 1 | `shadow.txt:1127` dur 3 s, "130 shadow damage every 1 s (3 ticks)" | yes [D] |
| Holy Fire `15261` R8 | `:92` dur 10000, tick 2, cast 3500 | `holy.txt:895` dur 10 s, cast 3.5 s, "15 … every 2 s (5 ticks)" | yes [D] |
| Abolish Disease `552` | `:88` dur 20000, tick 5 | `holy.txt:1` dur 20 s, "every 5 s (4 ticks)" | yes [D] |
| Dark Inspiration `1326168` | dur 10000 | `shadow.txt:78` dur 10 s | yes [D] |

## 3. Blizzard notes, Nov 6 to Nov 10

### 3.1 Nov 6 hotfixes (published Nov 7)

[V] https://worldofwarcraft.blizzard.com/en-us/news/24315281/wow-forever-hotfixes-november-6-2026 (fetched 2026-11-09).
The "Classes" block lists Quick and the Dead, Cooldown Manager, Druid, Mage, Rogue, Warlock and Warrior. **There is no
Priest sub-section.** The only generic lines are: "Fixed an issue with the Quick and the Dead Legacy Talent …" and "The
Cooldown Manager will now correctly display the duration of crowd control spells at all times, even when diminishing
returns or mechanic reductions (like orc stun reduction) are factors." Neither names a Priest spell. The Items line
"Searing Dagger is now only activated by spells that have a damaging component" is an item and not tracked by this class
list.

### 3.2 Nov 10 plan and Nov 8 post

- [V] https://us.forums.blizzard.com/en/wow/t/2404092 (2026-11-06T21:11Z). The three bullets are Hunter pets and
  Voidwalkers (durability), Affliction Warlock (Wrack vs Siphon Life / Corruption / Bane of Agony), and Enhancement
  Shaman (Strength vs Intellect). "Our plan is to make class balance changes on Tuesday, and then on future Tuesdays
  if necessary." **No Priest item.** I scanned all 551 post ids (28 requests of 20): the only staff-flagged or
  Blizzard-titled author is post 1. The last post I saw is 2026-11-09T20:26Z.
- [V] https://us.forums.blizzard.com/en/wow/t/2406595 (2026-11-08T19:47Z): "At about 11:05 PST today, we deployed a
  hotfix that increased kill experience in dungeons by 50%…". No class content.
- [V] A search for `@Kaivax after:2026-11-07` returns only those two staff posts (topics 2406595 and 2403040).
- Nov 10 itself has not happened yet (today is Nov 9). Anything that lands then is **[UNVERIFIED]** until re-checked.

### 3.3 gamedata: the one Priest spell diff in 70862

[D] `/tmp/gamedata-priest/patches/1.60.1.70862/hotfix-113775+3/spells.diff` and `…/hotfix-113789+8/spells.diff`
(commits `cbcf192` 2026-11-07T22:21:38Z and `5bb6789` 2026-11-07T23:21:38Z). Fear Ward `6346`:
- 113775: `-stance exclude Shadowform` / `+stance    Shadowform` (restricted to Shadowform).
- 113789: `-stance    Shadowform` (restriction removed).
- Net: the "exclude Shadowform" restriction is gone. Duration 180 s, cooldown 180 s, GCD 1.5 s and the proc line are
  unchanged. Our row (`Priest.lua:67`) is unaffected.
- No other Priest spell diff exists in the 70790, 70840 or 70862 patch folders. I searched the `### Priest: N added, N
  removed, N changed` summary lines of all three; only those two Fear Ward hits had non-zero counts [D].
- The newest gamedata commit I inspected file by file, `4e580e73` (2026-11-09T17:12Z), touches `hotfix-pushes.txt`, `items/items.txt`, `state.json` and one patch folder with `items.txt` + `CHANGES.md` only [D]. The `### Priest:` search above covers the other Nov 9 commits.

### 3.4 Context: the Nov 2 development notes (Priest lines; our digest `forever-dev-notes-2026-11-03.md` has none)

[V] Wowhead, 2026-11-02, Priest section: "Power Word: Shield can now correctly be replaced by a Power Word: Shield of
equal or greater rank." "Shadow Word: Death now causes 30% of maximum Health damage to the Priest if it fails to kill the
target, up from 10%. … will no longer damage the Priest when the spell misses." "Binding Heal removed" / "Holy Binding".
"Devouring Contagion no longer spreads Devouring Plague if it is spreading from a critter." "Vampiric Embrace Healing can no
longer roll a critical effect." "Fixed an issue where Cure Disease and Abolish Disease would take the Priest out of
Shadowform." None of these changes a duration, tick or cooldown we track. The store carries the 30% value already
(`1309636` effect 3 base 30) [D].

## 4. Mind Sear and the companion-row law

[D] `python3 tools/gen_spell_data.py priest --dry` (read-only) prints:
`info: Mind Sear -> 413259 (companion-row shadow: bare 413260 ranked above it on level/ID)`, and the same line for
Shadowguard (`28382`) and Touch of Weakness (`28598`).

- `413259`: family 6, DurationMs 6000, GCD 1500, aura 23 (`A_PERIODIC_TRIGGER_SPELL`), `period=1000ms`, `trigger=413260`
  (`shadow.txt:1333`; store `Effects`).
- `413260`: family 6, no duration, no cooldown, `E_SCHOOL_DAMAGE base=74 … radius=10` (`shadow.txt:1353`). It is the damage
  that fires each second.
- `415738`: family 3, aura 332 pointing at `413259`. A foreign-family companion; the family law never takes it.
- The generated row is right: `[413259] = { … tickEvery = 1, durationMs = 6000, gcdMs = 1500 }` (`Priest.lua:94`).
  **No `_pins` entry is needed.**
- [I] If the client reports `413260` from a trigger event, name-keyed resolution (`Locale.RankIDsForName`, AGENTS.md) still
  lands on the `Mind Sear` row, so no id-keyed code path breaks.

## 5. Findings

### 5.1 Weakened Soul (the assignment's "Power Word: Shield / Weakened Soul")

- [D] `6788` exists: family 6, `DurationMs 15000`, mechanic immunity (`other.txt:2321`). `docs/class-port.md:493`
  (`Priest.lua:87 AddDebuff id 6788 … absent … not feasible (no Forever spell)`) is wrong. That survey keyed the lookup
  by name, and the reference line had no name comment.
- [D] Power Word: Shield `refs 6788` (`discipline.txt:1767`); the tooltip says "Once shielded, the target cannot be
  shielded again for $6788d." The sim registers it that way too: `sim/priest/power_word_shield.go`
  (`spellData.PowerWordShieldTriggered.ByID(6788)`, a cast refused while the aura is active).
- [D] **Do not add `"Weakened Soul"` to `priest.json` as a plain name.** Two code facts:
  1. `Forte_Timer/Core/Registry.lua` has no `^Weakened` term, so the name would classify as `Default`. The zero-`Default`
     law in `Forte_Timer/tests/test_kinds.lua` would then fail.
  2. `Forte_Timer/Core/Casts.lua` has no cast-to-second-row map (no `extra` / `linked` hook; searched). `class-port.md` S15
     records that map as "port-adapted … a `{[castName]=extraName}` table", not built. Weakened Soul is created by
     the Power Word: Shield cast, not by a cast of its own, so the row could never be created by cast-predict.
- [D] Weakened Soul's remaining time is also shortened by effects we cannot see: Strength of Soul `415739` (Lesser Heal,
  Heal, Greater Heal and Flash Heal reduce Weakened Soul on targets by `409317` base 2 s, `other.txt:2100,2109`),
  Renewed Hope `425280` (the same heals and Penance reduce it by 5 s, `discipline.txt:1902`; wowforever.news repeats the
  5 s), and the passive `459603` "Weakened Soul Duration Decrease" (-2 s, `other.txt:2335`). [UNVERIFIED]: which item or
  rune grants `459603`; I found no `refs` to it.
- [I] Any Weakened Soul bar would be an upper bound. If built, it needs the cast map and a reconcile out of combat.

### 5.2 Renew has two live ladders (no timing effect)

[D] Classic ids `139, 6074 … 10929, 25315` and a second ladder `425268 … 425277` (194 base at Rank 10 vs 166) are both in
the store's priest root set. The generator picks `425277`. Duration (15 s) and tick (3 s) are identical in both
(`holy.txt:2162`, and `25315` in the same file). The sim registers the classic ladder (`sim/priest/spell_data_auto_gen.go`:
`Renew: Ranked(139, 6074, … 25315)`). [UNVERIFIED] which ladder the client casts. Name-keyed resolution covers both, so
this is only an id-trivia note.

### 5.3 Talent and rune effects that move a predicted window

The "what it does" column is [D] from gamedata text. The "our model" column is [I] unless it cites a file. None is a data bug, because the base spell data is right.

| Effect | Source row | What it does | Our model |
|---|---|---|---|
| Improved Shadow Word: Pain | `15275` (`shadow.txt:742`) | `SPELLMOD_DURATION +6 s` on Shadow Word: Pain. The sim has it as `Talent(15275, 2)`, so I take +6 s as the 2-rank total [I] | row says 18 s. `Registry.Learn(row.name, total)` (`Reconcile.lua:220-222`) learns the real length at the next out-of-combat reconcile |
| Pain and Suffering | `413251` (rune) | Mind Blast, Mind Spike and Mind Flay refresh one of Shadow Word: Pain, Void Plague or Vampiric Touch to full duration (the shortest one) | a cast-predicted expiry will be too early after any Mind Blast / Flay. Needs the same unbuilt `castName → extra` map as S15 |
| Pain and Suffering (Devouring Plague) | `1213708`, "S03 - Item - RAQ - Priest - Shadow 3P Bonus" | the rune can refresh Devouring Plague too | as above |
| Shared Pain | `401969` | Shadow Word: Pain also afflicts extra nearby targets | the extra targets get no cast event; invisible to cast-predict |
| Improved Psychic Scream | `15392` (`shadow.txt:731`) | cooldown -4 s on Psychic Scream | row says 30 s. [I] The cooldown reader (`C_Spell.GetSpellCooldown`) reads the real value, so this self-corrects |
| Devouring Contagion | `1309950` (`shadow.txt:193`) | mana -50% (rank dependent), and spreads on target death | no timing change except the spread, which is unseen |
| Tier 1 Shadow 5P | `1301706` (`other.txt`) | `SPELLMOD_COOLDOWN base=-60000` on Devouring Plague; `item_sets.go:166` comments "Reduces the cooldown of your Devouring Plague spell by 60 sec." | see §6 Q1 |
| Tier 1 Disc/Holy 3P | `1301041` | `SPELLMOD_COOLDOWN base=-60000` on Fear Ward; the sim comment at `item_sets.go:135` says "takes 60 sec off Fear Ward's cooldown" | [I] cooldown reader is real |

### 5.4 Prayer of Mending

[D] Our row is the cast (`1240827`, cd 10 s, no duration). The aura `401877` is 30 s "after each jump", `stack up to 5`
(`holy.txt:1638`), and it moves between players. The sim models jumps as delayed heals (`sim/priest/prayer_of_mending.go`).
[I] A cast-predicted 30 s bar on the first target would be wrong after the first jump, and nothing tells us about the
jump. The current list (cooldown only) is the safe shape.

### 5.5 Forever Priest spells in the store that we do not track

[D] Computed by listing every store row with `ClassOptions.Family == 6`, a name not in `priest.json`, and a GCD, cooldown
or duration, then checking each candidate with a throwaway copy of the generator in `/tmp/fxprobe` (list copy plus names,
writes only under `/tmp`):

| Name | Row the generator picks | Window |
|---|---|---|
| Penance | `1316995` Rank 4 | cd 12 s (cat 2414), GCD 1.5 s; the 2 s channel is `1316992`, a separate row |
| Mind Spike | `431655` | 10 s, 3 stacks, cast 1.5 s |
| Starshards | `19305` Rank 7 | 6 s, cd 30 s, tick 1 s |
| Feedback | `19275` Rank 5 | 15 s, cd 180 s |
| Elune's Grace | `2651` | 15 s, cd 300 s |
| Dark Sacrifice | `1277328` Rank 5 | 15 s, cd 600 s, tick 3 s |
| Desperate Prayer | `19243` Rank 7 | cd 600 s |
| Contingency Plan | `1277640` Rank 5 | 30 s, cd 600 s |
| Lightwell | `27871` Rank 3 | 180 s, cd 600 s, cast 1.5 s |
| Smite / Flash Heal / Mind Control / Divine Grace | `10934`, `10917`, `10912`, `1277378` | not timers worth a bar |

Every pick equals the row I would choose by hand, so no `_pins` are needed. [D] None of Penance, Mind Spike, Starshards,
Feedback, Elune's Grace, Desperate Prayer or Dark Sacrifice has a `Registry.lua` term (only `^Smite`, in the pet band, and
`^Sacrifice`, which is the SelfDebuff band and does not match `Dark Sacrifice`; `^` anchors the start). Adding any of
them to the list makes the name `Default` and fails `test_kinds.lua` until a term is added. So these are not pure-JSON
edits.

## 6. Open questions

1. **Devouring Plague cooldown.** The store, gamedata and mythicsim all say 24 s (category 691). The Tier 1 Shadow 5P
   bonus is a -60 s cooldown modifier (`other.txt`, spell `1301706`; `sim/priest/item_sets.go:166` carries the same 60 s). A 60 s
   reduction on a 24 s cooldown is meaningless. Either the set bonus is stale, or there is a second cooldown source the
   store lacks. [UNVERIFIED]: needs one live cast with `C_Spell.GetSpellCooldown`.
   Until measured, keep 24 s.
2. **Which Renew ladder does the client cast** (`25315` or `425277`)? Not timing-relevant; a first live
   `UNIT_SPELLCAST_SUCCEEDED` probe answers it.
3. **Does the `pet` unit's spell id stay readable** for Shadowfiend? Already an open item in
   `forever-postlaunch-2026-11-07.md` §2.2. Shadowfiend is cast by the player, so the player event is enough.
4. **Will Nov 10 touch Priest?** Blizzard has named no Priest change. Re-run the checks in §7 after the Nov 10 hotfixes.
5. **Who grants `459603`** (Weakened Soul -2 s)? I could not find a granting item or rune in gamedata.

## 7. Implications for our setup

1. **No data regeneration is needed for Priest.** The overlay pin (70790, push 113715) equals the store's priest stamp, and
   a 58-row comparison found 0 real differences. Re-run only if the store's `Builds.priest` or `Hotfixes.priest` moves.
2. **Re-check after Nov 10** (Tuesday): `git -C /tmp/wowsims-forever pull`, read `Builds` / `Hotfixes` for `priest`, then run
   `python3 tools/gen_spell_data.py priest --dry` and the gamedata diff for `### Priest:` lines. The Nov 10 post names no
   Priest change.
3. **Weakened Soul and Pain and Suffering need the same shared feed** as Class-port S15 (a `castName → extra` row map). That
   is one work item, not two. Until it exists, do not list Weakened Soul (§5.1).
4. **Inner Fire (20 charges), Elune's Grace and Shadowguard (3 charges)** carry their count in `AuraOptions.ProcCharges`, and
   the generator's `maxStack` feed reads only `MaxStack`. Prayer of Mending's aura `401877` has `MaxStack 5` but is not a
   row. The Priest `stack = 0` census in `test_data_feeds.lua:82` stays true.
5. **Mind Sear and Mind Flay are already tick-fed** (`tickEvery = 1`). The `Channel` band terms in `Registry.lua` cover both
   names. [UNVERIFIED]: whether `UNIT_SPELLCAST_SUCCEEDED` fires for the channel start of Mind Sear on this client; the
   cast spine has no `CHANNEL` hook (searched `Casts.lua`). The first live Shadow session should check this.
6. **Correct `docs/class-port.md` §4.4** (`Priest.lua:87` row for `6788`) the next time that file is edited. I did not
   edit it (read-only task).

## 8. Proposed patch

Target: `tools/spell_lists/priest.json` only. The generator picks the right row for every tracked and candidate name, so
**no `_pins` are needed.**

- **No add, remove, change or `_pins` edit to the existing entries.** Confidence **high**: no change to the existing 58 rows. The comparison in §2 found 0 real differences, and the dry run
  reports 0 gaps.

Optional additions, owner scope (the list is owner-curated). Each needs a matching `Registry.lua` `KIND_RULES` term in the
same change, or `test_kinds.lua` fails (§5.5):

```json
"cooldowns": ["…existing…", "Penance"],
"buffs":     ["…existing…", "Mind Spike"]
```
- `"Penance"` in `cooldowns`: confidence **medium**. Data is solid (`1316995`, cd 12 s, level 60). Value depends on Disc
  players; the 2 s channel is a separate row and would not be tracked.
- `"Mind Spike"` in `buffs`: confidence **low**. It is a rune spell with a 10 s, 3-stack debuff; whether the player has it
  engraved is not visible to the data.
- `"Starshards"`, `"Feedback"`, `"Elune's Grace"`, `"Desperate Prayer"`, `"Dark Sacrifice"` in `cooldowns`: confidence
  **low**. Data is correct, but these are race-locked and they need Registry terms.
- **Do not add** `"Weakened Soul"`: confidence **high**. No cast creates it and no Registry term matches it (§5.1).

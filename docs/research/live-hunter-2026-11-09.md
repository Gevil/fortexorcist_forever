# Hunter: live-data check against our pinned data, 2026-11-09

Author: RsrchHunter (read-only research subagent). Written 2026-11-09; every web page below was fetched on 2026-11-09.
Scope: `tools/spell_lists/hunter.json`, the generated `addon/Forte_Hunter/Data/Hunter.lua`, and the swing-bar logic
(`Forte_Hunter/Core/Tools.lua`, `UI/Swing.lua`, `Core/Melee.lua`). Not repeated: the 2026-11-07 reports
(`data-diff-live-2026-11-07.md`, `forever-postlaunch-2026-11-07.md`). They already say "Hunter: zero row and value deltas"
and "Nov 10: Hunter pets get sturdier". This report goes past both.

**Labels.** `[V]` verified: a quote or value from a page or file I fetched, with its URL or path.
`[D]` derived: I computed it from local data or code (method given). `[I]` inference. `[UNVERIFIED]` I could not check it.
I have no live client. Every claim about in-game behaviour is second-hand and is marked that way.

**Sources used.**
- Upstream store `/tmp/wowsims-forever` @ `9ca4d977` (2026-11-09). That is `assets/db_inputs/spell_store_inputs.json` (gzip) and `sim/hunter/*.go`.
- Client DB2 CSVs from wago.tools for builds 1.60.1.70790 and 1.60.1.70862.
- Blizzard forum JSON: the dev-notes thread and the Nov 10 tuning thread.
- The sim repo's hunter commit messages.

---

## 0. Answer first (ranked by damage to a user)

1. **[D] The Serpent Sting bar is 3 s short.** `Hunter.lua` carries id 425737 with `durationMs = 12000`. That row is not the
   castable spell. The castable ladder is 1978…13555 plus the book rank 25295. All of those are **15000 ms**, with a 3 s period.
   The Nov 2-3 hotfix (dev-notes post #9) retuned exactly that ladder (rank 9: 135 a tick, 675 in total) and left the 425xxx ladder at the old 111.
   Pin Serpent Sting to **13555** (§3.1, §9 line 1).
2. **[D] The Raptor Strike row is not the spell a character learns.** The row carries id 415343, which has BaseLevel 0,
   GCD 1500, and no "on next swing" attribute. The trainer ladder 2973…14266 is the spell the sim registers. It has
   `ON_NEXT_SWING` (attr0 `0x40004`, the same bit as Heroic Strike), GCD 0, a 6 s category cooldown, and range 5.
   Two consequences: the data's `gcdMs = 1500` is wrong, and on a non-English client `isKnown("Raptor Strike")` can never
   pass through the id path (§3.2).
3. **[D] Multi-Shot ↔ Aimed Shot share one 6 s cooldown (category 2), and we model none of it.**
   Adding `_shares` to the JSON alone is not enough. `Engine:Build` drops `shares` for non-racial rows
   (`Forte_Cooldown/Core/Engine.lua:167`; only `AddExtras` copies it, `:203-204`). The link needs a one-line code change too (§3.3).
4. **[D] The four traps share one 30 s cooldown (category 411, [V] Blizzard Nov 3). The Engine cannot express a 4-way
   group.** `shares` is one partner string per row, and the walk is one hop (`Engine.lua:264-269`, the `_partner` guard).
   This is a code gap, not a JSON edit (§3.4).
5. **Swing-bar name sets are out of date (§4).**
   - **Sniper Shot** (4000 ms cast) is missing from both sets.
   - **Steady Shot** is a Season-of-Discovery rune spell that no Forever character can learn. It is dead weight in the sets.
   - **Volley** holds Auto Shot's windup ([V] sim commit, from combat logs).
   - **Multi-Shot's cast time** is unresolved: the game data says 0 s, the sim authors say "in game 0.5 s".
   - **Aimed Shot is 2.0 s in the client table at build 70862.** The "3.0 s live" claim in a test comment has no support (§4.1).
6. **[I] Four SoD rune leftovers are tracked** (Chimera Shot, Flanking Strike, Kill Shot, Wyvern Strike) plus Carve. They are
   harmless when unknown but are noise (§3.6).
7. **No live Hunter data change exists after our pin.** The wago DB2 tables show zero Hunter row changes from 70790 to 70862.
   Blizzard's Nov 6 hotfix list has no Hunter line. The Nov 10 "sturdier pets" change is stat scaling that the store does
   not carry (`Hunter Pet Scaling` 415429 has **zero effect rows**), so **no static-data diff will show it** (§5).
8. Everything else on your checklist matches the live data (Rapid Fire, Bestial Wrath, Intimidation, Feign Death,
   Wing Clip, Viper and Scorpid Sting, aspects, Hunter's Mark): §3.5.

---

## 1. What Blizzard says is live for Hunters (through 2026-11-09)

All of this is from the dev-notes thread https://us.forums.blizzard.com/en/wow/t/2360696 (Kaivax; fetched as JSON,
posts 4, 5, 6 and 9; no later post has a Hunter line) and from the tuning thread https://us.forums.blizzard.com/en/wow/t/2404092.

| Date (UTC) | Post | Hunter lines that touch our data |
|---|---|---|
| 2026-10-01 | #4 | Sniper Shot: "45-yard Range and increases the range of your next 3 shots made within 10 seconds by 10 yards" [V]. Our row: `durationMs 10000`, `castMs 4000`, cd 15 s ✓ |
| 2026-10-08 | #5 | Disengage threat doubled; Expose Prey 10 s; Improved Wing Clip / Concussive proc fixes (no timers) |
| 2026-10-16 (Oct 15 build) | #6 | "Auto Shot now requires you to stand still for 0.5 seconds before shooting." "Your character will still fire Auto Shot while casting spells like Aimed Shot or Sniper Shot." Fire traps scale with AP; one Fire and one Ice trap may be active [V] |
| 2026-11-03 | #9 | "Hunter's Mark can no longer be applied to a target multiple times by using different ranks of the spell." "All types of Hunter traps now have the same shared 30 second cooldown, instead of separate cooldowns for Fire-based and Frost-based traps." Aimed/Arcane/Serpent/Sniper/Aspect-of-the-Hawk/Trueshot values raised [V] |
| 2026-11-04 | #10 | No Hunter line (UI only) |
| 2026-11-06 | hotfix list | **No Hunter line.** Only the Warlock, Druid, Mage, Rogue and Warrior lines in `forever-postlaunch-2026-11-07.md` §1.2 |
| 2026-11-08 | "Dungeon Enemy XP Increased" | XP only [V] https://us.forums.blizzard.com/en/wow/t/2406595 |
| 2026-11-06 (plan) | tuning thread post 1 | "We've seen that Hunter pets and Warlock Voidwalkers are not as durable as tanks as we would like them to be. Our intent is for their effectiveness to be relatively the same as in Classic Era. We will adjust their stats as necessary to accomplish this." Hotfixes "on Tuesday, November 10". As of 2026-11-09T20:26Z, none of the 551 posts is a Blizzard follow-up with detail [V, I read all 551] |

The Nov 3 numbers are in our store: `Aimed Shot` rank 6 is 350, `Arcane Shot` rank 8 is 280, and `Serpent Sting` ranks 8 and 9 tick 100 and
135 ([D], store rows 20904, 14287, 13555, 25295). That fits "Hunter stats are at push 113715".

---

## 2. Provenance of our numbers (what "live" means here)

- **[D]** The store's Hunter group is still `1.60.1.70790`, hotfix push **113715**. Items and Paladin were re-taken at
  70862 / 113823 (`Builds` and `Hotfixes` keys in `spell_store_inputs.json`; upstream commit `314deb02`, "[Paladin] Take the paladin
  spell data to 1.60.1.70862 at hotfix push 113823"). No one has re-extracted Hunter since push 113715.
- **[D]** I closed the gap that the client tables can close. I diffed wago.tools DB2 exports `SpellMisc`, `SpellCooldowns`,
  `SpellEffect` and `SpellName` between 70790 and 70862 over **833 Hunter-related ids**. These are every id whose store
  `ClassOptions.Family == 9`, the 450 Hunter group roots, and every name in `hunter.json`. The result is **0 changed ids in all
  four tables.** The DB2 files carry no hotfix pushes, so a push after 113715 could still hide a change. Blizzard's published
  hotfix lists for Nov 5 to Nov 8 contain none.
- **[V]** The latest `wowf` build on wago is still 1.60.1.70862 (`https://wago.tools/api/builds`, fetched today).
- **[D]** A row can be right as a name and wrong as a spell. The generator's rank law takes the highest "Rank N" row after
  excluding book ranks (`gen_spell_data.py:125-135`). On Hunter that picks non-learnable duplicate ladders for **two**
  names (Serpent Sting, Raptor Strike). I scanned all 76 tracked names for rows with different timing tuples. Only these
  two have a real ladder conflict that matters. The rest are triggered rows or value-less shells (§3.7).

---

## 3. Row checks

### 3.1 Serpent Sting: 15 s, not 12 s (and one sting per target)

[D] Store rows, same name, same family 9, both "Rank 9, spell level 60":

| id | BaseLevel | Speed | range | DurationMs | period | per-tick base | cast |
|---|---|---|---|---|---|---|---|
| **25295** (book) | 60 | 40 | 8-35 | **15000** | 3000 | **135** | -1000000, GCD 1500 |
| 13555 (Rank 8, trainer) | 58 | 40 | 8-35 | **15000** | 3000 | **100** | same |
| 425737 (what we ship) | **0** | 0 | 0-100 | **12000** | 3000 | 111 | same, no GCD |

- The Nov 3 hotfix says Serpent Sting rank 8 is 500 (was 415) and rank 9 is 675 (was 555). 5 ticks × 100 = 500 and
  5 ticks × 135 = 675 ✓ for the 15 s ladder. 425737's 111 is 555 ÷ 5, the **pre**-hotfix number. So that ladder was
  not retuned and is not the spell the hotfix described.
- The sim registers `ByID(13555)` and `ByID(25295)` only (`sim/hunter/serpent_sting.go:8-10`).
- Client DB2 70862 agrees that the two rows differ: `SpellMisc` `DurationIndex` is 8 for 25295 and 29 for 425737, matching the store's 15000 vs 12000.
- **Why we picked it [I].** 425737 is not in the AQ20 book list, and it has the highest "Rank 9" text, so the rank law lands on
  it. The 425728-425737 ladder looks like an internal helper: BaseLevel 0, Speed 0, range 100, no GCD, a different `Attr`.
  I did not find out what it is for.
- **Effect:** the Serpent Sting bar and its ticks end 3 s early (4 ticks drawn where 5 happen).
- **One sting per target.** The store text on 25295, 14280 and 3043 reads "Only one Sting per Hunter can be active on any
  one target." [V]. The sim does the same (`hunter.go:154-160`, `dropOtherSting`). `Casts.UNIQUE` holds only Hunter's Mark
  (`Forte_Timer/Core/Casts.lua:111`), so casting Viper or Scorpid Sting over a Serpent Sting leaves a stale Serpent bar [I].
  This is a code item (§7).

### 3.2 Raptor Strike: wrong ladder, and a swing-reset reading

[D] Three Raptor Strike ladders exist in the store:

| ladder | ids (rank 1 … 8) | BaseLevel | attr0 | GCD | cd | note |
|---|---|---|---|---|---|---|
| **trainer** | 2973, 14260-14266 | 1 … 56 | `0x40004` = **ON_NEXT_SWING** | **0** | 6000 (cat 40) | the sim's ladder (`spell_data_auto_gen.go:400`) |
| ours | 415335-415343 | **0** | `0x50000` (no 0x4) | 1500 | 6000 (cat 40) | damage 140 at rank 8 vs 70 |
| no cooldown row | 409691-409755 | 0 | `0x50000` | none | none | |

- `Heroic Strike` (78, 11567) carries attr0 `0x50014`, the same on-next-swing bit [D]. Mongoose Bite 14271 does not carry it
  (it is the 1.5 s-GCD instant).
- The sim's rule: Raptor Strike is queued, and "the next swing casts it in the swing's place"
  (`sim/hunter/raptor_strike.go:24-25`; `hunter.go:96` `ReplaceMHSwing`). **[D] reading: the "reset" is the replaced swing.
  There is no extra reset on top of it.** After the strike the main-hand timer restarts as after any swing.
- **Live evidence on when `UNIT_SPELLCAST_SUCCEEDED` fires** (second-hand, [V] in `forever-postlaunch-2026-11-07.md` §2.6, from
  nameplatesct-reforged PR #39): the live Heroic Strike trace is `UNIT_SPELLCAST_SUCCEEDED Heroic Strike` → `PLAYER_SWING`
  → damage. So SUCCEEDED arrives **at the swing**, directly before `PLAYER_SWING`. **[I]** Raptor Strike behaves the same. Then
  `Melee.lua`'s "re-arm on SUCCEEDED" is harmless: `PLAYER_SWING` follows at once with the real duration.
  **[UNVERIFIED]** I found no trace for Raptor Strike itself. If SUCCEEDED fires at queue time, the melee rail refills too early.
- **Known-gate effect (a real bug, not an inference).** `Forte_Cooldown/Module.lua:79-95` `isKnown(name)` tries
  `Locale.RankIDsForName(name)` first. That list is **only the data row's id** (`Locale.lua:254-257`; the header comment at `:41`
  says "every rank row", but `Hunter.lua` holds one row per name). For Raptor Strike that is 415343, which no player knows,
  so the id path fails. The fallback `C_Spell.GetSpellInfo(name)` works only on an English client (the comment at `Module.lua:80-84` says so). On a
  localized client **the Raptor Strike cooldown row is never tracked** [D from the code; no live run].
- **GCD value.** The row's `gcdMs = 1500` feeds the weave arithmetic in `docs/hunter-tools.md` and `wst-swing-design.md`
  ("1.5 s GCD for Raptor Strike / Mongoose Bite"). A real Raptor Strike uses no GCD, so the weave line over-reserves
  one global for Raptor. Harmless but wrong.
- Fix: pin Raptor Strike to **14266** (§9 line 2).

### 3.3 Shared cooldowns

[D] Store rows (`Cooldowns` + `Categories`):

| pair | category | cooldown | evidence |
|---|---|---|---|
| Aimed Shot ↔ Multi-Shot | **2** | 6000 | 2643, 19434…20904; descriptions: "Aimed Shot shares its cooldown with Multi-Shot." / "Multi-Shot shares its cooldown with Aimed Shot." |
| Arcane Shot ↔ Summon Hawk | **1173** | 6000 | 3044…14287 and 1293241, 1293525-27; Hawk ranks also carry the 6 s category cooldown ✓ |
| Arcane Shot ↔ Aimed Shot | not shared | - | the two categories differ (1173 vs 2) ✓ |

- Only the second pair is modelled (`_shares: {"Summon Hawk": "Arcane Shot"}`).
- **`Engine:Build` ignores `shares`** (`Engine.lua:167` builds `{name, dataId, baseDuration}`; only `AddExtras` at `:203-204` copies it).
  The Hawk pair works because Summon Hawk is a racial row. A `_shares` for Multi-Shot / Aimed Shot, which both come through
  `Build`, would be **inert** without a code change. The change is to add `shares = spell.shares` to line 167.
- Effect today: a Multi-Shot cast leaves the Aimed Shot cooldown bar "ready" for 6 s (and the reverse). In combat the real
  cooldown is secret, so the predicted bar is the only signal [D from `AGENTS.md`].

### 3.4 Traps

- [D] All four (Freezing 14311, Frost 13809, Immolation 14305, Explosive 14317) carry cd 30000, category **411**. That
  matches the Nov 3 official line ([V] §1). Our rows are correct on cooldown.
- [D] `durationMs = 60000` on those rows is the **armed trap's lifetime**: the store description of each says "Trap will exist for $d".
  It is not the effect on the target. The target effects are separate rows we do not track: Freezing Trap 10 / 15 / **20** s
  (3355 / 14308 / **14309**), Frost Trap slow zone 30 s (13810), Immolation DoT 15 s (14301), Explosive 20 s (13812-14315).
  Those are unseeable by cast prediction: a trap springs when an enemy walks in. The trigger would need an aura or log
  event, and both are closed in combat [I].
- [V] Oct 15 (post #6): one Fire and one Ice trap may be active. [D] The Frost family is Freezing + Frost Trap; the Fire family is Immolation + Explosive
  (store descriptions: "Only one Frost trap can be active at a time" / "Only one Fire trap…"). Placing Frost Trap should retire a
  live Freezing Trap bar, and Explosive should retire Immolation. FX has no eviction group for this [I]. This is a code item (§7).
- **Engine gap.** A 4-way shared cooldown cannot be written as one `shares` partner per row. Casting Freezing Trap would start
  Frost Trap and Explosive Trap in a ring layout, but not Immolation Trap. A star layout covers only casts of the hub.
  `OnCast(pname, now, true)` stops after one hop (`Engine.lua:264-269`).

### 3.5 Items on your checklist that match live

| Item | Our row | Store / client | Verdict |
|---|---|---|---|
| Rapid Fire | 3045: 15000 / 300000 cd, cat 55 | same; "+$s1% ranged **and melee** attack speed" (40) | ✓ |
| Bestial Wrath | 19574: 18000 / 120000 | same | ✓ |
| Intimidation | 19577: 15000 / 60000, cat 1132 | 15 s is the pet-command window ("on its next successful attack"); the **stun** is 3000 ms on the triggered 24394 | ✓ row; the bar is the window, not the stun [I] |
| Feign Death | 5384: 360000 / 30000 | "Lasts $d. If not cancelled, after $d you will actually die." | ✓ the bar is a death timer |
| Hunter's Mark | 14325 (rank 4): 120000 | ranks 1130, 14323, 14324, 14325 all 120 s | ✓. Single target is handled in `Casts.UNIQUE` (`Casts.lua:111`, `:587-592`). **[UNVERIFIED]** I found no store flag that proves "one target per hunter". The only evidence is the owner's 2026-11-06 live note in that code comment |
| Wing Clip | 14268: 10000 | all three ranks 10000; rank 3 slows 60% | ✓ |
| Viper Sting | 14280: 8000 / 15000, tick 2 s | same | ✓ |
| Scorpid Sting | 3043: 20000 | same | ✓ |
| Aspects (9) | `durationMs = -1` | all nine exist in the sim ladders; Hawk row is the trainer rank 6 (14322) | ✓ |
| Concussive 12 s, Scatter 30 s, Disengage 5 s, Counterattack 5 s, Mongoose 5 s, Distracting 8 s, Tranq 20 s | as listed | match store | ✓ |
| Mine! 3 s/90 s, Dismember 6 s/15 s | match | [V, secondary] the Oct 15 pet cuts as reported by https://wowforevertierlist.com/classes/hunter/changes (page dated 2026-10-31) | ✓ |
| Aimed Shot 20904 | cast 2000, cd 6000 | DB2 70862: `CastingTimeIndex` 5 = 2000 ms | ✓ (§4.1) |

### 3.6 Tracked names that look like SoD rune leftovers [I, medium-high]

`Chimera Shot` 409433, `Kill Shot` 409593, `Flanking Strike` 415320 and `Wyvern Strike` 458482 (and `Carve` 425711 in
`pet_and_utility`). All have BaseLevel 0, and none sits in any sim ladder or in the Hunter group roots. Their rune-grant / action-bar-override partner rows
(409976, 409974, 415720, 458479 and friends) are `Family 93` spells in the sim's spell dump. The sim's generator skips "a Season of Discovery rune
ability" with this rule (`/tmp/wowsims-forever/tools/database/gen_spell_data.go:95-101, 203-217, 375-376`): a spell
is rune-only when an "Engrave" spell reaches it and no trainer or level `SkillLineAbility` row teaches it. A forum player
also writes "We lack filler rotational abilities like steady shot and kill command" (Hunter feedback thread, search snippet,
https://us.forums.blizzard.com/en/wow/t/hunter-feedback/2349379; not fetched in full). I cannot prove the negative from here.
The runtime cost is zero: `Engine:Build` tracks a spell only if `isKnown` is true.

### 3.7 Competing rows that do **not** matter

The scan flagged Enchanted Flare, Flanking Strike, Intimidation, Kill Shot, Multi-Shot, Rapid Fire, Wyvern Strike,
Heart of the Lion, Precision, Rapid Recuperation, Stalker's Ally, Aspect of the Viper, all four traps and most pet-ability names. In each
case the other rows are value-less shells, triggered effect rows, or a different, correct, lower-rank row. The picked row holds the
timing that matters. `Hunter.lua` consistently keeps the cast row. The two exceptions are §3.1 and §3.2.

---

## 4. Swing-bar logic checks

### 4.1 Cast times: what the client table says

[D] DB2 70862 `SpellMisc.CastingTimeIndex` → `SpellCastTimes.Base`, matching the store:

| Spell | id | cast | note |
|---|---|---|---|
| Auto Shot | 75 | 0 | range 8-35. Oct 15: 0.5 s stand-still before it fires [V] |
| Aimed Shot | 19434…20904 | **2000** | every rank |
| Multi-Shot | 2643 | **0** | attr0 `0x10002` |
| Steady Shot | 437123 | 1500 | rune-only; see §3.6 |
| Sniper Shot | 1310687 / 1310785 / 1310786 | **4000** | 10 s window, 15 s cd |
| Volley | 1510, 14294, 14295 | 0 (channel, DurationMs **6000**, period 1000) | no cooldown |

- **Aimed Shot 3.0 s.** `tests/test_swing_casttime.lua:10-12` says "Measured live on uiforever 2026-11-04: Aimed Shot rides 3.0 s on
  the client while the generated row says 2000 ms". The client table says 2000 ms in 70790 and 70862. `uiforever.com` is
  the UI simulator named in `AGENTS.md` ("Visual: uiforever.com"), not a Forever server. **[I]** The 3.0 s probably came from that
  simulator's own spell data. Do not change the data. The swing code's design (prefer `C_Spell.GetSpellInfo(id).castTime`,
  fall back to data) is right, but nothing here shows a real-client 3.0 s. Wowhead's Forever Hunter list labels Aimed Shot
  rank 6 "Updated: Faster cast" (search snippet, https://www.wowhead.com/forever/spells/abilities/hunter; the page itself returns
  HTTP 403 to curl, so that is second-hand).
- **Multi-Shot is a real conflict.** Game data says instant. The sim says "In game Multi-Shot has a 0.5 s cast, which the
  game files leave out" (`sim/hunter/multi_shot.go:15-16`), with no stated source. A tracker also read it as instant in
  build 70425 (wowforevertierlist, secondary). The WST finding adapted in `Core/Tools.lua` says Multi-Shot "emits no START"
  (`Castbar.lua:195-205`). A spell with no START is instant, which supports the table. **[UNVERIFIED] on the live
  client. A 20-second probe settles it** (§10 Q1).

### 4.2 Name sets

`Core/Tools.lua:205-207` `SHOT_CAST_SET` and `UI/Swing.lua:1859-1861` `CLIP_SHOT_NAMES` both read
`{Aimed Shot, Multi-Shot, Steady Shot}`.

1. **Sniper Shot is missing.** It is a 4 s cast shot with the same interlock. Blizzard names it beside Aimed Shot ("while casting spells
   like Aimed Shot or Sniper Shot", [V] Oct 15). The sim's core has a `heldByCast` state: "The swing came due during a cast that
   resets it and waits for the cast to end" (`sim/core/attack.go:350`) and a 0.5 s `RangedSwingWindup` (`constants.go:20-22`).
   Adding it needs care: `UI/Swing.lua:1961-1965` picks the **longest** data cast among the names, so adding Sniper Shot would
   widen every Hunter's idle clip mark from 2.0 s to 4.0 s, including Hunters who never learned it. It must be gated on known spells.
2. **Steady Shot never fires on Forever** (§3.6). Removing it is cosmetic.
3. **Volley holds Auto Shot.** [V] sim commit `47a16873` (2026-11-08), from two combat logs of a level 34-36 Beast Mastery
   Hunter: "No Auto Shot fired during 87 channels, and the next shot wound up 0.45 to 1.15 s after a channel ended, so the
   channel holds Auto Shot's windup while its swing timer runs." Implemented at `sim/hunter/volley.go` (`DelayRangedUntil`). The bar
   has no channel interlock. **[I]** `UNIT_SPELLCAST_CHANNEL_START`/`STOP` would supply it. Evidence is one
   character on two days at levels 34-36, not independently replicated.
4. **Dev-note wording.** "Your character will still fire Auto Shot while casting spells like Aimed Shot" reads as at odds with a clip model.
   The sim models the opposite: a due swing waits for the cast (`attack.go:350`). Blizzard's note is about the stand-still rule
   (a cast counts as standing still), not about clipping [I]. Leave the clip model as is.

### 4.3 Raptor Strike swing reset

See §3.2. In short: the reset is the replaced swing, SUCCEEDED probably arrives at the swing, and no live Raptor trace exists.

---

## 5. The Nov 10 "sturdier Hunter pets" hotfix

- **[V]** The plan: "adjust their stats as necessary", target "relatively the same as in Classic Era". No spell is named.
- **[D]** Pet durability is carried by `Hunter Pet Scaling` (415429), which has **no effect rows** in the store (the sim's own
  comment: "states every inherited stat without an amount, the server pricing them", `sim/hunter/pets.go`
  `makeStatInheritance`). The Great Stamina (4187-5049), Natural Armor (24545-24632), Pet Hardiness (6280-6286), Endurance
  Training (19583) and Pet Recovery (6328-6334) ladders are the tooltip-level pieces.
- **[I] None of our rows depends on pet stats.** The pet rows we track (Growl 5 s, Bite 10 s, Mine! 3/90, Dismember 6/15,
  Pinch, Tendon Rip, Web, Dust Cloud, Swipe, Thunderstomp, Scorpid Poison) are cooldown and duration rows. A stat retune should
  not move them. A hotfix could still touch pet ability numbers, and Blizzard did not say.
- **After the hotfix:** re-extract Hunter (`extract_store.py` against a clone pulled after push 113823) and re-run the DB2
  diff in §2 on the new build. Expect zero timing deltas. A non-zero delta on any id in §3.5's table is news.
  A pet-sheet change cannot be seen in static data. It needs an in-game read.

---

## 6. Evidence quality

| Claim group | Source | Sample / period | Look-ahead, leakage | Costs | Replicated? |
|---|---|---|---|---|---|
| Store values (cd, dur, cast, shared category) | pinned store 70790 / push 113715, DB2 70790 and 70862 | static game data | n/a | n/a | the two sources agree (4 tables, 833 ids) |
| Serpent Sting / Raptor Strike ladder choice | store rows + the sim's ladder choice + the hotfix's numbers | static | n/a | n/a | consistent across store, sim and hotfix text. No live cast checked |
| Official behaviour (traps, Hunter's Mark, Auto Shot stand-still) | Blizzard thread posts, fetched | notes through Nov 3 | n/a | n/a | primary source |
| Volley / shot rules | sim authors' two combat logs | L34-36, one BM Hunter, Nov 7-8 | out of sample for L60 | n/a | **not** independently replicated |
| Multi-Shot 0.5 s | one code comment, no source | - | - | - | **not** replicated; it contradicts the table |
| Heroic Strike trace | PR #39 (second-hand via the Nov 7 report) | one live frame | - | n/a | one author |
| "Aimed Shot 3.0 s live" | a test comment, uiforever | 2026-11-04 | - | n/a | contradicted by DB2 |

"Reported by the sim authors" is what the sim repo can give. "Replicated" would mean a second logger. I found none.

---

## 7. Implications for our setup

Ordered by effort:

1. **Pins and shares** (§9 lines 1-3) are JSON-only, except that the Multi-Shot ↔ Aimed share needs `shares = spell.shares`
   added to `Engine.lua:167`.
2. **Sting exclusivity** (code): add the three stings to a "one per target" rule next to `Casts.UNIQUE`.
3. **Trap eviction and the 4-way cooldown** (code): a `group` field in the data and a walk that handles N partners.
   Casting any trap should start the other three trap cooldown bars (a real 30 s shared cooldown, [V] Nov 3). Freezing /
   Frost should retire each other's armed-trap bars, and so should Immolation / Explosive.
4. **Swing sets**: add Sniper Shot (gated on known); drop Steady Shot; add a Volley channel interlock. Treat these as
   behaviour changes: each needs a probe first (§10).
5. **`isKnown` on a localized client** is fragile for any name whose data row is not the id the character knows. That includes
   Raptor Strike today. More broadly, it means any level-below-60 character whose rank is below the picked rank row, and
   Aspect of the Hawk once the book rank 25296 replaces 14322. `Locale.idsByEnglish` holds one id per name, not
   "every rank row" as its header says. This is a general bug, so not a Hunter-only task [D from `Locale.lua:41,254-257`].
6. **No data refresh is needed for Nov 10.** Re-run the §2 DB2 diff once the post-hotfix build exists.

---

## 8. Not proposed (and why)

- Pet signature abilities FX does not track (Savage Rend 60 s/18 s, Shell Shield 180 s/12 s, Furious Howl 30 s/60 s, Trickster's
  Dance 180 s/12 s, Demoralizing Screech 10 s/30 s, Dash and Dive 30 s/15 s, Charge 25 s): they pass the selection policy,
  but nobody has shown that a `pet` cast event carries a readable spell id on Forever. Name collisions (Charge) need a generator
  dry run first. Revisit after Q3.
- A Summon Hawk duration (the hawk lives 18 s, `SummonHawkTriggered` 1293248): the row has no `durationMs`. The data model
  has no field for "spawned pet window", so there is no JSON patch for it.
- Trap target-effect bars (Freezing 20 s etc.): unseeable in combat (§3.4).

---

## 9. Proposed patch (`tools/spell_lists/hunter.json`)

Names, not ids, except in `_pins`. Each line carries a confidence and its one-line reason.

```jsonc
// 1. HIGH. The castable ladder is 15 s; the picked 425xxx helper ladder is 12 s.
"_pins": {
  // ... existing three pins stay ...
  "Serpent Sting": {
    "id": 13555,
    "reason": "Rank 8 trainer row, 15000 ms / 3000 ms tick; the rank law lands on the BaseLevel-0 helper row 425737 (12000 ms, pre-hotfix 111/tick); the Nov 3 hotfix (dev notes post 9) retuned 13555/25295 (docs/research/live-hunter-2026-11-09.md §3.1)"
  },
  // 2. MEDIUM. Learnable ladder, ON_NEXT_SWING, GCD 0, and the id the known-gate can match.
  "Raptor Strike": {
    "id": 14266,
    "reason": "Rank 8 trainer row (attr0 0x40004 on-next-swing, GCD 0, cat 40 / 6000); the rank law picks the BaseLevel-0 ladder 415343 (GCD 1500, no next-swing bit), which no character knows (live-hunter-2026-11-09.md §3.2)"
  }
},

// 3. HIGH on the fact (store category 2, 6000 on both rows), but INERT until Engine.lua:167 copies `shares`.
"_shares": {
  "Summon Hawk": "Arcane Shot",
  "Multi-Shot": "Aimed Shot"
},

// 4. MEDIUM, low urgency. SoD rune leftovers: BaseLevel 0, in no sim ladder, rune-grant partners are Family 93.
//    REMOVE from "cooldowns": "Chimera Shot", "Flanking Strike", "Kill Shot", "Wyvern Strike"
//    REMOVE from "pet_and_utility": "Carve"
//    (expect Hunter test counts that pin the tracked-set size to move)

// 5. LOW-MEDIUM, optional. Volley is a real 6 s channel that holds Auto Shot (sim commit 47a16873).
//    The rank law would pick a value-less wave row (1279715), so it needs a pin.
//    ADD to "buffs": "Volley"
//    ADD to "_pins": "Volley": { "id": 14295, "reason": "Rank 3 cast row, DurationMs 6000, periodic dummy 1000 ms; the rank law would take the dur-0 wave row 1279715" }
```

Expected generated rows after 1 and 2 (from the store): `Serpent Sting` → `durationMs = 15000, tickEvery = 3,
castMs = -1000000, gcdMs = 1500, rank = "Rank 8"`; `Raptor Strike` → `cooldownMs = 6000, cooldownCategory = 40, rank = "Rank 8"`
(GCD 0 is omitted).

I did **not** run the generator (read-only task). Run `python3 tools/gen_spell_data.py hunter` after the edit and check those two rows.

---

## 10. Open questions (one probe each, on a live client)

1. **Multi-Shot cast time.** `/dump C_Spell.GetSpellInfo("Multi-Shot").castTime` and, while casting, `/dump UnitCastingInfo("player")`.
   Table says 0, the sim says 500 ms.
2. **Raptor Strike event order.** Log `UNIT_SPELLCAST_SENT/SUCCEEDED` and `PLAYER_SWING` timestamps for one queued Raptor
   Strike. Does SUCCEEDED fire at the press or at the swing?
3. **Pet casts.** Is `UNIT_SPELLCAST_SUCCEEDED("pet")` `spellID` readable in combat? FX registers `"pet"`
   (`Forte_Timer/Module.lua:788`). Nothing reports it.
4. **Serpent Sting duration on a real target.** After the pin: cast rank 8 or 9 on a dummy and time the debuff. 15 s expected.
5. **Does Volley stop Auto Shot** on the live client, and does `UNIT_SPELLCAST_CHANNEL_START` fire for it?
6. **Are Chimera / Kill / Flanking / Wyvern / Steady castable?** `IsPlayerSpell(409433)` etc. on a level-60 Hunter
   settles §3.6.
7. **Pet sheet after Nov 10.** The hotfix is stat-only and invisible in static data. Record health and armor of one level-60 pet
   before and after if the owner wants a number.
8. **Hunter's Mark single-target.** Is there a data flag, or only the owner's live observation (`Casts.lua:587-592`)?

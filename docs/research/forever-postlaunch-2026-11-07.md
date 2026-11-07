# WoW Forever post-launch research: hotfixes, addon-API reports, builds 70790/70840/70862

Researched and written 2026-11-07 (all pages fetched on 2026-11-07). Scope: launch (2026-11-04) to 2026-11-07.
Author: PostLaunchResearch (read-only research subagent). No repo files other than this one were touched.

**Labels used on every claim**

- **[V]**: verified. A verbatim quote or value from a page or file I fetched. The URL is next to it.
- **[D]**: derived. I computed it from fetched data, such as a diff of two fetched files or a DB2 export. The method is given.
- **[I]**: inference. My reading of what the evidence means for ForteXorcist (FX). Nobody has tested it.

Every URL below was fetched during this session. I added no links I did not open.

---

## 0. Bottom line for ForteXorcist (ranked)

1. **[D] The Rogue "Shank" data row probably has the wrong spell.** `addon/Forte_Rogue/Data/Rogue.lua:71/134` maps `"Shank"` to
   **15617**. In the client, 15617 (and 15248) is an old Shank: "Inflicts normal damage plus $s1 to an enemy when
   attacking from behind." It has no class family and no cooldown. The real Forever Shank is **1329283** (Rank 1) and
   **1329549** (Rank 2). Both are family 8 (Rogue), with RecoveryTime 10000 ms and GCD 1000 ms. The "Rank 1"/"Rank 2"
   subtext first appears in 70862, which matches Blizzard's Nov 6 hotfix line "Shank will now display Rank 1 and Rank 2
   in the tooltips" (§1.2, §1.6).
2. **[D] The Mage "Arcane Blast" cooldown row probably has the wrong spell.** `addon/Forte_Mage/Data/Mage.lua:80/154` maps
   `"Arcane Blast"` to **18091**, with `cooldownMs = 8000`. In the client, 18091 reads "Blasts a target for $s1 Arcane
   damage." That is the same text as the item-proc rows (`Forte_ItemProcs/Data/Procs.lua:108` uses 18091 as Archeus's
   proc). The mage's own Arcane Blast ranks are **400574 / 1239696 / 1239697 / 1239699 / 1239700** (Rank 1–5). All have
   CategoryRecoveryTime 0, so the spell has **no cooldown**. Its effect aura is **400573** with a duration of **18000 ms**.
   The client text for 400574 says the effect "lasts $400573d from time of initial application". **[I]** If cast-predict
   starts an 8 s timer on every Arcane Blast, the timer is wrong. The thing worth timing is the 18 s, non-refreshing 400573
   window. Blizzard's Nov 6 hotfix fixed that window on the server (§1.2).
3. **[V] Planned for Tuesday 2026-11-10:** Affliction changes to Siphon Life, Corruption, Bane of Agony and Wrack. All
   four are tracked in `warlock.json` `buffs`. Hunter pets and the Voidwalker will also get sturdier (§1.3). **[I]**
   Check the warlock DoT durations and tick intervals after the hotfix. `Forte_Timer/tests/test_data_feeds.lua:136`
   currently asserts that Corruption ticks every 3 s.
4. **[V] Author reports support the core FX design.** For **other players**, `UNIT_SPELLCAST_SUCCEEDED` returns a secret
   spellID and castGUID. For **your own** casts the spellID is readable, and several addons use it in combat. Aura reads
   return nil or are refused in combat, and `UNIT_COMBAT.amount` is always secret. `PLAYER_SWING` reaches addons on the
   live client (§2).
5. **[V] Swing-timer pitfall to avoid.** One author found that the player's `UNIT_SPELLCAST_SUCCEEDED` for spell 6603
   "Attack" fires on engage and retarget, not on each swing. The same author found `UnitAttackSpeed` hidden on 238 of
   238 reads. **[D]** FX's Hunter melee rail ignores 6603 and anchors on the `PLAYER_SWING` duration
   (`Forte_Hunter/Core/Melee.lua:269-296`), so it is not affected.
6. **[D] No addon-API change in any post-launch build.** The forever-branch UI diffs are 70790 (chat/BattleNet
   whisper), 70840 (shard-transfer toast, subscription UI) and 70862 (barbershop and gamepad). No combat, spell, aura or
   swing API changed (§3.2).
7. **[D] Correction for `docs/api/wow-addon-api-agents/SOURCE.md:21`.** That line says the 70790→70862 delta includes
   `C_ActionBar.IsHighestSpellRank` and "`UNIT_COMBAT.amount` now `SecretValue`". Both are already present in **70755**
   (`17ed2c3`) and in 70790 (`eac30af`). They are absent at 70707 (`aff0d8c`). The 70790→70862 compare contains neither
   (§3.2). I did not edit that file.
8. **[D] Risk for the next data regeneration.** Build 70840 added 395 SpellName rows. A few new NPC-style rows reuse
   tracked names **and** carry a class family. The largest risk is **Frost Armor 1283419**: family 3, RecoveryTime
   10000, duration 1800000. Two others are Blast Wave 1291176 (family 3) and Charge 1283073 (family 4) (§3.3). **[I]**
   If the generator's "CD-carrier rank pick" ever sees these rows, it could pick the NPC row. Re-check those three names
   in the generator output after the next upstream pull.

---

## 1. Blizzard official posts, 2026-11-04 → 2026-11-07

### 1.1 Index of blue posts in the window

Built from the Discourse search API (`@Kaivax after:2026-11-03`) on us/eu forums and from the per-thread JSON.

| UTC timestamp | Post | URL |
|---|---|---|
| 2026-11-04 18:13 | World of Warcraft: Forever Launch Time (no class content) | (search hit only, not fetched) |
| 2026-11-04 19:35 | Dev notes thread, post #10: "We've added this section…" (UI and Accessibility) | https://us.forums.blizzard.com/en/wow/t/2360696/10 (fetched as JSON) |
| 2026-11-05 02:43 | Issues Resolved for Invite-a-Friend Players (not class) | (search hit only) |
| 2026-11-05 15:42 (edited 22:07) | Known Issues – WoW Forever – Updated Nov. 5 | https://us.forums.blizzard.com/en/wow/t/2402363 (fetched as JSON) |
| 2026-11-06 02:34 | WoW: Forever Hotfixes thread (Nov 5 list) | https://us.forums.blizzard.com/en/wow/t/wow-forever-hotfixes-november-6-2026/2403040 |
| 2026-11-06 21:11 | Class Tuning Incoming – November 10 | https://us.forums.blizzard.com/en/wow/t/2404092/1 |
| 2026-11-07 01:07 | Same hotfix thread, post #4 adds the Nov 6 list; post #1 edited at 01:08 | https://us.forums.blizzard.com/en/wow/t/wow-forever-hotfixes-november-6-2026/2403040 |
| (news, "November 7th") | WoW: Forever Hotfixes – November 6, 2026 (news mirror of the same list) | https://worldofwarcraft.blizzard.com/en-us/news/24315281/wow-forever-hotfixes-november-6-2026 |

EU mirrors (same text, Kaivax): https://eu.forums.blizzard.com/en/wow/t/wow-forever-hotfixes-november-5-2026/639885. The
EU "Class Tuning Incoming – 10 November" (topic 640100, 2026-11-06 21:12) appeared only as a search hit and I did not
fetch it.

**[D]** For the hotfix thread I diffed post #1 against post #4 using the thread JSON. Post #4 (2026-11-07T01:07:59Z) is
the Nov 6 list without the Nov 5 section. Post #1 was edited at 01:08:16Z to hold both. Posts #2 and #3 are empty.

### 1.2 Hotfixes, November 6, 2026: every class, spell, talent and item line (verbatim)

Source **[V]**: https://worldofwarcraft.blizzard.com/en-us/news/24315281/wow-forever-hotfixes-november-6-2026 (byline
"November 7th by Blizzard Entertainment"). The same text is in forum thread 2403040, post #4.

> **Classes**
> - Fixed an issue with the Quick and the Dead Legacy Talent where it sometimes did not work as intended.
> - **Cooldown Manager**
>   - The Cooldown Manager will now correctly display the duration of crowd control spells at all times, even when diminishing returns or mechanic reductions (like orc stun reduction) are factors.
> - **Druid**
>   - Bloom will now correctly heal the target.
>   - Fixed a bug where the tooltip of Bear Form claimed an incorrect health value increase. The functionality was correct, but the wrong value was reported.
>   - The tooltip for Ravage reported an incorrect value for its damage, and the tooltip has been corrected. There was no change made to damage done.
>   - Fixed the tooltip for Swiftmend to no longer incorrectly mention consuming the effect.
> - **Mage**
>   - Fixed an issue where Mages were still learning the Research spell and then losing it upon relogging. This spell should not exist, and you should only have the Study spell after completing the relevant quest.
>   - Fixed an issue with Arcane Blast where its duration was not properly 18 seconds.
> - **Rogue**
>   - Shank will now display Rank 1 and Rank 2 in the tooltips.
>   - While Boot Knife is talented, Shank will now correctly display the number of Combo Points it grants.
> - **Warlock**
>   - Voidwalker base health increased by about 40 at all levels.
>   - The Soul Siphon talent no longer incorrectly causes Wrack to increase its own damage.
> - **Warrior**
>   - Fixed the tooltip for Reckless Swings to mention that it activates Gore Drinker.
>
> **Items**
> - Searing Dagger is now only activated by spells that have a damaging component.
>
> **Races**
> - **Night Elf** – Fixed a bug granting Shadowmelded Druids access to Ravage and Pounce.
> - **Orc** – Fixes an issue where some Warlock pet abilities were benefitting too much from the Orc Command racial ability.

The rest of the Nov 6 list covers dungeons, NPCs, professions (Tanning Rack 140→125), quests and world. It has no
class content.

### 1.3 Class Tuning Incoming – November 10 (planned, not yet live)

Source **[V]**: https://us.forums.blizzard.com/en/wow/t/2404092/1 (Kaivax, 2026-11-06T21:11:39Z; title "Class Tuning
Incoming - November 10")

> "…we're still investigating these issues and working through them with a plan to release hotfixes on Tuesday, November 10 to address:
> - We've seen that Hunter pets and Warlock Voidwalkers are not as durable as tanks as we would like them to be. Our intent is for their effectiveness to be relatively the same as in Classic Era. We will adjust their stats as necessary to accomplish this.
> - Affliction Warlock reports indicate that always channeling Wrack is superior to also casting damage-over-time abilities like Siphon Life, Corruption, and Bane of Agony. We will make adjustments to make sure those are always worthwhile to cast combined with Wrack, without affecting Affliction Warlocks' total damage output.
> - Enhancement Shamans are finding that Intellect and Spellpower are superior stats compared to Strength and Attack Power. We plan to make changes so that Strength is always their strongest stat…"
>
> "Our plan is to make class balance changes on Tuesday, and then on future Tuesdays if necessary."

Second-hand, not a blue post **[V]**: https://seramate.com/news/forever/2026/11/06/forever-shaman-talents-revisit-next-year-ccab8e0c
(2026-11-06, a mirror of the Wowhead news item). It quotes Kris Zierhut from a Crix interview: "I wouldn't be surprised
if early next year we revisit Shaman talents a little bit. It's not going to be sooner than that. It's going to be a
Patch." No spell data changes now.

### 1.4 Development notes addendum, 2026-11-04 (post #10)

Source **[V]**: https://us.forums.blizzard.com/en/wow/t/2360696/10 (Kaivax, 2026-11-04T19:35:16Z). This is the only
dev-notes post in the window.

> "User Interface and Accessibility
> - Swing Timer bar will no longer fade out due to distance until the swing finishes.
> - … Fixed an issue where Nameplates did not display Elite enemy status.
> - Debuff icons on the Nameplate can now be clicked through. …"

It contains no spell or talent changes. The swing-timer line concerns Blizzard's own frame, not the API.

### 1.5 Known Issues – Updated Nov. 5

Source **[V]**: https://us.forums.blizzard.com/en/wow/t/2402363 (Kaivax, created 2026-11-05T15:42Z, edited 22:07Z).
It lists Dungeons (the Razorfen Kraul cauldron), Gamepad (2), NPCs (PvP vendors unavailable, a Stormwind guard text),
Quests ("Vorsha the Lasher" disabled, fixed in the Nov 6 list), UI ("Bank pages are displaying in pages, causing the
tabs to be listed outside the frame.") and World (the Stormwind Keep entrance). **There are no class, spell or addon-API
entries.**

The Nov 5 hotfixes **[V]** (same thread / news page) contain no class or spell changes. The PvP section reads: "Plainsrunning can no longer
stack and stacks will be cancelled when carrying a flag in a battleground." Plainsrunning is a Tauren racial and is not
tracked by FX.

### 1.6 Cross-check of every class or item line against `tools/spell_lists/*.json`

Method **[D]**: I walked all nine JSON files (all keys including `_deferred_H7` and `_renames`) and did a case-insensitive
substring match. I then grepped `addon/` for generated IDs. The client columns come from the wago.tools DB2 CSV exports
(SpellName, Spell, SpellCooldowns, SpellMisc, SpellDuration, SpellClassOptions) for build 1.60.1.70862, e.g.
https://wago.tools/db2/SpellName/csv?build=1.60.1.70862.

| Hotfix line | Tracked by FX? | Touches us? |
|---|---|---|
| Quick and the Dead (Legacy) | no | no |
| Cooldown Manager CC duration | n/a (FX doesn't use CDM, `docs/why-not-blizzard-cdm.md`) | **[I]** No code impact. The CDM can now show CC durations with diminishing returns applied. FX cannot do that without combat-log data, so expect a visible difference on CC durations if players compare the two. |
| Bloom heals | `druid.json` buffs → `Bloom = 1328621` | heal fix only. No timing data. |
| Bear Form tooltip | `druid.json` forms → `Bear Form = 5487` | tooltip only |
| Ravage tooltip | no | no |
| Swiftmend tooltip | `druid.json` cooldowns → `18562` | tooltip only |
| Research / Study | no | no |
| **Arcane Blast 18 s duration** | `mage.json` cooldowns → **18091** (`cooldownMs = 8000`) | **YES.** See §0 item 2. **[D]** In the client, 400573 is 18000 ms in 70790, 70840 and 70862 alike, so the fix was server-side. 18091 is the 8 s item-style row. |
| **Shank Rank 1/2 tooltip; Boot Knife CP** | `rogue.json` cooldowns → **15617** | **YES.** See §0 item 1. **[D]** The 1329283/1329549 subtext is empty in 70790 and 70840 and reads "Rank 1"/"Rank 2" in 70862. Cooldown 10000 ms in all three. |
| Voidwalker +40 health | `warlock.json` demonic-utility → `Summon Voidwalker = 697` | no timing impact |
| Soul Siphon / Wrack self-buff | `warlock.json` buffs → `Wrack = 1316697` | damage only |
| Reckless Swings tooltip / Gore Drinker | `warrior.json` `_deferred_H7` has Reckless Swings; Gore Drinker not tracked | tooltip only |
| Searing Dagger trigger | not in spell_lists, but in `Forte_ItemProcs/Data/Procs.lua:369` (item 273003, buff "Sear") | **[I]** Low. The proc now fires less often (only from damaging spells). No data change is needed. |
| Shadowmeld → Ravage/Pounce | Pounce in `druid.json` buffs | exploit removal only |
| Orc Command / warlock pets | no | no |
| (Nov 10 plan) Siphon Life, Corruption, Bane of Agony, Wrack | all in `warlock.json` buffs (`18881`, `1223963`, `11713`, `1316697`) | **YES if durations or ticks change.** Re-check after 11-10 (§0 item 3). |
| (Nov 10 plan) Hunter pets, Voidwalker stats | pet heal/revive spells in `hunter.json` pet_and_utility | stats only, so probably no timing impact **[I]** |
| (Nov 10 plan) Enhancement Strength vs Int | none of the shaman entries name a stat talent | **[I]** probably no impact |

One related row the hotfix notes do not mention **[D]**: Gouge **1324481** (no class family; a description that redirects
to the rank-specific Gouge text) gained a cooldown row (RecoveryTime 0, CategoryRecoveryTime 10000, GCD 1000) between
70840 and 70862. FX's `Gouge = 11286` (Rank 5) is unchanged. **[I]** If the live client reports 1324481 in
`UNIT_SPELLCAST_SUCCEEDED`, then `Locale.RankIDsForName("Gouge")` must resolve it. Check this with the first in-game
probe.

---

## 2. Addon-author reports since launch (GitHub, Blizzard forums)

Search method **[D]**: GitHub issue/PR search via `gh api search/issues` with `created:>=2026-11-04` and the terms
secret, RegisterUnitEvent, swing, taint, 16001, PLAYER_SWING, C_SwingTimer, CooldownViewer, UnitAttackSpeed,
UNIT_SPELLCAST_SUCCEEDED, surname/UnitName, C_UnitAuras, GetSpellCooldown, ADDON_ACTION_FORBIDDEN. I also ran Discourse
searches on us/eu forums. I did a web search for Reddit (r/classicwow, r/wowaddons) but found no post-launch addon-API
threads. I did not reach CurseForge or WoWInterface discussions (see §5).

### 2.1 Combat log is gone for addons

- **[V]** RankSentinel PR #116 (gnummers, 2026-11-06), comment of 2026-11-07T00:16Z: "On WoW Forever (build 16001,
  `WOW_PROJECT_ID` 18) the combat log is not available to addons. `CombatLogGetCurrentEventInfo` is `nil`, and
  registering the event is a protected call (it raises `ADDON_ACTION_FORBIDDEN`)." https://github.com/valkyrnstudios/RankSentinel/pull/116
- **[V]** Soundboard PR #22 (2026-11-07): "patch 12.0 removed addon access to `COMBAT_LOG_EVENT_UNFILTERED`, so
  `RegisterEvent` for it raises `ADDON_ACTION_FORBIDDEN`. The popup is driven by that event, not the Lua error, so the
  `pcall` guard … [was] a misdiagnosis". https://github.com/heyaapl/Soundboard/pull/22
- **[V]** CrusaderStrike PR #16 (2026-11-05): "`CombatLogGetCurrentEventInfo` missing … `DungeonLog.lua` no longer
  depends on CLEU `UNIT_DIED`". It uses `ENCOUNTER_END` and `BOSS_KILL` instead. https://github.com/CrusaderStrike/addon/pull/16
- **For FX:** this confirms the AGENTS.md ban on combat-log designs. **[I]** The Soundboard finding matters: wrapping
  the registration in `pcall` does **not** stop the blocked-action popup. FX already never registers CLEU, so the
  takeaway is to keep it that way, even inside a pcall-guarded probe.

### 2.2 Secret values: casts, auras, power, cooldowns, amounts

- **Other players' casts are secret; your own are readable.** **[V]** RankSentinel PR #116: "**Own casts:** detected
  through `UNIT_SPELLCAST_SUCCEEDED`, where the spell ID is readable. **Other group members' casts:**
  `UNIT_SPELLCAST_SUCCEEDED` gives `spellID=<secret>` for other players… the buff's spell ID and `sourceUnit` stay
  readable [in `UNIT_AURA`]". The comment adds: "for another player's cast, `UNIT_SPELLCAST_SUCCEEDED` gives `spellID`
  and `castGUID` as secrets… I confirmed both in game."
  - Supporting evidence **[V]**: LoremCooldownTracker PR #4 (2026-11-07): "Spells cast during combat that were not
    registered during initial scan are now dynamically detected and registered on `UNIT_SPELLCAST_SUCCEEDED`."
    https://github.com/JulianNorton/LoremCooldownTracker/pull/4. MaxDps-Rogue issue #19 (2026-11-06): the author's patch
    tracks "SnD state … via `UNIT_SPELLCAST_SUCCEEDED` since aura reads return nil here".
    https://github.com/kaminaris/MaxDps-Rogue/issues/19
  - **For FX [I]:** this is the strongest outside support so far for cast-predict + reconcile (PLAN §3.2). FX's own
    `UNIT_SPELLCAST_SUCCEEDED("player")` is the right source. No report says whether the **`pet`** unit's spellID is
    readable. FX registers `"player","pet"` (`Forte_Timer/Module.lua:788`), so this should be checked live. The
    existing resolver already turns a secret value into nil.
  - Workaround for other players **[V]**: RankSentinel reads `C_DamageMeter`, which "lists each group member's
    damage/healing spells with **readable spell IDs**". The author verified this in game and polls every 15 s. **[I]**
    Not useful for FX timers (too much lag, no timing), but worth knowing.
- **Aura data during restrictions.** **[V]** gryphonFrames PR #9 (2026-11-05): "power values and aura data are secret
  during addon restrictions such as combat … when the client refuses to list auras, the row stays as it is until the
  restriction ends." https://github.com/Clausi/gryphonFrames/pull/9. **[V]** Pretty-Wide-Quest-Log issue #23
  (2026-11-06): "`GetAuraDataByIndex(): Auras cannot be accessed when secret while tainted by 'Pretty-Wide-Quest-Log'`".
  The error came from Blizzard's own `Blizzard_MawBuffs` after the addon had tainted the tracker path.
  https://github.com/Gogo1951/Pretty-Wide-Quest-Log/issues/23
  - **For FX [I]:** this matches the AGENTS.md rule that a secret read never overwrites known state. The PWQL case
    adds a taint warning: if FX hooks or calls Blizzard UI paths (objective tracker, quest UI), Blizzard's later
    aura reads on that path fail. FX should not touch those frames.
- **Power.** **[V]** gryphonFrames PR #10 (2026-11-05): "Power is secret in combat on Forever, so the rule now starts
  from `UNIT_SPELLCAST_SUCCEEDED` plus a mana cost from `C_Spell.GetSpellPowerCost`". https://github.com/Clausi/gryphonFrames/pull/10.
  **[V]** MaxDps-Rogue issue #19: "`MaxDps.Power("energy", false)` returns `math.huge` via SecretHelper".
  - **For FX [I]:** any FX feature gated on power (e.g. `Forte_Warlock/Core/Tools.lua` listening to
    `UNIT_POWER_UPDATE`) must treat power as unknown in combat.
- **Cooldowns.** **[V]** LoremCooldownTracker PR #4: "Handled restricted combat return values in
  `C_Spell.GetSpellCooldown` and `C_Container.GetContainerItemCooldown`, falling back to duration objects when
  necessary." Another report **[V]**: EasyControllerWowForever issue #19 (2026-11-05) says that replacement buttons "never
  show a cooldown" until they use `SetCooldownFromDurationObject`. https://github.com/moust4ki/EasyControllerWowForever/issues/19
  - **For FX [I]:** this matches `Compat.PlainOrNil` around cooldown reads. Duration objects, which are drawable
    without reading the numbers, could serve as a display fallback for a running cooldown swipe.
- **UNIT_COMBAT.** **[V]** forever-addons PR #18 (2026-11-05): "**UNIT_COMBAT's `amount` is always secret on Forever**,
  in and out of combat. The other fields are readable … **Heals report school 1 (Physical)** whatever the spell's
  school". https://github.com/ljukas/forever-addons/pull/18. **[D]** This matches `UnitDocumentation.lua` on the forever
  branch at 70790 and 70862, which has `{ Name = "amount", … SecretValue = true }` on `UNIT_COMBAT`.
- **PARTY_KILL.** **[V]** dgks PR #6 (2026-11-07): "`events:PARTY_KILL` is sometimes called with the attacker and target
  GUIDs as secret values". https://github.com/linman0x90/dgks/pull/6. **[I]** FX does not use it.
- **Secret strings break ordinary string code.** **[V]** AllTheThings issue #2738 (2026-11-06): "An attempt to index
  a secret value was blocked because of taint from AllTheThings … `toLowerString` does `tostring(value):lower()`".
  https://github.com/ATTWoWAddon/AllTheThings/issues/2738. **[V]** Details issue #1143 (2026-11-05):
  "`source.specIconID` from the Blizzard damage meter comes back as a secret number on Forever", used as a table key.
  https://github.com/Tercioo/Details-Damage-Meter/issues/1143. Details issue #1145 shows arithmetic on a secret number
  in a resize path. https://github.com/Tercioo/Details-Damage-Meter/issues/1145
  - **For FX [I]:** `tostring()`, `:lower()`, table indexing and arithmetic on any value that might be secret all fail.
    This includes **names** (see §2.4). Locale or name code that lower-cases or keys on a unit name must go through
    `PlainOrNil` first.

### 2.3 RegisterUnitEvent behaviour

- **[V]** Everloot issue #799 (2026-11-06): with `UNIT_SPELLCAST_*` "registered with `RegisterEvent` … they fire for
  every unit"; the fix is "`RegisterUnitEvent(event, "player")` on a small dedicated frame". https://github.com/Everloot/everloot/issues/799
- No external report covers the replace-on-second-call behaviour. FX's own live finding of 2026-11-06 is recorded in
  `Forte_Timer/Module.lua:784-790`: a second `RegisterUnitEvent` for the same event replaces the first unit set, and
  `UNIT_DIED` as a unit event raises an error. **[I]** That is consistent with retail semantics. I found nothing
  post-launch that contradicts it.

### 2.4 Unit identity: first name + surname

- **[V]** polestar PR #1019 (2026-11-06): "`UnitName(unit)` gives a party member as `("Ana", "Smith")`: the second
  return is the **surname**, where other clients give the realm (Forever's FrameXML,
  `Blizzard_FrameXMLUtil/Camelot/NameUtil.lua`: `local name, surname = UnitName(unit)`). The player's own name comes
  either split the same way or whole (`"Ana Smith"`); `UnitNameUnmodified("player")` splits it." https://github.com/fitzforge/polestar/pull/1019
- **[V]** I checked this in the source: `Interface/AddOns/Blizzard_FrameXMLUtil/Camelot/NameUtil.lua` at forever 70862
  (`9dc84f0`) has `NameUtil.FormatUnitNameForDisplay(unit)` → `local name, surname = UnitName(unit)` and
  `NameUtil.IsPlayerMe` → `UnitNameUnmodified("player")`.
  https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_FrameXMLUtil/Camelot/NameUtil.lua
- **[V]** AskAzeroth PR #141 (2026-11-05; "findings confirmed in-game on live Forever 2026-11-05"): "`UnitFullName` =
  `"Phenom Shira", ""` … `GetNormalizedRealmName()` still returns a realm". https://github.com/PhenomDevel/AskAzeroth/pull/141
- **[V]** RankSentinel PR #116: "`UnitName()` returns only the first, so whispers failed … now comes from
  `GetPlayerInfoByGUID`".
- **For FX [I]:** these reports agree with `Forte_Core/Core/Identity.lua` (lines 38-41 and 173-183): UnitName gives
  (first, SURNAME) and UnitFullName gives (full name, …). Nothing new is needed. One case to keep covered: the
  **player's** own `UnitFullName` returns `"First Surname", ""` (empty second return), while group members come back
  split.

### 2.5 CooldownViewer (Blizzard Cooldown Manager)

- **[V]** Hotfix (§1.2): CDM now shows CC durations with DR and mechanic reductions applied.
- **[V]** Player report, EU forums, 2026-11-06: "The Cooldown Manager is not working properly. I play Paladin and at
  least I cannot track seals. I can add the seals to the trackable section but those are not shown in actual use."
  https://eu.forums.blizzard.com/en/wow/t/639910 (fetched as JSON)
- I found no GitHub issue from an addon author about the `C_CooldownViewer` API since launch. Two PRs only mention it
  in a list (KstyleUI #13, WowVision #101). Neither was fetched.
- **For FX [I]:** this is more evidence for `docs/why-not-blizzard-cdm.md`. Blizzard's own viewer has gaps (seals) and
  still needs server fixes.

### 2.6 Swing timer API (`C_SwingTimer` / `PLAYER_SWING`)

- **[V] API (source).** `Blizzard_APIDocumentationGenerated/SwingTimerDocumentation.lua` at forever 70862 declares
  namespace `C_SwingTimer` with `EnableRangeCheck(swingType, enable)` and `IsTargetWithinSwingRange(swingType)` →
  `isInRange` ("Nil must not be treated as out of range."). It also declares the events `PLAYER_SWING` (`swingDuration`,
  `swingType`, `SynchronousEvent = true`) and `PLAYER_SWING_RANGE_UPDATE` (`swingType`, `isInRange`, `checksRange`), and
  `PlayerSwingType` MainHand=0/OffHand=1/Ranged=2. No `SecretValue` flag is on the payload fields.
  https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/SwingTimerDocumentation.lua
- **[V] Live evidence that PLAYER_SWING reaches addons.** nameplatesct-reforged PR #39 (2026-11-06) records a live
  Warrior frame: "`UNIT_SPELLCAST_SUCCEEDED  Heroic Strike` / `WOUND <secret> Empty Report` / `PLAYER_SWING` / `Log Line
  direct` / `WOUND <secret> real Hit`". It says it was checked "In game". https://github.com/dbspringer/nameplatesct-reforged/pull/39
- **[V] The "Attack" cast is not a swing.** hogtron-ui PR #159 (2026-11-06): "Forever's `UNIT_SPELLCAST_SUCCEEDED` 6603
  "Attack" fires on **engage / retarget** (174 of them against 109 engages and hundreds of swings) … `UnitAttackSpeed`
  is hidden on every read (238/238), so the period stayed at the 2.0 default in a 2.5 s form."
  https://github.com/Hogtron-Solutions-Tech-Stack/hogtron-ui/pull/159
- Other users of PLAYER_SWING, none verified live:
  - **[V]** HunterSuite 4.0 PR #1 (2026-11-05) says "the swing timer is native (`C_SwingTimer` / `PLAYER_SWING`)" and
    builds an Auto Shot timer on it. It also states "Not yet verified in the live client".
    https://github.com/sniffingpickles/HunterSuite/pull/1
  - **[V]** flat-ui PR #3 (Auto Shot ring from `PLAYER_SWING`, ranged; "Not checked in game").
    https://github.com/dismlx/flat-ui/pull/3
  - **[V]** KstyleUI PR #54 (a swing timer "from `PLAYER_SWING`"; it hides Blizzard's `SwingTimer*Frame`s with a
    `SetAlpha` hook "instead of reparented").
    https://github.com/korallis/KstyleUI/pull/54
- **[V] Interaction with Blizzard's bar.** Matts-Action-Bar-Fonts issue #1 (2026-11-05): "Blizzard's ranged swing timer
  (SwingTimerRangedFrame) shows on screen while MABF is loaded, even with Blizzard's swing timer disabled
  (showSwingTimer = 0)". https://github.com/seathasky/Matts-Action-Bar-Fonts/issues/1
- **For FX [I]:**
  1. The Hunter swing design (`Forte_Hunter/Core/Melee.lua`, `Swing.lua`, `Range.lua`) uses PLAYER_SWING with duration
     first, UnitAttackSpeed via PlainOrNil as a fallback, and IsTargetWithinSwingRange plus the range-update event.
     This matches the declared API. The live Heroic Strike trace and the hogtron findings remove most of the
     "launch-day caveat" in Melee.lua's header. PLAYER_SWING does fire, and the payload duration should be treated as
     the only speed source, because UnitAttackSpeed is secret.
  2. **Do not** treat spell 6603 "Attack" as a swing or a re-arm signal. FX currently does not (`grep 6603` in
     Forte_Hunter: no hits). Keep it that way in any new melee code.
  3. If FX hides or restyles Blizzard's swing frames, follow KstyleUI's approach and **don't reparent** them. Their
     container reparents them on every layout pass.
- Unrelated hit: SuperCleveRoidMacros issue #11 mentions `PLAYER_SWING`, but it concerns ClassicAPI on another client,
  not Forever. I excluded it.

### 2.7 Taint and restricted actions

- **[V]** RankSentinel (above): registering CLEU is a protected call.
- **[V]** PWQL issue #23 and ATT issue #2738 (above): taint from an addon makes later Blizzard secret reads fail.
- **[V]** Search hits for `ADDON_ACTION_FORBIDDEN` since launch are mostly guild invites, guild notes, bank purchases
  and player-menu actions (guildos issues #256 and #259, Embolsao PR #18). These are non-combat UI actions; titles were
  read from the search result only.
- **[V]** Matts-Action-Bar-Fonts issue #1: when the addon is loaded, Blizzard's UI checkboxes show no checked state.
- **For FX [I]:** the main rule is "no hooks or secure calls on Blizzard frames". FX's `Forte_Core` single-bootstrap-frame
  rule and its avoidance of CDM already lower the risk.

### 2.8 Other client facts reported since launch

- **[V]** MaxDps-Rogue issue #19: "WoW "Forever" client (WOW_PROJECT_ID 18 / Camelot), Interface 16001". This agrees
  with AGENTS.md (`WOW_PROJECT_CAMELOT`) and with RankSentinel. An older beta-era note (2026-09-21,
  https://raw.githubusercontent.com/realworldbuilder/wowwrapped/main/docs/addon-api.md) claimed `WOW_PROJECT_ID` 1. It is
  out of date.
- **[V]** MaxDps-Rogue issue #19: "This client's `C_Spell.IsSpellUsable` returns true for never-learned spells queried
  by raw ID … Gating every line with `IsPlayerSpell(spellId)` (pcall-wrapped) fixed it." **[I]** This implies the
  legacy `IsPlayerSpell` global exists and works on live, which is the first link in FX's `Compat.IsPlayerSpell`
  chain. FX should never use `IsSpellUsable` as a "known" test.
- **[V]** MaxDps-Rogue issue #19, comment of 2026-11-06T14:43Z: the stubs still ship stale IDs. "`2098` for Eviscerate
  (real id on this client: 6760), `1752` for Sinister Strike (real: 1758)". They resolve through
  `C_Spell.GetSpellInfo(name).spellID`. **[I]** This is the same kind of ID problem as §0 items 1 and 2.
- **[V]** RankSentinel PR #116: "`C_Spell.GetSpellLink` on Forever already includes the rank in the link text, which
  produced "(Rank 1) (Rank 1)"." **[I]** Relevant if FX ever adds the rank to messages (Forte_Messages).
- **[V]** MaxDps-Rogue issue #19, comment: "every Forever character dispatches to spec 1 because C_SpecializationInfo
  returns a default on this tree-based client". **[I]** FX must not infer spec from C_SpecializationInfo.
- **[V]** OneForAll_Forever issue #35 (2026-11-05): a buff reminder said Mark of the Wild had run out while a
  **higher rank from another player** was active. https://github.com/smoergi/OneForAll_Forever/issues/35. **[I]** This
  is the rank problem again. FX buff checks must match all ranks (`RankIDsForName`), not one ID.
- **[V]** cjber/tweaks-forever issue #301 (2026-11-04): "WeakAuras has no 1.60.1 build" and "a tracked aura and
  cooldown list … is the biggest genuine gap in the ecosystem". https://github.com/cjber/tweaks-forever/issues/301
  **[I]** This is the gap FX fills.

---

## 3. Build history: 70790 / 70840 / 70862

### 3.1 Build timeline

**[V]** wago.tools builds API (`https://wago.tools/api/builds`, key `wowf`), fetched 2026-11-07:

| version | wago `created_at` | build_config |
|---|---|---|
| 1.60.1.70753 | 2026-11-02 21:35:11 | 6f9eae52… |
| 1.60.1.70755 | 2026-11-03 18:16:08 | 9d9888f2… |
| 1.60.1.70790 | 2026-11-04 18:08:09 | 9006ba69… |
| 1.60.1.70840 | 2026-11-07 02:28:07 | 6ca8f0e6… |
| 1.60.1.70862 | 2026-11-07 04:43:07 | 5ada9542… |

**[V]** Gethe/wow-ui-source branch `forever` commits (`gh api repos/Gethe/wow-ui-source/commits?sha=forever`):

| commit | committer date (UTC) | message |
|---|---|---|
| `9dc84f0d3bba` | 2026-11-07T04:46:13Z | 1.60.1 (70862) |
| `5987a8e2304c` | 2026-11-06T23:31:24Z | 1.60.1 (70840) |
| `eac30af597e5` | 2026-11-04T18:16:22Z | 1.60.1 (70790) |
| `17ed2c3e8471` | 2026-11-03T18:32:09Z | 1.60.1 (70755) |
| `aff0d8cd53bf` | 2026-11-02T13:15:56Z | 1.60.1 (70707) |

Gethe's 70840 commit time (11-06 23:31Z) is earlier than wago's `created_at` (11-07 02:28). The wago timestamp's time zone
is not stated. Community trackers date 70840 to Nov 6 (§3.4).

### 3.2 UI-source diffs (Gethe compares)

**[V]** From `gh api repos/Gethe/wow-ui-source/compare/<a>...<b>`:

- **70755 → 70790**
  (https://github.com/Gethe/wow-ui-source/compare/17ed2c3e8471cdc3806ab0d26a082be7c67d3d7c...eac30af597e5aaa43a60f6675ef5fdcea100375f):
  5 files, +49 / −11. `BattleNetDocumentation.lua` adds `C_BattleNet.GetDefaultTitleWhisperTarget` (SecretArguments
  `AllowedWhenUntainted`). `ChatFrameEditBox.lua` and `ChatFrameUtil.lua` add whispers to "title friends".
  `UnitPopupButtons.lua` drops 6 lines. Also `version.txt`.
- **70790 → 70840**
  (https://github.com/Gethe/wow-ui-source/compare/eac30af597e5aaa43a60f6675ef5fdcea100375f...5987a8e2304c1331346dc861d5ccacf4c510cf0f):
  5 files, +48 / −10. `CharacterSelect.lua` and `SubscriptionInterstitialUI.lua/.xml` (gamepad and glue handling).
  `SocialToast.lua`: shard-transfer toasts (`SHARD_TRANSFER_IMMINENT`, `GetEvictionTimeRemaining()`), so the toast
  shows at once if a transfer is already scheduled. **[I]** This is likely layering-related.
- **70840 → 70862**
  (https://github.com/Gethe/wow-ui-source/compare/5987a8e2304c1331346dc861d5ccacf4c510cf0f...9dc84f0d3bbae1768ac3405b3716000bd93eda06):
  5 files, +32 / −7. `Blizzard_BarberShopUI.lua/.xml`, `FrameControlsManager.lua` and `SmartNavigation.lua`
  (gamepad focus and navigation).
- **[D]** There are no changes to Spell, Aura, Cooldown, SwingTimer, Unit, CombatLog or Secret* API documentation in any of
  the three post-launch builds. The single compare `eac30af...9dc84f0` (2 commits ahead) lists only the files above.
- **[D] Correction of `docs/api/wow-addon-api-agents/SOURCE.md:21`.** I fetched
  `ActionBarFrameDocumentation.lua` and `UnitDocumentation.lua` at four commits. `IsHighestSpellRank` and the
  `UNIT_COMBAT` `amount … SecretValue = true` flag are **absent at 70707 (`aff0d8c`) and present at 70755 (`17ed2c3`),
  70790 and 70862.** They are pre-launch changes, not part of the 70790→70862 delta.

### 3.3 Client game-data deltas (wago.tools DB2 CSV exports)

Method **[D]**: I downloaded `https://wago.tools/db2/<Table>/csv?build=<version>` for SpellName, SpellCooldowns,
SpellMisc and SpellDuration at 70790, 70840 and 70862. I downloaded Spell (NameSubtext/Description) at 70790, 70840
and 70862, and SpellClassOptions at 70862. I then compared them for every row whose name matches a name in
`tools/spell_lists/*.json` (4,000 rows). Caveat: these are the exported client tables. I did not confirm whether
wago applies the server hotfix cache in these exports, so server-only hotfixes (§1.2) may not show.

- Row counts: SpellName 32,087 → **32,482** → 32,482. SpellCooldowns 4,512 → 4,541 → 4,542. SpellMisc 31,956 →
  32,350 → 32,350.
- **70790 → 70840:** +395 SpellName rows, 0 removed, 1 renamed (1327245 "Thunderclap" → "Warstomp"; no class family).
  The new rows are mostly NPC-looking: "Dummy" ×13, "Arcane Marker" ×9, Deluge, Summon Infernal ×4, "Portal to
  Auberdine/Southshore/Theramore/…", and so on. 30 of them reuse a tracked name. Three of those carry a **class family**:
  Frost Armor 1283419 (family 3; RecoveryTime 10000; duration 1800000), Blast Wave 1291176 (family 3; duration 2000) and
  Charge 1283073 (family 4). Their descriptions are generic NPC text ("Encases the caster in a layer of frost…",
  "Charges an enemy, inflicting normal damage plus $s3."). FX currently uses Frost Armor 7301, Blast Wave 13021 and
  Charge 27685, so nothing changed for FX. See §0 item 8 for the regeneration risk. Cooldown and duration values of
  existing tracked rows did not change.
- **70840 → 70862:** SpellName is identical. The only tracked-name cooldown/duration change is **Gouge 1324481**, which
  gained a cooldown row (0 / 10000 / 1000). The Spell table gained the Shank "Rank 1"/"Rank 2" subtext on 1329283/1329549.
- **Spell rows behind §0 items 1 and 2** (70862):
  - Shank: 15248 and 15617 ("Inflicts normal damage plus $s1 to an enemy when attacking from behind.", no family, no
    cooldown). 1329283 (Rank 1) and 1329549 (Rank 2) ("Instantly strike with your off-hand weapon, dealing $s1% weapon
    damage…", family 8, RecoveryTime 10000, GCD 1000).
  - Arcane Blast: 18091 and 16067 ("Blasts a target for $s1 Arcane damage.", family 3, CategoryRecoveryTime 8000). 400574
    Rank 1 and 1239696/7/9 and 1239700 Ranks 2–5 (family 3, CategoryRecoveryTime 0, GCD 1500). 400573 (the aura, duration
    index 85 = 18000 ms in all three builds). 400586, 1300176 and 1300177 (8000 ms variants of the older TBC-style
    text). `Forte_Timer/Core/Registry.lua:206` names the self-debuff `AddSelfDebuff(36032)`, but **36032 does not exist in
    the Forever Spell table**. Its pattern `^Arcane Blast` still matches by name.

### 3.4 What community trackers say changed per build

These are second-hand. I list them where they add detail, along with where they disagree.

- **ForeverChanges** (https://foreverchanges.pro/patch-notes, feed https://foreverchanges.pro/patch-notes/feed.xml,
  fetched 2026-11-07):
  - **[V]** 70790 (Nov 4): "The launch client … It writes the November 3 hotfixes into the client files: the class
    changes of Blizzard's launch notes now read from the client in every language. Items did not change."
  - **[V]** "Hotfix, November 4": "Defiance and Defensive Stance now read as the notes say. Chain Lightning keeps the
    client's 2.5 sec cast: the launch realms do not send the 2 sec of the notes."
  - **[V]** "Hotfix, November 6": "In the client it fixes three tooltips: Gore Drinker now names Reckless Swings, Bear
    Form gives the Health of Classic, and Ravage shows its real bonus damage."
  - **[V]** 70862 (Nov 7): "Blizzard has posted no notes for it. The Adventurer's Tent is a rested tent again, Rock on
    Stick and Bigger Rock on Bigger Stick read their bleed, four quest items get a Use line, and the client now holds
    five of the new dungeons with their encounters." Its Hunter line: "Great Stamina: Its tooltip at ranks 9 and 10
    says Health increased by 32 and 40 instead of Stamina … Not in Blizzard's notes, found in the game." Its Ravage
    line: "Now reads 435% weapon damage plus 42, 62, 78 and 98 by rank, instead of plus 147, 217, 273 and 343."
  - ForeverChanges does not list 70840 as its own build.
- **wowforever.news** (https://wowforever.news/changes.html, fetched 2026-11-07):
  - **[V]** "From Blizzard: 7 Nov 2026 · Build 1.60.1.70862 · 41 changes". "From Blizzard: 6 Nov 2026 · Build
    1.60.1.70840 · 15 changes". "From Blizzard: 4 Nov 2026 · Build 1.60.1.70790 · 109 changes".
  - **[V]** Data mined from 70840: Great Stamina rank 10 "Now: Health increased by 40. Was: Stamina increased by 40";
    Defensive Stance "(30% -> 80%)"; Defiance "(15% -> 20%)".
  - **[V]** Data mined from 70862: "Shank: Now 2 ranks, was 1 … generating 25 Energy" (rank 2); Ravage "Rank 4 … 435%
    damage plus 426 … (343 -> 426)"; Bear Form "(180 -> 560)"; Gore Drinker now lists Reckless Swings.
- **Disagreements [D]:**
  1. The two sites give Ravage's new bonus as rank 4 "+98" (ForeverChanges) versus "+426" (wowforever.news). Neither is
     tracked by FX, so this is unresolved and not worth pursuing.
  2. Defensive Stance and Defiance are placed in the Nov 4 hotfix cache by ForeverChanges and in 70840 by
     wowforever.news. Great Stamina is placed in 70862 versus 70840.
  3. The Shank rank finding agrees with my DB2 check: the subtext appears in 70862 and is absent in 70840.

---

## 4. Sources fetched (all accessed 2026-11-07)

Blizzard (official):
- https://worldofwarcraft.blizzard.com/en-us/news/24315281/wow-forever-hotfixes-november-6-2026
- https://us.forums.blizzard.com/en/wow/t/wow-forever-hotfixes-november-6-2026/2403040 (and `.json`, posts 1–4)
- https://eu.forums.blizzard.com/en/wow/t/wow-forever-hotfixes-november-5-2026/639885
- https://us.forums.blizzard.com/en/wow/t/2404092/1 (Class Tuning Incoming – November 10)
- https://us.forums.blizzard.com/en/wow/t/2360696/10.json (dev notes post #10, 2026-11-04)
- https://us.forums.blizzard.com/en/wow/t/2402363/1.json (Known Issues – Updated Nov. 5)
- https://us.forums.blizzard.com/en/wow/search.json and https://eu.forums.blizzard.com/en/wow/search.json (queries in §1.1 and §2)
- https://eu.forums.blizzard.com/en/wow/t/639910/1.json (CD Manager seals report, player post)

Data and source:
- https://wago.tools/api/builds
- https://wago.tools/db2/{SpellName,Spell,SpellCooldowns,SpellMisc,SpellDuration,SpellClassOptions}/csv?build=1.60.1.{70790,70840,70862}
- https://github.com/Gethe/wow-ui-source (branch `forever`; commits, compares and raw files cited in §2.4, §2.6, §3.1, §3.2)

Addon authors (GitHub):
- https://github.com/valkyrnstudios/RankSentinel/pull/116 (plus comments)
- https://github.com/heyaapl/Soundboard/pull/22
- https://github.com/CrusaderStrike/addon/pull/16
- https://github.com/JulianNorton/LoremCooldownTracker/pull/4
- https://github.com/kaminaris/MaxDps-Rogue/issues/19 (plus comments)
- https://github.com/Clausi/gryphonFrames/pull/9 and https://github.com/Clausi/gryphonFrames/pull/10
- https://github.com/Gogo1951/Pretty-Wide-Quest-Log/issues/23
- https://github.com/ATTWoWAddon/AllTheThings/issues/2738
- https://github.com/Tercioo/Details-Damage-Meter/issues/1143 and https://github.com/Tercioo/Details-Damage-Meter/issues/1145
- https://github.com/ljukas/forever-addons/pull/18
- https://github.com/linman0x90/dgks/pull/6
- https://github.com/Everloot/everloot/issues/799
- https://github.com/fitzforge/polestar/pull/1019
- https://github.com/PhenomDevel/AskAzeroth/pull/141
- https://github.com/moust4ki/EasyControllerWowForever/issues/19
- https://github.com/Hogtron-Solutions-Tech-Stack/hogtron-ui/pull/159
- https://github.com/dbspringer/nameplatesct-reforged/pull/39
- https://github.com/sniffingpickles/HunterSuite/pull/1
- https://github.com/dismlx/flat-ui/pull/3
- https://github.com/korallis/KstyleUI/pull/54
- https://github.com/seathasky/Matts-Action-Bar-Fonts/issues/1
- https://github.com/smoergi/OneForAll_Forever/issues/35
- https://github.com/cjber/tweaks-forever/issues/301
- https://github.com/vattiss/wowkit/issues/17 (Shield Block glow only once per combat; read, not cited above)
- https://github.com/babunidev/FlourishForever/pull/2 (read; no API finding beyond spellbook item types)

Community trackers and news:
- https://foreverchanges.pro/patch-notes and https://foreverchanges.pro/patch-notes/feed.xml
- https://wowforever.news/changes.html
- https://seramate.com/news/forever/2026/11/06/forever-hunter-warlock-shaman-class-tuning-0908bdd5 (mirror of the Nov 10 post)
- https://seramate.com/news/forever/2026/11/06/forever-shaman-talents-revisit-next-year-ccab8e0c
- https://raw.githubusercontent.com/realworldbuilder/wowwrapped/main/docs/addon-api.md (pre-launch, 2026-09-21; used only to mark the WOW_PROJECT_ID conflict)

## 5. Gaps and what I could not verify

- **Reddit, CurseForge, WoWInterface:** web search returned no post-launch addon-API threads on r/wowforever,
  r/classicwow or r/wowaddons. I did not search WoWInterface forums or CurseForge comments directly, so they are not
  covered.
- **EU "Class Tuning Incoming – 10 November" (topic 640100):** seen as a search hit only. I assume it has the same text
  as the US post but did not fetch it.
- **Pet spellID secrecy** (`UNIT_SPELLCAST_SUCCEEDED` for unit `pet`): no author reports it either way. It needs a live
  probe.
- **Whether wago.tools CSV exports include the server hotfix cache:** not confirmed. §3.3 reflects client tables only.
- **§0 items 1 and 2 (Shank/Arcane Blast IDs)** come from client DB2 data. I did not run the generator, the sim or the
  game (outside my brief). The main session should check them against `tools/gen_spell_data.py` output and the
  mythicsim-forever-engine `spells.jsonl` rows before acting.

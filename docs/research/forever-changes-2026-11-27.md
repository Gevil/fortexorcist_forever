# WoW Forever: changes 2026-11-21 .. 2026-11-27 (builds 1.60.1.71091 and 1.60.1.71139)

Researched 2026-11-27. Read-only research; no other repo file was touched, no git was run.
Baseline = the previous report `forever-changes-2026-11-21.md` (build 71037, push 114286 / 114320 item import).

## (d) Executive summary

1. **Builds.** 71037 stayed live until 11-24. **71091** was in use by wowsims from 11-24 17:50 UTC (first "Update items to 71091" commit). **71139** is dated by wowsims "from 2026-11-25 19:14 UTC in the US and the EU" (commit abf82558e4). Blizzard publishes no build numbers; the dates are inferred (I).
2. **Primary source.** Blizzard's hotfix topic 2403040 (renamed "Forever Hotfixes - November 25, 2026"). Posts 14-16 carry the 11-20, 11-23 and 11-25 notes. There is **no 11-26 or 11-27 hotfix note** yet. Post 16 was created 2026-11-25 23:25 UTC. The "11-26 Hunter hawk crit hotfix" is that 11-25 note ("~5% less critical strike chance than intended"). "Beta Development Notes" (2360696) has had no post since 11-04.
3. **Summon Hawk** (spell 1293248; 18 s per the sim source comment; hawk count = effect 3 of the row, value not read; "max 2" is unverified). The 11-25 hotfix makes hawks attack the target they were summoned on even when the pet is Passive, dismissable by Dismiss Pet or by right-clicking an icon under the portrait, and gives them back the ~5% crit they lacked. Player reports on 11-26/27 say hawks now ignore `/petattack`, stick to the first target and pull extra mobs. The 18 s duration is not stated in any Blizzard note. It is read from the sim source comment ("up for 18 s").
4. **Druid Balance rework** (push 114344, live in the 11-25 notes): Improved Wrath -> **Starlight Wrath**; Improved Moonfire -> **Moon and Stars**; Improved Starfire cut to 2 ranks (8/15%); Eclipse adds +7/13/20% Wrath crit; **Moonfury removed, Dreamstate added**; Moonkin Form +10% Arcane/Nature. Spell/talent **renames break name-based lookups**. Genesis now also boosts Hurricane and Tranquility.
5. **Timers changed:** Oath of Light 5 min -> **60 min** (spell 1328548, 11-25); World buffs (Songflower, Fengus' Ferocity, Mol'dar's Moxie, Slip'kik's Savvy, Sayge's Dark Fortune) **no longer fall off on area change** (11-23; AuraInterrupt bit 0x400000 removed from their rows); Scarlet Illusion quest buff 30 min -> 60 min; Feralheart 4pc = 4 energy regen per 1 s for 5 s (11-23).
6. **Procs / items:** Revelation enchant rolls once per AoE wave and no longer covers the whole duration of channels; Fist of Shahram (16601) now lands on the wielder (8 s, 30% melee haste); Blackblade of Shahram haste fixed; Libram of Law now buffs Judgement of Command; Seed of Renewal and Stormshroud 3pc were already known. Three crafted Tier 1 sets were re-statted in 71091 (Grovekeeper Ferocity/Rage, Spiritcaller's Rage).
7. **Combat/aura behaviour fixes (P):** Mind Vision no longer procs; Intensity now works on Incinerate; Chain Lightning now consumes Clearcasting when 5 Maelstrom Weapon stacks are up; Poised is removed by Sap/Distract in Stealth; Exorcism can crit (server change 11-25 ~20:03 UTC, before the note); Judgements refresh below 20 s duration; "a few spells and abilities caused more weapon procs than intended" was fixed on 11-23 (spells not named; the data shows Execute, Mutilate, Judgement and Judgement of Command rows got Suppress Weapon Procs).
8. **Racials:** nothing that changes a tracked timer. Wisp Form can no longer be applied to living players (11-23). The class/racial regenerations carry no racial row changes in the diffs I read.
9. **Addon API / secret values / GUID obfuscation:** no Blizzard note, no confirmation in this window that the relayed "realm ID in GUIDs obfuscated, will apply to Forever in an upcoming 1.60.1 hotfix" shipped. **Not shipped as far as any source shows (UNVERIFIED).** Cooldown Manager: no Blizzard change in the window; player reports that proc buffs list the passive spell instead of the buff (11-27).
10. **Blocked:** wowhead (needs a browser, none installed), warcraft.wiki.gg page is a generic Forever article with no patch notes, `web_search` returned unrelated pages, Reddit not reachable. Details in (b).

Confidence key: **P** Blizzard primary (forum hotfix thread), **G-DB** value read from a game-data diff in a wowsims commit, **G-msg** wowsims commit message, **M** third-party measurement (Warcraft Logs, via wowsims), **F** fan/player post, **I** my inference.

---

## (a) Change table

Source shorthand:
- `HF` = https://us.forums.blizzard.com/en/wow/t/2403040.json (post 1 = rolling compilation, posts 14/15/16 = 11-20 / 11-23 / 11-25; read 2026-11-27).
- `GH:<sha>` = https://github.com/wowsims/forever/commit/<sha> (read through `api.github.com/repos/wowsims/forever/commits`, 563 commits since 2026-11-21; the large `spells_auto_gen.go` patches were read for the commits listed in a1).
- `FT:<id>` = https://us.forums.blizzard.com/en/wow/t/<id> (player thread).

### a1. Builds and data pushes

| Date (UTC) | Build / push | What | Source | Conf. |
|---|---|---|---|---|
| 11-20 / 11-21 | 71037 / 114309, 114313, 114320 | Binary spells take the Spell Piercing bonus (114309); Execute, Mutilate and Judgement get Suppress Weapon Procs (114313); Intensity's class mask widens (114320). | GH:da7056f934, GH:be0def37c0 | G-msg |
| 11-24 ~02:10 | 71037 (hotfix, no push id given) | Tamed pets' white swings take the owner-inherited crit (EV-0134: 28.7% vs 12.8% at Ferocity 5/5). | GH:a67b8e36d9 | G-msg, M |
| 11-24 | 71037 / 114366 | Instance/quest placement regenerated (drop sources only). | GH:35ea30eb99 | G-msg |
| 11-24 <=17:50 | **71091** / up to 114378 | First 71091 item update; class/racial/shared groups regenerated at 21:34 to push 114378 (Will of Shahram loses aura options; Fist of Shahram targets the wielder's master). | GH:9b890b3073, GH:be0def37c0 | G-msg, G-DB |
| 11-25 09:58 | 71091 / 114405 | Genesis names Hurricane and Tranquility; Revelation buffs gain the periodic-harmful proc flag; Judgement of Command ladder gets Suppress Weapon Procs; Oath of Light 1 h; Blackhand's Breadth physical; poisons bind on pickup. | GH:456c2a8253 | G-msg, G-DB |
| 11-25 ~20:03 | server change, no push id | Exorcism crits (15.2% of 2,249 hits after, 0 of 6,929 before; Holy Wrath 17.4% over the same window). | GH:77800d6ec7 (EV-0188) | M |
| 11-25 19:14 | **71139** | Build timestamp as stated in commit text. | GH:abf82558e4 | G-msg |
| 11-25 23:25 | HF post 16 | "Hotfixes - November 25, 2026" published. Contains the Balance rework, hawk fixes, Exorcism, Oath of Light, Revelation, items. | HF post 16 | P |
| 11-25 19:33 | push 114344 (Balance rework) | wowsims note: raidbots held 114344 under an older unique id with pre-rework rows; regenerated from the live cache. | GH:b57a61d659 | G-msg |
| 11-26 05:08 | 71139 | Item import ("hotfixes as of 2026-11-26"): new consumable Plated Armorfish (item 286152); Well Fed 1319310 armor aura type changed. | GH:18af55acf9 | G-DB |

Pipeline noise to ignore: `70739a13d9` (11-25 22:38) briefly reverted the Starlight Wrath / Moon and Stars names and dropped Vilerend Slicer (item 11603, "Wound" 1320808: 225 damage) from `db.json`; `18af55acf9` restored the names. The Vilerend Slicer row flipped in and out of the data (11-24 in, 11-25 out). Read it as a data-extraction artefact, not a game change (I).

### a2. Class and spell changes

| Date | Build / push | Class / area | Change (exact numbers) | Source | Affects ForteXorcist | Conf. |
|---|---|---|---|---|---|---|
| 11-25 | 71139 / 114344 | Druid Balance | **Improved Wrath (16814) renamed Starlight Wrath**; also reduces Starfire cast time by **0.1/0.2/0.3/0.4/0.5 s** (was Wrath cast-time only). | HF 16; GH:b57a61d659 | data, name lookups; cooldown bar none | P, G-DB |
| 11-25 | 71139 / 114344 | Druid Balance | **Improved Moonfire (16821) renamed Moon and Stars**; grants Starfire a **50/100%** chance not to lose casting time when the druid takes damage (pushback protection). | HF 16; GH:b57a61d659 | data, names; Spell Timer (pushback) none | P, G-DB |
| 11-25 | 71139 / 114344 | Druid Balance | Improved Starfire (16850) **5 points -> 2**, **8/15%** per point-count; 3+ points spent -> all talent points reset. Per the wowsims note it now "only stuns". | HF 16; GH:b57a61d659 | data only | P, G-msg |
| 11-25 | 71139 / 114344 | Druid Balance | **Eclipse (408248)** also raises **Wrath crit by 7/13/20% at all times**. | HF 16; GH:b57a61d659 | Spell Timer (Eclipse buff unchanged; added passive effect) | P, G-DB |
| 11-25 | 71139 / 114344 | Druid Balance | **Moonfury (16896) removed, replaced by Dreamstate (408258)**: **20/40/60/80/100%** of Innervate's benefit when the druid casts it on another player. Innervate (29166) is 20 s duration, 360 s cooldown (unchanged in the diff). | HF 16; GH:b57a61d659 | cooldown bar (Innervate: self-cast vs other-cast), talent id swap | P, G-DB |
| 11-25 | 71139 / 114344 | Druid Balance | Moonkin Form (aura 24905 Passive) now also +**10% Arcane and Nature damage** while in form. | HF 16; GH:b57a61d659 | data only | P, G-DB |
| 11-25 | 71139 / 114405 | Druid | Genesis (1223081) now also boosts **Hurricane** damage and **Tranquility** healing; Hurricane's final hit lands. Balance multi-target sim +3.7%. | HF 16; GH:456c2a8253 | data only | P, G-msg |
| 11-23 | 71037 | Druid Feral | **Feralheart 4-piece**: 4 Energy regeneration every 1 s for 5 s (was incorrect). | HF 15 | item procs (set bonus buff, 5 s) | P |
| 11-25 | 71139 | Hunter BM | **Summoned Hawks**: attack the target they were summoned on even if the pet is Passive; dismissed when Dismiss Pet completes; can be dismissed by right-clicking their icon below the portrait; attack the current target if idle. | HF 16 | Hunter tools (hawk timer: dismissal ends the 18 s early; new UI icon under the portrait) | P |
| 11-25 | 71139 | Hunter, Warlock | Pets had **0% crit on melee basic attacks** (fixed). Hawks had **~5% less crit than intended** (fixed). Succubus and Incubus had **5% higher crit than intended** (fixed). | HF 16; GH:e2ac76a12c | Hunter-Warlock tools (data) | P |
| 11-26 | sim | Hunter | Sim model: a hawk's crit is the tamed pet's = max(owner melee, owner ranged crit) + Ferocity (was half the owner's); TestHunterPets average 756.8 -> 770.7. **18 s duration** and "number of hawks at once" (effect 3 of spell 1293248's row) are read from the sim source comments. Hawk base: health 5% of creature health, armor 30% of owner's, AP 80% of owner's ranged AP + weapon share, 2.5 s swing. | GH:e2ac76a12c, `sim/hunter/summon_hawk.go` | Hunter tools: confirms 18 s / hawk count from game data row, not from a Blizzard note | G-msg, M |
| 11-26 | 71139 | Hunter | Player reports: hawks no longer obey `/petattack`, stick to first mob, pull unflagged mobs, "half damage". Not Blizzard-confirmed. | FT:2429541, FT:2430112, FT:2430150, FT:2430569 | Hunter tools (hawk target/uptime reasoning) | F |
| 11-27 | live logs | Hunter | Pet focus regenerates 10/s times Bestial Discipline times each ranged-haste aura (Quick Shots 1.3, Rapid Fire 1.4, Berserking 1.1); Frenzy and Bestial Wrath do not count (490 pets). Pet autocast steps 0.8 s. | GH:8f08858ecd, GH:a67b8e36d9 | Hunter tools | M |
| 11-25 | 71139 | Paladin | Judgements failed to refresh from attacks when below a **20 s duration** (fixed). Exorcism could not crit (fixed; server change ~20:03 UTC). | HF 16; GH:77800d6ec7 | Spell Timer (Judgement debuff refresh) | P, M |
| 11-25 | 71091 / 114405 | Paladin Holy | **Oath of Light (1328548) duration 300 s -> 3600 s.** | HF 16; GH:456c2a8253 | Spell Timer (buff duration) | P, G-DB |
| 11-24..25 | 71091 / 114405 | Paladin | Judgement of Command ranks (20425, 20961, 20962, 20967, 20968) get **Suppress Weapon Procs** (Attr4 0x800000); Judgement (20271) too since 114313; Libram of Law ("Judgement Increased Damage" 1291086, +4%) now also applies to Judgement of Command. | HF 16; GH:456c2a8253, GH:be0def37c0 | item procs (weapon procs no longer roll off Judgements) | P, G-DB |
| 11-23 | 71037 | Warlock Destruction | **Intensity (18135)** now works on Incinerate (class-mask word 1 = 64 added). | HF 15; GH:be0def37c0 | data only | P, G-DB |
| 11-23 | 71037 | Priest | Mind Vision (2096, 10909) no longer procs effects (Suppress procs attrs set). Shadow: Dark Inspiration gives the right Spirit % when activated by Mind Flay; Chastise (ranks 1277331-1277335, 2 s root, 120 s category cooldown) usable in Shadowform. | HF 15; GH:be0def37c0 | Spell Timer (Dark Inspiration), cooldown bar (Chastise availability) | P, G-DB |
| 11-23 | 71037 | Warrior | Mortal Strike in the spellbook cannot be used without the talent point (stays visible). **11-25:** Arms Weaponmaster reapplies after death in Battlegrounds. | HF 15, HF 16 | cooldown bar (Mortal Strike usable state) | P |
| 11-25 | 71139 | Shaman | Chain Lightning now consumes Clearcasting when the shaman has Clearcasting and 5 Maelstrom Weapon stacks. Sim note: Lightning Bolt that spends 5 stacks and Chain Lightning under "Maelstrom Ready!" keep Clearcasting; a Windfury Totem hit spends no Flurry charge. | HF 16; GH:bc17504ea8 | Spell Timer (Clearcasting, Maelstrom Weapon, Flurry) | P, G-msg |
| 11-25 | 71139 | Rogue | **Poised** is now removed when the rogue casts Sap or Distract in Stealth. All rogue poisons and Blinding Powder are **temporarily bind-on-pickup**. | HF 16; GH:456c2a8253 | Spell Timer (Poised), consumable tracking | P, G-msg |
| 11-24..27 | 71139 / live | Rogue | Since push 114281 a lone Shank is followed by a Windfury Totem hit 10.18% of the time (Sinister Strike 10.05%; before 0.05%). Shank rolls the off-hand weapon and equip procs once, the main hand never. Execute, Judgement of Command and Mutilate roll once per hand. | GH:bc0f83f346, GH:f041296cae, GH:c755fe3672 (EV-0155) | item procs / extra-attack counting | M |
| 11-23 | 71037 | Spells (general) | "A few spells and abilities were causing **more weapon procs than intended**" (names not given). Data: Execute ranks 1-5 and Mutilate ranks 1-3 carry Attr4 0x800000 since 114313. | HF 15; GH:be0def37c0 | item procs | P, G-DB |
| 11-23 | 71037 | World buffs | **World Buffs no longer fall off when changing areas** (they still fall off entering raids). Data: Songflower Serenade 15366 (3600 s), Fengus' Ferocity 22817 (7200 s), Mol'dar's Moxie 22818, Slip'kik's Savvy 22820, Sayge's Dark Fortune of Damage 23768 lose AuraInterrupt 0x400000 (and InterruptFlags 8 where present). | HF 15; GH:6050bf0615 | Spell Timer (world buff durations persist across zones) | P, G-DB |
| 11-23 | 71037 | World buffs | **Fengus' Ferocity**: effect rows 3 and 4 **230 -> 115** (half). **Darkmoon Faire buffs** reduced to half (Sayge's Dark Fortune of Damage 23768's first effect changed from Mod Damage Done to a dummy aura; other Darkmoon rows were beyond the part of the patch I read). | HF 15; GH:6050bf0615 | data only | P, G-DB |
| 11-25 | 71139 | Enchanting | **Revelation** weapon enchant: rolls its proc chance **once per AoE wave** (was per target); no longer affects the **entire duration of channeled spells**. Priest and warlock Revelation buffs (1323377 / 1323392, 15 s, 1 charge) ProcFlags 0x14000 -> **0x54000** (adds periodic harmful). | HF 16; GH:456c2a8253 | item procs (Revelation 15 s buff, 1 charge) | P, G-DB |
| 11-25 | 71139 | Legacy | **Reinforce** now cuts durability loss **8/16/24/32/40%**. **The Quick and the Dead** now makes Shadowform, Moonkin Form, Travel Form and Trueshot Aura **free** (as intended). | HF 16 | none (mana cost only) | P |
| 11-23 | 71037 | Race | Wisp Form cannot be applied to living players. | HF 15 | none | P |
| 11-25 | 71139 | Quests | Scarlet Illusion (from "Scarlet Subterfuge") lasts **1 h (was 30 min)**. | HF 16 | Spell Timer (quest buff, only if tracked) | P |

### a3. Item changes

| Date | Build / push | Item | Change | Source | Affects | Conf. |
|---|---|---|---|---|---|---|
| 11-25 | 71139 / 114378 | **Fist of Shahram (16601)** | 30% melee attack speed for **8 s**, now cast on the **wielder** (target type 27, "caster's master") instead of Shahram; a second Fist refreshes the first. **Will of Shahram (16598)** loses its aura options (20 s, +50 stat). Blackblade of Shahram haste now works "only to the wielder". | HF 16; GH:be0def37c0, GH:344b483eef (EV-0125) | item procs (8 s haste buff) | P, G-DB |
| 11-25 | 71139 | Libram of Law | Now affects Judgement of Command (see a2). | HF 16 | item procs | P |
| 11-25 | 71139 | Totem of the Storm (272432) | Renamed **Totem of the Maelstrom** (effect 1291078 "Lightning Bolt Can Activate Maelstrom Weapon"). | HF 16; GH:7778dc4497 | name lookups | P, G-DB |
| 11-25 | 71139 | The Blackhand's Breadth (spell 1318944) | Trinket "can no longer be resisted"; spell school 32 (Shadow) -> 1 (Physical), defense type removed; +5% crit for the caster, 20 s. | HF 16; GH:456c2a8253 | item procs (20 s buff) | P, G-DB |
| 11-25 | 71139 | Chained Essence of Eranikus' | Was going through immunities (fixed); cloud aura 1300240 attributes changed. | HF 16; GH:456c2a8253 | none | P, G-DB |
| 11-25 | 71139 | Night Watchman's Torch | Usable while mounted/casting again. | HF 16 | none | P |
| 11-25 | 71139 | Unerring Purpose | Sells for more than 2 copper. | HF 16 | none | P |
| 11-24 | 71091 | Crafted Tier 1 sets: Grovekeeper Ferocity (2115), Grovekeeper Rage (2113), The Spiritcaller's Rage (2110) | Items restatted (e.g. Grovekeeper Kilt 0:18, 1:14, 2:21, 3:16, 35:10). Bonuses parsed at **2/4/5 (Ferocity), 2/4 (Rage), 2/4/5 (Spiritcaller's Rage)**. The 3pc effects (Hibernate, Rebirth, totem radius) and a **Berserk cooldown -15 s** (spell 1301249) are not modelled by the sim; the 5-piece bonuses need head and chest pieces that the game files do not ship yet. | GH:fd3d351ec7, GH:9b890b3073, GH:be0def37c0 | item procs / set bonus buffs (Berserk 15 s CD reduction) | G-msg, G-DB |
| 11-23 | 71037 | Filcher's Cowl (219343) | Level requirement removed. | HF 15; GH:9b890b3073 | none | P, G-DB |
| 11-24 | 71037/71091 | Seed of Renewal (219326) | Unchanged from the 11-21 report: buff 443678 30 s, 40% proc, 120 s ICD. Still present in 71091. | GH:9b890b3073 | item procs | G-DB |
| 11-23 | 71037 | Cooking | Boiled Clams, Clam Chowder, Goblin Deviled Clams, Giant Clam Scorcho, Undermine Clam Chowder, Clam Linguine now give the correct Well Fed and are recategorised as Stamina Food. Murloc Fin Soup moves up one food tier. Plated Armorfish (item 286152, new in 71139): Nutritious Food 1319311 -> Well Fed 1319310 (900 s); Well Fed's armor effect changed to "armor no mods", item stat slot 38 = 150. | HF 15; GH:18af55acf9 | consumable buffs (Well Fed 15 min) | P, G-DB |
| 11-23 | 71037 | Engineering | Goblin/Gnome Engineer's Renewal Gift no longer a broken "?" item. | HF 15 | none | P |
| 11-21..26 | 71037/71139 | Elixirs | Owner check on 11-24: every elixir's crit stacks with Leader of the Pack and Moonkin Aura; only one elixir's 2% crit counts. | GH:490b3bc569 | consumable buffs | M (owner in-game check, not Blizzard) |

### a4. Third-party measured proc rates in the window (not Blizzard changes)

| Date | Item / effect | Value | Source | Conf. |
|---|---|---|---|---|
| 11-21 | Sword of Zeal (Zeal) | 1.95 PPM (was 1.8), 3,079 procs, 12 wearers | GH:14df0d1172 | M |
| 11-23 | Masterwork Stormhammer (Chain Lightning) | 0.9 PPM observed | GH:93d32c946a | M |
| 11-22 | Blackhand Doomsaw (Fatal Wound) | 0.9 PPM | GH:9036681861 (headline only) | M |
| 11-24 | Ragehammer (Enrage 12686) | 2.0 PPM; Enrage = **+6% melee attack speed and +102 attack power** | GH:75bda6a45e (EV-0186) | M, G-DB |
| 11-26 | Kindling Stave (Ignition 1300781) | 1.72 PPM on the cast time (min 1.5 s), 10 ms cooldown; 389 reports | GH:310e73022e | M |
| 11-26 | Seven weapons: Cruel Hand of Timmy 2.05; Felstriker 0.5; Alcor's Sunrazor 1.95; Judge's Gavel 1.05; Electrified Dagger 1.35; Shadowblade 1.0; Shimmering Platinum Warhammer 2.05 PPM | PPM | GH:36b36334f6 | M |
| 11-23 | Nature's Bounty (27784): shapeshifts, Frenzied Regeneration and Shifting Power roll nothing; energy in bear forms returns with Cat Form | counts of ~3,300 / 600 / 2,163 | GH:2bba2e23bc, GH:cbcfc42281 | M |
| 11-27 | Spell Piercing: 0 of 265 hits at 5, 17 of 231 at 6 for a level 60 mage | 1% cut between 5 and 6 | GH:4d33741a1d | M |

---

## Addon API / UI / secret values / combat log

| Date | Finding | Source | Affects | Conf. |
|---|---|---|---|---|
| 11-20 | Relayed WoWUIDev note: realm ID in creature, vehicle, pet and game object GUIDs obfuscated; "will also apply to Forever in an upcoming 1.60.1 hotfix". **No evidence it shipped** in 71091 or 71139: Blizzard's 11-23 and 11-25 notes do not mention it; no player report of broken GUID parsing. Thread 2423386 has no posts that confirm it (posts to 11-24 read). | FT:2423386; HF 15, 16 | NPC-id parsing from GUIDs | F (unshipped), P (absence in notes) |
| 11-26 | Player: **Decimation** is not shown in the Cooldown Manager when the buff is up. | FT:2429763 | Cooldown Manager overlap | F |
| 11-27 | Player: Cooldown Manager lists the **passive** (e.g. Missile Barrage) not the proc buff's spell id, so proc buffs never trigger. Reporter says it affects many classes. | FT:2430683 | Spell Timer / WA-style proc tracking is still needed; CDM cannot track those procs | F |
| 11-26 | Player: Ice Lance missing from the Cooldown Manager (older thread, still active 11-26). | FT:2412318 | CDM overlap | F |
| 11-25 | UI: Summoned Hawks can be dismissed by right-clicking an icon under the Hunter's portrait. New UI element; its frame/unit token is unknown. | HF 16 | Hunter tools (hawk display) | P |
| 11-26 | Player thread on a hunter "dead zone" addon (ForeverHunterDeadzone, CurseForge) says range-circle addons are blocked ("purposefully prevented"). Not Blizzard-confirmed. | FT:2430018 | none | F |
| 11-21 | A player reports a `BlizzardError` file appearing after each update; the thread's client version was 1.60.1.71037. | FT:2424256 | none | F |
| any | **Combat log:** no Blizzard note. wowsims text: Windfury Totem strikes log 6-20 ms before their damage (carried from 11-21 report), and Shank's off-hand rolls the totem. | GH:bc0f83f346 | item procs | M |
| any | **Secret values:** no Blizzard note for Forever in 11-20/23/25. | HF | n/a | P (absence) |

---

## (b) Not found / blocked

| Source | Result |
|---|---|
| Blizzard hotfix note for 11-26 / 11-27 | Not published as of 2026-11-27 ~15:00 local. `t/2403040.json` last post is 2026-11-25 23:25 UTC. Forum search for "Hotfixes - November 26/27" returns only 2403040 and player threads. A player thread titled "No warrior changes 11/26" (FT:2429950) suggests players expected a note. |
| 11-26 hawk "crit hotfix" | Is the 11-25 note ("~5% less critical strike chance"), posted 23:25 UTC on 11-25. wowsims' PR #1252 merged 11-26 11:14 UTC. No separate 11-26 Blizzard post. |
| Summon Hawk numbers (18 s, max 2) | Not in any Blizzard note. Duration read from the sim's source comment ("up for 18 s"); the hawk count is "effect 3 of Summon Hawk Triggered (1293248)" in the sim source, whose value I did not read. "Max 2" is the user's figure; I did not confirm it from game data. |
| Beta Development Notes (2360696) | Last post 2026-11-04. Nothing newer. |
| `[DB]` push `be0def37c0` / `456c2a8253` / `b57a61d659` / `4269136e8f` | Messages and file lists read. `spells_auto_gen.go` patches read for be0def37c0 and 456c2a8253 and the relevant hunks of b57a61d659 (the image-only view cut some lines). 4269136e8f is a merge of PR #1252 (hawk crit, "Faster Attack on Cats only", trap arming); its code diff was not read beyond the hawk crit lines. The `spell_store_inputs.json` raw store changes are too large for the API. |
| Warcraft.wiki.gg Patch_1.60.1 | Works but is a general Forever overview; no patch notes or API change list. |
| Wowhead `/forever/news`, spell pages | Not readable: no headless browser installed ("no chromium/chrome binary"). |
| Reddit, Icy Veins, Wowpedia | `web_search` returned only unrelated pages (YouTube, MDN). Not fetched. |
| BlizzTrack for Forever | Not found; only the Classic Era page loaded. Build numbers rest on wowsims commit dates. |
| uiforever.com | Not re-checked; no changelog existed on 11-21. |
| Addon repos with Forever 71091/71139 notes | Not searched again this session. |

---

## (c) Open questions only the live client can answer

1. **Summon Hawk:** duration (18 s?), maximum hawks (2?), whether the hawks are real guardian pets with units (`UnitExists("pet")`-style token or a totem-like slot), the icon under the portrait (frame name, timer text), and whether Dismiss Pet fires a SPELL_AURA_REMOVED/summon-end event. What does `/petattack` do now?
2. **Hawk crit:** is the ~5% a data row (Hunter Guardian Hawk Pet Scaling 01, spell 1293586) or code? Is crit visible in tooltips?
3. **Druid:** are Starlight Wrath (16814), Moon and Stars (16821), Improved Starfire (16850), Dreamstate (408258), Eclipse (408248) the same spell ids in the talent API? Does `GetTalentInfo` return the new names? Does Eclipse keep its 15 s / stack behaviour?
4. **Dreamstate:** does an Innervate cast on another player show a new aura on the caster, and with what duration?
5. **Oath of Light** (1328548): confirm the 60 min on the buff; is it a self buff or party aura?
6. **World buffs:** do they really persist across zone changes, and does the aura timer keep ticking? Any new aura flag?
7. **Fist of Shahram / Blackblade of Shahram:** is the 8 s, 30% haste aura now visible on the wielder, and what is the proc chance and ICD?
8. **Revelation** (priest/warlock 15 s, 1 charge): confirm the once-per-wave rule and whether the charge still appears as a stack on the player.
9. **Plated Armorfish / Well Fed 1319310:** what does the Well Fed tooltip show (armor rating), and does the 900 s timer match?
10. **GUID obfuscation:** has the realm ID in creature GUIDs been obfuscated on 71139? What does `UnitGUID("target")` return and do NPC-ID parses still work?
11. **Cooldown Manager:** which proc buffs list the passive instead of the buff (Missile Barrage, Decimation)? Are the Maelstrom Weapon, Reckless Swings, Redoubt entries from 11-10..16 still correct?
12. **Aura API:** can addons still read self-debuffs on the player (Arcane Blast) and stack counts on 71139?
13. **Judgement refresh:** what is the Judgement debuff duration (the note says "20 second duration"), and do melee attacks refresh it past a 20 s threshold?
14. **Poised / Poisons BoP:** is the poison BoP a persistent flag or a short-lived workaround ("temporarily")?
15. **Mortal Strike without the talent:** does `IsUsableSpell` return false, and does the cooldown bar still show the spell?
16. **Crafted Tier 1 set bonuses** (Grovekeeper Ferocity 2/4/5, Rage 2/4, Spiritcaller's Rage 2/4/5; Berserk -15 s): confirm the tooltips and that the 5-piece pieces are not yet obtainable.

## Method notes

- Forum data: public Discourse JSON of topics 2403040 (16 posts), 2360696, 2423386 (posts after 11-21 filtered for GUID/realm/patch/addon), 2419742, 2415650 and the player threads cited above, read 2026-11-27.
- GitHub data: `api.github.com/repos/wowsims/forever/commits?since=2026-11-21T00:00:00Z&per_page=100` pages 1-6 (563 commits, last page 63) plus `/commits/<sha>` for the DB pushes listed in a1. Unauthenticated, no rate-limit errors.
- Rows labelled "P, G-DB" pair a Blizzard note (player-facing change) with the game-data diff (spell ids, numbers). Rows labelled "M" are sim-author measurements from Warcraft Logs, not Blizzard values.

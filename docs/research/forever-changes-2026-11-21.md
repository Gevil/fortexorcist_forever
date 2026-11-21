# WoW Forever: changes since 2026-11-12 (through build 1.60.1.71037)

Researched 2026-11-21. Read-only research; no repo files other than this one were touched.
Baseline = our last data refresh: build 1.60.1.70888 / hotfix push 114027.

## (d) Executive summary

1. Builds since the baseline: **70938** (client patch ~2026-11-13), **70959** (~2026-11-17/18, after weekly maintenance) and **71037** (2026-11-20, evening UTC). Dates for the builds are inferred from wowsims commit timestamps and forum posts; Blizzard publishes no build numbers in its notes.
2. The best primary source is the Blizzard forum thread "WoW: Forever Hotfixes - November 20, 2026" (topic 2403040). Its public `.json` endpoint works and holds every hotfix post through 2026-11-20. The "Beta Development Notes" thread (2360696) has had no post since 2026-11-04.
3. **Windfury Totem was reworked** (push 114060, 11-13). It no longer applies a 1 s, 2-charge buff. Its proc is now a weapon strike (spell 10610) with a 100 ms internal cooldown, so no Windfury buff/aura exists to track. This is the largest change for Spell Timer / aura tracking.
4. **Shaman Enhancement** (pushes 113722 and 114027, 11-10/11-12) changed Stormstrike (100% weapon damage, 8 s CD) and Maelstrom Weapon (-20% cast time and mana per stack; 6/7/8/9/10 procs per minute by rank). Weapon imbues now coexist with weapon totems. Per Blizzard, Maelstrom Weapon is now trackable in the Cooldown Manager.
5. **Paladin**: all Judgements except Command became Ranged attacks (push 114060). Unsealed Wrath gained a 0.1 s proc cooldown. Two-Handed Weapon Specialization now raises all Holy damage (11-19, push 114094).
6. **Priest**: Vampiric Embrace healing is 10% of Shadow damage (was 20%), with +100% to the caster's own healing (11-16/17). Dark Inspiration no longer stacks across several Shadow priests. **Warrior**: Flurry, Unbridled Wrath and Reckless Swings now work correctly with Heroic Strike/Cleave (11-16). "Reckless Swings adjusted in the cooldown manager for tracking."
7. **Items (game data)**: the Stormshroud Armor 3pc bonus is 3% for 18 energy (was 4% / 30), pushed 11-20 and confirmed in the 71037 data. Seed of Renewal (item 219326, spell 443278) is new in 71037. Gloves of Holy Might were fixed twice. Rogue Tier 1 5P now reduces Death Mark's cost instead of Envenom's (70959).
8. **Addon/API**: Blizzard's notes contain no addon-API or secret-value line for Forever. A relayed WoWUIDev note (unverified, via a forum player) says realm-ID obfuscation in GUIDs "will also apply to Forever in an upcoming 1.60.1 hotfix". Player reports say the minimap tooltip text became secret from 11-13, and that aura reads only work for buffs on friendlies / debuffs on hostiles. All of this is unconfirmed.
9. Most "item" commits in wowsims/forever since 11-12 are **third-party measured proc rates** from Warcraft Logs (many "game files give no rate" cases). They are not Blizzard changes and are listed as such (section c).
10. Blocked or empty: warcraft.wiki.gg (403), the Wowhead news page (JS shell), Blizzard news (404), uiforever (no changelog exists), no tracker-addon repo with Forever build notes. Details in (b).

Confidence labels: **P** = Blizzard primary source (forum hotfix thread). **G-DB** = value read out of the game data wowsims extracted (patch diff in the wowsims/forever commit). **G-msg** = wowsims commit message only. **M** = third-party measurement from logs (wowsims EV-xxxx evidence). **F** = fan/player post. **I** = my inference.

---

## (a) Change table

Source shorthands:
- `HF` = https://us.forums.blizzard.com/en/wow/t/2403040 (topic JSON: `.../t/2403040.json`, post 1 holds the full history; read 2026-11-21).
- `GH:<sha>` = https://github.com/wowsims/forever/commit/<sha> (read through `https://api.github.com/repos/wowsims/forever/commits...`, 2026-11-21).

### a1. Builds and pushes (timeline)

| Date (UTC) | Build / push | What | Source | Conf. |
|---|---|---|---|---|
| 11-12 | 70888 @ push 114015 / 114027 | Our baseline. Push 113722 (Stormstrike, Maelstrom Weapon, imbue/totem) went live to all regions 10:45 PST 11-12 after a deployment delay. | HF post 9; GH:a63f2b3 | P, G-msg |
| 11-13 | **70938** @ push 114060 -> 114075 | Class groups moved to 70938 at push 114075. Windfury Totem rework (114060), Judgements Ranged. | GH:7fc973b, GH:91aeeee, GH:8f7ad04 | G-msg |
| 11-14 ~02:00 | push ~114091 | Hotfix observed in logs ("after the 02:00 UTC hotfix"): Windfury Totem rolls on every main-hand melee ability. | GH:0e8c4a7, GH:8f415b4 | G-msg, M |
| 11-16 21:15 | 70938 @ push 114115 -> 114122 | Class, racial, shared and item groups regenerated. 173 records lay between 114044 and 114111. 114121 adds 72 reissued dungeon set 0.5 pieces. 114122 adds spell 1297774 (Magical Awareness). | GH:a566a41, GH:fa131e4 | G-msg |
| 11-17/18 | **70959** @ push 114196 -> 114281 | First 70959 item update was 11-18 04:27. Class groups regenerated on 11-20 at push 114281. | GH:6bbad82, GH:dfb4436 | G-msg, I |
| 11-20 | push 114286 | Item DB extraction push. | GH:60f289a, GH:7dc4235 | G-msg |
| 11-20 ~19:00 | **71037** | First "Update items to 1.60.1.71037" commit is 11-20 20:22. A forum thread at 19:17 asks "what was in that patch just now?". A player confirms version 1.60.1.71037 on 11-21. | GH:b9a7a37; forum topics 2423811, 2424256 | G-msg, F |
| 11-21 | 71037 @ push 114320 | Item/set data import (Stormshroud 3pc 3% / 18 energy). | GH:12920e1 (merge text) | G-msg |

### a2. Class and spell changes

Everything marked P is from `HF`. The "since baseline" test is push > 114027, i.e. Blizzard notes dated 11-13 or later, plus anything the notes did not cover. A few 11-10/11-11 notes are included, flagged "pre-baseline", where our 11-03 mining could have missed them.

| Date | Build / push | Class / area | Change (exact numbers) | Source | Affects ForteXorcist | Conf. |
|---|---|---|---|---|---|---|
| 11-13 | 70938 / 114060 | Shaman | **Windfury Totem**: the proc spell (ranks 8516 / 10608 / 10610) loses its attack-power aura, its 2 charges, its 1 s duration and its extra attack. It now casts one main-hand weapon strike (spell 10610) on the target in the same instant. The attack power (246 at rank 3) moved onto the raid aura (8515 / 10609 / 10612) as a dummy effect. The raid aura has a 100 ms cooldown. | GH:91aeeee; P (HF Nov 13: "activated by all melee abilities") | Spell Timer / aura: there is no Windfury buff or charge on the player to track (the sim author found no aura registered for 10610). Cooldown bar: none. | G-msg (+P) |
| 11-13 | 70938 | Shaman | Windfury Totem is activated by all melee abilities even without the main hand. The main-hand strike of Whirlwind/Mutilate still can; off-hand strikes cannot. | HF Nov 13 | procs / data | P |
| 11-14 | ~114091 | Shaman | Logs after the 11-14 02:00 UTC hotfix: Holy Strike, Stormstrike, Shred, Rake, Ferocious Bite, Claw and bear Swipe all roll the totem. Execute rolls it twice (31.6% of landed Executes). Sweeping Strikes' copied hit 12723 never rolls it (0 of 490). | GH:0e8c4a7, GH:8f415b4 | item procs (extra attacks fed by the totem) | M |
| 11-16/17 | maint. | Shaman | Windfury Totem attacks no longer ignore armor and have an internal cooldown; they generate Rage; Mutilate/Execute lose the extra totem attempt; Shield Slam/Shield Bash/shield-empowered Holy Strike no longer trigger it. Enhancement: Maelstrom Weapon can no longer benefit two casts; Thundering Strikes no longer needs a weapon equipped. | HF Nov 16 | Spell Timer (Maelstrom stacks) | P |
| 11-17 | maint. | Shaman | Flurry no longer wrongly loses stacks when Windfury Totem attacks land. | HF Nov 17 | Spell Timer (Flurry stacks) | P |
| 11-12 | 70888 / 113722 | Shaman Enh. | Stormstrike: 100% weapon damage (was 150%), **cooldown 8 s (was 6 s)**. Mental Dexterity: 33/66/100% (was 50/100/150%). Maelstrom Weapon: 20% reduced cast time and mana cost per stack at all ranks (was 4/8/12/16/20%), activates **6/7/8/9/10 times per minute** (was 20/min); the tooltip shows the chance from the main-hand speed (5/5 with a 3.6 weapon = 60%, with a 2.0 weapon = 33%). Imbues and weapon totems can now be used together. Pre-baseline in Blizzard's text, but the data only moved at push 114027 on 11-12. | HF post 9 (11-12 19:10), HF Nov 10; GH:a63f2b3 | cooldown bar (Stormstrike 8 s); Spell Timer (Maelstrom stack chance) | P, G-msg |
| 11-10 | pre-baseline | Shaman | Per Blizzard, Maelstrom Weapon can now be tracked in the Cooldown Manager. | HF Nov 10 | Cooldown Manager overlap | P |
| 11-13 | 70938 | Paladin | **Judgement of Command** activates on-hit effects and counts as a melee attack. Every other Judgement stays Ranged. Pre-baseline in the notes (11-11): Judgement became a Ranged attack. In the data (push 114060) 29 Judgement rows moved from Melee to Ranged (Righteousness, Fury, Light, Wisdom, Justice, Crusader; Command stays Melee). | HF Nov 11, Nov 13; GH:8f7ad04 | data (procs hearing Judgements); Spell Timer for Judgement-proc buffs | P, G-msg |
| 11-13 | 70938 | Paladin Ret | **Unsealed Wrath** gains a 0.1 s proc cooldown. Windfury Totem attacks no longer generate echoes. | GH:8f7ad04; HF Nov 11 | Spell Timer (echo proc) | G-msg, P |
| 11-19 | 114094 | Paladin Ret | Two-Handed Weapon Specialization raises **all Holy damage** while a two-hander is equipped (row 20111 Attr5 0x10000). | HF Nov 19; GH:dfb4436, GH:3c82b22 | data only | P, G-msg |
| 11-10 | pre-baseline | Paladin | Redoubt can now be tracked in the Cooldown Manager. | HF Nov 10 | Cooldown Manager overlap | P |
| 11-16/17 | 114093 | Priest | **Vampiric Embrace** now heals 10% of the Shadow damage done by the casting priest (was 20%). A new second effect gives the casting priest **+100% healing** from it. Revelation no longer procs from VE. | HF Nov 10, Nov 16; GH:dfb4436 | data / buff text | P, G-msg |
| 11-16 | maint. | Priest | **Dark Inspiration** no longer stacks when there are several Shadow priests in the party. | HF Nov 16 | Spell Timer (Dark Inspiration) | P |
| 11-13 | 70938 | Priest | Quick and the Dead (Legacy Perk) now reduces the mana cost of Divine Spirit. | HF Nov 13 | data only | P |
| 11-16 | 114115 | Warrior Fury | Unbridled Wrath is activated by Cleave and Heroic Strike. Flurry stacks are no longer consumed by Cleave/Heroic Strike (sim reading: one charge per Heroic Strike/Cleave cast whatever its outcome). Reckless Swings is activated by Cleave/Heroic Strike. **"Reckless Swings adjusted in the cooldown manager for tracking."** | HF Nov 16; GH:35f2faf | Spell Timer (Flurry, Reckless Swings); Cooldown Manager | P, G-msg |
| 11-13 | 70938 | Warrior | Berserker Rage removes Sap (the data row gains Sapped immunity). | HF Nov 13; GH:7fc973b | cooldown bar (none), data only | P |
| 11-13 | 70938 | Warrior, Mage, Warlock, general | Stun diminishing returns against and from creatures fixed (was none). Mage: Frost Nova is broken by proc damage and Blizzard. Warlock: Siphon Life Rank 1 cannot be cast while silenced. | HF Nov 13 | Spell Timer / DR trackers | P |
| 11-16 | maint. | Druid | Fixed: ranks of **Wild Growth** not going on cooldown (data: a shared cooldown category across ranks). Genesis now increases Pounce's bleed damage. | HF Nov 16; GH:7fc973b | cooldown bar (Wild Growth), data | P, G-msg |
| 11-13 | 70938 | Druid Resto | Wild Growth cannot be cast while moving; healing coefficient 6.6% (was 3.3%). Earlier (11-10): Nature's Swiftness makes Wild Growth instant. | HF Nov 13, Nov 10; GH:3b7e5d8 | data only | P |
| 11-16 | 70938 | Rogue | Rogue poison ranks cannot exceed the maximum rank. Shank on a target without your combo points no longer strips combo points from other targets (when Boot Knife is not talented). | HF Nov 16 | data only | P |
| 11-20 | 70959 -> 71037 | Rogue Combat | Blade Flurry makes Shank's damage hit an additional target. | HF Nov 20 | data only | P |
| 11-20 | 70959 / 114268, 114281 | Rogue | Shank loses its Suppress Caster/Target/Weapon Procs attributes (build 70959 drops its empty third effect). **Boot Knife** is now a proc-trigger aura on spell 1329285. **Tier 1 Rogue 5P** reduces **Death Mark's** cost (was Envenom's). | GH:dfb4436 | data / item procs; Spell Timer (Boot Knife) | G-msg |
| 11-21 | 71037 | Rogue | wowsims changed its model so that Mutilate's cast spell no longer rolls main-hand poison procs ("Nov 21 Hotfix - Remove Mutilate's 2nd MH proc chance"). No Blizzard note found. | GH:bd717cf | item procs / poison proc counting | I (sim author) |
| 11-20 | 70959 | Warlock | Fixed the Demonic Aegis snapshot (it could be kept after untalenting); Demonic Aegis and Demon Skin are removed on unlearn. Pre-baseline (11-10): Voidwalker, Succubus and Incubus health +~15%, Imp Firebolt (first 4 ranks) base damage up; Wrack rework: Wrack deals Shadow damage each second for 6 s and your Siphon Life/Corruption/Bane of Agony tick 100% faster while it is channelled. | HF Nov 20, Nov 10 | Hunter-Warlock tools (Wrack, dots) | P |
| 11-10 | pre-baseline | Hunter | Arcane Shot and Summon Hawk cost 11% of base mana at all ranks. Pet health 115% (was 150%). Hawk melee damage +~80%. | HF Nov 10 | Hunter tools | P |
| 11-11/12 | 114015 | Hunter | Volley no longer activates procs; Volley's cast/wave rows gain Suppress Weapon Procs. | HF Nov 11; GH:3b7e5d8 | Hunter tools | P, G-msg |
| 11-10 | pre-baseline | Mage | Arcane Concentration chance is split across the cast and each bolt. Flamestrike ticks no longer consume Clearcasting (11-09). Arcane Blast duration is 18 s (11-06). | HF Nov 9, Nov 6 | Spell Timer (Arcane Blast) | P |
| 11-17 | 70959 | Legacy buffs | Might of Stormwind and Warchief's Blessing always cancel on death and are no longer applied to non-players. | HF Nov 17 | Spell Timer (buff list) | P |
| 11-06..11-13 | pre-baseline | Cooldown Manager | CC durations are always shown even with DR/mechanic reductions (11-06). Druid: Berserk removed from the manager, Lacerate shown (11-09). Paladin Seals shown correctly (11-09). Thunder Clap tracks only its cooldown (11-09). | HF Nov 6, Nov 9 | Cooldown Manager overlap | P |
| 11-20 | 71037 | Data | Nature's Bounty (27784) periodic-energize effect now carries Misc 3 (energy power type). | GH:d013825 | data only | G-DB |

### a3. Item changes (game data)

| Date | Build / push | Item | Change | Source | Affects | Conf. |
|---|---|---|---|---|---|---|
| 11-20 | 71037 / 114320 | **Stormshroud Armor 3pc** (set 142; spells 23863/23864 "Revitalize") | 3% chance (was 4%) on melee attack of restoring **18 energy (was 30)**; the effect row lost ProcChance 101. | HF Nov 20; GH:d013825 (patch of `spells_auto_gen.go`) | item procs | P, G-DB |
| 11-20 | 71037 | **Seed of Renewal** (item 219326, new) | On-equip spell 443278: 40% proc, 120 s ICD (`ICDMs 120000`), ProcFlags 0x51000. It embeds a seed (aura 443678, 30 s) in humanoids/beasts/dragonkin; if the creature dies within 30 s a Healing Blossom grows. | GH:d013825 | item procs / Spell Timer (30 s mark) | G-DB |
| 11-21 | 71037 | Consumables | New Well Fed foods: Boiled Clams (5525), Clam Chowder (5526), Undermine Clam Chowder (16766), Clam Linguine (250081). Murloc Fin Soup (3663) and Goblin Deviled Clams (5527) get changed stat values and new buffs. Generic food/aura spells 5006 and 19708 were removed. | GH:42cb97b | consumable buffs | G-DB |
| 11-20/21 | 71037 | Crafted Tier 1 / class sets | `db.json` lines of 69 crafted set pieces (items 273884-273951, e.g. Grovekeeper, Manaflare, Justice, Demonheart) were rewritten in b9a7a37. I did not diff the fields. | GH:b9a7a37 | data only | I |
| 11-13 | 70938 | Gloves of Holy Might | Procs only on harmful spells and abilities that deal damage; corrected text. Earlier fix on 11-09. | HF Nov 13, Nov 9 | item procs | P |
| 11-11 | 70888 | Bloody Claws of Attack | Correctly +1 Fist/Unarmed weapon skill. | HF Nov 11 | data only | P |
| 11-13 | 70938 | Channeler's Ring / Blessed Band of Light | Channeler's Ring now has Spell Power (was Spirit); Blessed Band of Light's Hit removed; exchangeable at Pix Xizzix's vendor. | HF Nov 13 | data only | P |
| 11-17 | 70959 | Soulforge Armor, staffs | Soulforge (upgraded tank set): Spell Power (was Strength). Whiteout Staff = Crackling Staff = 25 Stamina, 25 Intellect, 74 Spell Power. Escape Plan gets correct range/damage. | HF Nov 17 | data only | P |
| 11-19 | 70959 | Motes of Unstable Magic | Now soulbound. | HF Nov 19 | none | P |
| 11-13 | 70938 | Other items | Taran Icebreaker is a 2-handed mace; Darkspear signet Mp5 corrected; Everstaring Abomination Eye Spirit; The Bad Hat; Souvenir Sea Shell; Glimmering Mithril Insignia. | HF Nov 13 | data only | P |
| 11-16 | 70938 | Onyxia Blood Talisman | The sim author reports it **lost its on-use**; the data change was in push 114115. Darkmoon Card: Maelstrom's new `$s2` is a x2 against Aquatic enemies. Heroism heals 198. | GH:35f2faf | item procs / on-use tracking | G-msg |
| 11-16 | 114115 | **Krol'dok Battlegear 4pc/5pc** | 4pc Krol'dok Resolve heals 18 on every blocked hit, at most once a second (flat 44 in Strongholds/Cities). 5pc Ogre Dominance adds a Stamina stack on every landed hit taken, at most once per 3 s (ogre form at 20 stacks). The 4pc cooldown was introduced by a hotfix between 17:40 and 17:50 UTC on 11-16. | GH:60f289a (EV-0160) | Spell Timer (stacks) | G-msg, M |

Racial changes: **none found** in the class/racial regenerations (pushes 114015, 114027, 114075, 114115, 114122, 114281). The 114027 commit says the racials "regenerate with no row changes". Tauren Cultivation is cooldown-after-cast only (11-09) and works more reliably (11-19), Orc Command and Night Elf Shadowmeld were fixed on 11-06; Skyborne reputation discount 11-19. None changes a tracked timer. (P for the notes, G-msg for "no row changes".)

### a4. Third-party measured proc rates (not Blizzard changes)

wowsims/forever fits these from Warcraft Logs reports (evidence ids "EV-nnnn" in the repo). The game files often give no rate, so the sim author writes an override. Treat as **M**, never as Blizzard numbers. Dates are commit dates.

| Date | Item / effect | Measured value | Commit |
|---|---|---|---|
| 11-12 | Dragon's Call | 4.5 PPM, 45 s cooldown | GH:b27386a |
| 11-12 | Highborne Research Tablet | 2.6/min, later a flat chance on spell hits | GH:41437d2, GH:6dd962f |
| 11-12 | Hand of Justice | 1%, 3x vs Dwarves | GH:8402907 |
| 11-12 | Fist of Stone | restores mana 3.2/min | GH:606d7d6 |
| 11-13 | Mark of the Chosen | 2% on hits taken, 120 s cooldown | GH:59d1ee7 |
| 11-14 | Draconic Infused Emblem | 8% per landed spell hit | GH:79704b2 |
| 11-14 | Moonshadow Stave | 1.5 PPM on cast time | GH:6ac634a |
| 11-14 | Zealot Plate | 5% mana on landed melee swings taken | GH:2e6fd88 |
| 11-14 | Rock on Stick | 1.85 PPM | GH:be43b11 |
| 11-15 | Flurry Axe | 1.65/min; Skullforge Reaver 1.95/min; Rot-Covered Harpoon 1.45 PPM | GH:0da2416, GH:e8f005b, GH:ef9fa21 |
| 11-16 | Revelation (enchant) | 8% proc chance; the charge is spent at the cast on every class (EV-0129/0149) | GH:adbd6e5, GH:5749b42 |
| 11-16 | Argent Avenger ~0.99/min; Argent Defender 0.5 PPM; Warrior's Resolve ~1/min; Heart of Wyrmthalak 2 PPM; Fiery Weapon 6 PPM; Destiny 1.2 PPM / Brain Hacker 1 PPM; Crusader 1 PPM | various | GH:c593cab, GH:8c0943d, GH:ebab8a4, GH:c752c00 |
| 11-18 | Mutilator 4.8 PPM (Lacerations); Flame Wrath 1.9 PPM; Malown's Slam 1.8 PPM (53 Strength, 20 s); Force of Will 6% per melee hit taken, 30 s cooldown, 10 s buff | | GH:5829ef6, GH:69628a0, GH:1db374c, GH:f5b10bc |
| 11-18 | Revelation rolls on spells only and scales with spell level | ramp clamp((SpellLevel+32-level)/20,0,1) | GH:5749b42 |
| 11-20 | Blackrock Slicer 1.9 PPM; Claymore of Two Moons 1.35 PPM (Waning Moon 10 s Strength); Iceblade Hacker 2.05 PPM | | GH:a4121e1, GH:b32b784, GH:b282925 |

Sim-side rulings that tell us how procs are counted: a weapon proc's strike rolls weapon procs again only off a main-hand white swing (R-0040/EV-0145). A druid's form-paw swing chains nothing. Windfury Totem's strike logs 6-20 ms **before** its damage event (GH:2023c80). Spell Piercing bonus hits log as "(10% Pierced)" in the sim's own log (not the game's).

---

## Addon API / UI / secret values / combat log

| Date | Finding | Source | Affects | Conf. |
|---|---|---|---|---|
| 11-20 | **Relayed** WoWUIDev Discord notes (12.1.7 PTR 6): "The realm ID in creature, vehicle, pet and game object GUIDs is now obfuscated along with the server ID and spawn ID. **This will also apply to Forever in an upcoming 1.60.1 hotfix.**" Also: most C_Intl APIs reject secret values from tainted code; custom community-invite link text is rejected, "will also apply to Forever in a future patch". A forum player pasted it; the post's own claim that "the Nov 24th patch disables Layer addons" is speculation. | https://us.forums.blizzard.com/en/wow/t/2423386 (post 1) | Anything that parses GUID fields (NPC id extraction from a GUID is the likely exposure; realm-ID parsing breaks) | F (quoting official notes) |
| 11-14 | Player report: since ~11-13 the minimap-tracking tooltip text is a secret value for addons (reporter's guess: a server-side change; client build was still 70888). | https://us.forums.blizzard.com/en/wow/t/2415650 | none directly | F |
| 11-17 | Player report: the Forever aura API only exposes buffs on friendly and debuffs on hostile units, so Arcane Blast (a debuff on the player) cannot be read by custom trackers. This describes behaviour, not a new change, and was not checked against the live client. | https://us.forums.blizzard.com/en/wow/t/2419742 | Spell Timer (Arcane Blast and other self-debuffs) | F |
| 11-17 | Player report: Blizzard UI errors with no addons ("attempt to compare ... a secret number value ... ForceTaint_Strong" in `HealthBar.lua`). | https://us.forums.blizzard.com/en/wow/t/2420339 | none | F |
| 11-06..11-20 | Cooldown Manager changes are listed in a2/a3 (Reckless Swings, Redoubt, Maelstrom Weapon, Thunder Clap, Berserk/Lacerate, Seals, CC durations). Players ask for more entries (Demoralizing Shout, Maelstrom 5-stack alert), which suggests the manager's spell list is curated per class. | HF; topics 2415855, 2423269, 2407499 | Cooldown bar overlap | P (HF), F (requests) |
| 11-13 | UI: Action Bar settings no longer reset on logout for players with secondary talents (dual spec). | HF Nov 13 | none | P |
| 11-17 | UI: ignore lists persist across logout; Master Swordsmith/Axesmith/Hammersmith UI fix. | HF Nov 17 | none | P |
| 11-20 | UI: Group Finder showed fewer groups than intended (fixed). | HF Nov 20 | none | P |
| any | **Combat log**: no Blizzard note. wowsims commit text notes that Hellfire Effect, Windfury Totem strikes and weapon-proc strikes log as separate events in a specific order (see a4). | GH:b421b80, GH:2023c80 | item procs | M |
| any | **Secret values / API**: Blizzard's hotfix notes have no mention of addon API or secret values; the repo's `docs/api` mirror was not compared because nothing public documents 70938 -> 71037 API changes. | HF full read | n/a | P (absence) |

---

## (b) Not found / blocked

| Source | Result |
|---|---|
| Forum page `.../2360696/9` (HTML) | Not fetchable: the fetch tool has no headless browser. The public JSON `.../t/2360696.json` works. **That thread's last post is 2026-11-04 19:35 (post 10)**; nothing newer exists. The 11-03 post is the 44 KB post 9 we already mined. |
| Forum hotfix thread 2403040 | Works via `https://us.forums.blizzard.com/en/wow/t/2403040.json`. Posts 1 and 4-14 read. No Nov 21 post exists yet. Post 1 is a rolling compilation with the Nov 5 - Nov 20 notes. |
| Forum search (`search.json`) | Works. Used to find 2403040, 2423811, 2423386, 2415650, 2419742, 2420339. No Blizzard "known issues" thread found for 1.60.1. |
| `worldofwarcraft.blizzard.com/en-us/news/forever` | 404. A forum post (2423811) says the launcher's "patch notes" link goes to a different game, and the real notes live in the bug-report forum thread. No Blizzard support article with build numbers found. |
| Wowhead (`/forever/news`) | HTTP 200 but returns an empty JS shell; no news items readable. Spell/class pages were not tried. |
| Icy Veins, Reddit, X/Twitter | Not fetched. `web_search` returned only generic landing pages (YouTube, Wikipedia, home pages), no patch-note pages. |
| warcraft.wiki.gg (`Patch_1.60.1`, `/API_changes`) | HTTP 403 for scripted fetch. Wayback not tried. |
| uiforever.com | Home and `/compat` load (a marketing page and an addon compatibility matrix for Details!, DBM, BigWigs, Plater, etc.). `/changelog`, `/api`, `/docs`, `/releases`, `/news`, `/whats-new`, `/addons` are 404. **No release notes or API-version notes exist** on the site. The browser-based fetch also failed with "no chromium", so only the raw HTML was read. |
| Tracker repos (CooldownMaster, WeakAuras-for-Forever forks, OmniCD, TidyPlates ThreatPlates) | GitHub search found no such repos for Forever. EllesmereUI forks (`nobewayo/EllesmereUIForeverFix`, `JimmyRustling/forever-addons`, `soockee/EllesmereUIShamanProfiles`) have no commits since 11-12 that mention a build fix (the first two returned no commits in the range). |
| wowsims/forever commits | Worked, unauthenticated, 998 commits since 11-12 (10 pages). I read headlines for 11-12..11-18 and full bodies for the hotfix/DB-push commits and most of 11-18..11-21. Commit bodies of the "Update items" commits are empty; their file diffs were read for 71037 (`d013825`, `42cb97b`, partially `b9a7a37`). The `spell_store_inputs.json` patches are too large for the API (no patch returned). No releases or GitHub release notes exist. |
| Docs mirror (`docs/api`) | Not checked in this session; no public API changelog for 70938 -> 71037 was found to compare against. |

---

## (c) Open questions the live client must answer

1. **Windfury Totem**: does the player get any aura/buff event when the totem proc fires (spell 10610 is now a weapon strike)? What does the combat log show for the strike (SPELL_DAMAGE vs SWING_DAMAGE, source, name "Windfury Totem (Attack)")? Does the raid aura 10612 still appear in the player's buff list and with what duration?
2. **Maelstrom Weapon**: the exact buff spell id, max stacks (5), duration, and the displayed chance (60% at 3.6 speed) so we can verify "6-10 per minute scaled by main-hand speed". Is the stack count readable by addons (not secret) for self?
3. **Stormstrike**: confirm the 8 s cooldown from `GetSpellCooldown`, and that Windfury Weapon plus Windfury Totem can both be active.
4. **Unsealed Wrath**: is the 0.1 s cooldown visible in the tooltip, and is the echo "buff" aura trackable?
5. **Stormshroud Armor 3pc**: is the in-game tooltip "3% ... 18 energy" and is there an ICD? (The data row has none.) Which spell id appears on the combat log (23863 vs 23864)?
6. **Seed of Renewal (219326)**: confirm 40% / 120 s ICD in the tooltip and whether the 30 s seed aura (443678) shows on the enemy (debuff on hostile = readable?).
7. **Rogue (70959/71037)**: Boot Knife aura 1329285, Tier 1 5P Death Mark cost reduction, whether Mutilate's cast still triggers main-hand poison (sim author's reading of the 11-21 hotfix, not in any Blizzard note).
8. **Aura API visibility**: can addons read the Arcane Blast self-debuff, Flurry, Reckless Swings and Maelstrom stack counts, and which aura filters return secret values on 71037? (player claim: only friendly buffs / hostile debuffs).
9. **GUID obfuscation**: has the "upcoming 1.60.1 hotfix" shipped in 71037? Does `UnitGUID`/`CombatLogGetCurrentEventInfo` still return a numeric realm field, and does our NPC-id parsing survive?
10. **Cooldown Manager overlap**: which of our tracked spells are now first-class there (Reckless Swings, Redoubt, Maelstrom Weapon, Lacerate, Seals, CC durations), so we can drop duplicates or align names.
11. **Vampiric Embrace**: confirm 10% heal and the +100% self-heal text and the buff duration (unchanged?).
12. **Wild Growth**: all ranks now share one cooldown category; confirm `GetSpellCooldown` on each rank.
13. **Revelation**: is the proc chance on the tooltip 8% and the proc truly spell-only (EV-0149)? ICD and buff duration unchanged?
14. **Crafted T1 set pieces** in the 71037 `db.json` (items 273884-273951): did bonuses, sources or required profession change? I did not diff them.
15. **Layer addons / "Nov 24th patch"** claim: is there an official note? None found.
16. Several measured proc rates in a4 conflict with nothing in the game files but are fits. Any tracker that shows a proc "chance" should read the tooltip rather than reuse them.

## Method notes

- Commit data came from `api.github.com/repos/wowsims/forever/commits?since=2026-11-12T00:00:00Z` (10 pages, 998 commits) and `/commits/<sha>` diffs.
- Forum data came from the public Discourse JSON of topics 2403040, 2360696, 2423811, 2423386, 2415650, 2419742, 2420339, 2423234, 2407499, 2415855, 2423269, 2409463, 2424256, read on 2026-11-21.
- Where a table row cites both P and G-msg, the Blizzard note gives the player-facing change and the wowsims commit gives the spell-level detail.

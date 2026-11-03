# Blizzard WoW Forever Beta development notes — what matters to ForteXorcist

Source (owner-supplied): "WoW Forever Beta Development Notes – Updated November 2",
https://us.forums.blizzard.com/en/wow/t/wow-forever-beta-development-notes-%E2%80%93-updated-november-2/2360696/9
(posts by Kaivax; read 2026-11-03 by the manager). Post 9 (2026-11-03) lists the changes made "since the last full
update to the Beta on October 15" — i.e. very likely **newer than client build 1.60.1.70707**, the build our generated
data and the API catalog are pinned to. The launch build (2026-11-04) is expected to carry them.

## 1. Data the addon shows (cooldowns, durations, spell names) — cross-checked by `DataScout2`

| Class | Change (post 9) | Our impact |
|---|---|---|
| Warrior | Slam cooldown 15 s (was 18); Improved Slam 2.5/5 s; new talent **Reckless Swings** (15 s cd) | Slam row value; candidate new row |
| Shaman | **Lava Burst removed** (passive Call of Thunder replaces); **Totemic Projection → Totemic Call**, cd 30 s; **Elemental Mastery → Lightning Mastery**; Stormstrike cd 6 s (was 8); Riptide cd 12 s (was 6), no initial heal; Chain Lightning cast 2.5 s | T1 added Lava Burst — remove; renames + values |
| Mage | Ice Lance gets an 8 s cooldown **shared with Fire Blast**; Arcane Blast 18 s; Frost Blast removed; Piercing Ice removed | shared category on the bar; values |
| Hunter | **All traps share one 30 s cooldown** (was separate Fire/Frost); Hunter's Mark one rank per target; Aimed Shot / Arcane Shot / Serpent Sting damage up | trap category law on the bar |
| Druid | **Berserk talent removed** (Primal Bite replaces); Lacerate is a Feral talent; Ferocious Bite new rank 1; Shifting Power is a talent; Wild Growth 3 s cast; new talent Bloom | T1 added Berserk — remove |
| Rogue | **New spell Shank** (level 24, 10 s cd); **new talent Death Mark** (active, 10 s cd, 6 s mark); Poised passive; Thousand Cuts, Cutthroat, Murder, Improved Distract removed | add Shank + Death Mark |
| Paladin | **Blessing of Light removed**; Salvation, Mass Salvation, Revoke removed (70707 already had these three gone); Righteous Fury at level 10; Swift Judgement no longer shares Judgement's cooldown; new **Oath of Light** (no cd, 5 min oath) | drop Blessing of Light (our 26650 row had no captured values) |
| Racials | Orc **Blood Fury cd 2 min** (was 3); Troll Berserking 15 s; Undead **Touch of the Grave ICD 15 s** (was 25); Skyborne Read Leyline 15 s | racial rows / proc ICD |

Earlier posts (Sept–Oct) for reference: Mangle renamed **Primal Bite**; Shaman totems no longer stack in a group.

## 2. Client/UI facts

- **Blizzard's own UI has swing timers** ("Fixed an issue where the Off-Hand Swing Timer could fail to appear after
  logging in on dual-wielding characters"). Our Hunter bar is independent; worth a launch-day look for overlap.
- **Throw** now uses the 0.5 s windup with the throwing weapon's speed (a non-Hunter ranged swing; not tracked by us).
- "Improved Gamepad UI compatibility with user-created add-ons" — gamepad UI and addons coexist better.
- Blizzard **Cooldown Manager** known issues (post 1): Healthstone cooldown, **pet cooldowns** and **item enhancements
  (Windfury, rogue poisons)** "cannot be tracked"; Banes/Curses lose tracking on target re-acquire; Mana gem needs an
  extra cast. These hint at what the client exposes — add as launch-day probes for our bar (healthstone cooldown,
  pet cooldowns, weapon enchants, curse re-acquire).
- Bags no longer auto-equip; learning spells no longer auto-adds them to action bars (no impact).

## 3. Actions (planned in PLAN §11.2 wave I-2)

1. Data refresh: apply the post-9 values/removals/renames/new spells where the upstream data does not already carry
   them — as a documented `post9` override layer if the data lags the notes.
2. Hunter trap shared-cooldown and Mage Ice Lance/Fire Blast shared category on the cooldown bar.
3. Launch-day probes: healthstone, pet and weapon-enchant cooldown readability; curse tracking on target re-acquire;
   swing bar vs Blizzard's swing timer.

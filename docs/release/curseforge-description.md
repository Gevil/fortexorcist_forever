<!--
CurseForge project: ForteXorcist Forever  (slug: fortexorcist-forever)
Paste the SUMMARY into the "Summary" field and everything under "DESCRIPTION" into the description
editor set to Markdown. Keep in sync with README.md.
-->

## SUMMARY (one sentence, ~190 characters)

Cooldown timeline, spell timers and class tools for WoW Forever - a rebuild of the classic ForteXorcist, written for Forever's modern API and its combat restrictions.

## DESCRIPTION

# ForteXorcist Forever

A rebuild of the classic **ForteXorcist** addon for **World of Warcraft: Forever** (client 1.60.1). One cooldown bar, per-target spell timers and class tools, in the original's look (Classic skin, URW Gothic font, the original's textures), written for the Forever client's modern API and its combat restrictions.

> **A separate rewrite.** This is a new codebase for Forever. It is not the TBC Classic ForteXorcist builds that exist elsewhere on CurseForge.
> **Install note:** the download contains 16 small addons (Forte_Core, Forte_Cooldown, Forte_Timer ...). Install all of them; only the ones for your own class load their data.

## What you get

- **Cooldown Timer** - one horizontal bar on a power-scale time axis. Icons slide left as cooldowns burn down, overlapping icons cross-fade, charge counts, a failed-cast warning flash, vertical / flipped / hide-when-empty modes. Also tracks trinkets, potions and weapon enchants.
- **Secondary Splash** - the original's big pop of a cooldown's icon the moment it comes ready.
- **Spell Timer** - stacked rows per spell and target, grouped by target and coloured by kind (your own casts, your pet's, Shaman totems by element). Choose whether the stack grows up or down from where you place it.
- **Messages & Sound** - the original's crowd-control fade/break warnings and sounds, self messages, and optional party/raid announcements.
- **Options window** - the original-style window with per-character or shared profiles; every setting applies live.
- **Hunter tools** - an Auto Shot swing bar with the full shot cycle (orange = reload, red = stand still while the shot aims, white = the shot left, move or cast freely), Aimed/Multi-Shot clip marking, an optional melee-weave line and melee swing rail, a range light and an aspect-missing reminder.
- **Warlock tools** - Shard Manager, Soulstone Tracker, Healthstone Spy and Summon Assistant plates.
- **Spell and item data for all nine Forever classes** - generated from the live game data, loaded only for your own class, and working on localized clients.

Everything is **off or quiet by default where it matters**: a fresh install sends nothing to party or raid chat; announcements are opt-in.
(Exception, as in the original: with the Warlock tools, "Group comms" lets ForteXorcist users in your group share stone and shard counts over the hidden addon channel. It only sends while you are in a group, never solo, never as chat text, and you can switch it off in the Warlock options.)


## Commands

| Command | What it does |
|---|---|
| `/fx options` | open / close the options window |
| `/fx unlock` / `/fx lock` | unlock to drag the frames, lock them again |
| `/fx reset` | reset frame positions |
| `/fx status` | one status block per module |
| `/fx test` | demo mode: fills the bars with synthetic entries so you can set up the layout |
| `/fx timer status` / `clear` | Spell Timer status / clear its rows |
| `/fx probe` | diagnostics you can paste into a bug report |

## How it works (and why some timers are predicted)

On Forever, addons cannot read the combat log and many buff and cooldown values are hidden ("secret") during combat. ForteXorcist predicts timers from your own casts, uses the values the game keeps readable in combat, and corrects itself whenever the real values can be read again. A predicted timer can therefore be briefly off until the game confirms it; the addon never touches protected values.

## Good to know

- Built for **WoW Forever 1.60.1** (interface 16001). Not for Retail or Classic Era.
- Spell data tracks the live game data; Blizzard's balance changes land in an addon update shortly after they go live.
- Some spells from the Season of Discovery era exist in the data but are not in Forever's spellbook; they stay hidden because the addon only tracks spells you actually know.
- Found a problem? Please report it on GitHub with the output of `/fx probe`.

## Links

- Source code, issues and full documentation: https://github.com/Gevil/fortexorcist_forever
- Issue tracker: https://github.com/Gevil/fortexorcist_forever/issues

## Credits and licence

- **ForteXorcist** - the original addon by **Xus** (GPL-3.0); the original's textures are included unmodified, see the attribution file inside `Forte_Core`.
- **URW Gothic** (URW++, AGPL-3.0 with font exception) - the shipped lookalike of Century Gothic.
- **WeaponSwingTimer** (LeftHandedGlove, GPL-3.0; the Forever build by WatchYourSixx) - the Hunter swing bar's shot-cycle model is adapted from it.
- **CooldownMaster** (MIT) - reference for the Forever-safe cooldown engine design.
- **wowsims/forever** and **mythicsim-forever-engine** (MIT) - spell and item data; **JBurlison/WoWAddonAPIAgents** (MIT) - the pinned Forever API reference.

Licensed under **GPL-3.0**. Not affiliated with or endorsed by Blizzard Entertainment.

---

## SCREENSHOTS TO UPLOAD (Images tab) - all from the repo's docs/demo folder

1. `live-cooldown-bar.gif` - cooldown bar + Spell Timer running
2. `cooldown-bar-and-timer.png` - bar with time tags above two target groups
3. `hunter-swing-signals.gif` - Hunter swing bar signals
4. `warlock-plates.png` - the four Warlock plates
5. `options-window.png` - the options window

## SUGGESTED SETTINGS

- Game: World of Warcraft - Addons. Main category: **Buffs & Debuffs**; additional: **Combat**, **Damage Dealer**, **Hunter**, **Warlock** (add more classes if the form allows).
- License: **GNU General Public License v3 (GPL-3.0)**.
- Comments on; Issue tracker URL `https://github.com/Gevil/fortexorcist_forever/issues`; Source URL `https://github.com/Gevil/fortexorcist_forever`.
- Logo: an original 400x400 PNG (not the WoW logo and not the original addon's `ForteXorcist.blp` art).

# ForteXorcist for WoW Forever

A rebuild of the classic **ForteXorcist** addon (cooldown timeline, spell timers, class tools)
for **World of Warcraft: Forever** — written for the Forever client's modern API and its
combat restrictions, with the original's look (Classic skin, URW Gothic font, the original's
textures).

> Status: **pre-release**, built and tested in two simulators (wow-ui-sim, uiforever.com);
> first real-client session is launch day (see [`docs/launch-day.md`](docs/launch-day.md)).
> Plan, decisions and the full test record: [`PLAN.md`](PLAN.md).

## Screenshots

<p align="center">
  <img src="docs/demo/live-cooldown-bar.gif" alt="Cooldown bar and Spell Timer running live: icons slide along the power-scale bar, a ready cooldown pops as a Secondary Splash, timer rows count down" width="600"><br>
  <em>Live in a Forever-style client (uiforever.com): cooldowns slide along the power-scale bar, Kick pops ready as the
  Secondary Splash, Spell Timer rows count down per target. (<a href="docs/demo/live-cooldown-bar.mp4">MP4</a>)</em>
</p>

| Cooldown Timer + Spell Timer | Warlock plates |
|---|---|
| <img src="docs/demo/cooldown-bar-and-timer.png" alt="Cooldown bar with time tags above two Spell Timer target groups" width="420"> | <img src="docs/demo/warlock-plates.png" alt="The four purple Warlock plates: shards, soulstone, summon, healthstone" width="420"> |

<p align="center">
  <img src="docs/demo/hunter-swing.gif" alt="Hunter Auto Shot swing bar: orange reload, red stand-still aim window, white safe-to-move bar after the shot" width="460"><br>
  <em>Hunter swing bar: orange while reloading, red = stand still (the shot is aiming), white = the shot left, move or
  cast freely. (<a href="docs/demo/hunter-swing.mp4">MP4</a>)</em>
</p>

<p align="center">
  <img src="docs/demo/warlock-plates.gif" alt="The four purple Warlock plates: shard counter, soulstone timer, summon queue and healthstone row updating" width="640"><br>
  <em>Warlock plates rendered at 30 fps from the addon itself in the wow-ui-sim simulator (manual clock): the shard
  counter, the soulstone timer counting down, the summon queue and the healthstone row. (<a href="docs/demo/warlock-plates.mp4">MP4</a>)</em>
</p>

<p align="center">
  <img src="docs/demo/options-window.png" alt="The original-style options window with its 16-cell module index" width="620"><br>
  <em>The options window in the original's style: profile tabs, module index, every setting applies live.</em>
</p>

## What it does today
| Module | What you see |
|---|---|
| **Cooldown Timer** (`Forte_Cooldown`) | One horizontal bar on a power-scale time axis; icons slide left as cooldowns burn, overlapping icons cross-fade, coloured segment fills, cast splash and ready pulse, charge counts, a failed-cast warning flash, vertical/flipped/hide-when-empty modes, trinkets/potions (`Forte_Items`) and weapon enchants |
| **Secondary Splash** | The original's big pop of a cooldown's icon the moment it comes ready |
| **Spell Timer** (`Forte_Timer`) | Stacked rows per spell and target, grouped by target, coloured by kind, with the original's reconciliation rules (own and pet casts predicted; corrected from real auras out of combat); Shaman totems by element |
| **Messages & Sound** (`Forte_Messages`) | The original's crowd-control fade/break warnings and sounds (Banish, Fear, Polymorph, Sap, Seduction…), self messages, and party/raid announcements — all chat to other players is opt-in and respects Forever's chat restrictions |
| **Hunter tools** (`Forte_Hunter`) | Auto Shot swing bar with the full shot cycle (orange reload, red stand-still aim window, white safe-to-move window after the shot), Aimed/Multi-Shot cast tracking and clipping, movement/Feign Death handling, a range light, and the aspect-missing reminder |
| **Warlock tools** (`Forte_Warlock`) | Shard Manager, Soulstone Tracker, Healthstone Spy (shares stone counts with your group), Summon Assistant plates |
| **Options** (`Forte_Options`) | The original-style options window with per-character or shared profiles; every setting applies live |
| **Spell data** (`Forte_<Class>`) | Generated cooldown/duration data for all nine Forever classes (~590 spells, live build 1.60.1.70707), loaded only for your own class, working on localized clients |

### Why some things are predicted
On Forever (Retail 12.x engine) addons cannot read the combat log, and most buff/cooldown
values are hidden ("secret") during combat. ForteXorcist predicts from your own casts, uses
the values the game keeps readable in combat, and corrects itself whenever real values are
readable. Background: [`docs/design-combat-procs.md`](docs/design-combat-procs.md),
[`docs/research/secrets-unknowns.md`](docs/research/secrets-unknowns.md).

## Commands
| Command | |
|---|---|
| `/fx options` (`/fx config`) | open / close the options window |
| `/fx lock` · `/fx unlock` · `/fx reset` | lock, unlock (drag frames), reset positions |
| `/fx status` | one status block per module |
| `/fx timer status \| test \| clear` | Spell Timer status, a demo, clear rows |
| `/fx probe` · `/fx probe show` · `/fx probe bar` | launch-day diagnostics (stored in SavedVariables) |

## Install
Copy each folder in `addon/` into `World of Warcraft/_forever_/Interface/AddOns/`, or from a
checkout run `scripts/deploy.sh --copy` (copy mode: tools that rewrite addon `.toc` files
must never write into the git tree through a symlink). Each addon ships `X.toc` and an
identical `X_Camelot.toc`.

## Development
```
addon/      the addons the game loads
tools/      spell / item data generators (python3 tools/gen_spell_data.py <class>)
scripts/    gate.py (full verification gate), api_lint.py, deploy.sh
docs/       design, research, reviews, API references, media index
```
`python3 scripts/gate.py` runs every simulator test suite, a live load probe, toc-twin and
syntax checks, the API/event lint (every API and event must exist in the pinned Forever
catalog) and the data-determinism check.

## Credits
- ForteXorcist — original addon by Xus (GPL-3.0); textures vendored unmodified, see
  `addon/Forte_Core/ATTRIBUTION.md`.
- URW Gothic (URW++, AGPL-3.0 with font exception) — the shipped lookalike of Century Gothic.
- [CooldownMaster](https://github.com/wheelbarrel00/CooldownMaster) (MIT) — reference for the
  Forever-safe cooldown engine design.
- [WeaponSwingTimer SixxFix](https://www.curseforge.com/wow/addons/weaponswingtimer-sixxfix) by WatchYourSixx
  (original WeaponSwingTimer by LeftHandedGlove, GPL-3.0) — the Hunter swing bar's shot-cycle model
  (aim window, safe-to-move window, cast/clipping machine) is adapted from its Forever build.
- [mythicsim-forever-engine](https://github.com/sage3648/mythicsim-forever-engine) (MIT) and
  [wowsims/forever](https://github.com/wowsims/forever) (MIT) — spell and item data.
- [JBurlison/WoWAddonAPIAgents](https://github.com/JBurlison/WoWAddonAPIAgents) (MIT) — pinned
  Forever API catalogs; [Osso/wow-ui-sim](https://github.com/Osso/wow-ui-sim) — simulator and
  behavioural specs; [uiforever.com](https://uiforever.com) — browser simulator.
- [Thunderz96/forever-addon-kit](https://github.com/Thunderz96/forever-addon-kit) — measured client findings.

## License
GPL-3.0 (see `LICENSE`).

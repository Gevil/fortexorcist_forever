# ForteXorcist for WoW Forever

A rebuild of the classic **ForteXorcist** addon (cooldown timeline, spell timers, class tools)
for **World of Warcraft: Forever** — written for the Forever client's modern API and its
combat restrictions, with the original's look (Classic skin, URW Gothic font, the original's
textures).

> Status: **pre-release**, built and tested in two simulators (wow-ui-sim, uiforever.com);
> first real-client session is launch day (see [`docs/launch-day.md`](docs/launch-day.md)).
> Plan, decisions and the full test record: [`PLAN.md`](PLAN.md).

## What it does today
| Module | What you see |
|---|---|
| **Cooldown Timer** (`Forte_Cooldown`) | One horizontal bar on a power-scale time axis; icons slide left as cooldowns burn, overlapping icons cross-fade, coloured segment fills, cast splash and ready pulse, charge counts, trinkets/potions (`Forte_Items`) and weapon enchants |
| **Spell Timer** (`Forte_Timer`) | Stacked rows per spell and target, grouped by target, coloured by kind, with the original's reconciliation rules (own casts predicted; corrected from real auras out of combat) |
| **Hunter tools** (`Forte_Hunter`) | Auto Shot swing bar, aspect-missing reminder |
| **Warlock tools** (`Forte_Warlock`) | Shard Manager, Soulstone Tracker, Healthstone Spy, Summon Assistant plates |
| **Options** (`Forte_Options`) | The original-style options window: General, Cooldown Timer, Spell Timer, Hunter Tools and Warlock pages; every setting applies live |
| **Spell data** (`Forte_<Class>`) | Generated cooldown/duration data for all nine Forever classes (530 spells) |

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
- [mythicsim-forever-engine](https://github.com/sage3648/mythicsim-forever-engine) (MIT) and
  [wowsims/forever](https://github.com/wowsims/forever) (MIT) — spell and item data.
- [JBurlison/WoWAddonAPIAgents](https://github.com/JBurlison/WoWAddonAPIAgents) (MIT) — pinned
  Forever API catalogs; [Osso/wow-ui-sim](https://github.com/Osso/wow-ui-sim) — simulator and
  behavioural specs; [uiforever.com](https://uiforever.com) — browser simulator.
- [Thunderz96/forever-addon-kit](https://github.com/Thunderz96/forever-addon-kit) — measured client findings.

## License
GPL-3.0 (see `LICENSE`).

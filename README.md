# ForteXorcist Forever

Cooldown and spell timers, expiry warnings and a few class tools for **World of Warcraft: Forever**.
It is a rebuild of the classic **ForteXorcist** addon (2012, by Xus) for the Forever client's modern
API and its combat restrictions. It keeps the original's look (Classic skin, URW Gothic font, the
original's textures). It is not a port of the 2012 code.

**Version 1.0.0** · client **WoW Forever 1.60.1** (interface `16001`) · license **GPL-3.0**

## Who it is for

Players who want the original ForteXorcist's cooldown bar and spell-timer rows on Forever, with the
options window they remember. It has the most class-specific tools for **Hunter** and **Warlock**;
the other seven classes get the shared cooldown bar, Spell Timer and warnings from generated spell
data (details per class below).

## Status

- Built and tested in two simulators (wow-ui-sim and uiforever.com).
- Played on the live Forever client on **Hunter** (first live session 2026-11-06, build 1.60.1.70790);
  bugs found there are fixed (see `CHANGELOG.md`).
- The other eight classes have been tested in the simulators and against the live game data, not
  played live by the author. Please report what you find (see [Reporting issues](#reporting-issues)).

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
  <img src="docs/demo/hunter-swing-signals.gif" alt="Hunter swing bar in its default Safe window mode driven by /fx test: orange reload fill, dim clip band at the left, standing aim zone at the right, live red aim slice, cyan weave line, red cast interlock, white flight" width="460"><br>
  <em>The same bar driven by <code>/fx test</code> with the weave line on: orange = time to the stand-still, the left
  band = Aimed Shot's length, the red end = stand still, white = the shot left; the cyan line = the melee-weave
  budget, the frozen full-width red bar = a cast clips this cycle. (<a href="docs/demo/hunter-swing-signals.mp4">MP4</a>)</em>
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

## Requirements

- World of Warcraft: Forever, client **1.60.1** (interface **16001**). The addon is not for Retail or
  the other Classic clients.
- Nothing else. There are no bundled libraries and no required third-party addons.

## Install

Pick one. All three put the same 16 `Forte_*` folders into
`World of Warcraft/_forever_/Interface/AddOns/`.

1. **CurseForge app.** Open the app, choose your **Forever live installation**, search for
   *ForteXorcist Forever* and install. If the app does not recognise the folders, scan the addons
   folder manually. (This works once the CurseForge listing is approved; until then use 2 or 3.)
2. **WowUp.** *Install from URL*: `https://github.com/Gevil/fortexorcist_forever` on a Forever
   installation. WowUp only offers a GitHub zip to Forever when its name ends in `-forever.zip`;
   release zips are named `ForteXorcist-<version>-forever.zip`.
3. **Manual.** Download `ForteXorcist-<version>-forever.zip` from the
   [GitHub releases](https://github.com/Gevil/fortexorcist_forever/releases), unzip it, and copy the
   `Forte_*` folders into `World of Warcraft/_forever_/Interface/AddOns/` (not `_retail_`). Each
   folder must sit directly in `AddOns`, e.g. `AddOns/Forte_Core/Forte_Core_Camelot.toc`.

Each folder ships `Forte_X.toc` and an identical `Forte_X_Camelot.toc` (the Forever client reads the
`_Camelot` one). To check a release zip, compare it with the `.sha256` file next to it:
`sha256sum -c ForteXorcist-<version>-forever.zip.sha256`.

From a git checkout: `scripts/deploy.sh --copy` (copy mode, so tools that rewrite `.toc` files never
write into the git tree through a symlink).

## The 16 folders

| Folder | What it does |
|---|---|
| `Forte_Core` | Required by every other folder. Bootstrap, Forever compat layer, constants, saved-variables store and profiles, event bus, the `/fx` command, `/fx probe`, `/fx log`, `/fx test`, and the shared textures, font and sound. |
| `Forte_Cooldown` | **Cooldown Timer** (one bar on a power-scale time axis), **Secondary Splash**, the cooldown engine behind them: spells, trinkets and potions, weapon enchants, racials, optional item procs. |
| `Forte_Timer` | **Spell Timer**: stacked rows per spell and target. |
| `Forte_Messages` | **Messages & Sound**: self messages, banner, sounds, opt-in party/raid announcements. |
| `Forte_Options` | The options window (`/fx options`) with profiles. |
| `Forte_Items` | Generated item data: 238 on-use items, 79 consumables, 5 weapon enchants. |
| `Forte_ItemProcs` | Generated item proc data (400 rows). Load-on-demand; only read when you switch on **Procs** on the Cooldown Timer page (off by default). |
| `Forte_Druid`, `Forte_Mage`, `Forte_Paladin`, `Forte_Priest`, `Forte_Rogue`, `Forte_Warrior` | Generated spell data for that class (cooldowns, durations, GCD, cast times). Load-on-demand: only your own class's folder is loaded. |
| `Forte_Hunter` | Hunter spell data plus the Hunter tools (swing bar, range light, melee rail, aspect reminder). |
| `Forte_Shaman` | Shaman spell data plus the totem tracker. |
| `Forte_Warlock` | Warlock spell data plus the four Warlock plates and group comms. |

The class folders are `LoadOnDemand`; Forte_Core loads yours at login. Spell data is generated from
the game's own data (about 630 spell rows for the nine classes, live build 1.60.1.70862) and works on
localized clients; rows are keyed by the English name and joined to your client's names by spell and
item id.

## What it does

### Shared (all classes)

| Module | What you see |
|---|---|
| **Cooldown Timer** | One horizontal bar on a power-scale time axis. Icons slide left as cooldowns burn; overlapping icons cross-fade; coloured segment fills, a cast splash and a ready pulse, charge counts, a flash when you try to cast a spell on cooldown (option *Warn*), vertical / flipped / hide-when-empty modes. It also tracks trinkets and potions (`Forte_Items`), weapon enchants and the racials Berserking and Rapid Regeneration. Right-click the bar (without dragging) to open its options page. |
| **Secondary Splash** | The original's large pop of a cooldown's icon the moment it is ready (off until you tick Enable on its page). |
| **Spell Timer** | Rows per spell and target, grouped by target, coloured by kind. Own and pet casts are predicted, then corrected from real auras when you are out of combat. Rows are retired when a target dies. |
| **Messages & Sound** | Fade and break warnings for crowd control (Banish, Fear, Subjugate Demon, Seduction, Polymorph, Sap): a bell about 3 s before it ends and a break sound if it ends early. Optional self messages, a banner, and announcements (see Safety below). |
| **Options** | `/fx options`: a 16-cell module index (one cell, *Talent Spy*, is a dimmed placeholder that has no page), profile tabs, every setting applies live. |

### Per class

| Class | What you get beyond the shared modules |
|---|---|
| **Hunter** | **Auto Shot swing bar** with the whole shot cycle: orange = reloading, red = stand still (the shot is aiming), white = the shot left, so you can move or cast. Three bar modes (*Safe window*, the default; *One bar*; *Single fill*), a standing aim window, a clip band that shows whether Aimed Shot / Multi-Shot fits before the next Auto Shot, an optional melee-weave line (off by default), an optional melee swing rail that shows the main-hand swing (Raptor Strike refills it; opt-in), a colour-blind friendly palette, movement and Feign Death handling. **Range light** (opt-in): MELEE / DEAD 5-8 / 8-35 / 35+ / OUT; ticking it switches on the client's own ranged range check (`C_SwingTimer.EnableRangeCheck`). **Aspect reminder**: an icon pulses out of combat when no aspect is known to be active. Summon Hawk and Arcane Shot share their 6 s cooldown on the bar. The swing model is adapted from WeaponSwingTimer SixxFix (see Credits). |
| **Warlock** | Four purple plates: **Shard Manager** (shard count; read from the bag first, power bar as fallback), **Soulstone Tracker** (the 30-minute window is predicted from your cast; shows the target when the game lets the name be read), **Healthstone Spy** (stones in your bags, dimmed with a clock while the creation cooldown runs), **Summon Assistant** (the Ritual of Summoning channel). **Group comms** (see Safety): in a group, ForteXorcist users exchange stone and shard counts and summon starts, so the spy plates fill in; without the addon on the other side they stay at *unknown*. Succubus Seduction (pet casts) is tracked as a Spell Timer row. |
| **Shaman** | Totem tracker: one Spell Timer row per element (Fire, Earth, Water, Air); a new totem replaces the row of its slot. |
| **Druid, Mage, Paladin, Priest, Rogue, Warrior** | Cooldown bar and Spell Timer rows from the generated class data; Mage Polymorph and Rogue Sap have fade/break warnings; Rogue poisons and other weapon enchants are tracked as windows on the bar; Druid, Paladin and Warrior have opt-in raid announcements for 20 defensive/utility cast rows (6 / 8 / 6). No class-specific frames. |

Item data covers on-use items and consumables (cooldown windows) and weapon enchants. Item **procs**
(400 rows, with internal cooldowns where the data has them) are an opt-in setting on the Cooldown
Timer page.

### Why some things are predicted

On Forever (Retail 12.x engine) addons cannot read the combat log, and most buff and cooldown
values are hidden ("secret") during combat. ForteXorcist predicts from your own casts, uses the
values the game keeps readable in combat, and corrects itself whenever real values are readable
(usually after combat). Background: [`docs/design-combat-procs.md`](docs/design-combat-procs.md),
[`docs/research/secrets-unknowns.md`](docs/research/secrets-unknowns.md).

## Commands

`/fx` and `/fortexorcist` are the same command.

| Command | What it does |
|---|---|
| `/fx` | prints the version and a pointer to `/fx status` |
| `/fx status` | version, class, module list, then one status block per module |
| `/fx options` (also `config`, `opt`) | open / close the options window |
| `/fx lock` · `/fx unlock` · `/fx reset` | lock the bars, unlock them for dragging, reset the cooldown bar's position |
| `/fx reset list` · `/fx reset <module>` · `/fx reset all` | reset a module's settings (or all) to the shipped defaults; asks first. `/fx reset confirm` / `cancel` answer in chat. |
| `/fx timer status` · `test` · `clear` | Spell Timer status, a demo feed, clear all rows |
| `/fx test` · `/fx test on` · `off` · `status` | demo mode: fills the cooldown bar, Spell Timer and (Hunter) swing bar with synthetic entries. Refused in combat, never sends chat, never saves. |
| `/fx messages` | Messages & Sound counters |
| `/fx probe` · `/fx probe show` · `clear` · `bar` · `bar off` | diagnostics: records what the game lets addons read, in or out of combat, into the saved variables |
| `/fx log` · `/fx log on` · `off` · `test` | with `on`, every Lua error is copied to chat as `[FX-ERR]` |

## Settings and profiles

- The saved-variables table is `ForteXorcistDB`. Settings are stored **per profile** and only values
  that differ from the shipped defaults are saved, so a changed default in a later version reaches you
  unless you changed that setting yourself.
- Profiles are **per character by default** (keyed by the character's name without realm, because on
  Forever the realm is only a connection label). You can switch to one shared profile, create profiles
  as copies of the current one, rename and delete them (the last one cannot be deleted) on the
  Profiles page or in the tab row of the options window; switching applies live.
- Frame positions (cooldown bar, swing bar, timer panel, Warlock plates, options window) are stored
  outside the profile, so they stay put when you change profile.
- `/fx reset <module>` resets one module's settings for the active profile only.
- Saved-variables file: `World of Warcraft/_forever_/WTF/Account/<ACCOUNT>/SavedVariables/Forte_Core.lua`
  (named after the addon that declares it).

## Safety and privacy

- **No combat log.** `COMBAT_LOG_EVENT_UNFILTERED` is not used anywhere.
- **Secret values.** Every value read from a unit, aura, cooldown, item or power API passes a plain-value
  check before it is compared or stored. A secret (hidden) read never overwrites state the addon already
  knows; it just means "no reliable answer".
- **No chat to other players on a fresh install.** Every party, raid, channel and whisper announcement
  (ready, expiry, fade/break warnings, soulstone, the cast and pet rows) ships **off** and you turn on
  each one on the Party/Raid Messages page. Announcements respect the client's chat-messaging
  lockdown and are skipped, not queued, while it is active. Messages to yourself print only in your
  own chat frame.
- **One exception, Warlock group comms, is on by default.** In a party or raid, `Forte_Warlock` sends
  small *addon-channel* messages (healthstone and shard counts, summon start/stop) that other
  ForteXorcist users read; players do not see them in chat. Solo it never sends. They are
  rate-limited and bounded; during a chat-messaging lockdown they wait in a small queue (lines older
  than five minutes are dropped). Switch them off with
  **Warlock Tools → Raid Spy → Group comms**. Non-Warlocks send nothing.
- **Probe data stays local.** `/fx probe` stores its results in your saved-variables file. A run
  includes plain facts about your character (including its name), so look at the file before you
  share it.
- No analytics, no telemetry. The addon has no network access.

## Known limitations

- **Predicted timers.** In combat, buff, debuff and many cooldown values are hidden. Rows show
  predicted times from your own casts and are corrected when the real values can be read, so a row can
  be off by a little until then, and a haste or talent effect the data does not model can make the
  prediction early or late.
- **No combat-log features.** Anything the original did from the combat log is not possible here
  (for example the Priest's Rapture cooldown).
- **Season of Discovery rune spells.** The generated class lists contain some names that come from
  rune-era Season of Discovery spells; the research could not confirm any of them as learnable on
  Forever (`docs/research/live-*-2026-11-09.md`). The cooldown bar only shows spells your character
  knows, so such a row stays invisible unless the game does let you learn it.
- **Other players' state is mostly unknown.** Raid-wide soulstone/healthstone/shard information
  depends on the other players running ForteXorcist (Warlock comms); the Summon Assistant does not
  read rosters, distances or maps.
- **Talent Spy** is listed in the options index but not built.
- **Non-English clients.** Spell and item names are joined to the generated data by id, so tracking
  works on localized clients; this was tested with simulated German names and on a German client in
  uiforever, not on a live localized client. The addon's own texts (options, messages) are English
  only. Some names with no data row (for example `Auto Shot` in the Hunter fallback, the Soul Shard
  item, `Soulstone Resurrection`) are compared in English and may not match on a localized client;
  see `docs/localization.md`.
- **Live verification is partial.** Only Hunter has been played live by the author; the probe
  questions listed in `docs/VERIFICATION.md` and `docs/launch-day.md` are still open where marked.
- **Persistence** of profiles depends on the client writing SavedVariables normally; `/fx probe`
  reports whether the round trip works (the `EPOCH` and `SV` lines).

## Troubleshooting

- **Nothing shows up.** Check the folders are in `_forever_/Interface/AddOns/`, directly (not inside
  another folder), and that `/fx status` prints a module list. If the client lists the addons as out of
  date after a patch, enable *Load out of date AddOns* on the AddOns screen.
- **Bars are locked and you cannot move them.** `/fx unlock`, drag, `/fx lock`.
- **A bar is in the wrong place or gone.** `/fx reset` resets the cooldown bar; `/fx reset <module>`
  resets a module's settings.
- **A Lua error.** `/fx log on` copies every error to chat as `[FX-ERR]`; copy that line into the issue.
- **Something reads wrong in combat.** Run `/fx probe` out of combat and again in combat (it opens in a
  copy window; click the text, `Ctrl-C`), and attach both blocks. `/fx probe bar` shows a bar fed by a
  duration the addon builds itself, to see whether that ticks in combat.
- **Starting over.** Quit the game, then delete `ForteXorcistDB` entries from
  `SavedVariables/Forte_Core.lua` (or the whole file) in the `WTF` folder shown above.

## Reporting issues

Open an issue at <https://github.com/Gevil/fortexorcist_forever/issues> and include:

```
ForteXorcist version:        (the line printed by /fx, or the About page)
Game build:                  (the About page, or /fx probe's PROBE line)
Class / spec:
What you did:
What you expected:
What happened instead:       (screenshot if it is visual)
In combat or out of combat:
Lua error text:              (/fx log on, then paste the [FX-ERR] line)
/fx status output:
```

## Development

```
addon/      the addons the game loads (16 folders)
tools/      spell / item data generators (python3 tools/gen_spell_data.py <class>)
scripts/    gate.py (full verification gate), api_lint.py, deploy.sh, release.py, release_notes.py
docs/       design, research, reviews, API references; start at docs/README.md
```

`python3 scripts/gate.py` runs every simulator test suite, a live load probe, toc-twin and syntax
checks, the API/event lint (every API and event must exist in the pinned Forever catalog) and the
data-determinism check. Never hand-edit `addon/*/Data/*.lua`; they are generated.

Releasing: `VERSION`, every `.toc` and `Forte_Core/Core/Constants.lua` carry the version; a `v*` tag
triggers `.github/workflows/release.yml` (BigWigs packager, `.pkgmeta`) to publish to GitHub and
CurseForge. `python3 scripts/release.py` builds the same payload locally
(`dist/ForteXorcist-<version>-forever.zip` and its `.sha256`). Owner steps for the CurseForge
project: [`docs/release/CURSEFORGE-STEPS.md`](docs/release/CURSEFORGE-STEPS.md). See also
[`CONTRIBUTING.md`](CONTRIBUTING.md) and [`SECURITY.md`](SECURITY.md).

## Credits

- **ForteXorcist** — original addon by **Xus (Xussie of Kazzak EU)**, v1.980.8 (2012), GPL-3.0.
  Textures and one sound are vendored unmodified; see `addon/Forte_Core/ATTRIBUTION.md`. The Lua code
  here is an independent reimplementation.
- URW Gothic (URW++, AGPL-3.0 with font exception) — the shipped lookalike of Century Gothic. The
  `.otf` source of the converted `.ttf` is in the repository (`addon/Forte_Core/Fonts/`), not in the zip.
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

GPL-3.0, see [`LICENSE`](LICENSE). The textures and sound from the original ForteXorcist are GPL-3.0
as well; the font is AGPL-3.0 with the font exception (`addon/Forte_Core/Fonts/`).

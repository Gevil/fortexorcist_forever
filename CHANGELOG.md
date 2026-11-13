# Changelog

User-facing changes to **ForteXorcist Forever**, newest first. Each
entry says what a player sees or can do; the engineering reasoning behind it
lives in `PLAN.md` §9 (dated log) and `docs/`. The release number comes from
the `VERSION` file; `scripts/release.py` (and the CI packager) write it into
every add-on manifest.

**WoW Forever 1.60.1 (interface 16001).** The sections dated before 1.0.0
record the pre-release builds, which were verified in headless interface
simulators and uiforever.com and, from 2026-11-06, in the live game.

---

## Unreleased

- **Error recorder and a fixed `/fx log`.** The addon now quietly records its own Lua errors, blocked
  actions and warnings (only those that concern ForteXorcist, never other addons') in the saved
  variables; `/fx errors` lists them and `/fx errors clear` empties the list. `/fx log on` now copies each
  recorded error to chat as `[FX-ERR]` and turns on cast tracing; it no longer switches the game's chat
  logging on (that only records your real chat and never carried our lines), and the status line no longer
  shows the wrong `chatlog=` value.

---

## [1.0.0] - 2026-11-11

First full release for **WoW Forever 1.60.1** (interface 16001). Everything from the
pre-release builds below is included; this section is what changed since the last one.

- **Spell data refreshed to the live game (build 1.60.1.70888).** The cooldown bar and timers now
  follow the live numbers: Chain Lightning casts in 2.5 s, Totemic Projection has a 30 s cooldown, Shank
  is the real Forever spell with its 10 s cooldown, Vengeance stacks to 5.
- **Wrong spells fixed.** Several bars were tracking a look-alike spell (a hunter pet's version, an
  item proc, a Season of Discovery copy) instead of the class spell, so their cooldowns or
  durations were wrong. Corrected: Warrior Charge, Druid Dash / Cower / Thorns / Abolish Poison,
  Mage Fire Blast, Shaman Earth Shock and Lightning Shield (which now gets a timer), Warlock
  Corruption (18 s, was 12 s) and Unstable Affliction (18 s, was 5 s), Hunter Serpent Sting (15 s,
  was 12 s) and Raptor Strike, Paladin Cleanse and Exorcism.
- **Shared cooldowns work.** Casting one spell now starts the cooldown bars of the spells that
  share its lockout: the four Hunter traps, Multi-Shot and Aimed Shot, the three Shaman shocks,
  Ice Lance and Fire Blast, Summon Hawk and Arcane Shot.
- **New tracked spells:** Warrior Rend, Reckless Swings and Gore Drinker; Rogue poisons and Venom;
  Paladin Holy Strike, Light's Vigil, Holy Wrath and the Unsealed Wrath echoes.
- **Item cooldowns corrected** (Adaptive Combat Assistant, Weakness Analyzer, Serenity Field) and
  the item data re-checked against the live game.
- **Spell Timer "Expand up" works** (see the 2026-11-09 entry), and the stack stays where you put it.
- **Known gap:** effects the game applies at run time (for example Tuesday's Wrack change for Warlock
  damage-over-time spells) are not in the game's spell data, so those timers keep the base length until
  the game's own readings correct them.
- **Packaged for CurseForge and GitHub** as `ForteXorcist-1.0.0-forever.zip`.



## Unreleased — 2026-11-09 (Spell Timer growth direction)

- **"Expand up" unticked now grows the Spell Timer downward, and the stack no
  longer drifts.** The option only moved the title: the bars still stacked
  upward, and the whole stack crept up as bars appeared (the panel was pinned
  by its centre). The panel is now pinned by its first bar's corner: ticked
  (the default) the first bar stays put and new bars appear above it;
  unticked the first bar stays put and new bars appear below it. Toggling the
  option, changing Width/Height or changing Scale no longer moves the first
  bar, and a saved Scale now applies at login. Your existing position carries
  over to the same spot, and `/fx timer reset` restores the default spot.

## Unreleased — 2026-11-06 (first live session on the Forever client)

Found and fixed in the running game (Hunter, build 1.60.1.70790). Items marked
*(not re-tested live)* were changed after the last in-game check.

- **Spell Timer now sees your own casts, in and out of combat.** Registering
  the pet's cast events replaced the player's, so Serpent Sting and Hunter's
  Mark never reached the timer in combat. One registration per event now lists
  every unit. The Timer also starts again (the `UNIT_DIED` registration no
  longer aborts the module).
- **Targeting yourself no longer wipes the timer bars.** A target change swept
  the rows of the old target against the new unit and faded them all; rows are
  now swept only for the unit they belong to.
- **Hunter's Mark lives on one target.** Casting it on a new target retires the
  old target's bar. A confirmed aura adopts your cast's row instead of adding a
  second "target" row *(not re-tested live)*.
- **The timer's icon glow wraps the icon exactly** instead of a squashed
  rectangle.
- **The timer's drag title sits below the frame** when the stack grows upward.
- **Cooldown bar:** icons redraw at 60 Hz instead of 10 Hz; Berserking and
  Rapid Regeneration (Troll racials) are tracked; icons that land on the same
  spot stack in lanes instead of hiding each other *(lanes not re-tested live)*.
- **Summon Hawk (talent, spell 1293241) is on the cooldown bar** and shares
  its 6 s cooldown with Arcane Shot: casting either starts both bars *(not
  re-tested live; its name is read from the client)*.
- **A failing cast no longer jams the Spell Timer.** One raising cast job left
  a hole in the timer's queue and every later pass errored for the rest of the
  fight; jobs now run protected, the queue heals, and the first failure is
  named once in chat.
- **Options window closes with Esc and the X** and no longer traps the
  keyboard (number and text boxes no longer grab focus on their own); it draws
  above other add-ons.
- **Aspect reminder shows the aspect's icon** (by spell ID, first known aspect)
  instead of a grey square *(not re-tested live)*.
- **Probe:** the copy window now opens (font fallback, visible background); the
  login counter counts real logins, not `/reload`s.
- **Developer logging:** `/fx log on|off` copies every Lua error to chat as
  `[FX-ERR]`; with it on, cast events are traced as `[FX:timer]`.

---

## Unreleased — 2026-11-07 (code-review-10 remediation: hardening the live fixes, then the gate runs)

Hardening of the 2026-11-06 live fixes per `docs/reviews/code-review-10.md`,
on top of the November balance data refresh. Behaviour notes where one
changed; the rest is registration shape, defaults and test coverage
(every fix below ships with a test that fails on the pre-fix shape).

- **Spell Timer:** the death sweep registers `UNIT_DIED` as the base event it
  is (payload: a unit GUID, never a unit token) — the per-unit form the live
  client rejected is refused by a test, and the per-unit shape of every other
  registration is pinned. Target sweeps read identity only from the unit
  being swept, so a sweep can no longer retire a row that rode a token onto a
  friendly unit (the "rides" rule now requires the unit's NAME to answer).
  A recast of a one-target effect retires the old target's bar through the
  localised spell name too, an aura confirming a cast takes over that cast's
  row instead of adding a second one, and rows queued for eviction are no
  longer adoption targets. The cast pump counts every job it raises on
  (`/fx log`'s status line gained the count), and the unused Spark-Flare
  tuning entry is gone.
- **Cooldown bar:** the icon pump keeps its leftover time between frames, so
  the 60 Hz draw rate is real on a 100 Hz+ client (it drew ~50 Hz before); the
  overlap stack caps at 3 lanes so a dense cluster of short cooldowns stays
  on the bar.
- **Options:** the keyboard-trap and strata fixes are pinned by tests (text
  boxes never auto-focus, Enter/Escape release the focus, the window rides
  the dialog strata, the X and Esc close it).
- **Aspect reminder:** an aspect whose name the client does not list now
  reaches the name lookup (the lookup that runs the spell ID first, the name
  second, stopped at the ID when the ID was missing).
- **Developer logging:** `/fx log` (status) no longer calls the chat-logging
  toggler with no arguments — the argless call raised on the live client and
  killed the whole command, now the state is read from the client's query (or
  reports false); `/fx log test` survives a client without the error-handler
  getter; the login re-apply rides the module registry, so the add-on has one
  login-time registrant again and a fresh install writes no save key.
- **The review-10 test wave greens the gate (M3c).** The render pump's
  accumulator rides a one-slot box so the cadence tests start from a drained,
  known phase (the pump's draw law is unchanged); the shared
  `Rows.options`/`FX.db` seam restores are idempotent, and the leg fixtures
  that rode the pre-refresh world (the German client's druid sample, the
  grace-window cast time, the bulk-sweep seam, the tracker roster, the
  Enter-commit expectation, the sim's texture-identity form) follow the live
  data and the sim's real answers — no law softened, every red traced to a
  fixture or a leak. The gate's load probes now carry `Log` in the
  always-loaded set (inert by default: no frame, no events, no save writes
  until `/fx log on`), and `docs/research/data-diff-live-2026-11-07.md` §10
  records the data-side wave.

---

## Unreleased — 2026-11-04 (Iteration J: the Hunter swing bar reads your rotation)

- **The Hunter bar starts in its Safe-window mode as intended, and two
  characters sharing a first name keep their own settings.** A fresh Hunter
  profile booted in the Elapsed-fill mode and kept it — the retired
  `ShowSafeWindow` migration mistook "this profile has no old-mode key" for
  "the key says off" and wrote the choice into the save; now a profile with
  no mode word boots in the shipped Safe-window mode and stays unstamped.
  And the profile migration no longer moves an old `First-Realm` profile
  when a second character on the account shares that first name (an "Anne
  Ashvale" and an "Anne Brightoak" both wrote the old key
  `Anne-<realm>`): with the name shared, nothing is moved, each character
  keeps her own settings, and a profile row of another realm's label no
  longer folds onto your key.
- **Your settings survive the old `Name-Realm` profile key in every shape.**
  The launch-day check found installs whose saved profile is named after the
  *first* name plus the realm label (`Morvessa-Nethergarde`) while the profile
  key today packs the whole name (`MorvessaAshveil`). The migration now
  recognises that spelling too, so such a character wakes up on her settings
  instead of the defaults. Only your own character's key is moved — a profile
  you named yourself (a "Uther-Raid" page) is left exactly where it is, and an
  existing profile of the new name is never written over.
- **`/fx messages` reports the announces that are off.** A row switched off
  was skipped silently by the module and never counted, so the line read
  `off-skipped 0` on an install whose every announce is off. It now counts
  every opt-out, which is what makes a silent install legible.
- **`/fx warlock status`'s `rate` column counts.** The warlock comms rate
  limiter dropped lines it was asked to send too often without counting them;
  the launch-day readout now shows how many the rate law ate.
- **Auras that were already over when they were read are ignored.** A spell
  aura whose expiry timestamp is in the past is no longer treated as a live
  fact by the Spell Timer's aura sweep: it no longer plants a row that is born
  at zero, and it no longer wipes a live row of the same spell. A permanent
  aura (no end time) is a fact as before.
- **The Mage's Clearcasting shows on the Spell Timer.** The Arcane
  Concentration procs (the "your next Arcane/Frost/Fire spell is cheaper"
  window, 15 s) were measured live on a Mage and drawn no row: the Mage's
  spell list did not name the aura. It is tracked now (the Druid's and the
  Shaman's Clearcasting rows are unchanged).
- A dead range-check telemetry field on the Hunter swing tracker, a dead
  locale id-map and a dispatcher-less locale event hook were removed.

- **"Can I cast without clipping?" is on the bar.** A dim red mark shows the
  Aimed Shot length: in the default *Safe window* mode it sits at the bar's
  left end — start Aimed or Multi-Shot while the orange still reaches past
  it and the cast won't delay your next Auto Shot. While a shot is casting
  the mark follows that cast's real length.
- **The stand-still zone is always visible.** The right end of the bar
  carries a faint red region all cycle — the moment Auto Shot aims and you
  must not move — so you see it coming, not only when it starts.
- **Bar mode picker** (Hunter Tools options): *Safe window* (today's look,
  the default), *One bar* (the fill grows toward the aim end) or *Single
  fill* (plain cycle time). In the filling modes the clip mark sits at the
  right and the fill should stay left of it.
- **Weave line (opt-in):** a thin cyan line — while the bar is on the safe
  side of it there is room for one 1.5 s global cooldown (a melee weave or
  an instant shot) before the next Auto Shot.
- **Melee rail (opt-in):** your main-hand swing as a slim bar under the
  swing bar, shown only in melee range during combat; Raptor Strike resets
  it. Off by default — when off it costs nothing.
- **Non-English Warlocks: the soul-shard counter now counts.** A German
  client carrying four Soul Shards read `shards x0` — the bag pass asked
  the client's item table for the English name "Soul Shard", which a
  localized client counts at 0, and the shard (unlike the healthstones)
  has no generated data row for the localization layer to derive the
  client's own name from. The shard now carries its item id beside its
  name, so the localization layer learns the client's name for it —
  recorded at login, and on a cold item cache requested and applied the
  moment the client's answer lands, re-reading the count by itself. The
  German client's `Seelensplitter` now counts; English clients are
  unchanged.

## 0.1.0-dev — 2026-11-04 (Iteration I: launch-day build)

- **Your profile follows your character, not the server label.** On WoW
  Forever a character is a first and last name, and the "realm" the client
  reports is only a connection label that can change between logins. Your
  per-character profile is now keyed by your full name alone, so it can no
  longer appear to lose your settings after a server move. Older profiles
  are picked up automatically.
- **Cooldown data follows Blizzard's launch notes (3 Nov).** Slam 15 s,
  Stormstrike 6 s, Riptide 12 s; Ice Lance shares Fire Blast's cooldown and
  all Hunter traps share one; Oath of Light and other new spells are tracked;
  Lava Burst, Berserk, Blessing of Light, Salvation, Mass Salvation and Revoke
  are gone; Totemic Call and Lightning Mastery work under their new names.
- **12 more class procs are tracked** (Clearcasting, Fingers of Frost,
  Maelstrom Weapon, Infusion of Light, Vengeance, Enrage and others). In
  combat, where the game may hide aura details, they simply don't show
  rather than show something wrong.
- **The cooldown bar no longer empties mid-fight.** A spell-list change
  during combat (shapeshift, stance, loot, talents) used to clear every
  running cooldown from the bar; they now stay.
- **Test mode: `/fx test`** (or the button on the Cooldown options page)
  fills the cooldown bar, splash and Spell Timer with sample entries so you
  can place and style frames without casting. It never sends chat, never
  saves settings, clears itself when you stop it, enter combat or log out,
  and refuses to start in combat.
- **Warlock group tools (opt-in) work in parties.** Party comms and party
  announces never actually went out; they do now. Messages the game
  throttles are retried, messages blocked during an encounter are sent in
  order afterwards, and a groupmate appears once on the plates (not twice).
  Everything stays OFF until you switch it on.
- **Hunter range light**: a range read that came back empty in every case
  is fixed, and range updates can no longer error in combat.
- **More launch-day diagnostics in `/fx probe`**: your name/realm as the
  client reports them, whether every event we use exists, a settings
  save-and-reload check, and whether Healthstone, pet and weapon-enchant
  cooldowns are readable.

---

## Unreleased — 2026-11-03 (Iteration H, review-6 fix slice)

- **Your settings now survive a profile switch.** Switching profiles (or
  sharing settings) pushed every option back out at its effective value —
  and an option set to OFF under a default of ON (a bar you unlocked, the
  right-click switch you ticked off) was read as "unset" and pushed back as
  the default: every bar you unlocked re-locked, and the stored choice was
  deleted from the profile. The stored OFF now rides the switch and stays
  in the file (found by code review 6, M1).
- **Right-click keeps working after you drag.** The press stamp that tells
  a click from a drag rode only the left-button drag start, so on the live
  client the first drag left a stale stamp behind and every later
  right-click on that frame read as "the cursor moved" and opened nothing.
  The stamp now lands on every press and is consumed by the release, as in
  the original's `FW:StartMoving` / `FW:Moved` pair (M2). A release the
  client reports outside the frame no longer opens the window.
- **The Secondary Splash window joins the right-click law.** A right-button
  release on it now opens its own page, drag-safe and lock-safe like every
  other module frame (M3).
- **The Advanced page's Hunter strata row is live.** Typing a frame level
  into it moved the store and told the swing bar nothing; the bar now
  listens, like every other frame, and applies the row immediately (M4).

---

## Unreleased — 2026-11-03 (Iteration H, wave 6)

- **Right-click opens the page, on every module frame.** The Cooldown bar
  already had it; the original's CD-30 law now rides every module frame: a
  right-button release on the **Spell Timers panel** opens the options window
  on its page, on the **Hunter swing bar** on the Hunter page, and on each of
  the four **Warlock plates** on that plate's own page (Shard Manager,
  Soulstone Tracker, Healthstone Spy, Summon Assistant). A drag never opens
  the window (the cursor is stamped at press and compared at release, the
  original's `FW:Moved()` guard), the left button stays the drag button, and
  the General page's **Right-click headers for options** switch silences the
  seam live on all of them. Following the source, a **locked** frame keeps
  this seam: the lock stops the drag, it never takes the frame's mouse —
  which matters most on the frames that ship locked (the swing bar, the
  Warlock plates), where the port's earlier mouse-off-while-locked made the
  seam unreachable out of the box. (The Cooldown bar and the Secondary Splash
  window, built earlier, followed the same law the same day: locked now
  removes the drag start — the engine's `SetMovable(false)` plus a lock check
  in the drag script — and leaves the frame's mouse on, so the right-click
  seam works on the bar out of the box, the way the source's own row label,
  "Lock (disable dragging)", always said.)

- **Bar Font, Bar Texture, Icon size, Bar text: the cosmetics rows.** The
  General page's **Bar Font** and **Bar Texture** rows are the original's
  pickers (its FNT/TXT rows): the row opens a list — the font this add-on
  ships (URW Gothic Book), and the bar textures from the original's own
  texture list, the ones the port carries (Aluminium, Minimalist, Xus, BantoBar,
  … 19 of them, each shown as a swatch) — and a pick re-applies live: the
  Cooldown bar's text, the fill, the segments, the Hunter swing text and the
  Warlock plate labels all follow. The Cooldown page gained **Icon size** as
  the source ships it: a size plus an "enable" checkbox, the checkbox off at
  36 by default — icons ride the bar height — and on, the icons, their glows,
  the splashes and the ready pulses ride the number while the axis, the time
  tags and the segments keep riding the height, so the icons grow in place.
  **Bar text** (the time-tag colour, 2012's white at 20 %) joined the page's
  colour rows. All four ride the normal settings store: live applies, the
  section recycle restores the 2012 default.

---

## Unreleased — 2026-11-03 (Iteration H, wave 5)

- **The Advanced Options page has a cell that lights.** The module index of
  the options window had a dimmed `Advanced Options` square since the first
  build; it is a page now, and the square is live. In it: **Show startup
  text** (the login line in your chat, off = a silent login), **Expand all**
  and **Load expanded** (how a page opens: every section open, or folded
  except the tips and `Basics`, and whether a section you folded yourself is
  remembered on the next visit), **Animate auto-scrolling** (the mouse wheel
  eases to its target in the options list instead of jumping), and a
  **Frame level (strata)** row for each module frame — the Cooldown Timer,
  the Secondary Splash, the Spell Timers panel, the Hunter swing bar and the
  four Warlock plates — for the case the original's own tip describes: a
  module you can not click through, or that hides behind a Blizzard dialog,
  is one name off (`BACKGROUND`, `LOW`, `MEDIUM`, `HIGH`, `DIALOG`,
  `FULLSCREEN`, `FULLSCREEN_DIALOG`, `TOOLTIP`). Every row is applied live on
  the frame it names, and a name outside the eight is kept as typed and
  ignored, so a typo can not drop a bar off the screen. Rows of the 2012 page
  that have nothing to drive here — frame snapping, the update and animation
  intervals, the options column count and height — are not on the page, and
  the ones that are on the General page (**Right-click headers for options**,
  live on the Cooldown bar) are named in `Pages/Advanced.lua`.
- **Your settings, not ours.** Add-ons that remember every setting ever
  shipped remember them at the value the build had when they wrote the
  file — so a default the developers later changed (the alternate time
  format shipped ON, a shipped OFF for a chatty alert) never reached an
  install that never touched the switch: the stored old default won. The
  settings store now keeps **only the values that differ from the shipped
  defaults** — reading an untouched switch stores nothing, moving a switch
  back to its shipped value forgets it, and a reset clears the stored
  values instead of writing them. A one-time file cleanup (schema v2)
  drops the frozen defaults from existing installs, profile by profile;
  values that differ from a shipped default are kept (a stored choice can
  not be told apart from a frozen default, and losing your choices is the
  worse failure). SavedVariables files shrink to what you actually chose,
  and a future default change reaches every install that never opted out.

---

## Unreleased — 2026-11-02 (Iteration H: the launch kit)

- **Item proc timers have a switch.** The Cooldown Timer page's Specifics
  block gains **Item proc timers (experimental)**: tick it and the internal
  cooldown of an item or weapon proc rides the bar (the tracker of
  `Forte_Cooldown/Core/Procs.lua`); untick it and the feature, and the
  load-on-demand proc data add-on that only it pulls in, go away. The tip says
  what it is: experimental, off by default, and in-combat proc detection is a
  launch-day probe. The change is live the moment you tick it, and
  `/fx status` prints the state the box just set.
- **20 cast announces on the Raid Messages page.** The Druid, Paladin and
  Warrior raid warnings of the original (Barkskin, Survival Instincts,
  Frenzied Regeneration, Rebirth, Innervate, Tranquility; Aura Mastery,
  Salvation, Sacrifice, Freedom, Hand of Protection, Divine Protection,
  Guardian of Ancient Kings, Ardent Defender; Shield Wall, Last Stand,
  Rallying Cry, Enraged Regeneration, Intervene, Vigilance) are back as 20
  sections of three controls — the text (the original's, verbatim), a group
  send, a channel send. **Every one ships OFF**: a fresh install never talks
  to a party about a cooldown you never asked it to talk about, and each
  section tip says what the original shipped on so you can restore it. The
  two Paladin rows whose spell the current build dropped (Salvation, Ardent
  Defender) say so on the page.
- **Pet-cast timer rows are back.** Iteration G removed them because the
  1.60.1.70425 data pull had no Succubus kit; the live 1.60.1.70707 spell store
  has it (Seduction 6358/6359, Mesmerize 24594, Spell Lock, Soothing Kiss), so
  the Spell Timer now also follows the **pet's** own casts: a pet Seduction
  draws its 15-second crowd-control row, and its fading and early-break
  announces — the pair the original shipped party-ON — light with the boxes
  ticked.
- **Probe results are copyable.** `/fx probe` still prints its lines in chat,
  and now also opens a text window holding the whole run: clicking in the
  text selects all of it for Ctrl-C, and the `X` button (or `Esc`) closes it.
  Launch-day reports can be pasted, not retyped.
- **Install checks.** `scripts/deploy.sh --copy --verify` now compares an
  installed copy against the shipped file list and names every missing,
  extra or changed file. The install guide tells you to run it after a client
  patch. The installer never touches a file a third-party SavedVariables fix
  has patched, never removes an add-on it did not install, and `--target`
  lets you rehearse an install into a scratch directory first.
- **Releases.** `scripts/release.py` builds the player-facing
  `dist/ForteXorcist-<version>.zip`: tests, fonts and docs stay out, the
  version is stamped into every manifest (both manifest twins always
  identical), and rebuilding the same commit gives byte-identical bytes.
  `--dry-run` prints the file list and the size without writing.
- **One-call web check.** `scripts/uif_battery.js` drives the uiforever.com
  tester end to end: import the zip, reload, then assert that exactly your
  own class add-on is resident (plus the site's own Mage session), the
  modules list enables, the splash and messages modules are present, no
  party/raid chat goes out with the shipped defaults, and the site reports no
  Lua errors. Returns a pass/fail table. Three import-truthful gates
  (manager's 11-02 findings): the import waits (15 s) for the
  `Import addons?` dialog, clicks that dialog's own Import button and waits
  for the dialog to close — a larger zip's dialog lands seconds after the
  upload and the raced version passed every later check against the
  PREVIOUS import (false PASS); a CODE row proves the site runs the bytes
  just imported (a Lua marker expression must print true; default the
  shipped `ForteXorcist.CONST.VERSION`, option `expectMarker` for a newer
  build's symbol); and a `fresh` clear that removed 0 rows while Forte rows
  stood in the add-on list now fails, logging the selector, the matched
  count, the panel it counted and the visible row count. The visible-row
  count reads the **ADDONS list panel** — the left panel's header plus the
  per-addon rows under it — so the Lua console printing `ForteXorcist...`
  lines can no longer pose as add-on rows (70 console lines over an empty
  list used to read as 70 rows and fail the row); `scripts/uif_battery_mock_test.js`
  runs the shipped sweep against six fake pages (console noise over an empty
  panel, 16 rows, one row, a dead `✕`, a stray `✕` outside the panel,
  an unlocatable panel) and fails on the pre-fix counting.

## 2026-11-02 (Iteration G)

- Warlock soulstone/healthstone plates show their icon — the 16×16 icon sat
  under the plate's own artwork and was never visible; it now rides the plate
  body, the way the original draws it.
- Pet-cast timer rows are gone: WoW Forever 1.60.1 has no Seduction,
  Mesmerize, Devour Magic or Spell Lock to track. The related fade/break
  settings stay, labelled inert, so a saved profile survives their return.

## 2026-11-02 (Iteration F — reviewed chat behaviour)

- Ready cooldowns no longer print "`<name>` ready" in chat. The original
  prints nothing; the opt-in **Self Message → ready chat line** is now the
  only source of a ready line.
- Every party/raid announce defaults **off** (banish/enslave/seduction
  breaks, shard warnings and friends-who-broke-a-polymorph calls). Turn them
  on per control; the tips say what the original shipped on.
- The spell-timer expiry signal now fires on the first expiry of a session
  (it used to be wired too late to ever fire).

## 2026-11-02 (Iteration E — the missing original modules)

- **Secondary splash** (the big icon pulse when a cooldown ends) is rebuilt
  to the original's law: a one-second bell — the icon grows to double size
  and fades out.
- Cooldown-bar extras: your own failed cast flashes the bar and steals focus,
  right-click opens the Cooldown options page (drag-guarded), and the bar
  reacts the way the original does when you click through it.

## 2026-11-02 (Iteration D)

- **Spell Timer v1** (`Forte_Timer`): the rows panel for your own casts,
  predicted from the cast event and reconciled against the game's cooldown,
  with the original's group headers and arrival flash. `/fx timer test` paints
  the whole colour palette; the crowd-control rows finally read blue (a colour
  key typo and a test feed that stamped casts in the future had pinned every
  row to the flash colour).
- **Warlock UI v1**: the original's purple labelled plates (soulstone,
  healthstone, ritual) for Warlocks, and the shard bag reads bag-first,
  power-second.
- Fixes from the third review: the end-of-cooldown pulse fires live, the
  pulse pool reuses, and per-slot weapon-enchant timers are independent.

## 2026-11-02 (Iteration C)

- **Weapon-enchant timers**: a temporary weapon enchant's remaining time now
  shows as a timer (the modern enchant API), under the Buff category.
- **Warlock tools**: shard counts with their source label, soulstone,
  healthstone and ritual trackers (`docs/warlock-tools.md`).
- The Hunter tools page gained its module-index cell, the icon fade-in now
  matches the original's one second, the swing bar's default colour is
  visible on the default background, and the bar font reaches the swing text.
- **Load-on-demand class add-ons**: each `Forte_<Class>` add-on now declares
  itself load-on-demand, so a Hunter run loads the Hunter code only — the
  Warlock and Mage code is no longer resident on a Hunter. This also fixed a
  live bug where both Hunter event handlers passed arguments in the wrong
  order, which is why the swing bar never showed in a client.

## 2026-11-02 (Iteration B)

- `/fx probe` — the launch-day diagnostics kit (secret-value reads, cooldown
  reads, epoch, presentation probes) plus `docs/launch-day.md`, the day-of
  checklist: import, the F1–F13 feature checks, the data-epoch probe and the
  SavedVariables probe, the log locations.
- The cooldown bar now reads the real cooldown through in-combat read tiers:
  an "active/ready" flag gives the early edge, a plain duration object gives
  the exact anchor, and a secret value is never trusted as a number.
- **Hunter swing bar** and the aspect reminder, plus the Hunter options page.
- The splash and the end-of-cooldown pulse follow the original's law
  (linear 0→4×, alpha 1→0, over 1.0 s).

## 2026-11-02

- The **Death Knight module is gone** — WoW Forever has no Death Knight
  class. An unknown class simply loads no class add-on.
- Live finding: an always-loaded add-on listed the LoD class add-ons as
  optional dependencies, which made the client load *every* class for every
  character. Fixed, and the gate now rejects that shape statically.

## 2026-11-01

- **Cooldown Timer** (the bar): the single power-scale timeline of the
  original — a row per readiness event (cast start, cooldown start, charge
  ready), gold, icons at full bar height (the original's 24 px, not 36), the
  minute labels only above 60 s, a tag at the bar's end, gold segment fills
  that reach the first icon, per-icon time text, a spark tint, and the icon
  fade-in.
- **Options window** (16 pages): the original's General, Cooldown, Buff, Debuff,
  Procs, Consumable, Crowd Control, Pet, Combat, Racial, Debuffs, Self Message,
  Key Binding, Sound, Debug pages plus the module index, with the original's
  left-aligned gold labels, navy section bars, reset icons, header alpha and
  scale sliders, scrolling, and the 4×4 module grid. Row stacking, the title
  strip and the controls were rebuilt after three review rounds; every
  control writes through a named setter with an instant apply, so a click
  changes the bar on screen.
- **Spell and item data** for eight classes (no Death Knight in Forever) from
  the client's own spell table, generated by `tools/gen_spell_data.py` — the
  replacement for the original's missing `Register.lua`. 238 on-use item
  effects, 405 proc effects (400 items, 5 enchants) and 79 consumables.
- **Charges**: a charge spell's timer counts charges, and a plain "ready"
  read no longer clears a charge entry (the charge read owns its lifecycle) —
  the one behaviour change beyond adding fields.
- The identity skin: the original's Classic look, vendored under the GPL-3.0
  attribution with the Century Gothic look-alike replaced by the libre URW
  Gothic (the original's `GOTHIC.TTF` is a Monotype font and is not free).
- The add-on is licensed GPL-3.0 (`LICENSE`), with per-asset licenses in
  `ATTRIBUTION.md`.
- Cast counters and the `/fx status` readout; `/fx debug 1` for the
  second-by-second event dump; `/fx reset` for a clean settings baseline.
- The SavedVariables hazard: a third-party SavedVariables fix rewrites add-on
  manifests and links data into add-on folders, so the deployer gained a
  `--copy` mode that never follows links into this tree.

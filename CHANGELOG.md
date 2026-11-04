# Changelog

User-facing changes to **ForteXorcist for WoW Forever**, newest first. Each
entry says what a player sees or can do; the engineering reasoning behind it
lives in `PLAN.md` §9 (dated log) and `docs/`. The release number comes from
the `VERSION` file and is written into every add-on manifest by
`scripts/release.py`.

**WoW Forever 1.60.1 (interface 16001).** The client opens to the public
launch on 2026-11-04, so everything below was built and verified in the
headless interface simulator and on uiforever.com — not in a live game.

---

## Unreleased — 2026-11-04 (Iteration J: the Hunter swing bar reads your rotation)

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

# Hunter tools (`Forte_Hunter/Core/Tools.lua`) — contracts, evidence, probes

Groundwork only: two independent trackers, no on-screen UI.

- **Aspect tracker** — mutually exclusive stance-like buffs. In-combat state is
  cast-**predicted** from our own `UNIT_SPELLCAST_SUCCEEDED`; out of combat a plain
  aura read over the aspect list **reconciles** it (PLAN §3.2). The aspect list is
  derived from `ForteXorcist.Data.Hunter` by the name pattern `^Aspect of`
  (`Tools.DeriveAspectNames()`), never hard-coded IDs.
- **Ranged swing / Auto Shot timer** — driven by `PLAYER_SWING` /
  `PLAYER_SWING_RANGE_UPDATE` with the verified payload orders (duration first /
  swingType leads, PLAN §8); an `Auto Shot` cast event is the event-based fallback
  model.

Public API (module table `FX.Hunter.Tools`, registered as module `"Hunter"`):

| Name | Contract |
|---|---|
| `FX.Hunter.NewAspectTracker({names, inCombat})` | aspect tracker instance |
| `:OnCast(name)` → bool | adopt `name` when it is one of the aspects (mutual exclusivity: newest wins) |
| `:Reconcile(readAura)` → `"adopted"\|"cleared"\|"unchanged"` | `readAura(name)` → `true` plain-present / `false` plain-absent / `nil` unreliable; found replaces prediction, all-absent clears, any unreliable read with nothing found leaves state untouched |
| `:Current()` → string\|nil | tracked aspect name |
| `:Missing()` → bool | reminder predicate: no aspect known active **and** not in combat |
| `:Snapshot()` → table | `{ current, missing, aspects }` plain copy |
| `FX.Hunter.NewSwingTracker({now, speedReader, rangedType})` | swing tracker instance (injected clock/speed) |
| `:OnSwingStart(duration, swingType)` | `PLAYER_SWING` handler — **duration first**; Ranged filter; secret duration → speed read → last observed |
| `:OnSwingRange(swingType, isInRange, checksRange)` | `PLAYER_SWING_RANGE_UPDATE` handler — **swingType leads**; Ranged + `checksRange` out-of-range stops the timer |
| `:OnCast(name)` | `"Auto Shot"` fallback start from the speed read / last observed duration |
| `:Progress(now)` → `fraction, remaining \| nil` | nil when idle; observing completion finalises (subsequent calls report idle) |
| `:Snapshot()` → table | `{ active, duration, lastDuration, fraction, remaining }` |
| `FX.Hunter.Tools:Status()` → string | one `/fx status` line (see wiring note) |
| `FX.Hunter.DefaultAuraReader(name)` | live `readAura` (row in the table below) |

Every value read from a unit/aura/cooldown API passes `FX.Compat.PlainOrNil`
before any compare/arithmetic; a secret (nil) read never overwrites known state.

## Catalog evidence

Evidence files: `docs/api/wow-addon-api-agents/skills/<skill>/references/generated/forever.json`
(source pin `ca8368f2…`, declarations from `wow-ui-source` `Blizzard_APIDocumentationGenerated/*`;
payload prose cross-checked in `docs/audit/FOREVER-FINDINGS.md` §"Swing timer" and
`wow-api-combat/references/CURRENT-CONTRACTS.md`).
"Secret annotation" lists what the declaration attaches; `—` = none on the rows we consume.
The vendor's evidence level is `declaration: source-declared`, `runtime/addonAccess: unknown`
for the whole SwingTimer family — declaration exists, third-party runtime access is a
launch-day probe (list below), which is exactly why the Auto Shot cast fallback exists.

| Name | Exists? | Secret annotation | File |
|---|---|---|---|
| `PLAYER_SWING` | **yes** — payload `(swingDuration: number, swingType: PlayerSwingType)`, **duration first**, `SynchronousEvent` | — | `wow-api-combat …/forever.json` ← `SwingTimerDocumentation.lua:42` |
| `PLAYER_SWING_RANGE_UPDATE` | **yes** — payload `(swingType, isInRange, checksRange)`, **swingType leads**; ignore `isInRange` when `checksRange` false | — | `SwingTimerDocumentation.lua:53` |
| `Enum.PlayerSwingType` | **yes** — MainHand=0, OffHand=1, Ranged=2 | — | `SwingTimerDocumentation.lua:70` |
| `C_SwingTimer.EnableRangeCheck(swingType, enable)` | **yes** (not called by us — see probes) | `SecretArguments=AllowedWhenUntainted` | `SwingTimerDocumentation.lua:10` |
| `UNIT_SPELLCAST_SUCCEEDED` | **yes** — `(unit, castGUID, spellID[, castBarID])`, 4th field tolerated | **`SecretWhenUnitSpellCastRestricted=true`** → spellID may be secret in combat; name resolution pcall-guarded | `wow-api-unit-player …/forever.json` ← `UnitDocumentation.lua:4844` |
| `C_Spell.GetSpellInfo(spellID)` | **yes** — used for id→name | `SecretArguments=AllowedWhenTainted`; result `.name` through `PlainOrNil` | `wow-api-spells-abilities …/forever.json` ← `SpellDocumentation.lua:415` |
| `PLAYER_REGEN_ENABLED` | **yes** — out-of-combat marker → reconcile trigger | — | `UnitDocumentation.lua:3890` |
| `UNIT_AURA` (registered `player` only) | **yes** — out-of-combat aspect reconcile trigger (debounced 0.2 s) | payload `(unitTarget, updateInfo)` is not read | `UnitAuraDocumentation.lua` |
| `C_UnitAuras.GetAuraDataBySpellName(unit, spellName, filter)` | **yes** — the name-resolving lookup we use; `unit` NeverSecret, `filter` Nilable (we pass nil) | **`SecretWhenUnitAuraRestricted=true`**, `RequiresNonSecretAura` → secret return = "no reliable information" | `UnitAuraDocumentation.lua:244`; Blizzard usage: `Blizzard_FrameXMLUtil/AuraUtil.lua:87` |
| `C_UnitAuras.GetPlayerAuraBySpellName` | **NO — does not exist** in the catalog (whole `C_UnitAuras` set enumerated). The assignment's name is replaced by the row above | — | audited across every `*/references/generated/forever.json` |
| `UnitRangedDamage(unit)` | **yes** — first return is `speed` (then min/max/pos/neg/percent) | **`SecretWhenUnitStatsRestricted=true`** → every return through `PlainOrNil` | `UnitDocumentation.lua:2961` |
| `UnitAttackSpeed(unit)` | **yes** — `(attackSpeed, offhandAttackSpeed, rangedAttackSpeed)`; we use the 3rd | **`SecretWhenUnitStatsRestricted=true`** | `UnitDocumentation.lua:681` |
| `InCombatLockdown()` | **yes** — default combat sampler behind `Missing()` | — | `wow-api-lua-environment …/forever.json` ← `RestrictedActionsDocumentation.lua:44` |
| `GetTime()` | **yes** — default clock | — | `wow-api-settings-system …/forever.json` ← `SystemTimeDocumentation.lua:56` |
| `issecretvalue(v)` | **yes** — classifies a secret aura return (nil return = confirmed absent) | `SecretArguments=AllowedWhenUntainted` | `wow-api-widget …/forever.json` ← `FrameScriptDocumentation.lua:286` |
| `CreateFrame`, `RegisterEvent`, `RegisterUnitEvent`, `SetScript` | not rows of the generated catalogs (frame system); the identical OnEnable-frame pattern ships in `Forte_Core/Core/Init.lua` + `Forte_Cooldown/Module.lua` — sim-proven every gate run | — | `Forte_Core/Core/Init.lua:82-86` (pattern) |

## Cast-predicted vs read

| State | In combat | Out of combat |
|---|---|---|
| Current aspect | **predicted**: our own cast event, resolved id→name, name ∈ derived list | **read**: `Reconcile()` via `C_UnitAuras.GetAuraDataBySpellName` per aspect (triggered by `PLAYER_REGEN_ENABLED`, `PLAYER_ENTERING_WORLD` + one pass ~1 s later, and the player's own `UNIT_AURA` coalesced to one pass per 0.2 s; skipped while a plain in-combat read is true) — corrects a wrong prediction, clears all-absent, secret/nil reads leave state untouched; a reconcile that moves `current` calls the tracker's `OnChange` listener (the reminder) |
| Ranged swing | **event-driven**: `PLAYER_SWING` (no secret annotation on its payload) — no prediction window; `Auto Shot` cast events are the fallback start if the events do not reach addons | same (events are flavor-independent); `UnitRangedDamage`/`UnitAttackSpeed` speed reads are plain |
| `Missing()` reminder | never (combat gate) | true only when no aspect is known active |

`/fx status` wiring: `Forte_Core/Init.lua`'s status branch calls exactly one Status chain
(`FX.Cooldown.Module:Status()`), and Forte_Core is not ours to edit, so the Hunter line is
appended by wrapping that chain inside our `OnEnable` (idempotent, hunter-gated).
Open issue: without `Forte_Cooldown` installed, `/fx status` prints no Hunter line
(would need a Forte_Core change — not owned here).

## Live-client probe list (launch day, hunter character)

1. **`PLAYER_SWING` reachability** (the big one): register proves the event exists for
   third-party addons; log each payload — expect `(swingDuration, swingType)` with
   `swingType == Enum.PlayerSwingType.Ranged (2)` and `swingDuration ≈` ranged weapon
   speed while Auto Shot fires. If the event never arrives → the `Auto Shot` cast-event
   fallback is the model (confirm it fires per shot, plain spellID + name "Auto Shot").
2. **Event secrecy**: record whether `PLAYER_SWING` args / `UNIT_SPELLCAST_SUCCEEDED`
   spellID are secret (`issecretvalue`) in combat for our own actions (cast-event
   secrecy counts already run through Forte_Cooldown's `/fx status` counters).
3. **Speed reads**: `UnitRangedDamage("player")` first return and
   `UnitAttackSpeed("player")` third return — plain out of combat, secret-able in
   combat? Compare against the observed swing duration.
4. **Aspect reconcile**: out of combat, cycle every aspect in `FX.Hunter.Tools.aspectNames`;
   each cast → `PLAYER_REGEN_ENABLED` → confirm `Reconcile()` lands on the cast aspect
   (and clears when none is worn). In combat confirm `GetAuraDataBySpellName` returns a
   secret value (reader → nil) and never clobbers the prediction.
5. **Aspect exclusivity**: casting aspect B must drop A's aura (single tracker `current`).
6. **`Auto Shot` mechanics**: ranged shot cadence = tracker `duration`; verify the
   timer stays within a swing of reality while shooting (Progress wraps 0→1 per shot).
7. **Range gate**: `C_SwingTimer.EnableRangeCheck(2, true)` + `PLAYER_SWING_RANGE_UPDATE`
   (3-arg payload) for ranged; unconfirmed for addons (FOREVER-FINDINGS) — without it,
   out-of-range idling is not modelled (no event), document on return.
8. **`Trueshot Aura`** (data row, name `Aspect of …` pattern does not match it): confirm
   it behaves as a castable-aura, not a stance; keep it out of the aspect list (as now).

## UI layer (`Forte_Hunter/UI/*`, `Pages/Hunter.lua` — added 2026-11-02, agent `HunterUI`)

Two Classic-skin frames (the `Forte_Cooldown/UI/Timeline.lua` law: Aluminium fill on the
`Background`/`Border` backdrop, URW Gothic text) plus one options page. They are **pure
renderers** of the trackers above — no frame reads a unit/aura/cooldown API, and every
payload the UI's event frame receives is forwarded *unread*.

| Name | Contract |
|---|---|
| `FX.Hunter.Swing` | the Auto Shot swing bar (200x12 default) |
| `:Init()` / `:Update(now)` → bool | build frames (login/class-gated) / render one pass (`now` injectable) |
| `:SetTracker(t)` | the injected state source (tests; defaults to `Tools.Swing`) |
| `:Kick()` / `:OnSwingEvent()` | a swing event arrived: a running tracker starts the 10 Hz ticker |
| `:SetEnabled/Width/Height/BarColor/BgColor/ShowTime/Font/Locked` | the live seams the options page drives (`Font` rides the General page's shared `BarFont`) |
| `:RenderIdle()` / `:StartTicking/StopTicking` | the idle law: bar hidden **and** `SetScript("OnUpdate", nil)`; the script exists only mid-swing |
| `FX.Hunter.Reminder` | the aspect reminder (32x32 icon, pulsing alpha 0.35..1.0 over 1.2 s) |
| `:Refresh(now)` → bool | show while `Aspects:Missing()` (its out-of-combat gate included), hide otherwise |
| `:SetAspects(t)` / `:IconName()` | injected state source / the icon's aspect (live → last-known → the generic first) |
| `:SetEnabled/SetSize/SetColor` | live seams |
| `FX.Hunter.UI` | module `"HunterUI"`: class-gated `OnEnable` + `OnClassChanged`, the shared event frame, `/fx status` lines |
| `FX.Hunter.Pages.RegisterHunterPage()` | idempotent settings+page registration (load-time fast path, `HunterUI:OnEnable` fallback) |

**Settings** (module `Hunter`, defaults in `Pages/Hunter.lua`): `Enable`, `Lock`,
`ShowTime`, `EnableReminder`, `Width`, `Height`, `ReminderSize`, `BarColor`, `BgColor`,
`ReminderColor`. `BarColor`'s default *reads* `FX.Hunter.SwingSkin.BarColor` (the Forte_Cooldown
timeline's `Colors.Spell` tint at full alpha — the verbatim `{1, 0.5, 0, 1}` is the fallback
when that OptionalDep is not loaded), so the store default and the module skin cannot drift.
The bar's font is not a Hunter key: `Swing:SetFont` rides the **General** page's shared
`BarFont`, the same seam `FX.Cooldown.Display:SetBarFont` rides, and `UI/Swing.lua`'s
`STORED.General` pulls it at login. Positions: `FX.db.hunterSwing` / `FX.db.hunterReminder`.

**The `/fx lock|unlock` hook** (the question the assignment flagged): Forte_Cooldown exposes
no callback, but `FX.Cooldown.Display:SetLocked` **publishes** the live lock state into
`FX.Settings` (`Cooldown.Lock` + `General.GlobalLock`, its m4 rule). `FX.Hunter.Swing:_WireSettings`
mirrors exactly those two keys and publishes its own state into `Hunter.Lock`
(store-inequality-guarded, so the echo stops) — no Forte_Cooldown change was needed.
The shared lock moves both bars; the Hunter page's own checkbox moves only the Hunter frames.

**Module index**: `FX.Options.INDEX` now carries a 16th entry —
`{ id = "Hunter", label = "Hunter Tools", colour = C.BROWN }` (the Hunter page header's own
tint) — so the cell lights whenever our page is registered. The law lives in
`O:RefreshIndexCells()` (enabled + `SetPage` OnClick + full alphas while
`self.pages[entry.id]` exists; disabled + 0.45 alphas + a "not built yet" tip otherwise),
called from both `BuildIndex` and `RegisterPage` — which is what covers our late
(`PLAYER_LOGIN`) registration. `Forte_Options/tests/test_options.lua` asserts the 16-cell
grid and the enabled-iff-registered law; the cell is captured lit in
`docs/media/sim/fx_polish_index.png` (`cells=16 enabled=4 hunterEnabled=true`, agent
`Polish`).

**Verification (2026-11-02, agent `HunterUI`; polish pass included)**: `run-tests
Forte_Hunter` → **34 tests, 34 passed, 0 failed** (15 data/tracker tests + 19 UI tests in
`tests/test_swing.lua`), rc 0, 0 `Forte_*` error sites. `scripts/gate.py --fast` → PASS
(Forte_Cooldown 108, Forte_Core 13, Forte_Hunter 34, Forte_Options 44, Forte_Warlock 21;
modules `Cooldown, Hunter, HunterUI, Probe, Warlock`; tocs byte-identical;
syntax + api-lint OK). Screenshots `docs/media/sim/fx_hunter_swing.png`,
`fx_hunter_options.png`; dump-tree numbers: bar `200x12` at centre (800,775) with the fill
100 px at fraction 0.5, text `1.0`, and the URW Gothic file accepted (`_FONTURW`); reminder
`32x32` at centre (960,775), icon `Aspect of the Beast` (the generic first aspect, no live
aura in the sim), alpha pulsing (0.36 / 0.57 / 0.93 in three captures); options window
`780x650` with the Hunter page = 4 sections (Tips + 3) / 10 bound rows, content height 350.

## Reading the swing bar (Iteration J slice γ, 2026-11-04 — `docs/research/wst-swing-design.md` §7)

The Hunter options page's Shot Cycle section carries one picker and four
signals; each answers one rotation question, and each tip says it in one line.
The defaults: `BarMode = "safe"`, `ShowAimWindow = true`,
`ShowClipRegion = true`, `ShowWeaveLine = false` (a weave-build tool),
`EnableMeleeRail = false` — registered once in `Pages/Hunter.lua`; `BarMode`
replaced `ShowSafeWindow`, and a stored `ShowSafeWindow = false` reads back as
`BarMode = "elapsed"` (the `SetShowSafeWindow` migration seam in
`UI/Swing.lua`), `true`/unset as `"safe"`.

**Bar mode — how close is the next Auto Shot, and how much room do I have to
move?** Three readings of one cycle. *Safe window* (the shipped look) draws the
safe-to-move span as the fill shrinking toward the aim end: an empty left field
**is** the warning, so "must I stand still now?" arrives without arithmetic.
*One bar* draws the same quantity growing left→right as the cycle's progress,
stopping at the aim window and chasing its edge as the shot fires — the idiom
WeaponSwingTimer/YaHT players already have in their eyes; the fill reads as
"how far along am I". *Single fill* is the plain cycle clock (the old
`ShowSafeWindow = false` law): the bar is a swing stopwatch, the honest choice
for a player who does not weave.

**Aim window — when must I stop moving?** The right-end band that stands all
cycle: the aiming window (0.5 s, scaled by haste). The fill runs into it; when
the fill's edge touches the band, stop moving and let the shot go. The
full-alpha red slice inside it (the `ShowAimSlice` row) is the *live* windup, and
the printed number is its seconds — one fact, positional and numeric, no third
copy.

**Clip region — can I start Aimed Shot (or Multi-Shot) right now without
clipping the shot?** The threshold the fill's edge crosses, drawn in the
direction the chosen bar mode's fill moves: with the **shrinking bar**
(*Safe window*, the default) it is a dim band at the bar's **left** end, as
long as that shot's cast time — start the cast while the orange **still
reaches past** the band, and the shot lands before the windup. With the
**filling bars** (*One bar*, *Single fill*) it is the dim stripe at the
**right** end, as long as that shot's cast time plus the aim window — start
the cast while the fill's edge is **left** of the stripe. Both readings
answer the one test `time-to-the-aim-window − (aim + retry) ≥ cast time`;
press on the wrong side and the cast delays the next Auto Shot. The
marker's *fullness* is the message — a bar-spanning mark means this bow
never fits a cast-time shot between Auto Shots, the same truth the red
cast-interlock prints after the fact, now available before the press.

**Melee-weave line — is there room to step in, fire one global cooldown and be
back before the shot?** A 1-px line planted at the GCD's threshold in the
**direction the mode's fill moves** (the 1.5 s GCD is the shipped data row, not
a constant): with the **shrinking bar** at `1.5 s` from the **left** end —
step in while the orange **reaches past** the line; with the **filling bars**
at `aim + 1.5 s` from the **right** end — step in while the fill's edge is
**left** of it. Either side of the line says it: on the fitting side there is
room for one 1.5 s GCD — a Raptor Strike / Mongoose Bite weave or an instant
shot — before the stand-still window opens. The line parked off the bar (the
mode's own overflow direction): the hasted cycle has **no** room at all — do
not step in. Off by default: a signal a non-weaving build must learn to ignore
costs more than it pays.

**Melee rail — is my main-hand swing up for the Raptor Strike reset reward?**
An opt-in slim rail under the bar (under the range light when it is on; one
drag moves the stack). It fills left→right, **full = the swing is ready**, and
a landed Raptor Strike refills it (Mongoose Bite does not). It draws only in
combat and, with the range light on, only while the light reads MELEE — Auto
Shot needs ≥ 8 yd and Raptor/Mongoose need ≤ 5, so outside the melee band the
rail is noise by design, not an option.

**Colour palette — can I read this bar at all?** (Iteration K `K4B`,
2026-11-04.) The *Default* set is today's art, byte for byte. **Colour-blind
friendly (brightness steps)** repaints the same signals from
`FX.Hunter.SwingPalettes` so each one occupies its own rung of the **lightness**
scale, on top of the place it already holds: the live aim slice is the darkest
thing on the bar, the standing aim region is its socket, the retry and the cast
interlock sit in the middle, the clip mark and the fill above them, the white
flight state on top — so a signal is read by lightness and position, and colour
is never the only difference. Measured on the Aluminium art
(`tools/swing_contrast.py`, `tools/swing_palette_matrix.py`, WCAG contrast of
every pair that sits next to another): the shipped set puts its load-bearing
pairs at **1.07–1.43:1** (fill|clip 1.13, fill|aim region 1.26, aim slice|aim
region 1.14) — the range a protanope cannot separate — and the ladder lifts
those to **1.31–3.64** (fill|clip 1.31, fill|aim region 2.24, aim slice|aim
region 1.62, fill|aim slice 3.64), with no two signals closer than 0.013 on the
lightness scale. Measured over *every* pair of signals on the bar — not only the
neighbours — the floor moves from **1.03:1 to 1.11:1**, which is the number the
ladder is built for: the shipped art has three signals packed inside 0.012 of
lightness of each other, the ladder packs none closer than 0.013. Two pairs
stay under 1.5 by arithmetic, not by the palette:
white-on-Aluminium is the art itself (1.00 — the flight state is carried by the
whole bar turning and the spark, not by contrast), and the 1-px weave line
against the fill it crosses (1.49). The picker is a *base overlay*: your own
`Colour` pick survives a trip through both palettes, the melee rail's fill
follows the palette's bar colour, and the change is live, no reload.

## Verification (2026-11-01)

- `luajit -e "assert(loadfile(...)))"` — `Core/Tools.lua`, `tests/test_hunter.lua`: clean.
- `run-tests Forte_Hunter` → **12 tests, 12 passed, 0 failed**, exit 0, 0 `Forte_*` errors.
- `run-tests Forte_Cooldown` → **31/31** (unchanged), `run-tests Forte_Options` → **37/37** (unchanged).
- `lua-errors` verb: 0 lines naming `Forte_*` (baseline Blizzard_GamepadSmartNavigation /
  Transmog noise only).
- `Forte_Hunter.toc` == `Forte_Hunter_Camelot.toc` (`cmp`, byte-identical).

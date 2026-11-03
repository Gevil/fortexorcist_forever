# Simulator time and capture — the facts ForteXorcist drivers rely on

Binary: installed `wow-ui-sim-v0.1.39-forever-linux-x86_64` (Forever profile, run with
`--allow-ui-version-mismatch` against our 1.60.1.70707 client). Every measured row below was
re-run 2026-11-03 in this repo's own working tree through `run.sh` (frame-name side-effect
probes read back with `dump-tree`; `print` is swallowed, so probes publish through created
frames). Source cites are `github.com/Osso/wow-ui-sim` at tag `v0.1.39` = `389ca8a`
(checked identical at master head `06b67d9a`) and name **functions**, not line numbers, so
they survive upstream drift. This file is ForteXorcist-authored notes *about* the vendored
upstream specs next to it (`urls.txt` is their upstream-fetch manifest; this file is not in
it). Vendored specs cited below: [manual simulation clock](manual-simulation-clock.md),
[screenshot output format](screenshot-output-format.md),
[script object context access](script-object-context-access.md).

## Clock

Evidence labels used in this file (the corpus labels in `secret-auras.md:14-19` extended for
sim work): **MEASURED** = a probe run against the installed binary in this repo's tree, read
back through `dump-tree`; **CLI** = the binary's own `--help` text; **SOURCE** = the upstream
Rust at the pin above; **UI** = shipped Blizzard Lua in the pinned UI tree; **INFERRED** = a
conclusion, labelled as such.

- `GetTime()` in the sim returns **elapsed seconds**, not Retail's milliseconds.
  **MEASURED**: fresh process, no manual clock → `7.448462687` and `15.008815898` in two runs
  (wall-clock seconds since process start). With the manual clock: `SetManualClock(100)` +
  `AdvanceTime(2.5)` → `GetTime()` = **102.5**; `SetManualClock(50)` + `AdvanceTime(10)` →
  **60**. **SOURCE** (identical at the tag `389ca8a` and at head):
  `src/lua_api/globals/register.rs` registers `get_time`, which pushes
  `sim.clock_elapsed().as_secs_f64()`; `clock_elapsed()` = the manual clock when enabled,
  else `start_time.elapsed()` (`src/lua_api/manual_clock.rs`).
  `GetTimePreciseSec` is registered to the **same** function in this build - no sub-second
  difference to rely on.
- **The Forever client is on the same seconds scale; this was NOT measured in-game.** The
  scout note (`docs/research/upstream-sim-2026-11-03.md` §2.3, ranked item 3) labels **ms** for
  the *retail* client only. The client-side signal we do have is shipped-consumer arithmetic:
  Blizzard's own `BuffFrame.lua:774-777` (pinned `~/.cache/wow-ui-sim/blizzard-ui/wowforever/`
  tree, build 70532) divides the MILLISECONDS `timeLeft` by 1000 *before* adding it to
  `GetTime()` — arithmetic that is only coherent if the client's `GetTime()` advances in
  seconds. ForteXorcist runs on exactly that law (`Forte_Cooldown/Core/Enchants.lua:19-23`,
  `Forte_Core/Core/Compat.lua:108-112` "SECONDS, not ms",
  `Forte_Cooldown/tests/test_tiers.lua:527` "FrameTime == GetTime() units"). Launch-day probe,
  not a sim fact: a raw
  `GetTime()` delta across a known wall-clock gap in the live client.
- Cooldown reads ride the same clock, as absolute `(start, duration, modRate)` triples.
  **MEASURED** run A (manual clock at 100): `SetSpellCooldown(276105, 36)` →
  `GetSpellCooldown(276105)` = `(102.5, 36, 1)` after `AdvanceTime(2.5)`. Measured run B
  (manual clock at 50): `SetGCD(1.5)` → `GetSpellCooldown(61304)` (the GCD sentinel spell) =
  `(50, 1.5, 1)`; `SetSpellCooldown(193442, 25)` then `AdvanceTime(10)` leaves the stored pair
  at `(50, 25)` while `GetTime()` reads `60` — remaining time is **derived from the clock**,
  never decremented, which is why backdating a stamp (not shortening a duration) is how a
  capture loop advances a cooldown.

## `A_Admin` manual clock contract

- `A_Admin.SetManualClock(seconds)` is an **enable-once opt-in**. Measured: first call
  (`100`) returns true; the second call (`0`) raises (`pcall` → `false`) and leaves the clock
  untouched — `GetTime()` reads `102.5` before and after. Upstream: "A second opt-in fails
  without changing either clock" (`docs/specs/manual-simulation-clock.md`); enable it *before*
  seeding timestamped fixture state, because pre-existing timestamps are not migrated.
- `A_Admin.AdvanceTime(delta)` requires manual mode and rejects a negative delta (measured:
  `pcall(AdvanceTime, -1)` → `false`). One call = **one `OnUpdate` with exactly that delta**
  plus a `C_Timer` drain in deadline order; animation groups and EncounterTimeline advance off
  that delta (`manual_clock.rs`, head). This is why a manual-clock frame loop animates
  continuously while the headless `--delay` loop cannot.
- Real time remains the default: startup, renderer, watchdogs and profiling clocks stay real
  (`docs/specs/manual-simulation-clock.md`); the manual clock makes the *Lua-visible* clock
  deterministic, not the whole host.

## Headless `--delay` is a real-time loop, then a settle

`--delay <MS>` fires `OnUpdate` with **real** deltas and drains `C_Timer` in 16 ms slices
(`src/startup.rs`, `apply_delay_with_tick`), then the headless screenshot path runs exactly
**3 extra ticks at 0.016 s** (`src/bin/wow_sim/gui_commands.rs`: `run_extra_update_ticks(env, 3)`,
which calls `startup.rs`'s `fire_one_on_update_tick`), and startup settlement force-advances
animation groups by **2.0 s** (`src/startup.rs`, `settle_startup_animation_groups`).
Consequence, measured in our own pipeline: every fresh headless process sees wall-clock time,
so per-frame capture loops must backdate stamps (the `@K@` shim in `scripts/demo_media.sh`),
and a `GetTime()`-relative assertion needs a real tolerance, not `1e-6`
(`Forte_Cooldown/tests/test_tiers.lua:45-49`).

Phase order of the headless `screenshot` path (`src/bin/wow_sim/gui_commands.rs`, the
`--delay`/`--exec-lua` sequence, each phase separated by a `service_headless_reload`): settle
headless startup → apply `--ui-scale` → set screen size → **`--delay` loop** → **`--exec-lua`
chunk** → 3 settle ticks. So an `--exec-lua` driver runs *after* all real-time `OnUpdate`
traffic has already been delivered and reloaded away, and only the final 3 × 0.016 s ticks
follow it — that is the whole animation budget a one-shot capture gets, and the reason
`Forte_*` state driven from `OnUpdate` must be seeded inside the chunk itself.

## Scripted input: `--exec-lua @file`

`--exec-lua @/abs/path.lua` **works** in v0.1.39 (the PLAN §10.6 line "`@file` is silently
ignored" is false for this binary). Measured 2026-11-03 with chunks of 1299, 1327 and 1336 bytes:
every statement ran, including the last (`dump-tree` showed all 15 side-effect frames per run).
PLAN §10.6's ~1.2 KB chunk cap therefore did not bind at 1.34 KB; nothing above that has been
measured, so scenario drivers keep the ≤1.1 KB budget as a convention, not as a proven limit.
Inline form (`--exec-lua '<code>'`) works too. `print`/`io` output is swallowed — measured:
`print("HELLO-PROBE "..GetTime())` produced nothing on stdout; publish facts as named frames
and read them with `dump-tree`, or read `lua-errors`.

## Capture

- Image format: WebP is the **default** at quality **15** (`screenshot --help`: `--quality
  <1-100> … [default: 15]`, `--png` "written losslessly"; `screenshot-output-format.md` records
  quality 15 standalone / 65 live IPC, with the extension forced). Never build a GIF/MP4 from
  WebP frames — use `--png` (our `scripts/demo_media.sh` already does).
- Geometry: `--width`/`--height` default 1600×1200; `--ui-scale S` (default 1) lays the UI out
  for that scale the way the client does ("the client renders 1 UI unit as height/768 *
  uiScale pixels; 1440p at uiScale 0.9 is 1.6875. Above 1.0 the 2x atlas art is used";
  `WOW_SIM_HIRES_ATLASES=0/1` overrides). `--ui-scale` exists on the **headless** path only;
  `wow-cli screenshot` has no such option in this binary.
- Framing: `--crop WxH+X+Y` (both CLIs) or `-f <FrameName>` for a subtree-only render;
  geometry comes from `dump-tree -v --visible-only -f …` (rects), as `demo_media.sh dtbox`
  already consumes.
- The canvas is **opaque**: the headless render target is cleared to
  `[0.05, 0.05, 0.08, 1.0]` (`src/render/headless.rs`, `clear_headless_render_target`). There is
  no transparent background and no alpha in the output — every overlay baked into a clip
  carries the sim's dark-navy backdrop.

## Secrecy: the sim produces no secret values in the Forever profile

Measured on the installed binary:
- `C_Secrets` = exactly `{GetSpellAuraSecrecy, ShouldUnitIdentityBeSecret}`;
  `C_Secrets.ShouldCooldownsBeSecret` is **nil**.
- `SecretValue` and `IsSecretValue` globals are **nil**.
- `C_RestrictedActions` is a table containing **only** `CheckAllowProtectedFunctions`;
  `C_RestrictedActions.InCombatLockdown()` raises
  (`attempt to call field InCombatLockdown: a nil value`). The combat state a scenario can
  reach is `A_Admin.SetInCombat(true)` → `UnitAffectingCombat("player")` = `true`
  (measured `false` → `true`), which is the pair our modules gate on. The **global**
  `InCombatLockdown()` does exist and follows `SetInCombat` — MEASURED by the manager
  2026-11-03: `true` after `SetInCombat(true)`, `false` after `SetInCombat(false)`, with
  `PLAYER_REGEN_DISABLED` then `PLAYER_REGEN_ENABLED` delivered to a registered frame.

So in-combat secret-read behaviour cannot be produced by the sim (upstream: "No simulator
producer can determine the live aura-secret context" — [script-object-context-access.md](script-object-context-access.md),
Evidence and limits; `SimState.auras_secret_in_context` is Rust-integration-test-only and
defaults to false). In-sim tests exercise the
addon-side seam — plain-vs-secret results fed into the module — and the live question is
launch-day probe territory (`Forte_Core/Core/Probe.lua`, `docs/launch-day.md`).

## `A_Admin` combat/event surface used by our scenarios

Measured: `A_Admin` exposes **210** functions in this binary. The combat/event-relevant set,
all present: `SetInCombat`, `SetGCD`, `SetSpellCooldown`, `SetSpellBookItemLowRank`,
`SetCasting`, `StopCasting`, `DelayCasting`, `FailCasting`, `StartChannel`/`UpdateChannel`/
`StopChannel`, `StartEmpower`/`UpdateEmpower`, `AddBuff`, `AddDebuff`, `RemoveBuff`,
`ClearBuffs`, `AddLossOfControl`/`ClearLossOfControl`, `SetTarget`, `SetTargetHealth`,
`ClearTarget`, `SetFocus`, `SetEnemyPool`, `SetPartySize`/`SetPartyMember`/`SetRotDamage`,
`SetPlayerHealth`/`SetPlayerPower`, `SetFrameProtected`, `SetMoving`/`SetMounted`/`SetFlying`/
`SetSwimming`, `SetManualClock`, `AdvanceTime`, `SetWorldElapsedTime`/
`AdvanceWorldElapsedTime`/`StartWorldElapsedTimer`, `SetGameTime`, `SetGameRule`/
`SetActiveGameMode`, `FireEvent`, `SimulateBossKill`, `RegisterTestAddon`,
`IsSimulatorExitRequested`, `ToggleDebugBorders`/`ToggleDebugAnchors`. (`SetSpellCharges` and
`SetTargetCasting` do not exist; do not invent them.)

Event-injection facts, measured: `FireEvent("PLAYER_SWING", 1.6, 0)` and
`FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", <castGUID>, <spellID>, <castBarID>)` deliver
synchronously to registered handlers; `FireEvent` itself accepts *any* name (an unrecognised
`"SPELLSUPDATED"` returned `true` and reached nobody), while `RegisterEvent("SPELLSUPDATED")`
raises — validation lives on the registration side, so a typo in a driver's event name is
silent. Cast *completion* is emitted by the GUI live loop's `advance_casting`, so a headless
`--exec-lua` run never sees `UNIT_SPELLCAST_SUCCEEDED` from an elapsed `SetCasting` — inject
the event (scout note §2.6, "upstream-sim-2026-11-03.md").

## Our code against these facts

Audited 2026-11-03 (the check the scout note asks for, §2.3 action 3): every `GetTime()`
consumer in `addon/` treats the value as **seconds** — no `GetTime() * 1000` / `1000 /`
pattern exists anywhere in the tree, and the only ms→s division is the deliberate
`timeLeftMs / 1000` (`Forte_Cooldown/Core/Enchants.lua:222`, law stated at `:19-23`, mirrored
in the comment at `Forte_Core/Core/Compat.lua:387-391`), which follows shipped
`BuffFrame.lua`. The engine's
stamps (`Engine:OnCast(…, GetTime())`, `Forte_Cooldown/Module.lua:457,462`), the trackers'
`now = GetTime()` defaults (`Forte_Hunter/Core/Tools.lua:229`,
`Forte_Messages/UI/Banner.lua:48`) and the `Duration`-object law
(`Forte_Core/Core/Compat.lua:108-112`, asserted at `Forte_Cooldown/tests/test_tiers.lua:525-527`)
all sit on the seconds scale the sim gives — so a `SetManualClock`-driven scenario drives them
directly, and this doc's client-unit gap is the one place the law is not yet measured.

## Known gaps

- The client-side `GetTime` unit is inferred from shipped Blizzard consumer arithmetic at
  the 70532 UI tree, never measured at 70707. Launch-day probe closes it.
- The `--exec-lua @file` size ceiling is unmapped above 1.34 KB.
- GUI-server render cadence under load (wall-clock jitter freezing a frame slot) is not
  measured here; verify on the owner box before converting every capture loop.

## Out of scope

The `A_Admin` bag/mail/auction/quest/collection families, the recording recipe itself
(`scripts/demo_media.sh`, `scripts/scenarios/**` — I2d), the sim binary upgrade path, and
every secrecy question that only the live client can answer.

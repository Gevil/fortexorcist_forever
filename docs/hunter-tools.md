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
| Current aspect | **predicted**: our own cast event, resolved id→name, name ∈ derived list | **read**: `Reconcile()` via `C_UnitAuras.GetAuraDataBySpellName` per aspect (triggered by `PLAYER_REGEN_ENABLED`) — corrects a wrong prediction, clears all-absent, secret/nil reads leave state untouched |
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

## Verification (2026-11-01)

- `luajit -e "assert(loadfile(...)))"` — `Core/Tools.lua`, `tests/test_hunter.lua`: clean.
- `run-tests Forte_Hunter` → **12 tests, 12 passed, 0 failed**, exit 0, 0 `Forte_*` errors.
- `run-tests Forte_Cooldown` → **31/31** (unchanged), `run-tests Forte_Options` → **37/37** (unchanged).
- `lua-errors` verb: 0 lines naming `Forte_*` (baseline Blizzard_GamepadSmartNavigation /
  Transmog noise only).
- `Forte_Hunter.toc` == `Forte_Hunter_Camelot.toc` (`cmp`, byte-identical).

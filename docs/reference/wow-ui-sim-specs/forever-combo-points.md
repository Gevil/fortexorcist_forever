# Forever combo points

`GetComboPoints(unit, target)` exposes a target-bound view of the existing player combo-point pool. Implementation lives under `src/lua_api/globals/real/`; [the investigation](../wiki/investigations/forever-combo-points.md) records why this must not simply alias `UnitPower`.

## What it must do

- [x] On Forever, publish the legacy global requiring both unit-token arguments and returning one number for modeled queries. [Retail](retail-combo-points.md) retains its separate player-owned contract; [Wrath](wrath-combo-points.md) now reuses target-bound storage under its own bounded policy.
- [x] Read the existing `PlayerState.secondary_powers[4]` count. `A_Admin.SetPlayerPower(count, max, 4)` also assigns that snapshot to the selected target GUID; unrelated power inputs do not alter the assignment.
- [x] Return the pool count only for its assigned target. During `PLAYER_TARGET_CHANGED`, a different target must already report zero even when `UnitPower("player", 4)` still reports the earlier snapshot.
- [x] Resolve owner/target aliases through existing unit snapshots and GUID identity. An absent owner or target has no combo points and returns zero.
- [x] Preserve read-only queries, clear target assignment on a zero input, and leave a nonzero input made without a target unassigned. A new nonzero input replaces the single assignment.
- [x] Report unsupported resolved nonplayer ownership explicitly instead of fabricating its count. Exercise unchanged native ComboFrame initialization/update with `comboPointLocation=1`, including nonzero display and zero hiding.
- [x] With full UI startup, `PLAYER_ENTERING_WORLD` must refresh unchanged PlayerFrame/ComboFrame through the CVar-enabled event route for three and zero player combo points without Lua errors.

### Evidence and explicit guesses

Pinned Forever `UnitDocumentation.lua` declares the two unit-token parameters and a non-nil numeric result. Native `Mainline/ComboFrame.lua:65` calls `GetComboPoints(PlayerFrame.unit, "target")` when its CVar-enabled initialization has set `maxComboPoints`.

Cached EllesmereUI 9.2.2's changelog reports `UnitPower=3` while `GetComboPoints=0` during a target swap on Forever. This is addon-author evidence, not a simulator-run native probe. User-run Forever probes are unavailable.

**Simulator guesses:** binding the existing power input to one target GUID, retaining that assignment across selection changes until another power input, unassigned/no-target handling, player GUID aliases, and the unsupported-owner error policy. No multi-target point accumulation or combat-generated gains are inferred. Nonplayer/vehicle-owned combo pools are not modeled. These policies are not native conformance claims.

## How it works

- [Target ownership investigation](../wiki/investigations/forever-combo-points.md)
- [Existing admin health/power inputs](../admin-api/health-power.md)
- [Existing power-query boundaries](unit-power-missing.md)

## Implementation inventory

- `src/lua_api/globals/real/combo_points.rs`: modeled query, registration, and target assignment from power inputs.
- `src/lua_api/state_types/character_world.rs`: passive optional target GUID, used by target-bound profiles; count/max remain in the existing secondary pool.
- `src/lua_api/globals/admin.rs`: bind accepted combo-point inputs to their target.
- `src/lua_api/globals/real/mod.rs`, `src/lua_api/globals/register.rs`: profile-gated publication.

## Tests asserting this spec

`tests/combo_points.rs` joins the existing grouped integration target. It covers changing/zero inputs, primary-power independence, callback ordering across a target swap before a power update, GUID aliases, no-target input, explicit unsupported ownership, and unchanged native ComboFrame with its CVar enabled. `tests/click_targeting/forever_regressions.rs` exercises the full-startup world-entry event route.

Runtime RED exists in `/tmp/forever-addon-audit/batch-combo-error-transition.json` and the parent's no-addons shared-data control. At `c1e830ffa`, the isolated Forever integration build and `combo_points::` filter pass 6/6, including unchanged native ComboFrame updates with its CVar enabled. This proves the bounded simulator model, not native client behavior.

## Known gaps (current cycle)

- [x] Current-cache preservation: the old original-frame fixture calls removed `ComboFrame_Update` and reads obsolete `COMBO_FRAME_LAST_NUM_POINTS`. It fails identically on retained pre-change fd46b7a9a and current 1c3b548a7 libraries. The pinned `Blizzard_UnitFrame/Camelot/ComboFrame.lua` instead handles world-entry through `ComboFrameMixin:OnEvent` and updates pooled point states. The bounded fixture now invokes the installed original OnEvent handler and checks shown/filled points for3 then0, matching its prior direct-Update scope; global world-entry dispatch in this partial closure also invokes an unloaded BagsBar and is not the full-startup fixture. Whole Forever startup is separately measured. No vendor or producer change. The corrected case passes against both retained fd46b7a9a and current 1c3b548a7 libraries; the five unchanged model cases also pass on current source. Separate whole Forever startup is[]. Later changes are in a client-wrath-only module excluded from Forever compiler inputs.

- [ ] Verify affected addon paths under per-process CVar isolation; the shared-CVar baseline is invalidated and cannot provide this proof.
- [ ] Native PvP/secret-return semantics, nonplayer ownership, and combat generation/consumption remain unmodeled; affected workflows must remain explicit gaps.

## Out of scope

Addon/vendor/cache edits, constant-zero shims, changes to UnitPower snapshots or other profiles, arbitrary combo caps, multi-target accumulation, new targeting/event behavior, and inventory-wide compatibility claims.

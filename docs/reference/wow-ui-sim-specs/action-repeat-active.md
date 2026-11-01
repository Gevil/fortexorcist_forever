# Supplied action repeat-active state (G2)

Integration checkpoint (2026-10-16): Retail/Wrath behavioral RED → GREEN and preservation observed; see [bounded proof](../baselines/approved-batch-2026-10-16.md). No native-parity claim.

Explicit repeat-active slot input drives the existing `C_ActionBar.IsAutoRepeatAction`
query, and the Wrath/Mists legacy projection. This is a simulator contract,
not native parity. Source: `src/c_api/action_repeat.rs`; consumer mechanics remain
in unchanged cached Blizzard Lua. See [event system](../event-system.md).

## What it must do

- [ ] R/P/W/M/F: default false, per-environment repeat-active slot state is independent of casting/current-action, attack classification, spell identity and pet autocast.
- [ ] `A_Admin.SetActionRepeatActive(slot, active)` supplies a positive slot and literal boolean, returns no values and emits no events. Repeated input is idempotent. Invalid input fails before mutation.
- [ ] Query supplied membership from `C_ActionBar.IsAutoRepeatAction`; Wrath/Mists `IsAutoRepeatAction` reads the same state. No repeat inference from cast/combat/spell state.
- [ ] Original cached ActionButton UpdateState consumes current=false/repeat=true/non-pet as checked. An unrelated slot holding the same spell stays unchecked.
- [ ] After explicit START_AUTOREPEAT_SPELL, original StartFlash sets flashing; deterministic original OnUpdate calls toggle the real Flash texture. After clearing input and explicit STOP_AUTOREPEAT_SPELL, checked/flashing/texture return to inactive.
- [ ] Explicit ACTIONBAR_UPDATE_STATE refreshes checked state without inventing start/stop transitions. The setter never changes checked state directly.

Bounded execution covers Retail and Wrath, not every profile named in the contract. Wrath's original numeric checked-state calls require the [local CheckButton input contract](checkbutton-checked-input.md).

## How it works

- [Existing event dispatch](../event-system.md)
- [State-backed action API architecture](../lua-api.md)

## Implementation inventory

- `src/c_api/action_repeat.rs`: supplied membership query and admin ingress.
- `src/c_api/mod.rs`: model module declaration.
- `src/lua_api/state/sim_state.rs`, `src/lua_api/state.rs`: environment-owned membership and empty initialization.
- `src/lua_api/globals/action_bar_api.rs`, `action_bar_api/registration.rs`: namespace and applicable legacy projections.
- `src/lua_api/globals/admin.rs`: admin registration.
- `src/wrath/compat_bootstrap.lua`, `src/mists/compat_bootstrap.lua`: retire obsolete constant-false repeat defaults.

## Tests asserting this spec

`tests/action_repeat_active.rs`: original consumer start/stop/state refresh and Flash
visibility; independent current/attack/same-spell/environment controls; shared legacy
projection; input failure preservation. Original source files are read in full from
the active profile cache, not copied or rewritten. Wrath uses the cache's sibling
`FrameXML/ActionButton.lua`; R/P/M/F use `AddOns/Blizzard_ActionBar/Shared/ActionButton.lua`.
Native CheckButtons/textures and explicit event registration form a bounded fixture,
not a claim of full ActionBar startup/template/router coverage.

## Known gaps (current cycle)

- [x] Behavioral RED obtained with passive ingress before query wiring, then Retail/Wrath GREEN. Retail legacy-only early return carries no behavior credit.
- [ ] PTR/Mists/Forever targeted execution and full-profile/native acceptance remain open.

## Out of scope

- Automatic firing, timers, ammo, combat simulation, classification, G1/G3/G4 changes.
- Action replacement/clear/transfer event semantics. Supplied membership is slot-owned until explicitly cleared by the host; no action/spell lifetime inference.
- STOP's global non-attack flash cleanup remains original consumer behavior; no invented multiple-repeat event arbitration.
- Era/Anniversary acceptance, original ActionBar full startup, native/client security/secrecy claims, vendor edits.

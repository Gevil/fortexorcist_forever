# M2 equipment, spellbook and action startup inputs

M2 replaces individually required factory gaps with state-backed C API bindings or named temporary capabilities. [Follow-up notes](../wiki/systems/c-factory-startup-followup.md#m2-state-adapters) describe ownership; [nil-member publication](c-namespace-nil-members.md) remains unchanged.

## What it must do

- [x] Outside Wrath, `C_PaperDollInfo.OffhandHasWeapon()` reads equipped slot 17/catalog identity: the concrete weapon is true; shield and empty slot are false.
- [x] Retail/PTR/Forever default-player `C_SpellBook.IsSpellKnownOrInSpellBook` accepts seeded book membership and rejects an unknown ID. Pet/off-spec branches and identity-only overrides are source-described extensions, not separate native acceptance claims from this batch.
- [x] Forever `C_ActionBar.UnregisterActionUIButton` removes the selected registered frame without removing other buttons.
- [x] Forever `C_CooldownViewer.IsCooldownViewerAvailable` exposes the supplied availability and failure reason, including a host-supplied true snapshot, not an inferred class/spec policy.
- [x] Forever keyring, lifetime talent-point award and targeting item-condition queries return documented booleans through named temporary workarounds until their backing systems exist.

## How it works

- [State adapters and missing capability systems](../wiki/systems/c-factory-startup-followup.md#m2-state-adapters)

## Implementation inventory

- `src/c_api/{c_paper_doll_info,c_spell_book,c_action_bar,c_cooldown_viewer}.rs` — state/catalog queries and action mutation.
- `src/lua_api/globals/action_bar_api/registration.rs` — existing C API binding registration.
- `src/lua_api/{state.rs,state/sim_state.rs}` — existing availability snapshot also available to Forever.
- `src/lua_api/workarounds/temporary/forever_startup_capabilities.rs` — three explicitly missing systems; profile-only bootstrap wiring in workaround modules.

## Tests asserting this spec

- `tests/cfactory_m2_adapters.rs` — generated-documentation contracts, concrete weapon/shield/absence, spellbook membership and button-removal behavior.

## Known gaps (current cycle)

[Bounded proof and residuals](../wiki/systems/c-factory-startup-followup.md#bounded-proof--2026-10-21) record the completed original-member matrix. Newly exposed AmmoNeeded/GetTargetSpellID remain outside the frozen F0 list and are not implemented by this slice.

## Out of scope

Wrath behavior, inferred keyring visibility from key inventory, talent award inference from level/spent points, native targeting conditions and nonidentity spell overrides. No arbitrary C member factory.

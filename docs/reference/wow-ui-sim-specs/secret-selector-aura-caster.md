# Numeric-secret aura caster identity

Retail/PTR 12.1.5 caster-selector compatibility in `src/c_api/c_unit_auras.rs`; [aura runtime](../wiki/systems/lua-api.md).

## What it must do

- [x] `C_UnitAuras.GetAuraCasterGUID` accepts authentic numeric-secret aura instance IDs under public unit tokens in secure/tainted callers, selecting the same stored aura and configured source GUID as a plain instance.
- [x] Exactly one secret-wrapped GUID is returned for a secret numeric selector; exactly one ordinary GUID for a public selector. One ordinary nil remains the result for missing aura/unit/caster identity. Secret in → secret identity out is explicitly approved simulator policy, not native-parity evidence.
- [x] The unchanged original AuraContainerPublicAuraSourceMixin:GetAuraCasterGUID reaches the real producer and forwards its result with all four selector/caller controls.
- [x] Input opacity, caller taint and source/model rows remain unchanged. Public f64→i32 instance coercion is preserved for numeric-secret selection; non-numeric-secret instances and secret unit tokens remain rejected. INFERRED: native invalid-instance conversion/failure rules are not established by these tests.
- [x] The existing public-selector output and unit-aura-restriction behavior remain unchanged. Implementing the documented RequiresUnitAuraAccess/SecretWhenUnitAuraRestricted layer for this endpoint is separate follow-up scope, not silently bundled into numeric-selector support.

## How it works

- [C API overview](../wiki/systems/lua-api.md)

## Implementation inventory

- `src/c_api/c_unit_auras.rs`: endpoint-local host-only instance inspection and secret identity publication.

## Tests asserting this spec

- `tests/secret_selector_aura_caster.rs`
- `tests/unit_exists_state.rs`

## Bounded proof — 2026-10-20

PTR RED `670b7af51`: three cases fail at typed argument2 before lookup. Producer `130609242` passes direct selection/misses. Original-consumer observation initially fails only when Lua reads a tainted result global then attempts secure unwrapping. Test-only `3abd293c0` explicitly proves that observer taint/denial and checks the emitted secret GUID from the trusted host after Lua context exit: caster3/3 pass on PTR and Retail. No taint reset, VM change or producer workaround is used.

PTR UnitExists5/instance IDs6/admin14/duration selector2 pass; Retail UnitExists8/instance IDs6/admin14/duration selector1 pass. One intermediate helper build failed on private module access and was corrected; one empty guessed filter was rejected with zero credit. Neither is behavioral acceptance evidence.

Selector proof at `3abd293c0`: `tests/secret_selector_aura_caster.rs`, three cases pass on PTR and Retail.

## Known gaps (current cycle)

No unresolved failure within this selector subset. Native unit-aura precondition/output-restriction work remains held.

## Out of scope

Secret unit/spell-string selectors, Retail CarryOver, aura restriction model changes, private-aura endpoints, new GUID model and native invalid-instance ReturnNothing parity. Natural secret-instance producer provenance remains INFERRED; tests inject authentic VM wrappers at the original consumer's selector boundary.

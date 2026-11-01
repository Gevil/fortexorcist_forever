# Numeric-secret aura duration instance selectors

Retail/PTR 12.0.5+ duration-selector compatibility in `src/c_api/aura_duration.rs`; [aura runtime](../wiki/systems/lua-api.md).

## What it must do

- [x] `C_UnitAuras.GetAuraBaseDuration` and `GetRefreshExtendedDuration` accept authentic numeric-secret aura instance IDs under public unit tokens, in secure/tainted callers where existing aura access permits the query.
- [x] The selected stored aura and explicit recast metadata determine exactly one number or one nil, without changing model rows, alias lookup or elapsed-clock math. Unknown and invalid finite numeric instance IDs retain the existing one-nil result.
- [x] Original PTR `AuraContainerUtil.GetPandemicWindow` returns exactly two public numbers `[expiration-4, expiration]` for base20/cap6/remaining4, for public/secret IDs and secure/tainted callers. Retail CarryOver is not implemented as part of this batch.
- [x] Existing RequiresUnitAuraAccess remains enforced: restricted-tainted calls fail for both selector kinds. Restricted-secure duration outputs stay ordinary numbers. INFERRED: preserving plain duration output is approved selector-only simulator policy, not native SecretWhenUnitAuraRestricted parity. That documented output-restriction layer remains separate follow-up work.
- [x] Unit-token secrets, optional spell-selector secrets and non-numeric instance secrets are not widened. Numeric validation/miss behavior remains local to these two endpoints. Wrapper opacity and caller taint are preserved.

## How it works

- [C API overview](../wiki/systems/lua-api.md)

## Implementation inventory

- `src/c_api/aura_duration.rs`: bounded duration instance lookup; existing metadata and aura-access policy.

## Tests asserting this spec

- `tests/secret_selector_aura_duration.rs`
- `tests/aura_refresh_duration.rs`

## Bounded proof — 2026-10-20

PTR RED `25d704534`: both selector cases and the updated legacy selector control fail at the secret-instance guard. Producer `8ef48e2dc`: selector2/2 and legacy18/18 pass, including unchanged original PTR pandemic arithmetic. Retail at `3abd293c0`: selector1/1 and legacy18/18 pass; Retail CarryOver remains excluded. Existing aura access, ordinary duration output, exact nil arity and stored rows are preserved.

DurationObject remains5/6 before/after: the unchanged party fixture does not activate party_group_active. No producer or fixture workaround is included. Other preservation: PTR UnitExists5/instance IDs6/admin14 and Retail UnitExists8/instance IDs6/admin14 pass.

Selector and legacy proof: `tests/secret_selector_aura_duration.rs` and `tests/aura_refresh_duration.rs` pass at `8ef48e2dc` on PTR and `3abd293c0` on Retail.

## Known gaps (current cycle)

Unrelated DurationObject party fixture remains open. Native duration-output restriction remains held, not implemented.

## Out of scope

Retail `GetRefreshCarryOverDuration` backing model; SecretWhenUnitAuraRestricted output publication; secret unit strings/optional spell selectors; changing inferred nil/error or conversion policy to native ReturnNothing; unrelated aura methods. Natural secret-instance provenance is INFERRED: fixture injection proves selector compatibility, not a native startup producer.

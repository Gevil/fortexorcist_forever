# PTR aura caster GUID

`C_UnitAuras.GetAuraCasterGUID` queries the caster of an aura on a specific unit. The pinned contract is in [the 12.1.5 register](../../data/patch-api/sources/12.1.5-register.json); implementation is in [c_unit_auras.rs](../../src/c_api/c_unit_auras.rs).

## What it must do

- [x] Retail/PTR 12.1.5 publishes `GetAuraCasterGUID(auraInstanceUnit, auraInstanceID)`; earlier API epochs preserve absence, including namespace fallback and post-load bootstrap.
- [ ] Public arguments retain existing bridge validation and f64→i32 instance conversion. Retail1215/PTR numeric-secret instances use the [bounded caster selector contract](secret-selector-aura-caster.md).
- [x] Look up the aura through the shared per-unit instance lookup, including helpful and harmful auras; identical IDs on different units do not alias.
- [ ] Return exactly one nullable GUID with the [selected identity-secrecy policy](secret-selector-aura-caster.md); missing units/auras/unresolved source tokens remain one ordinary nil.
- [x] Resolve `source_unit` through the existing unit GUID model at query time. Player and party sources match `UnitGUID`; changing or removing the target source is reflected without replacing the aura.

Live source-token resolution is a simulator choice, not a caster-identity snapshot. An aura whose source token later refers to another unit therefore reports that token's current GUID. Unit existence follows the existing `UnitExists` model; tokens without a modeled GUID return nil rather than the resolver's unknown-creature sentinel.

## How it works

- [Lua API architecture](../lua-api.md)
- [Unit aura instance enumeration](unit-aura-instance-enumeration.md)

## Implementation inventory

- `src/c_api/c_unit_auras.rs`: 12.1.5 registration, nullable caster lookup and endpoint-local numeric-secret selection/publication.
- `src/lua_api/globals/auras.rs`: shared aura-instance lookup.
- `src/lua_api/globals/group_queries.rs`: shared existing-unit state predicate, also used by `UnitExists`.
- `src/lua_api/globals/unit_misc.rs`: live resolution through `guid_for_unit`, excluding unresolved GUIDs.

## Tests asserting this spec

- `src/loader/tests/wow_api_globals/patch_12_1_5_aura_caster_guid.rs`: player/party sources, unit and instance isolation, nil/error behavior, live target identity, earlier-retail absence.
- `tests/aura_instance_ids.rs` and `tests/c_unit_auras_admin.rs`: existing shared aura query regressions.

Focused proof: PTR query tests pass (2); retail absence passes (1). Existing `aura_instance_ids` (5) and `c_unit_auras_admin` (14) tests pass under both profiles. Logs: `/tmp/aura-caster-guid-b2a6b845c-*.log`; unchanged retail absence proof: `/tmp/aura-caster-guid-1ea409579-retail.log`.

## Known gaps (current cycle)

- [ ] Native `RequiresUnitAuraAccess` and `RequiresValidUnitAuraInstance` preconditions are not enforced by this slice.
- [ ] Full native SecretArguments/SecretWhenUnitAuraRestricted parity remains unverified. The [numeric-secret selector and approved identity-output subset](secret-selector-aura-caster.md) is separate simulator policy, not that aura-restriction layer.
- [ ] Native missing-instance behavior, identity lifetime, coercion and error details remain unverified; documented nil/validation behavior is simulator policy.

## Out of scope

Snapshot caster identity, additional GUID models, aura-filter changes and native preconditions beyond the [bounded numeric-selector policy](secret-selector-aura-caster.md) require separate work.

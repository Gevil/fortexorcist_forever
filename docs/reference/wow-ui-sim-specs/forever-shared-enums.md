# Forever Shared Enums

Forever publishes three existing enum contracts through `src/lua_api/globals/enum_data/forever_shared.rs`; see [client profiles](../wiki/systems/client-profiles.md).

## What it must do

- [x] Publish all source-documented `BattleNetFriendLevel` (1–3), `VisualAlertType` (1–10), and `CooldownViewerSound` (0–93) fields and matching metadata on Forever.
- [x] Let vendor AccountUtil rank friend levels and compare their ordering.
- [x] Let vendor cooldown sound data retain numeric sound enums and concrete sound-kit IDs.
- [x] Preserve bounded earlier-profile exposure: Retail/PTR friend-level values/metadata and ranks, sound endpoints/metadata and cat sound-kit mapping, visual-alert endpoints/metadata and template lookups; Classic absence of the nine named modern groups/metadata and RolodexType.LegacyFriend, plus original ClubStreamType numbers/metadata and available sort consumers.
- [ ] Exhaustive earlier-profile shared enum field preservation remains unverified; this isolation run does not replay Forever or establish its retail-epoch behavior.

## How it works

- [Client profiles](../wiki/systems/client-profiles.md)

## Implementation inventory

- `src/lua_api/globals/enum_data/forever_shared.rs` — existing values grouped behind one profile decision.
- `src/lua_api/globals/enum_data/mod.rs` — exports the group alongside base arrays.
- `src/lua_api/env_init/enums.rs` — registers both groups.

## Tests asserting this spec

- `tests/c_api_surface.rs::forever_shared_enums` — compares published fields/metadata against Forever API documentation and executes vendor AccountUtil and cooldown sound data.
- `tests/enum_isolation.rs` — earlier-profile absence and original AccountUtil, cooldown sound, visual-alert and Communities consumers. [Per-profile counts, exact named cases, revisions and evidence](forever-edit-mode-enums.md#earlier-profile-isolation-receipt--2026-10-18): all six GREEN, bounded assertions only. Wrath uses direct stream-value assertions because its inspected cache has no matching CommunitiesUtil file; no substitute consumer is imported.

## Known gaps (current cycle)

- [ ] Full Forever startup and native conformance are not established by these enum fixtures.

## Out of scope

- Other enums, API namespaces, or wholesale retail epoch enablement.

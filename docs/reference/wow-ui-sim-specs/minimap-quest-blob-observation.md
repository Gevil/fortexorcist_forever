# Supplied minimap quest-blob observation

`C_Minimap.IsInsideQuestBlob` reads scenario-supplied per-quest containment. The [minimap investigation](../wiki/investigations/minimap.md#supplied-quest-blob-containment) describes the consumer and evidence.

## What it must do

- [x] For Retail and PTR, pass supplied false and true values to the original objective-tracker consumer.
- [x] Publish the same query and passive input on Forever; prove its original consumer.
- [ ] Publish neither input nor query on undeclared profiles; runtime absence remains unverified.
- [ ] Accept `AllowedWhenUntainted` secret arguments as declared; secret behavior is not yet tested here.
- [ ] Return false for an unsupplied quest as a simulator scenario default. Native containment and its default are unknown; the default's exact Lua boolean is not yet independently tested.

Retail 12.1.5.70448, PTR 12.1.7.70493 and Forever 1.60.1.70532 declare the required numeric quest ID, non-nil boolean result and `SecretArguments = "AllowedWhenUntainted"` in `Blizzard_APIDocumentationGenerated/MinimapDocumentation.lua:151–163`, `:157–169` and `:151–163`, respectively.

## How it works

- [Supplied quest-blob containment](../wiki/investigations/minimap.md#supplied-quest-blob-containment)

## Implementation inventory

- `src/c_api/c_minimap_quest_blob.rs` — query and passive admin input.
- `src/lua_api/state.rs`, `src/lua_api/state/sim_state.rs` — per-environment observations.
- `src/lua_api/globals/admin.rs`, `src/lua_api/globals/missing_surface.rs` — registration.

## Tests asserting this spec

- `tests/c_map_api.rs::test_objective_tracker_quest_blob_observation` — original `QuestObjectiveItemButtonMixin:CheckUpdateInsideBlob` at `Blizzard_ObjectiveTrackerShared.lua:130–134` receives false and true.
- `tests/c_map_api.rs::test_minimap_is_inside_quest_blob` — legacy scenario-default preservation; Rust boolean conversion alone does not prove exact Lua type.

## Known gaps (current cycle)

- [ ] The Retail 11.0.7 publication sweep still fails on the same pre-existing stale LFG authentication gap in RED and GREEN. The minimap row is resolved.
- [x] All seven profile all-target checks pass with zero compiler warnings.

## Out of scope

Geometry, events and map rendering are not derived from this passive input.

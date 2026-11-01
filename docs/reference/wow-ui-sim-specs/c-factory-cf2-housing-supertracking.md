# CF-2 housing and supertracking consumers

Slice 5 restores the original cached Blizzard minimap housing overlay and quest-supertracking consumers on Retail, PTR and Forever. Modeled C_* producers belong in `src/c_api/`; Blizzard Lua remains unchanged. This edit-only delivery contains consumer fixtures, not producers or observed runtime proof.

## What it must do

### Housing overlay

- [ ] With explicitly supplied owned-house interior state, the original `MinimapMixin.UpdateStaticOverlayTexture` shows `MinimapBackdrop.StaticOverlayTexture` with atlas `ui-hud-minimap-housing-indoor-static-bg`.
- [ ] Moving the supplied state from that interior to its exterior owned plot hides the overlay; returning inside shows it again. An owned plot alone must not imply a house interior.
- [ ] Direct original-consumer calls add no Lua errors. Existing closure-load errors remain recorded rather than erased.

### Supertracking preservation

- [ ] Original `SuperTrackEventMixin:CacheCurrentSuperTrackInfo` reaches `Supertracking.OnChanged` after reading `C_SuperTrack.GetSuperTrackedContent`, without a new Lua error. The external listener receives the original frame cache once per explicit refresh.
- [ ] **PENDING-NATIVE-ORACLE:** Seed two supported populated content type/ID pairs through the normal simulator input path; refresh the original consumer and assert both stored fields and `QuestSuperTracking_GetSuperTrackedContent(tracker)` return each exact pair. No executable populated fixture exists yet: the current simulator has no content storage or setter, and valid-ID acceptance is unresolved.

## How it works

- [C API contract and placement](../../AGENTS.md#c-api-boundary)
- [Original addon loading](../addon-loading-pipeline.md)
- [Event dispatch](../event-system.md)

## Implementation inventory

- `tests/cf2_housing_supertracking.rs` — active-profile cache closure, owned-interior/plot transitions and original supertracking refresh boundary.
- `src/lua_api/state/support_types.rs` — existing supplied `HousingState.inside_owned_house` / `inside_owned_plot` fields. The fixture seeds these, not a fabricated generic interior field.
- `src/c_api/c_housing.rs` — existing ownership/location queries use supplied housing state under existing profile gates. No general `IsInsideHouse` implementation exists at the base revision.
- `src/c_api/c_housing/location.rs` — existing plot/neighborhood state; no general house-interior field.
- `src/lua_api/workarounds/temporary/super_track_defaults.rs` — explicitly unmodeled tracking defaults/no-op clears; no live tracked-content store or setter.
- `src/lua_api/workarounds/temporary/world_service_defaults.rs` — empty vignette/tracking probes, not tracked-content state.

## Tests asserting this spec

`tests/cf2_housing_supertracking.rs` in the discovered `integration` target:

- `original_minimap_overlay_follows_owned_house_interior_transitions`
- `original_supertracking_refresh_publishes_its_cache_to_listeners_preserves_boundary`

File-level cfg registers these cases only on Retail, PTR and Forever; other profiles register neither test. Both tests are authored, uncompiled and unrun. Only housing belongs to the expected-RED matrix. Supertracking is preservation only: an empty/no-op producer could satisfy it. It has no producer acceptance until the outstanding laptop PENDING-NATIVE-ORACLE answers establish normal populated inputs and genuine RED assertions. No supertracking producer may be written before those answers.

## Known gaps (current cycle)

- [ ] Observe RED at original `Minimap.lua:295` (Retail/PTR) or `:262` (Forever), missing `IsInsideHouse`, after an admitted slot is granted.
- [ ] Preserve original supertracking notification behavior; a missing-member failure at `Blizzard_QuestSuperTracking.lua:52` is not backing-producer RED acceptance.
- [ ] **PENDING-NATIVE-ORACLE:** Determine general interior state, visited/nonowned interiors and absent-state policy. Existing owned-house state covers only the explicit fixture domain; do not substitute `inside_owned_house` as the complete general-house model.
- [ ] **PENDING-NATIVE-ORACLE:** Determine normal content-input storage, valid IDs/catalog requirements, setter acceptance, mutation/event order and no-target tuple before authoring populated-pair transitions. Cached API documentation declares the tuple and setter arguments, not those policies.
- [ ] Implement housing producer only after observed state-dependent RED. Supertracking producer remains prohibited until native answers and populated RED coverage exist. No temporary stopgap is authorized here.

## Out of scope

- Housing purchase, teleport, ownership permissions and broad housing dashboard closure: separate systems.
- Quest/map-pin/vignette priority, automatic tracking, content catalog and native event-generation parity: not established by the two missing-member consumers.
- Other profiles, full startup health, build/test execution, producer changes and vendor changes: excluded from this edit-only phase.

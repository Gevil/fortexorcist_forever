# House-interior presence

`C_Housing.IsInsideHouse` reports supplied spatial housing presence, independent of ownership. Source: `src/c_api/c_housing.rs`; state storage: `SimState.housing.current_housing_area`. This is the remaining housing half of CF-2 slice 5; SuperTrack is excluded.

## What it must do

- [ ] On Retail, PTR and Forever, return one non-nil boolean: true only for supplied `HouseInterior`, false for `PlotExterior` or absent housing area.
- [ ] An empty world has `current_housing_area = None`; do not invent a house, GUID, room, service status, or native startup location.
- [ ] Visiting and owned interiors show the original Minimap indoor overlay and housing atlas; leaving for a plot or clearing presence hides it; reentry shows it again.
- [ ] The registered original `PLAYER_ENTERING_WORLD` consumer observes the same transitions without a Minimap error.
- [ ] Do not publish this endpoint on Wrath/Mists/Era/Anniversary for this slice.

Generated `HousingUIDocumentation.lua` declares `IsInsideHouse() -> isInside: bool` (not nilable), separately from `IsInsideOwnedHouse`. Original selected `MinimapMixin.UpdateStaticOverlayTexture` sets visibility and the indoor housing atlas from this boolean. The absent-area output is an **empty simulator-world policy**, not evidence of a native client's login location. Supplied `HouseInterior`/`PlotExterior` is a simulator input representation, not a claimed native enum.

## How it works

- [Consumer selection and RED proof](../wiki/investigations/consumer-selection-and-red-proof.md): profile TOC selection and nonvacuous tests.
- [Widget system](../widget-system.md): original consumer changes existing overlay state.

## Implementation inventory

- `src/c_api/c_housing.rs`: `HousingArea` data type and profile-gated state projection; no mutation or service simulation.
- `src/lua_api/state/support_types.rs`: optional current area, None in derived empty state.
- `tests/cf2_house_interior.rs`: original TOC-loaded Minimap, direct and registered-event transition selectors.

## Tests asserting this spec

`tests/cf2_house_interior.rs` registers exactly two selectors on Retail/PTR/Forever:

- `cf2_house_interior::original_minimap_overlay_tracks_house_plot_absence_and_ownership`
- `cf2_house_interior::original_minimap_world_event_tracks_house_plot_absence_and_ownership`

Each independently checks absent -> visiting interior -> plot exterior -> owned interior -> absent -> visiting interior. False/nil/no-return producers fail interior; constant true or any-area-present fail absent/plot; ownership-only fails visiting. No producer replacement, consumer copy, vendor edit, success-return gate or native-default fixture is used. Touched-file formatting is not runtime acceptance.

## Known gaps (current cycle)

- [ ] Runtime RED, producer GREEN, individual constant/no-op/ownership-only mutant rejection and compilation are pending: edit-only staging forbids builds/tests/slots.
- [ ] Paired Retail stock comparison must remove exactly the two existing IsInsideHouse message keys (one occurrence each), with no unrelated changes: expected 36 unique/42 occurrences -> 34/40. PTR/Forever totals require their own receipts.

## Out of scope

Native location discovery/teleportation, housing service enablement, ownership lifecycle/coherence, `IsInsideHouseOrPlot`, other residual members, SuperTrack, vendor behavior changes and all Classic profile API expansion. Existing owned-house/plot flags remain ownership inputs for their existing APIs; they are not substitutes or fallbacks for the new spatial presence input. A host fixture supplying both must describe a consistent world. No C API setter is fabricated to drive tests.

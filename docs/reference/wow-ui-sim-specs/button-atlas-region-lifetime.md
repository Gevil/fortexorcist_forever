# Button atlas region lifetime

Button atlas setters create their texture region independently of atlas-pixel availability. This restores the simulator's earlier button-method behavior; it is not native invalid-atlas parity evidence. The active implementation is `src/lua_api/frame/methods/button_anchor_hierarchy/textures.rs`.

## What it must do

- [ ] A string passed to a button atlas setter creates and publishes that slot's Texture before atlas lookup. Missing atlas data must not leave the slot nil.
- [x] Original PTR 70493 LegacyMicroButton `SetNormal` can set its highlight region's alpha even when its atlas pixels are unavailable.
- [x] Resolved atlas application, parent-slot fields and visibility behavior remain unchanged (10 atlas regressions and 19 texture tests).

## How it works

- [PTR original-consumer investigation](../wiki/systems/housing-spatial-presence.md#ptr-microbutton-region-lifetime).
- [Atlas architecture](../texture-atlas-system.md).

## Implementation inventory

- `src/lua_api/frame/methods/button_anchor_hierarchy/textures.rs` — create/synchronize region before optional atlas lookup.

## Tests asserting this spec

- `tests/cf2_housing_plot.rs::ptr_original_microbutton_keeps_texture_for_unresolved_atlas` — original PTR template and original Lua method.
- `tests/methods_button_textures.rs` — normal button texture behavior.
- `tests/texture_atlas_regressions.rs` — atlas mutation and button-slot preservation.

## Known gaps (current cycle)

- [x] Execute original-template GREEN on c029ad36c after original SetNormal:504 RED.
- [ ] Complete housing/talent acceptance after the separately owned IsWoWHack dependency.

## Out of scope

Missing atlas catalog acquisition, fabricated atlas names or pixels, vendor patches, and native invalid-atlas semantics are excluded. The behavior is not gated by profile because the regression is in the shared simulator setter.

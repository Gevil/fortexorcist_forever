# Disabled checked texture emission

CheckButton selection exercised through unchanged Retail LFGDungeonListButton_SetDungeon and Wrath LFDQueueFrameSpecificListButton_SetDungeon. See [rendering](../rendering-pipeline.md) and [widgets](../widget-system.md).

## What it must do

- [x] A checked enabled checkbox emits its normal checked texture, not its distinct disabled-checked texture; disable/enable selects only the appropriate slot.
- [x] Original reassignment to mixed selection while disabled replaces the emitted path with the mixed disabled-check path; old check paths disappear.
- [x] Unchecked state emits neither check slot; a hidden ancestor suppresses both slots while checked.
- [x] Reassignment and enable transitions preserve both texture child objects and their checkbox parent.

## Implementation inventory

- `src/lua_api/frame/methods/button_anchor_hierarchy/textures.rs`: slot assignment and selection predicate.
- `src/lua_api/frame/methods/button_anchor_hierarchy/buttons.rs`: enable synchronization.
- `src/iced_app/button_vis.rs`: visibility and ancestor filtering.
- `src/iced_app/strata_emit.rs`: emitted request boundary.

## Tests and proof

`tests/c12_disabled_check_consumer.rs` contains one shared test, executed once per Retail/Wrath profile. Both pass without producer changes. Replacing the disabled slot with the normal check after the original consumer runs makes each profile fail its emitted-path assertion, establishing non-vacuity. Fixtures supply row widgets/header data; complete original consumer functions choose the texture paths. Proof covers the source through `5f5aa4563`; later StartMoving capture changes do not affect this render path.

Existing `tests/methods_button_textures.rs` and `tests/checkbutton_render_order.rs` cover storage and ordinary ordering, not this disabled-output acceptance.

## Exclusions

Nil-slot fallback remains unspecified. No native-client parity, complete LFG startup, XML-template loading, screenshots, font precedence, AddonList desaturation or other-profile acceptance. Mists has a different caller and requires a separate applicability fixture. Cache, loader and compilation failures never count as behavioral RED.

# Rotated tiled edge prefix

Rotated horizontal edge tiling in [`src/iced_app/tiling.rs`](../../src/iced_app/tiling.rs) must preserve artwork order when clipping the final tile. See the [texture atlas system](../texture-atlas-system.md) for rendering context.

## What it must do

- [x] A partial final tile displays the left-to-right prefix of a complete rotated tile, not its suffix.
- [x] Complete tiles retain their reversed-V orientation: a source column with eight red texels followed by eight blue texels displays eight blue pixels followed by eight red pixels per 16-pixel tile.

## How it works

- [Texture atlas and tiling](../texture-atlas-system.md)

## Implementation inventory

- `src/iced_app/tiling.rs`: rotated horizontal tile emission and color-row regression tests.

## Tests asserting this spec

`src/iced_app/tiling.rs::rotated_tail_tests` samples concrete RGB rows from emitted quads:

- `rotated_partial_tile_preserves_full_tile_prefix`: 40 pixels contain two blue/red tiles followed by eight blue pixels.
- `rotated_complete_tile_keeps_reversed_v_orientation`: 32 pixels contain two unchanged blue/red tiles.

Exact-source standalone harness evidence: the partial-row test fails against the old emitter; both tests pass against the patched emitter.

## Known gaps (current cycle)

- [x] Integrated tiling-model tests passed at runtime source136; see [central receipt](../baselines/README.md#verified-scoped-receipts--2026-10-15).
- [x] Separate earlier [combined GPU receipt](../rendering-pipeline.md#combined-feedback-gpu-receipt--2026-10-15) confirms blue tail/reference and complete-tile controls at its recorded source, not current-source GPU acceptance.
- [ ] Filtering/atlas-bleed, native and full-parent acceptance remain open.

## Out of scope

- CPU row sampling does not establish GPU filtering or atlas-bleed behavior.
- No changes to vendor artwork, PNG output, sliders, or source caches.

# Texture SetTexture result

Shared `Texture:SetTexture` returns one non-nil boolean. The cached Retail
`Blizzard_APIDocumentationGenerated/SimpleTextureBaseAPIDocumentation.lua:604-618`
declares `success: bool`. Exact resolution and clear behavior below are simulator
policy, not measured native parity.

## What it must do

- [ ] Return true for paths or file IDs known to the existing texture catalogs,
  or files found through existing texture path resolution without decoding pixels.
- [ ] Return false for unresolved assets. Keep existing texture assignment and
  argument handling; do not fabricate catalog entries or return unconditional true.
- [ ] Clearing with nil, empty string, or numeric zero clears existing texture
  state and returns false: no asset was applied, matching the result-policy style
  of [SetAtlas](texture-atlas-application-result.md).
- [ ] Original Wrath LFD renderer preserves known heroic and holiday backgrounds
  rather than always executing its missing-texture fallback.

## How it works

- [Texture atlas system](../texture-atlas-system.md)

## Implementation inventory

- `src/lua_api/frame/methods/widgets/texture/atlas.rs`: texture mutation and result.
- Existing manifest/listfile and `TextureManager` resolution remain authoritative.

## Tests asserting this spec

- `tests/texture_set_texture_result.rs`: exact boolean count, known/missing paths
  and IDs, clears, addon file and directory controls; no GPU or pixel decoding.
- `tests/wrath_residual_b.rs`: original LFD renderer, catalogued heroic340816 and
  holiday brew368570 assets with supplied dungeon state.

## Known gaps (current cycle)

- [ ] RED/GREEN and shared SetTexture preservation; Retail and Wrath startup.
- Catalog existence does not prove local CASC availability or valid image pixels.

## Out of scope

Vendor edits, image decoding/rendering changes, fabricated assets, native parity,
and changes to unrelated texture setter/argument behavior.

# Retail tooltip path separator (U1)

Integration checkpoint (2026-10-16): corrected user-selected geometry oracle reached Retail RED → GREEN; [bounded proof](../baselines/approved-batch-2026-10-16.md). No native-parity claim.

Bounded simulator contract for the original cached Retail `SocialUIUtil.AddSeparatorToTooltip` consumer. Source: `src/lua_api/frame/methods/widgets/tooltip/line_frames.rs` and `src/iced_app/tooltip.rs`. Implemented simulator contract; numeric behavior is preserved. Geometry below is an explicit simulator policy, not established native semantics.

## What it must do

- [ ] Execute the unchanged cached `retail/AddOns/Blizzard_SocialUIShared/SocialUIUtil.lua:138-152` and attach its path/options divider to the wrapped blank row it just added, without increasing NumLines again.
- [ ] Emit one deferred texture request for that path between Header and Footer, spanning the content width with zero horizontal margins.
- [ ] Accepted simulator geometry policy (2026-10-16): keep the normal blank text-line height (15 body units here); center the supplied 10-unit image vertically in that row (2.5-unit offset). Supplied top/bottom margins do not shrink the row or shift the centered image. Existing inter-row spacing remains unchanged. Apply effective scale and tooltip alpha. The rejected alternative reserves 6 units (10 - 2 - 2) and starts the image at -2; it is not this contract.
- [ ] ClearLines removes the attachment; rebuilding text-only content emits no stale divider.
- [ ] Numeric and numeric-string AddTexture inputs still append their own rows, including when an options table is supplied; keep FileDataId storage unchanged.

## How it works

- [Rendering pipeline](../rendering-pipeline.md)
- [Widget system](../widget-system.md)

## Implementation inventory

- `src/lua_api/tooltip.rs`: attached path and height/margin data; one geometry function governs both row reservation and image offset.
- `src/lua_api/frame/methods/widgets/tooltip/line_frames.rs`: bounded path/options decoding and existing-row attachment.
- `src/lua_api/frame/methods/widgets/tooltip/sizing.rs`: immediate Lua-visible row sizing.
- `src/iced_app/tooltip.rs`: measured sizing, render collection and deferred path quad emission.

## Tests asserting this spec

- `tests/tooltip_separator_u1.rs`: original complete cached Lua file, helper invocation, row/text order, emitted quad bounds at scales 1 and 0.5, alpha, clear/rebuild and numeric preservation. No image decode or CASC access required for deferred quad evidence.
- `tests/tooltip_text.rs`: existing numeric and numeric-string behavior controls.

## Known gaps (current cycle)

- [x] User selected unchanged blank-row height and centered image on 2026-10-16; simulator policy only.
- [x] Corrected tests-only oracle reached missing-divider RED before producer; divider/numeric cases became GREEN, with existing tooltip preservation and startup observation.
- [ ] Texture decoding/GPU pixels, native and other-profile acceptance remain outside this evidence.

## Out of scope

Other texture anchor modes, path-only/legacy positional calls, arbitrary nonblank-row attachments, numeric rendering changes, atlas changes, native parity, texture decode/assets/GPU acceptance, other profiles and vendor Lua modifications.

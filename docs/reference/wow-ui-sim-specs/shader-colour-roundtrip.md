# Shader colour roundtrip

Rendering must not apply a brightness workaround to compensate for the missing 3D world. See the [rendering pipeline](../rendering-pipeline.md).

## What it must do

- [x] Preserve opaque sRGB texture bytes through white modulation into an sRGB output target; do not apply an artificial RGB power lift.
- [x] Retain the existing linear solid-input, sRGB attachment, premultiplied-alpha and additive blending paths.
- [x] Verify production shader readback for opaque textures, solids, half-alpha and additive controls on runtime source136 (not the unbuilt current import revision).

## How it works

- [Rendering pipeline](../rendering-pipeline.md)

## Implementation inventory

- `src/render/shader/quad.wgsl`: no post-modulation brightness lift.
- `src/render/headless_colour_tests.rs`: opt-in production wgpu readback regression; hardware and software adapters are valid functional backends.

## Tests asserting this spec

`render::headless::colour_tests::colour_readback_has_no_artificial_brightness_lift` checks concrete swatch bytes. Run its documented ignored-test filter explicitly.

Pre-fix standalone production rendering of an opaque RGB128 texture produced RGB162. A separate solid input of 0.5 produced RGB208. The texture result demonstrates the lift independently of Lua solid-colour interpretation. Post-fix production readback PASS; the [central receipt](../baselines/README.md#verified-scoped-receipts--2026-10-15) owns exact controls, adapter and source scope.

## Out of scope

No attachment/atlas format changes, extra transfer functions, vendor edits, or native WoW colour-space parity claim. A solid input of 0.5 is not assumed to mean encoded RGB128 under the existing linear-input contract. The feedback's alleged second encoding remains unestablished.

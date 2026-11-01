# Supplied animation transforms and Translation layout motion

Status: producer `269ed6f17` replaces the passive scaffold; historical behavioral RED accepted. Bounded producer GREEN accepted from the sealed component receipts below. No native, full-profile, startup, format or type-check acceptance is implied.

Translation, Scale and Rotation preserve supplied Lua/XML configuration. Translation uses the simulator's existing presentation-offset layout model. This contract is **simulator policy, not native parity**; historical behavioral RED and post-GREEN receipts are recorded below. Public sources establish signatures and consumption, not interpolation/restoration semantics. See [Path](path-control-point.md), [VertexColor](vertex-color-animation.md) and [query lifecycle](animation-query-lifecycle.md) for existing model boundaries.

## What it must do

- [ ] Translation `SetOffset(x,y)` / `GetOffset()` preserve signed/fractional supplied values, exactly two returns, independent per animation.
- [ ] Scale `SetScaleFrom/To(x,y)` / `GetScaleFrom/To()` preserve separate supplied pairs. `SetScale/GetScale` preserve a separate legacy two-number pair; **stage policy:** no inferred linkage to endpoint pairs and no scalar Frame-scale mutation. Scale/Rotation `SetOrigin(point,x,y)` / `GetOrigin()` preserve the three supplied values independently.
- [ ] Rotation `SetDegrees/GetDegrees` and `SetRadians/GetRadians` address one angle: degree/radian conversion, without wrapping. This mutual conversion is a simulator policy, not inferred from Wowless's independent stored fields.
- [ ] Normal addon XML loading applies `offsetX/Y`, `scaleX/Y`, `fromScaleX/Y`, `toScaleX/Y`, `degrees` and `<Origin point x y>` through the same public state. No synthetic `fromScale`/`toScale` scalar XML aliases are introduced.
- [ ] **Stage policy:** one positive-duration, order-1 Translation on a target in a NONE-looping group adds interpolated displacement to its pre-play presentation offset in existing screen-layout axes, at unit scale. NONE is linear; OUT uses existing VertexColor quadratic easing. Owner/default and childKey targets work; child-target motion leaves owner/sibling rectangles and target dimensions unchanged. Pause freezes, resume preserves baseline, Stop/natural finish/hidden-owner stop restore baseline, and replay snapshots changed baseline. `SetToFinalAlpha(true)` remains alpha-only; it does not retain offsets. No native restoration or coordinate-sign claim.

## How it works

- [Layout system](../layout-system.md)
- [Animation Path contract](path-control-point.md)
- [VertexColor contract](vertex-color-animation.md)
- [Animation lifecycle](animation-query-lifecycle.md)

## Implementation inventory

Producer `269ed6f17` replaces the tests-stage neutral queries with per-animation supplied configuration and shared Translation motion application/restoration, without a second attachment/publication path. Historical passive zero offset/angles, identity scale pairs and CENTER/zero origin were scaffold policy, not native defaults:

| Path | Role |
|---|---|
| `src/lua_api/animation.rs` | Supplied transform fields and shared saved motion offsets. |
| `src/lua_api/frame/methods/button_anchor_hierarchy/animations/transforms.rs` | Type-local configuration/query methods. |
| `animations/{creation,path_runtime,play,runtime}.rs` and `animations.rs` | Attach endpoints before template application; reuse target resolution, offset application/restoration and existing lifecycle. |
| `animations/vertex_color.rs` | Share the already-modeled progress/easing calculation without changing color output. |
| `src/xml/types_animation.rs`, `src/loader/helpers_anim.rs` | Existing parsed attributes and setter emission, unchanged. |
| `src/layout.rs` | Existing `anim_offset_x/y` projection, unchanged. |

## Tests asserting this spec

`tests/animation_transforms.rs`, discovered into `--test integration`, seven cases:

| Test | Observable assertions |
|---|---|
| `a1_translation_offset_round_trips` | Signed/fractional pairs, return arity, mutation, independent instance. |
| `a1_scale_pairs_and_origin_round_trip` | Distinct from/to/legacy pairs, mutation, independent origins, owner scale unchanged. |
| `a1_rotation_units_and_origin_round_trip` | Signed/unwrapped angle conversions, origin mutation, independent instance. |
| `a1_xml_transform_values_reach_queries` | Real addon TOC/XML loader, all listed attributes and explicit Scale/Rotation origins. |
| `a1_translation_ticks_restore_and_replay` | Child layout at quarter/half/three-quarter time, nonzero baseline, owner/sibling isolation, pause/resume, Stop/natural finish, changed-baseline replay, final-alpha independence. |
| `a1_translation_xml_out_moves_only_declared_child` | Literal CatalogShop Translation tag in reduced fixture, half-time OUT layout, owner isolation and natural restoration. |
| `a1_translation_owner_and_hidden_stop` | Default owner target moves; Hide stops/restores before explicit Stop. |

All cases are shared-source and ungated. Retail first; other profiles require separate execution. Reduced public-tag fixture is not whole-vendor lifecycle proof.

## Bounded RED and post-GREEN receipts — 2026-10-16

Historical tests/passive scaffold: `680a35a1e`; producer: `269ed6f17`. The independent RED report authenticates production-input hashes despite the libraries' older recorded HEAD and documents the cfg-excluded Retail helper conversion difference; do not attribute producer behavior to the RED libraries.

- Retail RED component: `/home/osso/.local/state/wow-ui-sim/verification/green-batch/label-retail-red-20261016T194438112412Z`.
- Wrath RED component: `/home/osso/.local/state/wow-ui-sim/verification/green-batch/label-wrath-red-20261016T195708968486Z`.
- Independent RED acceptance: `/home/osso/.local/state/wow-ui-sim/verification/green-batch/label-red-report.md` (saved artifact/source reconciliation, not a fresh run).

**A1 observed RED:** Retail 7 FAIL / 0 PASS; Wrath 7 FAIL / 0 PASS. Four numeric/XML cases reach wrong neutral values; three motion cases reach computed-layout x mismatches. Methods and setup succeed. Later replay/restoration assertions are not established by RED; existing setter/Path controls are separate preservation evidence.

**Accepted bounded GREEN receipt:** Retail `/home/osso/.local/state/wow-ui-sim/handoff/label-producers-green-private/components/label-prod-retail-labels-20261016T210501464288Z`; Wrath `/home/osso/.local/state/wow-ui-sim/handoff/label-producers-green-private/components/label-prod-wrath-labels-20261016T211404318442Z`; independent reports `/home/osso/.local/state/wow-ui-sim/verification/label-producers-green/retail-report.md` and `/home/osso/.local/state/wow-ui-sim/verification/label-producers-green/wrath-report.md`. Those reports own executed identities/counts, assertion reachability, source/artifact identity and preservation scope. Retail cannot earn Wrath-only C11/legacy quest credit. Preservation: Retail 181 active passes; Wrath 173 active passes. Wrath executes zero Path cases: all eight declarations in `tests/path_control_point.rs` are excluded by the pre-existing line-3 `#![cfg(feature = "retail-12-0-0")]`, absent from the emitted `client-wrath` feature set. No Wrath Path behavioral pass is claimed. Other profiles, ordinary startup, format/check and native parity remain separate gates.

## Known gaps (current cycle)

- [x] Saved passive-scaffold value/layout RED accepted; exact reached boundaries are above. Existing setter-callability tests in `animation_anim.rs` earn no new A1 credit.
- [ ] Producer and preservation acceptance is bounded by the resolved receipts above; format/check/startup and other profiles remain separate.
- [ ] Scale/Rotation visual effects remain unmodeled. Frame scalar scaling and static texture rotation exist but are not per-axis region animation/pivot hooks; this stage does not repurpose them or claim effective-size/pixel motion.

## Out of scope

Native defaults/coercion/errors/security/aliasing, full supported-profile certification, non-unit scale, native coordinate conversion, multi-animation/group composition, ordered translation accumulation, loop/reverse geometry proof, zero-duration behavior, callback ordering, SetTarget-family redesign, LineTranslation/LineScale, GPU/quads, and vendor changes. Neutral new field defaults (zero offset/angle, identity scale pairs, CENTER origin) are implementation initialization, not native-contract assertions. Existing Path behavior must remain unchanged; its tests are preservation controls, not new A1 credit.

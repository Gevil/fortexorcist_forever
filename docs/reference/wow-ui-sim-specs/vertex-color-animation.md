# VertexColor animation

Patch 10.2.5 introduces texture vertex-color interpolation. [Literal source](../../data/patch-api/sources/10.2.5-api-changes.txt), lines 15–47, specifies individual RGBA interpolation and equivalent two-second red/blue BOUNCE Lua/XML examples. The active retail cache's `Blizzard_APIDocumentationGenerated/SimpleAnimVertexColorAPIDocumentation.lua` specifies four endpoints: setters take one non-nil ColorMixin `colorRGBA`; getters return one non-nil ColorMixin `colorRGBA`. [Publication audit](patch-10-2-5-publication-sweep.md) remains separate from behavioral proof.

## What it must do

- [x] Receiver-scope repair, current bounded 7/7 runtime proof: the four endpoint methods are available only on actual `VertexColor` animation tables, not ordinary widgets, animation groups or other animation types. Applicable Retail method-diff baseline and discovery captures remain unchanged.
- [x] `SetStartColor`/`SetEndColor` accept complete RGBA color objects; `GetStartColor`/`GetEndColor` return color objects exposing `GetRGBA`, not four numbers. Endpoint state is independent of texture state.
- [x] Animate each RGBA component from start to end without color-space conversion; apply to texture owner or resolved animation child target, leaving other textures unchanged.
- [x] Run the literal two-second BOUNCE example through both directions and repeat; reverse playback starts at the end of the existing group timeline.
- [x] XML `StartColor`/`EndColor` configure the same endpoints and produce the same output as Lua; omitted XML alpha is one, matching `CreateColor(r,g,b)`.
- [x] **Modeled inference:** snapshot endpoint channels and return independent color objects. Native aliasing policy is unknown.
- [ ] **Modeled inference, untested:** endpoint defaults are opaque white; invalid ordinary arguments require a table with numeric RGBA channels. No initial-default assertion or invalid-color argument tests ran; native default/coercion/error policy is unknown.
- [x] **Modeled inference:** smoothing changes time progress, not channel color space: NONE linear, IN quadratic ease-in, OUT quadratic ease-out, IN_OUT piecewise quadratic. Start/end delays use the existing group scheduler. Native smoothing curve parity is unknown.
- [x] **Modeled inference:** save original target vertex color once per playback; pause freezes and resume retains the snapshot. Stop, hidden-owner stop, natural finish, and pending Finish restore it; replay captures the new baseline. `SetToFinalAlpha` controls alpha only and does not retain vertex color. Native vertex-color restoration policy is unknown; this extends existing alpha restoration semantics without inventing a final-color flag.

## How it works

- [Animation factory contract](animation-factory.md).
- [Lua API architecture](../lua-api.md).
- [Widget state and rendering](../widget-system.md).

## Implementation inventory

- `src/lua_api/animation.rs`: animation/group endpoint and saved-target state.
- `src/lua_api/frame/methods/button_anchor_hierarchy/animations/vertex_color.rs`: RGBA endpoint snapshots, independent color objects, smoothing and texture target application/restoration.
- `src/lua_api/frame/methods/button_anchor_hierarchy/animations/`: playback lifecycle and direction-aware boundary reflection; `animations.rs` connects stop/restart.
- `src/lua_api/frame/methods/button_anchor_hierarchy/mod.rs`: retains the four-method static Rust-function registration helper, no longer called on the shared animation method table.
- `src/lua_api/frame/methods/button_anchor_hierarchy/animations/creation.rs`: attaches those methods directly to the rooted, cached `VertexColor` Lua frame table during `CreateAnimation`, before template application. XML creation uses the same factory. Ordinary-widget metatable enumeration remains unchanged; animation/group frames still use `WidgetType::Frame` plus `object_type_name`.
- `src/xml/types_animation.rs`: parsed endpoint elements.
- `src/loader/helpers_anim.rs`: shared XML endpoint application.

## Tests asserting this spec

- `tests/vertex_color_animation.rs`: **6/6 GREEN**, exit0, at source `080833f1d182caaa762c734a988847edd20f633b`; endpoint objects, channel interpolation, bounce/reverse, smoothing/delays, target isolation, pause/resume/restoration/replay and actual addon XML loading. GREEN3176 runtime `runtime-scoped-20261013T013111696766Z`, artifact epoch `admitted-native-20261013T011400020026Z`; recorded compile/runtime source maps equal and saved seals unchanged by stat receipt. Public packet not yet retained; no public evidence link claimed.

- `vertex_color_animation_endpoints_are_scoped_to_vertex_color_receivers`: new focused actual-lookup test checks four usable VertexColor endpoints, RGBA snapshots and absent methods on Frame, Texture, AnimationGroup and every other modeled animation type. Current bounded run passes this receiver test and six existing controls, 7/7, exit0. Prior 6/6 GREEN remains historical.
- Retained receiver-leak RED at `080833f1d`: `method_diff_coverage` missing snapshot PASS, extra snapshot FAIL with 64 extras (four endpoints × 16 ordinary widget types), exit 101. Receipt retained privately; no public packet claimed. Current focused lookup plus six controls pass 7/7; both applicable method comparisons pass 2/2. Graph consistency is not native parity; public packet retention awaits main publication.

## Known gaps (current cycle)

- Historical RED at `6c4f39abc3b8a3987e7d45baca80271fa233091d`: six selected tests failed at missing `SetStartColor`; no downstream assertions reached. Production now committed and bounded GREEN above reaches those assertions; historical receipt remains unchanged.
- [ ] Explicit XML alpha, ordered-group composition and large-delta crossing proof require bounded tests before claiming those boundaries.

## Out of scope

Native/historical/security parity, invalid-argument compatibility, multi-group conflict resolution, nontexture color animation, other animation features, vendor changes and animation-system redesign. Publication fixtures and frozen historical evidence are parent-owned reconciliation, not behavioral proof.

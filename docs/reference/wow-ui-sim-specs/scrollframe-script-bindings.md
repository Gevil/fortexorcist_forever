# ScrollFrame script bindings

Scroll offset and range changes dispatch declared scripts through the existing binding registry. The simulator parses the unchanged Blizzard EventScrollFrame declarations rather than invoking similarly named properties as an alternate path. See [XML template system](../xml-template-system.md).

## What it must do

- [x] Parse and register XML `OnHorizontalScroll`, `OnVerticalScroll`, and `OnScrollRangeChanged` in ordinary and runtime-template construction.
- [x] Run registered precall, normal/hooks, and postcall handlers in order, with committed scroll values and existing payloads. Preserve unchanged-offset/range no-ops.
- [x] Report handler errors and continue later bindings.
- [x] Deliver unchanged EventScrollFrame callback-registry events once, before normal scripts as its XML declares; do not automatically invoke unregistered `*_Intrinsic` properties.
- [ ] Let empty `function=""` clear only its selected inherited script binding; preserve other bindings, nonempty functions, and methods.

## C9 range update boundary

The user-supplied functional requirement moves only explicit `UpdateScrollChildRect()` range refresh to the ScrollFrame update pass. Existing automatic resize refresh remains unchanged; no broader resize policy is authorized. Its historical evidence is 3.3.5a/build12340, not executed native or modern Retail timing proof; no reconstructed implementation was consulted.

- [ ] `UpdateScrollChildRect()` marks the ScrollFrame dirty and returns without recalculating ranges or dispatching `OnScrollRangeChanged` on that API call stack.
- [ ] Process the dirty ScrollFrame after its OnUpdate and animation processing. A request from OnUpdate or animation processing can complete later in that same frame; an arbitrary timer or extra tick does not satisfy this boundary.
- [ ] Preserve resolved subtree range arithmetic, commit both ranges before dispatch, and notify only when the resulting pair changed. Repeated unchanged refresh remains silent.
- [ ] Preserve registered-binding order/error reporting, independent synchronous offset callbacks, scroll-child ownership, anchors and presentation. Timing changes do not authorize vendor patches or a layout redesign.

Saved Retail-epoch baseline `d16876fcc9ec0e49851436a6af7a1e308d0a344c` executed all three cases in `tests/scroll_range_update_pass.rs`: **0 passed, 3 failed, exit 101**. The private saved epoch is `c8-producer-c7-c9-retail-baseline-20261016T003140348455Z`, selection `scroll-range-update-first-red`. Outside-call, OnUpdate, and real Alpha animation OnFinished traces all show range delivery before the explicit call returns, reproducing the timing failure. Callback entry is recorded before protected assertions; traces and the error sink are checked outside callbacks. Assertions after each first failure are not independent acceptance proof.

C9 producer `d7cd9040c`, separate from that saved baseline, queues explicit requests in a pending set, drains a snapshot after OnUpdate and animation processing but before existing late layout size callbacks, and uses the existing range refresh. Automatic resize refresh is unchanged. Saved Retail source `792d62003` passes all three C9 cases, exit0, including the actual Alpha OnFinished request and same-frame notification after animation processing; independent full-stream/seal verification confirms this bounded result. Existing explicit synchronous-refresh test assumptions were reconciled to real ticks in the producer commit, preserving arithmetic/binding assertions and automatic resize policy; saved `03769bb00` now independently passes the broader scroll selection, including the two `d374c9520` timing-reconciled XML fixtures with payload/global assertions intact. The [shared receipt](editbox-text-position-selection.md#saved-xmlscroll-and-genuine-consumer-acceptance) owns exact totals, expected sentinel, historical REDs and scope limits; this is not a new C9 rerun or shared-Wrath acceptance. Modern native timing and all-profile behavior remain unproven.

## Library fixture reconciliation

Tests-only `f00f230fe` changes `test_scrollframe_scroll_scripts_fire_from_native_methods` to tick `env.fire_on_update(0.016)` before reading its Lua snapshot, so it observes deferred explicit range-refresh callback work. Existing range, offset and callback assertions remain; no runtime implementation or automatic resize policy changes. Independently accepted saved source `655f0698b` Retail library execution passes one selected case, exit0, reaching all seven retained assertions after the real update tick: range callback count 1, horizontal/vertical ranges 0/150, scroll callback count 1 and offset 40, current offset/range 40/150. No direct handler invocation. See [saved bounded receipt](../wiki/investigations/test-suite-performance.md#saved-fullsuite39-bounded-runtime) for shared build and scope limits. Fullsuite39 remains historical FAIL.

## How it works

- [Event dispatch](../event-system.md)
- [Scroll offsets](scrollframe-offsets.md)
- [Scroll presentation](scrollframe-presentation.md)

## Implementation inventory

- `src/xml/types_support.rs`: parsed script declarations.
- `src/loader/helpers.rs`, `src/lua_api/globals/create_frame/template_chain.rs`: ordinary/runtime script enumeration and registration.
- `src/lua_api/frame/methods/widgets/slider.rs`: offset/range mutation and registered binding dispatch.

[Bounded PTR C9 execution](../baselines/README.md#ptr-shared-controls--2026-10-16) covers real update/animation boundaries under the shared simulator policy, not native timing parity.

## Tests asserting this spec

`tests/scroll_widgets/script_bindings.rs`, inside the existing grouped integration target, proves registration and dispatch through an ordinary XML `<ScrollFrame>` and through cached EventScrollFrame XML/Lua. Both paths verify public `GetScript` bindings, committed payloads, callback order, and zero recorded Lua errors. Existing `tests/scroll_widgets.rs` retains offset/range/presentation controls.

## Known gaps (current cycle)

Tests-only `1e4706e2a` originally reproduced four failures: three missing XML registrations because `ScriptsXml` dropped the declarations, plus automatic invocation of an unregistered property. These were not dispatch-only RED failures. `c82ed91af` closes that boundary with 60 unique relevant passing cases, including ordinary XML and strengthened cached EventScrollFrame coverage; `/tmp/cross-version-scroll-script-bindings-verification-ledger.md` records full registration and runtime proof. Pre-existing readability caps remain reported there: `input_handlers_with_options` length and `template_chain.rs` file size.

`6325ae0d4` established RED for empty `function=""` clearing in ordinary normal, runtime precall, and cached FauxScrollFrame inheritance; postcall and retained-binding assertions followed the first failure, so they were not independently RED. Bounded default-profile GREEN at `3e67e7b6e` passes 47 test instances plus format/check/integration compilation, proving ordinary normal and explicit precall/postcall clearing. Intrinsic-default selection, whitespace-only classification, and `method=` precedence are source-inspected only. See [XML empty script-function clearing](xml-empty-script-clearing.md).

Blizzard's cached `Blizzard_SharedXML/Shared/Frame/EventScrollFrame.xml` explicitly binds the three `*_Intrinsic` methods as precalls. The corresponding Lua methods emit callback-registry events. Both files remain unchanged; this is consumer/source corroboration, not a fresh native-client probe.

## Bounded Mists execution — 2026-10-16

[Shared Mists owner matrix](../baselines/README.md#mists-shared-controls--2026-10-16) owns independently accepted saved results, provenance, diagnostics and remaining profile limits. This supplements historical evidence, not native or broader contract acceptance.

[Bounded Era execution](../baselines/README.md#era-shared-controls--2026-10-16) separately accepts the corresponding matrix cases from saved artifacts only; current source and broader criteria remain unaccepted.

[Bounded Anniversary execution](../baselines/README.md#anniversary-shared-controls--2026-10-16) separately accepts the same corresponding matrix cases from saved Anniversary artifacts only; current source and broader criteria remain unaccepted.

## Out of scope

Mouse-wheel/size/lifecycle dispatch, new XML implicit argument names, offset clamping, layout or ownership changes, opposite-state recursive callback policy, and native/GPU/all-profile parity.

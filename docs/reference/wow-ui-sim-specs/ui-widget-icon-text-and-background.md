# Supplied IconTextAndBackground widgets

`C_UIWidgetManager.GetIconTextAndBackgroundWidgetVisualizationInfo(widgetID)` must project explicit environment-local supplied records for the unchanged cached Retail/PTR consumer. The source boundary is `src/c_api/ui_widget_manager/`; the [manager-state contract](ui-widget-manager-state.md) owns shared supplied-state behavior and the [manager architecture](../wiki/systems/ui-widget-manager-state.md) describes the existing lifecycle. Selector tests have an independently reconciled two-case PTR RED against normal-library source `161dad02a`; this is failing behavior, not acceptance. Passive record/map/feed plumbing then compiled at `4adc7cf89`; main-observed populated PTR baseline is0PASS/8FAIL, exit101. Getter source `2a422cb86` projects that supplied state. The [bounded PTR receipt](#bounded-ptr-producer-proof--2026-10-16) and [bounded Retail receipt](#bounded-retail-producer-proof--2026-10-16) independently accept the combined supplied-record requirements at their saved execution boundaries; broader gates remain open.

## What it must do

### Source eligibility and query

- [x] Support this record on Retail/PTR, where both cached `Blizzard_APIDocumentationGenerated/UIWidgetManagerDocumentation.lua` declarations and the registered `Blizzard_UIWidgets/Blizzard_UIWidgetTemplateIconTextAndBackground.lua` consumer exist. Eligibility rests on those actual sources, not a callable namespace entry or an inferred native catalog. No other-profile acceptance is claimed.
- [x] Require numeric `widgetID` using the existing manager required-number/secret policy. Missing, nil and non-number arguments (including numeric strings) reject at that boundary. Preserve documented `SecretArguments = "AllowedWhenUntainted"` through the shared policy; do not introduce a new secret policy. An absent numeric ID returns exactly one nil.
- [x] Project all 14 non-nil fields below with their supplied values and documented types; do not invent defaults or truncate the record to fields read by Setup. Enum values are supplied numeric scalars; texture kits are supplied strings.

| Exact field | Cached documented type |
| --- | --- |
| `shownState` | `WidgetShownState` |
| `text` | `string` |
| `widgetSizeSetting` | `number` |
| `textureKit` | `textureKit` |
| `frameTextureKit` | `textureKit` |
| `hasTimer` | `bool` |
| `orderIndex` | `number` |
| `widgetTag` | `string` |
| `inAnimType` | `WidgetAnimationType` |
| `outAnimType` | `WidgetAnimationType` |
| `widgetScale` | `UIWidgetScale` |
| `layoutDirection` | `UIWidgetLayoutDirection` |
| `modelSceneLayer` | `UIWidgetModelSceneLayer` |
| `scriptedAnimationEffectID` | `number` |

- [x] Each query returns a fresh snapshot. Caller mutation, retained snapshots, supplied replacements, distinct IDs and separate `WowLuaEnv` instances stay isolated. Record absence/removal and restoration affect subsequent queries only. Use the existing manager numeric identity policy; do not add integer, positivity or inferred-range restrictions.

### Normal feed and cached lifecycle

- [x] Existing normal host feeds accept the supplied visualization with the documented `Enum.UIWidgetVisualizationType.IconTextAndBackground` membership type. Store state before synchronous `UPDATE_UI_WIDGET`; wrong-type and absent-set updates reject without state mutation or notification. Membership removal/full set replacement uses existing `UPDATE_ALL_UI_WIDGETS` reconciliation and preserves independently queryable visualization records.
- [x] Actual cached Retail/PTR manager/template execution acquires this consumer from supplied membership, projects through the real getter, sets `Text` from `text`, and applies `textureKit` to `Icon`/`Glow` using the cached `%s-icon`/`%s-glow` region policy. Exercise supplied updates and base ordering/layout through normal feeds; do not replace providers, getter, Setup, pools or vendor behavior. Texture-region application is not proof of asset availability or rendered pixels.
- [x] Actual cached consumers release hidden widgets and reacquire shown widgets, remove consumers after membership removal, and stop updates/clean pools and subscriptions on live unregister. Let cached deferred layout/removal finish before assertions. Ordinary updates retain the acquisition `widgetTag`; reacquisition uses the current supplied tag. Snapshot replacement still exposes every updated field. These are supplied-state lifecycle requirements, not native timing/animation parity.

## How it works

- [Manager state and feeds](../wiki/systems/ui-widget-manager-state.md)
- [Event dispatch](../event-system.md)

## Implementation inventory

Passive supplied-input plumbing and query projection compiled in the sealed normal PTR and Retail builds below. Combined supplied-record requirements are independently accepted at those saved execution boundaries; remaining limits are retained below:

- `src/c_api/ui_widget_manager/icon_text_and_background.rs` — shared numeric/secret selector boundary, cloned supplied record and complete fresh rooted Lua result.

- `src/c_api/ui_widget_manager/icon_text_and_background_record.rs` — complete explicit 14-field input record, without defaults or seeds.

- `src/c_api/ui_widget_manager.rs` — public supplied records and shared numeric widget identity.
- `src/c_api/ui_widget_manager/inputs.rs` — environment-owned supplied inputs.
- `src/c_api/ui_widget_manager/queries.rs` — registers the modeled getter using the existing required-number/secret boundary.
- `src/c_api/ui_widget_manager/feed.rs` — typed visualization feeds and synchronous state-before-event lifecycle.

## Tests asserting this spec

- `tests/ui_widget_icon_text_and_background_selector.rs` — auto-discovered by the internal integration test harness on Retail/PTR; two public-selector cases (missing; explicit nil/numeric string/boolean/table/function), fresh `WowLuaEnv` and existing `GetWidgetSetInfo` required-number control for each invocation. No record scaffold, mocks or provider replacement. Main-observed PTR baseline: compile exit0; two unique FAIL, exit101, after shared controls. Missing-selector and explicit-nil target calls succeed instead of rejecting; later non-number loop inputs are unreached. Receipt: `/home/osso/.local/state/wow-ui-sim/verification/wrath-source-current/iconbackground-selector-ptr-first-red-20261016T095402891303Z`. The newly compiled test source is `e1a2ce806`; actual normal-library basis is `161dad02a`, not a whole-e1 library. Independent report: `/home/osso/.local/state/wow-ui-sim/verification/iconbackground-next/selector-red-report.md`. Its inferred missing-source-wiring finding is rejected: the internal harness generates module references for top-level test files; whole-integration execution remains unproved. A successful target call fails rejection; an unrelated missing-function error fails the required-number diagnostic assertion. The test does not assert what a successful call returned.
- `tests/ui_widget_icon_text_and_background.rs` and `tests/widget_icon_background/` — eight authored cases: complete14-field fresh/replacement snapshots, distinct fractional IDs/removal/restoration, required selectors, independent environments, normal-feed ordering/atomicity, actual secret-wrapper access and unchanged cached type4 lifecycle. The consumer includes two-widget ordering and full-set replacement. Existing `widget_two_records/helpers.rs` is reused, not replaced. Main-observed normal PTR library `4adc7cf89`: build8m15s/730 JSON records/zero compiler diagnostics, guard exited normally. The new standalone component compiles at test checkout `15e53e813` against that library and executes0PASS/8FAIL, exit101: seven supplied-table failures and one required-selector failure. Consumer fails before cached setup; later snapshot/security/feed/lifecycle assertions remain unreached. Receipt: `/home/osso/.local/state/wow-ui-sim/verification/wrath-source-current/iconbackground-populated-ptr-red-20261016T102150270256Z/iconbackground-populated-eight-first-red`. Independent populated-RED reconciliation PASS: `/home/osso/.local/state/wow-ui-sim/verification/iconbackground-next/populated-red-report.md`; the suite remains FAIL, not acceptance. Source/spec/format/readability independently accepted separately at `/home/osso/.local/state/wow-ui-sim/verification/iconbackground-next/passive-tests-source-report.md`; not runtime acceptance.

## Bounded PTR producer proof — 2026-10-16

Normal-library source `2a422cb8639110f2668d8b7af51365086e73d9fb`; build/seal receipt `/home/osso/.local/state/wow-ui-sim/verification/widget-discrete-progress-current/iconbackground-green-ptr-20261016T103120943248Z`. Main observed successful terminal exit0, build-finished success, 731 JSON records, zero compiler diagnostics and normal pressure-guard exit. Library and normal wow-sim artifacts are separately sealed with emitted normal-profile association.

Test checkout `e156442f3` has no relevant production/test/Cargo change from that source. Component receipt `/home/osso/.local/state/wow-ui-sim/verification/wrath-source-current/iconbackground-ptr-green-20261016T105921359928Z/iconbackground-ten-first-green` uses unchanged committed fixtures, actual common helpers, all21 emitted PTR features and exact normal-target-profile dependency artifacts. Compile exit0 retains35 inherited unused-helper warnings; no warning suppression. Runtime exit0: **10 distinct cases PASS**, not the sum of nested parent/child summaries.

| Executed boundary | Unique result | Proof / limits |
| --- | --- | --- |
| Complete14-field fresh/replacement snapshots; distinct fractional IDs/removal/restoration; separate environments | 3 PASS | All concrete assertions reached |
| Required selectors; actual secret-wrapper secure/tainted access | 2 PASS | Real secret-wrapper case executed, not cfg inference |
| Normal-feed state-before-event; wrong-type/absent-set atomic rejection | 2 PASS | Synchronous event-time state and no-mutation controls |
| Unchanged cached type4 lifecycle, two-widget ordering/full-set replacement, hide/reacquire, membership removal/live unregister | 1 PASS | Requested atlas names, not asset availability or pixels |
| Separate original missing/non-number selectors | 2 PASS | Shared required-number controls and every loop input reached |

Separate normal PTR startup `iconbackground-ptr-startup` in the build receipt exited0, stdout `[]`, stderr final `Status: CLEAN`, zero unique/total collector errors. It used `--no-addons --no-saved-vars`, CASC disabled for assets and the actual PTR cached Lua/XML. A fresh private `XDG_DATA_HOME` held a byte-exact copy of the current original CVar input, distinct inode; original full stat/hash remained unchanged afterward. No CVar reset, original restore, cache sync or profile substitution.

Independent getter source/spec/readability and postgetter `cargo fmt --all -- --check` accepted separately at `/home/osso/.local/state/wow-ui-sim/verification/iconbackground-next/getter-source-report.md`; formatter exit0, empty streams. **Independent build/seal/full-stream runtime/startup reconciliation PASS:** `/home/osso/.local/state/wow-ui-sim/verification/iconbackground-next/ptr-green-runtime-report.md`. Full startup stderr was inspected separately from the empty collector; existing WTF EditMode input remained in use, so CVar-write isolation is not whole-machine hermeticity. Historical selector RED at normal-library `161dad02a` and populated RED at `4adc7cf89` remain retained, not overwritten or credited as current acceptance.

Separate default `cargo check --offline --locked --message-format=json -j1` at `e156442f3` exited0 in43.70s:736 valid JSON records, zero emitted compiler diagnostics, normal guard exit. Actual default/client-retail feature closure checked the library and six binaries; `.rmeta` outputs are not linked executables or Retail runtime proof. Relevant production/Cargo inputs equal getter `2a422cb86`. Independent receipt `/home/osso/.local/state/wow-ui-sim/verification/iconbackground-next/default-check-doc-report.md` accepts this check and the bounded documentation/CPU-scope evidence; no rerun.

## Bounded Retail producer proof — 2026-10-16

Normal-library/runtime source `84da38a3bb0efd09b6f6e23a775eea8844f971db`; getter source remains `2a422cb8639110f2668d8b7af51365086e73d9fb`. Build/seal receipt `/home/osso/.local/state/wow-ui-sim/verification/widget-discrete-progress-current/iconbackground-retail-green-20261016T111625602178Z`: normal default build exit0, 731 JSON records, zero compiler diagnostics, normal guard exit; library and normal wow-sim separately sealed. This is actual Retail compilation, not the earlier default `.rmeta` check or a PTR artifact.

Component receipt `/home/osso/.local/state/wow-ui-sim/verification/wrath-source-current/iconbackground-retail-green-20261016T112735462796Z/iconbackground-retail-ten-first`; test checkout `13423aae452b0523fe5c3d726e904358e3d3ba58` differs from normal-library source `84da38a3b` and getter `2a422cb86` only outside the relevant production/fixture scope. Unchanged fixtures and actual common helpers used all21 emitted default Retail features and matching normal-profile externs. Initial wgpu package-ID spelling failed before compiler launch; corrected selection compiled0 with35 inherited helper warnings, not a compiler retry. Actual runtime: **10 cases PASS on Retail, exit0**. The PTR matrix above applies separately to each profile:3 snapshot/identity/environment,2 selectors/security,2 feed/atomicity,1 cached lifecycle,2 original selectors. These are the same ten logical cases on each profile, not20 distinct logical cases or additive parent/child summaries. Standalone common-helper execution is not whole-integration execution.

Separate sealed normal Retail `iconbackground-retail-startup` in the build receipt exited0: stdout `[]`; entire stderr inspected, final `Status: CLEAN`, zero unique/total collector errors and no other observed error diagnostics. It used actual cached Retail Lua/XML, `--no-addons --no-saved-vars`, CASC disabled for assets and a fresh private `XDG_DATA_HOME` containing a byte-exact current original CVar copy at a distinct inode. Original recorded stat/hash remained unchanged. No reset/restore or profile substitution; existing read-only WTF input means this is not whole-machine hermeticity.

Independent Retail build/seal/full-stream runtime/startup reconciliation PASS: `/home/osso/.local/state/wow-ui-sim/verification/iconbackground-next/retail-green-runtime-report.md`. Together with the separate accepted PTR receipt, this completes only the supplied-record Retail/PTR requirements above. Existing formatter/default-check proofs and historical selector/populated REDs retain their own attribution. Different CPU allocations and profiles prevent a performance comparison; no speedup/regression inference.

Whole-integration execution, broader profiles and full-parent acceptance remain OPEN. No assets/pixels, native catalog/population/transport or parity, or activation of projected timer/model/animation effects is established.

## Known gaps (current cycle)

- [x] Independently reconcile the newly compiled two-case selector RED against normal PTR library `161dad02a`; retain later inputs as unreached, not tested. This closes baseline attribution only.
- [x] Independently reconcile compiled passive plumbing and the eight populated missing-getter failures; retain their reached boundaries and source attribution. This closes RED provenance only, not supplied-state behavior.
- [x] Implement this complete supplied-record query/feed slice with behavioral coverage of snapshots, selectors/security and cached lifecycle on Retail/PTR; retain exact source/build/runtime attribution separately.

## Out of scope

Native catalog/default records, native population/transport, demo seeds, DB2 inference and native/rendered parity: neither the declarations nor the supplied-state model establish them. No vendor edits, other record types, additional profiles, new secret/selector policy, animation/timer/model-effect execution or speculative behavior. Main owns source integration, builds and runtime evidence; this draft changes none of them.

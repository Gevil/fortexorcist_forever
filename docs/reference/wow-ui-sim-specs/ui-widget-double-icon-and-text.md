# Supplied DoubleIconAndText widgets

`C_UIWidgetManager.GetDoubleIconAndTextWidgetVisualizationInfo(widgetID)` must expose explicit supplied records and drive the unchanged cached Retail consumer. The [manager-state contract](ui-widget-manager-state.md) owns supplied state and lifecycle; the [manager architecture](../wiki/systems/ui-widget-manager-state.md) describes existing feeds. Getter `c3096cd6b` has bounded Retail producer acceptance at saved source `5dfa94330`: nine unique cases PASS, exit0; profile preservation, check/startup and full-parent gates remain open. At source `a56e11267`, the first public-selector regression reaches the required-number rejection failure after its existing-manager control passes: one unique case FAIL, exit101. Nested parent/child summaries are not two independent cases. Scaffold inventory alone is not behavioral acceptance.

## What it must do

- [x] Require a numeric `widgetID` through the existing manager required-number/secret policy. Missing/non-number selectors reject rather than returning nil; unknown numeric selectors return exactly one nil.
- [x] Return complete fresh snapshots of supplied `DoubleIconAndTextWidgetVisualizationInfo` fields and Lua types, without invented defaults. Caller mutation, replacement, removal, distinct IDs and environments remain isolated.
- [x] Existing normal feeds publish supplied state before notifications and reject wrong-type/absent-set updates atomically.
- [x] Actual cached type5 consumers activate/update label, left/right text and tooltips, and layout from supplied state; hidden transitions, membership removal and live unregister clean up. Preserve acquisition tags during ordinary updates and use the current tag on reacquisition.

The active Retail generated `UIWidgetManagerDocumentation.lua` declares the required number, nullable record and `AllowedWhenUntainted` secret policy. Its record fields are `shownState`, `label`, `leftText`, `leftTooltip`, `rightText`, `rightTooltip`, `tooltipLoc`, `widgetSizeSetting`, `textureKit`, `frameTextureKit`, `hasTimer`, `orderIndex`, `widgetTag`, `inAnimType`, `outAnimType`, `widgetScale`, `layoutDirection`, `modelSceneLayer`, and `scriptedAnimationEffectID`. The active cached `Blizzard_UIWidgetTemplateDoubleIconAndText.lua` is the consumer target; these declarations do not establish execution or native parity.

## How it works

- [Manager state and feed](../wiki/systems/ui-widget-manager-state.md)
- [Event dispatch](../event-system.md)

## Implementation inventory

- `src/c_api/ui_widget_manager/double_icon_and_text_record.rs`: complete explicit supplied record, without defaults or demo seeds.
- `src/c_api/ui_widget_manager/{inputs,feed}.rs`: environment-owned initially empty map and typed type5 host feed through existing membership/event ordering.
- `src/c_api/ui_widget_manager.rs`: public record export.

- `src/c_api/ui_widget_manager/double_icon_and_text.rs`: uses shared required-number/secret handling, clones the supplied record before Lua allocation, roots and fills a fresh result table, and returns exactly one nil for absent IDs.
- `src/c_api/ui_widget_manager/queries.rs`: registers the modeled getter.

The passive scaffold and fixtures compiled at source1571253e9; getter source `c3096cd6b` subsequently compiled and executed in the saved source `5dfa94330` Retail artifact below. Source inspection shows all 19 explicit fields (10 numbers, eight strings, one boolean), shared `read_numeric_id`, record cloning before allocation, and a rooted fresh Lua result; this is not behavioral acceptance. No default records, demo seeds or vendor modifications are introduced.

## Tests asserting this spec

- `tests/ui_widget_double_icon_selector.rs`: first public missing-selector counterexample, with existing required-number behavior as its control. Executed at sourcea56: one unique FAIL/exit101 at “missing widgetID must reject, not return nil”; the failed assertion establishes successful target call, not independently its returned value. Environment/control setup passed; later target error-message assertions were unreached. Independent saved audit: `/home/osso/.local/state/wow-ui-sim/verification/doubleicon-selector-next/runtime-red-report.md`. No passive scaffold dependency or populated/lifecycle proof.

- `tests/ui_widget_double_icon_and_text.rs` and `tests/widget_double_icon/`: nine supplied-result cases executed at source1571253e9: **1 unknown-ID control PASS / 8 FAIL, exit101**. Seven failures reach supplied-table assertions (including the cached case before consumer setup); one reaches invalid-selector acceptance. Nested timeout parent/child summaries are the same nine identities, not eighteen. Later projection, tainted denial/recovery and cached lifecycle phases remain unreached. This historical RED is superseded only for the bounded producer criteria below. Authored assertions target complete fields/freshness/replacement (including distinct in/out animation values), numeric selectors and actual secret wrappers, distinct IDs/removal/restoration, environments, normal-feed state-before-event/rejection atomicity, and unchanged cached activation/update/Hidden/reacquisition/membership removal/live unregister. Feed callback failures are retained and asserted outside handlers. Saved private baseline `/home/osso/.local/state/wow-ui-sim/verification/widget-discrete-progress-current/doubleicon-populated-retail-red-20261015T214331907251Z/doubleicon-populated-first-red` owns source1571253e9 execution; getter source `c3096cd6b` follows these reached failures. Independent saved-runtime reconciliation at `/home/osso/.local/state/wow-ui-sim/verification/doubleicon-populated-next/runtime-red-report.md` confirms all nine unique identities, full streams and build/seal receipts; the cached case failed before consumer loading, so cached lifecycle was not reached.

## Bounded Retail producer acceptance — 2026-10-15

Saved source `5dfa94330e411efda0d23ad4fcb946b3759f602f` executes **nine unique cases PASS, exit0**, 27.55s. Parent/replayed child appearances are nonadditive. Independent report `/home/osso/.local/state/wow-ui-sim/verification/doubleicon-populated-next/producer-runtime-report.md` confirms the successful no-run build, emitted-artifact seal association, full runtime streams and exact identities; no rerun is needed for this receipt.

| Accepted criterion | Executed boundary |
|---|---|
| Complete supplied query | Exact 19 fields/types/values, independent in/out animation values, fresh tables, retained snapshots, all-field replacement, distinct fractional IDs, removal/restoration and two environments |
| Required selectors/security | Missing/invalid selectors reject; absent numeric ID returns exactly one nil; actual secret NUMBER wrappers allow secure access, deny tainted access, recover securely and preserve state |
| Normal feed | Complete state visible before synchronous callbacks; wrong type/missing set rejects without state/event mutation |
| Unchanged cached type5 consumer | Activation/update, hidden release, shown reacquisition, membership removal, live unregister and later inactive feed; acquisition tag retained on update and refreshed on reacquisition; actual text/tooltips/layout and pool/subscription cleanup |

These checkboxes accept only this supplied-state Retail matrix. Selected streams contain startup timings but no emitted warnings/errors; they are not a complete ordinary startup baseline. No profile-preservation, format/check, native/render/asset/timer/model/animation-execution or full-parent acceptance follows. Historical REDs retain their original source boundaries; this proof does not cover C3 or unrelated current-HEAD changes.

## Bounded PTR preservation — 2026-10-16

Saved source `161dad02ad868ecce067b4b0c1d87108ec5b2dcb`: **nine unique PASS, exit0**, including actual secret selectors and cached PTR type5 activation/update/removal/unregister. The standalone component imports unchanged real common helpers over the sealed normal PTR library; nested timeout-child output is nonadditive. Independent report: `/home/osso/.local/state/wow-ui-sim/verification/ptr-doubleicon-next/report.md`. Library build7m50s/730 JSON records/zero compiler diagnostics; component compile retains35 unused common-helper warnings. Formatter passes separately at `e1a2ce806`; default library check is reused only through proven production/Cargo equality with `dc2530c3c`. Existing Retail9 is unchanged, not replayed. No whole-integration, ordinary-startup, shared-control, native/rendered, all-profile or full-parent acceptance.

## Known gaps (current cycle)

- [x] Execute the public selector regression and independently distinguish its reached rejection-contract failure from compilation/setup failure; retained as RED, not acceptance.
- [x] Integrate explicit record/map/feed scaffold and source-audited populated query/secret/isolation/cached-lifecycle fixtures, correcting swallowed callback failures and ambiguous animation-field values. Source review is not compilation or behavior proof.
- [x] Compile and execute the nine supplied-result cases before the getter: source1571253e9 baseline reaches 1 control PASS /8 contract FAIL, exit101; not acceptance. Independent reconciliation is separate.
- [x] Compile/execute the modeled getter against the nine supplied-result cases at saved source `5dfa94330`; independent saved build/seal/runtime reconciliation PASS.
- [ ] Verify remaining profile preservation, format/check and ordinary startup gates. Full-parent acceptance remains separate.

## Out of scope

Native catalogs/defaults, demo seeds, DB2 inference, vendor patches, mocked providers/Setup/pools, rendered/native parity and cross-profile acceptance. Synthetic fixture inputs must be explicit supplied values, not claimed native metadata. No asset-application or pixel proof follows from text/layout assertions.

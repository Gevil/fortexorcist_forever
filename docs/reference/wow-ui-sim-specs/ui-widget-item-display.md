# Supplied ItemDisplay widgets

`C_UIWidgetManager.GetItemDisplayVisualizationInfo` exposes explicit supplied ItemDisplay records through the existing manager subsystem. Complete records, empty environment-owned storage, typed feeds and a fresh nested getter projection are present in `src/c_api/ui_widget_manager/`. The passive library's populated fixtures reached behavioral RED before getter implementation; [bounded combined Retail/PTR acceptance](#bounded-combined-retailptr-acceptance--2026-10-16) now covers the getter and completed synchronous cached consumer in each profile. See [manager state and feeds](../wiki/systems/ui-widget-manager-state.md) for the existing model.

## What it must do

- [x] Support the public getter in Retail and PTR, grounded in each profile's actual cached `Blizzard_APIDocumentationGenerated/UIWidgetManagerDocumentation.lua`: required numeric `widgetID`, nullable `ItemDisplayVisualizationInfo`, and `SecretArguments = "AllowedWhenUntainted"`. Preserve the existing manager secret policy; secret-wrapper behavior requires separate proof.
- [x] Reject missing, explicit nil, string (including numeric string), boolean, table and function selectors at the shared required-number boundary. Diagnostics contain `must be a number` and identify `GetItemDisplayVisualizationInfo`; the existing `GetWidgetSetInfo` rejection is the control.
- [x] Return exactly one nil for absent numeric `widgetID` `934207.5`. Do not infer catalog membership or introduce integer, positivity or range restrictions.

### Populated supplied-state scope — bounded Retail/PTR accepted

- [x] Project exactly the 15 outer and 16 nested declaration rows below; represent the four optional fields as Some/value or None/nil. Preserve Some empty strings and numeric zero; never synthesize item metadata into the manager record.
- [x] Return fresh public outer/nested snapshots; isolate caller mutations, retained snapshots, all-field replacements, fractional IDs, environments, removal and restoration.
- [x] Publish complete typed type27 state and membership before synchronous manager events; reject mismatched type/missing set without changing state or emitting events.
- [x] Apply the existing manager policy to actual permitted/denied secret wrappers, preserving wrappers, taint and state. No new policy.
- [x] Reach unchanged cached type27 ItemDisplay and XML BaseItem through normal feed with existing synchronous item metadata/load: completed update, supplied stack-count display and nil-count hiding through the cached default-one branch, nil optional text, hide/reacquire, membership/full-set removal, live unregister, child color-callback cleanup and later-feed inactivity. Check text/texture identity and completed parent/child sizing, not assets/pixels or pending/cancellation races. A populated getter assertion precedes every cached setup dependency.

Cached Retail and PTR `Blizzard_APIDocumentationGenerated/UIWidgetManagerDocumentation.lua` rows were inspected on 2026-10-16 and match field-for-field. This is a supplied-state contract, not a native/catalog/defaults claim. See [manager state](../wiki/systems/ui-widget-manager-state.md).

### ItemDisplayVisualizationInfo — complete projection

| Requirement | Field | Type | Nullable |
| --- | --- | --- | --- |
| [x] | `shownState` | `WidgetShownState` | false |
| [x] | `tooltipLoc` | `UIWidgetTooltipLocation` | false |
| [x] | `itemInfo` | `UIWidgetItemInfo` | false |
| [x] | `widgetSizeSetting` | `number` | false |
| [x] | `textureKit` | `textureKit` | false |
| [x] | `frameTextureKit` | `textureKit` | false |
| [x] | `hasTimer` | `bool` | false |
| [x] | `orderIndex` | `number` | false |
| [x] | `widgetTag` | `string` | false |
| [x] | `inAnimType` | `WidgetAnimationType` | false |
| [x] | `outAnimType` | `WidgetAnimationType` | false |
| [x] | `widgetScale` | `UIWidgetScale` | false |
| [x] | `layoutDirection` | `UIWidgetLayoutDirection` | false |
| [x] | `modelSceneLayer` | `UIWidgetModelSceneLayer` | false |
| [x] | `scriptedAnimationEffectID` | `number` | false |

### UIWidgetItemInfo — complete projection

| Requirement | Field | Type | Nullable |
| --- | --- | --- | --- |
| [x] | `itemID` | `number` | false |
| [x] | `stackCount` | `number` | true |
| [x] | `overrideItemName` | `string` | true |
| [x] | `infoText` | `string` | true |
| [x] | `overrideTooltip` | `string` | true |
| [x] | `textDisplayStyle` | `ItemDisplayTextDisplayStyle` | false |
| [x] | `tooltipEnabled` | `bool` | false |
| [x] | `iconSizeType` | `WidgetIconSizeType` | false |
| [x] | `infoTextEnabledState` | `WidgetEnabledState` | false |
| [x] | `showAsEarned` | `bool` | false |
| [x] | `itemNameTextFontType` | `UIWidgetFontType` | false |
| [x] | `itemNameTextSizeType` | `UIWidgetTextSizeType` | false |
| [x] | `infoTextFontType` | `UIWidgetFontType` | false |
| [x] | `infoTextSizeType` | `UIWidgetTextSizeType` | false |
| [x] | `itemNameCustomColor` | `WidgetEnabledState` | false |
| [x] | `itemNameCustomColorOverrideState` | `UIWidgetOverrideState` | false |

## How it works

- [Manager state and feeds](../wiki/systems/ui-widget-manager-state.md)

## Implementation inventory

Getter production source `64a5576b1` has [accepted bounded Retail/PTR execution](#bounded-combined-retailptr-acceptance--2026-10-16) at saved normal Retail source `bbeac6213` and actual PTR source `70f4c465a`. Namespace registration is unconditional, matching neighboring getters; selector handling reuses `read_numeric_id` without a new policy.

- `src/c_api/ui_widget_manager/queries.rs` — shared required-number/secret selector and modeled ItemDisplay getter registration.
- `src/c_api/ui_widget_manager/item_display.rs` — fresh rooted outer/nested snapshots, complete15+16 projection, omitted None fields and one-nil absence; no defaults or new selector policy. Bounded Retail/PTR getter execution is accepted at the separately attributed saved sources below.
- `src/c_api/ui_widget_manager/inputs.rs` — empty per-environment `item_display` map; no seeded records.
- `src/c_api/ui_widget_manager/feed.rs` — `WidgetVisualization::ItemDisplay`, type27 and supplied storage arm; existing feed validation and notification ordering unchanged.

- `src/c_api/ui_widget_manager/item_display_record.rs` — complete15-field `ItemDisplayRecord` and16-field `UiWidgetItemRecord`; four nullable fields use `Option`, no defaults.
- `src/c_api/ui_widget_manager.rs` — getter/record modules and public exports. Passive normal library source `3eab91eeb` compiled before populated RED; getter source is a later change with separately accepted bounded Retail execution.

## Tests asserting this spec

- `tests/ui_widget_item_display.rs` plus `tests/widget_item_display/{queries,feed,security,consumer}.rs` — eight logical cases reached the populated nil/non-table RED boundary against passive normal Retail source `3eab91eeb`. The unchanged eight populated cases and two original selector cases later PASS in each profile under the bounded combined receipt below; historical RED boundaries remain unchanged.

- `tests/ui_widget_item_display_selector.rs` — two public-selector regressions at test source `f67005a12a07661592c6a4f5615015102db5b9f3`; fresh `WowLuaEnv` instances, no mock registration, supplied records or cached UI load.

### Historical Retail selector RED — 2026-10-16

Saved runtime epoch: `/home/osso/.local/state/wow-ui-sim/verification/wrath-source-current/item-display-selector-retail-red-20261016T135057967011Z`. Component compile exits0 with no Rust diagnostics; tests link separately sealed normal Retail library `7273875b2d35ae305428661b2650116e802733e5`, not a whole-f670 build.

Exactly two tests run: **0 PASS / 2 FAIL / exit101**. Missing-input and explicit-nil cases each pass the shared `GetWidgetSetInfo` required-number control, public getter function check and absent numeric `934207.5` exactly-one-nil assertions. Each fails `ItemDisplay invalid widgetID must reject`: the invalid target call succeeds. Target diagnostics and later string, numeric-string, boolean, table and function iterations are **UNREACHED**.

Independent full-stream/source/feature/seal/CVar/readability RED reconciliation: `/home/osso/.local/state/wow-ui-sim/verification/item-widget-next/selector-red-report.md`. Child-only current-CVar copy and paired original stat/hash are unchanged at their observed boundaries. No reset/restore or historical preservation claim. This confirms bounded RED, not selector acceptance; PTR, secret wrappers, populated projection, cached consumers, native parity and parent acceptance remain unproved.

### Populated Retail RED before getter — 2026-10-16

Normal Retail `--lib` build source `3eab91eebdbe588f579f45d7bfe64ad950459526` (passive production `417f1badd`) finished successfully with730 Cargo JSON records and zero compiler-message records; pressure guard exited before sealing. Library epoch: `/home/osso/.local/state/wow-ui-sim/verification/widget-discrete-progress-current/item-widget-passive-retail-library-retry1-20261016T151704000183Z`.

Component epoch `/home/osso/.local/state/wow-ui-sim/verification/wrath-source-current/item-display-populated-retail-red-20261016T152638018148Z` snapshots the committed test/common inputs separately. Matching emitted Retail cfg and normal-profile externs compile successfully with38 inherited helper warnings. Runtime reaches **0 PASS / 8 unique FAIL / exit101** at `populated ItemDisplay getter returned nil/non-table`; parent/timeout-child prints are nonadditive. Cached consumer fails its populated precondition before vendor loading. Complete field values, nullable transitions, feed rejection/state preservation, later secret-policy controls and cached lifecycle assertions remain **UNREACHED**, not accepted.

Fresh child-only current-CVar copy and paired original stat/hash remain unchanged. No reset/restore, native/catalog/assets/pixels, PTR or whole-integration claim. Independent saved-evidence reconciliation: `/home/osso/.local/state/wow-ui-sim/verification/item-widget-next/populated-red-report.md` accepts eight unique behavioral failures at the one-return non-table boundary, source snapshots, seals, emitted cfg/externs and paired CVar guards. The diagnostic does not distinguish nil from another non-table scalar. New getter execution remains separate.

## Bounded Retail acceptance — 2026-10-16

**ACCEPTED: bounded Retail.** Later actual PTR acceptance and combined scope are recorded below; this receipt retains its Retail attribution. Independent saved-evidence receipt: `/home/osso/.local/state/wow-ui-sim/verification/item-widget-next/retail-green-report.md`. Normal Retail library/binary source `bbeac62133cfbf678faf3eca07eab27f6b9bcec8` includes production getter `64a5576b1fa7b8f21bcbade605a0058ba8366d88`; production inputs between those revisions are unchanged. Build exit0, 7m32s, 731 Cargo JSON records, zero compiler-message diagnostics; terminal pressure guard exited and library/binary seals reconciled. Separate component compile exit0 retains 38 inherited helper warnings. All 33 immutable fixture/common snapshots match committed `bbeac6213` test bytes, unchanged from `3eab91eeb`.

Ten unique tests PASS/exit0: eight unchanged populated cases plus two original selector regressions; timeout-child replays are nonadditive. Reached complete 15+16 projection, fresh/deep retained snapshots, four nullable fields including Some(0)/empty strings, replacement/fractional/environment/removal isolation, synchronous publication and rejection atomicity, and actual permitted/denied secret wrappers with taint/state preservation. Actual cached type27/XML BaseItem completes synchronous item loading: supplied counts17/23, nil optional text/count hiding, live identity/update, hide/reacquire, membership/full-set removal, live unregister, color-callback cleanup and later-feed inactivity. Text/texture identity and completed sizing are accepted, not assets or pixels. Historical selector RED and eight-populated RED above remain retained, not reclassified.

Separate sealed normal Retail startup PASS/exit0: stdout `[]\n`, final `Status: CLEAN`, zero Lua errors. Both runs use distinct fresh child-only `XDG_DATA_HOME` byte-exact copies of the then-current persisted CVar file; paired original stat/hash unchanged, no reset/restore. Startup child later differs only in serialization, not parsed values. Both runs disable CASC/sound; startup disables third-party addons/SavedVariables. This is not full integration or all-assets/all-addons proof.

Source/schema/readability audit separately PASS; it does not establish current type-check or whole-project formatter acceptance. The earlier PTR admission-only checkpoint is historical; actual PTR and combined bounded acceptance follow. No native/catalog, assets/fonts/pixels, alternate text-style, asynchronous pending-load/cancellation, projected animation/effect/timer activation, whole-integration or parent-goal acceptance follows.

## Bounded actual PTR acceptance — 2026-10-16

**ACCEPTED: bounded actual PTR**, independently supported by `/home/osso/.local/state/wow-ui-sim/verification/item-widget-next/ptr-green-report.md`, not inferred from Retail. Actual normal library/binary and component source `70f4c465ae7f0ef9acf0c8cae6a19c23f9410ee8`; production getter basis `64a5576b1fa7b8f21bcbade605a0058ba8366d88`, with production inputs unchanged. Build root `/home/osso/.local/state/wow-ui-sim/verification/widget-discrete-progress-current/item-widget-getter-ptr-green-20261016T160210613848Z`; component root `/home/osso/.local/state/wow-ui-sim/verification/wrath-source-current/item-display-ptr-green-component-20261016T161240645141Z`.

Normal PTR build completed exit0 in 6m28s: 731 Cargo records, zero compiler-message diagnostics; terminal observation, emitted profile.test=false linkage and three artifact seals independently reconciled. Component compile exit0 with 38 inherited helper warnings, not warnings-free. All 33 immutable copied inputs match committed `3eab91eeb` and `70f4c465a`; emitted cfgs select client-ptr/retail-12-1-5, not renamed Retail. Ten unique PASS/exit0 (8 populated +2 selectors); 18 raw name appearances include eight timeout-child replays, not extra cases. Actual profile-cached type27/XML BaseItem consumer executed unchanged.

Separate sealed normal PTR startup exit0: stdout `[]\n`, final `Status: CLEAN`, zero Lua errors; 283 Blizzard addons, third-party addons/SavedVariables disabled. Component and startup each use a distinct fresh child-only XDG_DATA_HOME initialized with a byte-exact copy of CURRENT persisted CVars; full paired original stat/hash unchanged, no reset/restore. Original 790-byte SHA-256 `3704e092febe9a79363a3d83f31c6b2e89c8cea1165b212c6a0fafaf2a22e4a0`; startup child later changes serialization only, parsed values unchanged; no child-byte-preservation claim. Both executions disable CASC/sound. These are separate startup and selected-runtime claims, not full integration.

## Bounded combined Retail/PTR acceptance — 2026-10-16

**The same ten logical cases PASS in each profile, not twenty distinct behaviors.** Main independently reconciled the full [Retail receipt](#bounded-retail-acceptance--2026-10-16); the full independent PTR report above is accepted separately. Normal Retail actual `bbeac62133cfbf678faf3eca07eab27f6b9bcec8` and normal PTR actual `70f4c465ae7f0ef9acf0c8cae6a19c23f9410ee8` share production basis `64a5576b1fa7b8f21bcbade605a0058ba8366d88`. Neither is a current-HEAD/type-check claim.

| Bounded requirement | Retail / actual PTR proof |
| --- | --- |
| Complete supplied projection | All 31 declaration rows checked: 15 outer + 16 nested; four nullable fields individually/all absent, Some(0)/empty strings retained; all-field replacement and independent in/out animation values projected. |
| Freshness and isolation | Fresh public outer/nested identities, caller-mutation isolation, retained snapshots, fractional IDs, independent environments, removal/one-nil absence and restoration reached. |
| Feed, rejection and secrets | Complete typed state/metadata/membership published before synchronous events; wrong-type/missing-set rejection atomic; actual host-secret wrappers permit secure and deny tainted callers before lookup, preserving wrappers, taint and state. Original two selector regressions PASS. |
| Actual cached completed lifecycle | Type27/XML BaseItem synchronous completed Hearthstone load; live frame/child/Icon identity and sizing, Count 17→23, nil-count hiding through cached default-one branch, nil optional text, hide/reacquire, membership/full-set release, live unregister, actual color-callback cleanup and later-feed inactivity reached. |
| Separate startup and preservation | Each profile has its own CLEAN sealed normal startup and separate component execution; each run has a fresh CURRENT child-CVar copy and paired unchanged original stat/hash. No reset/restore or all-addons/assets proof. |

Historical selector RED, populated-result RED and uncompiled source checkpoints remain historical, not current failures or acceptance. Live cache sources were inspected but not among the 33 immutable fixture inputs; no immutable historical vendor-byte authentication follows.

Independent saved sourcegate accepted: `/home/osso/.local/state/wow-ui-sim/verification/item-widget-next/default-check-format-report.md`. Default Retail Cargo check at recorded source `70f4c465a` completed successfully (736 JSON records, zero compiler-message records); separate whole-workspace `cargo fmt --all -- --check` exited0 with empty streams. Independent source/config comparisons and all 4,279 format-manifest entries (4,278 Rust files plus root Cargo.toml) match the audited filesystem at HEAD `3faaab8a9`, covering getter `64a5576b1`. This is saved source check/format acceptance, not a PTR type-check, all-profile or broader final-gate claim. No native/catalog/assets/fonts/pixels, alternate text-style activation, uncached async/pending load/cancellation race, projected animation/effect/timer activation, other-profile, whole-integration or parent-completion claim.

## Known gaps (current cycle)

- [x] Establish bounded selector acceptance under Retail/PTR: same two selector cases PASS in each profile; historical Retail RED retained.
- [x] Implement the modeled ItemDisplay getter/projection after populated behavioral RED: source `64a5576b1`; bounded Retail/PTR execution accepted separately above.
- [x] Compile and execute the populated fixtures separately against the passive normal Retail library: eight unique behavioral failures before getter implementation.
- [x] Complete bounded dual-profile getter and later-assertion acceptance: 31 fields, nullable/freshness/isolation/feed/rejection/actual secrets and completed synchronous cached-consumer assertions accepted above.
- [x] Independently accept saved whole-workspace formatting and default Retail Cargo check covering getter `64a5576b1`, with source/config and format-manifest equality to audited HEAD `3faaab8a9`; no PTR/all-profile type-check, broader final-gate or parent closure.

## Out of scope

Native parity/catalog/assets/pixels, other profiles, new selector restrictions/policy, new item providers, asynchronous pending loads/cancellation races, WorldQuestReward embedded-tooltip behavior, animation/timer/effect activation and broader parent acceptance remain outside this slice. Only the existing synchronous completed item-load model is included; no vendor behavior may be replaced.

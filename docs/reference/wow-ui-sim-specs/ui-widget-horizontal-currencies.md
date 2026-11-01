# HorizontalCurrencies supplied state

Private supplied-state contract for `src/c_api/ui_widget_manager/`; architecture
owner: [manager state](../wiki/systems/ui-widget-manager-state.md).
2026-10-16. Supplied-state behavior verified on Retail and PTR against sealed
normal libraries; no startup, native or pixel acceptance.
This expands the selector-only preparation without rewriting historical evidence.

## What it must do

- [x] Accept explicit complete supplied records only; fresh environments start
  with an empty map. Reuse existing `UiWidgetCurrencyRecord`, not a second row type.
- [x] Public `GetHorizontalCurrenciesWidgetVisualizationInfo(widgetID)` requires
  a number and returns exactly one nullable record. A populated record returns a
  table containing all 15 outer fields and every ordered 10-field currency row.
  Missing required input and invalid types are separate controls. Diagnostic
  wording follows existing simulator required-number behavior, not native proof.
- [x] Each query returns fresh outer/array/row tables. Caller edits, row insertion,
  deletion, whole replacement, later host updates and record removal do not mutate
  retained snapshots. Fractional keys remain distinct; environments stay isolated.
- [x] Empty currencies are a fresh empty table, not omitted/nil. Restore ordered
  rows without filling an older empty snapshot. No invented widget-ID range policy.
- [x] `SecretArguments = "AllowedWhenUntainted"`: test actual wrapped present/absent
  numbers securely, deny both under tainted callers before lookup, preserve wrappers,
  caller taint and host state, then recover securely. Security case is compiled only
  when the repository's `retail-12-1-0` feature exposes the existing test helpers.
- [x] Type9 feed publishes complete membership and record before synchronous
  `UPDATE_UI_WIDGET`; invalid visualization type or missing set changes neither
  records/membership nor events. Removing membership retains independent records.
- [x] Actual cached Retail/PTR HorizontalCurrencies Lua/XML, loaded through the
  existing addon closure and unmodified manager provider, consumes normal feeds.
  Cover activation, in-place reordered row update, empty rows, both cached width
  branches, sorting, full-set replacement, Hidden release, Shown reacquisition,
  membership removal, unregister while live, nested pool/subscription cleanup and
  non-reactivation after unregister. Assert fields/anchors/requested texture IDs,
  not rendered pixels or asset availability.

`HorizontalCurrenciesWidgetVisualizationInfo`:

| Requirement | Field | Declared type | Nilable |
| --- | --- | --- | --- |
| [x] | `shownState` | `WidgetShownState` | false |
| [x] | `currencies` | `table`, InnerType `UIWidgetCurrencyInfo` | false |
| [x] | `tooltipLoc` | `UIWidgetTooltipLocation` | false |
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

Ordered `UIWidgetCurrencyInfo` rows:

| Requirement | Field | Declared type | Nilable |
| --- | --- | --- | --- |
| [x] | `iconFileID` | `fileID` | false |
| [x] | `leadingText` | `string` | false |
| [x] | `text` | `string` | false |
| [x] | `tooltip` | `string` | false |
| [x] | `isCurrencyMaxed` | `bool` | false |
| [x] | `textFontType` | `UIWidgetFontType` | false |
| [x] | `textSizeType` | `UIWidgetTextSizeType` | false |
| [x] | `textEnabledState` | `WidgetEnabledState` | false |
| [x] | `iconSizeType` | `WidgetIconSizeType` | false |
| [x] | `updateAnimType` | `UIWidgetUpdateAnimType` | false |

## How it works

- [Manager state](../wiki/systems/ui-widget-manager-state.md).
- Public cached sources, independently inspected in both
  `~/.cache/wow-ui-sim/blizzard-ui/{retail,ptr}/AddOns/`:
  `Blizzard_APIDocumentationGenerated/UIWidgetManagerDocumentation.lua:170–181`
  (selector/security/return), `:1488–1507` (15 outer fields), `:2044–2057`
  (10 row fields); `UIWidgetManagerSharedDocumentation.lua:144` (type9).
- `Blizzard_UIWidgets/Blizzard_UIWidgetTemplateHorizontalCurrencies.lua:1–8`
  calls the public getter, filters Hidden and registers the real template;
  `:12–44` acquires ordered pooled rows, uses Yellow text and Red/White tooltips,
  anchors the first row to the widget and later rows with a 10-unit gap;
  `:47–53` determines dimensions, `:56–63` creates/resets the nested pool.
  The actual XML `Blizzard_UIWidgetTemplateHorizontalCurrencies.xml:3–5`
  declares the virtual template. Shared `Blizzard_UIWidgetTemplateBase.lua:325–403`
  consumes all row text, tooltip, icon, font/size and animation inputs.
- Fresh snapshot, exact supplied identity, feed atomicity and isolation are
  simulator contracts, not behavior inferred from native execution. Cached
  consumers ground the public integration assertions; metadata grounds fields.

## Implementation inventory

Implemented on branch `horizcurr` (not merged into canonical):

- `src/c_api/ui_widget_manager/horizontal_currencies_record.rs`: complete 15-field
  input, reusing existing `UiWidgetCurrencyRecord`.
- `src/c_api/ui_widget_manager.rs`: passive module declaration and public export.
- `src/c_api/ui_widget_manager/inputs.rs`: empty environment-owned record map.
- `src/c_api/ui_widget_manager/feed.rs`: variant, type9 validation and supply arm.

Patch `00-tests.patch` contains only this passive wiring and tests. Existing
missing-member namespace behavior returns nil, so populated tests must fail at
the table boundary. Patch `10-producer.patch` replaces that missing behavior with
explicit getter registration and complete fresh projection; adopted after
recording the populated behavioral RED.

## Tests asserting this spec

`tests/ui_widget_horizontal_currencies_passive.rs`: host-only storage/feed controls.
`tests/ui_widget_horizontal_currencies_selector.rs`: missing/type selector controls.
`tests/ui_widget_horizontal_currencies.rs` and `tests/widget_horizontal_currencies/`:
full query, feed, gated security and cached lifecycle assertions.

13 Rust test functions with security feature enabled (12 without). Two passive,
two selector, five query, two feed, one feature-gated security, one composite cached
lifecycle. Helpers/loops/profiles are not extra independent cases.

| Scope | Retail | PTR |
| --- | --- | --- |
| HorizontalCurrencies query/feed/security/cached lifecycle | 9/9 pass | 9/9 pass |
| Passive host controls | 2/2 pass | 2/2 pass |
| Required-number selectors | 2/2 pass | 2/2 pass |
| IconTextAndCurrencies preservation | 11/11 pass | 11/11 pass |
| ItemDisplay preservation | 10/10 pass | 10/10 pass |

Retail tests-first execution observed nine populated-table assertion failures and
two invalid-selector rejection assertion failures. One passive control passed;
the other incorrectly required removal of unrelated default sets. The approved
test-only correction preserves the exact original set map and explicitly checks
that supplied set 449 disappears. A deliberate copied-test no-op-removal
counterexample failed that absence assertion. No setup/nil-call/compile failure
was counted as populated RED.

Production revisions: passive `b7c4d1e11`, producer `b6bd754b8`.
Corrected test revision: `3978e49af`. Retail GREEN used the producer library;
PTR used the corrected-test revision with identical production inputs.
Private build/component manifests, seals, source snapshots, per-group results and
CVar stat/hash checks live under
`~/.local/state/wow-ui-sim/handoff/horizcurr-execution/`.
The reused runner's generic scope label mentions quest/charge; actual module
manifests and executed names establish this widget-only coverage.

## Known gaps (current cycle)

- [x] Branch adoption, changed-file formatting, normal-library builds and populated
  assertion RED followed by Retail/PTR GREEN and widget preservation.
- [ ] Canonical integration and broader parent acceptance, including startup;
  not part of this isolated slice.

## Out of scope

Native/catalog/default/domain inference; reconstructed sources; vendor mutation;
new currency schema; async/timer/fade/effect activation or pixel/asset acceptance;
all-profile/full-suite/parent-goal completion. Timer/fade/effect/update-animation
values occur only in projection/feed tests without a cached consumer.

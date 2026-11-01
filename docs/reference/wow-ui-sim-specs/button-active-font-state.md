# Button active font state

Button text selects a configured FontObject and projects its supplied fields into the existing FontString. This clean-room requirement comes from the user's functional description; historical source comparison is not executed native or universal modern-profile proof. See [widget system](../widget-system.md).

## What it must do

- [ ] Select disabled font while disabled; otherwise select highlight font while hovered or highlight-locked; otherwise select normal font. Pushed state does not suppress highlight-font selection.
- [ ] Refresh selection on enabled/state, hover/lock and active-slot changes. Updating an inactive slot must not overwrite the active style.
- [ ] Preserve the existing FontString identity and update its selected FontObject reference plus supplied font path, size, flags and color fields. Its emitted glyphs must reflect that style.
- [ ] Apply pushed text offset independently of selected font, including pushed plus active highlight.
- [ ] Preserve text, parent, anchors, draw layer and explicit texture ownership. Text selection must not reuse a texture-visibility predicate that suppresses pressed highlight.

## How it works

- [Widget system](../widget-system.md)
- [Existing locked highlight texture contract](button-locked-highlight-rendering.md)
- [FontString spacing and snapshot boundary](fontstring-spacing.md)

## Implementation inventory

- `src/lua_api/frame/methods/button_anchor_hierarchy/buttons.rs`: font slots and button font projection; C7 producer committed in `3b4dc7c99`. Current saved execution and historical failures are separated below.
- `src/lua_api/frame/methods/button_anchor_hierarchy/font_strings.rs`: existing FontString reference and snapshot helpers.
- `src/lua_api/frame/methods/text_attribute_event/text/formatting.rs`: public FontString FontObject reference/snapshot behavior.
- `src/iced_app/mouse.rs`: actual GUI hover transition; `A_Admin.SetMouseOverFrame` supplies separate simulated hover.

[Bounded PTR C7 execution](../baselines/README.md#ptr-shared-controls--2026-10-16) covers bare font-slot/state/ownership fixtures, not physical pointer input or all button controls.

## Tests asserting this spec

Saved Retail-epoch baseline `d16876fcc9ec0e49851436a6af7a1e308d0a344c` executed all three C7 cases in `tests/button_state_textures.rs`: **0 passed, 3 failed, exit 101**. The private saved epoch is `c8-producer-c7-c9-retail-baseline-20261016T003140348455Z`, selection `button-font-first-red`. The first two cases stop at unlabelled `C7Check` assertions; active-slot replacement stops at the explicit `selected FontObject reference` assertion. The fixture also incorrectly assumes mapped `GetTexture()` sources return path strings rather than numeric file IDs, so the first two failures do not establish a font-style defect. Later assertions do not independently establish RED or acceptance.

Two style cases omit initial reference assertions so a reference-storage failure cannot mask the style boundary. The authored tests compare emitted glyph quads with a separately rendered FontString and observe the selected path through public `GetFont`; the failing baseline does not prove those assertions pass. Saved producer source `792d62003` executes the full twelve-case module: nine controls pass and all three C7 cases still stop at unlabelled `C7Check` assertions. The reference-first case now reaches that helper, but no full C7 GREEN follows. The corrected oracle captures each assigned texture source before font changes and checks unchanged source/path with labelled assertions; font fields and glyph checks remain unchanged. Those earlier helper/oracle failures remain historical; current corrected-oracle execution follows. Modern native, all-profile, GPU/pixel behavior and loaded-face identity remain unproven.

## Saved Retail execution — 2026-10-15

Saved `3a530` corrected `button_state_textures`: 12 PASS/0 FAIL, comprising three C7 cases and nine controls. Independent bounded saved-runtime validation COMPLETE; all selected assertions reached, streams and sealed-artifact association reconciled. [EditBox receipt](editbox-text-position-selection.md#saved-retail-execution--2026-10-15) owns shared terminal compile/build-seal evidence, stderr caveats and remaining gates; no clean-startup or all-profile claim.

## Saved Wrath setup boundary

Saved `39d38` button module: **1 PASS, 11 SETUP FAIL**, including all three C7 cases, from missing Wrath `Blizzard_SharedXMLBase` TOC. Not font-behavior RED and not C7 acceptance. [Shared Wrath receipt](editbox-text-position-selection.md#saved-bounded-wrath-checkpoint) owns pending runtime audit5795 and build/hash qualifications; earlier Retail proof remains separate.

## Known gaps (current cycle)

- [x] Independently validate the corrected saved bounded projection and affected rendering/state controls. Historical three-case oracle RED remains separate; this is not native, GPU or all-profile acceptance.
- [ ] Cover actual GUI pointer/hit-test/dispatch; authored tests use public simulated hover, not manual OnEnter callbacks.

The three C7 fixtures construct their own fonts, Button, FontStrings and textures through public APIs; they do not consume a Blizzard template. Their bootstrap now uses a bare environment, removing the irrelevant modern SharedXML-cache prerequisite without changing assertions. Saved source `0184775b5db228e4136f1c29ffaba3b90f84725d` now executes exactly these three bare C7 cases: **3 PASS, exit0**, no Lua errors in C7 stderr. [Shared saved receipt](editbox-text-position-selection.md#saved-wrath-byte-limit-and-bare-font-execution--source0184775) owns all 46 distinct tests, independent build/seal/runtime reports, retained UnitRole warning and diagnostic/provenance limits. Earlier `39d38` missing-cache setup failures remain historical; the other texture controls retain their cache requirements and are not rerun here. No genuine Wrath consumer, native/all-profile/current-HEAD proof or guard retirement.

## Bounded Mists execution — 2026-10-16

[Shared Mists owner matrix](../baselines/README.md#mists-shared-controls--2026-10-16) owns independently accepted saved results, provenance, diagnostics and remaining profile limits. Bare font comparisons use system fallback, not native font/pixel proof.

[Bounded Era execution](../baselines/README.md#era-shared-controls--2026-10-16) separately accepts the corresponding matrix cases from saved artifacts only; current source and broader criteria remain unaccepted.

[Bounded Anniversary execution](../baselines/README.md#anniversary-shared-controls--2026-10-16) separately accepts the same corresponding matrix cases from saved Anniversary artifacts only; current source and broader criteria remain unaccepted.

## Out of scope

Later shared FontObject mutation propagation is separate T6 work; snapshot projection is not complete native FontObject inheritance. Missing-slot policy and unspecified/local-field restoration are not inferred here. No texture ownership redesign, vendor edits or reactive FontObject graph.

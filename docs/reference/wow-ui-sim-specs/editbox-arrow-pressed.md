# EditBox arrow scripts

Retail, PTR, Mists, Era, Anniversary and WowForever retain simulator support for `OnArrowPressed(self, key)` through the focused keyboard input path in `src/lua_api/key_dispatch.rs`. Wrath instead uses direct engine-side arrows without that script; see the [Wrath widget contracts](wrath-widget-labels.md). Script support lives in `src/lua_api/frame/methods/text_attribute_event/events.rs`; existing XML parsing and template binding already represent this handler. See [keyboard dispatch](../event-system.md).

## Wrath exception

`ACTIVE == ClientProfile::Wrath` selects direct caret/history handling. HasScript("OnArrowPressed") returns one nil; GetScript and SetScript reject it, including nil clearing. XML ignoreArrows and SetAltArrowKeyMode share a flag; true requires Alt, false accepts plain arrows. This is reconstructed 12340 behavior, not native-run proof. Multiline coverage is bounded to equal-glyph newline-separated lines; wrapped visual-line/preferred-column behavior and word movement remain unmodeled.

## What it must do (script-capable profiles)

- [x] EditBox supports `SetScript`, deferred `HookScript`, `GetScript`, `HasScript` and clearing `OnArrowPressed`; ordinary Frame does not acquire this handler.
- [x] Focused EditBox dispatches exactly `self` and an uppercase `LEFT`, `RIGHT`, `UP` or `DOWN` direction. Home/End do not emit arrow callbacks. Left/Right retain cursor movement and arrow input does not change text.
- [x] Generic EditBox alt-arrow mode defaults to false. False accepts plain arrows. True requires Alt for EditBox arrow handling; plain arrows neither invoke the handler nor move its cursor and remain available to bindings.
- [x] Alt is recognized from modifier state or an `ALT-` key prefix. Script arguments exclude modifier prefixes. An unfocused EditBox receives no arrow callback.
- [x] The original Blizzard `AutoCompleteEditBoxTemplate` XML binds its original `AutoCompleteEditBox_OnArrowPressed` function, and keyboard Up/Down changes the original autocomplete selection, including wraparound.

The false default is supported by wowless's EditBox `altArrowKeyMode.init` and Blizzard's `UI.xsd` `ignoreArrows` default. Blizzard's chat EditBox template explicitly requests `ignoreArrows="true"`; that is not the generic EditBox default. Blizzard AutoComplete temporarily calls `SetAltArrowKeyMode(false)` when showing suggestions and restores the previous mode when hiding them.

## How it works

- [Event and keyboard dispatch](../event-system.md)
- [XML/template loading](../xml-template-system.md)

## Implementation inventory

- `src/lua_api/frame/methods/text_attribute_event/events.rs` — EditBox-only script support.
- `src/lua_api/key_dispatch.rs` — mode-aware routing, direction argument and existing cursor editing.
- `src/lua_api/frame/methods/widgets/editbox.rs` — existing alt-arrow mode setter/getter, unchanged.
- `src/widget/frame_defaults.rs` — existing false default, unchanged.
- `src/xml/types_support.rs`, `src/loader/helpers.rs`, `src/lua_api/globals/create_frame/template_chain.rs` — existing XML script parsing/binding, unchanged.
- `src/xml/types.rs`, `src/lua_api/globals/template/direct/editbox.rs` — Wrath ignoreArrows/historyLines attributes.
- `src/lua_api/key_dispatch/wrath.rs` — direct Wrath caret/history handling.

## Tests asserting this spec

`tests/editbox_arrow_pressed.rs` covers script APIs and the deferred timer hook pattern, four directions, cursor/text preservation, alt mode and binding routing, focus exclusion, and original cached Blizzard XML/Lua consumer behavior. `tests/key_dispatch.rs` provides existing keyboard-dispatch preservation coverage.

### Bounded Retail proof — 2026-10-18

Four regressions passed at `8943614e0`, linked against the unchanged default-feature Retail library built at `855267dc2`. The original consumer fixture loads Blizzard's unchanged `Blizzard_SharedXMLBase/Compat.lua` prerequisite before `AutoComplete.lua`. All 28 existing `tests/key_dispatch.rs` cases passed against that same production revision in the preceding bounded run; they were not rerun for the fixture-only correction. The initial committed RED at `2bfe5b55b` had four failures, including explicit invalid-handler rejection and unchanged original autocomplete selection. This is bounded headless API/input proof, not native or full-addon acceptance.

## Known gaps (current cycle)

- [ ] Native-client parity and the full Ellesmere options acceptance rerun are not established by these bounded tests.

## Out of scope

IME composition handlers, non-Wrath XML `ignoreArrows` attribute modeling, Ctrl word navigation, Shift selection and wrapped visual-line/preferred-column cursor layout are separate compatibility work. Wrath physical history and bounded newline motion are covered by the linked widget contract; other-profile history navigation is unchanged. No Blizzard or third-party addon behavior is modified.

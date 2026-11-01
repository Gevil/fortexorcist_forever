# XML StatusBar and Slider range/default values

Shared `FrameXml` attributes initialize StatusBar/Slider state before scripts.
Source: `src/xml/types.rs` and shared template direct properties.
[XML architecture](../wiki/systems/xml-template-system.md#xml-widget-ranges-and-default-values)
owns application details.

## What it must do

- [x] Parse/apply `minValue`, `maxValue`, `defaultValue` for both widgets; resolve
  each inherited attribute independently, with instance values winning.
- [x] Expose initial range/default before OnLoad in direct XML and runtime
  CreateFrame/template-child paths.
- [x] Original cached tracker bar reports range0..100/default0, then actual value50
  and label `50%` after its unchanged SetPercent method.

Omitted attributes preserve existing values; other widget types ignore these fields.

## How it works

- [XML system](../wiki/systems/xml-template-system.md#xml-widget-ranges-and-default-values)

## Implementation inventory

- `src/xml/types.rs`: optional numeric attributes shared by both widget tags.
- `src/lua_api/globals/template/direct.rs`: inherited initial range/value application.
- `src/loader/xml_frame/setup.rs`: direct XML initialization.
- `src/lua_api/globals/create_frame/template_chain/runtime.rs`: runtime template initialization.

## Tests asserting this spec

`tests/xml_widget_values.rs` loads original
`Blizzard_ObjectiveTracker/Blizzard_ObjectiveTrackerShared.xml:243` (range0..100)
and its original percent/label method; a second fixture covers both widget types,
explicit overrides, inherited defaults and OnLoad ordering.

Test `2ea2da694` produced two genuine Retail REDs at saved `b8e9da11b`: range0..1
instead of0..100 and initial0/0 instead of50/15. Saved `fe529b241` passed both.
Saved `9d1430bf3` preservation passed XML170 (one existing ignored tooltip TODO),
Slider18 and six original StatusBar UI cases; timeout child summaries do not add
logical cases. Separate same-source Retail startup returned `[]`, exit0.
Receipts: private `quest-lifecycle-build/material-red-repaired-retail-*` and
`root-green-retail-*`; original CVar guards passed.

## Known gaps (current cycle)

No open gate for the bounded saved Retail cases.

## Out of scope

Malformed-XML/native validation parity, full suites, rendering and all-profile acceptance.

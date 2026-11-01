# Registered XML intrinsic tags

Parsed same-name cached `intrinsic="true"` declarations supply implicit inheritance
at XML tag sites. Source: `src/loader/xml_frame.rs`, `xml_file.rs` and
`xml_frame/finalize.rs`. [XML architecture](../wiki/systems/xml-template-system.md#registered-intrinsic-tag-declarations)
owns implementation details.

## What it must do

- [x] Apply the original cached intrinsic mixin and preload for top-level and nested
  `UIThemeContainerFrame` tags, preserving actual method identity and initialized fields.
- [x] Run intrinsic precall OnLoad before instance OnLoad; preserve explicit
  inheritance and nested parent binding.
- [x] Preserve runtime CreateFrame inheritance of the same original definition.

The existing supported-tag parser is unchanged; this is not arbitrary-tag support.

## How it works

- [XML system](../wiki/systems/xml-template-system.md#registered-intrinsic-tag-declarations)

## Implementation inventory

- `src/loader/xml_frame.rs`: shared lookup of registered intrinsic declarations.
- `src/loader/xml_file.rs`: top-level tag inheritance.
- `src/loader/xml_frame/finalize.rs`: nested tag inheritance.

## Tests asserting this spec

`tests/xml_intrinsic_tags.rs` loads unchanged active-profile AccessibilityTemplates.
Retail cache `AccessibilityIntrinsics.xml:3-9` declares the original mixin/precall;
`Mainline/AccessibilityTemplates.lua:3-7` initializes cvar/fontStrings/frames.

Test `eeb2b3bfa` reached genuine missing-mixin RED. Saved `f963b6b18` passed the
focused case, all170 XML-template preservation cases (one existing ignored tooltip
TODO), and separate headless Retail startup `[]`. Original CVar stat/hash guards
passed. Receipts: private `quest-lifecycle-build/intrinsic-{green,startup}-retail-*`.

Retail source inventory additionally activates EventFrame/EventEditBox and top-level
DropDownToggleButton/EventButton declarations. AuraButton, AuraContainer,
DropdownButton, ScrollingMessageFrame, ContainedAlertFrame, ItemButton and
EventScrollFrame already had explicit mappings. Inventory is not consumer reachability.

## Known gaps (current cycle)

No open gate for this bounded saved Retail proof. Broader profile acceptance is separate.

## Out of scope

Arbitrary unknown tags, new widgets, native/schema parity, vendor edits and full suites.

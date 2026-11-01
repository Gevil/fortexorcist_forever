# Numeric-secret spell classifications

Retail/PTR 12.0.5+ classification-selector compatibility in `src/c_api/c_spell_classification.rs`; [C API overview](../wiki/systems/lua-api.md#c-api-numeric-secret-selector-boundaries).

## What it must do

- [x] `C_Spell.IsSpellImportant`, `IsSpellCrowdControl`, and `IsConsumableSpell` accept authentic VM numeric-secret spell selectors from secure and tainted callers, with existing numeric/name conversion, no alias-first expansion or shared-reader widening.
- [x] Results remain exactly one ordinary boolean from existing supplied important/classification facts; unknown identities remain false. INFERRED: retaining ordinary booleans is approved simulator policy, not native selector-driven output-secrecy proof.
- [x] `IsExternalDefensive` remains AllowedWhenUntainted: secure numeric-secret selection works; tainted-secret selection fails. Non-numeric secret payloads are not widened.
- [x] Original NamePlateAurasMixin:IsAuraCrowdControl returns configured true; CastingBarMixin:UpdateHighlightImportantCast highlights the configured important spell, with public/secret × secure/tainted controls.
- [x] Model rows, input opacity and caller taint remain unchanged. Invalid/non-numeric controls preserve existing endpoint conversion and miss behavior, not the complete native SpellIdentifier grammar.

## How it works

- [C API numeric-secret boundaries](../wiki/systems/lua-api.md#c-api-numeric-secret-selector-boundaries)

## Implementation inventory

- `src/c_api/c_spell_classification.rs`: endpoint-local host-only numeric-secret selection; original fact tables and external-defensive permission.

## Tests asserting this spec

- `tests/secret_selector_classification.rs`
- `tests/p1200_rest_spell_plate.rs`

## Bounded proof — 2026-10-20

- RED `8b1c6d953`: three new cases fail with VM secret-access denial; original nameplate directly reaches classification rejection. Producer `587dd8603` changes only the bounded reader/model call path; unchanged cast-bar comparison and setters then pass, locating its earlier failure at the API boundary too.
- Final `6a6c5a32c`, `CARGO_INCREMENTAL=0`: three selector/original-consumer cases pass with explicit caller tags and complete classification-fact checks; public classification module remains 3/3 before/after. Integration ELF SHA256 `9390db837aeca4bbed16897c8006ff21e1b054c1581d8d5fa99431442d05096b`, 1955 embedded test-source paths, all this worktree. No zero-selection credit.
- Retail startup returns `[]`, exit0; binary SHA256 `44776ce1507f69c44b7a34c4ec181c47e4ce1432aafbd6697d5399c9e64d3ace`. Scoped Rustfmt and Cargo fmt checks pass; all three builds have zero warnings. Fourteen original Retail/PTR source hashes and original CVar stat/hash remain unchanged.

Proof at `6a6c5a32c`: three selector/original-consumer cases in `tests/secret_selector_classification.rs` and public classification controls in `tests/p1200_rest_spell_plate.rs` pass. Broader pre-existing duration-object preservation remains 5/6 (inactive-party fixture), unchanged before/after and outside classification scope. This is bounded simulator proof, not native or all-profile acceptance.

## Known gaps (current cycle)

None within this selector subset.

## Out of scope

Generated `SpellDocumentation.lua` marks the three widened endpoints AllowedWhenTainted and ExternalDefensive AllowedWhenUntainted. Original-consumer fixture injection proves selector compatibility, not naturally secret spell IDs at startup. New catalogs, secret-string widening, native output-secrecy parity, vendor edits, shims and VM changes are excluded.

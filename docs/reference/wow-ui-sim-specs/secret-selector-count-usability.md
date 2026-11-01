# Numeric-secret spell counts and usability

Retail/PTR 12.0.5+ numeric-selector compatibility in `src/c_api/c_spell_counts.rs` and `src/c_api/c_spell.rs`. [C API overview](../wiki/systems/lua-api.md).

## What it must do

- [x] Cast count and maximum cumulative aura applications accept authentic numeric-secret selectors in secure/tainted callers, with the existing alias-first identity lookup and strict integral u32 domain. Public numbers/strings remain unchanged; non-numeric secrets remain rejected.
- [x] Usability accepts numeric-secret selectors in secure/tainted callers with its existing strict u32 domain, known-spell membership, and exactly two ordinary booleans. No action-usability model substitution.
- [x] Counts return exactly one number, including zero on miss; usability returns `(false,false)` on miss. Configured spell19750 returns count3, maximum7, and `(true,false)`.
- [x] Cast-count secrecy still depends only on the existing cooldown restriction, maximum-count secrecy on the existing unit-aura restriction. Selector secrecy does not replace either policy. INFERRED: retaining the existing output policy is approved simulator behavior; generated AllowedWhenTainted alone does not establish native selector-driven output secrecy.
- [x] Original viewer CacheChargeValues caches count3/shown=true with genuinely absent charge rows; original RefreshIconColor sets real icon texture white for the configured known spell. Public/secret × secure/tainted run unrestricted; restricted-secure count also runs. Restricted-tainted comparison/setter failure is not a selector regression.
- [x] Queries preserve wrappers, caller taint, model rows and original Blizzard source. Invalid numeric domains and non-numeric secrets remain explicit failures.

## How it works

- [Existing spell runtime](../wiki/systems/lua-api.md)

## Implementation inventory

- `src/c_api/c_spell_counts.rs`: endpoint-local numeric-secret lookup, independent count publication.
- `src/c_api/c_spell.rs`: endpoint-local usability selector.

## Tests asserting this spec

- `tests/secret_selector_counts.rs`
- `tests/spell_count_outputs.rs`
- `tests/spell_max_cumulative_aura_applications.rs`

## Bounded proof — 2026-10-20

Retail RED `5ee8ff94d`: six selector cases fail at original API boundaries. Producer `98253972c` passes unrestricted original viewer count/color paths. Test-only `ba5be5354` uses permitted secure payload inspection instead of comparing wrappers directly; all six cases pass. Count30/max8/SSP1seven controls pass at the unchanged producer. Retail startup exit0 `[]`; original sources14/14 and persisted CVar stat/hash unchanged.

Proof at `ba5be5354`: six cases in `tests/secret_selector_counts.rs` pass, alongside controls in `tests/spell_count_outputs.rs` and `tests/spell_max_cumulative_aura_applications.rs`. This is bounded Retail proof, not natural secret-ID or native-secrecy proof.

## Known gaps (current cycle)

No unresolved failure within the exercised Retail selector subset; PTR-specific P4 runtime acceptance is not claimed.

## Out of scope

Natural startup secret-ID production, secret string selectors, count-display selectors, native output-secrecy parity, restricted-tainted original viewer comparison/widget consumption, action-usability changes, catalogs and shared-reader widening.

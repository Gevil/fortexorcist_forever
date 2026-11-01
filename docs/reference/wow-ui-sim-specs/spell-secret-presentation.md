# Numeric-secret spell presentation selectors

`C_Spell` presentation queries select existing generated spell records using authentic numeric VM secrets. This is bounded simulator behavior, not a native secrecy claim. Source: `src/c_api/c_spell.rs`; [Lua API architecture](../lua-api.md).

## What it must do

- [x] `GetSpellName`, `GetSpellTexture`, and `GetSpellInfo` select the same known database name/icon for public and authentic numeric-secret inputs in secure and ordinarily tainted callers. Presentation fields and containers remain public.
- [x] Explicit user policy (2026-10-20): `GetSpellInfo.spellID` stays secret for a secret numeric selector; public selection retains ordinary numeric identity. No caller-taint clearing or VM-wide unwrap changes.
- [x] `GetSpellDescription` returns public presentation text with existing public-selector behavior.
- [x] `GetSpellLink` returns a whole secret link string for authentic numeric-secret input under `all(retail-12-0-5, any(profile-retail, client-ptr))`, in secure and ordinarily tainted callers, because the link embeds identity. Public-selector results retain existing behavior. Misses return exactly one ordinary nil. Arg2's existing NeverSecret guard remains unchanged.
- [x] Preserve exact arity and misses for implemented presentation endpoints: Info one nil; Texture zero values; Name one `Unknown`; Description one empty string. Known Texture retains its epoch-specific arity (currently three: two public icon IDs and nil override). Link's separate selector regression is covered by `tests/secret_spell_link.rs`.
- [x] Only authentic numeric secrets are inspected. Retain each endpoint's existing numeric conversion: Info/Texture/Link accept finite nonnegative numbers with existing truncation/saturation; Name/Description require exact u32. In particular19750.5 selects19750 through Info/Texture but errors through typed Name. Wrap the resolved Info identity19750, not the original fractional selector. Negative/nonfinite/overflow and other secret kinds retain endpoint-appropriate error/miss behavior without payload disclosure. These are simulator conversion facts; native numeric-domain/error parity is **INFERRED**.
- [x] Wrapper opacity, original payload (including fractional selectors), caller taint and original consumer Lua remain unchanged. Generated spell records are immutable; queries introduce no model writes. Existing glyph argument2 NeverSecret controls remain passing.

## How it works

- [Host-only presentation lookup](../wiki/systems/lua-api.md#numeric-secret-spell-presentation-selectors)
- [Lua API architecture](../lua-api.md)
- [Frame data flow](../frame-data-flow.md)

## Implementation inventory

- `src/c_api/c_spell.rs` — opt-in presentation-selector inspection and identity-bearing output policy.
- `tests/secret_spell_presentation.rs` — authentic VM wrappers and original meter/reward consumers with real widget sinks.
- `tests/secret_spell_link.rs` — public link API, authentic numeric secrets, whole-string payload after GC, caller opacity, ordinary public/miss controls and unchanged glyph rejection.

## Tests asserting this spec

`tests/secret_spell_presentation.rs` and `tests/secret_spell_link.rs`. Runtime proof and exact revisions belong in the private handoff proof ledger until executed.

## Bounded Retail proof

Tests `6e06a4c6c` precede producer `b5a48499c`: four behavioral failures at the original meter icon/name, reward Info and typed secret-miss boundaries; existing spell API59, cooldown restriction17 and glyph security8 controls all pass. Baseline stock startup returns `[]` with original CVar stat/hash unchanged.

At description tests `4a2751af7`, the four core cases pass, including secret resolved identity and endpoint-specific fractional conversion. Original Contribution tooltip public control succeeds, then secret selection reaches `GetSpellDescription`'s typed-selector error: one distinct description RED, not a prior Info/dependency failure. Both compilations finish without warnings and their integration ELFs contain only this worktree's test paths. Final producer `fb3a8a74d` passes all five presentation cases plus the same84 preservation cases (89 PASS), zero warnings and focused formatting. Its ELF `b43dd3cc07dc77fef2c3947eeb5f1aaec4082ed52bc10de5af12ff00fd1ffce7` contains only the owning worktree's test paths. Stock Retail startup returns `[]`; original persisted CVar stat/hash remain unchanged. These are bounded headless Retail receipts, not native or other-profile acceptance.

## Spell-link selector regression — 2026-10-20

Test commit `e4d2891c6` precedes the link producer change. Retail and full-feature PTR each execute four public-API cases: three controls pass and the whole-secret-string assertion fails because the numeric-secret selector returns nil. Both builds have zero compiler warnings and source-bound test executables.

Producer `4eb5422e8`, with test-only observation corrections through `d11e11671`, passes the four link cases on Retail and full-feature PTR. Each profile also passes five presentation, four tooltip and eight glyph-security controls: 21 distinct tests per profile, none ignored or empty. The link fixture checks complete payload bytes after GC, secure payload equality and tainted unwrap/concatenation denial without making `canaccessvalue` an oracle. Both GREEN builds have zero compiler warnings. Stock Retail startup returns `[]` using a child-only copy of persisted CVars; the original's complete stat/hash is unchanged. This is public-API injection proof, not natural secret provenance, native parity or original-consumer sink acceptance.

## Known gaps (current cycle)

- [ ] Downstream link sinks remain held: original GuildPerks tooltip and flyout/chat paths reach `opt_string` sinks that do not consume authentic secret strings. Keep this downstream boundary separate from selector RED; no sink widening is authorized.

## Out of scope

- P3b power cost: actual `UnitCastingInfo` producer emits ordinary numeric spellID only; required real opaque cast source is unavailable. No fabricated casting provider or new casting secrecy model.
- Secret-string spell selectors, public identifier grammar expansion, new aliases, spell acquisition/override graphs, VM changes and render-sink widening.
- Native field secrecy, exact errors and natural secret provenance beyond literal generated documentation remain **INFERRED**. Original meter sources forward stored spell IDs, but injected wrappers do not establish a naturally secret startup call.

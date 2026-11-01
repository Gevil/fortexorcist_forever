# Pet journal hovered battle pet

`C_PetJournal.SetHoveredBattlePet` and `ClearHoveredBattlePet` select an environment-owned hovered GUID. Handlers and backing state live in [c_pet_journal_hover.rs](../../src/c_api/c_pet_journal_hover.rs); [pet_journal.rs](../../src/lua_api/globals/font_strings_collection/pet_journal.rs) installs them after creating the namespace. See [Lua API architecture](../wiki/systems/lua-api.md). Genuine pre-implementation behavioral RED at `080833f1d`: both API tests and all six state tests failed at missing validation or no-op mutation boundaries. Sealed Retail integration at `e3978fd48196` passes API2 + state6, exit0 each; native acceptance remains unverified.

## What it must do

### Cached documented surface

- [x] Setter requires non-nil `battlePetGUID` (`WOWGUID`), with `SecretArguments = "AllowedWhenUntainted"`. Clear has no documented arguments. Both return zero Lua values (inferred from absent Returns entries).

### Requested simulator policies — not native observations

- [x] Retain the supplied UTF-8 string exactly as an opaque GUID, including whitespace, case, arbitrary syntax, and non-ASCII characters. Each successful setter replaces the previous value without catalog or ownership validation, unit-token resolution, trimming, or numeric coercion.
- [x] Empty string is retained as `Some("")`, distinct from cleared state. A fresh environment defaults to `None`; clear removes selection and is idempotent. Separate environments own independent selections.
- [x] Missing, nil, or non-string setter arguments raise a string-validation error before mutation. Error text identifies the required string; exact wording is unspecified. This follows the existing strict GUID boundary rather than coercing string extraction.
- [x] Authentic VM secret strings succeed when untainted and retain exact payload. Malformed untainted secret payloads reach string validation. Tainted secret inputs fail with an untainted-caller error before type validation and mutation. Public strings and clear remain usable when tainted. Preserve caller taint and the original secret wrapper.

## How it works

- [Lua API architecture](../wiki/systems/lua-api.md)
- [Client profiles](../wiki/systems/client-profiles.md)

## Implementation inventory

- [c_pet_journal_hover.rs](../../src/c_api/c_pet_journal_hover.rs): public `PetJournalHoverState`, public optional GUID, default `None`; setter authenticates the original argument through VM `unwrap_secret`, then extracts a strict UTF-8 string before mutation. Setter stores `Some(guid)`; clear stores `None`; both return zero values.
- [c_api/mod.rs](../../src/c_api/mod.rs): unconditional module, matching the existing unconditional PetJournal registration in [font_strings_collection/mod.rs](../../src/lua_api/globals/font_strings_collection/mod.rs). This adds state availability, not cross-profile behavior proof.
- [sim_state.rs](../../src/lua_api/state/sim_state.rs): public `pet_journal_hover` owned state field.
- [state.rs](../../src/lua_api/state.rs): normal empty-state initialization.
- [pet_journal.rs](../../src/lua_api/globals/font_strings_collection/pet_journal.rs): both Set/Clear no-op registrations removed. Legacy registration creates the complete namespace before calling C_API hover registration, which adds the two handlers without replacing its other members. No shared registration file or default-state changes.

## Tests asserting this spec

- [pet_hover_api.rs](../../tests/pet_hover_api.rs): strict argument errors, void returns, real VM secret authentication/type ordering and taint/wrapper preservation.
- [pet_hover_state.rs](../../tests/pet_hover_state.rs): exact UTF-8/empty retention, replacement, default, host-seeded clear, isolation, secure payload retention, tainted public mutations, and immediately observed unchanged state after invalid/security errors.

Tests are Retail/PTR-gated. Retained scoped native runtime report at `080833f1d` records 2/2 API and 6/6 state tests failing, exit 101, with genuine behavioral RED and no fixture/type/timeout defect. Those historical failures did not reach later assertions. Sealed `e3978fd48196` now reaches the bounded API/state assertions: 8/8 PASS, zero FAIL. This is not actual Collections-consumer execution.

## Known gaps (current cycle)

- Parent committed tests/spec/default-only scaffold and obtained genuine behavioral RED against unchanged no-op handlers at `080833f1d` before mutation implementation. Missing-field compiler errors were not used as RED.
- [x] Sealed `e3978fd48196` proves targeted GREEN for all eight tests.
- [ ] Original Collections consumers remain inspection-only. Retail cached `PetJournalInfoDocumentation.lua` declares the setter argument/security metadata and argumentless clear. Cached `Blizzard_Collections/Shared/Blizzard_PetCollection.lua` list-item OnEnter passes guarded `self.petID`; drag-button OnEnter passes guarded parent `petID` before tooltip work. Both OnLeave handlers clear unconditionally. Exact `petID` comes from `GetPetInfoByIndex`, not species ID. Actual consumer execution, native semantics, and PTR cache parity remain unverified.

## Out of scope

Native GUID syntax/catalog/ownership validation, invented events, rendering/tooltips, persistence, production getters, and adjacent PetJournal APIs are excluded. Extra-argument and invalid-byte policies are unspecified; this contract covers supplied valid UTF-8 strings, not arbitrary Lua byte strings. Cached metadata establishes signature/security evidence, not native empty/arbitrary-GUID acceptance or default/lifecycle proof.

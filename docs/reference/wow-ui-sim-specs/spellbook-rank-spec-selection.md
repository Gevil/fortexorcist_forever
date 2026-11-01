# Spellbook rank and specialization selection

PTR and WoWForever declare these queries in their pinned `SpellBookDocumentation.lua:651` and `SpecializationInfoDocumentation.lua:364`. Their UI uses them for spellbook filtering and specialization tab availability.

## What it must do

- [ ] `C_SpellBook.IsSpellBookItemLowRank(slot, bank)` returns the supplied low-rank status of the corresponding modeled player spellbook item. The scenario starts with no low-rank spell IDs; this is not a native rank claim. Unmodeled banks and slots return false as a scenario policy, not a native claim.
- [ ] `C_SpecializationInfo.IsSpecSelectionEnabled(classID)` returns the supplied scenario boolean. It starts true so the selected specialization tab can be available when the other conditions in `Blizzard_PlayerSpellsFrame.lua:241` permit it. This is not a native eligibility rule.
- [ ] Both queries accept secret numeric arguments only from an untainted caller, as their `AllowedWhenUntainted` declarations require.
- [ ] Publish these queries only on PTR and WoWForever.
- [ ] `A_Admin.SetSpellBookItemLowRank(spellID, lowRank)` sets or clears a supplied spell flag; `A_Admin.SetSpecSelectionEnabled(enabled)` sets the scenario boolean.

## How it works

- [Spellbook architecture](../lua-api.md)

## Implementation inventory

- `src/lua_api/globals/admin.rs` — scenario setters.
- `src/lua_api/state/sim_state.rs`, `src/lua_api/talent_state.rs` — per-session inputs.
- `src/c_api/c_spell_book.rs`, `src/c_api/c_spec.rs` — query producers.

## Tests asserting this spec

- `tests/test_keybindings_spellbook_talents.rs` — supplied observations and original specialization tab.

## Known gaps (current cycle)

- [ ] Original spellbook consumer RED/GREEN and all profile gates remain unverified.

## Out of scope

Native rank acquisition, selection eligibility policy, and other missing UI APIs.

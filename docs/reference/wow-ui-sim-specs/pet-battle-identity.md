# Pet-battle identity

CF-2 slice 2 covers populated `C_PetBattles.GetName(owner, petIndex)` identities consumed by the original cached `Blizzard_PetBattleUI/Shared/Blizzard_PetBattleUI.lua`. The existing battle roster supplies the displayed name and species ID; populated journal fixtures supply species names. The intended producer belongs in `src/c_api/c_pet_battles.rs`. See [Lua API architecture](../lua-api.md) for environment and state access.

## What it must do

- [ ] On Retail, PTR, Forever and Mists, the original `PetBattleUnitFrame_UpdateDisplay` must consume the populated identity without a Lua error.
- [ ] Owner 1 and owner 2 select independent rosters; one-based slots select distinct pets. The original consumer must put the selected battle name into its real `Name` FontString.
- [ ] For a supplied custom name different from the supplied species name, the original consumer must show the species name in its real `SpeciesName` FontString.
- [ ] When the displayed name equals the species name, the original consumer must hide that species label; renaming again must show it with the correct species text.
- [ ] Changes to the battle name or species identity must reach the consumer on its next update without rebuilding the environment.

These are populated-fixture compatibility requirements, not evidence of native invalid-input behavior or native database lookup policy. The original consumer explicitly treats the first result as the displayed name (species name when unchanged) and compares it with the second result to control the species label.

## How it works

- [Lua API environment and state](../lua-api.md)
- [Profile-scoped addon loading](../addon-loading-pipeline.md)

## Implementation inventory

- `src/c_api/c_pet_battles.rs` — existing identity registration and species/icon lookup; intended home of `GetName`.
- `src/lua_api/sim_substates/mod.rs` — existing `PetBattlePet.name`, `species_id` and two owner rosters.
- `src/lua_api/state_types/collections.rs` — existing journal `PetData` species-name records.
- `tests/cf2_petbattle_identity.rs` — loads the original addon dependency closure from the active profile cache, verifies consumer provenance, seeds populated state, and observes real output widgets. No consumer replacement or copied function body.

## Tests asserting this spec

- `cf2_petbattle_identity::original_display_reads_names_by_owner_and_one_based_slot`
- `cf2_petbattle_identity::original_display_tracks_rename_and_species_label_transitions`

File-level profile cfg registers both tests only on Retail, PTR, Forever and Mists. Wrath, Era and Anniversary register neither test; no runtime N/A success or fail-fast path exists.

## Known gaps (current cycle)

- [ ] EDIT-ONLY phase: tests are authored but neither compiled nor executed. RED is expected, not observed.
- [ ] `GetName` producer remains absent; no implementation is committed in this phase.
- [ ] Native policy for absent species metadata, empty names, invalid owners/slots and inactive battles remains unestablished. No default, fallback or return-arity policy is prescribed here.

## Out of scope

- Battle engine, matchmaking, roster population and journal synchronization: no CF-2 requirement establishes their behavior.
- Icon, rarity, XP, models, health and pet-type presentation: the identity output fixture intentionally omits these optional children. The entire original display function still executes unchanged.
- Full startup-health and visual acceptance: unrelated stock residuals remain; these tests assert the direct original consumer's text/visibility and no additional recorded errors, without clearing load errors.
- Blizzard Lua edits and compatibility shims: the consumer is the target, not the implementation surface.

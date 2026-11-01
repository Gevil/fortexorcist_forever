# Pet-battle names

`C_PetBattles.GetName` projects supplied battle-pet identity for the selected Retail, PTR, Mists and Forever stock consumers. Source: `src/c_api/c_pet_battles.rs`. See [system and evidence](../wiki/systems/pet-battle-names.md).

## What it must do

- [ ] On these four runtime profiles, return exactly two strings for a supplied pet and species record: the battle pet's effective display name and its species name, in that order.
- [ ] Owner 1 selects the player roster; owner 2 the enemy roster. Slots are one-based. Changing owner/slot or replacing names must be visible on the next call and original `PET_BATTLE_PET_CHANGED` consumer refresh.
- [ ] Preserve distinct battle names independently of journal custom aliases. When the supplied battle name equals the species name, the original tooltip hides its species label; when they differ, it shows the current species label.
- [ ] Use zero results as the **documented-optional representation** (`MayReturnNothing`) for absent roster/species inputs and invalid selectors. Do not manufacture names or return a partial pair. These selected conditions are simulator policy, not verified native invalid-input behavior.
- [ ] Keep all other CF-2 residuals unchanged. Retail stock acceptance compares against a freshly built merged-master map and removes exactly its two GetName error keys (one occurrence each), with all other raw-key/count changes classified and explained. Historical totals are not integrated acceptance targets. SuperTrack is independent and not included.

## How it works

- [State projection, selection evidence and native gaps](../wiki/systems/pet-battle-names.md).
- [Consumer selection and RED proof discipline](../wiki/investigations/consumer-selection-and-red-proof.md).

## Implementation inventory

- `src/c_api/c_pet_battles.rs` — runtime-scoped registration and supplied battle/catalog name projection; no new state schema or defaults.
- `tests/cf2_pet_identity_consumers.rs` — selected original XML tooltip, event path, changing concrete fixtures and full-stock selector.

## Tests asserting this spec

Both exact selectors in `tests/cf2_pet_identity_consumers.rs` independently exercise different owners/slots, effective rename, species rename, equal/different label branches and optional results. Each must reject constant/no-op producers alone. Tests were committed before producer, but **not compiled or executed**: edit-only authorization permits formatting only. All checkboxes remain unverified until parent-run RED/GREEN and callable-mutant trials.

## Known gaps (current cycle)

- [ ] Parent executes frozen RED, producer GREEN, per-selector callable mutants, Retail exact error-set comparison and PTR/Mists/Forever preservation.
- [ ] Native invalid-owner/slot, absent catalog, argument coercion, battle-phase availability, locale and result-arity edge behavior are not measured. Generated docs permit no result but do not specify its conditions.

## Out of scope

Battle engine, server fetching, journal rename propagation, species-database corrections, other pet methods, matchmaking and remaining CF-2 slices. Existing sample names/species metadata remain simulator inputs, not native data claims. Wrath/Era/Anniversary have no selected PetBattleUI consumer and receive no new registration.

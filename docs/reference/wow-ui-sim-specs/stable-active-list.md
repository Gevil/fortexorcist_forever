# Supplied stable active-pet list

Retail and PTR expose supplied `PetInfo` observations through `C_StableInfo.GetActivePetList`. This is separate from [Forever stable reads](forever-stable-read-state.md). The implementation belongs in `src/c_api/c_stable_info/active_list.rs`.

## What it must do

- [x] Publish the getter and its admin inputs only on Retail/PTR. Retail's pinned `StableInfoDocumentation.lua:15–22,193–214` declares a non-nil `table<PetInfo>` with 16 fields. PTR 70493 declares the getter at `:19–26` and `PetInfo` at `:215–241`, with five additional loyalty/happiness/experience fields. Retail must not publish those additional fields.
- [x] Return one fresh array of fresh records, including fresh numeric ability arrays. Preserve the supplied observation order; do not infer native sorting from slot IDs or pet identities.
- [x] `A_Admin.SetActivePetList(records)` replaces the complete ordered observation. An explicitly supplied empty list projects as empty; this does not establish native initial or empty-state policy. Passing nil withdraws the observation.
- [x] `A_Admin.SetActivePet(index, record)` replaces an existing supplied ordinal or appends at the next ordinal. `A_Admin.RemoveActivePet(index)` removes an existing ordinal. These are simulator input operations, not native pet movement, sorting, stable capacity or event policies.
- [x] With no supplied observation, the getter raises `native-unknown: C_StableInfo.GetActivePetList has no supplied list or documented default`. Partial mutations of an unknown list fail explicitly. No placeholder pets are created.
- [x] Populated, add, update, remove and supplied-empty transitions reach the original selected `StableActivePetListMixin:Refresh` and its original XML slot buttons. Two independent environments retain disjoint observations.

## PTR selected-consumer prerequisites

The pinned PTR 70493 `PetConstantsDocumentation.lua:6–17` declares the `PetConsts_Retail` group with expressions using `Constants.PetConsts`. Publish only the five members read by selected Standard StableUI, only when ACTIVE is PTR. These are finite declarations, not inferred pet ownership or default records:

| Published member | Complete pinned chain to literals |
| --- | --- |
| `MAX_SUMMONABLE_HUNTER_PETS` | :12 → `NUM_PET_SLOTS_THAT_NEED_LEARNED_SPELL` :11 → literal5 |
| `EXTRA_PET_STABLE_SLOT` | :14 → `MAX_SUMMONABLE_HUNTER_PETS` :12 → learned slots :11 → literal5 |
| `STABLED_PETS_FIRST_SLOT_INDEX` | :15 → extra slot :14 → maximum summonable :12 → learned slots :11 → literal5 |
| `NUM_PET_SLOTS_HUNTER` | :16 → `MAX_STABLE_SLOTS` :13 literal200 + learned slots :11 literal5 → 205 |
| `MAX_STABLE_SLOTS` | :13 → literal200; selected consumer reads it at :887 |

The original consumer previously fails at Standard/Blizzard_StableUI.lua:11 before defining Refresh. The prerequisite is present in both producer-free RED and GREEN. Consumer construction, not isolated number assertions, is its proof boundary. PTR stock changes require attribution against the original base capture.

## How it works

- [Consumer selection and RED requirements](../wiki/investigations/consumer-selection-and-red-proof.md).

## Implementation inventory

- `src/c_api/c_stable_info/active_list.rs`: supplied list, validation, admin mutations and projection.
- `src/c_api/c_stable_info.rs`: profile-scoped getter registration.
- `src/c_api/c_stable_info/ptr_constants.rs`: declaration-backed PTR selected-consumer prerequisites.
- `src/lua_api/state/sim_state.rs`, `src/lua_api/state.rs`: environment-local observation storage.
- `src/lua_api/globals/admin.rs`: admin registration.

## Tests asserting this spec

- `tests/stable_active_list.rs`: original selected consumer and two-environment lifecycle.
The historical deferred `api_shape_stable_active_list.rs` is not restored. Its broader full-closure zero-errors, full Refresh completion and secondary `GetStablePetInfo` obligations remain unclaimed. The lane selectors, not that historical file, are the acceptance proof.

## Known gaps (current cycle)

No open gates within the supplied active-list scope. Retail/PTR exact lane selectors have producer-free RED and supplied-record GREEN. Retail stock remains 8/10 without raw changes; PTR remains 134/154 with only the two individually traced prerequisite replacements. All seven canonical all-target checks pass with zero compiler warnings; formatting and changed-line readability pass.

## Out of scope

Native acquisition, ordering, default membership, empty-state policy, validation rules and event timing are unknown. Admin validation is a simulator input contract only. Full-closure zero-errors, full Refresh completion and the secondary-pet `GetStablePetInfo` query remain unclaimed. PTR specialization observations at Standard StableUI.lua:1205 are covered separately by the [supplied catalog contract](stable-pet-spec-infos.md); native initial membership remains unknown. Forever's Camelot stable reads and Wrath/Mists/Era/Anniversary remain unchanged.

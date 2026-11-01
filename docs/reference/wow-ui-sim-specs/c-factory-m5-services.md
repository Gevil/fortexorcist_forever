# M5 housing, pets, bank and transmog startup inputs

M5 restores individually required startup inputs after [factory removal](c-namespace-nil-members.md). [Implementation notes](../wiki/systems/c-factory-startup-followup.md#m5-service-and-catalog-inputs) separate catalog-backed queries from named temporary service gaps.

## What it must do

- [x] Retail/PTR owned-house requests are available before the housing dashboard loads and asynchronously emit `PLAYER_HOUSE_LIST_UPDATED` with an empty list while the authoritative ownership service is absent.
- [x] Retail/PTR/Mists/Forever original pet action buttons remain disabled when swap/skip legality is unavailable. Named temporary predicates return false, not eligibility inferred from health alone.
- [x] Those profiles' pet-icon query joins the supplied battle species to pet-journal icon metadata; clearing the supplied pet record produces no icon.
- [x] Forever purchased bank-tab and player-bag capability queries return the documented table/boolean shapes through named temporary workarounds. Their fixed empty/false implementation choices are not native bank policy.
- [x] Forever `C_TransmogSets.HasAnyValidSets()` reads supplied catalog `valid_for_character` flags independently of UI filters. Other profile API publication is unchanged.

## How it works

- [Service/capability defaults and catalog projections](../wiki/systems/c-factory-startup-followup.md#m5-service-and-catalog-inputs)

## Implementation inventory

- `src/c_api/c_pet_battles.rs` — species/catalog icon projection.
- `src/c_api/c_transmog_sets{.rs,/catalog.rs}` — Forever valid-set query and existing catalog.
- `src/c_api/{mod.rs,registration.rs}` and `src/lua_api/{state.rs,state/sim_state.rs}` — share catalog storage without publishing unrelated profile members.
- `src/lua_api/workarounds/temporary/{housing_owned_house_requests,pet_battle_action_legality_defaults,forever_bank_capability_defaults}.rs` — named missing ownership service, battle legality and bank metadata/capability systems.
- `src/lua_api/workarounds/temporary/housing_dashboard_preload.rs` — reuses the same owned-house request definition instead of a late-only duplicate.

## Tests asserting this spec

- `tests/cfactory_m5_services.rs` — complete original pet UI chunks, generated icon/housing/bank/set contracts and asynchronous ownership response.

## Known gaps (current cycle)

[Bounded proof and residuals](../wiki/systems/c-factory-startup-followup.md#bounded-proof--2026-10-21) include a supplied validity flip independent of UI filters. New CanPurchaseBankTab and pet GetName cascades remain held outside the frozen F0 list.

## Out of scope

Wrath behavior; authoritative ownership, swap locks/turn legality, purchased bank-tab metadata and bank-type capability policies. No invented sample pets/houses/tabs, vendor changes or arbitrary member fabrication.

# Supplied guild-bank tab catalog

The existing Mists legacy guild-bank queries in `src/lua_api/globals/bank_storage_verbs.rs` must project an environment-local supplied tab catalog. This replaces the invented General tab, not native purchase, permission, or withdrawal policy. The existing model-backed registration remains Mists-only. See [consumer evidence](../wiki/investigations/invented-query-defaults.md).

## What it must do

- [x] A fresh environment has zero tabs. `GetNumGuildBankTabs` returns the catalog length; `GetGuildBankTabInfo` returns no values for an absent index.
- [x] A supplied tab returns its name, icon, view permission, deposit permission, withdrawal limit, remaining withdrawals, and filtered flag, in that order.
- [x] Original Mists `GuildBankFrame:UpdateTabs` hides absent tabs and displays supplied names through empty → populated → empty transitions.
- [ ] Existing seeded storage-flow assertions keep their meaning by explicitly supplying the General tab.

## How it works

- [Original-consumer evidence](../wiki/investigations/invented-query-defaults.md)

## Implementation inventory

- `src/lua_api/globals/bank_storage_verbs.rs` — existing legacy queries.
- `src/lua_api/state/sim_state.rs` — supplied catalog storage.
- `src/lua_api/globals/admin_actionbars_bags.rs` — explicit fixture inputs.

## Tests asserting this spec

- `tests/mists_bank_storage_panel.rs::original_guild_bank_tabs_follow_empty_supplied_empty_catalog`
- `tests/mists_bank_storage_panel.rs::mists_bank_and_guild_bank_support_storage_flow`

## Known gaps (current cycle)

- [ ] The preserved storage-flow test is blocked before its guild-bank assertions by missing `TriggerTutorial` at original `ContainerFrame_Shared.lua:976`, on both base and GREEN. The General tab is now explicit and all old assertions remain unchanged. The separate original tab-setup RED/GREEN and seven zero-warning all-target checks pass.

## Out of scope

Native tab acquisition, prices, withdrawal policy, guild membership policy, bank money defaults, and non-Mists legacy publication are not changed.

# Profile-specific nil-global call diagnostics

Simulator environments configure rilua's host-owned diagnostic switch at VM creation in `src/lua_api/env.rs`, including environment replacement during UI reload. Profile selection belongs to the simulator, not rilua.

## What it must do

- [ ] Wrath, Mists, Era and Anniversary enable named nil-global call errors: `attempt to call global 'X' (a nil value)` when the VM recovers the global name.
- [ ] Retail, PTR and Forever retain generic `attempt to call a nil value`.
- [ ] Retail inner `pcall` retains false/error and exactly two values through `WowLuaEnv`.
- [ ] The S25 FriendsFrame reproduction retains its missing `SetGuildRosterSelection` fault and observes the recovered name; no guild API or vendor behavior changes.

## Implementation inventory

- `src/lua_api/env.rs`: select the VM setting from `client_profile::ACTIVE` before simulator bootstrap.
- `Cargo.toml`, `Cargo.lock`: select the rilua revision providing the public setting.

## Tests asserting this spec

- `tests/lua_error_messages.rs`: `global_nil_call_error_matches_active_profile`; `retail_nil_global_pcall_preserves_generic_error_and_two_results`.
- `tests/classic_guild_roster_selection.rs`: unchanged `friends_frame_onload_reproduces_missing_guild_roster_selection` (Wrath/Mists).
- `tests/mists_dialog_helpers.rs`: `money_frame_set_type_reproduces_missing_basic_message_dialog_helper`.
- `tests/mists_currency_list.rs`: `token_frame_update_reproduces_missing_currency_list_size`.
- `tests/mists_compat_bootstrap.rs`: `mists_honor_frame_shared_reproduces_missing_honor_system_enabled`.

## Known gaps (current cycle)

- [ ] Static READY-FOR-SLOT only: behavioral RED/GREEN, executed profile registration and reload preservation remain unexecuted.

[Parent slot recipe](../nil-global-call-slot-recipe.md) preserves the exact OLD source/pin separately from master-integrated GREEN, with durable exit capture, exact selectors, protected CVar copies and paired stock comparison. No build or slot proof was run during staging.

## Out of scope

Missing APIs, stock startup error elimination and other VM diagnostic changes. Named classic errors expose missing callees; they do not fix them.

# Spectating UI scenario state

This simulator scenario supplies the state read by `C_SpectatingUI.IsSpectating`. The native contract and native default are unknown; generated Retail and PTR API documentation has no SpectatingUI entry.

## What it must do

- [ ] Publish `IsSpectating()` on Retail, PTR, and WowForever, whose pinned UI calls it.
- [x] Return the environment-local supplied boolean. The initial `false` is a user-authorized simulator scenario default, not a native observation.
- [x] The original Retail game-menu Esc handler consumes both supplied values.

## How it works

- [Spectating UI scenario](../wiki/systems/spectating-ui.md)

## Implementation inventory

- `src/c_api/c_spectating_ui.rs`: query and profile publication.
- `src/lua_api/state/sim_state.rs`: scenario fixture input.
- `src/lua_api/state.rs`: scenario default.

## Tests asserting this spec

`tests/chat_enter_binding.rs` exercises the original game-menu handler with an explicit Enter binding.

## Known gaps (current cycle)

- [x] Seven-profile all-target checks pass with zero compiler warnings.

## Out of scope

Spectating lifecycle, other `C_SpectatingUI` members, and native default or policy are not modeled.

# M3 social startup inputs

M3 replaces observed social/group/chat/guild gaps exposed by [factory removal](c-namespace-nil-members.md). Real C namespace queries and backing types belong in `src/c_api/`; explicit temporary defaults belong in `src/lua_api/workarounds/temporary/`. No arbitrary member factory is permitted. [Lua API notes](../wiki/systems/lua-api.md) describe the shared simulator state.

## What it must do

- [x] On the six observed non-Wrath profiles, `C_GuildInfo.GetGuildTabardInfo(unit?)` returns nil when local-player numeric tabard metadata is unavailable, or for units without a supplied snapshot. Wrath keeps this unregistered member nil.
- [x] Supplied tabard metadata projects existing guild-logo RGB values into fresh ColorMixin objects, with numeric `emblemFileID` and `emblemStyle`, matching the cached `GuildInfoSharedDocumentation.lua` DTO.
- [x] `A_Admin.SetGuildTabardMetadata(fileID?, style?)` accepts a complete pair of nonnegative u32 values, clears metadata when both are absent, and rejects invalid/partial updates without changing prior state. This is a simulator input contract, not a native setter.
- [x] Replacing the legacy logo through `SetGuildEmblem` invalidates numeric metadata that cannot be derived from its filename. Legacy RGB/filename behavior remains intact.
- [x] Other observed M3 members use existing backing state where available; otherwise only explicitly named temporary inactive-service contracts, each naming its missing backing system and retirement condition. No native policy is inferred from a method name.
- [x] Non-Wrath documented social contracts use explicit simulator defaults until their backing services exist: no cross-faction roster, no silence restriction, chat reception allowed, LFD/GroupFinder and LFG authentication unavailable. Mists preserves its existing guild-bank storage capability; other profiles report that unmodeled capability unavailable.
- [x] Retail/PTR/Forever mentorship reports documented `None=0`, Recruit-a-Friend availability and legacy friend mode are disabled, and language capability follows the existing explicit legacy language list. Forever friend-tag game-type capability is disabled. These are named temporary policies, not native defaults.
- [x] Existing explicit methods, strict/retired surfaces and arbitrary-member nil behavior remain intact. Original startup assertions remain unchanged.

## How it works

- [C namespace lookup and diagnostics](../wiki/systems/addon-loading.md#missing-c-members-f0-2026-10-20)

## Implementation inventory

- `src/lua_api/state_types/character_world.rs` — existing guild-logo RGB and filename state; numeric metadata integration point.
- `src/lua_api/globals/real/guild_logo.rs` — existing legacy projection, retained.
- `src/c_api/c_guild_info.rs` — typed tabard metadata and C query.
- `src/lua_api/workarounds/temporary/social_service_defaults.rs` — named missing-service policies, scoped by cached declarations.
- `src/lua_api/workarounds/temporary/startup_namespace_defaults.rs` — existing named empty-state defaults; do not replace real state with a factory.

## Tests asserting this spec

- `tests/guild_tabard_info.rs` — documented DTO with the original cached ColorMixin framework, supplied metadata, fresh mutable colors, validation/clearing and legacy state preservation; bootstrap color-stub completeness is outside this batch.
- `tests/c_factory_m3_social.rs` — per-profile generated-documentation return contracts and explicitly chosen temporary policies.
- `tests/c_namespace_nil_contract.rs`, `tests/nil_symbol_access.rs` — removal contract retained.
- `tests/startup_warnings.rs` — unchanged final startup health gate.

## Known gaps (current cycle)

- [x] Implement and prove the tabard snapshot behavior against the original GuildMicroButton consumer (`MainMenuBarMicroButtons.lua:1254` on Retail).
- [x] Resolve remaining observed M3 roots: mentorship status, cross-faction party status, guild-bank availability, friend-tag/game-type support, social mute/receive policy, language capability, legacy-friend mode, LFD/GroupFinder availability, LFG authentication and Recruit-a-Friend availability.
- [x] Re-capture the post-M3 frontier without hiding failures belonging to other batches.

## Bounded proof — 2026-10-21

Tests-first producer commits `e1c4d730f` and `fffd49163` follow frozen original-consumer RED at source-equivalent `0953c9b58`; fresh Retail contract RED at `2b3b600208` additionally reproduced missing APIs. The tabard DTO uses the original cached ColorMixin, not the incomplete bootstrap color default. Final integrated source `c246449ca` includes master `342acab31`; common registration/state and loader changes required all targeted cases to rerun. See the [combined matrix](c-factory-m4-world-inputs.md#bounded-proof--2026-10-21).

All assigned M3 original rows and missing-member signatures are absent from the final stock matrix. Newly reached invitation/squelch/party queries remain unfixed residuals, not extra M3 producers. This is not clean-startup or native-condition parity proof.

## Out of scope

- Guessing modern native conditions or reconstructing client code.
- M1/M2/M4/M5/T6 producer work, except preserving their recorded failures and necessary existing state.
- Changes to Blizzard/vendor Lua, rilua, original persisted CVars, or arbitrary member fabrication.
- Newly exposed members absent from the frozen gap-list: retain them as residuals with profile, original consumer location, stderr receipt and causal root fix; do not expand this batch.

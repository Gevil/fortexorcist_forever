# Unit existence state and aura visibility

`UnitExists` reads simulator state, and shared aura collection suppresses records for units without modeled existence. This records commits `1a5e8f348`, `1681029d7` and `35822d5c7`; the producers live in `src/lua_api/globals/group_queries.rs` and `src/lua_api/globals/auras.rs`. See [Lua API architecture](../wiki/systems/lua-api.md). These are simulator contracts, not native-parity claims.

## What it must do

### Modeled existence

- [x] Keep `player` present. Report `pet` present exactly when `pet.icon` is populated; summon/dismiss state changes must update the result.
- [x] Report `vehicle` present exactly while `player.in_vehicle` is true; entering/exiting must update the result.
- [x] Original Retail `CompactUnitFrame_UpdateVisible` must hide/show/hide a frame whose `unit` and `displayedUnit` are `vehicle` across absent/entered/exited occupancy, publishing `unitExists` false/true/false. Keep both tokens, the player control's visibility/tokens and stored pet fixture unchanged. This does not exercise vehicle/pet token substitution.
- [x] Report `target` absent before selection and after clearing, and present while `current_target` is populated.
- [x] Report `focus` present exactly when `current_focus` is populated. Party tokens require both `party_group_active` and an in-range member index (`unit_exists_in_state`).

### Aura visibility and result boundaries

- [x] Absent targets expose no legacy UnitAura/UnitDebuff record, indexed/instance record or aura slots; selecting a target exposes its stored debuffs, and clearing it hides them again.
- [x] Inactive party membership hides stored party auras from legacy and indexed queries without deleting them; activating membership exposes the stored records.
- [x] All retrieval/enumeration paths using the shared collector must suppress records for missing units. This does not bypass existing argument validation or access checks.
- [x] Preserve these specific missing-record results for otherwise accepted inputs, where the API is registered: `GetAuraApplicationDisplayCount` returns `""`; `IsAuraFilteredOutByInstanceID` returns **true** (missing means filtered out); `GetAuraBaseDuration` and `GetRefreshExtendedDuration` return nil; `DoesAuraHaveExpirationTime` returns false.
- [x] Preserve existing errors rather than describing every aura query as empty: curve-based `GetAuraDispelTypeColor` raises `aura instance not found`; `GetAuraDuration` raises `no such aura instance`.

Original existence/visibility regressions retain historical Retail/Forever GREEN evidence. The additional focus/party boundaries and public shared-collector result/error/access matrix have bounded Retail execution below; no Forever or native acceptance is inferred for those additions.

## How it works

- [Lua API architecture](../wiki/systems/lua-api.md).
- [Unit GUID presence](unit-guid-presence.md) — separate identity-query contract.

## Implementation inventory

- `src/lua_api/globals/group_queries.rs`: `UnitExists` and shared `unit_exists_in_state` predicate.
- `src/lua_api/globals/auras.rs`: existence gate before aura-store reads; shared collection and instance lookup.
- `src/c_api/c_unit_aura_display_count.rs`: empty missing-record display count.
- `src/c_api/c_unit_aura_filter_query.rs`: missing records are filtered out.
- `src/c_api/c_unit_aura_dispel_color.rs`: curve query's missing-instance error.
- `src/c_api/aura_duration.rs`: base/refresh nil results, expiration false and duration-object error on missing records.
- `src/lua_api/globals/utility_system_spell/spell_api.rs`: unchanged pet/vehicle player-vitals shortcut.

## Tests asserting this spec

`tests/unit_exists_state.rs`:

- `pet_existence_tracks_summon_and_dismiss_from_rust_state` and `vehicle_existence_tracks_player_occupancy_from_rust_state`: absent/present/absent transitions and player controls.
- `target_aura_queries_follow_selection_and_clear`: existence, legacy/index/instance/slot absence and populated target controls.
- `party_aura_queries_require_active_membership_without_deleting_stored_auras`: inactive/active/inactive query visibility and retained stored aura.
- `focus_and_party_index_boundaries_follow_state_transitions`: focus absent/present/cleared and inactive/active/inactive party indices zero, first, last and one-past-end.
- Retail-only `missing_unit_aura_paths_preserve_results_errors_and_access_checks`: retained helpful/harmful target fixtures through missing/present/missing/present transitions, raw-registered collector endpoints, exact missing-record boundaries, invalid/secret arguments and restricted tainted access. Player-only queries retain populated controls; private-store endpoints do not use the shared public collector. Execution status lives in the bounded proof report, not this test inventory.
- Retail-only `compact_unit_frame_pet_visibility_tracks_summon_and_dismiss` and `blizzard_aura_util_visits_only_selected_target_debuffs`: cached Blizzard consumers through simulator state transitions.

`tests/unit_exists_vehicle_consumer.rs` adds Retail-only `compact_unit_frame_vehicle_visibility_tracks_enter_and_exit`. It loads the complete original profile-cache `Blizzard_UnitFrame/Shared/CompactUnitFrame.lua` (SHA-256 `1f7064c5d54466c26c53fded64684612d76891cb10d514fe3a806839079848fb`), calls its unchanged visibility function and delegates existence through its original `CompactUnitFrame_UnitExists`. No consumer function or unit query is replaced. `tests/integration.rs` discovers this module through `crates/test-harness/build.rs`; no manual registration is needed. Bounded RED/GREEN evidence follows.

The first four have historical Retail and Forever passes; consumer tests have Retail passes only. This does not establish all-profile coverage.

## Additional bounded proof — 2026-10-18

Source `f8afe3b3f9e23082aa7c44acef9feafb05ff4f59`, based on `29fac7076965dd53973168c47d972e4090f27b98`: both new `unit_exists_state::` tests above selected **1 PASS / 0 FAIL each**, using the same Retail integration executable. Features: `--no-default-features --features sound,gui,casc,client-retail`. Private-store-relative receipts: `handoff/a1-timer-unit-tests/build-03-B5.json` and `build-03-B6.json`; each binds exact selector, executable SHA-256, features and source revision. `cargo fmt --check` and matching Retail `cargo check --lib` passed.

The aura fixture retains concrete helpful/harmful records through four existence transitions, including reactivation. It covers the registered legacy, `C_UnitAuras` and `AuraUtil` public collector queries, plus party indexed-tooltip reads. Player-only queries remain populated controls because `player` cannot disappear; private-store APIs are not callers of this public collector. No product behavior was changed.

## Original vehicle consumer bounded proof — 2026-10-18

Test-first commit `eef4943e9` adds the original-consumer test; source `018da33df` (base `721b0ec49`, documentation-only follow-up) selected **1 PASS / 0 FAIL**, 11,350 filtered, in 3.16s with Retail default features. It proves absent/entered/exited visibility and `unitExists`, retained unit tokens, visible player control and unchanged stored pet icon. GREEN executable SHA-256: `820b5d2b70c97b0ee4b354559ecdeda0fb01115e5bb10d3875d844d86c6bd5d4`.

Retroactive RED used detached `1a5e8f348` (`1681029d7^`) plus only the byte-identical new test (SHA-256 `2fc6365c15cfb27ff250e9949e66cf0e8ea633a2d8984d35cbdd170cc5567573`). The original consumer loaded, then the first absent-vehicle visibility assertion failed: actual shown **true**, expected **false**; **0 PASS / 1 FAIL**, 11,325 filtered, in 1.04s, exit 101. RED executable SHA-256: `85ed9a00dc0af2612af1a985e19e938d6d9bf6b891dee30eb791bd06dcdb932d`. Existing producer `1681029d7` replaces unconditional vehicle existence with occupancy state; no new model or consumer edits were needed.

The same slot was used for both builds. Initial current compilation failed on a stale generated test-harness absolute path after historical worktree removal; regenerating that package's build outputs resolved it without source changes. This compilation failure is not product RED. `cargo fmt --check` and standalone `rustfmt --check` for the new test passed. Runtime limits were 4 GiB/90 seconds. No vehicle/pet unit substitution, native, other-profile, GUI or vitals acceptance is inferred.

## Known gaps (current cycle)

- [ ] Pet/vehicle vitals still return player vitals before checking existence in `lookup_unit_vitals`; health/power behavior is unchanged and inconsistent with absent pet/vehicle existence.
- [x] Dedicated focus and missing-unit aura transition regressions have bounded Retail GREEN. Neither these nor the original six regressions establish native or all-profile parity.

## Out of scope

New pet/vehicle vitals or identity models, new aura stores, changes to argument/security policy, native-client equivalence and unmeasured GUI effects. This slice changes existence and aura visibility, not every API that accepts a unit token.

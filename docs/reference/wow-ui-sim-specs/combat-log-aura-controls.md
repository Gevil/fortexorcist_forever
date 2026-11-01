# Combat log and aura controls (CF-2 slice 3)

The original cached Blizzard combat-log processor, arena debuff cleanup and group-buff manager must consume simulator-owned filter/aura controls. Modeled `C_*` behavior belongs in `src/c_api/`; Blizzard Lua remains unchanged. This slice is test/spec-only: RED has not been observed and no producer is authorized before it is.

## What it must do

### Combat-log filter setup preservation — Retail / PTR

- [ ] Original `CombatLogProcessor:SetFilterSettings` traverses `ApplyFilterSettings` and secure `AddEventFilter` without error, retains the supplied settings and replaces them on a later selection.
- [ ] Original filter setup controls matching event inclusion/exclusion, not merely API callability. **PENDING-NATIVE-ORACLE:** populated ingest and matching policy have no established simulator model; this acceptance requirement does not yet have an executable test.

### Arena cleanup — Retail / PTR

- [ ] Original `ArenaUnitFrameDebuffMixin:Update` with no active loss-of-control aura clears all display blocks for its selected unit; both supplied helpful aura records reappear through public index enumeration.
- [ ] Cleanup preserves another unit's block and the underlying aura records, hides the stale debuff widget, tolerates repeated cleanup and clears newly re-added blocks.

### Group-buff manager preservation — Forever

- [ ] Original `GroupBuffMixin:RefreshGroupBuffVisualAlerts()` reaches the real getter without an error; no explicit argument or test override may bypass it.
- [ ] Original alert-change consumer maps supplied `{spellID, visualValue}` records to per-spell lookups and replaces, rather than merges, the previous records.
- [ ] Implicit getter refresh consumes configured populated alert records. **PENDING-NATIVE-ORACLE:** normal Forever configuration/backing-state path is missing; payload mapping coverage alone is not proof of this requirement.

## How it works

- [Addon loading and dependency closure](../addon-loading-pipeline.md)
- [Event dispatch](../event-system.md)
- [C API surface](../lua-api.md)

## Implementation inventory

- `tests/cf2_combat_aura_controls.rs` — Retail/PTR concrete blocked-aura enumeration acceptance.
- `tests/cf2_combat_filter_preservation.rs` — Retail/PTR settings boundary preservation only.
- `tests/cf2_group_buff_preservation.rs` — Forever getter boundary and direct payload preservation only.
- `src/lua_api/globals/auras.rs` — existing aura lookup and public `AddBlockedAura`; live blocks currently reside in namespace state, not the unused `SimState.blocked_auras_by_unit` field.
- `src/lua_api/workarounds/temporary/combat_log_state.rs` — existing temporary combat history; no secure event-filter matching model.
- `src/lua_api/workarounds/temporary/unit_auras_state.rs` — existing modern-profile alert state; current feature selection omits the Forever getter/setter.
- Future backing filter/aura-control model and C namespace registration belong in `src/c_api/`. No producer implementation is included here; no workaround or vendor patch is proposed.

## Tests asserting this spec

Integration target selectors:

- `cf2_combat_aura_controls::original_arena_cleanup_restores_selected_unit_aura_enumeration` — Retail/PTR selected-unit block removal, independent other-unit block, repeat/reblock and original widget visibility. Only this case is expected-RED producer acceptance.
- `cf2_combat_filter_preservation::original_combat_processor_applies_selected_event_settings_preserves_boundary` — Retail/PTR settings retention/replacement only; not secure matching proof.
- `cf2_group_buff_preservation::original_group_buff_manager_reads_api_then_maps_supplied_alert_records_preserves_boundary` — Forever implicit-getter boundary and direct payload mapping; not configured getter proof.

Each file uses file-level cfg listing exactly its applicable profiles. Other profiles register no such tests. No test has been compiled or executed.

Secure filtering and the Forever configured-alert getter have no producer acceptance until the outstanding laptop PENDING-NATIVE-ORACLE answers establish normal populated state paths and genuine RED assertions. No producer may be written for either surface before those answers; preservation tests cannot authorize no-op implementations.

## Known gaps (current cycle)

- [ ] Obtain admitted build slot and observe exact original-consumer REDs before producer work. Compilation/provenance/setup failures do not count as RED.
- [ ] PENDING-NATIVE-ORACLE — Retail/PTR `Blizzard_CombatLogProcessor/Blizzard_CombatLogProcessor.lua:118-183` builds event lists and source/destination masks or GUIDs; `:49-54` queries secure `ShouldShowCurrentEntry`. What are nil/empty event-list semantics, mask category matching, GUID matching and multi-filter composition? Which normal simulator event ingest/state path should own populated records? Do not infer this from the current public always-true-for-nonempty workaround.
- [ ] PENDING-NATIVE-ORACLE — Forever `Blizzard_FrameXMLUtil/AuraUtil.lua:702-706` reads ordered alert records; `:715-717` accepts changed records. `Blizzard_APIDocumentationGenerated/UnitAuraDocumentation.lua:555-564` documents the setter, but the simulator publishes neither getter nor setter for Forever. What native configuration source, allowed values, persistence and changed-event policy should back the implicit read? No invented empty defaults or private-table test seeding.
- [ ] After those answers, add populated matching/configured-getter assertions through normal state paths. Existing boundary/payload tests are intentionally incomplete acceptance coverage and must not justify no-op producers.

## Out of scope

- Other CF-2 slices and unrelated startup errors.
- Combat-history redesign, absent/invalid input policies, security/taint restriction parity and loss-of-control selection/reblocking beyond the no-active-aura cleanup branch; require separate native evidence and authorization.
- Builds, tests, cargo checks, producer source, push/merge and whole-profile acceptance in this EDIT-ONLY phase.

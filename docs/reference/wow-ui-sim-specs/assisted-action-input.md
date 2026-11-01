# Assisted action identity and slot lookup

Explicit optional assisted action identity is independent of the next-cast recommendation. Input state lives in `src/lua_api/state/support_types.rs`; query producers now project that input. Six pre-producer cases executed (one PASS/five behavioral FAIL); bounded Retail execution is recorded below. Architecture: [Lua API](../lua-api.md).

## What it must do

- [ ] Supplied `action_spell_id: Option<u32>` defaults to `None`. No identity inferred from recommendations or populated bars.
- [ ] Zero-argument `C_AssistedCombat.GetActionSpell()` returns the current numeric identity or nil, live and environment-local, without changing `next_cast_spell_id` or `GetNextCastSpell()`.
- [ ] Zero-argument `C_ActionBar.FindAssistedCombatActionButtons()` matches semantic spellID assignments against action identity, never next-cast recommendation.
- [ ] **Simulator policy:** matching sparse positive slots form a dense ascending list; absent identity or no matches returns nil. Native ordering and exact miss arity are unverified.
- [ ] Results are fresh snapshots reflecting current identity and assignments. Caller mutation cannot alter backing inputs or another result; retained results survive input changes.

Contract grounding: cached `Blizzard_APIDocumentationGenerated/ActionBarFrameDocumentation.lua` declares a zero-argument, potentially absent table of slot indices. `AssistedCombatDocumentation.lua` declares separate action and recommendation queries. Cached `Blizzard_ActionBar/Mainline/AssistedCombatManager.lua` reads these identities independently. These sources do not establish a recommendation or identity-selection algorithm.

## How it works

- [Lua API architecture](../lua-api.md)

## Implementation inventory

| Path | Role |
|---|---|
| `src/lua_api/state/support_types.rs` | Independent optional action input; derived default is absent. |
| `src/lua_api/state/sim_state.rs`, `src/lua_api/state.rs` | Existing environment-owned assisted state and default initialization. |
| `src/c_api/c_assisted_combat_action.rs`, `src/lua_api/globals/missing_surface/small_namespaces.rs` | Modeled action getter registered through the existing namespace; old nil stub removed, next-cast getter unchanged. |
| `src/c_api/c_action_bar_spell_slots.rs` | Direct and assisted queries share effective spell-slot filtering and ascending projection; assisted misses return nil. |
| `tests/assisted_action_input.rs` | Six behavioral tests, shared `retail-12-0-0` capability gate. |

## Tests asserting this spec

`tests/assisted_action_input.rs` covers live optional identity, independent environments, sparse ascending matches, absent/unmatched identity, fresh/live snapshots and recommendation independence. Fixtures use explicit semantic spellIDs and clear macros/outfits; map values are not universally spellIDs. The assertion helper declares Find calls but does not execute them during setup. Generated `--test integration` filter: `assisted_action_input::` (expected six cases). At `ff72f3c3b`, six selected cases produce one absent/miss-policy PASS and five behavioral failures on supplied identity or matching-slot results; no observed fixture failures. Later snapshot/transition assertions remain unreached in that RED where earlier results fail. Executed scoped Retail producer GREEN: 6/6 PASS at `6b522c595`; [investigation SSOT](../wiki/investigations/integrated-source-and-factory-proof-2026-10-09.md#executed-staged-queries-and-new-producers).

## Known gaps (current cycle)

- [x] Compile and execute genuine RED against unchanged producers; compilation or fixture failure is not behavioral RED.
- [x] Implement minimal action getter and assisted slot query after relevant behavioral failures.
- [ ] Mixed GREEN/startup/API-registration/profile gate remains open: startup still fails with 12 SMOOTH setup errors, not clean; default-check/PTR acceptance remains pending.

## Out of scope

Macros, outfits, talent-ID reinterpretation, shadowed assignments, slot-zero validation and special-bar membership are not modeled by these semantic-slot fixtures. Recommendation synthesis, automatic identity selection, new admin/import producers, events and persistence are excluded. No native ordering, security, miss arity, cached-caller parity or broad-profile acceptance is claimed.

# Supplied PvP match completion (CF-2)

Retail/PTR `C_PvP.IsMatchComplete` must project the existing supplied completion snapshot. The original selected `Blizzard_PVPMatch/PVPMatchResults.lua` entering-world consumer is the behavioral boundary. This is a first slice, not closure of Forever's selected consumer.

## What it must do

- [x] Publish `C_PvP.IsMatchComplete` for runtime `client_profile::ACTIVE` Retail/PTR, returning exactly `SimState.pvp_catalog.match_completed` without mutation.
- [x] Preserve the existing `HasMatchStarted` active-queue-or-completed behavior; do not alias completion to activity or queue status.
- [ ] One selector uses the normal XML-created `PVPMatchResults`, retaining its installed `OnEvent` script, asserting the frame method equals the original mixin method with original-file provenance, and observing that script call the method exactly once. It covers inactive/incomplete → active/incomplete → inactive/complete → inactive/incomplete snapshots, resetting actual registrations between snapshots without replacing scripts or repairing presentation.
- [ ] Assert original active-event subscriptions and unchanged hidden presentation. The selector independently rejects constant true and constant false.
- [ ] Obtain independent Retail/PTR RED at the original completion call, then GREEN and complete own-base stock-map comparisons against master571284aaa. The authorized static producer stage precedes runtime execution; no observed RED/GREEN is claimed.

## How it works

- [Event dispatch](../event-system.md)
- [Client profiles](../wiki/systems/client-profiles.md)

## Implementation inventory

- `src/c_api/c_pvp/catalog.rs`: existing supplied completion input and unchanged `HasMatchStarted`.
- `src/c_api/c_pvp.rs`: GREEN publishes a read-only `IsMatchComplete` callback only for runtime ACTIVE Retail/PTR, inside the input's `retail-12-0-0` availability gate. It pushes the supplied boolean directly. No new default, activity alias, queue inference, reset or lifecycle policy is added. Forever receives no publication from this producer.
- The paired RED is GREEN with only that registration and callback removed. Its tests and documentation are identical; this inventory describes GREEN, not the producer-subtracted control.
- `src/lua_api/state/sim_state.rs`: existing epoch-gated `pvp_catalog` storage.

## Tests asserting this spec

- `tests/cf2_pvp_completion.rs`: calls through the normal XML-created frame's unchanged installed event script. A temporary debug call hook observes the original method by function identity and is removed even when the call errors; the error is then asserted. No surrogate frame, manual Mixin, SetScript, or API replacement. Explicit `retail-12-0-0` compile gate matches the existing input's availability; runtime profile assertion admits only Retail/PTR. The prior Retail execution failed at the incorrect script/method equality premise, before provenance and completion. The corrected setup has static proof only; runtime RED is still required.

## Known gaps (current cycle)

- [ ] Slot admission, observed RED/GREEN, executed constant/no-op mutation proofs, zero-new-warning test-target checks and actual stock deltas remain pending. The producer is statically implemented; no build or runtime acceptance is claimed.
- [ ] Forever's selected original consumer needs an explicit normal completion input/publication contract; its current epoch has no `pvp_catalog` field. No Forever API or compatibility claim in this slice.

## Static selector discrimination

The original-consumer selector is `cf2_pvp_completion::original_match_results_enter_world_tracks_inactive_active_and_completed_match`. Each row below describes that same selector, separately for Retail and PTR. These are source-level contradictions, not executed mutant kills. Runtime provenance and dispatch checks must first succeed in the selected profile cache.

| Profile | Constant true | Constant false | No-op (zero returns/nil or absent publication) |
|---|---|---|---|
| Retail | Snapshot 1 incorrectly registers eight active events | Snapshot 3 omits eight required active events | Snapshot 3 omits events; an absent/noncallable API can instead error at the original completion call |
| PTR | Snapshot 1 incorrectly registers eight active events | Snapshot 3 omits eight required active events | Snapshot 3 omits events; an absent/noncallable API can instead error at the original completion call |

Snapshot 2 uses independent activity and short-circuits the completion call. Snapshot 4 checks the return to incomplete state. The unchanged hidden-presentation and no-new-error assertions remain additional constraints.

`p1200_rest_catalogs::p1200_rest_pvp_catalog_empty` and `pvp_info::pvp_info_methods_use_seeded_world_and_locklist_state` are preservation selectors. Neither reads `IsMatchComplete`; neither independently rejects its constant/no-op replacements. They do not count as producer RED.

## Out of scope

Match simulation, reward/reset timing policy, Mists vehicle records, speculative Forever enablement, native parity and full-prefork completion. Other startup blockers remain independent.

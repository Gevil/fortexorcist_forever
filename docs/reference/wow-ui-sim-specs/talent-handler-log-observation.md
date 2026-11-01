# Talent handler-log observation

Test-scoped observations associate existing handler logs with the canonical talent latency fixture. Logged records describe dispatch attempts and rounded intervals, not unique/top-level callbacks or exclusive callback-body cost. Logging may perturb latency; no repaired-performance or native claim follows.

## What it must do

- [x] Mark each original tick outside its measured timer, preserving20 baseline/10 settle/24 steady samples, setup/order and existing35ms average/75ms max/+20ms delta assertions.
- [x] Parse complete ordered begin/end windows and existing handler records in input order; JSON exports grouped/tick summaries, not per-tick ordered record identities. Preserve repeated OnUpdate/OnPostUpdate/other attempts, identities, zero intervals, grouped sums/maxima, and outside-window/unparsed-line counts.
- [x] Reject malformed records, invalid durations, mismatched/overlapping/out-of-order/duplicate/missing/unclosed windows; emit deterministic JSON for a complete canonical log and explicit failure for invalid input.
- [x] Retain actual diagnostic input/resource/source/command identity and original selector outcome. Completeness requires existing `WOW_SIM_LOG_HANDLER_TIMINGS=0` before process/OnceLock initialization; launcher metadata and child-inheritance source support this, not independent child environment/PID attestation. Parser `all_attempts_verified=false` remains conservative; a logged-run threshold result is not repair evidence.

## How it works

- [Event system](../event-system.md)
- [Frozen performance investigation](../wiki/investigations/fullsuite-ba-2026-10-11.md)

## Implementation inventory

- `tests/talent_panel_onupdate_perf.rs`: existing canonical fixture and test-only tick markers.
- `src/lua_api/script_helpers/event_dispatch.rs`: existing OnUpdate dispatch interval logger, unchanged.
- `src/lua_api/env_events.rs`: existing generic script/OnPostUpdate interval logger, unchanged.
- `tools/talent_handler_log.py`: standard-library-only log-to-JSON observation tool. Global grouping includes setup/outside-window records; phase grouping does not.

## Tests asserting this spec

- `tools/test_talent_handler_log.py`: concrete parser/CLI fixtures; development RED46 assertion failures then GREEN12 tests. Independent source/parser-development PASS authenticates saved outcomes and current GREEN scope, not independently witnessed past execution or cryptographic provenance of historical RED implementation; initial syntax error excluded from RED credit.
- `tests/talent_panel_onupdate_perf.rs::talent_panel_open_onupdate_tick_latency_stays_under_budget`: original assertions retained; actual marked/logged selector PASS once, independent2779 capture coherence PASS via raw reconstruction. Parent/child summaries are one body execution.

## Known gaps (current cycle)

- [x] Saved development RED46/GREEN12 reviewed within historical-provenance limits; new seal first authenticated once and actual54 windows/aggregate coherence independently verified.
- [x] Source/readability and interpretation limits verified; actual compile/fmt PASS. Default check REUSED for unchanged production/library scope only, not new instrumentation.
- [x] Independent packet retention/link/privacy bounded PASS at `e95d9f1901ef270058f18dac788814863f070423`:57 copies/2,845,419 bytes,19 links/4 anchors,zero privacy findings; no binaries/images/replays. Retained-text scope only, not universal secret detection; no cache-contents attestation.
- [ ] Native/performance/root-cause/full-handoff acceptance remains open.

[Current meaning and limits](../wiki/investigations/fullsuite-ba-2026-10-11.md#talent-handler-log-observation--2026-10-12) link the detailed packet rather than duplicating its numerical ledger.

## Out of scope

No vendor/runtime optimization, production metrics or new runtime configuration. Intervals include helper/error/nested work; summing nested intervals can double-count. Rounded log values and logging overhead are not a CPU profile or exclusive-body measurement. OnUpdate modes/visibility/budget filters still govern actual dispatch. Frozen16-thread full-suite failure and isolated single-case inputs/conditions are not established equivalent; historical/root-cause/full-handoff acceptance remains open.

[Immediate-EOF symbolization control](../wiki/investigations/test-suite-performance.md#separate-immediate-eof-symbolization-control--2026-10-14) also fails its bounded deadline. It supplies no handler-cost attribution or performance-repair proof.


[Tagged symbolizer source](../wiki/investigations/test-suite-performance.md#upstream-tagged-symbolizer-source--2026-10-14) closes upstream source availability only, not installed equivalence or performance acceptance.

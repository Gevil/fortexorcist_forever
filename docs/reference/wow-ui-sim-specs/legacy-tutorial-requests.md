# Legacy tutorial requests

`TriggerTutorial` records legacy tutorial requests in environment-local simulator state. The native boundary lives in `src/lua_api/globals/real/tutorial_requests.rs`; [consumer evidence](../wiki/investigations/invented-query-defaults.md#legacy-tutorial-request-boundary) explains the bounded contract.

## What it must do

- [x] Publish only on Mists, Era, Anniversary and Wrath, whose pinned UI has selected legacy consumers.
- [x] Record each supplied numeric tutorial identifier in call order, including repeated requests, without sharing requests between environments.
- [x] Do not invent tutorial events, flag transitions, UI presentation or persistence. This is a call recorder, not complete native tutorial behavior.
- [x] Move the unchanged old Mists storage flow beyond the original `ContainerFrame_Shared.lua:976` call; report successor failures separately.

The consumers discard all results. Returning no Lua values is the bounded simulator contract, not a claim about unobserved native return arity.

## How it works

- [Pinned consumers and loading](../wiki/investigations/invented-query-defaults.md#legacy-tutorial-request-boundary)

## Implementation inventory

- `src/lua_api/globals/real/tutorial_requests.rs`: profile-gated native call recorder.
- `src/lua_api/globals/register.rs`: invokes registration.
- `src/lua_api/state/sim_state.rs`, `src/lua_api/state.rs`: empty per-environment `tutorial_requests` vector.

## Tests asserting this spec

- `tests/legacy_trigger_tutorial.rs`: publication, ordered repeated requests, environment isolation and no invented synchronous event dispatch.
- `tests/mists_bank_storage_panel.rs`: unchanged original bank/guild-bank storage flow.

## Known gaps (current cycle)

The four affected profiles pass request-history and publication tests. Their stock maps are byte-identical before/after (Mists 6/12; Era, Anniversary and Wrath 0/0). All seven all-target checks have zero compiler warnings.

The unchanged old storage-flow test still exits101: the Lua body now completes all assertions, but callback/startup errors fail the process-status check. Its next newly exposed boundary is missing `C_Engraving` at original `ContainerFrame_Shared.lua:315`. That successor is outside this lane; the later [engraving investigation](../wiki/investigations/mists-engraving-inputs.md#historical-bag-lane-proof) records its replacement by a named unsupplied-state error, not a passing storage flow.

## Out of scope

Native tutorial enablement, flags, event admission/forceShow policy, display, text, persistence, undocumented argument validation and unrelated successor API failures require evidence beyond the pinned call sites.

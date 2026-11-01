# Supplied container split and use requests

Status: producer `269ed6f17` replaces the passive scaffold; historical behavioral RED accepted. Bounded producer GREEN accepted from the sealed component receipts below. No native, full-profile, startup, format or type-check acceptance is implied.

Container splitting and accepted item-use requests share state across `C_Container` and legacy entry points. Backing behavior belongs in `src/c_api/container_inventory.rs`; passive eligibility and request records belong in `src/c_api/container_actions.rs`. See [inventory context](../wiki/systems/lua-api.md).

This is a **simulator-authored supplied-state policy**, not native parity. Public BankFrame callbacks establish split dispatch and HUDInventoryButton/ChatFrame establish use dispatch. They do not establish native validation, consumption, casting, cooldown, or event effects.

## What it must do

### Splitting

- [ ] A supplied five-item stack split by two retains three in its source and puts the same item ID/count two on the cursor, with source bag/slot origin. Unrelated stacks stay unchanged; dropping through existing pickup conserves the split quantity.
- [ ] `GetCursorInfo()` for an item returns `("item", itemID, stackCount)`. **The third count result is simulator-authored**, not a claim about native return positions. Other cursor kinds keep existing results.
- [ ] Zero, negative, fractional, non-number (including numeric-string), or amounts at least the source count are inert. Missing source and occupied cursor are inert. Positive controls prove that valid operations still mutate state.
- [ ] Namespaced and evidenced Wrath legacy calls use the same state transition. Finite integer bag, slot, and amount inputs are required; existing supplied bag keys are used without inventing native bank/capacity rules.

### Bounded use dispatch

- [ ] An occupied positive-count bag slot whose item ID is explicitly supplied in `container_actions.usable_items` appends one `{bag, slot, item_id}` to environment-local `use_requests` on each namespaced or legacy call.
- [ ] Unsupplied eligibility and empty slots append nothing. Requests neither consume/move the stack nor replace an existing cursor. A second environment starts without eligibility or requests.
- [ ] Eligibility is supplied simulator state, not an inference from item ID, quality, a native catalog, or callability. Supplied five-stack Hearthstone is deliberately synthetic; native stackability is not asserted.

## How it works

- [Lua API context](../wiki/systems/lua-api.md).
- [Existing cursor transfer contract](cursor-item-transfer.md).

## Implementation inventory

- `src/c_api/container_actions.rs` — passive eligibility/request types, installed with the tests-stage scaffold.
- `src/lua_api/state/sim_state.rs`, `src/lua_api/state.rs` — per-environment passive state and initialization.
- `src/c_api/mod.rs` — public fixture/model module.
- `src/c_api/container_inventory.rs` — shared split/use producers and namespaced publication.
- `src/lua_api/globals/inventory_verbs.rs` — shared legacy publication and item cursor-count projection.
- `src/lua_api/globals/stubs/global_stubs.rs` — generic legacy UseContainerItem no-op removed in the scaffold; producer registers the shared state-backed action in `inventory_verbs.rs`.
- `src/lua_api/workarounds/temporary/container_default_shapes.rs` — split/use no-op entries retired; [remaining workaround boundary](../wiki/systems/lua-api.md#remaining-container-default-shapes) owns the residual scope.

## Tests asserting this spec

`tests/container_split_use.rs` (auto-discovered grouped integration module):

- `b1_split_moves_supplied_quantity_and_reports_cursor_count`
- `b1_invalid_amounts_are_inert_then_valid_split_succeeds`
- `b1_occupied_cursor_and_missing_source_are_inert`
- `b3_namespaced_and_legacy_use_record_the_same_supplied_request_model`
- `b3_unsupplied_and_empty_use_are_inert_then_eligible_use_records`

## Bounded RED and post-GREEN receipts — 2026-10-16

Historical tests/passive scaffold: `680a35a1e`; producer: `269ed6f17`. The independent RED report authenticates production-input hashes despite the libraries' older recorded HEAD and documents the cfg-excluded Retail helper conversion difference; do not attribute producer behavior to the RED libraries.

- Retail RED component: `/home/osso/.local/state/wow-ui-sim/verification/green-batch/label-retail-red-20261016T194438112412Z`.
- Wrath RED component: `/home/osso/.local/state/wow-ui-sim/verification/green-batch/label-wrath-red-20261016T195708968486Z`.
- Independent RED acceptance: `/home/osso/.local/state/wow-ui-sim/verification/green-batch/label-red-report.md` (saved artifact/source reconciliation, not a fresh run).

**B1/B3 observed RED:** Retail 5 FAIL / 0 PASS; Wrath 5 FAIL / 0 PASS. Source stack stays `(6948,5)` instead of `(6948,3)`; use requests stay empty instead of recording the supplied request. Wrath loops fail at legacy first, so later namespaced calls are not independently reached by RED.

**Accepted bounded GREEN receipt:** Retail `/home/osso/.local/state/wow-ui-sim/handoff/label-producers-green-private/components/label-prod-retail-labels-20261016T210501464288Z`; Wrath `/home/osso/.local/state/wow-ui-sim/handoff/label-producers-green-private/components/label-prod-wrath-labels-20261016T211404318442Z`; independent reports `/home/osso/.local/state/wow-ui-sim/verification/label-producers-green/retail-report.md` and `/home/osso/.local/state/wow-ui-sim/verification/label-producers-green/wrath-report.md`. Those reports own executed identities/counts, assertion reachability, source/artifact identity and preservation scope. Retail cannot earn Wrath-only C11/legacy quest credit. Other profiles, ordinary startup, format/check and native parity remain separate gates.

## Known gaps (current cycle)

Wrath public legacy calls: `~/.cache/wow-ui-sim/blizzard-ui/wrath/FrameXML/BankFrame.lua:15` (`SplitContainerItem`) and `ChatFrame.lua:1005` (`UseContainerItem`). Retail/PTR/Mists/Forever cached consumers use `C_Container`; Era/Anniversary caches are absent, so no legacy-consumer conclusion is claimed for them. Wrath tests try legacy first so its inert baseline fails on state values; other profiles compile only namespaced cases. Historically, the scaffold moved `UseContainerItem` out of the generic no-op list and added passive Wrath split publication. Producer `269ed6f17` replaces both passive actions with the shared model; no duplicate publication is retained.

- [x] Behavioral RED accepted for the passive scaffold; exact reached boundaries are recorded above.
- [ ] Bounded GREEN/profile preservation is limited to the resolved receipts above; format/check/startup and other profiles require separate evidence.
- [ ] Use dispatch is observable only through supplied model state. No gameplay effect or public event is established by the inspected call sites; B3 gameplay compatibility remains unproven.

## Out of scope

Native effects, eligibility discovery, target argument behavior (including Wrath's optional target), bank transfer modes, combat/security gates, BAG_UPDATE/CURSOR_CHANGED timing, cooldowns, casting, healing, consumption, stack maxima, merging, richer cursor metadata, automatic ClearCursor return, and runtime reachability of cached public consumers. No vendor edits or reconstructed implementation evidence.

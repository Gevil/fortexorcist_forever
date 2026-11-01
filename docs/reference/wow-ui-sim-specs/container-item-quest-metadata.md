# Container item quest metadata

Status: producer `269ed6f17` replaces the passive scaffold; historical behavioral RED accepted. Bounded producer GREEN accepted from the sealed component receipts below. No native, full-profile, startup, format or type-check acceptance is implied.

Simulator-authored supplied-state policy for `C_Container.GetContainerItemQuestInfo`
and Wrath's legacy `GetContainerItemQuestInfo`. Public Blizzard UI consumers
motivate fields and return shapes; association lookup, invalid-slot policy and
membership authority below are simulator contracts, **not native-parity claims**.
Backing model: `src/c_api/container_quest.rs`.

## What it must do

- [ ] Host-supplied metadata keyed by item ID contains an independent quest-item
  boolean and optional quest ID. Query the item currently occupying the requested
  bag slot; replacement/removal cannot leave stale slot-based metadata.
- [ ] C_Container returns a fresh non-nil table with boolean `isQuestItem`, optional
  numeric `questID`, and boolean `isActive`. A quest flag without an ID remains true.
- [ ] `isActive` reflects membership of that quest ID in
  `SimState.quest_log_entries.entries`, including seeded active entries; completion
  history alone does not make an item active. Do not OR in the lightweight list.
- [ ] `ConfirmAcceptQuest` makes the next query active without changing supplied item metadata. Non-Wrath `SetAbandonQuest` removes active membership immediately; Wrath marking preserves it until `AbandonQuest` confirmation. The [Wrath abandon contract](wrath-quest-abandon.md) owns that confirmation boundary.
- [ ] Ordinary items without supplied metadata, empty slots, unknown bags, nonpositive
  slots and slots beyond supplied bag capacity return `(false, nil, false)` fields.
  The documentation specifies the table/field types but does **not** specify these
  edge-case values. These values are explicitly simulator-authored policy.
- [ ] On Wrath, the legacy global returns exactly three positional values:
  `isQuestItem, questId, isActive`, from the same backing model. No table wrapper.

## How it works

- [Lua API/state architecture](../wiki/systems/lua-api.md)
- [Admin quest verbs](../admin-api/quests.md)

## Implementation inventory

- `src/c_api/container_quest.rs` — passive supplied record and state-backed query.
- `src/c_api/mod.rs` — public backing-model module.
- `src/c_api/item_spell/c_container.rs` — C_Container registration hook.
- `src/lua_api/state/sim_state.rs`, `src/lua_api/state.rs` — host-facing map/default.
- `src/lua_api/globals/real/container_legacy.rs` — Wrath positional projection.
- `src/lua_api/workarounds/temporary/container_default_shapes.rs` — quest entry retired;
  [remaining workaround boundary](../wiki/systems/lua-api.md#remaining-container-default-shapes) owns residual no-state helpers.
- `src/lua_api/sim_substates/quest_log.rs`, `src/lua_api/globals/quest_verbs.rs` —
  existing membership authority and transitions; unchanged by this feature.

## Tests asserting this spec

`tests/container_item_quest_metadata.rs` (new top-level integration module):
supplied lifecycle, flag-only item, rich/history distinction, negative shapes,
slot identity, Wrath legacy lifecycle and legacy negative shapes.
`tests/bags.rs::test_bag_ui_c_container_helpers_have_safe_default_shapes`
remains unchanged as a no-supplied-metadata preservation test.

## Bounded RED and post-GREEN receipts — 2026-10-16

Historical tests/passive scaffold: `680a35a1e`; producer: `269ed6f17`. The independent RED report authenticates production-input hashes despite the libraries' older recorded HEAD and documents the cfg-excluded Retail helper conversion difference; do not attribute producer behavior to the RED libraries.

- Retail RED component: `/home/osso/.local/state/wow-ui-sim/verification/green-batch/label-retail-red-20261016T194438112412Z`.
- Wrath RED component: `/home/osso/.local/state/wow-ui-sim/verification/green-batch/label-wrath-red-20261016T195708968486Z`.
- Independent RED acceptance: `/home/osso/.local/state/wow-ui-sim/verification/green-batch/label-red-report.md` (saved artifact/source reconciliation, not a fresh run).

**B4 observed RED:** Retail 4 FAIL / 1 preservation PASS; Wrath 5 FAIL / 2 preservation PASS. Shared positive queries return `(false,nil,false)` instead of supplied metadata; Wrath positive legacy call has the required arity three but wrong values. Negative-shape passes are controls, not feature RED. Accept/abandon assertions after the first failure await GREEN.

**Accepted bounded GREEN receipt:** Retail `/home/osso/.local/state/wow-ui-sim/handoff/label-producers-green-private/components/label-prod-retail-labels-20261016T210501464288Z`; Wrath `/home/osso/.local/state/wow-ui-sim/handoff/label-producers-green-private/components/label-prod-wrath-labels-20261016T211404318442Z`; independent reports `/home/osso/.local/state/wow-ui-sim/verification/label-producers-green/retail-report.md` and `/home/osso/.local/state/wow-ui-sim/verification/label-producers-green/wrath-report.md`. Those reports own executed identities/counts, assertion reachability, source/artifact identity and preservation scope. Retail cannot earn Wrath-only C11/legacy quest credit. Other profiles, ordinary startup, format/check and native parity remain separate gates.

## Known gaps (current cycle)

- [x] Behavioral RED accepted on the passive scaffold; passive legacy arity/value and negative controls are distinguished above.
- [ ] Focused GREEN and default-shape preservation are bounded by the resolved receipts above; broader profile acceptance remains open.
- [ ] Run format/check and startup gates through the integrating session.

## Out of scope

Native item-to-quest catalogue discovery, quest acceptance on item use, new admin
Lua verbs, visual marker rendering/reachability, secret-argument/error parity,
legacy publication beyond directly evidenced Wrath, Cataclysm.

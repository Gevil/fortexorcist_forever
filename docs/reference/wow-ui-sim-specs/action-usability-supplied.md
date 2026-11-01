# Supplied spell-action usability

Integration checkpoint (2026-10-16): spell kind explicitly approved; Retail/Wrath behavioral RED → GREEN and preservation observed. See [bounded proof](../baselines/approved-batch-2026-10-16.md); no native-parity claim.

G3 supplies usability for existing spell actions to the namespace query and public button consumer. State belongs to `src/c_api/action_usability.rs`; see [Lua API architecture](../lua-api.md). This is a simulator contract, not a native resource-rule claim.

## What it must do

- [ ] Accept explicit usable, insufficient-power and other-unusable classifications keyed by spell ID. Missing input means usable for an occupied spell action, preserving the current baseline.
- [ ] Return `(true,false)`, `(false,true)` and `(false,false)` respectively through `C_ActionBar.IsUsableAction` and the Wrath legacy query / Retail deprecated wrapper.
- [ ] Drive the original cached Wrath `ActionButton_OnEvent` usability branch to white `(1,1,1)`, blue `(0.5,0.5,1)` and gray `(0.4,0.4,0.4)` icon colors. Normal texture is white except in the blue branch. Returning to usable restores white.
- [ ] Resolve supplied inputs through the current spell binding: duplicate bindings share classification; a different spell does not inherit it; an empty slot returns `(false,false)` despite retained spell input.
- [ ] Preserve existing macro/outfit occupancy behavior; do not infer their usability from spell inputs.

## How it works

- [Lua API architecture](../lua-api.md)

## Implementation inventory

- `src/c_api/action_usability.rs` — supplied classification and query projection.
- `src/lua_api/state/sim_state.rs`, `src/lua_api/state.rs` — input storage / empty initialization.
- `src/lua_api/globals/action_bar_api.rs` — namespace query registration import.
- `src/wrath/compat_bootstrap.lua` — legacy query delegation.

## Tests asserting this spec

- `tests/action_usability_supplied.rs` — full cached Wrath file, actual textures, original event consumer; Retail additionally loads its complete deprecated wrapper.
- `tests/action_usability_modern_supplied.rs` — active Retail/PTR/Mists/Forever shared ActionButton file and SharedXMLBase closure; unchanged modern mixin query refresh and `ACTION_USABLE_CHANGED` watcher, Rust-supplied spell state, passive supply, per-slot routing, rebind and empty-slot colors. Explicit host event delivery, not automatic notifications. See bounded proof below.

## Known gaps (current cycle)

- [x] Both original Retail/Wrath cases compiled and reached original color assertions before producer; both became GREEN after producer. Modern shared-mixin proof is recorded below; full ActionBar/template/router startup and native parity remain unproved.
- [ ] Macro/outfit checks preserve occupancy-query/color behavior only, not action execution or broader action-kind acceptance.

## Modern consumer bounded proof

Test revision `c5f96b724f11cf299e74b87d5327c7bf69ee26e6`, based on master `46afa7fc4`: both modern G3 tests were already GREEN. This is missing-proof coverage only, not a simulator behavior change. No production or Blizzard/vendor source changed.

| Profile | Modern G3 | Preserved existing cases |
|---|---|---|
| Retail | 2/2 | 3 G2 + 2 Wrath-consumer/deprecated-wrapper G3 |
| PTR | 2/2 | 3 G2 |
| Mists | 2/2 | 4 G2, including applicable legacy projection |
| Forever | 2/2 | 3 G2 |

All 23 selected profile/test pairs passed through the tracked `integration` target with `--no-default-features --features sound,gui,casc,client-<profile>`, `-j1`, serial execution and a 9 GiB systemd limit. Legacy G2 early returns outside Mists were excluded, not counted. The first Retail warm-cache attempt selected zero tests because its generated harness retained another checkout's absolute paths; it carries no behavioral credit. Regenerating only the dev harness cache produced the passing tracked run. No extracted/reconstructed consumer, external component acceptance, gameplay policy or automatic-event claim.

Private command/output/artifact-feature records, CVar before/after guards and exact pass names: `/home/osso/.local/state/wow-ui-sim/handoff/g3-retail-actionbutton/`. Proof is bounded to unchanged query-refresh and watcher methods on native widgets, not full addon startup, native resource rules or GPU pixels.

## Combined-tree acceptance

Combined revision `0636c88ffd4d3f1c77c761d2723ec2270f458596`, tree `415f988e92d274493fc02ee783c44b25b54eee5b`, rebased onto master `f452d5a4b` (including the global Slider quantization fix): the exact tracked `integration` selections passed again, sequentially in reusable slot-1.

| Profile | Named PASS | Selection |
|---|---|---|
| Retail | 7 | 2 modern G3 + 3 G2 + 2 legacy/deprecated G3 |
| PTR | 5 | 2 modern G3 + 3 G2 |
| Mists | 6 | 2 modern G3 + 4 G2, including legacy projection |
| Forever | 5 | 2 modern G3 + 3 G2 |

All 23 profile/test pairs ran on that combined revision with `--locked -j1 --no-default-features --features sound,gui,casc,client-<profile>`, serial libtest execution and `MemoryMax=9G`. Non-Mists selections skipped the early-return legacy projection. Every run reported zero failed/ignored/measured tests and emitted the matching profile's integration artifact; the generated harness selected this worktree's sources. No zero-selection run or cache invalidation was needed. Original CVar stat/hash remained unchanged around every isolated byte-exact copy, including the check run. Mists/Forever retain the pre-existing UnitRole dead-code warning; Retail/PTR and default check emitted no compiler warnings.

`cargo fmt --all -- --check` and default-feature `cargo check --locked -j1` both passed on the same combined revision. These gates cover the tracked selections and default compilation, not a full suite or additional profile acceptance. The following documentation-only receipt preserves their source scope. Exact commands, named tests, compiler artifacts, harness snapshots and CVar guards: `/home/osso/.local/state/wow-ui-sim/handoff/g3-combined-rerun/`; owning ledger: `/home/osso/.local/state/wow-ui-sim/handoff/g3-retail-actionbutton/proof-ledger.json`.

## Out of scope

Resource/range/cooldown calculations, casting eligibility/enforcement, automatic notifications, attack/repeat state (G1/G2), UseAction dispatch (G4), vendor edits, native parity and broader profile acceptance. Host supplies state; the fixture explicitly delivers the public usability event.

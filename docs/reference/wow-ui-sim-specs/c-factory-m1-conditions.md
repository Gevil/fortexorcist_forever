# Explicit startup conditions after C namespace factory removal

M1 restores only original-consumer conditions exposed by [factory removal](c-namespace-nil-members.md). The named defaults live in `src/lua_api/workarounds/temporary/startup_condition_capability_defaults.rs`; [implementation notes](../wiki/systems/c-factory-startup-followup.md) distinguish placeholders from modeled policy.

## What it must do

- [x] `C_PaperDollInfo.IsRangedSlotShown()` returns one nonnil boolean on Retail, PTR, Mists, Era, Anniversary and Forever, matching their generated documentation.
- [x] `C_GameRules.IsHardcoreActive()` returns one nonnil boolean for the actual Mists/Era/Anniversary/Forever popup consumers; an arbitrary game-rule key must not be interpreted as native Hardcore policy.
- [x] Forever `C_DateAndTime.IsDayTime()` returns one nonnil boolean for the original Camelot diel consumer.
- [x] Each condition is a named temporary workaround, not native policy. Other unknown namespace members remain nil; Wrath startup remains empty. The fixed false implementation choice is described in the linked notes, not established as native behavior.

## How it works

- [Named conditions and missing backing systems](../wiki/systems/c-factory-startup-followup.md#m1-conditions)

## Implementation inventory

- `src/lua_api/workarounds/temporary/startup_condition_capability_defaults.rs` — raw-presence-guarded, profile-scoped conditions.
- `src/lua_api/workarounds/{mod.rs,temporary/mod.rs}` — bootstrap registration.
- `src/lua_api/workarounds/temporary/game_rules_namespace_fallback.rs` — preserves its unrelated unknown-member diagnostic test.

## Tests asserting this spec

- `tests/cfactory_m1_conditions.rs` — executes active-profile generated documentation and verifies the declared nonnil boolean contract plus unknown-member absence.

## Known gaps (current cycle)

[Bounded proof and residuals](../wiki/systems/c-factory-startup-followup.md#bounded-proof--2026-10-21) retain four historical pool-cascade rows per Retail/PTR without treating their old source-order hypothesis as a current IsRangedSlotShown failure. New members remain held outside the frozen F0 list.

## Out of scope

Native realm game-rules state, ranged-slot display capability state and an authoritative day/night clock are missing. These defaults must be retired individually when those systems exist. No native-policy inference, vendor edits or arbitrary member factory is authorized.

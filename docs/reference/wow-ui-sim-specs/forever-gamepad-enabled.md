# Forever gamepad-enabled capability

Forever `C_GamePad.IsEnabled()` projects the explicit `GamePadEnable` CVar stored by the simulator. The producer lives in `src/c_api/c_game_pad.rs`. [System notes](../wiki/systems/gamepad-mapped-state.md) describe the separate mapped-stick model and this capability's evidence boundary.

## What it must do

- [x] Publish only on Forever; return one ordinary boolean with no arguments, as declared by Forever 1.60.1.70532 `Blizzard_APIDocumentationGenerated/GamePadDocumentation.lua:222-229`.
- [x] Read the existing stored `GamePadEnable` CVar (`"1"` means enabled). Its existing default `"0"` means disabled in the simulator. This state projection is an explicit simulator policy, not proof of native CVar/device equivalence or native hardware detection.
- [x] Preserve independence from `SimState.gamepad_mapped_sticks`: enabled with no snapshot and disabled with nonzero sticks must both work; replacement and clearing must not change the capability.
- [x] Select the original Game-screen restricted addon and its secure `RestrictedEnvironment.lua`; authenticate the original scrubber and forwarding function, then observe disabled/enabled/disabled through `CallRestrictedClosure` and `IsGamePadEnabled`.
- [x] Preserve Retail and PTR raw publication: this lane must not add `C_GamePad.IsEnabled` to either profile, even when their stored CVar changes.

The supplied-state policy follows the explicit October 2026 decision to reuse an existing `GamePadEnable` CVar if present. `src/cvars.yaml` already declares default `"0"`. The pinned Forever Lua wrapper calls `C_GamePad.IsEnabled`; it does not establish the CVar relationship or a native default. No automatic device detection, stick inference, or separate capability flag is introduced.

## How it works

- [Mapped-state system and capability boundary](../wiki/systems/gamepad-mapped-state.md).
- [Consumer selection and RED requirements](../wiki/investigations/consumer-selection-and-red-proof.md).

## Implementation inventory

- `src/c_api/c_game_pad.rs` — bounded Forever namespace and capability projection.
- `src/c_api/mod.rs`, `src/c_api/registration.rs` — existing Forever feature publication boundary.
- `src/cvars.yaml`, `src/cvars.rs` — existing default and stored boolean input; unchanged by this lane.

## Tests asserting this spec

`tests/forever_gamepad_enabled.rs` contains one original restricted-wrapper transition selector for Forever and one raw publication negative selector executed separately on Retail and PTR. The Forever original-wrapper selector has executed RED at `00e3c265a` and GREEN at `5efd665d9` with identical test bytes. Retail/PTR exact raw-publication controls also pass.

## Known gaps (current cycle)

- [x] Original-consumer RED/GREEN and profile controls pass; stock maps are unchanged (Forever 26/26, Retail 16/18, PTR 296/410 keys/occurrences). All-target checks pass on all three profiles; Retail has zero warnings, PTR/Forever retain only the three approved pre-existing fast-handler dead-code warnings.

## Out of scope

Native enablement detection/default, hardware and hotplug lifecycle, device enumeration, enablement events, temporary-CVar behavior, the deferred Gamepad SetTempCVar test, module import initialization, and promotion to other profiles. Native evidence must settle these separately.

# Forever combat-audio pulse enums

Forever 1.60.1.69913 publishes the pulse-health enumeration described by its cached `Blizzard_APIDocumentationGenerated/CombatAudioAlertSharedDocumentation.lua`.

## What it must do

- [x] Publish `Enum.CombatAudioAlertPulsePercentValues`: `Off=0`, then `Under90Percent=1` through `Under10Percent=9`.
- [x] Publish corresponding `Meta`: `MinValue=0`, `MaxValue=9`, `NumValues=10`.
- [x] Allow the actual `TextToSpeechCommands.lua` pulse-health command block to register range 0–9, accept each integer in that range, and reject -1, 10, and nonnumeric input without changing the CVar.
- [x] Publish these same documented values for Retail 12.1.5+ and Forever; preserve earlier Retail epochs without enabling a Retail epoch on Forever.

## How it works

- [Lua API](../lua-api.md)

## Implementation inventory

- `src/lua_api/globals/enum_data/forever_shared.rs`: exact-build values.
- `src/lua_api/env_init/enums.rs`: shared pulse-only registration, gated once by Retail 12.1.5+ or Forever.

## Tests asserting this spec

- `tests/c_api_surface.rs`: generated-documentation equality and actual vendor command-block execution in the existing grouped integration target.

## Retail 70448 consumer

Retail 12.1.5.70448 `CombatAudioAlertSharedDocumentation.lua:147–163` publishes the same ten values. Original `Blizzard_ChatFrame/Shared/TextToSpeechCommands.lua:814` consumes their metadata during startup. The initial Retail regression fails on the missing metadata; the startup inventory records this root separately from UnitFrameUtil and event-registration failures.

## Known gaps (current cycle)

- [ ] Full TextToSpeechCommands startup and other-profile runtime isolation remain integration verification obligations.

## Out of scope

Native conformance, audio playback, other combat-audio enums, and changes to the Retail epoch bundle itself. The command test substitutes surrounding slash-command registration and label helpers; it does not establish complete addon loading.

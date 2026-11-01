# T6 explicit startup service inputs

T6 restores named original-consumer service inputs after [factory removal](c-namespace-nil-members.md), with the original Forever timer family now [attributed to its defensive classification query](c-namespace-nil-members.md#forever-original-opaque-timer-pair--2026-10-22). [Implementation notes](../wiki/systems/c-factory-startup-followup.md#t6-service-inputs) distinguish real existing state from unavailable service capabilities.

## What it must do

### State adapters

- [x] Retail/PTR `C_Log.LogErrorMessage(message)` uses the existing simulator console sink.
- [x] Era/Anniversary `C_VoiceChat.IsSpeakForMeActive()` exposes the independent supplied activity flag, including a supplied true value.

### Named service gaps

- [x] All six non-Wrath profiles' chat-type TTS preference queries return false until per-chat-type preference storage exists.
- [x] Retail/PTR/Forever voice-login and collectable-source tracking queries return nonnil booleans through named temporary workarounds; channels/connection status are not authentication evidence.
- [x] Retail/PTR secure combat-filter reset returns no values while no secure filter backend exists, independent of ordinary combat-log filters.
- [x] Era/Anniversary corpse-map position remains absent until map-keyed corpse coordinates exist; player coordinates must not substitute.
- [x] Forever's original preferred-locale dropdown completes without a catalog; Discord voice/provider queries return boolean/numeric shapes. Each names its missing backing system; fixed defaults are not native service-policy claims.

### Preservation

- [x] Unknown members remain nil and Wrath startup stays empty.

## How it works

- [Service capability gaps and existing activity/sink adapters](../wiki/systems/c-factory-startup-followup.md#t6-service-inputs)

## Implementation inventory

- `src/c_api/registration.rs` — existing log sink publication for actual Retail/PTR consumers.
- `src/c_api/c_voice_chat_activity.rs` — existing supplied activity also published for documented Era/Anniversary consumers.
- `src/lua_api/workarounds/temporary/startup_service_capability_defaults.rs` — individually named and profile-scoped missing service systems.
- `src/lua_api/workarounds/{mod.rs,temporary/mod.rs}` — non-Wrath bootstrap registration.

## Tests asserting this spec

- `tests/cfactory_t6_services.rs` — generated documentation contracts, concrete console/activity state and complete original preferred-locale dropdown consumer.

## Known gaps (current cycle)

[Bounded proof and residuals](../wiki/systems/c-factory-startup-followup.md#bounded-proof--2026-10-21) record the completed original-member matrix, not clean startup.

- [x] Identify Forever's original opaque pair and publish the existing defensive classification model; [owning contract](c-namespace-nil-members.md#forever-original-opaque-timer-pair--2026-10-22) records attribution and verification status.
- [ ] Mists, Era and Anniversary opaque rows retain null attribution; Forever's identification is not proof of other profiles' callees.
- [ ] Newly exposed AddEventFilter, MarkCharacterSettingsSaved and GetPreferredDatacenterLocalities remain held outside the frozen F0 member list.

## Out of scope

Wrath changes, invented timer attribution, native authentication/provider selection, service entitlement policy, corpse coordinates, preferred-locale catalogs and per-chat-type preference storage. No generic function fabrication or vendor changes.

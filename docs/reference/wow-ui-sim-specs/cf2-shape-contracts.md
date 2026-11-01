# CF2 shape-only contracts

`tests/cf2_*_shape_contract.rs` checks documented shapes with runtime-selected original Blizzard consumers. User decision 2026-10-23: **native semantics remain unknown**. Shape-compatible constants/empty tables are preservation, never semantic RED or producer acceptance. All cases are authored only; no compilation or execution is claimed.

## What it must do

Every case must assert documented arity/types/nullability and applicable enum membership, invoke the unchanged selected consumer without a new Lua error, and register on every profile with both a generated declaration and a runtime-selected original consumer. TOC AllowLoad/AllowLoadGameType/ExcludeLoadGameType restrictions and selected Family/Game paths determine applicability; cached source alone does not. Missing members are source-predicted shape blockers, not observed failures. Existing loader errors are retained; new consumer errors fail the case.

### social: `original_navigation_squelch_shape_blocker`

- [ ] Profiles: retail, ptr, mists. No arguments → exactly one non-nil boolean. No silence mapping or button-state expectation.
- Native behavior/defaults/lifecycle: **unknown**; no semantic values asserted.
- Original consumer: `Blizzard_GroupFinder/Mainline/LFGList.lua:189 (retail/ptr); Classic/LFGList.lua:94 (mists)`.
- Forever excluded despite its declaration: `Blizzard_GroupFinder/Blizzard_GroupFinder.toc:10` has `ExcludeLoadGameType: camelot`; `src/toc/mod.rs:64-76,481-483` makes that exclusion active. Its cached Mainline LFGList is not runtime-selected. This corrects the earlier requested Forever registration.
- Documentation: retail: `Blizzard_APIDocumentationGenerated/SocialRestrictionsDocumentation.lua:96 (IsSquelched)`; ptr: `Blizzard_APIDocumentationGenerated/SocialRestrictionsDocumentation.lua:71 (IsSquelched)`; mists: `Blizzard_APIDocumentationGenerated/SocialRestrictionsDocumentation.lua:62 (IsSquelched)`.
- Unexecuted prediction: **FAIL** — IsSquelched missing; only boolean shape, no button state.

### social: `original_lfr_visibility_shape_blocker`

- [ ] Profiles: mists. No arguments → exactly one non-nil boolean. No eligibility/visibility expectation.
- Native behavior/defaults/lifecycle: **unknown**; no semantic values asserted.
- Original consumer: `Blizzard_GroupFinder/Classic/PVEFrame.lua:229`.
- Documentation: mists: `Blizzard_APIDocumentationGenerated/LFGInfoDocumentation.lua:179 (IsLFREnabled)`.
- Unexecuted prediction: **FAIL** — IsLFREnabled missing; no visibility or eligibility policy.

### social: `original_microbutton_invitation_records_shape_blocker`

- [ ] Profiles: retail, ptr, wowforever, mists, era, anniversary. No arguments → exactly one non-nil table; recursively validate actual ClubSelfInvitationInfo, ClubInfo and ClubMemberInfo records, nullable fields and enum membership. No nonempty-list requirement. Opaque IDs: documented non-nullability only. `favoriteTimeStamp` and `joinTime` are nullable `BigUInteger`; Lua primitive representation is **native-unknown**. Assert only documented nullability, never number/string representation (`ClubDocumentation.lua:1772-1773` retail/ptr/wowforever; `:1674-1675` mists/era/anniversary).
- Native behavior/defaults/lifecycle: **unknown**; no semantic values asserted.
- Original consumer: `Blizzard_MicroMenu/Mainline/MainMenuBarMicroButtons.lua:1230 (retail/ptr), :1386 (wowforever); Classic/MainMenuBarMicroButtons.lua:520 (mists/era/anniversary)`.
- Documentation: retail/ptr/wowforever: `Blizzard_APIDocumentationGenerated/ClubDocumentation.lua:580 (GetInvitationsForSelf)`; retail/ptr/wowforever: `Blizzard_APIDocumentationGenerated/ClubDocumentation.lua:1938 (ClubSelfInvitationInfo)`; retail/ptr/wowforever: `Blizzard_APIDocumentationGenerated/ClubDocumentation.lua:1760 (ClubInfo)`; retail/ptr/wowforever: `Blizzard_APIDocumentationGenerated/ClubDocumentation.lua:1808 (ClubMemberInfo)`; mists/era/anniversary: `Blizzard_APIDocumentationGenerated/ClubDocumentation.lua:545 (GetInvitationsForSelf)`; mists/era/anniversary: `Blizzard_APIDocumentationGenerated/ClubDocumentation.lua:1839 (ClubSelfInvitationInfo)`; mists/era/anniversary: `Blizzard_APIDocumentationGenerated/ClubDocumentation.lua:1662 (ClubInfo)`; mists/era/anniversary: `Blizzard_APIDocumentationGenerated/ClubDocumentation.lua:1710 (ClubMemberInfo)`.
- Unexecuted prediction: **FAIL** — GetInvitationsForSelf missing; recursive actual records, empty list allowed.

### combataura: `original_group_buff_records_shape_blocker`

- [ ] Profiles: retail, ptr, wowforever. Getter: no arguments → exactly one non-nil table; actual entries require numeric spellID and VisualAlertType visualValue. Assert exact ten enum names/values 1–10. Setter auxiliary: actual record table → no returns. No setter/event timing expectation or synthetic changed payload.
- Native behavior/defaults/lifecycle: **unknown**; no semantic values asserted.
- Original consumer: `Blizzard_FrameXMLUtil/AuraUtil.lua:704`.
- Selection: retail/ptr `Blizzard_FrameXMLUtil/Blizzard_FrameXMLUtil.toc:5,15` allows Game and loads AuraUtil.lua without game-type exclusion.
- Documentation: retail/ptr use the same record and enum schemas cited below; retail getter/setter `UnitAuraDocumentation.lua:377/555`, ptr `:376/533`. wowforever: `Blizzard_APIDocumentationGenerated/UnitAuraDocumentation.lua:377 (GetGroupBuffVisualAlerts)`; wowforever: `Blizzard_APIDocumentationGenerated/UnitAuraDocumentation.lua:555 (SetGroupBuffVisualAlerts)`; wowforever: `Blizzard_APIDocumentationGenerated/UnitConstantsDocumentation.lua:23 (GroupBuffVisualAlertInfo)`; wowforever: `Blizzard_APIDocumentationGenerated/VisualAlertConstantsDocumentation.lua:6 (VisualAlertType)`.
- Unexecuted prediction: retail/ptr **PASS** — existing table getter and void setter are shape-compatible preservation, not native semantics. Forever **FAIL** — getter and setter missing. Actual records only, exact enum, no required list contents.

### pvpmap: `original_match_enter_world_shape_blocker`

- [ ] Profiles: retail, ptr, wowforever. No arguments → exactly one non-nil boolean. Inactive match is a fixture input so the original OR expression reaches completion; no transition/subscription result asserted.
- Native behavior/defaults/lifecycle: **unknown**; no semantic values asserted.
- Original consumer: `Blizzard_PVPMatch/PVPMatchResults.lua:201`.
- Selection: Forever `Blizzard_PVPMatch/Blizzard_PVPMatch.toc:4,7` allows camelot and loads PVPMatchResults.xml; XML `:3` loads PVPMatchResults.lua. No TOC game-type exclusion.
- Documentation: retail/wowforever: `Blizzard_APIDocumentationGenerated/PvpInfoDocumentation.lua:987 (IsMatchComplete)`; ptr: `Blizzard_APIDocumentationGenerated/PvpInfoDocumentation.lua:946 (IsMatchComplete)`.
- Unexecuted prediction: **FAIL** — IsMatchComplete missing; boolean and original event acceptance only.

### pvpmap: `original_vehicle_provider_shape_blocker`

- [ ] Profiles: retail, ptr, wowforever, mists, era, anniversary. Numeric map ID → zero returns OR exactly one non-nil table. Validate all actual records: x/y/facing/textureWidth/textureHeight numbers, name/atlas strings, four boolean flags. Indexed query uses actual index/map ID and likewise permits zero returns. Original pin calls only when an indexed record exists; no count/order/lifetime expectation.
- Native behavior/defaults/lifecycle: **unknown**; no semantic values asserted.
- Original consumer: `Blizzard_SharedMapDataProviders/VehicleDataProvider.lua:31,58,76`.
- Selection: retail/ptr/wowforever WorldMap_Mainline.toc `:3` requires SharedMapDataProviders; selected SharedMapDataProviders_Mainline.toc `:5-6,26` allows Game/mainline and includes VehicleDataProvider.xml. Era/anniversary WorldMap_Vanilla.toc `:3,5-6` requires that provider and allows Game/vanilla; SharedMapDataProviders_Classic.toc `:5-6,21` allows Game/vanilla and includes the same XML. No added root/provider TOC excludes the active game type. XML `:3` loads the unchanged provider. Both queries are MayReturnNothing with identical record fields in every registered profile.
- Documentation: `Blizzard_APIDocumentationGenerated/PvpInfoDocumentation.lua` (list getter/indexed getter/record): retail `:300/283/1660`, ptr `:281/264/1619`, wowforever `:300/283/1670`, era/anniversary `:96/80/769`. mists: `Blizzard_APIDocumentationGenerated/PvpInfoDocumentation.lua:87 (GetBattlefieldVehicles)`; mists: `Blizzard_APIDocumentationGenerated/PvpInfoDocumentation.lua:71 (GetBattlefieldVehicleInfo)`; mists: `Blizzard_APIDocumentationGenerated/PvpInfoDocumentation.lua:760 (BattlefieldVehicleInfo)`.
- Unexecuted prediction: **FAIL** — vehicle getters missing; optional table or zero returns, actual records only.

### housing: `original_supertracking_pair_shape_blocker`

- [ ] Profiles: retail, ptr, wowforever. No arguments → zero returns OR exactly two non-nil values (ContentTrackingType, number). Exact enum Appearance=0/Mount=1/Achievement=2/Decor=3. Original passthrough query and cache event handler accept actual output. No fabricated content ID or setter/clear policy.
- Native behavior/defaults/lifecycle: **unknown**; no semantic values asserted.
- Original consumer: `Blizzard_FrameXMLUtil/Mainline/Blizzard_QuestSuperTracking.lua:52,107`.
- Documentation: retail/ptr/wowforever: `Blizzard_APIDocumentationGenerated/SuperTrackManagerDocumentation.lua:32 (GetSuperTrackedContent)`; retail/ptr/wowforever: `Blizzard_APIDocumentationGenerated/ContentTrackingTypesDocumentation.lua:60 (ContentTrackingType)`.
- Unexecuted prediction: **FAIL** — GetSuperTrackedContent missing; optional enum-number pair, no demanded content ID.

### housing: `original_minimap_housing_predicates_shape_blocker`

- [ ] Profiles: retail, ptr, wowforever. No arguments → exactly one non-nil boolean for IsInsideHouse and five documented sibling predicates. Original minimap consumes IsInsideHouse; siblings are auxiliary shape checks, not claimed minimap callees. No atlas/visibility or owned/visitor mapping expectation.
- Native behavior/defaults/lifecycle: **unknown**; no semantic values asserted.
- Original consumer: `Blizzard_Minimap/Mainline/Minimap.lua:295 (retail/ptr), :262 (wowforever)`.
- Documentation: retail/ptr/wowforever: `Blizzard_APIDocumentationGenerated/HousingUIDocumentation.lua:307 (IsInsideHouse)`; retail/ptr/wowforever: `Blizzard_APIDocumentationGenerated/HousingUIDocumentation.lua:352 (IsInsidePlot)`; retail/ptr/wowforever: `Blizzard_APIDocumentationGenerated/HousingUIDocumentation.lua:325 (IsInsideOwnedHouse)`; retail/ptr/wowforever: `Blizzard_APIDocumentationGenerated/HousingUIDocumentation.lua:343 (IsInsideOwnedPlot)`; retail/ptr/wowforever: `Blizzard_APIDocumentationGenerated/HousingUIDocumentation.lua:316 (IsInsideHouseOrPlot)`; retail/ptr/wowforever: `Blizzard_APIDocumentationGenerated/HousingUIDocumentation.lua:334 (IsInsideOwnedHouseOrPlot)`.
- Unexecuted prediction: **FAIL** — IsInsideHouse missing; boolean predicates, original minimap accepts general interior result.

### forever: `original_ping_manager_shape_blocker`

- [ ] Profiles: retail, ptr, wowforever. No arguments → exactly one non-nil boolean; original manager OnLoad accepts it. No options count, availability or CVar alias expectation.
- Native behavior/defaults/lifecycle: **unknown**; no semantic values asserted.
- Original consumer: `Blizzard_CompactRaidFrames/Mainline/Blizzard_CompactRaidFrameManager.lua:163`.
- Selection: retail/ptr `Blizzard_CompactRaidFrames/Blizzard_CompactRaidFrames.toc:6` loads `[Family]` manager, selected Mainline by `src/toc/mod.rs:227-235`; no AllowLoad or game-type exclusion. Explicit root Blizzard_Menu.toc `:5` allows Both with no game-type restriction.
- Documentation: retail/ptr/wowforever: `Blizzard_APIDocumentationGenerated/PingManagerDocumentation.lua:44 (IsPingSystemEnabled)`.
- Unexecuted prediction: **FAIL** — IsPingSystemEnabled missing; no availability, option-count or CVar mapping.

### forever: `original_camelot_equipment_predicates_shape_blocker`

- [ ] Profiles: wowforever. AmmoNeeded and IsRangedSlotShown: no arguments → exactly one non-nil boolean each. Original slot OnLoad accepts them; no visibility/weapon/class policy. Ranged getter is already shape-compatible inside this combined blocker.
- Native behavior/defaults/lifecycle: **unknown**; no semantic values asserted.
- Original consumer: `Blizzard_UIPanels_Game/Camelot/PaperDollFrame.lua:1899,1918`.
- Documentation: wowforever: `Blizzard_APIDocumentationGenerated/PaperDollInfoDocumentation.lua:11 (AmmoNeeded)`; wowforever: `Blizzard_APIDocumentationGenerated/PaperDollInfoDocumentation.lua:258 (IsRangedSlotShown)`.
- Unexecuted prediction: **FAIL** — AmmoNeeded missing; ranged boolean already shape-compatible, no visibility assertions.

### forever: `original_bank_purchase_shape_blocker`

- [ ] Profiles: wowforever. Character/Account BankType input → exactly one non-nil boolean eligibility, number count and table of actual BankTabData. Validate record fields and BankType membership. Exact BankType Character=0/Guild=1/Account=2; no operational Guild-bank claim or required count/eligibility.
- Native behavior/defaults/lifecycle: **unknown**; no semantic values asserted.
- Original consumer: `Blizzard_UIPanels_Game/Mainline/BankFrameTemplates.lua:937,969,1009; Camelot/BankFrame.lua:43`.
- Documentation: wowforever: `Blizzard_APIDocumentationGenerated/BankDocumentation.lua:61 (CanPurchaseBankTab)`; wowforever: `Blizzard_APIDocumentationGenerated/BankDocumentation.lua:226 (FetchNumPurchasedBankTabs)`; wowforever: `Blizzard_APIDocumentationGenerated/BankDocumentation.lua:241 (FetchPurchasedBankTabData)`; wowforever: `Blizzard_APIDocumentationGenerated/BankDocumentation.lua:440 (BankTabData)`; wowforever: `Blizzard_APIDocumentationGenerated/ItemConstantsDocumentation.lua:17 (BankType)`.
- Unexecuted prediction: **FAIL** — CanPurchaseBankTab missing; boolean, count and actual tab records, no eligibility/count expectations.

### forever: `original_target_spell_context_shape_blocker`

- [ ] Profiles: wowforever. No arguments → exactly one non-nil number. Original ItemButtonUtil.GetItemContext runs with earlier real context frames hidden; no target sentinel, FeedPet/nil branch or cast mapping asserted.
- Native behavior/defaults/lifecycle: **unknown**; no semantic values asserted.
- Original consumer: `Blizzard_FrameXMLUtil/ItemUtil.lua:108`.
- Documentation: wowforever: `Blizzard_APIDocumentationGenerated/SpellDocumentation.lua:631 (GetTargetSpellID)`.
- Unexecuted prediction: **FAIL** — GetTargetSpellID missing; numeric result only, no no-target sentinel or context outcome.

### petbattle: `original_pet_display_name_pair_shape_blocker`

- [ ] Profiles: retail, ptr, wowforever, mists. BattlePetOwner and numeric slot → zero returns OR exactly two non-nil strings. Exact owner enum Weather=0/Ally=1/Enemy=2; use only supplied valid Ally slot. No absent/invalid/inactive result or fallback name expectation.
- Native behavior/defaults/lifecycle: **unknown**; no semantic values asserted.
- Original consumer: `Blizzard_PetBattleUI/Shared/Blizzard_PetBattleUI.lua:1055 (retail/ptr/wowforever), :1063 (mists)`.
- Documentation: retail/ptr/wowforever: `Blizzard_APIDocumentationGenerated/PetBattlesDocumentation.lua:44 (GetName)`; retail/ptr/wowforever/mists: `Blizzard_APIDocumentationGenerated/BattlePetConstantsDocumentation.lua:37 (BattlePetOwner)`; mists: `Blizzard_APIDocumentationGenerated/PetBattlesDocumentation.lua:42 (GetName)`.
- Unexecuted prediction: **FAIL** — GetName missing; optional two strings and original display acceptance, no fallback names.

### tts: `original_tts_numeric_preferences_contract`

- [ ] Profiles: retail, ptr, wowforever, mists, era, anniversary. Rate/volume getters: no arguments → exactly one non-nil number; setters accept a number and return nothing. Original sliders consume actual getters and call original setters. No ranges/defaults, round-trip values, save ownership or persistence asserted.
- Native behavior/defaults/lifecycle: **unknown**; no semantic values asserted.
- Original consumer: `Blizzard_ChatFrame/Shared/TextToSpeechFrame.lua:269,680,698 (retail/wowforever); :266,677,695 (ptr/mists/era/anniversary)`.
- Documentation: retail/ptr/wowforever: `Blizzard_APIDocumentationGenerated/TTSSettingsDocumentation.lua:65 (GetSpeechRate)`; retail/ptr/wowforever: `Blizzard_APIDocumentationGenerated/TTSSettingsDocumentation.lua:74 (GetSpeechVolume)`; retail/ptr/wowforever: `Blizzard_APIDocumentationGenerated/TTSSettingsDocumentation.lua:165 (SetSpeechRate)`; retail/ptr/wowforever: `Blizzard_APIDocumentationGenerated/TTSSettingsDocumentation.lua:175 (SetSpeechVolume)`; mists/era/anniversary: `Blizzard_APIDocumentationGenerated/TTSSettingsDocumentation.lua:62 (GetSpeechRate)`; mists/era/anniversary: `Blizzard_APIDocumentationGenerated/TTSSettingsDocumentation.lua:71 (GetSpeechVolume)`; mists/era/anniversary: `Blizzard_APIDocumentationGenerated/TTSSettingsDocumentation.lua:156 (SetSpeechRate)`; mists/era/anniversary: `Blizzard_APIDocumentationGenerated/TTSSettingsDocumentation.lua:165 (SetSpeechVolume)`.
- Unexecuted prediction: **PASS** — numeric getters and void setters already shape-compatible; original sliders only, no round-trip values.

### tts: `original_tts_saved_settings_shape_blocker`

- [ ] Profiles: retail, ptr, wowforever, mists, era, anniversary. Saved getter: no arguments → exactly one non-nil boolean; marker: no arguments → no returns. Keep these direct API assertions separate from the original-consumer sequence so a shape preflight cannot mask its first failure. No expected flag value, migration or persistence result.
- Native behavior/defaults/lifecycle: **unknown**; no semantic values asserted.
- Original consumer: `Blizzard_ChatFrame/Shared/TextToSpeechFrame.lua:469,475 (retail/wowforever); :466,472 (ptr/mists/era/anniversary)`.
- Documentation: retail/ptr/wowforever: `Blizzard_APIDocumentationGenerated/TTSSettingsDocumentation.lua:26 (GetCharacterSettingsSaved)`; retail/ptr/wowforever: `Blizzard_APIDocumentationGenerated/TTSSettingsDocumentation.lua:113 (MarkCharacterSettingsSaved)`; mists/era/anniversary: `Blizzard_APIDocumentationGenerated/TTSSettingsDocumentation.lua:25 (GetCharacterSettingsSaved)`; mists/era/anniversary: `Blizzard_APIDocumentationGenerated/TTSSettingsDocumentation.lua:108 (MarkCharacterSettingsSaved)`.
- Unexecuted prediction: **FAIL** — saved getter and marker missing; boolean and void calls, original CheckLoad accepts actual result.
- [ ] `original_tts_saved_settings_consumer_blocker` independently owns the existing provenance checks, supplied legacy settings and original OnEvent/CheckLoad sequence. Partition only; no new semantic assertions. Consumer execution remains unverified; this is not a constant/no-op-rejecting saved-state oracle.

### tts: `original_gamepad_temp_cvar_shape_blocker`

- [ ] Profiles: wowforever. SetTempCVar: non-nil name, nullable cstring value → no returns; RemoveTempCVar: non-nil name → no returns. Original Gamepad numeric-value coercion and mode callbacks, plus auxiliary nil-value call, use known public names. No overlay, event, invalid-name or persistence semantics.
- Native behavior/defaults/lifecycle: **unknown**; no semantic values asserted.
- Original consumer: `Blizzard_Gamepad/Core.lua:4,6 via Blizzard_SharedXML/InputUtil.lua transition listener`.
- Documentation: wowforever: `Blizzard_APIDocumentationGenerated/CVarDocumentation.lua:171 (SetTempCVar)`; wowforever: `Blizzard_APIDocumentationGenerated/CVarDocumentation.lua:114 (RemoveTempCVar)`.
- Unexecuted prediction: **FAIL** — temporary CVar members missing; nullable value and void calls through normal mode callbacks.

## How it works

- [Consumer selection and proof boundaries](../wiki/investigations/consumer-selection-and-red-proof.md).
- [Addon loading](../addon-loading-pipeline.md).

## Implementation inventory

- `tests/common/cf2_shape.rs`: shared shape assertions and profile-cache closure loading, no API replacement.
- `tests/cf2_*_shape_contract.rs`: seven lane modules; per-file union and narrower per-case compile-time gates.

## Tests asserting this spec

- `tests/cf2_social_shape_contract.rs`.
- `tests/cf2_combataura_shape_contract.rs`.
- `tests/cf2_pvpmap_shape_contract.rs`.
- `tests/cf2_housing_shape_contract.rs`.
- `tests/cf2_forever_shape_contract.rs`.
- `tests/cf2_petbattle_shape_contract.rs`.
- `tests/cf2_tts_shape_contract.rs`.

## Known gaps (current cycle)

- [ ] Compilation, original-consumer setup and all runtime results remain unverified under EDIT-ONLY authorization. A setup/provenance/other-callee failure is not proof of the predicted target gap.
- [ ] C1 retail/ptr: Blizzard_APIDocumentationGenerated/CombatLogSecureDocumentation.lua:102 declares ShouldShowCurrentEntry (no arguments → one non-nil boolean). Normal populated ingest/current-entry path is not established. No executable contract or passing count. AddEventFilter (:11) has no parameter schema; a forwarding-only call cannot replace the boolean subcheck. No private-history seed.
- [ ] Club IDs/member IDs/invitation IDs, Discord IDs and nullable BigUInteger favoriteTimeStamp/joinTime: generated declarations provide names/nullability, not an established Lua primitive mapping here. BigUInteger representation remains native-unknown. Validate non-nullability; do not invent a representation. Modern optional DiscordChatInfo recursively uses Blizzard_APIDocumentationGenerated/DiscordConstantsDocumentation.lua:42 and ClubDocumentation.lua:1843; older profiles have no Discord field declaration.
- [ ] Empty lists/MayReturnNothing validate only the observed shape. Populated records/indexed pins are conditional coverage, not claimed when absent. Mists PvpInfoDocumentation.lua:74 also marks the indexed query MayReturnNothing, correcting the earlier plan's nonoptional indexed-return wording.
- [ ] H1 setter/input validation and C2 changed-event lifecycle are not covered: no invented valid content IDs or fabricated getter/event linkage. TTS cases require sealed executables outside deps, fresh child-only copied XDG_DATA_HOME and original CVar stat/hash receipts; they do not assert persistence.

## Out of scope

Native defaults/state sources, filtering policy, transitions, mutation/event timing, eligibility, ownership, persistence and migration semantics remain unknown. No producer/vendor changes. F4 account locale/locality arrays have no generated declaration and receive no fabricated shape test. NEW stable/item-upgrade/store/equipment-set lanes are outside these seven requested lane groups. Inventory-flyout and profession-bag groups have no documented shape.

## TTS producer-stage amendment — 2026-10-24

The earlier TTS shape-only predictions and blanket no-producer statement are
historical. [Bounded TTS contract](c-factory-cf2-tts.md#edit-only-preference-producer-staging--2026-10-24)
now owns the source-backed preference model, independent two-value callback RED,
shape/CheckLoad partition, supplemental documented pairs and ASK-USER persistence
boundary. Existing selector names remain stable. Runtime results remain unverified;
this amendment does not extend any other lane's scope or native-parity claims.

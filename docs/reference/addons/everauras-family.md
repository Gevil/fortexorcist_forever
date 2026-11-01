# WeakAuras-family forks for WoW Forever: EverAuras, ForeverAuras, Musca-Auras

Research target: how the WeakAuras family survives the Forever secret/aura regime, and what of it
transfers to a self-drawn timeline bar.

All three repos were cloned and read from real source (shallow clones, HEAD dates below). Nothing
is inferred from marketing text; every claim carries a `file:line`, and the two CurseForge/web pages
are quoted only as claims, separately labelled.

| Addon | Repo | HEAD / version | Targets Forever? | Own aura-container code? |
| --- | --- | --- | --- | --- |
| **Musca Auras** | `github.com/dldvlpr-addons-wow/Musca-Auras` | `505aa86`, 2026-10-29, v5.22.0 | yes — `WeakAuras/WeakAuras.toc:1` `## Interface: 16001` | **yes, a 30-file `BlizzardAuraDisplay*` + `SecretAura*` module family** |
| **EverAuras** | `github.com/Hackblarvest/EverAuras` | `2fc6a6b`, 2026-10-29, v0.9.9-beta | yes (README: fork of M33kAuras "rebuilt for the *World of Warcraft: Forever* client") | **yes, one 8912-line `ForeverEngineAura.lua` + a dev-probe addon** |
| **ForeverAuras** | `github.com/Tulkas22/ForeverAuras` | 2026 clone, `## Interface: 16001` (`ForeverAuras/ForeverAuras.toc:1`) | yes (`:7` "Unofficial fork of WeakAuras for WoW Forever") | **NO — zero matches for `AuraContainer`/`CustomAuraContainerTemplate`/`AddAuraGroup`/`C_AuraContainerUtil` repo-wide** |
| M33kAuras (upstream of EverAuras) | `github.com/m33shoq/M33kAuras` | cloned as dependency | retail 12.x-era | no containers; supplies **duration-object** + **boolean-property** machinery |

Verdicts are per-addon because they are not the same addon any more: ForeverAuras is the oldest
branch (no secret regime handling), Musca and EverAuras independently built the same answer.

---

## Verdict

| Addon | Verdict |
| --- | --- |
| **Musca Auras** | **uses-game-aura-container** (primary), plus `reads-spell-state` (`C_Spell.GetSpellCooldown` readiness), plus `uses-native-alert` (`C_UnitAuras.AddAuraSound`), plus `uses-events-only` for a fallback trigger path that keeps a live timer on secret auras. |
| **EverAuras** | **uses-game-aura-container** (primary, by construction), plus `reads-spell-state` (`C_Spell.IsSpellInRange` as a readable gate), plus `uses-native-alert` (`AddAuraSound`), plus the engine-as-a-comparator trick (`SetAlphaFromBoolean`, `C_CurveUtil.EvaluateColorValueFromBoolean`, `UnitPowerPercent` + curves, engine-authored geometry widths). |
| **ForeverAuras** | **no-in-combat-support** in the clone. It reads aura payloads directly with no guards; its own README (`README.md:5`) says "Status: early development. Expect errors, especially in combat." The sibling Musca CHANGES.md is the record of what this fork's approach costs: "The `C_UnitAuras` calls of the restricted path … fail for addon code in combat ("Auras cannot be accessed when secret while tainted", confirmed in game for `GetAuraDuration` and `GetUnitAuraInstanceIDs`): stacks stay frozen, and a buff …" (`CHANGES.md:2106-2109`). |

The family's single load-bearing principle, stated in prose at `GUIDE.md:107`:
**"Put the display on secret data, and the logic on readable data."**

---

## API surface used

### A. Aura containers — the "let the game draw it" route

| API | where (file:line) | what for |
| --- | --- | --- |
| `CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")` | Musca `WeakAuras/SecretAuraFlow.lua:229`; Musca `SecretAuraFlowGrid.lua:235`; EverAuras `tools/forever_files/ForeverEngineAura.lua:2523`, `:2987`, `:5214`, `:6298`, `:7052`, `:7111` | the container itself. Musca hands it two templates and prefers `"CustomAuraContainerTemplate, DisableUntrustedLayoutScriptsTemplate"` (`SecretAuraFlow.lua:19-20`) — the second template is a deliberate lockdown of script execution on the game-owned frame |
| `pcall(CreateFrame, "AuraContainer", …)` wrapped, with fallback | Musca `SecretAuraFlow.lua:229-232` (returns `auraContainer, true`, else plain template + `false`); EverAuras `addons/ForeverDevInfo/ForeverDevInfo.lua:549-554` falls back to `CreateFrame("Frame", …, "CustomAuraContainerTemplate")` | the intrinsic type may be absent; probe, then degrade |
| `container:SetAuraProcessingPolicy(CustomAuraContainerAuraProcessingPolicy.None)` | Musca `BlizzardAuraDisplayInstances.lua:94`, `:163`, `:185`; `SecretAuraFlowGrid.lua:237`; `SecretAuraFlowShadow.lua:57`; EverAuras `ForeverEngineAura.lua` grid/slot paths | forces the game to stop classifying auras for the addon — the addon does not want the auras, only their drawing |
| `container:AddAuraGroup(key, filterString, {maxFrameCount, candidateFilters, sortMethod, sortDirection, initializeFrame})` | Musca `BlizzardAuraDisplayInstances.lua:165-169`; `SecretAuraFlowGrid.lua:298-301`; EverAuras `ForeverEngineAura.lua:2921-2925`, `:6431-6435`, `:7063-7067` | a group = a flow of game-drawn buttons. `maxFrameCount` caps the copies; `sortMethod = AuraContainerSortMethod.ExpirationOnly` makes the *game* sort by remaining time (EverAuras `:7066`; probe note `Probe_Sort.lua:3-4`: "the comparison runs inside Blizzard's own aura update, where the secret times may be compared") |
| `container:AddAuraSlot(key, filterString, {candidateFilters, initializeFrame})` | Musca `BlizzardAuraDisplayInstances.lua:96-98`; EverAuras `ForeverEngineAura.lua:2533-2535`, `:5557-5559`, `:616-620`(probe `Probe_Dyn.lua:212`) | a slot = one game-drawn button, the primary single-aura primitive |
| `container:SetAuraGroupFilterString` / `SetAuraGroupCandidateFilters` / `SetAuraGroupSortMethod` (+ `SetAuraSlot*` twins) | Musca `BlizzardAuraDisplayInstances.lua:186-188`; EverAuras `ForeverEngineAura.lua:2778-2779`, `:2966-2967`, `:5673-5675` | live retarget of an existing slot/group without recreating the container |
| `container:SetUnit(unitToken)` | Musca `SecretAuraFlowGrid.lua:238`; `SecretAuraSingleMissing.lua:178`; `SecretAuraAnchor.lua:178`; EverAuras `ForeverDevInfo.lua:584`, `Probe_Late.lua:262` | **the binding that answers the injection question** (§below) |
| `container:UpdateAllAuras()` | Musca `BlizzardAuraDisplayInstances.lua:141`, `BlizzardAuraDisplayUnitRefresh.lua:122`, `SecretAuraFlowGrid.lua:439`; EverAuras `ForeverDevInfo.lua:536` | the pull. EverAuras labels it `-- Inbound secure delegate, PoC-verified in combat` (`ForeverEngineAura.lua:8890-8893`) |
| `container:SetAuraSlotEnabled(key, bool)` | EverAuras `ForeverEngineAura.lua:2780`, `:5675`, `:7410`; Musca `SecretAuraSingleRemaining.lua:66`, `:106`, `:130` | show/hide a single game-drawn aura slot |
| `button:SetIcon(icon)`, `button:SetDurationCooldown(cooldownFrame)` | Musca `BlizzardAuraDisplayButtons.lua:261-262`; EverAuras `ForeverEngineAura.lua:2566`, `:2678`; probe `ForeverDevInfo.lua:597` | hand the game our own Texture + Cooldown frame; the game writes the icon texture and drives the swipe |
| `button:SetDurationText(fs, options)` | EverAuras `ForeverEngineAura.lua:2567`, `:2841`, `:2892`; Musca `SecretAuraSingleGateDisplay.lua:138`, `SecretAuraSingleRemaining.lua:94`, `CDMAuraProgress.lua:520`, `:528` | the game renders the countdown into our FontString. `options.textColor = { property = Enum.DurationTextBindingProperty.RemainingDuration, curve = … }` (Musca `SecretAuraSingleRemaining.lua:96-98`) makes the *game* do the "red below X seconds" comparison |
| `button:SetApplicationCount(fs, nil)`, `button:SetApplicationBar(statusBar, {min,max})` | EverAuras `ForeverEngineAura.lua:2568`, `:2731`, `:2781`; probe `Probe_Stacks.lua:3-6` | stacks. The engine calls `SetMinMaxValues`/`SetValue`/`SetShown` on our StatusBar for us |
| `button:SetDurationBar(statusBar, {direction})`, `button:SetSpellName(fs)` | EverAuras `ForeverEngineAura.lua:2565`, `:2569`, `:2656`, probe `ForeverDevInfo.lua:1477` | the game fills our bar from the aura duration |
| `button:SetDurationText` with `textFormat.formatString = "|T<file>:40:40|t"` | EverAuras `ForeverDevInfo.lua:1269-1272` | an inline icon *as text*, coloured by the engine's duration curve |
| `button:AddDispelTypeTexture(tex, {showWhenHelpful, showWhenHarmful, style, stealableFilter, customDispelAssetMap…})` | Musca `SecretAuraAppearance.lua:867-872`, `SecretAuraConditions.lua:1415`, `DispelTypeDisplay.lua:63-66` | dispel-type border/icon, coloured by the game |
| `button:AddAuraShownAnimation(animationGroup)` | Musca `SecretAuraGlow.lua:348`, `SecretAuraConditions.lua:1358-1359`; probe `Probe_Anim.lua:3-5` | **the native proc alert**: "plays them itself whenever the button goes from hidden to shown (Blizzard_CustomAuraButton.lua ApplyVisibility), also in combat" |
| `button:AddPandemicRegion(tex)`, `SetHideTooltipInCombat`, `SetDispelTypeText`, `SetCountdownFormatter`, `GetCountdownFontString` | EverAuras `ForeverDevInfo.lua:600-601`, `:1176`; Musca `BlizzardAuraDisplayButtons.lua:224-231`, `SecretAuraSingleGateDisplay.lua:143-150` | refresh-window flash; the probe explicitly tests that a combat tooltip is not force-hidden |
| `AuraContainerSortMethod` / `AuraContainerSortDirection` | EverAuras `ForeverEngineAura.lua:7062-7063`; Musca `BlizzardAuraDisplay.lua:90-93` (`sortMethods` catalogue incl. `ExpirationOnly`, `BigDefensive`, `UnitFrameDebuff`) | engine-side ordering |
| `C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer")` / `C_AddOns.LoadAddOn("Blizzard_AuraContainer")` | Musca `BlizzardAuraDisplayLifecycle.lua:100-107`; EverAuras `ForeverDevInfo.lua:543-546` | the mixins live in a Blizzard addon that must be loaded first |
| `container:SetAuraGroupLayout(key, {elementWidth, elementHeight, …})`, `SetAuraSlotLayout`, `SetFlowLayoutPadding`, `SetFlowLayoutAxis`, `SetFlowLayoutGrowthDirection`, `SetBreakpoints` | EverAuras `ForeverEngineAura.lua:3018`, probe `Probe_Dyn.lua:180`, `:196`, `:7113-7114`; Musca `SecretAuraFlow.lua` layout paths | layout of the flow of game-drawn frames |

### B. Gating on the secret regime

| API | where | what for |
| --- | --- | --- |
| `Private.hasCombatLog = not (C_DamageMeter or issecretvalue or (C_CombatLog and C_CombatLog.SetFilteredEventsEnabled))` | Musca `WeakAuras/SecretRestrictions.lua:5` | **the combat-log-closed test**, phrased as an *absence* test for three client features. Gates ~15 code paths (`BuffTrigger2.lua:2494`, `:4305`, `:2617`) |
| `C_Secrets.ShouldAurasBeSecret` / `ShouldCooldownsBeSecret` / `ShouldSpellCooldownBeSecret` / `ShouldUnitStatsBeSecret` / `ShouldUnitIdentityBeSecret` / `ShouldUnitAuraInstanceBeSecret` | Musca `SecretRestrictions.lua:44-51` (query table), `:53-64` (`Private.IsRestricted`), `:67-72` | the granular gate. Policy: "A query the client has but cannot answer (error or secret result) counts as restricted. A query the client lacks counts as unrestricted, so combat alone decides there." (`:66-67`) |
| `WeakAuras.IsRestricted() = InCombatLockdown() or IsKindRestricted("auras") or IsKindRestricted("cooldowns")` | Musca `SecretRestrictions.lua:75-77` | one predicate, ~60 call sites |
| `InCombatLockdown()` — engine global | Musca `SecretRestrictions.lua:76`, `SecretAuraFlow.lua:93`, `:343`, `:448`; EverAuras `ForeverEngineAura.lua:106`, `ForeverCheck.lua:462`, `ForeverGate.lua` header; ForeverAuras `ForeverAuras.lua:150`, `RegionPrototype.lua:988` | present in all three; EverAuras' own gate is 3 lines: `if InCombatLockdown() then return false end` + `C_Secrets.ShouldAurasBeSecret()` (`ForeverEngineAura.lua:105-109`) |
| `issecretvalue(v)` | Musca 24 files, e.g. `BlizzardAuraDisplayButtons.lua:40`, `Instances.lua:33/116/130/136`, `BlizzardAuraDisplayUnitRefresh.lua:28/36`, `SecretAuraAnchor.lua:184-185`; EverAuras `ForeverGate.lua:97/101`, `ForeverEngineAura.lua:1956/6064` | guards before every compare/arithmetic |
| `canaccessvalue` / `hasanysecretvalues` / `scrubsecretvalues` / `canaccesssecrets` / `canaccesstable` | **only in Musca's test harness**: `Tests/Harness/WowApi.lua:179-193` | these exist in the client, and Musca stubs them for tests; the shipped addon code uses only `issecretvalue` + `Private.IsSecret`. EverAuras probes their existence, not their use: `ForeverDevInfo.lua:435` `"add("[7] issecretvalue=%s canaccessvalue=%s canaccesssecrets=%s canaccesstable=%s"` |
| their own scrubber: `ScrubSecretState(state)` — replaces secret fields with the last readable value, and explicitly **does not** scrub `secretValue/secretTotal/secretPercent/secretPercentText/secretStacks/secretIcon/secretName/thresholdAlpha/absorb/healabsorb/^secretFlag*` | Musca `WeakAuras/WeakAuras.lua:5533-5557` | the "conditions keep their last state" behaviour is *implemented here*, not delegated to the client |
| `C_Secrets.GetSpellAuraSecrecy(id) == Enum.SecrecyLevel.NeverSecret` (also `GetSpellCastSecrecy`, `GetSpellCooldownSecrecy`, `GetPowerTypeSecrecy`) | Musca `SecretAuraSingleLearning.lua:20-30`, `PrototypeSecretHelpers.lua:150-154`; EverAuras `ForeverEngineAura.lua:643-651` (`NeverSecret`), probe `ForeverDevInfo.lua:422-427` | **per-spell secrecy query**: before trusting a spell-ID filter, ask whether *that* spell is ever secret. Musca's own field note: only `ComboPoints` is `NeverSecret`; 31964 of 31970 spells are `ContextuallySecret` on aura, cast and cooldown (`Tests/Packs/Chaman/NOTES.md:60`) |
| `ADDON_RESTRICTION_STATE_CHANGED` + `C_RestrictedActions.GetAddOnRestrictionState` + `Enum.AddOnRestrictionState.Inactive` | Musca `BlizzardAuraDisplayEvents.lua:172`, `SecretRestrictions.lua:90`; EverAuras `ForeverEngineAura.lua:8835`, `:8850-8856`, `ForeverCheck.lua:86-87` | the *only* event that tells you the regime flipped |
| pcall around every aura read | Musca `BuffTriggerRestrictedAuras.lua:36`, `:66`, `:97-98`, `:106-108`, `:133`; EverAuras `ForeverEngineAura.lua:8629`, `:8694`, every probe | documented at `GUIDE.md:299-301`: "In combat, the `C_UnitAuras` functions refuse addon code when auras are secret. They stop the code with "Auras cannot be accessed when secret while tainted" (tested in game): call them under `pcall`, or only out of combat." |

### C. Duration objects / timer curves

| API | where | what for |
| --- | --- | --- |
| `C_UnitAuras.GetAuraDuration(unit, auraInstanceID)` → a duration **object**, kept as `data.durationObject` | Musca `BuffTriggerRestrictedAuras.lua:97-102`, `:133` | the readable-in-combat handle for a secret aura's timer (readable as an object, not as numbers) |
| `statusBar:SetTimerDuration(durationObject, Enum.StatusBarInterpolation.*, Enum.StatusBarTimerDirection.*)` | Musca `NativeProgressPainter.lua:143-146` (gated by `Painter.CanDrawDurationObject = Enum.StatusBarTimerDirection ~= nil and statusBar.SetTimerDuration ~= nil`, `:24`); M33kAuras `RegionTypes/AuraBar.lua:632`, `:1250`, `ProgressTexture.lua:917-919`; probe EverAuras `ForeverDevInfo.lua:679`, `:784` | the game animates a StatusBar from a duration object. **This is the timer engine.** |
| `statusBar:SetMinMaxValues(0, total)` + `SetValue(secretValue)` (+ `Enum.StatusBarInterpolation.ExponentialEaseOut`) | Musca `NativeProgressPainter.lua:133-136` — comment: *"Value and total may be secret: they are only handed to the native setters."* | secret numbers driving a bar without ever being read |
| `C_DurationUtil.CreateDuration()` / `CreateDurationTextBinding()` → `binding:SetFontString`/`SetFormatter`/`SetDuration`/`SetEnabled` | Musca `SubRegionTypes/SubTextNative.lua:4-5`, `:17-30`; `SecretAuraSingleFollow.lua:107-108`, `:187`; `SpellCooldownState.lua:228-233`; `CooldownViewerCatalog.lua:51-54` | a live countdown text with no polling |
| `cooldown:SetCooldownFromDurationObject(durationObject, true)` | Musca `SecretRestrictions.lua:113` (`Private.ApplyCooldownDuration`, pcall'd); M33kAuras `RegionTypes/Icon.lua:674` | swipe driven by a duration object |
| `cooldown:SetCooldown(expirationTime - duration, duration, modRate)` (pcall, requires readable numbers) | Musca `SecretRestrictions.lua:108-111` | the readable-path twin, used out of combat |
| `durationObject:EvaluateRemainingDuration(curve)` → alpha; `GetTotalDuration()`; `IsZero`/`HasExpired`; `d:HasSecretValues()`; `FormatRemainingDuration(fmt)` | M33kAuras `Icon.lua:675-676`, `RegionPrototype.lua:457`; EverAuras probe `ForeverDevInfo.lua:786-788`, `:680`; M33kAuras `Prototypes.lua:9200` (`timingReadable = durationObject and not durationObject:HasSecretValues()`) | curves evaluated *by the engine* over the remaining time |
| `durationObject` sources beyond auras: `GetSpellCooldownDuration(id[, noGCD])`, `UnitCastingDuration(unit)`, `UnitChannelDuration`, `UnitEmpoweredChannelDuration`, `GetTotemDuration(slot)` | M33kAuras `Prototypes.lua:4729-4730`, `:9193-9197`, `:6978`; Musca `Prototypes.lua:8049` (`Private.ExecEnv.GetCastDurationObject(unit, castType)`); Musca `SecretAuraSingleFollow.lua:186-190` (`object:SetTimeFromStart(expiration - duration, duration)`) | the same sink fed by cast/cooldown objects — relevant to a *timeline* |
| `C_CurveUtil.CreateCurve()`/`SetType(Enum.LuaCurveType.Linear)`/`AddPoint`/`SetBreakpoints`, `C_StringUtil.CreateNumericRuleFormatter():SetBreakpoints(...)` | EverAuras `ForeverGate.lua:44-62`; Musca `SecretAuraSingleGateDisplay.lua:107-108`, `SecretAuraConditions.lua:781-782`, `DurationText.lua:73-74` | the engine-side comparison: a curve whose *output* is the alpha/colour |
| `C_CurveUtil.EvaluateColorValueFromBoolean(secretBool, a, b)` | EverAuras `ForeverGate.lua:102`; M33kAuras `Conditions.lua:649-652`, `:701` (generated condition code) | secret boolean → alpha/colour, addon never sees the value |
| `frame:SetAlphaFromBoolean(secretBool, 1, 0)` | EverAuras probe `ForeverDevInfo.lua:341`, `:786`, `:884`; `Probe_Absorb.lua:227` | "the one sink that also accepts a secret boolean" (`ForeverDevInfo.lua:827`) |
| `UnitPowerPercent(unit, powerType, false, curve)` | EverAuras `ForeverGate.lua:64-69`, header `:11-19` | "The player's current mana is secret even out of combat on Forever (measured 2026-09-24), so these are the only ways to act on it." |
| `C_Spell.IsSpellInRange(spell, unit)` | EverAuras `ForeverEngineAura.lua:46`, `:1750-1753`; probe `ForeverDevInfo.lua:824-828`, `:862` | "answers with a plain boolean on Forever, in combat too (probe 2026-09-19)" — a genuinely readable in-combat predicate |
| `C_Spell.GetSpellCooldown(id)` → `info.isActive`/`isEnabled`/`duration`; `C_Spell.GetSpellCooldownDuration(id, true)` | Musca `SecretSpellCooldown.lua:44-67`, header `:6-9`; probe `ForeverDevInfo.lua:789` ("SpellCooldownInfo.isActive/isEnabled/isOnGCD are NeverSecret") | the `reads-spell-state` proxy route |

### D. Native alerts / game-side triggers

| API | where | what for |
| --- | --- | --- |
| `C_UnitAuras.AddAuraSound(Enum.UnitAuraSoundTrigger.Added / .Removed / .ApplicationsIncreased, {unitToken, spellID, soundFileName, soundFileID, outputChannel, throttleSeconds})` → `soundID`; `C_UnitAuras.RemoveAuraSound(soundID)` | Musca `BlizzardAuraDisplaySounds.lua:72-73`, `:117-127`; EverAuras `ForeverEngineAura.lua:1777-1780` (design note), `:1952-1960` (validate-and-drop), `:6062-6069` | "C_UnitAuras.AddAuraSound makes the game play a sound itself when an aura is added to or removed from a unit, **also in combat**." Requires spell IDs + a sound FILE, not a Sound Kit ID. EverAuras verifies the returned id (`if issecretvalue(sid) then pcall(RemoveAuraSound, sid); return false end`, `:1956`) |
| `C_UnitAuras.AddAuraSound` on `party*`/`raid*` tokens | EverAuras probe `Probe_Sound.lua:1-16`, `:373-378`, `:604-608`; `Probe_SoundLoad.lua:151-154` | per-member sounds, incl. cost measurement |
| `C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, auraInstanceID, filter .. "\|" .. nativeFilter)` | Musca `BuffTriggerNativeFilter.lua:35-37`; M33kAuras `BuffTrigger2.lua:1946-1947`, `:1956-1957` | **the Game-Categories predicate.** Answers "does this instance match Blizzard's category filter" **without returning any aura field**, so it is callable in combat |
| `C_NamePlate.GetNamePlates()` / `GetNamePlateForUnit` | Musca `BlizzardAuraDisplayEvents.lua:38-40`, `BlizzardAuraDisplayValidation.lua:36-38` | unit-token discovery for nameplate anchoring |

### E. The "Game Categories" mechanism (Musca), code + prose

Prose (`GUIDE.md:140-160`): the categories table, and the operative sentence —
> "**Game Categories alone shows everything, even hidden auras.** When Game Categories is the only filter of the trigger (no name, no spell ID, no other filter), auras applied during combat show even when the game hides all their data. Their icon, timer and stack text are drawn by the game; their name stays empty until combat ends."

and the failure mode (`GUIDE.md:579`): "**My icon has no name in combat.** It is an aura hidden by the game, found by Game Categories: the name comes back when combat ends."

Code that realises it:

1. Category catalogue → the *same strings* the container filter language uses: `BlizzardAuraDisplay.lua:64-88` (`PLAYER`, `RAID`, `CANCELABLE`, `EXTERNAL_DEFENSIVE`, `CROWD_CONTROL`, `RAID_IN_COMBAT`, `RAID_PLAYER_DISPELLABLE`, `BIG_DEFENSIVE`, `IMPORTANT`, `DISPELLABLE`) and `:31-62` (boolean property filters `isFromPlayerOrPlayerPet`, `canApplyAura`, `isStealable`, `isBossAura`, `isRoleAura`, `isBossOrRoleAura`, `isPriorityAura`, `nameplateShowAll`, `nameplateShowPersonal`).
2. The filter string: `BlizzardAuraDisplayTrigger.lua:66-80` — `segments = { trigger.debuffType }` then `segments[#segments+1] = value and key or "!" .. key`, `table.concat(segments, "|")` → e.g. `"HARMFUL|CROWD_CONTROL"`. Validated against the client with `AuraUtil.IsValidFilterString` (`BlizzardAuraDisplayValidation.lua:83`).
3. Container path: that string goes straight into `AddAuraGroup`/`AddAuraSlot` (`Instances.lua:165`, `:186`).
4. Addon-trigger path (so non-container regions benefit): `BuffTriggerNativeFilter.lua:16-41`, quoted in §D.
5. Validation of the client's own filter vocabulary: probe `Probe_Dispel.lua:117-120`.

The paired *anti*-mechanism — why spell-ID filters are the weak form:
- Musca `SecretAuraSingleLearning.lua:52-70`: `SpellIDFilterNote` → error `"In combat Blizzard keeps %s on %s out of spell ID filters. … Try Approximate Match."`
- Musca preview notice `BlizzardAuraDisplaySounds.lua:140`: `"Preview only: spell ID filters hide these auras in combat."`
- Musca `SecretAuraSingleLearning.lua:229-244` (`ApproximateFilters`): **`filterTable.includeSpellIDs, filterTable.excludeSpellIDs = nil, nil`** and substitutes a learned fingerprint (`maxDuration`, `includeDispelTypes`, boolean flags) learned out of combat.
- EverAuras reaches the same conclusion independently: `DISPEL_NAMES`/`PROPERTY_FLAGS` at `ForeverEngineAura.lua:85-92` with the comment *"Aura properties Blizzard's containers filter on for EVERY aura (not identity filters, so the rule that keeps addons from picking debuffs on friendly units by spell does not apply to them)"*; `nameless` mode at `:1117-1118` (`if nameless then candidate = {} end` — all identity filters dropped); and the user-facing toggle at `ForeverEngineAuraOptions.lua:157-158`: *"Match debuffs on you by their properties (approximation) — Blizzard does not let addons pick debuffs on yourself by spell while auras are secret (in combat)"*; warning set at `ForeverEngineAura.lua:1157-1162` (`warn = "friendly"/"hostile"` when a target/focus trigger names spells not in your spellbook).
- The escape hatch for a spell that *is* readable: `AllNeverSecret(ids)` gated on `C_Secrets.GetSpellAuraSecrecy` (`SecretAuraSingleLearning.lua:44`), `open = NeverSecret(sorted)` (`ForeverEngineAura.lua:1119`) — the warning is suppressed for spells the client declares NeverSecret.

### F. ForeverAuras' (absent) surface, for contrast

`ForeverAuras/AuraEnvironment.lua:17-23` `UnitAura` → `C_UnitAuras.GetAuraDataByIndex` + `AuraUtil.UnpackAuraData`, ungaurded; `ForeverAuras/BuffTrigger2.lua:1778`, `:1931`, `:1962`, `:4109`, `:4235` all call `AuraUtil.ForEachAura(unit, filter, nil, HandleAura, true)` / `GetAuraDataByAuraInstanceID` with **no `pcall`, no `Private.IsSecret`, no `IsRestricted`, no container**. Repo-wide grep for `issecretvalue` in `ForeverAuras/ForeverAuras/` matches only `InCombatLockdown()` sites (secure-frame protection, `RegionPrototype.lua:988/1019/1073/1139`) — no `C_Secrets`, no `hasCombatLog`, no aura-container.

---

## Events registered

Musca, native-display dispatcher (`BlizzardAuraDisplayEvents.lua:169-183`):
`PLAYER_REGEN_ENABLED`, `ADDON_RESTRICTION_STATE_CHANGED`, `UI_SCALE_CHANGED`, `DISPLAY_SIZE_CHANGED`,
`PLAYER_ENTERING_WORLD`, `GROUP_ROSTER_UPDATE`, `PLAYER_TARGET_CHANGED`, `PLAYER_FOCUS_CHANGED`,
`UPDATE_MOUSEOVER_UNIT`, `UNIT_TARGET`, `UNIT_PET`, `INSTANCE_ENCOUNTER_ENGAGE_UNIT`,
`ARENA_OPPONENT_UPDATE`, `NAME_PLATE_UNIT_ADDED`, `NAME_PLATE_UNIT_REMOVED`, `UNIT_NAME_UPDATE`,
`PLAYER_ROLES_ASSIGNED` — each through `pcall(mainFrame.RegisterEvent, mainFrame, event)`, plus a status
frame on `UNIT_HEALTH`, `UNIT_FLAGS`, `UNIT_CONNECTION` (`:179-183`).

Musca, restriction tracker (`SecretRestrictions.lua:88-95`):
`PLAYER_ENTERING_WORLD`, `PLAYER_REGEN_DISABLED`, `PLAYER_REGEN_ENABLED`, + pcall'd
`ADDON_RESTRICTION_STATE_CHANGED`, `PLAYER_IN_COMBAT_CHANGED`, `ENCOUNTER_STATE_CHANGED`,
`CHALLENGE_MODE_START`, `PVP_MATCH_ACTIVE`, `PVP_MATCH_INACTIVE`, `PVP_MATCH_COMPLETE`,
`PVP_MATCH_STATE_CHANGED`.

Musca, legacy aura trigger (`BuffTrigger2.lua:2473-2492`):
`UNIT_AURA`, `UNIT_FACTION`, `UNIT_NAME_UPDATE`, `UNIT_FLAGS`, `PLAYER_FLAGS_CHANGED`, `UNIT_PET`,
`RAID_TARGET_UPDATE`, `PLAYER_SOFT_ENEMY_CHANGED`, `PLAYER_SOFT_FRIEND_CHANGED`, `PLAYER_TARGET_CHANGED`,
`ENCOUNTER_START`, `ENCOUNTER_END`, `INSTANCE_ENCOUNTER_ENGAGE_UNIT`, `NAME_PLATE_UNIT_ADDED`,
`NAME_PLATE_UNIT_REMOVED`, `GROUP_ROSTER_UPDATE`, `PLAYER_ENTERING_WORLD`, `PARTY_MEMBER_DISABLE`,
`PARTY_MEMBER_ENABLE`, `UNIT_TARGETABLE_CHANGED`; plus conditionally
`Buff2Frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")` (`:2507`) — registered **only**
under `if not Private.hasCombatLog then` (`:2494`), i.e. the own-cast event is the Forever-only path.
`COMBAT_LOG_EVENT_UNFILTERED` is registered behind the inverse guard
`if Private.hasCombatLog then` (`:4305-4306`) — dead on Forever.

EverAuras (`ForeverEngineAura.lua:8831-8837`), all via `Engine.RegisterEvents` which pcall's and
records refusals into `Engine.badEvents` (`:152-158`):
`PLAYER_TARGET_CHANGED`, `PLAYER_FOCUS_CHANGED`, `PLAYER_REGEN_ENABLED`, `PLAYER_ENTERING_WORLD`,
`GROUP_ROSTER_UPDATE`, `UNIT_FLAGS`, `UNIT_CONNECTION`, `PLAYER_ALIVE`, `PLAYER_UNGHOST`,
`PARTY_MEMBER_ENABLE`, `PARTY_MEMBER_DISABLE`, `UNIT_PHASE`, `SPELLS_CHANGED`,
`LEARNED_SPELL_IN_SKILL_LINE`, `PLAYER_LEVEL_UP`, `UI_SCALE_CHANGED`, `DISPLAY_SIZE_CHANGED`,
`ADDON_RESTRICTION_STATE_CHANGED`, `UNIT_PET`(unit), and `UNIT_AURA`(unit, for player/target/focus/pet).

Known-secret-annotated / regime-relevant, marked:
- **`ADDON_RESTRICTION_STATE_CHANGED`** — regime flip (both addons; Musca `:172`, EverAuras `:8835`).
- **`PLAYER_REGEN_ENABLED`** — "combat ended, restrictions lifted", the replay trigger (Musca
  `SecretRestrictions.lua:90`, `BlizzardAuraDisplayEvents.lua:139`; EverAuras `:8881-8886`).
- **`UNIT_AURA`** — payload is secret in combat. Musca detects that literally:
  `Private.IsSecret(arg1)` on the *unit token itself* (`BuffTrigger2.lua:2394`) and then marks every
  unit for re-scan. EverAuras never reads the payload at all (`:8846-8848`).
- **`NAME_PLATE_UNIT_ADDED`** — unit token may be secret: `if issecretvalue(unit) … then return end`
  (`BlizzardAuraDisplayEvents.lua:26-27`).
- **`UNIT_HEALTH`/`UNIT_FLAGS`/`UNIT_CONNECTION`** — status probes whose results get secret-tested
  (`BlizzardAuraDisplayUnitRefresh.lua:27-38`).
- **`UNIT_SPELLCAST_SUCCEEDED`** — the readable one; the Musca GUIDE uses it as the canonical custom
  trigger (`GUIDE.md:479-510`) with `issecretvalue(spellID)` guard *inside* the handler.
- Absent by design in both: any `COMBAT_LOG_EVENT_UNFILTERED`, `C_CombatLog*`,
  `CombatLogGetCurrentEventInfo` — no reference to those exists in EverAuras' files, and Musca's only
  references are the *absence* test (`SecretRestrictions.lua:5`) and the `hasCombatLog`-gated legacy
  branches.

---

## The in-combat trick, step by step

**Musca Auras / EverAuras (the shared shape):**

1. **Classify the regime once, granularly.** `WeakAuras.IsRestricted()` / `Engine.IsSafe()` =
   `InCombatLockdown() or C_Secrets.ShouldAurasBeSecret()…` (Musca `SecretRestrictions.lua:75-76`;
   EverAuras `ForeverEngineAura.lua:105-109`). Everything downstream asks this one predicate.
2. **Detect a legacy WeakAuras port and refuse to run it blind.** `Private.hasCombatLog`
   (`SecretRestrictions.lua:5`) — the CLEU/`C_CombatLog`/`issecretvalue` absence test — switches on
   the pcall-everything handler (`BuffTrigger2.lua:2494-2506`), whose failure message is
   "Aura triggers paused until the end of combat (secret aura data)".
3. **For the display: hand the display to the game.** `CreateFrame("AuraContainer", nil, parent,
   "CustomAuraContainerTemplate")` → `SetAuraProcessingPolicy(None)` →
   `AddAuraGroup/AddAuraSlot(key, filterString, {maxFrameCount, candidateFilters, sortMethod,
   initializeFrame})` (Musca `SecretAuraFlow.lua:229`, `Instances.lua:163-169`; EverAuras
   `ForeverEngineAura.lua:2523`, `:2533-2535`). The container is bound to a *unit* (`SetUnit`), and the
   addon's only inputs are (a) a Blizzard filter string and (b) a candidate-filter table.
4. **Inside `initializeFrame`, hand over our own draw targets.** This callback runs synchronously
   *before* the game applies `DenyTaintedAccessWhenAurasAreSecret` to the button — EverAuras states
   this twice, as the reason the design works at all (`ForeverEngineAura.lua:2536`, `:5560`; probe
   `ForeverDevInfo.lua:581-582`). Inside it: `SetIcon`, `SetDurationCooldown`, `SetDurationBar`,
   `SetDurationText`, `SetApplicationCount`, `SetApplicationBar`, `AddPandemicRegion`,
   `AddDispelTypeTexture`, `AddAuraShownAnimation`.
5. **From then on, the addon is blind and it does not matter.** The engine writes secret icon/timer/
   count values into our regions; we cannot read them back, and we never try. EverAuras' header,
   stated as verified fact: *"Every inbound call is a secure delegate; the engine writes secret values
   into regions we hand over and marks them unreadable. Proven in game 2026-09-18."*
   (`ForeverEngineAura.lua:3-7`).
6. **Match by category, not by identity, when identity is refused.** `filterString` carries
   `PLAYER|RAID|CROWD_CONTROL|IMPORTANT|…` (`BlizzardAuraDisplayTrigger.lua:66-80`); when the spell-ID
   list would be dead in combat, drop it: `filterTable.includeSpellIDs, excludeSpellIDs = nil, nil`
   and substitute a learned out-of-combat fingerprint (`SecretAuraSingleLearning.lua:229-244`;
   EverAuras `:1118`, `:85-92`). Categories work on the addon-trigger side too via
   `IsAuraFilteredOutByInstanceID` (`BuffTriggerNativeFilter.lua:35-37`).
7. **Drive layout with engine-authored geometry, not with reads.** EverAuras' "Missing" mode is the
   clean statement (`ForeverEngineAura.lua:12-17`): the engine sizes the container to 1 px while the
   aura is absent and `W+1` px while present; a clipping frame is anchored from the container's right
   edge to the region's right edge — full width = absent, zero width = present. "Pure geometry driven
   by a value we cannot read." Same trick at stack granularity via
   `SetApplicationBar(statusBar, {min, max})` + anchoring a gate to `sb:GetStatusBarTexture()`'s fill
   edge (`:2730-2736`). Musca's mirrors: `NativeProgressPainter.AnchorMaskToFill(mask,
   active:GetStatusBarTexture(), …)` (`AuraBarNative.lua:154-156`) — the addon's own painted fill
   follows the engine-animated bar's texture.
8. **Route every decision to an engine-side comparator.** Thresholds become curves
   (`C_CurveUtil.CreateCurve` + `AddPoint`, `C_StringUtil.CreateNumericRuleFormatter():SetBreakpoints`),
   booleans become `C_CurveUtil.EvaluateColorValueFromBoolean` / `SetAlphaFromBoolean`, percentages
   become `UnitPowerPercent(unit, pt, false, curve)`, "expiring" becomes the
   `textColor = {property = Enum.DurationTextBindingProperty.RemainingDuration, curve = …}` option
   (Musca `SecretAuraSingleRemaining.lua:94-99`; M33kAuras `Conditions.lua:649-652`; EverAuras
   `ForeverGate.lua:100-106`).
9. **Fire alerts from the game.** `AddAuraSound(Added/Removed/ApplicationsIncreased, {unitToken,
   spellID, …})` (`BlizzardAuraDisplaySounds.lua:117-127`), retried on
   `ADDON_RESTRICTION_STATE_CHANGED` (EverAuras `:8850-8856`); `AddAuraShownAnimation(group)` so the
   glow plays from the engine's own show transition.
10. **Keep a live timer for addon-drawn regions on a secret aura.** On `UNIT_AURA` do **not** read the
    payload (Musca `BuffTrigger2.lua:2391-2401`, EverAuras `:8846-8848`); mark the unit; on the next
    `OnUpdate` (`BuffTrigger2.lua:2626-2631`) run
    `GetUnitAuraInstanceIDs` → per-instance `ShouldUnitAuraInstanceBeSecret` → for readable ones
    `GetAuraDataByAuraInstanceID`, for secret ones a placeholder
    `{name = "", isSecretPlaceholder = true, secretIcon = pcall(…GetAuraDataByAuraInstanceID…).icon}`
    (`BuffTriggerRestrictedAuras.lua:35-53`) → for matched ones attach `GetAuraDuration`
    (`data.durationObject`) and `GetAuraApplicationDisplayCount` (`data.secretStacks`) (`:93-106`).
    Rendering: `%p` binds through `C_DurationUtil.CreateDurationTextBinding()`
    (`SubTextNative.lua:17-30`), `%s` prints the pre-formatted `secretStacks` string
    (`SubTextNative.lua:48-52`), the icon takes `SetTexture(iconState.secretIcon)`
    (`RegionTypes/Icon.lua:564-565`), the bar takes `SetTimerDuration`
    (`NativeProgressPainter.lua:143-146`).
11. **Replay everything when the regime lifts.** `RestrictionChanged` → full rescan
    (`BuffTriggerRestrictedAuras.lua:191-213`); Musca defers refused layout work in a queue and
    replays it (`SecretAuraFlow.lua:83-99`, `:343`, `:448`).
12. **State the residual honestly to the user.** Musca `SecretAuraConditions.lua:466` +
    `BlizzardAuraDisplayButtons.lua:25` PENDING_TEXT "changes will apply when the game stops hiding
    combat data"; EverAuras' per-display "Engine-driven: … Not available: conditions and texts that
    read aura state" strings (`ForeverEngineAuraOptions.lua:113`, `ForeverEngineAura.lua:2126-2230`).

**ForeverAuras (the control group):** register `UNIT_AURA` → `AuraUtil.ForEachAura` →
`GetAuraDataByIndex`/`GetAuraDataByAuraInstanceID` → unpack the fields → drive our own regions. Steps
3-12 above simply do not exist in that tree, which is why it is labelled early-development.

---

## Applicability to a compact timeline bar

Our bar = **our own** icons sliding on a power-scale axis. Ranked by transfer value:

**1. `StatusBar:SetTimerDuration(durationObject, interpolation, direction)` — the single highest-value
call for us.** It is a timer that ticks in combat *on addon-owned frames*, so long as the addon only
holds an opaque duration object. Sources proven callable: `C_UnitAuras.GetAuraDuration(unit, instanceID)`
under pcall (Musca `BuffTriggerRestrictedAuras.lua:97`), `C_Spell.GetSpellCooldownDuration(id, noGCD)`
(M33kAuras `Prototypes.lua:4729`), cast/channel objects (`Prototypes.lua:9193-9197`), and a
self-built one via `C_DurationUtil.CreateDuration()` + `SetTimeFromStart(start, dur)`
(Musca `SecretAuraSingleFollow.lua:186-190`) — the last is the "timer from my own cast" path our
`UNIT_SPELLCAST_SUCCEEDED` design already has the trigger for. Gate on
`Painter.CanDrawDurationObject` exactly as Musca does (`NativeProgressPainter.lua:24`), and on
`durationObject:HasSecretValues()` as M33kAuras does (`Prototypes.lua:9200`). **Blocker:** it needs a
*duration object*, not a number; there is no evidence in any of these trees that a plain
`(start, dur)` pair can be promoted into one from tainted code, so a bar driven by numbers we computed
ourselves will freeze in combat — only engine-sourced objects tick.

**2. The anchor-to-fill-edge idiom, which is exactly "slide an icon along the power axis".**
`statusBar:SetAlpha(0)` (never drawn, geometry only) → `SetTimerDuration`/`SetApplicationBar`/
`SetValue(secret)` → anchor our icon to `statusBar:GetStatusBarTexture()`'s fill edge. Musca
`AuraBarNative.lua:154-156` + `NativeProgressPainter.AnchorMaskToFill`; EverAuras
`ForeverEngineAura.lua:2730-2736` (a full stack-count gate built this way) and the Missing-width clip
at `:12-17`. **Blocker:** we may not read the fill's position (`GetStatusBarTexture` returns a texture
we can anchor to, not a coordinate), so the icon's motion must be pure anchoring geometry; anything
that wants an x value will die.

**3. `SetAlphaFromBoolean` / `EvaluateColorValueFromBoolean` / curve-driven `SetBreakpoints`.** Every
threshold we currently compute (red below N, dim when full, glow when expiring) must be expressed as
a curve handed to the engine, or a boolean fed to a boolean sink. EverAuras' `ForeverGate.lua` is a
whole, small, self-contained module that *shadows* `SetAlpha`/`GetAlpha` on the instance to do this —
the same shadowing pattern fits a timeline bar's own region prototype, and it deliberately keeps
`GetAlpha` returning the requested base so animation seeds never see a gated value
(`ForeverGate.lua:6-9`). **Blocker:** curves are linear-ramp, not step, in EverAuras' implementation
(`ForeverGate.lua:34-36`, "the documentation does not say which side a Step curve takes") — budget for
a 0.0005-wide edge.

**4. `C_Spell.IsSpellInRange(spell, unit)` — a readable in-combat boolean.** Directly usable for
"grey out segments out of range", sampled 5x/s as EverAuras does. Verified by their probe, not by us.

**5. `C_UnitAuras.AddAuraSound` — our proc-alert channel, zero reads.** Per `(trigger, unitToken,
spellID)` registration, works in combat, survives a reload only if you clean strays (EverAuras
`ForeverEngineAura.lua:5930-5940` keeps a saved list and removes ids it cannot keep). This is the
route for a timeline's audible "proc landed" cue.

**6. `AuraContainer` + `AddAuraGroup/AddAuraSlot`.** Usable *only* if we accept game-drawn content.
For us it is a whole-segment handover, not a per-icon assist: the container lays out its own frames
(`SetAuraGroupLayout`, `SetFlowLayout*`), the addon cannot mint buttons (they arrive via
`initializeFrame`), and the drawn set is bounded by the game's aura list on the bound unit (§below).
Two genuinely useful placements for a timeline: (a) a "you are missing this DoT" chip that is
`Missing`-mode (EverAuras `:12-17`) so the space collapses when the aura is present; (b) a
`sortMethod = ExpirationOnly` row, which gives a **game-sorted expiry queue** — the one thing we
cannot compute at all in combat (EverAuras `:7063-7067`; probe `Probe_Sort.lua:3-6`).

**7. The `nameless`/fingerprint and Game-Categories fallback.** Directly applicable to our segment
matching: if we key segments on spell IDs, the same "Blizzard keeps them out of spell ID filters in
combat" rule bites us (Musca `SecretAuraSingleLearning.lua:64-70`). Their answer — learn each
spell's `(duration, dispelType, boolean flags)` out of combat, then match on properties only —
transfers verbatim as a matching strategy for our segments, with the fingerprint-collision caveat
they state (`ForeverEngineAura.lua:2282`).

**Not applicable / dead ends we should not spend time on:** the container's animation/animation-group
surface for *our* icons (`SecretAuraConditions.lua:1358` hands a game animation group to a game
button, not ours); `CustomAuraButton:SetDurationText` for our fonts (that API is on the game's aura
button object, not on a FontString — our equivalent is `C_DurationUtil.CreateDurationTextBinding` +
`SetFontString`, `SubTextNative.lua:17-19`); anything CLEU-derived — these three addons have zero
combat-log code paths for Forever (Musca's is behind `hasCombatLog`, EverAuras' has none).

**Cross-cutting discipline worth copying verbatim:** the `secret*` field-naming convention
(`secretValue`, `secretTotal`, `secretPercentText`, `secretStacks`, `secretIcon`, `secretName`,
`^secretFlag*`) plus the single scrubber that whitelists them (`WeakAuras.lua:5533-5557`). It makes
"which fields are allowed to be secret" one greppable list, and it is what makes "conditions keep
their last state" an explicit design decision rather than an accident.

---

## Can an addon add an ARBITRARY spell (an item proc) to a Blizzard aura container, and does that display tick in combat?

**No, it cannot add an arbitrary spell. Yes, what a container does display ticks in combat —
demonstrated in game by both addons. The two halves are separately evidenced.**

**(a) No injection surface exists. What the container takes is a *filter*, and it is bound to a *unit*.**

- The container is unit-bound, and the addon is the one calling `SetUnit`:
  `auraContainer:SetUnit(unit)` — Musca `SecretAuraFlowGrid.lua:238`,
  `SecretAuraSingleMissing.lua:178`
  (`if unit then auraContainer:SetUnit(unit) end`), `SecretAuraAnchor.lua:178`;
  EverAuras probe `ForeverDevInfo.lua:584` (`try("SetUnit(target)", c.SetUnit, c, "target")`),
  `Probe_Late.lua:262`.
- The only population call is `AddAuraGroup(key, filterString, {maxFrameCount, candidateFilters, …})`
  / `AddAuraSlot(key, filterString, {candidateFilters, initializeFrame})` — Musca
  `BlizzardAuraDisplayInstances.lua:165`, `:96`; EverAuras `ForeverEngineAura.lua:2533`, `:2921`,
  `:6431`, `:7063`. Its *arguments* are a Blizzard category string plus a candidate-filter table; its
  *callback* hands a button **from the game to us** (`initializeFrame = function(button) …`), never the
  reverse.
- `candidateFilters` narrows; it never adds. Its whole vocabulary, enumerated from real code:
  `includeSpellIDs`, `excludeSpellIDs`, `maxDuration`, `includeDispelTypes`, `excludeDispelTypes`,
  `isFromPlayerOrPlayerPet`, `canApplyAura`, `isStealable`, `isBossAura`, `isRoleAura`,
  `isBossOrRoleAura`, `isPriorityAura`, `nameplateShowAll`, `nameplateShowPersonal`
  (Musca `BlizzardAuraDisplayButtons.lua:266-325`, `BlizzardAuraDisplay.lua:31-88`).
  And the narrowing is *negative* under the regime: `filterTable.includeSpellIDs,
  filterTable.excludeSpellIDs = nil, nil` (`SecretAuraSingleLearning.lua:236`).
- Exhaustive-search result across all three trees: **the only `Add*Aura*` APIs are `AddAuraGroup`,
  `AddAuraSlot` (container-side, filter-taking) and `C_UnitAuras.AddAuraSound` (audio, spell-ID-keyed).**
  Zero matches for `AddAura(`, `ForceAura`, `FakeAura`, `InjectAura`, `SetCustomAura`, `AddCustomAura`.
  No call in any of these addons passes a spell ID to anything that creates a displayed aura.
- The security rationale is stated in the source, not inferred: `DISPEL_NAMES` comment — *"not identity
  filters, so the rule that keeps addons from picking debuffs on friendly units by spell does not apply
  to them"* (`ForeverEngineAura.lua:85-87`); options text — *"Blizzard does not let addons pick debuffs
  on yourself by spell while auras are secret (in combat)"* (`ForeverEngineAuraOptions.lua:158`);
  and the container's per-button lockdown is literally named
  `DenyTaintedAccessWhenAurasAreSecret` (`ForeverEngineAura.lua:2536`, `:5560`;
  `ForeverDevInfo.lua:581-582`).
- Consequence for an item proc: the display appears **iff the game considers that proc a real aura on
  the bound unit**, in which case the container shows it with no help from us. If the proc is purely
  client-side (an internal proc-cooldown, a spell-activation overlay, a "proc glow"), there is nothing
  to filter on and nothing to add. EverAuras probes exactly that open question and leaves it open:
  `ForeverDevInfo.lua:447-448` `"-- 5. Does Forever populate spell activation overlays (the proc-glow
  channel)?"` → `add("[5] IsSpellOverlayed(348)=%s C_SpellActivationOverlay=%s", …)`.

**(b) Container-drawn content ticks in combat — proven, and the mechanism is named.**

- EverAuras states it as verified fact: *"Icon and Progress Bar displays with Aura triggers are
  rendered by Blizzard_AuraContainer (CustomAuraContainerTemplate), so they keep working while auras
  are secret in combat. The addon never reads aura state. Every inbound call is a secure delegate;
  the engine writes secret values into regions we hand over and marks them unreadable. **Proven in
  game 2026-09-18.**"* (`ForeverEngineAura.lua:1-7`), plus the range-probe date 2026-09-19 (`:46`), and
  the pull-call note *"Inbound secure delegate, **PoC-verified in combat**"* for `UpdateAllAuras`
  (`:8890-8893`).
- Musca's prose table of in-combat outcomes: "Icon of a buff or debuff | Shown, drawn by the game.",
  "Cooldown swipe, timer bar | Keep running, drawn by the game.", "Text `%p` … Drawn by the game",
  "Text `%s` … Drawn by the game", "Border colored by dispel type | Colored by the game"
  (`GUIDE.md:86-96`).
- Musca's code-level corroboration for the *fallback* (non-container) path: CHANGES.md `:1883-1887` —
  the matched auras get a `durationObject` from `C_UnitAuras.GetAuraDuration` "so its icon swipe and
  bar keep running in combat"; `:1884-1886` names the exact calls.
- The precise reason it is legal: the container methods are *inbound secure delegates* — the tainted
  call crosses into the secure partition, the aura reads happen untainted, and the resulting values
  are written into our regions as secrets we cannot read back (`ForeverDevInfo.lua:465-471` — quoting
  `Blizzard_AuraContainer`'s own TOC: the templates are global "to allow intrinsics and templates to
  be instantiated by external code").
- EverAuras' probe `ForeverDevInfo.lua:429-432` is a direct construction test:
  `C_AuraContainerUtil=%s CustomAuraButtonMixin=%s AuraContainerMixin=%s CreateFrame(CustomAuraButtonTemplate)=%s`
  — labelled *"Does the engine-drawn aura button exist? It would be correct by construction."*

**Bottom line for ForteXorcist:** an item proc is displayable by the game only when the game itself
has it as an aura instance on a unit — that is a data question (does the proc carry `APPLY_AURA` /
have a spell ID on the unit's aura list), answerable from `mythicsim-forever-engine` data plus a
`C_UnitAuras` probe, not a code trick. Where the proc has no game-side aura, the three viable
in-combat channels are, in cost order: (1) `C_UnitAuras.AddAuraSound` for an audible cue;
(2) a duration-object timer we start from our own readable `UNIT_SPELLCAST_SUCCEEDED` and drive into
`SetTimerDuration`/`SetCooldownFromDurationObject`; (3) the `reads-spell-state` proxy
(`C_Spell.GetSpellCooldown` `isActive`/`isEnabled`, Musca `SecretSpellCooldown.lua:44-67`) for
proc-cooldown readiness. `[INFERENCE]` for this repo, not claimed by the three addons.

---

## Confidence + what you could not verify

**High confidence (read in shipped code):** everything in the API table, the gating predicate tree,
the events list, the Game-Categories mechanism (prose + the 41-line file that implements it), the
duration-object sinks, the absence of any injection API, and ForeverAuras' lack of both containers and
secret gating.

**High confidence (in-game claims by the authors, with dates, that I did not reproduce — I ran no
game):** `UpdateAllAuras`/`AddAuraShownAnimation`/`AddAuraSound` working in combat (2026-09-18,
2026-09-19, 2026-09-24 in-file dates); the exact "Auras cannot be accessed when secret while tainted"
error text (quoted as "confirmed in game" at `CHANGES.md:2106-2109` and "tested in game" at
`GUIDE.md:300`); mana being secret even out of combat; `C_Spell.IsSpellInRange` returning a plain
boolean; the container width 1px↔W+1px behaviour; `C_Secrets.GetSpellAuraSecrecy` returning
`ContextuallySecret` for ~all spells. These are corroborated by *two independent codebases* that
design around them identically, which is why I treat them as reliable — but they are the addons'
measurements, not mine.

**Not verified, stated plainly:**
1. **`C_AuraContainerUtil` — zero call sites.** The task named it as a route; it appears in EverAuras
   only as a *type probe* (`ForeverDevInfo.lua:430`) and in Musca only in
   `.luacheckrc:15` (globals) and the **test harness** (`Tests/Scenarios/45_SingleContract.lua:72-73`,
   `:700`, where it is stubbed as `ProcessCustomAuraButtonApplicationBarOptions`). Neither shipped
   addon calls it. Same for `C_AuraUtil`: no occurrences at all. Their container work is entirely on
   the frame mixin surface.
2. `canaccessvalue`/`hasanysecretvalues`/`scrubsecretvalues` in *shipped* code: none. Only the Musca
   harness stubs (`Tests/Harness/WowApi.lua:179-193`) and EverAuras' existence probe
   (`ForeverDevInfo.lua:435`). Their shipped scrubbing is self-written
   (`WeakAuras.lua:5533-5557`).
3. **EverAuras' shipped source was not read as a whole addon.** The repo ships only the fork delta
   (`tools/forever_files/`, 11,419 lines incl. `ForeverEngineAura.lua` 8,912) plus dev probes; the
   WeakAuras core is a submodule pointer `tools/UPSTREAM` (`git ls-files -s tools/UPSTREAM` → mode
   `100644`, i.e. a **gitlink not initialised in my shallow clone**), and the release is built by
   `tools/rebuild_everauras.sh` + `make_release_zip.py`. So EverAuras' *trigger-side* lines
   (`BuffTrigger2`-class behaviour, `Prototypes.lua`) I read through the M33kAuras clone, and the
   `InCombatLockdown()`-style core gating through ForeverAuras/Musca. The delta files themselves are
   fully read.
4. Whether the game exposes a **proc** (as opposed to an applied aura) to the container at all:
   unprobed by me; EverAuras leaves `C_SpellActivationOverlay.IsSpellOverlayed` as an open probe
   (`ForeverDevInfo.lua:447-449`).
5. Whether `SetTimerDuration` accepts a tainted-constructed duration object (`C_DurationUtil.
   CreateDuration()` + `SetTimeFromStart`) on a **plain StatusBar that is not a container button** —
   Musca does exactly this (`SecretAuraSingleFollow.lua:186-190` feeding
   `SetTimerDuration` via `NativeProgressPainter`), so it works; the *edge* I could not pin is
   whether an object built from our own `(start, duration)` numbers keeps ticking once auras go
   secret, since `SecretAuraSingleFollow` uses it for a "missing aura" estimate. Needs a live test.
6. **No in-game run.** Per instructions, read-only source analysis only; no `wow-ui-sim` invocation.
7. ForeverAuras: I read the `main` HEAD clone. Its README calls it early-development; if a
   secret-regime layer exists on a branch, it is not in the default branch.

# Active loss of control

## Contract

A new simulated world has no active loss-of-control effects. Supplied entries are ordered per unit. Player queries and explicit player-unit queries read the same entries; other units are independent. Removing entries returns counts to zero and indexed queries to nil. `A_Admin.AddLossOfControl(unit, data)` appends a declared record and returns its one-based index. `A_Admin.ClearLossOfControl(unit)` removes that unit's entries. Fixture input does not synthesize native events or infer effects from auras.

Entries follow `Blizzard_APIDocumentationGenerated/LossOfControlDocumentation.lua` in each pinned runtime cache:

| Profile | Queries | `LossOfControlData` fields |
| --- | --- | --- |
| Retail | 11–81 | 151–161 |
| PTR | 11–81 | 151–161 |
| Mists | 11–77 | 146–156 |
| Era | 11–77 | 146–156 |
| Anniversary | 11–77 | 146–156 |
| Forever | 11–82 | 151–161 |

All six declare numeric `iconTexture`, optional numeric `startTime`, `timeRemaining`, `duration`, and `auraInstanceID`, required string `locType` and `displayText`, and numeric `spellID`, `lockoutSchool`, `priority`, and `displayType`. All six declare `GetActiveLossOfControlDuration` as an optional `LuaDurationObject`, not a numeric number of seconds. Duration objects derive from the supplied timing fields. No timing is invented when these fields are absent.

Wrath has no pinned generated API documentation or FrameXML consumer for this namespace. It must not publish `C_LossOfControl`.

`LossOfControlInfo` models spell cooldowns, not active effect records: its `modRate`, `isActive`, and `shouldReplaceNormalCooldown` fields do not fit the active-effect declaration. Active effects require a distinct record.

## Consumer proof

The original selected Retail and PTR `Blizzard_FrameXML/LossOfControlFrame.lua` `LossOfControlMixin:UpdateDisplay` branches on absent/present data. It must hide for the empty world, show a supplied effect with its text/icon, then hide after removal. PTR additionally requires two loaded environments to keep their displays and supplied state independent. No vendor code is replaced. The Retail proof retains byte-identical tests on seeded and corrected producers; the PTR proof requires byte-identical tests on the current producer and a sibling with only PTR LOC registration subtracted.

Retail `Blizzard_FrameXML.toc:126–128` and PTR `Blizzard_FrameXML.toc:135–137` select this consumer for mists/mainline (the middle entry is the Mists-only family override). Both profiles' `Blizzard_APIDocumentationGenerated/LossOfControlConstantsDocumentation.lua:10` declare active index 1. PTR XML:4,109–112 binds the original mixin and scripts; Lua:36–52 initializes the widths/animation handler, :229–240 queries and shows/hides, :149–208 presents supplied fields and :243–258 sets the remaining time. The PTR proof must complete the original OnLoad without replacing Edit Mode initialization. See the [implementation proof](../wiki/systems/lua-api.md#active-loss-of-control-state) for executed scope. The original model's seven-profile stock proof remains separate; this tests-only extension requires PTR stock before/after and seven separate zero-warning all-target checks.

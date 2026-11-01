# CF-2 Forever character, bank, account and guild consumers

Slice 6 covers six missing C API members consumed by the original WowForever Blizzard UI. The current cycle authors original-consumer tests only; producer work requires observed RED. Model ownership follows the [C API boundary](../../AGENTS.md#c-api-boundary); existing [factory follow-up](../wiki/systems/c-factory-startup-followup.md) describes preceding adapters.

## What it must do

### Guild Discord enablement

- [ ] With an explicitly seeded guild leader, the original `GuildControlUI_SetupSelected` menu generator reads live `discordClientEnabled` through `C_Discord.IsEnabled`; the Discord radio (data 4) is absent for 0, present exactly once for 1, absent again for 0.
- [ ] The original guild-ranks radio (data 1) stays selected and present exactly once; menu generation leaves selected tab 1 unchanged. Original menu descriptions, not authored menu stand-ins, are the observable output.
- [ ] Direct original generator invocation produces no additional recorded Lua errors. Existing loader errors are preserved. Source provenance must resolve to the profile cache's original GuildControlUI Lua.

### Native evidence required before state-dependent fixtures

- [ ] `C_PaperDollInfo.AmmoNeeded`: original Camelot `PaperDollItemSlotButton_OnLoad` must hide AmmoSlot when explicitly not needed and retain slot initialization when needed. **PENDING-NATIVE-ORACLE:** equipment exists, but no evidenced ammo-requirement mapping or live requirement input exists. Do not infer from class, ammo inventory, or ranged slot alone.
- [ ] `C_Bank.CanPurchaseBankTab`: original `BankPanelMixin` purchase prompt/first-tab decision must reflect supplied bank-type eligibility and retain independent types. **PENDING-NATIVE-ORACLE:** legacy purchased bank-bag slots are not purchased bank-tab metadata or eligibility. Do not derive tab eligibility from them or invent limits/costs.
- [ ] `C_AccountServices.GetPreferredDatacenterLocalities`: original guild-preference dropdown must expose the supplied paired IDs/names in order and select the staged ID. **PENDING-NATIVE-ORACLE:** no locality catalog/source exists; do not invent regional IDs, labels, order or empty defaults.
- [ ] `C_Ping.IsPingSystemEnabled`: original `CompactRaidFrameManager_OnLoad` must configure its restriction menu only when enabled. **PENDING-NATIVE-ORACLE:** `enablePings` exists but its relationship to availability is not established. Existing audit marks this API evidence-required; no assumed CVar alias.
- [ ] `C_Spell.GetTargetSpellID`: original `ItemButtonUtil.GetItemContext` must yield FeedPet for supplied active Feed Pet targeting and not for a different target spell when prior contexts are inactive. **PENDING-NATIVE-ORACLE:** active targeting cursor is unmodeled; current casts/book membership do not establish target spell identity.

## How it works

- [C API architecture rules](../../AGENTS.md#c-api-boundary)
- [Existing startup adapters and residuals](../wiki/systems/c-factory-startup-followup.md)
- [Ping availability evidence gap](patch-api-audit-manifest.md)

## Implementation inventory

- `tests/cf2_forever.rs` — original guild setup/generator, live CVar and roster seeds, concrete real-menu assertions; no producer implementation.
- `src/c_api/c_discord.rs` — existing enablement implementation reads `SimState.cvars`; publication currently restricted by existing retail epoch gate. Not edited in this phase.
- `src/c_api/c_account_services.rs` — account-save state only, not datacenter locality. Not edited.
- `src/c_api/item_spell/c_currency.rs` — existing bank tab-count constant, not an eligibility model. Not edited.
- `src/lua_api/globals/bank_storage_verbs.rs` — legacy bank-bag slots, not tab eligibility. Not edited.
- `src/lua_api/globals/combat_verbs.rs` — explicitly unmodeled targeting cursor. Not edited.
- `src/lua_api/workarounds/temporary/forever_bank_capability_defaults.rs` — existing named missing bank-policy/tab-catalog defaults; not evidence of eligibility and not edited.
- `src/lua_api/workarounds/temporary/forever_startup_capabilities.rs` — existing named targeting-condition default; not target spell identity and not edited.

## Tests asserting this spec

- `tests/cf2_forever.rs::original_guild_control_discord_radio_tracks_live_enablement` — authored, uncompiled/unrun, expected missing `IsEnabled` at original GuildControlUI line 70. File-level cfg registers it only on WowForever; other profiles register no such test, with no runtime N/A return.
- No executable populated fixture yet for the five pending members. Future acceptance requires native evidence and normal live model seed paths first; nil-boundary smoke tests alone cannot close them.

## Known gaps (current cycle)

- [ ] Admit and compile the authored fixture, observe intended original-consumer RED, then permit a separate producer commit. Compile/setup/provenance/other-callee failures are not RED.
- [ ] Resolve the five PENDING-NATIVE-ORACLE questions; author their populated fixtures before production code. Consumer paths, exact lines, questions and source hashes are in the external slice handoff.
- [ ] Establish GREEN on the same applicable selector after producer work; no startup-health or full-matrix claim from bounded menu proof.

## Out of scope

Other CF-2 slices, other-profile compatibility claims, network integrations, fabricated native defaults/lifecycle, vendor Lua changes, new temporary stopgaps, producer code before observed RED, builds/tests/checks in EDIT-ONLY, push and merge. C API backing models must remain in `src/c_api`; no Lua-global reclassification or new hiding cfg gates.

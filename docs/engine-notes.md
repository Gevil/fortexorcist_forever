# Engine notes — facts the code relies on, and where they came from

| Fact | Source |
|---|---|
| Forever = Retail 12.x engine, interface 16001, build 1.60.1.70707 installed | `<WoW>/.build.info`; CooldownMaster `Core/Compat.lua` ("Forever (1.60.x) is a Vanilla ruleset on the retail engine"); Thunderz96/forever-addon-kit findings table |
| `COMBAT_LOG_EVENT_UNFILTERED` registration fires `ADDON_ACTION_FORBIDDEN` | CooldownMaster `Core/Compat.lua:20-21` |
| Addons can't read buffs in combat (own included) | CooldownMaster changelog 2.0.2 / 2.0.3 (2026-10-20/27); forever-addon-kit "In combat, secret auras are locked" |
| Own `UNIT_SPELLCAST_SUCCEEDED` stays readable in combat | forever-addon-kit; CooldownMaster `Engine:RestartBuffFromCast` (`Core/Engine.lua:1188-1250`) |
| Cooldowns can be secret in combat | CooldownMaster `Core/Engine.lua:3450` comment |
| Secret numbers can't go into `Cooldown:SetCooldown`; use `C_Spell.GetSpellCooldownDuration` → `SetCooldownFromDurationObject` | forever-addon-kit "Secret timings and the Cooldown widget" |
| Comparing/`or`-ing a secret value throws | forever-addon-kit; BlizzThreatPlates patch notes (Atraeau/WoW-Addons `vendor/BlizzThreatPlates/PATCHES.md`) |
| `C_Spell.GetSpellCooldown` returns a table | kimgod1142/wow-tww-api-notes §3; CooldownMaster `Core/Compat.lua:26-37` |
| Top-level `RegisterEvent` can throw if the Lua state is already tainted | kimgod1142/wow-tww-api-notes §1 |
| Range checks plain in combat; `PLAYER_SWING` fires per auto attack | forever-addon-kit findings table |
| Client stops reporting Lua errors after 100/session | forever-addon-kit findings table |
| Bag items: `C_Container.GetContainerNumSlots/GetContainerItemID/GetItemCooldown`; trinkets `GetInventoryItemCooldown("player", 13/14)` | CooldownMaster `Engine:PollOneItem` (`Core/Engine.lua:3712-3736`), `ClassifyBagItem` (`:74-84`) |
| Soul Shards are inventory items on Forever | "Soul Shards Forever" addon (CurseForge); Wowhead Forever Soul Bags |
| Curse of Agony/Doom → Bane of Agony/Doom | mythicsim `data/spells.jsonl` (IDs 980/1014/11713, 603) |
| Client prefers `<Addon>_Camelot.toc` | Atraeau/WoW-Addons README (`tocSuffix`); CooldownMaster ships one |
| Login order: `PLAYER_LOGIN` **can be missed** by a frame registered during its own dispatch, so every module's login work runs in `OnEnable` (called directly by `FX.RunLoginPass`), the first `PLAYER_ENTERING_WORLD` carries the login pass when `PLAYER_LOGIN` did not reach us, and the `FX._loginDone` + `FX._enabledModules` pair makes the pass exactly-once. No Forte module registers `PLAYER_LOGIN` (only `Core/Init.lua`'s bootstrap frame), because one that registers it in `OnEnable` can wait for the session | `docs/research/upstream-addons-2026-11-03.md` §7.3 (`CDM@e5811752 Core/Init.lua:153-157, 214-218`); `addon/Forte_Core/tests/test_login_order.lua` |
| SavedVariables: the **ForeverSVFix premise is retired** — the tool's author declares the loader bug fixed by Blizzard, and the live `_forever_` install carries the stamp in **1 of 33** add-on folders (that one's `ForeverSVFixData` link dangles into the retired `_classic_beta_` path). The client's own order is *data first, then files*; `## LoadSavedVariablesFirst: 1` is the declared opt-in to the pre-script order, `## SavedVariablesPerCharacter:` is a client feature (31 installed TOCs). The `scripts/deploy.sh` SVFix block is shape handling, not a premise; the stamp's readability seam is `C_AddOns.GetAddOnMetadata` | `docs/research/upstream-addons-2026-11-03.md` §5 (`SVFix@c1591b1 README.md:1-5`, `RELEASE_NOTES_v1.0.1.md`; `Questie_Vanilla.toc:29`, `Auctionator.toc:24`, `TidyPlates_ThreatPlates.toc:12,26`) |
| The nameplate **cooperation protocol** (`C_NamePlates.ForbidNamePlates` / `ReleaseNamePlatesForAddon(<ownerId>, <ownerSet>)` / the `OnNamePlatesForbidden` script / `C_NamePlatesAreForbidden`) is used by 21 installed files but is **not declared** in our pinned 70707 catalog (10254 declarations: `C_NamePlate`, `C_NamePlateManager`, `FORBIDDEN_NAME_PLATE_*` only) — `scripts/api_lint.py` rejects it as an unknown namespace, so a plate-ownership plan stays out of the tree and nameplate work keeps the `GetFramesRegion()` geometry shape. Same split on the CVar law: `C_CVar.GetCVarDefault` is declared; the bare `GetCVarDefault`/`RestoreCVarToDefault`/`CVarIsHardSet` are not | `docs/research/upstream-addons-2026-11-03.md` §7.5–§7.6 (`install: EllesmereUINameplates_Init.lua:422-431,1226-1230,1627`, `TidyPlates_ThreatPlates/CVarsManager.lua:11-40`); our scan of `docs/api/wow-addon-api-agents/skills/*/references/generated/forever.json` (build 1.60.1.70707) |

Patterns adapted from CooldownMaster (MIT, wheelbarrel00/CooldownMaster):
cast-predict + reconcile, name-keyed tracking, `PlainOrNil`, frame pools, dirty-checked styling,
staggered polling, "inferred entries never pop ready".

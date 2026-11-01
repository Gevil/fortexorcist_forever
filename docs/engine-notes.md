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

Patterns adapted from CooldownMaster (MIT, wheelbarrel00/CooldownMaster):
cast-predict + reconcile, name-keyed tracking, `PlainOrNil`, frame pools, dirty-checked styling,
staggered polling, "inferred entries never pop ready".

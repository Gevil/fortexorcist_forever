# RdyGaming/hated-wow-mcp: static WoW addon knowledge/tooling MCP, not an in-game bridge (P3, 2026-11-11)

Tags: **[V]** verified in code or by running it (file:line, command or probe named), **[I]** inference, **[U]** unverified.
Subject: `https://github.com/RdyGaming/hated-wow-mcp` at `f6d79af7` (2026-11-09), plus the npm package `hated-wow-mcp@0.8.0`.
All work was in `/tmp/ingame-research/` (clone, `npm install` with a /tmp npm cache, a throwaway stdio MCP client `mcpcall.mjs`, a copy of our `addon/`). Nothing was written into the repo, the client folder or `~/.cache`. The only reads outside /tmp were repo files and one read-only look at the Proton `.build.info`.

## 1. Answer first

- **Can it do the develop+test loop for us (code in, game reload, errors out)? No.** It is a *static* knowledge and tooling server. It has no channel to the running client. [V] `grep` of `src/` (excluding the vendored exporter) for `WoWChatLog`, `SavedVariables/`, `Errors.txt`, `WTF`, `Logs/`, `xdotool`, `SendInput`, `/proc/` finds nothing. Its only reads from a game folder are `.build.info` and an `AddOns` directory listing (`src/config.ts` `readBuild`, `listAddons`).
- **What it is:** 27 tools (not ~20; `package.json`, `node dist/index.js --list`, `tools/list`). They are an Interface-API reference (functions, events, enums, structures, CVars), a search/grep over Blizzard's shipped UI source, a Lua linter, a TOC validator, an XML validator, an addon scaffolder, FileDataID/icon/atlas lookups, and a CASC-based model/texture/map exporter. The exporter is irrelevant to ForteXorcist.
- **Forever is a first-class flavor** (`forever`, Interface 16001, `_forever_`, product `wowf`; `src/config.ts:89-94` flavor entry, `:146-153` install dir, `:254-255` product `wowf`) with its own API index, UI-source index, CVar list and atlas index.
- **Forever API data is current only if you do not use the npm package as published.** `hated-wow-mcp@0.8.0` ships a Forever index generated 2026-11-01, which is the **70532-era** API. The git repo's committed index (2026-11-09) is the **70862-era** API, API-identical to our 70790 pin. [V] details in §4.
- **Secret-value coverage is partial and one layer thinner than our catalog.** It carries `SecretArguments` / `SecretReturns` per function and nothing else: no `SecretWhen*Restricted`, no `NeverSecret`, no event-payload `SecretValue`, no `ConditionalSecret`. [V] §5.
- **Its Lua lint found no real bug in our `addon/`.** It produced 3 error/warning hits in production code, all false positives or harmless, plus 40 info notes. It also *misses* four things our `scripts/api_lint.py` catches. It adds one class of check we do not have: bare-global removed/moved APIs (`UnitAura`, `GetSpellInfo`, `IsSpellKnown`) and taint rules. [V] §6.
- **Offline at runtime, no telemetry, no `.env` required.** [V] §7.
- **Recommendation: Extend, narrowly.** Mount it for the agents as a read-only reference tool, from a pinned git checkout (not `npx`), for three tasks: Blizzard UI-source/template/mixin/CVar lookup, a "bare-global removed in Forever?" lint pass on new Lua, and TOC sanity. Do **not** make it a source of truth for secrecy, signatures of `InCombatLockdown`-style globals, or the Camelot TOC convention. It does not replace layer 1 (`docs/api/wow-addon-api-agents`) or `scripts/gate.py`. §10.

## 2. Exact tool list (27) [V]

Source: `tools/list` over stdio from the installed 0.8.0 package (`out-api.json`), cross-checked against `src/tools/*.tools.ts`. `flavor` = enum `mainline|mists|cata|wrath|tbc|vanilla|forever`; default is `WOW_DEFAULT_FLAVOR`, else `mainline`. "Sync" = needs a one-off network sync before it works.

| Tool | Inputs (req = required) | Returns | Data / sync |
|---|---|---|---|
| `wow_api_search` | `query` (req), `flavor`, `namespace`, `limit` 1-100 | Matching functions with args/returns, doc text, `secretArguments`/`secretReturns` | bundled index, no sync |
| `wow_api_event_search` | `query` (req), `flavor`, `limit` | Event name + ordered payload | bundled |
| `wow_api_type_search` | `query` (req), `flavor`, `kind` (Enumeration/Structure/Constants/CallbackType), `limit` | Enum/struct/constant tables with fields | bundled |
| `wow_api_diff` | `name` (req) | Per-client availability (retail, mists, vanilla, forever) of a function/event/type; hints "moved into namespace" | bundled |
| `wow_api_stats` | none | Which data sets are loaded, sync dates, counts | bundled |
| `wow_ui_template_search` | `query` (req), `flavor`, `type`, `limit` ≤60 | Virtual XML templates, inheritance chain, mixins, file | UI-source sync |
| `wow_ui_mixin_search` | `query` (req), `flavor`, `limit` | Mixin definition site, composition, method list | UI-source sync |
| `wow_cvar_search` | `query` (req), `flavor`, `usedOnly`, `limit` | CVar default/category/scope/protected flag/help; UI usage sites | registry bundled in API index; usage needs UI-source sync |
| `wow_ui_grep` | `pattern` (req, JS regex), `flavor`, `ext` (lua/xml/toc), `pkg`, `pathContains`, `context` 0-6, `ignoreCase`, `limit` ≤200 | `file:line` hits over Blizzard Lua/XML | UI-source sync |
| `wow_ui_read_file` | `path` (req), `flavor`, `startLine`, `endLine` | Numbered file window (default 300 lines) | UI-source sync |
| `wow_ui_list_packages` | `filter`, `flavor` | `Blizzard_*` packages + file counts + commit | UI-source sync |
| `wow_lua_lint` | `code` or `path`, `flavor`, `knownGlobals[]`, `disable[]` | Diagnostics `line:col severity rule` | bundled |
| `wow_xml_validate` | `xml` or `path` | Element/attribute/nesting errors against `UI.xsd` | bundled `data/ui.xsd` |
| `wow_toc_validate` | `toc`(+`fileName`) or `path` (file or addon folder) | Per-TOC issues; folder mode also checks listed-vs-present files | none |
| `wow_addon_scaffold` | `name` (req), `flavors[]`, `author`, `version`, `notes`, `slashCommand`, `withFrame`, `withOptions`, `savedVariables[]`, `write`, `overwrite` | Generated TOC/Core.lua/XML; writes only with `write:true` | none. The only write tool besides the exporters |
| `wow_install_info` | none | Detected installs, build from `.build.info`, third-party addon folders | local files |
| `wow_file_search` | `query` (req; numeric = FileDataID), `under`, `ext`, `includeNonInterface`, `limit` | Path + FileDataID | game-data sync (listfile) |
| `wow_icon_search` | `query` (req), `limit` | Icon FileDataID + name + `SetNormalTexture` snippet | game-data sync |
| `wow_atlas_search` | `query` (req), `flavor`, `limit` | `SetAtlas` names, sizes, sheet FileDataID, build | game-data sync from wago.tools |
| `wow_data_status` | none | Which game-data sets are built | none |
| `wow_model_search`, `wow_model_export`, `wow_creature_search`, `wow_creature_export`, `wow_texture_export`, `wow_map_search`, `wow_map_export` | search: `query`(+`kind`/`x`,`y`/`flavor`/`limit`); export: `model`/`creatureId`/`displayId`/`texture`/`mapId` + `outputDir` (req), `format`, `animations`, `equipment`, `tiles`, `objects`, `flavor` | glTF/OBJ/PNG written to `outputDir` | read the local CASC install (`src/wowexport/`) |

Server `instructions` (sent at `initialize`) tell the model to check `wow_api_search` before writing game calls, use `wow_ui_grep` for Blizzard's own implementation, and run `wow_lua_lint` before finishing (`src/server.ts`).

Observed behaviour [V]: `tools/list` is 24,981 bytes for all 27. `initialize` returned in ~145 ms. Server RSS was 156-172 MB after loading the indexes. Probe results are in `/tmp/ingame-research/out-*.json`.

## 3. Static, not a bridge: the evidence [V]

- `server.js` at the repo root is only a local web UI that calls the tool handlers directly ("deliberately does NOT speak the MCP protocol"); it is unrelated to the client.
- `src/index.ts` runs a stdio MCP server (`StdioServerTransport`), or `sync` / `--list`.
- No tool reads `SavedVariables`, `Logs/`, `Errors.txt` or any BugSack/Mechanic output, and none can send input or trigger `/reload`. The Lua it analyzes is whatever you pass as `code` or `path`.
- So in our terms it covers only the first third of the loop ("is this API name/shape valid, is this TOC sane"), never "load it in the client and read the result". Those channels are for P1/P2/P4 (Mechanic, witchcraft, our own `/fx probe` and `/fx log`).

## 4. Where the data comes from and how current it is

### Sources [V] (`src/sync/api.ts:32-48`, `ui-source.ts:29-38`, `game-data.ts:43-45`)

| Data | Upstream | Shipped in package? |
|---|---|---|
| API index (functions, events, tables) | `Gethe/wow-ui-source` branch `forever` (`Blizzard_APIDocumentationGenerated`, raw.githubusercontent) | **yes**, `data/api-*.json` |
| global function list, event names, CVar registry | `Ketho/BlizzardInterfaceResources` branch `forever` | **yes** (inside the same JSON) |
| `UI.xsd` | `Gethe/wow-ui-source` **`live`** (retail) `Blizzard_SharedXML/UI.xsd` (`api.ts:697-701`) | **yes**, `data/ui.xsd` (70 KB) |
| UI source (4,491 files / 349 packages for Forever) | `git clone --depth 1 --branch forever https://github.com/Gethe/wow-ui-source.git` into the cache on the user's machine | no, fetched by `sync ui-source` |
| file index | `wowdev/wow-listfile` latest release CSV | no |
| atlas index | `wago.tools` DB2 export (its own error text says wago.tools uses bot protection and may answer HTTP 403 from datacentre/VPN addresses; `game-data.ts:310-313`) | no |

The index records only `generatedAt` and the branch name (`Gethe/wow-ui-source@forever`), **not a commit or build** [V: `jq` of `data/api-forever.json`]. The build must be inferred from dates.

### Currency vs our pin [V unless tagged]

Upstream `forever` branch commits (`gh api repos/Gethe/wow-ui-source/commits?sha=forever`): 70532 on 10-22; 70707 on 11-02 13:15Z; 70755 on 11-03; **70790 on 11-04** (our pin `eac30af`); 70840 on 11-06; 70862 on 11-07; **70888 on 11-10**.

| Copy | `generatedAt` | Forever functions / events | Build [I from the commit dates] |
|---|---|---|---|
| npm `0.8.0` (what `npx -y hated-wow-mcp` gives you) | 2026-11-01T12:34Z | 6617 / 1815 | **70532** (the newest `forever` commit before that time) |
| git `f6d79af7` (weekly-CI-committed, cron Mondays 06:00 UTC, `.github/workflows/sync-api.yml`) | 2026-11-09T15:15Z | 6621 / 1817 | **70862** |
| our vendored catalog | n/a | 1816 events | 70790, **API-identical to 70862** per `docs/api/wow-addon-api-agents/SOURCE.md` (Gethe compare 70790→70862: no `Blizzard_APIDocumentationGenerated` change) |
| installed client | n/a | n/a | **1.60.1.70888** (`wow_install_info` against the Proton prefix, from `.build.info`; our `SOURCE.md` still says 70707 for the client) |

- npm→git delta in the Forever index: +5 functions (`C_ActionBar.IsHighestSpellRank`, `C_BattleNet.GetDefaultTitleWhisperTarget`, `C_GameRules.SetForeverExperiencePresetPostLogin`, `…PreLogin`, `C_PetInfo.IsPetOrderMoveToPending`), -1 (`C_GameRules.SetForeverExperiencePreset`), +2 events (`PET_ORDER_MOVE_TO_PENDING_CHANGED`, `SETTINGS_HEADER_TEXT_UPDATE`). The npm copy is therefore missing real post-launch API. Our `SOURCE.md` already lists `C_ActionBar.IsHighestSpellRank` as landed by 70755.
- Git copy's events: 1816 literal names, **identical set** to our catalog's 1816 (`hated-only []`, `ours-only []`). [V]
- I ran `npm run sync-api -- forever` in the /tmp checkout (11.6 s, needs network + `tsx` from `npm ci`). It pulled the current 70888 docs. Versus the 11-09 commit the only difference is **one event payload**, `PARTY_INVITE_REQUEST`. So 70862→70888 changes at least one API doc that our 70790 pin does not have (not used by ForteXorcist as far as I know [U]).
- **To get fresh data: clone the repo and run `npm ci && npm run build`**, optionally `npm run sync-api -- forever` (needs the git checkout, `CONTRIBUTING.md:33-35`). The published npm package will lag by up to a week or whenever the maintainer next publishes (0.8.0 dated 2026-11-01 is still `latest`).

### Data-model defects I hit [V]

- `wow_api_search "InCombatLockdown"` returns `C_RestrictedActions.InCombatLockdown()`. That name does not exist as a call: our catalog declares `InCombatLockdown` as a *global* (`namespace: null`, `RestrictedActionsDocumentation.lua:443`). Same flavor's `wow_api_diff` correctly says "callable as a global", and the linter accepts the bare call. The cause is that the indexer builds `signature` from the doc *system's* namespace. The same happens to `GetArenaOpponentSpec` → shown as `C_PvP.GetArenaOpponentSpec` [I: same mechanism]. An agent trusting `wow_api_search` could write a call that errors in the client. Our catalog has 3 symbols the index lacks under the same name: `InCombatLockdown`, `GetArenaOpponentSpec`, `C_StringUtil.GetDefaultAbbreviationBreakpoints` (the last one's cause is [U]).
- `UI.xsd` is retail's, not Forever's (`api.ts:698`), so XML validation could differ for Forever-only elements [I].
- `wow_api_diff` says `COMBAT_LOG_EVENT_UNFILTERED` is a "valid event" on Forever (event-name list from Ketho). Valid-as-name is not the same as addon-registrable; our rule forbids it regardless.

## 5. Secret values / restricted APIs on Forever

What the index carries per function (`src/sync/api.ts:398-400,469-471`, `src/wowapi/types.ts`): `secretArguments` (3,952 Forever functions) and `secretReturns` (19). `ApiParam` and `ApiEvent.payload` have **no** secrecy field [V]. The CVar record has a `secure` (protected) flag.

Compared against our layer-1 record for the same symbols (both read directly) [V]:

| Symbol | Our catalog (`forever.json`) | hated index / tool output |
|---|---|---|
| `C_Spell.GetSpellCooldown` | `SecretWhenCooldownsRestricted: true`, `SecretArguments: AllowedWhenTainted` | only `secretArguments: AllowedWhenTainted` |
| `C_UnitAuras.GetAuraDataByIndex` | `RequiresUnitAuraAccess`, `SecretWhenUnitAuraRestricted`, `SecretArguments: AllowedWhenUntainted` | only `secretArguments: AllowedWhenUntainted` |
| `UNIT_COMBAT` payload `amount` | `"SecretValue": true` | `amount: number`, no annotation (also absent in the 11-09 data) |
| `SpellCooldownInfo` fields `isActive`/`isOnGCD` | NeverSecret boolean contract (Compat.lua comment cites it) | no secrecy info; fields carry only docs |
| `UnitHealth` | `SecretReturns: true`, `SecretArguments: AllowedWhenUntainted` | same two lines |

Our catalog's declaration JSON carries `SecretWhen*` in 243 records, `NeverSecret` in 148, `ConditionalSecret` in 15, payload `SecretValue` in 13 (substring counts, rough) [V]. None of that survives into the hated index.

Positives: it does expose the secrecy *API surface*: `issecretvalue` (system FrameScript, `secretArguments: AllowedWhenUntainted`), `IsPreventingSecretValues`, and the whole `C_Secrets.*` namespace (`GetPowerTypeSecrecy`, `GetSpellAuraSecrecy`, `GetSpellCastSecrecy`, `ShouldAurasBeSecret`, `CanCompareUnitTokens`, `HasSecretRestrictions`) with signatures. [V: probe]

The linter has **no secret-value rule**. A probe with `local info = C_Spell.GetSpellCooldown(1); if info.duration > 0 then print(UnitHealth("player") / 2) end` was flagged only with the generic `api/signature-changed` note for `GetSpellCooldown`, nothing about secret comparison or arithmetic. [V: `out-probe.json`] Its taint rules are the pre-12.0 model (`PROTECTED_FUNCTIONS`, `COMBAT_LOCKED_METHODS`, `src/lua/rules.ts`).

Net: **layer 1 stays authoritative for secrecy.** hated is at best a faster signature lookup that points you at the right symbol.

## 6. What its validators check that `scripts/gate.py` / `api_lint.py` do not

### What it actually ran on (all against `/tmp/ingame-research/addon-copy`, a `cp -r` of `addon/`) [V]

`wow_lua_lint` (flavor `forever`) on 164 `.lua` files (**including `tests/`**; our `api_lint.py` skips `tests/` and `Data/` and covers 64) took 317 ms in total. `wow_toc_validate` on all 16 addon folders reported 32 TOCs. `wow_xml_validate`: our addon has **no `.xml` files**, so it was exercised only with synthetic input. `python3 scripts/api_lint.py /tmp/ingame-research/addon-copy` was run for comparison: `[api-lint] 64 files, catalog 4380 C_ symbols / 966 enums / 1816 events: OK`. The right-hand column of the probe table below is from actually running `api_lint.py` on the same synthetic lines (`/tmp/ingame-research/synth/synth.lua`: 6 hits, exit 1), not from reading its code.

### Findings in our code (production, file:line) [V]

| Severity / rule | Where | Verdict |
|---|---|---|
| error `loadstring-in-addon` | `Forte_Core/Core/Loader.lua:185` | **False positive.** Line is `notice(name .. " did not load (" .. …)`. The line-based regex `\b(loadstring\|load)\s*\(` (`src/lua/rules.ts` `PATTERN_RULES`) matches the text `load (` inside a string literal. Only whole-line comments are exempted (`analyze.ts` "line-based pattern rules"). |
| error `taint/overwrite-api` | `Forte_Warlock/UI/Frame.lua:1014` | **False positive.** `time = time ~= nil and tostring(time) or ""` reassigns the *parameter* `time` of `Frame:SetExtraRowText(e, name, time)`. Cause in the analyzer: function parameters are never declared as locals, because the `else if (t.value === "function")` parameter branch (`analyze.ts:244`) is unreachable behind the earlier `BLOCK_OPENERS.has(t.value)` branch, whose set already contains `function` (`:79`, `:208`). A minimal repro `local function F(time) time = 5 … end` is flagged the same way. |
| warning `api/moved-to-namespace` | `Forte_Core/Core/Compat.lua:65` | Harmless. It is the deliberate fallback `elseif type(GetSpellCooldown) == "function" then return GetSpellCooldown(spellID)` under `Compat.GetSpellCooldown`; the global is guarded, and on Forever the `C_Spell` branch above wins. |
| info `api/signature-changed` (12) | `Forte_Cooldown/Core/Enchants.lua:282`; `Forte_Cooldown/Module.lua:92,643`; `Forte_Cooldown/UI/Timeline.lua:1323`; `Forte_Core/Core/Compat.lua:61,79,314`; `Forte_Hunter/Core/Tools.lua:1031,1048`; `Forte_Messages/Module.lua:457`; `Forte_Timer/Core/Casts.lua:123`; `Forte_Warlock/Core/Tools.lua:731` | Static reminders keyed on the call name (4 hard-coded entries in `rules.ts`); they fire on any use of `C_Spell.GetSpellInfo`/`GetSpellCooldown`, whether handled right or not. |
| info `onupdate-string-alloc` (15) | `Forte_Cooldown/Module.lua:930`; `Forte_Cooldown/UI/Splash.lua:575,589`; `Forte_Hunter/UI/Melee.lua:321,341`; `Range.lua:268,284`; `Reminder.lua:298,314`; `Swing.lua:2065,2083`; `Forte_Options/UI/Window.lua:928,935`; `Forte_Warlock/UI/Module.lua:158,172` | Fires on every `SetScript("OnUpdate"…)`; no analysis of the body. Noise. |
| info `global-frame-name` (13) | `Forte_Cooldown/UI/Splash.lua:176`; `Timeline.lua:593,1768`; `Forte_Hunter/UI/Melee.lua:125`, `Range.lua:123`, `Reminder.lua:88`, `Swing.lua:552`; `Forte_Messages/UI/Banner.lua:54`; `Forte_Options/UI/Window.lua:248,370,379`; `Forte_Timer/UI/Rows.lua:146`; `Forte_Warlock/UI/Module.lua:143` | Intended named frames. Noise. |
| info `print-left-in` (69) | all in `tests/` | Noise (test files should not have been linted). |

**Net: zero true bugs found in `addon/`.** TOC: 0 errors, 0 warnings, 178 "exists in the addon folder but is not listed in the .toc" notes, all under `tests/` (our `deploy.sh` and release exclude `tests/`, so these are expected). No non-test orphan file, no missing listed file.

### Behaviour probes (synthetic inputs, `out-probe.json`) [V]

| Defect class | hated `wow_lua_lint` | our `api_lint.py` |
|---|---|---|
| unknown `C_Spell.Foo` (known namespace) | **error** `api/unknown-namespaced` | flagged ("not in namespace") |
| unknown namespace `C_Nonexistent.Thing()` | **not flagged** | flagged ("unknown namespace") |
| unknown `Enum.NotAnEnum` | **not flagged** | flagged |
| unknown event literal in `RegisterEvent` | warning `event/unknown` | flagged (it also checks event-name *tables* [from code, not probed]) |
| `COMBAT_LOG_EVENT_UNFILTERED` | warning with *retail advice* (use `CombatLogGetCurrentEventInfo()`), i.e. does not know it is forbidden on Forever | not checked (policy rule in AGENTS.md) |
| `SetScript("OnEvent", function(...) handler(f, ...) end)` (frame forwarded as the event) | **not flagged** | flagged |
| Lua pattern `"a\|b"` alternation | **not flagged** | flagged |
| bare removed/moved globals: `UnitAura`, `GetSpellInfo`, `IsSpellKnown` | **warning**, with replacement (`C_UnitAuras.GetAuraDataByIndex`, `C_Spell.GetSpellInfo`, `C_SpellBook.IsSpellKnown`) | **not checked** (only `C_*.x`) |
| protected calls (`CastSpellByName`…), assigning Blizzard globals, `loadstring`, `setfenv`, `getglobal`, tokenizer-level syntax errors | yes | no (luajit syntax is in gate) |
| secret-value comparison/arithmetic | no | no (only the sim and review catch it) |

Other validators:
- **TOC** (`src/toc/parse.ts`): checks `## Interface` format and match against the flavor and filename suffix, missing `Title`, **unknown directives** (a fixed allow-list, `X-` prefix exempt), `SavedVariables` identifier validity, `LoadOnDemand` value, duplicate lines, non-`.lua/.xml` entries, backslashes, and (folder mode) **listed-but-missing = error**, present-but-unlisted = info. Our gate checks none of the file-list properties; it checks only twin byte-identity, `Interface == 16001`, and LoD-dependency coherence, which hated does not check. [V]
- **XML**: `UI.xsd`-derived element/attribute/nesting checks (probe: unknown attribute and unknown element caught). Irrelevant today (0 XML files); useful the day we add one.
- **Camelot TOC convention conflict** [V]: its config states Forever has "deliberately no filename suffix … no `_Camelot.toc` exists" (`config.ts:88-90`), and the scaffold for `flavors:["forever"]` emits one plain `X.toc` (`Interface: 16001`). `wow_toc_validate` treats our `X_Camelot.toc` as "all flavors (no filename suffix)". Our AGENTS.md requires an identical `X_Camelot.toc` twin; I found no evidence in the vendored `wow-client-targets` skill files either way. This is **unresolved** (P4/owner should decide with the client). Do not use hated's scaffold or TOC rules to change that convention.

## 7. Network, telemetry, env [V]

- **Runtime (stdio tool calls): offline.** I ran lint, TOC, XML and API search inside `unshare -rn` (an empty network namespace: only a DOWN `lo`). `initialize`, `tools/list` and all 4 calls succeeded, 0 errors, ~147 ms. `wow_ui_*`, `wow_file_*`, `wow_icon_*`, `wow_atlas_*` return "data set has not been built yet, run `npx -y hated-wow-mcp sync …`" as a tool error until synced; they never fetch on their own.
- `fetch(` / `git clone` appear only in `src/sync/{api,game-data,model-data,ui-source}.ts` (UA `wow-mcp-server/sync`), run only by the explicit `sync` subcommand (`src/index.ts`, spawns `dist/sync/index.js`). The vendored `wowexport/lib/generics.js` still contains an HTTP `get` helper and `constants.js` has Battle.net patch-server host strings, but THIRD_PARTY.md says the CDN fallback was removed and the exporter reads the local install only. I did not trace its call sites [U]; irrelevant to non-export tools.
- **Telemetry: none found.** No analytics/telemetry/sentry strings, no network primitives outside the above, dependencies are `@modelcontextprotocol/sdk`, `fast-xml-parser`, `zod` only. [V: tight grep over `src/`; `package.json`]
- `process.env` use is confined to `WOW_DEFAULT_FLAVOR`, `WOW_INSTALL_PATH`, `WOW_ADDON_PATH`, `WOW_MCP_DATA_DIR`, `WOWEXPORT_DATA`, `PORT` (web UI), and the OS cache-dir variables. **No `.env` file is read or required**; `.env.example` documents exported variables only and "all settings are optional".
- **Install-location trap** [V]: `findInstallations()` only auto-probes Windows/macOS default paths (`config.ts:157-165` `DEFAULT_INSTALL_ROOTS`; `:183` uses them only when `WOW_INSTALL_PATH` is unset), so on this Linux/Proton box nothing is detected unless `WOW_INSTALL_PATH` points at `…/compatdata/2691180173/pfx/drive_c/Program Files (x86)/World of Warcraft`. With it set, the server lists **`_classic_era_` first and `_forever_` second**, and `addonRoot()` takes the **first** install (`config.ts:275-279`). So without `WOW_ADDON_PATH` the file tools (including `wow_addon_scaffold write:true`) would default to the Classic Era AddOns folder. Always set `WOW_ADDON_PATH`.
- Writes: only `wow_addon_scaffold` (when `write:true`; refuses to overwrite without `overwrite:true`; confined to `WOW_ADDON_PATH`, `dev.tools.ts`) and the four exporters (into the `outputDir` you give). The synced data goes to `WOW_MCP_DATA_DIR`, else `./data` in a checkout, else `~/.cache/hated-wow-mcp`.

## 8. How to register it, and what it costs

OMP reads `~/.omp/agent/mcp.json` (skill `omp-mcp-server-register`). The skill `mcp-stdio-npx-hang-diagnosis` documents that `npx -y <pkg>` launchers have hung on this box (corrupt `~/.npm/_npx`), so use a pinned local install and the absolute `node` path.

```sh
git clone https://github.com/RdyGaming/hated-wow-mcp ~/.local/share/hated-wow-mcp
cd ~/.local/share/hated-wow-mcp && git checkout f6d79af7      # or a later weekly data commit
npm ci && npm run build                                      # verified in /tmp: ~2.5 s, 61 MB node_modules
node dist/index.js sync ui-source -- forever                 # optional; verified in /tmp: 3.2 s, 56 MB, forever @ 4cd0ab75 = 70888
npm run sync-api -- forever                                  # optional data refresh to upstream HEAD; verified in /tmp: 11.6 s, needs network
```

```json
"hated-wow": {
  "type": "stdio",
  "command": "/home/linuxbrew/.linuxbrew/bin/node",
  "args": ["/var/home/gevil/.local/share/hated-wow-mcp/dist/index.js"],
  "env": {
    "WOW_DEFAULT_FLAVOR": "forever",
    "WOW_ADDON_PATH": "/var/home/gevil/Work/Personal/wow-fortexorcist/addon"
  },
  "timeout": 30000
}
```

- Tools then appear as `xd://mcp__hated_wow_wow_lua_lint`, `…_wow_api_search`, etc. [I from the skill's naming rule]. Setting `WOW_ADDON_PATH` to our repo's `addon/` makes `path` arguments relative (`Forte_Core/Core/Loader.lua`) and refuses paths outside it. Absolute paths are rejected while it is set. Do not auto-approve `wow_addon_scaffold`.
- Do **not** set `WOW_INSTALL_PATH` unless you want `wow_install_info` (a read-only look at the Proton prefix), see the trap in §7.
- Cost [V]: startup ~145 ms, RSS ~160-170 MB, tool schemas ~25 KB (~6k tokens) if all 27 were inlined; xd:// devices are loaded on demand, so the practical cost is the short device summaries. Disk: package 14.8 MB unpacked; checkout + `node_modules` + `dist` ≈ 75 MB; UI source ≈ 56 MB; plus the 13 MB bundled `data/`. A fixed lint run of the whole addon was 317 ms.
- Maintenance burden: one `git pull && npm run build` per patch day; data refresh is committed by CI on Mondays and `workflow_dispatch`.

## 9. Licence and redistribution

- Project licence **MIT**, © 2026 Hated Gaming (`LICENSE`; `package.json`, `server.json`) [V]. Compatible with our GPL-3.0 project as a *tool* (we only run it; we copy no code). We would copy nothing from it.
- `THIRD_PARTY.md` covers only the **model exporter**: a headless port of `Kruithne/Marlamin wow.export` (MIT, commit `c2fd7bde`, licence text in `src/wowexport/WOW_EXPORT_LICENSE`) and the sync-time data (`WoWDBDefs`, `TACTKeys`, `wow-listfile`). It states "None of this is Blizzard game data, and no game files are downloaded or shipped" [V].
- **Does it redistribute Blizzard UI source? Not the 4,000-file UI source**: that is `git clone`d by the user's own machine from `Gethe/wow-ui-source` into the cache (not in the npm `files` list). **But the package does ship Blizzard-derived material**: `data/api-*.json` (generated from Blizzard's `Blizzard_APIDocumentationGenerated` plus Ketho's resource lists) and `data/ui.xsd` (Blizzard's own `UI.xsd`, byte-for-byte fetched, `api.ts:697-701`) [V: `package.json` `files`]. The README's closing line "All game data is fetched at runtime from public community mirrors and is not redistributed by this project" and `THIRD_PARTY.md` do not mention this, and `THIRD_PARTY.md` does not credit `Gethe/wow-ui-source` or `Ketho/BlizzardInterfaceResources`. For us this is only a note: we would run it locally and not ship it. [I] Not legal advice.

## 10. Maintenance health [V: `gh api`]

26 stars, 3 forks, 0 open issues, created 2026-08-11, last push 2026-11-09, 59 commits, single author ("Hated Gaming"), MIT, no GitHub releases but npm versions up to 0.8.0 (2026-11-01). Of the last 12 commits: two are automated data syncs (2026-11-02 `85fbc120`, 2026-11-09 `f6d79af7`), one is Forever launch support (`b0893aac`, 2026-11-01, "released client under `_forever_` / product `wowf`, full API lists"), the rest are exporter work and the 0.7.0/0.8.0 release commits (2026-10-31 to 11-01). It has a smoke test (`test/smoke.mjs`, "111 end-to-end checks") and a GitHub Actions build. Young, fast-moving, one maintainer; no issue history to judge responsiveness [I]. Open question: no stated policy on Forever API drift beyond the weekly cron.

## 11. Recommendation

`Verdict: Extend - hated-wow-mcp (git checkout, pinned) as an optional read-only MCP reference - it adds Blizzard UI-source/template/mixin/CVar search and a bare-global lint that our catalog and api_lint lack; it does not carry Forever secrecy annotations, has data-model defects (InCombatLockdown), and is not a bridge to the client.`

Add to the agents' toolbox **only for** these tasks:

1. **"How does Blizzard do X?"** `wow_ui_grep`, `wow_ui_read_file`, `wow_ui_template_search`, `wow_ui_mixin_search` against the Forever UI source (3 s sync, 56 MB). This is the one capability our layers do not offer as a ready tool; layer 3 (`wow-ui-sim`) has an extracted tree but no search tool. It is quicker than raw `git clone` + `grep` and gives `file:line`. Treat it as reading, not as proof of what an *addon* may call (layer 1's "Environment = All is not an addon permission").
2. **CVar lookup** (`wow_cvar_search`): default/scope/protected flag/help. Useful before any `SetCVar`. Forever's registry has 1,785 CVars.
3. **A second lint pass on new Lua** (`wow_lua_lint flavor:forever`, `disable:["print-left-in","onupdate-string-alloc","global-frame-name","api/signature-changed"]`, and **never on `tests/`**), for the bare-global removed/moved check, `loadstring`/taint rules and syntax. Expect the two known false-positive classes (string literals containing `load (`; reassigned parameters named like a Blizzard global). Do not use it in place of `api_lint.py`: it misses unknown namespaces, unknown `Enum.*`, vararg `OnEvent`, and Lua-pattern `|`.
4. **TOC sanity on new addon folders** (`wow_toc_validate path:<addon>`), especially listed-but-missing files and unknown directives. Ignore its flavor-suffix advice (see §6).
5. **Optional: `wow_xml_validate`** if we ever add XML.

Do **not** use it for: secret/restricted-API decisions (layer 1 only), exact signatures of globals that Blizzard documents inside a namespaced doc system (verify `InCombatLockdown`-style names against `docs/api` first), the Camelot TOC naming, anything about the running client, or the scaffold/exporters. Do not use `npx`, and do not rely on the published 0.8.0 package for Forever data.

Caveats / open questions:
- The Camelot twin-TOC question (§6) is unresolved and belongs to P4/owner with a real-client check.
- Its Forever API index has no build stamp; if we mount it, add a line to `docs/api/README.md` as layer 2.5 with "= 70862 data, fetched from Gethe `forever`, secrecy partial".
- Not verified: `sync api` as a subcommand name (only `npm run sync-api` was run); `wowexport` call sites; whether `wow_atlas_search` / `wow_file_search` work from this box (wago.tools bot protection was not tested; I did not run `sync game-data`); the XML validator against real Forever XML.

## 12. Evidence trail

`/tmp/ingame-research/`: `hated-wow-mcp/` (clone at `f6d79af7`, built, data refreshed to 70888 in the copy only), `pkg/` (npm 0.8.0), `addon-copy/` (copy of `addon/`), `mcpcall.mjs` + `calls-*.json` (probe client and calls), `out-api.json`, `out-api-checkout.json`, `out-lint.json`, `lint-all.txt`, `out-probe.json`, `out-probe2.json`, `out-offline.json` (empty-netns run), `out-ui.json`, `out-install.json`. Upstream refs: `gh api repos/Gethe/wow-ui-source/commits?sha=forever`, `gh api repos/RdyGaming/hated-wow-mcp`, `npm view hated-wow-mcp`. Our side: `docs/api/wow-addon-api-agents/SOURCE.md`, `docs/api/README.md`, `scripts/api_lint.py`, `scripts/gate.py`, `scripts/deploy.sh`, `AGENTS.md`, `PLAN.md` §11.10.

Side observations for the manager (not acted on): `docs/api/README.md` still describes layer 1 as pinned to 70707, whereas `SOURCE.md` says 70790; the per-file index in `SOURCE.md` still labels the catalogs "aff0d8cd5 (build 1.60.1.70707)"; the installed client is now 1.60.1.70888.

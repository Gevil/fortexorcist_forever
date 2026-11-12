# Falkicon/Mechanic — can it be our in-game develop+test loop on Linux/Proton? (2026-11-11)

Researcher: RsrchMechanic (Sonnet 5.5). Scope: P1 of PLAN §11.10. Read-only on the repo and the game folder; everything I ran lives in `/tmp/ingame-research/` (clone `mechanic/` @ `4cfcbb0`, 2026-11-01; venv `venv/`; scratch HOMEs `home/`, `home2/`; fake client root `fakewow/`). Nothing was installed into the game folder, no input was sent to any window, the game was not run.

Evidence tags: **[V]** verified (file:line / command I ran / URL read on 2026-11-11), **[I]** inference, **[U]** unverified.

## 1. Answer first

**Develop+test loop with Mechanic on Linux/Proton: PARTLY.**

- **Works natively on Linux, outside the Wine prefix [V].** The desktop side is a pure-Python (FastAPI + MCP) tool. I installed it into a /tmp venv (Python 3.14.8), pointed it at the real Proton path, and `diagnostic.targets`, `addon-output` (over a real stdio MCP handshake, 61 tools) returned the old 2026-09-18 data. No Wine, no copy into the prefix; it just reads host paths under `compatdata/.../drive_c/...`.
- **Game → agent channel = SavedVariables flushed at /reload or logout. Not live [V].** Mechanic does not watch the chat log, take screenshots, or talk to the client in any other way.
- **Agent → game channel = a generated Lua file loaded at the next addon load [V].** `lua.queue` rewrites `Interface/AddOns/!Mechanic/MechanicQueue.lua`; the client executes it with `loadstring` when `!Mechanic` loads. So: arbitrary Lua yes, but only at load time, *before* any other addon (incl. ours) has loaded, and the results only reach disk on the *next* reload/logout (two reloads per round trip).
- **It cannot reload the client on Linux [V].** Auto-reload (`--auto-reload`) is Windows (PowerShell SendKeys) and macOS (AppleScript) only; Linux returns False. There is no `reload` MCP tool. A human (or our own desktop-control tool) must type `/reload`.
- **Error capture needs `!BugGrabber`, which is not installed here [V].** Mechanic has no error handler of its own.
- **No screenshots, no CPU/memory export for arbitrary addons [V].** Per-addon CPU/memory exist only in the in-game Performance tab (not persisted); persisted perf = sub-metrics an addon registers itself.
- **Licence: GPL-3.0 (clean), usable as a dev tool; we should not vendor it (nothing to gain) [V].**
- **Net value vs our existing seams [I]:** our `/fx probe` → `ForteXorcistDB`, `/fx log on` → `WoWChatLog.txt` already cover the out-channel with the same reload latency. What Mechanic adds is (a) a prebuilt code-in channel, (b) MCP wrappers, (c) BugGrabber/Inspect UI for the owner. A ~30-line dev-only equivalent of (a) inside our own addon removes the third-party dependency and the early-execution limit (see §10).

## 2. What it is (components)

Repo root listing and `AGENTS.md` @ `4cfcbb0` [V]. 93 commits, created 2025-12-24, 26 stars, not archived, last push 2026-11-01, 10 open issues (all by the author; Linux/Proton appears in none) — `gh api repos/Falkicon/Mechanic`.

| Folder | What | Version (TOC / package) |
|---|---|---|
| `!Mechanic/` | **Bootstrap addon.** Loads first (`!` prefix). Ships LibStub + **MechanicLib-1.0** (registration API), owns the `MechanicDB` SavedVariable, executes the Lua/API queue at `ADDON_LOADED`. Files: `Bootstrap.lua`, `MechanicQueue.lua` (the queue file the desktop writes), `Bindings.xml`, `Libs/`. | 1.4.6 (`!Mechanic.toc`) |
| `Mechanic/` | **Main addon** (`Dependencies: !Mechanic`, `OptionalDeps: !BugGrabber, FenCore`). In-game hub UI (FenUI + Ace3): Inspect (frame tree/properties/watch), Console, Errors, Tests, Performance, Tools, API test bench (4,521 generated API defs). `/mech` slash, minimap button, bindings `MECHANIC_TOGGLE`, `MECHANIC_DEV_RELOAD` (calls `ReloadUI()`, no default key). | 1.3.7 (`Mechanic.toc`) |
| `desktop/` | **Mechanic Desktop**, Python package `mechanic-desktop` 0.5.0 (`requires-python >=3.10`): Click CLI (`mech`/`mechanic`), FastAPI dashboard on 127.0.0.1:3100 + WebSocket, `watchfiles` SavedVariables watcher, SQLite history (`~/.mechanic/data/mechanic.db`), 60-command registry on the hosted `afd` framework (PyPI `afd>=0.8,<0.9`), MCP adapter. Deps: afd, click, fastapi, uvicorn, watchfiles, pydantic, python-dotenv, requests; extra `mcp>=1.28`. | 0.5.0 |
| `.mcp.json` | `{"mcpServers":{"mechanic":{"command":"mech","args":["mcp"]}}}` — stdio. | — |
| `_TemplateAddon/` | Ace3 addon template (`TemplateAddon/Core.lua`, `DevMarker.lua`, `embeds.xml`, `.pkgmeta`, `.luacheckrc`, CI); `addon.create` copies it. `Core.lua` registers with MechanicLib behind a nil guard; the TOC declares `Interface: 120100, 16001`. | — |
| `docs/`, `tests/`, `PLAN/` | Integration guides (`docs/integration/*.md`), `addon-architecture.md`, 24 addon-dev guides; Lua (`*_regressions.lua`) and Node (`*_regressions.cjs`) offline harnesses; roadmap/PRD (compat workbench "proposed, not implemented"). | — |
| `AGENTS.md`, `CLAUDE.md`, `.claude/`, `.agent/` | Agent instructions; `.claude/skills/using-mechanic/SKILL.md` is the canonical reload/target protocol. | — |

Status per the repo itself: "The project is in alpha" (`README.md`); "CI … has not been run on GitHub for this tree" (`README.md`, Development section) [V]. Test status recorded in `AGENTS.md`: 707 collected / 700 passed (7 locale-parity failures) [V, not re-run by me].

## 3. OS support, Linux, Wine/Proton

- **Declared:** PyPI classifiers = Windows + macOS only (`desktop/pyproject.toml`). README: "Windows has the most complete desktop integration; platform-specific setup, file picking, links, and reload automation have limitations elsewhere" [V].
- **Linux code paths exist but are thin [V]:**
  - `config.py:get_common_wow_roots()` Linux fallbacks: `~/.wine/drive_c/Program Files (x86)/World of Warcraft`, `~/Games/World of Warcraft`. **Steam/Proton `compatdata/<appid>/pfx/...` is not auto-discovered** → set `wow_root` (or `MECHANIC_WOW_ROOT`) explicitly.
  - Config: `~/.mechanic/config.json`, `$XDG_CONFIG_HOME/mechanic/config.json`, `./mechanic.config.json`.
  - `utils.trigger_wow_reload`: win32 → PowerShell, darwin → osascript, else `# Linux not supported for window focus` → `False`.
  - `system.pick_file`: Windows only (`UNSUPPORTED_PLATFORM`).
  - `mech setup` tool downloader (luacheck/StyLua/Lua): Windows only; Linux must provide `lua5.1`, `luacheck`, `stylua`, `busted` on PATH (`desktop/README.md`, `setup.py` comment "linux — Unsupported but handle gracefully"). CI matrix has Linux, Python 3.10–3.13 (not run on GitHub per README).
- **Does it have to live in the Wine prefix? No [V].** I ran it from `/tmp/ingame-research/venv` with `HOME=/tmp/ingame-research/home` and a config `{"wow_root": "<compatdata path>/drive_c/Program Files (x86)/World of Warcraft", "flavors": ["_forever_"]}`:
  - `mech status` resolved the root; `mech --json call diagnostic.targets` returned the target `client=…/World of Warcraft/_forever_, account=GREATESTEVIL, character="Mann Sandstrider - Classic Beta PvP 2", profile=Default` with `sv_path` and `addon_path` (`…/_forever_/Interface/AddOns/!Mechanic`).
  - A stdio MCP client (`mcp.client.stdio`) listed 61 tools and `addon-output {"agent_mode":true}` returned the parsed old file (0 errors, 1 console entry, 1 Lua eval).
  - Python 3.14.8 worked although CI covers only 3.10–3.13; pydantic printed an `IncompleteFieldDefinitionWarning` on stderr (noise) [V].
- **Gotcha 1 — flavor list [V]:** default flavors are `["_retail_","_beta_","_ptr_","_classic_beta_"]`; `_forever_` is not in it. With a default config `diagnostic.targets` returned `{'targets': []}` on a root that had `_forever_/WTF/...`. Set `"flavors": ["_forever_"]` (verified). The code in `config.py:discover_saved_variables` walks `<root>/<flavor>/WTF/Account/*/SavedVariables/!Mechanic.lua`.
- **Gotcha 2 — chicken and egg [V]:** targets are discovered only from an existing `!Mechanic.lua`; `lua.queue` needs a target (exactly one candidate, or an explicit one). A fresh install needs one login+logout first. Here the old file provides a target, but its character key is the beta one (`Mann Sandstrider - Classic Beta PvP 2`); `Bootstrap.lua` drops the queue silently if `target.character` ≠ the logged-in `Name - Realm` (§5). After the first run with the new character a second candidate appears and every call needs an explicit `target`.
- **Addon links:** `addon.sync` makes symlinks from a `_dev_` source dir into each client (Windows: junctions). Whether Proton/Wine follows symlinks inside `drive_c` for WoW addons is **[U]**; our `scripts/deploy.sh` copies, which is the safe path.
- **File watching** uses inotify through `watchfiles`/`awatch` on the host path; irrelevant to Wine [I]. The watcher only reports "file changed"; it never proves a reload happened (the repo's own rule).

## 4. MCP server (`.mcp.json`)

- **Transport [V]:** stdio by default (`mech mcp`); `mech mcp --transport sse` serves SSE on `127.0.0.1:3101` (`--host/--port`), unauthenticated, warns on stderr. Server name `mechanic` (FastMCP, `mcp>=1.28`); my run: `serverInfo name=mechanic version=1.28.1`, protocol `2025-11-25`.
- **Naming:** registry names use dots, the MCP adapter replaces dots with dashes (Cursor compat); `fencore-*` are dashed natively; `system.pick_file` → `system-pick_file`.
- **Tools [V, listed from the live server, 61 = 60 registry commands + `mechanic-manifest`]:**

| Group | Exact MCP names | What they do |
|---|---|---|
| Meta | `mechanic-manifest`, `commands-list` | Categorised tool overview; full input/output schemas + read-only/mutating flags. |
| Diagnostics | `diagnostic-targets`, `diagnostic-metrics` | List client/account/character/profile identities (from `!Mechanic.lua`); bounded desktop overhead (+ last saved addon overhead snapshot with a target). |
| **Live-game bridge** | **`lua-queue`**, **`lua-results`**, **`api-queue`**, **`addon-output`**, `sv-parse`, `sv-discover` | Write snippets/API tests into `MechanicQueue.lua` (mutating); read saved Lua results; read saved errors/tests/console/libs/perf/Lua evals/API tests as markdown+JSON (`agent_mode` compresses); parse an SV file; find SV dirs. |
| Static dev | `addon-validate`, `addon-lint` (luacheck), `addon-format` (StyLua), `addon-test` (Busted), `addon-deprecations`, `addon-security`, `addon-complexity`, `addon-deadcode`, `docs-stale`, `locale-validate`, `locale-extract` | Offline analysers; need external Lua tools on Linux. `addon-deprecations` DB is a small seed (`DEPRECATION_DB_LIMITED`). |
| Offline sandbox | `sandbox-generate`, `sandbox-status`, `sandbox-exec`, `sandbox-test` | Restricted Lua 5.1 with generated WoW API stubs (no os/io/require outside addon, 30 s/60 s limits). Overlaps our wow-ui-sim gate; weaker. |
| API reference | `api-search`, `api-info`, `api-list`, `api-stats`, `api-populate`, `api-generate`, `api-refresh`, `api-download`, `atlas-scan`, `atlas-search` | Offline API/atlas lookup from generated 12.0.1 defs (not Forever 16001; Mechanic issue #17 open). Overlaps our vendored catalog. |
| Env/libs/assets | `env-status`, `tools-status`, `addon-create`, `addon-sync`, `libs-check`, `libs-init`, `libs-sync`, `assets-list`, `assets-sync` | Paths/tools; template instantiate; symlink/junction sync (`dry_run`); Ace3 sync; PNG→TGA. |
| Perf (offline) | `perf-baseline`, `perf-compare`, `perf-list`, `perf-report` | Store/compare numbers the caller supplies (they do not measure the client). |
| Release/git | `version-bump`, `changelog-add`, `git-commit`, `git-tag`, `release-all` | **Mutating, run with the user's permissions.** |
| Other | `dashboard-metrics`, `server-shutdown`, `docs-generate`, `research-query` (Gemini, network, needs `GEMINI_API_KEY`), `system-pick_file`, `fencore-catalog`, `fencore-info`, `fencore-search` | Dashboard/housekeeping; FenCore catalog only if that addon is loaded. |

- **Safety [V, `SECURITY.md`]:** MCP clients get command execution with the desktop process's permissions; annotations are not access controls. Expose a read-only subset if possible (there is no tool allow-list in Mechanic itself; if omp lacks per-tool filtering, the git/release tools stay callable) [U for omp].
- **Verified call (read-only):** `addon-output` returned "0 errors, 0 tests, 1 console, 0 API tests, 1 Lua evals", timestamp `2026-09-18 15:04:30`, 12 libraries.

## 5. The exact bridge mechanism

### Out (game → desktop): SavedVariables
1. Addons register via `MechanicLib:Register(name, caps)`; the main addon keeps them in memory.
2. On **`PLAYER_LOGOUT`** (fires for both `/reload` and logout) `Mechanic:OnPlayerLogout()` (`Mechanic/Core.lua` ~L565) runs `SyncAllAddonData()` — for every registered addon: `getDebugBuffer()` (last 50 lines kept), every `tests.getAll()` entry's `tests.getResult(id)` (called automatically, not clicked), `performance.getSubMetrics()` — plus `Console:PersistBuffer()` (100 entries) and the loaded-library list, all into `MechanicDB.profiles[<profile>]`. Each callback is `pcall`ed; a failure goes to the health log.
3. The client writes `WTF/Account/<ACCT>/SavedVariables/!Mechanic.lua` (+ `.bak` of the previous). **Nothing is written while playing** (`docs/integration/saved-variables.md`).
4. Desktop: `watcher.py` (`awatch`) sees the change, waits 100 ms, parses with its own SV parser (no Lua evaluation); MCP `addon-output` re-reads the file on demand. Only `!Mechanic.lua` and `!BugGrabber.lua` are read by the dashboard commands; **our own `ForteXorcistDB` is never parsed** — `sv.parse` on our `Forte_Core.lua` fails with `TARGET_READ_ERROR "Each profile must have a string name and table value"` [V, I ran it].

### In (desktop → game): queue file + `loadstring`
1. `lua.queue` (`commands/lua.py:write_lua_queue_file`) *rewrites* `<client>/Interface/AddOns/!Mechanic/MechanicQueue.lua` with `MECHANIC_DIAGNOSTIC_TARGET = {client,account,character,profile}` and `MECHANIC_LUA_QUEUE = {{label=…, code=[[…]]}, …}` (`api.queue` writes the API queue to the same file; writing one erases the other: "both … written fresh"). Non-atomic `write_text` (open issue #12). I ran it against a copy of the old SV in `fakewow/` and read the generated file [V].
2. The file is listed in `!Mechanic.toc` right before `Bootstrap.lua`, so it is just a normal addon file executed at load. The queue **is not cleared after running** — only the global is nil'd; `lua.py` has no clear step, so the same snippets re-run on every load until overwritten [V code]. The old SV shows the same snippet executed at 14:51:40 (in `.bak`) and again at 14:59:55 [V], consistent with that [I].
3. `Bootstrap.lua` (`ADDON_LOADED` for `!Mechanic`): guards that `target.character`/`target.profile` match `UnitName("player").." - "..GetRealmName()` and the profile; else **silently nils both queues**. Then `Mechanic:ProcessLuaEvalQueue()` runs each snippet: tries `loadstring("return "..code)`, falls back to `loadstring(code)`, `pcall`s it, stores `{label, code, executedAt, success, result (tostring; tables = first 10 k=v pairs), resultType | error}` in `MechanicDB.profiles[p].luaEvalResults`, prints "`[!Mechanic] Lua Eval: n passed, m failed`". `issecretvalue` guarded.
   - `Core.lua`'s `ProcessLuaEvalQueue` (0.5 s delayed, after init) is only a fallback — the bootstrap has already nil'd the global (issue #13 "Consolidate bootstrap and main-addon fallback queue execution").
4. **Consequences [V code, I interpretation]:**
   - Snippets run at `!Mechanic`'s `ADDON_LOADED` → **before `Forte_*` and nearly all other addons exist**, before `PLAYER_LOGIN`. Reading our frames/state from a snippet returns nothing. The owner's old run is the proof: it queried `_G["ForeverHunterUI_player"…]` → `player=MISSING, pet=MISSING, castbar=MISSING, hunter=MISSING …` while `UIParent` existed [V]; "not loaded yet" is my explanation [I] (the addon may also have been absent).
   - A snippet *can* defer: `C_Timer.After`/an event frame inside the snippet runs later and could write into any SavedVariables table (ours, or `MechanicDB`) [I; not tested].
   - Results reach disk only at the **next** flush: queue → `/reload` #1 (snippet runs after load; results in memory; `Core.lua` prints "Completed … /reload to save.") → `/reload` #2 or logout → `addon-output`/`lua-results`. The repo docs describe one reload; the code and the dated files say two [V: results of the 14:59:55 run appear in the file saved at 15:04:30, not in the 14:59:53 `.bak`].
   - Arbitrary code includes `ReloadUI()`/`RunScript`/`ConsoleExec` (`UI/API.lua` lists `ReloadUI`, `ConsoleExec`, `RunScript`… as restricted for the API-tab bench [V]; the queue code has no such list [V]; [I] that the bench list is a denylist) [V code; behaviour of `ReloadUI()` at load time **[U]**, and a persistent queue would loop — never do this].
5. **Reload trigger [V]:** none from the MCP side. `mech dashboard --auto-reload --src PATH` (watcher `src` change on a `.lua` file) calls `trigger_wow_reload(key)`: Windows — PowerShell, finds a process named `Wow*` whose main window title is exactly `World of Warcraft`/`(Beta)`/`(PTR)`, `AppActivate(pid)`, `SendKeys` (default `^+r`; CLI `--reload-key` default is actually `9`) which must match the in-game binding of `MECHANIC_DEV_RELOAD`; macOS — AppleScript keystroke. **Linux — `False`, nothing.** Not file-injection and not a window message. The README/AGENTS also forbid agents inferring reload completion from watcher events.
6. Forever title: the Windows helper matches exact titles `World of Warcraft…`; whether Forever's window title matches is **[U]** (irrelevant on Linux).

## 6. Capability matrix for our questions

| Capability | Verdict | How / limit |
|---|---|---|
| Execute arbitrary Lua in the client | **Yes, at load only** [V] | `lua-queue` → `/reload`; runs at `!Mechanic` `ADDON_LOADED`; no REPL; results need a 2nd flush; stringified values (tables: 10 pairs). |
| Run addon tests in game | **Partly** [V] | In-game tests = your own functions registered as `tests.{getAll,getResult,run}`; `getResult` is called for every test at every `PLAYER_LOGOUT` and stored (`addonData[addon].tests[id] = {passed,message,duration,logs,details[]}`); the Tests tab can run them by click (owner). No "run test X now" tool. Desktop-side tests (`sandbox-test`, `addon-test`) are offline. |
| Capture Lua errors | **Only with `!BugGrabber`** [V] | `UI/Errors.lua`/`output.py` read `BugGrabberDB`; grep for `seterrorhandler` in Mechanic: no match. `!BugGrabber` is **not installed** here and no `!BugGrabber.lua` SV exists [V, directory listing]; Forever compatibility of BugGrabber **[U]**. Our `/fx log on` already captures errors to chat/`WoWChatLog.txt` live. |
| Read addon state | **Only what the addon exposes** [V] | `getDebugBuffer` (50 lines), test `details`, perf sub-metrics, Inspect watch list (`inspect.getWatchFrames`, in-game UI), plus queued snippets (early). Your own SV is not read. |
| Screenshots | **No** [V] | grep: no screenshot/`Screenshot()` code anywhere. |
| Chat-log / combat log | **No** [V] | No `LoggingChat` use; console = `print` post-hook + `MechanicLib:Log` (AceConsole `:Print` and direct chat-frame writes are not captured: `docs/integration/troubleshooting.md`). |
| Measure performance | **Own sub-metrics only** [V] | Performance tab: UI-only `UpdateAddOnCPUUsage/MemoryUsage` per addon (needs `scriptProfile` CVar + reload, not persisted); persisted = `performance.getSubMetrics()` rows + `diagnosticOverhead` (Mechanic's own tickers, hub-sync ms). Real SV shows `inspect_ticker_active=true` — Mechanic's watch ticker is always on. |
| Live (non-reload) feedback | **No** [V] | "The data is a snapshot, not a live stream." |
| Reload from the agent | **No on Linux** [V] | see §5. |

## 7. How an addon integrates / what ForteXorcist would add

Integration API (`!Mechanic/Libs/MechanicLib/MechanicLib.lua`, MINOR 3; `docs/integration/mechaniclib.md`) [V]:
`LibStub("MechanicLib-1.0", true)` (nil when Mechanic is absent) → `:Register(name, {version, getDebugBuffer, clearDebugBuffer, tests={getAll,getCategories,run,getResult}, performance={getSubMetrics}, tools={createPanel}, inspect={getWatchFrames}, settings=<AceConfig args>})`, `:Log(addon,msg,category)`, `:AddToWatchList`, `:IsEnabled`. `_TemplateAddon` only registers `{version=…}`; `DevMarker.lua` is a git-only dev flag file (TOC `#@debug@` block) — a convention we do not need.

What FX would have to add (all optional, dev-only, no hard dependency) [I]:
1. **Guarded registration** in one place (module `OnEnable` / the login pass, never a top-level `RegisterEvent`): `local LS = _G.LibStub; local ML = LS and LS("MechanicLib-1.0", true); if ML then pcall(ML.Register, ML, "Forte_Core", {...}) end`. We ship no LibStub (no `Libs/`), so the `_G.LibStub` guard is mandatory. Load order: `!Mechanic` sorts first, and registration at PLAYER_LOGIN is late enough; adding `## OptionalDeps: !Mechanic` would be belt-and-braces but must be mirrored byte-identically in `Forte_Core_Camelot.toc` (gate rule) — probably unnecessary.
2. **`getDebugBuffer`** returning a ring of `FX.Log` lines (today `FX.Log` only prints to chat; Mechanic captures only `print` post-hooks and `MechanicLib:Log`). Cap is the last 50 lines per addon.
3. **`tests`**: wrap the in-client batteries — `Probe` groups (secret/plain classification, casts seen plain|secret|unresolved, SV round-trip), `/fx test` mode self-check — as `{id,name,category}` + `getResult(id)` returning `{passed,message,duration,details={{label,value,status}}}`. `getResult` runs at every `PLAYER_LOGOUT` (combat/secret state unknown), so it must return *stored* last-run results, never touch secret values live (route through `FX.Compat.PlainOrNil`; `SyncAllAddonData` copies result tables raw into SV [V code] — a secret value there would be unsafe [I]).
4. **`performance.getSubMetrics`**: `{name, ms, description}` for engine tick/sweep/row-render blocks (`debugprofilestop` brackets) — only worth it if we want trend numbers.
5. Optional `inspect.getWatchFrames` for the row/icon frames (owner-facing UI).
Cost: small guarded block; risk: none when Mechanic is absent. Our `AGENTS.md` rule "FX is file-local; no `if not FX`" applies to the new file.

## 8. WoW Forever support

- **TOCs [V]:** both `!Mechanic.toc` and `Mechanic.toc` declare `## Interface: 120100, 16001` (comma list; Retail 12.1.0 + Forever). **No `*_Camelot.toc` files exist in the repo** (searched). Our convention (`AGENTS.md`, `docs/research/curseforge-forever-publishing-2026-11-09.md`) is `X.toc` + byte-identical `X_Camelot.toc`, "the Forever client prefers `<Addon>_Camelot.toc`". Whether the Forever client loads Mechanic's single `X.toc` with the comma list and honours 16001 from it is **[U]** — no in-repo evidence of a live test for the 16001 TOC; the only live evidence is the old run below (a `120100`-only TOC).
- **Support timeline [V, git log/tags]:** v1.4.4/1.3.5 (2026-09-06, Interface 120100 only) → v1.4.5/1.3.6 (2026-09-18, commit `b1f3d5a` "Add WoW: Forever support", adds 16001) → v1.4.6/1.3.7 (2026-09-23). Desktop 0.5.0 (2026-09-30): TOC validation accepts `120100` and `16001`; PR #7 added the `_classic_beta_` flavor; PR #10 (`additional_wow_roots`, example "a WoW: Forever client under D:/Programs/World of Warcraft").
- **Known issues relevant to us:**
  - `_forever_` flavor missing from default flavors (§3). The beta install lived in `_classic_beta_`; the current client is `_forever_` [V, our PLAN notes + paths].
  - API definitions are Retail 12.0.1.64914 (4,521 APIs), not Forever 16001 (issue #17 open for 12.1); the in-game API tab/`api-*` tools can mislead for Forever-only/removed APIs [V].
  - Unreleased notes mention a `print` post-hook change (taint-friendlier), Toggle key fix, Errors/Inspect fixes (`Mechanic/CHANGELOG.md` [Unreleased]) — i.e. the installed code would be the unreleased `HEAD`, not a tag, if we want those.
  - Nothing in the repo mentions Proton/Wine problems (no issues, grep for `proton`/`wine`: only the config fallbacks above).
- **Repo weight [V]:** FenUI + Ace3 + 4.5k API-def tables, an always-on inspect ticker; fine for a dev profile, not for the owner's daily profile.

## 9. Licence

- GitHub says `NOASSERTION` ("Other") [V, `gh api`]. Cause: `LICENSE` (and `_TemplateAddon/LICENSE`, `Mechanic/Libs/FenUI/LICENSE`) is the full **GNU GPL v3, 29 June 2007**, but as a Markdown-formatted copy that does not match GitHub's licensee text. I diffed it word-by-word against `gnu.org/licenses/gpl-3.0.txt` (99.31 % identical): differences are `https`→`http` in URLs, §6's lead-in reads "meet all of these conditions" instead of "convey the machine readable Corresponding Source … in one of these ways", and the last sentence of §8 ("Termination of your rights under this section does not terminate the licenses of parties who have received copies…") is absent [V]. These are transcription defects of the standard text, not custom terms; no additional terms, exceptions or "or later" wording anywhere.
- Declared everywhere as **GPL-3.0**: `README.md` ("GPL-3.0 — see LICENSE"), both TOCs (`## X-License: GPL-3.0`), `desktop/pyproject.toml` (`license = {text="GPL-3.0"}`, classifier GPLv3). No "-or-later" ⇒ treat as GPL-3.0-only [I]. Embedded libs: FenUI is GPL-3.0 [V `FenUI/LICENSE`]; Ace3/LibStub/CallbackHandler/LibDataBroker/LibDBIcon carry their own upstream terms (BSD/public-domain, [U] not re-checked per file).
- **May we depend on / vendor it?** Our project is GPL-3.0 and wow-ui-sim (GPL-3.0) is already used "as a tool only". Depending on `!Mechanic` at runtime through the optional `LibStub("MechanicLib-1.0", true)` call is a soft, dynamic dependency (no code copied). Using the desktop tool from a venv is plain use. Copying code into our repo is permitted *because* both are GPL-3.0 (keep notices, record in `addon/Forte_Core/ATTRIBUTION.md`), but we have no reason to vendor; if we ever want the queue idea, write our own (§10). **Do not bundle `!Mechanic`/`Mechanic` into our release zip** (users install it themselves; it is a separate GPL-3.0 work with its own author) [I].

## 10. The old SavedVariables file

`…/_forever_/WTF/Account/GREATESTEVIL/SavedVariables/!Mechanic.lua` (3,211 B, mtime 2026-09-18 15:04:30 +02:00) and `!Mechanic.lua.bak` (3,210 B, mtime 14:59:53) [V, read both]:

- **Installed version: `!Mechanic v1.3.5`** — console entry "Addon registered: !Mechanic v1.3.5" and `addonData["!Mechanic"].version = "1.3.5"`. That is the **main addon** version (Mechanic.toc 1.3.5 ↔ bootstrap 1.4.4), the 2026-09-06 release, **before** Forever support (16001 was added in 1.3.6/1.4.5 the same day, 2026-09-18) and with a `120100`-only TOC. So the Forever beta client loaded an addon whose TOC lacked 16001 (probably via "load out-of-date addons") **[I]** and the full lifecycle worked: main addon initialised, Inspect ticker started (`inspect_ticker_active=true`, `active_tickers=1`), `PLAYER_LOGOUT` sync ran (`lastSync=1789736670`=2026-09-18 13:04:30 UTC, `librariesTimestamp` 15:04:30 local, `hub_sync_ms≈0.028`), libraries list persisted (AceAddon r13, AceConfig r3, AceConfigCmd r14, AceConfigDialog r92, AceConfigRegistry r22, AceConsole r7, AceDB r33, AceEvent r4, AceGUI r41, DropDown-ItemBase r2000, AceLocale r6, **FenUI 2.4.0**).
- **Character/profile:** `profileKeys["Mann Sandstrider - Classic Beta PvP 2"]="Default"` — a Forever **beta** realm name; one profile, `Default`. Account folder `GREATESTEVIL`. `size.width≈1000` (default window).
- **What it recorded:** 1 console line (`System`, `[Core]`, time 1789736396 = 14:59:56 local); `testResults`/`tests` empty; perf sub-metrics for `!Mechanic` itself (Console Buffer 1/1000, Health Log 0, Watch List 0); **no `!BugGrabber.lua`** ⇒ the Errors path was never populated.
- **It proves the queue channel was used by the owner:** `luaEvalResults.lastRun="2026-09-18 14:59:55"`, one result `snippet_1`, `success=true`, `resultType=table`, result `{_uiparent=table: …, player=MISSING, _gamepad=table: …, castbar=MISSING, target=MISSING, hunter=MISSING, targettarget=MISSING, pet=MISSING}`; the code (kept in the file) inspects `_G["ForeverHunterUI_<key>"]` frames (`GetPoint`, shown/visible/alpha/scale/parent/size, `fhuiPlain`), `GamepadPersistentInputLegend`, `UIParent`. The `.bak` holds an earlier run of the same snippet at 14:51:40 with the same shape. So: (a) snippets executed at `!Mechanic` load, (b) a persistent queue file re-ran at the next load, (c) results appeared one flush later, (d) the frames were `MISSING` at that time **[I: not yet created at `ADDON_LOADED`; the addon may also not have been present]**. No sign that the owner (or an agent) used `lua.queue` for anything after 2026-09-18; `!Mechanic`/`Mechanic` are **not currently installed** under `Interface/AddOns/` (89 folders listed; none match) and `_forever_/WTF/.../SavedVariables` has no newer Mechanic file [V].
- Safe to leave as is; it is also useful as a harmless fixture (`diagnostic-targets` works on it).

## 11. Health / maintenance [V, `gh api`, git]

Single author (Jason "Falkicon" Falk). 93 commits; 14 addon tags v1.0.0…v1.4.6 (last tag 2026-09-23); desktop 0.5.0 (2026-09-30, untagged); last commit/push 2026-11-01 (PR #19). 10 open issues, all author-filed roadmap items (queue atomicity #12, bootstrap/main consolidation #13, SV grammar #11, API refresh #17, macOS validation #15, Windows `setup_dev_env.bat` failure #2). 26 stars, no GitHub releases object, no Linux user reports. Expect slow, Windows-first evolution; extensive `.claude`/`.agent` agent skills suggest an AI-assisted workflow [I].

## 12. How we would wire Mechanic into our dev loop on this machine

**Option A — Mechanic as shipped (not recommended as the primary loop).**
1. *Owner:* decide whether to put third-party dev addons into the Forever install. (We would copy, not symlink: `!Mechanic/` and `Mechanic/` from a pinned clone into `…/_forever_/Interface/AddOns/`, via an extension of `scripts/deploy.sh`; symlink behaviour under Proton is [U].) Optionally also `!BugGrabber` (needs download; Forever compatibility [U]).
2. *Agent, in a venv outside the repo* (e.g. `/var/home/gevil/.local/share/mechanic-venv`): `pip install -c constraints-dev.txt -e "desktop[mcp]"` from a pinned clone. Config `~/.mechanic/config.json`: `{"wow_root": "/var/home/gevil/.steam/steam/steamapps/compatdata/2691180173/pfx/drive_c/Program Files (x86)/World of Warcraft", "flavors": ["_forever_"]}` (exact content verified to work, §3).
3. *Agent:* register an omp MCP entry `mechanic` = stdio, `<venv>/bin/mech mcp` (same as repo `.mcp.json`, but absolute path) — via the `omp-mcp-server-register` skill; restrict/ignore the mutating release/git tools [U whether omp can filter].
4. *Owner:* log in once with both addons enabled, `/reload` (so the current character lands in `profileKeys`, giving a correct target), then `diagnostic-targets` → pick the explicit `target` (the beta character will also be listed).
5. Loop per change: edit → `scripts/deploy.sh` (owner-approved) → `lua-queue` only if a load-time snippet is needed → **owner `/reload` #1** → play/trigger the situation → **owner `/reload` #2 or logout** → `addon-output {agent_mode:true, target}` → check `timestamp` is newer than the reload. For `ForteXorcist` state, rely on our own `ForteXorcistDB` (Probe) read directly; `sv-parse` cannot read it (§5).
6. Owner optional: bind "Reload UI (Dev)" (`MECHANIC_DEV_RELOAD`) in Key Bindings so a manager-driven keypress works; key injection from our desktop-control tool is a separate decision (ToS/Warden question belongs to P4) — Mechanic itself offers no Linux injector.

**Option B — recommended minimum [I]:** keep our out-channel (`/fx probe`, `/fx log on`, SV reading) and add only the in-channel idea ourselves, dev-only: a git-only `Forte_Core/DevQueue.lua` (excluded from `.pkgmeta` like Mechanic's `DevMarker.lua`) that, on `PLAYER_ENTERING_WORLD`, `pcall(loadstring(...))`s a snippet list from a generated file and writes results into `ForteXorcistDB.devResults` (flushed on the next reload). That avoids the third-party dependency, runs *after* our addons exist (Mechanic's blocker), and shares `deploy.sh`/`gate.py`. If the owner also wants Mechanic's Inspect/Console UI, do Option A's steps 1 and the guarded registration of §7 only (no desktop tool needed).

**Steps that need the owner (summary):** (1) approve installing `!Mechanic`/`Mechanic`(/`!BugGrabber`) into the live Forever folder; (2) enable them on the character list, log in, `/reload` ×1–2 per round trip (and once initially to create the right target); (3) optional key binding; (4) approval to install the Python venv and register the MCP server; (5) separate approval for any keypress injection (`/reload`) by the desktop-control tool.

## 13. Open questions

1. Does the Forever client (1.60.1.70862) load Mechanic's single comma-list TOC, or does it need `*_Camelot.toc`? (Test: copy to a throwaway profile, enable, check the addon list.) [U]
2. Do `UnitName("player")`/`GetRealmName()` resolve at `!Mechanic`'s `ADDON_LOADED` on Forever? If not, a targeted queue is dropped silently by the guard. [U]
3. Is BugGrabber working on Forever 16001? [U]
4. Do symlinks under `drive_c` load in Proton? [U]
5. Is a snippet deferral (`C_Timer.After` writing to a SV table) actually flushed correctly at `/reload` on Forever (our own `Probe` SV-stamp test in PLAN already addresses SV round-trip on 70707+)? [U]

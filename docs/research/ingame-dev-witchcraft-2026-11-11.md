# Geraldlol/witchcraft: can it give us develop + test in the running WoW Forever client? (2026-11-11)

Researcher: RsrchWitchcraft (read-only; PLAN.md §11.10). Subject repo: https://github.com/Geraldlol/witchcraft, cloned `--depth 1` to `/tmp/ingame-research/witchcraft` at `6b41409` (merge of PR #10, 2026-11-07), addon `Witchcraft/Witchcraft.toc` v0.2.0, interface 16001.

Tags: `[V]` verified in code or by a command I ran (file:line or command given). `[I]` inference. `[U]` unverified. Nothing here was tested inside a game client: I did not run WoW, send input to a window, or touch the game folder. The author's own docs say native in-game delivery, latency and combat behaviour still need recorded acceptance checks (`docs/MCP.md`, "Status").

## 1. Answer first

**Can Witchcraft do the develop + test loop for us on Linux/Proton? No, not as shipped. Parts of it are reusable, and one of its transports is a plain file lane that Linux can read.**

- Witchcraft is not a terminal inside the game's renderer. It is an addon window (ordinary Lua frames) that shows text, plus a Node daemon on the desktop that owns the real terminals. The two sides talk through files and screen pixels only. [V]
- Daemon to game: the daemon writes Lua data files into 3000 pre-generated load-on-demand helper addons (`Witchcraft_Chunk_0001..3000`). The addon calls `LoadAddOn()` on the next slot once a second or so and the file is run. [V]
- Game to daemon (typed text, button presses, WoW context, Lua errors): the addon paints a 132x12 px strip of coloured cells at the top-left of the game window. A PowerShell helper screenshots that region. A second carrier writes data into a key binding and persists it with `SaveBindings()`; the daemon watches `WTF/Account/.../bindings-cache.wtf`. [V]
- No keystrokes are sent to WoW, no window messages, no process-memory read, no injection. The only WoW-facing actions are a pixel read of a 132x12 region and file reads/writes in `Interface/AddOns` and `WTF`. [V] (§4, with the code.)
- It does not reload addons for you. A human types `/reload` (or confirms a dialog). The MCP error tool's description says "Use it after the player reloads an addon you changed". [V]
- Windows-only parts: the screen capture (PowerShell 5.1 + `System.Drawing` + `user32.dll`), mirroring an existing console (`AttachConsole`/`WriteConsoleInputW`), the Claude-Code management skill (`.ps1`), and CI (daemon tests run only on `windows-latest`). [V] Portable parts: node-pty, the ring/chunk writer, the binding-file reader, the MCP server. [V] I ran these on Linux (§5).
- For our setup the reusable value is in the ideas (Lua-error capture, a freshness-aware export format, a file-based host to game lane), not in the program. §7 lists them.

## 2. Mechanism: how a terminal is "inside" WoW

### 2.1 What the player sees

`Witchcraft/View.lua` builds a frame with text lines, an edit box and buttons. The terminal screen is data. The daemon runs each agent (Claude, Codex, Copilot) in a pseudo-terminal, feeds output to a headless xterm emulator, converts the emulated screen to colour-tagged WoW strings, and ships them to the addon. `tools/witchcraft-daemon/src/screen.js` (headless `@xterm/headless` + serialize addon), `src/pty.js:85-88`:

```js
const child = spawn(launch.file, launch.args, { name: 'xterm-256color', cols, rows,
  cwd, env: { ...process.env, TERM: 'xterm-256color' }, useConpty: true, useConptyDll: false });
```

`useConpty` only affects Windows. On Linux node-pty uses forkpty (verified, §5).

A second, separate presentation exists: an optional Electron overlay window (`src/overlay-electron-main.js:75-76`: `transparent: true, frame: false, alwaysOnTop: true`). It is a desktop window floating above the game. It does not render into the game and does not talk to the game process. [V]

### 2.2 Daemon to game: the "ring" of helper addons

Lua side `Witchcraft/Core.lua:1307-1308` (the load tick):

```lua
local ok, loaded = false, false
if self.api.LoadAddOn then ok, loaded = pcall(self.api.LoadAddOn, name) end
```

`name` comes from `Ring:Next()` = `string.format("Witchcraft_Chunk_%04d", nextSeq)` (`Witchcraft/Ring.lua`). The comment at `Core.lua:~1161` says "A generated slot runs synchronously inside LoadAddOn". Each slot is single-use per UI session: `methods:Consumed` advances the cursor even if the file was empty (`Ring.lua`).

Daemon side, `src/init.js:35` writes each slot at install time (I ran this, §5):

```
## Interface: 16001
## Title: Witchcraft stream 1
## LoadOnDemand: 1
## Dependencies: Witchcraft
## X-Witchcraft-Chunk: 1

Chunk.lua
```

with a placeholder `Witchcraft_ReceiveChunk({["protocol"]=1,["ready"]=false,["ringSize"]=3,["seq"]=1})`. At run time `src/ring.js` (`RingWriter.publish`) atomically rewrites only the slot the game asked for next, with `Witchcraft_ReceiveChunk({...serialized screens...})` (`src/lua.js: serializeChunk`, data-only serializer with byte/node budgets, 1 MiB chunk cap). The addon's global `Witchcraft_ReceiveChunk` validates the table (`Ring.lua OnChunk`: protocol, seq, epoch, UI nonce, ack monotonic, text control-char filter, 8192 B per line, 300000 B per session).

Why 3000 folders: the client only learns about addons at startup, so the slots must exist before WoW starts. This is why the README insists on a full WoW restart after `init`. Single-use slots imply the client does not re-read an already-loaded addon, which is the author's design assumption; I did not observe it in game. [I]

Ring pacing: base rate 1 Hz (`Ring.New` hz 1), doubles up to 8 s while nothing changes (`Ring.lua OnChunk`: `self.delay = (payload.changed or newEpoch) and self.baseDelay or math.min(8, self.delay * 2)`). When all 3000 slots are used the addon asks the user to `/reload` (`Core.lua MaybeReload`, `ConfirmReload` popup; since "Unreleased" it never reloads silently). On shutdown the daemon scrubs every written slot back to the placeholder because chunks contain the whole terminal transcript (`ring.js scrubSlot/stop`).

### 2.3 Game to daemon: two carriers, and one that reads the filesystem on reload

1. **Pixel strip** (`Witchcraft/Pixel.lua`, `View.lua:1208`, `capture-strip.ps1`). The addon encodes each message into frames of 22 cells; each cell is a colour with 2 bits per channel (`rgb(value)` = `{floor(v/16)*85, floor(v/4)%4*85, v%4*85}`), 6 bits per cell, checksum cell last. `cell:SetColorTexture(r, g, b, 1)` paints them. The daemon screenshots a calibrated 132x12 region at 5 fps (`capture-strip.ps1`: `Graphics.CopyFromScreen`) and decodes (`src/pixel.js`). Capture only runs while the foreground process is named `WowB` (`ForegroundIsWow()` compares `process.ProcessName` with "WowB"). Calibration screenshots the whole virtual desktop once to find the strip (`/witch calibrate` then `witchcraft calibrate`). Payload bandwidth is roughly 55 bytes/s (`docs/MCP.md`).
2. **Binding carrier** (`Witchcraft/Binding.lua`, `src/binding-carrier.js`). The addon claims a verified-empty key from `CTRL-ALT-SHIFT-F12/F11/F10/F9`, binds it to `CLICK WitchcraftCarrier_V1_<epoch>_<nonce>_<uiNonce>_<slot>_<seq>_<part>_<count>_<base32 payload>_<crc32>:LeftButton` via `SetBinding`, then `SaveBindings`. The daemon watches `bindings-cache.wtf` under the account folder (`discoverBindingFiles`, `readStableBindingFile` double-read, `fs.watch`). The binding names a click on a frame that does not exist, so it can never execute (`Binding.lua` header comment). After the host acknowledges through the ring, the addon restores the exact prior binding. Everything is skipped in combat (`methods:Claim`: "Carrier paused in combat"). Payload is at most 32 bytes per frame, up to 32 frames.
3. **SavedVariables recovery path** (`src/outbox.js watchSavedVariables`, `parseSavedVariables`). Typed input queued in `WitchcraftDB.global.outbox` reaches the daemon whenever WoW flushes `WTF/Account/<ACC>/SavedVariables/Witchcraft.lua` (reload/logout). The daemon parses it with `luaparse` as literal data only (node/depth/byte budgets, "Nothing from the file is executed").
4. **Optional, off by default:** a cooldown-viewer carrier that stuffs frames into the client's `cooldownmanager.txt` via `C_CooldownViewer.GetLayoutData/SetLayoutData` (`CooldownCarrier.lua:274-275, 349`), and an addon-state carrier that toggles `WitchcraftStateBit###` pseudo-addons through `C_AddOns.EnableAddOn/DisableAddOn/SaveAddOns` (`AddonsState.lua:57-58,100,117,125`). Both write the player's real game settings and are pinned to client build 1.60.1.70205 in `Evidence.lua`; they stay off on any other build. For us these are not worth the risk.

Typed text path: user types in the addon edit box, addon encodes it as `{epoch, id, tab, action, text}` (`Pixel.Encode`; actions `text|enter|interrupt|escape|up|down`), carrier delivers it, `Outbox.accept` (`outbox.js`) maps it to bytes and writes them into the right PTY (`TerminalPair.write` -> `session.process.write`). Mapping (`outbox.js`, `ACTIONS` constant near the top): `enter '\r'`, `interrupt '\x03'`, `escape '\x1b'`, `up '\x1b[A'`, `down '\x1b[B'`; text becomes `text + '\r'`, multi-line text becomes a bracketed paste. Messages carry IDs and an ack, so delivery is stop-and-wait with dedupe per daemon session.

Joined sessions (the default): `--cwd` makes the Claude tab mirror an already-running Claude Code console. That is done by a PowerShell helper that calls `AttachConsole`, `ReadConsoleOutputW`, `WriteConsoleInputW`, `VkKeyScanW` (`console/console-mirror.ps1:28-63`). Windows-only. [V]

## 3. The MCP server

Source: `tools/witchcraft-daemon/src/mcp-server.js`, `guide-tools.js`, `adventure-tools.js`, `bin/witchcraft-mcp.js`.

- **Transport:** MCP over local **stdio** (`serveStdio` from `@modelcontextprotocol/server` 2.4.0). No listening port. Server name `witchcraft-wow` version `0.1.1`. [V]
- **Launch:** `node <repo>/tools/witchcraft-daemon/bin/witchcraft-mcp.js [--cache <abs path>] [--allow-local-writes]`. The daemon injects it into spawned `claude`/`codex`/`copilot` command lines (`src/mcp-launch.js`; Copilot via `--additional-mcp-config`). A joined Claude session needs `witchcraft mcp-setup --apply` once. [V]
- **Tools (15), verified by running the server on this machine** (initialize + `tools/list` over stdio, §5):
  - Game context (read-only): `wow_get_context`, `wow_get_character`, `wow_get_quests`, `wow_get_progress`, `wow_get_errors`. Resource: `wow://context`.
  - Reference/guide (read-only, bundled Classic catalog, not verified Forever data per the README): `wow_find_guide`, `wow_explain_quest`, `wow_get_loot_sources`, `wow_get_loot_plan`, `wow_rehearse_dungeon`, `wow_suggest_detours`, `wow_get_passport`.
  - Local writes, only with `--allow-local-writes` (they write JSON beside the cache on the PC, not the game): `wow_set_loot_goal`, `wow_stamp_passport`, `wow_set_passport_campaign`. They carry `readOnlyHint:false, destructiveHint:true`.
  - All tools take an empty strict input object for the context group (`z.object({}).strict()`); no tool performs a gameplay action or types into a terminal (server instructions: "No tools control gameplay or terminals").
- **What data:**
  - `player` domain: name, class, level, map id, zone, subzone (`Context.lua:157-160`: `UnitLevel`, `GetZoneText`, `GetSubZoneText`, `C_Map.GetBestMapForUnit`).
  - `quests`: up to 10 tracked quests, 4 objectives each, via `C_QuestLog.GetNumQuestWatches / GetQuestIDForQuestWatchIndex / GetTitleForQuestID / IsComplete / GetQuestObjectives` (`Context.lua:161-166`). Title/objective text is capped at 64 bytes, character/location fields at 40.
  - `progress`: money, XP, rested XP, instance/difficulty, group size, own role, dead/ghost, in combat (`Context.lua:168-176`). Nothing about other players.
  - `errors`: see §3.1.
- **How the data leaves the client:** only through the carriers in §2.3, never through a network socket. The addon assembles the domain, encodes it as context frames (`Pixel.EncodeContext`, sync marker 50, max 580 bytes of text per message, at most 10 parts for quests), the daemon assembles, validates and atomically writes `tools/witchcraft-daemon/.local/wow-context.json`. Each MCP adapter process only reads that file.
- **Pull model, not a stream** (`docs/MCP.md` "Delivery and freshness", `context-want.js`): when a tool finds a domain stale it writes `wow-context.want.<domain>.json` (`{protocol:1, requestedAt}`) next to the cache and waits up to 12 s (`CONTEXT_WAIT_MS`, polling 150 ms). The daemon folds new wants into the next ring chunk as `contextWant`/`contextWantMask` (bits: 1 player, 2 quests, 4 progress, 8 errors; chunk `contextProtocol: 4`). The addon then captures and sends that domain. `wow_get_errors` re-requests any copy older than 5 s (`ERRORS_MAX_AGE_MS`). A want older than 60 s is ignored.
- **Freshness:** older than 180 s = `stale`; no heartbeat for 30 s = `disconnected`; ages include a conservative 30 s retransmission allowance (`docs/MCP.md`). Author-measured latency over the strip: player 3.1 s, player+progress 6.6 s, measured 2026-09-24 (code comment in `mcp-server.js`, not reproduced by me). Quest snapshots "can take tens of seconds"; carriers pause in combat; so the data is never live in combat.
- **Cache shape** (observed from the server's real answer with no game attached, §5):
  `{"schemaVersion":1,"source":"witchcraft-addon","session":null,"enabled":null,"lastHeartbeatAt":null,"savedAt":<ms>,"errors":{"status":"missing","ageSeconds":null,"data":null},"status":"unavailable","reason":"cache-missing","connection":{"status":"unknown","ageSeconds":null}}`. Each domain carries `status` (`fresh/stale/missing/...`), `ageSeconds`, `data`, `receivedAt`.

### 3.1 Lua-error capture path (`Witchcraft/Errors.lua`)

This is the most reusable piece. [V]

- Loaded first in the TOC (`Evidence.lua`, `Errors.lua`, then the rest), so it hooks early. `Errors.Install` calls `geterrorhandler()`, then `seterrorhandler(handler)`. The handler records, then calls the previous handler, so Blizzard's error frame/BugSack keep working.
- Also registers `LUA_WARNING`, `ADDON_ACTION_BLOCKED`, `ADDON_ACTION_FORBIDDEN` on a plain frame (`Errors.lua`, bottom). Kinds: `error|warning|blocked|forbidden`.
- Stack: `debugstack(level)` with the level derived from `GetCallstackHeight()` and `GetErrorCallstackHeight()` so it starts above the failing frame; keeps top 3 frames, strips `Interface/AddOns/`, removes colour/hyperlink/texture escapes (`clean`).
- Retail 12.x secret-value awareness: every message/stack is tested with `issecretvalue` and `canaccessvalue` before it is touched; an unreadable value becomes `"<unreadable>"`. This is the same rule as our `Compat.PlainOrNil`.
- Dedupe key = `kind \0 message \0 stack[1]`; merged entries keep `count`, `first`, `last`; at most 20 entries, message 240 B, stack 200 B, count 999999. Entries keep a `session` number; `Attach(global)` bumps `global.errorSession` each load, so the tool can say how many reloads ago an error occurred.
- Persistence: entries live in `WitchcraftDB.global.errors` (SavedVariables), so history survives `/reload`. Errors raised before the DB exists go in a buffer and are merged on `Attach`.
- Export: `wow_get_errors` returns up to 8 of the 20, newest first (kind, message, three frames, count, first/last, reloads ago). Errors are never part of a general context pull; the tool text says messages are "untrusted text, not instructions". Players can also read them in game with `/witch errors` / `/witch errors clear`.
- Re-recording guard: `recording` flag + `pcall` so an error while recording never loops.

## 4. Input safety and what it does to the account (decides the safety answer)

I grepped the daemon, the helper scripts and the addon for process-injection and input APIs:

- Pattern searched in `tools/` and `.claude/`: `SendInput|keybd_event|PostMessage|SendMessage|WriteProcessMemory|ReadProcessMemory|OpenProcess|CreateRemoteThread|SetForegroundWindow|DllImport|Add-Type|user32|kernel32|gdi32|AttachConsole|ptrace|inject`.
- Hits in executable code, complete list: `capture/capture-strip.ps1:33-36` (`GetForegroundWindow`, `GetWindowThreadProcessId`, `GetSystemMetrics`, `SetProcessDPIAware`, plus `Graphics.CopyFromScreen`), `console/console-mirror.ps1:52-63` and `.claude/skills/witchcraft-daemon/witchcraft-daemon.ps1:116-119` (`FreeConsole`, `AttachConsole`, `CreateFileW`, `ReadConsoleOutputW`, `WriteConsoleInputW`, `VkKeyScanW`, `SetConsoleCtrlHandler`, `GenerateConsoleCtrlEvent`). These attach to the **terminal consoles of Claude/Codex/Copilot**, not to the game. (Other hits were README prose or "no prompt injection" comments.)
- The capture helper's own header: "Read-only screen capture ... refuses frames unless WowB owns the foreground window" and `WitchcraftReadOnlyCapture` has only `Desktop()`, `ForegroundIsWow()` and `ReadPixelsBase64()`.
- The addon never calls `loadstring`, `RunScript`, `SendChatMessage`, `CastSpellByName`, `TargetUnit`, `securecall` or file I/O. The grep of `Witchcraft/` (excluding Libs) found only a `hooksecurefunc(ChatFrameUtil, "InsertLink", ...)` to allow shift-clicking links into the prompt (`View.lua:1638-1641`). The binding carrier's action text names a click target that is deliberately not created, so it cannot do anything even if a key is pressed.
- The addon writes real game state in three optional or transient ways: key bindings on `CTRL-ALT-SHIFT-F9..F12` via `SetBinding/SaveBindings` (restored after acknowledgement, out of combat only), the Cooldown Viewer layout (opt-in), and addon enable state (opt-in).

Conclusion on the account question [I]: no process-memory access, no injection, no synthetic input into WoW. It exfiltrates player data by drawing coloured cells that a program screenshots. That is a well-known shape for external helpers, so Blizzard could view it with suspicion even though nothing here automates gameplay. Blizzard's policies as read: the add-on policy (item 3: no "unnecessary loading from the hard disk", relevant to a once-a-second `LoadAddOn` poll and 6000 extra files; item 7: addons must follow the ToU/EULA; https://us.forums.blizzard.com/en/wow/t/ui-add-on-development-policy/24534, 2009) and the 2025-08-05 enforcement post (EULA 1.C "Cheating": code "which changes and/or facilitates the gameplay"; https://us.forums.blizzard.com/en/wow/t/prohibitions-on-third-party-software/2142972, 2025). I found no statement about WoW Forever specifically, and I found no Blizzard statement about pixel-reading helpers. I cannot give a ban-risk number.

Third-party risk the author documents: every enabled addon can type into every agent session. WoW addons share one Lua global space and `WitchcraftDB` / `Witchcraft_ReceiveChunk` are readable (`README.md` "Security and privacy"; open issue #2 "Hardening: other addons can inject into the outbox and binding carrier"). The author declined frame signing and promised a hold-Enter gate for permission prompts; the issue is still open. Not a fit for an agent with edit rights on a machine where you run other addons, unless the agent runs with a restricted config.

## 5. What I ran on this Linux box (Node v26.7.0, node 24+ required by `package.json`)

All inside `/tmp/ingame-research/witchcraft` or `/tmp/ingame-research/fakewow` (a fake `_forever_/Interface/AddOns` + `WTF/Account/ACC` tree). Nothing touched the real game folder.

| Check | Command (abridged) | Result |
|---|---|---|
| Dependencies | `ELECTRON_SKIP_BINARY_DOWNLOAD=1 npm ci --ignore-scripts` in `tools/witchcraft-daemon` | 38 packages installed |
| node-pty on Linux | `npm rebuild node-pty --ignore-scripts=false`, then spawn `/bin/echo` with `useConpty:true` | built; output `"pty-ok\r\n"`, exit 0 |
| Tests | `node --test` | 11 tests: 10 pass, 1 skipped ("the .exe rule applies on Windows only"). The suite in `test/` is mostly Copilot-routing, so this says little about the carriers. |
| Chunk generator | `node bin/witchcraft.js init --ring 3` against a Linux absolute `addonsDir` | created `Witchcraft_Chunk_0001..0003` with the TOC/`Chunk.lua` quoted in §2.2 |
| Daemon boot | `witchcraft.js run --only claude --no-pixels --no-mcp --no-current --no-overlay --cwd /tmp -- /bin/cat`, 8 s | printed the banner, stayed up until the timeout, no crash. No chunk written (it only publishes when a game heartbeat asks, and none exists) |
| MCP server | `/tmp/ingame-research/probe-mcp.mjs`: spawn `bin/witchcraft-mcp.js --allow-local-writes`, JSON-RPC `initialize`, `tools/list`, `resources/list`, `tools/call wow_get_errors` | server `witchcraft-wow` 0.1.1, protocol 2025-06-18, 15 tools (names in §3), resource `wow://context`, errors call returned in 3 ms with `status:"unavailable", reason:"cache-missing"` |

Not run: anything with the pixel capture, the console mirror, the Electron overlay, a real Claude/Codex session, or the game.

## 6. Windows-only parts and Linux/Proton feasibility

| Part | Windows dependency | Linux/Proton |
|---|---|---|
| Terminals (`src/pty.js`, `screen.js`) | node-pty `useConpty` (ignored off Windows); `taskkill.exe` on dispose (Windows branch only; else `process.kill`); `.exe` resolution only when `win32` | Works natively on Linux [V, §5]. Agents run on the Linux host, which is where omp/claude already live. |
| Ring writer + chunk addons (`ring.js`, `init.js`, `lua.js`) | none; comments mention Windows rename races, retried on `EPERM/EBUSY/EACCES` | Plain files. `addonsDir` only has to be an absolute path ending in `Interface/AddOns` (`config.js`). The Proton prefix is a normal directory on the host (`.../compatdata/<id>/pfx/drive_c/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns`), so no shared Wine prefix is needed. [V for the writer; I for how the game behaves when Proton reads them] |
| Binding carrier (`binding-carrier.js`) | none in the host side; it reads `WTF/Account/**/bindings-cache.wtf` with `fs.watch` + stable double read | Readable from Linux in principle. The background heartbeat that tells the host which slot to write is "Not yet validated in game" (`CHANGELOG.md` Unreleased). The README also says the default carrier needs `/witch bindprobe` each UI session. [U in game] |
| Pixel capture (`capture.js`, `capture-strip.ps1`) | hard-coded `…\WindowsPowerShell\v1.0\powershell.exe` (`capture.js:6`), `user32.dll`, `System.Drawing`, process name `WowB` | Not portable. A Linux version would need its own X11/Wayland/gamescope capture and a foreground-window test, and Proton scaling or HDR could shift pixels. Would be a rewrite, and I would not do it. [I] |
| Console join (`console-mirror.ps1`, `console-list.js`, `current-sessions.js`) | `AttachConsole`, `ReadConsoleOutputW`, `WriteConsoleInputW`, `pwsh` process enumeration | Not portable. Only the "spawn a fresh agent in a PTY" mode works. |
| Electron overlay | none by code, but it is a transparent always-on-top desktop window | Irrelevant to us; layering over a Wine/Gamescope window is not something the repo handles. |
| `.claude/skills/witchcraft-daemon` | PowerShell 7 + `kernel32` `GenerateConsoleCtrlEvent` | Windows only. |
| CI | daemon tests on `windows-latest`, addon luacheck on `ubuntu-latest` (`.github/workflows/ci.yml`) | no Linux daemon CI; nothing claims Linux support |
| MCP server | none | Runs verbatim [V]; but its only data source is the cache the daemon fills from the carriers above |

So: a Linux build of the full product needs the pixel capture replaced (or dropped in favour of the binding/SavedVariables lanes), the console join dropped, and the in-game behaviour of the file carriers proven. The author has not claimed or tested any of that.

## 7. What we would take from witchcraft for our own pipeline

Ordered by value for the owner's goal (edit -> get it into the client -> reload -> read errors/state back -> iterate), cheapest first.

1. **Lua-error capture module for `Forte_Core`.** Port the shape of `Errors.lua`: chained `seterrorhandler`, the three extra events, secret-value guards (`issecretvalue`/`canaccessvalue`), early-in-TOC load, 3-frame stack via the callstack-height trick, dedupe key `kind\0message\0stack[1]`, cap 20, "reloads ago" counter, persisted in our SavedVariables. This turns `/fx log on` (chat-copy) into structured history that survives `/reload`. It needs no pixels and no daemon. It is MIT, small, and we can write our own version in about 150 lines; copy only with the MIT notice if we copy code. Respect our own rule: no `COMBAT_LOG_EVENT_UNFILTERED`, none is used here.
2. **Read errors back from SavedVariables, not from pixels.** Witchcraft parses `WTF/Account/<ACC>/SavedVariables/<Addon>.lua` as literal data only (`outbox.js parseSavedVariables`: luaparse, node/depth/byte budgets, no evaluation). A host-side reader for our `ForteXorcistDB` on Linux gives us "errors since last reload" the moment WoW flushes. For a Python/shell harness: run `luajit` against the file with an empty environment (`setfenv(chunk, {})`), or a small literal parser; do not `dofile` into a global environment. `/reload` (or logout) is the flush trigger. [I: we have not tested flush timing under Proton]
3. **Export/freshness contract.** Copy the idea, not the code: one JSON cache with `schemaVersion`, per-domain `{status, ageSeconds, receivedAt, data}`, a `connection` block, explicit `stale`/`missing`/`unavailable`/`disconnected` states, and tool text telling the model that addon strings are untrusted data. Whatever MCP/skill we end up with (omp's MCP client or hated-wow-mcp) should return age and status with every answer so the agent never treats a stale snapshot as live.
4. **MCP-over-stdio with a pull request file.** The server is a read-only adapter over a cache plus per-domain "want" files (`context-want.js`) that the single daemon folds into the next outbound message. Good pattern for one writer and many readers; it also avoids a network port. We only need it if we build our own daemon.
5. **A host to game command lane that needs no input injection [I, not tested]:** pre-generate N load-on-demand helper addons (`## LoadOnDemand: 1`, `## Dependencies: <our addon>`), have the addon poll `LoadAddOn("FXDev_Chunk_%04d")` and treat `Chunk.lua` (`FXDev_Receive({...})`) as a command. A one-field command such as `{cmd="reload"}` would let the host trigger `ReloadUI()` itself. Because `/reload` flushes SavedVariables, one host-driven reload would also yield the error list from item 2. That closes edit -> deploy (`scripts/deploy.sh`) -> reload -> read errors without a keypress, no pixels and no Windows. Everything in it is Linux-readable files. Open points that decide whether it works: (a) the single-use-slot behaviour under Proton/Forever was never observed by us; (b) whether `ReloadUI()` is allowed from a timer-driven (non-hardware-event) context on Forever, since Witchcraft only calls it from a slash command or a popup accept (`Core.lua:1461, 1624-1627`); (c) a full client restart is needed once after slots are created; (d) policy item 3 about disk polling, so poll slowly (Witchcraft backs off 1 s -> 8 s) and use far fewer than 3000 slots. Keep it out of combat as Witchcraft does (`InCombatLockdown` gate).
6. **Safety habits worth copying:** only load/write files marked as ours (`X-Witchcraft-Chunk: 1` + dependency check in `assertOwnedChunk` before every write; refuse symlinks), scrub generated slots on shutdown, atomic write via temp file + rename, bounded serializers on both sides, versioned protocol with epoch/nonce so stale sessions are rejected.

Things we would not take: the pixel strip and screen capture (Windows-only, plus the pixel-out-of-game pattern is the one a policy reader is most likely to dislike), the console-join feature, the Electron overlay, the cooldown/addon-state carriers (they edit real player settings and are build-pinned), the terminal-in-game UI (we already work from omp on the host), and the bundled Classic guide/loot/passport catalog (not Forever data).

## 8. Licence and compatibility

- `LICENSE`: MIT, "Copyright (c) 2026 Geraldlol". `README.md`: bundled Ace3/CallbackHandler (BSD-style, `Witchcraft/Libs/LICENSE-Ace3.txt`), LibStub (public domain), DejaVu Sans Mono (`Witchcraft/Media/LICENSE-DejaVu.txt`); npm dependencies keep their own licences (not audited by me). [V]
- MIT is GPL-3.0 compatible: we may copy MIT code into a GPL-3.0 project if we keep the MIT copyright and permission notice (for us: an entry in `addon/Forte_Core/ATTRIBUTION.md`, like the CooldownMaster/WeaponSwingTimer entries AGENTS.md already requires). Combined work is distributed under GPL-3.0. [I, not legal advice]
- Interface/engine: addon TOC is `## Interface: 16001`, the same as ours. The author's carrier pins are for client 1.60.1 build 70205; our notes already target 1.60.1. [V]
- Blizzard add-on policy item 1 and 2 (free, visible source): satisfied by an MIT repo.

## 9. Project health (GitHub API, 2026-11-11)

- Created 2026-10-04; last push 2026-11-11T13:07Z; default branch `main`; latest commit on `main` 2026-11-07 (PR #10). ~41 commits total (page count of `commits?per_page=1`), 12.1k lines in `Witchcraft/*.lua` + `src/*.js`.
- 20 stars, 3 forks, 1 open issue (#2, the security hardening thread, open pending the hold-Enter gate and docs), not archived. Contributors: Geraldlol 36 commits, JBurlison 3 (JBurlison's PR #3 was closed and re-done as #4).
- PRs #1, #4-#10 merged between 2026-11-01 and 2026-11-07, so it is moving fast but is one person plus a drive-by contributor. Tags `v0.1.0`, `v0.1.1`, `v0.2.0`; GitHub *Releases* lists only `v0.1.0` (2026-10-04). `CHANGELOG.md` says 0.2.0 is dated 2026-11-06.
- CI: luacheck on Linux, daemon tests on Windows only. "Unreleased" changelog items (background link through the binding carrier, console follow, ring backoff) are marked "Not yet validated in game".
- Maturity caveats: the README states the cooldown/addon-state carriers are pinned to one client build; the author's own docs list native delivery/latency/combat behaviour as still needing in-game acceptance. Last verified product state in the README is Windows 10/11 + Node 24.

## 10. Open questions

1. Does Forever's loader re-read a changed `Chunk.lua` of an already-loaded LoD addon? (Witchcraft's single-use design suggests not; not tested.)
2. Does a host-written `Interface/AddOns/**/Chunk.lua` become visible to a running Proton client immediately (inotify/overlay-fs behaviour under Wine on Bazzite's drive layout)? Not tested.
3. Is `ReloadUI()` callable from a `C_Timer` callback (non-hardware-event) in Forever 1.60.1? Not tested.
4. How soon after `/reload` is `SavedVariables/<Addon>.lua` fully written when the client is under Proton? Not tested.
5. Does the binding carrier's background heartbeat work with the client in the background? The author says "not yet validated".
6. Blizzard's stance on a screen-pixel data channel on Forever: no statement found.

## Sources

- Repo files read at `6b41409`: `README.md`, `docs/MCP.md`, `tools/witchcraft-daemon/README.md`, `CHANGELOG.md`, `LICENSE`, `Witchcraft/{Witchcraft.toc,Ring.lua,Pixel.lua,Binding.lua,Errors.lua,Evidence.lua,Core.lua (1149-1333, 1439-1473, plus grep hits at 1460-1461, 1623-1653),Context.lua (grep),CooldownCarrier.lua,AddonsState.lua,View.lua (grep)}`, `tools/witchcraft-daemon/{package.json,src/{ring,lua,outbox,pty,binding-carrier,mcp-server,context-want,init,config,capture,overlay-electron-main}.js,capture/capture-strip.ps1,console/console-mirror.ps1}`, `.claude/skills/witchcraft-daemon/{SKILL.md,witchcraft-daemon.ps1}`, `.github/workflows/ci.yml`.
- GitHub API for the repo, tags, releases, commits, PRs, contributors, issue #2: https://github.com/Geraldlol/witchcraft/issues/2 (2026-11-04 and later reply).
- Blizzard UI Add-On Development Policy: https://us.forums.blizzard.com/en/wow/t/ui-add-on-development-policy/24534 (2009 text, fetched 2026-11-11).
- Blizzard "Prohibitions on Third-party Software" first post, 2025-08-05: https://us.forums.blizzard.com/en/wow/t/prohibitions-on-third-party-software/2142972

## Implications for our setup

1. Do not adopt witchcraft as a tool: it is Windows-only where it matters (pixel capture, console mirror), unproven under Proton, and we do not need its terminal-in-game UI.
2. Do add structured Lua-error capture to `Forte_Core` (item 1) and a host-side SavedVariables reader (item 2). That alone gives the agent "errors since the last reload" with no pixels, using `/reload` as the flush.
3. If the owner wants a hands-off loop, prototype the file-based host to game command lane (item 5) with 2-3 slots first and answer open questions 1-4 in a throwaway test before building anything.
4. Whatever MCP we use should copy witchcraft's freshness/status contract (item 3).

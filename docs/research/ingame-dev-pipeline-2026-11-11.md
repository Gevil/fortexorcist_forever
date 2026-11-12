# Developing and testing the addon inside the running Forever client: landscape, channel physics, policy, design

Researcher `RsrchPipeline`, 2026-11-11 (revised after reading `docs/research/ingame-dev-witchcraft-2026-11-11.md`). The Mechanic and hated-wow-mcp sibling reports did not exist when this was written; each tool gets one paragraph here, not a deep dive. Where I cite the witchcraft sibling report I tag it **[W]**.

Evidence tags: **[V]** verified in code or on a page I read (file:line or URL, read 2026-11-11); **[I]** inference; **[U]** unverified or untested. Nothing here was run against the game: no input sent, no window touched, nothing installed outside `/tmp/ingame-research/`. Clones I read there: `mechanic`, `hated-wow-mcp`.

Facts about this PC come from the manager (message of 2026-11-11 21:14, read-only checks) and are tagged **[M]**:
- KDE Plasma on **Wayland**; the game runs through Steam Linux Runtime 4 (pressure-vessel/bwrap) with Proton-GE Latest, and is running now.
- Installed on the host: xdotool, ydotool, protontricks, protontricks-launch, node, npx, python3, gamescope, spectacle. Not installed: wtype, dotool, kdotool, wine, grim.
- The agent's desktop-control tool reports backend wayland, `capture=false`, `backgroundWindowInput=false`, and lists only an `xwaylandvideobridge` window. It cannot screenshot or target the game.
- `Logs/WoWChatLog.txt` does not exist yet; no `Screenshots/` folder exists.
- `WTF/Account/<ACCOUNT>/SavedVariables/Forte_Core.lua` exists (written 2026-11-10 19:52, 4.9 KB, with a `.bak` twin). It already holds `diag.casts`/`diag.timerCasts` (66 own casts, all plain ids, 36 in combat, 0 secret), `probesEvents.casts`, `probesEvents.restricts`, `probesEvents.swings`, `cooldownLearned` and the timer position.

---

## 0. Answer first

**Can we run a develop-and-test loop against the real client from Linux/Proton? Partly yes, with a human on the keyboard. A fully automatic loop is not possible: the reload that makes new code run, and that flushes SavedVariables, needs a hardware keypress. Only synthetic input could replace the keypress, and that is a policy question for the owner.**

| Loop leg | Possible without input injection? | How |
|---|---|---|
| Edit code and get it into the game folder | Yes | `scripts/deploy.sh --copy`. |
| Make the client run the new code | **No, needs a human keypress** | `/reload` needs a hardware event [V]. A *new* file or a TOC change needs a **full client restart** [V]. A queued command that calls `ReloadUI()` from a timer is **expected to be blocked** (§2.2). |
| Read results out | Yes, with lag | SavedVariables are written **only at /reload, logout, exit**, so on-disk results are **one reload behind**. Faster lanes: a `Screenshot()` PNG [U on restrictions], the chat log [U on flushing], and the key-binding cache that witchcraft uses (`SaveBindings`, immediate in principle [W, U in game]). |
| Send commands in without a reload | **Possibly, via pre-made load-on-demand "slots"** | Slots can carry *commands and data* (run a selftest, arm a combat suite). They cannot carry *changed code* (needs `/reload`). The file-discovery rules were measured by other projects, not by us, and must be validated first (§5.4). |
| Capture the game window from the host | **No, today** | Wayland and `capture=false` [M]. The game's own `Screenshot()` needs no desktop capture. |

Recommended path:
- **Tier A now.** No policy decision, S–M work.
- **Tier B as a thin CLI first, plus the slot lane (B2) after a throwaway in-game validation.** Both are addon-API-only and inject no input.
- **Tier C (synthetic input) is not recommended.** The reasons are policy ambiguity and a practical focus-steal risk under Wayland (§4.2).

---

## 1. Landscape

Searches run: GitHub and web for "wow mcp", "world of warcraft mcp addon", "wow forever mcp", AlvOps/wow-mcp-forever, forever-addon-kit, BugGrabber/BugSack, DevTool/ViragDevTool, WoWUnit, "addon hot reload", wowlua. Last-activity dates are the GitHub `pushed_at` from `gh api` unless stated.

| Name | What it does | Bridge mechanism | Forever | OS | Licence | Last activity |
|---|---|---|---|---|---|---|
| **Mechanic** (Falkicon) [github](https://github.com/Falkicon/Mechanic) | In-game diagnostics hub plus desktop dashboard/CLI/MCP: 60 commands, offline Lua sandbox tests | CLI writes `MechanicQueue.lua`, listed in `!Mechanic.toc`; the game runs it at `/reload`. Results return through `MechanicDB` SavedVariables (`!Mechanic.lua`); a desktop watcher reads them. | Yes: TOC `120100, 16001` [V `/tmp/ingame-research/mechanic/!Mechanic/!Mechanic.toc`] | Python 3.10+; "Windows has the most complete desktop integration" [V README]; `--auto-reload` key-sender is Windows/macOS only, "Linux does not support it" [V desktop/README.md:120] | GPL-3.0 per README/TOC (GitHub API: NOASSERTION) | 2026-11-01 |
| **witchcraft** (Geraldlol) [github](https://github.com/Geraldlol/witchcraft) | Claude Code/Codex/Copilot terminals inside WoW, plus a 15-tool MCP (12 read-only) | Host to game: daemon rewrites one of 3,000 pre-made `Witchcraft_Chunk_NNNN` LoD addons; the addon pulls the next with `LoadAddOn()` about once a second, no reload. Game to host: a 132×12 px pixel strip (screen capture), data smuggled into a key binding saved with `SaveBindings` to `bindings-cache.wtf`, and an SavedVariables outbox flushed at reload [W, V in code]. | Yes (TOC 16001; some carriers pinned to build 70205) | Windows 10/11: Node 24, PowerShell, Electron; **the sibling ran the ring writer, node-pty and MCP server on Linux, but pixel capture and console mirror are Windows-only** [W] | MIT | 2026-11-11 (main last commit 2026-11-07) |
| **wow-ai** (chelinho139) [github](https://github.com/chelinho139/wow-ai) | Chat with Claude/Codex/Grok/Antigravity/Hermes from inside WoW | Game to host: pixel strip (`capture_x11.py` / `capture.ps1`). Host to game: 200 pre-made `LoadOnDemand` slot addons plus empty-`.wav` flags; fallback keypress-armed `/reload`. | Yes (`_forever_`, TOC 16001) | Windows; Linux/Wine on **X11 only** ("Wayland blocks reading other windows' pixels") [V docs/INSTALL-LINUX.md]; macOS | MIT | 2026-11-04 |
| **wow-forever-codex** (0xInuarashi) [github](https://github.com/0xinuarashi/wow-forever-codex) | Codex chat panel, "no generated keyboard/mouse input" | Pixel strip out; reply bytes encoded as font glyph widths, in via a 65,535-file font bank | Beta build 69913 | Windows (NTFS hard links, tkinter) | none stated | 2026-09-24 |
| **hated-wow-mcp** (RdyGaming) [github](https://github.com/RdyGaming/hated-wow-mcp) | Knowledge MCP: 27 tools (README; PLAN says 20) for the Lua API, Blizzard UI source, CVars, FileDataIDs, lint, TOC/XML validation, scaffolding, model export | **None.** Indexes the installed client's files; never talks to a running game. | Yes (`api-forever.json`, `_forever_` sync) | Node 20+, any OS | MIT | 2026-11-09 |
| **AlvOps/wow-mcp-forever** [raw README](https://raw.githubusercontent.com/AlvOps/wow-mcp-forever/main/README.md) | Wowhead-Forever database MCP (`forever_find/search/lookup/details`) | None (scraper behind AWS WAF via headless Chromium) | Yes (data only) | Node 22, Chromium | MIT | 2026-10-13 |
| **Everloot** MCP (remote) | Forever lore and player-observed drops/quests data | None | Data only | remote | not checked [U] | listing "checked 1 Nov 2026" |
| **wow-dev-mcp** (juemrami), **wow_api_mcp** (Nighthawk42), **wow-api-mcp** (spartanui-wow) | API / global-string / wiki lookup MCPs | None | wow-dev-mcp lists mainline/mists/vanilla; wow_api_mcp lists live/classic/classic_era/classic_anniversary [V search snippets]; neither lists Forever | Node | MIT / MIT / none | 2025-09-04 / 2026-11-11 / 2026-02-06 |
| **Thunderz96/forever-addon-kit** [README](https://github.com/Thunderz96/forever-addon-kit/blob/main/README.md) | Beta findings, API dump, `ForeverBeacon` harvester, Python tools: `sv_bridge.py`/`sv_watch.py`, `read_bugs.py` ("print BugGrabber's errors from disk"), `api_scan.py` | Disk only: reads SavedVariables after `/reload`. No live channel. | Yes, beta-era (1.60.1.69893). Its "SavedVariables are never loaded" row is a beta bug, since fixed (§2.1). | Python; scripts need the WoW path edited (Windows-style) | MIT | 2026-09-25 |
| **nezorflame/wow-forever-addon-kit** | Search listing: "SavedVariables bridge, addon patches, GPU memory sampler (Linux + Windows)", MIT | Disk (SavedVariables) | Beta | Linux+Windows per listing | MIT per listing | **Repo returned HTTP 404 on 2026-11-11 [U]. Do not rely on it.** |
| **ForeverSVFix** (nobewayo) | Workaround for the beta SavedVariables-not-restored bug | Edits `.toc` in place | Beta | any | NOASSERTION | archived, 2026-09-25. Already handled in `deploy.sh`. |
| **!BugGrabber / BugSack** | Capture Lua errors with stack, count, session; BugGrabber keeps them in its own SavedVariables | Disk at reload/logout | BugGrabber v12.1.1 (2026-10-21) and BugSack v12.1.8 have Forever builds [V mmonster.co, CurseForge listing] | in-game | see CurseForge page [U] | Oct 2026 |
| **DevTool** (brittyazel) / ViragDevTool | In-game table inspector | none | Not checked [U] | n/a | MIT | DevTool **archived**, last push 2026-02-09 |
| **WoWUnit** (Jaliborc) [github](https://github.com/Jaliborc/WoWUnit) | In-game unit-test framework, results shown in-game | None; results reach disk only through SavedVariables | A Forever 1.60 listing exists (Interface 12.1, upload 2026-10-06) [V Warperia snippet] | in-game | not reported by API [U] | 2026-09-18 |
| **wow-ui-sim** (Osso) / **uiforever.com** | Headless engine and browser simulator. **Ours already** (`AGENTS.md` Verification). | They *simulate* the client; they are not the client. | Yes | Linux binary; web | GPL-3.0 | wow-ui-sim 2026-11-11 |
| **AutoChatLog** (ReneSarjeant) | Forever addon that enables `/chatlog` on login | Chat log file | Yes | in-game | none stated | 2026-11-01 |

Conclusions from the landscape:
- **Nobody has a hot-reload for Lua in the live client.** The only "hot reload" I found is `scryer`, a *preview* tool, not the real client [V search result, `vertex-wow.github.io/scryer`]. Every real-client loop is `/reload`-bound. [I] from absence in search.
- The live-ish *inbound* channels (witchcraft, wow-ai, wow-forever-codex) all exploit "files that already existed at client launch are read the first time they are used." All three deliberately generate no input.
- The pixel-strip *outbound* channels cannot work on this PC today, because Wayland blocks capture (§4.3). Witchcraft's binding-cache carrier and the SavedVariables outbox are host-readable files and therefore not blocked by Wayland.

### One paragraph per sibling tool
- **Mechanic.** The closest existing fit for tier A/B, and the only candidate whose mechanism matches ours: a generated Lua file loaded at reload, results read from SavedVariables. Limits [V]: it reads two specific SavedVariables files, not arbitrary ones; it needs two addon folders (`!Mechanic`, `Mechanic`); its auto-reload is Windows/macOS only. Its Linux/Proton path discovery is unverified [U]. GPL-3.0, same as our project, so no licence work.
- **witchcraft.** Not usable as a program here (Windows-only capture and console mirror) [W]. It is a rich source of *techniques* we can reuse without its binary: the LoD ring (inbound), the structured Lua-error recorder `Errors.lua` (MIT, ~150 lines of idea), the literal-only SavedVariables parser, the freshness-aware cache contract, and the file-ownership safety habits [W §7]. It also confirms the one-way weaknesses: the author's own open issue #2 is that any other addon can inject into the lane [W].
- **hated-wow-mcp.** A knowledge tool; it does not touch a running game. Its marginal value for us is low because we already vendor the API catalog and lint it in the gate (`scripts/api_lint.py`).

---

## 2. Channel physics

### 2.1 Out of the client (addon to the outside world)

| Channel | What reaches disk, and when | Evidence | Implication |
|---|---|---|---|
| **SavedVariables** | The client writes them "when you log out, disconnect, quit the game, or reload your user interface". `PLAYER_LOGOUT` is "the last event before your saved variables are written". Not written on a crash. | [V warcraft.wiki.gg/wiki/Saving_variables_between_game_sessions]; forevermastery.com/en/guides/install-addons: "If the game crashes, settings changed since your last /reload or logout are not saved." | **One reload behind.** After `/reload` #1 the *new* code runs, but disk still holds the *old* code's data. The new code's data lands at reload #2. This is the central constraint of the design. |
| SavedVariables **on Forever** | Beta bug: "written correctly but not restored". `deploy.sh`'s header says its premise is retired, because SVFix's own README says Blizzard fixed it. | [V `scripts/deploy.sh:5-24`]; [V Thunderz kit README] for the original bug. **[M] our `Forte_Core.lua` was written 2026-11-10 with live data, so the write half works on this install.** | The read-back half is covered by the existing `SV:` probe row (`Probe.lua`, `docs/launch-day.md` F21); not re-proven here [U]. |
| **Key-binding cache** (`SaveBindings` → `WTF/Account/<ACCOUNT>/bindings-cache.wtf`) | Witchcraft binds a never-pressable key (`CTRL-ALT-SHIFT-F9..F12`) to a `CLICK <payload-in-the-name>:LeftButton` and calls `SaveBindings`; its host watches the file with `fs.watch` and a stable double read. Skipped in combat; the addon restores the prior binding after the host acknowledges. | [W §2.3, V in `Binding.lua`/`binding-carrier.js`]. The author lists the *background heartbeat* as "Not yet validated in game" [W §6]. | A write path to disk that does **not** wait for `/reload`, if it works under Proton **[U]**. It edits the player's real key bindings (restored afterwards) and carries only small payloads (payload cap 32 parts). Candidate for a tiny "selftest finished: N/M, stamp S" beacon, not for full results. |
| **Chat log** `Logs/WoWChatLog.txt` | `LoggingChat([newState])` "gets or sets whether logging chat to Logs\WoWChatLog.txt is enabled." The wiki lists the call for Forever 1.60.1. | [V warcraft.wiki.gg/wiki/API:LoggingChat] | See flush below. |
| ...flush behaviour | **Not guaranteed live.** A 2012 thread reports a 2–4 KB output buffer ("can be minutes worth of off-peak chatter"). The reply: *"No. This is intentional, as Blizzard does not want anything close to real-time communication in either direction between WoW and outside applications."* That was a community answer on macOS in 2012, not Blizzard. | [V wowinterface.com/forums/showthread.php?t=43380, posts of 2012-05-01/02]. No Forever/Proton measurement exists. **[U]** | **`Log.lua`'s docstring says "appends every chat line to Logs/WoWChatLog.txt as it happens" and `docs/launch-day.md` calls it "live".** That is unmeasured. The first job of tier A is a 5-minute measurement (§6, step 0). |
| ...does `AddMessage` text reach the file? | `FX.Log` and `[FX-ERR]` print via `DEFAULT_CHAT_FRAME:AddMessage` (`Log.lua`). Whether locally added lines are logged, as opposed to chat events, is **not documented anywhere I found [U]**. | n/a | Same measurement. If AddMessage lines are not logged, `[FX-ERR]` never reaches the file and the "live" story fails. |
| Chat log content risk | It logs the player's whole chat, including whispers and guild chat. | [I] | See the safety rules (§3.4). |
| **Combat log** `Logs/WoWCombatLog.txt` | `LoggingCombat([newState])`, "heavily rate limited ... 5 calls per 10 seconds, shared across all addons". | [V warcraft.wiki.gg/wiki/API:LoggingCombat] | Useless to us: `COMBAT_LOG_EVENT_UNFILTERED` is `HasRestrictions` on Forever, and `AGENTS.md` bans combat-log designs. |
| **Screenshot** | `Screenshot()` saves `WoWScrnShot_MMDDYY_HHMMSS.jpg` in `...\Screenshots`; format via CVar `screenshotFormat` = jpeg (default), png or tga. The wiki shows **no** protected or hwevent flag. | [V warcraft.wiki.gg/wiki/API:Screenshot] | Immediate, in-engine, independent of Wayland. The agent can `read` the PNG. Whether Forever restricts it or rate-limits it is **[U]**; `/run Screenshot()` is the test. |
| **Clipboard** | `CopyToClipboard(text)` exists but is `#protected`. | [V warcraft.wiki.gg/wiki/API:CopyToClipboard] | Only an EditBox plus the user's Ctrl-C works; the Probe copy window already does this (`docs/launch-day.md` step 4). |
| **Pixel "beacon"** | Draw coloured squares, screenshot from outside. wow-ai: 8 colours, 4×4 px cells, about 3.2 KB per frame. witchcraft: a 132×12 px strip. wow-forever-codex: black/white, 64 bytes per frame. | [V their READMEs/docs; W] | Needs host capture of the game window: impossible on this PC today (§4.3). `Screenshot()` is a simpler, in-engine variant. |
| **Optional witchcraft carriers** | Cooldown-viewer layout and addon-enable-state carriers write the player's real settings and are pinned to build 70205. | [W §2.3] | Not worth the risk. |

### 2.2 Into the client (outside world to addon)

An addon has no file, socket or process API and cannot read anything at runtime *except what the client loads for it* [V wow-ai ARCHITECTURE.md "The sandbox"; consistent with the wiki]. What reaches it:

| Channel | Behaviour | Evidence |
|---|---|---|
| **Lua files in the addon folder** | **Re-read on `/reload`**: "Reloading the interface saves the current settings to disk, and updates any addon files previously loaded by the game. In order to load new files (or addons), the game must be restarted." Forever sources say the same: "Edits to `.lua` files need a `/reload`. New files and TOC changes need a full client restart." | [V warcraft.wiki.gg/wiki/API:C_UI.Reload]; [V Tautellini `docs/forever-addon-development.md`, build 70790]; [V forevermastery.com install guide, 2026-11-04] |
| Consequence for us | **Any new `.lua` file or TOC edit costs a full quit-and-relaunch.** A "dev commands" file and a "dev stamp" file must be in the TOC from the first launch; afterwards only their *contents* change. Both `Forte_Core.toc` and `Forte_Core_Camelot.toc` must be edited (`gate.py` enforces byte equality). | [V `scripts/gate.py` `toc_pairs`] |
| **Load-on-demand "slots"** (corrects my earlier "nothing at runtime" wording) | `C_AddOns.LoadAddOn` reads a LoD addon's files **at load time, at runtime, no `/reload`**. Witchcraft's addon does `pcall(LoadAddOn, "Witchcraft_Chunk_%04d")` about once a second, backing off to 8 s when idle; "a generated slot runs synchronously inside LoadAddOn"; each slot is single-use per UI session. wow-ai does the same with 200 slots and reports the rules below. | [W §2.2, V in `Core.lua:1307-1308`, `Ring.lua`]; [V wow-ai ARCHITECTURE.md "Inbound: load-on-demand slots"] |
| ...file-discovery rules | A file that existed at client launch is read fresh the first time it is used; files created after launch are not discovered (so slots must be pre-made, and the client restarted after creating them); an already-loaded file returns cached content for the rest of the process, even across `/reload`, except addon *Lua code*, which is re-read on reload. | **[I]** measured by *other projects* on Forever builds 69913–69977 ([V wow-ai ARCHITECTURE.md] crediting wow-forever-codex). Witchcraft's author calls the carriers "not yet validated in game" [W]. **Not measured by us, not on the current build (70888 per PLAN).** |
| What slots would and would not give us | They can feed **commands and data** without a reload: re-run a suite, arm a combat suite, request a screenshot. They cannot deliver **changed code** (still `/reload`), and they **cannot call `ReloadUI()`** (next row). | [I] |
| **`ReloadUI()` from a queued command or timer** | Expected **blocked**. `C_UI.Reload()` is restricted: "#hwevent - This requires a hardware event i.e. keyboard/mouse input." wow-ai's design notes say `ReloadUI()` "can only be called from a hardware event (a key or click), never from a timer," and its fallback is a frame that reloads on the *player's next keypress*. Thunderz: "ReloadUI() is protected: addon 'Reload UI' buttons are blocked. Type /reload." Witchcraft's open question 3 ("is `ReloadUI()` callable from a `C_Timer` callback in Forever 1.60.1?") is untested [W §10]. | [V warcraft.wiki.gg/wiki/API:C_UI.Reload]; [V wow-ai ARCHITECTURE.md, "Reload fallback"]; [V Thunderz kit README]; [W §10] |
| Consequence | **A slot-delivered command can ask for a reload but cannot perform it.** The correct pattern is: the command sets an on-screen prompt and arms a "next keypress reloads" frame (wow-ai pattern); one human keypress, one action. The test in §5.4 (V4) can confirm whether a timer-driven reload is really blocked on this build; I would not design on the hope that it is not. | [I] |
| **Typing into chat / macros** | `/run`, `/fx ...`, `/reload`: anything the *player* types. | [V wiki "Create a WoW AddOn in 15 Minutes"] |
| **Hardware-event rules on Forever** | `SendChatMessage` with `"EMOTE"` needs a hardware event outside instances, like SAY/YELL. Trial accounts cannot send addon messages. | [V Tautellini doc, "Restrictions added in Forever 1.60.1"] |

### 2.3 What Forever's secret-value rules do to an in-game test harness

Source: [V warcraft.wiki.gg/wiki/Secret_Values]; [V Tautellini doc]; [V `AGENTS.md`, `Probe.lua`, `secrets-unknowns.md`].

- Our harness is **tainted** code. In restricted states (combat, encounters, restricted maps), tainted code gets an **immediate Lua error** for arithmetic, comparison or boolean tests on secrets, `#`, indexing, calling, and using a secret as a table key. It *may* store secrets in variables/tables, pass them to Lua functions and concatenate them.
- Consequences for a test runner:
  1. Every assertion on a live API value must classify first with `issecretvalue`, and sit in its own `pcall`, exactly as `Probe.K` does. `Probe.K` is a ready-made classifier to reuse.
  2. A harness **must never write a raw API value into its result table** (the SavedVariables serializer's behaviour with secrets is untested [U]); write the K-string. `tostring(secret)` returns a secret string ([V Thunderz kit "Secret-value toolbox"]), so even formatting must classify first.
  3. Combat-state assertions cannot be *created* by the harness. It cannot start combat. They need the human to fight a training dummy (the existing `docs/launch-day.md` protocol), so the runner needs a **"combat-armed" mode**: arm, then on `PLAYER_REGEN_DISABLED` plus N s run the group, then store. `Probe` already runs this way ("ooc" vs "combat" by `InCombatLockdown()`). A slot-delivered "arm" command (B2) would let the agent arm it without a reload.
  4. Protected-frame operations fail in combat, so UI creation tests are out-of-combat only. Key-binding carriers pause in combat [W].
  5. Own-cast and tracked state is readable; other units' casts, auras and health are secret ([M]: `probesEvents.casts` shows another unit's nameplate cast spell id as SECRET). A suite's secret-value assertion is "this *is* secret and our code did not raise," which is what a test of `Compat.PlainOrNil` needs.
  6. The client **stops delivering Lua errors after 100 per session** ("Error reporting is now paused") [V Thunderz kit], so an error-flooding test run can hide the real error. The harness needs de-duplication and a per-run cap.
- An error handler that formats the error text can itself raise if the text is a secret. Guard with `issecretvalue` before any string operation. Witchcraft's `Errors.lua` does this with `issecretvalue`/`canaccessvalue` and records `"<unreadable>"` [W §3.1]; `Log.lua`'s wrapper uses `tostring(err)` inside a `pcall`, which is safe but would log a useless value.

---

## 3. Policy and account safety

All quoted pages were read on 2026-11-11.

### 3.1 What Blizzard has actually written

| Source | Date | What it says |
|---|---|---|
| **Blizzard EULA**, §1.C [blizzard.com](https://www.blizzard.com/en-us/legal/fba4d00f-c7e4-4883-b8b9-1b4500a402ea/blizzard-end-user-license-agreement) | Last revised 2024-03-21 | ii: *"bots; i.e. any code and/or software, not expressly authorized by Blizzard, that allows the automated control of a Game, or any other feature of the Platform, e.g. the automated control of a character in a Game"*. iv: *"any code and/or software, not expressly authorized by Blizzard, that can be used in connection with the Platform ... which changes and/or facilitates the gameplay or other functionality"*. vi (Data Mining): *"Use any unauthorized process or software that intercepts, collects, reads, or 'mines' information generated or stored by the Platform; provided, however, that Blizzard may, at its sole and absolute discretion, allow the use of certain third-party user interfaces."* §4 (Consent to Monitor): the Platform *"MAY MONITOR YOUR COMPUTER ... MEMORY FOR UNAUTHORIZED THIRD PARTY PROGRAMS RUNNING EITHER CONCURRENTLY WITH A GAME OR OUT OF PROCESS."* |
| **"Prohibitions on Third-party Software"** (Kaivax, Blizzard) [us.forums.blizzard.com](https://us.forums.blizzard.com/en/wow/t/prohibitions-on-third-party-software/2142972) | 2025-08-05 | Blizzard "regularly implement[s] new and better cheat detection aimed at identifying those who reverse-engineer and bypass our security protocols to modify the game client and/or control the game in ways that are prohibited." Quotes EULA 1.C. Names no tool; does not mention addons, macros or SavedVariables. |
| **"Policy Update for Input Broadcasting Software"** [worldofwarcraft.blizzard.com/en-us/news/23558957](https://worldofwarcraft.blizzard.com/en-us/news/23558957) | 2020-11-03 | Targets "third-party input broadcasting software, which allows a single keystroke or action to be automatically mirrored to multiple game clients"; warnings escalate to suspension/closure. About *multiple clients*; silent on one client. |
| **UI Add-On Development Policy** (reposted by Kaivax) [us.forums.blizzard.com](https://us.forums.blizzard.com/en/wow/t/ui-add-on-development-policy/24534) | text 2009, reposted 2018 | Rule 2: code "must in no way be hidden or obfuscated". **Rule 3**: addons must not negatively impact realms or players, e.g. "excessive use of the chat system, **unnecessary loading from the hard disk**, and slow frame rates". Rule 7: abide by ToU and EULA. Rule 8: Blizzard "reserves the right to disable any add-on functionality". No automation rule. |
| "One action per keypress" (a reply in a player thread) [thread](https://us.forums.blizzard.com/en/wow/t/is-this-a-tou-violation/388812) | 2019-12-14 | In a GSE thread: *"I wouldn't touch anything - ever - that had more functionality than what the in-game systems allow. One action per keypress is the rule, yes."* The poster is labelled **Orlyia**; I could not confirm from the page that this is a Blizzard employee (lazygrip.net calls it a "Customer Support staff member") **[U on authorship]**. |
| 2008 Blizzard forum posts on macro keyboards | 2008 | Second-hand via lazygrip.net (one hardware function equals one action; no auto-spam of rotations). I did not read the primary page **[secondary]**. |
| Community statements | 2012 | Phanx (well-known addon author, not Blizzard): Blizzard "does not want anything close to real-time communication in either direction between WoW and outside applications" **[community opinion]**. |

lazygrip.net's own summary (read 2026-11-11) matches mine: Blizzard "has never ruled" on addon-assisted or sequencing tools by name; the only written principle is *one keypress, one action* with the player doing the pressing; "nothing ... has said it" about safety.

### 3.2 Classification

| Activity | Status | Basis |
|---|---|---|
| Writing and installing addon Lua/TOC into `Interface/AddOns` | **Clearly allowed** | The addon system itself, and the UI policy. |
| An addon writing SavedVariables, a chat log, a screenshot | **Clearly allowed** | Documented API behaviour. |
| A host program reading SavedVariables / `Logs/` / screenshots after the fact | **Tolerated in practice**; the **literal EULA 1.C.vi text is broad** ("reads ... information generated or stored by the Platform") | Mechanic, ForeverBeacon + `fb_extract.py`, forever-addon-kit `read_bugs.py`, TSM/WeakAuras-style companion apps all do it. Blizzard has published no action against it **[I]**. One forum thread in Aug 2025 called the TSM app "a grey area"; Blizzard did not answer. |
| **Host writes Lua into pre-made LoD slot addons; the addon `LoadAddOn()`s them at runtime** (witchcraft, wow-ai pattern) | **Addon-API-only: no input injection, no memory access, no process attach.** No Blizzard statement. Mechanically it is "an addon reads files from its own folder." | Points against: Phanx's 2012 remark (community, not Blizzard) that Blizzard dislikes near-real-time external comms; UI policy rule 3 ("unnecessary loading from the hard disk") for a polling loop and thousands of extra folders; rule 2 (code must be visible: the slot files are plain Lua and must stay that way); EULA 1.C.iv ("facilitates the gameplay") if a command could ever cast, move, target or chat. Points for: public precedent: wow-ai says it has an official CurseForge page [V README]; witchcraft is public MIT. **View: light grey, clearly below input injection. Acceptable for dev only if it is slow, whitelisted and non-gameplay (§3.4 rules 8–10).** |
| **A binding-cache beacon** (`SetBinding`+`SaveBindings` carrying data) | Addon-API-only; but it **edits the player's real key bindings** and uses them as a data carrier; no statement | Witchcraft restores the prior binding after acknowledgement and skips combat [W]. View: grey, a step less clean than slots because it abuses player settings; use only if the chat log and screenshot lanes fail, and only on the throwaway character. |
| A pixel strip read by screen capture | Addon draws pixels; the host reads the screen. No injection. No statement. | Not usable here anyway (§4.3); [W] notes this is the shape "a policy reader is most likely to dislike". |
| **A host program sending a single `/reload` keystroke, or typing a chat command into the game** | **Grey. Not named anywhere I found.** | Literal EULA 1.C.ii: software "that allows the automated control of a Game". The input-broadcasting policy is about multi-client mirroring and does not apply to one client. The *one action per keypress* principle is about gameplay automation where one trigger yields multiple actions; a reload gives no gameplay advantage. Nobody with authority has ruled either way. Counter-evidence: Mechanic *ships* a key-sender (`--auto-reload`, Windows/macOS) in a public project [V README]; but wow-ai, witchcraft and wow-forever-codex all advertise "no generated input", a deliberate avoidance [V READMEs; W §4]. |
| Memory reading, injection, hooking, anti-cheat bypass, bots, automated movement/combat/casting, mirroring input | **Clearly banned** | EULA 1.C.i–1.C.ii, the 2025 post, the 2020 policy. |
| Playing the client under Linux/Proton | **Unsupported, reportedly tolerated** | See Warden below. |

### 3.3 Warden and Linux/Proton

- anti-cheat.org rates WoW/Warden **"Running. Reported to work, but not officially supported ... a ban risk can't be ruled out."** [V anti-cheat.org/game/wow, read 2026-11-11]
- A 2022 EU forum thread says (a poster's recollection) that Customer Support replies stated that playing on Linux alone is not bannable and that early mistaken bans were overturned [V thread content; second-hand, **[I]**]. The same thread notes Wine/Proton is not officially supported.
- Warden checks the **game process's** environment and memory. Writing files into the AddOns folder is what every addon manager does. A pipeline that only edits files and reads `Logs/`/`WTF/` is outside Warden's scope **[I]**.
- EULA §4 says the Platform may monitor "out of process" programs. A **Windows companion running inside the same prefix** (`protontricks-launch`) *is* an out-of-process program in the game's Wine session, so it is more exposed than a Linux-host tool that never enters the prefix **[I]**. See §4.5.
- Do not reason about detectability. A uinput or XTEST key event is indistinguishable from a keyboard to the game; the policy question is intent. Do not design around non-detection.

### 3.4 Recommended safety rules for the pipeline

1. **Tier A and B only until the owner decides otherwise.** The human presses `/reload`; the agent never sends input to the game window.
2. **Develop on a throwaway character on an account the owner accepts risk for.** Never on a main with valuable state; a Hunter alt level 1–10 is enough for the load/error/UI suites.
3. **Never automate combat, movement, casting, targeting, looting or chat.** A test harness may *observe* combat the human creates; it never causes it. The selftest module sends **no chat and no addon messages** (as `TestMode.lua` already promises).
4. **Chat log privacy:** `LoggingChat` writes all chat, including whispers and guild. Turn it on only for dev sessions on the throwaway character, tail only lines starting `[FX`, never commit or share `Logs/`, and `/fx log off` when done.
5. **The agent reads a fixed allow-list of files**, not the whole `WTF/` tree (account names and every other addon's data live there): `SavedVariables/Forte_Core.lua`, `!BugGrabber.lua`, `Forte_Dev.lua`, `Logs/WoWChatLog.txt` (filtered), `Screenshots/*`. It writes only under `Interface/AddOns/Forte_*` and the dev slot folders (through `deploy.sh` and the slot generator).
6. **The dev addon and its slots are not shipped.** The UI policy requires visible code and no hidden functionality; a command-executing dev module in a published addon is the wrong thing to ship. `scripts/release.py` excludes only `tests`/`docs` dirs and `*.otf` (`EXCLUDE_DIR_PARTS`, line 47) **[V line 47; how addon dirs are enumerated is not checked]**.
7. **No companion process inside the Proton prefix.** Keep every tool on the Linux host.
8. **Keep any disk polling slow** (UI policy rule 3): the slot poll should be event-driven or at most every few seconds with backoff when idle (witchcraft backs off 1 s → 8 s [W]); the slot pool small (100 folders, not 3,000); polling only while a dev session is armed.
9. **A slot command language is a whitelist of dev verbs** (`selftest`, `probe`, `screenshot`, `arm-combat`, `status`, `prompt-reload`). No arbitrary `loadstring` from a slot, nothing that casts, targets, moves or sends chat. Free-form Lua stays in the human-reloaded `DevCommands.lua`, where the owner reads it.
10. **Authenticate the lane:** only load files marked as ours (`X-FXDev-Slot: 1` plus a dependency check before every write, refuse symlinks, atomic temp+rename, session nonce/epoch, bounded sizes), and scrub the slots at session end. Witchcraft's open issue #2 is exactly "other addons can inject into the lane" [W §4]; the nonce check and keeping the receiver function in a local, not a global, closes most of it.
11. **Record in the report which client build** each result came from (`GetBuildInfo` is already in Probe output). Forever hotfixes change restrictions weekly.

---

## 4. Linux/Proton practicalities (bazzite)

### 4.1 Where things live, and file-change latency
- Game dir (given context): `/var/home/gevil/.steam/steam/steamapps/compatdata/2691180173/pfx/drive_c/Program Files (x86)/World of Warcraft/_forever_/` with `Interface/AddOns`, `WTF/Account/<ACCOUNT>/SavedVariables/`, `Logs/`, and (not yet present [M]) `Screenshots/`. `scripts/deploy.sh` already defaults to this prefix (`DEFAULT_DEST`).
- The prefix is a normal directory tree on the host, so host-side reads and writes are plain file operations. Witchcraft's writer only needs an absolute `addonsDir` and writes straight into such a path [W §6]. pressure-vessel bind-mounts the prefix into the container; files are the same inodes **[I]**.
- The client writes `SavedVariables/<Addon>.lua` and a `.bak` twin ([M] observed). **Read only after size/mtime settle** and verify it parses, because a read during the write can see a truncated file **[I]**. Parse it as **literal data** (witchcraft parses with `luaparse` and a node/depth/byte budget and executes nothing [W §7]; on this box use `luajit` with an empty environment via `setfenv`, never `dofile` into a global environment).
- Host-side latency is inotify/stat polling (milliseconds). The latency that matters is client-side: SavedVariables at the next reload (§2.1); slot content at the addon's next poll (seconds); whether the running Proton client sees a host-written new file immediately is **[U, V3 in §5.4]** (witchcraft open question 2 [W §10]).
- Editing addon files while the client is running is safe in the sense that nothing re-reads them until `/reload` **[V wiki C_UI.Reload]**. Do not `deploy.sh` *during* a reload; wait for the human to say it finished.

### 4.2 Can the agent deliver synthetic input to the game? (documentation only; not tried)

Facts: Wayland session, game in a pressure-vessel container under Proton-GE [M]. Proton windows are X11 clients on XWayland by default; Proton can opt into a native Wayland driver (`PROTON_ENABLE_WAYLAND`) **[U: not checked on this build]**.

| Tool | Installed [M] | Reaches a Proton game? | Caveats |
|---|---|---|---|
| **xdotool** | yes | **Only XWayland windows** (it speaks the X protocol). "xdotool does not work for any native Wayland applications, but it does work for all applications running via XWayland" **[V github.com/jordansissel/xdotool/issues/346, comment of 2021-08-05]**. | The maintainer says he has not seen it "work correctly on Wayland/XWayland" in all cases and once made it refuse to run there (issues 341/346). Under KWin the target window generally must be focused for XTEST key events; targeting an unfocused window by id is **[U]**. |
| **ydotool** | yes (daemon status unknown) | Yes, compositor-independent: it creates a **uinput virtual keyboard** at kernel level. "`ydotoold` ... requires access to `/dev/uinput`. This usually requires root permissions." [V README] | Events go to **whatever window has focus**; it cannot target the game. If the owner is in a terminal or editor, `ydotool type '/reload'` types into it. A real data-loss and safety risk, not just policy. |
| wtype | **no** | Needs the Wayland virtual-keyboard protocol, which KWin does not implement **[I]** | n/a |
| dotool, kdotool, grim | no | n/a | n/a |
| Portal + libei (KDE RemoteDesktop) | not checked [U] | The sanctioned route; asks the user for consent each session **[I]** | Not evaluated. |
| gamescope | installed, but the session is Plasma and no gamescope wrapper is stated [M] | If the game ran inside gamescope the nested compositor owns input and focus **[I]** | Does not apply today. |

Whether a synthetic key counts as a *hardware event* for `C_UI.Reload` is **[U]**; uinput events look like keyboard events to the kernel and X, so I expect yes, but nobody has documented it and I did not test it.

Bottom line: the only input route that works regardless of window is ydotool, which cannot be aimed. A tool that blindly types a slash command into the foreground window is unsafe even if the policy question is answered favourably.

### 4.3 Screenshots of the game window from the agent's side
- The desktop-control tool reports `capture=false` and no game window [M]. The pixel-beacon tools are X11-only in practice (wow-ai: "Wayland sessions block reading other windows"; a compositor that unredirects the window can return black frames) **[V docs/ARCHITECTURE.md, INSTALL-LINUX.md]**; witchcraft's capture is a PowerShell/GDI helper [W]. Unusable here.
- **In-engine `Screenshot()`** (§2.1) needs no desktop permission. Set `/console screenshotFormat png` once; the agent reads `_forever_/Screenshots/*.png` with its normal file read. The open questions are whether a *timer-driven* addon call is allowed and where the file lands inside the prefix **[U, measure]**.
- Host-side `spectacle` (installed [M]) can take a portal screenshot; whether the agent's shell may call KWin's screenshot interface without a per-call dialog is **[U]**. The desktop tool's `capturePermission` is unavailable [M]; the owner would have to grant it or use another route.

### 4.4 What the agent can already do with no new software
`read` the SavedVariables file (decode with `luajit`, present per AGENTS.md); `read` PNGs; `grep` the chat log; run `scripts/deploy.sh --copy --verify`. The read-back leg of tier A "already works" ([M] item 5): yesterday's `Forte_Core.lua` carries our counters and probe rings.

### 4.5 Running a Windows-only companion inside the prefix
Mechanics: `protontricks-launch --appid 2691180173 <exe>` runs a Windows program in the game's prefix ([V github.com/Matoking/protontricks README]); `$PROTON_VERSION` and `$STEAM_COMPAT_DATA_PATH` select the Proton and prefix; `proton run` with `STEAM_COMPAT_DATA_PATH` is the direct route. A second process in the same prefix attaches to the **same wineserver** as the running game **[I, standard Wine behaviour]**.

Pitfalls (all **[I]/[U]**, none tested):
1. Proton-GE Latest in the container versus the Proton protontricks picks: a mismatched wineserver can kill the running game. Pin `PROTON_VERSION` to the one in use.
2. Electron/node-pty need GPU and ConPTY, fragile under Wine; PowerShell setup scripts and `node.exe` would have to be installed into the prefix.
3. The companion would live in the prefix's filesystem and **see the game process**: the EULA §4 exposure in §3.3.
4. It still could not capture the screen or send input under Wayland.

Conclusion: Windows-only companions are **not needed and not recommended**. The sibling confirmed that the host-side pieces we want (ring writer, PTY, MCP server, literal parser) run natively on Linux [W §5–6].

---

## 5. Design for this project

Existing pieces I read (the design builds on them):
- `Core/Log.lua`: `/fx log on` wraps the error handler to print `[FX-ERR]` to chat, turns on `LoggingChat`, persists `FX.db.logOn`; `FX.Log(tag, ...)` prints `[FX:tag]`. It does not store errors.
- `Core/Probe.lua`: `/fx probe` runs probe groups in `pcall`, classifies every value through `Probe.K`, stores up to 20 runs in `FX.db.probes`, event rings in `FX.db.probesEvents`, an `SV:` stamp round-trip row.
- `Core/TestMode.lua`: `/fx test` fills frames with synthetic rows tagged `_source = "test"`; sends no chat; refuses in combat; scrubs on exit.
- `scripts/deploy.sh`: `--copy` (real dirs, marker file), `--verify` (exits 1 on a real diff), refuses to touch foreign directories, only ever touches `Forte_*`, excludes `tests/`, `docs/`, `*.otf`.
- `scripts/gate.py`: sim tests, load census, TOC pair equality, syntax, generator determinism, api-lint, provenance. Nothing in it runs in the real client.
- `docs/launch-day.md`: a manual real-client protocol; its artefact is the SavedVariables file.

### 5.1 The physical shape of the loop (read this first)

```
agent edits repo -> deploy.sh --copy --verify -> [human: /reload]  (new code runs)
                                                 -> selftest runs at login+N s, prints [FX-ST] lines
   outputs, by arrival:
     immediate   Screenshot() PNG           (agent reads the file)             [U: restrictions]
     immediate?  binding-cache beacon       (tiny "done N/M stamp S" payload)  [U: Proton, optional]
     live?       Logs/WoWChatLog.txt        ([FX-ST] lines)                    [U: buffering]
     next reload SavedVariables files       (Forte_Core.lua, Forte_Dev.lua, !BugGrabber.lua)
   re-runs on already-loaded code (B2): host writes slot -> addon LoadAddOn()s it -> selftest/arm-combat/screenshot
```

Because SavedVariables are one reload behind, a loop that relies only on them needs **two reloads per iteration** (reload 1 loads the new code and runs the tests; reload 2 flushes the results). The chat log, the screenshot and the optional beacon exist to avoid that second reload. A slot command can only *prompt* for the reload (§2.2), never perform it.

The agent can tell which build produced a result because each result carries the **dev stamp** (§5.2 A4). Mechanic's agent rule is the same: "Never treat a file notification or elapsed time as confirmation that the requested reload completed."

### 5.2 Tier A: zero-risk file loop (no input, no new running processes)

**Enables:** edit, deploy, owner reloads, agent reads structured results, errors and probe data, iterates. Real-client assertions the sim cannot make.
**Effort: S–M. Risk: none beyond §3.4. Needs one full client restart, once, for the new TOC entries.**

- **A1. Errors.**
  - *Cheapest:* install **!BugGrabber** (Forever build v12.1.1) and BugSack. BugGrabber stores errors with stack, count and context in `!BugGrabber.lua`; forever-addon-kit's `read_bugs.py` already reads it. The owner must approve a third-party addon.
  - *Own recorder (recommended, S):* a new `Core/Errors.lua` module, installed in `OnEnable` (never a top-level `RegisterEvent`), modelled on witchcraft's `Errors.lua` [W §3.1]: chained `seterrorhandler` that calls the previous handler; `LUA_WARNING`, `ADDON_ACTION_BLOCKED`, `ADDON_ACTION_FORBIDDEN` on a plain frame; stack via `debugstack` with the callstack-height trick, top 3 frames, escapes stripped; every message and stack tested with `issecretvalue`/`canaccessvalue` before any string operation; dedupe key `kind\0message\0stack[1]`; cap 20 entries; per-entry `count`, `first`, `last` and a session number (a "reloads ago" counter); persisted in `FX.db.errors`; a re-record guard so an error while recording cannot loop. Write our own version; if any code is copied, keep the MIT notice and add an entry to `addon/Forte_Core/ATTRIBUTION.md` (MIT is GPL-3.0-compatible [W §8]). Add `inCombat`, build and the dev stamp to each entry. Risk: BugGrabber and our wrapper both call `seterrorhandler`; whether BugGrabber re-asserts its handler is **[U]**; if it does, read BugGrabber's file and skip our ring.
- **A2. `/fx selftest` runner (new, not shipped, M).** A separate addon `Forte_Dev` (new `.toc` pair; **not** `LoadOnDemand`, own `## SavedVariables: ForteDevDB`), so it is outside the release set and independent of the LoD-SavedVariables question in PLAN §11 ("a load-on-demand add-on's SavedVariables arrive with the load ... unproven"). Content: an assertion API (`check(name, fn)`, every body in `pcall`, every live value through `Probe.K`) and real-client suites:
  1. *Load census* — mirrors `gate.py`'s `PROBE` on the live client.
  2. *API presence* — pinned-catalog symbols the addons call (`C_Spell`, `C_UnitAuras`, `C_SwingTimer`, `C_DurationUtil`), complementing the static `api_lint.py`.
  3. *Secret behaviour* — in combat-armed mode, assert `Compat.PlainOrNil` neither raises nor passes a secret through; own-cast ids plain.
  4. *Frames* — expected frames exist, position and scale sane, fonts and textures load (the `.otf` trap), no stale `_source="test"` rows after `/fx test` stops.
  5. *Persistence* — write a nonce; verify it after the next reload (the `SV:` row logic, generalised).
  Results: `ForteDevDB.selftest = { stamp, build, combat, started, finished, tests = {{name,status,detail}...} }`, plus `[FX-ST] <status> <name> <detail>` chat lines, plus an on-screen summary panel and `C_Timer.After(1, Screenshot)` when `screenshot=true`. Risks: new code in the client (excluded from release); the secret-value traps in §2.3.
- **A3. Dev command file (S).** `Forte_Dev/DevCommands.lua`, in the TOC from day one and *overwritten* by the agent before a reload. It returns e.g. `{ "selftest ooc", "probe ooc", "screenshot" }`; `Forte_Dev` runs a whitelist of verbs after `PLAYER_ENTERING_WORLD` plus a delay, never in combat, through the existing `FX.slashSubs`. A free-form verb (`lua = {"return ..."}` through `loadstring` + `pcall`) is acceptable **here only**, because the owner reads the file and reloads by hand (same power as `/run`; Mechanic's `lua.queue` is the existing equivalent). No extra restart is needed after the first install.
- **A4. Deploy stamp and a host-side reader (S).**
  - `deploy.sh --copy` writes a generated `Forte_Dev/DevStamp.lua` (`ForteDevStamp = "<git short sha>+<UTC time>"`); the addon embeds it in every result.
  - `scripts/fxdev.py` (stdlib; shells out to `luajit` with an empty environment to load a SavedVariables file and emit JSON): `status` (disk stamp vs last flushed stamp vs file mtime), `read <file>`, `errors`, `chatlog [--since]`, `shots`, `wait --stamp <s> --timeout n`. It adopts the witchcraft freshness contract [W §7.3]: every answer carries `{status: fresh|stale|missing, ageSeconds, receivedAt}` and says that addon strings are untrusted data. It never writes outside `Interface/AddOns/Forte_*`.

**Tier-A protocol:** (1) agent edits; (2) `deploy.sh --copy --verify`; (3) agent writes `DevCommands.lua`; (4) "reload now"; (5) owner `/reload`; (6) the selftest prints `[FX-ST] done N/M` and a screenshot appears; (7) agent reads the PNG / chat log; (8) owner `/reload` again (or logs out) to flush; (9) `fxdev.py wait --stamp` then `read`.

**First launch only:** because it adds files and TOC lines, the owner quits and relaunches the client once and enables the new addon on the character screen ([M]: `AddOns.txt` did not list Forte on 11-09 yet the addon loads; verify the enable state).

*Existing tools that could supply pieces:* BugGrabber (A1), Mechanic's queue + `MechanicDB` (A3 and part of the result transport), WoWUnit (A2's assertion layer; only a Forever 1.60 listing exists [U], last push 2026-09-18). None supplies the secret-value-aware Forte suites, so A2's content is ours either way.

### 5.3 Tier B: tier A + CLI/MCP + the slot lane

**B1. CLI/MCP tools. Enables** typed tools (`wow_reload_needed`, `wow_get_errors`, `wow_get_probe`, `wow_run_selftest`, `wow_deploy`, `wow_get_screenshot`) and a bounded "wait for results with this stamp" step. **Effort: S for the CLI (A4), M for an MCP server. Risk: low.**
1. **Our own thin MCP over `fxdev.py`** (Python or Node on the host; stdio, no port, as witchcraft's does [W §3]). Each tool is one `fxdev.py` verb; `wow_run_selftest` returns `{status:"awaiting_reload", stamp}` and `wow_wait_results(stamp)` blocks (bounded). *My view:* build the CLI first; add the MCP only if a second harness needs it, since the agent already has `bash`.
2. **Mechanic as the transport.** Install `!Mechanic` + `Mechanic`; register Forte through `MechanicLib`; use `lua.queue`/`lua.results`, `addon.output`, `mech mcp`. It supplies a queue, a watcher, an MCP and a dashboard. Costs: two more addons in the client; target discovery on Linux/Proton paths is **[U]**; "Mechanic does not read arbitrary addon SavedVariables" [V docs/integration/saved-variables.md], so our data must go through its registration API; a reload is still the human's job on Linux. The beta-era `!Mechanic.lua` in the WTF folder shows the owner has had it installed (PLAN §11.10). Licence compatible (GPL-3.0).
3. **hated-wow-mcp** for API/UI-source lookup: orthogonal; optional.
4. **witchcraft's MCP:** not usable on this OS as a product [W]; only its patterns.

**B2. Slot lane (inbound commands without a reload; upgraded from my earlier "skip"). Enables:** re-running a suite, arming the combat suite while the owner is already at the dummy, requesting a screenshot, and *prompting* for a reload, all without `/reload`. **It does not deliver code changes and cannot perform a reload.** **Effort: M. Risk: low–medium (light-grey policy, §3.2; unmeasured file-discovery rules).**

Design (modelled on witchcraft's ring and wow-ai's slots [W §2.2, §7.5; V ARCHITECTURE.md]):
- A generator `scripts/fxdev_slots.py` creates about **100** folders `FXDev_Slot_NNN` (not 3,000) in `Interface/AddOns`, each: `## Interface: 16001`, `## LoadOnDemand: 1`, `## Dependencies: Forte_Dev`, `## X-FXDev-Slot: 1`, one `Slot.lua` with an inert placeholder. They are **outside** `deploy.sh`'s `Forte_*` scope on purpose (the script's safety rule is "only `Forte_*`"), so the generator carries its own marker file and refuses foreign folders. They are not in `gate.py`'s `Forte_*` TOC-pair check. The client must be **restarted once after generating them** (files not present at launch are not discovered).
- `Forte_Dev` arms a poll **only while a dev session is on** (`/fxdev on`): `pcall(C_AddOns.LoadAddOn, nextSlot)` on a `C_Timer` at 2 s, backing off to 10 s while idle; each slot is single-use per UI session; reload frees them all.
- The slot file calls a **local** receiver (not a global; this closes the "other addons can inject" hole, [W §4]) with a table `{epoch, nonce, seq, verb, args}`; the receiver checks the session nonce, `seq` monotonicity, size caps, refuses in combat, and runs a **whitelist** (§3.4 rule 9). The host rewrites only the slot the game will load next, atomically, and scrubs them at session end.

**What must be validated in the game before building B2** (throwaway test with 3 slots and a 20-line addon; this is the sibling's open questions 1–4 plus ours):
- **V1.** Slots created before launch are discovered; a slot **rewritten after launch but before its first load** returns the *new* content on the current build (the central assumption; both other projects measured it on older builds).
- **V2.** A slot that has been loaded once is not re-read (cached) until `/reload`: confirms single-use accounting.
- **V3.** A file the **host** writes through the Proton prefix is visible to the running client immediately (no overlay/cache lag; witchcraft open question 2).
- **V4.** `ReloadUI()` / `C_UI.Reload()` called from the slot-run code and from a `C_Timer` callback **is blocked** (witchcraft open question 3). If it is *not* blocked on this build, the tier-B loop becomes keypress-free, but I would **not** build on that: Blizzard's docs say hwevent and any hotfix can close it.
- **V5.** `LoadAddOn` from a timer is accepted outside combat and cheap (per-load cost; policy rule 3).
- **V6.** Optional: the `SaveBindings` beacon writes `bindings-cache.wtf` within about a second and the host sees it under Proton (witchcraft "not yet validated in game").
If V1 or V3 fails, drop B2; tiers A and B1 still stand.

**Combined tier-B loop:** edit → deploy → owner reload (reload 1: new code runs, selftest auto-runs) → agent reads screenshot/chat → agent re-runs suites with slot commands as often as it likes → at the end a slot command prompts "press F5" (bound to a `/reload` macro, or the keypress-armed frame) → one flush reload → `fxdev.py wait` + `read`.

### 5.4 Tier C: assisted input (policy decision required)

**What it would enable:** the agent triggers `/reload` or a chat command itself, making the loop fully automatic. **Effort: M. Risk: high (policy grey area, §3.2; focus-steal and wrong-window input, §4.2).**
- **C0 (no new input): keypress-armed reload frame** in `Forte_Dev` (the wow-ai pattern): when a pending flag is set (by a slot command or the owner), the owner's *next* keypress triggers the reload through `SetPropagateKeyboardInput(true)`; or the owner binds a key to a `/reload` macro (Mechanic's "Reload UI (Dev)" binding is the same). One human keypress, one action. **Recommended if wanted; it is tier A/B, not C.**
- **C2 (synthetic `/reload` key via ydotool/xdotool):** only with the owner's explicit, recorded decision. If ever done: **a single key**, an F-key bound to a `/reload` macro (never type text); sent only on the owner's explicit command; only out of combat; only when the game window has focus (verifiable today only by a window list that shows `xwaylandvideobridge` [M]); throwaway character; no loops, no retries, no scheduling.
- **C3 (typing chat commands):** not recommended.
- *Existing tools:* none on Linux. Mechanic's `--auto-reload` is Windows/macOS only [V README]; wow-ai/witchcraft/wow-forever-codex avoid input by design.

### 5.5 Tier summary

| Tier | Enables | Effort | Risk | Supplied by an existing tool? |
|---|---|---|---|---|
| **A** file loop | Deploy, human reload, structured results, errors, screenshot, chat lines | S–M | None beyond §3.4 | BugGrabber (errors); witchcraft `Errors.lua` (pattern); Mechanic *optionally*; suites are ours |
| **B1** CLI/MCP | Typed tools, wait-for-results | S (CLI), M (MCP) | Low | Mechanic's `mech mcp`; hated-wow-mcp (API lookup only) |
| **B2** slot lane | Commands/data into a running client without reload; prompts a reload | M | Low–medium; needs V1–V6 first | witchcraft ring and wow-ai slots (patterns; not runnable here) |
| **C0** keypress-armed reload | Fewer manual steps | S | Low | wow-ai's fallback |
| **C2** synthetic key | Automatic reload | M | **High / owner decision** | Mechanic `--auto-reload` (Win/macOS only) |

---

## 6. Recommended first step

**Step 0, a 15-minute owner session (no code).** It settles the physics facts that decide the design:
1. `/fx log on`, then `/fx log test`, `/run print("probe-line")`, `/fx probe`. From a host shell watch whether `Logs/WoWChatLog.txt` appears and **grows while the game keeps running** (compare `stat` size/mtime over ~60 s), and whether the `[FX-ERR]`/`[FX:...]`/`print` lines are in it. Settles §2.1 chat-log flush and AddMessage logging.
2. `/console screenshotFormat png`, then `/run Screenshot()` and `/run C_Timer.After(2, Screenshot)`. Check `Screenshots/` appears and where it lands. Settles §2.1 and §4.3.
3. `/reload`; confirm the mtime of `SavedVariables/Forte_Core.lua` changes only at the reload.
4. `/run C_Timer.After(1, ReloadUI)` out of combat. Expect an "action blocked"/no reload: that is the V4 answer, cheap to get now and it decides whether B2 can ever be keypress-free. (Only the owner types it.)
Then `/fx log off`.

**Step 1 (S):** `scripts/fxdev.py` reader (`status`, `read`, `errors`, `chatlog`) and the dev stamp in `deploy.sh`; useful immediately against the existing 2026-11-10 SavedVariables file.
**Step 2 (M):** `Forte_Dev` with the assertion API, load-census and persistence suites, `DevCommands.lua`, and the screenshot/chat/SavedVariables result channels; add the own error recorder (A1). Add the TOC entries in the same change that needs the one full restart, and **generate the 3 test slots in that same restart** so V1–V3 can be run immediately.
**Step 3 (S):** run V1–V6. If V1 and V3 pass, build B2 with a 100-slot pool; otherwise stay on A + B1.
**Step 4 (S):** combat-armed suite using the training-dummy protocol from `docs/launch-day.md` (re-armed by slot command if B2 exists).
Do not start tier C.

The manager should verify (read-only) before step 2: the measurements in step 0 (owner session), `scripts/release.py`'s addon enumeration (so `Forte_Dev` and `FXDev_Slot_*` are excluded), and that `Forte_Core_Camelot.toc` stays byte-identical to `Forte_Core.toc` after edits (`gate.py`).

## 7. Questions only the owner can answer

1. **Tier C.** Is any synthetic input to the game window acceptable on this account, ever? If yes: throwaway account/character only, a single `/reload` key only? (My recommendation: no; C0 instead.)
2. **Slot lane (B2).** Is a runtime file-polling channel (addon API only, no input) acceptable in a dev build, knowing there is no Blizzard statement either way and the UI policy's disk-loading rule? OK to restart the client once to create about 100 slot folders?
3. **Dev character.** A throwaway Hunter alt (recommended) or the main? Combat suites need a training dummy.
4. **Third-party addons.** May I install **!BugGrabber** + BugSack (and later Mechanic) into `_forever_/Interface/AddOns`? The deploy script refuses to touch foreign folders, so this is a manual copy by the owner.
5. **Reload cadence.** Will the owner accept "reload, wait for the `[FX-ST]` line, reload again" and bind a key to a `/reload` macro (or accept the keypress-armed frame)?
6. **Chat logging.** OK to run `/fx log on` during dev sessions knowing it logs all chat (whispers included), readable by the agent through a `[FX` filter?
7. **Screenshots.** Is `Screenshot()` into the prefix enough, or should the agent get desktop capture (`capturePermission` unavailable now) or `spectacle` access?
8. **Release hygiene.** Confirm `Forte_Dev` and the slot folders must never ship in the release zip or on CurseForge (my recommendation), so `release.py` gets an exclusion.
9. **Proton details.** Stock Steam entry, or `PROTON_ENABLE_WAYLAND` / gamescope? Only matters if tier C is on the table.

## 8. Open items I could not verify
- Whether `WoWChatLog.txt` flushes live under Proton, and whether `AddMessage` text is logged (decides the "live `[FX-ERR]`" claim in `Log.lua` and `docs/launch-day.md`).
- Whether Forever restricts `Screenshot()` (hardware event, rate limit) and where the file lands.
- Whether `ReloadUI()` is blocked from a timer on this build (V4); documentation says hwevent.
- Whether a synthetic key counts as a hardware event for `/reload`.
- Whether the launch-time-file-discovery and single-use rules from wow-ai/wow-forever-codex/witchcraft hold on the current build and under Proton (V1–V3); whether the binding-cache beacon works in the background (V6).
- Mechanic's behaviour on this Linux/Proton layout.
- Licence/Forever status of BugGrabber (licence), DevTool (Forever), WoWUnit (licence, Forever listing) were taken from listings.
- `nezorflame/wow-forever-addon-kit` (HTTP 404).

## 9. Sources
- Repo (read): `AGENTS.md`, `PLAN.md` §11.10 (as returned by search), `scripts/deploy.sh`, `scripts/gate.py`, `scripts/release.py` (exclusion lines), `addon/Forte_Core/Core/Log.lua`, `Probe.lua`, `TestMode.lua`, `addon/Forte_Core/Forte_Core.toc`, `docs/launch-day.md`.
- Sibling report: `docs/research/ingame-dev-witchcraft-2026-11-11.md` (RsrchWitchcraft; read at witchcraft `6b41409`).
- Clones: `/tmp/ingame-research/mechanic` (README, `!Mechanic.toc`, `docs/integration/*`, `desktop/README.md`), `/tmp/ingame-research/hated-wow-mcp` (README).
- Warcraft Wiki: [API:LoggingChat](https://warcraft.wiki.gg/wiki/API:LoggingChat), [API:LoggingCombat](https://warcraft.wiki.gg/wiki/API:LoggingCombat), [API:Screenshot](https://warcraft.wiki.gg/wiki/API:Screenshot), [API:C_UI.Reload](https://warcraft.wiki.gg/wiki/API:C_UI.Reload), [API:CopyToClipboard](https://warcraft.wiki.gg/wiki/API:CopyToClipboard), [Saving variables between game sessions](https://warcraft.wiki.gg/wiki/Saving_variables_between_game_sessions), [Secret Values](https://warcraft.wiki.gg/wiki/Secret_Values), [Create a WoW AddOn in 15 Minutes](https://warcraft.wiki.gg/wiki/Create_a_WoW_AddOn_in_15_Minutes).
- Forever dev docs: [Tautellini/forever-addon-development.md](https://github.com/Tautellini/TautelliniAddons/blob/main/docs/forever-addon-development.md) (build 70790, 2026-11-04); [forevermastery.com install guide](https://forevermastery.com/en/guides/install-addons) (2026-11-04); [Thunderz96/forever-addon-kit README](https://github.com/Thunderz96/forever-addon-kit/blob/main/README.md) (2026-09-24).
- Bridges: [wow-ai README/ARCHITECTURE/INSTALL-LINUX](https://github.com/chelinho139/wow-ai); [wow-forever-codex README](https://github.com/0xinuarashi/wow-forever-codex); [witchcraft README](https://github.com/Geraldlol/witchcraft); [wow-mcp-forever README](https://raw.githubusercontent.com/AlvOps/wow-mcp-forever/main/README.md); [wow-dev-mcp](https://github.com/juemrami/wow-dev-mcp).
- Policy: [Blizzard EULA](https://www.blizzard.com/en-us/legal/fba4d00f-c7e4-4883-b8b9-1b4500a402ea/blizzard-end-user-license-agreement); [Prohibitions on Third-party Software, 2025-08-05](https://us.forums.blizzard.com/en/wow/t/prohibitions-on-third-party-software/2142972); [Input Broadcasting policy, 2020-11-03](https://worldofwarcraft.blizzard.com/en-us/news/23558957); [UI Add-On Development Policy](https://us.forums.blizzard.com/en/wow/t/ui-add-on-development-policy/24534); [Is this a TOU Violation?, 2019-12-14](https://us.forums.blizzard.com/en/wow/t/is-this-a-tou-violation/388812); [lazygrip.net compilation, checked 2026-11-09](https://lazygrip.net/guide/blizzard-and-addons); [WoWInterface chat-log thread, 2012](https://wowinterface.com/forums/showthread.php?t=43380).
- Linux: [anti-cheat.org WoW](https://www.anti-cheat.org/game/wow); [Blizzard EU thread: Steam Deck ban risk, 2022](https://eu.forums.blizzard.com/en/wow/t/steam-deck-is-there-a-risk-of-a-ban/417962); [ydotool README](https://raw.githubusercontent.com/ReimuNotMoe/ydotool/master/README.md); [xdotool issue 346](https://github.com/jordansissel/xdotool/issues/346); [protontricks README](https://raw.githubusercontent.com/Matoking/protontricks/master/README.md).
- Repo metadata: `gh api repos/<owner>/<repo>` `pushed_at`/licence, 2026-11-11.

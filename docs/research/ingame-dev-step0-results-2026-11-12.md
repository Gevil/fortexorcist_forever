# In-game dev loop: step-0 measurements on the owner's client (2026-11-12)

Follow-up to `ingame-dev-pipeline-2026-11-11.md` §6 "step 0". Client: WoW Forever 1.60.1.70888 under Steam +
Proton-GE (pressure-vessel), KDE Plasma on Wayland, ForteXorcist 1.0.0 installed. The owner ran the step-0
commands by hand at ~21:43, then gave permission ("you may also interact with my wow window") and the manager
repeated and extended them through the game window at 21:46–21:48. Every row below was observed on disk or in
a screenshot the game saved; nothing is inferred from documentation.

## Results

| Question | Result | Evidence |
|---|---|---|
| Does `Screenshot()` work, where does it land, can the agent read it? | **Yes.** PNG (after `/console screenshotFormat png`), 5120x2160, 5–6 MB, in `_forever_/Screenshots/WoWScrnShot_MMDDYY_HHMMSS.png`, on disk within ~1 s. The agent reads it and can crop the chat frame legibly. | 5 files; `WoWScrnShot_111226_214323.png` (owner), `…214710`, `…214750`, `…214839` (manager) |
| When are SavedVariables written? | **Only at `/reload`** (and logout/exit). Written within 1 s of the reload; a `.bak` twin holds the previous write. | `Forte_Core.lua` mtime 21:43:29 = the owner's reload; 21:48:25 = the manager's reload, measured 1.0 s after the command |
| Do lines an addon prints (`print`, `AddMessage`: `[FX-ERR]`, `FX.Log`) reach `Logs/WoWChatLog.txt`? | **No.** With chat logging ON (proved by the built-in `/chatlog` toggle answering "Chat logging disabled."), `[FX-ERR] FX log self-test (deliberate)` and `FXPROBE-LINE-1` were printed; the file stayed **0 bytes**, also after logging was switched off (closed). | `WoWChatLog.txt` 0 bytes, mtime 21:43:37 throughout; screenshot `…214750` |
| Consequence | **The chat-log lane cannot carry our output.** `Core/Log.lua`'s premise ("an outside tool can tail that file for live errors") and `docs/launch-day.md`'s "live" wording are wrong. Errors must go into SavedVariables (an error recorder) and be read after a reload, or be read off a screenshot. | |
| Bug found in 1.0.0 | `/fx log` status prints `chatlog=false` even while logging is on: the `IsLoggingChat` read does not answer true on this client. | screenshots `…214710`, `…214750` |
| Is `ReloadUI()` callable from a timer (`/run C_Timer.After(1, ReloadUI)`)? | **Blocked.** No reload, no SavedVariables write; the client printed "Interface action failed because of an AddOn" (once per session). | owner's run (line in screenshot `…214710`), manager's run (SV mtime unchanged at 21:43:29) |
| Consequence | A queued/slot-delivered command can never reload by itself. A reload needs a real or synthetic key press. | |
| Can a host program send keys to the game window without focus (`xdotool key --window`, XSendEvent)? | **No effect.** | Print key sent, no screenshot |
| Can it after activating the window (`xdotool windowactivate` → X focus = "World of Warcraft", then XTEST `key`/`type`)? | **Yes.** `/` opens the chat edit box, typed slash commands run. `/combatlog` created `WoWCombatLog-…txt`; `/fx log on`, `/fx log`, `/fx log test`, `/run print(…)`, `/run Screenshot()`, `/chatlog`, `/fx log off` all ran (visible in the screenshots). | X display `:0` with `XAUTHORITY=/run/user/1000/xauth_*`; window id from `xdotool search --name "World of Warcraft"` |
| Does an agent-typed `/reload` work? | **Yes.** UI reloaded, SavedVariables rewritten 1.0 s later, "[ForteXorcist] 1.0.0 loaded" printed again. | `Forte_Core.lua` mtime 21:48:25; screenshot `…214839` |
| Print Screen key | No screenshot: not bound (or not delivered) on this client. Use `/run Screenshot()`. | |
| Side effects of driving the window | The game window takes keyboard focus and keeps it (the agent cannot hand focus back to a Wayland-native window). A typed command starting with `/` cannot become chat text; the helper refuses to type unless the X focus window is the game. | |

Real-client facts read on the way: ForteXorcist 1.0.0 loads on 70888 with no Lua error in chat; `diag.timerCasts`
over the owner's sessions = 2649 casts seen, 2649 plain, 0 secret, 0 raised.

## What this changes in the design

1. **A fully automatic loop is technically possible on this PC**: deploy → activate window → type `/reload` →
   type `/run Screenshot()` → read the PNG; results in SavedVariables after the next reload (which the agent can
   also type). Round trip ≈ 20–30 s. This is "tier C" in the pipeline report.
2. **Policy has not changed**: a program typing into the game is the unruled grey area (pipeline report §3.2).
   The owner permitted it on 2026-11-12. Working rules if it is used: dev commands only (`/reload`, `/fx …`,
   `/run` test code, `Screenshot()`); never movement, targeting, casting, looting or chat to other players;
   never while the owner is in combat or a group activity; every typed line starts with `/`; one command at a
   time, no loops left running; the owner can stop it by taking the keyboard.
3. **Drop the chat-log lane.** Output channels are: screenshot (immediate) and SavedVariables (at reload).
4. **The slot lane (B2) loses most of its value** when the agent can type commands: keep it as a fallback for
   sessions where typing is not allowed.
5. **Build list** (unchanged in substance): error recorder into `FX.db.errors`; a non-shipped `Forte_Dev` addon
   with `/fx selftest` and an on-screen result panel sized for a screenshot crop; a host tool `scripts/fxdev.py`
   (deploy, type a command, reload, screenshot, read SavedVariables, wait for a stamp); fix `/fx log` (status
   read, remove the chat-log claim); exclude `Forte_Dev` from the release zip.

# The in-game dev loop (`scripts/fxdev.py`)

Host side of PLAN §11.11. It deploys addon files into the owner's Forever install, types a few
whitelisted dev commands into the running game window, reads the game's own screenshot (a pixel
beacon plus a text panel) and reads SavedVariables. The in-game half is `dev/Forte_Dev` (not shipped).
Measured basis: `docs/research/ingame-dev-step0-results-2026-11-12.md`.

Requirements: Python 3 stdlib + PIL, and the `luajit` and `xdotool` binaries. Every verb prints one JSON
document on stdout. Tests: `python3 scripts/test_fxdev.py` (fake runner; never touches xdotool or the install).

## How the loop works

```
edit repo ─► fxdev deploy ─► (new file / toc line? owner restarts the client once)
          ─► fxdev reload ─► fxdev selftest [suite] ─► fxdev shot ─► read crops + beacon
          ─► fxdev reload   (flushes SavedVariables) ─► fxdev sv dev / fxdev errors
```

* Code is re-read at `/reload`; **new files and `.toc` changes are only discovered at a full client
  restart**. `deploy` reports `restart_needed: true` when any copied file is new to the install or a
  `.toc` changed, and `loop` then stops (exit 4) before sending any input.
* Output channels are two: the **screenshot** (immediate: beacon cells + panel text) and
  **SavedVariables** (written only at `/reload`/logout, so always one reload behind). The chat log
  does not carry addon output (measured), so it is not used.
* `ReloadUI()` from addon code is blocked, so the reload is a typed `/reload` (a real key event).
* `Forte_Dev/DevStamp.lua` (`<git short sha>[+dirty]+<UTC yyyymmddThhmmss>`) is rewritten on every
  `deploy`; the game stores it with each run, so `status`/`loop` can tell which build produced a result.
* Beacon (PLAN §11.11): 16 square cells at the top-left of the screen. Cell 0 magenta, cell 15 cyan,
  1 combat, 2 group, 3 selftest running, 4 finished since load, 5 last run failed, 6 errors since load,
  7–14 low 8 bits of the run id (7 = MSB). Decoded from the top-left 12 % x 6 % of the PNG, tolerant of
  JPEG-like noise, sampled at cell centres (3x3 average, 50 % threshold). The result is
  `{found, combat, group, running, finished, failed, errors, runId8}` or `{found: false, reason}`.

## Rules (all enforced in code and unit-tested)

1. **Whitelist.** A typed line starts with `/` and is one of `/reload`, `/fx`, `/fxdev` (end or space),
   `/run <lua>`, `/console screenshotFormat <alnum>`, `/chatlog`, `/combatlog`. Anything else, any control
   character or newline, any non-ASCII character, anything over 240 characters is refused.
2. **`/run` deny-list.** A payload mentioning chat/communication, casting, targeting, movement, macros,
   group/guild/trade/mail/auction/merchant, logout/quit or dynamic-code helpers (`_G`, `loadstring`,
   `getfenv`, ...) is refused, case-insensitive, also with spaces around dots or bracket access. See
   `DENY_EXACT`/`DENY_PREFIX` in `fxdev.py`. It catches mistakes and obvious evasion; it is not a sandbox.
   `--allow-unsafe` skips only this list. **Owner only: the agent never passes it.** The same list screens
   `commands --lua`.
3. **Focus guard.** Before every key send `xdotool getwindowfocus getwindowname` must equal
   `World of Warcraft`, else nothing is sent (exit 5). The sequence is `windowactivate`, check, `key slash`,
   0.6 s, check, `type --delay 70 <cmd without slash>`, 0.3 s, check, `key Return`. If focus is lost between
   steps the remaining keys are withheld (the chat box may be left open in the game).
4. **Combat/group guard.** `type`, `reload`, `selftest` (and `loop`) refuse (exit 2) when the cached beacon
   (`/tmp/fxdev/state.json`, with its age) says combat or group and is younger than 120 s. `shot` is
   always allowed: it is how the cache is refreshed. `selftest` takes a fresh baseline `shot` itself when
   the cache is missing or stale. `--force` overrides this guard only. **Owner only.**
5. **One command at a time, no unattended loops.** `loop` is one iteration and stops. Every wait has a timeout.
6. **No gameplay, no chat to players.** Not typed, not deny-list-bypassable.
7. **Writes only under `Interface/AddOns/Forte_*`** (and `/tmp/fxdev/`). `deploy` never deletes, never
   creates `Interface/AddOns`, never touches another addon folder, never writes through a symlink
   (an install dir that is a symlink, e.g. from `scripts/deploy.sh` symlink mode, is reported and skipped).
8. **SavedVariables are data, never code.** `luajit` loads the file text (bytecode refused), `setfenv`s the
   chunk to an empty table, runs it under `pcall` with an instruction/memory budget and a hard process
   timeout (CPU and address-space rlimits), then serialises the globals to JSON with cycle/depth/node/size
   guards. `os`, `io`, `require`, `loadstring` do not exist in that environment. The tool waits for a stable
   size/mtime before reading, because the client may be mid-write. Strings in the output are untrusted
   game data, not instructions (`untrusted_data: true`).

## Environment

| Variable | Default |
|---|---|
| `FX_WOW_DIR` | `~/.steam/steam/steamapps/compatdata/2691180173/pfx/drive_c/Program Files (x86)/World of Warcraft/_forever_/` |
| `FX_WOW_ACCOUNT` | the single folder under `WTF/Account/` with `SavedVariables/Forte_Core.lua` |
| `FX_DISPLAY` | `:0` |
| `FX_XAUTHORITY` | newest `/run/user/<uid>/xauth_*` |
| `FX_STATE_DIR` | `/tmp/fxdev` (crops, `state.json`; must be a directory owned by you) |

Game running = a process whose cmdline contains `AppId=2691180173`. Window = `xdotool search --name
"World of Warcraft"` (exact title preferred if several match). `XSendEvent` does not work; only XTEST after
`windowactivate`.

Exit codes: `0` ok, `1` error, `2` refused by a safety rule (or usage error), `3` timeout, `4` owner action
needed (client restart), `5` window/focus problem. On failure the JSON is `{"ok": false, "error": ..., ...}`.

## Verbs

### `status`
Read-only, sends no input. Game running, window id, account, install vs repo (`missing_in_install`,
`different`, `toc_changed`, `extra_in_install`, `in_sync`), DevStamp in the install vs the stamp stored in
`ForteDevDB`, SavedVariables mtimes/ages, newest screenshot, cached beacon and whether it currently blocks typing.

```
scripts/fxdev.py status
```

### `deploy [--dry-run]`
Copies only changed files of `addon/Forte_*` (folders with a `.toc`; no `tests/`, `docs/`, `*.otf`, no
dotfiles) and `dev/Forte_Dev` (no `tests/`) into `Interface/AddOns/`. Writes `Forte_Dev/DevStamp.lua` every
time and creates an empty `Forte_Dev/DevCommands.lua` if missing (so the client sees both files at its next
start); a repo copy of either name is never copied. Prints `copied`, `new`, `changed`, `toc_changed`,
`unchanged`, `skipped`, `extra_in_install`, `stamp`, `restart_needed` (+ `restart_reasons`), `reload_needed`.

```
scripts/fxdev.py deploy --dry-run     # plan only
scripts/fxdev.py deploy
```

### `commands [VERB ...] [--lua 'code' ...]`
Rewrites `Forte_Dev/DevCommands.lua` as `ForteDevCommands = { "selftest ooc", "shot", { lua = "..." } }`
(safe Lua quoting for any text), in the order given. No arguments clears it. A verb is the `/fxdev` verb
without the slash; `--lua` code is screened by the deny-list. The game runs the entries ~3 s after login
or reload, never in combat. If the file did not exist, `restart_needed` is true.

```
scripts/fxdev.py commands "selftest ooc" shot --lua 'print(C_AddOns.IsAddOnLoaded("Forte_Dev"))'
```

### `type "<cmd>"`
Types one whitelisted command (all rules above).

```
scripts/fxdev.py type "/fx errors"
scripts/fxdev.py type "/run print(InCombatLockdown())"
```

### `reload [--timeout 45] [--settle 4]`
Types `/reload`, waits until the SavedVariables mtime/size changed and is stable (measured: ~1 s), then lets
the UI settle for `--settle` seconds. Exit 3 if nothing was written (the reload may not have happened).

```
scripts/fxdev.py reload
```

### `shot [--timeout 20] [--file PNG]`
Types `/fxdev shot`, waits for a NEW `Screenshots/WoWScrnShot_*.png` with a stable size, decodes the beacon,
updates the combat/group cache, and writes crops to `/tmp/fxdev/`: `panel.png` (top-left 30 % x 45 %),
`chat.png` (bottom-left 24 % x 28 %), `overview.png` (1600 px wide). Open those with `read`. `--file`
decodes an existing PNG without typing and without touching the cache. Set the format once with
`type "/console screenshotFormat png"`. Each shot is a 5-6 MB file in the game's folder; this tool never
deletes them.

```
scripts/fxdev.py shot
scripts/fxdev.py shot --file ~/some.png
```

### `sv core|dev [--path a.b.c]`
`core` = `Forte_Core.lua` (`ForteXorcistDB`), `dev` = `Forte_Dev.lua` (`ForteDevDB`). `--path` selects a part
of the JSON; Lua lists are 1-based and `-1` is the last element. Empty Lua tables come out as `[]`.

```
scripts/fxdev.py sv core --path errors.list.-1
scripts/fxdev.py sv dev --path runs.-1
```

### `errors`
`ForteXorcistDB.errors` (`session`, `list`: kind, msg, stack, count, first, last, session) as of the last
flush; it is one reload behind, so `reload` first for current data.

### `selftest [suite] [--timeout 60] [--poll 4]`
Remembers the beacon run id, types `/fxdev selftest <suite>`, then `shot`s every ~4 s until the beacon says
finished (not running) with a changed run id, or the timeout (exit 3, last beacon included). Prints the
decoded beacon and the crops. Full results (`ForteDevDB.runs`) reach disk only after the next `reload`.

```
scripts/fxdev.py selftest ooc
scripts/fxdev.py reload && scripts/fxdev.py sv dev --path runs.-1
```

### `loop [--suite S]`
ONE iteration: `deploy` → `reload` → `selftest` → `shot` → `reload` → read `ForteDevDB` + errors. Reports
every step, the newest run (pass/fail/skip, first 12 failing tests), `stamp_match` (did the game run the
build that was just deployed) and the recorded errors. Stops at the first failing step; exit 4 if the deploy
needs a client restart (nothing typed in that case).

```
scripts/fxdev.py loop --suite ooc
```

## First install and troubleshooting

* First time (and whenever `restart_needed` is true): `deploy`, then ask the owner to quit and relaunch the game
  and enable `Forte_Dev` on the character screen; after that `/reload` is enough.
* `focus ... sent nothing` (exit 5): the game window is not focused and could not be activated (Wayland keeps
  focus with another window). Nothing was typed; ask the owner to click the game window.
* `beacon not found`: `Forte_Dev` not loaded, panel off (`/fxdev panel on`), or the UI hides the top-left
  corner. Read `panel.png` / `overview.png`.
* `stamp_match: false`: the game ran older code than the install; the reload before the selftest did not take.
* The client stops reporting Lua errors after 100 per session; a flooded run can hide the first error.

# dev/ — the in-game dev loop (not shipped)

`dev/Forte_Dev` is a dev-only addon (PLAN §11.11, iteration Q): a selftest runner with real-client
suites, a pixel beacon + text panel for screenshots, and a command queue. It is **never released**:
`.pkgmeta` ignores `dev/`, `scripts/release.py` builds from `git archive HEAD addon`, and
`scripts/deploy.sh` only reads `addon/`. The host tool `scripts/fxdev.py` (sibling Q3) deploys it.

## Files

| File | Role |
|---|---|
| `Forte_Dev.toc` + identical `Forte_Dev_Camelot.toc` | `## Dependencies: Forte_Core`, `## SavedVariables: ForteDevDB` |
| `DevStamp.lua` | `ForteDevStamp = "<gitsha>+<utc>"`, rewritten by the host tool on deploy |
| `DevCommands.lua` | `ForteDevCommands = { ... }`, rewritten by the host tool (see below) |
| `Core.lua` | helpers (classifiers), `ForteDevDB`, the `/fxdev` dispatcher, DevCommands runner, event frame |
| `Selftest.lua` | runner: `T.check / eq / truthy / falsy / skip / note / fail`, caps, combat arming |
| `Suites/*.lua` | census, api, frames, persistence, data, errors (`ooc`) and combat (`combat`) |
| `Suites/ApiList.lua` | **generated** by `python3 dev/gen_api_list.py` (`--check` = staleness test) |
| `Beacon.lua`, `Panel.lua` | the screenshot surface |
| `tests/*.lua` | simulator tests |

## `/fxdev`

`selftest [ooc|combat|all]`, `shot`, `status`, `panel on|off`, `run`, `clear`.
`ooc` (default) runs every out-of-combat suite at once. `combat` **arms** the combat suite: it runs 3 s
after `PLAYER_REGEN_DISABLED` (you create the combat; Forte_Dev never does) and disarms. `all` = ooc now +
arm. `shot` repaints the beacon/panel, then calls `Screenshot()` 0.2 s later. `run` re-runs DevCommands.
`clear` empties runs/commands (the run id keeps counting) and disarms.

In combat only `status`, `panel`, `shot` and `selftest combat` (arming) are accepted; everything else is refused.

## DevCommands — read this

`ForteDevCommands` runs **once per UI load**, ~3 s after `PLAYER_ENTERING_WORLD` (a fallback fires 5 s after
the module enable if the zone-in event never reaches the frame), **never in combat** (also re-checked before
each entry), at most 20 entries, each through the same dispatcher as `/fxdev`:

```lua
ForteDevCommands = { "selftest ooc", "shot", { verb = "status" }, { lua = "return 1 + 1" } }
```

A `{ lua = "..." }` entry runs through `loadstring` + `pcall`: **the same power as `/run`**. The file is
therefore written **only by the owner's own host tool** (`scripts/fxdev.py commands ...`) and read by the
owner before a `/reload`; nothing else may write it. Results (or the error) land in `ForteDevDB.commands`
as classified strings.

## ForteDevDB (contract shape)

```
{ stamp, build, runId,
  runs = { { id, stamp, build, suite, started, finished, combat, pass, fail, skip, dropped,
             tests = { { name, status = "pass"|"fail"|"skip", detail } } } ... },   -- cap 5, newest last
  commands = { { t, verb, ok, detail } ... },                                       -- cap 30
  nonce = { value, check, written, stamp } }                                        -- persistence suite
```

Additive keys beyond the contract: `runs[].build`, `runs[].dropped` (results past the caps), `nonce`.
Only plain strings/numbers/booleans are stored — every live value goes through `FX.Probe.K` /
`FX.Compat.PlainOrNil` first. Caps: 30 recorded failures and 150 recorded entries per run, 160 characters per
detail (the client stops reporting errors after 100 per session); the pass/fail/skip counts keep counting.

## Beacon (top-left, 16 cells of 6 UI units, 96x6, strata TOOLTIP)

cell 0 magenta, cell 15 cyan; cells 1–14 black = 0 / white = 1: **1** in combat, **2** in a group,
**3** selftest running **or the combat suite armed and waiting**, **4** a run finished since load,
**5** the last run had a failure, **6** `FX.Errors.sinceLoad > 0`, **7–14** low 8 bits of `runId`
(cell 7 = most significant). Cells are colour textures tinted by the same 0/1 colour (idempotent), so the
texture API (`GetVertexColor`) reports each cell's colour. The panel (stamp, build, suite, counts, first 12
failures of up to 3 wrapped lines each, last 5 recorded errors, last 3 `ForteDevDB.commands` results with ok +
detail, so a DevCommands `lua` result is readable from the screenshot) sits under it; `/fxdev panel off` hides
only the panel. Repaint is
event-driven (run events, `PLAYER_REGEN_*`, `GROUP_ROSTER_UPDATE`, `shot`); there is no `OnUpdate`.
Cell 6 only changes on a repaint, so poll with `shot`.

## Safety

No chat, no addon messages, nothing protected or gameplay (no cast, target, move, reload). The only text
output is the local chat frame answering a typed `/fxdev`. In combat only the armed combat suite's READ
assertions run. `tests/test_safety.lua` puts tripwires on the chat/gameplay globals through a full run.

## Simulator

```
scripts/dev_sim.sh                         # builds /tmp/fx-dev-addons (symlinks: addon/Forte_* + dev/Forte_Dev)
scripts/dev_sim.sh run-tests Forte_Dev     # build + run the Forte_Dev tests (flock'd, one sim at a time)
python3 scripts/api_lint.py dev/Forte_Dev  # api_lint scans addon/ by default; dev/ needs the explicit path
python3 dev/gen_api_list.py [--check]      # regenerate / verify Suites/ApiList.lua
```

`scripts/gate.py` does not know `dev/` (it globs `addon/Forte_*`): the dev tests, toc-twin check and
syntax check are run separately. The simulator is not the client: `Screenshot()` is absent there and live
spell names differ, so those two suite checks fail in the sim by design (the sim test exempts them).

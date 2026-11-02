# fortexorcist_forever

ForteXorcist rebuilt for **World of Warcraft: Forever** (launch 2026-11-04): cooldown/spell timers,
alerts and class tools for all classes and specs, **Hunter first**. Not a port of the 2012 addon.
`PLAN.md` = what/why/next (read it before any work). `docs/` = research notes behind decisions.
GitHub: `Gevil/fortexorcist_forever`.

## Layout
- `addon/` — everything the game loads. One folder per addon: `Forte_Core` (bootstrap, compat,
  constants, module registry, `/fx`), `Forte_Cooldown` (engine + display), `Forte_<Class>`
  (generated `Data/<Class>.lua`, later class tools). Shared global namespace `ForteXorcist`.
- `tools/` — `gen_spell_data.py` + `spell_lists/<class>.json`. Never shipped.
- `scripts/` — deploy/test helpers. `docs/` — research notes.

## Workflow (owner preference)
- The main session **plans, delegates and reviews**. Actual implementation, research and scouting
  go to subagents on the local **basalt** GPU lane:
  - `fx-worker` (`~/.omp/agent/agents/fx-worker.md`) — one implementation task per call.
  - `fx-scout` (`~/.omp/agent/agents/fx-scout.md`) — one read-only research question per call,
    writes a cited note to the path it is given (use `docs/research/`).
- Basalt is **one slot**: parallel spawns queue. Check it is up before spawning
  (`~/.local/bin/gpu-lanes/lanes-status`, `curl -s http://127.0.0.1:8004/v1/models`). Don't start
  or restart the lane without the owner's go-ahead (it takes ~27 GiB VRAM and ~10 min to load; the
  owner may be playing). If a lane restart kills a running subagent, re-run it after `/v1/models`
  reports `loaded`.
- Review every subagent result against the files on disk before marking work done.

## Hard technical rules
- Forever = Retail 12.x engine, interface **16001**, `WOW_PROJECT_CAMELOT`. Use `C_Spell`,
  `C_UnitAuras`, `C_Container`, `C_Item`; old Classic globals don't exist.
- `COMBAT_LOG_EVENT_UNFILTERED` is forbidden. No combat-log designs.
- Buffs/debuffs can't be read in combat; cooldown numbers may be secret in combat. Route every such
  read through `ForteXorcist.Compat.PlainOrNil`; a secret read never overwrites known state.
  In-combat state comes from your own `UNIT_SPELLCAST_SUCCEEDED` + learned durations
  (cast-predict + reconcile, PLAN.md §3.2).
- Don't build on Blizzard's Cooldown Manager (`docs/why-not-blizzard-cdm.md`).
- No `RegisterEvent` at a file's top level except `Forte_Core`'s bootstrap frame.
- Data tables are keyed by the English **name** (ranks differ by ID), but clients can be localized
  (Forever ships 10 languages): resolve client names through `ForteXorcist.Locale`
  (`CanonicalName`, `RankIDsForName`, `FX.L`) and read by data id, never compare English strings
  to client names.
- Never write `if not FX then return end` (or any guard on `FX`) at a file's top: `FX` is a
  file-local alias (`local FX = ForteXorcist`), not a global, so the guard silently skips the file.
- There is no `FX:CallSafe`; wrap callbacks in `pcall` yourself.
- `$WORK/TODO.md` is the owner's ledger, maintained by the main session only.
- Spell IDs are generated, never hand-typed: edit `tools/spell_lists/<class>.json`, run
  `python3 tools/gen_spell_data.py <class>`. Never hand-edit `addon/*/Data/*.lua`.
- Every addon has `X.toc` and identical `X_Camelot.toc` (interface 16001). Keep them in sync.
- CooldownMaster (MIT) is the reference implementation; reuse with credit in README.
  WeaponSwingTimer SixxFix (GPLv3, WatchYourSixx; original WST by LeftHandedGlove) is the Hunter
  swing reference: code may be adapted with attribution (`addon/Forte_Core/ATTRIBUTION.md`).
  wow-ui-sim is GPL-3.0: use as a tool only, never copy its code here.

## Verification
- Syntax: `luajit -e "assert(loadfile('<file>'))"` (no `luac` on this box).
- Logic: luajit smoke test with stubs (PLAN.md §6), then wow-ui-sim tests:
  `$WORK/wow-ui-sim/run.sh wow-sim --allow-ui-version-mismatch --addons-path <abs>/addon run-tests <Addon>`.
  Always use `run.sh` (ICU 78 libs, headless, install shim for the launcher's `.product.db`;
  see PLAN.md §5). Ignore the Blizzard-side baseline errors; only `Forte_*` errors count.
  luajit stub tests do NOT validate WoW API usage — UI/API code needs a sim run.
- Visual: uiforever.com (`/app?flavor=forever`). Final: the real client
  (`<WoW install>/_forever_/`).
- A change isn't done until it has run somewhere real (sim or client), not just parsed.

## Boundaries
- Sibling checkouts are read-only: `../wow-forever-sim/forever/` (pull only, never commit),
  `../mythicsim-forever-engine/`, `../wow-ui-sim/` (binaries + `run.sh`, `icu-vendor/`).
- Commit/push only when the owner asks. Never write into the installed client except via
  `scripts/deploy.sh` when asked.

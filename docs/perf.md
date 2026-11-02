# H5s — Performance survey (measured in wow-ui-sim, 2026-11-02)

Agent `PerfScout`, baseline `e41e308`. Feeds wave-2 `H5 Perf fixes`.

**Method.** wow-ui-sim v0.1.39-forever, headless (`dump-tree`), `--class Hunter` /
`--class Warlock`, `--no-saved-vars`, probes via `--exec-lua @/tmp/perf/probe[0-6].lua`
(throwaway; repo untouched). The headless sim never fires a `C_Timer.NewTicker` callback
(the established test finding, `Forte_Cooldown/tests/test_splash.lua:27-29`; re-confirmed:
a probe ticker read 0 fires) — so every loop is measured by driving **the exact tick body**
through its public entry (`ProcessReadyPops` + `Display:Update`, `Timer:Draw`/`Logic`,
`Swing:Update`, `Reminder:Refresh`, `Banner:Update` + `_BannerPumpStep`, `Warlock UI:Tick`,
`Splash:Update`) with the ticker closure replicated 1:1 from source, N = 2000 ticks, clock
fixed (no pop) or advancing 1 tick-step. Timed with `os.clock` (CPU seconds; calibration:
2·10⁶ adds = 36.5 ms). Garbage with `collectgarbage("count")` (Kbytes; calibration: 100 k
one-cell tables = 9375 KB — LuaJIT counts BYTES, not objects, so "objects/tick" below are
inferred from cited source lines, deltas are measured).
**Numbers tagged [M] measured, [E] estimated, [I] inferred.** Measured spread across
identical probes: the first bench in a session runs hottest-traced; e.g. Cooldown-30-entry
tick measured 307 µs (Warlock run) and 480 µs (Hunter run, behind pop benches) — treat
±40 % at ≥10-entry cases. LuaJIT constant-folds closures with no upvalues, so bare
`function(a,b)` comparators are free; closures capturing upvalues allocate per creation.

Sim API caveat: `UpdateAddOnMemoryUsage()`/`GetAddOnMemoryUsage()` exist but return 0 in
the sim, `ResetAddOnCPUUsage`/`GCGetInfo`/`C_AddOns.UnloadAddOn` are nil (probe3/probe4) —
so per-add-on *resident* memory is NOT reproducible here; the uiforever 686 KB figure for
`Forte_Items` is a client number; the sim measures the Lua GC heap, which is the same
object set. The 686 KB / 700–760 KB [E] agreement (§3) shows the GC proxy is sound.

---

## 0. The loop ledger (owners, rates, per-tick walk)

Grepping the whole addon for `OnUpdate`/`C_Timer`/`NewTicker`/`After` yields exactly these
owners. `Forte_Core`, `Forte_Options`, `Forte_Items` (data-only) run **no periodic loop**.

| # | Owner (file:line) | Rate | Life | What one tick walks |
|---|---|---|---|---|
| L1 | `Forte_Cooldown/Module.lua:531-543` (ticker body :532-542) | 10 Hz | always on | `Engine:Sweep` over every live entry (`Core/Engine.lua:455-501`); per pop: OnReady + icon resolve + splash + bus fire (`Module.lua:391-418`); `Engine:Sorted` = walk entries + row-cache refill + sort (`Core/Engine.lua:528-540`); Timeline `D:Update` = per-entry pos/anchor/text, slot-release pass, grouping + cross-fade (`UI/Timeline.lua:1616-1785`); every 10th tick `ReadAll` = pcall'd C_Spell read ladder over EVERY tracked spell (`Module.lua:125-199`, gate :536) |
| L2 | `Forte_Timer/Module.lua:579-584` | 25 Hz (`DRAW_SECONDS = 0.04`, :54) | always on | `Draw` = `Rows:Sorted` walks all rows (GateAlpha + link columns + sort, `Core/Rows.lua:680-754`) + `Display:Update` = group runs, row acquire, time+name text, smart-space measure, `BindRow` (geometry, colour keys, anchors, fill, spark, slice, ticks — `UI/Rows.lua:418-760`). Every 12th tick `Logic` = `Casts:Pump` + `Rows:Sweep` + gated `Reconcile:SweepAll` (Module.lua:496-502) |
| L3 | `Forte_Hunter/UI/Swing.lua:420-428` | 10 Hz | only while a swing runs (`StopTicking` at idle :435-438) | `Swing:Update` = tracker `Progress` + fill width + time text, all dirty-checked (:362-401) |
| L4 | `Forte_Hunter/UI/Reminder.lua:265-277` | 10 Hz | only while shown | `Refresh` = aspect-missing read + alpha pulse (:239-252) |
| L5 | `Forte_Messages/Module.lua:220-235` | 20 Hz (`BANNER_TICK = 0.05`, :67) | self-rescheduling chain, stops the pass the banner lapses (:235) | `Banner:Update` = expiry + alpha fade (`UI/Banner.lua:110-126`) |
| L6 | `Forte_Warlock/UI/Module.lua:151-159` | 10 Hz | only while a view is time-driven (stop :162-165) | `Tick` walks the 4 views' `Update` (:170-182); e.g. Soulstone = tracker reads, fill fraction, clock text, target text (`UI/Soulstone.lua:103-152`) |
| L7 | `Forte_Cooldown/UI/Splash.lua:497-508` | 10 Hz | only while shown | `D:Update` walks live splash slots (bell size/alpha, dirty-checked, :467-511) |

Event-driven, not loops (floor noted where measured): the three `C_Timer.After` debounces
(`Cooldown/Module.lua:62,480,502`), `Items:Rescan` bag walk (124 µs / 1.46 KB [M] per rescan,
empty bag, probe4), `Enchants:ReadAll` 3 slots (20.9 µs [M] per call, probe3), pop path
1.64 ms / 4.25 KB [M] per 10-spell pop event (probe3; rare).

---

## 1. Per-tick cost, 0 / 10 / 30 active entries

All [M], µs per tick (1 tick = the ticker closure body); GC = bytes allocated per tick
(`collectgarbage("count")` delta ÷ N). N = 2000 ticks (200 s of session at each rate).

**L1 Forte_Cooldown ticker (10 Hz)** — entries seeded straight into `Engine.entries`
(`source="predict"`, far endTime, clock fixed → no pops; bar visible on 10/30, HideZero
hides it at 0):

| entries | µs/tick | µs per session-second | GC B/tick | GC per session-s |
|---|---|---|---|---|
| 0 | 8.7–10.4 | ~100 | 96 | ~1.0 KB |
| 10 | 133–163 | 1.3–1.6 ms | 223 | 2.2 KB |
| 30 | 307–480 | 3.1–4.8 ms | 305 | 3.1 KB |

Split at 30: `Engine:Sorted` alone = 82.8 µs + 53 B [M]; `ProcessReadyPops` (empty sweep)
alone = 6.9 µs + 48 B [M] → the Timeline draw is the remaining ~200–390 µs; super-linear
0→10→30 (13×→36× µs, only 2.3×→3.2× GC) = layout/grouping work, not allocation
(`UI/Timeline.lua:1616-1785`). 1 Hz sub `ReadAll` with the full 41-spell Hunter set
(`Engine:Build("Hunter", stubKnown)`): 229 µs + 488 B [M] per pass → ~0.23 ms/s.

**L2 Forte_Timer ticker (25 Hz)** — rows via public `Rows:InsertFromCast`, 3600 s rows,
clock fixed:

| rows | µs/tick | µs per session-second | GC B/tick | GC per session-s |
|---|---|---|---|---|
| 0 | 7.2 | ~180 | 192 | **4.8 KB** |
| 10 | 296 | 7.4 ms | 2 305 | 58 KB |
| 30 | **1 061** | **26.5 ms** | **6 342** | **158 KB ≈ 9.5 MB/min** |

`Logic` at 30 rows (every 12th tick = 2 Hz): 325 µs + **15.2 KB/call** [M] → 0.65 ms/s CPU,
30 KB/s GC (sim = out of combat, the `Reconcile:Gates` early-out (:67-80) is open; in
combat the whole 15 KB leg is 0 [M by gate structure]).

**L3 Swing (10 Hz, one live 10 000 s swing, advancing clock):** 1.6 µs/tick, **0 B** [M].
**L4 Reminder (10 Hz, shown):** 4.0 µs/tick, 0 B [M]. **L5 Banner pump (20 Hz, live):**
`Banner:Update` 0.6 µs 0 B; full pump step **10.4 µs + 712 B/step** [M] → 14.2 KB/s while
the banner is live. **L6 Warlock UI `Tick` (10 Hz, one live soulstone window, 3 idle
views):** 22.6 µs/tick + 256 B [M]; `Soulstone:Update` alone 9.6 µs + 128 B [M] — the
idle-plate legs cost ~13 µs/tick. **L7 Splash (10 Hz, one pop shown):** 0.5 µs/tick, 0 B
[M] (the bell runs inside `OnReady`; the ticker pass is dirty-checked steady state).

**Session totals [M]:** idle (0 entries, 0 rows, no class UI): ≈ **0.7 ms per session-s
(0.07 % of one sim core)** ≈ 100 (L1) + 180 (L2 draw) + 230 (1 Hz ReadAll) + 180 (2 Hz
Logic floor [E], 30-row leg measured) + 21 (Enchants) µs. Hot: Hunter mid-combat with 30 bar entries + 30 panel
rows + a running swing: ≈ **33 ms/s ≈ 3.2 % of one core**; GC ≈ 195 KB/s, of which the
Timer panel is 158 KB/s + 30 KB/s and everything else ~7 KB/s combined.

---

## 2. Garbage per tick — the allocating lines

Measured deltas §1; the sites are read from source (`..`-chains and `string.format`
between the tick entry and its leaves; LuaJIT number→string conversion allocates the
string at the concat).

**L2 Timer Draw (6 342 B/tick @ 30 rows — the addon's single largest producer).**
Per-row, per-tick, all dirty-checked *after* the key is built, i.e. the key IS the
garbage:
- `UI/Rows.lua:632` `fillKey = fillR .. "/" .. fillG .. "/" .. fillB` — 3 float→string
  conversions + 3 concats; `:637` `bgKey = fillKey .. "/" .. bgA`; `:643`
  `ncKey = nc[1] .. "/" .. nc[2] .. "/" .. nc[3]` — the NormalColor triple is a CONSTANT
  per skin yet re-stringified per row per tick.
- `UI/Rows.lua:378` `key = o.barWidth .. "|" .. o.height .. "|" .. o.iconSize`
  (`ApplyRowGeometry`) — 2 concats/row/tick; `:482` `sizeKey = o.groupWidth .. "/" .. h`
  per group/tick.
- `UI/Rows.lua:601-603` — `NameFor` builds a fresh options **table literal** per row/tick
  (~104 B); `Core/Laws.lua:336,339` concat `#id` / `(stacks)` suffixes inside `NameText`.
- `UI/Rows.lua:549` → `Laws.TimeText` → `Core/Laws.lua:205-217` — `string.format` per
  row/tick unconditionally (no `timeKey` pre-gate; contrast the Timeline law,
  `UI/Timeline.lua:316-319, 1697-1702`).
- `UI/Rows.lua:663` `tostring(row.stacks)` per row/tick when stacks ride.
- `Core/Rows.lua:708` `table.sort(out, function(a, b) … Laws.CompareLinks(a, b,
  grouping, opts.outwands …) end)` — captures upvalues → **one closure per Sorted call**
  = 25 closures/s even at 0 rows (the 192 B/tick idle floor, partly [I]; frame-side cost
  lives in the sim).
- Event-path only: `Core/Laws.lua:348` `RowKey` concats (insert/find/remove, not tick).

**L2 Timer Logic (15.2 KB/call @ 30 rows @ 2 Hz).** Per-row `SweepRow → call` varargs +
`pcall` forwarding; `Core/Reconcile.lua:96-99` and `:144` allocate a **fresh pcall
closure per aura read**; `:253-257` allocates `local out = {}` per bulk sweep. (All
[Infer-at-site]; total [M].) Zero while the gate is shut (in combat) [M structure].

**L1 Cooldown ticker (305 B/tick @ 30).** No string site survives inside the tick
(`groupSignature` reuses `g._fxParts`, `UI/Timeline.lua:1534-1543`; rows cached at
`Core/Engine.lua:506-511`); the residue is `formatRemaining`'s string at the ~1 Hz
per-slot display-key change (`UI/Timeline.lua:1697-1702`, 30 slots/s) + anchor/point
marshalling [I]. Pop events: `popInfoScratch` reuses nested tables
(`Core/Engine.lua:493-497`); `resolveReadyIcon` pcalls C_Spell per pop (`Module.lua:336-345`)
— 4.25 KB [M] per 10-pop event, event-rate.

**L5 Banner pump (712 B/step).** `Module.lua:222`/`:232` allocate a fresh
`function() M:_BannerPumpStep() end` closure per reschedule (≈50 B [I]); the ≈660 B
residue is the engine's timer object per `C_Timer.After` [I — pattern cost, measured
total].

**L6/L3/L4/L7: 0–256 B/tick [M]** — pools + dirty-checks do their job; no site to name.

---

## 3. Memory (measured on the Lua GC heap; per-addon resident APIs are sim-stubs)

- Baselines [M] (probe5, fresh sessions, at `exec-lua` time): Blizzard UI only =
  **42 803 KB**; + full Forte suite at login (Hunter profile, `Forte_Items` parsed, 8 LoD
  class add-ons NOT parsed) = **44 234 KB** → suite session cost ≈ **1 431 KB**.
- `Forte_Items` (223 588 B source, always-loaded; the uiforever number is 686 KB resident):
  not unloadable in the sim (`C_AddOns.UnloadAddOn` nil [M]), so measured *in the
  extrapolation* below. Section bytes [M]: onUse rows 55 906 B (238) + index 12 471 B;
  **procs rows 89 793 B (405) + `ProcsByName` 22 283 B + `ProcsByBuffName` 23 965 B
  = 136 041 B = 60.8 % of the file**; consumables 16 685 B (79).
- LoD class-data loads, FRESH session, each [M] (probe6; per-load GC Δ / parse clock):
  Mage 24 KB/0.6 ms, Priest 23/0.3, Paladin 26/0.3, Rogue 22/0.3, Shaman 26/0.3,
  Warrior 26/0.3, Druid 24/0.3 (files 6.4–8.5 KB, 47–76 rows) → GC ≈ **3.1–3.4 × source
  bytes**, parse ≤ 0.6 ms each. (Mid-session loads cost 1–3 ms, probe3 — JIT.)
- `Forte_Items` extrapolated from the measured ratio: 223.6 KB × 3.1–3.4 ≈
  **700–760 KB GC [E]** — matches the 686 KB uiforever resident (±10 %), which validates
  the ratio for the Items split [E].
- LoD split payoff already banked [M]: a Hunter parses 10.4 KB of the 78.3 KB of class
  Lua (one class); the nine class files total ~78 KB source → ~250 KB GC [E] if every
  class were always-loaded.
- Class add-ons beyond data (`Core/Tools`, `UI/*`, `Pages/*`, Warlock 5 UI files, Hunter
  3): inside the 1 431 KB suite total, not separable in-sim [E].

---

## 4. Top-5 savings, ranked by gain (each: fix + file:line; gains labelled)

**1. `Forte_Items` — split procs out of the always-loaded data (memory).**
`Data/Items.lua` (procs rows at the `procs = {` table, index assigns at
`items.ProcsByName[…]`/`items.ProcsByBuffName[…]`, byte share 60.8 % [M]). The proc
display itself is wave-2 `H7` and **off by default** (PLAN §11.1 H7,
`docs/design-combat-procs.md`) — today every session pays 136 KB of source (≈420 KB GC
[E]) for data nothing reads. Fix: `tools/gen_item_data.py` emits `Data/Procs.lua`
(procs + its two index tables) as a new `## LoadOnDemand: 1` add-on (mirrors
`Forte_Core/Core/Loader.lua`'s pattern) loaded by `Forte_Cooldown/Core/Items.lua` at the
first proc-display enable, procs off ⇒ never loaded. Gain ≈ **0.4 MB resident [E]**
(60 % of the 686 KB uiforever number; measured byte share × measured 3.2× ratio).

**2. Forte_Timer UI — replace the string dirty-check keys with numbers, gate the text
formats (garbage + CPU).** `UI/Rows.lua:632,637,643` (colour keys: cache
`r._fillR/_fillG/_fillB` numbers, compare numerically — 632/637/643 delete), `:378` +
`:482` (geometry/size keys: compute once in the option setters behind a `_geomDirty`
flag), `:601-603` (one module-scope scratch options table, wipe+refill), `:549` +
`Core/Laws.lua:205-217` (adopt the Timeline `timeKey` law — `UI/Timeline.lua:316-319,
1697-1702`: compute the integer display key, `string.format`/`SetText` only on change —
and `NameText` `Core/Laws.lua:330-341` concats ride the same key). Measured base: 6.3
KB/tick @ 30 rows = 9.5 MB/min; 2.3 KB/tick @ 10. Gain [E from measured per-row deltas,
sites attributed by reading]: **−60…75 % of the panel's 25 Hz garbage (≈9 MB/min →
2–4 MB/min)** and **≈ −25…35 % of Draw** (1 061 → ~700–800 µs/tick, 26.5 → 18–20 ms/s);
this makes the panel — the 3.4×-faster-per-row loop (10→30 rows costs 3.6× µs at the
2.5×-higher rate) — the whole suite's #1 CPU loop at realistic load.
**3. Forte_Timer UI — stop re-anchoring geometry every tick (CPU).** `UI/Rows.lua:489-490`
(`g.frame:ClearAllPoints()` + `SetPoint` per group per tick), `:613-614` (per-row bar
ClearAllPoints+SetPoint; the x = `o.barInset + extra`, y = `barOffset` are option/layout
values, not time), `:690-694` spark (x = `barval * o.barWidth` DOES move — keep),
`:737-741` tick marks (static per row — keep only on acquire). Gate each anchor behind
the (x, y, key) numbers, re-anchor on change only. Gain [E from the per-row Draw deltas]:
**≈ −10…20 % of Draw (~2.5–5 ms/s at 30 rows)**.
**4. Forte_Timer Logic — de-closure the out-of-combat aura sweep (garbage).**
`Core/Reconcile.lua:96-99` + `:144` hoist the two `pcall(function() … end)` field-readers
to module-scope functions taking `aura` (pass as `pcall(readExp, aura)`), `:253-257`
preallocate the byIndex `out` scratch on `Reconcile`. Measured base: 15.2 KB/call @ 2 Hz
= 30 KB/s out-of-combat (0 in combat, gate `:67-80`). Gain [E]: **−70…85 % of that leg
(≈20–25 KB/s of out-of-combat idle)** — matters because it runs on EVERY login session's
out-of-combat minutes, at zero rows too.
**5. Idle floors: hoist the sort closure; do NOT stop the tickers (garbage).**
`Core/Rows.lua:708` — move `grouping`/`outwands` into module-scope locals refreshed at
the top of `Rows:Sorted`, so the comparator is upvalue-free (constant-folded, zero
closures; the Timeline's comparator `Core/Engine.lua:536-539` is the shape to copy). Kills
25 closures/s of the 4.8 KB/s 0-row floor [M base, E part]. Stopping tickers at idle is
**not** a saving worth taking: measured floors are 10.4 µs@10 Hz (L1) and 7.2 µs@25 Hz
(L2) — the suite idles at ~0.7 ms per session-second (0.07 % of a core) [M]; a
visibility gate buys <0.2 ms/s and adds a lifecycle law.

Near-misses (measured, small): banner pump closure hoist — `Forte_Messages/Module.lua:222
+ :232` share one prebuilt closure (≈ −1 KB/s of the 14.2 KB/s while a banner is live
[E]; the ≈660 B/step engine-timer residue [I] is the price of the catalog-legal
self-rescheduling pattern, `Module.lua:213-217`); `Engine:Sorted`'s O(n log n) sort
(`Core/Engine.lua:536`) is 83 µs of L1's 307–480 [M] — an insertion-sorted live list would
cut it ~2× [E], worth doing only alongside #2's pattern, not alone.

**What is NOT a problem [M]:** the Hunter swing (1.6 µs, 0 B), Reminder (4 µs, 0 B),
Splash (0.5 µs, 0 B), banner `Update` body (0.6 µs, 0 B), Warlock views (22.6 µs, 256 B)
— the hidden-frame law + start/stop ticker discipline + slot pools work: every
shown-only loop is 2 orders of magnitude below the always-on panels. The 1 Hz
read-ladder (229 µs @ 41 tracked) scales ~5.6 µs/tracked-spell — at the biggest live
set (~76, Warlock) ~0.4 ms/s [E].

---

## 5. Open questions

1. **Real-client per-frame rates.** The sim's OnUpdate `elapsed` gates never run here
   (no frames); the 10 Hz gates (`Swing.lua:420`, `Reminder.lua:265`,
   `Warlock/UI/Module.lua:151`, `Splash.lua:497`) accumulate `elapsed` and skip below
   `TICK_SECONDS`, so per-frame cost is a few adds + the gate — [I] — but the µs numbers
   above are tick-body costs; a 1 fps-fraction per frame remains unmeasured until
   uiforever / launch. Launch-day `/fx` probe should read `GetAddOnCPUUsage` windows
   (exists [M probe1], returns per-addon totals the sim leaves at 0).
2. **`collectgarbage("count")` is a bytes counter** (LuaJIT), so §2's per-site object
   counts are source-readings; a GC-step-count instrument would separate string vs table
   allocations. None in the sim (`GCGetInfo` nil [M]).
3. **Items split load trigger**: procs-load must also ride the H7 enable path (new
   wave-2 flag) — Loader today knows only class tokens (`Loader.lua:38-48`); a
   `FX.LoadAddOnOnDemand(name)` generalization is needed (1 function).
4. **Frame/texture object cost** (Timeline slot pools, Timer row pools) is invisible to
   the sim's GC counter; the uiforever import (manager) should snapshot
   `UpdateAddOnMemoryUsage`+`GetAddOnMemoryUsage` per Forte add-on — the API pair is
   live there, stubbed here [M].
5. **Sort at 60+ entries** (full raid-buff wear): L1 measured to 30; the 0→30 trend is
   ~quadratic in µs; the 10 Hz tick at 60 entries extrapolates ≈ 1–2 ms/tick [E] —
   measure before any Max increase.

Probe scripts: `/tmp/perf/probe0-6.lua` (throwaway, outside the repo).

---

## 6. Wave 2a H5 — fixes 2, 3, 4, 5 applied (after)

Same rig, same probes: `Casts.now`-injected clock, the public tick bodies
(`Module:Draw`, `Rows:Sorted`, `Module:Logic`), `os.clock()` for CPU (µs) and
`collectgarbage("count")` deltas × 1024 for bytes. Files:
`Forte_Timer/UI/Rows.lua` (fixes 2 + 3), `Forte_Timer/Core/Rows.lua` (fix 5,
comparator only), `Forte_Timer/Core/Reconcile.lua` (fix 4).

**The renderer reads the global `GetTime()`** for the times, the fills and the
spark (`UI/Rows.lua`'s `now`), while the sort, the gates and the logic cadence
ride the module's injectable `Casts.now`. Two clocks, and the sim's `GetTime`
advances in whole seconds: a measurement body that runs 20+ passes crosses a
second boundary, which is a *shown value changing* — the reason
`Forte_Timer/tests/test_perf_gates.lua` stubs the global for its bodies, and
the reason the numbers below advance `Casts.now` (the renderer's `now` is
fixed) and move each row's `drawExpireAt` (the fill and the times move)
together.

### Draw (`Module:Draw`, 25 Hz; µs/tick, bytes/tick)

| rows | before | after | ∆ CPU | ∆ GC |
|---|---|---|---|---|
| 0  | 12.6 / 168  | 7.9 / 72   | −37 % | −57 % |
| 10 | 402.2 / 2113 | 149.7 / 74 | −63 % | −97 % |
| 30 | 1098.0 / 6305 | 562.0 / 437 | −49 % | −93 % |

At 30 rows the panel goes from 27 ms + 158 KB of garbage **per session-second**
to 14 ms + 11 KB. The row's per-tick bytestream is now ~15 B at 10 rows (the
pool, the spark's `SetPoint`s and the `SparkOffset` string the frame's law
requires), and the steady-state 30-row figure (437 B/tick) is dominated by the
*fill* leg's `SparkOffset` concats, not by dirty-check keys: §4's fix 2 "2000
formats/s" was 100 % of the string keying and is gone.

### Sorted (`Rows:Sorted`, per call; µs, bytes)

| rows | before | after |
|---|---|---|
| 0 (fresh out table) | 3.9 / 168  | 2.4 / 72 |
| 0 (reused out)      | 3.7 / 96   | 0.6 / 0  |
| 10 | 58.7 / 168  | 39.6 / 72 |
| 30 | 143.9 / 168 | 119.9 / 72 |

The 0-row reuse leg is the clean read of fix 5: **96 B and 3.1 µs → 0 B and
0 µs** — the per-call comparator closure, charged even when there is nothing to
sort, 25 times a second on an idle panel. The 72 B in the "fresh out table"
column is the caller's table literal, not the pass's.

### Logic / aura sweep (`Module:Logic`, 2 Hz out of combat; µs, bytes)

| rows | before | after |
|---|---|---|
| 0  | 293.4 / 15104 | 116.9 / 11705 |
| 30 | 275.6 / 15176 | 125.7 / 11776 |

**Attribution.** ~11.6 KB of both columns is the *sim's* live aura readers
allocating a fresh aura list per read: the leg is 596 reads/call (2 rows walked
× 12 reader passes + the liveness probes), 808 reads/s at 2 Hz, ~19 B per read.
The preallocated-stub-reader rig (facts handed as prebuilt tables, so the
readers allocate nothing) separates the code from the harness, 12 rows:

| leg | before | after |
|---|---|---|
| sealed auras (12 sealed reads/call; the sealed leg exits the row's path) | 463 B/call | 36 B/call |
| 0 rows | 144 B/call | 72 B/call |
| live readers, 12 rows | 5447 B/call | 1544 B/call |

Fix 4's own cost is the sealed column: a sealed read is a `pcall` that raises,
so the sealed leg is where the two hoisted field readers run, and it is 12
closures per call before and 0 after. The live-readers column's 5447 → 1544 is
the `SweepBulk` `out = {}` per pass plus the closure rides on the same path.

### Tests (the gates, `Forte_Timer/tests/test_perf_gates.lua`)

Every ceiling sits between a measured before and after number, so each one
fails on the pre-fix code (the three files' fix sites were reverted to their
pre-fix bodies on 2026-11-02, each seam on its own and all together, and this
file failed: the counters raise (`D.counts` is
new), 20 steady passes formatted 20 time texts (ceiling 0), a 40-pass run
re-anchored groups 40 times (ceiling 0), the sweep read 463 B/call (ceiling
150), the 0-row sort cost 3.7 µs (ceiling 3.4), the 30-row draw 6305 B/tick
(ceiling 1500)).

One gate is NOT a GC gate: `Rows:Sorted`'s closure is a compile-time-visible
allocation the LuaJIT backend hoists out of a measurement loop at 0 rows, so
the byte counter reads the same on both builds. Fix 5 is gated on **time**
(3.9 → 2.4 µs/call at 0 rows) plus an order-parity test against
`Laws.CompareLinks` under all four `{groupID, outwands}` combinations, and the
zero-allocation fact is read from the hoist's shape, not measured.

### Visual

`docs/media/sim/fx_timer_perf_before.png` / `_after.png`: the same
`/fx timer test` panel, bars, fills, tick marks, sparks and headers identical.

Probe scripts: `/tmp/perf/probe_h5.lua`, `/tmp/perf/probe_h5r.lua` (throwaway,
outside the repo).

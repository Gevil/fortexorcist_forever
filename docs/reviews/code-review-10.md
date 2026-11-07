# Code review 10 — `d490e2e` "First live session on the Forever client" (adversarial)

Scope: all 18 files of `git show d490e2e`, judged against `AGENTS.md` hard rules, the pinned
Forever API catalog (`docs/api/wow-addon-api-agents`), and the test suites as they stand.
Line numbers are the commit's post-image, verified identical to the working tree
(`git log d490e2e..HEAD -- addon/` is empty). All catalog checks were run against
`docs/api/wow-addon-api-agents` (the `api-coverage.json` / `skills/*/references` pairs).

## Answer (the headline)

**No BLOCKER.** The two headline fixes — the multi-unit `RegisterUnitEvent` calls and the
`probeEpoch`/`isInitialLogin` ride — are exactly right against the catalog. Four findings are
MAJOR: (1) the `UNIT_DIED` "fix" silently retires the target-death cleanup on the real client
while `test_unit_died.lua` stays green by driving the branch by hand — the suite now certifies
code that cannot run in the field; (2) `Engine.AddExtras` hand-keyed `"Berserking"` /
`"Rapid Regeneration"` into `tracked` break on every non-enUS client (English names compared
against canonicalized client names — the repo's own H1 doctrine says that path "returns nil
and every known filter dies"); (3) `Log:Status()` calls `LoggingChat()` with no argument —
the catalog declares `LoggingChat(enable)` (the query is `IsLoggingChat`), so a bare `/fx log`
raises on the real client through the unpctalled slash dispatch; (4) `Log.lua` registers
`PLAYER_LOGIN` from a file's top level, which the law allows for one frame only — the
Forte_Core bootstrap. 8 MINOR, 15 INFO, 16 changed behaviours with no test (suite never run —
run-tests + the frame budget in `docs/perf.md` are the main verification gap).

The pump-heal / pcall job isolation, the self-target sweep gate, the aura adoption
(`OnAuraFact` arg order verified), the `shares` partner logic (bounded, no recursion), the
icon glow (`iconSize == height` invariant), the Options keyboard fix, and the toc parity
(md5-identical) all check out.

---

## (a)+(b)+(d) Findings

### M1 — MAJOR — `Forte_Timer/Module.lua:802-805`: the UNIT_DIED "fix" loses the feature on the live client, and the suite certifies dead code

```lua
-- UNIT_DIED does not exist as a unit event on the live client (live
-- 2026-11-06: RegisterUnitEvent raised and aborted the whole module).
-- Optional: dead-target rows then retire on row expiry instead.
pcall(f.RegisterUnitEvent, f, "UNIT_DIED", "target")
```

Diagnosis is half right (the raise is a live observation, and not aborting the module is the
right triage) — but the comment's claim is contradicted by the pinned catalog: `UNIT_DIED`
exists in Forever (`api-coverage.json:26933`:
`["event","UNIT_DIED","Global:Unit","Unit","All",378,4223, ...,[["unitGUID","WOWGUID",false]],...,{"SecretWhenUnitIdentityRestricted":"true",...}]`).
Its payload is a **WOWGUID**, not a unit token — events whose payload is not unit-keyed are
base events: `f:RegisterEvent("UNIT_DIED")`, and `RegisterUnitEvent` raising for it is the
expected behavior, not evidence of a missing event. The existing `OnEvent` branch classifies
the payload and answers `UnitExists("target")` — content-agnostic by design
(`test_unit_died.lua:1-19`: "The payload's CONTENT is not compared") — so a **base-event
registration feeds the branch as-is**, GUID payload included (a non-string payload classifies
non-string → inert, which the "inert" legs already pin).

Failing scenario (real client): kill a mob with Hunter's Mark up; the mark row sits its full
window (60 s+) against a corpse, exactly the stale-bar class the E5 law was written to retire.
And every test in `test_unit_died.lua` passes — they all go through
`dispatch("UNIT_DIED", ...)` on the frame's `OnEvent` script, never through registration
(`grep IsEventRegistered` in `Forte_Timer/tests` = 0 hits). The suite green-certifies a feature
that cannot fire on the shipped client.

Fix: `pcall(f.RegisterEvent, f, "UNIT_DIED")` (base event, catalog shape); keep the pcall
wrapper. Comment the *payload shape* (unitGUID, SecretWhenUnitIdentityRestricted — inert when
sealed, the inert legs already cover it). Add a registration-pinning test (below, MT-2).

### M2 — MAJOR — `Forte_Cooldown/Core/Engine.lua:150-153, 194-201`: hand-kept English names break `AddExtras` on localized clients (law: "never compare English strings to client names")

```lua
Engine.RACIALS = {
    [20554] = { name = "Berserking", cooldownMs = 180000 },
    [1260270] = { name = "Rapid Regeneration", cooldownMs = 180000 },   -- channel; 3 min per owner
    [1293241] = { cooldownMs = 6000, shares = "Arcane Shot" },          -- Summon Hawk talent (owner, 2026-11-06)
}
...
local name = spell.name or liveSpellName(id)
local known = name and (isKnown(name)
    or (FX.Compat.IsPlayerSpell and FX.Compat.IsPlayerSpell(id)))
```

The feed that fills `tracked` keys is `RecordCastEvent`'s canonicalized client name:
`Engine:OnCast(FX.Locale and FX.Locale.CanonicalName(name) or name, GetTime())`
(`Forte_Cooldown/Module.lua:417-418`). `Locale` aliases are built **from the data ids**
(`Forte_Core/Core/Locale.lua:21`: "Aliases are built from the DATA IDS via
`C_Spell.GetSpellInfo(id).name`"). 20554 / 1260270 are in no generated data file, so on a deDE
client a Berserking cast canonicalizes to `"Berserken"` (identity, no alias) and
`tracked["Berserking"]` never matches. The known gate confirms it: `isKnown("Berserking")`
resolves via the client's name table — the Module's own doctrine
(`Forte_Cooldown/Module.lua:79-84`): "on a non-enUS client it returns nil and every known
filter dies" — so the gate survives only via the `IsPlayerSpell(id)` fallback, which then
tracks the spell as an **inert** bar.

Failing scenario (deDE Troll Hunter): the bar carries "Berserking" (and
"Rapid Regeneration") as permanent ready entries; casting the racials starts neither bar.
enUS is fine. The `1293241` entry (name omitted → `liveSpellName` = the client's own localized
name) is the locale-coherent half — proof the author knew the shape; the hand-written English
names are the violation. The file is also the "names never ids at runtime" law's runtime
surface: the id-keyed hand table is the source the law guards against.

Fix: route RACIALS through the generator (a `tools/spell_lists/extras.json` input emitting
ordinary data rows with `isUnique`/`shares` — the same route the `Casts.UNIQUE` comment
promises "hand-kept until the generator emits isUnique"); interim: drop the hand-written
`name` fields entirely and let `CanonicalName(liveSpellName(id))` (with an alias registration)
key the entry on every locale.

### M3 — MAJOR — `Forte_Core/Core/Log.lua:65-68`: `/fx log` (no argument) raises on the real client

```lua
function Log:Status()
    local chatOn = type(_G.LoggingChat) == "function" and _G.LoggingChat() or false
```

Catalog: `LoggingChat(enable)` takes a required boolean
(`skills/wow-api-misc-systems/references/RETAIL-BASELINE.md:315-318`:
`LoggingChat(enable) | — | Toggle combat log file` / `IsLoggingChat() | isLogging | Chat logging?`).
The query function is `IsLoggingChat`. Calling `LoggingChat()` with no argument raises the
C-side usage error; `FX.OnSlash` dispatches registered subs **unprotected**
(`Forte_Core/Core/Init.lua:100-102`: `fn(rest)` — no pcall).

Failing scenario (real client): type `/fx log` → Lua error (popup / BugGrabber / and with
`/fx log on`'s own wrapper, an `[FX-ERR]` spam of the status command). The bare-status path is
the documented "else" leg of the slash handler, so the everyday "what's the state" command is
the one that raises.

Fix: `local ok, chatOn = pcall(_G.IsLoggingChat or _G.LoggingChat)` — prefer
`IsLoggingChat()` (documented zero-arg query), pcall'd, defaulting false.

### M4 — MAJOR — `Forte_Core/Core/Log.lua:87-92`: top-level `RegisterEvent` — law-violating registrant

```lua
local f = _G.CreateFrame and _G.CreateFrame("Frame")
if f then
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function()
```

AGENTS.md, verbatim: "No `RegisterEvent` at a file's top level except `Forte_Core`'s bootstrap
frame." This is a second login-time registrant in Forte_Core; the repo convention is explicit
that the bootstrap's frame is the only one (`test_probe.lua`'s epoch test, pre-change: "OnEnable
rides Forte_Core's bootstrap's PLAYER_LOGIN"; `Probe`/`TestMode` obey — they register inside
`OnEnable`).

Failing scenario: none at runtime (the code works) — the law exists to keep login-order events
in one auditable place, and this commit's own launch-day work is precisely about
login/reload/restriction event order; a second silent registrant is the class of drift the
law exists to stop. Fix: drive re-apply from the bootstrap (`Events.lua` PLAYER_LOGIN chain →
`FX.LogModule:Reapply()`), from `Log:OnEnable`-style module wiring, or gate at the existing
`PLAYER_LOGIN` consumers — not a file-top frame.

### m1 — MINOR — `Forte_Timer/Core/Reconcile.lua:291-299`: the aura adoption admits `IGNORE`-band rows

```lua
        if row and row.name == name and row.state <= Laws.REMOVE
            and row.targetKey ~= "none"
```

`Laws.IGNORE = -1` (`Forte_Timer/Core/Laws.lua:43`) is *below* `NORMAL = 0`, so the intended
"live rows" band `state <= REMOVE(3)` also matches the refuse-removal/zeroing band. A row the
pump is mid-evicting (state IGNORE, zeroed by the next `Fade`, `Rows.lua:590`) counts as the
adopt target: `OnAuraFact` mutates it, and its verdict is never `"inserted"`, so the insert is
suppressed — the confirmed aura's bar rides a row that is leaving the array. Window is one
pump cycle, out-of-combat sweeps, reproducible on a re-applied Hunter's Mark landing in the
fade band (the exact live case this hunk is about). Fix:
`row.state >= Laws.NORMAL and row.state <= Laws.REMOVE`.

### m2 — MINOR — `Forte_Hunter/UI/Reminder.lua:210`: `ipairs` over an array with a nil-first hole silently drops the name-keyed attempt

```lua
    for _, key in ipairs({ id, name }) do
```

`{ id, name }` with `id == nil` stores nothing at `[1]`; `ipairs` starts at 1, reads nil, and
**the loop body never runs** — the "then by name" leg (the comment's promise) cannot execute
for exactly the spells that have no `HunterByName` entry. Latent today (every reachable
`IconName()` value — tracker canonical name, `_lastAspect`, `names[1]` — resolves through the
data-derived list), real the moment a tracker carries a name the data file lacks. Real-client
symptom: the reminder shows the question-mark icon forever with a spell the client *does* list
by name. Fix:

```lua
    local keys = { id, name }
    for i = 1, 2 do
        local key = keys[i]
        ...
```

### m3 — MINOR — `Forte_Cooldown/UI/Timeline.lua:2115-2121`: lane steps are unclamped

```lua
        local lane = 0
        while lanes[lane] and math.abs(x - lanes[lane]) < H do lane = lane + 1 end
        lanes[lane] = x
        local step = lane * H * 0.75
        if S.Vertical then ox = ox + step else oy = oy + step end
```

Geometry, orientation choice (`ox` is perpendicular in vertical, `oy` in horizontal), per-lane
greedy keying, the per-pass lane wipe (`:2075-2077`) and the `slot._cl` dirty leg are all
correct. The number of lanes is unbounded: a dense log-scale tail (a dozen near-ready icons
inside one icon-width) chains lanes 0..11 → offsets to ~`11 * 0.75 * H` ≈ 165 px off the axis
with `H=18` — icons drawn far outside the bar, over neighbouring UI. `math.abs` itself is fine
(`skills/wow-lua-api/references/MATH_LIBRARY.md:16`). Real-client scenario: burst of same-cd
casts (traps, shared Arcane Shot/Summon Hawk windows) near the ready edge → icons visibly
detached from the bar. Fix: clamp the lane index (`if lane > 3 then lane = ...` — fold
overflow icons back into the last lane, or stack a second axis step) and state the cap.

### m4 — MINOR — `Forte_Cooldown/Core/Engine.lua:150-153`: hand-typed spell ids in shipped code

AGENTS.md verbatim: "**Spell IDs are generated, never hand-typed**: edit
`tools/spell_lists/<class>.json`, run `python3 tools/gen_spell_data.py <class>`. Never
hand-edit `addon/*/Data/*.lua`." The `RACIALS` block hand-types `20554`, `1260270`, `1293241`
into `addon/Forte_Cooldown/Core/Engine.lua`. It is outside `Data/*.lua`, so the letter is
met, and the comment owns the hand-keep ("Hand-kept, ID-keyed") — the drift the law prevents
is the one now being paid: the ids bypass `gen_spell_data.py`, the `DataRefreshM*` refresh,
and the rank-variant sweep (Berserking has rank siblings in 2012 data — a rank-drift on the
live build is invisible to the refresh that would catch a data-file twin). The 1260270 /
1293241 ids are owner-measured (comment) and unverifiable offline `[INFERENCE]`. Fix: fold the
three into the generator's extras input (M2's fix is the same move).

### m5 — MINOR — `Forte_Core/Core/Log.lua:80-81`: `/fx log test` calls a possibly-nil global

```lua
        pcall(error, "FX log self-test (deliberate)")
        _G.geterrorhandler()("FX log self-test (deliberate)")
```

`geterrorhandler` is real on the client (`skills/wow-api-lua-environment/references/RETAIL-BASELINE.md:335-336`),
so the client leg works — but the call is ungated while every other client touch in the file is
`type(...) == "function"`-gated, and `pcall(error, ...)` on line 80 never reaches the wrapper
at all (pcall swallows) — the first line is decoration, the second is the test. In a
restricted/absent-handler environment (sim, future client) the command dies with "attempt to
call a nil value". Fix: drop line 80; gate line 81 with the file's own `type(...)` idiom.

### m6 — MINOR — `Forte_Cooldown/Module.lua:916-933`: render pump — the lifecycle claim checks out; the cadence math and budget are unpinned

```lua
    if not M._renderFrame then
        local rf = CreateFrame("Frame", nil, UIParent)
        M._renderFrame = rf
        local acc = 0
        rf:SetScript("OnUpdate", function(_, elapsed)
            acc = acc + (tonumber(elapsed) or 0)
            if acc < RENDER_SECONDS then return end
            acc = 0
```

Checked, all good: there is **no disable path** in the codebase (`Loader.lua` has no
`OnDisable`/`DisableAll` — grep = 0), so "only runs while the module is enabled" is true
trivially; the frame is never hidden, so the law ("hidden frames get no OnUpdate") is honored
by design; a hidden bar costs ~nothing (`Timeline.lua:2066-2070` `UpdateVisibility` gate
returns before any slot work); `GetTime()`/`GetSpellCharges`/`math.*` all documented; the
shared `sortedScratch` is single-threaded-safe. Two residuals: (1) `acc = 0` (not
`acc = acc - RENDER_SECONDS`) throws away the remainder every pass, so on a 60 Hz client
(elapsed ≈ 16.7 ms, jittered) the realized rate oscillates ~30–60 Hz — the CHANGELOG's
"60 Hz" is nominal; (2) the full `Update` pass (`Engine:Sorted` sort + slot loop) now runs up
to 6×/s more than the budget in `docs/perf.md` was measured against, and no test pins the
pump's existence, cadence, or `Display:Update` call rate at all. `[INFERENCE]` the added cost
is small (dirty-checked C++ writes). Fix: carry the remainder (`acc = acc - RENDER_SECONDS`
after the gate loop) and pin pump-once / hidden-bar-cheap in a sim test.

### m7 — MINOR — `Forte_Timer/Core/Casts.lua:661-666`: the `raised` instrument is outside its own init contract

```lua
            if not okJob then
                self:InitStatus()
                self.status.raised = (self.status.raised or 0) + 1
```

`InitStatus`'s key list (`Casts.lua:190-196`) enumerates `seen…retired` — **no `"raised"`** —
so the `InitStatus()` call before the increment is a no-op for this key and the counter lands
in `FX.db.diag.timerCasts` un-initialized (works via `or 0`, accumulates across sessions like
its siblings). Chat: the one-line `FX.Print("timer: a cast job failed: ...")` (line 665)
prints through the ungated `FX.Print` (`Forte_Core/Core/Constants.lua:68-71`) — by-design
("report ... in chat", CHANGELOG'd), deduped by `_pumpErr`, and the message is an engine
string, no secret content. Fix: add `"raised"` to the init list; the rest is cosmetic.

### m8 — MINOR — `Forte_Timer/Core/Laws.lua:140`: `SparkFlareFactor` is now dead weight

The glow swap (`Rows.lua:474`, `Rows.lua:634`) replaced the factor's only two consumers;
`grep SparkFlareFactor addon/` now hits only its own definition. The law's cited source value
(:2534) rides on as unreferenced skin. Fix: delete (the comment records the source figure
already) — or keep it as a cited law value *with* a consumer; as is it is the constant a
future reader "fixes" back.

### INFO (verified — no action, evidence for the record)

- **i1 — the headline registration fix is catalog-correct.**
  `SimpleFrameAPI:RegisterUnitEvent` takes `["eventName","cstring"],["units","UnitTokenType",{"StrideIndex":"1"}]`
  — variadic unit tokens (`docs/audit/api-coverage.json:24839`), documented
  `RegisterUnitEvent(event, unit1, ...)` (`wow-api-widget/references/FRAME-WIDGETS.md:20`).
  The live observation (second call replaced the first unit set) is consistent with that
  signature, and one call per event listing every unit is the documented shape.
  `Forte_Timer/Module.lua:788,790,801` are right. (The replace semantics themselves are
  `[INFERENCE]` from the live note; the catalog does not document re-registration.)
- **i2 — `tokenHoldsRowUnit` (`Reconcile.lua:250-263`) is fail-open and law-clean.** `pcall`
  + `plain()` on `UnitName`; guid-first (identity), name-second, "anything unreadable answers
  true" = the old sweep. The cast rows' `targetKey` is the target's name (the pump promotes
  `row.unitToken`/`castToken` only, `Casts.lua:596-600`) so the `key ~= token` name leg fires
  exactly for `token = "target"`. Self-target: guid leg (aura rows) answers false, name leg
  answers false, row survives — the live report is fixed; a sealed identity falls back to the
  old wipe, honestly documented.
- **i3 — `Casts.UNIQUE` keyed by English works on deDE.** `job.name` is
  `NameOf(spellID)`'s output, canonicalized: `if FX.Locale then return
  FX.Locale.CanonicalName(resolved) end` (`Casts.lua:132`); Hunter's Mark's id is in the
  generated data, so its deDE alias exists and the table key matches. Law-compliant
  ("keyed by the English name … resolve … through `FX.Locale`").
- **i4 — `table.maxn` exists on the client** (`wow-lua-api/references/TABLE_LIBRARY.md:25`:
  "`table.maxn(list)` Returns the largest positive numeric index"). The heal loop
  (`Casts.lua:562-569`) compacts correctly and the tail truncation is consistent
  (`:676`). Sim parity `[INFERENCE]` — the suite was not run; the run-tests pass is the gate.
- **i5 — the pcall-wrapped job is a semantics-preserving wrap.** The enclosed region
  (`Casts.lua:576-658`) contains no top-level `return`/`break` whose meaning the closure
  changes (all control is `if`/`for` nesting); one closure allocation per due job is the GC
  cost, acceptable at the queue's cadence.
- **i6 — the aura adoption calls `OnAuraFact` with the right argument order**
  (`Reconcile.lua:362-364` vs `Rows.lua:400-401`: `(row, factExpire, factTotal, stacks, now,
  unitToken, raidMark, guid)`); the verdict tuple is taken single-valued (correct). Note the
  adopt/extend/refresh verdicts increment **no** counter in the bulk pass (only `"inserted"`
  is counted, `Reconcile.lua:375-377`) — `counts.adopted` stays a per-row-sweep-only story.
- **i7 — `shares` has no recursion hazard.** `OnCast(pname, now, true)` guards the partner
  leg with `if not _partner` (`Engine.lua:259-266`); the sweep mutates `entries`, iterates
  `tracked`; mutual `shares` entries settle in one hop. `AddExtras` runs after `Build`'s
  wipe and before `carryRestore` (`Module.lua:487-492`), so carried windows ride it; the
  known-gate (`isKnown` H1 chain, then `IsPlayerSpell(id)`) keeps non-Trolls clean; sim
  `GetSpellInfo(1293241)` → nil → `known = nil` → not tracked → the existing tracked-count
  tests are undisturbed.
- **i8 — `probeEpoch` matches the catalog exactly:** `PLAYER_ENTERING_WORLD` payload =
  `[["isInitialLogin","bool"],["isReloadingUi","bool"]]`
  (`api-coverage.json:26933`, `wow-api-unit-player/references/PLAYER-FUNCTIONS.md:352`);
  binding `(frame, _, isInitialLogin)` is right, the self-unregister
  (`Probe.lua:1272`) keeps zone transitions out, the lifecycle order
  (`wow-addon-structure/references/LOADING_LIFECYCLE.md:19-21`) guarantees the frame registers
  before the login's PEW. Updated test (leg-for-reload, leg-for-login) is the right pin.
- **i9 — the Probe window fixes are the documented idioms:** `CreateTexture(nil,"BACKGROUND")`
  + `SetAllPoints` + `SetColorTexture` mirrors `FRAME-WIDGETS.md:75-77`; the
  `pcall(f.CreateTexture, ...)` gate + `_win` existence check
  (`Probe.lua:1092`, set at `:1046`) turns the live "font not set" swallow into a named report.
- **i10 — Options: every new API call is catalog-documented:** `SetAutoFocus(false)`
  (`SimpleEditBoxAPI:SetAutoFocus`; the `FRAME-CONTROLS.md:99` example *is*
  `edit:SetAutoFocus(false)`), `RegisterForClicks`/`EnableMouse`/`SetFrameStrata`/
  `SetFrameLevel` (`FRAME-WIDGETS.md:26-28`, `forever.json:838/1087/1088`). The Esc close
  itself rides the pre-existing `UISpecialFrames` registration
  (`Window.lua:397-407`) — the commit's real Esc fix was the DIALOG strata (other addons'
  MEDIUM frames covering the window is also why the X appeared dead; the `EnableMouse`/
  `RegisterForClicks` pair is belt-and-suspenders, the default button shape already answers
  `LeftButtonUp`, `SCRIPT-HANDLERS.md:390`). The Esc-restore tests (`test_options.lua:171-175,
  236-240`) pass against the new handlers (they call the script by hand with `(eb)`).
- **i11 — both `.toc` files list `Core/Log.lua` and are md5-identical** (verified on disk:
  `62b69a6b...` ×2); load order (after `Probe.lua`) is safe — `Log.lua` only needs
  `FX.RegisterSlash`/`FX.Print` from `Init.lua`/`Constants.lua`, both earlier.
- **i12 — Log SavedVariables: one boolean.** `FX.db.logOn` is the whole write
  (`Log.lua:50,62`); chat lines go to the client's `Logs/WoWChatLog.txt`, not SV; the chat
  logging itself is opt-in and off by default (chat/comms law honored); the Timer dev trace
  (`Module.lua:883-893`) prints `P()`-classified values only (seals arrive as `nil`),
  `UnitAffectingCombat` is documented (`api-coverage.json:32470`), and the trace is gated on
  `FX.LogModule.on`.
- **i13 — icon glow geometry:** `o.iconSize == o.height` is an enforced invariant
  (`Rows.lua:220`, `Module.lua:356`), so `iconSize * IconGlowFactor × height * IconGlowFactor`
  is a uniform 64/34 scale of a square ring; the bright line (px 15..49 per the comment) maps
  to the icon edge on both axes; acquire-time and geometry-time formulas agree.
- **i14 — `Rows.lua:186-193` carries a vestige:** the new `self.title/self.anchor` pair plus
  the call, then the pre-existing `self.anchor, self.title = f, title` re-assigns the same
  values. Harmless; delete the second pair at the next touch. `D:Init` sets `self.options`
  (`:132`) before `ApplyTitleAnchor` (`:191`), so the `self.options == nil` leg is dead on
  that path (it exists for the `nil`-expand call — fine); `SetExpand` nil-guards
  `FX.Timer.Display` (`Module.lua:379-382`) and Init applies the stored value.
- **i15 — `test_unit_died.lua`'s header cites the registration at "Module.lua:577"**, now at
  `:802-805`; the file is behavior-pinned through the dispatch seam only (see M1).

## (c) Changed behaviour with no test (run-tests has not seen any of this)

1. **MT-1 registration shape**: no test asserts the event-frame registration at all
   (`IsEventRegistered` grep = 0 in `Forte_Timer/tests`); the multi-unit `player,pet` /
   `player,target` form — the commit's headline fix — is unpinned. Drive
   `M._eventFrame:IsEventRegistered(...)` legs.
2. **MT-2 `UNIT_DIED` registration** (M1): a `IsEventRegistered("UNIT_DIED")` pin (with the
   base-event registration) is the only test that can fail the "feature lost in the field"
   shape.
3. **MT-3 self-target sweep gate** (`tokenHoldsRowUnit`, Reconcile.lua:250): no test
   targets-then-self-targets with a target row and asserts the row rides on.
4. **MT-4 `Casts.UNIQUE` retirement** (Casts.lua:587-593): recast-on-new-target retiring the
   old rows — no test.
5. **MT-5 Pump raise isolation** (Casts.lua:562-575, 659-666): no test injects a raising job
   (e.g. a poisoned `rows:InsertFromCast`) and asserts the rest of the queue runs, the queue
   heals, `raised` counts, the chat line is once-per-distinct.
6. **MT-6 aura adoption** (`findRowForUnit`/adopt, Reconcile.lua:288-301, 353-364): the "two
   Hunter's Mark bars" live case has no fixture asserting one row after a bulk sweep.
7. **MT-7 `Engine:AddExtras`**: tracked-set for a known-ids fixture / unknown-ids fixture, the
   count return, the sim-side no-op — nothing.
8. **MT-8 `shares`**: cast Arcane Shot → Summon Hawk entry started and vice versa, partner
   flag bounding — nothing (test_engine.lua knows neither).
9. **MT-9 render pump**: frame created once, `Display:Update` called from the pump, hidden bar
   cheap — nothing.
10. **MT-10 Timeline lanes**: two same-cd entries → perpendicular separation, axis `x`
    unchanged, lane reset per pass — nothing (test_timeline.lua predates `_lanes`).
11. **MT-11 title anchor**: `SetExpand` → title point TOP↔BOTTOM; Init with
    `expand=false` → above — nothing.
12. **MT-12 glow geometry**: the `64/34` sizes — nothing (visual, uiforever is its gate).
13. **MT-13 Options keyboard**: `SetAutoFocus(false)` pin, Enter→`ClearFocus`, window DIALOG
    strata, close clickability — nothing (Esc-restore legs pre-exist and pass).
14. **MT-14 Reminder**: IconName's first-known-aspect loop, `aspectTexture`'s id-first order,
    the question-mark fallback — nothing.
15. **MT-15 Probe window-open**: the bg/font fixes are real-client font behavior,
    un-pinnable in the sim — record as client-verified only; the epoch fix is tested (good).
16. **MT-16 `Log.lua`**: the whole file — no `test_log.lua`; the `LoggingChat()` raise (M3)
    and `/fx log test` are exactly what a stub-surface test catches.

## Open questions

- Live re-check needed: does `f:RegisterEvent("UNIT_DIED")` (base form) register on the
  shipped client without raising, and does the branch's `UnitExists("target")` answer
  survive the GUID payload? (Catalog says the event exists; only the client proves the
  registration form.)
- The replace-on-re-register `RegisterUnitEvent` semantics are a live observation, not
  catalog text — worth one probe run (register `player`, then `pet`, then fire) to record the
  shape in `docs/research`.
- Is the 60 Hz render pump budgeted against the `docs/perf.md` frame-time gates? Needs the
  one sim run to say.

## Counts

- **BLOCKER: 0**
- **MAJOR: 4** (M1 UNIT_DIED feature loss + green-dead tests; M2 AddExtras English keys /
  locale law; M3 `LoggingChat()` argless raise in `/fx log`; M4 top-level `RegisterEvent`
  law violation)
- **MINOR: 8** (m1 IGNORE-band adoption; m2 `ipairs` nil-hole; m3 unclamped lanes; m4
  hand-typed ids vs generator law; m5 `/fx log test` nil-call leg; m6 pump cadence drift +
  unpinned budget; m7 `raised` outside the init contract; m8 dead `SparkFlareFactor`)
- **INFO: 15** (verified-correct register of the checks above)
- **Changed behaviours with no test: 16** (MT-1 … MT-16)
- Files reviewed: 18/18. Catalog APIs verified: RegisterUnitEvent, PLAYER_ENTERING_WORLD,
  PLAYER_LOGIN, UNIT_DIED, LoggingChat/IsLoggingChat, geterrorhandler/seterrorhandler,
  UnitAffectingCombat, table.maxn, math.abs, SetAutoFocus, EnableMouse, RegisterForClicks,
  SetFrameStrata, SetFrameLevel, CreateTexture/SetAllPoints/SetColorTexture.

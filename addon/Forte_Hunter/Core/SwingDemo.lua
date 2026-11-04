-- addon/Forte_Hunter/Core/SwingDemo.lua
-- FX.Hunter.SwingDemo: the `/fx test` demo pilot of the SWING BAR
-- (Forte_Core/Core/TestMode.lua, PLAN §11.4 row K2). While test mode runs on
-- a Hunter, the bar plays a looping synthetic Auto Shot cycle -- 2.8 s cycle,
-- 0.5 s aim window, and a fake Aimed Shot cast every third cycle so the clip
-- mark retargets and the cast interlock shows -- and the owner can walk the
-- real layout (docs/hunter-tools.md, docs/research/wst-swing-design.md) with
-- no fight, no target and no bow.
--
-- HOW IT DRIVES THE REAL BAR WITHOUT TOUCHING THE REAL STATE. The bar
-- (FX.Hunter.Swing, UI/Swing.lua) renders `self.Tracker` through the public
-- injected-tracker seam `D:SetTracker`, and every number it draws arrives
-- from a SwingTracker. So the demo BUILDS ITS OWN SwingTracker (the real
-- constructor, the real event machine -- the phases, the aim slice, the
-- flight stamp, the interlock and the J4 markers are the SHIPPED code, run
-- by scripted events, not a re-implementation) and swaps it into the bar for
-- the length of the mode. `FX.Hunter.Tools.Swing` -- the player's real
-- tracker -- is never fed, never written, never even read past its identity:
-- the demo's events go to the demo's object. On Scrub (every TestMode exit:
-- the hand stop, the combat start, the logout, the disable) the real tracker
-- is put back; if a real cycle is running (the player shot between the
-- swaps) the bar picks it up, else it returns to the idle state.
--
-- THE BEAT. A cycle is 2.8 s; the TestMode pump is 1 Hz, too coarse to keep
-- the cycle alive, so the demo rides its OWN `C_Timer` ticker (0.2 s), built
-- on the FX7c law of the pump: a DEMO-lifetime resource, armed at the Fill,
-- cancelled at every exit, never armed from the enable. It registers no
-- event, no OnUpdate (the hidden-frame law) and writes no settings, and it
-- prints nothing: `FX.Print` is never named in this file. The ticker callback
-- self-scrubs if the mode is no longer running, so a Stop that somehow missed
-- the Scrub leaves no beat behind.
--
-- THE CLASS GATE. Test Mode is a layout pass for the class you play: the
-- Fill answers 0 (no rows, no swap, no ticker) for every non-Hunter, and the
-- bar must be Init'ed (its frames built) for a swap to mean anything. The
-- Hunter-only enable idiom of this add-on (Core/Tools.lua's gate) is the
-- model; the token read is `FX._playerClass`, Core's cached class file.
ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
FX.Hunter = FX.Hunter or {}

local M = {}
FX.Hunter.SwingDemo = M

-- THE VISIBILITY LAW (the flake post-mortem, 2026-11-04): the beat plan is
-- CYCLE-RELATIVE stamps, and the drive walks that plan -- the demo clock
-- derives its cycle phase from the plan, so EVERY window (the aim window,
-- the fire window, the cast pair) contains stamps BY CONSTRUCTION and no
-- grid-phase can starve a phase. The earlier design drove a FIXED grid
-- (base + 0.2k) and let the cycle phase fall where the arming clock dropped
-- it: the post-mortem measured it (in-process AIMSEQ 19/20 -- the 1 miss the
-- cast cycle, by design -- and a 1-cycle phase offset drops the fixed grid
-- entirely out of the 0.5 s aim window [2.0, 2.5] at base + 2.7). The
-- phase-free stamps mirror the real event spine: a fresh swing, the aim
-- START at 2.0 (the tracker's `ev` window runs to 2.5), the fire at 2.55,
-- the Aimed Shot's pair on every third cycle, and the cycle's tail (the
-- re-arm beat -- what the live client gets from the next swing's
-- PLAYER_SWING). The cycle. 2.8 s cycle, 0.5 s aim window (AIM_SECONDS *
-- cycle / base, the file-header law of Core/Tools.lua's AIM_SECONDS), the
-- Aimed Shot the J4 clip-mark carrier at the shipped 2.0 s cast (the live
-- check of 2026-11-03: a 2.0 s cast on a 2.8 s cycle "never fits" is the
-- honest read the bar shows).
local CYCLE_SECONDS = 2.8
local AIM_SECONDS = 0.5            -- documentary: the tracker pins it per cycle
local CAST_SECONDS = 2.0           -- the fake Aimed Shot's cast length
local CAST_EVERY = 3               -- the interlock rides every third cycle
local BEAT_SECONDS = 0.2           -- the live-client ticker's rate

--- The cycle-rel stamp set of one cycle: the event spine's stamps plus the
--- aim-window centre, the reload witness (rendered BEFORE the aim stamp's
--- own events fire -- the pre-aim instant, the reload span by construction)
--- and the cycle tail. `cast` marks the Aimed Shot's pair (every third
--- cycle, `CAST_EVERY`).
local function stampsFor(index)
    -- The stamp geometry rides the SHIPPED phase law (Core/Tools.lua
    -- CycleState): a stamped aim window reads `aim` at
    -- `remaining <= floor` -- the cycle's last AIM_SECONDS, stamps riding
    -- 0.01 INSIDE the bound for float headroom -- and the proven flight
    -- outranks it from its stamp on. The reload witness rides 0.1: the 0.0
    -- swing stamp CLEARED the prior cycle's flight and aim record
    -- (OnSwingStart's fresh-cycle law), so at 0.1 the phase is the reload
    -- span by construction; the aim START opens its window at 2.31 (the
    -- floor, headroom in), the aim centre 2.39, the fire 2.7 (the tail at
    -- 2.8 samples the proven flight), and the cycle tail -- a pure grid
    -- advance: the auto-repeat gates ride the MODE's length (the Fill's
    -- OnAutoRepeatStart opens them), exactly as on the client where the
    -- shot's SUCCEEDED and the fresh PLAYER_SWING are the only closures.
    local s = { { 0.0, "swing" }, { 0.1, "reloadWitness" },
        { 2.31, "aimStart" }, { 2.39, "aimMid" }, { 2.7, "fire" },
        { 2.8, "tail" } }
    if (index % CAST_EVERY) == 1 then
        s[#s + 1] = { 0.6, "castSent" }
        s[#s + 1] = { 2.6, "castDone" }
    end
    return s
end

--- The drive schedule over [from, to]: every cycle's planned stamps,
--- absolute, ascending. A drive that walks THIS walks the plan, so every
--- window is sampled by construction at any base phase.
local function beatPlan(from, to)
    local out = {}
    local cycleStart = from
    local index = 1
    while cycleStart <= to + 1e-9 do
        for _, s in ipairs(stampsFor(index)) do
            local t = cycleStart + s[1]
            if t >= from - 1e-9 and t <= to + 1e-9 then
                out[#out + 1] = { t = t, ev = s[2], cycle = cycleStart,
                    index = index }
            end
        end
        cycleStart = cycleStart + CYCLE_SECONDS
        index = index + 1
    end
    table.sort(out, function(a, b) return a.t < b.t end)
    return out
end
M.beatPlan = beatPlan           -- the test drive walks the SAME plan the demo clocks

local function byAt(a, b) return a.at < b.at end

--- The scripted events of one cycle, chronological, stamped absolute off
--- `startAt`, per the planned stamp set (`stampsFor`). The Auto Shot's
--- START/SUCCEEDED pair is the event-proven aim phase and the proven
--- flight; the START leg also OPENS THE FULL AIM_SECONDS-WIDE `ev` WINDOW
--- (the visibility law: a 0.5 s window, wider than the 0.2 s beat grid, so
--- every non-interlock cycle carries the aim phase; a gate-shut beat --
--- not-ready -- drops it exactly as a real aim attempt ends, and the
--- demo's readers stand ready, so the window lives its whole width). The
--- Aimed Shot's pair is the cast interlock (the SENT-opens-the-interlock
--- law). `id` is nil everywhere: the demo's cast length arrives through the
--- tracker's injected `castLenReader`, never a hand-typed spell id.
local function buildMarks(tracker, startAt, index)
    local marks = {}
    local function add(rel, fn)
        marks[#marks + 1] = { at = startAt + rel, fn = fn, rel = rel }
    end
    for _, s in ipairs(stampsFor(index)) do
        local rel, kind = s[1], s[2]
        if kind == "reloadWitness" then
            -- A render instant, not an event: the pre-aim phase witness.
        elseif kind == "swing" then
            add(rel, function() tracker:OnSwingStart(CYCLE_SECONDS,
                tracker.rangedType) end)
        elseif kind == "aimStart" then
            local seal = "FXDEMO-A" .. index
            add(rel, function()
                tracker:OnShotCast("START", "Auto Shot", nil, seal)
                local at = tracker.at
                if at then
                    at.startAt = startAt + rel
                    at.endAt = startAt + rel + AIM_SECONDS
                end
            end)
        elseif kind == "fire" then
            local seal = "FXDEMO-A" .. index
            add(rel, function()
                tracker:OnShotCast("SUCCEEDED", "Auto Shot", nil, seal)
            end)
        elseif kind == "castSent" then
            local seal = "FXDEMO-C" .. index
            add(rel, function()
                tracker:OnShotCast("SENT", "Aimed Shot", nil, seal)
            end)
        elseif kind == "castDone" then
            local seal = "FXDEMO-C" .. index
            add(rel, function()
                tracker:OnShotCast("SUCCEEDED", "Aimed Shot", nil, seal)
            end)
        end
    end
    table.sort(marks, byAt)
    return marks
end

--- The demo tracker: the REAL SwingTracker constructor with every
--- unit/cooldown read replaced by a fixed answer (the same injected-seam
--- shape tests/test_swing2.lua and test_swing3.lua drive): a target stands
--- there, the player stands still, the bow runs at `CYCLE_SECONDS`, the
--- cast-time shots run `CAST_SECONDS`, and the range edge carries no
--- knowledge (the permissive nil). The clock rides `M._clock`, which the
--- beat sets -- so a test drives time through `Beat` and the live client
--- rides GetTime through the ticker.
local function newDemoTracker()
    return FX.Hunter.NewSwingTracker({
        now = function() return M._clock end,
        speedReader = function() return CYCLE_SECONDS end,
        baseSpeed = CYCLE_SECONDS,
        targetReader = function() return true end,
        deadReader = function() return false end,
        attackReader = function() return true end,
        speedSampler = function() return 0 end,
        rangeReader = nil,
        castLenReader = function() return CAST_SECONDS end,
    })
end

--- One beat of the scripted cycle. The stamps of the plan (`stampsFor`):
--- the 0.0 stamp is the cycle's swing start -- the cycle ADOPTS the stamp
--- grid, so a drive walking `beatPlan` owns the clock and the phase (the
--- visibility law); the cycle-tail stamp re-arms the cycle (the next
--- swing's PLAYER_SWING leg, fired AFTER the shots of the cycle it
--- closes); the rest are the scripted events. Public: the ticker calls it,
--- and a test drives it directly (the C_Timer ticker does not fire
--- headless).
function M:Beat(now)
    if not self._on then return end
    if FX.TestMode and not FX.TestMode:IsActive() then
        self:Scrub()                                  -- the exit belt
        return
    end
    local tracker, UI = self._tracker, FX.Hunter.Swing
    if not tracker or not UI then self:Scrub() return end
    now = now or GetTime()
    -- The drive-clock law (the flake post-mortem): a Beat whose clock moves
    -- BACKWARD (a real-time ticker beat landing between test statements,
    -- sampled on the live `GetTime`) is dropped -- the demo's clock only
    -- runs forward, so a live-client beat can never perturb a driven cycle.
    if self._clock and now < self._clock - 1e-6 then return end
    self._clock = now
    -- THE PHASE LOCK (the visibility law): the drive carries the demo's OWN
    -- cycle grid (its stamps are cycle-relatives laid off `now`), and the
    -- demo's cycle SNAPS TO THE STAMP: the stamp whose cycle-relative
    -- offset is nearest below `now` sets the cycle start. The phase is then
    -- a property of the drive -- every window carries its stamps by
    -- construction -- and the wall-clock instant of the Fill drops out of
    -- the picture entirely (the flake post-mortem: the arming base carries
    -- the process's GetTime, so a plan laid on wall clocks lands at a
    -- process-random phase -- MEASURED aim=0 in one process, aim=20 in
    -- another).
    local off = (now - self._start) % CYCLE_SECONDS
    local rel = off < 0 and off + CYCLE_SECONDS or off
    local target
    for _, s in ipairs(stampsFor(self._index)) do
        if s[1] <= rel + 1e-9 and (target == nil or s[1] > target) then
            target = s[1]
        end
    end
    target = target or 0
    if rel - target > 0.35 + 1e-9 then
        self._start = now - target
        self._marks = buildMarks(tracker, self._start, self._index)
        self._mi = 1
        tracker.start = self._start
        tracker.active = true
        pcall(tracker.OnSwingStart, tracker, CYCLE_SECONDS, tracker.rangedType)
        tracker.start = self._start
        tracker.active = true
    elseif rel - target > 1e-9 then
        self._marks = buildMarks(tracker, self._start, self._index)
        self._mi = 1
    end
    local fired = 0
    local marks = self._marks
    while self._mi <= #marks and marks[self._mi].at <= now do
        local m = marks[self._mi]
        if m.rel == 0.0 then
            -- The cycle's start leg: the fresh swing (the PLAYER_SWING
            -- spine leg). The cycle clock stamps from the GRID (the phase
            -- lock's grid IS the time law), not the demo clock -- the two
            -- ride together, and the windows (the aim floor, the flight)
            -- land where the plan put them.
            tracker.start = m.at
            pcall(tracker.OnSwingStart, tracker, CYCLE_SECONDS,
                tracker.rangedType)              -- the cycle's own start
            tracker.start = m.at
            tracker.active = true
        elseif m.rel >= CYCLE_SECONDS then
            -- The cycle tail: a pure grid advance (the next cycle's 0.0
            -- stamp fires the fresh swing). The auto-repeat gates ride the
            -- mode's length, as on the client.
            self._start = self._start + CYCLE_SECONDS
            self._index = self._index + 1
            self._marks = buildMarks(tracker, self._start, self._index)
        elseif m.fn then
            pcall(m.fn)                          -- one leg is never a crash path
        end
        self._mi = self._mi + 1
        fired = fired + 1
    end
    if fired > 0 then UI:Kick() end
end

--- Fill (TestMode contract): swap the demo tracker in, arm the cycle and
--- the beat. Idempotent: a Refill while the demo runs is a no-op (the beat
--- keeps the cycle alive; there is nothing to top up).
function M:Fill(now)
    if self._on then return 1 end
    if FX._playerClass ~= "HUNTER" then return 0 end
    local UI = FX.Hunter.Swing
    if not UI or type(UI.SetTracker) ~= "function" then return 0 end
    if not UI.anchor then return 0 end               -- the bar is not built
    local real = FX.Hunter.Tools and FX.Hunter.Tools.Swing
    if not (real and FX.Hunter.NewSwingTracker) then return 0 end
    now = now or GetTime()
    self._clock = now
    local tracker = newDemoTracker()
    tracker:OnAutoRepeatStart()                      -- shooting: the readiness gate opens
    self._real = real
    self._tracker = tracker
    self._start = now
    self._index = 1
    self._marks = buildMarks(tracker, now, 1)
    self._mi = 2                                   -- skip the 0.0 swing stamp
    UI:SetTracker(tracker)                           -- the public seam; `real` rides in _real
    tracker:OnSwingStart(CYCLE_SECONDS, tracker.rangedType)
    self._on = true
    if C_Timer and C_Timer.NewTicker then
        local ok, ticker = pcall(C_Timer.NewTicker, BEAT_SECONDS, function()
            M:Beat(GetTime())
        end)
        if ok then self._ticker = ticker end         -- a raise leaves no handle (the pump law)
    end
    UI:Kick()
    return 1
end

--- Scrub (TestMode contract): stop the beat, put the real tracker back on
--- the bar, and leave the bar where the real state says it belongs (a live
--- real cycle resumes its ticker; an idle tracker returns the bar to its
--- idle state). Answers the number of demo rows removed (the bar is one).
function M:Scrub()
    if not self._on then return 0 end
    self._on = nil
    if self._ticker and self._ticker.Cancel then
        pcall(self._ticker.Cancel, self._ticker)
    end
    self._ticker = nil
    local UI = FX.Hunter.Swing
    if UI and self._real then
        UI:SetTracker(self._real)
        if self._real.active then UI:Kick() else UI:RenderIdle() end
    end
    self._tracker, self._real = nil, nil
    self._marks, self._mi, self._start, self._index = nil, nil, nil, nil
    return 1
end

--- Live (TestMode contract): the demo bar is one synthetic row.
function M:Live()
    return self._on and 1 or 0
end

--- The module: the feeder registration rides the enable (the idiom of the
--- fed frames), idempotent by name, and the disable scrubs as the belt (the
--- mode itself stops at its own exits, running this Scrub through the
--- feeder). No events, no pump, no print at the enable.
function M:OnEnable()
    if FX.TestMode then
        FX.TestMode.RegisterFeeder({ Name = "HunterSwing",
            Fill = function(now) return self:Fill(now) end,
            Scrub = function() return self:Scrub() end,
            Live = function() return self:Live() end })
    end
end

function M:OnDisable()
    self:Scrub()
end

FX.RegisterModule("HunterSwingDemo", M)

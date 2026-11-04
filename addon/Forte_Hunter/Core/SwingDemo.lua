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

-- The demo cycle. A hasted-feeling 2.8 s Auto Shot cycle whose aim window is
-- AIM_SECONDS * cycle / base = 0.5 s exactly (the tracker derives the window
-- from the pair, the file-header law of Core/Tools.lua's AIM_SECONDS), the
-- Aimed Shot the J4 clip-mark carrier at the shipped 2.0 s cast (the live
-- check of 2026-11-03: a 2.0 s cast on a 2.8 s cycle "never fits" is the
-- honest read the bar shows, and the interlock is what the owner is here to
-- see). Stamps are cycle-relative; the beat fires them when due.
local CYCLE_SECONDS = 2.8
local AIM_SECONDS = 0.5            -- documentary: the tracker pins it per cycle
local CAST_SECONDS = 2.0           -- the fake Aimed Shot's cast length
local CAST_EVERY = 3               -- the interlock rides every third cycle
local CAST_SENT_AT = 0.6           -- SENT: the interlock opens, the clip mark retargets
local AIM_AT = CYCLE_SECONDS - AIM_SECONDS  -- the Auto Shot's aim window opens
-- SUCCEEDED leaves the beat grid a window of `REARM_GRACE + 0.05` (here
-- 0.35 s) before the re-arm: wider than the 0.2 s beat, so the proven
-- flight ALWAYS lands between two beats (a flight stamped in the same
-- beat the cycle re-arms is wiped by the fresh PLAYER_SWING and the white
-- phase would skip that cycle). Real play carries this too: the shot
-- leaves ~0.25 s before the next swing's event (the fire->swing gap).
local FIRE_AT = CYCLE_SECONDS - 0.25        -- SUCCEEDED: the projectile leaves
local CAST_DONE_AT = CAST_SENT_AT + CAST_SECONDS
local REARM_GRACE = 0.05
local BEAT_SECONDS = 0.2

local function byAt(a, b) return a.at < b.at end

--- The scripted events of one cycle, chronological, stamped absolute off
--- `startAt`. The Auto Shot's START/SUCCEEDED pair is the event-proven aim
--- phase and the proven flight; the Aimed Shot's pair is the cast interlock
--- (the SENT-opens-the-interlock law: Forever's cast-time shots reach the
--- tracker the same way the real event spine feeds it, Core/Tools.lua).
--- `id` is nil everywhere: the demo's cast length arrives through the
--- tracker's injected `castLenReader`, never a hand-typed spell id.
local function buildMarks(tracker, startAt, index)
    local marks = {}
    local function add(rel, fn)
        marks[#marks + 1] = { at = startAt + rel, fn = fn }
    end
    if (index % CAST_EVERY) == 1 then
        local seal = "FXDEMO-C" .. index
        add(CAST_SENT_AT, function()
            tracker:OnShotCast("SENT", "Aimed Shot", nil, seal)
        end)
        add(CAST_DONE_AT, function()
            tracker:OnShotCast("SUCCEEDED", "Aimed Shot", nil, seal)
        end)
    end
    local sealA = "FXDEMO-A" .. index
    add(AIM_AT, function()
        tracker:OnShotCast("START", "Auto Shot", nil, sealA)
    end)
    add(FIRE_AT, function()
        tracker:OnShotCast("SUCCEEDED", "Auto Shot", nil, sealA)
    end)
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

--- One beat of the scripted cycle: fire every event that is due, re-arm the
--- cycle as it completes (the PLAYER_SWING leg of the next shot, catching a
--- starved ticker up by whole cycles). Public: the ticker calls it, and a
--- test drives it directly (the C_Timer ticker does not fire headless).
function M:Beat(now)
    if not self._on then return end
    if FX.TestMode and not FX.TestMode:IsActive() then
        self:Scrub()                                  -- the exit belt
        return
    end
    local tracker, UI = self._tracker, FX.Hunter.Swing
    if not tracker or not UI then self:Scrub() return end
    now = now or GetTime()
    self._clock = now
    local elapsed = now - self._start
    if elapsed >= CYCLE_SECONDS then
        local skip = math.floor(elapsed / CYCLE_SECONDS)
        self._start = self._start + skip * CYCLE_SECONDS
        self._index = self._index + skip
        self._marks = buildMarks(tracker, self._start, self._index)
        self._mi = 1
        tracker:OnSwingStart(CYCLE_SECONDS, tracker.rangedType)
        UI:Kick()
        elapsed = now - self._start
    end
    local fired = 0
    local marks = self._marks
    while self._mi <= #marks and marks[self._mi].at <= now do
        pcall(marks[self._mi].fn)                     -- one leg is never a crash path
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
    self._mi = 1
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

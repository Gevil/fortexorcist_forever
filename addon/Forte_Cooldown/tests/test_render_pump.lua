-- addon/Forte_Cooldown/tests/test_render_pump.lua
-- PLAN §11.13 (Iteration S, S1): MOTION FOLLOWS THE FRAME, LOGIC DOES NOT.
--
-- History: Code-review-10 m6 + section (c) MT-9 pinned the OLD pump -- an
-- OnUpdate that fed the WHOLE `Display:Update` through a 1/60 s accumulator
-- (`RENDER_SECONDS`, remainder carried). At 165 fps that gate fires on an
-- uneven 3-3-2 frame pattern (judder) and paid the full pass every time. The
-- accumulator is gone; the law it pinned is replaced by this one:
--
--   * the render frame (`M._renderFrame`) is created once by the enable and
--     carries NO script by default;
--   * it carries an OnUpdate ONLY while the bar is shown AND something
--     animates (the Display tells the Module through `M:SetMotion` at the end
--     of every full pass; the script also removes itself the frame nothing
--     animates any more), or while ONE full pass is requested;
--   * the script is the MOTION pass: exactly one `Display:Motion(GetTime())`
--     per rendered frame -- no accumulator, no cadence gate, the time base is
--     the clock read once per frame, never a summed `elapsed`;
--   * the FULL pass (`Display:Update`: sort, grouping, text, visibility)
--     rides the 10 Hz heartbeat body `M:Tick`, and ONE extra pass is
--     requested for the next rendered frame when the Engine's entry set
--     changes outside the beat (an event, a debounced read, a rescan, the
--     test-mode fill): a dirty flag consumed by that one frame, however many
--     changes landed in it -- an idle bar still has no script;
--   * a row parked beyond Max that crosses into the curve is armed from its
--     cached crossing time (a one-shot timer -> a requested pass).
--
-- The geometry of the motion pass itself is pinned in test_zzc_motion.lua; this
-- file pins the PUMP: who owns the script, when it exists, how often each
-- pass runs. The Display is stubbed by SWAPPING FX.Cooldown.Display (the
-- Module reads the field at call time) and restored on every path.

local FX = ForteXorcist
local M = FX.Cooldown.Module
local Engine = FX.Cooldown.Engine

local function enableModule()
    if not M._eventFrame then M:OnEnable() end
    return M
end

--- Start a leg from a drained pump (earlier suite files dispatch events that
--- legitimately leave a request pending).
local function resetPump()
    local p = M._pump
    p.dirty, p.wanted, p.armedAt = false, false, nil
    M:SyncPump()
end

--- The global clock stub: the pump reads GetTime() once per frame.
local clock = 0
local function withClock(body)
    local saved = _G.GetTime
    _G.GetTime = function() return clock end
    local ok, err = pcall(body)
    _G.GetTime = saved
    if not ok then error(err, 0) end
end

--- Swap in a counting Display stub whose Motion answers `motionAnswer`
--- (true = still animating). restore ALWAYS runs (a failed leg must not
--- strand the stub for the files that sort after this one -- that leak once
--- killed every Display leg in the suite).
local function withStub(motionAnswer, body)
    local real = FX.Cooldown.Display
    local realReadAll = M.ReadAll
    local stub = { motion = 0, updates = 0, lastNow = nil }
    FX.Cooldown.Display = {
        Motion = function(_, now)
            stub.motion = stub.motion + 1
            stub.lastNow = now
            return motionAnswer
        end,
        Update = function() stub.updates = stub.updates + 1 end,
    }
    M.ReadAll = function() end          -- the 1 Hz net is not under test here
    for name in pairs(Engine.entries) do Engine.entries[name] = nil end
    resetPump()
    local ok, err = pcall(body, stub)
    FX.Cooldown.Display = real
    M.ReadAll = realReadAll
    for name in pairs(Engine.entries) do Engine.entries[name] = nil end
    resetPump()                         -- never leak a stub-driven script
    if not ok then error(err, 0) end
end

test("S1: the enable creates the render frame exactly once, with no script while idle",
function()
    enableModule()
    assertNotNil(M._renderFrame, "the render frame rides the enable")
    local f = M._renderFrame
    M:OnEnable()                                -- the idempotence leg
    assertEquals(f, M._renderFrame,
        "a second enable creates NO second frame (the `if not M._renderFrame`"
        .. " gate; the module has no disable path)")
    assertNil(M._renderAcc, "the accumulator box is gone with the 60 Hz gate")
    -- An empty feed through the real Display: nothing animates, so the frame
    -- carries no script (idle = zero per-frame Lua).
    resetPump()
    FX.Cooldown.Display:Init()
    FX.Cooldown.Display:Update({}, GetTime())
    assertNil(f:GetScript("OnUpdate"), "idle bar: no OnUpdate on the render frame")
end)

test("S1: SetMotion installs and removes the one script, idempotently",
function()
    enableModule()
    resetPump()
    local f = M._renderFrame
    M:SetMotion(true)
    local first = f:GetScript("OnUpdate")
    assertNotNil(first, "SetMotion(true) installs the pump")
    M:SetMotion(true)
    assertEquals(first, f:GetScript("OnUpdate"), "a second install is a no-op")
    M:SetMotion(false)
    assertNil(f:GetScript("OnUpdate"), "SetMotion(false) removes it")
    M:SetMotion(false)                          -- idempotent
    assertNil(f:GetScript("OnUpdate"))
end)

test("S1: one Display:Motion per rendered frame at ANY frame rate, on the GetTime clock",
function()
    enableModule()
    withStub(true, function(stub)
        withClock(function()
            M:SetMotion(true)
            local f = M._renderFrame
            local pump = f:GetScript("OnUpdate")
            for _, fps in ipairs({ 30, 60, 165, 240 }) do
                stub.motion = 0
                clock = 1000
                for i = 1, fps do                     -- one second of frames
                    clock = 1000 + i / fps
                    pump(f, 1 / fps)
                end
                assertEquals(fps, stub.motion,
                    "every rendered frame runs the motion pass exactly once at "
                    .. fps .. " fps (no 1/60 gate, no 3-3-2 pattern)")
            end
            -- The time base is the clock read ONCE per frame, never the
            -- summed `elapsed`: a frame that claims elapsed = 99 (a hitch)
            -- or garbage still hands the pass the current GetTime.
            clock = 2000
            pump(f, 99)
            assertEquals(2000, stub.lastNow, "the pass gets GetTime(), not an accumulated elapsed")
            clock = 2000.004
            pump(f, "ten")
            pump(f, nil)
            assertEquals(2000.004, stub.lastNow)
        end)
    end)
end)

test("S1: the script removes itself the frame nothing animates any more",
function()
    enableModule()
    withStub(false, function(stub)
        M:SetMotion(true)
        local f = M._renderFrame
        local pump = f:GetScript("OnUpdate")
        pump(f, 1 / 165)
        assertEquals(1, stub.motion)
        assertNil(f:GetScript("OnUpdate"),
            "Motion answered false: the render frame carries no script any more")
    end)
end)

test("S1: the pump is safe with no Display (the guard)",
function()
    enableModule()
    resetPump()
    local real = FX.Cooldown.Display
    M:SetMotion(true)
    local f = M._renderFrame
    FX.Cooldown.Display = nil
    local ok = pcall(f:GetScript("OnUpdate"), f, 1 / 165)
    FX.Cooldown.Display = real
    assertTrue(ok, "a missing Display costs the pass, not the frame")
    assertNil(f:GetScript("OnUpdate"), "and the script leaves")
    resetPump()
end)

test("S1: the FULL pass rides the 10 Hz heartbeat body, never the frame stream",
function()
    enableModule()
    withStub(true, function(stub)
        withClock(function()
            M:SetMotion(true)
            local f = M._renderFrame
            local pump = f:GetScript("OnUpdate")
            -- 600 rendered frames (3.6 s at 165 fps): no full pass at all.
            for i = 1, 600 do
                clock = 3000 + i / 165
                pump(f, 1 / 165)
            end
            assertEquals(600, stub.motion)
            assertEquals(0, stub.updates,
                "the frame stream never runs Display:Update (the old 60 Hz pump did, every 3rd frame)")
            -- One simulated second of heartbeats: ten bodies, ten full passes.
            for i = 1, 10 do
                M:Tick(3010 + i * 0.1)
            end
            assertEquals(10, stub.updates,
                "the heartbeat body runs the full pass once per beat (10 Hz)")
        end)
    end)
end)

-- ------------------------------------------- the set-change request (S1.2) --

--- Adopt an entry the way a real event does: through the Module's own event
--- script. The WEAPON_ENCHANT_CHANGED branch calls Engine.Enchants:ReadAll(),
--- so the leg swaps that one reader for a body that adopts `names` (the
--- engine's own OnCast insert path) and restores it on every path.
local function withAdopter(names, body)
    local E = Engine.Enchants
    local real = E and E.ReadAll
    for _, name in ipairs(names) do
        Engine.tracked[name] = { name = name, dataId = 1, baseDuration = 60 }
    end
    local pending = {}
    for i, name in ipairs(names) do pending[i] = name end
    E.ReadAll = function()
        local name = table.remove(pending, 1)
        if name then Engine:OnCast(name, GetTime()) end
    end
    local ok, err = pcall(body)
    E.ReadAll = real
    for _, name in ipairs(names) do Engine.tracked[name] = nil end
    if not ok then error(err, 0) end
end

local function fireEnchantEvent()
    local f = M._eventFrame
    f:GetScript("OnEvent")(f, "WEAPON_ENCHANT_CHANGED")
end

test("S1.2: an entry adopted between beats gets ONE full pass on the next rendered frame; the idle bar has no script before and after",
function()
    enableModule()
    withStub(false, function(stub)
        withClock(function()
            clock = 4000
            local f = M._renderFrame
            assertNil(f:GetScript("OnUpdate"), "idle before")
            withAdopter({ "PumpAdopt1" }, function()
                fireEnchantEvent()                   -- adopts one entry, no beat
                assertEquals(0, stub.updates, "the event itself runs no pass")
                local pump = f:GetScript("OnUpdate")
                assertNotNil(pump, "a request installs the one-shot")
                pump(f, 1 / 165)                      -- the next rendered frame
                assertEquals(1, stub.updates, "exactly one full pass on that frame")
                assertNil(f:GetScript("OnUpdate"),
                    "nothing animates (stub Display): the one-shot is gone again")
            end)
        end)
    end)
end)

test("S1.2: 20 adoptions inside one frame cost ONE full pass",
function()
    enableModule()
    withStub(false, function(stub)
        withClock(function()
            clock = 4100
            local names = {}
            for i = 1, 20 do names[i] = "PumpBurst" .. i end
            withAdopter(names, function()
                for _ = 1, 20 do fireEnchantEvent() end
                assertEquals(0, stub.updates)
                local f = M._renderFrame
                local pump = f:GetScript("OnUpdate")
                assertNotNil(pump)
                pump(f, 1 / 165)
                assertEquals(1, stub.updates, "a burst is one flag, one pass")
                assertNil(f:GetScript("OnUpdate"))
                local n = 0
                for _ in pairs(Engine.entries) do n = n + 1 end
                assertEquals(20, n, "all twenty were adopted")
            end)
        end)
    end)
end)

test("S1.2: an event that changes nothing requests nothing (the idle bar stays script-free)",
function()
    enableModule()
    withStub(false, function(stub)
        withClock(function()
            clock = 4200
            local f = M._renderFrame
            local E = Engine.Enchants
            local real = E.ReadAll
            E.ReadAll = function() end
            local ok, err = pcall(fireEnchantEvent)
            E.ReadAll = real
            assertTrue(ok, tostring(err))
            assertNil(f:GetScript("OnUpdate"), "no change, no request, no script")
            assertEquals(0, stub.updates)
        end)
    end)
end)

test("S1.2: a re-anchored end time (same set) also asks for a pass; the beat satisfies a pending request",
function()
    enableModule()
    withStub(false, function(stub)
        withClock(function()
            clock = 4300
            Engine.tracked["PumpAnchor"] = { name = "PumpAnchor", dataId = 1, baseDuration = 60 }
            Engine:OnCast("PumpAnchor", 4300)
            local E = Engine.Enchants
            local real = E.ReadAll
            E.ReadAll = function() Engine.entries["PumpAnchor"].endTime = 4300 + 55 end
            local ok, err = pcall(fireEnchantEvent)
            E.ReadAll = real
            assertTrue(ok, tostring(err))
            local f = M._renderFrame
            assertNotNil(f:GetScript("OnUpdate"), "a moved end time is an entry change")
            -- The 10 Hz beat runs the pass first: the request is consumed.
            M:Tick(4300.05)
            assertEquals(1, stub.updates)
            assertFalse(M._pump.dirty, "the beat's pass satisfied the request")
            assertNil(f:GetScript("OnUpdate"), "and the one-shot is gone without running")
            Engine.tracked["PumpAnchor"] = nil
        end)
    end)
end)

test("S1.2: a row parked beyond Max arms ONE crossing timer; its fire requests a pass",
function()
    enableModule()
    withStub(false, function()
        withClock(function()
            local timers = {}
            local savedAfter = C_Timer.After
            C_Timer.After = function(delay, fn) timers[#timers + 1] = { delay, fn } end
            local ok, err = pcall(function()
                clock = 5000
                M:ArmCrossing(5050)
                assertEquals(1, #timers, "one timer armed")
                assertTrue(math.abs(timers[1][1] - 50) < 1e-9, "for the crossing moment")
                M:ArmCrossing(5050)
                assertEquals(1, #timers, "the same moment is not armed twice (every beat re-reports it)")
                M:ArmCrossing(5040)
                assertEquals(2, #timers, "an EARLIER crossing arms its own timer")
                local f = M._renderFrame
                assertNil(f:GetScript("OnUpdate"), "arming installs nothing")
                timers[2][2]()                        -- the timer fires
                assertTrue(M._pump.dirty)
                assertNotNil(f:GetScript("OnUpdate"), "the fire requests a pass on the next frame")
            end)
            C_Timer.After = savedAfter
            if not ok then error(err, 0) end
        end)
    end)
end)

-- addon/Forte_Cooldown/tests/test_render_pump.lua
-- Code-review-10 m6 + section (c) MT-9: the 60 Hz render pump of
-- Module.lua's OnEnable d490e2e added, with NO test of its existence, its
-- cadence, or its `Display:Update` call rate ("the main verification gap" of
-- the review). What this suite pins:
--
--   * the pump frame exists after the enable, and the enable is idempotent
--     (the `if not M._renderFrame` gate: a second OnEnable adds NO frame);
--   * the frame is created INSIDE the enable (a module-scoped lifecycle
--     object, not a load-time one) -- the leg: the enable path is the only
--     way here, and the frame rides the module;
--   * the cadence gate: an OnUpdate whose elapsed sum sits under
--     RENDER_SECONDS draws NOTHING; crossing it draws exactly once;
--   * m6, the remainder carry: the old `acc = 0` threw the overage away, so a
--     ~100 Hz frame stream (elapsed 0.010) realized a 50 Hz draw rate -- the
--     CHANGELOG's "60 Hz" was nominal. Carrying the remainder makes 600
--     frames of 10 ms realize ~360 draws (6.0 s of clock at 60 Hz), not 300;
--   * the pump survives a nil/absent Display field (the guard), and a hidden
--     bar (the Display's own UpdateVisibility gate) costs no slot work -- the
--     pump's cost while the bar is hidden is the pump call alone.
--
-- The Display is stubbed by SWAPPING FX.Cooldown.Display (the pump reads the
-- field at call time) and restored on every path; the module's own enable is
-- driven by hand (the gate run's login sequence does not reach Forte_Core's
-- module loop -- the established finding of Forte_Hunter/tests/test_swing.lua).

local FX = ForteXorcist
local M = FX.Cooldown.Module

local RENDER_SECONDS = 1 / 60

local function enableModule()
    if not M._eventFrame then M:OnEnable() end
    return M
end

--- Install a counting Display stub; returns (counter, restore).
---
--- The pump frame is SHOWN once the module is enabled, so the sim's own
--- frame stream delivers it OnUpdate calls with REAL elapsed values at the
--- frame boundaries between the scripted calls -- those ambient draws are
--- the test's noise floor (they put the cadence census at 1 where the
--- scripted pump alone gives 0). A hidden frame gets no OnUpdate, so the
--- stub legs hide the pump for their duration and drive the script handler
--- directly; restore shows it again. restore also runs on a failed leg
--- (see guarded), so neither the stub nor the hidden pump ever leaks into
--- a later test file.
local function installDisplayStub()
    local real = FX.Cooldown.Display
    local frame = M._renderFrame
    local wasShown = frame and frame:IsShown()
    if frame then frame:Hide() end
    M._renderAcc.v = 0           -- drained, known phase for the scripted leg
    local n = 0
    FX.Cooldown.Display = { Update = function() n = n + 1 end }
    return { n = function() return n end },
        function()
            FX.Cooldown.Display = real
            if frame and wasShown then frame:Show() end
        end
end

--- Run the scripted body; the restore ALWAYS runs (an assert that throws
--- must not strand the Display stub for the files that sort after this one
--- -- that leak is what once killed every Display leg in the suite).
local function guarded(body, restore)
    local ok, err = pcall(body)
    restore()
    if not ok then error(err, 0) end
end

test("MT-9: the enable creates the render pump exactly once",
function()
    enableModule()
    assertNotNil(M._renderFrame, "the pump frame rides the enable")
    local f = M._renderFrame
    M:OnEnable()                                -- the idempotence leg
    assertEquals(f, M._renderFrame,
        "a second enable creates NO second pump (the `if not M._renderFrame`"
        .. " gate; the module has no disable path -- Loader.lua has no"
        .. " OnDisable -- so this gate is the frame's whole lifecycle)")
    assertNotNil(f:GetScript("OnUpdate"), "the pump is the OnUpdate script")
end)

test("MT-9: the cadence gate -- under RENDER_SECONDS draws nothing, the crossing draws once",
function()
    enableModule()
    local stub, restore = installDisplayStub()
    guarded(function()
        local pump = M._renderFrame:GetScript("OnUpdate")
        local frame = M._renderFrame
        pump(frame, 0.005)
        pump(frame, 0.005)
        assertEquals(0, stub.n(),
            "two 5 ms frames (10 ms) sit under the 16.7 ms draw window")
        pump(frame, 0.010)                          -- 20 ms total: one draw
        assertEquals(1, stub.n(), "the crossing draws exactly once")
        pump(frame, 0.001)                          -- 4 ms: under again
        assertEquals(1, stub.n(), "and the next frame does not redraw")
    end, restore)
end)

test("m6: the remainder rides (the old `acc = 0` threw it away): a 10 ms frame stream realizes ~60 Hz, not 50",
function()
    enableModule()
    local stub, restore = installDisplayStub()
    guarded(function()
        local pump = M._renderFrame:GetScript("OnUpdate")
        local frame = M._renderFrame
        -- 600 frames of 10 ms = 6.0 s of clock. The carry realizes
        -- floor(6.0 / RENDER_SECONDS) = 360 draws; the throwing-away shape
        -- caps at 300 (a draw only when a fresh 10 ms frame crosses the
        -- window).
        for _ = 1, 600 do pump(frame, 0.010) end
        local draws = stub.n()
        print(string.format("[render-pump] 600 x 10 ms -> %d draws", draws))
        assertTrue(draws >= 355,
            "6.0 s of 10 ms frames draws >= 355x (the carry; the old shape stops"
            .. " at 300): got " .. draws)
        assertTrue(draws <= 365, "and the rate does not exceed the window: " .. draws)
    end, restore)
end)

test("MT-9: a non-number elapsed cannot run the pump backwards",
function()
    enableModule()
    local stub, restore = installDisplayStub()
    guarded(function()
        local pump = M._renderFrame:GetScript("OnUpdate")
        local frame = M._renderFrame
        pump(frame, nil)
        pump(frame, "ten")
        assertEquals(0, stub.n(), "nil/string elapsed contribute zero seconds")
        pump(frame, 1 / 60)
        assertEquals(1, stub.n(), "and the accumulator is not poisoned")
    end, restore)
end)

test("MT-9: the pump is safe with no Display (the guard) and the hidden-bar gate is the Display's own",
function()
    enableModule()
    local real = FX.Cooldown.Display
    local pumped = 0
    FX.Cooldown.Display = nil                    -- the nil-safe half
    local pump = M._renderFrame:GetScript("OnUpdate")
    local ok = pcall(pump, M._renderFrame, 1.0)  -- a whole second: the pump runs
    FX.Cooldown.Display = real
    assertTrue(ok, "a missing Display costs the draw, not the frame")
    -- The hidden-bar half: Display:Update on a hidden bar runs its
    -- UpdateVisibility gate and returns before any slot work (Timeline.lua's
    -- `if not self._shown` gate) -- the pump's per-frame cost while the bar
    -- is hidden is that gate. The gate's own census lives in
    -- tests/test_timeline.lua (UpdateVisibility); the pump rides it.
    assertNotNil(FX.Cooldown.Display)
end)

-- addon/Forte_Hunter/tests/test_swing_modes.lua
-- Iteration J slice A (docs/research/wst-swing-design.md §7.8, the eight
-- acceptance items of slice α) on the Hunter swing bar:
--   1. the `safe` mode -- and an UNSET mode -- reproduce today's shipped
--      numbers exactly (the v2 sequence of test_swing2.lua, verbatim: the
--      safe-window fill, the aim slice in phase `aim` only, the interlock's
--      full-width slice), so that file and test_swing.lua pass UNEDITED --
--      the baseline is a law, not a proposal;
--   2. the `one` mode's capped ramp (§7.2) and where the cap bites;
--   3. the `elapsed` mode = fraction x width, no slices;
--   4. the standing aim region (P2, §7.3): aimLen x scale the WHOLE cycle in
--      every mode, its alpha below the live slice's, hideable alone;
--   5. the clip stripe (P1, §7.4): (castLen + aimLen) x scale clamped to the
--      bar, castLen from the INJECTED data table, retargeted to the live
--      cast under the interlock, 0 when off;
--   6. the weave line (P4, §7.4): x = W - (aimLen + gcd) x scale, hidden
--      when that runs off the bar's left edge (the no-room law), hidden by
--      its own key, default off;
--   7. PARITY: one Auto Shot cycle through the "lua" and the "engine" fill
--      path yields the same _fillIntent sequence in EVERY mode (the
--      test_swing3.lua parity law, mode-parameterised);
--   8. StatusLine() names the mode, the aim-region alpha and the stripe's
--      width (the /fx status seam).
--
-- Every tracker is INJECTED (the test_swing2.lua clock + gate-reader shape)
-- and every number is read off the REAL frame scripts through the bar's real
-- Update path; `nearpx` is the 0.5-px law of that file (the sim round-trips
-- frame geometry through float32). Nothing here touches the tracker, the toc
-- or the options page (slice α is render-only), and every leg restores the
-- module's shipped state.

local FX = ForteXorcist
local Tools = FX.Hunter.Tools
local Swing = FX.Hunter.Swing
local S = FX.Hunter.SwingSkin
local ST = FX.Settings

local function nearpx(actual, expected)
    return assertTrue(math.abs(actual - expected) <= 0.5)
end
local function near3(actual, expected)
    return assertTrue(math.abs(actual - expected) < 1e-3)
end

-- The geometry-law suite law: the bar reads the DRAWN widths, so the fill
-- path is pinned to the v2 lua path (UI/Swing.lua's DEFAULT POSTURE); item 7
-- is what walks the engine path.
Swing:SetFillEngineMode("lua")
assertFalse(Swing:UsesEngineFill())

--- A permissive-gate tracker (test_swing2.lua's shape): the cycle tests want
--- the readiness gate OPEN so the aim phase runs.
local function v2Tracker(clock, extra)
    local opts = {
        now = function() return clock[1] end,
        speedReader = function() return nil end,
        rangedType = 2,
        targetReader = function() return true end,
        deadReader = function() return false end,
        attackReader = function() return true end,
        speedSampler = function() return nil end,
        rangeReader = function() return nil end,
        castLenReader = function() return nil end,
    }
    for k, v in pairs(extra or {}) do opts[k] = v end
    local t = FX.Hunter.NewSwingTracker(opts)
    t.shooting = true
    return t
end

--- The shipped state the file leaves behind: the safe mode, the γ.1 marker
--- defaults (aim window ON, clip region ON, weave line OFF), the lua fill,
--- the production tracker, an idle bar.
---
--- `Tools.DataCastMsByName` is a MODULE-table field: a plain write is not
--- covered by the sim's per-file AutoRestore (only `_G` writes and the
--- registered patch helpers are), so every data-table injection here is
--- paired with this restore — the clip stripe reads shipped data through
--- that function, and test_zz_combat_hunter.lua asserts its shipped
--- numbers (the "len=4" leak this law prevents).
local REAL_DATA_CAST_MS = FX.Hunter.Tools.DataCastMsByName
local injectedData = false
local function useData(map)
    FX.Hunter.Tools.DataCastMsByName = function() return map end
    injectedData = true
    Swing:InvalidateClipCastLength()
end
local function restoreBar()
    if injectedData then
        FX.Hunter.Tools.DataCastMsByName = REAL_DATA_CAST_MS
        injectedData = false
    end
    Swing:SetBarMode("safe")
    Swing:SetShowAimWindow(true)
    Swing:SetShowClipRegion(true)
    Swing:SetShowWeaveLine(false)
    Swing:SetFillEngineMode("lua")
    Swing:SetTracker(Tools.Swing)
    Swing:RenderIdle()
    Swing:InvalidateClipCastLength()
    Swing:FillLog(nil)
end

Swing:Init()                       -- idempotent; the frame + marker art
assertNotNil(Swing.anchor)
assertNotNil(Swing.aimRegion)      -- the standing aim region (P2)
assertNotNil(Swing.clip)           -- the clip stripe (P1)
assertNotNil(Swing.weave)          -- the weave line (P4)

local W = 200                      -- the shipped bar width (S.Width)
assertEquals(200, S.Width)
assertEquals(12, S.Height)

-- The module's shipped defaults, read BEFORE this file's first setter (the
-- §7.8 γ.1 posture: mode safe, aim window ON, clip region ON, weave line OFF).
local D_MODE = Swing.state.barMode
local D_AIM = Swing.state.showAimWindow
local D_CLIP = Swing.state.showClipRegion
local D_WEAVE = Swing.state.showWeaveLine

-- ================================================= 1. the safe-mode baseline ==

test("mode safe: the v2 sequence of test_swing2.lua, verbatim", function()
    Swing:SetBarMode("safe")
    Swing:SetShowAimWindow(false)      -- the baseline: today's art alone
    Swing:SetShowClipRegion(false)
    local clock = { 4000 }
    local t = v2Tracker(clock, { baseSpeed = 1.0 })
    Swing:SetTracker(t)
    Swing:RenderIdle()
    t:OnSwingStart(2.0, 2)             -- aimLen 0.5, floor 0.5
    -- fill = max(0, (remaining - floor)/duration) x W  (test_swing2 :410-413)
    Swing:Update(clock[1])
    nearpx(Swing.fill:GetWidth(), 150)
    clock[1] = 4001.0
    Swing:Update(clock[1])
    nearpx(Swing.fill:GetWidth(), 50)
    clock[1] = 4001.6                  -- inside the aim window
    Swing:Update(clock[1])
    nearpx(Swing.fill:GetWidth(), 0)
    -- aim slice = aimLen x scale, phase `aim` only
    assertTrue(Swing.aim:IsShown())
    nearpx(Swing.aim:GetWidth(), 0.5 * (W / 2.0))
    Swing:RenderIdle()
    restoreBar()
end)

test("mode safe: the aim/retry/interlock slices ride the v2 numbers", function()
    Swing:SetBarMode("safe")
    Swing:SetShowAimWindow(false)
    Swing:SetShowClipRegion(false)
    local clock = { 4100 }
    local t = v2Tracker(clock, { baseSpeed = 1.0 })
    Swing:SetTracker(t)
    Swing:RenderIdle()
    t:OnSwingStart(2.0, 2)
    clock[1] = 4101.0                  -- at the aim edge
    t:OnShotCast("FAILED_QUIET", "Auto Shot", 75, "GR")
    Swing:Update(4101.2)
    assertTrue(Swing.retry:IsShown())
    nearpx(Swing.retry:GetWidth(), 0.3 * (W / 2.0))   -- test_swing2 :509
    Swing:Update(4101.6)                              -- the retry expired
    assertFalse(Swing.retry:IsShown())
    -- The interlock: the full-width red slice, the frozen fill, the cast text.
    local clock2 = { 4200 }
    local u = v2Tracker(clock2, { baseSpeed = 1.0,
        castLenReader = function() return 1.5 end })
    Swing:SetTracker(u)
    Swing:RenderIdle()
    u:OnSwingStart(2.0, 2)
    Swing:Update(clock2[1])
    nearpx(Swing.fill:GetWidth(), 150)
    clock2[1] = 4201.0                          -- half the cycle run
    Swing:Update(4201.0)
    nearpx(Swing.fill:GetWidth(), 50)
    -- The press at the cycle's halfway mark freezes the fill at 0.5.
    u:OnShotCast("SENT", "Aimed Shot", 20904, "GA")
    Swing:Update(4201.0)
    assertTrue(Swing.cast:IsShown())
    nearpx(Swing.cast:GetWidth(), W)               -- the full-width slice
    nearpx(Swing.fill:GetWidth(), 100)             -- frozen at 0.5 fraction
    Swing:RenderIdle()
    restoreBar()
end)

test("mode safe: an UNSET mode is the safe law, not a new one", function()
    -- `safe` is the reading of an unset mode (the module default, and the
    -- §7.1 migration's `true`/unset arm) -- a nil mode must never select the
    -- `one` expression, so the baseline pixels survive a nil.
    local saved = FX.Hunter.Swing.state.barMode
    FX.Hunter.Swing.state.barMode = nil
    local clock = { 4300 }
    local t = v2Tracker(clock, { baseSpeed = 1.0 })
    Swing:SetTracker(t)
    Swing:SetShowAimWindow(false)
    Swing:SetShowClipRegion(false)
    Swing:RenderIdle()
    t:OnSwingStart(2.0, 2)
    Swing:Update(clock[1])
    nearpx(Swing.fill:GetWidth(), 150)             -- the v2 safe-window number
    clock[1] = 4301.6
    Swing:Update(clock[1])
    nearpx(Swing.fill:GetWidth(), 0)
    Swing:RenderIdle()
    FX.Hunter.Swing.state.barMode = saved
    restoreBar()
end)

test("ShowSafeWindow is the mode picker's servant (the §7.1 migration)",
function()
    assertNotNil(ST)
    assertEquals("safe", FX.Hunter.Swing.state.barMode)
    assertTrue(FX.Hunter.Swing.state.showSafeWindow)
    -- A stored false reads back as `elapsed` -- the key's exact today-law.
    ST:Set("Hunter", "ShowSafeWindow", false)
    assertEquals("elapsed", FX.Hunter.Swing.state.barMode)
    assertFalse(FX.Hunter.Swing.state.showSafeWindow)
    ST:Set("Hunter", "ShowSafeWindow", true)
    assertEquals("safe", FX.Hunter.Swing.state.barMode)
    assertTrue(FX.Hunter.Swing.state.showSafeWindow)
    Swing:SetBarMode("nonsense")                   -- an unknown mode is safe
    assertEquals("safe", FX.Hunter.Swing.state.barMode)
end)

-- ================================================================= 2. `one` ==

test("mode one: the fill runs toward the aim end, capped by the aim region",
function()
    Swing:SetBarMode("one")
    Swing:SetShowClipRegion(false)
    Swing:SetShowWeaveLine(false)
    Swing:SetShowAimWindow(true)
    local clock = { 5000 }
    local t = v2Tracker(clock, { baseSpeed = 2.0 })
    Swing:SetTracker(t)
    Swing:RenderIdle()
    t:OnSwingStart(2.0, 2)                     -- aimLen 0.5, scale 100
    local aimW = 0.5 * (W / 2.0)               -- 50 px: the standing region
    -- The cycle's START: progress 0.
    Swing:Update(clock[1])
    nearpx(Swing.fill:GetWidth(), 0)
    -- The cycle's MIDDLE: W x progress.
    clock[1] = 5001.0
    Swing:Update(clock[1])
    nearpx(Swing.fill:GetWidth(), 100)
    assertTrue(Swing.fill:GetRight() <= Swing.anchor:GetRight() - aimW + 0.5,
        "the right edge stays out of the aim region while the cycle reloads")
    -- The cap bites EXACTLY at progress = 1 - aimLen/duration = 0.75.
    clock[1] = 5001.5
    Swing:Update(clock[1])
    nearpx(Swing.fill:GetWidth(), W - aimW)
    -- Through the aim phase the cap opens with the drained region: the edge
    -- is the live slice's left edge, W - remaining x scale.
    clock[1] = 5001.7
    assertEquals("aim", t:CycleState(5001.7))
    Swing:Update(5001.7)
    nearpx(Swing.fill:GetWidth(), W - 0.3 * (W / 2.0))
    clock[1] = 5001.9
    Swing:Update(5001.9)
    nearpx(Swing.fill:GetWidth(), W - 0.1 * (W / 2.0))
    -- FULL WIDTH at the aim's end: the cap opens as the window drains, so at
    -- 0.001 s of flight left the edge is 0.1 px off the bar's right end.
    clock[1] = 5001.999
    Swing:Update(5001.999)
    nearpx(Swing.fill:GetWidth(), W)
    Swing:RenderIdle()
    restoreBar()
end)

test("mode one: the reload phase never crosses the region's left edge",
function()
    Swing:SetBarMode("one")
    Swing:SetShowClipRegion(false)
    Swing:SetShowWeaveLine(false)
    Swing:SetShowAimWindow(true)
    local clock = { 5200 }
    -- base 3.0 / cycle 3.0: aimLen = 0.5 x 3.0 / 3.0 = 0.5, scale = W/3.0.
    local t = v2Tracker(clock, { baseSpeed = 3.0 })
    Swing:SetTracker(t)
    Swing:RenderIdle()
    t:OnSwingStart(3.0, 2)
    local aimW = 0.5 * (W / 3.0)
    local cap = W - aimW
    local i = 0
    local worst = 0
    local sawReload, sawAim = 0, 0
    -- Every reload-phase pass: the edge is at most the cap.
    while 5200 + i * 0.1 < 5203.0 do
        local at = 5200 + i * 0.1
        clock[1] = at
        Swing:Update(at)
        if Swing._phase == "reload" then
            sawReload = sawReload + 1
            worst = math.max(worst, Swing.fill:GetWidth())
            assertTrue(Swing.fill:GetWidth() <= cap + 0.5,
                "reload pass at +" .. string.format("%.1f", at - 5200)
                .. " drew " .. tostring(Swing.fill:GetWidth())
                .. " past the cap " .. tostring(cap))
        elseif Swing._phase == "aim" then
            sawAim = sawAim + 1
        end
        i = i + 1
    end
    assertTrue(sawReload > 5, "the cycle really ran its reload phase")
    assertTrue(sawAim > 0, "and its aim phase")
    assertTrue(worst > 0, "the fill runs (a dead fill proves nothing)")
    Swing:RenderIdle()
    restoreBar()
end)

-- ============================================================== 3. `elapsed` ==

test("mode elapsed: fraction x width, no slice (today's off-mode law)",
function()
    Swing:SetBarMode("elapsed")
    local clock = { 6000 }
    local t = v2Tracker(clock, { baseSpeed = 1.0 })
    Swing:SetTracker(t)
    Swing:RenderIdle()
    t:OnSwingStart(2.0, 2)
    Swing:Update(clock[1])
    nearpx(Swing.fill:GetWidth(), 0)          -- the pre-v2 law
    clock[1] = 6001.6                         -- inside the aim window
    Swing:Update(clock[1])
    nearpx(Swing.fill:GetWidth(), 160)        -- fraction 0.8 x 200
    assertFalse(Swing.aim:IsShown())          -- the slices hide wholesale
    assertFalse(Swing.retry:IsShown())
    assertFalse(Swing.cast:IsShown())
    Swing:RenderIdle()
    restoreBar()
end)

-- ==================================================== 4. the aim region (P2) ==

test("the aim region: aimLen x scale for the WHOLE cycle, in every mode",
function()
    for _, mode in ipairs({ "safe", "one", "elapsed" }) do
        Swing:SetBarMode(mode)
        Swing:SetShowAimWindow(true)
        Swing:SetShowClipRegion(false)
        Swing:SetShowWeaveLine(false)
        local clock = { 7000 }
        local t = v2Tracker(clock, { baseSpeed = 2.0 })
        Swing:SetTracker(t)
        Swing:RenderIdle()
        t:OnSwingStart(2.0, 2)
        local expect = 0.5 * (W / 2.0)
        local probes = { 7000, 7000.7, 7001.4, 7001.6, 7001.95 }
        for _, at in ipairs(probes) do
            clock[1] = at
            assertTrue(Swing:Update(at))
            assertTrue(Swing.aimRegion:IsShown(),
                mode .. " at +" .. tostring(at - 7000) .. " hid the region")
            nearpx(Swing.aimRegion:GetWidth(), expect)
            nearpx(Swing.aimRegion:GetRight(), Swing.anchor:GetRight())
        end
        Swing:RenderIdle()
    end
    restoreBar()
end)

test("the aim region: dimmer than the live slice; its own key hides it alone",
function()
    Swing:SetBarMode("safe")
    Swing:SetShowAimWindow(true)
    Swing:SetShowClipRegion(false)
    local clock = { 7200 }
    local t = v2Tracker(clock, { baseSpeed = 2.0 })
    Swing:SetTracker(t)
    Swing:RenderIdle()
    t:OnSwingStart(2.0, 2)
    clock[1] = 7201.6                      -- phase aim: both reds on screen
    assertTrue(Swing:Update(clock[1]))
    assertTrue(Swing.aim:IsShown())
    assertTrue(Swing.aimRegion:IsShown())
    local regionA = select(4, Swing.aimRegion:GetVertexColor())
    local liveA = select(4, Swing.aim:GetVertexColor())
    near3(regionA, S.AimRegionAlpha)
    near3(liveA, S.AimColor[4])
    assertTrue(regionA < liveA, "the region is a REGION, the slice is LIVE ("
        .. tostring(regionA) .. " !< " .. tostring(liveA) .. ")")
    -- The region is the same aim hue, so the right end is one legible family.
    local rr, rg, rb = Swing.aimRegion:GetVertexColor()
    local lr, lg, lb = Swing.aim:GetVertexColor()
    near3(rr, lr); near3(rg, lg); near3(rb, lb)
    -- ShowAimWindow=false: the region goes, the live slice is untouched.
    Swing:SetShowAimWindow(false)
    Swing:Update(clock[1])
    assertFalse(Swing.aimRegion:IsShown())
    assertTrue(Swing.aim:IsShown())
    nearpx(Swing.aim:GetWidth(), 0.5 * (W / 2.0))
    Swing:SetShowAimWindow(true)
    Swing:Update(clock[1])
    assertTrue(Swing.aimRegion:IsShown())
    Swing:RenderIdle()
    restoreBar()
end)

test("the aim region: under a live retry it dims so the yellow stays loudest",
function()
    Swing:SetBarMode("safe")
    Swing:SetShowAimWindow(true)
    Swing:SetShowClipRegion(false)
    local clock = { 7400 }
    local t = v2Tracker(clock, { baseSpeed = 2.0 })
    Swing:SetTracker(t)
    Swing:RenderIdle()
    t:OnSwingStart(2.0, 2)
    clock[1] = 7401.0
    Swing:Update(clock[1])
    near3(select(4, Swing.aimRegion:GetVertexColor()), S.AimRegionAlpha)
    t:OnShotCast("FAILED_QUIET", "Auto Shot", 75, "GR")   -- a 0.5 s retry
    Swing:Update(7401.1)
    assertTrue(Swing.retry:IsShown())
    local a = select(4, Swing.aimRegion:GetVertexColor())
    near3(a, S.AimRegionRetryAlpha)
    assertTrue(a < S.AimRegionAlpha,
        "the region dimmed: " .. tostring(a))
    Swing:Update(7401.6)                    -- the retry expired
    near3(select(4, Swing.aimRegion:GetVertexColor()), S.AimRegionAlpha)
    Swing:RenderIdle()
    restoreBar()
end)

-- ===================================================== 5. the clip stripe P1 ==

test("the clip stripe: (castLen + aimLen) x scale, castLen from the DATA",
function()
    -- The injected data table (the §7.8 item-5 seam: the stripe's cast
    -- length is Tools.DataCastMsByName's number, never a hand-typed one).
    -- The pcall wrapper is the leak law: an assert failure must not leave
    -- the module's data index patched for the files that run after.
    local ok, err = pcall(function()
    useData({ ["Aimed Shot"] = 1000 })
    Swing:SetBarMode("safe")
    Swing:SetShowAimWindow(false)
    Swing:SetShowClipRegion(true)
    Swing:SetShowWeaveLine(false)
    local clock = { 8000 }
    local t = v2Tracker(clock, { baseSpeed = 2.0 })
    Swing:SetTracker(t)
    Swing:RenderIdle()
    t:OnSwingStart(2.0, 2)                  -- aimLen 0.5, scale 100
    Swing:Update(clock[1])
    assertTrue(Swing.clip:IsShown())
    nearpx(Swing.clip:GetWidth(), (1.0 + 0.5) * (W / 2.0))     -- 150 px
    nearpx(Swing.clip:GetRight(), Swing.anchor:GetRight())
    near3(select(4, Swing.clip:GetVertexColor()), S.ClipRegionAlpha)
    -- Clamped to the bar: the honest "Aimed Shot always clips on this bow".
    useData({ ["Aimed Shot"] = 4000 })
    Swing:Update(clock[1])
    nearpx(Swing.clip:GetWidth(), W)
    -- Off is zero width.
    Swing:SetShowClipRegion(false)
    Swing:Update(clock[1])
    assertFalse(Swing.clip:IsShown())
    nearpx(Swing.clip:GetWidth(), 0)
    Swing:SetShowClipRegion(true)
    Swing:RenderIdle()
    end)
    restoreBar()
    if not ok then error(err, 0) end
end)

test("the clip stripe: the shipped data's Aimed Shot is the default length",
function()
    -- No injection: the number is the generated data's (§7.4: 2000 ms), the
    -- same index the interlock's fallback rides.
    Swing:InvalidateClipCastLength()
    local sec = Swing:ClipCastSeconds()
    assertNotNil(sec)
    nearpx(sec, 2.0)
    -- An un-hasted 2.0 s cycle therefore draws a FULL-WIDTH stripe: the
    -- honest "a cast-time shot always clips on this bow" (§7.4).
    Swing:SetBarMode("safe")
    Swing:SetShowAimWindow(false)
    Swing:SetShowClipRegion(true)
    local clock = { 8200 }
    local t = v2Tracker(clock, { baseSpeed = 2.0 })
    Swing:SetTracker(t)
    Swing:RenderIdle()
    t:OnSwingStart(2.0, 2)
    Swing:Update(clock[1])
    nearpx(Swing.clip:GetWidth(), W)
    Swing:RenderIdle()
    restoreBar()
end)

test("the clip stripe: retargeted to the LIVE cast under the interlock",
function()
    local ok, err = pcall(function()
    useData({ ["Aimed Shot"] = 4000 })
    Swing:SetBarMode("safe")
    Swing:SetShowAimWindow(false)
    Swing:SetShowClipRegion(true)
    local clock = { 8400 }
    local t = v2Tracker(clock, { baseSpeed = 2.0,
        castLenReader = function() return 0.8 end })
    Swing:SetTracker(t)
    Swing:RenderIdle()
    t:OnSwingStart(2.0, 2)
    Swing:Update(clock[1])
    nearpx(Swing.clip:GetWidth(), W)        -- 4.0 s data length: clamped
    -- The Aimed Shot SENT opens the interlock (the Forever no-START law):
    -- the stripe retargets to the LIVE cast's 0.8 s, so the frozen red bar
    -- shows the reason it is red (§7.4).
    t:OnShotCast("SENT", "Aimed Shot", 20904, "GA")
    Swing:Update(8400.1)
    assertTrue(Swing.cast:IsShown())
    -- freeze = 1 - (press - cycleStart)/duration = 1: the press ate the
    -- WHOLE cycle, so the red bar is full-width (the v2 interlock law).
    nearpx(Swing.fill:GetWidth(), W)
    nearpx(Swing.clip:GetWidth(), (0.8 + 0.5) * (W / 2.0))  -- 130 px
    -- The interlock's own light tint is what reads over the red bar.
    local r, g, b, a = Swing.clip:GetVertexColor()
    near3(r, S.ClipInterlockColor[1]); near3(g, S.ClipInterlockColor[2])
    near3(b, S.ClipInterlockColor[3])
    near3(a, S.ClipRegionAlpha)
    -- Out of the interlock the stripe rides the aim hue again.
    t:OnShotCast("SUCCEEDED", "Aimed Shot", 20904, "GA")
    Swing:Update(8400.2)
    assertFalse(Swing.cast:IsShown())
    local r2, g2 = Swing.clip:GetVertexColor()
    near3(r2, S.AimColor[1]); near3(g2, S.AimColor[2])
    nearpx(Swing.clip:GetWidth(), W)
    Swing:RenderIdle()
    end)
    restoreBar()                             -- restores the data index too
    if not ok then error(err, 0) end
end)

-- ======================================================== 6. the weave line ==

test("the weave line: x = W - (aimLen + gcd) x scale, on its key", function()
    local gcd = Swing.GcdSeconds()
    nearpx(gcd, 1.5)                     -- the shipped data's gcdMs = 1500
    Swing:SetBarMode("safe")
    Swing:SetShowAimWindow(false)
    Swing:SetShowClipRegion(false)
    Swing:SetShowWeaveLine(true)
    local clock = { 9000 }
    local t = v2Tracker(clock, { baseSpeed = 3.0 })
    Swing:SetTracker(t)
    Swing:RenderIdle()
    t:OnSwingStart(3.0, 2)               -- aimLen 0.5, scale 200/3
    Swing:Update(clock[1])
    assertTrue(Swing.weave:IsShown())
    local expect = W - (0.5 + gcd) * (W / 3.0)
    local centre = (Swing.weave:GetLeft() + Swing.weave:GetRight()) * 0.5
    nearpx(centre, Swing.anchor:GetLeft() + expect)
    nearpx(Swing.weave:GetWidth(), S.WeaveWidth)
    nearpx(Swing.weave:GetHeight(), S.Height + S.MarkerOvershoot)
    -- The line rides OUTSIDE the bar's edges: the taller-than-the-bar law.
    assertTrue(Swing.weave:GetTop() >= Swing.anchor:GetTop() + 1)
    assertTrue(Swing.weave:GetBottom() <= Swing.anchor:GetBottom() - 1)
    -- Off its key: gone.
    Swing:SetShowWeaveLine(false)
    Swing:Update(clock[1])
    if Swing.weave:IsShown() then
        error("weave facts: x=" .. tostring(Swing._weaveX)
            .. " flag=" .. tostring(FX.Hunter.Swing.state.showWeaveLine)
            .. " barShown=" .. tostring(Swing._shown)
            .. " nodeShown=" .. tostring(Swing.weave._shown)
            .. " strata=" .. tostring(Swing.weave:GetFrameStrata())
            .. " w=" .. tostring(Swing.weave:GetWidth())
            .. " h=" .. tostring(Swing.weave:GetHeight())
            .. " phase=" .. tostring(Swing._phase))
    end
    assertFalse(Swing.weave:IsShown())
    Swing:RenderIdle()
    restoreBar()
end)

test("the weave line: off-bar is the no-room message; default off", function()
    -- A 2.0 s cycle with aim 0.5 and the 1.5 s GCD: (0.5+1.5)/2.0 of the bar
    -- is the WHOLE bar -- the budget runs off the left edge, so the line
    -- hides (§7.4's hasted "do not step in" law).
    Swing:SetBarMode("safe")
    Swing:SetShowAimWindow(false)
    Swing:SetShowClipRegion(false)
    Swing:SetShowWeaveLine(true)
    local clock = { 9200 }
    local t = v2Tracker(clock, { baseSpeed = 2.0 })
    Swing:SetTracker(t)
    Swing:RenderIdle()
    t:OnSwingStart(2.0, 2)
    Swing:Update(clock[1])
    assertFalse(Swing.weave:IsShown(), "x = 0 is off-bar, not a border line")
    -- A hasted 1.5 s cycle (aim 0.375): aim + gcd = 1.875 > 1.5 -- off the bar.
    local h = v2Tracker({ 9400 }, { baseSpeed = 2.0 })
    Swing:SetTracker(h)
    Swing:RenderIdle()
    h:OnSwingStart(1.5, 2)
    Swing:Update(9400)
    assertFalse(Swing.weave:IsShown())
    Swing:RenderIdle()
    -- The γ.1 defaults are the MODULE's shipped state (captured above,
    -- before this file ran a single setter): mode safe, aim window ON, clip
    -- region ON, weave line OFF.
    assertEquals("safe", D_MODE)
    assertEquals(true, D_AIM)
    assertEquals(true, D_CLIP)
    assertEquals(false, D_WEAVE)
    restoreBar()
end)

-- ================================================================= 7. parity ==

--- One Auto Shot cycle through the REAL Update path (test_swing3.lua's
--- runCycle law), `mode` picking the bar mode and `path` the fill path;
--- returns the per-pass observations and the pass count.
local function runCycle(mode, path)
    Swing:SetBarMode(mode)
    Swing:SetShowAimWindow(true)
    Swing:SetShowClipRegion(true)
    Swing:SetShowWeaveLine(true)
    Swing:SetFillEngineMode(path)
    local clock = { 11000 }
    local t = v2Tracker(clock, { baseSpeed = 2.0 })
    Swing:SetTracker(t)
    Swing:RenderIdle()
    t:OnSwingStart(2.0, 2)
    local out, passes = {}, 0
    local i = 0
    while clock[1] <= 11003.0001 do
        if math.abs(clock[1] - 11001.5) < 1e-6 then
            t:OnShotCast("START", "Auto Shot", 75, "G1")
        elseif math.abs(clock[1] - 11001.9) < 1e-6 then
            t:OnShotCast("SUCCEEDED", "Auto Shot", 75, "G1")
        elseif math.abs(clock[1] - 11002.0) < 1e-6 then
            t:OnSwingStart(2.0, 2)
        end
        passes = passes + 1
        Swing:Update(clock[1])
        -- The mode's whole draw: the fill intent, the phase, the v2 slices
        -- and the three slice-A markers.
        out[#out + 1] = string.format(
            "%s|i%.2f|a%.2f|r%.2f|c%.2f|A%.2f|C%.2f|K%s|k%s|s%s",
            tostring(Swing._phase), Swing._fillIntent or -1,
            Swing._aimW or -1, Swing._retryW or -1, Swing._castW or -1,
            Swing._aimRegionW or -1, Swing._clipW or -1,
            tostring(Swing._weaveX), tostring(Swing._timeKey),
            tostring(Swing._shown and 1 or 0))
        i = i + 1
        clock[1] = 11000 + i * 0.1
    end
    Swing:RenderIdle()
    return out, passes
end

test("parity: one cycle draws the same sequence on both fill paths, in 3 modes",
function()
    for _, mode in ipairs({ "safe", "one", "elapsed" }) do
        local luaObs, luaPasses = runCycle(mode, "lua")
        local engObs, engPasses = runCycle(mode, "engine")
        assertTrue(#luaObs >= 30, mode .. ": the cycle really ran")
        assertEquals(luaPasses, engPasses)
        assertEquals(#luaObs, #engObs)
        local sawFill = 0
        for _, o in ipairs(luaObs) do
            if o:find("|i0.00") == nil then sawFill = sawFill + 1 end
        end
        assertTrue(sawFill > 0, mode .. ": the fill moved")
        for i = 1, #luaObs do
            assertEquals(luaObs[i], engObs[i],
                mode .. " pass " .. tostring(i))
        end
    end
    restoreBar()
end)

-- ============================================================ 8. StatusLine ==

test("StatusLine names the mode, the aim-region alpha and the stripe width",
function()
    Swing:SetBarMode("one")
    Swing:SetShowAimWindow(true)
    Swing:SetShowClipRegion(true)
    Swing:SetShowWeaveLine(false)
    local clock = { 12000 }
    local t = v2Tracker(clock, { baseSpeed = 2.0 })
    Swing:SetTracker(t)
    Swing:RenderIdle()
    t:OnSwingStart(2.0, 2)
    Swing:Update(clock[1])
    local line = Swing:StatusLine()
    assertNotNil(line)
    local clipped = string.gsub(line, "\n", " ")
    assertTrue(clipped:find("mode=one") ~= nil,
        "the mode is named: " .. clipped)
    assertTrue(clipped:find(string.format("aimRegion=%.1f@%.2f",
        0.5 * (W / 2.0), S.AimRegionAlpha)) ~= nil,
        "the aim region + its alpha: " .. clipped)
    assertTrue(clipped:find("clip=") ~= nil,
        "the clip stripe's width: " .. clipped)
    assertTrue(clipped:find(string.format("clip=%.1f",
        (Swing._clipW or 0))) ~= nil, "as a number: " .. clipped)
    assertTrue(clipped:find("weave=off") ~= nil,
        "the weave line reads off: " .. clipped)
    Swing:SetBarMode("elapsed")
    Swing:Update(clock[1])
    assertTrue(Swing:StatusLine():find("mode=elapsed") ~= nil)
    Swing:RenderIdle()
    restoreBar()
end)

-- ============================================================ the art laws ==

test("the marker art: the Aluminium family, the aim hue, one off-family line",
function()
    -- The legibility law of the SwingSkin comment: the two reds are the SAME
    -- hue at a stepped alpha (0.22 stripe, 0.45 region, 1.0 live slice), and
    -- the weave line is the one colour outside the cycle family.
    local cr, cg, cb, ca = Swing.clip:GetVertexColor()
    local rr, rg, rb = Swing.aimRegion:GetVertexColor()
    near3(cr, S.AimColor[1]); near3(cg, S.AimColor[2])
    near3(rr, S.AimColor[1]); near3(rg, S.AimColor[2])
    assertTrue(S.ClipRegionAlpha < S.AimRegionAlpha)
    assertTrue(S.AimRegionAlpha < S.AimColor[4])
    assertTrue(S.AimRegionRetryAlpha < S.AimRegionAlpha)
    assertTrue(S.AimRegionRetryAlpha > S.ClipRegionAlpha,
        "the region stays the brighter knob even dimmed for the retry")
    local wr, wg, wb, wa = Swing.weave:GetVertexColor()
    near3(wr, S.WeaveColor[1]); near3(wg, S.WeaveColor[2])
    near3(wb, S.WeaveColor[3]); near3(wa, S.WeaveColor[4])
    assertTrue(wb > wr, "the weave line is off-family from the reds")
    assertEquals(S.BarTexture, Swing.aimRegion:GetTexture())
    assertEquals(S.BarTexture, Swing.clip:GetTexture())
    assertEquals(S.WeaveTexture, Swing.weave:GetTexture())
    -- The fill path the mode flips between is untouched by slice A.
    assertEquals(S.BarTexture, Swing.fill:GetTexture())
end)

test("a resize re-pins the markers on the new geometry", function()
    Swing:SetBarMode("safe")
    Swing:SetShowAimWindow(true)
    Swing:SetShowClipRegion(true)
    Swing:SetShowWeaveLine(true)
    local savedW = S.Width
    Swing:SetWidth(300)
    assertEquals(300, S.Width)
    local clock = { 13000 }
    local t = v2Tracker(clock, { baseSpeed = 3.0 })
    Swing:SetTracker(t)
    Swing:RenderIdle()
    t:OnSwingStart(3.0, 2)                  -- aimLen 0.5, scale 300/3 = 100
    Swing:Update(clock[1])
    nearpx(Swing.aimRegion:GetWidth(), 0.5 * (300 / 3.0))
    nearpx(Swing.clip:GetWidth(), math.min(300,
        (Swing:ClipCastSeconds() + 0.5) * (300 / 3.0)))
    -- The weave line rides the seam: W - (aimLen + gcd) x scale.
    nearpx(Swing._weaveX, 300 - (0.5 + Swing.GcdSeconds()) * (300 / 3.0))
    assertTrue(Swing.weave:IsShown())
    Swing:RenderIdle()
    Swing:SetWidth(savedW)
    assertEquals(200, S.Width)
    restoreBar()
end)

test("an idle bar parks every marker (no stale stripe on a hidden bar)",
function()
    Swing:SetBarMode("one")
    Swing:SetShowAimWindow(true)
    Swing:SetShowClipRegion(true)
    Swing:SetShowWeaveLine(true)
    local clock = { 14000 }
    local t = v2Tracker(clock, { baseSpeed = 3.0 })
    Swing:SetTracker(t)
    Swing:RenderIdle()
    t:OnSwingStart(3.0, 2)                  -- aimLen 0.5, scale 66.7: the
                                            -- weave line is ON the bar
    Swing:Update(clock[1])
    assertTrue(Swing.clip:IsShown() and Swing.aimRegion:IsShown()
        and Swing.weave:IsShown(),
        "clip=" .. tostring(Swing._clipW) .. " region="
        .. tostring(Swing._aimRegionW) .. " weave=" .. tostring(Swing._weaveX))
    Swing:RenderIdle()
    assertFalse(Swing.clip:IsShown())
    assertFalse(Swing.aimRegion:IsShown())
    assertFalse(Swing.weave:IsShown())
    nearpx(Swing.clip:GetWidth(), 0)
    nearpx(Swing.aimRegion:GetWidth(), 0)
    -- The mode/marker seams are legal before the frames exist too (the
    -- options page applies stored values at login through them).
    assertEquals("one", FX.Hunter.Swing.state.barMode)
    restoreBar()
    assertEquals("safe", FX.Hunter.Swing.state.barMode)
    assertTrue(Swing.state.showAimWindow)
    assertTrue(Swing.state.showClipRegion)
    assertFalse(Swing.state.showWeaveLine)
    assertFalse(Swing.anchor:IsShown())
end)

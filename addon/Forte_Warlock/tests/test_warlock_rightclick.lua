-- addon/Forte_Warlock/tests/test_warlock_rightclick.lua
-- Wave 6 "Right-click everywhere" (PLAN §11.1): the four plates' CD-30 seam,
-- the Cooldown bar's law ported onto the shared base (UI/Frame.lua's
-- _StampPress / Moved / OnMouseUp / _WireRightClick; the source's FWSSFrame
-- law, Forte_Soulstone.xml:189-196 wiring OnMouseDown = FW:StartMoving and
-- OnMouseUp = FW:SSFrame_OnClick -- SSFrame_OnClick's non-left branch is
-- FW:ScrollTo(FWL.SOULSTONE_TRACKER), Forte_Soulstone.lua's OnClick, the
-- Healthstone/Summon pairs at Forte_Healthstone.lua / Forte_Summon.lua).
-- EACH PLATE OPENS ITS OWN PAGE: ShardManager / Soulstone / Healthstone /
-- Summon (the ids Pages/Warlock.lua registers).
--
-- The mouse law proven here is the source's: the lock gates the DRAG
-- (EnableMove gates the drag frame's registration; the mouse itself is the
-- user's EnableMouse switch), so the plates ship LOCKED (FrameSkin.Locked,
-- the store's default) and STILL carry the seam. The release rides the
-- topmost mouse-enabled frame of the plate's region: the Shard Manager's
-- always-live tooltip frame, the plain plates' anchor; the seam is wired on
-- the anchor, the tip and the drag frame alike, so the one that receives it
-- runs the same law.
--
-- Driven through the REAL frame scripts: GetScript("OnMouseUp") called as
-- the engine calls it, the Forte_Cooldown/tests/test_timeline.lua CD-30
-- pattern.
--
-- FAILS-ON-THE-OLD-CODE: the plates carried no OnMouseUp anywhere (the seam
-- reads nil), SetLocked(true)/ApplyMouse switched the anchor's mouse off
-- (the plates ship locked -- the seam was unreachable out of the box), the
-- drag frame's OnDragStart stamped nothing, and no plate knew a pageId.

local FX = ForteXorcist
local UI = FX.Warlock.UI
local Shards = FX.Warlock.Shards
local Stone = FX.Warlock.Soulstone
local HS = FX.Warlock.Healthstone
local Summon = FX.Warlock.Summon
local O = FX.Options
local S = FX.Settings

local function ensureBuilt()
    UI:_InitViews()
    local P = FX.Warlock.Pages
    if P and P.RegisterWarlockPages then P.RegisterWarlockPages() end
end

local function plates()
    return {
        { p = Shards, page = "ShardManager" },
        { p = Stone, page = "Soulstone" },
        { p = HS, page = "Healthstone" },
        { p = Summon, page = "Summon" },
    }
end

--- The frame that owns the plate's mouse region: the tooltip frame while it
--- exists (the Shard Manager's, mouse-on by its own law), the anchor
--- otherwise.
local function mouseFrame(p)
    return p.tip or p.anchor
end

test("every plate carries the seam; each right-button release opens ITS OWN page",
function()
    ensureBuilt()
    for _, e in ipairs(plates()) do
        local p = e.p
        assertNotNil(p.anchor, e.page .. ": the plate is built")
        assertNotNil(p.anchor:GetScript("OnMouseUp"),
            e.page .. ": the anchor carries the release")
        assertNotNil(p._dragFrame and p._dragFrame:GetScript("OnMouseUp"),
            e.page .. ": the drag frame carries the release")
        if p.tip then
            assertNotNil(p.tip:GetScript("OnMouseUp"),
                e.page .. ": the tip carries the release")
        end
        assertNotNil(O.pages[e.page], e.page .. ": its page is registered")
        -- The plates ship LOCKED (the store's Lock default) -- the source's
        -- law: locked gates the drag, not the release.
        O:Close()
        local f = mouseFrame(p)
        p._downX, p._downY = nil, nil
        f:GetScript("OnMouseUp")(f, "RightButton")
        assertEquals(true, O:IsOpen(), e.page .. ": the release opens")
        assertEquals(e.page, O.pageId, e.page .. ": opens ITS OWN page")
    end
    O:Close()
end)

test("a plate release that followed a drag does not open", function()
    ensureBuilt()
    local p = Stone
    local f = mouseFrame(p)
    O:Close()
    local realPos = GetCursorPosition
    p._downX, p._downY = nil, nil
    p:_StampPress()
    assertEquals(false, p:Moved(), "no travel yet")
    _G.GetCursorPosition = function() return 400, 400 end
    p._downX, p._downY = 300, 300
    assertEquals(true, p:Moved(), "the cursor travelled")
    f:GetScript("OnMouseUp")(f, "RightButton")
    assertEquals(false, O:IsOpen(), "a drag never opens the options window")
    _G.GetCursorPosition = realPos
    p._downX, p._downY = nil, nil
end)

test("RightClickOptions off silences every plate; the recycle opens them again",
function()
    ensureBuilt()
    assertEquals(true, S:GetDefault("General", "RightClickOptions"),
        "Forte_Core.lua:2495 ships it on")
    S:Set("General", "RightClickOptions", false)
    for _, e in ipairs(plates()) do
        O:Close()
        local p = e.p
        p._downX, p._downY = nil, nil
        local f = mouseFrame(p)
        f:GetScript("OnMouseUp")(f, "RightButton")
        assertEquals(false, O:IsOpen(), e.page .. ": off = the plate is silent")
    end
    S:Reset("General", "RightClickOptions")
    O:Close()
    local p = Stone
    p._downX, p._downY = nil, nil
    local f = mouseFrame(p)
    f:GetScript("OnMouseUp")(f, "RightButton")
    assertEquals(true, O:IsOpen(), "the recycle opens it again")
    O:Close()
end)

test("the left release opens nothing; an unlocked plate opens its page too",
function()
    ensureBuilt()
    local p = Shards
    local f = mouseFrame(p)
    O:Close()
    local realPos = GetCursorPosition
    _G.GetCursorPosition = function() return 100, 100 end
    p._downX, p._downY = 100, 100
    f:GetScript("OnMouseUp")(f, "LeftButton")
    assertEquals(false, O:IsOpen(), "the left release opens nothing")
    _G.GetCursorPosition = realPos
    -- Unlocked: the same release on the same frame opens the plate's page.
    local was = p.cfg.locked
    p:SetLocked(false)
    p:ApplyMouse()
    p._downX, p._downY = nil, nil
    f:GetScript("OnMouseUp")(f, "RightButton")
    assertEquals(true, O:IsOpen(), "unlocked = the seam is alive")
    assertEquals("ShardManager", O.pageId)
    O:Close()
    p:SetLocked(was and true or false)
    p:ApplyMouse()
    p._downX, p._downY = nil, nil
end)

-- M2 (CodeReview6): the press stamp must ride OnMouseDown (ANY button) on
-- EVERY frame that can own the plate's mouse region -- the source stamps
-- every press (`<OnMouseDown>FW:StartMoving(self,button)`,
-- Forte_Soulstone.xml:189-191), while the engine fires OnDragStart only for
-- the drag frame's registered button: on the live client the right-press
-- stamped nothing and the first drag poisoned every later right-click with
-- its stale stamp. These legs drive the scripts the CLIENT fires, in the
-- client's order, and never touch _StampPress -- they fail on the old code
-- where GetScript("OnMouseDown") is nil.
test("M2: anchor, tip and drag frame stamp every press through OnMouseDown",
function()
    ensureBuilt()
    for _, e in ipairs(plates()) do
        local p = e.p
        for _, fr in ipairs({
            { "anchor", p.anchor }, { "tip", p.tip }, { "drag", p._dragFrame },
        }) do
            if fr[2] then
                assertNotNil(fr[2]:GetScript("OnMouseDown"),
                    e.page .. ": the " .. fr[1] .. " stamps every press")
                assertNotNil(fr[2]:GetScript("OnMouseUp"),
                    e.page .. ": the " .. fr[1] .. " carries the release")
            end
        end
    end
end)

test("M2: a plate drag, then a right-click at a NEW spot, opens its own page",
function()
    ensureBuilt()
    for _, e in ipairs(plates()) do
        local p = e.p
        local f = mouseFrame(p)
        local dragF = p._dragFrame
        local was = p.cfg.locked
        p:SetLocked(false)
        p:ApplyMouse()
        O:Close()
        local realPos = GetCursorPosition
        -- 1. LEFT press at (100,100), drag, release at (400,400): inert.
        _G.GetCursorPosition = function() return 100, 100 end
        f:GetScript("OnMouseDown")(f, "LeftButton")
        dragF:GetScript("OnDragStart")(dragF)
        _G.GetCursorPosition = function() return 400, 400 end
        dragF:GetScript("OnDragStop")(dragF)
        f:GetScript("OnMouseUp")(f, "LeftButton")
        assertEquals(false, O:IsOpen(),
            e.page .. ": a drag-release opens nothing")
        -- 2. LATER a right press+release at a DIFFERENT (250,250) spot: the
        -- fresh press re-stamps (the stale drag stamp was M2's dead seam).
        _G.GetCursorPosition = function() return 250, 250 end
        f:GetScript("OnMouseDown")(f, "RightButton")
        f:GetScript("OnMouseUp")(f, "RightButton")
        assertEquals(true, O:IsOpen(),
            e.page .. ": M2: the right-click at the new spot opens")
        assertEquals(e.page, O.pageId, e.page .. ": opens ITS OWN page")
        O:Close()
        -- 3. right press, MOVE, release: the travel reads as a drag.
        _G.GetCursorPosition = function() return 120, 120 end
        f:GetScript("OnMouseDown")(f, "RightButton")
        _G.GetCursorPosition = function() return 500, 500 end
        f:GetScript("OnMouseUp")(f, "RightButton")
        assertEquals(false, O:IsOpen(),
            e.page .. ": a moved right release never opens")
        _G.GetCursorPosition = realPos
        p:SetLocked(was and true or false)
        p:ApplyMouse()
    end
end)

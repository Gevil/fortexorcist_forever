-- addon/Forte_Timer/tests/test_rows_rightclick.lua
-- Wave 6 "Right-click everywhere" (PLAN §11.1): the Spell Timer panel's
-- CD-30 seam, the Cooldown bar's law ported (Forte_Cooldown/UI/Timeline.lua's
-- _StampPress / Moved / OnMouseUp; the source's FWSSFrame law,
-- Forte_Soulstone.xml:189-196 + SSFrame_OnClick + FW:Moved,
-- Forte_Core/Options.lua:649-662). A right-button release on the panel's
-- anchor opens the options window on THIS module's page (id `SpellTimer`,
-- Pages/Timer.lua:34); a release after a drag (the cursor travelled between
-- the press stamp and the release) never opens it; `General.RightClickOptions`
-- off silences it; the left button (the drag button) opens nothing; and the
-- source's lock law: the lock gates the DRAG START (FW_StartMoving
-- :651), not the mouse, so a LOCKED panel carries the seam too.
--
-- Driven through the REAL frame scripts: GetScript("OnMouseUp") /
-- GetScript("OnDragStart") called as the engine calls them, exactly the
-- Forte_Cooldown/tests/test_timeline.lua CD-30 pattern.
--
-- FAILS-ON-THE-OLD-CODE: before this change the panel carried no OnMouseUp
-- at all (the anchor script read nil -- the first assertNil-shaped seam
-- raises), SetLocked switched the mouse off (the locked-release test
-- silences), and OnDragStart was the bare `f.StartMoving` reference (the
-- locked bar started moving, the stamp test saw no stamp).

local FX = ForteXorcist
local D = FX.Timer.Display
local M = FX.Timer.Module
local O = FX.Options
local S = FX.Settings

local function ensureBuilt()
    if not M.options then M:OnEnable() end
    assertNotNil(D.anchor, "the Spell Timer panel is built in every gate run")
    local P = FX.Timer.Pages
    if P and P.RegisterTimerPage then P.RegisterTimerPage() end
    assertNotNil(O.pages["SpellTimer"], "the SpellTimer page is registered")
end

test("a right-button release opens the SpellTimer page; a drag does not; left is inert",
function()
    ensureBuilt()
    local release = D.anchor:GetScript("OnMouseUp")
    assertNotNil(release, "the panel carries the release handler")
    local was = D.cfg.locked
    D:SetLocked(false)
    O:Close()

    -- A press and a release on the same pixel: the page opens.
    local realPos = GetCursorPosition
    _G.GetCursorPosition = function() return 100, 100 end
    D:_StampPress()
    release(D.anchor, "RightButton")
    assertEquals(true, O:IsOpen())
    assertEquals("SpellTimer", O.pageId)
    O:Close()
    assertFalse(O:IsOpen())

    -- A DRAG: the cursor travelled between the press stamp and the
    -- release, so Moved() is true and the window stays shut (FW:Moved,
    -- Forte_Core/Options.lua:659-662).
    D:_StampPress()
    assertEquals(false, D:Moved(), "no travel yet")
    _G.GetCursorPosition = function() return 400, 400 end
    D._downX, D._downY = 300, 300
    assertEquals(true, D:Moved(), "the cursor travelled")
    release(D.anchor, "RightButton")
    assertEquals(false, O:IsOpen(), "a drag never opens the options window")

    -- The left button is the drag button, not the options button.
    _G.GetCursorPosition = function() return 100, 100 end
    D._downX, D._downY = 100, 100
    release(D.anchor, "LeftButton")
    assertEquals(false, O:IsOpen(), "the left release opens nothing")
    _G.GetCursorPosition = realPos
    D._downX, D._downY = nil, nil
    D:SetLocked(was and true or false)
end)

test("the lock gates the drag start, not the mouse: a locked panel opens too",
function()
    ensureBuilt()
    local release = D.anchor:GetScript("OnMouseUp")
    local drag = D.anchor:GetScript("OnDragStart")
    assertNotNil(drag, "the panel carries the drag-start script")
    local was = D.cfg.locked
    O:Close()

    -- LOCKED: FW_StartMoving stamps the press FIRST (Options.lua:650) and
    -- the lock gates only the drag start (:651) -- StartMoving is not
    -- reached, the stamp is.
    D:SetLocked(true)
    assertEquals(true, D.cfg.locked)
    local real = D.anchor.StartMoving
    local starts = 0
    D.anchor.StartMoving = function() starts = starts + 1 end
    D._downX, D._downY = nil, nil
    drag(D.anchor, "LeftButton")
    assertEquals(0, starts, "a locked panel never starts moving")
    assertNotNil(D._downX, "the press stamp is taken before the lock is read")

    -- UNLOCKED: the same script reaches StartMoving.
    D:SetLocked(false)
    drag(D.anchor, "LeftButton")
    assertEquals(1, starts, "unlocked: the drag starts")
    D.anchor.StartMoving = real

    -- And the LOCKED panel's right release opens its page (the source's
    -- frames keep the mouse while locked -- the Forte_Soulstone law).
    D:SetLocked(true)
    D._downX, D._downY = nil, nil
    release(D.anchor, "RightButton")
    assertEquals(true, O:IsOpen(), "a locked panel carries the seam too")
    assertEquals("SpellTimer", O.pageId)
    O:Close()
    D:SetLocked(was and true or false)
end)

test("RightClickOptions gates the panel's right-release", function()
    ensureBuilt()
    local release = D.anchor:GetScript("OnMouseUp")
    local was = D.cfg.locked
    D:SetLocked(false)
    O:Close()
    assertEquals(true, S:GetDefault("General", "RightClickOptions"),
        "Forte_Core.lua:2495 ships it on")
    S:Set("General", "RightClickOptions", true)
    D:_StampPress()
    release(D.anchor, "RightButton")
    assertEquals(true, O:IsOpen(), "on = the release opens the window")
    O:Close()
    S:Set("General", "RightClickOptions", false)
    D:_StampPress()
    release(D.anchor, "RightButton")
    assertEquals(false, O:IsOpen(), "off = the panel is silent")
    S:Reset("General", "RightClickOptions")
    D:_StampPress()
    release(D.anchor, "RightButton")
    assertEquals(true, O:IsOpen(), "the recycle opens it again")
    O:Close()
    D._downX, D._downY = nil, nil
    D:SetLocked(was and true or false)
end)

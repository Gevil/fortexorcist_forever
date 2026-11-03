-- addon/Forte_Hunter/tests/test_swing_rightclick.lua
-- Wave 6 "Right-click everywhere" (PLAN §11.1): the Hunter swing bar's CD-30
-- seam, the Cooldown bar's law ported (Forte_Cooldown/UI/Timeline.lua's
-- _StampPress / Moved / OnMouseUp; the source's FWSSFrame law,
-- Forte_Soulstone.xml:189-196 + SSFrame_OnClick + FW:Moved,
-- Forte_Core/Options.lua:649-662). A right-button release on the bar opens
-- the options window on THIS module's page (id `Hunter`,
-- Pages/Hunter.lua:111); a release after a drag never opens it;
-- `General.RightClickOptions` off silences it; the left button (the drag
-- button) opens nothing; and the lock gates the DRAG START (FW_StartMoving
-- :651), not the mouse -- decisive HERE, where the bar ships LOCKED by
-- default (DEFAULT.locked = true), so the port's old mouse-off-while-locked
-- made the seam unreachable out of the box.
--
-- Driven through the REAL frame scripts: GetScript("OnMouseUp") /
-- GetScript("OnDragStart") called as the engine calls them, the
-- Forte_Cooldown/tests/test_timeline.lua CD-30 pattern.
--
-- FAILS-ON-THE-OLD-CODE: the bar carried no OnMouseUp (the seam read nil),
-- SetLocked(true) switched the mouse off (the locked-release test silences),
-- OnDragStart was the bare `f.StartMoving` reference (the locked bar started
-- moving; no stamp).

local FX = ForteXorcist
local Swing = FX.Hunter.Swing
local O = FX.Options
local S = FX.Settings

local function ensureBuilt()
    Swing:Init()
    assertNotNil(Swing.anchor, "the swing bar is built in this suite")
    local P = FX.Hunter.Pages
    if P and P.RegisterHunterPage then P.RegisterHunterPage() end
    assertNotNil(O.pages["Hunter"], "the Hunter page is registered")
end

test("a right-button release opens the Hunter page; a drag does not; left is inert",
function()
    ensureBuilt()
    local release = Swing.anchor:GetScript("OnMouseUp")
    assertNotNil(release, "the bar carries the release handler")
    local was = Swing.cfg.locked
    Swing:SetLocked(false)
    O:Close()

    -- A press and a release on the same pixel: the page opens.
    local realPos = GetCursorPosition
    _G.GetCursorPosition = function() return 100, 100 end
    Swing:_StampPress()
    release(Swing.anchor, "RightButton")
    assertEquals(true, O:IsOpen())
    assertEquals("Hunter", O.pageId)
    O:Close()
    assertFalse(O:IsOpen())

    -- A DRAG: the cursor travelled between the press stamp and the
    -- release, so Moved() is true and the window stays shut (FW:Moved,
    -- Forte_Core/Options.lua:659-662).
    Swing:_StampPress()
    assertEquals(false, Swing:Moved(), "no travel yet")
    _G.GetCursorPosition = function() return 400, 400 end
    Swing._downX, Swing._downY = 300, 300
    assertEquals(true, Swing:Moved(), "the cursor travelled")
    release(Swing.anchor, "RightButton")
    assertEquals(false, O:IsOpen(), "a drag never opens the options window")

    -- The left button is the drag button, not the options button.
    _G.GetCursorPosition = function() return 100, 100 end
    Swing._downX, Swing._downY = 100, 100
    release(Swing.anchor, "LeftButton")
    assertEquals(false, O:IsOpen(), "the left release opens nothing")
    _G.GetCursorPosition = realPos
    Swing._downX, Swing._downY = nil, nil
    Swing:SetLocked(was and true or false)
end)

test("the lock gates the drag start, not the mouse: the bar ships locked and opens",
function()
    ensureBuilt()
    local release = Swing.anchor:GetScript("OnMouseUp")
    local drag = Swing.anchor:GetScript("OnDragStart")
    assertNotNil(drag, "the bar carries the drag-start script")
    local was = Swing.cfg.locked
    O:Close()

    -- LOCKED (the shipped default): FW_StartMoving stamps the press FIRST
    -- (Options.lua:650) and the lock gates only the drag start (:651) --
    -- StartMoving is not reached, the stamp is.
    Swing:SetLocked(true)
    assertEquals(true, Swing.cfg.locked)
    local real = Swing.anchor.StartMoving
    local starts = 0
    Swing.anchor.StartMoving = function() starts = starts + 1 end
    Swing._downX, Swing._downY = nil, nil
    drag(Swing.anchor, "LeftButton")
    assertEquals(0, starts, "a locked bar never starts moving")
    assertNotNil(Swing._downX, "the press stamp is taken before the lock is read")

    -- UNLOCKED: the same script reaches StartMoving.
    Swing:SetLocked(false)
    drag(Swing.anchor, "LeftButton")
    assertEquals(1, starts, "unlocked: the drag starts")
    Swing.anchor.StartMoving = real

    -- And the LOCKED bar's right release opens its page (the source's
    -- frames keep the mouse while locked -- the Forte_Soulstone law).
    Swing:SetLocked(true)
    Swing._downX, Swing._downY = nil, nil
    release(Swing.anchor, "RightButton")
    assertEquals(true, O:IsOpen(), "the shipped-locked bar carries the seam")
    assertEquals("Hunter", O.pageId)
    O:Close()
    Swing:SetLocked(was and true or false)
end)

test("RightClickOptions gates the bar's right-release", function()
    ensureBuilt()
    local release = Swing.anchor:GetScript("OnMouseUp")
    local was = Swing.cfg.locked
    Swing:SetLocked(false)
    O:Close()
    assertEquals(true, S:GetDefault("General", "RightClickOptions"),
        "Forte_Core.lua:2495 ships it on")
    S:Set("General", "RightClickOptions", true)
    Swing:_StampPress()
    release(Swing.anchor, "RightButton")
    assertEquals(true, O:IsOpen(), "on = the release opens the window")
    O:Close()
    S:Set("General", "RightClickOptions", false)
    Swing:_StampPress()
    release(Swing.anchor, "RightButton")
    assertEquals(false, O:IsOpen(), "off = the bar is silent")
    S:Reset("General", "RightClickOptions")
    Swing:_StampPress()
    release(Swing.anchor, "RightButton")
    assertEquals(true, O:IsOpen(), "the recycle opens it again")
    O:Close()
    Swing._downX, Swing._downY = nil, nil
    Swing:SetLocked(was and true or false)
end)

-- addon/Forte_Timer/tests/test_display_anchor_glow.lua
-- Code-review-10 section (c) MT-11 + MT-12 (the review's i13/i14 verified the
-- shapes; nothing pinned them): the two display laws d490e2e shipped.
--
--   * MT-11 -- the title anchor rides the growth direction (UI/Rows.lua's
--     ApplyTitleAnchor): a panel that expands UPWARD hangs its stack off the
--     frame's BOTTOM edge, and the handle the player positions IS that bottom
--     edge -- the drag title rides BELOW the frame (title TOP -> anchor
--     BOTTOM). A panel that grows downward keeps the title above (title
--     BOTTOM -> anchor TOP). The module's SetExpand seam drives it, and the
--     Init path applies the stored value.
--   * MT-12 -- the icon glow geometry (the Spark2 ring swap): the ring's
--     bright line spans px 15..49 of its 64 px texture, so the drawn size is
--     iconSize * (64/34) on the width and height * (64/34) on the height --
--     and because the geometry law keeps `iconSize == height` (Rows.lua's
--     geometry init, Module:SetHeight), the two agree and the ring wraps the
--     square icon exactly. Both the acquire-time and the geometry-time
--     sites must agree (the review's i13: the formulas agree at both).
--
-- The numbers are measured off the real frames (this agent has no vision --
-- the pixel check is uiforever's, the FORMULA is this suite's).

local FX = ForteXorcist
local D = FX.Timer.Display
local M = FX.Timer.Module
local Laws = FX.Timer.Laws
local Skin = FX.Timer.Skin

local function near3(actual, expected)
    assertTrue(math.abs(actual - expected) < 1e-3)
end

local function enableTimer()
    if not M.options then M:OnEnable() end
    return M
end

-- ==================================================== MT-11: title anchor ==

test("MT-11: the drag title rides BELOW the panel while it grows upward",
function()
    enableTimer()
    assertNotNil(D.anchor)
    assertNotNil(D.title)
    -- The shipped default: expand ON (the stack grows UP from the bottom
    -- edge), so the title sits below the frame.
    local point, _, relPoint = D.title:GetPoint()
    assertEquals("TOP", point, "expand=true: the title's own TOP edge anchors")
    assertEquals("BOTTOM", relPoint,
        "to the anchor's BOTTOM edge: the handle the player drags stays"
        .. " clear of the stack (the upward-growth law)")
end)

test("MT-11: SetExpand(false) flips the title ABOVE the panel, SetExpand(true) back below",
function()
    enableTimer()
    M:SetExpand(false)
    local point, _, relPoint = D.title:GetPoint()
    assertEquals("BOTTOM", point, "expand=false: the stack grows DOWN, the"
        .. " title rides above the frame")
    assertEquals("TOP", relPoint)
    M:SetExpand(true)
    point, _, relPoint = D.title:GetPoint()
    assertEquals("TOP", point, "the flip is a two-way seam, not a one-shot")
    assertEquals("BOTTOM", relPoint)
    -- The store rides the flip (the panel's own SavedVariables half).
    assertEquals(true, M.options.expand)
end)

test("MT-11: ApplyTitleAnchor(nil) answers the STORED expand, not a constant",
function()
    enableTimer()
    M.options.expand = false
    D:ApplyTitleAnchor(nil)
    local point = D.title:GetPoint()
    assertEquals("BOTTOM", point,
        "the nil call is the Init path's: it reads self.options.expand")
    M.options.expand = true
    D:ApplyTitleAnchor(nil)
    assertEquals("TOP", D.title:GetPoint())
    M:SetExpand(true)   -- leave the shipped default
end)

-- ====================================================== MT-12: glow sizes ==

test("MT-12: the icon glow is the 64/34 ring scale of the icon, at the acquire size",
function()
    enableTimer()
    local o = M.options
    -- The invariant the law rides on (the review's i13): the icon is square
    -- and its size IS the row height.
    assertEquals(o.height, o.iconSize, "the iconSize == height invariant")
    local row = D:AcquireRow(1)
    assertNotNil(row.iconSpark)
    near3(row.iconSpark:GetWidth(), o.iconSize * Skin.IconGlowFactor)
    near3(row.iconSpark:GetHeight(), o.height * Skin.IconGlowFactor)
    -- The 64 px texture's bright ring (px 15..49) is 34 px wide -- the factor
    -- IS that ratio, recorded so a "fix" to a round number trips here.
    near3(Skin.IconGlowFactor, 64 / 34)
end)

test("MT-12: the geometry-time resize keeps the ring glued to the icon edge (both formulas agree)",
function()
    enableTimer()
    local o = M.options
    local h0 = o.height
    local row = D:AcquireRow(1)
    D:SetSize(o.width, 20)                      -- the row height to 20
    assertEquals(20, o.iconSize,
        "the resize law: SetHeight moves iconSize WITH height (i13)")
    -- The geometry pass, driven exactly as the render loop drives it.
    D:ApplyRowGeometry(row, o, M.skin, 1)
    near3(row.iconSpark:GetWidth(), o.iconSize * Skin.IconGlowFactor)
    near3(row.iconSpark:GetHeight(), o.height * Skin.IconGlowFactor)
    near3(row.icon:GetWidth(), o.iconSize)
    near3(row.icon:GetHeight(), o.iconSize)
    -- The two formulas (acquire-time at Init, geometry-time here) agree on
    -- the same numbers: the width uses iconSize, the height uses height, and
    -- the invariant keeps them the same scale of the same square.
    near3(row.iconSpark:GetWidth(), row.iconSpark:GetHeight())
    D:SetSize(o.width, h0)                      -- restore the panel geometry
    D:ApplyRowGeometry(row, o, M.skin, 1)
end)

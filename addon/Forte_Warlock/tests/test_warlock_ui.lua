-- addon/Forte_Warlock/tests/test_warlock_ui.lua
-- wow-ui-sim tests for the warlock UI (UI/Frame.lua + Shards/Soulstone/
-- Healthstone/Summon + UI/Module.lua + Pages/Warlock.lua): the four plates'
-- geometry (the original's plate law, every constant cited in UI/Frame.lua:
-- 106x20 header = 100+2*3 x 20, Forte_Soulstone.lua:65 + Forte_Core.lua:479 +
-- Forte_Soulstone.xml:124; the x<n> count at x=18, Forte_Soulstone.xml:131-138;
-- the right label at x=-4, Forte_Soulstone.xml:140-146; the second-line bar
-- 100x12 at (3,-18), Forte_Soulstone.lua:123-124,:670-671), their show/hide
-- law driven by INJECTED trackers and an injected clock, the exact label
-- texts, a numeric VISIBILITY PASS over every label (shown, non-empty, inside
-- its plate: string width <= its slot budget <= plate width), the 10 Hz ask
-- (which frame says "keep ticking"), the kick law (activity is on screen
-- without any OnUpdate), the real OnEvent dispatch through the module's own
-- frame, the live settings seam, the shared lock mirror, the class gate and
-- the four registered options pages.
--
-- Every tracker here is INJECTED (SetTracker): no real time, no bag read, no
-- cast driving. The sim profile is not a Warlock, so the module's login gate
-- never fires in the gate run — Init/OnClassChanged("WARLOCK") are driven
-- directly (the established pattern of Forte_Hunter/tests/test_swing.lua).

local FX = ForteXorcist
local UI = FX.Warlock.UI
local Shards = FX.Warlock.Shards
local Stone = FX.Warlock.Soulstone
local HS = FX.Warlock.Healthstone
local Summon = FX.Warlock.Summon
local WK = FX.Warlock
local SS = FX.Warlock.ShardsSkin
local StS = FX.Warlock.SoulstoneSkin
local HSS = FX.Warlock.HealthstoneSkin
local SuS = FX.Warlock.SummonSkin
local ST = FX.Settings
local Frame = FX.Warlock.Frame

local function nearpx(actual, expected)
    return assertTrue(math.abs(actual - expected) <= 0.5)
end
local function near3(actual, expected)
    return assertTrue(math.abs(actual - expected) < 1e-3)
end
local function fakeClock(box)
    return function() return box[1] end
end

-- The label-visibility pass: every label the plate prints must be SHOWN,
-- non-empty, measurably narrower than its slot inside the plate (the slot
-- budgets are the plate's own geometry: 106 wide, the count centred at x=18
-- from the LEFT, Forte_Soulstone.xml:135, the right label ending at x=-4 from
-- the RIGHT, Forte_Soulstone.xml:144; the bar pair runs 1..100 minus the
-- clock's slot, Forte_Soulstone.xml:32,:18). No clipping is possible when
-- string width <= slot width.
local function assertVisibleLabel(fs, label, slotW)
    assertNotNil(fs, label)
    local t = fs:GetText()
    assertTrue(type(t) == "string" and t ~= "",
        label .. ": text non-empty (got " .. tostring(t) .. ")")
    assertTrue(fs:IsShown(), label .. ": shown")
    local ok, w = pcall(function() return fs:GetStringWidth() end)
    assertTrue(ok and type(w) == "number" and w > 0,
        label .. ": string width is a positive number")
    assertTrue(w <= slotW,
        string.format("%s: %q width %.1f exceeds slot %d", label, t, w, slotW))
    assertTrue(w <= 106, label .. ": width <= plate width")
end

-- The frames must exist before the geometry tests; the class gate test drives
-- the teardown path.
local function ensureBuilt()
    UI:_InitViews()
end

-- m5 (CodeReview3): Frame:_AttachTip built its tip with
-- `CreateFrame("Frame", self.anchor)` -- the 2nd argument of CreateFrame is
-- the NAME, the parent is the 3rd (the shape every other frame in the file
-- uses, and the Shards override gets right), so the tip came out PARENTLESS:
-- a plate's tip must ride the plate's scale/strata and die with it. Latent
-- while no view sets `opts.tip` (the Shards view builds its own), so the
-- shape is proven directly here.
test("the plate tip is a CHILD of the plate, not a frame named by a frame",
function()
    local probe = Frame:new({
        name = "TipProbe", dbKey = "tipprobe",
        tip = { title = "Probe tip", body = { "one" } },
    })
    probe:_Build()
    assertNotNil(probe.tip, "opts.tip reaches _AttachTip")
    assertTrue(probe.tip:GetParent() == probe.anchor,
        "the tip hangs off the plate: CreateFrame's 3rd argument is the parent")
    local tipName = probe.tip:GetName()
    assertTrue(type(tipName) ~= "table",
        "the plate is not squeezed into the tip's NAME slot")
    -- A parentless tip would keep its mouse region when the plate hides; a
    -- child inherits the hide (the law the assertion above exists for).
    probe.anchor:Hide()
    probe.tip:EnableMouse(false)
end)

-- -------------------------------------------------------------------- init --

test("the four plates build, are named and sized, idempotent, hidden", function()
    UI:_InitViews()
    assertNotNil(Shards.anchor)
    assertEquals("ForteXorcistWarlockShardsAnchor",
        ForteXorcistWarlockShardsAnchor:GetName())
    assertNotNil(Stone.anchor)
    assertNotNil(ForteXorcistWarlockSoulstoneAnchor)
    assertNotNil(HS.anchor)
    assertNotNil(Summon.anchor)
    -- 106x20 = the original's FWSSFrame/FWHSFrame/FWSUFrame
    -- (Forte_Soulstone.xml:124, Forte_Healthstone.xml:83,
    --  Forte_Summon.xml:91).
    assertEquals(106, Shards.anchor:GetWidth())
    assertEquals(20, Shards.anchor:GetHeight())
    assertEquals(106, HS.anchor:GetWidth())
    assertEquals(20, HS.anchor:GetHeight())
    assertEquals(106, Stone.anchor:GetWidth())
    assertEquals(20, Stone.anchor:GetHeight())
    assertEquals(106, Summon.anchor:GetWidth())
    assertEquals(20, Summon.anchor:GetHeight())
    -- The plate wash: the Background tile inside the 5px Border inset
    -- (Forte_Soulstone.xml:227-230).
    assertEquals(96, Shards.plate:GetWidth())
    assertEquals(10, Shards.plate:GetHeight())
    -- The 16x16 icon at TOPLEFT (2,-2) (Forte_Soulstone.xml:156,161).
    assertEquals(16, Shards.icon:GetWidth())
    assertEquals(16, Shards.icon:GetHeight())
    -- The second-line bar: Width-2*BORDER x RowHeight = 100x12
    -- (Forte_Soulstone.lua:65,:670-671).
    assertEquals(100, Stone.row:GetWidth())
    assertEquals(12, Stone.row:GetHeight())
    -- The dark-purple plate default (Forte_Soulstone.lua:659).
    local pr, pg, pb, pa = Shards.plate:GetVertexColor()
    near3(pr, 0.31); near3(pg, 0.00); near3(pb, 0.62); near3(pa, 0.75)
    -- Idempotence: a second Init rebuilds nothing.
    UI:_InitViews()
    assertEquals(106, Stone.anchor:GetWidth())
    -- Nothing is active: every frame is hidden, no second line, and none owns
    -- a per-frame script (the driver is the one ticker, not the frames).
    assertFalse(Shards.anchor:IsShown())
    assertFalse(Stone.anchor:IsShown())
    assertFalse(HS.anchor:IsShown())
    assertFalse(Summon.anchor:IsShown())
    assertFalse(Stone.row:IsShown())
    assertNil(Stone.anchor:GetScript("OnUpdate"))
    -- The 10 Hz driver is its own frame and is ALWAYS shown (a hidden frame
    -- never receives OnUpdate).
    assertNotNil(UI._driver)
    assertEquals("ForteXorcistWarlockUIDriver", UI._driver:GetName())
    assertTrue(UI._driver:IsShown())
end)

-- The wow-ui-sim icon law (found 2026-11-02, docs/warlock-tools.md "The
-- 16x16 module icon"): the headless renderer paints a texture that lives on
-- the ANCHOR frame UNDER the whole child body (backdrop art + plate wash) --
-- a capture A/B with the icon hidden changed 0 of 256 pixels inside the
-- icon's box (the icon contributed nothing) while the same .blp as the
-- body's last-created texture changed 215 of 256. The icon is therefore the
-- PLATE BODY's child, built after the backdrop and the wash -- the shape of
-- the 2012 law too (FWSSButton is a <Frames> child created after the plate's
-- backdrop, Forte_Soulstone.xml:122-186), and the OVERLAY layer keeps the
-- real client painting it above the BACKGROUND wash. Proven to fail on the
-- old code: an anchor-parented icon fails the parent assertion.
test("every module icon rides the plate body: parent, layer, art, 16x16",
function()
    ensureBuilt()
    for _, view in ipairs({ Shards, Stone, HS, Summon }) do
        local icon = view.icon
        assertNotNil(icon, view.NAME .. ": the plate carries an icon")
        assertTrue(icon:GetParent() == view.body,
            view.NAME .. ": the icon is the BODY's child -- a texture on "
            .. "the anchor paints under the whole body in the sim")
        local layer = icon:GetDrawLayer()
        assertTrue(layer == "OVERLAY",
            view.NAME .. ": OVERLAY over the BACKGROUND plate wash")
        assertTrue(icon:IsShown(), view.NAME .. ": the icon is shown")
        local tex = icon:GetTexture()
        assertTrue(type(tex) == "string" and tex ~= ""
            and string.upper(tex) == string.upper(view.skin.IconTexture),
            view.NAME .. ": the vendored module art is set on the icon")
        assertEquals(16, icon:GetWidth())
        assertEquals(16, icon:GetHeight())
    end
    -- The Healthstone art follows the stone state on the same icon object
    -- (HS2 in the bags / HS3 not, Forte_Healthstone.lua:168,172).
    local box = { 1000 }
    local hs = WK.NewHealthstoneTracker({
        now = fakeClock(box),
        countReader = function() return 2 end,
        cooldownReader = function() return nil end,
    })
    HS:SetTracker(hs)
    hs:ReadCounts()
    HS:Update(box[1])
    assertTrue(HS.icon:IsShown())
    assertTrue(string.find(string.upper(HS.icon:GetTexture()), "HS2") ~= nil,
        "Healthstone: stones in the bags swap the icon art to HS2")
    HS:RenderIdle()
end)

-- ------------------------------------------------------------ shard plate --

test("Shard Manager: the x<n> count, the <n> total label, the source line", function()
    ensureBuilt()
    local s = WK.NewShardCounter({
        countReader = function() return nil end,
        powerReader = function() return nil end,
    })
    Shards:SetTracker(s)
    -- Never read: nothing to show.
    assertFalse(Shards:Update(1000))
    assertFalse(Shards.anchor:IsShown())
    s.count, s.source = 12, "bag"
    Shards:Update(1000)
    assertTrue(Shards.anchor:IsShown())
    -- `x<n>` (the plate's count slot, Forte_Soulstone.lua:292) and the
    -- right label `<n> total` (the plate's Info slot,
    -- Forte_Soulstone.xml:140-146; FWL.TOTAL, Localization.lua:48).
    assertEquals("x12", Shards.amountFS:GetText())
    assertEquals("12 total", Shards.infoFS:GetText())
    -- The source label rides the second line.
    assertTrue(Shards.row:IsShown())
    assertEquals("bag", Shards.nameFS:GetText())
    assertTrue(Shards.nameFS:IsShown())
    -- The power source label rides the same seam.
    s.source = "power"
    Shards:Update(1000)
    assertEquals("power", Shards.nameFS:GetText())
    -- Every label: shown, non-empty, fits its slot (count centred at x=18
    -- of a 106 plate: 30 of room; right label: 56 of room; source line: the
    -- whole bar).
    assertVisibleLabel(Shards.amountFS, "shards.amount", 30)
    assertVisibleLabel(Shards.infoFS, "shards.info", 56)
    assertVisibleLabel(Shards.nameFS, "shards.source", 98)
    -- The plate grows with the second line: 20 + (12+1)
    -- (Forte_Soulstone.lua:235 at n=1).
    assertEquals(33, Shards.body:GetHeight())
    -- A count is not time-driven: the 10 Hz ask is always false.
    assertFalse(Shards:Update(1001))
    -- Back to "never read" (a secret read leaves the count, so this is the
    -- fresh-session shape): the plate hides.
    Shards:SetTracker(WK.NewShardCounter({
        countReader = function() return nil end,
        powerReader = function() return nil end,
    }))
    Shards:Update(1002)
    assertFalse(Shards.anchor:IsShown())
end)

--- Region left/right. GetRect is the engine's live geometry and in this
--- engine answers (left, bottom, width, height) (measured in the sim
--- 2026-11-02), the accessors are the fallback.
local function horizontalExtent(o)
    local l, b, w, h
    if o.GetRect then l, b, w, h = o:GetRect() end
    if l and w and h then
        return l, l + w
    end
    return o:GetLeft(), o:GetRight()
end

test("Shard Manager: the right label fits its slot and the plate's right inset",
function()
    ensureBuilt()
    -- The widest realistic readout: a 3-digit count (bag + power, the
    -- plate's widest label). The pre-fix label carried NO width: its box
    -- was the string's own laid width (~86 of the 106 plate), its right
    -- edge reached the InfoX inset but its LEFT overran the count slot, and
    -- the plate's clip ate the label's tail on screen (`0 tota`, the
    -- manager's 2026-11-02 shot).
    local s = WK.NewShardCounter({
        countReader = function() return 999 end,
        powerReader = function() return nil end,
    })
    s.count, s.source = 999, "bag"
    Shards:SetTracker(s)
    Shards:Update(1000)
    assertTrue(Shards.anchor:IsShown())
    assertEquals("x999", Shards.amountFS:GetText())
    assertEquals("999 total", Shards.infoFS:GetText())
    local slot = Shards:InfoSlotWidth()
    nearpx(slot, SS.Width - 2 * SS.AmountX - 2 * math.abs(SS.InfoX))
    -- The string's laid width fits the visible slot.
    local w = Shards.infoFS:GetStringWidth()
    assertTrue(type(w) == "number" and w > 0 and w <= slot, string.format(
        "info %q width %.1f exceeds slot %.1f",
        Shards.infoFS:GetText(), w, slot))
    -- The label BOX is the slot: the pre-fix widthless label's box is the
    -- string's natural laid width, wider than the slot at 3-digit counts.
    local iw = Shards.infoFS:GetWidth()
    assertTrue(iw <= slot + 0.01, string.format(
        "info box %.1f wider than slot %.1f", iw, slot))
    -- The right-edge law: the label's right edge <= plate's right edge - 4
    -- (Forte_Soulstone.xml:144); the box spans the slot.
    local il, ir = horizontalExtent(Shards.infoFS)
    local al, ar = horizontalExtent(Shards.anchor)
    assertTrue(ir <= ar - 4 + 0.01, string.format(
        "info right %.1f must stay at/inside plate right - 4 (%.1f)",
        ir, ar - 4))
    assertTrue(il >= ar - 4 - slot - 0.01, string.format(
        "info left %.1f overruns the slot at the plate's left", il))
    -- The count label keeps its slot (Forte_Soulstone.xml:135): centred at
    -- plateLeft + AmountX, its laid width ends at/inside the slot's left.
    local cw = Shards.amountFS:GetStringWidth()
    assertTrue(al + SS.AmountX + cw / 2 <= ar - 4 - slot + 0.5, string.format(
        "count right %.1f is over the slot left %.1f",
        al + SS.AmountX + cw / 2, ar - 4 - slot))
    -- The ShardSize seam: the slot and the box ride the plate width, the
    -- inset law rides it too.
    Shards:SetWidth(140)
    local slot2 = Shards:InfoSlotWidth()
    assertTrue(Shards.infoFS:GetWidth() <= slot2 + 0.01,
        "the box follows the resized slot")
    local _, ir2 = horizontalExtent(Shards.infoFS)
    local _, ar2 = horizontalExtent(Shards.anchor)
    assertTrue(ir2 <= ar2 - 4 + 0.01, "the right inset is kept on resize")
    Shards:SetWidth(SS.Width)
    Shards:RenderIdle()
end)

test("Shard Manager: ShowTime off drops the labels, not the count", function()
    ensureBuilt()
    local s = WK.NewShardCounter({
        countReader = function() return 3 end,
        powerReader = function() return nil end,
    })
    s:Read()                            -- what Tools:ReadItems does on a bag event
    Shards:SetTracker(s)
    Shards:Update(1000)
    assertTrue(Shards.anchor:IsShown())
    assertEquals("x3", Shards.amountFS:GetText())
    ST:Set("Warlock", "ShowTime", false)
    Shards:Update(1000)
    assertTrue(Shards.amountFS:IsShown())
    assertFalse(Shards.infoFS:IsShown())
    assertFalse(Shards.row:IsShown())        -- the source line is label text
    ST:Set("Warlock", "ShowTime", true)
    Shards:Update(1000)
    assertTrue(Shards.infoFS:IsShown())
    assertTrue(Shards.row:IsShown())
end)

-- --------------------------------------------------------- soulstone plate --

test("Soulstone plate: no ss up, the live pair, the depleting bar", function()
    ensureBuilt()
    local box = { 1000 }
    local t = WK.NewSoulstoneTracker({
        now = fakeClock(box), duration = 1800,
    })
    Stone:SetTracker(t)
    -- The plate is the standing readout: enabled, no stone -> x0 + no ss up
    -- (Forte_Soulstone.lua:291 + Localization.lua:57), no second line, no ask.
    Stone:Update(box[1])
    assertTrue(Stone.anchor:IsShown())
    assertEquals("x0", Stone.amountFS:GetText())
    assertEquals("no ss up", Stone.infoFS:GetText())
    assertFalse(Stone.row:IsShown())
    assertFalse(Stone:Update(box[1]))
    t:OnCastSent("Create Soulstone", "Gevil")
    t:OnCast("Create Soulstone")
    assertTrue(Stone:Update(box[1]))                -- live: asks for ticks
    assertTrue(Stone.anchor:IsShown())
    assertTrue(Stone.row:IsShown())
    -- x1 (one live stone, Forte_Soulstone.lua:292), the clock in the right
    -- label (Forte_Soulstone.lua:291), the bearer at the bar's left, the
    -- clock at its right (Forte_Soulstone.xml:42-51, :14-27).
    assertEquals("x1", Stone.amountFS:GetText())
    assertEquals("30:00", Stone.infoFS:GetText())
    assertEquals("Gevil", Stone.nameFS:GetText())
    assertEquals("30:00", Stone.timeFS:GetText())
    local w = StS.Width - 2 * StS.Border          -- 100 (Forte_Soulstone.lua:65)
    nearpx(Stone.fill:GetWidth(), w)              -- fraction 1
    -- The plate body grew with the line: 20 + (12+1) (Forte_Soulstone.lua:235).
    assertEquals(33, Stone.body:GetHeight())
    -- The label pass: count slot 30, right label 56, bearer 60, clock 38.
    assertVisibleLabel(Stone.amountFS, "ss.amount", 30)
    assertVisibleLabel(Stone.infoFS, "ss.info", 56)
    assertVisibleLabel(Stone.nameFS, "ss.name", 60)
    assertVisibleLabel(Stone.timeFS, "ss.time", 38)
    -- 28:43 left of the 30:00 window.
    box[1] = 1000 + 77
    assertTrue(Stone:Update(box[1]))
    assertEquals("28:43", Stone.timeFS:GetText())
    nearpx(Stone.fill:GetWidth(),
        (1723 / 1800) * w)
    -- An unread bearer (the secret SENT target) prints the marker, the
    -- timer stands.
    local t2 = WK.NewSoulstoneTracker({ now = fakeClock(box), duration = 900 })
    Stone:SetTracker(t2)
    t2:OnCastSent("Create Soulstone", nil)
    t2:OnCast("Create Soulstone")
    Stone:Update(box[1])
    assertEquals("(target unread)", Stone.nameFS:GetText())
    assertEquals("15:00", Stone.timeFS:GetText())
    -- The window expires: the second line retires with it, the plate stays
    -- on no ss up.
    box[1] = box[1] + 901
    assertFalse(Stone:Update(box[1]))
    assertTrue(Stone.anchor:IsShown())
    assertFalse(Stone.row:IsShown())
    assertEquals("x0", Stone.amountFS:GetText())
    assertEquals("no ss up", Stone.infoFS:GetText())
    assertEquals(20, Stone.body:GetHeight())
    Stone:RenderIdle()
end)

-- ------------------------------------------------------- healthstone plate --

test("Healthstone: the Total line, the icon swap, the cooldown dim and clock", function()
    ensureBuilt()
    local box = { 2000 }
    local h = WK.NewHealthstoneTracker({
        now = fakeClock(box),
        countReader = function() return 2 end,
        cooldownReader = function() return nil end,
    })
    HS:SetTracker(h)
    -- Never read: hidden (never rendered as an empty bag).
    assertFalse(HS:Update(box[1]))
    assertFalse(HS.anchor:IsShown())
    h:ReadCounts()                      -- the bag read Tools:ReadItems drives
    HS:Update(box[1])
    assertTrue(HS.anchor:IsShown())
    -- `x2` in the count slot (Forte_Healthstone.lua:164); the icon art rides
    -- the stone state (HS2 with stones, Forte_Healthstone.lua:168).
    assertEquals("x2", HS.amountFS:GetText())
    assertEquals("Interface\\AddOns\\Forte_Core\\Textures\\HS2", HS._iconArt)
    -- The second line: `Total` at the bar's left (FWL.TOTAL,
    -- Forte_Healthstone/Localization.lua:48, Forte_Healthstone.lua:197), the
    -- count at its right (the bar Amount, Forte_Healthstone.lua:139).
    assertTrue(HS.row:IsShown())
    assertEquals("Total", HS.nameFS:GetText())
    assertEquals("2", HS.timeFS:GetText())
    nearpx(HS.fill:GetWidth(), HSS.Width - 2 * HSS.Border)
    assertEquals(1, HS.plate:GetAlpha())          -- ready: full alpha
    assertFalse(HS.infoFS:IsShown())              -- no cooldown, no clock
    assertVisibleLabel(HS.amountFS, "hs.amount", 30)
    assertVisibleLabel(HS.nameFS, "hs.total", 60)
    assertVisibleLabel(HS.timeFS, "hs.amount2", 38)
    assertFalse(HS:Update(box[1]))               -- a count asks for no tick
    -- The stone goes on cooldown: the plate dims, mm:ss in the right label,
    -- the frame asks for the 10 Hz pass.
    h.cdStart, h.cdDuration = 2000, 180
    box[1] = 2060
    assertTrue(HS:Update(box[1]))
    assertTrue(HS.infoFS:IsShown())
    assertEquals("2:00", HS.infoFS:GetText())
    assertVisibleLabel(HS.infoFS, "hs.cd", 56)
    near3(HS.plate:GetAlpha(), HSS.CooldownAlpha)
    box[1] = 2100
    HS:Update(box[1])
    assertEquals("1:20", HS.infoFS:GetText())
    -- The cooldown self-expires: full alpha, no clock, no tick ask.
    box[1] = 2181
    assertFalse(HS:Update(box[1]))
    assertFalse(HS.infoFS:IsShown())
    assertEquals(1, HS.plate:GetAlpha())
    -- A known-empty bag hides the plate (and the icon is the no-stones art,
    -- Forte_Healthstone.lua:172).
    h.count, h.present = 0, false
    HS:Update(box[1])
    assertFalse(HS.anchor:IsShown())
end)

-- ------------------------------------------------------------ summon plate --

test("Summon: the channel runs the bar and retires with the cast", function()
    ensureBuilt()
    local box = { 5000 }
    local s = WK.NewSummonTracker({
        now = fakeClock(box), channelSeconds = 5,
    })
    Summon:SetTracker(s)
    assertFalse(Summon:Update(box[1]))
    assertFalse(Summon.anchor:IsShown())
    s:OnCastSent("Ritual of Summoning", "Alice")
    assertTrue(Summon:Update(box[1]))            -- a channel asks for ticks
    assertTrue(Summon.anchor:IsShown())
    assertTrue(Summon.row:IsShown())
    assertEquals("x1", Summon.amountFS:GetText())
    assertEquals("Alice", Summon.nameFS:GetText())
    assertEquals("0:05", Summon.timeFS:GetText())
    assertEquals("0:05", Summon.infoFS:GetText())
    assertVisibleLabel(Summon.amountFS, "su.amount", 30)
    assertVisibleLabel(Summon.infoFS, "su.info", 56)
    assertVisibleLabel(Summon.nameFS, "su.name", 60)
    assertVisibleLabel(Summon.timeFS, "su.time", 38)
    local w = SuS.Width - 2 * SuS.Border
    nearpx(Summon.fill:GetWidth(), 0)
    box[1] = 5002.5
    assertTrue(Summon:Update(box[1]))
    nearpx(Summon.fill:GetWidth(), 0.5 * w)
    assertEquals("0:02", Summon.timeFS:GetText())
    -- The channel ends (the tracker retires the prediction): the plate
    -- retires with it (SU-09).
    s:End("Ritual of Summoning", "succeeded")
    assertFalse(Summon:Update(5010))
    assertFalse(Summon.anchor:IsShown())
    -- An unread target prints the marker.
    local box2 = { 6000 }
    local s2 = WK.NewSummonTracker({ now = fakeClock(box2), channelSeconds = 5 })
    Summon:SetTracker(s2)
    s2:OnCastStart("Ritual of Summoning")
    Summon:Update(6000)
    assertEquals("(target unread)", Summon.nameFS:GetText())
    assertEquals("0:05", Summon.timeFS:GetText())
    Summon:RenderIdle()
end)

-- ------------------------------------------------------------------ kick --
-- Manager regression (found live on uiforever 2026-11-02, the Hunter swing
-- bar's bug): a hidden frame never receives OnUpdate, so activity must be on
-- screen from the kick alone. No Update call in these tests.
test("a kick renders the active plates without any OnUpdate", function()
    ensureBuilt()
    UI:StopTicking()
    local box = { 9000 }
    local t = WK.NewSoulstoneTracker({ now = fakeClock(box), duration = 600 })
    Stone:SetTracker(t)
    local s = WK.NewSummonTracker({ now = fakeClock(box), channelSeconds = 5 })
    Summon:SetTracker(s)
    local h = WK.NewHealthstoneTracker({
        now = fakeClock(box), countReader = function() return 1 end,
    })
    h.read, h.count, h.present = true, 1, true   -- the injected-state shape
    HS:SetTracker(h)
    local sc = WK.NewShardCounter({
        countReader = function() return 7 end, powerReader = function() return nil end,
    })
    sc:Read()                           -- Tools:ReadItems drives this seam
    Shards:SetTracker(sc)
    assertFalse(Stone.anchor:IsShown())
    t:OnCast("Create Soulstone", "Gevil")       -- a live stone
    s:OnCastSent("Ritual of Summoning", "Alice")  -- a live channel
    local animating = UI:Kick({ "Soulstone", "Summon", "Healthstone", "Shards" },
        box[1])
    assertTrue(animating, "a live window asks for the ticker")
    assertTrue(Stone.anchor:IsShown(), "the kick must render the plate itself")
    assertTrue(Stone.row:IsShown(), "and its second line")
    assertTrue(Summon.anchor:IsShown())
    assertTrue(HS.anchor:IsShown())
    assertTrue(Shards.anchor:IsShown())
    assertNotNil(UI._driver:GetScript("OnUpdate"), "the ticker runs")
    UI:StopTicking()
    assertNil(UI._driver:GetScript("OnUpdate"))
    Stone:RenderIdle()
    Summon:RenderIdle()
    HS:RenderIdle()
    Shards:RenderIdle()
end)

-- ------------------------------------------------------------- real events --
--- The module's own event frame, driven with a real payload: the binding
--- must swallow the frame (OnEvent is (frame, event, ...)), and the payload
--- fields are forwarded unread.
local function uiHandler()
    if not UI._eventsEnabled then UI:EnableEvents() end
    local f = UI._eventFrame
    assertNotNil(f, "the event frame exists once enabled")
    local h = f:GetScript("OnEvent")
    assertEquals("function", type(h))
    return h, f
end

test("real OnEvent dispatch drives the views it is routed to", function()
    ensureBuilt()
    local h, f = uiHandler()
    -- Injected trackers so the render is the assertion, not the game.
    local saved = { Shards.Tracker, Stone.Tracker, HS.Tracker, Summon.Tracker }
    local box = { 12000 }
    local sc = WK.NewShardCounter({
        countReader = function() return 5 end,
        powerReader = function() return nil end,
    })
    sc:Read()                             -- Tools:ReadItems drives this seam
    Shards:SetTracker(sc)
    local st = WK.NewSoulstoneTracker({ now = fakeClock(box), duration = 600 })
    Stone:SetTracker(st)
    st:OnCast("Create Soulstone", "Gevil")
    UI:StopTicking()
    Stone:RenderIdle()
    Shards:RenderIdle()
    assertFalse(Stone.anchor:IsShown())
    assertFalse(Shards.anchor:IsShown())
    -- A real UNIT_SPELLCAST_SENT payload: (unitTarget, target, castGUID,
    -- spellID). The UI reads none of it; it is a kick for the soulstone.
    h(f, "UNIT_SPELLCAST_SENT", "player", "Gevil", "Cast-0-1-1", 20757)
    assertTrue(Stone.anchor:IsShown(), "the routed kick rendered the plate")
    assertTrue(Stone.row:IsShown(), "with the live second line")
    -- A real bag event reaches the shard plate (payload = the changed itemID).
    Shards:RenderIdle()
    h(f, "ITEM_COUNT_CHANGED", 5720)
    assertTrue(Shards.anchor:IsShown())
    -- An event that names none of them changes nothing.
    Shards:RenderIdle()
    h(f, "PLAYER_REGEN_DISABLED")
    assertFalse(Shards.anchor:IsShown())
    UI:StopTicking()
    Shards:RenderIdle()
    Stone:RenderIdle()
    Shards.Tracker, Stone.Tracker, HS.Tracker, Summon.Tracker =
        saved[1], saved[2], saved[3], saved[4]
end)

-- ----------------------------------------------------------- live settings --

test("Warlock settings drive the four plates live", function()
    ensureBuilt()
    assertNotNil(ST)
    assertTrue(ST:IsRegistered("Warlock"))
    -- Sizes: the plate width (Forte_Soulstone.xml:124) and the second-line
    -- bar height (Forte_Soulstone.lua:671, Forte_Summon.lua:587).
    ST:Set("Warlock", "SoulstoneWidth", 200)
    assertEquals(200, Stone.anchor:GetWidth())
    assertEquals(194, Stone.row:GetWidth())      -- Width - 2*3
    ST:Reset("Warlock", "SoulstoneWidth")
    assertEquals(106, Stone.anchor:GetWidth())
    ST:Set("Warlock", "SummonHeight", 20)
    assertEquals(20, Summon.row:GetHeight())
    ST:Reset("Warlock", "SummonHeight")
    assertEquals(12, Summon.row:GetHeight())     -- SoulstoneHeight 12
    ST:Set("Warlock", "ShardSize", 150)          -- the plate width
    assertEquals(150, Shards.anchor:GetWidth())
    assertEquals(20, Shards.anchor:GetHeight())  -- the header row stays 20
    ST:Reset("Warlock", "ShardSize")
    assertEquals(106, Shards.anchor:GetWidth())
    ST:Set("Warlock", "HealthstoneSize", 144)
    assertEquals(144, HS.anchor:GetWidth())
    ST:Reset("Warlock", "HealthstoneSize")
    assertEquals(106, HS.anchor:GetWidth())
    -- Colours.
    ST:Set("Warlock", "SoulstoneColor", { 1, 0, 0, 1 })
    local r, g, b = Stone.fill:GetVertexColor()
    near3(r, 1); near3(g, 0); near3(b, 0)
    ST:Reset("Warlock", "SoulstoneColor")
    local d = StS.BarColor
    r, g, b = Stone.fill:GetVertexColor()
    near3(r, d[1]); near3(g, d[2]); near3(b, d[3])
    ST:Set("Warlock", "ShardColor", { 0, 1, 0, 1 })
    -- The count text carries the colour law: the frame's own key wins over
    -- the General page's shared TextColor (the Reminder's shared-font law).
    -- The colour lands on the fontstring's vertex (the shipped widgets'
    -- text-colour idiom); the client's text-colour getter is a different
    -- property, so the assertion reads the one the frame writes.
    local sr, sg, sb = Shards.amountFS:GetVertexColor()
    assertTrue(sr < 0.01 and sg > 0.99 and sb < 0.01,
        string.format("shard vertex=%.2f/%.2f/%.2f own2=%s", sr, sg, sb,
            tostring(Shards._ownText and Shards._ownText[2])))
    ST:Reset("Warlock", "ShardColor")
    -- m3 (CodeReview3): the Healthstone page's Count colour had NO
    -- consumer -- the count text followed only the shared TextColor, so
    -- the picker painted nothing. Its ShardColor pair is the law: the
    -- frame's OWN colour key is the specific answer for the count.
    ST:Set("Warlock", "HealthstoneColor", { 0, 0, 1, 1 })
    local hr, hg, hb = HS.amountFS:GetVertexColor()
    assertTrue(hr < 0.01 and hg < 0.01 and hb > 0.99,
        string.format("healthstone count vertex=%.2f/%.2f/%.2f", hr, hg, hb))
    ST:Reset("Warlock", "HealthstoneColor")
    hr, hg, hb = HS.amountFS:GetVertexColor()
    assertTrue(hr > 0.99 and hg > 0.99 and hb > 0.99,
        "the recycle restores the white count")
    -- The shared plate colour reaches the PLATE washes of all four frames,
    -- never the bar fills (a plate colour can not repaint a bar).
    local beforeR = Stone.fill:GetVertexColor()
    ST:Set("Warlock", "BarColor", { 0.5, 0.5, 0.5, 1 })
    local pr = Shards.plate:GetVertexColor()
    near3(pr, 0.5)
    near3(Stone.plate:GetVertexColor(), 0.5)
    near3(Stone.fill:GetVertexColor(), beforeR)
    ST:Reset("Warlock", "BarColor")
    -- The master switch off hides every frame live.
    local box = { 20000 }
    local sc = WK.NewShardCounter({
        countReader = function() return 4 end, powerReader = function() return nil end,
    })
    sc:Read()                           -- Tools:ReadItems drives this seam
    Shards:SetTracker(sc)
    local st = WK.NewSoulstoneTracker({ now = fakeClock(box), duration = 600 })
    Stone:SetTracker(st)
    st:OnCast("Create Soulstone", "Gevil")
    Shards:Update(box[1])
    Stone:Update(box[1])
    assertTrue(Shards.anchor:IsShown())
    assertTrue(Stone.anchor:IsShown())
    ST:Set("Warlock", "Enable", false)
    Shards:Update(box[1])
    Stone:Update(box[1])
    assertFalse(Shards.anchor:IsShown())
    assertFalse(Stone.anchor:IsShown())
    ST:Set("Warlock", "Enable", true)
    Shards:Update(box[1])
    Stone:Update(box[1])
    assertTrue(Shards.anchor:IsShown())
    assertTrue(Stone.anchor:IsShown())
    -- One frame's own switch is granular to that frame.
    ST:Set("Warlock", "SoulstoneEnable", false)
    Stone:Update(box[1])
    Shards:Update(box[1])
    assertFalse(Stone.anchor:IsShown())
    assertTrue(Shards.anchor:IsShown())
    ST:Reset("Warlock", "SoulstoneEnable")
    -- The General page's shared bar font reaches the plates' texts: the URW
    -- Gothic lookalike at the original's 11 (Forte_Core.lua:2547).
    local shipped = "Interface\\AddOns\\Forte_Core\\Fonts\\URWGothic-Book.ttf"
    assertTrue(Stone.infoFS:GetFont():lower() == shipped:lower())
    assertEquals(11, StS.TextSize)
    -- A font file the client can not load is REFUSED (the shipped font
    -- validation law of Forte_Options/Forte_Hunter): the label keeps the
    -- shipped face, it does not go blank.
    ST:Set("General", "BarFont", "Interface\\AddOns\\Forte_Core\\Fonts\\NOPE.ttf")
    assertTrue(Stone.infoFS:GetFont():lower() == shipped:lower(),
        "a missing font file is refused, " .. Stone.infoFS:GetFont())
    ST:Reset("General", "BarFont")
    assertTrue(Stone.infoFS:GetFont():lower() == shipped:lower())
    Stone:RenderIdle()
    Shards:RenderIdle()
end)

-- -------------------------------------------------------------------- lock --

test("Lock: the frames publish Warlock.Lock; GlobalLock and the Cooldown bar move them", function()
    ensureBuilt()
    Stone:SetLocked(true)
    assertEquals(true, ST:Get("Warlock", "Lock"))
    ST:Set("Warlock", "Lock", false)
    assertFalse(Stone.cfg.locked)
    assertFalse(Shards.cfg.locked)
    assertFalse(Summon.cfg.locked)
    -- Locked frames are click-through: the mouse is off.
    ST:Set("Warlock", "Lock", true)
    if Stone.anchor.GetMouseEnabled then
        assertEquals(false, Stone.anchor:GetMouseEnabled())
    end
    if Stone.anchor.IsMouseEnabled then
        assertEquals(false, Stone.anchor:IsMouseEnabled())
    end
    -- The General page's Global Frame Lock (= /fx lock|unlock) drives ours.
    ST:Set("General", "GlobalLock", false)
    assertFalse(Stone.cfg.locked)
    ST:Set("General", "GlobalLock", true)
    assertTrue(Stone.cfg.locked)
    assertEquals(true, ST:Get("Warlock", "Lock"))
    -- Forte_Cooldown's published lock state (its SetLocked publish IS the
    -- lock-change hook, m4) is mirrored into the warlock frames.
    local d = FX.Cooldown and FX.Cooldown.Display
    if d and d.SetLocked then
        d:SetLocked(false)
        assertFalse(Stone.cfg.locked)
        assertFalse(Shards.cfg.locked)
        d:SetLocked(true)
        assertTrue(Stone.cfg.locked)
    end
    ST:Set("Warlock", "Lock", true)
end)

-- m1 (CodeReview3): Frame:_HookSettings registered its FOUR listeners per
-- frame on EVERY Init, and UI:OnClassChanged("WARLOCK") -- the T4/T15 class
-- round trip the suite itself drives -- re-runs _InitViews -> Init. FX.Settings
-- appends with no dedup, so each round trip added 16 more listeners; every
-- Set then fired all copies, unbounded across a session. The single-
-- registration convention (_wired in Module, _lockWired in Window, wired on
-- the Hunter page) is the law; the store seam counts it.
test("the class round trip does not multiply the frames' store listeners",
function()
    ensureBuilt()
    assertNotNil(ST.CountListeners, "the counting seam exists")
    local function total()
        -- The four listeners a wired frame registers, spread over the
        -- three modules it follows: Warlock (its keymap + Lock), General
        -- (the shared keys + GlobalLock) and Cooldown (its Lock relay).
        return ST:CountListeners("Warlock") + ST:CountListeners("General")
            + ST:CountListeners("Cooldown")
    end
    local before = total()
    assertTrue(before >= 16,
        "the four frames carry their four listeners each: " .. before)
    local savedClass = FX._playerClass
    -- Three full T4/T15 round trips: away from and back to WARLOCK, the
    -- exact calls Core's FX.RefreshPlayerClass makes.
    for _ = 1, 3 do
        UI:OnClassChanged("WARLOCK")
        UI:OnClassChanged(savedClass)
    end
    assertEquals(before, total(),
        "the listener list is stable across three round trips")
    assertEquals(savedClass, FX._playerClass)
    -- And the seam still WORKS after the guard (the guard skips
    -- re-registering, not wiring): a live Set reaches the frames.
    ST:Set("Warlock", "HealthstoneSize", 144)
    assertEquals(144, HS.anchor:GetWidth())
    ST:Reset("Warlock", "HealthstoneSize")
    assertEquals(106, HS.anchor:GetWidth())
end)

-- -------------------------------------------------------------- position --

test("a dragged position persists into FX.db.warlockUI", function()
    ensureBuilt()
    Stone.anchor:ClearAllPoints()
    Stone.anchor:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 137, -58)
    Stone:SavePosition()
    local cfg = FX.db and FX.db.warlockUI and FX.db.warlockUI.soulstone
    assertNotNil(cfg)
    assertEquals("TOPLEFT", cfg.point)
    assertEquals("TOPLEFT", cfg.relPoint)
    nearpx(cfg.x, 137)
    nearpx(cfg.y, -58)
    Stone:Reset()
    assertEquals("CENTER", cfg.point)
    nearpx(cfg.x, 60)
    nearpx(cfg.y, -215)
    Stone:ApplyPosition()
    assertEquals("CENTER", Stone.anchor:GetPoint())
end)

-- ----------------------------------------------------------------- gating --

test("the UI module follows the class (events, frames, driver)", function()
    local savedClass = FX._playerClass
    UI:OnClassChanged("WARLOCK")
    assertNotNil(UI._eventFrame)
    assertEquals("function", type(UI._eventFrame:GetScript("OnEvent")))
    assertNotNil(Shards.anchor)
    assertNotNil(Stone.anchor)
    assertTrue(UI._driver:IsShown())

    UI:OnClassChanged("HUNTER")
    assertNil(UI._eventFrame:GetScript("OnEvent"))
    assertFalse(Shards.anchor:IsShown())
    assertFalse(Stone.anchor:IsShown())
    assertFalse(HS.anchor:IsShown())
    assertFalse(Summon.anchor:IsShown())
    assertNil(UI._driver:GetScript("OnUpdate"))      -- no ticker, no work
    -- A fresh login of a non-warlock class wires nothing at all.
    local savedFrame = UI._eventFrame
    UI._eventFrame, UI._eventsEnabled = nil, false
    UI:OnEnable()
    assertFalse(UI._eventsEnabled)
    assertNil(UI._eventFrame)
    UI._eventFrame = savedFrame

    UI:OnClassChanged(savedClass)
    assertNil(UI._eventFrame:GetScript("OnEvent"))
    assertEquals(savedClass, FX._playerClass)
end)

-- ------------------------------------------------------------------ pages --

test("the four index cells have pages and build in the options window", function()
    if not (FX.Options and FX.Options.pages) then
        print("[fxui] Forte_Options is not loaded -- pages skipped")
        return
    end
    -- The module index maps ONE id per cell, so the build registers one
    -- page per cell: the index's own four warlock ids.
    local ids = { "ShardManager", "Soulstone", "Healthstone", "Summon" }
    for _, id in ipairs(ids) do
        assertNotNil(FX.Options.pages[id], "page " .. id)
        assertEquals(id, FX.Options.pages[id].id)
        assertEquals("Warlock", FX.Options.pages[id].module)
        assertEquals("Lock", FX.Options.pages[id].lockKey)
    end
    for _, id in ipairs(ids) do
        FX.Options:Open(id)
        assertEquals(true, FX.Options:IsOpen())
        assertEquals(id, FX.Options.pageId)
        local page = FX.Options.pagesBuilt[id]
        assertNotNil(page)
        assertEquals(4, #page.sections)          -- Tips + 3 built sections
        local counts = {}
        for i, sec in ipairs(page.sections) do counts[i] = #sec.widgets end
        assertEquals(0, counts[1])               -- Some Tips is text lines
        assertEquals(4, counts[2])               -- the shared Basics row
        assertTrue(counts[3] >= 1)               -- Frame Sizing
        assertEquals(3, counts[4])               -- Coloring
        assertNotNil(page.sections[1].lines[1])
        assertNotNil(FX.Options.header)
        assertNotNil(FX.Options.header.bar)
        FX.Options:Close()
        assertEquals(false, FX.Options:IsOpen())
    end
    -- The raid-wide Shard Spy cell stays dim: the module is not built.
    local spy = nil
    for i, entry in ipairs(FX.Options.INDEX) do
        if entry.id == "ShardSpy" then spy = entry end
    end
    assertNotNil(spy)
    assertNil(FX.Options.pages["ShardSpy"])
end)

-- m4 (CodeReview3): the page used to add ONE store listener of its own -- the
-- `FX.Settings:OnChange("Warlock")` mirror that routed every key to
-- `v:ApplySettings`, a method NO Warlock frame has (the grep of
-- Forte_Warlock: zero definitions), so the block was dead code and the store
-- census is the observable that says so. The frames' self-wiring
-- (`Frame:_HookSettings`, one keymap listener per frame on the module) is the
-- one live path, and the `_HookSettings` keymap is the Warlock idiom: the
-- page adds nothing.
test("the four pages add no settings listener of their own", function()
    ensureBuilt()
    if not (FX.Options and FX.Options.pages) then
        print("[fxui] Forte_Options is not loaded -- page seam skipped")
        return
    end
    assertNotNil(ST.CountListeners, "the counting seam exists")
    -- Every page has been opened by the test above, so the old mirror had
    -- its single chance to register.
    local wired = 0
    for _, v in ipairs({ Shards, Stone, HS, Summon }) do
        if v._wired then wired = wired + 1 end
    end
    assertEquals(4, wired, "every frame wired itself exactly once")
    -- The Warlock module carries the four frames' keymap listeners plus
    -- Forte_Options' ONE header lock relay (`Window.lua:710`, registered for
    -- the page's `lockKey`, `_lockWired`-guarded). The deleted page mirror
    -- would sit on top of that as a 6th.
    assertEquals(wired + 1, ST:CountListeners("Warlock"),
        "four frame listeners + the header's lock relay; the deleted page "
        .. "mirror would make it " .. (wired + 2))
    -- And the surviving path is the live one: a store write reaches a plate.
    ST:Set("Warlock", "SummonWidth", 128)
    assertEquals(128, Summon.anchor:GetWidth())
    ST:Reset("Warlock", "SummonWidth")
    assertEquals(106, Summon.anchor:GetWidth())
end)

-- ----------------------------------------------------------------- status --

test("Status prints one line per built frame", function()
    ensureBuilt()
    local lines = {}
    local realPrint = FX.Print
    FX.Print = function(msg) lines[#lines + 1] = tostring(msg) end
    UI:Status()
    FX.Print = realPrint
    assertEquals(4, #lines)
    assertContains(lines[1], "Shard Manager")
    assertContains(lines[2], "Soulstone Tracker")
    assertContains(lines[3], "Healthstone")
    assertContains(lines[4], "Summon Assistant")
    assertContains(Shards:StatusLine(), "106x20")
    assertContains(Stone:StatusLine(), "106x20")
end)

test("the clock format is the original's compact m:ss", function()
    assertEquals("0:00", Frame.FormatClock(0))
    assertEquals("0:05", Frame.FormatClock(5.4))
    assertEquals("0:59", Frame.FormatClock(59.4))
    assertEquals("1:00", Frame.FormatClock(60))
    assertEquals("28:43", Frame.FormatClock(1723))
    assertEquals("30:00", Frame.FormatClock(1800))
    assertEquals("1:00:00", Frame.FormatClock(3600))
    assertEquals("0:00", Frame.FormatClock(-5))
    assertEquals(1723, Frame.ClockKey(1723.4))
    assertEquals(-1, Frame.ClockKey(nil))
    -- The plate count format (Forte_Soulstone.lua:292).
    assertEquals("x31", Frame.FormatAmount(31))
    -- The target law.
    assertEquals("(target unread)", Frame.FormatTarget(nil))
    assertEquals("(target unread)", Frame.FormatTarget(""))
    assertEquals("Meinhertz", Frame.FormatTarget("Meinhertz"))
end)

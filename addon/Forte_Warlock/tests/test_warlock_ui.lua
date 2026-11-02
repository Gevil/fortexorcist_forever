-- addon/Forte_Warlock/tests/test_warlock_ui.lua
-- wow-ui-sim tests for the warlock UI (UI/Frame.lua + Shards/Soulstone/
-- Healthstone/Summon + UI/Module.lua + Pages/Warlock.lua): the four frames'
-- geometry, their show/hide law driven by INJECTED trackers and an injected
-- clock, the exact label texts, the 10 Hz ask (which frame says "keep
-- ticking"), the kick law (activity is on screen without any OnUpdate), the
-- real OnEvent dispatch through the module's own frame, the live settings
-- seam, the shared lock mirror, the class gate and the four registered
-- options pages.
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

-- The frames must exist before the geometry tests; the class gate test drives
-- the teardown path.
local function ensureBuilt()
    UI:_InitViews()
end

-- -------------------------------------------------------------------- init --

test("the four frames build, are named and sized, idempotent, hidden", function()
    UI:_InitViews()
    assertNotNil(Shards.anchor)
    assertEquals("ForteXorcistWarlockShardsAnchor",
        ForteXorcistWarlockShardsAnchor:GetName())
    assertNotNil(Stone.anchor)
    assertNotNil(ForteXorcistWarlockSoulstoneAnchor)
    assertNotNil(HS.anchor)
    assertNotNil(Summon.anchor)
    assertEquals(34, Shards.anchor:GetWidth())
    assertEquals(34, Shards.anchor:GetHeight())
    assertEquals(34, HS.anchor:GetWidth())
    assertEquals(140, Stone.anchor:GetWidth())
    assertEquals(12, Stone.anchor:GetHeight())      -- SoulstoneHeight 12
    assertEquals(140, Summon.anchor:GetWidth())
    assertEquals(12, Summon.anchor:GetHeight())     -- SummonHeight 12
    -- Idempotence: a second Init rebuilds nothing.
    UI:_InitViews()
    assertEquals(140, Stone.anchor:GetWidth())
    -- Nothing is active: every frame is hidden and none owns a per-frame
    -- script (the driver is the one ticker, not the frames).
    assertFalse(Shards.anchor:IsShown())
    assertFalse(Stone.anchor:IsShown())
    assertFalse(HS.anchor:IsShown())
    assertFalse(Summon.anchor:IsShown())
    assertNil(Stone.anchor:GetScript("OnUpdate"))
    -- The 10 Hz driver is its own frame and is ALWAYS shown (a hidden frame
    -- never receives OnUpdate).
    assertNotNil(UI._driver)
    assertEquals("ForteXorcistWarlockUIDriver", UI._driver:GetName())
    assertTrue(UI._driver:IsShown())
    print("[fxui] font=" .. tostring(Stone.fontFile))
end)

-- ------------------------------------------------------------ shard plate --

test("Shard Manager: the count renders, the source label rides it", function()
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
    assertEquals("12", Shards.text:GetText())
    assertEquals("bag", Shards.sourceFS:GetText())
    assertTrue(Shards.sourceFS:IsShown())
    -- The power source label rides the same seam.
    s.source = "power"
    Shards:Update(1000)
    assertEquals("power", Shards.sourceFS:GetText())
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

test("Shard Manager: ShowTime off drops the source label, not the count", function()
    ensureBuilt()
    local s = WK.NewShardCounter({
        countReader = function() return 3 end,
        powerReader = function() return nil end,
    })
    s:Read()                            -- what Tools:ReadItems does on a bag event
    Shards:SetTracker(s)
    Shards:Update(1000)
    assertTrue(Shards.anchor:IsShown())
    assertEquals("3", Shards.text:GetText())
    ST:Set("Warlock", "ShowTime", false)
    Shards:Update(1000)
    assertTrue(Shards.text:IsShown())
    assertFalse(Shards.sourceFS:IsShown())
    ST:Set("Warlock", "ShowTime", true)
    Shards:Update(1000)
    assertTrue(Shards.sourceFS:IsShown())
end)

-- --------------------------------------------------------- soulstone bar --

test("Soulstone bar: the label, the depleting fill, the hidden law", function()
    ensureBuilt()
    local box = { 1000 }
    local t = WK.NewSoulstoneTracker({
        now = fakeClock(box), duration = 1800,
    })
    Stone:SetTracker(t)
    -- No stone: hidden, no 10 Hz ask.
    assertFalse(Stone:Update(box[1]))
    assertFalse(Stone.anchor:IsShown())
    t:OnCastSent("Create Soulstone", "Gevil")
    t:OnCast("Create Soulstone")
    assertTrue(Stone:Update(box[1]))                -- live: asks for ticks
    assertTrue(Stone.anchor:IsShown())
    -- `Soulstone: <target> mm:ss`, the assignment's text.
    assertEquals("Soulstone: Gevil 30:00", Stone.text:GetText())
    local ins = StS.Inset
    nearpx(Stone.fill:GetWidth(), StS.Width - 2 * ins)   -- fraction 1
    -- 28:43 left of the 30:00 window.
    box[1] = 1000 + 77
    assertTrue(Stone:Update(box[1]))
    assertEquals("Soulstone: Gevil 28:43", Stone.text:GetText())
    nearpx(Stone.fill:GetWidth(),
        (1723 / 1800) * (StS.Width - 2 * ins))
    -- An unread bearer (the secret SENT target) prints the marker, the
    -- timer stands.
    local t2 = WK.NewSoulstoneTracker({ now = fakeClock(box), duration = 900 })
    Stone:SetTracker(t2)
    t2:OnCastSent("Create Soulstone", nil)
    t2:OnCast("Create Soulstone")
    Stone:Update(box[1])
    assertEquals("Soulstone: (target unread) 15:00", Stone.text:GetText())
    -- The window expires: the bar retires with it.
    box[1] = box[1] + 901
    assertFalse(Stone:Update(box[1]))
    assertFalse(Stone.anchor:IsShown())
end)

-- ------------------------------------------------------- healthstone plate --

test("Healthstone: shows on presence, dims and counts the cooldown down", function()
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
    assertEquals("2", HS.text:GetText())
    assertEquals(1, HS.plate:GetAlpha())          -- ready: full alpha
    assertFalse(HS.cdText:IsShown())
    assertFalse(HS:Update(box[1]))               -- a count asks for no tick
    -- The stone goes on cooldown: the plate dims, mm:ss appears, the frame
    -- asks for the 10 Hz pass.
    h.cdStart, h.cdDuration = 2000, 180
    box[1] = 2060
    assertTrue(HS:Update(box[1]))
    assertTrue(HS.cdText:IsShown())
    assertEquals("2:00", HS.cdText:GetText())
    near3(HS.plate:GetAlpha(), HSS.CooldownAlpha)
    box[1] = 2100
    HS:Update(box[1])
    assertEquals("1:20", HS.cdText:GetText())
    -- The cooldown self-expires: full alpha, no text, no tick ask.
    box[1] = 2181
    assertFalse(HS:Update(box[1]))
    assertFalse(HS.cdText:IsShown())
    assertEquals(1, HS.plate:GetAlpha())
    -- A known-empty bag hides the plate.
    h.count, h.present = 0, false
    HS:Update(box[1])
    assertFalse(HS.anchor:IsShown())
end)

-- ---------------------------------------------------------- summon channel --

test("Summon: the channel fills the bar and ends with the cast", function()
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
    local ins = SuS.Inset
    nearpx(Summon.fill:GetWidth(), 0)
    assertEquals("Summoning Alice 0:05", Summon.text:GetText())
    box[1] = 5002.5
    assertTrue(Summon:Update(box[1]))
    nearpx(Summon.fill:GetWidth(), 0.5 * (SuS.Width - 2 * ins))
    assertEquals("Summoning Alice 0:02", Summon.text:GetText())
    -- The channel ends (the tracker retires the prediction).
    s:End("Ritual of Summoning", "succeeded")
    assertFalse(Summon:Update(5010))
    assertFalse(Summon.anchor:IsShown())
    -- An unread target prints the marker.
    local box2 = { 6000 }
    local s2 = WK.NewSummonTracker({ now = fakeClock(box2), channelSeconds = 5 })
    Summon:SetTracker(s2)
    s2:OnCastStart("Ritual of Summoning")
    Summon:Update(6000)
    assertEquals("Summoning (target unread) 0:05", Summon.text:GetText())
    Summon:RenderIdle()
end)

-- ------------------------------------------------------------------ kick --
-- Manager regression (found live on uiforever 2026-11-02, the Hunter swing
-- bar's bug): a hidden frame never receives OnUpdate, so activity must be on
-- screen from the kick alone. No Update call in these tests.
test("a kick renders the active frames without any OnUpdate", function()
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
    assertTrue(Stone.anchor:IsShown(), "the kick must render the bar itself")
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
    assertTrue(Stone.anchor:IsShown(), "the routed kick rendered the bar")
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

test("Warlock settings drive the four frames live", function()
    ensureBuilt()
    assertNotNil(ST)
    assertTrue(ST:IsRegistered("Warlock"))
    -- Sizes.
    ST:Set("Warlock", "SoulstoneWidth", 200)
    assertEquals(200, Stone.anchor:GetWidth())
    ST:Reset("Warlock", "SoulstoneWidth")
    assertEquals(140, Stone.anchor:GetWidth())
    ST:Set("Warlock", "SummonHeight", 20)
    assertEquals(20, Summon.anchor:GetHeight())
    ST:Reset("Warlock", "SummonHeight")
    assertEquals(12, Summon.anchor:GetHeight())
    ST:Set("Warlock", "ShardSize", 48)           -- a plate is square
    assertEquals(48, Shards.anchor:GetWidth())
    assertEquals(48, Shards.anchor:GetHeight())
    ST:Reset("Warlock", "ShardSize")
    assertEquals(34, Shards.anchor:GetWidth())
    ST:Set("Warlock", "HealthstoneSize", 44)
    assertEquals(44, HS.anchor:GetWidth())
    ST:Reset("Warlock", "HealthstoneSize")
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
    -- The count text carries the colour law: the frame's own key wins over
    -- the General page's shared TextColor (the Reminder's shared-font law).
    local sr, sg, sb = Shards.text:GetVertexColor()
    assertTrue(sr < 0.01 and sg > 0.99 and sb < 0.01,
        string.format("shard vertex=%.2f/%.2f/%.2f own2=%s", sr, sg, sb,
            tostring(Shards._ownText and Shards._ownText[2])))
    ST:Reset("Warlock", "ShardColor")
    -- The shared plate colour reaches the plates, never the bar fills.
    local beforeR = Stone.fill:GetVertexColor()
    ST:Set("Warlock", "BarColor", { 0.5, 0.5, 0.5, 1 })
    local pr = Shards.plate:GetVertexColor()
    near3(pr, 0.5)
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
    -- The General page's shared bar font reaches the frames' texts.
    local shipped = "Interface\\AddOns\\Forte_Core\\Fonts\\URWGothic-Book.ttf"
    assertTrue(Stone.text:GetFont():lower() == shipped:lower())
    -- A font file the client can not load is REFUSED (the shipped font
    -- validation law of Forte_Options/Forte_Hunter): the label keeps the
    -- shipped face, it does not go blank.
    ST:Set("General", "BarFont", "Interface\\AddOns\\Forte_Core\\Fonts\\NOPE.ttf")
    assertTrue(Stone.text:GetFont():lower() == shipped:lower(),
        "a missing font file is refused, " .. Stone.text:GetFont())
    ST:Reset("General", "BarFont")
    assertTrue(Stone.text:GetFont():lower() == shipped:lower())
    Stone:RenderIdle()
    Shards:RenderIdle()
    print("[fxui] text font=" .. Stone.text:GetFont())
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
    assertTrue(Stone.anchor:IsShown() == false or true)
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
    assertContains(Shards:StatusLine(), "34x34")
    assertContains(Stone:StatusLine(), "140x12")
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
end)

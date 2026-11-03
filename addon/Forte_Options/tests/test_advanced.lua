-- addon/Forte_Options/tests/test_advanced.lua
-- The Advanced page (Pages/Advanced.lua) and its consumers, on the real
-- frames and through the real settings path: the page registers and its
-- module-index cell lights, every shipped default is the source's, and
-- every key of the module moves ITS consumer -- the login print
-- (Forte_Core/Core/Init.lua `PrintStartupLine`), the General page's
-- `RightClickOptions` gate on the Cooldown bar's own right-release
-- (Forte_Cooldown/UI/Timeline.lua `OnMouseUp`), each module frame's
-- `SetFrameStrata` (the Timeline's, the Splash's, the Spell Timer's, the
-- Hunter swing's, the four Warlock plates'), the window's wheel
-- (`AnimateScroll`) and its section-fold law (`ExpandSubcats` /
-- `LoadExpandSubcats`).
--
-- FAILS ON THE OLD CODE: before this wave the page does not exist (the
-- index cell is dimmed, the module is unregistered), the login print is
-- unconditional, the bar's right-release opens with no gate, no frame has a
-- `SetStrata` at all, the wheel can only jump, and a page build has no fold
-- law beyond `page.collapsed = {}`.
--
-- Every test hands its keys back to the shipped defaults and clears the
-- fold memory, so the suites that run after this one (test_options.lua
-- first) see the pages they expect.

local FX = ForteXorcist
local O = FX.Options
local S = FX.Settings

-- ============================================================ the page ====

test("Advanced: the page registers and its module's defaults are the source's",
function()
    assertNotNil(O.pages["Advanced"], "Pages/Advanced.lua registered the page")
    assertTrue(S:IsRegistered("Advanced"))
    -- The source's defaults: ShowStartupText true (Forte_Core.lua:2529),
    -- AnimateScroll false (:2477), LoadExpandSubcats true (:2531), and its
    -- one `Strata` for every frame (:2531). ExpandSubcats is the recorded
    -- ship-expanded drift (:2530 is false; the fold law is live, the shipped
    -- LOOK is the panel screenshot's -- the GlobalLock ruling).
    assertEquals(true, S:GetDefault("Advanced", "ShowStartupText"))
    assertEquals(false, S:GetDefault("Advanced", "AnimateScroll"))
    assertEquals(true, S:GetDefault("Advanced", "ExpandSubcats"))
    assertEquals(true, S:GetDefault("Advanced", "LoadExpandSubcats"))
    for _, key in ipairs({ "CooldownStrata", "SplashStrata", "TimerStrata",
        "HunterStrata", "ShardStrata", "SoulstoneStrata",
        "HealthstoneStrata", "SummonStrata" }) do
        assertEquals("MEDIUM", S:GetDefault("Advanced", key), key)
    end
end)

test("Advanced: the module-index cell lights and opens the page", function()
    O:Open("General")
    local i
    for n, entry in ipairs(O.INDEX) do
        if entry.id == "Advanced" then i = n end
    end
    assertNotNil(i, "the grid carries an Advanced cell")
    local btn = O.indexButtons[i]
    assertEquals("Advanced", btn.pageId)
    -- The cell law (UI/Window.lua RefreshIndexCells): a registered page is
    -- an enabled cell with its OnClick, the art at full alpha.
    assertEquals(true, btn:IsEnabled())
    assertNotNil(btn:GetScript("OnClick"))
    local _, _, _, a = btn.art:GetVertexColor()
    local ra = btn.art:GetAlpha()
    assertTrue(a == nil or ra == nil or ra > 0.99,
        "a built cell is not dimmed")
    btn:GetScript("OnClick")(btn)
    assertEquals("Advanced", O.pageId)
end)

test("Advanced: the page builds, every row rides the Advanced module", function()
    local page = O.pagesBuilt["Advanced"]
    assertNotNil(page, "the cell click above built it")
    local n, keys = 0, {}
    for si = 2, #page.sections do
        for _, wd in ipairs(page.sections[si].widgets) do
            n = n + 1
            assertEquals("Advanced", wd.spec.module,
                page.sections[si].title .. " row is the Advanced module's")
            keys[wd.spec.key] = true
        end
    end
    assertEquals(12, n, "4 behaviour rows + 8 strata rows")
    for _, key in ipairs({ "ShowStartupText", "AnimateScroll",
        "ExpandSubcats", "LoadExpandSubcats", "CooldownStrata",
        "SplashStrata", "TimerStrata", "HunterStrata", "ShardStrata",
        "SoulstoneStrata", "HealthstoneStrata", "SummonStrata" }) do
        assertTrue(keys[key], "the page ships a row for " .. key)
    end
end)

test("Advanced: the labels are the source's strings", function()
    O:Open("Advanced")
    local page = O.pagesBuilt["Advanced"]
    local by = {}
    for si = 2, #page.sections do
        for _, wd in ipairs(page.sections[si].widgets) do
            by[wd.spec.key] = wd.spec.label
        end
    end
    -- Forte_Core/Localization.lua :497, :500, :502, :347, :440.
    assertEquals("Show startup text", by.ShowStartupText)
    assertEquals("Expand all", by.ExpandSubcats)
    assertEquals("Load expanded", by.LoadExpandSubcats)
    assertEquals("Animate auto-scrolling", by.AnimateScroll)
    assertEquals("Frame level (strata)", by.CooldownStrata)
end)

-- ======================================================== the login line ===

test("ShowStartupText gates the login print through the store", function()
    assertNotNil(FX.PrintStartupLine, "the login print is the gated seam")
    local real = _G.DEFAULT_CHAT_FRAME
    local lines = 0
    _G.DEFAULT_CHAT_FRAME = { AddMessage = function() lines = lines + 1 end }
    S:Set("Advanced", "ShowStartupText", false)
    assertEquals(false, FX.PrintStartupLine())
    assertEquals(0, lines, "off = a silent login")
    S:Set("Advanced", "ShowStartupText", true)
    assertEquals(true, FX.PrintStartupLine())
    assertEquals(1, lines, "on = the line goes out")
    _G.DEFAULT_CHAT_FRAME = real
end)

-- ==================================================== the right-click gate ==

test("RightClickOptions gates the Cooldown bar's right-release", function()
    local D = FX.Cooldown and FX.Cooldown.Display
    assertNotNil(D, "the bar is live in every gate run")
    local release = D.anchor:GetScript("OnMouseUp")
    assertNotNil(release, "the bar carries the release handler")
    O:Close()
    assertEquals(true, S:GetDefault("General", "RightClickOptions"),
        "Forte_Core.lua:2495 ships it on")
    S:Set("General", "RightClickOptions", true)
    D:_StampPress()
    release(D.anchor, "RightButton")
    assertEquals(true, O:IsOpen(), "on = the release opens the window")
    assertEquals("Cooldown", O.pageId)
    O:Close()
    S:Set("General", "RightClickOptions", false)
    D:_StampPress()
    release(D.anchor, "RightButton")
    assertEquals(false, O:IsOpen(), "off = the bar is silent")
    S:Reset("General", "RightClickOptions")
    D:_StampPress()
    release(D.anchor, "RightButton")
    assertEquals(true, O:IsOpen(), "the recycle opens it again")
    O:Close()
end)

-- ================================================================ strata ====

--- Drive one frame's strata through the real settings path. The frame's
--- `SetFrameStrata` is recorded (and restored): the assertion is that the
--- module's seam calls the catalog method with the name the store carries,
--- and that a name outside the eight never reaches the frame.
local function strataDrives(key, frame, label)
    -- m5 (CodeReview6): the recorder below REPLACES the catalog method, and
    -- every production call is presence-guarded (`if self.anchor
    -- .SetFrameStrata`) -- if the client frame lacked the method the suite
    -- would be silent on the real leg. Pin its presence BEFORE replacing
    -- (the IsMouseEnabled-probe convention, test_splash.lua).
    assertNotNil(frame.SetFrameStrata,
        label .. ": the client frame carries SetFrameStrata")
    local rec = {}
    local real = frame.SetFrameStrata
    frame.SetFrameStrata = function(_, name) rec[#rec + 1] = name end
    S:Set("Advanced", key, "HIGH")
    assertEquals("HIGH", rec[#rec], label .. ": the store drives the frame")
    S:Set("Advanced", key, "NOT_A_STRATA")
    assertEquals("HIGH", rec[#rec], label .. ": a name outside the eight is ignored")
    S:Reset("Advanced", key)
    assertEquals("MEDIUM", rec[#rec], label .. ": the recycle reaches the frame")
    frame.SetFrameStrata = real
    -- Leave the frame where the shipped default puts it, for real.
    S:Set("Advanced", key, "MEDIUM")
end

test("CooldownStrata drives the cooldown bar's SetFrameStrata", function()
    local D = FX.Cooldown and FX.Cooldown.Display
    assertNotNil(D and D.SetStrata, "the bar has the seam")
    strataDrives("CooldownStrata", D.anchor, "the bar")
end)

test("SplashStrata drives the Secondary Splash window's SetFrameStrata",
function()
    local SP = FX.Cooldown and FX.Cooldown.Splash
    assertNotNil(SP and SP.SetStrata, "the splash has the seam")
    strataDrives("SplashStrata", SP.anchor, "the splash")
end)

test("TimerStrata drives the Spell Timer panel's SetFrameStrata", function()
    local m = FX.Timer and FX.Timer.Module
    local d = FX.Timer and FX.Timer.Display
    assertNotNil(m and m.SetStrata, "the module has the seam")
    assertNotNil(d and d.SetStrata, "and the panel has its own")
    strataDrives("TimerStrata", d.anchor, "the panel")
end)

test("HunterStrata drives the swing bar's SetFrameStrata", function()
    local SW = FX.Hunter and FX.Hunter.Swing
    assertNotNil(SW and SW.SetStrata, "the bar has the seam")
    -- M4 (CodeReview6): the old leg short-circuited on the gate's
    -- (non-Hunter) profile and never drove the store -- the gate passed at
    -- 707 with the leg dark. Build the frame on EVERY profile (Init is
    -- idempotent; test_swing_rightclick.lua's ensureBuilt rides the same
    -- call) so the live seam is really driven. The drive below is the fail-
    -- on-the-old-code proof: the swing's _WireSettings wired Hunter /
    -- Cooldown / General only, so on the old code S:Set("Advanced",
    -- "HunterStrata", "HIGH") moved the store and fired ZERO listeners on
    -- the bar -- rec stays empty, the equality raises.
    SW:Init()
    assertNotNil(SW.anchor, "the swing bar is built in this suite")
    strataDrives("HunterStrata", SW.anchor, "the swing bar")
end)

test("the four Warlock plates carry the strata seam and their keys", function()
    local F = FX.Warlock and FX.Warlock.Frame
    assertNotNil(F and F.SetStrata, "the shared plate base has the seam")
    local byName = {
        Shards = "ShardStrata", Soulstone = "SoulstoneStrata",
        Healthstone = "HealthstoneStrata", Summon = "SummonStrata",
    }
    for name, key in pairs(byName) do
        local plate = FX.Warlock[name]
        assertNotNil(plate, name .. " is registered")
        assertNotNil(plate.SetStrata, name .. " carries the seam")
        assertEquals(key, plate.opts and plate.opts.advancedKey,
            name .. " reads the Advanced page's " .. key)
        if plate.anchor then
            strataDrives(key, plate.anchor, name)
        end
    end
end)

-- ======================================================== AnimateScroll ====

test("AnimateScroll: off the wheel jumps, on it rides and retires", function()
    O:Open("Cooldown")
    assertTrue(O.contentHeight > O.viewport:GetHeight(),
        "the Cooldown page overflows the viewport")
    local maxScroll = O.contentHeight - O.viewport:GetHeight()
    local want = math.min(maxScroll, 240)

    -- Off (the shipped default, Forte_Core.lua:2477): one call, all the way.
    S:Set("Advanced", "AnimateScroll", false)
    O:Scroll(-want)
    assertEquals(want, O._scroll)
    assertNil(O.window:GetScript("OnUpdate"), "off installs no driver")

    S:Set("Advanced", "AnimateScroll", false)
    O:Scroll(4000)                        -- the instant way back to the top
    assertEquals(0, O._scroll)
    S:Set("Advanced", "AnimateScroll", true)
    O:Scroll(-want)                       -- from the top toward `want`
    assertNotNil(O._scrollTarget, "the wheel left a target")
    assertEquals(0, O._scroll, "and the content has not arrived yet")
    local step = O.window:GetScript("OnUpdate")
    assertNotNil(step, "the window carries the driver while it rides")
    local guard = 0
    while O._scrollTarget and guard < 400 do
        step(O.window, 0.05)
        guard = guard + 1
    end
    assertEquals(want, O._scroll)
    assertNil(O.window:GetScript("OnUpdate"), "the driver retires at the target")
    S:Set("Advanced", "AnimateScroll", false)
    O:Close()
end)

-- ================================================ ExpandSubcats / Load ====

local function sectionOf(pageId, title)
    for _, sec in ipairs(O.pagesBuilt[pageId].sections) do
        if sec.title == title then return sec end
    end
end

test("ExpandSubcats is the fold law of a fresh page build", function()
    -- The page has "Some Tips", "Basics" and deeper sections.
    local foldPage = "Cooldown"
    S:Set("Advanced", "LoadExpandSubcats", false)   -- the pure default path
    S:Set("Advanced", "ExpandSubcats", true)
    O:InvalidatePage(foldPage)
    O:Open(foldPage)
    local wide = O.pagesBuilt[foldPage]
    assertNotNil(sectionOf(foldPage, "Basics"), "the page has a Basics")
    assertEquals(false, sectionOf(foldPage, "Basics").bar.collapsed,
        "Expand all: Basics open")
    assertEquals(false, sectionOf(foldPage, "Frame Appearance").bar.collapsed,
        "Expand all: a deep section open")

    S:Set("Advanced", "ExpandSubcats", false)
    O:InvalidatePage(foldPage)
    O:Open(foldPage)
    assertEquals(true, sectionOf(foldPage, "Some Tips").bar.collapsed
        == false, "the tips line of a page never folds")
    assertEquals(false, sectionOf(foldPage, "Basics").bar.collapsed,
        "folded by default EXCEPT from the 'Basics' (the option's own words)")
    assertEquals(true, sectionOf(foldPage, "Frame Appearance").bar.collapsed,
        "off: a deep section opens folded")
    assertEquals(false, sectionOf(foldPage, "Frame Appearance").content:IsShown(),
        "and its content is hidden")
end)

test("LoadExpanded remembers a fold of mine; off it is this session's only",
function()
    local foldPage = "Cooldown"
    S:Set("Advanced", "LoadExpandSubcats", true)     -- the source default
    S:Set("Advanced", "ExpandSubcats", false)        -- fold for this test
    O:InvalidatePage(foldPage)
    O:Open(foldPage)
    local deep = sectionOf(foldPage, "Frame Appearance")
    -- It opens folded (ExpandSubcats off): unfold it by hand.
    assertEquals(true, deep.bar.collapsed)
    deep.bar.bar:GetScript("OnClick")(deep.bar.bar, "LeftButton")
    assertEquals(false, deep.bar.collapsed)
    local mem = FX.db and FX.db.optionsExpanded
    assertNotNil(mem, "the fold memory lives in the SavedVariables row")
    assertEquals(false, mem[foldPage]["Frame Appearance"],
        "Load expanded on: the fold is recorded")

    -- The remembered state wins over the (off) Expand-all default.
    O:InvalidatePage(foldPage)
    O:Open(foldPage)
    assertEquals(false, sectionOf(foldPage, "Frame Appearance").bar.collapsed,
        "the remembered state is what the rebuild opens with")

    -- Load expanded OFF: a fold is not remembered, and the memory is not
    -- consulted -- the rebuild follows ExpandSubcats.
    S:Set("Advanced", "LoadExpandSubcats", false)
    local basics = sectionOf(foldPage, "Basics")
    basics.bar.bar:GetScript("OnClick")(basics.bar.bar, "LeftButton")
    assertEquals(true, basics.bar.collapsed, "folded by hand")
    O:InvalidatePage(foldPage)
    O:Open(foldPage)
    assertEquals(false, sectionOf(foldPage, "Basics").bar.collapsed,
        "off: the fold is this page's only, the rebuild follows Expand all")

    -- Hand every key and the memory back.
    S:Reset("Advanced", "ExpandSubcats")
    S:Reset("Advanced", "LoadExpandSubcats")
    if FX.db then FX.db.optionsExpanded = {} end
    O:InvalidatePage(foldPage)
    O:InvalidatePage("Advanced")
    O:Open("General")
    O:Close()
end)

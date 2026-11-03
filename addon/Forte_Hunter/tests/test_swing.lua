-- addon/Forte_Hunter/tests/test_swing.lua
-- wow-ui-sim tests for the Hunter UI (UI/Swing.lua, UI/Reminder.lua,
-- Pages/Hunter.lua): the Auto Shot swing bar geometry driven by an injected
-- clock, its idle/ticker law, the aspect reminder's Missing() gate and
-- pulse, the live settings seam (FX.Settings -> the frames), the shared lock
-- convention, the class gate and the registered options page.
--
-- Every tracker here is INJECTED (Swing:SetTracker / Reminder:SetAspects):
-- no real time, no combat driving, no real aura read. The sim profile is not
-- a Hunter, so the UI module's login gate never fires in the gate run --
-- Init()/OnClassChanged("HUNTER") are driven directly (the established
-- pattern of Forte_Cooldown/tests/test_timeline.lua).

local FX = ForteXorcist
local Swing = FX.Hunter.Swing
local Reminder = FX.Hunter.Reminder
local UI = FX.Hunter.UI
local S = FX.Hunter.SwingSkin
local RS = FX.Hunter.ReminderSkin
local ST = FX.Settings

local function near(actual, expected)
    return assertTrue(math.abs(actual - expected) < 1e-6)
end
-- Frame geometry round-trips float32 in the sim; the acceptance's tolerance.
local function nearpx(actual, expected)
    return assertTrue(math.abs(actual - expected) <= 0.5)
end
local function near3(actual, expected)
    return assertTrue(math.abs(actual - expected) < 1e-3)
end

local function fakeTracker(nowBox)
    return FX.Hunter.NewSwingTracker({
        now = function() return nowBox[1] end,
        speedReader = function() return nil end,
        rangedType = 2,
    })
end

-- The whole file is the geometry-LAW suite: it reads the drawn fill width,
-- which is the v2 10 Hz SetSize law. Wave I-3 added the engine-armed fill
-- beside it (UI/Swing.lua's Fill law; its default posture is this same lua
-- path, and the flip of that default is a launch-day probe), so the mode is
-- pinned here explicitly: this file keeps pinning the law no matter which
-- path the module defaults to. The engine path, its arms and its parity
-- with this law are tests/test_swing3.lua's subject.
Swing:SetFillEngineMode("lua")
assertFalse(Swing:UsesEngineFill())

-- ---------------------------------------------------------------- Swing bar --

test("Init builds the 200x12 swing bar, idempotent, hidden while idle", function()
    Swing:Init()
    assertNotNil(Swing.anchor)
    assertNotNil(ForteXorcistHunterSwingAnchor)
    assertEquals("ForteXorcistHunterSwingAnchor",
        ForteXorcistHunterSwingAnchor:GetName())
    assertEquals(200, Swing.anchor:GetWidth())
    assertEquals(12, Swing.anchor:GetHeight())
    -- Idempotence: a second Init rebuilds nothing.
    Swing:Init()
    assertEquals(200, Swing.anchor:GetWidth())
    -- Idle: no bar, no per-frame script, no fill.
    assertFalse(Swing.anchor:IsShown())
    assertNil(Swing.anchor:GetScript("OnUpdate"))
    assertEquals(0, Swing.fill:GetWidth())
    print("[swing] font=" .. tostring(Swing.fontFile))
end)

test("fill width = fraction x width at 0 / 0.5 / 1 (injected clock)", function()
    local clock = { 1000 }
    local t = fakeTracker(clock)
    Swing:SetTracker(t)
    -- The single-phase fallback mode: the pre-v2 geometry law.
    Swing:SetShowSafeWindow(false)
    t:OnSwingStart(2.0, 2)                       -- a 2.0 s ranged swing
    local W = S.Width
    assertEquals(200, W)

    -- fraction 0: the bar is up, the fill has zero width.
    assertTrue(Swing:Update(clock[1]))
    assertTrue(Swing.anchor:IsShown())
    nearpx(Swing.fill:GetWidth(), 0)
    nearpx(Swing.fill:GetHeight(), S.Height)

    -- fraction 0.5: half the bar.
    clock[1] = 1001
    assertTrue(Swing:Update(clock[1]))
    nearpx(Swing.fill:GetWidth(), W * 0.5)

    -- fraction -> 1: the fill spans (nearly) the whole bar. Progress
    -- finalises the swing exactly at start + duration, so the last sample
    -- is the instant BEFORE completion.
    clock[1] = 1001.9999
    assertTrue(Swing:Update(clock[1]))
    nearpx(Swing.fill:GetWidth(), W * ((clock[1] - 1000) / 2.0))
    nearpx(Swing.fill:GetWidth(), W)
    Swing:SetShowSafeWindow(true)
end)

test("the remaining text prints tenths and rides the right edge", function()
    local clock = { 1000 }
    local t = fakeTracker(clock)
    Swing:SetTracker(t)
    t:OnSwingStart(2.0, 2)
    Swing:Update(clock[1])
    -- 2.0 s left -> "2.0"
    assertEquals("2.0", Swing.text:GetText())
    clock[1] = 1001
    Swing:Update(clock[1])
    assertEquals("1.0", Swing.text:GetText())
    clock[1] = 1001.5
    Swing:Update(clock[1])
    assertEquals("0.5", Swing.text:GetText())
    -- Right-aligned inside the bar.
    assertEquals("RIGHT", Swing.text:GetJustifyH())
    local point = Swing.text:GetPoint()
    assertEquals("RIGHT", point)
    -- The text formatter's own law (m:ss past a minute, tenths below).
    assertEquals("59.9", Swing.FormatRemaining(59.94))
    assertEquals("60.0", Swing.FormatRemaining(59.96))
    assertEquals("1:00", Swing.FormatRemaining(60))
    assertEquals("1:30", Swing.FormatRemaining(90.2))
end)

test("the bar hides after completion and the OnUpdate script is gone", function()
    local clock = { 1000 }
    local t = fakeTracker(clock)
    Swing:SetTracker(t)
    t:OnSwingStart(2.0, 2)
    assertTrue(Swing:Update(clock[1]))
    assertTrue(Swing.anchor:IsShown())
    clock[1] = 1002                                -- completes exactly here
    assertFalse(Swing:Update(clock[1]))
    assertFalse(Swing.anchor:IsShown())
    assertNil(Swing.anchor:GetScript("OnUpdate"))
    assertFalse(Swing:Update(clock[1]))            -- stays idle
    assertFalse(Swing.anchor:IsShown())
    -- A fresh swing brings it back (single-phase fill law).
    Swing:SetShowSafeWindow(false)
    t:OnSwingStart(2.0, 2)
    assertTrue(Swing:Update(clock[1]))
    assertTrue(Swing.anchor:IsShown())
    nearpx(Swing.fill:GetWidth(), 0)
    Swing:SetShowSafeWindow(true)
end)

test("the 10 Hz OnUpdate exists only while a swing runs", function()
    local t = FX.Hunter.NewSwingTracker({
        now = function() return GetTime() end,
        speedReader = function() return nil end,
        rangedType = 2,
    })
    Swing:SetTracker(t)
    Swing:RenderIdle()
    assertNil(Swing.anchor:GetScript("OnUpdate"))   -- idle: no script
    t:OnSwingStart(600, 2)                          -- a long, live swing
    Swing:Kick()
    assertNotNil(Swing.anchor:GetScript("OnUpdate"))
    Swing:RenderIdle()
    assertNil(Swing.anchor:GetScript("OnUpdate"))   -- idle: the script is unset
    -- A kick while the tracker is still mid-swing restarts the ticker: the
    -- self-heal path (an event arrived, the swing is live, the bar renders).
    Swing:Kick()
    assertNotNil(Swing.anchor:GetScript("OnUpdate"))
    Swing:RenderIdle()
    assertNil(Swing.anchor:GetScript("OnUpdate"))
    -- Once the tracker itself reports idle, a kick is a no-op.
    t:OnSwingStart(1.0, 2)
    assertNil(t:Progress(GetTime() + 5))            -- observes completion
    Swing:Kick()
    assertNil(Swing.anchor:GetScript("OnUpdate"))
end)

-- Manager regression, found live on uiforever 2026-11-02: a hidden frame never
-- receives OnUpdate, so a bar that waits for its own OnUpdate to Show() itself
-- never appears in a client. The kick path alone (no Update call here) must
-- leave the bar shown with the right fill.
test("a kick on a live swing shows the bar immediately (no OnUpdate needed)", function()
    -- Real clock, exactly like the production tracker (StartTicking renders at GetTime()).
    local t = FX.Hunter.NewSwingTracker({
        now = function() return GetTime() end,
        speedReader = function() return nil end,
        rangedType = 2,
    })
    Swing:SetTracker(t)
    Swing:RenderIdle()
    assertFalse(Swing.anchor:IsShown())
    t:OnSwingStart(600, 2)                            -- a long, live swing
    Swing:Kick()                                      -- the event path, nothing else
    assertTrue(Swing.anchor:IsShown(), "the kick must render the bar itself")
    assertTrue(Swing.fill:GetWidth() >= 0)
    -- Same cleanup as the ticker test: idle again, script gone, text cleared.
    t.active = false
    Swing:RenderIdle()
    assertNil(Swing.anchor:GetScript("OnUpdate"))
end)

test("ShowTime off drops the text; the fill keeps running", function()
    local clock = { 1000 }
    local t = fakeTracker(clock)
    Swing:SetTracker(t)
    Swing:SetShowTime(false)
    Swing:SetShowSafeWindow(false)               -- the single-phase fill law
    t:OnSwingStart(2.0, 2)
    assertTrue(Swing:Update(clock[1]))
    assertFalse(Swing.text:IsShown())
    assertEquals("", Swing.text:GetText())
    clock[1] = 1001
    assertTrue(Swing:Update(clock[1]))
    nearpx(Swing.fill:GetWidth(), S.Width * 0.5)
    Swing:SetShowTime(true)
    clock[1] = 1001.5
    assertTrue(Swing:Update(clock[1]))
    assertTrue(Swing.text:IsShown())
    assertEquals("0.5", Swing.text:GetText())
    Swing:SetShowSafeWindow(true)
end)

test("Enable off hides the bar mid-swing", function()
    local clock = { 1000 }
    local t = fakeTracker(clock)
    Swing:SetTracker(t)
    t:OnSwingStart(2.0, 2)
    assertTrue(Swing:Update(clock[1]))
    assertTrue(Swing.anchor:IsShown())
    Swing:SetEnabled(false)
    assertFalse(Swing.anchor:IsShown())
    assertFalse(Swing:Update(clock[1]))
    Swing:SetEnabled(true)
    assertTrue(Swing:Update(clock[1]))
    assertTrue(Swing.anchor:IsShown())
end)

test("the dragged position persists into FX.db.hunterSwing", function()
    Swing.anchor:ClearAllPoints()
    Swing.anchor:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 137, -58)
    Swing:SavePosition()
    local cfg = FX.db and FX.db.hunterSwing
    assertNotNil(cfg)
    assertEquals("TOPLEFT", cfg.point)
    assertEquals("TOPLEFT", cfg.relPoint)
    nearpx(cfg.x, 137)
    nearpx(cfg.y, -58)
    Swing:Reset()
    assertEquals("CENTER", cfg.point)
    nearpx(cfg.x, 0)
    nearpx(cfg.y, -175)
    Swing:ApplyPosition()
    local point = Swing.anchor:GetPoint()
    assertEquals("CENTER", point)
end)

-- ---------------------------------------------------------------- Reminder --

test("Init builds the 32x32 reminder, hidden while no aspect is missing", function()
    Reminder:Init()
    assertNotNil(Reminder.anchor)
    assertNotNil(ForteXorcistHunterReminderAnchor)
    assertEquals("ForteXorcistHunterReminderAnchor",
        ForteXorcistHunterReminderAnchor:GetName())
    assertEquals(32, Reminder.anchor:GetWidth())
    assertEquals(32, Reminder.anchor:GetHeight())
    Reminder:Init()
    assertEquals(32, Reminder.anchor:GetWidth())
    -- Click-through chrome: the frame never takes mouse input.
    local f = Reminder.anchor
    if f.GetMouseEnabled then
        assertEquals(false, f:GetMouseEnabled())
    end
    if f.IsMouseEnabled then
        assertEquals(false, f:IsMouseEnabled())
    end
    Reminder:HideNow()
    assertFalse(Reminder.anchor:IsShown())
    assertNil(Reminder.anchor:GetScript("OnUpdate"))
end)

test("the reminder shows ONLY while Missing() (out of combat, none worn)", function()
    local inCombat = false
    local fake = FX.Hunter.NewAspectTracker({
        names = FX.Hunter.Tools.aspectNames,
        inCombat = function() return inCombat end,
    })
    local saved = Reminder.Aspects
    Reminder:SetAspects(fake)

    Reminder:Refresh(1000)                 -- out of combat, nothing worn
    assertTrue(Reminder.anchor:IsShown())
    assertNotNil(Reminder.anchor:GetScript("OnUpdate"))   -- pulse runs

    inCombat = true
    Reminder:Refresh(1000.1)               -- in combat: silent
    assertFalse(Reminder.anchor:IsShown())
    assertNil(Reminder.anchor:GetScript("OnUpdate"))

    inCombat = false
    fake:OnCast("Aspect of the Hawk")
    Reminder:Refresh(1000.2)               -- an aspect is worn: silent
    assertFalse(Reminder.anchor:IsShown())

    fake:Reconcile(function() return false end)   -- the buff dropped
    Reminder:Refresh(1000.3)
    assertTrue(Reminder.anchor:IsShown())

    Reminder:StopTicking()
    Reminder:SetAspects(saved)
end)

test("the icon rides the last-known aspect, else the generic first", function()
    local fresh = FX.Hunter.NewAspectTracker({
        names = FX.Hunter.Tools.aspectNames,
        inCombat = function() return false end,
    })
    local saved = Reminder.Aspects
    Reminder:SetAspects(fresh)
    Reminder._lastAspect = nil
    -- Never cast one: the generic first aspect of the derived list.
    assertEquals(FX.Hunter.Tools.aspectNames[1], Reminder:IconName())
    fresh:OnCast("Aspect of the Cheetah")
    assertEquals("Aspect of the Cheetah", Reminder:IconName())
    fresh:Reconcile(function() return false end)     -- cleared
    assertNil(fresh:Current())
    -- The last-known aspect survives the clear (the icon stays familiar).
    assertEquals("Aspect of the Cheetah", Reminder:IconName())
    Reminder:SetAspects(saved)
end)

test("the pulse breathes between PulseMin and PulseMax", function()
    local fake = FX.Hunter.NewAspectTracker({
        names = FX.Hunter.Tools.aspectNames,
        inCombat = function() return false end,
    })
    local saved = Reminder.Aspects
    Reminder:SetAspects(fake)
    Reminder:Refresh(1000)
    assertTrue(Reminder.anchor:IsShown())
    Reminder:StopTicking()               -- drive the pulse by hand
    Reminder._anchor0 = 1000
    local a0 = Reminder:UpdateAlpha(1000)
    near(a0, RS.PulseMin)
    near3(Reminder.anchor:GetAlpha(), RS.PulseMin)
    local a1 = Reminder:UpdateAlpha(1000 + RS.PulsePeriod * 0.5)
    near(a1, RS.PulseMax)
    near3(Reminder.anchor:GetAlpha(), RS.PulseMax)
    -- Mid-breath sits strictly between the endpoints.
    local a2 = Reminder:UpdateAlpha(1000 + RS.PulsePeriod * 0.25)
    assertTrue(a2 > RS.PulseMin and a2 < RS.PulseMax)
    Reminder:HideNow()
    assertFalse(Reminder.anchor:IsShown())
    Reminder:SetAspects(saved)
end)

-- ----------------------------------------------------------- live settings --

test("Hunter settings drive the frames live", function()
    assertNotNil(ST)
    assertTrue(ST:IsRegistered("Hunter"))
    local w0 = Swing.anchor:GetWidth()
    ST:Set("Hunter", "Width", 320)
    assertEquals(320, Swing.anchor:GetWidth())
    ST:Set("Hunter", "Width", w0)
    assertEquals(w0, Swing.anchor:GetWidth())

    local h0 = Swing.anchor:GetHeight()
    ST:Set("Hunter", "Height", 20)
    assertEquals(20, Swing.anchor:GetHeight())
    ST:Set("Hunter", "Height", h0)
    assertEquals(h0, Swing.anchor:GetHeight())

    ST:Set("Hunter", "BarColor", { 1, 0, 0, 1 })
    local r, g, b = Swing.fill:GetVertexColor()
    near3(r, 1); near3(g, 0); near3(b, 0)
    -- Back to the registered default through the store (Reset writes the
    -- default THROUGH Set, so the bar self-heals the same way a recycle does).
    ST:Reset("Hunter", "BarColor")
    local d = FX.Hunter.SwingSkin.BarColor
    local r2, g2, b2 = Swing.fill:GetVertexColor()
    near3(r2, d[1]); near3(g2, d[2]); near3(b2, d[3])

    -- Enable off hides the bar live, on shows it on the next swing.
    local eclock = { 3000 }
    local et = fakeTracker(eclock)
    Swing:SetTracker(et)
    et:OnSwingStart(2.0, 2)
    assertTrue(Swing:Update(eclock[1]))
    assertTrue(Swing.anchor:IsShown())
    ST:Set("Hunter", "Enable", false)
    assertFalse(Swing.anchor:IsShown())
    assertFalse(Swing:Update(eclock[1]))
    assertNil(Swing.anchor:GetScript("OnUpdate"))
    ST:Set("Hunter", "Enable", true)
    assertTrue(Swing:Update(eclock[1]))
    assertTrue(Swing.anchor:IsShown())
    Swing:RenderIdle()

    -- The reminder's own keys.
    ST:Set("Hunter", "ReminderSize", 48)
    assertEquals(48, Reminder.anchor:GetWidth())
    assertEquals(48, Reminder.anchor:GetHeight())
    ST:Set("Hunter", "ReminderSize", 32)
    assertEquals(32, Reminder.anchor:GetWidth())
    ST:Set("Hunter", "ReminderColor", { 0, 1, 0, 1 })
    local ir, ig, ib = Reminder.icon:GetVertexColor()
    near3(ir, 0); near3(ig, 1); near3(ib, 0)
    ST:Set("Hunter", "ReminderColor", { 1, 1, 1, 1 })

    ST:Set("Hunter", "ShowTime", false)
    -- A live swing to drive the bar with the text option off.
    local clock = { 2000 }
    local t = fakeTracker(clock)
    Swing:SetTracker(t)
    t:OnSwingStart(2.0, 2)
    assertTrue(Swing:Update(clock[1]))
    assertTrue(Swing.anchor:IsShown())
    assertFalse(Swing.text:IsShown())
    ST:Set("Hunter", "ShowTime", true)
    clock[1] = 2001
    assertTrue(Swing:Update(clock[1]))
    assertTrue(Swing.text:IsShown())
    assertEquals("1.0", Swing.text:GetText())
    Swing:RenderIdle()

    ST:Set("Hunter", "EnableReminder", false)
    Reminder:Refresh()
    assertFalse(Reminder.anchor:IsShown())
    ST:Set("Hunter", "EnableReminder", true)
end)

test("the fill's default colour is the Cooldown Spell category, full alpha",
function()
    -- Polish pass 2026-11-02 defect 3: the 1,1,1 a 0.20 fill over the
    -- Aluminium texture was all but invisible. The default is now the
    -- Forte_Cooldown timeline's Spell category colour at FULL alpha.
    local sc = FX.Cooldown and FX.Cooldown.TimelineSkin
        and FX.Cooldown.TimelineSkin.Colors and FX.Cooldown.TimelineSkin.Colors.Spell
    assertNotNil(sc)
    local d = ST:GetDefault("Hunter", "BarColor")
    assertNotNil(d)
    near3(d[1], sc[1]); near3(d[2], sc[2]); near3(d[3], sc[3])
    near3(d[4], 1)                                   -- full alpha
    -- The module skin and the store default are ONE truth (the page reads
    -- the skin), and the live fill rides them.
    near3(FX.Hunter.SwingSkin.BarColor[2], sc[2])
    local r, g, b, a = Swing.fill:GetVertexColor()
    near3(r, sc[1]); near3(g, sc[2]); near3(b, sc[3]); near3(a, 1)
    -- The BACKGROUND default is untouched: the Classic black a 0.50.
    near3(ST:GetDefault("Hunter", "BgColor")[4], 0.50)
    print(string.format("[swing] fill=%.2f,%.2f,%.2f a=%.2f bgA=%.2f",
        r, g, b, a, ST:GetDefault("Hunter", "BgColor")[4]))
end)

test("the General BarFont drives the swing text live", function()
    local shipped = "Interface\\AddOns\\Forte_Core\\Fonts\\URWGothic-Book.ttf"
    assertNotNil(Swing.text)
    -- The options file is the vendored one the General page registers, and
    -- login applied it through this very seam (ApplyStoredSettings).
    assertEquals(shipped, ST:Get("General", "BarFont"))
    assertTrue(Swing.text:GetFont():lower() == shipped:lower())
    -- General -> Swing:SetFont -> validateFontFile + applyFont (the sim's
    -- font loader accepts every path CreateFont takes, so what this proves
    -- is the live re-apply of the bar's own fontstring).
    ST:Set("General", "BarFont", "Interface\\AddOns\\Forte_Core\\Fonts\\NOPE.ttf")
    assertTrue(Swing.text:GetFont():lower()
        == "interface\\addons\\forte_core\\fonts\\nope.ttf")
    ST:Reset("General", "BarFont")
    assertTrue(Swing.text:GetFont():lower() == shipped:lower())
    print("[swing] text font=" .. Swing.text:GetFont())
end)

test("Lock: the bar publishes Hunter.Lock; GlobalLock and the Cooldown bar move it", function()
    Swing:SetLocked(true)
    assertEquals(true, ST:Get("Hunter", "Lock"))
    -- Unlocked: the frame is movable (drag possible).
    ST:Set("Hunter", "Lock", false)
    assertFalse(Swing.cfg.locked)
    -- The General page's Global Frame Lock (=/fx lock|unlock) drives ours.
    ST:Set("General", "GlobalLock", false)
    assertFalse(Swing.cfg.locked)
    ST:Set("General", "GlobalLock", true)
    assertTrue(Swing.cfg.locked)
    assertEquals(true, ST:Get("Hunter", "Lock"))
    -- Forte_Cooldown's published lock state (its SetLocked publish is the
    -- lock-change hook, m4) is mirrored into the Hunter bar.
    local d = FX.Cooldown and FX.Cooldown.Display
    if d and d.SetLocked then
        d:SetLocked(false)
        assertFalse(Swing.cfg.locked)
        d:SetLocked(true)
        assertTrue(Swing.cfg.locked)
        assertTrue(Swing.anchor)
    end
    Swing:SetLocked(true)
end)

-- ----------------------------------------------------------------- gating --

test("the UI module follows the class (events, frames, page)", function()
    local savedClass = FX._playerClass
    -- To HUNTER first: the frame the disable path asserts on must exist.
    UI:OnClassChanged("HUNTER")
    assertNotNil(UI._eventFrame)
    assertNotNil(UI._eventFrame:GetScript("OnEvent"))
    assertNotNil(Swing.anchor)
    assertNotNil(Reminder.anchor)

    UI:OnClassChanged("WARLOCK")
    assertNil(UI._eventFrame:GetScript("OnEvent"))
    assertFalse(Swing.anchor:IsShown())
    assertFalse(Reminder.anchor:IsShown())
    assertNil(Swing.anchor:GetScript("OnUpdate"))
    assertNil(Reminder.anchor:GetScript("OnUpdate"))

    UI:OnClassChanged("HUNTER")
    assertNotNil(UI._eventFrame:GetScript("OnEvent"))
    -- The page registration: the page file's load-time fast path when
    -- Forte_Options loaded first, this call path when it did not.
    if FX.Options and FX.Options.pages then
        assertNotNil(FX.Options.pages["Hunter"])
        assertEquals("Hunter", FX.Options.pages["Hunter"].id)
        assertEquals("Hunter", FX.Options.pages["Hunter"].module)
    end
    UI:OnClassChanged(savedClass)
    assertNil(UI._eventFrame:GetScript("OnEvent"))
    assertEquals(savedClass, FX._playerClass)
end)

test("the Hunter page builds in the options window", function()
    if not (FX.Options and FX.Options.pages and FX.Options.pages["Hunter"]) then
        print("[page] Forte_Options has no Hunter page -- skipped")
        return
    end
    FX.Options:Open("Hunter")
    assertEquals(true, FX.Options:IsOpen())
    assertEquals("Hunter", FX.Options.pageId)
    local page = FX.Options.pagesBuilt["Hunter"]
    assertNotNil(page)
    -- Tips + Basics + Shot Cycle + Frame Sizing + Coloring + Range Light
    -- + Combat Alpha (swing v2 added Shot Cycle, Range Light, Combat Alpha).
    assertEquals(7, #page.sections)
    local counts = {}
    for i, sec in ipairs(page.sections) do counts[i] = #sec.widgets end
    assertEquals(0, counts[1])      -- Some Tips is text lines
    assertEquals(4, counts[2])      -- Enable, Lock, ShowTime, EnableReminder
    assertEquals(6, counts[3])      -- the five Show* keys + BaseSpeed
    assertEquals(3, counts[4])      -- Width, Height, ReminderSize
    assertEquals(3, counts[5])      -- BarColor, BgColor, ReminderColor
    assertEquals(1, counts[6])      -- ShowRangeLight
    assertEquals(2, counts[7])      -- InCombatAlpha, OutOfCombatAlpha
    assertEquals(7, #page.sections[1].lines)
    assertNotNil(FX.Options.header)
    assertNotNil(FX.Options.header.bar)
    FX.Options:Close()
    assertEquals(false, FX.Options:IsOpen())
end)

-- The page's tips are the shipped defaults' only prose, and two of them
-- used to describe code that is not the code (code-review-5 m4, m5): the
-- Combat Alpha row stated the WeaponSwingTimer in-combat-only law against a
-- shipped default of 1.0 (UI/Swing.lua's skin comment: "parked VISIBLE"), and
-- the Latency row was pushed toward "Live" against a control whose state
-- field no render pass reads. A tip that contradicts its own key is a defect
-- the owner files as "the option does nothing", so the two rows are pinned
-- to the code they describe -- the same pin on every future tip edit.
test("the Hunter page's tips tell the truth about their keys", function()
    if not (FX.Options and FX.Options.pages and FX.Options.pages["Hunter"]) then
        print("[page] Forte_Options has no Hunter page -- skipped")
        return
    end
    FX.Options:Open("Hunter")
    local page = FX.Options.pagesBuilt["Hunter"]
    assertNotNil(page, "the page builds")
    local tips, labels = {}, {}
    for _, sec in ipairs(page.sections) do
        for _, w in ipairs(sec.widgets) do
            local spec = w.spec
            if spec and spec.key then
                tips[spec.key] = spec.tip or ""
                labels[spec.key] = spec.label or ""
            end
        end
    end
    FX.Options:Close()

    -- m4: the alpha pair's default IS visible (the store's default and the
    -- skin agree -- the alpha law of UI/Swing.lua's pair), so the tip has to
    -- say the shipped number and never the WST law the module does not ship.
    assertEquals(1.0, FX.Settings:GetDefault("Hunter", "OutOfCombatAlpha"))
    local ooc = tips["OutOfCombatAlpha"]
    assertNotNil(ooc, "the OutOfCombatAlpha row is on the page")
    assertContains(ooc, "1.0")
    assertContains(ooc, "VISIBLE")
    local inCombat = tips["InCombatAlpha"]
    assertContains(inCombat, "1.0")

    -- m5: the latency strip has no render consumer -- the state field its
    -- setter writes is read by nobody in the bar (UI/Swing.lua), which is the
    -- Gap-12 launch-probe law, not a live feature. The tip says "inert", the
    -- label says "needs launch probe", and NEITHER may claim "Live" while no
    -- render path reads it.
    local lat = tips["ShowLatency"]
    assertNotNil(lat, "the ShowLatency row is on the page")
    assertContains(lat, "inert")
    assertContains(labels["ShowLatency"], "launch probe")
    local function claimsLive(text)
        return text:find("Live", 1, true) ~= nil
    end
    assertFalse(claimsLive(lat), "the latency tip claims a live strip")
    assertFalse(claimsLive(labels["ShowLatency"]),
        "the latency label claims a live strip")
    -- And the claim the sibling rows DO make: the alpha pair is applied at
    -- the frame (UI/Swing.lua's _ApplyCombatAlpha leg).
    assertContains(inCombat, "Live")
end)

test("Status prints the swing bar, the reminder and the range light", function()
    local lines = {}
    local realPrint = FX.Print
    FX.Print = function(msg) lines[#lines + 1] = tostring(msg) end
    UI:Status()
    FX.Print = realPrint
    -- swing v2: the range light adds its line once its frame is built (the
    -- class-gate test above builds it through UI:OnClassChanged).
    assertTrue(#lines >= 2)
    assertContains(lines[1], "Swing bar")
    assertContains(lines[2], "Aspect reminder")
    local hasRange = false
    for _, l in ipairs(lines) do
        if l:find("Range light") then hasRange = true end
    end
    assertTrue(hasRange)
    assertContains(Swing:StatusLine(), "locked")
    assertContains(Reminder:StatusLine(), "icon=")
    -- Restore the shared state the geometry tests drove.
    Swing:SetTracker(FX.Hunter.Tools.Swing)
    Reminder:SetAspects(FX.Hunter.Tools.Aspects)
    Swing:RenderIdle()
    Reminder:HideNow()
    Swing:SetLocked(true)
end)

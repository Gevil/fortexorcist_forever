-- addon/Forte_Cooldown/tests/test_splash.lua
-- wow-ui-sim tests for the Secondary Splash (UI/Splash.lua) and its
-- ready-pop seam in Module:ProcessReadyPops.
--
-- The law under test, source-cited in UI/Splash.lua (the Splash frame's
-- Draw, Forte_Cooldown.lua :1008-1051): for each cooldown in its end
-- window (the SAME 1.0 s expiry window the bar's pulse uses -- t14 set to
-- 1 at the ready, decayed -1/s) the pop rides the BELL
--   s1 = 1 - 4*(0.5 - t14)^2,
--   icon alpha = s1 * s.alpha, size = 32*(scale + (SSM-scale)*s1),
-- the icon fading IN then OUT, peaking at 32*SecondSplashMax mid-window;
-- the slot retires with the window (the cd[14] > 0 gate, :1017). The
-- unlocked-idle placeholder (:1040-49): enabled + not locked + no live
-- splash = one icon at 32*scale, alpha s.alpha, spark 2.2x; locked+idle
-- draws nothing. At most SplashMax = 8 run at once (CD-28); SplashGlow
-- crops 0.133..0.867 + the 2.2x ADD-blend Spark2 (:978-988, :1031-34); the
-- backdrop plate rides BgColor[4]*0.7; off by default (:1869).
--
-- The alpha bar: the source applies s.alpha to the FRAME (:1060) and
-- s1*s.alpha to the ICON (:1027), the placeholder icon s.alpha (:1043) --
-- the effective on-screen alpha is the PRODUCT frame x icon, s1 *
-- s.alpha^2 (peak 0.49 at the 0.7 defaults, placeholder 0.49). The rebuild
-- mirrors that structure exactly: the window frame carries S.Alpha, the
-- slot frame s1*S.Alpha (placeholder: S.Alpha), and the bar measures
-- effAlpha = the product of the two frame alphas.
--
-- The pop is driven through the Module's REAL path (ProcessReadyPops --
-- the public method the 10 Hz ticker drives; the C_Timer ticker is not
-- reachable headless, the established finding of test_timeline/test_module).
-- The hidden-frame law: the activity starts through the public pop path
-- and IsShown() is asserted WITHOUT calling the render function; the
-- clock is injected into Update everywhere the curve is sampled.

local FX = ForteXorcist
local Splash = FX.Cooldown.Splash
local Skin = FX.Cooldown.SplashSkin
local Module = FX.Cooldown.Module
local Engine = FX.Cooldown.Engine
local Settings = FX.Settings

local function nearpx(actual, expected)
    return assertTrue(math.abs(actual - expected) <= 0.5)
end
local function near3(actual, expected)
    return assertTrue(math.abs(actual - expected) < 1e-3)
end

--- The EFFECTIVE icon alpha: the window frame's S.Alpha factor x the slot
--- frame's bell factor (the source's single :1026 s1*s.alpha, split).
local function effAlpha(slot)
    return slot.frame:GetAlpha() * Splash.anchor:GetAlpha()
end

--- A tracked name with a predicted window that the Sweep pops at `now`
--- through the engine's real book-keeping (the inferred-entry law: a
--- "cast" entry pops; feed it like the Module feeds it).
local function armedSpell(name, start, duration)
    Engine.tracked[name] = { name = name, dataId = 1, baseDuration = duration }
    Engine:OnCast(name, start)
    return Engine.entries[name]
end

local function activeIcons()
    local n = 0
    for _, slot in ipairs(Splash._icons or {}) do
        if slot.active then n = n + 1 end
    end
    return n
end

local function clearPops()
    Splash:SetEnabled(false)          -- releases every live pop + hides
    Splash:Update(GetTime() + 100)    -- flush (idempotent)
    for name in pairs(Engine.entries) do Engine.entries[name] = nil end
    for name in pairs(Engine.tracked) do
        if name:find("^SplashTest") then Engine.tracked[name] = nil end
    end
end

-- ------------------------------------------------------------------ enable --

test("the splash module is registered, OFF by default (the original :1869)",
function()
    assertNotNil(Splash)
    assertNotNil(FX.modules["Splash"], "registered through FX.RegisterModule")
    -- Forte_Cooldown.lua:1869 -- FW.InstanceDefault.Splash.Enable = false.
    assertEquals(false, Skin.Enable)
    assertEquals(4, Skin.SecondSplashMax)   -- :1870, the bell's peak x 32
    assertEquals(8, Skin.SplashMax)         -- CD-28
    assertEquals(true, Skin.SplashGlow)     -- :1871
    near3(Skin.Alpha, 0.7)                  -- :1872
    assertEquals(2, Skin.Scale)             -- :1873
    near3(Skin.Window, 1.0)                 -- the fixed bell window (:353-54, :632-35)
    -- The page's registered defaults (the module "Splash" of the page file).
    assertTrue(Settings:IsRegistered("Splash"))
    assertEquals(false, Settings:GetDefault("Splash", "Enable"))
    assertEquals(8, Settings:GetDefault("Splash", "SplashMax"))
end)

test("Init builds the 32*scale splash window, idempotent, hidden, draggable",
function()
    Splash:OnEnable()          -- the PLAYER_LOGIN path (Init idempotent)
    assertNotNil(Splash.anchor)
    assertNotNil(ForteXorcistSplashAnchor)
    assertEquals("ForteXorcistSplashAnchor", ForteXorcistSplashAnchor:GetName())
    -- The frame size is 32*scale (:1061-62), scale default 2.
    assertEquals(64, Splash.anchor:GetWidth())
    assertEquals(64, Splash.anchor:GetHeight())
    assertFalse(Splash.anchor:IsShown(), "an idle window shows nothing")
    assertNil(Splash.anchor:GetScript("OnUpdate"),
        "a hidden window carries no ticker")
    Splash:Init()              -- idempotent: no rebuild, no raise
    assertTrue(Splash.anchor == ForteXorcistSplashAnchor,
        "the one anchor survives the second Init")
    -- Locked by default: the drag title is hidden (the Timeline title law).
    assertFalse(Splash.title:IsShown())
end)

-- ----------------------------------------------------------------- the bell --

test("the curve is the source bell over the fixed 1.0 s window (:1024-27)",
function()
    -- s1 = 1 - 4*(0.5-t14)^2: 0 at the spawn frame, 1 mid-window, 0 at the
    -- window's end.
    near3(Splash:Bell(1), 0)
    near3(Splash:Bell(0.5), 1)
    near3(Splash:Bell(0.25), 0.75)
    near3(Splash:Bell(0), 0)
    -- size = 32*(scale + (SSM-scale)*s1) at the defaults (scale 2, SSM 4):
    -- the 32*scale normal at the ends, 32*SSM at the peak.
    nearpx(Splash:BellSize(1), 64)
    nearpx(Splash:BellSize(0.5), 128)
    nearpx(Splash:BellSize(0.25), 112)
    nearpx(Splash:BellSize(0), 64)
    nearpx(Splash:NormalSize(), 64)
    -- The window is FIXED: the curve never reads the cooldown duration
    -- (t14 is a pure function of the seconds since the pop).
    assertEquals(64, Splash.anchor:GetWidth())
    local slot = { startAt = 100 }
    near3(Splash:SlotT14(slot, 100), 1)
    near3(Splash:SlotT14(slot, 100.5), 0.5)
    near3(Splash:SlotT14(slot, 101), 0)
end)

-- ------------------------------------------------------- the real pop path --

test("a Module-path pop rides the bell: in, peak, out, retired at 1.0 s",
function()
    FX.Cooldown.Display:Init()   -- idempotent; OnReady needs its Init state
    Splash:SetEnabled(true)
    -- FAR-FUTURE epoch: the live 10 Hz ticker's real-GetTime Sweep must
    -- never pop these windows (the test_tiers.lua 1000+ law).
    local e = armedSpell("SplashTestPop", 1000, 20)   -- window 1000..1020
    assertNotNil(e)
    -- The Module's real pop path: the ticker's body, driven by hand.
    Module:ProcessReadyPops(1021)
    -- The hidden-frame law: the pop SHOWS the window synchronously --
    -- asserted without any call to the render function.
    assertTrue(Splash.anchor:IsShown())
    assertEquals(1, activeIcons())
    local slot = Splash._icons[1]
    assertTrue(slot.frame:IsShown())
    -- t14 = 1 (the spawn frame the source draws at :1024-27): the bell is
    -- 0 -- alpha 0, size the 32*scale normal.
    nearpx(slot.tex:GetWidth(), 64)
    nearpx(slot.tex:GetHeight(), 64)
    near3(effAlpha(slot), 0)
    -- The plate: the bar backdrop texture at BgColor[4]*0.7 (CD-27:
    -- 0.50*0.7 = 0.35) and the inset pair (+6, the :1865 insets x2).
    local pr, pg, pb, pa = slot.plate:GetVertexColor()
    near3(pr, 0); near3(pg, 0); near3(pb, 0)
    near3(pa, 0.35)
    nearpx(slot.plate:GetWidth(), 64 + 6)
    -- SplashGlow on (the default): the :980 crop + the :1031-32 2.2x spark.
    local ulx, uly, blx, bly, urx, _, brx, bry = slot.tex:GetTexCoord()
    near3(ulx, 0.133); near3(blx, 0.133); near3(urx, 0.867); near3(brx, 0.867)
    near3(uly, 0.133); near3(bly, 0.867); near3(bry, 0.867)
    assertTrue(slot.spark:IsShown())
    nearpx(slot.spark:GetWidth(), 64 * 2.2)
    -- The spark rides FixIntensity(category): Spell (1, .5, 0) ->
    -- (1, .65, .3) (largest == 1 branch, Forte_Core.lua :796-805).
    local sr, sg, sb = slot.spark:GetVertexColor()
    near3(sr, 1.00); near3(sg, 0.65); near3(sb, 0.30)

    -- t14 = 0.5 (0.5 s into the FIXED 1.0 s window -- the duration is 20
    -- and moves nothing): the PEAK, 32*SSM, alpha s1*s.alpha^2 = 0.49
    -- (the :1060 frame factor x the :1027 icon factor), spark 2.2 peak.
    Splash:Update(1021.5)
    nearpx(slot.tex:GetWidth(), 128)
    nearpx(slot.tex:GetHeight(), 128)
    near3(effAlpha(slot), 0.49)
    nearpx(slot.spark:GetWidth(), 128 * 2.2)
    -- t14 = 0.25 (0.75 s in): riding back down -- the bell is 0.75, the
    -- effective alpha 0.75 * 0.7^2 = 0.3675.
    Splash:Update(1021.75)
    nearpx(slot.tex:GetWidth(), 112)
    nearpx(slot.tex:GetHeight(), 112)
    near3(effAlpha(slot), 0.3675)
    -- The window's end: t14 = 0 (1.0 s after the pop) is the source's
    -- cd[14] > 0 gate (:1017) -- the slot retires, the locked idle window
    -- hides (no ticker on a hidden frame).
    Splash:Update(1022.0)
    assertEquals(0, activeIcons())
    assertFalse(slot.frame:IsShown())
    assertFalse(Splash.anchor:IsShown())
    assertNil(Splash.anchor:GetScript("OnUpdate"))
end)

test("at most SplashMax (8) splashes run at once (CD-28)", function()
    Splash:SetEnabled(true)
    for i = 1, 9 do
        armedSpell("SplashTestCap" .. i, 2000, 8)
    end
    Module:ProcessReadyPops(2009)        -- all nine pop in one sweep
    assertEquals(8, activeIcons(), "the 9th pop is dropped at the cap")
    assertEquals(8, #Splash._icons, "the pool itself caps at SplashMax")
    clearPops()
    assertEquals(0, activeIcons())
    Splash:SetEnabled(true)
end)

test("FX_COOLDOWN_READY fires once per pop; the Module is inert without the bus",
function()
    Splash:SetEnabled(false)            -- isolate the bus from the pool
    armedSpell("SplashTestBusA", 3000, 5)
    armedSpell("SplashTestBusB", 3000, 5)
    local seen = {}
    FX.Fire = function(event, name, now, texPath, category)
        seen[#seen + 1] = { event = event, name = name, now = now,
            texPath = texPath, category = category }
    end
    Module:ProcessReadyPops(3006)
    FX.Fire = nil
    assertEquals(2, #seen, "exactly one event per pop")
    -- The Sweep iterates pairs(): the pair is a SET, no order law.
    local byName = {}
    for _, rec in ipairs(seen) do
        assertEquals("FX_COOLDOWN_READY", rec.event)
        assertEquals(3006, rec.now)
        assertEquals("Spell", rec.category)
        byName[rec.name] = true
    end
    assertTrue(byName["SplashTestBusA"] and byName["SplashTestBusB"],
        "both pops named, no duplicate")
    -- The nil-guarded bus: with NO bus installed the pop path runs on
    -- (a raise here is the guard missing). The recorder must gain NOTHING.
    local seenBefore = #seen
    armedSpell("SplashTestBusC", 3006, 5)
    Module:ProcessReadyPops(3012)
    assertEquals(seenBefore, #seen, "no bus, no events")
    clearPops()
end)

-- ------------------------------------------------------------ idle face --

test("the unlocked-idle placeholder rides 32*scale at alpha s.alpha (:1040-49)",
function()
    Splash:SetEnabled(true)
    -- Locked by default: the :1040 `not s.lock` gate -- locked + idle
    -- draws NOTHING (the window stays hidden).
    Splash:SetLocked(true)
    assertFalse(Splash.anchor:IsShown(), "locked + idle is hidden")
    assertEquals(0, activeIcons())
    -- Unlocking an enabled, idle window opens it on the placeholder.
    Splash:SetLocked(false)
    assertTrue(Splash.anchor:IsShown(), "the unlocked idle window shows")
    local slot = Splash._placeholder
    assertNotNil(slot, "the idle face is the placeholder")
    assertEquals(1, activeIcons())
    assertTrue(slot.frame:IsShown())
    nearpx(slot.tex:GetWidth(), 64)              -- 32*scale (:1043-44)
    nearpx(slot.tex:GetHeight(), 64)
    near3(effAlpha(slot), 0.49)                  -- s.alpha icon x s.alpha frame (:1043, :1060)
    nearpx(slot.spark:GetWidth(), 64 * 2.2)      -- :1045-46
    nearpx(slot.spark:GetHeight(), 64 * 2.2)
    assertTrue(slot.spark:IsShown())             -- SplashGlow on
    -- The face is STABLE: the pump keeps one active icon, grows no pool.
    local poolN = #Splash._icons
    Splash:Update(GetTime() + 5)
    assertEquals(1, activeIcons())
    assertEquals(poolN, #Splash._icons)
    -- A pop takes the placeholder's slot OVER (the source's Draw fills
    -- icons[1..] before the :1040 branch can run -- never stacks).
    armedSpell("SplashTestIdlePop", 6000, 6)
    Module:ProcessReadyPops(6007)
    assertEquals(1, activeIcons(), "the pop replaces the face, not stacks")
    assertEquals(slot, Splash._icons[1], "the same slot object")
    assertNil(Splash._placeholder, "the face is gone while the pop lives")
    -- The pop's window ends: the idle face returns (unlocked + idle).
    Splash:Update(6008.5)
    assertNotNil(Splash._placeholder, "the idle face is back")
    assertTrue(Splash.anchor:IsShown())
    -- Re-locking WHILE idle: the face is released and the window hides.
    Splash:SetLocked(true)
    assertEquals(0, activeIcons(), "the placeholder is not a live pop")
    assertFalse(Splash.anchor:IsShown(), "locked + idle hides the window")
    assertNil(Splash.anchor:GetScript("OnUpdate"))
    clearPops()
end)

-- -------------------------------------------------------------- live seam --

test("the settings keys are live through FX.Settings", function()
    Splash:OnEnable()   -- _WireSettings is idempotent; Init ran already
    local popAt = 4000
    local function pop(name)
        armedSpell(name, popAt, 10)
        Module:ProcessReadyPops(popAt + 11)
    end
    -- Enable through the store: a pop with Enable off shows nothing.
    Settings:Set("Splash", "Enable", false)
    assertEquals(false, Skin.Enable, "the store reached the skin")
    pop("SplashTestLiveOff")
    assertFalse(Splash.anchor:IsShown())
    Settings:Set("Splash", "Enable", true)
    pop("SplashTestLiveOn")
    assertTrue(Splash.anchor:IsShown())
    -- SplashMax through the store.
    Settings:Set("Splash", "SplashMax", 5)
    assertEquals(5, Skin.SplashMax)
    -- SplashGlow through the store: the live pop re-crops and hides the
    -- spark; back on re-crops to the glow pair.
    Settings:Set("Splash", "SplashGlow", false)
    local slot = Splash._icons[1]
    local ulx, _, blx = slot.tex:GetTexCoord()
    near3(ulx, 0); near3(blx, 0)
    assertFalse(slot.spark:IsShown())
    Settings:Set("Splash", "SplashGlow", true)
    local ulx2 = slot.tex:GetTexCoord()
    near3(ulx2, 0.133)
    assertTrue(slot.spark:IsShown())
    -- Alpha through the store rides the window.
    Settings:Set("Splash", "Alpha", 0.4)
    near3(Splash.anchor:GetAlpha(), 0.4)
    -- Scale through the store resizes the frame (32 x scale).
    Settings:Set("Splash", "Scale", 3)
    assertEquals(96, Splash.anchor:GetWidth())
    Settings:Set("Splash", "Scale", 2)
    assertEquals(64, Splash.anchor:GetWidth())
    clearPops()
    -- Restore the shipped defaults for the tests that follow.
    for _, key in ipairs({ "SplashMax", "Alpha" }) do
        Settings:Reset("Splash", key)
    end
    Settings:Set("Splash", "SplashGlow", true)
    Settings:Set("Splash", "Enable", false)
end)

test("the lock mirrors /fx lock|unlock (the Cooldown.Lock + GlobalLock pair)",
function()
    local d = FX.Cooldown.Display
    d:Init()                       -- idempotent
    Splash:SetLocked(true)
    assertTrue(Splash.cfg.locked)
    assertFalse(Splash.anchor:IsMovable(), "the lock removes the drag")
    if Splash.anchor.IsMouseEnabled then
        -- (method-presence probe, the test_swing.lua:262 pattern) The lock
        -- law: the lock gates the DRAG START and never takes the frame's
        -- mouse (the source's label is "Lock (disable dragging)").
        assertTrue(Splash.anchor:IsMouseEnabled(),
            "locked keeps the mouse: the window's releases stay live")
    end
    assertEquals(true, Settings:Get("Splash", "Lock"), "the m4 publish")
    -- /fx unlock runs Display:SetLocked(false), which publishes
    -- Cooldown.Lock + General.GlobalLock -- the splash window follows.
    d:SetLocked(false)
    assertFalse(Splash.cfg.locked, "the window unlocked with the bar")
    assertEquals(false, Settings:Get("Splash", "Lock"))
    -- And the General page's shared lock moves it alone.
    d:SetLocked(true)
    assertTrue(Splash.cfg.locked)
    Settings:Set("General", "GlobalLock", false)
    assertFalse(Splash.cfg.locked, "the window unlocked with GlobalLock")
    -- The window publishing its OWN lock never moves the bar (m4, one
    -- truth per frame): lock the pair through the bar (the mirror follows),
    -- then free the splash ALONE -- the bar and its keys stay locked.
    d:SetLocked(true)
    assertTrue(d.cfg.locked)
    assertTrue(Splash.cfg.locked, "the mirror locked the window with the pair")
    Splash:SetLocked(false)
    assertTrue(d.cfg.locked, "the splash lock does not move the bar")
    assertEquals(true, Settings:Get("Cooldown", "Lock"), "the bar's key untouched")
    d:SetLocked(true)
    Splash:SetLocked(true)
end)

-- ------------------------------------------------------------------- page --

test("the Splash page registers and the Secondary Splash cell lights", function()
    local O = FX.Options
    assertNotNil(O, "Forte_Options is an always-loaded addon")
    local def = O.pages["Splash"]
    assertNotNil(def, "Pages/Splash.lua registered the page")
    assertEquals("Splash", def.module)
    assertEquals("Secondary Splash", def.title)
    assertEquals("Lock", def.lockKey)
    assertEquals("function", type(def.lockFrame), "C4: the page hands its frame")

    local i, entry
    for n, e in ipairs(O.INDEX) do
        if e.id == "Splash" then i, entry = n, e end
    end
    assertNotNil(i, "the O.INDEX cell exists")
    assertEquals("Secondary Splash", entry.label)

    -- The cell law: a registered page lights the cell (enabled, OnClick).
    O:Open("Splash")
    local btn = O.indexButtons[i]
    assertNotNil(btn)
    assertEquals(true, btn.built)
    assertEquals(true, btn:IsEnabled())
    assertNotNil(btn:GetScript("OnClick"))
    -- Un-register, refresh: the cell dims (the RefreshIndexCells law).
    local saved = O.pages["Splash"]
    O.pages["Splash"] = nil
    O:RefreshIndexCells()
    assertEquals(false, btn:IsEnabled())
    assertNil(btn:GetScript("OnClick"))
    O.pages["Splash"] = saved
    O:RefreshIndexCells()
    assertEquals(true, btn:IsEnabled())
    -- C4: the page header reads the SPLASH window's live lock, not the
    -- bar's: diverge them on purpose.
    local d = FX.Cooldown.Display
    d:SetLocked(true)
    Splash:SetLocked(false)
    O:Open("Splash")
    local r, g = O.header.lockText:GetTextColor()
    assertTrue(g >= 0.70 and r >= 0.99,
        "the header reads the unlocked splash window (gold)")
    Splash:SetLocked(true)
    O:Close()
end)

test("the splash numbers print for the record", function()
    Splash:SetEnabled(true)
    armedSpell("SplashTestShot", 5000, 20)
    Module:ProcessReadyPops(5021)
    local slot = Splash._icons[1]
    print(string.format(
        "[splash] frame %dx%d | spawn tex %dx%d plate %dx%d spark %dx%d | alpha %.3f",
        Splash.anchor:GetWidth(), Splash.anchor:GetHeight(),
        slot.tex:GetWidth(), slot.tex:GetHeight(),
        slot.plate:GetWidth(), slot.plate:GetHeight(),
        slot.spark:GetWidth(), slot.spark:GetHeight(),
        effAlpha(slot)))
    -- t14 = 0.5: the PEAK frame (docs/media/sim/fx_splash_peak.png).
    Splash:Update(5021.5)
    print(string.format(
        "[splash] peak t14=0.50 tex %dx%d plate %dx%d spark %dx%d | alpha %.3f",
        slot.tex:GetWidth(), slot.tex:GetHeight(),
        slot.plate:GetWidth(), slot.plate:GetHeight(),
        slot.spark:GetWidth(), slot.spark:GetHeight(),
        effAlpha(slot)))
    Splash:Update(5021.75)
    print(string.format("[splash] t14=0.25 tex %.2f alpha %.3f",
        slot.tex:GetWidth(), effAlpha(slot)))
    Splash:Update(5022.5)
    assertFalse(Splash.anchor:IsShown())
    Splash:SetEnabled(false)
    clearPops()
end)

-- ------------------------------------------------------- the pop's own law --
-- E1 (CodeReview4, owner ruling): the ready pop prints NOTHING to chat. The
-- source's pop loop prints nothing (zero "ready" prints in
-- /tmp/fxref/Forte_Cooldown.lua; its ">> %s is ready in %s <<" trio is the
-- bar-icon CLICK readout family, Forte_Core.lua:2188 `FW:ShowTimeFor` reached
-- from Forte_Cooldown.lua:911,1128). The only ready chat line is Forte_
-- Messages' SelfMsg `ReadyChat` row (templated, coloured, opt-in). The pop
-- path is the SAME one the 10 Hz ticker drives, so these tests drive the real
-- path through Module:ProcessReadyPops.

test("a ready pop prints no chat line (E1)", function()
    Splash:SetEnabled(false)              -- the splash is not the subject
    local prints, adds = 0, 0
    local realPrint = FX.Print
    local realAdd = DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage
    FX.Print = function() prints = prints + 1 end
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME.AddMessage = function() adds = adds + 1 end
    end
    -- The bus proves the pop REACHED the loop's end (the print sat at the
    -- top of it): a silent loop would satisfy the print counts by exit, and
    -- that is not what is under test.
    local events = 0
    local realFire = FX.Fire
    FX.Fire = function(event)
        if event == "FX_COOLDOWN_READY" then events = events + 1 end
    end
    armedSpell("E1TestPopA", 7000, 6)     -- window 7000..7006
    Engine.entries["E1TestLive"] = {
        name = "E1TestLive", start = 7005, duration = 900, endTime = 7905,
        source = "cast", anchored = true,
    }                                       -- live, NOT popping: no print
    Module:ProcessReadyPops(7007)
    FX.Print = realPrint
    if DEFAULT_CHAT_FRAME and realAdd then
        DEFAULT_CHAT_FRAME.AddMessage = realAdd
    end
    FX.Fire = realFire
    assertEquals(1, events, "the pop ran: one FX_COOLDOWN_READY")
    assertEquals(0, prints, "FX.Print at a pop (the E1 ungated line)")
    assertEquals(0, adds, "DEFAULT_CHAT_FRAME:AddMessage at a pop")
    Engine.tracked["E1TestPopA"] = nil
    clearPops()
end)

-- m3 (CodeReview4): the pop snapshot is a POP-SITE capture, not a per-tick
-- walk. Every live entry is a proxy whose field reads are COUNTED (the
-- fields live in the backing table, so every read runs the metamethod); the
-- old ProcessReadyPops re-snapshotted `duration`, `icon` and `category` of
-- EVERY live entry on EVERY 10 Hz tick, so a live, non-popping entry saw all
-- three reads every tick. The Sweep's own reads are charges/endTime (+ the
-- pop's name/source/anchored), so asserting the three snapshot fields are
-- read for the popping entry and never for a live one says the per-tick
-- snapshot work is O(pop), not O(live entries).
test("the pop snapshot scales with pops, not with live entries (m3)",
function()
    Splash:SetEnabled(false)
    local SNAPSHOT_FIELDS = { duration = true, icon = true, category = true }
    local function proxy(fields)
        local reads = {}
        local t = setmetatable({}, {
            __index = function(_, k)
                reads[k] = (reads[k] or 0) + 1
                return fields[k]
            end,
        })
        return t, reads
    end
    local function snapshotReads(reads)
        local perField = {}
        for k in pairs(SNAPSHOT_FIELDS) do perField[#perField + 1] = reads[k] or 0 end
        return perField
    end

    local function assertEachReads(counts, want, what)
        for _, n in ipairs(counts) do assertEquals(want, n, what) end
    end

    -- Five live entries that do not pop this tick + one that does.
    local live, liveReads = {}, {}
    for i = 1, 5 do
        local name = "M3TestLive" .. i
        Engine.tracked[name] = { name = name, dataId = 1, baseDuration = 900 }
        local p, reads = proxy({
            name = name, start = 8000, duration = 900, endTime = 8900,
            source = "cast", anchored = true,
        })
        Engine.entries[name] = p
        live[i], liveReads[i] = name, reads
    end
    local popName = "M3TestPop"
    Engine.tracked[popName] =
        { name = popName, dataId = 1, baseDuration = 6 }
    local popProxy, popReads = proxy({
        name = popName, start = 8000, duration = 6, endTime = 8006,
        source = "cast", anchored = true,
    })
    Engine.entries[popName] = popProxy

    Module:ProcessReadyPops(8007)

    assertEachReads(snapshotReads(popReads), 1,
        "the popping entry's snapshot fields are captured exactly once")
    for i = 1, 5 do
        assertEachReads(snapshotReads(liveReads[i]), 0,
            "a live, non-popping entry is never snapshotted: the per-tick"
            .. " snapshot walk scaled with the live-entry count (m3)")
        Engine.tracked[live[i]] = nil
    end
    Engine.tracked[popName] = nil
    clearPops()
end)


-- addon/Forte_Cooldown/tests/test_zzb_splash_ready.lua
-- Issue #1 "Cooldown Splash plays at start of Cooldown, rather than at the
-- end". The bar's `Splash ready cooldowns` (key `Splash`) acts at READY only:
-- the ONE pulse at the bar's left end (Display:OnReady -> SpawnPulse). The
-- old first-sighting splash on the icon is the opt-in `SplashOnCast`
-- (default OFF, sparse like every setting).
--
-- Driven through the real Display (Timeline) and the Module's real pop path
-- (Module:ProcessReadyPops -> Display:OnReady + Secondary Splash). Clocks are
-- injected; epochs sit far above every other file's so earlier pulses are
-- retired by the first Update and the live 10 Hz ticker never pops our
-- windows.
-- (File order: sorts after test_timeline on purpose -- the cast-splash tests below grow the grow-only splash pool, which test_timeline asserts is empty by default.)

local FX = ForteXorcist
local Display = FX.Cooldown.Display
local TM = FX.Cooldown.TimelineMath
local S = FX.Cooldown.TimelineSkin
local Splash = FX.Cooldown.Splash
local Module = FX.Cooldown.Module
local Engine = FX.Cooldown.Engine
local Settings = FX.Settings

local function near3(actual, expected)
    return assertTrue(math.abs(actual - expected) < 1e-3)
end

local function shownSplashes()
    local n = 0
    for _, s in ipairs(Display.splashPool) do
        if s.frame:IsShown() then n = n + 1 end
    end
    return n
end

local function livePulses()
    local list = {}
    for _, p in ipairs(Display.pulsePool) do
        if p._endAt and p.frame:IsShown() then list[#list + 1] = p end
    end
    return list
end

local function activeIcons()
    local n = 0
    for _, slot in ipairs(Splash._icons or {}) do
        if slot.active then n = n + 1 end
    end
    return n
end

local function armedSpell(name, start, duration)
    Engine.tracked[name] = { name = name, dataId = 1, baseDuration = duration }
    Engine:OnCast(name, start)
    return Engine.entries[name]
end

local function clean(now)
    for name in pairs(Engine.entries) do Engine.entries[name] = nil end
    for name in pairs(Engine.tracked) do
        if name:find("^SplashReady") then Engine.tracked[name] = nil end
    end
    Display:Update({}, now)
end

local function feedOf(name, now, duration)
    return { { name = name, start = now, duration = duration,
               endTime = now + duration } }
end

local function resetKeys()
    Settings:Reset("Cooldown", "Splash")
    Settings:Reset("Cooldown", "SplashOnCast")
end

test("SplashOnCast ships OFF and a cast with the defaults shows NO splash frame",
function()
    Display:Init()
    resetKeys()
    assertEquals(false, Settings:GetDefault("Cooldown", "SplashOnCast"))
    assertEquals(false, Settings:Get("Cooldown", "SplashOnCast"))
    assertEquals(false, S.SplashOnCast)
    assertEquals(true, S.SplashOn)
    local now = 90000
    clean(now)
    local pool0 = #Display.splashPool
    local feed = feedOf("SplashReadyCast", now, 60)
    Display:Update(feed, now)
    assertNotNil(Display._byName["SplashReadyCast"], "the icon is on the bar")
    assertEquals(0, shownSplashes(), "a cast does not splash")
    assertEquals(pool0, #Display.splashPool, "no splash frame was even created")
    Display:Update(feed, now + 0.5)
    assertEquals(0, shownSplashes())
    assertEquals(0, #livePulses(), "and no pulse: the cooldown is not ready")
    clean(now + 5)
end)

test("SplashOnCast = true brings the first-sighting splash back, gated by Splash",
function()
    local now = 90100
    clean(now)
    Settings:Set("Cooldown", "SplashOnCast", true)
    assertEquals(true, S.SplashOnCast, "applies live")
    Display:Update(feedOf("SplashReadyCastOn", now, 60), now)
    assertEquals(1, shownSplashes(), "the old splash returns, unchanged")
    clean(now + 2)
    assertEquals(0, shownSplashes())
    -- Splash off still rules it: SplashOnCast alone never splashes.
    Settings:Set("Cooldown", "Splash", false)
    Display:Update(feedOf("SplashReadyCastOff", now + 3, 60), now + 3)
    assertEquals(0, shownSplashes(), "the Splash gate wins")
    clean(now + 5)
    resetKeys()
end)

test("a Module-path ready pop spawns exactly ONE pulse at the left end; Splash=false none",
function()
    Display:Init()
    resetKeys()
    local now = 90200
    clean(now)
    local name = "SplashReadyPop"
    armedSpell(name, now, 20)
    Display:Update(feedOf(name, now, 20), now)      -- the cast
    assertEquals(0, shownSplashes(), "no splash at the cast")
    Module:ProcessReadyPops(now + 21)              -- the real pop path
    Display:Update({}, now + 21.05)                -- the entry is gone: live order
    local pulses = livePulses()
    assertEquals(1, #pulses, "exactly one expiry visual")
    assertEquals(0, shownSplashes(), "and it is not a splash frame")
    local _, _, _, xoff = pulses[1].frame:GetPoint()
    near3(xoff, S.Inset + TM.pos(0, S.Width, S.Height, S.Max, S.Loga)
        + S.Height * 0.5 - S.Width * 0.5)
    assertNil(Display._ready[name], "the queued pop is consumed once")
    Display:Update({}, now + 21.05 + S.PulseSeconds + 0.1)
    assertEquals(0, #livePulses(), "the pulse retires")

    -- Splash off: the same pop draws nothing on the bar.
    Settings:Set("Cooldown", "Splash", false)
    local name2 = "SplashReadyPopOff"
    local t2 = now + 100
    armedSpell(name2, t2, 20)
    Display:Update(feedOf(name2, t2, 20), t2)
    Module:ProcessReadyPops(t2 + 21)
    Display:Update({}, t2 + 21.05)
    assertEquals(0, #livePulses(), "Splash = false: no pulse")
    assertEquals(0, shownSplashes())
    resetKeys()
    clean(t2 + 30)
end)

test("a ready pop shows the pulse even with SplashOnCast on, in addition to the cast splash",
function()
    local now = 90400
    clean(now)
    Settings:Set("Cooldown", "SplashOnCast", true)
    local name = "SplashReadyBoth"
    armedSpell(name, now, 20)
    Display:Update(feedOf(name, now, 20), now)
    assertEquals(1, shownSplashes(), "opt-in: the cast splash")
    Module:ProcessReadyPops(now + 21)
    Display:Update({}, now + 21.05)
    assertEquals(1, #livePulses(), "and the one ready pulse")
    resetKeys()
    clean(now + 40)
end)

test("the Secondary Splash still fires exactly once per pop, whatever the bar options say",
function()
    Display:Init()
    Splash:OnEnable()
    Splash:SetEnabled(true)
    for _, cfg in ipairs({
        { splash = true,  cast = false },
        { splash = false, cast = false },
        { splash = true,  cast = true },
    }) do
        resetKeys()
        Settings:Set("Cooldown", "Splash", cfg.splash)
        Settings:Set("Cooldown", "SplashOnCast", cfg.cast)
        Splash:SetEnabled(false)
        Splash:SetEnabled(true)
        local now = 90500
        clean(now)
        local name = "SplashReadyFlash"
        armedSpell(name, now, 20)
        Display:Update(feedOf(name, now, 20), now)
        assertEquals(0, activeIcons(), "nothing before the pop")
        Module:ProcessReadyPops(now + 21)
        assertEquals(1, activeIcons(),
            "one Secondary Splash for the one pop (Splash=" .. tostring(cfg.splash)
            .. ", SplashOnCast=" .. tostring(cfg.cast) .. ")")
        Display:Update({}, now + 21.05)
    end
    resetKeys()
    Splash:SetEnabled(false)
    Splash:Update(GetTime() + 100)
    clean(90600)
end)

test("SplashOnCast is sparse, live both ways, and turning it off clears cast splashes",
function()
    local t = Settings._store("Cooldown")
    resetKeys()
    assertEquals(nil, t.SplashOnCast, "the default is not written")
    Settings:Set("Cooldown", "SplashOnCast", false)       -- = default
    assertEquals(nil, t.SplashOnCast, "setting the default stores nothing")
    Settings:Set("Cooldown", "SplashOnCast", true)
    assertEquals(true, t.SplashOnCast, "a real choice is stored")
    assertEquals(true, S.SplashOnCast)
    local now = 90700
    clean(now)
    Display:Update(feedOf("SplashReadyLive", now, 60), now)
    assertEquals(1, shownSplashes())
    Settings:Set("Cooldown", "SplashOnCast", false)       -- live off
    assertEquals(nil, t.SplashOnCast, "back at the default: the key is removed")
    assertEquals(false, S.SplashOnCast)
    assertEquals(0, shownSplashes(), "the running cast splash is cleared")
    -- A later first sighting does not splash again.
    Display:Update(feedOf("SplashReadyLive2", now + 1, 60), now + 1)
    assertEquals(0, shownSplashes())
    -- The bulk seam and the saved-settings list both carry the key.
    Display:ApplySettings({ SplashOnCast = true })
    assertEquals(true, S.SplashOnCast)
    Display:ApplySettings({ SplashOnCast = false })
    assertEquals(false, S.SplashOnCast)
    clean(now + 5)
    resetKeys()
end)

-- addon/Forte_Messages/tests/test_messages.lua
-- The self-messages half: the bus -> chat/banner/sound chain (the public
-- path is FX.Fire of the contract event -- no test calls a render function,
-- the UI-test law), the banner's synchronous show and clock retirement (the
-- hidden-frame law: the show rides the kick itself), the sound law (the
-- repeat count of the original's third slot, Forte_Core.lua:2063-2067), the
-- live settings seam, the registered pages lighting the SelfMsg/Sound index
-- cells, and the FORTE_TIMER WRAP: options.onExpire chain-called, the bus
-- fired after it, Forte_Timer untouched.
--
-- The login law of the suite family (Forte_Hunter/tests/test_swing.lua,
-- Forte_Timer/tests/test_module.lua): the gate run's login sequence does
-- not reach Forte_Core's module loop, so the enable path is driven directly.

local FX = ForteXorcist
local M = FX.Messages.Module
local Channel = FX.Messages.Channel
local Sounds = FX.Messages.Sounds
local Announce = FX.Messages.Announce
local Banner = FX.Messages.Banner
local ST = FX.Settings

local function enable()
    if not M.cfg then M:OnEnable() end
end

-- Chat capture: the layer reads _G.DEFAULT_CHAT_FRAME fresh at every Show,
-- so the stub is the cleanest capture and the real frame is restored whole.
local realChat
local chats
local function installChat()
    if not realChat then realChat = _G.DEFAULT_CHAT_FRAME end
    chats = {}
    _G.DEFAULT_CHAT_FRAME = {
        AddMessage = function(_, text, r, g, b)
            chats[#chats + 1] = { text = text, r = r, g = g, b = b }
        end,
    }
end
local function restoreChat()
    _G.DEFAULT_CHAT_FRAME = realChat
end

local function lastChat() return chats[#chats] end

-- ---------------------------------------------------------------- enable --

test("the module enables on the bus: listeners, frame, layers, banner",
function()
    enable()
    assertNotNil(M.cfg)
    assertNotNil(M._eventFrame)
    assertNotNil(Banner.frame)
    assertEquals("FXMessagesBanner", Banner.frame:GetName())
    assertFalse(Banner.frame:IsShown())
    assertTrue(FX.ListenerCount(FX.EVENTS.COOLDOWN_READY) >= 1)
    assertTrue(FX.ListenerCount(FX.EVENTS.TIMER_EXPIRED) >= 1)
    assertEquals(M.cfg, FX.Messages.Sounds.cfg, "one shared live view")
end)

-- The three pages on their index cells (O.INDEX is the cell census; the
-- cell "lights" when a page of its id is registered -- Window.lua's
-- RegisterPage -> RefreshIndexCells).
test("the pages register and the SelfMsg/Sound/RaidMsg cells are lit",
function()
    enable()
    local O = FX.Options
    assertNotNil(O)
    local ids = { SelfMsg = false, Sound = false, RaidMsg = false }
    local seen = 0
    for _, row in ipairs(O.INDEX) do
        if ids[row.id] ~= nil then
            seen = seen + 1
            assertNotNil(O.pages[row.id],
                "index cell " .. row.id .. " has its page")
        end
    end
    assertEquals(3, seen, "all three index cells exist")
    assertEquals("Self Messages", O.pages["SelfMsg"].title)
    assertEquals("Sound", O.pages["Sound"].title)
    assertEquals("Party/Raid", O.pages["RaidMsg"].title)
    -- Idempotent re-registration (a re-enable must not double-register).
    local before = O.pages["SelfMsg"]
    M:RegisterPages()
    assertEquals(before, O.pages["SelfMsg"])
end)

-- ------------------------------------------------- ready event -> message --

test("a fired ready event prints the chat message on the public path and "
.. "the counted sound plays the repeat count", function()
    enable()
    installChat()
    local plays = {}
    local played0 = Sounds.counts.played
    Sounds.playFn = function(path) plays[#plays + 1] = path end
    ST:Set("SelfMsg", "ReadyEnable", true)
    ST:Set("SelfMsg", "ReadyChat", true)
    ST:Set("SelfMsg", "ReadyBanner", false)
    ST:Set("Sound", "CooldownReadyEnable", true)
    ST:Set("Sound", "CooldownReadyTimes", 3)
    local ready0 = M.counts.ready
    FX.Fire(FX.EVENTS.COOLDOWN_READY, "Rapid Fire", 500.0,
        "Interface\\IC\\x", "Spell")
    assertEquals(ready0 + 1, M.counts.ready)
    assertNotNil(lastChat())
    assertEquals(">> Rapid Fire is ready <<", lastChat().text)
    -- The default colour row: {1,1,0} (Forte_Soulstone.lua:651 ReadColor).
    assertEquals(1.00, lastChat().r)
    assertEquals(1.00, lastChat().g)
    assertEquals(0.00, lastChat().b)
    -- NEW-CD-33 opt-in sound: three plays of the row's path (the repeat-
    -- count law, Forte_Core.lua:2063-2067).
    assertEquals(3, #plays)
    assertEquals("Sound\\Spells\\SimonGame_Visual_GameStart.wav", plays[1])
    assertEquals(played0 + 3, Sounds.counts.played)
    -- The gate: enable off = silence, the chat half off = silence.
    ST:Set("Sound", "CooldownReadyEnable", false)
    ST:Set("SelfMsg", "ReadyChat", false)
    local n = #plays
    FX.Fire(FX.EVENTS.COOLDOWN_READY, "Rapid Fire", 501.0, nil, nil)
    assertEquals(n, #plays)
    ST:Set("SelfMsg", "ReadyChat", false)
    Sounds.playFn = nil
    restoreChat()
end)

test("the splash kick rides the opt-in flag", function()
    enable()
    local seen = {}
    local h = FX.On(FX.EVENTS.SPLASH, function(name, tex)
        seen[#seen + 1] = { name, tex }
    end)
    ST:Set("SelfMsg", "SplashKick", false)
    FX.Fire(FX.EVENTS.COOLDOWN_READY, "Rapid Fire", 1.0, "Interface\\a", nil)
    assertEquals(0, #seen)
    ST:Set("SelfMsg", "SplashKick", true)
    FX.Fire(FX.EVENTS.COOLDOWN_READY, "Rapid Fire", 2.0, "Interface\\a", nil)
    ST:Set("SelfMsg", "SplashKick", false)
    assertEquals(1, #seen)
    assertEquals("Rapid Fire", seen[1][1])
    assertEquals("Interface\\a", seen[1][2])
    FX.Off(h)
end)

-- --------------------------------------------------------------- the banner --

test("the banner shows SYNCHRONOUSLY on the public kick and retires on the "
.. "clock (no OnUpdate anywhere)", function()
    enable()
    installChat()
    local clockT = 100.0
    Banner.now = function() return clockT end
    ST:Set("SelfMsg", "ReadyEnable", true)
    ST:Set("SelfMsg", "ReadyChat", false)
    ST:Set("SelfMsg", "ReadyBanner", true)
    ST:Set("SelfMsg", "ReadySeconds", 3)
    assertFalse(Banner.frame:IsShown())
    local shown0 = Banner.counts.shown
    FX.Fire(FX.EVENTS.COOLDOWN_READY, "Rapid Fire", 1.0, nil, nil)
    assertTrue(Banner.frame:IsShown(), "the show rode the kick")
    assertEquals(1.0, Banner.frame:GetAlpha())
    assertEquals(">> Rapid Fire is ready <<", Banner.text:GetText())
    assertEquals(shown0 + 1, Banner.counts.shown)
    -- The fade belongs to the tail half-second; before it the alpha is 1.
    clockT = clockT + 2.0
    Banner:Update(clockT)
    assertTrue(Banner.frame:IsShown())
    assertEquals(1.0, Banner.frame:GetAlpha())
    clockT = clockT + 0.65                     -- 0.35 s of life left
    Banner:Update(clockT)
    local a = Banner.frame:GetAlpha()
    assertTrue(a > 0 and a < 1, "fading: alpha " .. tostring(a))
    clockT = clockT + 0.5
    Banner:Update(clockT)
    assertFalse(Banner.frame:IsShown())
    assertFalse(Banner.active)
    Banner.now = nil
    ST:Set("SelfMsg", "ReadyChat", true)
    restoreChat()
end)

-- ------------------------------------------------------------------ sounds --

test("the sound law: the repeat count plays N times and breaks at a raise",
function()
    enable()
    local n = 0
    Sounds.playFn = function()
        n = n + 1
        if n >= 2 then error("FXTEST-SILENCE", 0) end
    end
    ST:Set("Sound", "TimerExpireEnable", true)
    ST:Set("Sound", "TimerExpireTimes", 5)
    local p0 = Sounds.counts.played
    local played = Sounds:TimerExpired()
    assertEquals(1, played, "the loop broke at the first raise")
    assertEquals(p0 + 1, Sounds.counts.played)
    Sounds.playFn = nil
    ST:Set("Sound", "TimerExpireTimes", 2)
end)

test("the default playFn is the original's PlaySoundFile, pcall'd",
function()
    enable()
    local got = {}
    local real = _G.PlaySoundFile
    _G.PlaySoundFile = function(path) got[#got + 1] = path end
    Sounds.playFn = nil
    ST:Set("Sound", "TimerExpireEnable", true)
    ST:Set("Sound", "TimerExpirePath", "Sound\\Spells\\ShaysBell.wav")
    ST:Set("Sound", "TimerExpireTimes", 2)
    local played = Sounds:TimerExpired()
    _G.PlaySoundFile = real
    assertEquals(2, played)
    assertEquals(2, #got)
    assertEquals("Sound\\Spells\\ShaysBell.wav", got[1])
    ST:Set("Sound", "TimerExpireEnable", false)
end)

-- ---------------------------------------------------------- the timer wrap --

test("Forte_Timer's onExpire is WRAPPED: the prior handler runs, then the "
.. "bus fires the expire chain", function()
    enable()
    local TM = FX.Timer and FX.Timer.Module
    assertNotNil(TM, "Forte_Timer loads in the suite (OptionalDep)")
    if not TM.options then TM:OnEnable() end
    local prev = TM.options.onExpire
    assertNotNil(prev)
    local chainSaw = nil
    TM.options.onExpire = function(row) chainSaw = row end
    M:WrapTimerExpire()
    assertEquals("wrapped", M.timerHook)
    local wrapped = TM.options.onExpire
    assertTrue(M.wrappedFns[wrapped] == true,
        "the wrap is in the registry (a function carries no fields)")
    -- Re-enable: the wrap is idempotent, it must not nest.
    M:WrapTimerExpire()
    assertEquals(wrapped, TM.options.onExpire)
    installChat()
    ST:Set("SelfMsg", "ExpireEnable", true)
    ST:Set("SelfMsg", "ExpireChat", true)
    local e0 = M.counts.expired
    wrapped({ name = "Serpent Sting", targetKey = "Vile Poacher",
        kind = "Default" })
    assertEquals(chainSaw and chainSaw.name, "Serpent Sting",
        "the prior handler got the row first")
    assertEquals(e0 + 1, M.counts.expired)
    assertNotNil(lastChat())
    assertEquals(">> Serpent Sting on Vile Poacher is fading <<",
        lastChat().text)
    -- The no-target twin (TimeLeftNoTarg, Forte_Core.lua:2526).
    wrapped({ name = "Serpent Sting", targetKey = "none", kind = "Default" })
    assertEquals(">> Serpent Sting is fading <<", lastChat().text)
    TM.options.onExpire = prev
    restoreChat()
end)

-- ----------------------------------------------------------- live settings --

test("every key is live: an ST:Set moves the shared cfg the layers read",
function()
    enable()
    ST:Set("SelfMsg", "ExpireSeconds", 7)
    assertEquals(7, M.cfg.ExpireSeconds)
    assertEquals(7, M.cfg["ExpireSeconds"])
    ST:Set("Sound", "CooldownReadyPath", "sound\\a.mp3")
    assertEquals("sound\\a.mp3", M.cfg.CooldownReadyPath)
    ST:Set("Sound", "CooldownReadyEnable", true)
    assertEquals(true, M.cfg.CooldownReadyEnable)
    ST:Set("Sound", "CooldownReadyEnable", false)
    ST:Set("SelfMsg", "ReadyColor", { 0, 1, 0, 1 })
    assertEquals(0, M.cfg.ReadyColor[1])
    assertEquals(1, M.cfg.ReadyColor[2])
    -- Colour clamps and type gates: garbage does not move the view.
    ST:Set("SelfMsg", "ReadyColor", { 4, -2, 0.5, 1 })
    assertEquals(1, M.cfg.ReadyColor[1])
    assertEquals(0, M.cfg.ReadyColor[2])
    ST:Set("Sound", "TimerExpireTimes", "not-a-number")
    assertEquals(2, M.cfg.TimerExpireTimes)
    ST:Set("SelfMsg", "ReadyColor", { 1, 1, 0, 1 })
end)

test("Channel.format degrades a broken template to the raw text",
function()
    assertEquals(">> X is ready <<",
        Channel.format(">> %s is ready <<", "X"))
    assertEquals("raw %q stays", "raw %q stays",
        Channel.format("raw %q stays"))
    -- An empty template prints the payload (the one-%s rows stay honest).
    assertEquals("x", Channel.format("", "x"))
end)

-- ------------------------------------------------------------------ status --

test("the status prints the counters, the announce census and the hook",
function()
    enable()
    local printed = {}
    local real = FX.Print
    FX.Print = function(...)
        printed[#printed + 1] = table.concat({ ... }, " ")
    end
    M:Status()
    FX.Print = real
    assertEquals(3, #printed)
    assertTrue(printed[1]:find("fading") ~= nil)
    assertTrue(printed[1]:find("broken") ~= nil)
    assertTrue(printed[2]:find("locked%-skipped") ~= nil)
    assertTrue(printed[3]:find("timer hook") ~= nil)
end)

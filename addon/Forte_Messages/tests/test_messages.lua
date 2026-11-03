-- addon/Forte_Messages/tests/test_messages.lua
-- The self-messages half: the bus -> chat/banner/sound chain (the public
-- path is FX.Fire of the contract event -- no test calls a render function,
-- the UI-test law), the banner's synchronous show and clock retirement (the
-- hidden-frame law: the show rides the kick itself) with its ON-DEMAND pump
-- clock (m5), the sound law (the repeat count of the original's third slot,
-- Forte_Core.lua:2073-2077), the live settings seam, the registered pages
-- lighting the SelfMsg/Sound/RaidMsg index cells, and the EXPIRY CHAIN
-- (E3): a row expiring through FORTE_TIMER'S OWN SWEEP reaches this module's
-- listener in a session where Messages enabled BEFORE the Timer and in one
-- where it enabled AFTER -- the load-order bug the review found, tested at
-- the order that hid it.
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

-- E6 (code-review-4) deleted the `SplashKick` row, its FX_SPLASH fire and
-- the bus declaration: the splash has its own page and its own Enable, and
-- Forte_Cooldown pops it directly (`disp/splash:OnReady`). What the ready
-- pop's own clock needs lives in the next test.
test("m5: the banner pump clock is ON DEMAND -- armed by a show, ended by "
.. "the lapse, and nothing runs while no banner is up", function()
    enable()
    installChat()
    local clockT = 900.0
    Banner.now = function() return clockT end
    ST:Set("SelfMsg", "ReadyEnable", true)
    ST:Set("SelfMsg", "ReadyChat", false)
    ST:Set("SelfMsg", "ReadyBanner", true)
    ST:Set("SelfMsg", "ReadySeconds", 2)
    -- Retire any window a peer left, then retire the pump it armed.
    Banner:Update(clockT + 60)
    M:_BannerPumpStep()
    assertFalse(M:BannerPumpActive(), "idle: no pump is running")
    FX.Fire(FX.EVENTS.COOLDOWN_READY, "Rapid Fire", 1.0, nil, nil)
    assertTrue(Banner.frame:IsShown(), "the show rode the kick")
    assertTrue(M:BannerPumpActive(), "the show armed the pump")
    -- The pump steps: a live window re-arms, the lapse ends the chain.
    clockT = clockT + 1.0
    assertTrue(M:_BannerPumpStep(), "live at 1 s of a 2 s window")
    clockT = clockT + 1.2
    assertFalse(M:_BannerPumpStep(), "the window lapsed")
    assertFalse(M:BannerPumpActive(), "and the pump ended with it")
    assertFalse(Banner.frame:IsShown())
    assertFalse(M:_BannerPumpStep(), "a step after the end is a no-op")
    Banner.now = nil
    ST:Set("SelfMsg", "ReadyChat", true)
    ST:Set("SelfMsg", "ReadyBanner", false)
    restoreChat()
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

-- The soulstone pair (Forte_Soulstone.lua:640-641, the SND rows of the
-- Soulstone Tracker's Bar Coloring sub, defaults :677-678). The producer is
-- Forte_Warlock's own tracker (`SoulstoneTracker:Expire`, tested in
-- Forte_Warlock/tests/test_warlock.lua at its real site); the public path
-- here is the contract event, the same shape as the COOLDOWN_READY test
-- above: the UI-test law says no test calls a render function.

test("the soulstone pair is on the bus, registered and listened", function()
    enable()
    assertEquals(1, FX.ListenerCount(FX.EVENTS.SOULSTONE_EXPIRED))
    assertEquals(1, FX.ListenerCount(FX.EVENTS.SOULSTONE_READY))
end)

test("the soulstone pair: the rows are the original's, defaults verbatim",
function()
    enable()
    -- The Sound page's shipped defaults (Forte_Soulstone.lua:677-678: both
    -- rows `{[0]=true, path, 1}`), asserted on the live view the layers read
    -- and on the page table that seeds it.
    local def = FX.Messages.Pages.DEFAULTS.Sound
    assertEquals(true, def.SoulstoneFadeEnable)
    assertEquals(true, def.SoulstoneReadyEnable)
    assertEquals(true, M.cfg.SoulstoneFadeEnable)
    assertEquals("Interface\\AddOns\\Forte_Core\\Sounds\\SoulstoneExpire.mp3",
        M.cfg.SoulstoneFadePath)
    assertEquals(1, M.cfg.SoulstoneFadeTimes)
    assertEquals(true, M.cfg.SoulstoneReadyEnable)
    assertEquals("Sound\\Spells\\SimonGame_Visual_GameTick.wav",
        M.cfg.SoulstoneReadyPath)
    assertEquals(1, M.cfg.SoulstoneReadyTimes)
    assertNotNil(Sounds.rows.SoulstoneFade)
    assertNotNil(Sounds.rows.SoulstoneReady)
end)

test("the soulstone pair rings on the public path, with the row's repeat count",
function()
    enable()
    local got = {}
    Sounds.playFn = function(path) got[#got + 1] = path end
    local fade0 = M.counts.soulstoneFade
    local ready0 = M.counts.soulstoneReady
    FX.Fire(FX.EVENTS.SOULSTONE_EXPIRED, "Gvil", 1000.5)
    FX.Fire(FX.EVENTS.SOULSTONE_READY, "Gvil", 1000.5)
    Sounds.playFn = nil
    assertEquals(fade0 + 1, M.counts.soulstoneFade, "the expiry counted")
    assertEquals(ready0 + 1, M.counts.soulstoneReady, "the ready counted")
    assertEquals(2, #got, "both bells rang, once each (the rows' x1)")
    assertEquals("Interface\\AddOns\\Forte_Core\\Sounds\\SoulstoneExpire.mp3",
        got[1])
    assertEquals("Sound\\Spells\\SimonGame_Visual_GameTick.wav", got[2])
end)

test("the soulstone pair: switching a row off silences that bell only",
function()
    enable()
    local got = {}
    Sounds.playFn = function(path) got[#got + 1] = path end
    ST:Set("Sound", "SoulstoneFadeEnable", false)
    FX.Fire(FX.EVENTS.SOULSTONE_EXPIRED, "Gvil", 1001)
    FX.Fire(FX.EVENTS.SOULSTONE_READY, "Gvil", 1001)
    ST:Set("Sound", "SoulstoneFadeEnable", true)
    ST:Set("Sound", "SoulstoneReadyEnable", false)
    FX.Fire(FX.EVENTS.SOULSTONE_EXPIRED, "Gvil", 1002)
    FX.Fire(FX.EVENTS.SOULSTONE_READY, "Gvil", 1002)
    ST:Set("Sound", "SoulstoneReadyEnable", true)
    Sounds.playFn = nil
    -- The sequence rings exactly the two bells that were ON at their event:
    -- the Ready bell at 1001 (Fade off) and the Fade bell at 1002 (Ready
    -- off). Each off row is silent on its own event -- that is the law.
    assertEquals(2, #got, "the off row is silent, the on row rings")
    assertEquals("Sound\\Spells\\SimonGame_Visual_GameTick.wav", got[1],
        "the Ready bell rang at 1001 (its row was on)")
    assertEquals("Interface\\AddOns\\Forte_Core\\Sounds\\SoulstoneExpire.mp3",
        got[2], "the Fade bell rang at 1002 (its row was back on)")
end)

test("the soulstone pair: the repeat count is the row's third slot",
function()
    enable()
    local got = {}
    Sounds.playFn = function(path) got[#got + 1] = path end
    ST:Set("Sound", "SoulstoneReadyTimes", 3)
    FX.Fire(FX.EVENTS.SOULSTONE_READY, "Gvil", 1003)
    ST:Set("Sound", "SoulstoneReadyTimes", 1)
    Sounds.playFn = nil
    assertEquals(3, #got)
end)

-- ------------------------------------------------------- the expiry chain --
-- E3 (code-review-4): the wrapper this suite used to drive (`M:WrapTimerExpire`
-- plus a hand-called `wrapped({name=...})`) is GONE, and with it the shortcut
-- that made the load-order bug invisible: the old test called the wrapper by
-- hand, so it proved the chain while the shipped enable order never installed
-- it. What is tested now is the REAL producer -- `Forte_Timer.Core.Rows`'s
-- own Sweep -- reaching this module's listener in BOTH enable orders.
local function enableTimer()
    local TM = FX.Timer.Module
    if not TM.options then TM:OnEnable() end
    return FX.Timer.Rows
end

--- Drive ONE row of `spell` through the Timer's own sweep to a true expiry,
--- on the injectable cast clock. No test touches a render path and no test
--- fires the event: `Rows:Sweep` is the producer.
local function expireInRealSweep(Rows, spell, targetKey, base)
    local clock = { base }
    FX.Timer.Casts.now = function() return clock[1] end
    local row = Rows:InsertFromAura(spell, targetKey, base + 4, 4, 0,
        nil, 0, base)
    assertNotNil(row)
    clock[1] = base + 4.5
    Rows:Sweep(clock[1])
    FX.Timer.Casts.now = nil
    return row
end

local function freshMessagesEnable()
    M.cfg = nil
    M:OnEnable()
end

test("E3 (order A): Messages enabled BEFORE the Timer -- a row expiring in "
.. "the Timer's real sweep reaches the listener", function()
    freshMessagesEnable()                 -- the enable that used to be first
    local TM = FX.Timer.Module
    TM.options = nil                       -- the Timer enables AFTER
    local Rows = enableTimer()
    installChat()
    ST:Set("SelfMsg", "ExpireEnable", true)
    ST:Set("SelfMsg", "ExpireChat", true)
    assertEquals("FX_TIMER_EXPIRED", FX.EVENTS.TIMER_EXPIRED)
    local e0 = M.counts.expired
    expireInRealSweep(Rows, "Serpent Sting", "Vile Poacher", 60000)
    assertEquals(e0 + 1, M.counts.expired,
        "the Timer's own fire reached the pre-Timer listener")
    assertNotNil(lastChat())
    assertEquals(">> Serpent Sting on Vile Poacher is fading <<",
        lastChat().text)
    Rows:Clear()
    restoreChat()
end)

test("E3 (order B): Messages enabled AFTER the Timer -- the same sweep, the "
.. "same delivery, and the fire is once-per-row", function()
    local TM = FX.Timer.Module
    TM.options = nil
    local Rows = enableTimer()             -- the Timer first ...
    freshMessagesEnable()                  -- ... Messages after
    installChat()
    ST:Set("SelfMsg", "ExpireEnable", true)
    ST:Set("SelfMsg", "ExpireChat", true)
    local e0 = M.counts.expired
    local row = expireInRealSweep(Rows, "Serpent Sting", "none", 61000)
    assertEquals(e0 + 1, M.counts.expired,
        "the row is rendered with the no-target template")
    assertEquals(">> Serpent Sting is fading <<", lastChat().text)
    -- Pumping the sweep more does not re-fire: the row's own stamp.
    FX.Timer.Casts.now = function() return 61010 end
    Rows:Sweep(61010)
    FX.Timer.Casts.now = nil
    assertEquals(e0 + 1, M.counts.expired, "one fire per row")
    assertNotNil(row)
    Rows:Clear()
    restoreChat()
end)

test("E3: a row whose window is extended past the crossing does not expire, "
.. "and the expiry is independent of the AnnounceExpiry chat gate",
function()
    local Rows = enableTimer()
    installChat()
    ST:Set("SelfMsg", "ExpireEnable", true)
    ST:Set("SelfMsg", "ExpireChat", true)
    local clock = { 62000 }
    FX.Timer.Casts.now = function() return clock[1] end
    local row = Rows:InsertFromAura("Serpent Sting", "Vile Poacher",
        clock[1] + 4, 4, 0, nil, 0, clock[1])
    local e0 = M.counts.expired
    clock[1] = clock[1] + 3
    Rows:Sweep(clock[1])                  -- 1 s left: not yet
    assertEquals(e0, M.counts.expired)
    -- The fact arrives LONGER (the extend law): the crossing moves away.
    Rows:OnAuraFact(row, clock[1] + 30, 30, 1, clock[1], nil, 0, nil)
    Rows:Sweep(clock[1])
    assertEquals(e0, M.counts.expired, "an extended row has not expired")
    clock[1] = clock[1] + 30.5
    Rows:Sweep(clock[1])
    assertEquals(e0 + 1, M.counts.expired, "and it fires at the new end")
    -- m7's production gate does not gate the bus: `expireMessage` OFF (the
    -- shipped default) stamped the row's chat column 0 above, and the event
    -- still rode the expiry -- the SelfMsg/RaidMsg/Sound rows are the gates.
    assertFalse(FX.Timer.Module.options.expireMessage,
        "the AnnounceExpiry gate is off by default")
    FX.Timer.Casts.now = nil
    Rows:Clear()
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
    -- The seam line reports the BUS, not a wrapper: the expiry producer is
    -- Forte_Timer's own, so the status census is the listener count (E3),
    -- and the banner pump reports its on-demand state (m5).
    assertTrue(printed[3]:find("FX_TIMER_EXPIRED") ~= nil)
    assertTrue(printed[3]:find("banner") ~= nil)
end)

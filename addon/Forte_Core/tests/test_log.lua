-- addon/Forte_Core/tests/test_log.lua
-- Core/Log.lua after the step-0 measurements (docs/research/
-- ingame-dev-step0-results-2026-11-12.md): addon-printed lines never reach
-- Logs/WoWChatLog.txt and the old `chatlog=` status field read false while
-- chat logging was on. So `/fx log`
--   * never calls `LoggingChat` and never reads `IsLoggingChat` (the legs
--     below install spies that count AND raise, so a regression is loud);
--   * prints a status line with no `chatlog` field;
--   * `on` means: copy every error the recorder (Core/Errors.lua) stores to
--     chat as `[FX-ERR]`, and turn on FX.Log tracing; `off` undoes both.
-- Older code-review-10 legs stay: M4 (the file rides the module registry, no
-- file-top registrant, default OFF, the login re-apply seam) and m5
-- (`/fx log test` survives a missing handler getter).
--
-- The slash is driven through `FX.OnSlash` (the real dispatch); the errors
-- come through the REAL recorder wrapper on a fake client handler surface;
-- every leg installs and restores the globals it touches.

local FX = ForteXorcist
local Log = FX.LogModule
local Errors = FX.Errors

local FORTE_MSG = "Interface\\AddOns\\Forte_Timer\\Core\\Rows.lua:123: attempt to index a nil value"
local FORTE_STACK = "Interface\\AddOns\\Forte_Timer\\Core\\Rows.lua:123: in function 'Sweep'"
local FOREIGN_MSG = "Interface\\AddOns\\Bagnon\\Main.lua:9: boom"
local FOREIGN_STACK = "Interface\\AddOns\\Bagnon\\Main.lua:9: in function 'Open'"

local function capturePrint()
    local lines, real = {}, FX.Print
    FX.Print = function(...) lines[#lines + 1] = table.concat({ ... }, " ") end
    return lines, function() FX.Print = real end
end

local function hasLine(lines, needle)
    for _, line in ipairs(lines) do
        if line:find(needle, 1, true) then return true end
    end
    return false
end

--- Spies on the whole chat-logging surface: every call is counted and raises
--- (the catalog's `LoggingChat(enable)` raises on a missing argument; a
--- query that answers would be the old, wrong read).
local function installChatSpies()
    local hits = { n = 0, names = {} }
    local saved = { t = _G.LoggingChat, q = _G.IsLoggingChat }
    local function spy(name)
        return function()
            hits.n = hits.n + 1
            hits.names[#hits.names + 1] = name
            error("FXTEST: " .. name .. " must not be called", 0)
        end
    end
    _G.LoggingChat = spy("LoggingChat")
    _G.IsLoggingChat = spy("IsLoggingChat")
    local ci = _G.C_ChatInfo
    local savedCi
    if type(ci) == "table" then
        savedCi = ci.IsLoggingChat
        ci.IsLoggingChat = spy("C_ChatInfo.IsLoggingChat")
    end
    return hits, function()
        _G.LoggingChat, _G.IsLoggingChat = saved.t, saved.q
        if type(ci) == "table" then ci.IsLoggingChat = savedCi end
    end
end

--- A fake client around the real recorder wrapper, plus a chat frame spy.
--- Returns { fire = fn(msg, stack), chat = {lines} } and the restore.
local function newClient()
    local saved = {
        get = _G.geterrorhandler, set = _G.seterrorhandler,
        stack = _G.debugstack, chatFrame = _G.DEFAULT_CHAT_FRAME,
        errors = FX.db.errors, since = Errors.sinceLoad, ignored = Errors.ignored,
        logOn = FX.db.logOn,
    }
    Errors:Uninstall()
    local client = { chat = {}, stack = FOREIGN_STACK, prevCalls = 0 }
    client.current = function() client.prevCalls = client.prevCalls + 1 end
    _G.geterrorhandler = function() return client.current end
    _G.seterrorhandler = function(h) client.current = h end
    _G.debugstack = function() return client.stack end
    _G.DEFAULT_CHAT_FRAME = {
        AddMessage = function(_, text)
            -- Only the recorder copies: FX.Print status lines share the frame.
            if tostring(text):find("[FX-ERR]", 1, true) == 1 then
                client.chat[#client.chat + 1] = text
            end
        end,
    }
    FX.db.errors = nil
    Errors.sinceLoad, Errors.ignored = 0, 0
    assertTrue(Errors:Install())
    function client.fire(msg, stack)
        -- The scripted stack is live for this call only: errors the sim
        -- raises on its own meanwhile must not look like ours.
        client.stack = stack or FORTE_STACK
        local r = client.current(msg)
        client.stack = FOREIGN_STACK
        return r
    end
    return client, function()
        Log:Disable()
        Errors:Uninstall()
        _G.geterrorhandler, _G.seterrorhandler = saved.get, saved.set
        _G.debugstack, _G.DEFAULT_CHAT_FRAME = saved.stack, saved.chatFrame
        FX.db.errors = saved.errors
        Errors.sinceLoad, Errors.ignored = saved.since, saved.ignored
        FX.db.logOn = saved.logOn
        Errors:Install()
    end
end

-- ============================================================ the shape ==

test("the Log rides the module registry (M4: no file-top registrant)",
function()
    assertNotNil(Log, "FX.LogModule is loaded by Forte_Core")
    assertNotNil(FX.modules["Log"],
        "the login re-apply rides FX.RegisterModule (Core/Init.lua's law:"
        .. " login work belongs in OnEnable, which the pass calls DIRECTLY)")
    assertEquals(Log, FX.modules["Log"])
    assertNotNil(FX.slashSubs["log"], "the /fx log sub rides the seam")
end)

test("the default install is OFF: nothing subscribed, no SavedVariables write",
function()
    assertEquals(false, Log.on, "a fresh session is not logging")
    assertNil(FX.db and FX.db.logOn,
        "FX.db.logOn is written only by Log:Enable (the ONE SV key of this"
        .. " module); a fresh install carries no key")
    if FX._loginDone then
        assertEquals(true, FX._enabledModules["Log"],
            "the login pass ran the Log's OnEnable -- on a fresh install that"
            .. " is the no-op leg")
    end
    assertEquals(false, Log.on, "and the no-op is total")
end)

-- ======================================================== the status line ==

test("/fx log status has no chatlog field and never touches the chat-logging surface",
function()
    local hits, restoreSpies = installChatSpies()
    local lines, rp = capturePrint()
    local ok, err = pcall(FX.OnSlash, "log")
    rp(); restoreSpies()
    assertTrue(ok, "the bare status does not raise: " .. tostring(err))
    assertTrue(hasLine(lines, "Log: errors->chat=false"),
        "the status line printed: " .. (lines[1] or "<nothing>"))
    for _, line in ipairs(lines) do
        assertNil(line:find("chatlog", 1, true), "no chatlog field: " .. line)
    end
    assertEquals(0, hits.n, "the status never calls LoggingChat / IsLoggingChat: "
        .. table.concat(hits.names, ","))
end)

test("/fx log on|off|test never call LoggingChat or IsLoggingChat", function()
    local client, restore = newClient()
    local hits, restoreSpies = installChatSpies()
    local lines, rp = capturePrint()
    local results = {}
    for _, cmd in ipairs({ "log on", "log", "log test", "log off", "log" }) do
        local ok, err = pcall(FX.OnSlash, cmd)
        results[#results + 1] = ok or (cmd .. ": " .. tostring(err))
    end
    rp(); restoreSpies()
    local logOn = FX.db.logOn
    restore()
    for _, r in ipairs(results) do assertEquals(true, r) end
    assertEquals(0, hits.n, "no chat-logging call at all: " .. table.concat(hits.names, ","))
    assertNil(logOn, "off cleared the stored switch")
    for _, line in ipairs(lines) do
        assertNil(line:find("chatlog", 1, true), "no chatlog field: " .. line)
    end
    assertTrue(hasLine(lines, "Log: errors->chat=true"), "the on status")
end)

-- ================================================ on = the [FX-ERR] copy ==

test("/fx log on copies recorded errors to chat as [FX-ERR]; foreign errors and off do not",
function()
    local client, restore = newClient()
    local lines, rp = capturePrint()
    pcall(FX.OnSlash, "log on")
    rp()
    assertEquals(true, Log.on)
    assertEquals(true, FX.db.logOn, "the switch persists")
    client.fire(FORTE_MSG, FORTE_STACK)
    client.fire(FOREIGN_MSG, FOREIGN_STACK)
    local afterOn = #client.chat
    local first = client.chat[1]
    lines, rp = capturePrint()
    pcall(FX.OnSlash, "log off")
    rp()
    client.fire("Interface\\AddOns\\Forte_Hunter\\X.lua:1: later", FORTE_STACK)
    local afterOff = #client.chat
    local prevCalls = client.prevCalls
    restore()
    assertEquals(1, afterOn, "exactly the recorded (Forte) error was copied")
    assertEquals("[FX-ERR] " .. FORTE_MSG:gsub("|", "||"), first)
    assertEquals(1, afterOff, "off stops the copy")
    assertEquals(3, prevCalls, "the previous handler ran once per error throughout")
end)

test("the other kinds are copied with their kind", function()
    local client, restore = newClient()
    pcall(FX.OnSlash, "log on")
    if not Errors._frame then Errors:OnEnable() end
    local script = Errors._frame and Errors._frame:GetScript("OnEvent")
    assertNotNil(script)
    script(Errors._frame, "ADDON_ACTION_BLOCKED", "Forte_Timer", "Frame:Show()")
    local chat = client.chat
    restore()
    assertEquals(1, #chat)
    assertEquals("[FX-ERR] [blocked] Forte_Timer: Frame:Show()", chat[1])
end)

test("/fx log on twice subscribes once", function()
    local client, restore = newClient()
    pcall(FX.OnSlash, "log on")
    pcall(FX.OnSlash, "log on")
    client.fire(FORTE_MSG, FORTE_STACK)
    local n = #client.chat
    restore()
    assertEquals(1, n)
end)

-- ========================================================== m5: the test ==

test("m5: /fx log test survives a missing handler getter and reports through a present one",
function()
    local saved = { g = _G.geterrorhandler, s = _G.seterrorhandler }
    _G.geterrorhandler = nil
    local ok, err = pcall(FX.OnSlash, "log test")
    _G.geterrorhandler = saved.g
    _G.seterrorhandler = saved.s
    assertTrue(ok, "the self-test with NO handler getter: " .. tostring(err))

    local got = {}
    _G.geterrorhandler = function()
        return function(e) got[#got + 1] = tostring(e) end
    end
    ok, err = pcall(FX.OnSlash, "log test")
    _G.geterrorhandler = saved.g
    _G.seterrorhandler = saved.s
    assertTrue(ok, "the self-test with a handler getter: " .. tostring(err))
    assertEquals(1, #got, "the self-test is the one deliberate line through the handler")
    assertTrue(got[1]:find("FX log self%-test") ~= nil,
        "and it carries its label: " .. got[1])
end)

-- ======================================================= M4: the lifecycle ==

test("M4: Log:OnEnable re-applies a stored switch (migration: logOn keeps its meaning)",
function()
    local client, restore = newClient()
    local hits, restoreSpies = installChatSpies()
    assertEquals(false, Log.on, "start OFF")
    FX.db.logOn = true                      -- what an older build stored
    Log:OnEnable()
    assertEquals(true, Log.on, "the stored `on` re-applies through OnEnable")
    Log:OnEnable()                          -- idempotence
    client.fire(FORTE_MSG, FORTE_STACK)
    local n = #client.chat
    Log:Disable()
    assertEquals(false, Log.on)
    assertNil(FX.db.logOn, "Disable cleared the stored key")
    Log:OnEnable()
    assertEquals(false, Log.on, "no stored choice, no enable")
    restoreSpies()
    restore()
    assertEquals(1, n, "the re-applied switch copies errors, once")
    assertEquals(0, hits.n, "and never calls the chat-logging surface")
end)

-- ============================================ update hazard: no Errors.lua ==

test("without FX.Errors (new .toc file not found after a /reload update) /fx log never raises",
function()
    local savedErrors, savedLogOn = FX.Errors, FX.db.logOn
    local lines, rp = capturePrint()
    local results = {}
    local ok, err = pcall(function()
        FX.Errors = nil
        for _, cmd in ipairs({ "log on", "log", "log off" }) do
            local okCmd, errCmd = pcall(FX.OnSlash, cmd)
            results[#results + 1] = okCmd or (cmd .. ": " .. tostring(errCmd))
            if cmd == "log on" then
                results.onAfter = Log.on
                results.stored = FX.db.logOn
            end
        end
        -- A stored switch at login (Log:OnEnable) with the module absent.
        FX.db.logOn = true
        local okEn, errEn = pcall(Log.OnEnable, Log)
        results[#results + 1] = okEn or ("OnEnable: " .. tostring(errEn))
        results.enableOn = Log.on
        local okOff, errOff = pcall(Log.Disable, Log)
        results[#results + 1] = okOff or ("Disable: " .. tostring(errOff))
    end)
    -- Guarded teardown: always runs, whatever the body did.
    pcall(Log.Disable, Log)
    Log.on = false
    FX.Errors, FX.db.logOn = savedErrors, savedLogOn
    rp()
    assertTrue(ok, "the body raised: " .. tostring(err))
    for _, r in ipairs(results) do assertEquals(true, r) end
    assertEquals(true, results.onAfter, "the switch itself still turns on")
    assertEquals(true, results.stored)
    assertEquals(true, results.enableOn, "the stored switch re-applies")
    local notices = 0
    for _, line in ipairs(lines) do
        if line:find("error recorder (Core/Errors.lua) is not loaded", 1, true) then
            notices = notices + 1
        end
    end
    assertEquals(2, notices, "`/fx log on` and the login re-apply each say once that a restart is needed")
    assertTrue(hasLine(lines, "restart the game"), "the status line works and names the restart")
    assertEquals(savedErrors, FX.Errors, "the recorder is back")
end)

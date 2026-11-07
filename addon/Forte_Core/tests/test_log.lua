-- addon/Forte_Core/tests/test_log.lua
-- Code-review-10 M3 + M4 + m5, section (c) MT-16: `Log.lua` was the whole
-- file with NO suite, and the two shipped bugs are exactly what a
-- stub-surface test catches:
--
--   * M3 -- the bare `/fx log` status read the chat-logging state with
--     `_G.LoggingChat()`; the catalog declares `LoggingChat(enable)` (a
--     REQUIRED boolean -- the query twin is `IsLoggingChat()`), the C-side
--     usage error it raises rode `FX.OnSlash`'s UNPROTECTED sub dispatch
--     (Core/Init.lua: `fn(rest)` -- no pcall), and the everyday "what's the
--     state" command died on the shipped client. The legs below run the REAL
--     slash path with the query absent, raising, and returning, and the
--     catalog-shaped `LoggingChat` (raises on a nil argument -- the exact
--     argless-call witness).
--   * m5 -- `/fx log test` called `_G.geterrorhandler()` UNGATED (the
--     "attempt to call a nil value" class in any environment without the
--     client's handler getter -- the sim) behind a `pcall(error, ...)`
--     decoration that never reached any handler.
--   * M4 -- the login re-apply rode a file-top `CreateFrame` +
--     `RegisterEvent("PLAYER_LOGIN")`, a SECOND login-time registrant where
--     the law allows only Forte_Core's bootstrap frame. The file rides the
--     module registry now (FX.RegisterModule), and the legs pin the registry,
--     the ledger, the default-OFF install and the re-apply seam.
--
-- Every leg installs and restores the client globals it touches; the
-- slash is driven through `FX.OnSlash` (the real dispatch, the Options
-- suite's idiom), and the prints are captured through `FX.Print`.

local FX = ForteXorcist
local Log = FX.LogModule

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

--- Install the chat-logging surface: the QUERY (`IsLoggingChat`) and the
--- TOGGLER (`LoggingChat`, catalog-shaped: a required boolean).
local function installChatSurface(query, toggler)
    local saved = { q = _G.IsLoggingChat, t = _G.LoggingChat }
    _G.IsLoggingChat = query
    _G.LoggingChat = toggler
    return saved
end
local function restoreChatSurface(saved)
    _G.IsLoggingChat = saved.q
    _G.LoggingChat = saved.t
end

-- ============================================================ the shape ==

test("the Log rides the module registry (M4: no file-top registrant)",
function()
    assertNotNil(Log, "FX.LogModule is loaded by Forte_Core")
    assertNotNil(FX.modules["Log"],
        "the login re-apply rides FX.RegisterModule (Core/Init.lua's law:"
        .. " login work belongs in OnEnable, which the pass calls DIRECTLY)"
        .. " -- the old file-top CreateFrame + PLAYER_LOGIN was the second"
        .. " silent registrant the single-registrant law exists to stop")
    assertEquals(Log, FX.modules["Log"])
    assertNotNil(FX.slashSubs["log"], "the /fx log sub rides the seam")
end)

test("the default install is OFF: no chat logging armed, no SavedVariables write",
function()
    assertEquals(false, Log.on, "a fresh session is not logging")
    assertNil(FX.db and FX.db.logOn,
        "FX.db.logOn is written only by Log:Enable (the ONE SV key of this"
        .. " module); a fresh install carries no key")
    -- The enable the login pass ran (FX._loginDone) called OnEnable with no
    -- stored choice: the enable must not have enabled anything.
    if FX._loginDone then
        assertEquals(true, FX._enabledModules["Log"],
            "the login pass ran the Log's OnEnable -- on a fresh install that"
            .. " is the no-op leg")
    end
    assertEquals(false, Log.on, "and the no-op is total")
end)

-- ======================================================== M3: the status ==

test("M3: the bare /fx log with the catalog's required-arg LoggingChat present does NOT raise",
function()
    -- The exact M3 witness. The old Status called `_G.LoggingChat()` -- the
    -- C-side usage error that raises rode FX.OnSlash's unprotected dispatch,
    -- so the whole slash command died. The new read prefers IsLoggingChat
    -- and never calls the toggler with no argument.
    local calls = {}
    local saved = installChatSurface(nil, function(enable)
        if enable == nil then error("LoggingChat: boolean expected", 0) end
        calls[#calls + 1] = enable
    end)
    local lines, restorePrint = capturePrint()
    local ok, err = pcall(FX.OnSlash, "log")
    restorePrint()
    restoreChatSurface(saved)
    assertTrue(ok, "the bare status survives the catalog-shaped toggler: "
        .. tostring(err))
    assertEquals(0, #calls,
        "the STATUS line never touches the toggler at all -- it is a read")
    assertTrue(hasLine(lines, "Log: errors->chat="),
        "the status line printed: " .. (lines[1] or "<nothing>"))
    assertTrue(hasLine(lines, "chatlog=false"),
        "no lawful query, no answer: the state reads false")
end)

test("M3: the query absent is inert; the query raising is absorbed; the query answering true reads true",
function()
    -- (a) absent: nothing is callable, the read defaults false.
    local saved = installChatSurface(nil, nil)
    local lines, rp = capturePrint()
    local okA = pcall(FX.OnSlash, "log")
    rp(); restoreChatSurface(saved)
    assertTrue(okA, "a bare status with NO chat-logging surface must not raise")
    assertTrue(hasLine(lines, "chatlog=false"))

    -- (b) raising: the read is pcall'd, so a raising query is a "false".
    saved = installChatSurface(function()
        error("FXTEST-QUERY-RAISE", 0)
    end, nil)
    lines, rp = capturePrint()
    local okB = pcall(FX.OnSlash, "log")
    rp(); restoreChatSurface(saved)
    assertTrue(okB, "a raising query must not reach the slash dispatch")
    assertTrue(hasLine(lines, "chatlog=false"))

    -- (c) answering: the state rides the answer.
    saved = installChatSurface(function() return true end, nil)
    lines, rp = capturePrint()
    local okC = pcall(FX.OnSlash, "log")
    rp(); restoreChatSurface(saved)
    assertTrue(okC)
    assertTrue(hasLine(lines, "chatlog=true"),
        "the query's TRUE is the state the status prints")
end)

test("M3: /fx log on drives the toggler WITH its boolean (the catalog form, never argless)",
function()
    local calls = {}
    local saved = installChatSurface(function() return false end,
        function(enable) calls[#calls + 1] = enable end)
    local lines, rp = capturePrint()
    local ok = pcall(FX.OnSlash, "log on")
    rp(); restoreChatSurface(saved)
    assertTrue(ok, "/fx log on must not raise")
    assertEquals(1, #calls, "Enable drove the toggler exactly once")
    assertEquals(true, calls[1], "with the required boolean true")
    Log:Disable()                                  -- leave the session off
    assertNil(FX.db and FX.db.logOn, "Disable clears the SV key (no growth)")
end)

-- ========================================================== m5: the test ==

test("m5: /fx log test survives a missing handler getter and reports through a present one",
function()
    -- (a) the sim shape: no client handler getter at all. The old shape's
    -- second line called a nil value and died.
    local saved = { g = _G.geterrorhandler, s = _G.seterrorhandler }
    _G.geterrorhandler = nil
    local ok, err = pcall(FX.OnSlash, "log test")
    _G.geterrorhandler = saved.g
    _G.seterrorhandler = saved.s
    assertTrue(ok, "the self-test with NO handler getter: " .. tostring(err))

    -- (b) the client shape: the deliberate line is handed to the handler.
    local got = {}
    _G.geterrorhandler = function()
        return function(err) got[#got + 1] = tostring(err) end
    end
    ok, err = pcall(FX.OnSlash, "log test")
    _G.geterrorhandler = saved.g
    _G.seterrorhandler = saved.s
    assertTrue(ok, "the self-test with a handler getter: " .. tostring(err))
    assertEquals(1, #got,
        "the self-test is the one deliberate line through the handler")
    assertTrue(got[1]:find("FX log self%-test") ~= nil,
        "and it carries its label: " .. got[1])
end)

-- ======================================================= M4: the lifecycle ==

test("M4: Log:OnEnable re-applies the stored choice and the enable/disable pair round-trips",
function()
    assertEquals(false, Log.on, "start OFF")
    local calls = {}
    local saved = installChatSurface(function() return #calls > 0 end,
        function(enable) calls[#calls + 1] = enable end)
    -- The stored choice: the login pass's OnEnable leg enables.
    FX.db.logOn = true
    Log:OnEnable()
    assertEquals(true, Log.on, "the stored `on` re-applies through OnEnable")
    assertEquals(1, #calls, "the re-apply armed the chat logging once")
    assertEquals(true, calls[1])
    -- Idempotence: the enable gate.
    Log:OnEnable()
    assertEquals(1, #calls, "a second re-apply is a no-op")
    Log:Disable()
    assertEquals(false, Log.on)
    assertEquals(2, #calls)
    assertEquals(false, calls[2], "the disable disarms with the false boolean")
    -- The no-choice default: OnEnable with no stored key enables nothing.
    assertNil(FX.db.logOn, "Disable cleared the stored key")
    Log:OnEnable()
    assertEquals(false, Log.on, "no stored choice, no enable")
    restoreChatSurface(saved)
end)

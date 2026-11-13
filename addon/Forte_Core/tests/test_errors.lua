-- addon/Forte_Core/tests/test_errors.lua
-- Core/Errors.lua (PLAN.md §11.11): the shipped, silent error recorder.
--
-- Everything runs through the REAL pieces: the real handler wrapper
-- (installed on a fake client handler surface -- `geterrorhandler` /
-- `seterrorhandler` doubles, a scripted `debugstack`), the real module event
-- script (the payloads are the pinned catalog's: ADDON_ACTION_BLOCKED /
-- ADDON_ACTION_FORBIDDEN (isTainted: cstring, function: cstring), LUA_WARNING
-- (warningText: cstring)) and the real slash path (FX.OnSlash).
--
-- wow-ui-sim's own `debugstack` is a stub that returns a fixed Blizzard
-- frame list, so every leg scripts the stack it wants. Every leg restores
-- the globals it touched, the recorder's state and the SavedVariables table.

local FX = ForteXorcist
local Errors = FX.Errors

local FORTE_MSG = "Interface\\AddOns\\Forte_Timer\\Core\\Rows.lua:123: attempt to index a nil value"
local FORTE_STACK = table.concat({
    "[C]: in function 'error'",
    "|cffff0000Interface\\AddOns\\Forte_Timer\\Core\\Rows.lua:123: in function 'Sweep'|r",
    "Interface\\AddOns\\Forte_Core\\Core\\Errors.lua:300: in function <Errors.lua:290>",
    "Interface\\AddOns\\Forte_Timer\\Core\\Module.lua:45: in function <Module.lua:40>",
    "Interface\\AddOns\\Forte_Core\\Core\\Events.lua:170: in function 'Fire'",
    "Interface\\AddOns\\Forte_Core\\Core\\Init.lua:233: in function <Init.lua:233>",
}, "\n")
local FOREIGN_MSG = "Interface\\AddOns\\Bagnon\\Main.lua:9: boom"
local FOREIGN_STACK = "Interface\\AddOns\\Bagnon\\Main.lua:9: in function 'Open'\n"
    .. "Interface\\AddOns\\Bagnon\\Core.lua:4: in function <Core.lua:3>"

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

--- A fake client around the recorder: handler doubles whose "current
--- handler" lives in `client.current`, a scripted stack, a clock, a clean
--- store. Returns the client and the restore function.
local function newClient(base)
    local saved = {
        get = _G.geterrorhandler, set = _G.seterrorhandler,
        stack = _G.debugstack, secret = _G.issecretvalue,
        now = Errors.now, errors = FX.db.errors,
        since = Errors.sinceLoad, ignored = Errors.ignored,
    }
    Errors:Uninstall()          -- hand the real chain back to the real client
    local client = { calls = {}, stack = FOREIGN_STACK, clock = 1000 }
    client.base = base or function(msg) client.calls[#client.calls + 1] = msg end
    client.current = client.base
    _G.geterrorhandler = function() return client.current end
    _G.seterrorhandler = function(h) client.current = h end
    _G.debugstack = function() return client.stack end
    Errors.now = function() return client.clock end
    FX.db.errors = nil
    Errors.sinceLoad = 0
    Errors.ignored = 0
    assertTrue(Errors:Install(), "the wrapper installs on the fake client")
    function client.fire(msg, stack)
        -- The scripted stack is live for this call only: errors the sim
        -- raises on its own meanwhile must not look like ours.
        client.stack = stack or FORTE_STACK
        local r = client.current(msg)
        client.stack = FOREIGN_STACK
        return r
    end
    local function restore()
        Errors:Uninstall()
        _G.geterrorhandler, _G.seterrorhandler = saved.get, saved.set
        _G.debugstack, _G.issecretvalue = saved.stack, saved.secret
        Errors.now = saved.now
        FX.db.errors = saved.errors
        Errors.sinceLoad, Errors.ignored = saved.since, saved.ignored
        Errors:Install()        -- back onto the real client handler
    end
    return client, restore
end

local function storedList()
    return FX.db.errors and FX.db.errors.list
end

local function eventScript()
    if not Errors._frame then Errors:OnEnable() end
    local frame = Errors._frame
    assertNotNil(frame, "OnEnable creates the recorder's event frame")
    local script = frame:GetScript("OnEvent")
    assertEquals("function", type(script))
    return function(...) script(frame, ...) end
end

-- ============================================================== the shape ==

test("Errors rides the module registry and the /fx errors seam", function()
    assertNotNil(Errors, "FX.Errors is loaded by Forte_Core")
    assertEquals(Errors, FX.modules["Errors"])
    assertNotNil(FX.slashSubs["errors"])
    assertEquals("number", type(Errors.sinceLoad))
end)

-- ============================================================== recording ==

test("a Forte error is recorded with a trimmed, clean stack; the previous handler runs once",
function()
    local client, restore = newClient()
    local ok, err = pcall(function()
        client.fire(FORTE_MSG .. string.rep("x", 400))
    end)
    local list = storedList()
    local calls = client.calls
    local since = Errors.sinceLoad
    restore()
    assertTrue(ok, "the wrapper must not raise: " .. tostring(err))
    assertNotNil(list)
    assertEquals(1, #list)
    local e = list[1]
    assertEquals("error", e.kind)
    assertEquals(1, e.count)
    assertEquals(1000, e.first)
    assertEquals(1000, e.last)
    assertEquals(1, e.session)
    assertTrue(#e.msg <= 300, "msg is cut at 300: " .. #e.msg)
    assertEquals(FORTE_MSG:sub(1, 40), e.msg:sub(1, 40))
    local frames = {}
    for line in e.stack:gmatch("[^\n]+") do frames[#frames + 1] = line end
    assertEquals(3, #frames, "top 3 frames")
    assertTrue(frames[1]:find("Rows.lua:123", 1, true) ~= nil, "first frame: " .. frames[1])
    assertNil(e.stack:find("|c", 1, true), "colour escapes are stripped")
    assertNil(e.stack:find("[C]", 1, true), "C frames are dropped")
    assertNil(e.stack:find("Errors.lua", 1, true), "our own recorder frames are dropped")
    assertEquals(1, #calls, "the previous handler ran exactly once")
    assertEquals(FORTE_MSG .. string.rep("x", 400), calls[1], "with the untouched message")
    assertEquals(1, since)
end)

test("stack frames are cut at 200 chars", function()
    local client, restore = newClient()
    client.fire(FORTE_MSG, "Interface\\AddOns\\Forte_Timer\\A.lua:1: in function '"
        .. string.rep("y", 500) .. "'")
    local list = storedList()
    restore()
    assertEquals(200, #list[1].stack)
end)

test("a repeat is de-duplicated and counted; a different first frame is its own entry",
function()
    local client, restore = newClient()
    client.fire(FORTE_MSG, FORTE_STACK)
    client.clock = 1005
    client.fire("Interface\\AddOns\\Forte_Hunter\\X.lua:1: other",
        "Interface\\AddOns\\Forte_Hunter\\X.lua:1: in function 'Z'")
    client.clock = 1010
    client.fire(FORTE_MSG, FORTE_STACK)                     -- the repeat
    client.fire(FORTE_MSG, "Interface\\AddOns\\Forte_Timer\\Other.lua:7: in function 'Q'")
    local list = storedList()
    local since = Errors.sinceLoad
    restore()
    assertEquals(3, #list, "kind+msg+first stack line key: 3 distinct entries")
    assertEquals("other", list[1].msg:match("other"), "the untouched entry keeps its place")
    assertEquals(2, list[2].count, "the repeat is counted")
    assertEquals(1000, list[2].first)
    assertEquals(1010, list[2].last)
    assertEquals(FORTE_MSG, list[2].msg, "and moved to the newest end")
    assertEquals(1, list[3].count)
    assertEquals(4, since, "sinceLoad counts every stored occurrence")
end)

test("the cap of 20 keeps the newest", function()
    local client, restore = newClient()
    for i = 1, 25 do
        client.fire("Interface\\AddOns\\Forte_Timer\\R.lua:1: err #" .. i,
            "Interface\\AddOns\\Forte_Timer\\R.lua:1: in function 'F'")
    end
    local list = storedList()
    restore()
    assertEquals(20, #list)
    assertTrue(list[1].msg:find("err #6", 1, true) ~= nil, "oldest kept is #6: " .. list[1].msg)
    assertTrue(list[20].msg:find("err #25", 1, true) ~= nil, "newest last: " .. list[20].msg)
end)

test("a foreign addon's error is not stored; the previous handler still runs once",
function()
    local client, restore = newClient()
    client.fire(FOREIGN_MSG, FOREIGN_STACK)
    local stored = FX.db.errors
    local calls, ignored, since = client.calls, Errors.ignored, Errors.sinceLoad
    restore()
    assertNil(stored, "nothing written for another addon's error")
    assertEquals(1, #calls, "previous handler ran once")
    assertEquals(FOREIGN_MSG, calls[1])
    assertEquals(1, ignored, "the ignored-foreign counter moved")
    assertEquals(0, since)
end)

test("an error whose message is foreign but whose stack passes through our code is ours",
function()
    local client, restore = newClient()
    client.fire(FOREIGN_MSG, "Interface\\AddOns\\Bagnon\\Main.lua:9: in function 'Open'\n"
        .. "Interface\\AddOns\\Forte_Cooldown\\Display.lua:50: in function 'OnUpdate'")
    local list = storedList()
    restore()
    assertEquals(1, #list)
end)

-- ============================================================ secret safety ==

test("a secret message never raises, is stored as <unreadable>, and still reaches the previous handler",
function()
    local client, restore = newClient()
    -- Any operation on the secret raises: it proves nothing touches it before
    -- the issecretvalue classification (PlainOrNil) has answered.
    local trap = function() error("FXTEST: operation on a secret value", 0) end
    local SECRET = setmetatable({}, {
        __index = trap, __newindex = trap, __len = trap, __concat = trap,
        __tostring = trap, __eq = trap, __lt = trap, __le = trap, __call = trap,
    })
    _G.issecretvalue = function(v) return rawequal(v, SECRET) end
    local ok, err = pcall(client.fire, SECRET, FORTE_STACK)
    local list = storedList()
    local calls = client.calls
    -- Same secret, but a stack that is not ours: ignored, not stored.
    Errors.ignored = 0
    local ok2, err2 = pcall(client.fire, SECRET, FOREIGN_STACK)
    local ignored = Errors.ignored
    local count = #storedList()
    restore()
    assertTrue(ok, "a secret message must not raise: " .. tostring(err))
    assertEquals(1, #list)
    assertEquals("<unreadable>", list[1].msg)
    assertTrue(rawequal(SECRET, calls[1]), "the previous handler got the value untouched")
    assertTrue(ok2, tostring(err2))
    assertEquals(1, ignored)
    assertEquals(1, count, "the foreign secret stored nothing")
end)

test("a non-string message (table) is <unreadable>, a number is its text", function()
    local client, restore = newClient()
    client.fire({}, FORTE_STACK)
    client.fire(42, "Interface\\AddOns\\Forte_Timer\\N.lua:1: in function 'N'")
    local list = storedList()
    restore()
    assertEquals("<unreadable>", list[1].msg)
    assertEquals("42", list[2].msg)
end)

-- ====================================================== chain robustness ==

test("a raising previous handler does not break recording or the caller", function()
    local client, restore = newClient(function() error("FXTEST previous handler raised", 0) end)
    local ok, err = pcall(client.fire, FORTE_MSG, FORTE_STACK)
    local list = storedList()
    restore()
    assertTrue(ok, "the wrapper absorbs the previous handler's raise: " .. tostring(err))
    assertEquals(1, #list)
end)

test("an addon that REPLACES the handler later is re-chained, each handler runs once",
function()
    local client, restore = newClient()
    local replaced = 0
    client.current = function() replaced = replaced + 1 end   -- replaces ours, no chaining
    eventScript()("ADDON_LOADED", "SomeOtherAddon")           -- the re-assert point
    client.fire(FORTE_MSG, FORTE_STACK)
    local list = storedList()
    local calls = client.calls
    restore()
    assertEquals(1, #list, "recorded after the replacement")
    assertEquals(1, replaced, "the replacing handler runs once")
    assertEquals(0, #calls, "the replaced original is the replacer's business")
end)

test("an addon that WRAPS the handler does not recurse; every handler runs once", function()
    local client, restore = newClient()
    local ours, wrapped = client.current, 0
    client.current = function(msg) wrapped = wrapped + 1 return ours(msg) end
    eventScript()("PLAYER_ENTERING_WORLD", true, false)       -- re-chain on top of the wrapper
    local ok, err = pcall(client.fire, FORTE_MSG, FORTE_STACK)
    local list = storedList()
    local calls = client.calls
    restore()
    assertTrue(ok, tostring(err))
    assertEquals(1, #list)
    assertEquals(1, list[1].count, "recorded once, not once per link")
    assertEquals(1, wrapped, "the wrapper ran once")
    assertEquals(1, #calls, "the original ran once")
end)

test("re-entrancy: a previous handler that calls back in, and a recorder that errors into the handler",
function()
    -- (a) the previous handler calls the current handler again.
    local client, restore = newClient()
    local depth = 0
    client.base = function(msg)
        depth = depth + 1
        client.calls[#client.calls + 1] = msg
        if depth < 5 then client.current(msg) end
    end
    client.current = client.base
    Errors:Uninstall()
    assertTrue(Errors:Install())
    local ok, err = pcall(client.fire, FORTE_MSG, FORTE_STACK)
    local list = storedList()
    restore()
    assertTrue(ok, tostring(err))
    assertEquals(1, #list)
    assertEquals(1, list[1].count)
    assertTrue(depth <= 2, "the call-back was cut off, depth " .. depth)

    -- (b) the recorder itself raises into the handler path.
    local client2, restore2 = newClient()
    local realCapture, entered = Errors.Capture, 0
    Errors.Capture = function(self, kind, msg)
        entered = entered + 1
        client2.current(msg)                 -- an error inside the recorder
        error("FXTEST recorder raised", 0)
    end
    local ok2, err2 = pcall(client2.fire, FORTE_MSG, FORTE_STACK)
    Errors.Capture = realCapture
    local calls2 = client2.calls
    restore2()
    assertTrue(ok2, "the handler never raises: " .. tostring(err2))
    assertEquals(1, entered, "the recorder is not re-entered")
    assertTrue(#calls2 >= 1, "the chain still ran")
end)

-- ======================================================= the other events ==

test("ADDON_ACTION_BLOCKED / _FORBIDDEN for our addon are recorded, for another addon they are not",
function()
    local client, restore = newClient()
    local fire = eventScript()
    fire("ADDON_ACTION_BLOCKED", "Forte_Timer", "Frame:Show()")
    fire("ADDON_ACTION_FORBIDDEN", "Forte_Hunter", "SetAttribute()")
    fire("ADDON_ACTION_BLOCKED", "SomeOtherAddon", "Frame:Show()")
    fire("ADDON_ACTION_FORBIDDEN", "SomeOtherAddon", "Forte_Misnamed")  -- names us in the function slot
    local list = storedList()
    local ignored, since = Errors.ignored, Errors.sinceLoad
    restore()
    assertEquals(3, #list)
    assertEquals("blocked", list[1].kind)
    assertEquals("Forte_Timer: Frame:Show()", list[1].msg)
    assertEquals("forbidden", list[2].kind)
    assertEquals("Forte_Hunter: SetAttribute()", list[2].msg)
    assertEquals(1, ignored, "the other addon's blocked action only bumped the counter")
    assertEquals(3, since)
end)

test("a secret blocked-action payload does not raise and is ignored unless the other half names us",
function()
    local client, restore = newClient()
    local trap = function() error("FXTEST: operation on a secret value", 0) end
    local SECRET = setmetatable({}, { __index = trap, __len = trap, __concat = trap,
        __tostring = trap, __eq = trap })
    _G.issecretvalue = function(v) return rawequal(v, SECRET) end
    local fire = eventScript()
    local ok1 = pcall(fire, "ADDON_ACTION_BLOCKED", SECRET, SECRET)
    local ok2 = pcall(fire, "ADDON_ACTION_BLOCKED", SECRET, "Forte_Timer:Show")
    local list = storedList()
    restore()
    assertTrue(ok1 and ok2, "no raise on a secret payload")
    assertEquals(1, #list)
    assertEquals("<unreadable>: Forte_Timer:Show", list[1].msg)
end)

test("LUA_WARNING: a Forte warning is recorded, another addon's is not", function()
    local client, restore = newClient()
    local fire = eventScript()
    fire("LUA_WARNING", "Interface\\AddOns\\Forte_Options\\Page.lua:4: unused variable")
    client.stack = FOREIGN_STACK
    fire("LUA_WARNING", "Interface\\AddOns\\Bagnon\\Main.lua:4: unused variable")
    fire("LUA_WARNING", 1, "Interface\\AddOns\\Forte_Cooldown\\X.lua:2: shadowed")  -- (type, text) shape
    local list = storedList()
    restore()
    assertEquals(2, #list)
    assertEquals("warning", list[1].kind)
    assertTrue(list[1].msg:find("Forte_Options", 1, true) ~= nil)
    assertTrue(list[2].msg:find("Forte_Cooldown", 1, true) ~= nil, "the text is the LAST argument")
end)

-- ============================================================ the slash path ==

test("/fx errors prints the list, /fx errors clear empties it", function()
    local client, restore = newClient()
    client.fire(FORTE_MSG, FORTE_STACK)
    client.fire(FORTE_MSG, FORTE_STACK)
    local lines, rp = capturePrint()
    local ok1, e1 = pcall(FX.OnSlash, "errors")
    rp()
    assertTrue(ok1, tostring(e1))
    assertTrue(hasLine(lines, "Errors: 1 recorded"), "header: " .. tostring(lines[1]))
    assertTrue(hasLine(lines, "[error] x2"), "the repeat count shows")
    assertTrue(hasLine(lines, "Rows.lua:123"), "message and first frame show")

    lines, rp = capturePrint()
    local ok2, e2 = pcall(FX.OnSlash, "errors clear")
    rp()
    assertTrue(ok2, tostring(e2))
    assertTrue(hasLine(lines, "cleared"))
    assertEquals(0, #storedList(), "the list is empty")
    assertEquals(0, Errors.sinceLoad, "and the load counter is re-armed")

    lines, rp = capturePrint()
    pcall(FX.OnSlash, "errors")
    rp()
    restore()
    assertTrue(hasLine(lines, "Errors: 0 recorded"))
end)

test("sparse: nothing is written before the first stored entry", function()
    local client, restore = newClient()
    local lines, rp = capturePrint()
    pcall(FX.OnSlash, "errors")
    pcall(FX.OnSlash, "errors clear")
    pcall(FX.OnSlash, "status")
    rp()
    client.fire(FOREIGN_MSG, FOREIGN_STACK)
    eventScript()("ADDON_ACTION_BLOCKED", "SomeOtherAddon", "X()")
    eventScript()("LUA_WARNING", "Bagnon: nothing")
    Errors:OnEnable()                                     -- a load with no table
    local untouched = FX.db.errors
    client.fire(FORTE_MSG, FORTE_STACK)
    local created = FX.db.errors
    restore()
    assertNil(untouched, "no errors table until the first stored entry")
    assertNotNil(created)
    assertEquals(1, created.session, "the first entry creates the table at session 1")
end)

test("the session counter bumps at every UI load once the table exists", function()
    local client, restore = newClient()
    FX.db.errors = { session = 4, list = {} }
    Errors:OnEnable()
    local first = FX.db.errors.session
    Errors:OnEnable()
    local second = FX.db.errors.session
    client.fire(FORTE_MSG, FORTE_STACK)
    local entrySession = FX.db.errors.list[1].session
    restore()
    assertEquals(5, first)
    assertEquals(6, second)
    assertEquals(6, entrySession, "entries carry the load they were seen in")
end)

test("a hand-damaged errors table is repaired by the next entry, never raised on", function()
    local client, restore = newClient()
    FX.db.errors = { session = "x", list = "y" }
    local lines, rp = capturePrint()
    local okShow = pcall(FX.OnSlash, "errors")
    rp()
    local okFire = pcall(client.fire, FORTE_MSG, FORTE_STACK)
    local e = FX.db.errors
    restore()
    assertTrue(okShow and okFire)
    assertEquals("table", type(e.list))
    assertEquals(1, #e.list)
    assertEquals("number", type(e.session))
end)

test("/fx status prints the recorder's line", function()
    local lines, rp = capturePrint()
    pcall(FX.OnSlash, "status")
    rp()
    assertTrue(hasLine(lines, "Errors: recorded="))
end)

-- Forte_Dev/Core.lua
-- The dev-only addon of the in-game loop (PLAN §11.11). NOT shipped: .pkgmeta ignores dev/, the
-- release zip is `git archive HEAD addon`. Namespace: ForteXorcist.Dev.
--
-- What lives here: the shared helpers (every live value is classified before it is stored or
-- compared), ForteDevDB, the /fxdev dispatcher, the DevCommands runner and the event frame.
-- Selftest.lua = the runner, Suites/*.lua = the assertions, Beacon.lua / Panel.lua = the screenshot
-- surface.
--
-- SAFETY (the dev loop's contract, tests/test_safety.lua pins it):
--   * no chat and no addon messages are ever sent; the only text output is the LOCAL chat frame
--     (DEFAULT_CHAT_FRAME:AddMessage) answering a /fxdev command;
--   * nothing protected or gameplay: no casting, targeting, movement, looting;
--   * in combat nothing runs except the armed combat suite's READ assertions (and the always-safe
--     status / panel / shot verbs); DevCommands are skipped in combat.
--
-- SECRET LAW: a live API value is never compared, concatenated or stored raw. It goes through
-- Dev.K / Dev.S (FX.Probe.K: "SECRET" for a secret, else type + plain rendering) or
-- Dev.plain (FX.Compat.PlainOrNil) first. ForteDevDB only ever holds plain strings/numbers/booleans.
--
-- No file-top RegisterEvent (AGENTS.md): the event frame is created in the module's OnEnable, which
-- Forte_Core's login pass calls. SavedVariables are readable from OnEnable on (the client fills
-- ForteDevDB before PLAYER_LOGIN), never at file load.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist

local Dev = {}
FX.Dev = Dev

-- ----------------------------------------------------------------- limits --
Dev.MAX_RUNS = 5          -- ForteDevDB.runs (contract: cap 5, newest last)
Dev.MAX_COMMANDS = 30     -- ForteDevDB.commands (contract: cap 30)
Dev.MAX_FAILS = 30        -- recorded FAIL entries per run (the client pauses error reports after 100/session)
Dev.MAX_TESTS = 150       -- recorded entries per run, all statuses; the counts keep counting past it
Dev.DETAIL_MAX = 160      -- characters kept of any detail / message
Dev.NAME_MAX = 80
Dev.COMBAT_DELAY = 3      -- seconds after PLAYER_REGEN_DISABLED the armed combat suite runs
Dev.COMMANDS_DELAY = 3    -- seconds after PLAYER_ENTERING_WORLD DevCommands run
Dev.COMMANDS_FALLBACK = 5 -- seconds after OnEnable, when no PLAYER_ENTERING_WORLD was seen (login fallback)
Dev.MAX_COMMAND_ENTRIES = 20

--- Session state (never saved).
Dev.state = {
    running = false,        -- a run is executing right now
    armed = false,          -- the combat suite waits for combat
    combatTimerSet = false,
    finished = false,       -- a run finished since this load
    lastRun = nil,
    pewSeen = false,
    commandsScheduled = false,
    commandsRan = false,
    runningCommands = false,
    panelOn = true,
    prevNonce = nil,        -- ForteDevDB.nonce as it was ON DISK at this load (persistence suite)
    castRing = nil,         -- K strings of own UNIT_SPELLCAST_SUCCEEDED ids while the combat suite is armed
}

--- Suite registry: { { name, group = "ooc"|"combat", fn = function(T) } ... } in load order.
Dev.suites = {}
function Dev.RegisterSuite(name, group, fn)
    Dev.suites[#Dev.suites + 1] = { name = name, group = group, fn = fn }
end

--- Timer seam (tests replace it; no sleeps in the suites).
function Dev.After(seconds, fn)
    local CT = _G.C_Timer
    if CT and CT.After then
        CT.After(seconds, fn)
    else
        fn()
    end
end

-- ------------------------------------------------------------ classifiers --

--- True when `v` is a secret value. Fails CLOSED: an issecretvalue that raises counts as secret
--- (the same posture as Compat.PlainOrNil). No issecretvalue at all = nothing is secret.
function Dev.isSecret(v)
    local f = _G.issecretvalue
    if type(f) ~= "function" then return false end
    local ok, secret = pcall(f, v)
    if not ok then return true end
    return secret and true or false
end

--- `v`, or nil for a secret / unknowable value (FX.Compat.PlainOrNil).
function Dev.plain(v)
    return FX.Compat.PlainOrNil(v)
end

--- FX.Probe.K (the classifier law): "SECRET" | "number:1" | "string:x" | "boolean:true" | "nil" | type.
function Dev.K(v)
    local P = FX.Probe
    if P and P.K then return P.K(v) end
    if Dev.isSecret(v) then return "SECRET" end
    local t = type(v)
    if t == "number" then return "number:" .. string.format("%.6g", v) end
    if t == "string" then return "string:" .. v end
    if t == "boolean" then return "boolean:" .. tostring(v) end
    if t == "nil" then return "nil" end
    return t
end

--- Shorten a plain string to `max` characters, newlines flattened.
function Dev.clip(s, max)
    s = tostring(s):gsub("[\r\n]+", " ")
    max = max or Dev.DETAIL_MAX
    if #s > max then s = s:sub(1, max - 3) .. "..." end
    return s
end

--- A short PLAIN rendering of any value for stored details: K without the type prefix.
function Dev.S(v, max)
    local k = Dev.K(v)
    k = k:gsub("^number:", ""):gsub("^boolean:", ""):gsub("^string:", "")
    return Dev.clip(k, max)
end

function Dev.now()
    local f = _G.time
    if type(f) == "function" then
        local ok, t = pcall(f)
        if ok and type(t) == "number" then return t end
    end
    return 0
end

function Dev.stamp()
    local s = _G.ForteDevStamp
    if type(s) == "string" and s ~= "" then return Dev.clip(s, 60) end
    return "unstamped"
end

--- "1.60.1.70888 (16001)" from GetBuildInfo, every value classified; "?" when unreadable.
function Dev.buildString()
    local f = _G.GetBuildInfo
    if type(f) ~= "function" then return "?" end
    local ok, vals = pcall(function() return { f() } end)
    if not ok then return "?" end
    local function pick(i)
        local p = Dev.plain(vals[i])
        if type(p) == "string" or type(p) == "number" then return Dev.clip(tostring(p), 24) end
        return nil
    end
    local version, build, toc = pick(1), pick(2), pick(4)
    if not version and not build then return "?" end
    local out = (version or "?") .. "." .. (build or "?")
    if toc then out = out .. " (" .. toc .. ")" end
    return out
end

function Dev.inCombat()
    local f = _G.InCombatLockdown
    if type(f) ~= "function" then return false end
    local ok, v = pcall(f)
    local p = ok and Dev.plain(v)
    return p and true or false
end

function Dev.inGroup()
    local f = _G.IsInGroup
    if type(f) ~= "function" then return false end
    local ok, v = pcall(f)
    local p = ok and Dev.plain(v)
    return p and true or false
end

--- The player's class token ("HUNTER"), nil when unknown.
function Dev.classToken()
    local c = FX._playerClass
    if type(c) == "string" and c ~= "" then return c:upper() end
    return nil
end

--- "HUNTER" -> "Hunter" (the FX.Data key).
function Dev.classTitle(token)
    token = token or Dev.classToken()
    if not token then return nil end
    return token:sub(1, 1) .. token:sub(2):lower()
end

--- C_AddOns.IsAddOnLoaded as a plain boolean; nil when the API cannot answer.
function Dev.isAddOnLoaded(name)
    local api = _G.C_AddOns
    if type(api) ~= "table" or type(api.IsAddOnLoaded) ~= "function" then return nil end
    local ok, a = pcall(api.IsAddOnLoaded, name)
    if not ok then return nil end
    local p = Dev.plain(a)
    if p == nil then return nil end
    return p and true or false
end

--- Local-only text output (the answer to a typed /fxdev). Never SendChatMessage / addon messages.
function Dev.print(text)
    local cf = _G.DEFAULT_CHAT_FRAME
    if cf and cf.AddMessage then
        cf:AddMessage("|cff55ccff[FXDEV]|r " .. tostring(text))
    end
end

-- ---------------------------------------------------------------- the DB --

--- ForteDevDB, repaired to the contract shape:
--- { stamp, build, runs = { run... cap 5 }, runId, commands = { cmd... cap 30 } }
--- (+ `nonce`, the persistence suite's key).
function Dev.DB()
    local db = _G.ForteDevDB
    if type(db) ~= "table" then
        db = {}
        _G.ForteDevDB = db
    end
    if type(db.runs) ~= "table" then db.runs = {} end
    if type(db.commands) ~= "table" then db.commands = {} end
    if type(db.runId) ~= "number" then db.runId = 0 end
    if type(db.stamp) ~= "string" then db.stamp = Dev.stamp() end
    if type(db.build) ~= "string" then db.build = Dev.buildString() end
    return db
end

local function copyNonce(n)
    if type(n) ~= "table" then return nil end
    if type(n.value) ~= "string" or type(n.check) ~= "string" then return nil end
    return { value = n.value, check = n.check,
        written = type(n.written) == "number" and n.written or 0,
        stamp = type(n.stamp) == "string" and n.stamp or "?" }
end

--- Load-time DB init: repair the shape, refresh stamp/build, capture the nonce the previous load wrote.
function Dev.InitDB()
    local db = Dev.DB()
    db.stamp = Dev.stamp()
    db.build = Dev.buildString()
    Dev.state.prevNonce = copyNonce(db.nonce)
    return db
end

local function trim(list, cap)
    while #list > cap do table.remove(list, 1) end
end

function Dev.AddRun(run)
    local db = Dev.DB()
    db.runs[#db.runs + 1] = run
    trim(db.runs, Dev.MAX_RUNS)
end

function Dev.RecordCommand(verb, ok, detail)
    local db = Dev.DB()
    db.commands[#db.commands + 1] = {
        t = Dev.now(),
        verb = Dev.clip(verb, 80),
        ok = ok and true or false,
        detail = Dev.clip(detail, Dev.DETAIL_MAX),
    }
    trim(db.commands, Dev.MAX_COMMANDS)
end

--- Repaint the screenshot surface. Each leg is protected: a paint failure must never kill a run.
function Dev.Repaint()
    if Dev.Beacon and Dev.Beacon.Paint then pcall(Dev.Beacon.Paint) end
    if Dev.Panel and Dev.Panel.Paint then pcall(Dev.Panel.Paint) end
end

-- ------------------------------------------------------------- the verbs --
-- A verb handler returns (ok, detail). `combatOk(rest)` marks the verbs allowed in combat.

Dev.USAGE = "/fxdev selftest [ooc|combat|all] | shot | status | panel on|off | run | clear"
Dev.verbs = {}

Dev.verbs.selftest = {
    combatOk = function(rest) return rest == "combat" end,
    fn = function(rest)
        local which = rest ~= "" and rest or "ooc"
        if which ~= "ooc" and which ~= "combat" and which ~= "all" then
            return false, "selftest: unknown suite '" .. Dev.clip(which, 20) .. "' (ooc|combat|all)"
        end
        return Dev.Selftest.Request(which)
    end,
}

Dev.verbs.shot = {
    combatOk = function() return true end,
    fn = function() return Dev.Shot() end,
}

Dev.verbs.status = {
    combatOk = function() return true end,
    fn = function() return true, Dev.StatusLine() end,
}

Dev.verbs.panel = {
    combatOk = function() return true end,
    fn = function(rest)
        if rest ~= "on" and rest ~= "off" then return false, "panel: on|off" end
        Dev.state.panelOn = (rest == "on")
        Dev.Repaint()
        return true, "panel " .. rest
    end,
}

Dev.verbs.run = {
    fn = function()
        if Dev.state.runningCommands then return false, "run: refused (already inside DevCommands)" end
        return Dev.RunCommands(true)
    end,
}

Dev.verbs.clear = {
    fn = function()
        local db = Dev.DB()
        db.runs, db.commands = {}, {}
        local st = Dev.state
        st.armed, st.finished, st.lastRun = false, false, nil
        if Dev.Selftest and Dev.Selftest.Disarm then Dev.Selftest.Disarm() end
        Dev.Repaint()
        return true, "cleared runs and commands (runId stays " .. db.runId .. ")"
    end,
}

--- One line of state: what `/fxdev status` prints and the host reads.
function Dev.StatusLine()
    local db = Dev.DB()
    local st = Dev.state
    local last = st.lastRun or db.runs[#db.runs]
    local lastText = "none"
    if type(last) == "table" then
        lastText = string.format("#%s %s pass=%s fail=%s skip=%s", tostring(last.id), tostring(last.suite),
            tostring(last.pass), tostring(last.fail), tostring(last.skip))
    end
    local E = FX.Errors
    local errs = E and Dev.plain(E.sinceLoad)
    return Dev.clip(string.format("stamp=%s build=%s class=%s runId=%d last=[%s] armed=%s combat=%s errors=%s",
        Dev.stamp(), db.build, tostring(Dev.classToken()), db.runId, lastText, tostring(st.armed),
        tostring(Dev.inCombat()), type(errs) == "number" and tostring(errs) or "n/a"), 400)
end

--- `/fxdev shot`: repaint the beacon + panel NOW, then Screenshot() on a later frame.
function Dev.Shot()
    if type(_G.Screenshot) ~= "function" then return false, "shot: Screenshot() is not available" end
    Dev.Repaint()
    Dev.After(0.2, function()
        pcall(_G.Screenshot)
    end)
    return true, "shot scheduled"
end

--- THE dispatcher: /fxdev and DevCommands both end here. Returns (ok, detail); never raises.
function Dev.Dispatch(msg)
    msg = tostring(msg or ""):lower():match("^%s*(.-)%s*$")
    local verb, rest = msg:match("^(%S+)%s*(.*)$")
    if not verb then return false, Dev.USAGE end
    local h = Dev.verbs[verb]
    if not h then return false, "unknown verb '" .. Dev.clip(verb, 20) .. "': " .. Dev.USAGE end
    if Dev.inCombat() and not (h.combatOk and h.combatOk(rest)) then
        return false, "refused in combat: " .. verb
    end
    local ok, a, b = pcall(h.fn, rest)
    if not ok then return false, "raised: " .. Dev.S(a) end
    return a and true or false, Dev.clip(b == nil and "" or tostring(b), 400)
end

_G.SLASH_FORTEDEV1 = "/fxdev"
_G.SlashCmdList["FORTEDEV"] = function(msg)
    local ok, detail = Dev.Dispatch(msg)
    Dev.print((ok and "" or "FAILED: ") .. tostring(detail))
end

-- ----------------------------------------------------------- DevCommands --

local function luaChunk(code)
    local compile = _G.loadstring or _G.load
    if type(compile) ~= "function" then return nil, "no loadstring" end
    return compile(code, "=ForteDevCommands")
end

--- Run one DevCommands entry. Returns (verbText, ok, detail).
local function runEntry(entry)
    if type(entry) == "string" then
        local ok, detail = Dev.Dispatch(entry)
        return entry, ok, detail
    end
    if type(entry) == "table" and type(entry.verb) == "string" then
        local ok, detail = Dev.Dispatch(entry.verb)
        return entry.verb, ok, detail
    end
    if type(entry) == "table" and type(entry.lua) == "string" then
        local label = "lua: " .. Dev.clip(entry.lua, 60)
        local fn, cerr = luaChunk(entry.lua)
        if not fn then return label, false, "compile: " .. Dev.S(cerr) end
        local ok, res = pcall(fn)
        if not ok then return label, false, "error: " .. Dev.S(res) end
        return label, true, "ok " .. Dev.S(res)
    end
    return "(bad entry)", false, "entry is neither a string nor { verb = } / { lua = }"
end

--- Run ForteDevCommands. ONCE per load unless `force` (the `run` verb). Skipped in combat (also
--- re-checked before every entry). Every entry lands in ForteDevDB.commands.
function Dev.RunCommands(force)
    local st = Dev.state
    if not force and st.commandsRan then return true, "already ran this load" end
    st.commandsRan = true
    if Dev.inCombat() then
        Dev.RecordCommand("devcommands", false, "skipped: in combat")
        return false, "skipped: in combat"
    end
    local list = _G.ForteDevCommands
    if type(list) ~= "table" then
        Dev.RecordCommand("devcommands", false, "ForteDevCommands is not a table")
        return false, "ForteDevCommands is not a table"
    end
    st.runningCommands = true
    local done = 0
    for i = 1, math.min(#list, Dev.MAX_COMMAND_ENTRIES) do
        if Dev.inCombat() then
            Dev.RecordCommand("devcommands", false, "stopped before entry " .. i .. ": in combat")
            break
        end
        local okRun, verb, ok, detail = pcall(runEntry, list[i])
        if not okRun then
            Dev.RecordCommand("(entry " .. i .. ")", false, "raised: " .. Dev.S(verb))
        else
            Dev.RecordCommand(verb, ok, detail)
        end
        done = done + 1
    end
    st.runningCommands = false
    Dev.Repaint()
    return true, "ran " .. done .. " command(s)"
end

--- Schedule the once-per-load DevCommands run `delay` seconds out.
function Dev.ScheduleCommands(delay)
    local st = Dev.state
    if st.commandsScheduled or st.commandsRan then return false end
    st.commandsScheduled = true
    Dev.After(delay, function()
        pcall(Dev.RunCommands, false)
    end)
    return true
end

-- --------------------------------------------------------------- the frame --

local function onEvent(_, event, ...)
    local st = Dev.state
    if event == "PLAYER_ENTERING_WORLD" then
        st.pewSeen = true
        Dev.ScheduleCommands(Dev.COMMANDS_DELAY)
    elseif event == "PLAYER_REGEN_DISABLED" then
        if st.armed and Dev.Selftest then Dev.Selftest.OnCombatStart() end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if Dev.Selftest then Dev.Selftest.OnOwnCast(select(3, ...)) end
    end
    Dev.Repaint()
end

--- Test seam: drive a handler exactly as the client would.
function Dev.HandleEvent(event, ...)
    local ok, err = pcall(onEvent, nil, event, ...)
    if not ok then Dev.state.lastError = Dev.S(err) end
    return ok
end

local Module = {}

function Module:OnEnable()
    Dev.InitDB()
    if Dev.Beacon then Dev.Beacon.Build() end
    if Dev.Panel then Dev.Panel.Build() end
    local f = _G.CreateFrame("Frame")
    Dev.frame = f
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:RegisterEvent("GROUP_ROSTER_UPDATE")
    f:SetScript("OnEvent", function(self, event, ...)
        local ok, err = pcall(onEvent, self, event, ...)
        if not ok then Dev.state.lastError = Dev.S(err) end
    end)
    -- The login fallback: when the zone-in event never reaches this frame (it registered during
    -- the dispatch), DevCommands still run, a little later.
    Dev.After(Dev.COMMANDS_FALLBACK, function()
        if not Dev.state.pewSeen then Dev.ScheduleCommands(0) end
    end)
    Dev.Repaint()
end

Dev.Module = Module
FX.RegisterModule("Dev", Module)

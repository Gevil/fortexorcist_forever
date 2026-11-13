-- Core/Errors.lua -- the shipped, always-on, silent error recorder.
--
-- Why it exists (docs/research/ingame-dev-step0-results-2026-11-12.md): the
-- chat-log lane cannot carry our output (addon-printed lines never reach
-- Logs/WoWChatLog.txt), and SavedVariables are only written at /reload or
-- logout. So problems that concern ForteXorcist are recorded INTO
-- SavedVariables, where a developer (or `/fx errors`) reads them after the
-- next reload. The contract is PLAN.md §11.11:
--
--   ForteXorcistDB.errors = { session = <n>, list = { {
--       kind = "error"|"blocked"|"forbidden"|"warning", msg, stack|nil,
--       count, first, last, session }, ... } }       newest last, cap 20,
--   de-duplicated on kind + msg + first stack line;
--   FX.Errors.sinceLoad   = occurrences recorded since this UI load;
--   /fx errors            = print the list;  /fx errors clear = empty it.
--
-- WHAT IS CAPTURED (names and payloads checked against the pinned catalog,
-- docs/api/wow-addon-api-agents/skills/wow-api-lua-environment/references/
-- generated/forever.json):
--   * Lua errors through the client error handler (RETAIL-BASELINE:
--     `seterrorhandler(fn)` / `geterrorhandler()`; `debugstack([thread,]
--     [start [, count1 [, count2]]])`);
--   * ADDON_ACTION_BLOCKED / ADDON_ACTION_FORBIDDEN, payload
--     (isTainted: cstring, function: cstring) -- RestrictedActions
--     Documentation.lua:74 / :85; the first string is the addon the client
--     blames, the second the function it tried to call;
--   * LUA_WARNING, payload (warningText: cstring) -- ScriptWarnings
--     Documentation.lua:14. The text is read from the LAST payload argument,
--     so a client that also sends a leading type argument still works.
--
-- ONLY ENTRIES THAT CONCERN US ARE STORED: the message or the (trimmed)
-- stack mentions `Forte_` / `ForteXorcist`, or a blocked-action payload names
-- one of our addons. Everything else only bumps `Errors.ignored` (memory,
-- this session), so other addons' errors never fill the user's SavedVariables.
--
-- SECRET SAFETY: an error message can be a secret value. Every value goes
-- through FX.Compat.PlainOrNil (issecretvalue first, fails closed) BEFORE any
-- string operation; a value that is not a plain string/number is stored as
-- "<unreadable>". Stack text comes from debugstack inside a pcall, our own
-- recorder frames and C frames are dropped, colour escapes are stripped, at
-- most 3 frames of at most 200 chars are stored, msg is cut at 300 chars.
--
-- ONE HANDLER CHAIN. The module installs exactly one wrapper (`handler`
-- below). It records, then calls the previously installed handler exactly
-- once. Another addon that REPLACES the handler later is re-chained at
-- ADDON_LOADED / PLAYER_ENTERING_WORLD (Errors:Install is idempotent: when the
-- current handler is not ours, it is pushed on `prevs` and ours goes back on
-- top). If that addon instead WRAPS us (its handler calls ours), the call
-- re-enters `handler`; the depth counter then skips recording and continues
-- one link further down `prevs`, so every handler of the chain still runs
-- once and nothing recurses. Core/Log.lua does not wrap anything: it
-- subscribes to this module (Errors:Subscribe) for its chat copy.
--
-- SPARSE: no `errors` table exists until the first stored entry. If one
-- exists, its `session` counter is bumped at every UI load (OnEnable); the
-- table is created, with session 1, by the first entry.
--
-- Lifecycle: registered through the module registry; the handler and the
-- event frame are created in OnEnable (login pass), never at file top.
-- Load-time errors of the Forte_* files themselves happen before OnEnable and
-- are therefore not seen.

local FX = ForteXorcist

local Errors = { sinceLoad = 0, ignored = 0 }
FX.Errors = Errors

Errors.CAP = 20             -- entries kept (the newest)
Errors.MSG_MAX = 300        -- chars of a stored message
Errors.STACK_FRAMES = 3     -- frames of a stored stack
Errors.LINE_MAX = 200       -- chars of one stored stack frame
Errors.UNREADABLE = "<unreadable>"

local SCAN_FRAMES = 12      -- frames inspected when deciding whether an error is ours
local MAX_PREVS = 8         -- bound on the remembered handler chain

--- The clock (tests replace it).
function Errors.now()
    if type(_G.time) == "function" then return _G.time() end
    return 0
end

-- ----------------------------------------------------------- sanitising --

--- Strip colour / link / texture escapes, so stored text is plain.
local function clean(s)
    s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
    s = s:gsub("|r", "")
    s = s:gsub("|H[^|]*|h", "")
    s = s:gsub("|h", "")
    s = s:gsub("|T[^|]*|t", "")
    s = s:gsub("|A[^|]*|a", "")
    s = s:gsub("|n", " ")
    return s
end

--- Cut to `max` bytes without leaving half of a UTF-8 sequence behind.
local function truncate(s, max)
    if #s <= max then return s end
    local n = max
    -- The first dropped byte being a continuation byte (10xxxxxx) means the
    -- cut is inside a character: back up to the character's start.
    while n > 0 do
        local b = s:byte(n + 1)
        if b and b >= 0x80 and b < 0xC0 then n = n - 1 else break end
    end
    return s:sub(1, n)
end

--- A plain string from a value that might be a secret; nil when it is not
--- usable. PlainOrNil runs FIRST: not even type() is trusted before it.
local function plainString(v)
    local plain = FX.Compat.PlainOrNil(v)
    local t = type(plain)
    if t == "string" then return plain end
    if t == "number" then return tostring(plain) end
    return nil
end

local function mentionsUs(s)
    return s:find("Forte_", 1, true) ~= nil or s:find("ForteXorcist", 1, true) ~= nil
end

--- The calling frames, newest first, as cleaned lines (at most SCAN_FRAMES).
--- Our own recorder frames and C frames carry no information (and our own
--- file name would make every error "ours"), so they are dropped.
local function readFrames()
    local fn = _G.debugstack
    if type(fn) ~= "function" then return {} end
    local ok, raw = pcall(fn, 1, SCAN_FRAMES, 0)
    if not ok then return {} end
    raw = plainString(raw)
    if not raw then return {} end
    local frames = {}
    for line in raw:gmatch("[^\r\n]+") do
        line = clean(line)
        if not line:find("^%s*%[C%]")
            and not line:find("Core[\\/]Errors%.lua") then
            frames[#frames + 1] = line
            if #frames >= SCAN_FRAMES then break end
        end
    end
    return frames
end

--- The stored form of a frame list: the top frames, each cut.
local function packStack(frames)
    local out = {}
    for i = 1, math.min(#frames, Errors.STACK_FRAMES) do
        out[i] = truncate(frames[i], Errors.LINE_MAX)
    end
    if #out == 0 then return nil end
    return table.concat(out, "\n")
end

local function firstLine(stack)
    return stack and stack:match("^[^\n]*") or nil
end

-- ------------------------------------------------------------- recording --

local listeners = {}

--- Subscribe fn(kind, msg, stack, entry) to every STORED occurrence (Log's
--- chat copy rides this). Returns false for a non-function.
function Errors:Subscribe(fn)
    if type(fn) ~= "function" then return false end
    for _, f in ipairs(listeners) do
        if f == fn then return true end
    end
    listeners[#listeners + 1] = fn
    return true
end

function Errors:Unsubscribe(fn)
    for i, f in ipairs(listeners) do
        if f == fn then
            table.remove(listeners, i)
            return true
        end
    end
    return false
end

--- Store one occurrence (already sanitised). Counts it, finds or creates the
--- entry, enforces the cap, tells the subscribers. Returns the entry.
function Errors:Record(kind, msg, stack)
    self.sinceLoad = self.sinceLoad + 1
    local db = FX.db
    if type(db) ~= "table" then return nil end
    local e = db.errors
    if type(e) ~= "table" then
        e = { session = 1, list = {} }
        db.errors = e
    end
    if type(e.session) ~= "number" then e.session = 1 end
    if type(e.list) ~= "table" then e.list = {} end
    local list = e.list
    local now = self.now()
    local key = firstLine(stack)
    local entry
    for i = 1, #list do
        local c = list[i]
        if type(c) == "table" and c.kind == kind and c.msg == msg
            and firstLine(c.stack) == key then
            entry = c
            table.remove(list, i)
            break
        end
    end
    if entry then
        entry.count = (tonumber(entry.count) or 1) + 1
        entry.last = now
        entry.session = e.session
    else
        entry = { kind = kind, msg = msg, stack = stack, count = 1,
                  first = now, last = now, session = e.session }
    end
    list[#list + 1] = entry                -- newest (last seen) goes last
    while #list > self.CAP do table.remove(list, 1) end
    for _, fn in ipairs({ unpack(listeners) }) do
        pcall(fn, kind, msg, stack, entry)
    end
    return entry
end

--- A Lua error or warning: classify, then store when it concerns us.
function Errors:Capture(kind, rawMsg)
    local raw = plainString(rawMsg)
    local frames = readFrames()
    local ours = raw ~= nil and mentionsUs(raw)
    if not ours then
        for _, line in ipairs(frames) do
            if mentionsUs(line) then ours = true break end
        end
    end
    if not ours then
        self.ignored = self.ignored + 1
        return false
    end
    local msg = self.UNREADABLE
    if raw then msg = truncate(clean(raw), self.MSG_MAX) end
    self:Record(kind, msg, packStack(frames))
    return true
end

--- ADDON_ACTION_BLOCKED / _FORBIDDEN: stored when the payload names us.
function Errors:CaptureAction(kind, addon, func)
    local a, f = plainString(addon), plainString(func)
    if not ((a and mentionsUs(a)) or (f and mentionsUs(f))) then
        self.ignored = self.ignored + 1
        return false
    end
    local msg = truncate(clean((a or self.UNREADABLE) .. ": " .. (f or self.UNREADABLE)),
        self.MSG_MAX)
    self:Record(kind, msg, packStack(readFrames()))
    return true
end

-- ----------------------------------------------------------- the handler --

local prevs = {}        -- handlers this one replaced, oldest first (false = none)
local depth = 0         -- how many links of `prevs` the running call is below
local capturing = false -- the recorder is running (re-entrancy guard)
local installed = false

--- The ONE wrapper. Records (outermost call only), then calls the next
--- handler down the chain exactly once, protected: a raising previous
--- handler costs its own output, never the recording and never the game.
local function handler(err)
    local d = depth
    if d == 0 and not capturing then
        capturing = true
        pcall(Errors.Capture, Errors, "error", err)
        capturing = false
    end
    local prev = prevs[#prevs - d]
    if type(prev) ~= "function" then return end
    depth = d + 1
    local ok, result = pcall(prev, err)
    depth = d
    if ok then return result end
end

--- Put the wrapper on top of the client handler. Idempotent: it is also the
--- re-assert (another addon replaced the handler -> chain it again).
function Errors:Install()
    local get, set = _G.geterrorhandler, _G.seterrorhandler
    if type(get) ~= "function" or type(set) ~= "function" then return false end
    local ok, current = pcall(get)
    if not ok then return false end
    if current ~= handler then
        prevs[#prevs + 1] = current or false
        while #prevs > MAX_PREVS do table.remove(prevs, 1) end
        if not pcall(set, handler) then
            prevs[#prevs] = nil
            return false
        end
    end
    installed = true
    return true
end

--- Take the wrapper off (tests, and a clean hand-back): restores the handler
--- it replaced when it is still on top.
function Errors:Uninstall()
    local get, set = _G.geterrorhandler, _G.seterrorhandler
    if installed and type(get) == "function" and type(set) == "function" then
        local ok, current = pcall(get)
        if ok and current == handler and type(prevs[#prevs]) == "function" then
            pcall(set, prevs[#prevs])
        end
    end
    prevs = {}
    depth = 0
    capturing = false
    installed = false
end

--- The handler itself (the tests' handle; nothing else should call it).
Errors.handler = handler

-- -------------------------------------------------------------- the UI --

local function esc(s)
    return (tostring(s):gsub("|", "||"))
end

local function stored()
    local e = FX.db and FX.db.errors
    if type(e) == "table" and type(e.list) == "table" then return e end
    return nil
end

function Errors:Show()
    local e = stored()
    local list = e and e.list or {}
    FX.Print(string.format(
        "Errors: %d recorded | %d this load | %d from other addons ignored this load",
        #list, self.sinceLoad, self.ignored))
    for i, c in ipairs(list) do
        if type(c) == "table" then
            local when = ""
            if type(_G.date) == "function" and tonumber(c.last) and c.last > 0 then
                when = " " .. _G.date("%m-%d %H:%M:%S", c.last)
            end
            FX.Print(string.format("  %d. [%s]%s%s (session %s%s)", i, esc(c.kind),
                (tonumber(c.count) or 1) > 1 and (" x" .. c.count) or "",
                " " .. esc(c.msg), esc(c.session), when))
            local top = firstLine(c.stack)
            if top then FX.Print("       " .. esc(top)) end
        end
    end
end

function Errors:Clear()
    local e = stored()
    if e then e.list = {} end
    self.sinceLoad = 0
    self.ignored = 0
    FX.Print("Errors: cleared")
end

function Errors:Status()
    local e = stored()
    FX.Print(string.format("Errors: recorded=%d sinceLoad=%d ignored=%d (/fx errors)",
        e and #e.list or 0, self.sinceLoad, self.ignored))
end

-- ------------------------------------------------------------ lifecycle --

-- One literal per line so scripts/api_lint.py checks each against the pinned
-- catalog (the Probe law: a mistyped event name raises on the client).
local ACTION_EVENTS = {
    "ADDON_ACTION_BLOCKED",
    "ADDON_ACTION_FORBIDDEN",
    "LUA_WARNING",
}
-- Re-assert points for the handler chain (another addon replaced it).
local CHAIN_EVENTS = {
    "ADDON_LOADED",
    "PLAYER_ENTERING_WORLD",
}

local function onEvent(_, event, ...)
    if event == "ADDON_ACTION_BLOCKED" then
        pcall(Errors.CaptureAction, Errors, "blocked", ...)
    elseif event == "ADDON_ACTION_FORBIDDEN" then
        pcall(Errors.CaptureAction, Errors, "forbidden", ...)
    elseif event == "LUA_WARNING" then
        local n = select("#", ...)
        if n > 0 then
            pcall(Errors.Capture, Errors, "warning", (select(n, ...)))
        end
    else
        pcall(Errors.Install, Errors)
    end
end

function Errors:OnEnable()
    local e = stored()
    if e then e.session = (tonumber(e.session) or 0) + 1 end
    self:Install()
    if not self._frame and type(_G.CreateFrame) == "function" then
        local f = _G.CreateFrame("Frame")
        self._frame = f
        for _, name in ipairs(ACTION_EVENTS) do pcall(f.RegisterEvent, f, name) end
        for _, name in ipairs(CHAIN_EVENTS) do pcall(f.RegisterEvent, f, name) end
        f:SetScript("OnEvent", onEvent)
    end
end

FX.RegisterModule("Errors", Errors)

FX.RegisterSlash("errors", function(rest)
    rest = (rest or ""):match("^%s*(.-)%s*$")
    Errors:Install()                 -- re-assert before answering
    if rest == "clear" then
        Errors:Clear()
    else
        Errors:Show()
    end
end)

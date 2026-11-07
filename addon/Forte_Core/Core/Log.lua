-- Core/Log.lua -- live debug log for development sessions.
--
-- `/fx log on` does two things:
--   1. wraps the client error handler so EVERY Lua error (any addon) is also
--      printed to chat as `[FX-ERR] <message>` (the original handler still
--      runs, so popups / BugGrabber keep working),
--   2. turns on the client's chat logging (`LoggingChat(true)` — the
--      catalog's form takes the enable boolean, so it is called WITH it and
--      only with it), which appends every chat line to
--      Logs/WoWChatLog.txt as it happens.
-- An outside tool can then tail that file for live errors and `FX.Log` lines
-- instead of waiting for a /reload to flush SavedVariables.
--
-- `/fx log off` restores the previous handler and stops chat logging.
-- The on/off choice persists in FX.db.logOn and is re-applied through the
-- module registry at login (see the tail: the login re-apply rides
-- Log:OnEnable, the Core/Init.lua law; this file registers no event frame).
-- The DEFAULT install is off: FX.db.logOn is written only by Log:Enable and
-- nil'd by Log:Disable, so a fresh install re-applies nothing at login and
-- adds nothing to SavedVariables.
-- `FX.Log(tag, ...)` prints `[FX:<tag>] ...` (always, cheap, chat-only).

local FX = ForteXorcist

local Log = { on = false, prev = nil, handler = nil }
FX.LogModule = Log

local function say(msg)
    if _G.DEFAULT_CHAT_FRAME then
        _G.DEFAULT_CHAT_FRAME:AddMessage(msg)
    end
end

--- Tagged debug line (chat -> WoWChatLog.txt while logging is on).
function FX.Log(tag, ...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    say("[FX:" .. tostring(tag) .. "] " .. table.concat(parts, " "))
end

function Log:Enable()
    if self.on then return end
    self.on = true
    if type(_G.geterrorhandler) == "function"
        and type(_G.seterrorhandler) == "function" then
        self.prev = _G.geterrorhandler()
        self.handler = function(err)
            -- Never let the logger itself raise inside the error path.
            pcall(say, "[FX-ERR] " .. tostring(err))
            if type(self.prev) == "function" then
                return self.prev(err)
            end
        end
        _G.seterrorhandler(self.handler)
    end
    -- The catalog form is `LoggingChat(enable)`: the boolean rides every
    -- call (the argless shape is the M3 raise, see Log:Status).
    if type(_G.LoggingChat) == "function" then pcall(_G.LoggingChat, true) end
    if FX.db then FX.db.logOn = true end
end

function Log:Disable()
    if not self.on then return end
    self.on = false
    if self.handler and type(_G.geterrorhandler) == "function"
        and _G.geterrorhandler() == self.handler and self.prev then
        _G.seterrorhandler(self.prev)
    end
    self.handler = nil
    if type(_G.LoggingChat) == "function" then pcall(_G.LoggingChat, false) end
    if FX.db then FX.db.logOn = nil end
end

--- The bare `/fx log` status line. M3 (code-review-10): the OLD shape read
--- the state with `_G.LoggingChat()` -- an argless call of a function the
--- catalog declares as `LoggingChat(enable)` (RETAIL-BASELINE: "Toggle
--- combat log file"), whose QUERY twin is `IsLoggingChat()` -- and the
--- C-side usage error it raises rode the unprotected slash dispatch
--- (Core/Init.lua: `fn(rest)`, no pcall), so the everyday "what's the state"
--- command died on the shipped client. The read is lawful now: prefer the
--- zero-arg query, pcall it, classify through PlainOrNil, default false.
--- `LoggingChat` itself is NOT in the pinned Forever catalog at all, so the
--- whole read is optional/unknown: no query, no answer, and no unguarded
--- call of anything.
function Log:Status()
    local chatOn = false
    local query = _G.IsLoggingChat
    if type(query) == "function" then
        local ok, v = pcall(query)
        chatOn = (ok and FX.Compat.PlainOrNil(v)) and true or false
    end
    FX.Print(string.format("Log: errors->chat=%s chatlog=%s (Logs/WoWChatLog.txt)",
        tostring(self.on), tostring(chatOn)))
end

FX.RegisterSlash("log", function(rest)
    rest = (rest or ""):match("^%s*(.-)%s*$")
    if rest == "on" then
        Log:Enable()
        Log:Status()
    elseif rest == "off" then
        Log:Disable()
        Log:Status()
    elseif rest == "test" then
        -- m5 (code-review-10): the old shape was `pcall(error, ...)` (a
        -- decoration -- pcall swallows it, the wrapper never saw it) plus an
        -- UNGATED `_G.geterrorhandler()(...)` -- the one client touch in
        -- this file that ignored the file's own presence idiom, so the
        -- command died with "attempt to call a nil value" wherever the
        -- handler getter is absent (a restricted client, the sim). The
        -- self-test is the second line, gated: with the log ON its wrapper
        -- prints the [FX-ERR] line through the chat frame; with the log off
        -- the client's own handler (if any) answers.
        if type(_G.geterrorhandler) == "function" then
            local ok, handler = pcall(_G.geterrorhandler)
            if ok and type(handler) == "function" then
                handler("FX log self-test (deliberate)")
            end
        end
    else
        Log:Status()
    end
end)

-- The login re-apply rides Forte_Core's module registry (Core/Init.lua's
-- law: "login-time work belongs in OnEnable, which the pass calls DIRECTLY";
-- Probe and TestMode follow it). Code-review-10 M4: this file used to run
-- `_G.CreateFrame(...):RegisterEvent("PLAYER_LOGIN")` at file top -- a
-- second login-time registrant besides the bootstrap frame, which the
-- single-registrant law exists to keep out of the tree (login/reload/
-- restriction event order is exactly what launch work rides on). The
-- default install is OFF: OnEnable enables only on the stored `on`, so a
-- fresh login writes nothing and registers no chat-logging call.
function Log:OnEnable()
    if FX.db and FX.db.logOn then
        self:Enable()
    end
end

FX.RegisterModule("Log", Log)

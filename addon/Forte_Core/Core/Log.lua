-- Core/Log.lua -- live debug log for development sessions.
--
-- `/fx log on` does two things:
--   1. wraps the client error handler so EVERY Lua error (any addon) is also
--      printed to chat as `[FX-ERR] <message>` (the original handler still
--      runs, so popups / BugGrabber keep working);
--   2. turns on the client's chat logging (`LoggingChat(true)`), which
--      appends every chat line to Logs/WoWChatLog.txt as it happens.
-- An outside tool can then tail that file for live errors and `FX.Log` lines
-- instead of waiting for a /reload to flush SavedVariables.
--
-- `/fx log off` restores the previous handler and stops chat logging.
-- The on/off choice persists in FX.db.logOn and is re-applied at login.
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

function Log:Status()
    local chatOn = type(_G.LoggingChat) == "function" and _G.LoggingChat() or false
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
        pcall(error, "FX log self-test (deliberate)")
        _G.geterrorhandler()("FX log self-test (deliberate)")
    else
        Log:Status()
    end
end)

-- Re-apply the persisted choice once the database exists.
local f = _G.CreateFrame and _G.CreateFrame("Frame")
if f then
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function()
        if FX.db and FX.db.logOn then Log:Enable() end
    end)
end

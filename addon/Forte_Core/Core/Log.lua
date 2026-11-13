-- Core/Log.lua -- live debug switch for development sessions.
--
-- `/fx log on` does two things:
--   1. copies every error the recorder STORES (Core/Errors.lua: errors,
--      blocked actions, Lua warnings that concern ForteXorcist) to chat as
--      `[FX-ERR] <message>` the moment it is recorded (`[FX-ERR] [blocked]
--      <message>` for the other kinds). The stored list itself is `/fx errors`.
--      This file wraps NO error handler: it subscribes to the recorder, so
--      there is exactly one handler chain (Errors.lua owns it);
--   2. turns on `FX.Log` tracing (`FX.Log(tag, ...)` prints `[FX:<tag>] ...`;
--      the Spell Timer reads `FX.LogModule.on` to trace casts).
-- `/fx log off` undoes both.
--
-- WHAT WAS MEASURED (docs/research/ingame-dev-step0-results-2026-11-12.md,
-- WoW Forever 1.60.1.70888, 2026-11-12): the client's chat logging records
-- the player's real chat only. With chat logging ON (the built-in `/chatlog`
-- answered "Chat logging disabled." when toggled), `[FX-ERR]` and `FX.Log`
-- lines were printed and Logs/WoWChatLog.txt stayed 0 bytes. So this file
-- never calls `LoggingChat` (turning it on only logs the player's real chat,
-- a privacy cost with no benefit to us) and never reads `IsLoggingChat`
-- (on that client the read printed `chatlog=false` while logging was on, so
-- the old status field was wrong). Errors reach an outside reader through
-- SavedVariables (`ForteXorcistDB.errors`, written at /reload or logout).
--
-- The on/off choice persists in FX.db.logOn and is re-applied through the
-- module registry at login (the login re-apply rides Log:OnEnable, the
-- Core/Init.lua law; this file registers no event frame). A stored `logOn`
-- from an older build keeps meaning the same switch. The DEFAULT install is
-- off: FX.db.logOn is written only by Log:Enable and nil'd by Log:Disable, so
-- a fresh install re-applies nothing at login and adds nothing to
-- SavedVariables.

local FX = ForteXorcist

local Log = { on = false, listener = nil }
FX.LogModule = Log

local function say(msg)
    if _G.DEFAULT_CHAT_FRAME then
        _G.DEFAULT_CHAT_FRAME:AddMessage(msg)
    end
end

--- Tagged debug line (chat only: it does not reach any log file).
function FX.Log(tag, ...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    say("[FX:" .. tostring(tag) .. "] " .. table.concat(parts, " "))
end

--- The chat copy of one recorded entry. Never raises (the recorder pcalls
--- its subscribers, and this adds its own pcall around the print).
local function copyToChat(kind, msg)
    local text = tostring(msg):gsub("|", "||")
    if kind ~= "error" then text = "[" .. tostring(kind) .. "] " .. text end
    pcall(say, "[FX-ERR] " .. text)
end

local NO_RECORDER = "Log: the error recorder (Core/Errors.lua) is not loaded -- "
    .. "restart the game once to load it (a file added to the .toc is only "
    .. "found at a full client start, not at /reload)."

--- Subscribe the chat copy to the recorder. FX.Errors is nil when this
--- Log.lua was reloaded by /reload after an update but Core/Errors.lua, new
--- in the .toc, was not discovered (that needs a full client restart): the
--- switch then still turns FX.Log tracing on, says so once, and copies nothing.
function Log:Subscribe()
    local errors = FX.Errors
    if type(errors) ~= "table" or type(errors.Subscribe) ~= "function" then
        return false
    end
    self.listener = self.listener or copyToChat
    return errors:Subscribe(self.listener)
end

function Log:Enable()
    if self.on then return end
    self.on = true
    if not self:Subscribe() then FX.Print(NO_RECORDER) end
    if FX.db then FX.db.logOn = true end
end

function Log:Disable()
    if not self.on then return end
    self.on = false
    local errors = FX.Errors
    if self.listener and type(errors) == "table"
        and type(errors.Unsubscribe) == "function" then
        errors:Unsubscribe(self.listener)
    end
    if FX.db then FX.db.logOn = nil end
end

--- The bare `/fx log` status line. No client query is involved (see the
--- header: the chat-logging read was wrong on the live client and the
--- chat-logging state is not ours), so it cannot raise; it reads the stored
--- list directly, so it also works without the recorder module.
function Log:Status()
    local e = FX.db and FX.db.errors
    local n = (type(e) == "table" and type(e.list) == "table") and #e.list or 0
    FX.Print(string.format("Log: errors->chat=%s recorded=%d (%s)",
        tostring(self.on), n,
        FX.Errors and "/fx errors" or "error recorder not loaded: restart the game"))
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
        -- m5 (code-review-10): the self-test hands one deliberate line to the
        -- client's current error handler, gated on the getter being present
        -- (a restricted client or the sim may not have it). With the
        -- recorder installed that handler is ours: the line is recorded
        -- (its stack runs through this file, so it is "ours") and, with the
        -- log ON, copied to chat.
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
-- Probe and TestMode follow it). The default install is OFF: OnEnable
-- enables only on the stored `on`. Errors.lua is registered (and so enabled)
-- before this module: the TOC loads it first.
function Log:OnEnable()
    if FX.db and FX.db.logOn then
        self:Enable()
    end
end

FX.RegisterModule("Log", Log)

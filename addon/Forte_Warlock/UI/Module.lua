-- addon/Forte_Warlock/UI/Module.lua
-- FX.Warlock.UI: the module that owns the four warlock frames' lifecycle
-- (Shard Manager, Soulstone Tracker, Healthstone Spy, Summon Assistant) and
-- their events — the Forte_Hunter/UI/Swing.lua `FX.Hunter.UI` shape, at the
-- bottom of which the module registers as `WarlockUI`.
--
-- Why a module of its own: Forte_Warlock's module is Core/Tools.lua's
-- (`Warlock`, the state module) and its OnEnable is class-gated for the
-- trackers' event frame. The frames need their OWN class-gated OnEnable +
-- OnClassChanged, and Forte_Core is not ours to edit. Frames and
-- RegisterEvent live inside these handlers, never at file load (the taint
-- rule, Forte_Core/Core/Init.lua).
--
-- Event law: Core/Tools.lua's own event frame is what FEEDS the trackers
-- (it owns every payload contract, docs/warlock-tools.md). This module
-- registers the same events on its own frame and forwards them UNREAD —
-- they mean "the state may have moved" and nothing more. The two frames are
-- independent, and their delivery order is not specified by the engine, so a
-- kick that finds the tracker not yet moved is expected: every kick also
-- opens a short settle window (SETTLE_SECONDS of 10 Hz passes) so the state
-- the sibling frame writes is on screen a tick later.
--
-- Update law (PLAN §3.4 "staggered polling, not one heavy per-event
-- handler"): ONE driver frame runs the 10 Hz pass over the four views, and
-- only while something is live. The driver frame is shown from Init and
-- NEVER hidden — a hidden frame never receives OnUpdate (found live on
-- uiforever 2026-11-02, the Hunter swing bar's bug), so the ticker can not
-- live on a frame that renders itself. It has no textures, so showing it is
-- free; it is mouse-disabled, so it is click-through. Its OnUpdate script is
-- installed while any view reports itself time-driven (a live soulstone
-- window, a counting-down item cooldown, a running channel) or inside a
-- settle window, and uninstalled the moment none does.
--
-- Visibility law: activity arrives through Kick, which renders every named
-- view SYNCHRONOUSLY (the frame is on screen before any OnUpdate is relied
-- on), then starts the ticker when a view is time-driven.
--
-- Lock law: the frames mirror `/fx lock|unlock` themselves (see
-- UI/Frame.lua's SetLocked/_WireSettings), so this module has no lock code.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
FX.Warlock = FX.Warlock or {}

FX.Warlock.UI = {}
local U = FX.Warlock.UI

local VIEWS = { "Shards", "Soulstone", "Healthstone", "Summon" }
U.VIEW_NAMES = VIEWS

local TICK_SECONDS = 0.1                       -- the 10 Hz render rate
local SETTLE_SECONDS = 0.5                     -- the post-event settle window

-- The events that mean "this view's state may have moved". Every one of them
-- is a Forte_Warlock/Core/Tools.lua registration already (the same catalog
-- rows, docs/warlock-tools.md); the payloads are forwarded UNREAD.
local KICK_SHARDS = {
    BAG_UPDATE_DELAYED = true,
    ITEM_COUNT_CHANGED = true,
    UNIT_POWER_UPDATE = true,
    PLAYER_REGEN_ENABLED = true,
}
local KICK_HEALTHSTONE = {
    BAG_UPDATE_DELAYED = true,
    ITEM_COUNT_CHANGED = true,
    PLAYER_REGEN_ENABLED = true,
}
local KICK_SOULSTONE = {
    UNIT_SPELLCAST_SENT = true,
    UNIT_SPELLCAST_SUCCEEDED = true,
    PLAYER_REGEN_ENABLED = true,
}
local KICK_SUMMON = {
    UNIT_SPELLCAST_SENT = true,
    UNIT_SPELLCAST_START = true,
    UNIT_SPELLCAST_CHANNEL_START = true,
    UNIT_SPELLCAST_SUCCEEDED = true,
    UNIT_SPELLCAST_STOP = true,
    UNIT_SPELLCAST_FAILED = true,
    UNIT_SPELLCAST_INTERRUPTED = true,
    UNIT_SPELLCAST_CHANNEL_STOP = true,
}
local KICK_ALL = {
    PLAYER_ENTERING_WORLD = true,
}

local CAST_EVENTS = {
    "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_STOP",
}

local function viewsFor(event)
    if KICK_ALL[event] then return VIEWS end
    local out = {}
    if KICK_SHARDS[event] then out[#out + 1] = "Shards" end
    if KICK_HEALTHSTONE[event] then out[#out + 1] = "Healthstone" end
    if KICK_SOULSTONE[event] then out[#out + 1] = "Soulstone" end
    if KICK_SUMMON[event] then out[#out + 1] = "Summon" end
    return out
end
U.viewsFor = viewsFor

-- ------------------------------------------------------------------ views --
function U:_Views()
    local out = {}
    for i = 1, #VIEWS do
        local v = FX.Warlock[VIEWS[i]]
        if v then out[#out + 1] = v end
    end
    return out
end

--- Wire the frames to the module's trackers and build them. Runs from
--- OnEnable/OnClassChanged for a WARLOCK only. The tracker slot names are the
--- view names (Tools.Shards / .Soulstone / .Healthstone / .Summon), so one
--- lookup covers all four; SetTracker is the test seam, so an injected
--- tracker is never overwritten.
function U:_InitViews()
    local tools = FX.Warlock.Tools
    for i = 1, #VIEWS do
        local view = FX.Warlock[VIEWS[i]]
        if view and tools then
            view.Tracker = view.Tracker or tools[VIEWS[i]]
        end
        if view and view.Init then view:Init() end
    end
    self:InitDriver()
end

-- ----------------------------------------------------------------- driver --
--- The always-shown 10 Hz driver. Mouse-off, no art, 1x1: showing it is free.
function U:InitDriver()
    if self._driver then return self._driver end
    local d = CreateFrame("Frame", "ForteXorcistWarlockUIDriver", UIParent)
    d:SetSize(1, 1)
    d:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
    d:EnableMouse(false)
    d:SetClampedToScreen(true)
    d:Show()
    self._driver = d
    return d
end

function U:StartTicking()
    local d = self._driver
    if not d or self._ticking then return end
    self._ticking = true
    self._acc = 0
    d:SetScript("OnUpdate", function(_, elapsed)
        local acc = (self._acc or 0) + (tonumber(elapsed) or 0)
        if acc < TICK_SECONDS then
            self._acc = acc
            return
        end
        self._acc = 0
        self:Tick(GetTime())
    end)
end

function U:StopTicking()
    if not self._ticking then return end
    self._ticking = false
    if self._driver then self._driver:SetScript("OnUpdate", nil) end
end

--- One 10 Hz pass over the views; stops the ticker once no view is
--- time-driven and the settle window has passed.
function U:Tick(now)
    local animating = false
    local views = self:_Views()
    for i = 1, #views do
        local v = views[i]
        if v.Update and v:Update(now) then animating = true end
    end
    if not animating and (now or 0) >= (self._settleUntil or 0) then
        self:StopTicking()
    end
    return animating
end

--- The activity entry point: render the named views NOW (a hidden frame
--- never receives OnUpdate, so visibility may never wait for a tick), then
--- keep the ticker alive while any of them counts down.
function U:Kick(names, now)
    now = now or GetTime()
    local animating = false
    for _, name in ipairs(names) do
        local v = FX.Warlock[name]
        if v and v.Update and v:Update(now) then animating = true end
    end
    self._settleUntil = now + SETTLE_SECONDS
    self:InitDriver()
    if animating then self:StartTicking() end
    return animating
end

-- ----------------------------------------------------------------- events --
--- The event frame's dispatcher. The payload fields are received and
--- deliberately UNREAD: Core/Tools.lua owns the contracts (its
--- `onToolEvent`), this dispatcher only routes the kick.
local function onUIEvent(self, event)
    local names = viewsFor(event)
    if #names == 0 then return end
    if not self._driver then return end
    self:Kick(names)
end

--- Register the UI's events (idempotent while enabled). The frame is created
--- here, inside OnEnable/OnClassChanged (the taint rule).
function U:EnableEvents()
    if self._eventsEnabled then return end
    local f = self._eventFrame
    if not f then
        f = CreateFrame("Frame")
        self._eventFrame = f
    end
    for _, ev in ipairs(CAST_EVENTS) do
        f:RegisterUnitEvent(ev, "player")
    end
    f:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
    f:RegisterEvent("BAG_UPDATE_DELAYED")
    f:RegisterEvent("ITEM_COUNT_CHANGED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    -- OnEvent receives (frame, event, ...): swallow the frame, or `event`
    -- would be the frame and no branch would ever match. The payload fields
    -- after the event name are received as varargs and never read.
    f:SetScript("OnEvent", function(_, event, ...)
        onUIEvent(U, event, ...)
    end)
    self._eventsEnabled = true
end

--- Tear the registrations back down when the class moves away from WARLOCK
--- (Core FX.RefreshPlayerClass). Unregister* is nil-guarded exactly like
--- Core/Tools.lua's DisableEvents (the sim's frame emulation lacks them).
function U:DisableEvents()
    local f = self._eventFrame
    if f and self._eventsEnabled then
        if f.UnregisterUnitEvent then
            for _, ev in ipairs(CAST_EVENTS) do
                f:UnregisterUnitEvent(ev, "player")
            end
            f:UnregisterUnitEvent("UNIT_POWER_UPDATE", "player")
        end
        if f.UnregisterEvent then
            f:UnregisterEvent("BAG_UPDATE_DELAYED")
            f:UnregisterEvent("ITEM_COUNT_CHANGED")
            f:UnregisterEvent("PLAYER_REGEN_ENABLED")
            f:UnregisterEvent("PLAYER_ENTERING_WORLD")
        end
        f:SetScript("OnEvent", nil)
    end
    self._eventsEnabled = false
end

-- ------------------------------------------------------------- lifecycle --
function U:OnEnable()
    -- The page registration is NOT class-gated: this chunk runs at
    -- PLAYER_LOGIN, the first point where Forte_Options' files are
    -- guaranteed to exist (the loader may run Forte_Warlock first — the
    -- dependency is optional and the alphabetical order puts Forte_Warlock
    -- before Forte_Options). Pages/Warlock.lua's load-time attempt was a
    -- no-op then. Idempotent.
    local pages = FX.Warlock.Pages
    if pages and pages.RegisterWarlockPages then pages.RegisterWarlockPages() end
    -- Warlocks only (the Core bootstrap runs OnEnable for every class).
    if FX._playerClass ~= "WARLOCK" then return end
    self:_InitViews()
    self:EnableEvents()
    -- State that was already true at login (shards in the bags, a running
    -- channel) renders immediately.
    self:Kick(VIEWS)
end

--- Core FX.RefreshPlayerClass notification (the uiforever T4 class guard):
--- the frames, the driver and the event frame follow the class.
function U:OnClassChanged(classFile)
    if classFile == "WARLOCK" then
        self:_InitViews()
        self:EnableEvents()
        self:Kick(VIEWS)
        return
    end
    self:DisableEvents()
    self:StopTicking()
    for i = 1, #VIEWS do
        local v = FX.Warlock[VIEWS[i]]
        if v and v.OnClassChanged then v:OnClassChanged(classFile) end
    end
end

--- `/fx status` integration (Core's status loop calls Status per module).
function U:Status()
    local lines = {}
    for i = 1, #VIEWS do
        local v = FX.Warlock[VIEWS[i]]
        if v and v.StatusLine and v.anchor then
            lines[#lines + 1] = v:StatusLine()
        end
    end
    if #lines == 0 then
        lines[1] = "Warlock UI: not built (class "
            .. tostring(FX._playerClass) .. ")"
    end
    for _, l in ipairs(lines) do FX.Print(l) end
end

FX.RegisterModule("WarlockUI", U)

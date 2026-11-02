-- Forte_Core/Core/Events.lua
-- The shared event bus: the one seam the Forte_* addons use to talk to each
-- other without importing each other's internals. The contract (plan §6,
-- the shared contract row):
--
--   FX.On(event, fn)   -> handle            (subscribe; returns a handle)
--   FX.Off(handle)     -> removed?          (unsubscribe by that handle)
--   FX.Fire(event, ...) -> listeners run    (every listener in its own
--                                            pcall -- a listener that raises
--                                            is reported and skipped, the
--                                            firer NEVER breaks)
--
-- Event names (FX.EVENTS, the exact wire strings):
--   "FX_COOLDOWN_READY"  (name, now, texPath, category)  fired by the Cooldown
--                        module when an entry pops ready (the engine's
--                        ready-pop loop; the hook point is Forte_Cooldown/
--                        Module.lua's ticker `disp:OnReady(name, now)` call).
--   "FX_TIMER_EXPIRED"   (spell, target, kind)           fired when a Spell
--                        Timer row's window ends (the Forte_Timer
--                        options.onExpire seam, Core/Rows.lua's Sweep).
--   "FX_TIMER_FADING"    (spell, target, kind, secondsLeft)
--                        fired ONCE per row when a registered CC row's
--                        remaining crosses its fade threshold -- the
--                        original's ST_UpdateSpellTimers fade block
--                        (Forte_Timer.lua:1049-1056), stamped at insert from
--                        ST_GetFadeTime (:1590-1603, the threshold is the
--                        first number in the fade message's text, fallback
--                        0.1). The stamp is FX.Timer.FadeWarnings[spell],
--                        populated by Forte_Messages (name-keyed, class-
--                        agnostic -- no class add-on is required).
--   "FX_TIMER_BROKEN"    (spell, target, kind)           fired when the aura
--                        sweep removes a row early -- the :1207 law site
--                        (Rows:OnAuraAbsent's "removed" verdict: the aura
--                        is gone with more than MAXLAG of window left).
--                        The original's ST_BreakMessages site.
--   "FX_SPLASH"          (name, texPath)                 optional: a ready
--                        icon request for the Secondary Splash.
--
-- Laws this bus keeps:
--   * dispatch order = registration order (the registry is the only order
--     the project owns -- Forte_Core/Core/Init.lua's module law);
--   * Fire iterates a SNAPSHOT of the listener list taken at fire time, so
--     an On/Off from inside a listener never mutates the running dispatch
--     and never skips a peer;
--   * Off removes exactly the handle it is given, is idempotent, and answers
--     false for a handle it does not know;
--   * a listener error never propagates to the firer (FE-01's one-dispatcher
--     rule, Forte_Core.lua:278-306: one module's failure costs that module,
--     not the event);
--   * pcall is spelled `pcall(fn, ...)` -- the payload rides as varargs, so
--     the bus is allocation-free per fire (the snapshot is the one copy).
--
-- Pure Lua, no game API, no frames: safe at file-load time, usable by every
-- Forte_* addon's chunk (Forte_Core is the hard dependency of the whole set).

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist

FX.EVENTS = FX.EVENTS or {
    COOLDOWN_READY = "FX_COOLDOWN_READY",
    TIMER_EXPIRED  = "FX_TIMER_EXPIRED",
    TIMER_FADING   = "FX_TIMER_FADING",
    TIMER_BROKEN   = "FX_TIMER_BROKEN",
    SPLASH         = "FX_SPLASH",
}

FX._bus = FX._bus or { nextId = 1, byEvent = {} }
local bus = FX._bus

--- Subscribe fn to `event`. Returns the handle for FX.Off, or nil for a
--- bad call (a bus must not kill a caller over a typo).
function FX.On(event, fn)
    if type(event) ~= "string" or type(fn) ~= "function" then return nil end
    local list = bus.byEvent[event]
    if not list then
        list = {}
        bus.byEvent[event] = list
    end
    local handle = { id = bus.nextId, event = event }
    bus.nextId = bus.nextId + 1
    list[#list + 1] = { id = handle.id, fn = fn }
    return handle
end

--- Unsubscribe by the handle FX.On handed out. Returns true when a
--- listener was removed, false for an unknown / already-removed handle.
function FX.Off(handle)
    if type(handle) ~= "table" or type(handle.id) ~= "number" then return false end
    local list = bus.byEvent[handle.event]
    if not list then return false end
    for i = 1, #list do
        if list[i].id == handle.id then
            table.remove(list, i)
            return true
        end
    end
    return false
end

--- Run every listener of `event` with the payload, each in its own pcall.
--- Returns how many listeners ran. A raising listener is reported through
--- FX.Print (itself pcall'd) and the fire continues: the firer is never
--- broken by a listener.
function FX.Fire(event, ...)
    local list = bus.byEvent[event]
    if not list or #list == 0 then return 0 end
    -- Snapshot the array part: an Off (or On) from inside a listener must
    -- not mutate the running dispatch (registration order stays stable).
    local snapshot = {}
    for i = 1, #list do snapshot[i] = list[i] end
    local ran = 0
    for i = 1, #snapshot do
        local ok, err = pcall(snapshot[i].fn, ...)
        ran = ran + 1
        if not ok and FX.Print then
            pcall(FX.Print, "|cffff5555FX listener for " .. tostring(event)
                .. " failed:|r " .. tostring(err))
        end
    end
    return ran
end

--- How many listeners an event carries (read-only; the tests' census).
function FX.ListenerCount(event)
    local list = bus.byEvent[event]
    return list and #list or 0
end

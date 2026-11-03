-- Forte_Core/Core/TestMode.lua
-- The demo pilot: `/fx test` fills the on-screen frames with SYNTHETIC entries
-- so a layout pass (the owner's uiforever review loop, docs/research/
-- upstream-addons-2026-11-03.md §6 "Test Mode", ranked row 3) has something to
-- look at without a fight. `FX.TestMode`, loaded by Forte_Core and registered
-- as a module here, is the only owner of the flag; the features that own a
-- frame own their own synthetic rows (Forte_Cooldown/Module.lua,
-- Forte_Timer/Module.lua) and register them through `RegisterFeeder`.
--
-- WHY IT IS A GATE AND NOT A SCANNER. The law the upstream note states (§6:
-- "all feeds are skipped while Test Mode is active", CooldownMaster
-- Core/Cooldown.lua:233-255) is that a demo mode gates EVERY path that writes
-- entries -- the reads, the cast feeds, the aura/proc sweeps -- and not only
-- the periodic scan. A demo that blocks only its own scans mixes synthetic
-- rows in with a live player's real ones within one global cooldown, and every
-- launch-day probe (the read-tier and cast-secrecy counters Forte_Cooldown
-- keeps for the 2026-11-04 client) then measures a frame that is half fiction.
-- So the flag is read at the WRITE sites of the fed features, and each feature
-- is the one that knows which of its own paths write: the gates live there,
-- documented by their own comments. The public READ and DRAW paths are never
-- gated -- Test Mode fills the frames, it does not blind them.
--
-- WHAT A SYNTHETIC ENTRY IS. Every row this mode creates carries the tag
-- `_source = "test"` (`TestMode.Tag`) on a table of OURS -- never a value read
-- from the client, so the secret-value law is not in play at the tag itself.
-- The tag is the scrub key AND the silence key: the consumers that speak to the
-- world (Forte_Cooldown's FX_COOLDOWN_READY fire, Forte_Timer's
-- FX_TIMER_FADING / FX_TIMER_EXPIRED / FX_TIMER_BROKEN fires and its
-- expire-announce leg) skip a tagged row, which is how "Test Mode sends no
-- chat" holds without one gate inside Forte_Messages: a synthetic row never
-- reaches that add-on at all. A tagged row carries no `dObj` and no `itemID`,
-- so no consumer resolves it against a live unit, and the rows are built off
-- NAMES from our own generated data (the class spell table, the Timer's
-- registry) -- never a hand-typed spell id, and never a name compared against
-- a client name (docs/localization.md).
--
-- WHAT IT MUST NEVER DO.
--  * NO CHAT, NO COMMS. This file calls no send API: `FX.Print` writes into
--    DEFAULT_CHAT_FRAME:AddMessage, which is the local console echo, not a wire
--    send (the sends are C_ChatInfo.SendChatMessage / SendAddonMessage, which
--    live in Forte_Messages/Core/Announce.lua and Forte_Warlock/Core/Comms.lua
--    and are never named here). The synthetic events are silenced at their
--    fire sites, as above, so the two send counters stay 0 across a demo cycle.
--  * NO SETTINGS WRITE. The demo state is session-only. The options page's
--    "Test Mode" row is an ACTION button (Forte_Options/Core/Widgets.lua W.BTN,
--    no `key`): a W.CHK calls FX.Settings:Set and persists the demo mode into a
--    profile, which the sparse-store law forbids -- the store carries the
--    user's choices, not a demo switch (docs/research/upstream-addons-2026-11-03
--    .md §6 row 3: "never writes settings (sparse store law)").
--  * NO OnUpdate. The re-fill pump rides `C_Timer.NewTicker` created in
--    OnEnable, the Forte_Cooldown/Module.lua heartbeat idiom: a hidden frame
--    receives no OnUpdate, so an OnUpdate pump stops the moment the bar hides.
--  * NOT IN COMBAT. Starting is refused while `InCombatLockdown` answers a
--    plain true, and the reason is printed: synthetic rows on a live frame
--    during a fight are exactly the contamination the launch-day probes exist
--    to measure. The flag is sampled in a pcall and passes `Compat.PlainOrNil`
--    first (docs/aura-secret-display.md §2 -- the value may be secret, and a
--    secret answers "not known", which is not a refusal).
--  * LEAVING IS A SCRUB. Stopping by hand, a combat start (PLAYER_REGEN_DISABLED
--    @UnitDocumentation.lua:3884, the event Forte_Cooldown/Module.lua also
--    registers for its secret-state re-snapshot) and a logout / zone-out
--    (PLAYER_LOGOUT @PlayerDocumentation.lua:1342, PLAYER_LEAVING_WORLD
--    @UnitDocumentation.lua:1891 -- the leave events Forte_Messages' leave
--    handler and Forte_Timer/Module.lua treat as the "wipe it all" moment) all
--    run the same `Stop`, which asks every feeder to remove its tagged rows. A
--    synthetic row that outlives the mode is a row nobody can tell from a real
--    one: the one failure this slice may not ship.
--
-- The events are registered inside OnEnable -- Forte_Core's module loop runs at
-- PLAYER_LOGIN (Core/Init.lua), and a top-level RegisterEvent is forbidden
-- (AGENTS.md). Every client call this file makes is pcall'd and classified
-- through Compat.PlainOrNil.
ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist

local T = {}
FX.TestMode = T

--- The tag every synthetic row carries: the scrub key and the silence key.
T.SOURCE = "test"

--- The live flag. A plain boolean, read by the gated write sites.
T.active = false

--- The last verdict, printed by `/fx test status`: "on", "off", "combat",
--- "logout", "stopped", "disabled". Session-only, never stored.
T.reason = "off"

--- The pump interval: the CDM demo loop's own beat (UI/Cooldown.lua:1716
--- `spellCooldownPumpPeriod = 1`), the second the donor spread runs at.
T.pumpSeconds = 1

--- Counters for `/fx status` and the tests. They never print by themselves.
T.stats = { starts = 0, stops = 0, refusals = 0, pumped = 0, filled = 0,
    scrubbed = 0 }

--- The registered feeders, in registration order:
--- `{ Name = <string>, Fill = function(now) -> n, Scrub = function() -> n,
--- Live = function() -> n }`, registered by the feature that owns the frame.
T.feeders = {}

--- The injectable combat probe (the tests script it; the live default is the
--- catalog's own `InCombatLockdown`).
T.readers = nil

local function plain(v) return FX.Compat.PlainOrNil(v) end

--- Is the demo running? The gates ask this.
function T:IsActive()
    return self.active == true
end

--- Tag one of our own tables as synthetic. The table is ours by construction,
--- so the field write needs no protection.
function T.Tag(entry)
    if type(entry) == "table" then entry._source = T.SOURCE end
    return entry
end

--- Is this OUR synthetic row? True only for a plain table carrying the tag: a
--- userdata proxy never indexes to it, so the answer is "no" and a consumer
--- keeps its own behaviour (docs/aura-secret-display.md §3).
function T.IsSynthetic(v)
    return type(v) == "table" and v._source == T.SOURCE
end

--- Register a feeder (idempotent by name: a re-registration REPLACES the pair,
--- so a module re-enable cannot double a fill).
function T.RegisterFeeder(feeder)
    if type(feeder) ~= "table" or type(feeder.Name) ~= "string" then return nil end
    for i = 1, #T.feeders do
        if T.feeders[i].Name == feeder.Name then
            T.feeders[i] = feeder
            return feeder
        end
    end
    T.feeders[#T.feeders + 1] = feeder
    return feeder
end

local function callLive(f)
    return (type(f.Live) == "function") and (tonumber(f.Live()) or 0) or 0
end

local function callFill(f, now)
    return (type(f.Fill) == "function") and (tonumber(f.Fill(now)) or 0) or 0
end

local function callScrub(f)
    return (type(f.Scrub) == "function") and (tonumber(f.Scrub()) or 0) or 0
end

--- Run one feeder hook over every feeder, summing the row counts. A feeder
--- that raises is counted as nothing and the pass continues: one feature's
--- demo must never break another's, and a demo is never a crash path.
local function eachFeeder(fn)
    local total = 0
    for i = 1, #T.feeders do
        local f = T.feeders[i]
        local ok, n = pcall(fn, f, GetTime())
        if ok and type(n) == "number" then total = total + n end
    end
    return total
end

--- The live synthetic row count over every feeder: the tests' proof that "no
--- tagged row survives an exit", and `/fx test status`'s number.
function T:Count()
    return eachFeeder(callLive)
end

--- The combat gate: a plain true is the only refusal. An absent probe, a raise
--- or a secret value answer "not known", which is not a reason to refuse a
--- layout pass (the SecretState consumer law, docs/aura-secret-display.md §2).
function T:InCombat()
    local probe = self.readers and self.readers.inCombat
    if probe == nil then probe = InCombatLockdown end
    if type(probe) ~= "function" then return false end
    local ok, combat = pcall(probe)
    return (ok and plain(combat) == true) and true or false
end

--- Start the demo. The live rows go first (the CDM `TestMode()` law: the demo
--- starts from a cleared frame, not from a half-full one), then the fill.
function T:Start()
    if self.active then return true, "already" end
    if self:InCombat() then
        self.stats.refusals = self.stats.refusals + 1
        self.reason = "combat"
        FX.Print("Test Mode: NOT started - you are in combat. Synthetic rows "
            .. "would mix into the live frames and into the launch-day probes;"
            .. " run /fx test out of combat.")
        return false, "combat"
    end
    self.active = true
    self.reason = "on"
    self.stats.starts = self.stats.starts + 1
    local cleared = eachFeeder(callScrub)
    local filled = eachFeeder(callFill)
    self.stats.filled = self.stats.filled + filled
    FX.Print(string.format(
        "Test Mode: ON - %d synthetic row%s over %d feeder%s (%d live row%s "
        .. "cleared). Real feeds are paused; /fx test again, a combat start, "
        .. "or a logout scrubs everything.",
        filled, (filled == 1) and "" or "s", cleared, (cleared == 1) and ""
        or "s", #self.feeders, (#self.feeders == 1) and "" or "s"))
    return true, "on"
end

--- Stop the demo: scrub every tagged row FIRST, then drop the flag -- so a
--- feeder that has gone away (its add-on disabled) can not leave a tagged row
--- behind, and so the flag never reads "on" over an empty frame.
function T:Stop(why)
    if not self.active then return false, "off" end
    local n = eachFeeder(callScrub)
    self.active = false
    self.reason = why or "off"
    self.stats.stops = self.stats.stops + 1
    self.stats.scrubbed = self.stats.scrubbed + n
    if why == "logout" then
        -- The client is tearing the session down; a chat line at a logout is a
        -- line nobody reads (the same ruling Forte_Messages applies to its own
        -- leave-world pass).
        return true, "logout"
    end
    FX.Print(string.format("Test Mode: OFF (%s) - %d synthetic row%s scrubbed.",
        tostring(why or "stopped"), n, (n == 1) and "" or "s"))
    return true, why or "off"
end

--- Toggle: the `/fx test` verb and the options page's button.
function T:Toggle()
    if self.active then return self:Stop("stopped") end
    return self:Start()
end

--- Re-fill after a feature rebuilt its own state (`Engine:Build` wipes its
--- entries, Forte_Cooldown/Module.lua:Rebuild): the mode is still on, so the
--- frame the player is looking at keeps its demo rows.
function T:Refill()
    if not self.active then return 0 end
    local n = eachFeeder(callFill)
    self.stats.filled = self.stats.filled + n
    return n
end

--- The pump: a feeder whose rows have all run out gets them back, which is
--- what keeps a demo walkable through a whole layout session (the CDM pump
--- loop, Core/Cooldown.lua:1768-1798, over a donor spread). Public so a test
--- drives it without reaching for the client's ticker.
function T:Pump()
    if not self.active then return 0 end
    local n = eachFeeder(function(f, now)
        if callLive(f) == 0 then return callFill(f, now) end
        return 0
    end)
    self.stats.pumped = self.stats.pumped + 1
    self.stats.filled = self.stats.filled + n
    return n
end

--- `/fx test [|status]`: toggle, or report.
function T:Slash(input)
    local arg = ((input or ""):match("^(%S+)") or ""):lower()
    if arg == "status" then
        FX.Print(string.format(
            "Test Mode: %s | %d synthetic row%s over %d feeder%s",
            tostring(self.reason), self:Count(),
            (self:Count() == 1) and "" or "s", #self.feeders,
            (#self.feeders == 1) and "" or "s"))
        return
    elseif arg == "off" then
        if self.active then self:Stop("stopped") end
        return
    elseif arg == "on" then
        if not self.active then self:Start() end
        return
    end
    self:Toggle()
end

FX.RegisterSlash("test", function(input) T:Slash(input) end)

-- ------------------------------------------------------------------ lifecycle --
--- The leave/combat scrub. PLAYER_REGEN_DISABLED is the combat-start edge: the
--- demo must not ride a fight, so the mode stops and says why. The leave events
--- stop it silently: the session is going away.
function T:OnEvent(event)
    if event == "PLAYER_REGEN_DISABLED" then
        if self.active then self:Stop("combat") end
    elseif event == "PLAYER_LOGOUT" or event == "PLAYER_LEAVING_WORLD" then
        if self.active then self:Stop("logout") end
    end
end

function T:OnEnable()
    -- One frame, created inside the enable (a top-level RegisterEvent is
    -- forbidden). Every name is verified in the pinned Forever catalog first:
    -- PLAYER_REGEN_DISABLED @UnitDocumentation.lua:3884, PLAYER_LOGOUT
    -- @PlayerDocumentation.lua:1342, PLAYER_LEAVING_WORLD
    -- @UnitDocumentation.lua:1891.
    local f = CreateFrame("Frame")
    self._eventFrame = f   -- the tests' handle: they dispatch events on it
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_LOGOUT")
    f:RegisterEvent("PLAYER_LEAVING_WORLD")
    f:SetScript("OnEvent", function(_, event) self:OnEvent(event) end)
    -- The re-fill pump: a C_Timer ticker, never an OnUpdate (a hidden frame
    -- receives none). Cancelled at the disable.
    if C_Timer and C_Timer.NewTicker then
        local ok, ticker = pcall(C_Timer.NewTicker, self.pumpSeconds, function()
            T:Pump()
        end)
        if ok then self._ticker = ticker end
    end
end

function T:OnDisable()
    self:Stop("disabled")
    if self._ticker and self._ticker.Cancel then
        pcall(self._ticker.Cancel, self._ticker)
    end
    self._ticker = nil
end

--- The `/fx status` block (Forte_Core's status loop calls Status per module).
function T:Status()
    FX.Print(string.format(
        "Test Mode: %s | feeders %d | rows %d | starts %d stops %d refusals %d",
        tostring(self.reason), #self.feeders, self:Count(),
        self.stats.starts, self.stats.stops, self.stats.refusals))
    for i = 1, #self.feeders do
        local f = self.feeders[i]
        FX.Print(string.format("  %s: %d rows", tostring(f.Name), callLive(f)))
    end
end

FX.RegisterModule("TestMode", T)

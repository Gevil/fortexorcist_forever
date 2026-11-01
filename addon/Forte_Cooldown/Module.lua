-- Forte_Cooldown/Module.lua
-- Event wiring between the game and Core/Engine.lua: cast events, cooldown
-- reads, the 10 Hz ticker, class rebuilds. All state lives in the Engine;
-- this file only decides *when* it is fed.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
local Engine = FX.Cooldown.Engine

local M = {}
FX.Cooldown.Module = M
FX.RegisterModule("Cooldown", M)

local TICK_SECONDS = 0.1        -- 10 Hz display/sweep cadence
local READ_DEBOUNCE = 0.1       -- coalesce a SPELL_UPDATE_COOLDOWN burst
local REBUILD_DEBOUNCE = 0.5    -- coalesce a SPELLS_CHANGED burst
local READ_NET_TICKS = 10       -- every 10th tick = 1 Hz safety read pass

-- Scratch tables reused for the life of the session: these fill every tick,
-- so allocating per tick is pure garbage for the collector.
local readyScratch = {}
local sortedScratch = {}

local readPending, rebuildPending = false, false
local reasonShown = false

--- Can the player cast this spell? C_Spell resolves a name to exactly the
--- rank this character knows (that's why the Engine keys by name), and
--- IsPlayerSpell filters out name-squatters like trinket procs and trade
--- skills that share a name with a class spell.
local function isKnown(name)
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(name)
    local spellID = FX.Compat.PlainOrNil(info and info.spellID)
    return spellID ~= nil and FX.Compat.IsPlayerSpell(spellID)
end

--- Full read pass over every tracked spell, run at 1 Hz and from
--- SPELL_UPDATE_COOLDOWN/PLAYER_REGEN_ENABLED. `Engine:OnRead` /
--- `Engine:OnReadCharges` guard the values themselves (they may be secret in
--- combat), so we hand them the raw reads.
function M:ReadAll()
    local now = GetTime()
    local chargesReader = FX.Compat.GetSpellCharges
    for name in pairs(Engine.tracked) do
        -- pcall: a live read can itself throw on Forever (secret values
        -- propagate as a raise, not just a bad value). One spell blowing up
        -- must not abort the rest of the pass.
        local ok, info = pcall(FX.Compat.GetSpellCooldownInfo, name)
        if ok and info then
            Engine:OnRead(name, info.startTime, info.duration, now)
            if chargesReader then
                local okC, charge = pcall(chargesReader, name)
                if okC and charge then
                    Engine:OnReadCharges(name, charge.currentCharges,
                        charge.cooldownStartTime, charge.cooldownDuration, now)
                end
            end
            -- Active-edge fallback (PLAN §8 mitigation 2): a secret cast
            -- event spellsID leaves in-combat prediction with no event to
            -- ride, but isActive/isOnGCD are NeverSecret -- the cooldown
            -- itself says it is running. Only for spells with no live entry
            -- (a cast, a plain anchor, or a charges anchor above owns it).
            if not Engine.entries[name]
                and info.isActive == true and info.isOnGCD ~= true then
                Engine:OnActiveEdge(name, now)
            end
        else
            -- Legacy multi-return client: no info table means no booleans
            -- and no charge pair -- plain numbers only, no edge fallback.
            local okG, start, duration = pcall(FX.Compat.GetSpellCooldown, name)
            if okG then
                Engine:OnRead(name, start, duration, now)
            end
        end
    end
end

function M:Rebuild()
    local n, reason = Engine:Build(FX._playerClass, isKnown)
    if not n then
        -- SPELLS_CHANGED can fire constantly (loot, talents, levels). Say
        -- "no data for your class" once, not once per event.
        if not reasonShown then
            reasonShown = true
            FX.Print("cooldowns: " .. tostring(reason))
        end
        return
    end
    reasonShown = false
    -- Multi-charge detection: a live C_Spell.GetSpellCharges sweep marks
    -- tracked spells whose (NeverSecret) maxCharges is > 1. Runtime facts,
    -- not data -- see Engine:DetectCharges and the Engine header.
    Engine:DetectCharges()
    M:ReadAll()
end

--- Bind (and create) the cast-secrecy counters. The numbers live in
--- FX.db.diag.casts (SavedVariables -- cumulative across sessions), or in a
--- session-local table when SavedVariables never arrived. The pinned
--- Forever catalog annotates UNIT_SPELLCAST_SUCCEEDED's spellID with
--- SecretWhenUnitSpellCastRestricted (PLAN §8: "our own spellID is plain in
--- combat" is CooldownMaster's observation, NOT a guarantee), so every event
--- is counted: seen / plainId / secretId (a nil id is not usable, it counts
--- as secret) / resolved (the id named a spell) / unresolved. The in-combat
--- half is counted separately (InCombatLockdown sampled at event time);
--- out-of-combat is totals minus the split.
function M:InitCastDiag()
    local d
    if FX.db then
        FX.db.diag = FX.db.diag or {}
        FX.db.diag.casts = FX.db.diag.casts or {}
        d = FX.db.diag.casts
    elseif not M._castDiag then
        d = {}
    else
        d = M._castDiag
    end
    if d.seen == nil then
        d.seen, d.plainId, d.secretId, d.resolved, d.unresolved = 0, 0, 0, 0, 0
        d.inSeen, d.inPlain, d.inSecret, d.inResolved, d.inUnresolved = 0, 0, 0, 0, 0
    end
    M._castDiag = d
    return d
end

--- One UNIT_SPELLCAST_SUCCEEDED for the player. The event payload is
--- (unit, castGUID, spellID, castBarID) -- the handler's signature tolerates
--- the 4th field (PLAN §8 mitigation 3); `inCombat` is InCombatLockdown()
--- sampled at event time (tests pass it explicitly). Count the spellID's
--- secrecy, resolve the name and feed Engine:OnCast from it. NEVER any
--- arithmetic/comparison on a raw spellID: it is classified through
--- PlainOrNil and only ever looked up (pcall: a tainted-argument lookup
--- may raise in a restricted environment).
function M:RecordCastEvent(spellID, inCombat)
    local d = M._castDiag
    if not d then d = M:InitCastDiag() end
    d.seen = d.seen + 1
    if inCombat then d.inSeen = d.inSeen + 1 end
    if FX.Compat.PlainOrNil(spellID) ~= nil then
        d.plainId = d.plainId + 1
        if inCombat then d.inPlain = d.inPlain + 1 end
    else
        d.secretId = d.secretId + 1
        if inCombat then d.inSecret = d.inSecret + 1 end
    end
    local name
    if spellID ~= nil and C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and info then
            name = FX.Compat.PlainOrNil(info.name)
        end
    end
    if name then
        d.resolved = d.resolved + 1
        if inCombat then d.inResolved = d.inResolved + 1 end
        Engine:OnCast(name, GetTime())
    else
        d.unresolved = d.unresolved + 1
        if inCombat then d.inUnresolved = d.inUnresolved + 1 end
    end
end

function M:OnEnable()
    -- FX.db is set by Forte_Core at ADDON_LOADED; if SavedVariables never
    -- arrived (beta-era bug class), keep learned durations session-local.
    local storage
    if FX.db then
        FX.db.cooldownLearned = FX.db.cooldownLearned or {}
        storage = FX.db.cooldownLearned
    else
        storage = {}
    end
    Engine:AttachStorage(storage)
    M:InitCastDiag()

    -- One frame, created here inside the PLAYER_LOGIN handler: a top-level
    -- RegisterEvent can throw ADDON_ACTION_FORBIDDEN off a tainted chunk
    -- (see Forte_Core/Core/Init.lua).
    local f = CreateFrame("Frame")
    f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    f:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:RegisterEvent("SPELLS_CHANGED")
    f:SetScript("OnEvent", function(_, event, unit, castGUID, spellID, castBarID)
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            -- Our own casts: the signal most likely to stay readable in
            -- combat, but the 4-field payload (unit, castGUID, spellID,
            -- castBarID) is tolerated above and RecordCastEvent counts the
            -- spellID's secrecy per event (the first live session reads the
            -- truth off /fx status).
            local inCombat = type(InCombatLockdown) == "function" and InCombatLockdown()
            M:RecordCastEvent(spellID, inCombat and true or false)
        elseif event == "SPELL_UPDATE_COOLDOWN" then
            -- Blizzard says one cooldown changed; it says this per spell, so
            -- a spell-learn burst would mean N passes. Coalesce to one.
            if not readPending then
                readPending = true
                C_Timer.After(READ_DEBOUNCE, function()
                    readPending = false
                    M:ReadAll()
                end)
            end
        elseif event == "PLAYER_REGEN_ENABLED" then
            -- Regen back = out of combat = every read is plain again. The one
            -- moment predictions get re-anchored and real durations learned.
            M:ReadAll()
        elseif event == "SPELLS_CHANGED" then
            if not rebuildPending then
                rebuildPending = true
                C_Timer.After(REBUILD_DEBOUNCE, function()
                    rebuildPending = false
                    M:Rebuild()
                end)
            end
        end
    end)

    -- 10 Hz heartbeat: sweep ready alerts + feed the display. Every 10th
    -- tick do a full read pass: the 1 Hz safety net self-heals any spell
    -- whose events we missed (a hidden event, a combat-locked read).
    local ticks = 0
    C_Timer.NewTicker(TICK_SECONDS, function()
        local now = GetTime()
        ticks = ticks + 1
        wipe(readyScratch)
        local disp = FX.Cooldown.Display
        for _, name in ipairs(Engine:Sweep(now, readyScratch)) do
            FX.Print(name .. " ready")
            -- The only extra feed the Display needs: "this name just became
            -- ready" drives its ready pulse. Splash/fade come from first-
            -- sighting inside Update itself.
            if disp and disp.OnReady then
                disp:OnReady(name, now)
            end
        end
        if ticks % READ_NET_TICKS == 0 then
            M:ReadAll()
        end
        if FX.Cooldown.Display then
            FX.Cooldown.Display:Update(Engine:Sorted(sortedScratch), now)
        end
    end)

    -- Display arrives with UI/Display.lua; nil-safe until that lands.
    if FX.Cooldown.Display then FX.Cooldown.Display:Init() end
    M:Rebuild()
end

--- `/fx` status hook (Init.lua is not edited; `FX.Cooldown.Module:Status()`
--- is the entry point). Counts + live entries with remaining seconds.
function M:Status()
    local tracked = 0
    for _ in pairs(Engine.tracked) do tracked = tracked + 1 end
    local active = Engine:Sorted(sortedScratch)
    FX.Print(string.format("Cooldown: %d tracked, %d active", tracked, #active))
    for _, e in ipairs(active) do
        FX.Print(string.format("  %s: %.1fs%s", e.name,
            math.max(0, e.endTime - GetTime()),
            e.predicted and " (predicted)" or ""))
    end
    -- Cast-secrecy counters (PLAN §8 "instrument" mitigation): the first
    -- live combat session reads the truth off the `secret` column.
    local d = M._castDiag
    if d then
        FX.Print(string.format("casts seen %d | plain %d | secret %d | unresolved %d",
            d.seen, d.plainId, d.secretId, d.unresolved))
        FX.Print(string.format(
            "  in-combat seen %d | plain %d | secret %d | unresolved %d",
            d.inSeen, d.inPlain, d.inSecret, d.inUnresolved))
        FX.Print(string.format(
            "  out-of-combat seen %d | plain %d | secret %d | unresolved %d",
            d.seen - d.inSeen, d.plainId - d.inPlain,
            d.secretId - d.inSecret, d.unresolved - d.inUnresolved))
    end
end

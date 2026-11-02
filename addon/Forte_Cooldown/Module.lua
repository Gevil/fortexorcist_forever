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
local RESCAN_DEBOUNCE = 0.5     -- coalesce an inventory-change burst
local READ_NET_TICKS = 10       -- every 10th tick = 1 Hz safety read pass

-- Scratch tables reused for the life of the session: these fill every tick,
-- so allocating per tick is pure garbage for the collector.
local readyScratch = {}
local sortedScratch = {}

-- READ-TIER EVIDENCE (docs/research/secrets-unknowns.md §2 + §5, ranked
-- change 1-3; PLAN §8 "instrument" law). How often each tier of the read
-- ladder actually DID something this session:
--   numeric  a plain C_Spell.GetSpellCooldown/GetSpellCharges read anchored
--            or cleared an entry (Engine:OnRead verdicts).
--   boolean  the NeverSecret isActive/isOnGCD pair ended a prediction early
--            ("cleared") or started an "edge" entry no cast event named.
--   duration the unannotated duration object anchored an entry.
-- Built at load, so PER SESSION by construction; InitReadTiers republishes
-- the same table into FX.db.diag for /fx status to read. The launch-day
-- question -- "which tiers are real on the live client" -- is answered by
-- the boolean/duration columns.
local readTiers = { numeric = 0, boolean = 0, duration = 0 }

local readPending, rebuildPending, rescanPending = false, false, false
local reasonShown = false
local zeroShown = false

--- Coalesced item rescan (PLAYER_ENTERING_WORLD / BAG_UPDATE_COOLDOWN /
--- PLAYER_EQUIPMENT_CHANGED / BAG_UPDATE_DELAYED -- all four verified in
--- the pinned Forever catalog). A looting spree fires the bag events per
--- item; one rescan covers the burst.
local function requestRescan()
    if rescanPending then return end
    rescanPending = true
    C_Timer.After(RESCAN_DEBOUNCE, function()
        rescanPending = false
        if Engine.Items then Engine.Items:Rescan() end
    end)
end

--- Can the player cast this spell? C_Spell resolves a name to exactly the
--- rank this character knows (that's why the Engine keys by name), and
--- IsPlayerSpell filters out name-squatters like trinket procs and trade
--- skills that share a name with a class spell.
local function isKnown(name)
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(name)
    local spellID = FX.Compat.PlainOrNil(info and info.spellID)
    return spellID ~= nil and FX.Compat.IsPlayerSpell(spellID)
end

--- LuaDurationObject probes, hoisted so the 1 Hz pass allocates nothing.
--- Every one runs inside a pcall at the call site: a client object may lack
--- the method, and a read on a restricted client raises.
local function durationHasSecret(obj)
    return obj:HasSecretValues()
end
local function durationRemaining(obj)
    return obj:GetRemainingDuration()
end
local function durationTotal(obj)
    return obj:GetTotalDuration()
end

--- Tier 3 of the read ladder for one spell (Engine:OnReadDuration). The
--- object of C_Spell.GetSpellCooldownDuration(spell, true) -- the ignoreGCD
--- form, so the GCD's own window cannot masquerade as the spell's -- is the
--- one cooldown-timing read with NO output-restriction annotation
--- (docs/research/secrets-unknowns.md §2), so it may stay plain right
--- through a combat lockdown of the SpellCooldownInfo numbers. Gate:
--- `HasSecretValues()` answered PLAIN FALSE (`ReturnsNeverSecret` per the
--- pinned catalog) and `GetRemainingDuration()` is a plain number. Anything
--- secret, absent, un-callable or raising changes nothing -- this tier is
--- opportunistic by construction.
local function readDurationObject(name, now)
    local read = FX.Compat.GetSpellCooldownDurationObject
    if not read then return nil end
    local ok, obj = pcall(read, name, true)
    if not ok or not obj then return nil end
    local okS, has = pcall(durationHasSecret, obj)
    local plainSecret = okS and FX.Compat.PlainOrNil(has)
    if plainSecret ~= false then return nil end
    local okR, rem = pcall(durationRemaining, obj)
    if not okR then return nil end
    local okT, tot = pcall(durationTotal, obj)
    return Engine:OnReadDuration(name, rem, okT and tot or nil, now)
end

--- Full read pass over every tracked spell, run at 1 Hz and from
--- SPELL_UPDATE_COOLDOWN/PLAYER_REGEN_ENABLED. The Engine tiers guard the
--- values themselves (they may be secret in combat), so we hand them the raw
--- reads. The three tiers (Core/Engine.lua header): numeric
--- OnRead/OnReadCharges, then the NeverSecret boolean pair
--- (Engine:OnReadActive), then the unannotated duration object.
--- FX.SecretState.cooldownsSecret == true skips TIER 1 ONLY: the mode is a
--- work-saver, and a plain numeric read that does arrive is never discarded
--- on the strength of it (the spell-level exceptions the mode cannot see).
function M:ReadAll()
    local now = GetTime()
    local chargesReader = FX.Compat.GetSpellCharges
    local skipNumeric = FX.SecretState ~= nil
        and FX.SecretState.CooldownReadsAreSecret ~= nil
        and FX.SecretState.CooldownReadsAreSecret()
    for name in pairs(Engine.tracked) do
        local isActive, isOnGCD
        local ok, info = false, nil
        if not skipNumeric then
            -- pcall: a live read can itself throw on Forever (secret values
            -- propagate as a raise, not just a bad value). One spell blowing
            -- up must not abort the rest of the pass.
            ok, info = pcall(FX.Compat.GetSpellCooldownInfo, name)
        end
        if ok and info then
            -- Count the tier only when the read MOVED state: an "anchored"
            -- verdict always qualifies; a "cleared" one only when an entry
            -- was there to retire (a plain "ready" read of a spell with no
            -- entry is the common no-op, and counting it would bury the
            -- launch-day signal under ~40 hits a second).
            local hadEntry = Engine.entries[name] ~= nil
            local verdict = Engine:OnRead(name, info.startTime, info.duration, now)
            if verdict == "anchored" or (verdict == "cleared" and hadEntry) then
                readTiers.numeric = readTiers.numeric + 1
            end
            -- The booleans of the same read (NeverSecret -- the numbers of
            -- this very call may have come back secret, the pair did not).
            isActive, isOnGCD = info.isActive, info.isOnGCD
            if chargesReader then
                local okC, charge = pcall(chargesReader, name)
                if okC and charge then
                    Engine:OnReadCharges(name, charge.currentCharges,
                        charge.cooldownStartTime, charge.cooldownDuration, now)
                end
            end
        elseif not skipNumeric then
            -- Legacy multi-return client: no info table means no booleans
            -- and no charge pair -- plain numbers only, no boolean tier.
            local hadEntry = Engine.entries[name] ~= nil
            local okG, start, duration = pcall(FX.Compat.GetSpellCooldown, name)
            if okG then
                local verdict = Engine:OnRead(name, start, duration, now)
                if verdict == "anchored" or (verdict == "cleared" and hadEntry) then
                    readTiers.numeric = readTiers.numeric + 1
                end
            end
        end
        -- Tier 2. Also the ONLY tier that sees the booleans of a read whose
        -- numbers were secret -- that is its whole purpose -- and it owns
        -- the active-edge fallback (Engine:OnActiveEdge) the previous
        -- revision of this pass called by hand.
        local active = Engine:OnReadActive(name, isActive, isOnGCD, now)
        if active == "cleared" or active == "edge" then
            readTiers.boolean = readTiers.boolean + 1
        end
        -- Tier 3.
        if readDurationObject(name, now) == "anchored" then
            readTiers.duration = readTiers.duration + 1
        end
    end
    -- The item side rides the same pass: its entries live in
    -- Engine.entries too, so the 1 Hz net, PLAYER_REGEN_ENABLED and the
    -- debounced read events re-anchor items exactly like spells.
    if Engine.Items then
        Engine.Items:ReadAll(now)
    end
end

function M:Rebuild()
    -- The source line and the zero notice below describe THIS pass: clear
    -- the recorded source so Build's isKnown calls repopulate it (nil =
    -- no source answered during this Rebuild).
    FX.Compat.isPlayerSpellSource = nil
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
    -- M4 (review 2026-11-01): the data is there, the class is right, and
    -- the isKnown gate resolved NOTHING -- the shape a missing
    -- spell-known source leaves behind (IsPlayerSpell is not in the pinned
    -- Forever catalog; Compat.IsPlayerSpell now chains through the
    -- C_SpellBook fallbacks and records which source answers). 0 is
    -- truthy in Lua, so the `not n` branch above cannot carry this: say it
    -- out loud, naming the source, once per session -- an empty bar is
    -- otherwise indistinguishable from "nothing to show".
    if n == 0 and not zeroShown then
        zeroShown = true
        FX.Print("cooldowns: 0 spells known - spell-known check via "
            .. tostring(FX.Compat.isPlayerSpellSource
                or "none (IsPlayerSpell and C_SpellBook absent)")
            .. "; report this")
    end
    -- Multi-charge detection: a live C_Spell.GetSpellCharges sweep marks
    -- tracked spells whose (NeverSecret) maxCharges is > 1. Runtime facts,
    -- not data -- see Engine:DetectCharges and the Engine header.
    Engine:DetectCharges()
    M:ReadAll()
end

--- Core FX.RefreshPlayerClass notification (uiforever T4 class guard):
--- the tracked set is class data, so a class change is a full rebuild.
function M:OnClassChanged()
    M:Rebuild()
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

--- Publish the session's read-tier counters (the `readTiers` file header
--- table -- fresh per login by construction) at FX.db.diag.readTiers so the
--- live table is what a `/fx status` prints, and keep the same reference on
--- M._readTiers for the read pass and the status hook. The counters are
--- deliberately NOT cumulative across sessions (unlike the cast counters):
--- the launch-day question is "what did this session's combat look like",
--- and a sum over 200 sessions cannot answer it.
function M:InitReadTiers()
    if FX.db then
        FX.db.diag = FX.db.diag or {}
        FX.db.diag.readTiers = readTiers
    end
    M._readTiers = readTiers
    return readTiers
end

--- Re-snapshot FX.SecretState (Forte_Core/Core/Compat.lua): the six
--- add-on-restriction types plus ShouldCooldownsBeSecret/ShouldAurasBeSecret,
--- all cheap, all pcall'd inside. Driven by ADDON_RESTRICTION_STATE_CHANGED
--- (the regime flipped), PLAYER_REGEN_DISABLED (combat started) and
--- PLAYER_REGEN_ENABLED (out of combat -- the reads the mode describes just
--- became plain) and once at PLAYER_LOGIN. A client without the surface
--- (the wow-ui-sim build ships neither C_RestrictedActions nor C_Secrets)
--- leaves every field nil = unknown, which ReadAll reads as "ask everything"
--- and /fx status prints as `nil` -- the honest launch-day answer.
function M:RefreshSecretState()
    if FX.SecretState and FX.SecretState.Refresh then
        local ok, err = pcall(FX.SecretState.Refresh)
        if not ok then
            FX.Print("|cffff5555secret-state refresh failed:|r " .. tostring(err))
        end
    end
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
    -- No `spellID ~= nil` here: that is a comparison on a possibly-secret
    -- payload field. The pcall absorbs a nil/invalid argument instead.
    -- The info table may carry conditional-secret contents, so its truth test
    -- and field read stay inside the protected call; only a plain string leaves.
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, resolved = pcall(function()
            local info = C_Spell.GetSpellInfo(spellID)
            return info and FX.Compat.PlainOrNil(info.name)
        end)
        if ok and type(resolved) == "string" then name = resolved end
    end
    if name then
        d.resolved = d.resolved + 1
        if inCombat then d.inResolved = d.inResolved + 1 end
        Engine:OnCast(name, GetTime())
        -- Item path: a resolved name that is some tracked item's use spell
        -- starts its predicted window (shared potion category included);
        -- a class spell is inert here (not in byCastSpell).
        if Engine.Items then
            Engine.Items:OnCastBySpellName(name, GetTime())
        end
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
    M:InitReadTiers()
    -- The cached secrecy mode, read by ReadAll (skip-work only) and printed
    -- by /fx status. The client owns the truth; this is our snapshot of it.
    M:RefreshSecretState()

    -- One frame, created here inside the PLAYER_LOGIN handler: a top-level
    -- RegisterEvent can throw ADDON_ACTION_FORBIDDEN off a tainted chunk
    -- (see Forte_Core/Core/Init.lua).
    local f = CreateFrame("Frame")
    M._eventFrame = f -- the tests' handle: they dispatch events on it
    f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    f:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:RegisterEvent("SPELLS_CHANGED")
    -- The secrecy-mode triggers. Both names verified in the pinned Forever
    -- catalog before registration: ADDON_RESTRICTION_STATE_CHANGED
    -- (type, state) @RestrictedActionsDocumentation.lua:96 -- the one event
    -- that says the regime flipped -- and PLAYER_REGEN_DISABLED
    -- @UnitDocumentation.lua:3884 (PLAYER_REGEN_ENABLED, :3890, is already
    -- registered below as the out-of-combat read trigger).
    f:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    -- Item rescan triggers -- every event name verified in the pinned
    -- Forever catalog (SystemDocumentation / ContainerDocumentation /
    -- PaperDollInfoDocumentation) before registration.
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("BAG_UPDATE_COOLDOWN")
    f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    f:RegisterEvent("BAG_UPDATE_DELAYED")
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
        elseif event == "ADDON_RESTRICTION_STATE_CHANGED"
            or event == "PLAYER_REGEN_DISABLED" then
            -- The regime flipped (an add-on restriction type went
            -- Inactive/Activating/Active, or combat started): re-snapshot
            -- the mode. The payload (type, state) lands in the handler's
            -- `unit`/`castGUID` slots and is deliberately ignored -- the
            -- queries answer the question directly, no book-keeping needed.
            M:RefreshSecretState()
        elseif event == "PLAYER_REGEN_ENABLED" then
            -- Regen back = out of combat = every read is plain again. The one
            -- moment predictions get re-anchored and real durations learned.
            -- Refresh FIRST so this pass sees the mode it is about to run in.
            M:RefreshSecretState()
            M:ReadAll()
        elseif event == "SPELLS_CHANGED" then
            if not rebuildPending then
                rebuildPending = true
                C_Timer.After(REBUILD_DEBOUNCE, function()
                    rebuildPending = false
                    M:Rebuild()
                end)
            end
        elseif event == "PLAYER_ENTERING_WORLD"
            or event == "BAG_UPDATE_COOLDOWN"
            or event == "PLAYER_EQUIPMENT_CHANGED"
            or event == "BAG_UPDATE_DELAYED" then
            -- Inventory changed (loot, equip, a drunk potion's slot, zone-in
            -- resync): which items exist is a fresh question. The events
            -- carry payloads (booleans / an equipment slot) this branch
            -- deliberately ignores -- a rescan re-reads the whole inventory.
            requestRescan()
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
    -- First item sweep at login (PLAYER_ENTERING_WORLD re-runs it after a
    -- zone-in; the bag events cover looting). A no-op when Forte_Items is
    -- not installed -- Core/Items.lua degrades silently.
    if Engine.Items then Engine.Items:Rescan() end
end

--- `/fx` status hook (Init.lua is not edited; `FX.Cooldown.Module:Status()`
--- is the entry point). Counts + live entries with remaining seconds.
function M:Status()
    local tracked = 0
    for _ in pairs(Engine.tracked) do tracked = tracked + 1 end
    local active = Engine:Sorted(sortedScratch)
    FX.Print(string.format("Cooldown: %d tracked, %d active", tracked, #active))
    -- M4: the /fx status probe for the spell-known gate. "not probed"
    -- means IsPlayerSpell/chain was never consulted; the fallback names
    -- say the legacy IsPlayerSpell global was absent on this client.
    FX.Print(string.format("spell-known check: %s",
        tostring(FX.Compat.isPlayerSpellSource or "not probed")))
    -- The cached secrecy mode (launch-day probe #1,
    -- docs/research/secrets-unknowns.md §5 "Remaining live probe"): type
    -- abbreviations are combat / encounter / cooldowns / auras. `nil` means
    -- this client gives us no answer at all.
    if FX.SecretState and FX.SecretState.StatusLine then
        FX.Print(FX.SecretState.StatusLine())
    end
    -- The read-tier evidence (see the `readTiers` file header): which tier
    -- of the read ladder actually moved state this session. In a real raid
    -- the `boolean` column is the proof the NeverSecret pair works, and the
    -- `duration` column the proof the unannotated duration object does.
    FX.Print(string.format("readTiers: numeric %d | boolean %d | duration %d",
        readTiers.numeric, readTiers.boolean, readTiers.duration))
    for _, e in ipairs(active) do
        FX.Print(string.format("  %s: %.1fs%s", e.name,
            math.max(0, e.endTime - GetTime()),
            e.predicted and " (predicted)" or ""))
    end
    if Engine.Items then
        local it, ia = Engine.Items:Counts()
        FX.Print(string.format("Items: %d tracked, %d active", it, ia))
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

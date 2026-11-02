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
-- [name] = { duration, icon, category } of a JUST-RETIRED entry: the pop
-- needs the facts of the window that just ended and the Sweep deletes the
-- entry it pops, so Engine:Sweep fills this at the pop site (its optional
-- `popInfo` argument, m3/CodeReview4). Filled ONLY for popping entries --
-- a per-tick snapshot of every live entry was the old shape. Keys of
-- already-delivered pops ride on (every pop rewrites its own key whole);
-- the map is bounded by the tracked-spell count, not by session time.
local popInfoScratch = {}

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
--- item; one rescan covers the burst. The weapon-enchant read pass rides
--- the same debounced timer: PLAYER_ENTERING_WORLD (the zone resync of the
--- enchant state, Core/Enchants.lua header) lands here as a
--- PLAYER_EQUIPMENT_CHANGED companion, and re-reading three weapon slots
--- on a bag event is three pcall'd reads, free.
local function requestRescan()
    if rescanPending then return end
    rescanPending = true
    C_Timer.After(RESCAN_DEBOUNCE, function()
        rescanPending = false
        if Engine.Items then Engine.Items:Rescan() end
        if Engine.Enchants then Engine.Enchants:ReadAll() end
    end)
end

--- Can the player cast this spell? C_Spell resolves a name to exactly the
--- rank this character knows (that's why the Engine keys by name), and
--- IsPlayerSpell filters out name-squatters like trinket procs and trade
--- skills that share a name with a class spell.
local function isKnown(name)
    -- H1 Localization: the name path (C_Spell.GetSpellInfo("Rapid Fire"))
    -- resolves against the CLIENT's localized name table, so on a non-enUS
    -- client it returns nil and every known filter dies. The generated data
    -- rows carry the ids: try the data row's own ids first (locale-
    -- independent, every rank row of the name), then keep the name path
    -- (it works on enUS clients and for names the data set does not carry).
    local ids = FX.Locale and FX.Locale.RankIDsForName(name)
    if ids then
        for i = 1, #ids do
            if FX.Compat.IsPlayerSpell(ids[i]) then return true end
        end
    end
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(name)
    local spellID = FX.Compat.PlainOrNil(info and info.spellID)
    return spellID ~= nil and FX.Compat.IsPlayerSpell(spellID)
end
-- Test seam (tests/test_locale_cooldown.lua): the gate's build path
-- needs the module's own isKnown, and it is module-local by law.
M.IsKnown = isKnown

-- H1b (docs/localization.md "Lookup-critical", the `Module.lua:119,154,379`
-- audit rows): every live cooldown read in this file used to be keyed by the
-- ENGLISH DATA NAME (`C_Spell.GetSpellCooldown("Rapid Fire")`,
-- GetSpellCharges, GetSpellTexture, GetSpellCooldownDuration). A
-- `SpellIdentifier` is legal as a name OR an id (the pinned catalog,
-- SpellDocumentation), and on an English client the name is the row's own
-- client name -- on a localized client it is a string the client's spell
-- table does not contain, so the whole read ladder (the numeric anchor, the
-- charges pair, the duration object, the pop icon) went blind while the cast
-- events and the learned durations kept the rows alive. The fix is the id
-- half of the same SpellIdentifier, and the data row's id is the join key the
-- Locale module already walks: `Locale.RankIDsForName(english)`.
--
-- The English path must not move: on a client whose locale IS English the
-- data name and the client name are the same string, so `readKey` returns the
-- name and every read is bit-identical to before. On any other client the
-- data id takes over, with `FX.L(name)` (the client's own display name, the
-- FW:SpellName law) as the fallback for a name no generated row carries.
--
-- The answer is memoized per name (one IsPlayerSpell chain per spell per
-- rebuild, not one per 1 Hz read of ~40 spells) and the cache is cleared by
-- Rebuild, the one place the known-spell set is a fresh question.
local readKeyCache = {}
local readKeyStamp = nil

local function readKey(name)
    if type(name) ~= "string" then return name end
    local Locale = FX.Locale
    local stamp = (Locale and Locale.GetLocale and tostring(Locale.GetLocale()))
        or ""
    -- The memo is a function of the LOCALE: the alias maps it reads are
    -- rebuilt per client locale (and per login), so a locale change -- the
    -- test seam, and the shape of a client that answers with a new locale --
    -- invalidates every key in it.
    if stamp ~= readKeyStamp then
        readKeyStamp = stamp
        wipe(readKeyCache)
    end
    local cached = readKeyCache[name]
    if cached ~= nil then return cached end
    local key = name
    if Locale and Locale.IsEnglish then
        local english = Locale.IsEnglish()
        if not english then
            local ids = Locale.RankIDsForName(name)
            if ids then
                key = ids[1]
                for i = 1, #ids do
                    if FX.Compat.IsPlayerSpell(ids[i]) then
                        key = ids[i]
                        break
                    end
                end
            elseif FX.L then
                key = FX.L(name)
            end
        end
    end
    readKeyCache[name] = key
    return key
end

--- The charges reader `Engine:DetectCharges` gets: the same locale-safe key,
--- the same FX.Compat seam (the Engine's own default is the raw C_Spell read,
--- which on a localized client answers for no tracked spell at all and so
--- never sets a `maxCharges` flag).
function M.ReadChargesFor(name)
    local read = FX.Compat.GetSpellCharges
    if not read then return nil end
    return read(readKey(name))
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
local function readDurationObject(name, now, key)
    local read = FX.Compat.GetSpellCooldownDurationObject
    if not read then return nil end
    local ok, obj = pcall(read, key or name, true)
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
        -- H1b: every C_Spell read of this pass takes the locale-safe key
        -- (the data row's id on a localized client, the English name on an
        -- English one). `name` stays the Engine's key -- the reads are keyed
        -- on the client's identifier space, the state on the data key space.
        local key = readKey(name)
        local isActive, isOnGCD
        local ok, info = false, nil
        if not skipNumeric then
            -- pcall: a live read can itself throw on Forever (secret values
            -- propagate as a raise, not just a bad value). One spell blowing
            -- up must not abort the rest of the pass.
            ok, info = pcall(FX.Compat.GetSpellCooldownInfo, key)
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
                local okC, charge = pcall(chargesReader, key)
                if okC and charge then
                    Engine:OnReadCharges(name, charge.currentCharges,
                        charge.cooldownStartTime, charge.cooldownDuration, now)
                end
            end
        elseif not skipNumeric then
            -- Legacy multi-return client: no info table means no booleans
            -- and no charge pair -- plain numbers only, no boolean tier.
            local hadEntry = Engine.entries[name] ~= nil
            local okG, start, duration = pcall(FX.Compat.GetSpellCooldown, key)
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
        if readDurationObject(name, now, key) == "anchored" then
            readTiers.duration = readTiers.duration + 1
        end
    end
    -- The item side rides the same pass: its entries live in
    -- Engine.entries too, so the 1 Hz net, PLAYER_REGEN_ENABLED and the
    -- debounced read events re-anchor items exactly like spells.
    if Engine.Items then
        Engine.Items:ReadAll(now)
    end
    -- The weapon-enchant side rides it too (Core/Enchants.lua): the reads
    -- carry no SecretWhen… annotation at the pin, and every field rides
    -- PlainOrNil inside its OnReadSlot -- a secret in-combat read leaves
    -- the entry counting down from its last plain anchor.
    if Engine.Enchants then
        Engine.Enchants:ReadAll(now)
    end
end

function M:Rebuild()
    -- The source line and the zero notice below describe THIS pass: clear
    -- the recorded source so Build's isKnown calls repopulate it (nil =
    -- no source answered during this Rebuild).
    FX.Compat.isPlayerSpellSource = nil
    -- The known-spell set is a fresh question now, so the memoized locale-
    -- safe read keys are (H1b: they ride IsPlayerSpell).
    wipe(readKeyCache)
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
    -- not data -- see Engine:DetectCharges and the Engine header. H1b: the
    -- sweep gets this module's locale-safe reader (the Engine's default is
    -- the raw C_Spell read keyed by the English data name, which a localized
    -- client answers for no tracked spell at all -- the flag would then never
    -- be measured on a non-enUS install).
    Engine:DetectCharges(M.ReadChargesFor)
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
        Engine:OnCast(FX.Locale and FX.Locale.CanonicalName(name)
                    or name, GetTime())
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

--- The pop's icon (the event contract's texPath): item entries carry the
--- texture on the snapshot; a spell resolves through the locale-safe read
--- key (H1b: `C_Spell.GetSpellTexture(<English name>)` is a lookup in the
--- CLIENT's name table -- nil for every tracked spell on a localized client,
--- so the pop, the splash and the FX_COOLDOWN_READY listeners lost their
--- icon; the data row's id is the same SpellIdentifier, locale-free).
--- pcall + PlainOrNil: a sealed GetSpellTexture read raises
--- or returns a secret (CodeReview3 m8), and a secret texture is no
--- poppable icon.
local function resolveReadyIcon(name)
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, v = pcall(C_Spell.GetSpellTexture, readKey(name))
        if ok then return FX.Compat.PlainOrNil(v) end
    end
    return nil
end

--- Sweep + dispatch the ready pops: the timeline's ready pulse, the
--- Secondary Splash (spec CD-27/CD-28, UI/Splash.lua) and the shared bus
--- event FX_COOLDOWN_READY (name, now, texPath, category) -- exactly one
--- fire per pop, nil-guarded so the Module is inert without the Forte_Core
--- event bus. Public: the 10 Hz ticker drives it, and the tests drive the
--- REAL pop path through it (the C_Timer ticker is not reachable headless).
--- The per-entry facts ride the Sweep's pop-site snapshot (Engine:Sweep's
--- `popInfo` argument): the Sweep deletes the entry it pops, and only a
--- popping entry is ever touched (m3, CodeReview4 -- the old pre-pass
--- re-snapshotted every live entry on every 10 Hz tick for a pop that is
--- rare).
--- E1 (CodeReview4, owner ruling): the pop prints NOTHING to chat. The
--- source's pop loop prints nothing at a pop (zero "ready" prints across
--- /tmp/fxref/Forte_Cooldown.lua); its ">> %s is ready in %s <<" trio
--- (Forte_Core.lua:2188 `FW:ShowTimeFor`, Forte_Cooldown.lua:911,1128) is
--- the bar-icon CLICK readout family, not this one. The chat voice is
--- Forte_Messages' SelfMsg `ReadyChat` row (the templated, coloured,
--- original-shaped one, opt-in, default off); the gate is the owner's, not
--- this loop's -- an ungated print here was un-offable chat spam.
function M:ProcessReadyPops(now)
    wipe(readyScratch)
    local disp = FX.Cooldown.Display
    for _, name in ipairs(Engine:Sweep(now, readyScratch, popInfoScratch)) do
        -- The only extra feed the Display needs: "this name just became
        -- ready" drives its ready pulse. Splash/fade come from first-
        -- sighting inside Update itself.
        if disp and disp.OnReady then
            disp:OnReady(name, now)
        end
        local info = popInfoScratch[name]
        local duration = (info and info.duration) or Engine:BestDuration(name)
        -- The row's effective category (the Engine:Sorted / Timeline
        -- rowClass rule: entry category, then the per-spell fxClass
        -- override, then Spell).
        local category = (info and info.category)
            or (Engine.tracked[name] and Engine.tracked[name].fxClass)
            or "Spell"
        local texPath = (info and info.icon) or resolveReadyIcon(name)
        -- The Secondary Splash pops the ready icon big on its own window;
        -- nil-guarded, the frame arrives with UI/Splash.lua.
        local splash = FX.Cooldown.Splash
        if splash and splash.OnReady then
            splash:OnReady(name, now, texPath, duration, category)
        end
        -- The event bus (Forte_Core/Core/Events.lua): nil-guarded per the
        -- shared contract, every listener runs in the bus's pcall.
        if FX.Fire then
            FX.Fire("FX_COOLDOWN_READY", name, now, texPath, category)
        end
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
    -- The weapon-enchant change event -- verified in the pinned Forever
    -- catalog (ItemDocumentation.lua:1920, UniqueEvent, no payload) before
    -- registration; Core/Enchants.lua rides it.
    f:RegisterEvent("WEAPON_ENCHANT_CHANGED")
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
        elseif event == "WEAPON_ENCHANT_CHANGED" then
            -- A weapon slot's enchant list changed (poison applied, an
            -- enchant burned off): read the three weapon slots right now
            -- (Core/Enchants.lua). Payload-less UniqueEvent -- the read
            -- re-reads every slot, no book-keeping on the event.
            if Engine.Enchants then
                Engine.Enchants:ReadAll()
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
        M:ProcessReadyPops(now)
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
    -- Live weapon-enchant entries (Core/Enchants.lua): one per enchanted
    -- weapon slot with a readable timer.
    if Engine.Enchants then
        FX.Print(string.format("Enchants: %d", Engine.Enchants:Count()))
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

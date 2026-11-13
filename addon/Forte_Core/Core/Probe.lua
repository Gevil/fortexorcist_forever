-- Forte_Core/Core/Probe.lua
-- `/fx probe` -- the launch-day data collector (PLAN §11 Iteration B1).
--
-- One command runs every open live question from docs/research/secrets-unknowns.md
-- (questions 1-10 "Remaining live probe" snippets) and docs/design-combat-procs.md
-- §5 as *data-collecting functions*: each probe group runs inside its own
-- pcall and stores a small table of PLAIN facts, so one `/fx probe` out of
-- combat and one IN COMBAT (owner checklist: docs/launch-day.md) answer the
-- secrecy questions for the launch build. Runs persist in FX.db.probes (the
-- ## SavedVariables global ForteXorcistDB, Forte_Core.toc) -- bounded to the
-- last MAX_RUNS -- so the owner sends the SavedVariables file, not chat logs.
--
-- THE CLASSIFIER LAW (the whole file rides on it):
--   every value that leaves a Blizzard API passes Probe.K(v): "SECRET" when
--   issecretvalue(v) (FrameScriptDocumentation.lua:286), else type(v) + ":" +
--   a plain rendering. A secret value is therefore NEVER stored, compared,
--   concatenated or indexed -- K consumes it and emits a plain string. Runs
--   under a pcall so a raising API (the real secret-restriction behaviour,
--   docs/research/secrets-unknowns.md) leaves a recorded "raise=" string, not
--   a Lua error.
--
-- Event capture (questions 1, 5, 6): Probe's OnEnable creates ONE frame
-- (inside the PLAYER_LOGIN handler chain -- never a top-level RegisterEvent)
-- that passively records the last UNIT_SPELLCAST_SUCCEEDED / PLAYER_SWING
-- (_RANGE_UPDATE) / ADDON_RESTRICTION_STATE_CHANGED payloads, K-classified
-- at capture time, into bounded rings in FX.db.probesEvents.
--
-- Wave I-2 rows (2026-11-03, upstream-api Open questions 1/3, upstream-addons
-- ranked 4/5, dev-notes §2): SEC gains the widened gate set (per-spell aura,
-- unit identity, threat values, UnitThreat presence); NAME = the raw name
-- APIs (both returns) + the realm label; EVENTS = C_EventUtils.IsEventValid
-- over OUR_EVENTS (every event literal the addons register) + UNIT_THREAT;
-- SV = the SavedVariables stamp write/login-read pair; HS = healthstone
-- counts + item cooldowns (warlock data); PET = pet-bar action-cooldown
-- readability; ENCH = weapon-enchant records; BSW = Blizzard's own
-- swing-timer frames (the launch overlap question).
--
-- Slash surface (registered through FX.RegisterSlash, Core/Init.lua):
--   /fx probe [label]   run the battery; label defaults ooc / combat by
--                       InCombatLockdown()
--   /fx probe show      reprint the stored last run
--   /fx probe clear     empty the stored runs
--   /fx probe bar       StatusBar + Cooldown fed by a self-built
--                       C_DurationUtil duration (research Q7 / design §5.5):
--                       the owner watches whether it ticks in combat
--   /fx probe bar off   hide the bar frames

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist

local Probe = {}
FX.Probe = Probe

Probe.MAX_RUNS = 20   -- FX.db.probes bound (acceptance: runs bounded to 20)

-- ---------------------------------------------------------------- K law --

--- Classify one API value to a plain string. Reads _G.issecretvalue at call
--- time (the tests' sentinel seam patches that global). The issecretvalue
--- call runs FIRST and inside a pcall: comparing a secret raises (see
--- Compat.PlainOrNil's "Secret NIL is not public nil" note), and a
--- issecretvalue that itself raises is treated as "not detected secret"
--- (best-effort classification; the pcall boundary still protects storage).
function Probe.K(v)
    local iss = _G.issecretvalue
    if iss then
        local ok, secret = pcall(iss, v)
        if ok and secret then return "SECRET" end
    end
    local t = type(v)
    if t == "number" then return "number:" .. string.format("%.6g", v) end
    if t == "string" then return "string:" .. v end
    if t == "boolean" then return "boolean:" .. tostring(v) end
    if t == "nil" then return "nil" end
    return t -- table / function / userdata / thread: the type name only
end

local K = Probe.K

--- Print rendering: strip the type prefix of a K string (the STORED form
--- keeps it; the chat line stays compact like `st=SECRET dur=SECRET`).
local function compact(v)
    if type(v) ~= "string" then return tostring(v) end
    return (v:gsub("^number:", ""):gsub("^boolean:", ""):gsub("^string:", ""))
end

-- ------------------------------------------------------------- helpers --

local function inCombat()
    if type(_G.InCombatLockdown) ~= "function" then return false end
    local ok, v = pcall(_G.InCombatLockdown)
    local plain = ok and FX.Compat.PlainOrNil(v)
    return not not plain
end

local function stamp()
    if type(_G.date) ~= "function" then return "nodate" end
    local ok, s = pcall(_G.date, "!%Y-%m-%d %H:%M:%S")
    if ok and type(s) == "string" then return s end
    return "?"
end

--- { GetBuildInfo() } as plain scalars (build/touch/edition/toc + tail);
--- any non-plain value is dropped, never stored raw.
local function buildInfo()
    local out = {}
    if type(_G.GetBuildInfo) ~= "function" then return out end
    local ok, vals = pcall(function() return { GetBuildInfo() } end)
    if not ok then return out end
    for i, v in ipairs(vals) do
        local plain = FX.Compat.PlainOrNil(v)
        local t = type(plain)
        if (t == "number" or t == "string" or t == "boolean") and plain ~= "" then
            out[i] = plain
        end
    end
    return out
end

local function classKey()
    local c = FX._playerClass
    if type(c) ~= "string" or c == "" then return nil end
    return c:sub(1, 1) .. c:sub(2):lower() -- "HUNTER" -> "Hunter"
end

--- The persisted run list; a session-local table when SavedVariables never
--- arrived (matches Module:InitCastDiag's posture).
local function dbRuns()
    if FX.db then
        FX.db.probes = FX.db.probes or {}
        return FX.db.probes
    end
    Probe._runs = Probe._runs or {}
    return Probe._runs
end

--- Event-capture rings (plain K strings only).
local function events()
    if not FX.db then
        Probe._events = Probe._events
            or { casts = {}, swings = {}, restricts = {} }
        return Probe._events
    end
    FX.db.probesEvents = FX.db.probesEvents
        or { casts = {}, swings = {}, restricts = {} }
    return FX.db.probesEvents
end

local function push(ring, item, max)
    ring[#ring + 1] = item
    while #ring > max do table.remove(ring, 1) end
end

local function lastOf(ring)
    return ring and ring[#ring]
end

--- pcall + classify one call site. Returns the K string of the result, or
--- "raise:<err>" -- the recorded-error-string contract (no group dies from
--- one raising API; the group-level pcall in RunPlan is the outer net).
local function callK(fn, ...)
    if type(fn) ~= "function" then return "absent" end
    local ok, a = pcall(fn, ...)
    if not ok then return "raise:" .. tostring(a) end
    return K(a)
end

--- Resolve a tracked NAME to a current numeric spellID (C_Spell.GetSpellInfo
--- @SpellDocumentation.lua:517 neighbourhood; the resolved id, never the
--- build-sensitive data id, PLAN §8). nil when unresolvable.
local function resolvedSpellID(name)
    local CS = _G.C_Spell
    if not (CS and CS.GetSpellInfo) then return nil end
    local ok, info = pcall(CS.GetSpellInfo, name)
    local id = ok and info and FX.Compat.PlainOrNil(info.spellID)
    if type(id) == "number" then return id end
    return nil
end

--- SpellIdentifier call with the NAME law: the name first; when the name
--- call RAISES (the sim's C_Spell demands numbers -- "expected number, got
--- string") retry once with the resolved numeric id. Returns the last call's
--- (ok, value).
local function callSpellId(fn, name, resolvedID)
    if type(fn) ~= "function" then return false, "FXABSENT" end
    local ok, a = pcall(fn, name)
    if ok then return ok, a end
    if type(resolvedID) == "number" then
        local ok2, b = pcall(fn, resolvedID)
        return ok2, b
    end
    return ok, a
end

--- K string for a callSpellId result ("absent" / "raise:..." / K(value)).
local function kOfCall(ok, a, absent)
    if absent then return "absent" end
    if not ok then return "raise:" .. tostring(a) end
    return K(a)
end

-- ------------------------------------------------------- probe groups --
-- Every function returns a table whose values are all Probe.K outputs.

--- Research Q5: the cheap "is everything secret right now" mode surface,
--- widened by the I2c gate set (upstream-addons-2026-11-03.md §1: the shipped
--- set gates per-domain AND per-spell/per-unit) + the threat-surface
--- presence the §10.3 open question asks for. `firstSpell` (I2c) is a
--- tracked spell NAME for the per-spell gate -- planRuns passes the picked
--- spell so the row stays class-independent.
local function probeSecretState(firstSpell)
    local g = {}
    local CRA = _G.C_RestrictedActions
    if CRA and CRA.GetAddOnRestrictionState then
        for t = 0, 5 do -- AddOnRestrictionType Combat..Chat
            g["st" .. t] = callK(CRA.GetAddOnRestrictionState, t)
            g["act" .. t] = callK(CRA.IsAddOnRestrictionActive, t)
        end
    else
        g.cra = "absent"
    end
    local CS = _G.C_Secrets
    if CS then
        g.abs = callK(CS.ShouldAurasBeSecret)
        g.cbs = callK(CS.ShouldCooldownsBeSecret)
        g.hsr = callK(CS.HasSecretRestrictions)
        g.castP = callK(CS.ShouldUnitSpellCastingBeSecret, "player")
        g.sabs = firstSpell and callK(CS.ShouldSpellAuraBeSecret, firstSpell)
            or "no-spell"
        g.uibsP = callK(CS.ShouldUnitIdentityBeSecret, "player")
        g.uibsT = callK(CS.ShouldUnitIdentityBeSecret, "target")
        g.utbs = callK(CS.ShouldUnitThreatValuesBeSecret, "player", "target")
    else
        g.cSec = "absent"
    end
    g.threatFn = K(_G.UnitThreat)
    -- Event capture: has ADDON_RESTRICTION_STATE_CHANGED (the design's mode
    -- switch trigger, research Q5) been seen at all this session?
    local ev = events()
    g.rsSeen = K(ev.restricts and #ev.restricts)
    local last = lastOf(ev.restricts)
    if last then
        g.rsType = last.type
        g.rsState = last.state
    end
    return g
end

--- Q2: the spell-cooldown tier for one tracked spell (by NAME; the data
--- IDs are build-sensitive, PLAN §8; the numeric id is resolved live and
--- only used where the name call raises).
local function probeSpell(name)
    local g = {}
    local rid = resolvedSpellID(name)
    local CS = _G.C_Spell
    if CS and CS.GetSpellCooldown then -- SpellDocumentation.lua:308
        local has = type(CS.GetSpellCooldown) == "function"
        local ok, ci = callSpellId(CS.GetSpellCooldown, name, rid)
        g.cd = kOfCall(ok, ci, not has)
        if has and ok and ci ~= nil then
            g.en = K(ci.isEnabled) g.act = K(ci.isActive) g.gcd = K(ci.isOnGCD)
            g.st = K(ci.startTime) g.dur = K(ci.duration) g.rate = K(ci.modRate)
        end
    else g.cd = "absent" end
    if CS and CS.GetSpellCharges then -- SpellDocumentation.lua:290
        local has = type(CS.GetSpellCharges) == "function"
        local ok, ch = callSpellId(CS.GetSpellCharges, name, rid)
        g.chg = kOfCall(ok, ch, not has)
        if has and ok and ch ~= nil then
            g.mx = K(ch.maxCharges) g.chAct = K(ch.isActive) g.cur = K(ch.currentCharges)
            g.cst = K(ch.cooldownStartTime) g.cdur = K(ch.cooldownDuration)
        end
    else g.chg = "absent" end
    -- C_Spell.GetSpellCooldownDuration(id, true) -> LuaDurationObject
    -- (SpellDocumentation.lua:326); the widgets' gate idiom is
    -- HasSecretValues() (LuaDurationObjectAPIDocumentation.lua:350) +
    -- GetRemainingDuration(:270, arg DurationTimeModifier).
    if CS and CS.GetSpellCooldownDuration then
        local has = type(CS.GetSpellCooldownDuration) == "function"
        local ok, d = callSpellId(
            function(sid) return CS.GetSpellCooldownDuration(sid, true) end, name, rid)
        g.durObj = kOfCall(ok, d, not has)
        if has and ok and d ~= nil then
            g.secret = callK(d.HasSecretValues, d)
            local modifier = (_G.Enum and _G.Enum.DurationTimeModifier
                and _G.Enum.DurationTimeModifier.RealTime) or 0
            g.rem = callK(d.GetRemainingDuration, d, modifier)
        end
    else g.durObj = "absent" end
    local CSr = _G.C_Secrets
    if CSr then -- per-spell classifiers (SecretPredicateAPIDocumentation.lua:76 / :60)
        g.cdSec = CSr.GetSpellCooldownSecrecy
            and kOfCall(callSpellId(CSr.GetSpellCooldownSecrecy, name, rid)) or "absent"
        g.castSec = CSr.GetSpellCastSecrecy
            and kOfCall(callSpellId(CSr.GetSpellCastSecrecy, name, rid)) or "absent"
    end
    g.rid = K(rid)
    return g
end

--- Q3: the item-cooldown tier for one slot / bag item. The Get*Inventory*
--- legacy globals are binary-present, catalog-absent (Compat.lua header);
--- every call site is guarded and pcall'd.
local function probeItem(it)
    local g = {}
    g.id = "absent"
    local id = it.itemID
    if not id and it.slot and type(_G.GetInventoryItemID) == "function" then
        local ok, v = pcall(_G.GetInventoryItemID, "player", it.slot)
        id = ok and FX.Compat.PlainOrNil(v)
    end
    g.id = K(id)
    if it.slot and type(_G.GetInventoryItemCooldown) == "function" then
        local ok, s, d, e = pcall(_G.GetInventoryItemCooldown, "player", it.slot)
        if not ok then g.inv = "raise:" .. tostring(s)
        else g.invSt, g.invDur, g.invEn = K(s), K(d), K(e) end
    else g.inv = "absent" end
    if id ~= nil then
        local CC = _G.C_Container
        if CC and CC.GetItemCooldown then -- ContainerDocumentation.lua:336
            local ok, s, d, e = pcall(CC.GetItemCooldown, id)
            if not ok then g.cc = "raise:" .. tostring(s)
            else g.ccSt, g.ccDur, g.ccEn = K(s), K(d), K(e) end
        else g.cc = "absent" end
        local CI = _G.C_Item
        if CI and CI.GetItemCooldown then -- ItemDocumentation.lua:433
            local ok, s, d, e = pcall(CI.GetItemCooldown, id)
            if not ok then g.ci = "raise:" .. tostring(s)
            else g.ciSt, g.ciDur, g.ciEn = K(s), K(d), K(e) end
        else g.ci = "absent" end
        if CI and CI.GetItemSpell then -- ItemDocumentation.lua:969
            local ok, sp, spid = pcall(CI.GetItemSpell, id)
            if not ok then g.sp = "raise:" .. tostring(sp)
            else g.sp, g.spId = K(sp), K(spid) end
        else g.sp = "absent" end
    end
    return g
end

--- Q4: aura secrecy + the in-combat readability of one self-buff NAME.
local function probeAura(name)
    local g = {}
    local CS = _G.C_Secrets
    g.sec = callK(CS and CS.GetSpellAuraSecrecy, name) -- SecretPredicateAPIDocumentation.lua:44
    local CUA = _G.C_UnitAuras
    if CUA and CUA.GetAuraDataBySpellName then -- UnitAuraDocumentation.lua:244
        local ok, a = pcall(CUA.GetAuraDataBySpellName, "player", name, "HELPFUL")
        if not ok then
            g.auraRaise = K(a)
        elseif a == nil then
            g.aura = "nil"
        else
            g.aura = "table"
            g.n = K(a.name) g.a = K(a.applications)
            g.d = K(a.duration) g.exp = K(a.expirationTime)
        end
    else g.aura = "absent" end
    return g
end

--- Q1: the cast-counter snapshot (Forte_Cooldown's counters, owned by us --
--- plain numbers) plus the last captured cast payload.
local function probeCastCounters()
    local g = {}
    local d = FX.db and FX.db.diag and FX.db.diag.casts
    if d then
        g.seen = K(d.seen) g.plain = K(d.plainId) g.secret = K(d.secretId)
        g.unres = K(d.unresolved)
        g.inSeen = K(d.inSeen) g.inPlain = K(d.inPlain) g.inSecret = K(d.inSecret)
    else
        g.counters = "absent" -- Forte_Cooldown not loaded this session
    end
    local cast = lastOf(events().casts)
    g.cap = K(cast and #events().casts)
    if cast then
        g.cUnit, g.cGuid, g.cId, g.cBar = cast.a, cast.b, cast.c, cast.d
        g.cCombat = K(cast.combat)
    end
    return g
end

--- Q6: the swing surface + the last captured PLAYER_SWING payload.
local function probeSwing()
    local g = {
        pst = K(_G.Enum and _G.Enum.PlayerSwingType),   -- SwingTimerDocumentation.lua:70
        swt = K(_G.Enum and _G.Enum.SwingType),        -- NOT declared; presence only -- api-lint: ok presence probe
        stTimer = K(_G.C_SwingTimer
            and _G.C_SwingTimer.IsTargetWithinSwingRange),
    }
    local sw = lastOf(events().swings)
    g.cap = K(sw and #events().swings)
    if sw then g.sA, g.sB, g.sC = sw.a, sw.b, sw.c end
    return g
end

--- Q8: the gate-container load, OUT OF COMBAT ONLY (the "a container can
--- only be set up outside a fight" practice, research Q8). No frame is
--- created (the sim hard-exits on CustomAuraContainerTemplate frames; the
--- launch client does the visual half by hand -- docs/launch-day.md).
local function probeGate()
    if inCombat() then return { load = "skipped-combat" } end
    local CA = _G.C_AddOns
    if not (CA and CA.LoadAddOn) then return { load = "absent" } end
    if CA.IsAddOnLoaded then -- AddOnsDocumentation.lua:321
        local ok, ld = pcall(CA.IsAddOnLoaded, "Blizzard_AuraContainer")
        if ok and ld then return { loaded = K(ld) } end
    end
    local ok, a, b = pcall(CA.LoadAddOn, "Blizzard_AuraContainer") -- :346
    return { ok = K(ok), loaded = K(a), value = K(b) }
end

--- Surface-presence census (Q6/Q9/§9 + the Compat chains): type of each
--- global, K-classified (function/table/nil/...).
local function probePresence()
    return {
        createDuration = K(_G.C_DurationUtil and _G.C_DurationUtil.CreateDuration),
        addAuraSound = K(_G.C_UnitAuras and _G.C_UnitAuras.AddAuraSound),
        loadAddOn = K(_G.C_AddOns and _G.C_AddOns.LoadAddOn),
        isPlayerSpell = K(_G.IsPlayerSpell),
        knownInSpellBook = K(_G.C_SpellBook
            and _G.C_SpellBook.IsSpellKnownOrInSpellBook),
        getInvItemID = K(_G.GetInventoryItemID),
        getInvItemCD = K(_G.GetInventoryItemCooldown),
        slashCmdList = K(_G.SlashCmdList),
        uiSpecialFrames = K(_G.UISpecialFrames),
        playerSwingType = K(_G.Enum and _G.Enum.PlayerSwingType),
        swingType = K(_G.Enum and _G.Enum.SwingType), -- api-lint: ok presence probe of an undeclared name
    }
end

--- Q10: the SavedVariables persistence proof. probeEpoch is bumped by
--- OnEnable -- run by the Forte_Core bootstrap frame's PLAYER_LOGIN handler
--- (Core/Init.lua), i.e. exactly once per login: a full relog that shows the
--- epoch +1 in the stored file proves ForteXorcistDB round-trips; a /reload
--- must NOT bump it.
local function probeEpoch()
    local runs = dbRuns()
    local last = runs[#runs]
    return {
        epoch = K(FX.db and FX.db.probeEpoch or Probe._epoch),
        saved = K(FX.db ~= nil),
        runs = K(#runs),
        lastLbl = K(last and last.label),
    }
end

-- ------------------------------------------- I2c rows (wave I-2, 2026-11-03) --
-- The rows the launch-day guide adds for docs/research/upstream-api-2026-11-03.md
-- "Open questions" 1/3, upstream-addons-2026-11-03.md ranked 4 + 5 (§1, §2, §5)
-- and forever-dev-notes-2026-11-03.md §2 (Blizzard's own swing timers; the
-- Cooldown Manager "cannot track" healthstone cooldowns, pet cooldowns, item
-- enhancements -- the hints at what the client exposes). Every row is read-only
-- against the client (the SV row writes OUR own SavedVariables key, by design)
-- and rides the file's K law: every value passes K before it is stored.

--- Call `fn(...)` and K BOTH returns (the raw name APIs answer
--- (name, server)). Returns two K strings; "absent" / "raise:..." as usual.
local function call2K(fn, ...)
    if type(fn) ~= "function" then return "absent", "absent" end
    local ok, a, b = pcall(fn, ...)
    if not ok then return "raise:" .. tostring(a), "raise:" end
    return K(a), K(b)
end

--- NAME: the raw identity reads, both returns, for "player", plus the
--- connection realm label (upstream-api Open questions 1; the identity
--- finding: "a character is its first and last name, not Name-Realm", and
--- GetRealmName is the connection label, not identity). The three globals
--- carry SecretWhenUnit[Name]IdentityRestricted in the pinned catalog
--- (@UnitDocumentation.lua:2488/:1223/:2522) -- a SECRET entry in the combat
--- run is the answer Open-question 3 asks for.
local function probeRawNames()
    local g = {}
    g.n1, g.n2 = call2K(_G.UnitName, "player")
    g.f1, g.f2 = call2K(_G.UnitFullName, "player")
    g.u1, g.u2 = call2K(_G.UnitNameUnmodified, "player")
    g.realm = callK(_G.GetRealmName)
    return g
end

--- Every event literal our addons RegisterEvent/RegisterUnitEvent (static
--- scan of addon/**, 2026-11-03; api_lint.py checks the literals themselves
--- against the pinned catalog, this row asks the CLIENT, the shipped
--- capability probe -- upstream-addons-2026-11-03.md §2: C_EventUtils.
--- IsEventValid(event) @EventUtilsDocumentation.lua:25). MAINTENANCE LAW: a
--- new registration in any Forte_* module lands here too -- an event the
--- launch client does not know RAISES at RegisterEvent and kills that
--- module's event frame.
local OUR_EVENTS = {
    "ADDON_LOADED",
    "ADDON_RESTRICTION_STATE_CHANGED",
    "BAG_UPDATE_COOLDOWN",
    "BAG_UPDATE_DELAYED",
    "CHAT_MSG_ADDON",
    "GET_ITEM_INFO_RECEIVED",
    "GROUP_FORMED",
    "GROUP_JOINED",
    "GROUP_LEFT",
    "GROUP_ROSTER_UPDATE",
    "ITEM_COUNT_CHANGED",
    "ITEM_DATA_LOAD_RESULT",
    "PLAYER_DEAD",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_EQUIPMENT_CHANGED",
    "PLAYER_LEAVING_WORLD",
    "PLAYER_LOGIN",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "PLAYER_STARTED_MOVING",
    "PLAYER_STOPPED_MOVING",
    "PLAYER_SWING",
    "PLAYER_SWING_RANGE_UPDATE",
    "PLAYER_TARGET_CHANGED",
    "PLAYER_TOTEM_UPDATE",
    "SPELLS_CHANGED",
    "SPELL_UPDATE_COOLDOWN",
    "START_AUTOREPEAT_SPELL",
    "STOP_AUTOREPEAT_SPELL",
    "UNIT_AURA",
    "UNIT_DIED",
    "UNIT_POWER_UPDATE",
    "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_FAILED_QUIET",
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_SENT",
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_SUCCEEDED",
    "WEAPON_ENCHANT_CHANGED",
}

--- EVENTS: ask the client about every event we register (dynamic half; the
--- static half is api_lint.py). `ok` == n and `bad` == "-" is the green
--- launch-day answer; a name in `bad`/`raise` names an event whose
--- registration raises on this build. The list is OUR literals -- echoing a
--- name back as text is plain by construction, no API value is concatenated.
local function probeEventValidity()
    local g = { n = K(#OUR_EVENTS) }
    local CEU = _G.C_EventUtils
    if not (CEU and CEU.IsEventValid) then
        g.iev = "absent"
        return g
    end
    local okCount, bad, raised = 0, {}, {}
    for _, name in ipairs(OUR_EVENTS) do
        local ok, valid = pcall(CEU.IsEventValid, name)
        if not ok then
            raised[#raised + 1] = name
        elseif K(valid) == "boolean:true" then
            okCount = okCount + 1
        else
            bad[#bad + 1] = name
        end
    end
    g.ok = K(okCount)
    g.bad = (#bad == 0) and "-" or table.concat(bad, ",")
    g.raise = (#raised == 0) and "-" or table.concat(raised, ",")
    -- The threat-surface probe of upstream-addons-2026-11-03 §1/§10.3: the
    -- shipped ShouldUnitThreatValuesBeSecret predicate contradicts a pure
    -- "no threat API" reading. The classic UNIT_THREAT is NOT in the pinned
    -- catalog (only the two *_UPDATE events below are), so `ievThreat=false`
    -- is the catalog-expected answer -- the pair says which event shape the
    -- 70707 client carries.
    for key, ev in ipairs({
        "UNIT_THREAT", -- api-lint: ok deliberate probe of the catalog-absent classic name (the answer IS the datum)
        "UNIT_THREAT_LIST_UPDATE",        -- @UnitDocumentation.lua:4888
        "UNIT_THREAT_SITUATION_UPDATE",   -- @UnitDocumentation.lua:4899
    }) do
        local tok, tvalid = pcall(CEU.IsEventValid, ev)
        g["ievT" .. key] = tok and K(tvalid) or "raise:" .. tostring(tvalid)
    end
    return g
end

--- SV: the SavedVariables round-trip MARKER (upstream-addons §5 open
--- question 1: does the 70707 restore work, SVFix's claim is from
--- 2026-09-25). Every run writes a fresh stamp into ForteXorcistDB;
--- Probe:OnEnable latches whatever the store held at login (before any
--- write) into Probe._svLogin. `login=` equalling the PREVIOUS run's
--- `wrote=` -- across a /reload, and again across a full relog -- is the
--- value-level proof the epoch counter only implies.
local function svStamp()
    local t = 0
    if type(_G.GetTime) == "function" then
        local ok, v = pcall(_G.GetTime)
        t = (ok and FX.Compat.PlainOrNil(v)) or 0
    end
    return "FXS@" .. (stamp()):gsub(" ", "T") .. "/" .. string.format("%.4f", t)
end

local function probeSavedVars()
    local wrote = svStamp()
    local before
    if FX.db then
        before = FX.db.probeStamp
        FX.db.probeStamp = wrote
    else
        -- Session-local mirror (matches dbRuns' no-store posture).
        before = Probe._lastStamp
        Probe._lastStamp = wrote
    end
    return {
        login = K(Probe._svLogin),
        db = K(before),
        wrote = K(wrote),
        saved = K(FX.db ~= nil),
    }
end

--- HS: healthstone presence + the stones' ITEM cooldowns (dev-notes §2:
--- Blizzard's Cooldown Manager "cannot track" the healthstone cooldown --
--- the hint of what the client exposes). The stone rows ride the generated
--- Forte_Warlock data (ids are generated, never hand-typed), so the row
--- answers on a warlock session and says `no-warlock-data` elsewhere (the
--- class-independent law of planRuns). Bag items read by itemID --
--- Forte_Cooldown/Core/Items.lua's split; the count asks the CLIENT's name
--- through FX.L, Forte_Warlock/Core/Tools.lua's law.
local function healthstoneRows()
    local out = {}
    local data = FX.Data and FX.Data.Warlock
    if type(data) ~= "table" then return out end
    for _, row in pairs(data) do
        if type(row) == "table" and type(row.name) == "string"
            and type(row.id) == "number"
            and row.name:find("Healthstone$")
            and not row.name:find("^Create ") then
            out[#out + 1] = row
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

local function probeHealthstones()
    local rows = healthstoneRows()
    if #rows == 0 then return { hs = "no-warlock-data" } end
    local g = { hs = K(#rows) }
    for _, row in ipairs(rows) do
        local key = tostring(row.id)
        local CI = _G.C_Item
        if CI and CI.GetItemCount then
            local ok, n = pcall(CI.GetItemCount, FX.L(row.name))
            g["cnt" .. key] = ok and K(n) or "raise:" .. tostring(n)
        else g["cnt" .. key] = "absent" end
        local read = FX.Compat and FX.Compat.GetItemCooldownInfo
        if read then
            local ok, st, du, en = pcall(read, row.id)
            if not ok then
                g["cd" .. key] = "raise:" .. tostring(st)
            else
                g["cd" .. key] = K(st) .. "/" .. K(du) .. "/" .. K(en)
            end
        else g["cd" .. key] = "absent" end
    end
    return g
end

--- PET: a pet spell-cooldown read on the action-bar surface (dev-notes §2:
--- the Cooldown Manager "cannot track" pet cooldowns). pet bar 1, its first
--- slot, resolved through the catalog-declared C_ActionBar pet lookups
--- (@ActionBarFrameDocumentation.lua:386/:466/:433/:163 -- GetActionCooldown
--- carries SecretWhenCooldownsRestricted, the in-combat leg of the answer).
--- No action id is hand-typed: the first entry of GetPetActionPetBarIndices
--- IS pet bar 1 slot 1.
local PET_ACTION_BAR = 1

local function probePet()
    local g = {}
    if type(_G.UnitExists) == "function" then
        local ok, ex = pcall(_G.UnitExists, "pet")
        local plain = ok and FX.Compat.PlainOrNil(ex)
        g.pet = K(plain)
        if plain ~= true then return g end
    else g.pet = "absent" end
    local CAB = _G.C_ActionBar
    if not (CAB and CAB.GetPetActionPetBarIndices) then
        g.slots = "absent"
        return g
    end
    local okS, slots = pcall(CAB.GetPetActionPetBarIndices, PET_ACTION_BAR)
    if not okS then
        g.slots = "raise:" .. tostring(slots)
        return g
    end
    if slots == nil then g.slots = "nil" return g end
    g.slots = K(#slots)
    local first
    for _, slot in ipairs(slots) do
        local plain = FX.Compat.PlainOrNil(slot)
        if type(plain) == "number" and (first == nil or plain < first) then
            first = plain
        end
    end
    g.slot = K(first)
    if type(first) ~= "number" then return g end
    if CAB.HasAction then
        local ok, v = pcall(CAB.HasAction, first)
        g.has = ok and K(v) or "raise:" .. tostring(v)
    else g.has = "absent" end
    if CAB.GetSpell then
        local ok, id = pcall(CAB.GetSpell, first)
        g.spell = ok and K(id) or "raise:" .. tostring(id)
    else g.spell = "absent" end
    if CAB.GetActionCooldown then
        local ok, ci = pcall(CAB.GetActionCooldown, first)
        if not ok then
            g.cd = "raise:" .. tostring(ci)
        elseif ci == nil then
            g.cd = "nil"
        else
            g.cd = "table"
            g.en = K(ci.isEnabled) g.st = K(ci.startTime)
            g.dur = K(ci.duration) g.rate = K(ci.modRate)
        end
    else g.cd = "absent" end
    return g
end

--- ENCH: weapon-enchant records, Enum.WeaponSlot 0/1/2 (the pinned
--- enumeration { MainHand=0, OffHand=1, Ranged=2 }) -- readable out of
--- combat, the pair run decides in combat (dev-notes §2: the Cooldown
--- Manager "cannot track" item enhancements like Windfury/poisons).
--- Compat.GetWeaponEnchantInfo carries the catalog law: timeLeft is
--- MILLISECONDS, no SecretWhen annotation at the pin.
local WEAPON_SLOTS = {
    { key = "mh", slot = 0 },   -- Enum.WeaponSlot.MainHand
    { key = "oh", slot = 1 },   -- Enum.WeaponSlot.OffHand
    { key = "rng", slot = 2 },  -- Enum.WeaponSlot.Ranged
}

local function probeEnchants()
    local read = FX.Compat and FX.Compat.GetWeaponEnchantInfo
    if not read then return { en = "absent" } end
    local g = {}
    for _, ws in ipairs(WEAPON_SLOTS) do
        local ok, arr = pcall(read, ws.slot)
        if not ok then
            g[ws.key] = "raise:" .. tostring(arr)
        elseif arr == nil then
            g[ws.key] = "nil"
        else
            g[ws.key] = "n" .. tostring(#arr)
            local rec = arr[1]
            if type(rec) == "table" then
                g[ws.key .. "e"] = K(rec.hasEnchant)
                g[ws.key .. "t"] = K(rec.timeLeft)
                g[ws.key .. "i"] = K(rec.enchantID)
                g[ws.key .. "c"] = K(rec.charges)
            end
        end
    end
    return g
end

--- BSW: Blizzard's OWN swing-timer frames (dev-notes §2: "the Off-Hand
--- Swing Timer" is Blizzard UI -- Blizzard_SwingTimer.xml ships
--- SwingTimerManagerFrame + MainHand/OffHand/Ranged frames, gated on the
--- showSwingTimer CVar). The launch-day overlap question for the Hunter bar
--- starts with: are they live on the client at all. Frame globals exist
--- only when the add-on loaded -> "absent" is itself the answer.
local function framePresence(name)
    local f = _G[name]
    if f == nil then return "absent" end
    if type(f.IsShown) == "function" then
        local ok, v = pcall(f.IsShown, f)
        if not ok then return "raise:" .. tostring(v) end
        local plain = FX.Compat.PlainOrNil(v)
        if plain == nil then return "SECRET" end
        return plain and "shown" or "hidden"
    end
    return K(f)
end

local function probeBlizzardSwing()
    return {
        mgr = framePresence("SwingTimerManagerFrame"),
        mh = framePresence("SwingTimerMainHandFrame"),
        oh = framePresence("SwingTimerOffHandFrame"),
        rng = framePresence("SwingTimerRangedFrame"),
    }
end

-- ------------------------------------------------------- run planning --

local function sortedNames(t)
    local out = {}
    for name in pairs(t) do out[#out + 1] = name end
    table.sort(out)
    return out
end

--- Up to 3 tracked spells of the player's class: Engine.tracked first, the
--- generated class data as the fallback (the gate's class-independent law:
--- never hard-wire one class).
local function pickSpells()
    local Engine = FX.Cooldown and FX.Cooldown.Engine
    if Engine and next(Engine.tracked) then
        local all = sortedNames(Engine.tracked)
        local out = {}
        for i = 1, math.min(3, #all) do out[i] = all[i] end
        return out
    end
    local key = classKey()
    local data = key and FX.Data and FX.Data[key]
    local pool = {}
    if data then
        for _, spell in pairs(data) do
            if type(spell) == "table" and type(spell.name) == "string"
                and type(spell.cooldownMs) == "number"
                and spell.cooldownMs >= 30000 then
                pool[spell.name] = true
            end
        end
    end
    local all = sortedNames(pool)
    local out = {}
    for i = 1, math.min(3, #all) do out[i] = all[i] end
    return out
end

--- The class's self-buff names for the aura tier: the data's
--- "^Aspect of" family (Hunter first), else the first 2 picked spells.
local function pickAuras()
    local key = classKey()
    local data = key and FX.Data and FX.Data[key]
    local pool = {}
    if data then
        for _, spell in pairs(data) do
            if type(spell) == "table" and type(spell.name) == "string"
                and spell.name:find("^Aspect of") then
                pool[spell.name] = true
            end
        end
    end
    local out = sortedNames(pool)
    if #out == 0 then
        local sp = pickSpells()
        for i = 1, math.min(2, #sp) do out[i] = sp[i] end
    end
    return out
end

local function findBagPotion()
    local items = FX.Data and FX.Data.Items
    local rows = items and items.consumables
    if type(rows) ~= "table" then return nil end
    local wanted = {}
    for _, row in ipairs(rows) do
        if type(row) == "table" and type(row.name) == "string" then
            wanted[row.name] = true
        end
    end
    local CC = _G.C_Container
    if not (CC and CC.GetContainerNumSlots and CC.GetContainerItemID) then return nil end
    local okN, n = pcall(CC.GetContainerNumSlots, 0) -- backpack
    local slots = okN and FX.Compat.PlainOrNil(n)
    if type(slots) ~= "number" then return nil end
    for slot = 1, slots do
        local okI, id = pcall(CC.GetContainerItemID, 0, slot)
        id = okI and FX.Compat.PlainOrNil(id)
        if type(id) == "number" and id > 0 then
            local okT, name = pcall(FX.Compat.GetItemInfoName, id)
            if okT and type(name) == "string" and wanted[name] then
                return { name = name, itemID = id }
            end
        end
    end
    return nil
end

local function planRuns()
    local picks = pickSpells()
    local plan = {
        { label = "SEC", fn = function() return probeSecretState(picks[1]) end },
        { label = "NAME", fn = probeRawNames },
    }
    for _, name in ipairs(picks) do
        plan[#plan + 1] = { label = "CD " .. name, fn = function() return probeSpell(name) end }
    end
    local items = {
        { label = "trinket13", slot = 13 },
        { label = "trinket14", slot = 14 },
    }
    local pot = findBagPotion()
    if pot then items[#items + 1] = { label = "pot " .. pot.name, itemID = pot.itemID } end
    for _, it in ipairs(items) do
        plan[#plan + 1] = { label = "ITEM " .. it.label, fn = function() return probeItem(it) end }
    end
    for _, name in ipairs(pickAuras()) do
        plan[#plan + 1] = { label = "AURA " .. name, fn = function() return probeAura(name) end }
    end
    plan[#plan + 1] = { label = "CAST", fn = probeCastCounters }
    plan[#plan + 1] = { label = "SWING", fn = probeSwing }
    plan[#plan + 1] = { label = "BSW", fn = probeBlizzardSwing }
    plan[#plan + 1] = { label = "GATE", fn = probeGate }
    plan[#plan + 1] = { label = "PRES", fn = probePresence }
    plan[#plan + 1] = { label = "EVENTS", fn = probeEventValidity }
    plan[#plan + 1] = { label = "EPOCH", fn = probeEpoch }
    plan[#plan + 1] = { label = "SV", fn = probeSavedVars }
    plan[#plan + 1] = { label = "HS", fn = probeHealthstones }
    plan[#plan + 1] = { label = "PET", fn = probePet }
    plan[#plan + 1] = { label = "ENCH", fn = probeEnchants }
    return plan
end

-- ------------------------------------------------------- run/store/print --

--- The ONE renderer of a run: the lines chat prints, in print order. The
--- copy window below shows the SAME list, so the text the owner pastes back
--- is byte-for-byte what the chat showed (the launch-day guide reads the
--- chat lines; the paste is the artefact).
local function runLines(run)
    local lines = {}
    local build = {}
    for _, v in ipairs(run.build) do build[#build + 1] = tostring(v) end
    lines[#lines + 1] = string.format("PROBE %s epoch=%s build=[%s] date=%s",
        tostring(run.label), tostring(run.epoch), table.concat(build, "/"),
        tostring(run.date))
    for _, e in ipairs(run.results) do
        local parts = {}
        if e.raise then
            parts[1] = "raise=" .. compact(e.raise)
        else
            for k, v in pairs(e.values) do
                parts[#parts + 1] = k .. "=" .. compact(v)
            end
            table.sort(parts)
        end
        lines[#lines + 1] = e.group .. ": " .. table.concat(parts, " ")
    end
    return lines
end

local function printRun(run)
    for _, line in ipairs(runLines(run)) do
        FX.Print(line)
    end
end

-- ------------------------------------------------------------- copy window --
-- `/fx probe` prints (that is the launch-day reading surface) AND puts the
-- same lines into a copyable multi-line EditBox window, so the owner can
-- Ctrl-C the whole run into a paste instead of transcribing chat lines.
--
-- The window is built ON DEMAND, from the slash path only -- never at load
-- (AGENTS.md: frames only in OnEnable/handlers; `Probe:Bar` is this file's
-- existing precedent). Every widget call is pcall'd and method-guarded: a
-- surface that lacks multi-line EditBoxes costs the paste, not the run, and
-- nothing about the printed/stored run changes.
--
-- Copy mechanics, all surface-proven (docs/api widget refs, SCRIPT-HANDLERS.md):
--   * `SetMultiLine(true)` + MaxLetters/MaxBytes 0 (unlimited) -- a run is
--     many KB, and a positive MaxLetters truncates programmatic SetText;
--   * `OnEditFocusGained` -> `HighlightText(0, -1)` = select-all, so the
--     first click/Tab into the box selects the run and Ctrl-C copies it;
--   * a close Button, and ESC through the UISpecialFrames contract
--     (UIParentPanelManager.CloseSpecialWindows hides every shown entry --
--     the same law Forte_Options' window uses) plus the EditBox's own
--     OnEscapePressed, because a focused EditBox eats the key first.

Probe.WINDOW = {
    NAME = "ForteXorcistProbeRunBox",   -- global frame name (UISpecialFrames)
    W = 660, H = 420,
    TITLE_H = 24, PAD = 10, CLOSE_W = 22,
}

--- The run's window, built on demand; nil when the surface gives no frames
--- (the run is printed and stored either way).
function Probe:Window()
    if self._win then return self._win end
    if type(_G.CreateFrame) ~= "function" then return nil end
    local W = Probe.WINDOW
    local okF, f = pcall(_G.CreateFrame, "Frame", W.NAME, _G.UIParent)
    if not okF or not f then return nil end
    pcall(f.SetSize, f, W.W, W.H)
    pcall(f.SetPoint, f, "CENTER")
    pcall(f.SetToplevel, f, true)
    pcall(f.SetClampedToScreen, f, true)

    -- Real-client EditBoxes raise "Font not set" on SetText without a font
    -- (swallowed by the pcalls below => no text, no window). Give the frame
    -- an opaque background so it is visible regardless of text state.
    local okBg, bg = pcall(f.CreateTexture, f, nil, "BACKGROUND")
    if okBg and bg then
        pcall(bg.SetAllPoints, bg, f)
        pcall(bg.SetColorTexture, bg, 0.05, 0.05, 0.08, 0.95)
    end
    pcall(f.SetFrameStrata, f, "DIALOG")
    local title
    local okT, t = pcall(f.CreateFontString, f, nil, "OVERLAY",
        "GameFontHighlightSmall")
    if okT and t then
        title = t
        pcall(title.SetPoint, title, "TOPLEFT", f, "TOPLEFT", W.PAD, -3)
        pcall(title.SetText, title,
            "ForteXorcist probe run -- click in the text (selects all), Ctrl-C copies")
        pcall(title.SetTextColor, title, 1, 0.82, 0, 1)
    end

    local okE, eb = pcall(_G.CreateFrame, "EditBox", W.NAME .. "Edit", f)
    if not okE or not eb then
        pcall(f.Hide, f)
        return nil
    end
    pcall(eb.SetPoint, eb, "TOPLEFT", f, "TOPLEFT", W.PAD, -(W.TITLE_H + W.PAD))
    pcall(eb.SetPoint, eb, "BOTTOMRIGHT", f, "BOTTOMRIGHT", -W.PAD, W.PAD)
    pcall(eb.SetMultiLine, eb, true)
    pcall(eb.SetMaxLetters, eb, 0)     -- 0 = unlimited (the run is many KB)
    pcall(eb.SetMaxBytes, eb, 0)
    pcall(eb.SetWordWrap, eb, true)
    pcall(eb.SetJustifyH, eb, "LEFT")
    pcall(eb.SetJustifyV, eb, "TOP")
    pcall(eb.SetSpacing, eb, 2)
    pcall(eb.SetTextColor, eb, 0.92, 0.93, 0.96, 1)
    pcall(eb.SetHighlightColor, eb, 0.30, 0.52, 0.85, 0.55)
    pcall(eb.Enable, eb, true)
    pcall(eb.SetFontObject, eb, _G.ChatFontNormal or _G.GameFontHighlight)
    -- The shipped identity font (PLAN §11.12 font law): kept unless SetFont
    -- RAISES; the chat font object set above is the fallback.
    FX.Compat.ApplyFont(eb, FX.CLASSIC_FONT, 11, nil,
        _G.ChatFontNormal and "ChatFontNormal" or "GameFontHighlight")
    pcall(eb.SetScript, eb, "OnEditFocusGained", function(box)
        pcall(box.HighlightText, box, 0, -1)   -- select-all on focus
    end)
    pcall(eb.SetScript, eb, "OnEscapePressed", function()
        Probe:CloseWindow()
        return true
    end)

    local close
    local okC, c = pcall(_G.CreateFrame, "Button", W.NAME .. "Close", f)
    if okC and c then
        close = c
        pcall(close.SetSize, close, W.CLOSE_W, W.CLOSE_W)
        pcall(close.SetPoint, close, "TOPRIGHT", f, "TOPRIGHT", -2, -2)
        pcall(close.SetText, close, "X")
        pcall(close.SetScript, close, "OnClick", function()
            Probe:CloseWindow()
        end)
    end

    self._win = { frame = f, eb = eb, title = title, close = close,
                  text = nil }
    return self._win
end

--- Hide the window (close button / ESC path). Idempotent.
function Probe:CloseWindow()
    local w = self._win
    if not w then return end
    if w.eb and w.eb.HasFocus and w.eb:HasFocus()
        and w.eb.ClearFocus then
        pcall(w.eb.ClearFocus, w.eb)
    end
    pcall(w.frame.Hide, w.frame)
end

--- Print the run AND show it copyably. The window half is pcall'd: a widget
--- surface that refuses to build never costs the run.
local function presentRun(mod, run)
    printRun(run)
    local ok, err = pcall(function()
        local w = mod:Window()
        if not w then return end
        local text = table.concat(runLines(run), "\n")
        pcall(w.eb.SetText, w.eb, text)
        w.text = text
        pcall(w.frame.Show, w.frame)
        pcall(w.eb.SetFocus, w.eb)      -- focus fires the select-all
        if type(_G.UISpecialFrames) == "table" then
            -- ESC closes (entries are GLOBAL FRAME NAMES, hidden through
            -- _G[name]:Hide() by CloseSpecialWindows). The sim's native
            -- table is a proxy: tInsert is inert, direct indexing works.
            local present = false
            for i = 1, #_G.UISpecialFrames do
                if _G.UISpecialFrames[i] == Probe.WINDOW.NAME then
                    present = true
                    break
                end
            end
            if not present then
                _G.UISpecialFrames[#_G.UISpecialFrames + 1] = Probe.WINDOW.NAME
            end
        end
    end)
    if not ok then
        FX.Print("PROBE window unavailable: " .. tostring(err))
    elseif not mod._win then
        FX.Print("PROBE window unavailable: frame/EditBox could not be created")
    end
end

--- One run over an explicit plan (exposed for the tests' group-level pcall
--- check; /fx probe uses Run). Every group function runs in its own pcall:
--- a group that raises lands as { group = label, raise = <K string> }.
function Probe:RunPlan(label, plan)
    local combat = inCombat()
    local run = {
        t = _G.GetTime and GetTime() or 0,
        date = stamp(),
        label = label or (combat and "combat" or "ooc"),
        combat = combat,
        epoch = (FX.db and tonumber(FX.db.probeEpoch)) or Probe._epoch,
        build = buildInfo(),
        results = {},
    }
    for _, g in ipairs(plan) do
        local ok, values = pcall(g.fn)
        local entry = { group = g.label }
        if ok and type(values) == "table" then
            entry.values = values
        else
            entry.raise = K(values)
        end
        run.results[#run.results + 1] = entry
    end
    local runs = dbRuns()
    runs[#runs + 1] = run
    while #runs > Probe.MAX_RUNS do table.remove(runs, 1) end
    presentRun(self, run)
    return run
end

function Probe:Run(label)
    return self:RunPlan(label, planRuns())
end

function Probe:ShowLast()
    local runs = dbRuns()
    local run = runs[#runs]
    if not run then
        FX.Print("PROBE show: no stored runs")
        return nil
    end
    presentRun(self, run)
    return run
end

function Probe:Clear()
    local runs = dbRuns()
    for i = #runs, 1, -1 do runs[i] = nil end
    FX.Print("PROBE clear: stored runs emptied")
end

-- ------------------------------------------------------------ bar probe --

--- Q7 / design §5.5: does a duration object WE built animate our own
--- widgets in combat? C_DurationUtil.CreateDuration
--- (DurationUtilDocumentation.lua:10); SetTimeFromStart's duration unit is
--- SECONDS (LuaDurationObjectAPIDocumentation.lua:444 -- duration
--- "Seconds", modRate number; the research snippets' 10000/30000 were the
--- pre-unit-check form), fed to SimpleStatusBarAPI:SetTimerDuration
--- (SimpleStatusBarAPIDocumentation.lua:333) and
--- FrameAPICooldown:SetCooldownFromDurationObject
--- (FrameAPICooldownDocumentation.lua:307). Frames are created on demand
--- only (never at load), every method call pcall'd.
function Probe:Bar(on)
    if not on then
        if self._bar then
            pcall(self._bar.sb.Hide, self._bar.sb)
            if self._bar.cd then pcall(self._bar.cd.Hide, self._bar.cd) end
        end
        FX.Print("PROBE bar: off (frames hidden)")
        return
    end
    local CDU = _G.C_DurationUtil
    if not (CDU and CDU.CreateDuration) then
        FX.Print("PROBE bar: C_DurationUtil.CreateDuration absent")
        return
    end
    local ok, d = pcall(CDU.CreateDuration)
    if not ok or not d then
        FX.Print("PROBE bar: CreateDuration raise: " .. tostring(d))
        return
    end
    local nowOk, now = pcall(_G.GetTime)
    local okS = pcall(d.SetTimeFromStart, d, (nowOk and now) or 0, 10, 1) -- 10 SECONDS
    if not self._bar then
        local okB, sb = pcall(_G.CreateFrame, "StatusBar", "FXProbeBar", _G.UIParent)
        if not okB or not sb then
            FX.Print("PROBE bar: StatusBar create raise: " .. tostring(sb))
            return
        end
        local okC, cd = pcall(_G.CreateFrame, "Cooldown", "FXProbeCd", _G.UIParent)
        pcall(sb.SetSize, sb, 200, 12)
        pcall(sb.SetPoint, sb, "CENTER")
        pcall(sb.SetStatusBarColor, sb, 0, 1, 0, 1)
        if okC and cd then
            pcall(cd.SetSize, cd, 40, 40)
            pcall(cd.SetPoint, cd, "CENTER", sb, "RIGHT", 8)
        end
        pcall(sb.Show, sb)
        if okC and cd then pcall(cd.Show, cd) end
        self._bar = { sb = sb, cd = okC and cd or nil }
    end
    local bar = self._bar
    bar.dur = d
    pcall(bar.sb.SetTimerDuration, bar.sb, d, 0, 0)
    if bar.cd then pcall(bar.cd.SetCooldownFromDurationObject, bar.cd, d, false) end
    local secret = callK(d.HasSecretValues, d)
    local modifier = (_G.Enum and _G.Enum.DurationTimeModifier
        and _G.Enum.DurationTimeModifier.RealTime) or 0
    local rem = callK(d.GetRemainingDuration, d, modifier)
    bar.last = { set = K(okS), secret = secret, rem = rem }
    FX.Print(string.format(
        "PROBE bar: on 10s set=%s secret=%s rem=%s -- watch: does it tick in combat?",
        compact(K(okS)), compact(secret), compact(rem)))
    return bar.last
end

-- ------------------------------------------------------------- capture --

--- One captured event payload, every field K-classified AT CAPTURE TIME.
function Probe:Capture(event, a, b, c, d)
    local ok, err = pcall(function()
        local ev = events()
        local t = _G.GetTime and GetTime()
        if event == "UNIT_SPELLCAST_SUCCEEDED" then -- Q1
            push(ev.casts, { t = t, combat = inCombat(),
                a = K(a), b = K(b), c = K(c), d = K(d) }, 5)
        elseif event == "PLAYER_SWING"
            or event == "PLAYER_SWING_RANGE_UPDATE" then -- Q6
            push(ev.swings, { t = t, e = event, a = K(a), b = K(b), c = K(c) }, 5)
        elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then -- Q5
            push(ev.restricts, { t = t, type = K(a), state = K(b) }, 8)
        end
    end)
    return ok, err
end

-- -------------------------------------------------------------- module --
-- Registration is load-time (no events yet); the capture frame and the
-- probeEpoch bump happen in OnEnable, which the Forte_Core bootstrap calls
-- from its PLAYER_LOGIN handler -- exactly once per login.

--- The capture set, spelled out one event literal per line, and the reason
--- it is spelled out (code-review-5 m6): the registrations run through
--- `pcall(f.RegisterEvent, f, e)`, a shape `scripts/api_lint.py` cannot see
--- (its scans are a `RegisterEvent("NAME")` call and a line that is nothing
--- but quoted ALL-CAPS names), so a typo in one of these names -- which
--- RAISES on the live client, killing the passive capture for the whole
--- launch session -- would ship unlinted. Every line of this table is a line
--- the lint checks against the pinned catalog, and OnEnable registers
--- exactly this list.
local CAPTURE_EVENTS = {
    "UNIT_SPELLCAST_SUCCEEDED",
    "PLAYER_SWING",
    "PLAYER_SWING_RANGE_UPDATE",
    "ADDON_RESTRICTION_STATE_CHANGED",
}

function Probe:OnEnable()
    if FX.db then
        -- The SV row's read half: latch the stamp the PREVIOUS session's
        -- last run wrote, as it stands in the restored SavedVariables at
        -- PLAYER_LOGIN -- before this session's runs overwrite it.
        Probe._svLogin = FX.db.probeStamp
        -- probeEpoch counts real LOGINS. PLAYER_LOGIN also fires after /reload
        -- on the live client (epoch reached 20 in one session), so the bump
        -- rides PLAYER_ENTERING_WORLD's isInitialLogin instead (below).
    end
    if _G.CreateFrame and not self._epochFrame then
        local okE, ef = pcall(_G.CreateFrame, "Frame")
        if okE and ef then
            self._epochFrame = ef
            pcall(ef.RegisterEvent, ef, "PLAYER_ENTERING_WORLD")
            pcall(ef.SetScript, ef, "OnEvent", function(frame, _, isInitialLogin)
                pcall(frame.UnregisterEvent, frame, "PLAYER_ENTERING_WORLD")
                if isInitialLogin then
                    if FX.db then
                        FX.db.probeEpoch = (tonumber(FX.db.probeEpoch) or 0) + 1
                    else
                        Probe._epoch = (Probe._epoch or 0) + 1
                    end
                end
            end)
        end
    end
    if not self._frame and _G.CreateFrame then
        local ok, f = pcall(_G.CreateFrame, "Frame")
        if ok and f then
            for _, e in ipairs(CAPTURE_EVENTS) do
                pcall(f.RegisterEvent, f, e)
            end
            pcall(f.SetScript, f, "OnEvent", function(_, event, a, b, c, d)
                Probe:Capture(event, a, b, c, d)
            end)
            self._frame = f
        end
    end
end

function Probe:Status()
    local runs = dbRuns()
    local last = runs[#runs]
    FX.Print(string.format("Probe: epoch=%s runs=%d last=%s",
        tostring((FX.db and FX.db.probeEpoch) or Probe._epoch), #runs,
        last and (tostring(last.label) .. "@" .. tostring(last.date)) or "never"))
end

FX.RegisterModule("Probe", Probe)

-- /fx probe [label] | show | clear | bar | bar off -- through the shared
-- seam (Core/Init.lua); the message arrives lower-cased and trimmed.
FX.RegisterSlash("probe", function(rest)
    rest = (rest or ""):match("^%s*(.-)%s*$")
    if rest == "show" then
        Probe:ShowLast()
    elseif rest == "clear" then
        Probe:Clear()
    elseif rest == "bar" then
        Probe:Bar(true)
    elseif rest == "bar off" then
        Probe:Bar(false)
    elseif rest == "" then
        Probe:Run(nil)
    else
        Probe:Run(rest)
    end
end)

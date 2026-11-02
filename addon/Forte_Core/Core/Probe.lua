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

--- Research Q5: the cheap "is everything secret right now" mode surface.
local function probeSecretState()
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
    else
        g.cSec = "absent"
    end
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
    local plan = { { label = "SEC", fn = probeSecretState } }
    for _, name in ipairs(pickSpells()) do
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
    plan[#plan + 1] = { label = "GATE", fn = probeGate }
    plan[#plan + 1] = { label = "PRES", fn = probePresence }
    plan[#plan + 1] = { label = "EPOCH", fn = probeEpoch }
    return plan
end

-- ------------------------------------------------------------ run/store --

local function printRun(run)
    local build = {}
    for _, v in ipairs(run.build) do build[#build + 1] = tostring(v) end
    FX.Print(string.format("PROBE %s epoch=%s build=[%s] date=%s",
        tostring(run.label), tostring(run.epoch), table.concat(build, "/"),
        tostring(run.date)))
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
        FX.Print(e.group .. ": " .. table.concat(parts, " "))
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
    printRun(run)
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
    printRun(run)
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

function Probe:OnEnable()
    if FX.db then
        FX.db.probeEpoch = (tonumber(FX.db.probeEpoch) or 0) + 1
    else
        Probe._epoch = (Probe._epoch or 0) + 1
    end
    if not self._frame and _G.CreateFrame then
        local ok, f = pcall(_G.CreateFrame, "Frame")
        if ok and f then
            for _, e in ipairs({ "UNIT_SPELLCAST_SUCCEEDED", "PLAYER_SWING",
                "PLAYER_SWING_RANGE_UPDATE", "ADDON_RESTRICTION_STATE_CHANGED" }) do
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

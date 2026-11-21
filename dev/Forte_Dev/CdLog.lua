-- Forte_Dev/CdLog.lua
-- The passive cooldown-semantics recorder (dev only, never shipped). Question it answers: what do
-- C_Spell.GetSpellCooldown's booleans (isActive, isOnGCD, isEnabled) and numbers (duration, startTime)
-- REALLY do on WoW Forever, for every spell ForteXorcist tracks plus the wand `Shoot` and `Auto Shot`?
-- The owner just plays; the next session reads ForteDevDB.cdlog / ForteDevDB.cdlogSummary.
--
--   Dev.CdLog.Start(seconds) / Stop() / Status()      /fxdev cdlog [seconds|off|status]
--   DevCommands entry "cdlog 600" (fxdev.py commands cdlog 600): a 600 s recording at the next login/reload.
--
-- Recording = ONE frame. Its OnUpdate and its events exist ONLY while recording (Stop removes both).
-- Sampling ~10 Hz (INTERVAL), skipped while the player is dead. Per spell only CHANGES are stored: a row is
-- appended when isActive, isOnGCD, isEnabled, the plain duration (rounded to 0.01) or the NUMERIC verdict
-- (start + duration still in the future, which is the only way startTime changes anything) differs from the
-- previous sample of that spell; the first sample of a spell is stored once as a baseline (base = true).
-- Rows live in ForteDevDB.cdlog, a chronological array capped at MAX_ROWS: once full the oldest row table is
-- removed and REUSED for the new row (no allocation, SavedVariables growth bounded).
--
-- Row shapes (t = GetTime() rounded to 0.01, ev says which):
--   cd       { t, ev="cd", name, active, gcd, enabled, dur, start, secretNumbers, combat, base?, secretFlags? }
--            a nil field = secret or absent in that read; secretNumbers = duration/start were secret.
--   cast     { t, ev="cast", name?, secretId?, combat }     own UNIT_SPELLCAST_SUCCEEDED (name only when plain)
--   auto+ / auto-                                           START / STOP_AUTOREPEAT_SPELL
--   combat+ / combat-                                       PLAYER_REGEN_DISABLED / ENABLED
--   start { seconds } / stop { reason }                     the recording's own bounds
--
-- SAFETY (the dev loop's contract): no chat, no addon messages, nothing typed, nothing protected; every client
-- value is classified (Dev.isSecret) before it is compared or stored; events are registered when a recording
-- starts and unregistered when it stops, never at file top; recording auto-stops after its seconds (OnUpdate
-- deadline + a C_Timer backup); the file is in Forte_Dev, which the release never contains.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
local Dev = FX.Dev

local CdLog = {}
Dev.CdLog = CdLog

CdLog.MAX_ROWS = 4000
CdLog.MAX_SECONDS = 3600          -- fxdev.py CDLOG_MAX_SECONDS must agree
CdLog.INTERVAL = 0.1              -- ~10 Hz
CdLog.REFRESH_SECONDS = 5         -- how often the tracked-spell set is re-read
CdLog.REPAINT_SECONDS = 2         -- panel repaint cadence while recording
CdLog.TIMER_GRACE = 1             -- C_Timer backup fires this long after the deadline
CdLog.FLIP_WINDOW = 0.05          -- "all spells flipped together": seconds
CdLog.FLIP_SPELLS = 4             -- ... at least this many distinct spells
CdLog.PANEL_CLIP = 100
CdLog.EXTRA = { "Shoot", "Auto Shot" }
CdLog.EVENTS = { "UNIT_SPELLCAST_SUCCEEDED", "START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_LOGOUT" }
CdLog.USAGE = "cdlog [seconds|off|status]  (seconds 1-" .. CdLog.MAX_SECONDS .. ")"

--- Session state (never saved). rows = ForteDevDB.cdlog while recording.
local S = {
    recording = false,
    session = 0,
    endsAt = 0, startedAt = 0, planned = 0,
    acc = 0, repaintAcc = 0, refreshAt = 0, mark = 0,
    combat = false,
    dropped = 0, readErrors = 0,
    rows = nil,
    spells = {},     -- [name] = per-spell state (reused)
    order = {},      -- sampling order (sorted by name), nOrder entries
    nOrder = 0,
    frame = nil,
}
CdLog.state = S

-- ------------------------------------------------------------------- seams --

function CdLog.now()
    local f = _G.GetTime
    if type(f) == "function" then
        local ok, t = pcall(f)
        if ok and type(t) == "number" then return t end
    end
    return 0
end

--- C_Spell.GetSpellCooldown(key) inside a pcall; the info table, or nil.
function CdLog.read(key)
    local api = _G.C_Spell
    local f = type(api) == "table" and api.GetSpellCooldown or nil
    if type(f) ~= "function" then return nil end
    local ok, info = pcall(f, key)
    if not ok then
        S.readErrors = S.readErrors + 1
        return nil
    end
    if type(info) == "table" then return info end
    return nil
end

--- The names ForteXorcist tracks (Engine.tracked keys); nil when the cooldown add-on is absent.
function CdLog.tracked()
    local E = FX.Cooldown and FX.Cooldown.Engine
    return E and E.tracked or nil
end

--- True while the player is dead or a ghost (no sampling then).
function CdLog.isDead()
    local f = _G.UnitIsDeadOrGhost
    if type(f) ~= "function" then return false end
    local ok, v = pcall(f, "player")
    return ok and Dev.plain(v) == true
end

function CdLog.inCombat() return Dev.inCombat() end

function CdLog.createFrame() return _G.CreateFrame("Frame") end

-- ------------------------------------------------------------- classifiers --

local function round2(x) return math.floor(x * 100 + 0.5) / 100 end

--- (plain boolean | nil, wasSecret)
local function plainBool(v)
    if type(v) ~= "boolean" then return nil, false end
    if Dev.isSecret(v) then return nil, true end
    return v, false
end

--- (plain finite number | nil, wasSecret)
local function plainNum(v)
    if type(v) ~= "number" then return nil, false end
    if Dev.isSecret(v) then return nil, true end
    if v ~= v then return nil, false end
    return v, false
end

CdLog.plainBool, CdLog.plainNum = plainBool, plainNum

-- -------------------------------------------------------------------- rows --

--- Append a row (the oldest row table is reused when the ring is full). The caller fills the rest.
local function newRow(ev, now)
    local rows = S.rows
    local row
    if #rows >= CdLog.MAX_ROWS then
        row = table.remove(rows, 1)
        for k in pairs(row) do row[k] = nil end
        S.dropped = S.dropped + 1
    else
        row = {}
    end
    row.t = round2(now)
    row.ev = ev
    row.combat = S.combat
    rows[#rows + 1] = row
    return row
end

-- ------------------------------------------------------------------ spells --

--- The identifier C_Spell is asked for: the English name on an English client, else the data row's rank id
--- (the same rule Forte_Cooldown's readKey follows), else the client's own name for it.
local function resolveKey(name)
    local L = FX.Locale
    if L and L.IsEnglish then
        local okE, english = pcall(L.IsEnglish)
        if okE and english == false then
            if L.RankIDsForName then
                local okI, ids = pcall(L.RankIDsForName, name)
                if okI and type(ids) == "table" and #ids > 0 then
                    local pick = ids[1]
                    local known = FX.Compat and FX.Compat.IsPlayerSpell
                    if known then
                        for i = 1, #ids do
                            local okK, k = pcall(known, ids[i])
                            if okK and Dev.plain(k) == true then
                                pick = ids[i]
                                break
                            end
                        end
                    end
                    return pick
                end
            end
            if FX.L then
                local okL, localized = pcall(FX.L, name)
                if okL and type(localized) == "string" and localized ~= "" then return localized end
            end
        end
    end
    return name
end

local function byName(a, b) return a.name < b.name end

local function touch(name)
    local s = S.spells[name]
    if not s then
        s = { name = name, key = resolveKey(name), seen = false, active = nil, gcd = nil, enabled = nil,
            dur = nil, numActive = nil, mark = 0 }
        S.spells[name] = s
    end
    s.mark = S.mark
end

--- Re-read the tracked set; rebuild the (sorted) sampling order. A spell that left the set is re-baselined
--- if it comes back.
local function refresh(now)
    S.refreshAt = now + CdLog.REFRESH_SECONDS
    S.mark = S.mark + 1
    local tracked = CdLog.tracked()
    if type(tracked) == "table" then
        for name in pairs(tracked) do
            if type(name) == "string" then touch(name) end
        end
    end
    for i = 1, #CdLog.EXTRA do touch(CdLog.EXTRA[i]) end
    local n = 0
    for _, s in pairs(S.spells) do
        if s.mark == S.mark then
            n = n + 1
            S.order[n] = s
        else
            s.seen = false
        end
    end
    for i = n + 1, S.nOrder do S.order[i] = nil end
    S.nOrder = n
    table.sort(S.order, byName)
end

--- One read of one spell; a row only when something we watch changed (or on the baseline).
local function sampleSpell(s, now)
    local info = CdLog.read(s.key)
    if info == nil or Dev.isSecret(info) then return end
    local active, sa = plainBool(info.isActive)
    local gcd, sg = plainBool(info.isOnGCD)
    local enabled, se = plainBool(info.isEnabled)
    local dur, sd = plainNum(info.duration)
    local start, ss = plainNum(info.startTime)
    local numActive
    if dur then dur = round2(dur) end
    if dur and start then numActive = dur > 0 and start > 0 and start + dur > now end
    local first = not s.seen
    if first or active ~= s.active or gcd ~= s.gcd or enabled ~= s.enabled or dur ~= s.dur
        or numActive ~= s.numActive then
        s.seen, s.active, s.gcd, s.enabled, s.dur, s.numActive = true, active, gcd, enabled, dur, numActive
        local row = newRow("cd", now)
        row.name = s.name
        row.active, row.gcd, row.enabled = active, gcd, enabled
        row.dur = dur
        if start then row.start = round2(start) end
        row.secretNumbers = (sd or ss) and true or false
        if sa or sg or se then row.secretFlags = true end
        if first then row.base = true end
    end
end

-- ----------------------------------------------------------------- summary --

local function median(sorted)
    local n = #sorted
    if n == 0 then return nil end
    if n % 2 == 1 then return sorted[(n + 1) / 2] end
    return round2((sorted[n / 2] + sorted[n / 2 + 1]) / 2)
end

--- Pure: rows (chronological) -> the summary table. meta = { planned, tStart, tEnd, reason, dropped,
--- readErrors, stamp, build } (all optional).
--- Per spell: changes (non-baseline cd rows), periods = CLOSED active=true & gcd=false periods that began at
--- an observed transition, min/median/max of their lengths, longest = the longest period of any kind (also
--- one still open at the end, or one already running at the baseline sample), censored = closed periods that
--- began at the baseline, open, secretNumbers.
--- flipMoments: moments where >= FLIP_SPELLS distinct spells changed `active` within FLIP_WINDOW seconds
--- (greedy, non-overlapping). Only retained rows are summarised: `dropped` says how many were pushed out.
function CdLog.Summarize(rows, meta)
    meta = meta or {}
    local per, counts, lastActive, flips = {}, {}, {}, {}
    local tFirst, tLast
    for i = 1, #rows do
        local r = rows[i]
        if type(r) == "table" then
            local ev = type(r.ev) == "string" and r.ev or "?"
            counts[ev] = (counts[ev] or 0) + 1
            if type(r.t) == "number" then
                tFirst = tFirst or r.t
                tLast = r.t
            end
            local name = r.name
            if ev == "cd" and type(name) == "string" and type(r.t) == "number" then
                local st = per[name]
                if not st then
                    st = { changes = 0, lens = {}, censored = 0, secretNumbers = false, longest = nil }
                    per[name] = st
                end
                if r.secretNumbers then st.secretNumbers = true end
                local inCond = r.active == true and r.gcd == false
                if r.base then
                    lastActive[name] = r.active
                    st.since, st.cens = nil, false
                    if inCond then st.since, st.cens = r.t, true end
                else
                    st.changes = st.changes + 1
                    local prev = lastActive[name]
                    if prev ~= nil and r.active ~= nil and r.active ~= prev then
                        flips[#flips + 1] = { t = r.t, name = name }
                    end
                    lastActive[name] = r.active
                    if inCond and not st.since then
                        st.since, st.cens = r.t, false
                    elseif not inCond and st.since then
                        local len = round2(r.t - st.since)
                        if st.cens then
                            st.censored = st.censored + 1
                        else
                            st.lens[#st.lens + 1] = len
                        end
                        if not st.longest or len > st.longest then st.longest = len end
                        st.since, st.cens = nil, false
                    end
                end
            end
        end
    end
    local tEnd = meta.tEnd or tLast
    local tStart = meta.tStart or tFirst
    local spells, spellCount = {}, 0
    for name, st in pairs(per) do
        local lens = st.lens
        table.sort(lens)
        local open = false
        if st.since and tEnd then
            open = true
            local len = round2(math.max(0, tEnd - st.since))
            if not st.longest or len > st.longest then st.longest = len end
        end
        spellCount = spellCount + 1
        spells[name] = {
            changes = st.changes, periods = #lens, min = lens[1], median = median(lens), max = lens[#lens],
            longest = st.longest, censored = st.censored, open = open, secretNumbers = st.secretNumbers,
        }
    end
    local moments, i = 0, 1
    while i <= #flips do
        local j, seen, distinct = i, {}, 0
        while j <= #flips and flips[j].t - flips[i].t <= CdLog.FLIP_WINDOW + 1e-6 do
            if not seen[flips[j].name] then
                seen[flips[j].name] = true
                distinct = distinct + 1
            end
            j = j + 1
        end
        if distinct >= CdLog.FLIP_SPELLS then
            moments = moments + 1
            i = j
        else
            i = i + 1
        end
    end
    return {
        v = 1, reason = meta.reason, planned = meta.planned, started = tStart, ended = tEnd,
        elapsed = (tStart and tEnd) and round2(tEnd - tStart) or nil, wall = Dev.now(),
        stamp = meta.stamp, build = meta.build,
        rows = #rows, rowCounts = counts, dropped = meta.dropped or 0, readErrors = meta.readErrors or 0,
        spellCount = spellCount, flipMoments = moments, spells = spells,
    }
end

--- One line about the last stored summary (what `status` shows while idle). Pure.
function CdLog.SummaryLine(sm)
    if type(sm) ~= "table" then return "cdlog: idle, no summary yet (cdlog <seconds> starts one)" end
    local list = {}
    for name, st in pairs(type(sm.spells) == "table" and sm.spells or {}) do
        if type(st) == "table" and (st.periods or 0) > 0 then list[#list + 1] = { name = name, st = st } end
    end
    table.sort(list, function(a, b)
        if a.st.periods ~= b.st.periods then return a.st.periods > b.st.periods end
        return a.name < b.name
    end)
    local parts = {}
    for i = 1, math.min(3, #list) do
        local st = list[i].st
        parts[#parts + 1] = string.format("%s x%d med %s max %s", list[i].name, st.periods,
            tostring(st.median), tostring(st.max))
    end
    return Dev.clip(string.format("cdlog: idle; last %ss (%s): %s rows (%s dropped), %s spells, %s flip moments; "
        .. "active&!gcd: %s", tostring(sm.elapsed), tostring(sm.reason), tostring(sm.rows), tostring(sm.dropped),
        tostring(sm.spellCount), tostring(sm.flipMoments), #parts > 0 and table.concat(parts, "; ") or "none"), 400)
end

-- ---------------------------------------------------------------- recording --

local function recordingText()
    local left = math.max(0, math.ceil(S.endsAt - CdLog.now()))
    return string.format("cdlog: recording %d s left, %d rows", left, S.rows and #S.rows or 0)
end

--- The panel line (nil when not recording).
function CdLog.PanelLine()
    if not S.recording then return nil end
    return recordingText()
end

function CdLog.IsRecording() return S.recording end

function CdLog.Status()
    if S.recording then return recordingText() end
    return CdLog.SummaryLine(Dev.DB().cdlogSummary)
end

--- One sampling pass (OnUpdate calls it at INTERVAL). Public for tests.
function CdLog.Tick()
    if not S.recording then return end
    local now = CdLog.now()
    if now >= S.endsAt then
        CdLog.Stop("done")
        return
    end
    S.combat = CdLog.inCombat()
    if not CdLog.isDead() then
        if now >= S.refreshAt then refresh(now) end
        for i = 1, S.nOrder do sampleSpell(S.order[i], now) end
    end
    if S.repaintAcc >= CdLog.REPAINT_SECONDS then
        S.repaintAcc = 0
        Dev.Repaint()
    end
end

local function onUpdate(_, elapsed)
    if not S.recording then return end
    local e = plainNum(elapsed) or 0
    S.acc = S.acc + e
    S.repaintAcc = S.repaintAcc + e
    if S.acc < CdLog.INTERVAL then return end
    S.acc = 0
    local ok, err = pcall(CdLog.Tick)
    if not ok then Dev.state.lastError = Dev.S(err) end
end

local function spellNameOf(id)
    local api = _G.C_Spell
    local f = type(api) == "table" and api.GetSpellName or nil
    if type(f) ~= "function" then return nil end
    local ok, name = pcall(f, id)
    if not ok then return nil end
    name = Dev.plain(name)
    if type(name) == "string" and name ~= "" then return Dev.clip(name, Dev.NAME_MAX) end
    return nil
end

local function onEvent(_, event, ...)
    if not S.recording then return end
    local now = CdLog.now()
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if Dev.isSecret(unit) or unit ~= "player" then return end
        local row = newRow("cast", now)
        if Dev.isSecret(spellID) then
            row.secretId = true
        elseif type(spellID) == "number" then
            local name = spellNameOf(spellID)
            if name then row.name = name end
        end
    elseif event == "START_AUTOREPEAT_SPELL" then
        newRow("auto+", now)
    elseif event == "STOP_AUTOREPEAT_SPELL" then
        newRow("auto-", now)
    elseif event == "PLAYER_REGEN_DISABLED" then
        S.combat = true
        newRow("combat+", now)
    elseif event == "PLAYER_REGEN_ENABLED" then
        S.combat = false
        newRow("combat-", now)
    elseif event == "PLAYER_LOGOUT" then
        CdLog.Stop("logout")
    end
end

--- Test seam: deliver an event exactly as the frame would.
function CdLog.HandleEvent(event, ...)
    local ok, err = pcall(onEvent, nil, event, ...)
    if not ok then Dev.state.lastError = Dev.S(err) end
    return ok
end

local function attach(f)
    f:SetScript("OnEvent", function(self, event, ...) CdLog.HandleEvent(event, ...) end)
    for i = 1, #CdLog.EVENTS do
        local ev = CdLog.EVENTS[i]
        if ev == "UNIT_SPELLCAST_SUCCEEDED" and f.RegisterUnitEvent then
            f:RegisterUnitEvent(ev, "player")
        else
            f:RegisterEvent(ev)
        end
    end
    f:SetScript("OnUpdate", onUpdate)
end

local function detach(f)
    f:SetScript("OnUpdate", nil)
    f:UnregisterAllEvents()
    f:SetScript("OnEvent", nil)
end

--- Start a recording of `seconds` (1..MAX_SECONDS). Already recording: only the deadline moves (no new rows,
--- no second registration). Returns (ok, text).
function CdLog.Start(seconds)
    local n = tonumber(seconds)
    if not n or n ~= n or n < 1 then
        return false, "cdlog: seconds must be a number >= 1 (" .. CdLog.USAGE .. ")"
    end
    if n > CdLog.MAX_SECONDS then n = CdLog.MAX_SECONDS end
    local now = CdLog.now()
    if S.recording then
        S.endsAt, S.planned = now + n, n
    else
        local db = Dev.DB()
        db.cdlog = {}
        db.cdlogSummary = nil
        S.rows = db.cdlog
        S.recording = true
        S.session = S.session + 1
        S.startedAt, S.endsAt, S.planned = now, now + n, n
        S.acc, S.repaintAcc, S.refreshAt = 0, 0, 0
        S.dropped, S.readErrors = 0, 0
        S.combat = CdLog.inCombat()
        for k in pairs(S.spells) do S.spells[k] = nil end
        for i = 1, S.nOrder do S.order[i] = nil end
        S.nOrder = 0
        newRow("start", now).seconds = n
        local f = S.frame
        if not f then
            f = CdLog.createFrame()
            S.frame = f
        end
        attach(f)
    end
    local session = S.session
    Dev.After(n + CdLog.TIMER_GRACE, function()
        if S.recording and S.session == session and CdLog.now() >= S.endsAt then CdLog.Stop("done") end
    end)
    Dev.Repaint()
    return true, recordingText()
end

--- Stop the recording, compute the summary into ForteDevDB.cdlogSummary. Not recording: (false, ...).
function CdLog.Stop(reason)
    if not S.recording then return false, "cdlog: not recording" end
    S.recording = false
    if S.frame then detach(S.frame) end
    local now = CdLog.now()
    newRow("stop", now).reason = type(reason) == "string" and reason or "off"
    local db = Dev.DB()
    db.cdlog = S.rows
    db.cdlogSummary = CdLog.Summarize(S.rows, { planned = S.planned, tStart = round2(S.startedAt),
        tEnd = round2(now), reason = type(reason) == "string" and reason or "off", dropped = S.dropped,
        readErrors = S.readErrors, stamp = Dev.stamp(), build = db.build })
    S.rows = nil
    Dev.Repaint()
    return true, CdLog.SummaryLine(db.cdlogSummary)
end

-- --------------------------------------------------------------- the verb --

--- "600" -> "start", 600 | "off" | "status" | "" -> "status"; anything else -> nil, usage text.
function CdLog.ParseArg(rest)
    rest = tostring(rest or ""):match("^%s*(.-)%s*$")
    if rest == "" or rest == "status" then return "status" end
    if rest == "off" then return "off" end
    if rest:match("^%d+%.?%d*$") then
        local n = tonumber(rest)
        if n and n >= 1 and n <= CdLog.MAX_SECONDS then return "start", n end
    end
    return nil, "cdlog: '" .. Dev.clip(rest, 20) .. "' is not valid: " .. CdLog.USAGE
end

Dev.verbs.cdlog = {
    -- Stopping and reading are always safe; a start is refused in combat like every other verb.
    combatOk = function(rest) return rest == "" or rest == "off" or rest == "status" end,
    fn = function(rest)
        local kind, v = CdLog.ParseArg(rest)
        if kind == "status" then return true, CdLog.Status() end
        if kind == "off" then
            if not S.recording then return true, "cdlog: not recording" end
            return CdLog.Stop("off")
        end
        if kind == "start" then return CdLog.Start(v) end
        return false, v
    end,
}

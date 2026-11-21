-- dev/Forte_Dev/tests/test_cdlog.lua
-- The passive cooldown recorder (CdLog.lua) against a STUBBED clock, cooldown API, frame and event stream:
-- the simulator delivers no OnUpdate and no C_Timer callback inside a test, so every tick, event and timer
-- is fired by hand through the seams (CdLog.now / read / tracked / isDead / inCombat / createFrame, Dev.After).
-- What only the real client can tell: what the booleans and numbers REALLY do (that is what the recording
-- is for), whether OnUpdate really fires at the frame rate, and the true row rate of a long session.

local FX = ForteXorcist
local Dev = FX.Dev
local CdLog = Dev.CdLog
local S = CdLog.state

local SECRET = 777.125                 -- the "secret" number of the stub issecretvalue
local SEAMS = { "now", "read", "tracked", "isDead", "inCombat", "createFrame" }
local REAL = {}
for _, k in ipairs(SEAMS) do REAL[k] = CdLog[k] end

-- ------------------------------------------------------------- scaffolding --

local function stubFrame()
    local f = { events = {}, scripts = {}, created = 0 }
    function f:RegisterEvent(e) self.events[e] = true end
    function f:RegisterUnitEvent(e, unit) self.events[e] = unit end
    function f:UnregisterAllEvents() self.events = {} end
    function f:SetScript(k, fn) self.scripts[k] = fn end
    function f:GetScript(k) return self.scripts[k] end
    function f:eventCount()
        local n = 0
        for _ in pairs(self.events) do n = n + 1 end
        return n
    end
    return f
end

local function sandbox()
    local saved = { db = _G.ForteDevDB, after = Dev.After, combat = _G.InCombatLockdown,
        secret = _G.issecretvalue, cmds = _G.ForteDevCommands, frame = S.frame, seams = {}, state = {},
        lastError = Dev.state.lastError }
    for k, v in pairs(Dev.state) do saved.state[k] = v end
    for _, k in ipairs(SEAMS) do saved.seams[k] = CdLog[k] end
    if S.recording then CdLog.Stop("test") end
    _G.ForteDevDB = nil
    Dev.InitDB()
    S.frame = nil
    local env = { clock = 100, infos = {}, tracked = {}, timers = {}, dead = false, combat = false,
        reads = 0, frames = {}, secretBools = false, keys = {}, logKeys = false }
    CdLog.now = function() return env.clock end
    CdLog.read = function(key)
        env.reads = env.reads + 1
        if env.logKeys then env.keys[#env.keys + 1] = key end
        return env.infos[key]
    end
    CdLog.tracked = function() return env.tracked end
    CdLog.isDead = function() return env.dead end
    CdLog.inCombat = function() return env.combat end
    CdLog.createFrame = function()
        local f = stubFrame()
        env.frames[#env.frames + 1] = f
        return f
    end
    Dev.After = function(sec, fn) env.timers[#env.timers + 1] = { sec = sec, fn = fn } end
    _G.InCombatLockdown = function() return false end
    _G.issecretvalue = function(v)
        if env.secretBools and type(v) == "boolean" then return true end
        return v == SECRET
    end
    return env, function()
        if S.recording then CdLog.Stop("test") end
        _G.ForteDevDB = saved.db
        Dev.After = saved.after
        _G.InCombatLockdown, _G.issecretvalue, _G.ForteDevCommands = saved.combat, saved.secret, saved.cmds
        for _, k in ipairs(SEAMS) do CdLog[k] = saved.seams[k] end
        S.frame = saved.frame
        for k in pairs(Dev.state) do Dev.state[k] = nil end
        for k, v in pairs(saved.state) do Dev.state[k] = v end
        Dev.state.lastError = saved.lastError
        Dev.Repaint()
    end
end

local function withEnv(body)
    local env, restore = sandbox()
    local ok, err = pcall(body, env)
    restore()
    if not ok then error(err, 0) end
end

local function info(active, gcd, dur, start, enabled)
    return { isActive = active, isOnGCD = gcd, isEnabled = enabled ~= false, duration = dur or 0,
        startTime = start or 0 }
end

local function tick(env, dt)
    env.clock = env.clock + (dt or 0.1)
    CdLog.Tick()
end

local function rows() return Dev.DB().cdlog end

local function cdRows(name)
    local out = {}
    for _, r in ipairs(rows()) do
        if r.ev == "cd" and r.name == name then out[#out + 1] = r end
    end
    return out
end

local function near(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-6 end

-- ================================================================ sampling ==

test("cdlog: sampling records only CHANGES (a baseline row once, then silence)", function()
    withEnv(function(env)
        env.tracked["Aimed Shot"] = { name = "Aimed Shot" }
        env.infos["Aimed Shot"] = info(false, false, 0, 0)
        assertTrue(CdLog.Start(60))
        for _ = 1, 30 do tick(env) end
        assertEquals(2, #rows())                                   -- start marker + baseline
        local base = rows()[2]
        assertEquals("cd", base.ev); assertEquals("Aimed Shot", base.name); assertEquals(true, base.base)
        assertEquals(false, base.active); assertEquals(false, base.gcd); assertEquals(true, base.enabled)
        assertEquals(false, base.secretNumbers); assertEquals(false, base.combat)
        -- the cooldown starts: flags and duration change -> one row
        env.infos["Aimed Shot"] = info(true, false, 6, env.clock)
        tick(env)
        for _ = 1, 20 do tick(env) end
        assertEquals(3, #rows())
        local r = rows()[3]
        assertEquals(true, r.active); assertEquals(false, r.gcd); assertEquals(6, r.dur)
        assertTrue(near(r.start, math.floor(r.start * 100 + 0.5) / 100))
        assertEquals(nil, r.base)
        -- a NEW start with the same flags and duration, still running: the numeric verdict is unchanged -> no row
        env.infos["Aimed Shot"] = info(true, false, 6, env.clock - 0.5)
        tick(env)
        assertEquals(3, #rows())
        -- the numbers say "over" while the flags still say active: the numeric verdict changed -> a row with start
        env.clock = env.clock + 10
        CdLog.Tick()
        assertEquals(4, #rows())
        assertEquals(true, rows()[4].active)
        assertEquals("number", type(rows()[4].start))
        -- the flags catch up
        env.infos["Aimed Shot"] = info(false, false, 0, 0)
        tick(env)
        assertEquals(5, #rows())
        assertEquals(false, rows()[5].active)
    end)
end)

test("cdlog: every changed field triggers: isOnGCD, isEnabled, plain duration (0.01), nothing else", function()
    withEnv(function(env)
        env.tracked["A"] = {}
        env.infos["A"] = info(true, true, 1.5, 100)
        CdLog.Start(60)
        tick(env)
        local n = #rows()                                           -- start + baseline
        env.infos["A"] = info(true, false, 1.5, 100)               -- gcd flips
        tick(env); assertEquals(n + 1, #rows())
        env.infos["A"] = info(true, false, 1.5, 100, false)        -- enabled flips
        tick(env); assertEquals(n + 2, #rows())
        env.infos["A"] = info(true, false, 1.504, 100, false)      -- 1.504 rounds to 1.50 = unchanged: no row
        tick(env); assertEquals(n + 2, #rows())
        env.infos["A"] = info(true, false, 1.52, 100, false)       -- a real 0.01 step
        tick(env); assertEquals(n + 3, #rows())
        assertEquals(1.52, rows()[#rows()].dur)
    end)
end)

test("cdlog: times are rounded to 0.01 and rows carry the combat flag", function()
    withEnv(function(env)
        env.tracked["A"] = {}
        env.infos["A"] = info(false, false)
        env.clock = 100.126
        CdLog.Start(60)
        env.combat = true
        env.clock = 100.2
        CdLog.Tick()
        env.infos["A"] = info(true, false, 3, 100.2)
        tick(env)
        local r = rows()[#rows()]
        assertEquals(100.3, r.t)
        assertEquals(true, r.combat)
        assertEquals(100.13, rows()[1].t)
        assertEquals(false, rows()[1].combat)
    end)
end)

test("cdlog: a nil read (unknown spell) records nothing; Shoot and Auto Shot are always sampled by name", function()
    withEnv(function(env)
        env.logKeys = true
        env.tracked["Aimed Shot"] = {}
        CdLog.Start(60)
        tick(env)
        assertEquals(1, #rows())                                    -- only the start marker
        local seen = {}
        for _, k in ipairs(env.keys) do seen[k] = true end
        assertTrue(seen["Aimed Shot"]); assertTrue(seen["Shoot"]); assertTrue(seen["Auto Shot"])
        env.infos["Shoot"] = info(false, false)
        tick(env)
        assertEquals("Shoot", rows()[#rows()].name)
    end)
end)

test("cdlog: no sampling while the player is dead; sampling resumes after", function()
    withEnv(function(env)
        env.tracked["A"] = {}
        env.infos["A"] = info(false, false)
        CdLog.Start(60)
        env.dead = true
        local before = env.reads
        for _ = 1, 10 do tick(env) end
        assertEquals(before, env.reads)
        env.dead = false
        tick(env)
        assertTrue(env.reads > before)
        assertEquals(2, #rows())
    end)
end)

test("cdlog: the OnUpdate accumulates ~10 Hz and survives a raising read", function()
    withEnv(function(env)
        env.tracked["A"] = {}
        env.infos["A"] = info(false, false)
        CdLog.Start(60)
        local f = env.frames[1]
        local onUpdate = f:GetScript("OnUpdate")
        assertEquals("function", type(onUpdate))
        onUpdate(f, 0.05)
        assertEquals(0, env.reads)
        onUpdate(f, 0.06)
        assertTrue(env.reads > 0)
        local n = env.reads
        onUpdate(f, 0.02)
        assertEquals(n, env.reads)
        onUpdate(f, SECRET)                                         -- a secret elapsed counts as 0
        assertEquals(n, env.reads)
        CdLog.read = function() error("boom") end
        onUpdate(f, 0.2)
        assertEquals("string", type(Dev.state.lastError))
        assertTrue(CdLog.IsRecording())
    end)
end)

test("cdlog: the real read is pcall'd: a raising C_Spell.GetSpellCooldown is counted, not raised", function()
    local api = _G.C_Spell
    local real = api and api.GetSpellCooldown
    withEnv(function()
        CdLog.read = REAL.read
        _G.C_Spell = api or {}
        _G.C_Spell.GetSpellCooldown = function() error("secret value taint") end
        local before = S.readErrors
        local got = CdLog.read("Anything")
        assertEquals(nil, got)
        assertEquals(before + 1, S.readErrors)
        _G.C_Spell.GetSpellCooldown = function(k) return { isActive = true, key = k } end
        local ok = CdLog.read("X")
        assertEquals("X", ok.key)
        _G.C_Spell.GetSpellCooldown = function() return "not a table" end
        assertEquals(nil, CdLog.read("X"))
    end)
    if api then api.GetSpellCooldown = real else _G.C_Spell = nil end
end)

test("cdlog: a localized client reads by the data row's rank id (the one the player knows)", function()
    local L, C = FX.Locale, FX.Compat
    local saved = { stub = L.stubLocale, ranks = L.RankIDsForName, known = C.IsPlayerSpell }
    withEnv(function(env)
        L.stubLocale = function() return "deDE" end
        L.RankIDsForName = function(name) return name == "Aimed Shot" and { 111, 222 } or nil end
        C.IsPlayerSpell = function(id) return id == 222 end
        env.tracked["Aimed Shot"] = {}
        env.infos[222] = info(false, false)
        CdLog.Start(60)
        tick(env)
        local row
        for _, r in ipairs(rows()) do if r.name == "Aimed Shot" then row = r end end
        L.stubLocale, L.RankIDsForName, C.IsPlayerSpell = saved.stub, saved.ranks, saved.known
        assertTrue(row ~= nil, "Aimed Shot read through id 222")
    end)
    L.stubLocale, L.RankIDsForName, C.IsPlayerSpell = saved.stub, saved.ranks, saved.known
end)

-- ============================================================ secret values ==

test("cdlog: secret numbers and booleans are classified, never stored raw", function()
    withEnv(function(env)
        env.tracked["A"] = {}
        env.infos["A"] = info(true, false, SECRET, SECRET)
        CdLog.Start(60)
        tick(env)
        local r = rows()[2]
        assertEquals(true, r.secretNumbers)
        assertEquals(nil, r.dur); assertEquals(nil, r.start)
        assertEquals(true, r.active); assertEquals(false, r.gcd)
        -- booleans secret too (should never happen, but the classifier must hold)
        env.secretBools = true
        tick(env)
        local r2 = rows()[#rows()]
        assertEquals(nil, r2.active); assertEquals(nil, r2.gcd); assertEquals(nil, r2.enabled)
        assertEquals(true, r2.secretFlags)
        -- numbers plain again
        env.secretBools = false
        env.infos["A"] = info(true, false, 5, 100)
        tick(env)
        local r3 = rows()[#rows()]
        assertEquals(5, r3.dur); assertEquals(false, r3.secretNumbers)
        for _, row in ipairs(rows()) do
            for k, v in pairs(row) do
                assertTrue(v ~= SECRET, "raw secret stored in " .. tostring(k))
                local t = type(v)
                assertTrue(t == "string" or t == "number" or t == "boolean", "non-plain " .. t .. " in " .. k)
            end
        end
    end)
end)

test("cdlog: an issecretvalue that raises fails CLOSED (everything secret, nothing stored)", function()
    withEnv(function(env)
        env.tracked["A"] = {}
        env.infos["A"] = info(true, false, 5, 100)
        _G.issecretvalue = function() error("restricted") end
        CdLog.Start(60)
        tick(env)
        -- the info table itself counts as secret: no baseline row from an unreadable read
        assertEquals(1, #rows())
    end)
end)

test("cdlog: own casts: plain id -> name only; secret id -> secretId; other units ignored", function()
    local api = _G.C_Spell
    local realName = api and api.GetSpellName
    withEnv(function(env)
        _G.C_Spell = api or {}
        _G.C_Spell.GetSpellName = function(id) return id == 5019 and "Shoot" or nil end
        CdLog.Start(60)
        CdLog.HandleEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 5019)
        CdLog.HandleEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", SECRET)
        CdLog.HandleEvent("UNIT_SPELLCAST_SUCCEEDED", "target", "guid", 5019)
        CdLog.HandleEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 123)
        local rs = rows()
        assertEquals(4, #rs)                                        -- start + 3 casts (target ignored)
        assertEquals("cast", rs[2].ev); assertEquals("Shoot", rs[2].name); assertEquals(nil, rs[2].secretId)
        assertEquals(true, rs[3].secretId); assertEquals(nil, rs[3].name)
        assertEquals("cast", rs[4].ev); assertEquals(nil, rs[4].name)
        for _, r in ipairs(rs) do
            for _, v in pairs(r) do assertTrue(v ~= 5019 and v ~= 123, "an id was stored") end
        end
    end)
    if api then api.GetSpellName = realName else _G.C_Spell = nil end
end)

test("cdlog: marker rows for auto-repeat and combat, and they line up with the spell changes", function()
    withEnv(function(env)
        env.tracked["A"] = {}
        env.infos["A"] = info(false, false)
        CdLog.Start(60)
        tick(env)
        CdLog.HandleEvent("START_AUTOREPEAT_SPELL")
        CdLog.HandleEvent("PLAYER_REGEN_DISABLED")
        env.infos["A"] = info(true, false, 2, env.clock)
        env.combat = true
        tick(env)
        CdLog.HandleEvent("STOP_AUTOREPEAT_SPELL")
        CdLog.HandleEvent("PLAYER_REGEN_ENABLED")
        local evs = {}
        for _, r in ipairs(rows()) do evs[#evs + 1] = r.ev end
        assertEquals("start,cd,auto+,combat+,cd,auto-,combat-", table.concat(evs, ","))
        assertEquals(true, rows()[5].combat)
        assertEquals(false, rows()[7].combat)
    end)
end)

-- ================================================================== the ring ==

test("cdlog: the ring caps at 4000 rows, drops the oldest, and reuses the row table", function()
    withEnv(function(env)
        env.tracked["A"] = {}
        env.infos["A"] = info(false, false, 0, 0)
        CdLog.Start(3600)
        tick(env)                                                   -- start + baseline
        local flip = false
        while #rows() < CdLog.MAX_ROWS do
            flip = not flip
            env.infos["A"] = info(flip, false, flip and 2 or 0, env.clock)
            tick(env)
        end
        assertEquals(CdLog.MAX_ROWS, #rows())
        local first = rows()[1]
        assertEquals("start", first.ev)
        for _ = 1, 5 do
            flip = not flip
            env.infos["A"] = info(flip, false, flip and 2 or 0, env.clock)
            tick(env)
        end
        assertEquals(CdLog.MAX_ROWS, #rows())
        assertTrue(rows()[1] ~= first, "the oldest row was dropped")
        assertTrue(rows()[CdLog.MAX_ROWS - 4] == first, "the dropped row's table was reused for a new row")
        assertEquals(nil, first.seconds)                            -- no stale field of the old row
        assertEquals("cd", first.ev)
        assertEquals(5, S.dropped)
        local ok = CdLog.Stop("done")
        assertTrue(ok)
        assertEquals(CdLog.MAX_ROWS, #rows())                       -- the stop marker also pushed one out
        assertEquals(6, Dev.DB().cdlogSummary.dropped)
    end)
end)

test("cdlog: an idle sample allocates nothing of its own (the cooldown read is the client's)", function()
    withEnv(function(env)
        local names = { "A", "B", "C", "D" }
        local shared = info(false, false, 0, 0)
        for _, n in ipairs(names) do env.tracked[n] = {}; env.infos[n] = shared end
        CdLog.Start(3600)
        for _ = 1, 5 do tick(env) end
        local n0 = #rows()
        collectgarbage("collect")
        collectgarbage("stop")
        local before = collectgarbage("count")
        for _ = 1, 500 do
            env.clock = env.clock + 0.1
            CdLog.Tick()
        end
        local grew = collectgarbage("count") - before
        collectgarbage("restart")
        assertEquals(n0, #rows())
        assertTrue(grew < 16, "idle sampling grew the heap by " .. grew .. " KB")
    end)
end)

-- ============================================================ start and stop ==

test("cdlog: Start/Stop are idempotent; events and the OnUpdate exist ONLY while recording", function()
    withEnv(function(env)
        assertEquals(0, #env.frames)                                -- nothing created before a Start
        local ok1 = CdLog.Start(60)
        assertTrue(ok1)
        local f = env.frames[1]
        assertEquals(1, #env.frames)
        assertEquals(6, f:eventCount())
        for _, e in ipairs(CdLog.EVENTS) do assertTrue(f.events[e], e) end
        assertEquals("player", f.events["UNIT_SPELLCAST_SUCCEEDED"])
        assertEquals("function", type(f:GetScript("OnUpdate")))
        local n = #rows()
        env.clock = env.clock + 5
        local ok2 = CdLog.Start(120)                                -- second start: only the deadline moves
        assertTrue(ok2)
        assertEquals(1, #env.frames)
        assertEquals(6, f:eventCount())
        assertEquals(n, #rows())
        assertTrue(near(S.endsAt, env.clock + 120))
        assertTrue(CdLog.IsRecording())
        local s1 = CdLog.Stop("off")
        assertTrue(s1)
        assertEquals(0, f:eventCount())
        assertEquals(nil, f:GetScript("OnUpdate"))
        assertEquals(nil, f:GetScript("OnEvent"))
        assertEquals(false, CdLog.IsRecording())
        local s2, why = CdLog.Stop("off")
        assertEquals(false, s2)
        assertTrue(why:find("not recording", 1, true) ~= nil)
        local count = #rows()
        CdLog.HandleEvent("PLAYER_REGEN_DISABLED")                  -- a stray event after Stop adds nothing
        assertEquals(count, #rows())
        -- a second recording reuses the frame and starts a clean buffer
        assertTrue(CdLog.Start(30))
        assertEquals(1, #env.frames)
        assertEquals(6, f:eventCount())
        assertEquals(1, #rows())
        assertEquals(nil, Dev.DB().cdlogSummary)
    end)
end)

test("cdlog: Start refuses bad seconds and clamps to MAX_SECONDS", function()
    withEnv(function(env)
        for _, bad in ipairs({ 0, -3, "abc", 0.5 }) do
            local ok = CdLog.Start(bad)
            assertEquals(false, ok)
        end
        assertEquals(false, CdLog.Start(nil))
        assertEquals(false, CdLog.IsRecording())
        assertEquals(0, #env.frames)
        assertTrue(CdLog.Start(10 ^ 9))
        assertEquals(CdLog.MAX_SECONDS, S.planned)
        assertEquals("start", rows()[1].ev); assertEquals(CdLog.MAX_SECONDS, rows()[1].seconds)
    end)
end)

test("cdlog: auto-stop at the deadline (OnUpdate tick) and by the C_Timer backup", function()
    withEnv(function(env)
        env.tracked["A"] = {}
        env.infos["A"] = info(false, false)
        CdLog.Start(10)
        assertEquals(1, #env.timers)
        assertEquals(11, env.timers[1].sec)                         -- seconds + grace
        env.clock = 109.9
        CdLog.Tick()
        assertTrue(CdLog.IsRecording())
        env.timers[1].fn()                                          -- the backup fires early: no stop
        assertTrue(CdLog.IsRecording())
        env.clock = 110
        CdLog.Tick()
        assertEquals(false, CdLog.IsRecording())
        local sm = Dev.DB().cdlogSummary
        assertEquals("done", sm.reason)
        assertEquals(10, sm.elapsed)
        assertEquals(0, env.frames[1]:eventCount())
        assertEquals(nil, env.frames[1]:GetScript("OnUpdate"))
        -- backup alone (no frame ever ticks again)
        CdLog.Start(10)
        env.clock = 125
        env.timers[#env.timers].fn()
        assertEquals(false, CdLog.IsRecording())
        assertEquals("done", Dev.DB().cdlogSummary.reason)
    end)
end)

test("cdlog: a stale backup before the deadline does not stop a newer recording", function()
    withEnv(function(env)
        CdLog.Start(10)
        local old = env.timers[#env.timers]
        CdLog.Stop("off")
        env.clock = env.clock + 3
        CdLog.Start(100)
        env.clock = env.clock + 20
        old.fn()                                                    -- old session id: ignored
        assertTrue(CdLog.IsRecording())
    end)
end)

test("cdlog: PLAYER_LOGOUT finalizes (the summary reaches SavedVariables on a reload)", function()
    withEnv(function(env)
        CdLog.Start(600)
        CdLog.HandleEvent("PLAYER_LOGOUT")
        assertEquals(false, CdLog.IsRecording())
        assertEquals("logout", Dev.DB().cdlogSummary.reason)
    end)
end)

test("cdlog: the default frame factory works on the sim's real frames (script + events on, then off)", function()
    withEnv(function()
        CdLog.createFrame = REAL.createFrame
        assertTrue(CdLog.Start(30))
        local f = S.frame
        assertTrue(f ~= nil)
        assertEquals("function", type(f:GetScript("OnUpdate")))
        assertTrue(f:IsEventRegistered("PLAYER_REGEN_DISABLED"))
        assertTrue(f:IsEventRegistered("START_AUTOREPEAT_SPELL"))
        assertTrue(CdLog.Stop("off"))
        assertEquals(nil, f:GetScript("OnUpdate"))
        assertEquals(false, f:IsEventRegistered("PLAYER_REGEN_DISABLED") and true or false)
    end)
end)

-- ================================================================== summary ==

local function row(t, name, active, gcd, extra)
    local r = { t = t, ev = "cd", name = name, active = active, gcd = gcd, enabled = true, secretNumbers = false,
        combat = false }
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
end

test("cdlog: summary maths on a synthetic stream (wand-like periods, censored, open, secret)", function()
    local stream = {
        { t = 0, ev = "start", seconds = 60 },
        row(0, "Shoot", false, false, { base = true }),
        row(1.00, "Shoot", true, false), row(1.50, "Shoot", false, false),     -- 0.5
        row(3.00, "Shoot", true, false), row(3.60, "Shoot", false, false),     -- 0.6
        row(5.00, "Shoot", true, false), row(6.00, "Shoot", false, false),     -- 1.0
        row(7.00, "Shoot", true, false), row(8.50, "Shoot", false, false),     -- 1.5
        row(9.00, "Shoot", true, false),                                       -- open, 1.0 at tEnd 10
        row(0, "Aimed Shot", false, false, { base = true }),
        row(2.00, "Aimed Shot", true, true), row(3.50, "Aimed Shot", false, false),  -- a GCD: not counted
        row(0, "Auto Shot", true, false, { base = true }),                     -- already running at the baseline
        row(2.00, "Auto Shot", false, false),
        row(0, "Rapid Fire", false, false, { base = true, secretNumbers = true }),
        { t = 4.0, ev = "cast", name = "Shoot", combat = false },
        { t = 10, ev = "stop", reason = "done" },
    }
    local sm = CdLog.Summarize(stream, { planned = 60, reason = "done", dropped = 3 })
    local sh = sm.spells["Shoot"]
    assertEquals(8 + 1, sh.changes)
    assertEquals(4, sh.periods)
    assertEquals(0.5, sh.min); assertEquals(0.8, sh.median); assertEquals(1.5, sh.max)
    assertEquals(1.5, sh.longest)
    assertEquals(true, sh.open)
    assertEquals(false, sh.secretNumbers)
    local ai = sm.spells["Aimed Shot"]
    assertEquals(2, ai.changes); assertEquals(0, ai.periods); assertEquals(nil, ai.min)
    local au = sm.spells["Auto Shot"]
    assertEquals(0, au.periods); assertEquals(1, au.censored); assertEquals(2, au.longest); assertEquals(false, au.open)
    assertEquals(true, sm.spells["Rapid Fire"].secretNumbers)
    assertEquals(0, sm.spells["Rapid Fire"].changes)
    assertEquals(3, sm.dropped)
    assertEquals(4, sm.spellCount)
    assertEquals(#stream, sm.rows)
    assertEquals(1, sm.rowCounts.cast); assertEquals(1, sm.rowCounts.start)
    assertEquals(0, sm.flipMoments)
    assertEquals(10, sm.ended)
end)

test("cdlog: an odd number of periods takes the middle one; a single period is its own median", function()
    local s = { row(0, "X", false, false, { base = true }),
        row(1, "X", true, false), row(1.2, "X", false, false),
        row(2, "X", true, false), row(2.9, "X", false, false),
        row(4, "X", true, false), row(4.4, "X", false, false) }
    local x = CdLog.Summarize(s, {}).spells["X"]
    assertEquals(3, x.periods); assertEquals(0.2, x.min); assertEquals(0.4, x.median); assertEquals(0.9, x.max)
    local one = CdLog.Summarize({ row(0, "Y", false, false, { base = true }), row(1, "Y", true, false),
        row(1.25, "Y", false, false) }, {}).spells["Y"]
    assertEquals(1, one.periods); assertEquals(0.25, one.median); assertEquals(0.25, one.min)
    local none = CdLog.Summarize({}, {})
    assertEquals(0, none.rows); assertEquals(0, none.spellCount); assertEquals(0, none.flipMoments)
end)

test("cdlog: 'all spells flipped together' = >= 4 distinct spells flipping `active` within 50 ms", function()
    local names = { "A", "B", "C", "D", "E", "F" }
    local s = {}
    for _, n in ipairs(names) do s[#s + 1] = row(0, n, false, false, { base = true }) end
    for i = 1, 4 do s[#s + 1] = row(20.00, names[i], true, false) end                  -- moment 1: 4 at once
    for i = 1, 3 do s[#s + 1] = row(30.00, names[i], false, false) end                 -- only 3: no moment
    for i = 1, 3 do s[#s + 1] = row(40.00, names[i], true, false) end                  -- moment 2: 3 spells ...
    for i = 5, 6 do s[#s + 1] = row(40.04, names[i], true, false) end                  -- ... + 2 inside 50 ms
    for i = 1, 2 do s[#s + 1] = row(50.00, names[i], false, false) end                 -- 2 + 2, 100 ms apart: none
    for i = 3, 4 do s[#s + 1] = row(50.10, names[i], false, false) end
    local sm = CdLog.Summarize(s, {})
    assertEquals(2, sm.flipMoments)
    -- a row that changes only the duration (active unchanged) is not a flip
    local t = {}
    for _, n in ipairs(names) do t[#t + 1] = row(0, n, true, false, { base = true }) end
    for i = 1, 6 do t[#t + 1] = row(5, names[i], true, false, { dur = 3 }) end
    assertEquals(0, CdLog.Summarize(t, {}).flipMoments)
    -- 3 spells flipping in the same instant twice is still < 4 distinct
    local u = {}
    for i = 1, 3 do u[#u + 1] = row(0, names[i], false, false, { base = true }) end
    for i = 1, 3 do u[#u + 1] = row(1, names[i], true, false) end
    for i = 1, 3 do u[#u + 1] = row(1.02, names[i], false, false) end
    assertEquals(0, CdLog.Summarize(u, {}).flipMoments)
end)

test("cdlog: the wand pattern end to end (Shoot active & not GCD for ~0.5 s, GCD spell beside it)", function()
    withEnv(function(env)
        env.tracked["Arcane Shot"] = {}
        env.infos["Shoot"] = info(false, false)
        env.infos["Arcane Shot"] = info(false, false)
        CdLog.Start(60)
        tick(env)
        for _ = 1, 3 do
            env.infos["Shoot"] = info(true, false, 0.6, env.clock)
            env.infos["Arcane Shot"] = info(true, true, 1.5, env.clock)
            for _ = 1, 5 do tick(env) end
            env.infos["Shoot"] = info(false, false)
            env.infos["Arcane Shot"] = info(false, false)
            for _ = 1, 10 do tick(env) end
        end
        assertTrue(CdLog.Stop("off"))
        local sm = Dev.DB().cdlogSummary
        assertEquals(3, sm.spells["Shoot"].periods)
        assertTrue(near(sm.spells["Shoot"].median, 0.5), "median " .. tostring(sm.spells["Shoot"].median))
        assertEquals(0, sm.spells["Arcane Shot"].periods)
        assertEquals(6, sm.spells["Shoot"].changes)
        assertEquals(6, sm.spells["Arcane Shot"].changes)
        assertTrue(sm.flipMoments == 0)                             -- two spells only
        assertEquals(false, sm.spells["Shoot"].secretNumbers)
    end)
end)

test("cdlog: 4+ spells flipping in one sample is counted as a together-moment by the live recorder", function()
    withEnv(function(env)
        for _, n in ipairs({ "A", "B", "C", "D", "E" }) do
            env.tracked[n] = {}
            env.infos[n] = info(false, false)
        end
        CdLog.Start(60)
        tick(env)
        for _, n in ipairs({ "A", "B", "C", "D", "E" }) do env.infos[n] = info(true, true, 1.5, env.clock) end
        tick(env)
        for _ = 1, 15 do tick(env) end
        for _, n in ipairs({ "A", "B", "C", "D", "E" }) do env.infos[n] = info(false, false) end
        tick(env)
        CdLog.Stop("off")
        local sm = Dev.DB().cdlogSummary
        assertEquals(2, sm.flipMoments)
        assertEquals(5, sm.spellCount)
        assertEquals("table", type(sm.spells["A"]))
    end)
end)

test("cdlog: Stop stores a summary of plain data and Status() reads it", function()
    withEnv(function(env)
        assertTrue(CdLog.Status():find("no summary yet", 1, true) ~= nil)
        env.tracked["A"] = {}
        env.infos["A"] = info(false, false)
        CdLog.Start(60)
        tick(env)
        env.infos["A"] = info(true, false, 1, env.clock)
        tick(env)
        env.infos["A"] = info(false, false)
        tick(env)
        local ok, line = CdLog.Stop("off")
        assertTrue(ok)
        assertTrue(line:find("idle; last", 1, true) ~= nil, line)
        assertTrue(line:find("A x1", 1, true) ~= nil, line)
        assertEquals(line, CdLog.Status())
        local sm = Dev.DB().cdlogSummary
        local function plain(t, path)
            for k, v in pairs(t) do
                local ty = type(v)
                if ty == "table" then plain(v, path .. "." .. tostring(k))
                else assertTrue(ty == "string" or ty == "number" or ty == "boolean", path .. "." .. tostring(k)) end
            end
        end
        plain(sm, "cdlogSummary")
        assertEquals(1, sm.v)
        assertEquals("number", type(sm.wall))
        assertEquals("string", type(sm.stamp))
    end)
end)

-- ==================================================================== panel ==

test("cdlog: the panel shows `cdlog: recording N s left, M rows` only while recording", function()
    withEnv(function(env)
        assertEquals(nil, Dev.Panel.Text():find("cdlog: recording", 1, true))
        CdLog.Start(312)
        for _ = 1, 56 do CdLog.HandleEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 1) end
        assertEquals(57, #rows())
        local text = Dev.Panel.Text()
        assertTrue(text:find("cdlog: recording 312 s left, 57 rows", 1, true) ~= nil, text)
        env.clock = env.clock + 12.2
        assertTrue(Dev.Panel.Text():find("cdlog: recording 300 s left, 57 rows", 1, true) ~= nil)
        CdLog.Stop("off")
        assertEquals(nil, Dev.Panel.Text():find("cdlog: recording", 1, true))
        assertEquals(nil, CdLog.PanelLine())
    end)
end)

test("cdlog: the panel line is clipped and escaped like the other lines", function()
    withEnv(function()
        local saved = CdLog.PanelLine
        CdLog.PanelLine = function() return "cdlog: |cffff0000" .. string.rep("x", 300) end
        local text = Dev.Panel.Text()
        CdLog.PanelLine = saved
        assertTrue(text:find("||cffff0000", 1, true) ~= nil, "pipes escaped")
        assertEquals(nil, text:find(string.rep("x", 120), 1, true))
    end)
end)

test("cdlog: the repaint while recording happens at REPAINT_SECONDS, not every sample", function()
    withEnv(function(env)
        CdLog.Start(600)
        local f = env.frames[1]
        local paints = 0
        local real = Dev.Repaint
        Dev.Repaint = function() paints = paints + 1 end
        local onUpdate = f:GetScript("OnUpdate")
        for _ = 1, 30 do onUpdate(f, 0.1); env.clock = env.clock + 0.1 end    -- 3 s of frames
        Dev.Repaint = real
        assertEquals(1, paints)
    end)
end)

-- ================================================ DevCommands / the verb ==

test("cdlog: argument parsing", function()
    local function p(s) local k, v = CdLog.ParseArg(s); return k, v end
    local k, v = p("600"); assertEquals("start", k); assertEquals(600, v)
    k, v = p("  45  "); assertEquals("start", k); assertEquals(45, v)
    k, v = p("12.5"); assertEquals("start", k); assertEquals(12.5, v)
    k, v = p("3600"); assertEquals("start", k); assertEquals(3600, v)
    assertEquals("off", (p("off")))
    assertEquals("status", (p("status")))
    assertEquals("status", (p("")))
    assertEquals("status", (p(nil)))
    for _, bad in ipairs({ "0", "3601", "99999", "abc", "600 x", "-5", "off now", "1e3", "on" }) do
        k, v = p(bad)
        assertEquals(nil, k, bad)
        assertEquals("string", type(v))
    end
end)

test("cdlog: /fxdev cdlog and the DevCommands entries `cdlog 600` / `cdlog off` through the dispatcher", function()
    withEnv(function(env)
        local ok, d = Dev.Dispatch("cdlog 600")
        assertTrue(ok, d)
        assertTrue(CdLog.IsRecording())
        assertTrue(d:find("recording 600 s left", 1, true) ~= nil, d)
        ok, d = Dev.Dispatch("CDLOG Status")
        assertTrue(ok)
        assertTrue(d:find("recording", 1, true) ~= nil, d)
        ok, d = Dev.Dispatch("cdlog off")
        assertTrue(ok, d)
        assertEquals(false, CdLog.IsRecording())
        ok, d = Dev.Dispatch("cdlog off")
        assertTrue(ok, d)
        assertTrue(d:find("not recording", 1, true) ~= nil)
        ok, d = Dev.Dispatch("cdlog bogus")
        assertEquals(false, ok)
        assertTrue(d:find("cdlog [seconds|off|status]", 1, true) ~= nil, d)
        ok, d = Dev.Dispatch("cdlog 0")
        assertEquals(false, ok)
        assertEquals(false, CdLog.IsRecording())
        -- the runner: once per load, recorded in ForteDevDB.commands
        _G.ForteDevCommands = { "cdlog 600" }
        local okRun = Dev.RunCommands(true)
        assertTrue(okRun)
        assertTrue(CdLog.IsRecording())
        local cmd = Dev.DB().commands[#Dev.DB().commands]
        assertEquals("cdlog 600", cmd.verb); assertEquals(true, cmd.ok)
        _G.ForteDevCommands = { "cdlog off" }
        Dev.RunCommands(true)
        assertEquals(false, CdLog.IsRecording())
        assertEquals(true, Dev.DB().commands[#Dev.DB().commands].ok)
        assertTrue(Dev.USAGE:find("cdlog", 1, true) ~= nil)
    end)
end)

test("cdlog: in combat only off/status are accepted; a start is refused", function()
    withEnv(function()
        _G.InCombatLockdown = function() return true end
        local ok, d = Dev.Dispatch("cdlog 600")
        assertEquals(false, ok)
        assertTrue(d:find("refused in combat", 1, true) ~= nil, d)
        assertEquals(false, CdLog.IsRecording())
        _G.InCombatLockdown = function() return false end
        assertTrue(Dev.Dispatch("cdlog 600"))
        _G.InCombatLockdown = function() return true end
        assertTrue(Dev.Dispatch("cdlog status"))
        assertTrue(Dev.Dispatch("cdlog"))
        assertTrue(Dev.Dispatch("cdlog off"))
        assertEquals(false, CdLog.IsRecording())
    end)
end)

-- ==================================================================== safety ==

test("cdlog: safety - no chat, no addon message, nothing gameplay through a whole recording", function()
    local TRIP = { "SendChatMessage", "SendAddonMessage", "CastSpellByName", "CastSpellByID", "UseAction",
        "TargetUnit", "AssistUnit", "RunMacro", "RunMacroText", "JumpOrAscendStart", "MoveForwardStart",
        "UseContainerItem", "StartAttack", "ReloadUI", "Screenshot" }
    local saved, hits = {}, {}
    local function trip(n) return function() hits[#hits + 1] = n end end
    for _, n in ipairs(TRIP) do saved[n] = _G[n]; _G[n] = trip(n) end
    local chat = _G.C_ChatInfo
    local savedSend = chat and chat.SendAddonMessage
    if chat then chat.SendAddonMessage = trip("C_ChatInfo.SendAddonMessage") end
    local cf = _G.DEFAULT_CHAT_FRAME
    local savedAdd = cf and cf.AddMessage
    if cf then cf.AddMessage = trip("DEFAULT_CHAT_FRAME.AddMessage") end
    withEnv(function(env)
        env.tracked["A"] = {}
        env.infos["A"] = info(false, false)
        CdLog.Start(5)
        for i = 1, 20 do
            env.infos["A"] = info(i % 2 == 0, false, 1, env.clock)
            tick(env)
        end
        CdLog.HandleEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 5019)
        CdLog.HandleEvent("START_AUTOREPEAT_SPELL")
        CdLog.HandleEvent("PLAYER_REGEN_DISABLED")
        env.clock = env.clock + 10
        CdLog.Tick()                                                -- the auto-stop
        assertEquals(false, CdLog.IsRecording())
    end)
    for _, n in ipairs(TRIP) do _G[n] = saved[n] end
    if chat then chat.SendAddonMessage = savedSend end
    if cf then cf.AddMessage = savedAdd end
    assertEquals(0, #hits, "hit: " .. table.concat(hits, ","))
end)

test("cdlog: the recorder never registers an event at file load (no frame, no events before a Start)", function()
    assertEquals(false, S.recording)
    assertEquals(nil, S.frame)
end)

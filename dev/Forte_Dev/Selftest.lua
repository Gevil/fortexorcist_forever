-- Forte_Dev/Selftest.lua
-- The selftest runner: an assertion API (T.check / T.eq / T.truthy / T.skip ...), per-check pcall
-- isolation, per-run caps, results into ForteDevDB.runs.
--
--   Suites: "ooc"    every suite registered with group "ooc" -- safe out of combat, runs at once;
--           "combat" ARMS the combat suite: it runs Dev.COMBAT_DELAY seconds after
--                    PLAYER_REGEN_DISABLED (the owner makes the combat; this file never does);
--           "all"    ooc now + arm the combat suite.
--
-- A check body is `function(T) ... end` run under pcall. T.eq / T.truthy / T.fail raise a tagged
-- table, T.skip raises a skip tag, any other error is recorded as `raise: ...`. A live API value is
-- never compared raw: pass it through Dev.plain / Dev.K first (T.eq refuses a secret `actual` and
-- records "SECRET"). The detail of every result is a clipped PLAIN string.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
local Dev = FX.Dev

local S = {}
Dev.Selftest = S

local FAIL, SKIP = {}, {}   -- error tags (unique tables)

local function raiseFail(msg) error({ tag = FAIL, msg = msg }, 0) end

--- Build the assertion object bound to one run.
local function makeT(run)
    local T = {}
    local note

    local function record(name, status, detail)
        run[status] = run[status] + 1
        local tests = run.tests
        local fails = run._failRecorded
        local keep = #tests < Dev.MAX_TESTS and (status ~= "fail" or fails < Dev.MAX_FAILS)
        if status == "fail" and keep then run._failRecorded = fails + 1 end
        if keep then
            tests[#tests + 1] = {
                name = Dev.clip(name, Dev.NAME_MAX),
                status = status,
                detail = Dev.clip(detail or "", Dev.DETAIL_MAX),
            }
        else
            run.dropped = run.dropped + 1
        end
    end
    T.record = record

    --- One named check: fn(T) under pcall; the outcome is recorded, never propagated.
    function T.check(name, fn)
        note = nil
        local ok, err = pcall(fn, T)
        if ok then
            record(name, "pass", note)
        elseif Dev.isSecret(err) then
            record(name, "fail", "raise: SECRET")
        elseif type(err) == "table" and err.tag == FAIL then
            record(name, "fail", err.msg)
        elseif type(err) == "table" and err.tag == SKIP then
            record(name, "skip", err.msg)
        else
            record(name, "fail", "raise: " .. Dev.S(err))
        end
        note = nil
    end

    function T.fail(msg) raiseFail(Dev.clip(msg or "failed")) end
    function T.skip(reason) error({ tag = SKIP, msg = Dev.clip(reason or "skipped") }, 0) end
    --- Detail text for a PASSING check.
    function T.note(text) note = Dev.clip(text) end

    function T.eq(actual, expected, what)
        if Dev.isSecret(actual) then
            raiseFail(Dev.clip((what or "eq") .. ": SECRET value (not compared)"))
        end
        if actual ~= expected then
            raiseFail(Dev.clip(string.format("%s: expected %s got %s", what or "eq", Dev.S(expected, 60),
                Dev.S(actual, 60))))
        end
    end

    function T.truthy(v, what)
        if Dev.isSecret(v) then raiseFail(Dev.clip((what or "truthy") .. ": SECRET value (not tested)")) end
        if not v then raiseFail(Dev.clip((what or "expected a truthy value") .. " (got " .. Dev.S(v, 40) .. ")")) end
    end

    function T.falsy(v, what)
        if Dev.isSecret(v) then raiseFail(Dev.clip((what or "falsy") .. ": SECRET value (not tested)")) end
        if v then raiseFail(Dev.clip((what or "expected a falsy value") .. " (got " .. Dev.S(v, 40) .. ")")) end
    end

    return T
end

-- --------------------------------------------------------------- the runs --

local function newRun(label, combat)
    local db = Dev.DB()
    db.runId = db.runId + 1
    return {
        id = db.runId,
        stamp = Dev.stamp(),
        build = db.build,
        suite = label,
        started = Dev.now(),
        finished = 0,
        combat = combat and true or false,
        pass = 0, fail = 0, skip = 0,
        tests = {},
        dropped = 0,
        _failRecorded = 0,
    }
end

--- Run an explicit suite list (the registered ones, or a test's own). Returns the finished run, or
--- nil + reason. The run is stored in ForteDevDB.runs.
function S.RunList(list, label)
    local st = Dev.state
    if st.running then return nil, "a run is already in progress" end
    st.running = true
    Dev.Repaint()
    local run = newRun(label, Dev.inCombat())
    local T = makeT(run)
    local ok, err = pcall(function()
        for _, suite in ipairs(list) do
            local okSuite, errSuite = pcall(suite.fn, T)
            if not okSuite then
                local msg = Dev.isSecret(errSuite) and "SECRET"
                    or (type(errSuite) == "table" and errSuite.msg) or errSuite
                T.record("suite " .. tostring(suite.name), "fail", "suite raised: " .. Dev.S(msg))
            end
        end
    end)
    if not ok then T.record("runner", "fail", "runner raised: " .. Dev.S(err)) end
    run.finished = Dev.now()
    run._failRecorded = nil
    Dev.AddRun(run)
    st.lastRun = run
    st.finished = true
    st.running = false
    Dev.Repaint()
    return run
end

local function suitesOf(group)
    local out = {}
    for _, suite in ipairs(Dev.suites) do
        if suite.group == group then out[#out + 1] = suite end
    end
    return out
end

--- Run every registered suite of `group` under the label `label`.
function S.RunGroup(group, label)
    if group == "ooc" and Dev.inCombat() then return nil, "refused in combat" end
    return S.RunList(suitesOf(group), label or group)
end

function S.Summary(run)
    return string.format("run #%d %s pass=%d fail=%d skip=%d%s", run.id, run.suite, run.pass, run.fail,
        run.skip, run.combat and " (in combat)" or "")
end

-- ---------------------------------------------------------- combat arming --

function S.Arm()
    local st = Dev.state
    st.armed = true
    st.castRing = {}
    local f = Dev.frame
    if f then pcall(f.RegisterUnitEvent, f, "UNIT_SPELLCAST_SUCCEEDED", "player") end
    if Dev.inCombat() then S.OnCombatStart() end
    Dev.Repaint()
end

function S.Disarm()
    local st = Dev.state
    st.armed = false
    local f = Dev.frame
    if f then pcall(f.UnregisterEvent, f, "UNIT_SPELLCAST_SUCCEEDED") end
end

--- PLAYER_REGEN_DISABLED while armed (or arming while already in combat): run the suite after the delay.
function S.OnCombatStart()
    local st = Dev.state
    if not st.armed or st.combatTimerSet then return end
    st.combatTimerSet = true
    Dev.After(Dev.COMBAT_DELAY, function()
        st.combatTimerSet = false
        S.RunArmed()
    end)
end

--- Passive capture of the own cast spell ids while armed: K strings only, never a raw value.
function S.OnOwnCast(spellID)
    local ring = Dev.state.castRing
    if not ring then return end
    ring[#ring + 1] = Dev.K(spellID)
    while #ring > 20 do table.remove(ring, 1) end
end

--- The armed combat suite fires (once; the owner re-arms with `selftest combat`).
function S.RunArmed()
    local st = Dev.state
    if not st.armed then return nil end
    S.Disarm()
    return S.RunGroup("combat", "combat")
end

-- ------------------------------------------------------------ the request --

--- `selftest <which>` from the dispatcher. Returns (ok, detail).
function S.Request(which)
    if which == "combat" then
        S.Arm()
        return true, "combat suite armed: it runs " .. Dev.COMBAT_DELAY .. " s after combat starts"
    end
    local run, why = S.RunGroup("ooc", which)
    if not run then return false, why end
    local text = S.Summary(run)
    if which == "all" then
        S.Arm()
        text = text .. "; combat suite armed"
    end
    return true, text
end

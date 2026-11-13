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
--
-- ASYNC STEPS. A suite function may queue work that spans frames: T.step(fn) (a synchronous step that
-- runs in order, fn may call T.check) and T.async(name, timeout, begin) (a check that completes later).
-- The suite function returns at once; the runner then walks the queue step by step and only starts the
-- next step (and the next suite) when the previous one has finished. `begin(settle)` starts the work and
-- calls settle(body) from a C_Timer / OnUpdate callback: body is run like a T.check body under `name`
-- (settle() with no body records nothing). begin may return a cleanup function; when `timeout` seconds
-- pass without settle the cleanup runs and `name` is recorded as a FAIL ("timeout"). The run is stored
-- (ForteDevDB.runs), the beacon's "finished" cell and Dev.state.finished only after the last step.
--

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

    --- Attach a small plain-data table to the run result (ForteDevDB.runs[n][key]), e.g. the motion
    --- suite's CPU numbers. Refuses a key the run already uses (id, tests, pass ...).
    function T.attach(key, value)
        if type(key) ~= "string" or run[key] ~= nil then error("T.attach: key '" .. tostring(key) .. "' is taken", 2) end
        run[key] = value
    end

    --- Queue a synchronous step: fn(T) runs in order, after every earlier step has finished, and may
    --- call T.check. Only valid while a suite function (or one of its steps) runs. A raise is recorded.
    function T.step(fn)
        local q = T._queue
        q[#q + 1] = function(done)
            local ok, err = pcall(fn, T)
            if not ok then
                record("step", "fail", "step raised: " .. (Dev.isSecret(err) and "SECRET"
                    or Dev.S(type(err) == "table" and err.msg or err)))
            end
            done()
        end
    end

    --- Queue a check that completes later: begin(settle) starts it (see the header). Exactly one
    --- outcome is recorded: the settled body, a raise of begin, or the timeout FAIL.
    function T.async(name, timeout, begin)
        local q = T._queue
        q[#q + 1] = function(done)
            local settled, cleanup = false, nil
            local function settle(body)
                if settled then return end
                settled = true
                if type(body) == "function" then T.check(name, body) end
                done()
            end
            local ok, res = pcall(begin, settle)
            if ok then
                cleanup = res
            elseif not settled then
                settled = true
                record(name, "fail", "raise: " .. (Dev.isSecret(res) and "SECRET" or Dev.S(res)))
                done()
            end
            if settled then return end
            Dev.After(timeout, function()
                if settled then return end
                settled = true
                if type(cleanup) == "function" then pcall(cleanup) end
                record(name, "fail", "timeout: not finished after " .. tostring(timeout) .. " s")
                done()
            end)
        end
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

    --- Live geometry compare: |actual - expected| <= tol (default Dev.GEOM_TOL, 0.5 UI unit). The failure
    --- detail prints 4 decimals (Dev.S rounds to 6 significant digits, which hides 95.99999 as "96").
    function T.near(actual, expected, what, tol)
        tol = tol or Dev.GEOM_TOL
        local label = what or "near"
        if Dev.isSecret(actual) then
            raiseFail(Dev.clip(label .. ": SECRET value (not compared)"))
        end
        if type(actual) ~= "number" then
            raiseFail(Dev.clip(string.format("%s: expected %.4f got %s", label, expected, Dev.S(actual, 40))))
        end
        if not Dev.near(actual, expected, tol) then
            raiseFail(Dev.clip(string.format("%s: expected %.4f got %.4f (diff %.4f, tol %.2f)", label, expected,
                actual, actual - expected, tol)))
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

--- Run `items` in order: runItem(item, done), where done() may be called inline or from a later
--- callback; the next item starts only after done(). Inline completions loop (no recursion), so only a
--- late done() re-enters. `items` may grow while it is walked (a step may queue another step).
local function sequence(items, runItem, onDone)
    local i = 0
    local function walk()
        while true do
            i = i + 1
            local item = items[i]
            if item == nil then onDone() return end
            local inline, finished = true, false
            runItem(item, function()
                if finished then return end
                finished = true
                if not inline then walk() end
            end)
            inline = false
            if not finished then return end
        end
    end
    walk()
end

--- Run an explicit suite list (the registered ones, or a test's own) under the label `label`.
--- Returns (run, pending): `pending` is true while async steps of a suite are still queued -- the run
--- is then stored in ForteDevDB.runs (and `onDone(run)` called, `Dev.state.finished` set) only when the
--- last step has finished; the returned run keeps filling until then. nil + reason when refused.
function S.RunList(list, label, onDone)
    local st = Dev.state
    if st.running then return nil, "a run is already in progress" end
    st.running = true
    Dev.Repaint()
    local run = newRun(label, Dev.inCombat())
    local T = makeT(run)
    local complete = false
    local function finish()
        if complete then return end
        complete = true
        run.finished = Dev.now()
        run._failRecorded = nil
        T._queue = nil
        Dev.AddRun(run)
        st.lastRun = run
        st.finished = true
        st.running = false
        Dev.Repaint()
        if onDone then pcall(onDone, run) end
    end
    local ok, err = pcall(sequence, list, function(suite, doneSuite)
        local queue = {}
        T._queue = queue
        local okSuite, errSuite = pcall(suite.fn, T)
        if not okSuite then
            local msg = Dev.isSecret(errSuite) and "SECRET"
                or (type(errSuite) == "table" and errSuite.msg) or errSuite
            T.record("suite " .. tostring(suite.name), "fail", "suite raised: " .. Dev.S(msg))
        end
        sequence(queue, function(step, doneStep) step(doneStep) end, doneSuite)
    end, finish)
    if not ok then
        T.record("runner", "fail", "runner raised: " .. Dev.S(err))
        finish()
    end
    return run, not complete
end

local function suitesOf(group)
    local out = {}
    for _, suite in ipairs(Dev.suites) do
        if suite.group == group then out[#out + 1] = suite end
    end
    return out
end

--- Run every registered suite of `group` under the label `label`. Returns (run, pending) like RunList.
function S.RunGroup(group, label, onDone)
    if group == "ooc" and Dev.inCombat() then return nil, "refused in combat" end
    return S.RunList(suitesOf(group), label or group, onDone)
end

function S.Summary(run, pending)
    return string.format("run #%d %s pass=%d fail=%d skip=%d%s%s", run.id, run.suite, run.pass, run.fail,
        run.skip, run.combat and " (in combat)" or "", pending and " so far (async steps still running)" or "")
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

--- The armed combat suite fires (once; the owner re-arms with `selftest combat`). A run still in flight
--- (async steps of an ooc run) holds it back: it retries every second until that run has finished.
function S.RunArmed()
    local st = Dev.state
    if not st.armed then return nil end
    if st.running then
        Dev.After(1, S.RunArmed)
        return nil, "deferred: a run is in progress"
    end
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
    local run, second = S.RunGroup("ooc", which)
    if not run then return false, second end
    local text = S.Summary(run, second == true)
    if which == "all" then
        S.Arm()
        text = text .. "; combat suite armed"
    end
    return true, text
end

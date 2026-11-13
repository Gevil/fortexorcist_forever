-- Forte_Dev/Suites/Motion.lua
-- The motion suite (ooc group, async): do the displays MOVE on every rendered frame on the REAL client?
-- The shipped passes (Forte_Cooldown Display:Motion via Module._renderFrame, Forte_Timer D:MotionPass on
-- its anchor, Forte_Hunter Swing _MotionPass on its anchor) are driven by an OnUpdate script each; this
-- suite measures what the client actually renders, WITHOUT wrapping or changing any production function:
--   1. motion: frame pacing        a shown 1x1 frame's OnUpdate for PACING_SECONDS: frames, mean fps and
--                                  min / 95th percentile / max frame ms (bucket counts, no table growth)
--   2. one shared window           the demo (FX.TestMode: synthetic cooldown, spell timer and swing rows)
--                                  is started if it is not already running, WARM_SECONDS later every
--                                  display is sampled for SAMPLE_SECONDS from ONE OnUpdate; the demo is
--                                  then put back as it was and the displays' idle OnUpdate scripts are
--                                  awaited (IDLE_WAIT_SECONDS at most)
--      motion: cooldown bar moves every frame   icon GetPoint x/y of the first slots
--      motion: spell timer moves every frame    Display.counts.motionPass + row bar value / fill width
--      motion: swing bar moves every frame      spark GetPoint x, fill GetWidth (and GetValue when the
--                                               engine fill owns the animation)   [Hunter only]
--      An element "moved" on a frame when its observable differs from the previous frame's. PASS when
--      the best element moved on >= MIN_RATIO of the frames it could be compared on (a hitch frame may
--      repeat a value; a row parked beyond Max does not move, so the best of several elements counts).
--   3. motion: addon CPU           informational: the client's own profiler (C_AddOnProfiler recent-average time)
--                                  for every loaded Forte_* add-on, read (a) before the demo and (b) at the end
--                                  of the sampling window with it running; SKIP with the reason when unavailable.
-- Every client read is pcall'd and classified; the per-frame path allocates nothing (preallocated arrays,
-- no closures, no tables). Wall time: ~5 s nominal (2 + 0.5 + 1.5 + <= 1), every async step has a hard timeout.
--
-- Test seams (dev/Forte_Dev/tests/test_motion.lua replaces them): M.after, M.newDriver, M.buildTargets,
-- M.testMode, M.getFramerate, M.profilerApi, M.loadedForteAddOns.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
local Dev = FX.Dev

local M = {}
Dev.Motion = M

M.PACING_SECONDS = 2
M.WARM_SECONDS = 0.5
M.SAMPLE_SECONDS = 1.5
M.IDLE_WAIT_SECONDS = 1
M.IDLE_POLL_SECONDS = 0.1
M.PACING_TIMEOUT = 3.5      -- hard timeouts (a C_Timer that never fires still ends the run)
M.WINDOW_TIMEOUT = 4.5
M.MIN_RATIO = 0.9
M.MAX_ELEMENTS = 8          -- observed elements per display
M.BUCKET_MS = 0.5           -- frame-time histogram: 0.5 ms buckets up to 100 ms, one overflow bucket
M.BUCKETS = 200

M.ORDER = { "cooldown", "timer", "swing" }
M.TEST_NAMES = {
    cooldown = "motion: cooldown bar moves every frame",
    timer = "motion: spell timer moves every frame",
    swing = "motion: swing bar moves every frame",
}
M.METRIC_UNIT = "ms"        -- the unit of C_AddOnProfiler metric values (see the addon CPU section): "ms" | "ticks"

--- A plain finite number, or nil (a secret, NaN, nil or a non-number).
local function plainNum(v)
    if type(v) ~= "number" then return nil end
    if Dev.isSecret(v) then return nil end
    if v ~= v then return nil end
    return v
end

local function enabled(name)
    local e = FX._enabledModules
    return type(e) == "table" and e[name] and true or false
end

--- True when `frame` has an OnUpdate script, false when it has none, nil when it cannot be read.
local function hasUpdateScript(frame)
    if type(frame) ~= "table" or type(frame.GetScript) ~= "function" then return nil end
    local ok, script = pcall(frame.GetScript, frame, "OnUpdate")
    if not ok then return nil end
    return script ~= nil
end

-- ------------------------------------------------------------------- seams --

--- Timer seam (Dev.After at call time, so a test that swaps Dev.After drives this too).
function M.after(seconds, fn) Dev.After(seconds, fn) end

function M.testMode() return FX.TestMode end

--- GetFramerate() as a plain number, nil when unavailable.
function M.getFramerate()
    local f = _G.GetFramerate
    if type(f) ~= "function" then return nil end
    local ok, v = pcall(f)
    return ok and plainNum(v) or nil
end

--- The per-frame driver: ONE shown 1x1 anchored frame (created once), OnUpdate = onFrame(elapsed) with
--- `elapsed` a plain number or nil. Returns { Stop = function } which removes the script and hides it.
function M.newDriver(onFrame)
    local f = M.frame
    if not f then
        f = _G.CreateFrame("Frame", nil, _G.UIParent)
        f:SetSize(1, 1)
        f:SetPoint("BOTTOMLEFT", _G.UIParent, "BOTTOMLEFT", 0, 0)
        M.frame = f
    end
    f:Show()
    f:SetScript("OnUpdate", function(_, elapsed) onFrame(plainNum(elapsed)) end)
    return { Stop = function()
        f:SetScript("OnUpdate", nil)
        f:Hide()
    end }
end

-- ----------------------------------------------------------- frame pacing --

function M.NewPacing()
    local p = { n = 0, sum = 0, min = math.huge, max = 0, b = {} }
    for i = 1, M.BUCKETS + 1 do p.b[i] = 0 end
    return p
end

--- One frame of `elapsed` seconds. No allocation.
function M.PacingAdd(p, elapsed)
    local ms = elapsed * 1000
    p.n = p.n + 1
    p.sum = p.sum + elapsed
    if ms < p.min then p.min = ms end
    if ms > p.max then p.max = ms end
    local i = math.floor(ms / M.BUCKET_MS) + 1
    if i < 1 then i = 1 elseif i > M.BUCKETS + 1 then i = M.BUCKETS + 1 end
    p.b[i] = p.b[i] + 1
end

--- n, mean fps, min ms, 95th-percentile ms, max ms (n = 0: nils). The percentile is the upper edge of the
--- bucket holding the 95th-percentile frame, clamped into [min, max].
function M.PacingStats(p)
    if p.n == 0 or p.sum <= 0 then return p.n end
    local need = math.ceil(p.n * 0.95)
    local cum, p95 = 0, p.max
    for i = 1, M.BUCKETS + 1 do
        cum = cum + p.b[i]
        if cum >= need then
            p95 = math.min(math.max(i * M.BUCKET_MS, p.min), p.max)
            break
        end
    end
    return p.n, p.n / p.sum, p.min, p95, p.max
end

function M.PacingDetail(p, framerate)
    local n, fps, mn, p95, mx = M.PacingStats(p)
    return string.format("%d frames in %.1f s: mean %.1f fps; frame ms min %.1f p95 %.1f max %.1f; GetFramerate %s",
        n, p.sum, fps, mn, p95, mx, framerate and string.format("%.1f", framerate) or "n/a")
end

-- ---------------------------------------------------------------- sampler --
-- A sampler watches one display's OBSERVER per rendered frame:
--   observer.count()     -> number of elements to read this frame (<= MAX_ELEMENTS)
--   observer.read(i)     -> a, b, id   plain numbers (b may be 0) + an identity token, or nil when unreadable
--   observer.label(i)    -> short name of element i
-- Element i "moved" on a frame when (a, b) differs from the previous frame's AND the identity is the same
-- (a slot that was rebound to another row is not a move). compared[i] counts the frames with a comparable
-- previous reading.

function M.NewSampler(observer)
    local s = { observer = observer, frames = 0, sum = 0, changed = {}, compared = {}, pa = {}, pb = {}, pid = {} }
    for i = 1, M.MAX_ELEMENTS do
        s.changed[i], s.compared[i] = 0, 0
    end
    return s
end

--- One rendered frame (`elapsed` seconds or nil). Allocation-free.
function M.SamplerFrame(s, elapsed)
    s.frames = s.frames + 1
    if elapsed then s.sum = s.sum + elapsed end
    local ob = s.observer
    local n = ob.count()
    if n > M.MAX_ELEMENTS then n = M.MAX_ELEMENTS end
    for i = 1, n do
        local a, b, id = ob.read(i)
        if a ~= nil and id ~= nil then
            if s.pid[i] == id then
                s.compared[i] = s.compared[i] + 1
                if a ~= s.pa[i] or b ~= s.pb[i] then s.changed[i] = s.changed[i] + 1 end
            end
            s.pa[i], s.pb[i], s.pid[i] = a, b, id
        else
            s.pid[i] = nil
        end
    end
end

--- The element that moved most: index, changed, compared (nil when nothing was ever comparable).
function M.Best(s)
    local bi, bc, bn
    for i = 1, M.MAX_ELEMENTS do
        local n = s.compared[i]
        if n > 0 then
            local c = s.changed[i]
            if bi == nil or c > bc or (c == bc and c / n > bc / bn) then bi, bc, bn = i, c, n end
        end
    end
    return bi, bc, bn
end

--- "pass" | "fail" | "none" (nothing comparable), ratio, detail ("moved 243/247 frames (0.98) via icon x fps 164").
function M.Verdict(s)
    local i, c, n = M.Best(s)
    if not i then return "none", nil, "no element could be read on two consecutive frames (" .. s.frames .. " frames)" end
    local ratio = c / n
    local fps = s.sum > 0 and (s.frames / s.sum) or nil
    local label = s.observer.label and s.observer.label(i) or ("element " .. i)
    local detail = string.format("moved %d/%d frames (%.2f) via %s fps %s", c, n, ratio, label,
        fps and string.format("%.0f", fps) or "n/a")
    return (ratio >= M.MIN_RATIO) and "pass" or "fail", ratio, detail
end

-- ---------------------------------------------------------------- targets --
-- A target describes one display: { key, available() -> ok, why, rows() -> n, hasScript() -> bool|nil,
-- observer = {...}, extra(sampler) -> text|nil }. Built per window from the live FX tables.

local function cooldownTarget()
    local t = { key = "cooldown" }
    local function display()
        local CD = FX.Cooldown
        return CD and CD.Display, CD and CD.Module
    end
    function t.available()
        local D, mod = display()
        if not (D and mod) then return false, "Forte_Cooldown display/module absent" end
        if not enabled("Cooldown") then return false, "Cooldown module disabled" end
        if not D.anchor then return false, "cooldown bar not built" end
        return true
    end
    function t.rows()
        local D = display()
        return D and plainNum(D._mvN) or 0
    end
    function t.hasScript()
        local _, mod = display()
        return hasUpdateScript(mod and mod._renderFrame)
    end
    t.observer = {
        count = function()
            local D = display()
            local n = D and plainNum(D._mvN) or 0
            return n > M.MAX_ELEMENTS and M.MAX_ELEMENTS or n
        end,
        read = function(i)
            local D = display()
            local slots = D and D._islot
            local slot = type(slots) == "table" and slots[i]
            local fr = slot and slot.frame
            if not fr then return nil end
            local ok, _, _, _, x, y = pcall(fr.GetPoint, fr)
            if not ok then return nil end
            x, y = plainNum(x), plainNum(y)
            if not x then return nil end
            return x, y or 0, fr
        end,
        label = function() return "icon x" end,
    }
    return t
end

local function timerTarget()
    local t = { key = "timer" }
    local flat, nflat = {}, 0
    local function display() return FX.Timer and FX.Timer.Display end
    --- The bound rows of the last full pass, flattened into the preallocated `flat`.
    local function refresh()
        nflat = 0
        local D = display()
        local runs, ng = D and D._runs, D and D._ng
        if type(runs) ~= "table" or type(ng) ~= "number" then return end
        for gi = 1, ng do
            local run = runs[gi]
            if type(run) == "table" and type(run.count) == "number" then
                for j = 1, run.count do
                    if nflat >= M.MAX_ELEMENTS - 1 then return end
                    nflat = nflat + 1
                    flat[nflat] = run.slot[j]
                end
            end
        end
    end
    function t.available()
        local D = display()
        if not D then return false, "Forte_Timer display absent" end
        if not enabled("Timer") then return false, "Timer module disabled" end
        if not D.anchor then return false, "spell timer anchor not built" end
        return true
    end
    function t.rows()
        refresh()
        return nflat
    end
    function t.hasScript()
        local D = display()
        return hasUpdateScript(D and D.anchor)
    end
    t.observer = {
        count = function()
            refresh()
            return 1 + nflat
        end,
        read = function(i)
            local D = display()
            if i == 1 then
                local counts = D and D.counts
                local v = type(counts) == "table" and plainNum(counts.motionPass)
                if not v then return nil end
                return v, 0, counts
            end
            local r = flat[i - 1]
            if type(r) ~= "table" then return nil end
            local widget, method = r.bar, "GetValue"
            if r._mFlip then widget, method = r.fill, "GetWidth" end
            if type(widget) ~= "table" or type(widget[method]) ~= "function" then return nil end
            local ok, v = pcall(widget[method], widget)
            v = ok and plainNum(v)
            if not v then return nil end
            return v, 0, r
        end,
        label = function(i) return i == 1 and "motion passes" or "row fill" end,
    }
    --- The motion-pass counter is element 1: report it next to the best widget element.
    function t.extra(s)
        local n = s.compared[1]
        if n and n > 0 then return string.format("passes %d/%d", s.changed[1], n) end
        return nil
    end
    return t
end

local function swingTarget()
    local t = { key = "swing" }
    local function swing() return FX.Hunter and FX.Hunter.Swing end
    local function engine()
        local S = swing()
        return S and type(S.UsesEngineFill) == "function" and S:UsesEngineFill() or false
    end
    function t.available()
        local tok = Dev.classToken()
        if tok ~= "HUNTER" then return false, "not a Hunter (class " .. tostring(tok) .. ")" end
        local S = swing()
        if not (S and FX.Hunter.SwingDemo) then return false, "Forte_Hunter swing bar / demo absent" end
        if not enabled("HunterUI") then return false, "HunterUI module disabled" end
        if not S.anchor then return false, "swing bar not built" end
        return true
    end
    function t.rows()
        local S, D = swing(), FX.Hunter and FX.Hunter.SwingDemo
        if not (S and D and type(D.Live) == "function") then return 0 end
        local live = plainNum(D:Live()) or 0
        return (live > 0 and S._shown == true) and 1 or 0
    end
    function t.hasScript()
        local S = swing()
        return hasUpdateScript(S and S.anchor)
    end
    t.observer = {
        count = function() return engine() and 3 or 2 end,
        read = function(i)
            local S = swing()
            if not S then return nil end
            local widget, ok, a, b, c, x, y
            if i == 1 then
                widget = S.spark
                if type(widget) ~= "table" or type(widget.GetPoint) ~= "function" then return nil end
                ok, a, b, c, x, y = pcall(widget.GetPoint, widget)
                x, y = ok and plainNum(x), ok and plainNum(y)
                if not x then return nil end
                return x, y or 0, widget
            end
            widget = S.fill
            if type(widget) ~= "table" then return nil end
            local method = (i == 2) and "GetWidth" or "GetValue"
            if type(widget[method]) ~= "function" then return nil end
            local v
            ok, v = pcall(widget[method], widget)
            v = ok and plainNum(v)
            if not v then return nil end
            return v, 0, widget
        end,
        label = function(i) return (i == 1 and "spark x") or (i == 2 and "fill width") or "fill value" end,
    }
    return t
end

--- The displays, in M.ORDER. Always returns all three; `available()` says why one cannot be measured.
function M.buildTargets()
    return { cooldownTarget(), timerTarget(), swingTarget() }
end

-- ----------------------------------------------------------- demo window --

--- The shared window. Fills res[key] = { skip = reason } | { sampler, target, idle } for every target and
--- calls settle() when done (or settle(body) with a raising body for an internal error). Returns the
--- cleanup the async timeout runs: it stops the sampler and puts the demo back.
function M.RunWindow(res, settle)
    local tm = M.testMode()
    local targets = M.buildTargets()
    res.targets = targets
    local st = { dead = false, restored = false, started = false, wasActive = false, driver = nil }
    local sampled, samplers = {}, {}

    local function setSkip(t, why) res[t.key] = { skip = why } end
    local function skipRemaining(why)
        for _, t in ipairs(targets) do
            if res[t.key] == nil then setSkip(t, why) end
        end
    end
    local function stopDriver()
        if st.driver then
            pcall(st.driver.Stop, st.driver)
            st.driver = nil
        end
    end
    --- Put the demo back as it was found: stop it only when THIS window started it.
    local function restore()
        if st.restored then return end
        st.restored = true
        stopDriver()
        if st.started and not st.wasActive and type(tm) == "table" then pcall(tm.Stop, tm, "stopped") end
    end
    local function cleanup()
        st.dead = true
        restore()
    end
    local function guard(fn)
        return function()
            if st.dead then return end
            local ok, err = pcall(fn)
            if not ok then
                cleanup()
                settle(function() error(err, 0) end)
            end
        end
    end
    local function active()
        local ok, a = pcall(tm.IsActive, tm)
        return ok and a == true
    end

    if Dev.inCombat() then
        skipRemaining("in combat: the demo refuses to run and the displays must not be touched")
        settle()
        return cleanup
    end
    if type(tm) ~= "table" or type(tm.Start) ~= "function" or type(tm.IsActive) ~= "function" then
        skipRemaining("Forte_Core TestMode absent")
        settle()
        return cleanup
    end
    local usable = 0
    for _, t in ipairs(targets) do
        local ok, avail, why = pcall(t.available)
        if not ok then
            setSkip(t, "availability check raised: " .. Dev.S(avail, 80))
        elseif not avail then
            setSkip(t, why or "unavailable")
        else
            usable = usable + 1
        end
    end
    if usable == 0 then
        settle()
        return cleanup
    end

    st.wasActive = active()
    if not st.wasActive then
        local okS, started, why = pcall(tm.Start, tm)
        if not okS or started ~= true then
            skipRemaining("test mode did not start: " .. Dev.S(okS and why or started, 80))
            settle()
            return cleanup
        end
        st.started = true
    end

    local function wordFor(t)
        local ok, has = pcall(t.hasScript)
        if not ok or has == nil then return "?" end
        return has and "no" or "yes"
    end

    local function finalize()
        for _, t in ipairs(sampled) do
            local r = res[t.key]
            if r and r.sampler then
                r.idle = st.started and wordFor(t) or "n/a (demo was already running)"
            end
        end
        settle()
    end

    local function afterSample()
        stopDriver()
        -- reading (b) of the CPU metric: the demo is still running here
        if res.atSampleEnd then pcall(res.atSampleEnd) end
        local combatNow, stillOn = Dev.inCombat(), active()
        restore()                                    -- the demo goes back first, then the idle wait
        for i, t in ipairs(sampled) do
            if combatNow or not stillOn then
                setSkip(t, "combat began during the window: test mode scrubbed the demo")
            else
                res[t.key] = { sampler = samplers[i], target = t }
            end
        end
        local polls = math.ceil(M.IDLE_WAIT_SECONDS / M.IDLE_POLL_SECONDS - 1e-9)
        local function poll(k)
            local all = st.started
            if all then
                for _, t in ipairs(sampled) do
                    local r = res[t.key]
                    if r and r.sampler and wordFor(t) ~= "yes" then all = false end
                end
            end
            if all or not st.started or k >= polls then
                finalize()
                return
            end
            M.after(M.IDLE_POLL_SECONDS, guard(function() poll(k + 1) end))
        end
        poll(0)
    end

    M.after(M.WARM_SECONDS, guard(function()
        if Dev.inCombat() or not active() then
            restore()
            skipRemaining("demo stopped or combat began during warm-up (test mode scrubs on combat)")
            settle()
            return
        end
        for _, t in ipairs(targets) do
            if res[t.key] == nil then
                local ok, n = pcall(t.rows)
                if ok and type(n) == "number" and n > 0 then
                    sampled[#sampled + 1] = t
                    samplers[#samplers + 1] = M.NewSampler(t.observer)
                else
                    setSkip(t, "no rows after " .. M.WARM_SECONDS .. " s of demo (display hidden, disabled or empty)")
                end
            end
        end
        if #samplers == 0 then
            restore()
            settle()
            return
        end
        local ns = #samplers
        st.driver = M.newDriver(function(elapsed)
            for i = 1, ns do
                local s = samplers[i]
                if not s.broken then
                    -- an observer that raises is switched off (reported once), never raised every frame
                    local ok, err = pcall(M.SamplerFrame, s, elapsed)
                    if not ok then s.broken = Dev.S(err, 100) end
                end
            end
        end)
        M.after(M.SAMPLE_SECONDS, guard(afterSample))
    end))
    return cleanup
end

-- --------------------------------------------------------------- addon CPU --
-- The client's own profiler (C_AddOnProfiler, Enum.AddOnProfilerMetric.RecentAverageTime). The pinned catalog
-- declares GetAddOnMetric(name, metric) / GetOverallMetric(metric) / GetApplicationMetric(metric) as returning a
-- plain `number` and GetTicksPerSecond() as a BigInteger, but NOT the unit of the metric. Two third-party
-- add-ons (EllesmereUI, KullThranUI) print the recent-average value as milliseconds per frame, so the unit is
-- taken as "ms"; M.METRIC_UNIT = "ticks" would convert through GetTicksPerSecond. The first live numbers
-- should be sanity-checked against the frame time.

--- The profiler namespace and the Enum table (seam: a test stubs it).
function M.profilerApi() return _G.C_AddOnProfiler, _G.Enum end

--- A metric value in milliseconds under M.METRIC_UNIT ("ms" | "ticks").
function M.toMs(v, ticksPerSecond)
    if M.METRIC_UNIT == "ticks" then
        if type(ticksPerSecond) ~= "number" or ticksPerSecond <= 0 then return nil end
        return v / ticksPerSecond * 1000
    end
    return v
end

--- Names of the loaded add-ons that start with "Forte_" (pcall'd C_AddOns enumeration; seam).
function M.loadedForteAddOns()
    local out = {}
    local api = _G.C_AddOns
    if type(api) ~= "table" or type(api.GetNumAddOns) ~= "function" or type(api.GetAddOnInfo) ~= "function" then
        return out
    end
    local okN, n = pcall(api.GetNumAddOns)
    n = okN and plainNum(n)
    if not n then return out end
    for i = 1, n do
        local ok, name = pcall(api.GetAddOnInfo, i)
        if ok and type(name) == "table" then name = name.name end
        if ok and type(name) == "string" and not Dev.isSecret(name) and name:sub(1, 6) == "Forte_"
            and Dev.isAddOnLoaded(name) == true then
            out[#out + 1] = name
        end
    end
    return out
end

--- ctx, or nil + the exact reason the CPU test must SKIP. Every call is pcall'd and classified.
function M.CpuProbe()
    local api, enum = M.profilerApi()
    if type(api) ~= "table" then return nil, "C_AddOnProfiler is absent" end
    for _, fn in ipairs({ "IsEnabled", "GetAddOnMetric" }) do
        if type(api[fn]) ~= "function" then return nil, "C_AddOnProfiler." .. fn .. " is missing" end
    end
    if type(enum) ~= "table" or type(enum.AddOnProfilerMetric) ~= "table" then
        return nil, "Enum.AddOnProfilerMetric is missing"
    end
    local metric
    local okE = pcall(function()
        for name, value in pairs(enum.AddOnProfilerMetric) do
            if name == "RecentAverageTime" then metric = value end
        end
    end)
    if not okE then return nil, "Enum.AddOnProfilerMetric could not be enumerated" end
    metric = plainNum(metric)
    if metric == nil then return nil, "Enum.AddOnProfilerMetric.RecentAverageTime is missing" end
    local okI, enabled = pcall(api.IsEnabled)
    if not okI then return nil, "C_AddOnProfiler.IsEnabled() raised: " .. Dev.S(enabled, 60) end
    if Dev.isSecret(enabled) then return nil, "C_AddOnProfiler.IsEnabled() returned a secret value" end
    if enabled ~= true then return nil, "C_AddOnProfiler.IsEnabled() is " .. Dev.S(enabled, 20) .. " (profiler off)" end
    local ticks
    if type(api.GetTicksPerSecond) == "function" then
        local okT, t = pcall(api.GetTicksPerSecond)
        ticks = okT and plainNum(t) or nil
    end
    if M.METRIC_UNIT == "ticks" and not ticks then return nil, "metric unit is ticks but GetTicksPerSecond() is unreadable" end
    return { api = api, metric = metric, ticks = ticks }
end

--- One reading: { forte = { [addon] = ms }, product = ms (sum, Forte_Dev excluded), dev = ms|nil, read = n,
--- unreadable = n, overall = ms|nil, application = ms|nil, fps = n|nil }.
function M.CpuRead(ctx)
    local out = { forte = {}, product = 0, read = 0, unreadable = 0 }
    for _, name in ipairs(M.loadedForteAddOns()) do
        local ok, v = pcall(ctx.api.GetAddOnMetric, name, ctx.metric)
        local ms = ok and plainNum(v)
        ms = ms and M.toMs(ms, ctx.ticks)
        if ms then
            out.read = out.read + 1
            if name == "Forte_Dev" then
                out.dev = ms
            else
                out.forte[name] = ms
                out.product = out.product + ms
            end
        else
            out.unreadable = out.unreadable + 1
        end
    end
    local function scale(fnName)
        local fn = ctx.api[fnName]
        if type(fn) ~= "function" then return nil end
        local ok, v = pcall(fn, ctx.metric)
        v = ok and plainNum(v)
        return v and M.toMs(v, ctx.ticks) or nil
    end
    out.overall = scale("GetOverallMetric")
    out.application = scale("GetApplicationMetric")
    out.fps = M.getFramerate()
    return out
end

local function round4(v) return math.floor(v * 10000 + 0.5) / 10000 end

local function roundAll(t)
    local out = {}
    for k, v in pairs(t) do out[k] = round4(v) end
    return out
end

--- The CPU test's detail (<= 160 chars) and the small plain table stored in the run (`run.motion.cpu`).
function M.CpuSummary(idle, demo, ctx)
    local fps = demo.fps or idle.fps
    local frameMs = (fps and fps > 0) and (1000 / fps) or nil
    local pct = frameMs and (demo.product / frameMs * 100) or nil
    local detail = string.format("FX idle %.3f ms/frame, demo %.3f ms/frame", idle.product, demo.product)
    if pct then detail = detail .. string.format(" (%.1f%% of a %.2f ms frame @%.0f fps)", pct, frameMs, fps) end
    detail = detail .. "; dev " .. (demo.dev and string.format("%.3f", demo.dev) or "n/a")
    if demo.overall then detail = detail .. string.format("; all addons %.1f", demo.overall) end
    if demo.application then detail = detail .. string.format("; app %.1f", demo.application) end
    local data = {
        unit = M.METRIC_UNIT, metric = "RecentAverageTime", ticksPerSecond = ctx and ctx.ticks or nil,
        fps = fps and round4(fps) or nil, frameMs = frameMs and round4(frameMs) or nil, percent = pct and round4(pct) or nil,
        idle = roundAll(idle.forte), demo = roundAll(demo.forte),
        product = { idle = round4(idle.product), demo = round4(demo.product) },
        dev = { idle = idle.dev and round4(idle.dev) or nil, demo = demo.dev and round4(demo.dev) or nil },
        overall = demo.overall and round4(demo.overall) or nil,
        application = demo.application and round4(demo.application) or nil,
    }
    return detail, data
end

-- ------------------------------------------------------------------ suite --

Dev.RegisterSuite("motion", "ooc", function(T)
    local res = {}
    local cpu = {}

    -- (a) the idle CPU baseline, before anything starts; (b) is taken by the window at the end of its sampling
    T.step(function()
        local ctx, why = M.CpuProbe()
        if not ctx then
            cpu.skip = why
            return
        end
        cpu.ctx = ctx
        cpu.idle = M.CpuRead(ctx)
    end)
    res.atSampleEnd = function()
        if cpu.ctx then cpu.demo = M.CpuRead(cpu.ctx) end
    end

    T.async("motion: frame pacing", M.PACING_TIMEOUT, function(settle)
        local p = M.NewPacing()
        local driver = M.newDriver(function(elapsed)
            if elapsed then M.PacingAdd(p, elapsed) end
        end)
        local stopped = false
        local function stop()
            if stopped then return end
            stopped = true
            pcall(driver.Stop, driver)
        end
        M.after(M.PACING_SECONDS, function()
            stop()
            settle(function()
                if p.n == 0 then
                    T.fail("no OnUpdate frame in " .. M.PACING_SECONDS .. " s (the client is not rendering frames)")
                end
                T.note(M.PacingDetail(p, M.getFramerate()))
            end)
        end)
        return stop
    end)

    T.async("motion: demo window", M.WINDOW_TIMEOUT, function(settle)
        return M.RunWindow(res, settle)
    end)

    T.step(function()
        for _, key in ipairs(M.ORDER) do
            T.check(M.TEST_NAMES[key], function()
                local r = res[key]
                if not r then T.skip("the demo window did not complete") end
                if r.skip then T.skip(r.skip) end
                local status, _, detail = M.Verdict(r.sampler)
                if r.target and r.target.extra then
                    local okE, extra = pcall(r.target.extra, r.sampler)
                    if okE and extra then detail = detail .. "; " .. extra end
                end
                detail = detail .. "; idle script removed: " .. tostring(r.idle or "?")
                if r.sampler.broken then T.fail("observer raised: " .. r.sampler.broken) end
                if status ~= "pass" then T.fail(detail) end
                T.note(detail)
            end)
        end
    end)

    T.step(function()
        T.check("motion: addon CPU", function()
            if cpu.skip then T.skip(cpu.skip) end
            local demo = cpu.demo
            if not demo then
                T.skip("no demo reading: the demo window took no sample (see the display tests above)")
            end
            local idle = cpu.idle
            if idle.read == 0 then T.skip("no loaded Forte_ add-on metric could be read at the start (secret or unreadable)") end
            if demo.read == 0 then T.skip("no loaded Forte_ add-on metric could be read with the demo running (secret or unreadable)") end
            local detail, data = M.CpuSummary(idle, demo, cpu.ctx)
            T.attach("motion", { cpu = data })
            T.note(detail)
        end)
    end)
end)

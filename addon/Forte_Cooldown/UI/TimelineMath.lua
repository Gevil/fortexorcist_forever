-- Forte_Cooldown/UI/TimelineMath.lua
-- Frame-free math for the Classic Cooldown Timer timeline (PLAN.md §3.5),
-- lifted from the original render loop of Forte_Cooldown v1.980.8
-- (/tmp/fxref/Forte_Cooldown/Forte_Cooldown.lua, CD_CreateCooldowns
-- :499-536, the overlap test at :560, the custom-tag path of SetTimeTags
-- :1233-1295). No frames, no WoW globals beyond base Lua: unit-testable in
-- luajit AND in the wow-ui-sim tests (tests/test_timeline.lua).
--
-- Geometry (the original's, verbatim):
--   ih = bar height (the icon size; IconSize 36 is opt-in, the default icon
--   size IS the bar height -- :500, §9 correction 2026-11-01)
--   f1 = (W - ih)/W, f2 = 1 - f1                    (:501-502)
--   v  = f1*(t/Max)^Loga + f2   (t <= Max)          (:515-522)
--   icon centre x = v*W, icon LEFT x = v*W - ih/2  (:523-526)
--   t > Max parks at the right end (v = 1, :518-519); t <= 0 clamps to the
--   left end (the end-of-cooldown position, CD_EndCooldown :346-351).

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
FX.Cooldown = FX.Cooldown or {}

local TM = {}
FX.Cooldown.TimelineMath = TM

--- Icon LEFT-edge x for `t` seconds remaining, inside a W x H bar.
--- `t > Max` parks at the right end (icon centre on the right edge, the
--- original's v = 1 at :518-519); `t <= 0` clamps to the left end.
function TM.pos(t, W, H, Max, Loga)
    local ih = H
    local f1 = (W - ih) / W
    local f2 = 1 - f1
    local v
    if t > Max then
        v = 1
    elseif t <= 0 then
        v = f2
    else
        v = f1 * (t / Max) ^ Loga + f2
    end
    return v * W - ih * 0.5
end

--- The ONE position function of an icon: LEFT-edge x for `t` seconds
--- remaining plus the position factor v = centre / W (the original's t7:
--- the segment's TexCoord slice and alpha ride it). The full pass
--- (Timeline:Update) and the per-frame motion pass (Timeline:Motion) both
--- call exactly this, so an icon is at the same place whichever pass wrote it.
--- Pure arithmetic: returns two numbers, allocates nothing.
function TM.place(t, W, H, Max, Loga)
    local x = TM.pos(t, W, H, Max, Loga)
    return x, (x + H * 0.5) / W
end

--- Does an icon with `t` seconds remaining MOVE along the axis? Not before
--- it enters the curve (t > Max parks at the right end) and not once it
--- reached the left end (t <= 0 clamps). The motion pass runs only while
--- at least one entry answers true.
function TM.moves(t, Max)
    return t > 0 and t <= Max
end

--- Minute-label rule of the original's custom-tag path: a value is printed
--- divided by 60 ONLY when STRICTLY greater than 60
--- (`if v>60 then v=(v/60);end`, :1267 and :1286; the uniform-tag branch at
--- :1310 is `> 60` as well). 60 s therefore prints as "60", not "1"; 120 as
--- "2". The returned label is a plain string.
local function tagLabel(value)
    if value > 60 then
        local m = value / 60
        if m % 1 == 0 then m = math.floor(m) end
        return tostring(m)
    end
    return tostring(value)
end
TM.tagLabel = tagLabel

--- The custom time-tag list for `customTags` (a "0 1 10 30 60 120 300 600"
--- string, FW.InstanceDefault.Cooldown.CustomTags[1] :1840): parses every
--- whole number, drops tags >= Max (the original's `if v < s.Max ... else
--- break`, :1257/:1278), and places each on the SAME power curve as the
--- icons. Returns a list of { value, label, x } ordered as parsed; `x` is the
--- icon-left-x of that time (TimelineMath.pos), i.e. the tag centres on the
--- icon's left edge exactly as the original anchors them
--- (`d = Backdrop[6] + val*Width - ih*0.5`, :1259 -- the Backdrop[6] inset is
--- a frame detail, added by Timeline.lua, not here).
function TM.tags(customTags, W, H, Max, Loga)
    local out = {}
    for token in tostring(customTags or ""):gmatch("%d+") do
        local value = tonumber(token)
        if value >= Max then
            break
        end
        out[#out + 1] = {
            value = value,
            label = tagLabel(value),
            x = TM.pos(value, W, H, Max, Loga),
        }
    end
    return out
end

--- Overlap grouping over entries already ordered left-to-right by their
--- `.x` (icon left x) -- the Engine's Sorted order (endTime ascending) is
--- exactly this order since pos() is monotonic in t. Two adjacent entries
--- merge into one group when the previous CENTRE passes the current LEFT
--- edge, i.e. they overlap by more than half an icon (original :560:
--- `s9 > t10` -- "more than half an icon overlap"). Entries with x = nil
--- (hidden) are skipped. Returns groups: each group is a list of the entry
--- tables, in input order.
---
--- `out` (optional) is a CALLER-OWNED scratch table: the groups list and
--- every group sub-list are reused from it, the pass allocates NOTHING.
--- The contract: every list the pass produces lives in `out` (the live
--- groups in out[1..n], out.nested holding the whole pool), so the next
--- pass finds every list in the pool, wiped. Without `out` the result is
--- fresh tables, which keeps the pure/unit-test shape unchanged.
function TM.group(sortedEntries, H, out)
    local groups, nested, pool
    if out then
        groups = out
        nested = groups.nested
        if not nested then
            nested = {}
            groups.nested = nested
        end
        pool = #nested
        -- Detach the previous pass's live lists: they stay in the pool
        -- (nested), already wiped by the tail pass of the call that made
        -- them (see the clear below), so the pass starts on a full pool.
        for i = #groups, 1, -1 do
            groups[i] = nil
        end
    else
        groups, nested, pool = {}, nil, 0
    end
    local cur
    local prevCentre
    local n = 0
    for i = 1, #sortedEntries do
        local e = sortedEntries[i]
        if e.x then
            local centre = e.x + H * 0.5
            if prevCentre and prevCentre > e.x then
                cur[#cur + 1] = e
            else
                n = n + 1
                cur = nested and nested[n]
                if cur then
                    -- Reuse from the pool: the list may carry the last
                    -- pass's members -- wipe first, fill after.
                    for j = #cur, 1, -1 do cur[j] = nil end
                else
                    cur = {}
                    if nested then nested[n] = cur end
                end
                cur[1] = e
                groups[n] = cur
            end
            prevCentre = centre
        end
    end
    return groups
end

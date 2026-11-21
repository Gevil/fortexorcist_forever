-- addon/Forte_Timer/tests/test_show_self.lua
-- GitHub issue #3 ("Unable to remove Self timers"): the Spell Timer page's
-- `ShowSelf` checkbox. Every assertion drives the REAL path -- the settings
-- store (`FX.Settings:Set` -> OnChange -> Module:ApplySettings -> SetShowSelf),
-- `Module:Draw` (Rows:Sorted + Display:Update) and the frame's motion
-- OnUpdate -- never a stubbed link array.
--
-- The predicate under test is `Rows.IsSelfRow` (targetKey == "none"), the same
-- one the renderer's OffsetSelf reads.

local FX = ForteXorcist
local M = FX.Timer.Module
local Rows = FX.Timer.Rows
local Laws = FX.Timer.Laws
local Casts = FX.Timer.Casts
local D = FX.Timer.Display
local ST = FX.Settings
local O = FX.Options

local realGetTime = _G.GetTime
local clockNow

local function setTime(t)
    clockNow = t
    _G.GetTime = function() return clockNow end
    Casts.now = function() return clockNow end
end

local function ensure()
    if not M.options then M:OnEnable() end
    assertNotNil(D.anchor, "the display is built")
    local o = M.options
    o.enable, o.hide, o.flip, o.expand, o.outwands = true, false, false, true, true
    o.maxOn, o.maxRows = false, 15
    o.hideLonger = false
    ST:Set("SpellTimer", "ShowSelf", true)
    assertTrue(o.showSelf)
    return o
end

local function slotOf(row)
    for s = 1, #D.rows do
        if D.rows[s]._row == row and D.rows[s].bar:IsShown() then
            return D.rows[s]
        end
    end
    return nil
end

local function shownBars()
    local n = 0
    for i = 1, #D.rows do
        if D.rows[i].bar:IsShown() then n = n + 1 end
    end
    return n
end

local function shownGroups()
    local n = 0
    for i = 1, #D.groups do
        if D.groups[i].frame:IsShown() then n = n + 1 end
    end
    return n
end

local function groupY(i)
    return select(5, D.groups[i].frame:GetPoint())
end

--- Two enemy rows (their own groups) and one self row, at `base`.
local function seed(base)
    setTime(base)
    Rows:Clear()
    Rows.options = M.options
    local e1 = Rows:InsertFromCast("Serpent Sting", "Dummy-1", 30, base, base,
        1, "TargetDebuff")
    local e2 = Rows:InsertFromCast("Hunter's Mark", "Dummy-2", 60, base, base,
        1, "TargetDebuff")
    local me = Rows:InsertFromCast("Frenzy Self", "none", 20, base, base, 1,
        "SelfBuff")
    assertNotNil(e1) assertNotNil(e2) assertNotNil(me)
    assertEquals(3, Rows:Count())
    for _ = 1, 40 do M:Draw() end    -- the scale ease settles
    return e1, e2, me
end

local function cleanUp()
    local o = M.options
    o.maxOn, o.maxRows, o.hideLonger, o.outwands = false, 15, false, true
    ST:Set("SpellTimer", "ShowSelf", true)
    Rows:Clear()
    Casts.now = nil
    _G.GetTime = realGetTime
    M:Draw()
    D:RenderIdle()
end

--- The raw (sparse) per-profile value of SpellTimer.ShowSelf, nil when absent.
local function rawStored()
    local found
    local profiles = (FX.db and FX.db.profiles and FX.db.profiles.byName) or {}
    for _, p in pairs(profiles) do
        local t = p.settings and p.settings.SpellTimer
        if type(t) == "table" and t.ShowSelf ~= nil then found = t.ShowSelf end
    end
    return found
end

-- ------------------------------------------------------------------ default --

test("ShowSelf defaults ON: every row is drawn, self rows included", function()
    local o = ensure()
    assertEquals(true, ST:GetDefault("SpellTimer", "ShowSelf"))
    assertEquals(true, ST:Get("SpellTimer", "ShowSelf"))
    assertEquals(true, o.showSelf)
    local e1, e2, me = seed(realGetTime())
    assertEquals(3, shownBars())
    assertEquals(3, shownGroups())
    assertNotNil(slotOf(me))
    assertNotNil(slotOf(e1))
    assertNotNil(slotOf(e2))
    cleanUp()
end)

-- ----------------------------------------------------------------- the pred --

test("one predicate: the none key is the player's own row, nothing else is", function()
    assertEquals(true, Rows.IsSelfRow({ targetKey = "none" }))
    assertEquals(false, Rows.IsSelfRow({ targetKey = "target" }))
    assertEquals(false, Rows.IsSelfRow({ targetKey = "Dummy-1" }))
    assertEquals(false, Rows.IsSelfRow({ targetKey = "pet wolf" }))
end)

-- ------------------------------------------------------------------ hiding ---

test("off hides only self rows; enemy groups keep their slots, no gap", function()
    local o = ensure()
    local e1, e2, me = seed(realGetTime())
    local y1, y2 = groupY(1), groupY(2)
    local gy1, gy2 = D.groups[1]._ay, D.groups[2]._ay
    ST:Set("SpellTimer", "ShowSelf", false)       -- live: no Draw call here
    assertFalse(o.showSelf)
    assertEquals(2, shownBars(), "toggling redraws at once")
    assertEquals(2, shownGroups())
    assertNil(slotOf(me))
    assertNotNil(slotOf(e1))
    assertNotNil(slotOf(e2))
    -- enemy groups sit above the PRIOR_NONE band: they did not move
    assertEquals(y1, groupY(1))
    assertEquals(y2, groupY(2))
    assertEquals(gy1, D.groups[1]._ay)
    assertEquals(gy2, D.groups[2]._ay)
    -- the model still holds the self row
    assertEquals(3, Rows:Count())
    assertNotNil(Rows:Find("Frenzy Self", "none"))
    -- the anchor box is exactly two groups tall
    local one = o.height + o.labelHeight
    local expect = 2 * one + o.spacingHeight
    assertTrue(math.abs(D.anchor:GetHeight() - expect) < 0.5,
        D.anchor:GetHeight() .. " vs " .. expect)
    cleanUp()
end)

test("a self group BELOW the enemies leaves no empty slot when hidden", function()
    local o = ensure()
    o.outwands = false            -- self (key 0) now sorts FIRST = the bottom slot
    local e1, e2, me = seed(realGetTime())
    assertEquals(3, shownGroups())
    local bottomWithSelf = D.groups[1]._ay
    local secondWithSelf = D.groups[2]._ay
    assertTrue(secondWithSelf > bottomWithSelf)
    ST:Set("SpellTimer", "ShowSelf", false)
    assertEquals(2, shownGroups())
    assertEquals(2, shownBars())
    assertEquals(bottomWithSelf, D.groups[1]._ay, "the first slot is refilled")
    assertTrue(D.groups[2]._ay > D.groups[1]._ay)
    assertNil(slotOf(me))
    cleanUp()
end)

test("rows of one group: hiding the self row between them closes the gap", function()
    local o = ensure()
    -- grouping off: the sort is by drawn expiry only, so the self row sits
    -- BETWEEN two rows of the same target; hidden, they form ONE run
    o.groupID = false
    setTime(realGetTime())
    local base = clockNow
    Rows:Clear()
    Rows.options = o
    Rows:InsertFromCast("Serpent Sting", "Dummy-1", 10, base, base, 1,
        "TargetDebuff")
    local me = Rows:InsertFromCast("Frenzy Self", "none", 20, base, base, 1,
        "SelfBuff")
    Rows:InsertFromCast("Hunter's Mark", "Dummy-1", 30, base, base, 1,
        "TargetDebuff")
    for _ = 1, 10 do M:Draw() end
    assertEquals(3, shownBars())
    assertEquals(3, shownGroups())
    ST:Set("SpellTimer", "ShowSelf", false)
    assertEquals(2, shownBars())
    assertEquals(1, shownGroups(), "the two rows merge into one run")
    local ys = {}
    for i = 1, #D.rows do
        if D.rows[i].bar:IsShown() then
            ys[#ys + 1] = select(5, D.rows[i].bar:GetPoint())
        end
    end
    table.sort(ys)
    assertEquals(2, #ys)
    assertTrue(math.abs((ys[2] - ys[1]) - (o.height + o.space)) < 0.5,
        "adjacent slots, no hole: " .. ys[1] .. "," .. ys[2])
    assertNil(slotOf(me))
    o.groupID = true
    cleanUp()
end)

-- ---------------------------------------------------------------- restoring --

test("on again restores the row with its correct remaining time", function()
    local o = ensure()
    local base = realGetTime()
    local e1, e2, me = seed(base)
    ST:Set("SpellTimer", "ShowSelf", false)
    -- time passes while hidden: the row keeps living in the model
    local expireBefore = me.expireAt
    for i = 1, 25 do
        setTime(base + i * 0.2)
        M:Draw()
    end
    assertEquals(expireBefore, me.expireAt)
    assertNil(slotOf(me))
    assertEquals(3, Rows:Count())
    ST:Set("SpellTimer", "ShowSelf", true)
    local r = slotOf(me)
    assertNotNil(r, "back at once")
    assertEquals(3, shownBars())
    -- let the scale ease settle, then the bar value is the law's value
    for _ = 1, 60 do M:Draw() end
    local value = r.bar:GetValue()
    assertTrue(math.abs(value - Laws.BarVal(me.drawExpireAt, clockNow,
        me.maxTime)) < 1e-3)
    -- 20 s window, 5 s elapsed: 15 s remain, and the bar is not full
    assertTrue(math.abs((me.expireAt - clockNow) - 15) < 1e-6)
    assertTrue(value > 0 and value < 1)
    -- the motion pass moves it too
    setTime(base + 6)
    D.anchor:GetScript("OnUpdate")(D.anchor, 0.01)
    assertTrue(math.abs(r.bar:GetValue()
        - Laws.BarVal(me.drawExpireAt, clockNow, me.maxTime)) < 1e-3)
    cleanUp()
end)

test("a self row that EXPIRES while hidden is not resurrected", function()
    local o = ensure()
    local base = realGetTime()
    local e1, e2, me = seed(base)
    for _, r in ipairs({ e1, e2 }) do         -- the enemies outlive the run
        r.total, r.expireAt, r.drawExpireAt = 300, base + 300, base + 300
    end
    M:Draw()
    ST:Set("SpellTimer", "ShowSelf", false)
    setTime(base + 25)                    -- past the 20 s window
    M:Logic()                             -- the model expires/sweeps as before
    for i = 1, 30 do
        setTime(base + 25 + i * 0.2)
        M:Logic()
        M:Draw()
    end
    assertNil(Rows:Find("Frenzy Self", "none"))
    ST:Set("SpellTimer", "ShowSelf", true)
    assertEquals(2, shownBars())
    cleanUp()
end)

-- ------------------------------------------------------------------- maxRows --

test("maxRows counts only the rows that are drawn", function()
    local o = ensure()
    local base = realGetTime()
    setTime(base)
    Rows:Clear()
    Rows.options = o
    -- two self rows and two enemy rows; the cap is 2
    Rows:InsertFromCast("Self A", "none", 20, base, base, 1, "SelfBuff")
    Rows:InsertFromCast("Self B", "none", 25, base, base, 1, "SelfBuff")
    Rows:InsertFromCast("Serpent Sting", "Dummy-1", 30, base, base, 1,
        "TargetDebuff")
    Rows:InsertFromCast("Hunter's Mark", "Dummy-2", 60, base, base, 1,
        "TargetDebuff")
    ST:Set("SpellTimer", "MaxOn", true)
    ST:Set("SpellTimer", "Max", 6)
    o.maxRows = 2                         -- below the page's 4..64 slider
    for _ = 1, 10 do M:Draw() end
    assertEquals(2, shownBars(), "capped while self rows are shown")
    ST:Set("SpellTimer", "ShowSelf", false)
    -- the cap would be eaten by the hidden rows if they were counted
    assertEquals(2, shownBars())
    local links, n = Rows:Sorted({}, clockNow)
    assertEquals(2, n, "hidden rows have no link at all")
    for k = 1, n do
        assertFalse(Rows.IsSelfRow(Rows.rows[links[k][1]]))
        assertTrue(links[k][4] > 0, "both enemy rows are within the cap")
    end
    assertEquals(4, Rows:Count())
    o.maxRows = 15
    ST:Set("SpellTimer", "Max", 15)
    ST:Set("SpellTimer", "MaxOn", false)
    cleanUp()
end)

-- --------------------------------------------------------------------- fading --

test("a fading self row does not flash when the option flips", function()
    local o = ensure()
    local base = realGetTime()
    local e1, e2, me = seed(base)
    me.state = Laws.FADING
    me.removeAt = base - 1               -- the cubic fall starts at base
    local function height(t)
        setTime(t)
        M:Draw()
        local r = slotOf(me)
        return r and r.bar:GetHeight()
    end
    local function want(t)
        return o.height * Laws.Alpha(me.removeAt + (o.fadeTime or Laws.FADE), t)
    end
    local h1 = height(base + 0.10)
    assertTrue(math.abs(h1 - want(base + 0.10)) < 0.02)
    ST:Set("SpellTimer", "ShowSelf", false)
    assertNil(height(base + 0.14))
    ST:Set("SpellTimer", "ShowSelf", true)
    setTime(base + 0.18)
    M:Draw()
    local h3 = slotOf(me).bar:GetHeight()
    assertTrue(math.abs(h3 - want(base + 0.18)) < 0.02,
        "back on the ramp, not at full height: " .. h3)
    assertTrue(h3 < h1, "the ramp kept falling while hidden")
    cleanUp()
end)

test("the HideLonger stamp survives a hidden stretch (no re-fade)", function()
    local o = ensure()
    local base = realGetTime()
    local e1, e2, me = seed(base)
    ST:Set("SpellTimer", "HideLonger", true)
    ST:Set("SpellTimer", "HideTime", 3)
    o.hideLongerAt = 10
    setTime(base + 1)
    M:Draw()
    local stamp = me.hiddenSince
    assertTrue(stamp > 0, "the gate tripped")
    ST:Set("SpellTimer", "ShowSelf", false)
    setTime(base + 2)
    M:Draw()
    ST:Set("SpellTimer", "ShowSelf", true)
    setTime(base + 2.5)
    M:Draw()
    assertEquals(stamp, me.hiddenSince, "the stamp is the same, not restarted")
    ST:Set("SpellTimer", "HideLonger", false)
    ST:Set("SpellTimer", "HideTime", Laws.HIDE_TIME)
    cleanUp()
end)

-- ------------------------------------------------------------ motion pass ----

test("hidden rows are not in the run; the motion pass stays allocation-free",
function()
    local o = ensure()
    local base = realGetTime()
    local e1, e2, me = seed(base)
    ST:Set("SpellTimer", "ShowSelf", false)
    for _ = 1, 20 do M:Draw() end
    local fn = D.anchor:GetScript("OnUpdate")
    assertNotNil(fn, "the two enemy rows still move")
    local c = D.counts
    local before = c.motionRows
    setTime(base + 0.5)
    fn(D.anchor, 1 / 165)
    assertEquals(2, c.motionRows - before, "the self row is not in the run")
    for i = 1, 20 do setTime(base + 1 + i / 165) fn(D.anchor, 1 / 165) end
    collectgarbage("stop")
    collectgarbage("count")
    local g0 = collectgarbage("count")
    for i = 1, 1000 do
        clockNow = base + 2 + i / 165
        fn(D.anchor, 1 / 165)
    end
    local g1 = collectgarbage("count")
    collectgarbage("restart")
    assertEquals(0, g1 - g0, "motion pass allocated " .. ((g1 - g0) * 1024))
    cleanUp()
end)

test("only self rows live and the option off: nothing drawn, no motion script",
function()
    local o = ensure()
    local base = realGetTime()
    setTime(base)
    Rows:Clear()
    Rows.options = o
    Rows:InsertFromCast("Frenzy Self", "none", 20, base, base, 1, "SelfBuff")
    M:Draw()
    assertEquals(1, shownBars())
    ST:Set("SpellTimer", "ShowSelf", false)
    assertEquals(0, shownBars())
    assertEquals(0, shownGroups())
    assertNil(D.anchor:GetScript("OnUpdate"), "nothing moves: no per-frame Lua")
    ST:Set("SpellTimer", "ShowSelf", true)
    assertEquals(1, shownBars())
    assertNotNil(D.anchor:GetScript("OnUpdate"))
    cleanUp()
end)

-- ---------------------------------------------------------------- the store ---

test("the store is sparse: the default is not written, a non-default is", function()
    ensure()
    ST:Set("SpellTimer", "ShowSelf", true)
    assertNil(rawStored(), "the default is not stored")
    ST:Set("SpellTimer", "ShowSelf", false)
    assertEquals(false, rawStored(), "a non-default is")
    assertEquals(false, ST:Get("SpellTimer", "ShowSelf"))
    assertFalse(M.options.showSelf)
    -- the login pull applies the stored value to a fresh options table
    M.options.showSelf = true
    M:ApplyStoredSettings()
    assertFalse(M.options.showSelf)
    ST:Set("SpellTimer", "ShowSelf", true)
    assertNil(rawStored(), "back to default: the key is dropped again")
    assertTrue(M.options.showSelf)
    cleanUp()
end)

-- ----------------------------------------------------------------- the page ---

test("the page lists the checkbox beside 'Show target names', with its tip",
function()
    ensure()
    assertNotNil(O and O.pages and O.pages["SpellTimer"])
    O:Open("SpellTimer")
    local page = O.pagesBuilt["SpellTimer"]
    assertNotNil(page)
    local sec, self_, target, names
    for _, s in ipairs(page.sections) do
        for i, wd in ipairs(s.widgets) do
            if wd.spec and wd.spec.key == "ShowSelf" then
                sec, self_ = s, i
            end
            if wd.spec and wd.spec.key == "ShowTargetNames" then
                target = i
                names = s
            end
        end
    end
    assertNotNil(self_, "the control is on the page")
    assertTrue(sec == names, "same group as Show target names")
    assertEquals(target + 1, self_, "right next to it")
    local spec = sec.widgets[self_].spec
    assertEquals("SpellTimer", spec.module)
    assertEquals("Show timers on yourself", spec.label)
    assertEquals("Off hides every row that is on you (your own buffs and "
        .. "self-only windows such as Rapid Fire or Berserking); rows on "
        .. "enemies and other players stay.", spec.tip)
    assertEquals(spec.tip, FX.Timer.Pages.WIDGET_TIPS.ShowSelf)
    assertEquals("SetShowSelf", M.KEYMAP.ShowSelf)
    -- the section's recycle icon restores it too
    local inKeys = false
    for _, k in ipairs(sec.spec and sec.spec.keys or {}) do
        if k == "ShowSelf" then inKeys = true end
    end
    if sec.spec then assertTrue(inKeys, "in the section's recycle key list") end
    O:Close()
end)

test("show-self tests leave the panel idle and the clock restored", function()
    cleanUp()
    assertEquals(realGetTime, _G.GetTime)
    assertNil(D.anchor:GetScript("OnUpdate"))
end)

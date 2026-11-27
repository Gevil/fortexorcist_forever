-- addon/Forte_Timer/tests/test_hide_timers.lua
-- GitHub issue #4 ("Possibly add option to either exclude specific spells, or
-- exclude spells over a certain length, from spell timers"): the Spell Timer
-- page's `HideLongerThanOn` / `HideLongerThan` pair and its `ExcludeSpells`
-- list, plus the `/fx timer exclude|include|excluded` subcommands. The shape is
-- test_show_self.lua's: every assertion drives the REAL path -- the settings
-- store (`FX.Settings:Set` -> OnChange -> Module:ApplySettings -> the setter),
-- `Module:Draw` (Rows:Sorted + Display:Update) and the frame's motion OnUpdate,
-- the real slash line (`SlashCmdList.FORTEXORCIST`, which lowercases) -- never a
-- stubbed link array.
--
-- The three display filters (ShowSelf, the total-length limit, the excluded
-- names) all decide in `Rows:Sorted`, before a link exists.

local FX = ForteXorcist
local M = FX.Timer.Module
local Rows = FX.Timer.Rows
local Laws = FX.Timer.Laws
local Casts = FX.Timer.Casts
local Registry = FX.Timer.Registry
local D = FX.Timer.Display
local ST = FX.Settings
local O = FX.Options
local Locale = FX.Locale

local MOD = "SpellTimer"
local realGetTime = _G.GetTime
local realPrint = FX.Print
local clockNow

local function setTime(t)
    clockNow = t
    _G.GetTime = function() return clockNow end
    Casts.now = function() return clockNow end
end

local fakeEntries = {}       -- registry names this file added
local fakeAliases = {}       -- locale pairs this file added

local function addFakeSpell(name)
    if Registry.entries[name] == nil then
        Registry.entries[name] = { kind = "Default" }
        fakeEntries[#fakeEntries + 1] = name
    end
end

local function addAlias(english, localized)
    Locale.localizedToEnglish[localized] = english
    Locale.englishToLocal[english] = localized
    fakeAliases[#fakeAliases + 1] = { english, localized }
end

local function resetSettings()
    ST:Set(MOD, "ShowSelf", true)
    ST:Set(MOD, "HideLongerThanOn", false)
    ST:Set(MOD, "HideLongerThan", 60)
    ST:Set(MOD, "ExcludeSpells", "")
    ST:Set(MOD, "HideLonger", false)
    ST:Set(MOD, "HideTime", Laws.HIDE_TIME)
end

local function ensure()
    if not M.options then M:OnEnable() end
    assertNotNil(D.anchor, "the display is built")
    local o = M.options
    o.enable, o.hide, o.flip, o.expand, o.outwands = true, false, false, true, true
    o.maxOn, o.maxRows, o.groupID = false, 15, true
    o.hideLonger, o.hideLongerAt = false, 30
    resetSettings()
    return o
end

local function cleanUp()
    local o = M.options
    o.maxOn, o.maxRows, o.hideLonger, o.outwands = false, 15, false, true
    o.hideLongerAt, o.groupID = 30, true
    resetSettings()
    ST:Set(MOD, "Max", 15)
    ST:Set(MOD, "MaxOn", false)
    for i = 1, #fakeEntries do Registry.entries[fakeEntries[i]] = nil end
    fakeEntries = {}
    for i = 1, #fakeAliases do
        Locale.localizedToEnglish[fakeAliases[i][2]] = nil
        Locale.englishToLocal[fakeAliases[i][1]] = nil
    end
    fakeAliases = {}
    Locale.stubItemName = nil
    FX.Print = realPrint
    Rows:Clear()
    Casts.now = nil
    _G.GetTime = realGetTime
    M:Draw()
    D:RenderIdle()
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

--- Three rows: a 30 s DoT and a 120 s DoT on two enemies (their own groups)
--- and a 20 s buff on yourself.
local function seed(base)
    setTime(base)
    Rows:Clear()
    Rows.options = M.options
    local e1 = Rows:InsertFromCast("Serpent Sting", "Dummy-1", 30, base, base,
        1, "TargetDebuff")
    local e2 = Rows:InsertFromCast("Hunter's Mark", "Dummy-2", 120, base, base,
        1, "TargetDebuff")
    local me = Rows:InsertFromCast("Frenzy Self", "none", 20, base, base, 1,
        "SelfBuff")
    assertNotNil(e1) assertNotNil(e2) assertNotNil(me)
    assertEquals(3, Rows:Count())
    for _ = 1, 40 do M:Draw() end    -- the scale ease settles
    return e1, e2, me
end

--- The raw (sparse) per-profile value of SpellTimer.<key>, nil when absent.
local function rawStored(key)
    local found
    local profiles = (FX.db and FX.db.profiles and FX.db.profiles.byName) or {}
    for _, p in pairs(profiles) do
        local t = p.settings and p.settings.SpellTimer
        if type(t) == "table" and t[key] ~= nil then found = t[key] end
    end
    return found
end

local function listEquals(expected, actual, msg)
    assertEquals(#expected, #actual, (msg or "list") .. ": length "
        .. table.concat(actual, "|"))
    for i = 1, #expected do
        assertEquals(expected[i], actual[i], (msg or "list") .. " #" .. i)
    end
end

--- Run one slash line through the REAL registry (the line is lowercased the
--- way the client does); returns the printed lines joined, and the array.
local function slash(msg)
    local printed = {}
    FX.Print = function(text) printed[#printed + 1] = tostring(text) end
    local ok, err = pcall(SlashCmdList["FORTEXORCIST"], msg)
    FX.Print = realPrint
    assertTrue(ok, "slash raised: " .. tostring(err))
    return table.concat(printed, "\n"), printed
end

local function has(text, needle)
    return text:lower():find(needle:lower(), 1, true) ~= nil
end

-- ------------------------------------------------------------------ defaults --

test("defaults change nothing: filter off, limit 60, empty list, every row drawn",
function()
    local o = ensure()
    assertEquals(false, ST:GetDefault(MOD, "HideLongerThanOn"))
    assertEquals(60, ST:GetDefault(MOD, "HideLongerThan"))
    assertEquals("", ST:GetDefault(MOD, "ExcludeSpells"))
    assertEquals(false, ST:GetDefault(MOD, "HideLonger"), "the original gate")
    assertEquals(Laws.HIDE_TIME, ST:GetDefault(MOD, "HideTime"))
    assertEquals(false, o.hideLongerThanOn)
    assertEquals(60, o.hideLongerThan)
    assertNil(o.excludeSet, "no list, no set: the sort does no extra work")
    local e1, e2, me = seed(realGetTime())
    assertEquals(3, shownBars())
    assertEquals(3, shownGroups())
    assertNotNil(slotOf(e1))
    assertNotNil(slotOf(e2))
    assertNotNil(slotOf(me))
    cleanUp()
end)

-- ------------------------------------------------------------------- parsing --

test("list parsing: commas, new lines, spaces, duplicates, empties", function()
    listEquals({ "A", "B", "C" }, Rows.ParseSpellList("A, B,C"), "commas")
    listEquals({ "A", "B", "C" }, Rows.ParseSpellList("A\nB\r\nC"), "lines")
    listEquals({ "Serpent Sting", "hunter's mark" },
        Rows.ParseSpellList("  Serpent    Sting  ,hunter's mark ,, \n ,\n"),
        "spaces and empties")
    listEquals({ "Mend Pet" },
        Rows.ParseSpellList("Mend Pet, mend pet,\nMEND PET"), "duplicates")
    listEquals({ "Mend Pet", "Rapid Fire" },
        Rows.ParseSpellList("Mend Pet\n\n,Rapid Fire, mend pet"), "mixed")
    listEquals({}, Rows.ParseSpellList(""), "empty")
    listEquals({}, Rows.ParseSpellList("   "), "blank")
    listEquals({}, Rows.ParseSpellList(",,,\n,\r\n"), "only separators")
    listEquals({}, Rows.ParseSpellList(nil), "nil")
    listEquals({}, Rows.ParseSpellList(42), "not a string")
    assertNil(Rows.BuildExcludeSet(""), "an empty list builds no set")
    assertNil(Rows.BuildExcludeSet(" , \n,"), "a list of separators neither")
    local set = Rows.BuildExcludeSet("Serpent Sting, MEND PET")
    assertNotNil(set)
    assertTrue(set.names["serpent sting"] and set.names["mend pet"],
        "stored lowercased")
end)

test("the list is parsed on change, not per frame: a draw does no parsing", function()
    local o = ensure()
    local e1 = seed(realGetTime())
    ST:Set(MOD, "ExcludeSpells", "Serpent Sting")
    local set = o.excludeSet
    assertNotNil(set)
    local real = Rows.ParseSpellList
    local calls = 0
    Rows.ParseSpellList = function(...) calls = calls + 1 return real(...) end
    for _ = 1, 20 do M:Draw() end
    Rows.ParseSpellList = real
    assertEquals(0, calls, "the draw pass only looks the name up")
    assertTrue(o.excludeSet == set, "the same set, not rebuilt")
    assertNil(slotOf(e1))
    cleanUp()
end)

-- ------------------------------------------------------------ hide longer than --

test("hide longer than: hides rows by TOTAL, strictly longer, nothing else", function()
    local o = ensure()
    local e1, e2, me = seed(realGetTime())
    ST:Set(MOD, "HideLongerThanOn", true)          -- live, no Draw call here
    assertTrue(o.hideLongerThanOn)
    assertEquals(2, shownBars(), "toggling redraws at once")
    assertNil(slotOf(e2), "total 120 > 60")
    assertNotNil(slotOf(e1))
    assertNotNil(slotOf(me))
    assertEquals(3, Rows:Count(), "the row stays in the model")
    ST:Set(MOD, "HideLongerThan", 30)               -- exactly the 30 s row
    assertEquals(30, o.hideLongerThan)
    assertNotNil(slotOf(e1), "a timer exactly this long still shows")
    ST:Set(MOD, "HideLongerThan", 25)
    assertNil(slotOf(e1))
    assertNil(slotOf(e2))
    assertNotNil(slotOf(me), "20 s <= 25 s")
    ST:Set(MOD, "HideLongerThan", 19)
    assertEquals(0, shownBars())
    assertEquals(0, shownGroups())
    assertEquals(3, Rows:Count())
    ST:Set(MOD, "HideLongerThanOn", false)
    assertEquals(3, shownBars(), "off again: everything is back")
    ST:Set(MOD, "HideLongerThan", 5)
    assertEquals(3, shownBars(), "the limit alone does nothing while off")
    cleanUp()
end)

test("hide longer than: the limit is clamped to 5..3600 and junk is ignored", function()
    local o = ensure()
    ST:Set(MOD, "HideLongerThan", 1)
    assertEquals(5, o.hideLongerThan)
    ST:Set(MOD, "HideLongerThan", 99999)
    assertEquals(3600, o.hideLongerThan)
    ST:Set(MOD, "HideLongerThan", 90)
    assertEquals(90, o.hideLongerThan)
    ST:Set(MOD, "HideLongerThan", "soon")
    assertEquals(90, o.hideLongerThan, "a non-number changes nothing")
    ST:Set(MOD, "HideLongerThan", 0 / 0)
    assertEquals(90, o.hideLongerThan, "NaN neither")
    cleanUp()
end)

-- ------------------------------------------------------------ excluded spells --

test("excluded spells: only the named spell's rows go, every other keeps its slot",
function()
    local o = ensure()
    local e1, e2, me = seed(realGetTime())
    local gy2 = D.groups[2]._ay
    ST:Set(MOD, "ExcludeSpells", "Serpent Sting")
    assertNotNil(o.excludeSet)
    assertEquals(2, shownBars())
    assertEquals(2, shownGroups())
    assertNil(slotOf(e1))
    assertNotNil(slotOf(e2))
    assertNotNil(slotOf(me))
    assertEquals(3, Rows:Count())
    assertNotNil(Rows:Find("Serpent Sting", "Dummy-1"), "still in the model")
    local hFiltered = D.anchor:GetHeight()
    ST:Set(MOD, "ExcludeSpells", "")
    assertNil(o.excludeSet)
    assertEquals(3, shownBars())
    assertEquals(gy2, D.groups[2]._ay, "back where it was")
    -- the same two rows drawn alone make the same box: no hole where the
    -- hidden row was
    Rows:Clear()
    Rows:InsertFromCast("Hunter's Mark", "Dummy-2", 120, clockNow, clockNow, 1,
        "TargetDebuff")
    Rows:InsertFromCast("Frenzy Self", "none", 20, clockNow, clockNow, 1,
        "SelfBuff")
    for _ = 1, 40 do M:Draw() end
    assertEquals(2, shownBars())
    assertTrue(math.abs(D.anchor:GetHeight() - hFiltered) < 0.5,
        "box " .. hFiltered .. " vs alone " .. D.anchor:GetHeight())
    cleanUp()
end)

test("excluded spells: case-insensitive, trimmed, commas and lines, every spell of it",
function()
    local o = ensure()
    local e1, e2, me = seed(realGetTime())
    ST:Set(MOD, "ExcludeSpells", "  SERPENT sting ")
    assertNil(slotOf(e1))
    ST:Set(MOD, "ExcludeSpells", "frenzy self,\nHUNTER'S MARK")
    assertNotNil(slotOf(e1), "the previous list is replaced, not added to")
    assertNil(slotOf(e2))
    assertNil(slotOf(me))
    assertEquals(1, shownBars())
    ST:Set(MOD, "ExcludeSpells", "Hunter's")
    assertEquals(3, shownBars(), "a part of a name is not a match")
    -- every row of the spell, on whatever target
    local e3 = Rows:InsertFromCast("Serpent Sting", "Dummy-3", 30, clockNow,
        clockNow, 1, "TargetDebuff")
    for _ = 1, 10 do M:Draw() end
    assertEquals(4, shownBars())
    ST:Set(MOD, "ExcludeSpells", "serpent sting")
    assertNil(slotOf(e1))
    assertNil(slotOf(e3))
    assertEquals(2, shownBars())
    cleanUp()
end)

test("excluded spells: a localized client's names match the English data names",
function()
    local o = ensure()
    addFakeSpell("Zorgons Wrath")
    addAlias("Zorgons Wrath", "Zornblitz")
    setTime(realGetTime())
    Rows:Clear()
    Rows.options = o
    local en = Rows:InsertFromCast("Zorgons Wrath", "Dummy-1", 30, clockNow,
        clockNow, 1, "TargetDebuff")
    local other = Rows:InsertFromCast("Serpent Sting", "Dummy-2", 30, clockNow,
        clockNow, 1, "TargetDebuff")
    for _ = 1, 10 do M:Draw() end
    assertEquals(2, shownBars())
    -- the client's name, as typed (CanonicalName -> the English data name)
    ST:Set(MOD, "ExcludeSpells", "Zornblitz")
    assertNil(slotOf(en))
    assertNotNil(slotOf(other))
    -- lowercased, as the slash line delivers it (the name as the client shows it)
    ST:Set(MOD, "ExcludeSpells", "zornblitz")
    assertNil(slotOf(en), "the display name, lowercased")
    -- the English data name on a localized client
    ST:Set(MOD, "ExcludeSpells", "ZORGONS WRATH")
    assertNil(slotOf(en))
    ST:Set(MOD, "ExcludeSpells", "Zorn")
    assertNotNil(slotOf(en), "no partial match")
    -- a row that carries the client's name itself (no data key behind it)
    local loc = Rows:InsertFromCast("Zornblitz", "Dummy-3", 30, clockNow,
        clockNow, 1, "TargetDebuff")
    ST:Set(MOD, "ExcludeSpells", "Zorgons Wrath")
    assertNil(slotOf(loc), "its English canonical is on the list")
    assertNil(slotOf(en))
    assertNotNil(slotOf(other))
    ST:Set(MOD, "ExcludeSpells", "Zornblitz")
    assertNil(slotOf(loc), "and its own name too")
    cleanUp()
end)

test("a localized name that arrives late re-judges the rows (memo dropped)", function()
    local o = ensure()
    setTime(realGetTime())
    Rows:Clear()
    Rows.options = o
    local row = Rows:InsertFromCast("Zorgons Charm", "Dummy-1", 30, clockNow,
        clockNow, 1, "TargetDebuff")
    ST:Set(MOD, "ExcludeSpells", "zorngeschenk")
    for _ = 1, 5 do M:Draw() end
    assertNotNil(slotOf(row), "no alias yet: the typed name means nothing")
    -- the real late-name path: an item's localized name loads after login
    Locale.englishByItemID[999001] = "Zorgons Charm"
    Locale.stubItemName = function(id)
        if id == 999001 then return "Zorngeschenk" end
    end
    Locale.OnItemNameArrived(999001)
    fakeAliases[#fakeAliases + 1] = { "Zorgons Charm", "Zorngeschenk" }
    Locale.englishByItemID[999001] = nil
    for _ = 1, 5 do M:Draw() end
    assertNil(slotOf(row), "the alias landed: the row is excluded now")
    cleanUp()
end)

-- ------------------------------------------------------- with ShowSelf, all three --

test("each filter alone and in every combination with ShowSelf", function()
    local o = ensure()
    local e1, e2, me = seed(realGetTime())
    for mask = 0, 7 do
        local noSelf = mask % 2 == 1
        local noLong = math.floor(mask / 2) % 2 == 1
        local noName = math.floor(mask / 4) % 2 == 1
        ST:Set(MOD, "ShowSelf", not noSelf)
        ST:Set(MOD, "HideLongerThanOn", noLong)
        ST:Set(MOD, "HideLongerThan", 60)
        ST:Set(MOD, "ExcludeSpells", noName and "Serpent Sting" or "")
        local want = 3 - (noSelf and 1 or 0) - (noLong and 1 or 0)
            - (noName and 1 or 0)
        local tag = "mask " .. mask
        assertEquals(want, shownBars(), tag)
        assertEquals(noName, slotOf(e1) == nil, tag .. " e1")
        assertEquals(noLong, slotOf(e2) == nil, tag .. " e2")
        assertEquals(noSelf, slotOf(me) == nil, tag .. " self")
        assertEquals(3, Rows:Count(), tag .. ": the model is untouched")
        local _, n = Rows:Sorted({}, clockNow)
        assertEquals(want, n, tag .. ": no link for a hidden row")
    end
    assertEquals(0, shownBars())
    assertEquals(0, shownGroups())
    assertNil(D.anchor:GetScript("OnUpdate"), "nothing moves: no per-frame Lua")
    -- one filter lifted at a time while the other two stay on
    ST:Set(MOD, "ShowSelf", true)
    assertEquals(1, shownBars())
    assertNotNil(slotOf(me))
    ST:Set(MOD, "ExcludeSpells", "")
    assertEquals(2, shownBars())
    cleanUp()
end)

test("an excluded spell stays hidden when ShowSelf comes back, and vice versa",
function()
    local o = ensure()
    local e1, e2, me = seed(realGetTime())
    ST:Set(MOD, "ExcludeSpells", "Frenzy Self")
    ST:Set(MOD, "ShowSelf", false)
    ST:Set(MOD, "ShowSelf", true)
    assertNil(slotOf(me), "the name list still hides it")
    ST:Set(MOD, "ExcludeSpells", "")
    assertNotNil(slotOf(me))
    ST:Set(MOD, "ShowSelf", false)
    ST:Set(MOD, "ExcludeSpells", "Frenzy Self")
    ST:Set(MOD, "ExcludeSpells", "")
    assertNil(slotOf(me), "ShowSelf still hides it")
    cleanUp()
end)

-- ----------------------------------------------------- no gaps, no group runs --

test("rows of one group: a hidden row between two closes the gap (both filters)",
function()
    local o = ensure()
    o.groupID = false    -- sort by drawn expiry only: the middle row sits BETWEEN
    for _, mode in ipairs({ "exclude", "long" }) do
        setTime(realGetTime())
        local base = clockNow
        Rows:Clear()
        Rows.options = o
        Rows:InsertFromCast("Serpent Sting", "Dummy-1", 10, base, base, 1,
            "TargetDebuff")
        local mid = Rows:InsertFromCast("Mend Rest", "Dummy-2", 20, base, base,
            1, "TargetDebuff")
        Rows:InsertFromCast("Hunter's Mark", "Dummy-1", 30, base, base, 1,
            "TargetDebuff")
        for _ = 1, 10 do M:Draw() end
        assertEquals(3, shownBars(), mode)
        assertEquals(3, shownGroups(), mode .. ": the middle row splits the run")
        if mode == "exclude" then
            ST:Set(MOD, "ExcludeSpells", "Mend Rest")
        else
            -- the middle row becomes the only one over the limit
            mid.total = 90
            ST:Set(MOD, "HideLongerThanOn", true)
            ST:Set(MOD, "HideLongerThan", 60)
        end
        assertEquals(2, shownBars(), mode)
        assertNil(slotOf(mid), mode)
        local ys = {}
        for i = 1, #D.rows do
            if D.rows[i].bar:IsShown() then
                ys[#ys + 1] = select(5, D.rows[i].bar:GetPoint())
            end
        end
        table.sort(ys)
        assertEquals(2, #ys)
        assertTrue(math.abs((ys[2] - ys[1]) - (o.height + o.space)) < 0.5,
            mode .. ": adjacent slots, no hole: " .. ys[1] .. "," .. ys[2])
        assertEquals(1, shownGroups(), mode .. ": one run")
        resetSettings()
    end
    cleanUp()
end)

-- ------------------------------------------------------------------ restoring --

for _, f in ipairs({
    { name = "excluded spell", total = 20,
      on = function() ST:Set(MOD, "ExcludeSpells", "frenzy self") end,
      off = function() ST:Set(MOD, "ExcludeSpells", "") end,
      victim = 3 },
    { name = "long timer", total = 120,
      on = function() ST:Set(MOD, "HideLongerThanOn", true) end,
      off = function() ST:Set(MOD, "HideLongerThanOn", false) end,
      victim = 2 },
}) do
    test("re-enabling a hidden " .. f.name .. " shows the correct time at once",
    function()
        local o = ensure()
        local base = realGetTime()
        local rows = { seed(base) }
        local row = rows[f.victim]
        f.on()
        assertNil(slotOf(row))
        local expireBefore = row.expireAt
        for i = 1, 25 do          -- time passes while hidden
            setTime(base + i * 0.2)
            M:Draw()
        end
        assertEquals(expireBefore, row.expireAt)
        assertNil(slotOf(row))
        assertEquals(3, Rows:Count())
        f.off()
        local slot = slotOf(row)
        assertNotNil(slot, "back at once")
        assertEquals(3, shownBars())
        for _ = 1, 60 do M:Draw() end
        local value = slot.bar:GetValue()
        assertTrue(math.abs(value - Laws.BarVal(row.drawExpireAt, clockNow,
            row.maxTime)) < 1e-3)
        assertTrue(math.abs((row.expireAt - clockNow) - (f.total - 5)) < 1e-6,
            "5 s elapsed while hidden")
        assertTrue(value > 0 and value <= 1)
        if f.total <= 30 then
            assertTrue(value < 1, "a 20 s row with 15 s left is not full")
        end
        setTime(base + 6)                 -- the motion pass moves it too
        D.anchor:GetScript("OnUpdate")(D.anchor, 0.01)
        assertTrue(math.abs(slot.bar:GetValue()
            - Laws.BarVal(row.drawExpireAt, clockNow, row.maxTime)) < 1e-3)
        cleanUp()
    end)
end

test("a row that EXPIRES while excluded is not resurrected", function()
    local o = ensure()
    local base = realGetTime()
    local e1, e2, me = seed(base)
    for _, r in ipairs({ e1, e2 }) do         -- the others outlive the run
        r.total, r.expireAt, r.drawExpireAt = 300, base + 300, base + 300
    end
    M:Draw()
    ST:Set(MOD, "ExcludeSpells", "Frenzy Self")
    setTime(base + 25)                    -- past the 20 s window
    M:Logic()
    for i = 1, 30 do
        setTime(base + 25 + i * 0.2)
        M:Logic()
        M:Draw()
    end
    assertNil(Rows:Find("Frenzy Self", "none"), "the model expired it as before")
    ST:Set(MOD, "ExcludeSpells", "")
    assertEquals(2, shownBars())
    cleanUp()
end)

-- ------------------------------------------------------------------- maxRows --

test("maxRows counts only the rows that are drawn (both filters)", function()
    local o = ensure()
    local base = realGetTime()
    setTime(base)
    Rows:Clear()
    Rows.options = o
    -- two rows the filters will hide, two that stay; the cap is 2
    Rows:InsertFromCast("Hidden Name", "Dummy-1", 20, base, base, 1,
        "TargetDebuff")
    Rows:InsertFromCast("Hidden Long", "Dummy-2", 200, base, base, 1,
        "TargetDebuff")
    Rows:InsertFromCast("Serpent Sting", "Dummy-3", 30, base, base, 1,
        "TargetDebuff")
    Rows:InsertFromCast("Hunter's Mark", "Dummy-4", 40, base, base, 1,
        "TargetDebuff")
    ST:Set(MOD, "MaxOn", true)
    ST:Set(MOD, "Max", 6)
    o.maxRows = 2                         -- below the page's 4..64 field
    for _ = 1, 10 do M:Draw() end
    assertEquals(2, shownBars(), "capped while nothing is filtered")
    ST:Set(MOD, "ExcludeSpells", "Hidden Name")
    ST:Set(MOD, "HideLongerThanOn", true)
    -- the cap would be eaten by the hidden rows if they were counted
    assertEquals(2, shownBars())
    local links, n = Rows:Sorted({}, clockNow)
    assertEquals(2, n, "hidden rows have no link at all")
    for k = 1, n do
        local name = Rows.rows[links[k][1]].name
        assertTrue(name == "Serpent Sting" or name == "Hunter's Mark", name)
        assertTrue(links[k][4] > 0, "both are within the cap")
    end
    assertEquals(4, Rows:Count())
    o.maxRows = 15
    cleanUp()
end)

-- --------------------------------------------------------------------- fading --

for _, f in ipairs({
    { name = "excluded spell", victim = 3,
      on = function() ST:Set(MOD, "ExcludeSpells", "Frenzy Self") end,
      off = function() ST:Set(MOD, "ExcludeSpells", "") end },
    { name = "long timer", victim = 2,
      on = function() ST:Set(MOD, "HideLongerThanOn", true) end,
      off = function() ST:Set(MOD, "HideLongerThanOn", false) end },
}) do
    test("a fading " .. f.name .. " does not flash when the filter flips",
    function()
        local o = ensure()
        local base = realGetTime()
        local rows = { seed(base) }
        local row = rows[f.victim]
        row.state = Laws.FADING
        row.removeAt = base - 1             -- the cubic fall starts at base
        local function height(t)
            setTime(t)
            M:Draw()
            local r = slotOf(row)
            return r and r.bar:GetHeight()
        end
        local function want(t)
            return o.height * Laws.Alpha(row.removeAt + (o.fadeTime or Laws.FADE), t)
        end
        local h1
        if f.victim == 3 then h1 = height(base + 0.10) end
        f.on()
        assertNil(height(base + 0.14))
        f.off()
        setTime(base + 0.18)
        M:Draw()
        local h3 = slotOf(row).bar:GetHeight()
        assertTrue(math.abs(h3 - want(base + 0.18)) < 0.02,
            "back on the ramp, not at full height: " .. h3)
        if h1 then assertTrue(h3 < h1, "the ramp kept falling while hidden") end
        cleanUp()
    end)

    test("the HideLonger stamp survives a hidden " .. f.name .. " stretch",
    function()
        local o = ensure()
        local base = realGetTime()
        local rows = { seed(base) }
        local row = rows[f.victim]
        ST:Set(MOD, "HideLonger", true)
        ST:Set(MOD, "HideTime", 3)
        o.hideLongerAt = 10
        setTime(base + 1)
        M:Draw()
        local stamp = row.hiddenSince
        assertTrue(stamp > 0, "the gate tripped")
        f.on()
        setTime(base + 2)
        M:Draw()
        assertEquals(stamp, row.hiddenSince, "the gate kept running, unrestarted")
        f.off()
        setTime(base + 2.5)
        M:Draw()
        assertEquals(stamp, row.hiddenSince, "the stamp is the same, not restarted")
        cleanUp()
    end)
end

-- ------------------------------------------------ the original gate, not broken --

test("HideLonger (hide until the LAST 30 s) and the new limit (never show over N s) differ",
function()
    local o = ensure()
    local base = realGetTime()
    setTime(base)
    Rows:Clear()
    Rows.options = o
    local long = Rows:InsertFromCast("Hunter's Mark", "Dummy-1", 120, base,
        base, 1, "TargetDebuff")
    long.expireAt, long.drawExpireAt = base + 20, base + 20      -- 20 s LEFT
    local mid = Rows:InsertFromCast("Serpent Sting", "Dummy-2", 40, base, base,
        1, "TargetDebuff")
    mid.expireAt, mid.drawExpireAt = base + 35, base + 35        -- 35 s LEFT
    local function alphas(t)
        setTime(t)
        local links, n = Rows:Sorted({}, t)
        local out = {}
        for k = 1, n do out[Rows.rows[links[k][1]]] = links[k][4] end
        return out, n
    end
    -- the original gate: a timer with >= 30 s left is held back
    ST:Set(MOD, "HideLonger", true)
    ST:Set(MOD, "HideTime", 1)
    local a = alphas(base + 0.5)
    assertEquals(1, a[mid], "visible for HideTime after it appears")
    a = alphas(base + 3)
    assertEquals(0, a[mid], "then held back (35 - 3 = 32 s left, still >= 30)")
    assertEquals(1, a[long], "120 s total but only 20 s left: the gate lets it show")
    assertTrue(mid.hiddenSince > 0, "the gate's stamp is set")
    ST:Set(MOD, "HideLonger", false)
    ST:Set(MOD, "HideTime", Laws.HIDE_TIME)
    -- the new limit: judged on the TOTAL, whatever is left
    ST:Set(MOD, "HideLongerThanOn", true)
    ST:Set(MOD, "HideLongerThan", 60)
    local b, n = alphas(base + 3)
    assertEquals(1, n, "the 120 s row has no link")
    assertNil(b[long], "hidden although only 20 s are left")
    assertEquals(1, b[mid], "the 40 s row is shown, 35 s left or not")
    cleanUp()
end)

-- ------------------------------------------------------------- motion pass ----

for _, f in ipairs({
    { name = "excluded spell",
      on = function() ST:Set(MOD, "ExcludeSpells", "Frenzy Self") end },
    { name = "long timer",
      on = function() ST:Set(MOD, "HideLongerThanOn", true) end },
}) do
    test("hidden rows (" .. f.name .. ") are not in the run; the motion pass stays allocation-free",
    function()
        local o = ensure()
        local base = realGetTime()
        local e1, e2, me = seed(base)
        f.on()
        for _ = 1, 20 do M:Draw() end
        local fn = D.anchor:GetScript("OnUpdate")
        assertNotNil(fn, "the other rows still move")
        local c = D.counts
        local before = c.motionRows
        setTime(base + 0.5)
        fn(D.anchor, 1 / 165)
        assertEquals(2, c.motionRows - before, "the hidden row is not in the run")
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
end

test("Rows:Sorted allocates nothing in the steady state with both filters hiding the LAST rows",
function()
    local o = ensure()
    local base = realGetTime()
    setTime(base)
    Rows:Clear()
    Rows.options = o
    Rows:InsertFromCast("Serpent Sting", "Dummy-1", 30, base, base, 1,
        "TargetDebuff")
    Rows:InsertFromCast("Hunter's Mark", "Dummy-2", 120, base, base, 1,
        "TargetDebuff")                  -- over the limit, second to last
    Rows:InsertFromCast("Frenzy Self", "none", 20, base, base, 1, "SelfBuff")
    ST:Set(MOD, "HideLongerThanOn", true)
    ST:Set(MOD, "ExcludeSpells", "Frenzy Self")   -- excluded, last
    local out = {}
    for _ = 1, 5 do Rows:Sorted(out, clockNow) end
    local _, n = Rows:Sorted(out, clockNow)
    assertEquals(1, n)
    collectgarbage("stop")
    collectgarbage("count")
    local g0 = collectgarbage("count")
    for _ = 1, 1000 do Rows:Sorted(out, clockNow) end
    local g1 = collectgarbage("count")
    collectgarbage("restart")
    assertEquals(0, g1 - g0, "Sorted allocated " .. ((g1 - g0) * 1024))
    cleanUp()
end)

-- ------------------------------------------------------------------ the slash --

test("slash: exclude / include / excluded, names with spaces, idempotent", function()
    local o = ensure()
    local e1, e2, me = seed(realGetTime())
    local text = slash("timer excluded")
    assertTrue(has(text, "no spells are excluded"), text)

    text = slash("timer exclude Serpent Sting")
    assertTrue(has(text, "excluding serpent sting"), text)
    assertEquals("serpent sting", ST:Get(MOD, "ExcludeSpells"):lower())
    assertNil(slotOf(e1), "live at once")
    assertNotNil(slotOf(e2))
    assertNotNil(slotOf(me))

    local stored = ST:Get(MOD, "ExcludeSpells")
    text = slash("timer exclude SERPENT STING")
    assertTrue(has(text, "already excluded"), text)
    assertFalse(has(text, "timer: excluding"), text)
    assertEquals(stored, ST:Get(MOD, "ExcludeSpells"), "idempotent: not changed")

    text = slash("timer exclude Hunter's Mark, Frenzy Self")
    assertTrue(has(text, "excluding hunter's mark, frenzy self"), text)
    assertEquals(0, shownBars(), "all three are off now")
    text = slash("timer excluded")
    assertTrue(has(text, "3 excluded"), text)
    assertTrue(has(text, "serpent sting") and has(text, "hunter's mark")
        and has(text, "frenzy self"), text)

    text = slash("timer include FRENZY self")
    assertTrue(has(text, "showing again frenzy self"), text)
    assertNotNil(slotOf(me), "back at once")
    assertNil(slotOf(e1))
    text = slash("timer include frenzy self")
    assertTrue(has(text, "not excluded: frenzy self"), text)
    assertEquals(1, shownBars())
    text = slash("timer excluded")
    assertTrue(has(text, "2 excluded"), text)
    assertFalse(has(text, "frenzy"), text)

    -- the command also works through the page's own text
    ST:Set(MOD, "ExcludeSpells", "Alpha Spell\nBeta Spell, serpent sting")
    text = slash("timer excluded")
    assertTrue(has(text, "3 excluded") and has(text, "alpha spell")
        and has(text, "beta spell"), text)
    text = slash("timer include beta spell")
    assertTrue(has(text, "showing again"), text)
    assertEquals("Alpha Spell, serpent sting", ST:Get(MOD, "ExcludeSpells"))

    text = slash("timer include alpha spell, serpent sting, hunter's mark")
    assertTrue(has(text, "not excluded: hunter's mark"), text)
    assertEquals("", ST:Get(MOD, "ExcludeSpells"))
    assertNil(rawStored("ExcludeSpells"), "an empty list is the default: not stored")
    assertEquals(3, shownBars())
    cleanUp()
end)

test("slash: a spell that was never cast can be excluded, and is hidden when it is",
function()
    local o = ensure()
    seed(realGetTime())
    local text = slash("timer exclude Some Spell Nobody Cast")
    assertTrue(has(text, "excluding some spell nobody cast"), text)
    assertEquals(3, shownBars(), "no row of it exists: nothing changes")
    local late = Rows:InsertFromCast("Some Spell Nobody Cast", "Dummy-9", 30,
        clockNow, clockNow, 1, "TargetDebuff")
    assertNotNil(late)
    for _ = 1, 10 do M:Draw() end
    assertNil(slotOf(late))
    assertEquals(3, shownBars())
    text = slash("timer include some spell nobody cast")
    assertTrue(has(text, "showing again"), text)
    assertNotNil(slotOf(late))
    cleanUp()
end)

test("slash: usage on an empty name changes nothing; the registry's spelling is kept",
function()
    local o = ensure()
    seed(realGetTime())
    local text = slash("timer exclude")
    assertTrue(has(text, "/fx timer exclude <spell name>"), text)
    text = slash("timer exclude    ")
    assertTrue(has(text, "/fx timer exclude <spell name>"), text)
    text = slash("timer include ,, ,")
    assertTrue(has(text, "/fx timer include <spell name>"), text)
    assertEquals("", ST:Get(MOD, "ExcludeSpells"))
    assertEquals(3, shownBars())
    -- the slash line arrives lowercased; a spell the registry knows is stored
    -- in its own spelling, by its English name or by the client's
    addFakeSpell("Zorgons Wrath")
    addAlias("Zorgons Wrath", "Zornblitz")
    slash("timer exclude zorgons wrath")
    assertEquals("Zorgons Wrath", ST:Get(MOD, "ExcludeSpells"))
    slash("timer exclude zornblitz")
    assertEquals("Zorgons Wrath", ST:Get(MOD, "ExcludeSpells"),
        "the client's name is the same spell: already there")
    slash("timer include ZORNBLITZ")
    assertEquals("", ST:Get(MOD, "ExcludeSpells"), "removed by the client's name")
    -- the usage line lists the new subcommands
    text = slash("timer help")
    assertTrue(has(text, "exclude <spell>") and has(text, "include <spell>")
        and has(text, "excluded"), text)
    cleanUp()
end)

-- ---------------------------------------------------------------- the store ---

test("the store is sparse: a default is not written, a non-default is", function()
    local o = ensure()
    -- defaults are dropped
    ST:Set(MOD, "HideLongerThanOn", false)
    ST:Set(MOD, "HideLongerThan", 60)
    ST:Set(MOD, "ExcludeSpells", "")
    assertNil(rawStored("HideLongerThanOn"))
    assertNil(rawStored("HideLongerThan"))
    assertNil(rawStored("ExcludeSpells"))
    -- non-defaults are kept
    ST:Set(MOD, "HideLongerThanOn", true)
    ST:Set(MOD, "HideLongerThan", 90)
    ST:Set(MOD, "ExcludeSpells", "Serpent Sting, Mend Pet")
    assertEquals(true, rawStored("HideLongerThanOn"))
    assertEquals(90, rawStored("HideLongerThan"))
    assertEquals("Serpent Sting, Mend Pet", rawStored("ExcludeSpells"))
    -- the login pull applies the stored values to a fresh options table
    o.hideLongerThanOn, o.hideLongerThan, o.excludeSet = false, 60, nil
    M:ApplyStoredSettings()
    assertTrue(o.hideLongerThanOn)
    assertEquals(90, o.hideLongerThan)
    assertNotNil(o.excludeSet)
    assertTrue(o.excludeSet.names["mend pet"])
    assertEquals(2, #M:ExcludedList())
    -- back to the defaults: the keys are dropped again
    ST:Set(MOD, "HideLongerThanOn", false)
    ST:Set(MOD, "HideLongerThan", 60)
    ST:Set(MOD, "ExcludeSpells", "")
    assertNil(rawStored("HideLongerThanOn"))
    assertNil(rawStored("HideLongerThan"))
    assertNil(rawStored("ExcludeSpells"))
    assertNil(o.excludeSet)
    assertFalse(o.hideLongerThanOn)
    -- the recycle path (Reset) restores them too
    ST:Set(MOD, "ExcludeSpells", "A")
    ST:Reset(MOD, "ExcludeSpells")
    assertNil(rawStored("ExcludeSpells"))
    assertNil(o.excludeSet)
    cleanUp()
end)

-- ----------------------------------------------------------------- the page ---

test("the page lists the controls with their tips, beside each other", function()
    local o = ensure()
    assertNotNil(O and O.pages and O.pages["SpellTimer"])
    O:Open("SpellTimer")
    local page = O.pagesBuilt["SpellTimer"]
    assertNotNil(page)
    local found, sectionOf, indexOf = {}, {}, {}
    for _, s in ipairs(page.sections) do
        for i, wd in ipairs(s.widgets) do
            local key = wd.spec and wd.spec.key
            if key then found[key] = wd; sectionOf[key] = s; indexOf[key] = i end
        end
    end
    local TIPS = FX.Timer.Pages.WIDGET_TIPS
    local expect = {
        ExcludeSpells = "Excluded spells",
        HideLongerThanOn = "Hide timers longer than",
        HideLongerThan = "Longer than (seconds)",
        HideLonger = "Hide until the last 30 s",
        HideTime = "Held back timers visible for (s)",
    }
    for key, label in pairs(expect) do
        local wd = found[key]
        assertNotNil(wd, key .. " is on the page")
        assertEquals("SpellTimer", wd.spec.module)
        assertEquals(label, wd.spec.label, key)
        assertTrue(type(wd.spec.tip) == "string" and #wd.spec.tip > 40, key)
        assertEquals(TIPS[key], wd.spec.tip, key .. ": the one tip table")
        assertTrue(sectionOf[key] == sectionOf.ExcludeSpells,
            key .. " is in the same group")
        assertNotNil(M.KEYMAP[key], key .. " rides the module's key map")
    end
    assertEquals("SetHideLongerThanOn", M.KEYMAP.HideLongerThanOn)
    assertEquals("SetHideLongerThan", M.KEYMAP.HideLongerThan)
    assertEquals("SetExcludeSpells", M.KEYMAP.ExcludeSpells)
    assertEquals("SetHideLonger", M.KEYMAP.HideLonger, "the original gate's setter")
    assertEquals("SetHideTime", M.KEYMAP.HideTime)
    -- the checkbox is directly followed by its number field
    assertEquals(indexOf.HideLongerThanOn + 1, indexOf.HideLongerThan)
    assertEquals(indexOf.HideLonger + 1, indexOf.HideTime)
    -- the two kinds of hiding are told apart in the tips
    assertTrue(TIPS.HideLongerThanOn:find("TOTAL", 1, true))
    assertTrue(TIPS.HideLongerThanOn:find("Hide until the last 30 s", 1, true))
    assertTrue(TIPS.HideLonger:find("LEFT", 1, true))
    assertTrue(TIPS.HideLonger:find("Hide timers longer than", 1, true))
    assertTrue(TIPS.HideLonger:find("30 s", 1, true), "the fixed threshold is stated")
    assertTrue(TIPS.ExcludeSpells:find("commas", 1, true))
    assertTrue(TIPS.ExcludeSpells:find("/fx timer exclude", 1, true))
    assertTrue(TIPS.HideLongerThan:find("5 to 3600", 1, true))
    -- the section's recycle icon restores them
    local keys = sectionOf.ExcludeSpells.spec and sectionOf.ExcludeSpells.spec.keys
    if keys then
        local inKeys = {}
        for _, k in ipairs(keys) do inKeys[k] = true end
        for key in pairs(expect) do assertTrue(inKeys[key], key .. " in the recycle keys") end
    end
    -- the Show-self checkbox is where it was
    assertEquals(indexOf.ShowTargetNames + 1, indexOf.ShowSelf)
    assertTrue(sectionOf.ShowSelf ~= sectionOf.ExcludeSpells)

    -- the real widgets: typing in the box and Enter / the checkbox click
    -- reach the live filter through the store
    local e1, e2, me = seed(realGetTime())
    local eb = found.ExcludeSpells.obj
    eb:SetText("serpent sting, hunter's mark")
    eb:GetScript("OnEnterPressed")(eb)
    assertEquals("serpent sting, hunter's mark", ST:Get(MOD, "ExcludeSpells"))
    assertEquals(1, shownBars())
    assertNotNil(slotOf(me))
    eb:SetText("")
    eb:GetScript("OnEnterPressed")(eb)
    assertEquals(3, shownBars())
    local cb = found.HideLongerThanOn.obj
    cb:GetScript("OnClick")(cb)
    assertTrue(ST:Get(MOD, "HideLongerThanOn"))
    assertNil(slotOf(e2))
    local nb = found.HideLongerThan.obj
    nb:SetText("2")
    nb:GetScript("OnEnterPressed")(nb)
    assertEquals(5, ST:Get(MOD, "HideLongerThan"), "the field clamps to 5")
    assertEquals(0, shownBars(), "every row is longer than 5 s")
    nb:SetText("50000")
    nb:GetScript("OnEnterPressed")(nb)
    assertEquals(3600, ST:Get(MOD, "HideLongerThan"), "and to 3600")
    assertEquals(3, shownBars())
    O:Close()
    cleanUp()
end)

test("hide-timer tests leave the panel idle and the clock restored", function()
    cleanUp()
    assertEquals(realGetTime, _G.GetTime)
    assertEquals(realPrint, FX.Print)
    assertNil(D.anchor:GetScript("OnUpdate"))
    assertEquals("", ST:Get(MOD, "ExcludeSpells"))
    assertFalse(ST:Get(MOD, "HideLongerThanOn"))
end)

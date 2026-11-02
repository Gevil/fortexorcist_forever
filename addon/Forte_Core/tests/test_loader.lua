-- addon/Forte_Core/tests/test_loader.lua
-- The load-on-demand split (Core/Loader.lua + the PLAYER_LOGIN /
-- RefreshPlayerClass wiring in Core/Init.lua), proven on the real sim
-- registry:
--
--   * every Forte_<Class> add-on is `## LoadOnDemand: 1`, so at login the
--     client parses NONE of its Lua;
--   * Core loads exactly the player's own class add-on, so the other eight
--     class data sets are absent for the whole session;
--   * modules registered by a late load (after the PLAYER_LOGIN enable loop)
--     are enabled immediately, exactly once, in registration order;
--   * a class change (FX.RefreshPlayerClass) pulls in the NEW class's add-on;
--   * a failing LoadAddOn prints one notice and leaves the session alive.
--
-- The sim is the proof surface here (PLAN §10.2: the sim is the only API
-- proof). The suite runs with the sim's default class (Paladin), so
-- Forte_Paladin is the one data set that must be present.
--
-- Stubs: the failure-path test swaps _G.C_AddOns and FX.Print -- globals the
-- sim permits replacing, and both are restored. The loader's C_AddOns use is
-- itself proven by every other test in this file, which uses the real
-- registry and the real LoadAddOn.

local FX = ForteXorcist

local function titleCase(token)
    if type(token) ~= "string" or token == "" then return nil end
    return token:sub(1, 1) .. token:sub(2):lower()
end

local function loadedSet()
    local set = {}
    for _, name in pairs(FX.CLASS_ADDONS) do
        if C_AddOns.IsAddOnLoaded(name) then set[#set + 1] = name end
    end
    table.sort(set)
    return set
end

local function strip(name)
    FX.modules[name] = nil
    FX._enabledModules[name] = nil
    for i = #FX._moduleOrder, 1, -1 do
        if FX._moduleOrder[i] == name then table.remove(FX._moduleOrder, i) end
    end
end

-- ------------------------------------------------------------------ names --

test("the class map names one add-on per Forever class and no Death Knight",
function()
    assertEquals(9, (function()
        local n = 0
        for _ in pairs(FX.CLASS_ADDONS) do n = n + 1 end
        return n
    end)(), "nine class families on Forever 1.60.1 (PLAN §9), no Death Knight")
    assertEquals("Forte_Hunter", FX.ClassAddOnFor("HUNTER"))
    assertEquals("Forte_Hunter", FX.ClassAddOnFor("hunter"), "case-insensitive token")
    assertNil(FX.ClassAddOnFor("DEATHKNIGHT"))
    assertNil(FX.ClassAddOnFor(nil))
    assertNil(FX.ClassAddOnFor(7))
end)

-- ------------------------------------------------- the real registry state --

test("Forte_Items is always loaded: its data set is in the session", function()
    assertNotNil(FX.Data, "the data namespace exists")
    assertNotNil(FX.Data.Items, "Forte_Items is not load-on-demand")
    assertTrue(C_AddOns.IsAddOnLoaded("Forte_Items"))
end)

test("exactly the player's class add-on is loaded, the other eight are not",
function()
    local own = FX.ClassAddOnFor(FX._playerClass)
    assertNotNil(own, "the sim profile's class has a Forte add-on")
    local loaded = loadedSet()
    assertEquals(1, #loaded, "loaded class add-ons: " .. table.concat(loaded, ","))
    assertEquals(own, loaded[1])
    assertTrue(C_AddOns.IsAddOnLoaded(own), "the player's own class add-on is in")
    for _, name in pairs(FX.CLASS_ADDONS) do
        if name ~= own then
            assertFalse(C_AddOns.IsAddOnLoaded(name), name .. " must stay unloaded")
            assertFalse(C_AddOns.IsAddOnLoadOnDemand(name) == false,
                name .. " must still be declared load-on-demand")
        end
    end
end)

test("exactly the player's class data table is in, the others are absent",
function()
    local key = titleCase(FX._playerClass)
    assertNotNil(FX.Data[key], "the player's class data table")
    for _, name in pairs(FX.CLASS_ADDONS) do
        local dataKey = name:gsub("^Forte_", "")
        if dataKey ~= key then
            assertNil(FX.Data[dataKey], dataKey .. " data must not be parsed")
            assertNil(FX.Data[dataKey .. "ByName"], dataKey .. "ByName must not be parsed")
        end
    end
end)

test("the player's class modules registered late are enabled exactly once",
function()
    local key = titleCase(FX._playerClass)
    local hasModules = (key == "Hunter" and FX.modules.Hunter ~= nil)
        or (key == "Warlock" and FX.modules.Warlock ~= nil)
    if not hasModules then
        print("[loader] the profile class has no modules -- enable proof skipped")
        return
    end
    -- The class add-on's files ran inside PLAYER_LOGIN, and the login enable
    -- loop owns that pass: the modules are registered and enabled.
    for _, name in ipairs({ "Hunter", "HunterUI", "Warlock", "WarlockUI" }) do
        if FX.modules[name] then
            assertEquals(true, FX._enabledModules[name], name .. " was enabled")
        end
    end
    -- The exactly-once law: a repeat enable must not re-run OnEnable.
    for _, name in ipairs({ "Hunter", "HunterUI", "Warlock", "WarlockUI" }) do
        local mod = FX.modules[name]
        if mod then
            local calls, real = 0, mod.OnEnable
            mod.OnEnable = function(m) calls = calls + 1; return real(m) end
            FX.EnableModule(name)
            mod.OnEnable = real
            assertEquals(0, calls, name .. " must not enable a second time")
        end
    end
end)

-- --------------------------------------------------- late registration law --

test("a module registered after PLAYER_LOGIN enables at once, in order, once",
function()
    assertTrue(FX._loginDone, "PLAYER_LOGIN ran before the tests")
    local log = {}
    FX.RegisterModule("__FxLateA", { OnEnable = function() log[#log + 1] = "A" end })
    FX.RegisterModule("__FxLateB", { OnEnable = function() log[#log + 1] = "B" end })
    assertEquals(2, #log, "both enabled at registration, no login loop needed")
    assertEquals("A", log[1], "registration order")
    assertEquals("B", log[2], "registration order")
    assertEquals(true, FX._enabledModules.__FxLateA)
    -- The ledger is what makes it exactly-once.
    FX.EnableModule("__FxLateA")
    FX.EnableModule("__FxLateB")
    assertEquals(2, #log, "a repeat enable changes nothing")
    strip("__FxLateA")
    strip("__FxLateB")
end)

test("a module whose OnEnable raises is enabled once and reported, not retried",
function()
    local printed, realPrint = {}, FX.Print
    FX.Print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end
    local calls = 0
    FX.RegisterModule("__FxLateBoom", {
        OnEnable = function()
            calls = calls + 1
            error("FXTEST-ONENABLE-RAISE", 0)
        end,
    })
    FX.Print = realPrint
    assertEquals(1, calls, "the raise is caught; the enable is not retried")
    assertEquals(1, #printed)
    assertTrue(printed[1]:find("__FxLateBoom failed to enable", 1, true) ~= nil,
        "the notice names the module: " .. tostring(printed[1]))
    assertTrue(printed[1]:find("FXTEST-ONENABLE-RAISE", 1, true) ~= nil)
    assertEquals(true, FX._enabledModules.__FxLateBoom, "marked enabled anyway")
    FX.EnableModule("__FxLateBoom")
    assertEquals(1, calls)
    strip("__FxLateBoom")
end)

test("the login loop never runs a second time", function()
    -- PLAYER_LOGIN fired once at startup; a module registered now is enabled
    -- by the registration tail, so a second login pass (a tool's reload, a
    -- zone-in) can not enable anyone twice.
    assertTrue(FX._loginDone)
    local n = 0
    for _ in pairs(FX._enabledModules) do n = n + 1 end
    for _, name in ipairs(FX._moduleOrder) do
        assertEquals(true, FX._enabledModules[name], name .. " is in the ledger")
    end
    assertEquals(#FX._moduleOrder, n, "the ledger is exactly the registry")
end)

-- ------------------------------------------------------- the class change --

test("a class change loads the new class add-on and enables its modules",
function()
    local savedUC, savedClass = _G.UnitClass, FX._playerClass
    if savedClass == "WARLOCK" then
        print("[loader] profile is already a Warlock -- change proof skipped")
        return
    end
    assertNil(FX.Data.Warlock, "the new class's data starts unparsed")
    assertNil(FX.modules.Warlock, "and its modules are unregistered")

    _G.UnitClass = function() return nil, "WARLOCK" end
    local notified = {}
    local realOnClassChanged = FX.modules.Cooldown
        and FX.modules.Cooldown.OnClassChanged
    if FX.modules.Cooldown then
        FX.modules.Cooldown.OnClassChanged = function(m, c)
            notified[#notified + 1] = c
            if realOnClassChanged then return realOnClassChanged(m, c) end
        end
    end
    FX.RefreshPlayerClass()

    assertEquals("WARLOCK", FX._playerClass)
    assertNotNil(FX.Data.Warlock, "RefreshPlayerClass loaded the new class add-on")
    assertNotNil(FX.modules.Warlock, "its module registered")
    assertEquals(true, FX._enabledModules.Warlock, "and was enabled at once")
    assertNotNil(FX.modules.WarlockUI, "its UI module too")
    assertEquals(true, FX._enabledModules.WarlockUI)
    assertTrue(FX.Warlock.Tools._eventsEnabled,
        "the freshly enabled module saw the NEW class in OnEnable")
    if FX.modules.Cooldown then
        assertEquals(1, #notified, "the login-era modules got the wave once")
        assertEquals("WARLOCK", notified[1])
        FX.modules.Cooldown.OnClassChanged = realOnClassChanged
    end
    assertNil(FX.Data.Mage, "and no other class came along")

    -- Restore: the class goes back, the Warlock modules go silent. They stay
    -- registered (unloading a add-on mid-session is not a thing) and the
    -- ledger keeps them, which is exactly what the next test asserts.
    _G.UnitClass = savedUC
    FX.RefreshPlayerClass()
    assertEquals(savedClass, FX._playerClass)
    assertFalse(FX.Warlock.Tools._eventsEnabled,
        "the restored class leaves the Warlock module silent")
    assertEquals(true, FX._enabledModules.Warlock, "the ledger keeps it enabled")
end)

test("a class change with no add-on for the new class changes nothing",
function()
    local savedUC, savedClass = _G.UnitClass, FX._playerClass
    _G.UnitClass = function() return nil, "DEATHKNIGHT" end
    local printed, realPrint = {}, FX.Print
    FX.Print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end
    FX.RefreshPlayerClass()
    FX.Print = realPrint
    _G.UnitClass = savedUC
    assertEquals("DEATHKNIGHT", FX._playerClass, "the token is still re-read")
    -- No add-on for a class is not an error: the LOADER prints nothing (other
    -- modules may report their own "no data for your class" line).
    for _, line in ipairs(printed) do
        assertFalse(line:find("did not load", 1, true) ~= nil, "loader notice: " .. line)
        assertFalse(line:find("Forte_Deathknight", 1, true) ~= nil, "named it: " .. line)
    end
    assertNil(FX.Data.Deathknight)
    FX._playerClass = savedClass
    FX.RefreshPlayerClass()
    assertEquals(savedClass, FX._playerClass)
end)

-- --------------------------------------------------------- the failure path --

test("a failing LoadAddOn prints ONE notice, is remembered, and continues",
function()
    local savedAddOns, savedPrint, savedLedger = _G.C_AddOns, FX.Print, FX._loadedAddOns
    local calls = 0
    _G.C_AddOns = {
        IsAddOnLoaded = function() return false, false end,
        IsAddOnLoadOnDemand = function() return true end,
        IsAddOnLoadable = function() return false end,
        LoadAddOn = function(name)
            calls = calls + 1
            assertEquals("Forte_Mage", name)
            return false, "DISABLED"
        end,
    }
    local printed = {}
    FX.Print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end
    local ok = FX.LoadClassAddOn("MAGE")
    local ok2 = FX.LoadClassAddOn("MAGE")
    local ok3 = FX.LoadClassAddOn("mage")
    FX.Print = savedPrint
    _G.C_AddOns = savedAddOns
    FX._loadedAddOns = savedLedger

    assertFalse(ok, "a disabled add-on is a failed load")
    assertFalse(ok2, "and it stays failed")
    assertFalse(ok3)
    assertEquals(1, calls, "the second and third call ride the ledger, not the loader")
    assertEquals(1, #printed, "exactly one notice: " .. table.concat(printed, " / "))
    assertTrue(printed[1]:find("Forte_Mage", 1, true) ~= nil)
    assertTrue(printed[1]:find("DISABLED", 1, true) ~= nil, "the loader's reason is printed")
    assertNil(FX.Data.Mage, "the session carries no Mage data")
    assertNotNil(FX.Compat, "and the session is alive")
end)

test("LoadClassAddOn is idempotent on the loaded class and quiet on no-add-on classes",
function()
    local printed, realPrint = {}, FX.Print
    FX.Print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end
    local own = FX.ClassAddOnFor(FX._playerClass)
    assertTrue(FX.LoadClassAddOn(FX._playerClass), "the loaded class loads again true")
    assertTrue(FX.LoadClassAddOn(FX._playerClass))
    assertFalse(FX.LoadClassAddOn("DEATHKNIGHT"), "no add-on: false")
    assertFalse(FX.LoadClassAddOn(nil))
    assertFalse(FX.LoadClassAddOn(42))
    FX.Print = realPrint
    assertEquals(0, #printed, "no notice for a repeat load or a classless token")
    assertNil(FX.ClassAddOnFor(nil))
    assertTrue(C_AddOns.IsAddOnLoaded(own))
end)

-- ------------------------------------------------- the general LoD seam --
-- `FX.LoadAddOnOnDemand(name)` (H7): the same ledger and the same rules the
-- class loader runs, for a NON-class add-on. Forte_ItemProcs is the real
-- subject: the proc data is `## LoadOnDemand: 1`, so a login session must not
-- carry it, and the feature that owns it (Forte_Cooldown/Core/Procs.lua)
-- pulls it in through this seam.

test("a load-on-demand data add-on is not parsed at login", function()
    assertNil(FX.Data.ItemProcs,
        "Forte_ItemProcs was parsed at login: its data is not load-on-demand")
    assertFalse(C_AddOns.IsAddOnLoaded("Forte_ItemProcs"))
    assertTrue(C_AddOns.IsAddOnLoadOnDemand("Forte_ItemProcs"),
        "the add-on is declared load-on-demand in its .toc")
    assertFalse(FX.IsAddOnLoadedOnDemand("Forte_ItemProcs"))
    assertFalse(FX.IsAddOnLoadedOnDemand(nil))
end)

test("LoadAddOnOnDemand loads a named add-on, is idempotent and quiet",
function()
    local printed, realPrint = {}, FX.Print
    FX.Print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end
    local calls = 0
    local savedAddOns, savedLedger = _G.C_AddOns, FX._loadedAddOns
    local realLoad = _G.C_AddOns.LoadAddOn
    _G.C_AddOns = setmetatable({
        LoadAddOn = function(name)
            calls = calls + 1
            return realLoad(name)
        end,
    }, { __index = _G.C_AddOns })
    local first = FX.LoadAddOnOnDemand("Forte_ItemProcs")
    local second = FX.LoadAddOnOnDemand("Forte_ItemProcs")
    local third = FX.LoadAddOnOnDemand("Forte_ItemProcs")
    local loaded = C_AddOns.IsAddOnLoaded("Forte_ItemProcs")
    local ownIn = FX.LoadAddOnOnDemand(FX.ClassAddOnFor(FX._playerClass))
    local junkNil, junkEmpty, junkNum = FX.LoadAddOnOnDemand(nil),
        FX.LoadAddOnOnDemand(""), FX.LoadAddOnOnDemand(42)
    FX.Print = realPrint
    _G.C_AddOns = savedAddOns
    FX._loadedAddOns = savedLedger

    assertTrue(first, "the load reports true")
    assertTrue(second, "a repeat call reports true")
    assertTrue(third, "and stays true")
    assertEquals(1, calls, "the loader ran once; the repeats ride the ledger")
    assertEquals(0, #printed, "a load and its repeats print nothing")
    assertTrue(loaded, "the add-on is in the session")
    -- The add-on's files run to completion before LoadAddOn returns: the
    -- data table is usable on the caller's next statement.
    assertNotNil(FX.Data.ItemProcs, "ForteXorcist.Data.ItemProcs arrived")
    assertNotNil(FX.Data.ItemProcs.procs, "the proc rows")
    assertNotNil(FX.Data.ItemProcs.ProcsByName, "the proc name index")
    assertNotNil(FX.Data.ItemProcs.ProcsByBuffName, "the proc buff-name index")
    assertTrue(FX.IsAddOnLoadedOnDemand("Forte_ItemProcs"))
    assertTrue(ownIn, "the class half rides the same seam")
    -- Junk names are false, never a raise and never a loader call.
    assertFalse(junkNil)
    assertFalse(junkEmpty)
    assertFalse(junkNum)
    assertEquals(1, calls, "a junk name never reaches the loader")
end)

-- ------------------------------------------------ listed is not parsed (F-B)
-- `run-tests Forte_<Class>` puts the add-on under test in the runner's add-on
-- list: `C_AddOns.IsAddOnLoaded` answers TRUE for it while none of its files
-- have been parsed (measured in the sim: `FX.Data.Shaman` absent, its module
-- unregistered, `IsAddOnLoadOnDemand` true). Trusting the listing settles the
-- ledger on true and the class's data never arrives -- the hole Forte_Shaman's
-- suite used to patch by calling the raw loader itself. The loader's own probe
-- is the add-on's data table, so the listing can not hide an unparsed add-on.

test("a listed add-on whose files never ran is loaded for real", function()
    local savedAddOns, savedLedger = _G.C_AddOns, FX._loadedAddOns
    local savedProbe = FX.ADDON_MARKERS.Forte_Mage
    local calls, probes = 0, 0
    FX._loadedAddOns = {}
    FX.ADDON_MARKERS.Forte_Mage = function()
        probes = probes + 1
        return false                       -- the files have not run
    end
    _G.C_AddOns = {
        IsAddOnLoaded = function() return true, true end,   -- the runner's list
        IsAddOnLoadOnDemand = function() return true end,
        LoadAddOn = function(name)
            calls = calls + 1
            assertEquals("Forte_Mage", name)
            return true
        end,
    }

    local ok = FX.LoadClassAddOn("MAGE")
    local usable = FX.IsAddOnLoadedOnDemand("Forte_Mage")
    local again = FX.LoadClassAddOn("MAGE")

    _G.C_AddOns = savedAddOns
    FX._loadedAddOns = savedLedger
    FX.ADDON_MARKERS.Forte_Mage = savedProbe

    assertTrue(ok, "the listed-but-unparsed add-on reports a load")
    assertEquals(1, calls,
        "the listing did not excuse the loader: LoadAddOn ran once")
    assertTrue(probes > 0, "the loader asked the add-on's own probe")
    assertFalse(usable,
        "is-its-data-usable says NO while the files have not run")
    assertTrue(again, "the second call rides the ledger, not the loader")
    assertEquals(1, calls, "the loader ran exactly once")
    assertEquals(1, FX._listedNotRun.Forte_Mage,
        "the listed-not-parsed shape is counted for /fx status")
end)

test("a listed add-on whose probe says its files ran is not re-loaded", function()
    local savedAddOns, savedLedger = _G.C_AddOns, FX._loadedAddOns
    local calls = 0
    FX._loadedAddOns = {}
    -- Forte_Paladin (the profile class) is listed AND parsed: its probe is the
    -- real `FX.Data.Paladin`, so the listing is the whole truth.
    local own = FX.ClassAddOnFor(FX._playerClass)
    _G.C_AddOns = {
        IsAddOnLoaded = function(name)
            if name == own then return true, true end
            return false, false
        end,
        IsAddOnLoadOnDemand = function() return true end,
        LoadAddOn = function() calls = calls + 1; return true end,
    }
    local ok = FX.LoadAddOnOnDemand(own)
    local usable = FX.IsAddOnLoadedOnDemand(own)
    local noProbe = FX.IsAddOnLoadedOnDemand("Forte_Someone_Elses")
    _G.C_AddOns = savedAddOns
    FX._loadedAddOns = savedLedger
    assertTrue(ok, "a genuinely loaded add-on reports true")
    assertTrue(usable)
    assertEquals(0, calls, "an add-on that is in is never handed to the loader again")
    assertFalse(noProbe, "a name the session does not carry is false, not an error")
    assertNil(FX._listedNotRun[own], "the honest listing costs no count")
end)

test("AddOnFilesRan reads the add-on's own probe, and trusts an unknown name",
function()
    local savedProbe = FX.ADDON_MARKERS.Forte_Mage
    -- No probe registered for a name (an always-loaded split, a third-party
    -- add-on): the listing is all the loader has, so it is believed.
    FX.ADDON_MARKERS.Forte_Mage = nil
    assertTrue(FX.AddOnFilesRan("Forte_Mage"), "no probe: the listing is believed")
    assertFalse(FX.AddOnFilesRan(nil), "a junk name is false")
    FX.ADDON_MARKERS.Forte_Mage = function() error("FXTEST-PROBE-RAISE", 0) end
    assertFalse(FX.AddOnFilesRan("Forte_Mage"), "a raising probe is not a run")
    FX.ADDON_MARKERS.Forte_Mage = savedProbe
    -- The derived class probes: the profile class's own data table is in.
    local ownAddOn = FX.ClassAddOnFor(FX._playerClass)
    assertTrue(FX.AddOnFilesRan(ownAddOn),
        "a class probe reads that class's generated data table")
    local other = FX.ClassAddOnFor("MAGE")
    if other ~= ownAddOn then
        assertFalse(FX.AddOnFilesRan(other),
            "a class the session has not parsed fails its own probe")
    end
end)

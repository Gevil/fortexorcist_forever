-- addon/Forte_Core/tests/test_login_order.lua
-- The login ORDER, driven through the real Core/Init.lua bootstrap frame
-- script. Source: docs/research/upstream-addons-2026-11-03.md §7.3
-- (`CDM@e5811752 Core/Init.lua:153-157, 214-218`), ranked 7 of §9.
--
-- The shipped law that file states:
--
--   "the login handler is driven from whichever of PLAYER_LOGIN / first
--    PLAYER_ENTERING_WORLD reaches us first (`PLAYER_LOGIN` can be missed)"
--   "AceAddon enables us mid-PLAYER_LOGIN dispatch on a fresh login, so the
--    PLAYER_LOGIN handler registered in OnEnable can miss its own event"
--
-- Our shape is exactly the exposed one: Core/Init.lua + Core/Loader.lua
-- enable Forte_<Class> DURING the PLAYER_LOGIN dispatch (the class add-on's
-- files run inside it), so any class module that registered PLAYER_LOGIN in
-- its own OnEnable would never see it. What this suite proves:
--
--   * the login pass is one-shot: a replayed PLAYER_LOGIN through the real
--     script enables nobody, loads no add-on, builds no frame, prints nothing;
--   * PLAYER_LOGIN has ONE consumer -- the bootstrap frame. Our code fans the
--     event out to no module, so a module that gates login work on seeing
--     PLAYER_LOGIN gets nothing: login work belongs in OnEnable, which the
--     pass calls directly;
--   * every registered module (always-loaded AND load-on-demand) sits in the
--     enable ledger and cannot be enabled a second time;
--   * the LoD-at-login path: a class add-on pulled in by the login entry
--     point enables EACH of its modules exactly once, inside the load;
--   * the PLAYER_ENTERING_WORLD class-change path: through the real script it
--     loads the new class's add-on, enables its modules exactly once,
--     registers the class's events (the Tools' `_eventsEnabled`/`_eventFrame`
--     are the visible half) and runs the OnClassChanged wave exactly once --
--     and re-running it with the same class does nothing at all;
--   * the fallback: when PLAYER_LOGIN is missed, the first
--     PLAYER_ENTERING_WORLD runs the login pass exactly once, and the PLAYER_LOGIN
--     that then arrives (or a second zone-in) adds nothing.
--
-- The law's audit result (2026-11-03, the whole tree): the ONLY PLAYER_LOGIN
-- registration in addon/** is Core/Init.lua's bootstrap frame -- no class
-- module registers it, so none can miss it. Two rows that are NOT the trap and
-- one that is dead are reported to the manager: Forte_Cooldown registers
-- PLAYER_ENTERING_WORLD (which fires AFTER PLAYER_LOGIN, so a frame registered
-- mid-dispatch still hears it), and Forte_Core/Core/Locale.lua's
-- `LocaleModule.OnEvents` PLAYER_LOGIN leg is never dispatched by anyone (no
-- OnEvents dispatcher exists in the tree) -- that module's login rebuild rides
-- its OnEnable, and its class-change rebuild rides OnClassChanged, both of
-- which do run.
--
-- Stubs: `_G.CreateFrame`, `_G.C_AddOns`, `_G.UnitClass` are patched with
-- counting proxies that forward to the real globals (the loads are real), and
-- every patch is restored on every path through withGlobals. The registry
-- snapshot in the last test swaps FX.modules/_moduleOrder/_enabledModules for
-- an isolated set so no real module's OnEnable is ever run twice; the profile
-- class and the ledger are restored exactly.

local FX = ForteXorcist

local function titleCase(token)
    if type(token) ~= "string" or token == "" then return nil end
    return token:sub(1, 1) .. token:sub(2):lower()
end

--- The bootstrap frame's OnEvent script -- the script the client itself
--- calls. Every order test below dispatches through it, never through a
--- re-implementation of it.
local function loginScript()
    local frame = FX._bootstrapFrame
    assertNotNil(frame, "Core/Init.lua hands the bootstrap frame to its tests")
    local handler = frame:GetScript("OnEvent")
    assertEquals("function", type(handler), "the bootstrap frame has an OnEvent script")
    return handler
end

--- Run body with the named globals replaced, restoring them on every path.
--- Returns pcall's (ok, err) so a raising body can not strand a patched
--- global for the rest of the suite.
local function withGlobals(patches, body)
    local saved = {}
    for key, value in pairs(patches) do
        saved[key] = _G[key]
        _G[key] = value
    end
    local ok, err = pcall(body)
    for key, value in pairs(saved) do _G[key] = value end
    return ok, err
end

--- A counting proxy over the REAL C_AddOns table: the loads stay real, the
--- calls are counted.
local function proxyAddOns()
    local real = _G.C_AddOns
    local calls = { load = 0, isLoaded = 0 }
    local proxy = {
        LoadAddOn = function(name)
            calls.load = calls.load + 1
            return real.LoadAddOn(name)
        end,
        IsAddOnLoaded = function(name, ...)
            calls.isLoaded = calls.isLoaded + 1
            return real.IsAddOnLoaded(name, ...)
        end,
        IsAddOnLoadOnDemand = function(name) return real.IsAddOnLoadOnDemand(name) end,
    }
    return proxy, calls
end

--- A counting proxy over the REAL CreateFrame: the frames stay real, so a
--- module's event frame really is built, and every build is counted.
local function proxyCreateFrame()
    local real = _G.CreateFrame
    local calls = { frames = 0 }
    local proxy = function(frameType, ...)
        calls.frames = calls.frames + 1
        return real(frameType, ...)
    end
    return proxy, calls
end

--- Count every call of `method` on the given modules. Returns counts plus a
--- restore that puts the pristine functions back.
local function countMethod(names, method)
    local counts, marks = {}, {}
    for _, name in ipairs(names) do
        local mod = FX.modules[name]
        if mod and type(mod[method]) == "function" then
            local real = mod[method]
            counts[name] = 0
            marks[#marks + 1] = { mod = mod, method = method, real = real }
            local key = name
            mod[method] = function(...)
                counts[key] = counts[key] + 1
                return real(...)
            end
        end
    end
    local function restore()
        for _, mark in ipairs(marks) do mark.mod[mark.method] = mark.real end
    end
    return counts, restore
end

local function registeredNames()
    local names = {}
    for _, name in ipairs(FX._moduleOrder) do names[#names + 1] = name end
    return names
end

-- ------------------------------------------------------------------ shape --

test("the login pass is a one-shot function on the shared seam", function()
    assertEquals("function", type(FX.RunLoginPass),
        "FX.RunLoginPass is the single login entry point")
    assertTrue(FX._loginDone, "the real login pass ran before the tests")
    -- One-shot: with the pass already run, calling it is a no-op.
    local names = registeredNames()
    local counts, restore = countMethod(names, "OnEnable")
    local ran = FX.RunLoginPass()
    restore()
    assertFalse(ran, "a second call reports 'I was not the pass'")
    for _, name in ipairs(names) do
        if counts[name] then assertEquals(0, counts[name], name .. " was not enabled again") end
    end
end)

-- ------------------------------------------- a replayed PLAYER_LOGIN pass --

test("a replayed PLAYER_LOGIN through the bootstrap script is inert",
function()
    local handler = loginScript()
    local names = registeredNames()
    local enables, restoreEnables = countMethod(names, "OnEnable")
    local waves, restoreWaves = countMethod(names, "OnClassChanged")
    local proxy, calls = proxyAddOns()
    local makeFrame, frames = proxyCreateFrame()
    local printed, realPrint = {}, FX.Print
    FX.Print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end

    local ok, err = withGlobals({ C_AddOns = proxy, CreateFrame = makeFrame }, function()
        handler(nil, "PLAYER_LOGIN", FX.CONST.ADDON_NAME)
        handler(nil, "PLAYER_LOGIN", "SomeoneElse")
    end)

    FX.Print = realPrint
    restoreEnables()
    restoreWaves()
    assertTrue(ok, "the replay raised: " .. tostring(err))
    assertTrue(FX._loginDone, "and the login flag stands")
    for _, name in ipairs(names) do
        if enables[name] then assertEquals(0, enables[name], name .. ": no second OnEnable") end
        if waves[name] then assertEquals(0, waves[name], name .. ": no class wave") end
    end
    assertEquals(0, calls.load, "no add-on is loaded by a login replay")
    assertEquals(0, frames.frames, "no frame (no event frame) is built by a login replay")
    assertEquals(0, #printed, "a replayed login is silent: " .. table.concat(printed, " / "))
end)

-- ------------------------------------------------- the single-consumer law --

test("PLAYER_LOGIN has one consumer: our code fans it out to no module",
function()
    local handler = loginScript()
    -- A frame registered for PLAYER_LOGIN the way a module's OnEnable would
    -- register it. The §7.3 trap is a module that then WAITS for the event.
    local probe = CreateFrame("Frame")
    local seen = 0
    probe:SetScript("OnEvent", function() seen = seen + 1 end)
    probe:RegisterEvent("PLAYER_LOGIN")
    -- The one module in the tree that still has an OnEvents(event, ...) hook
    -- (Core/Locale.lua). Counting it proves the framework delivers no raw
    -- event to any module -- the reason that hook's PLAYER_LOGIN leg can
    -- never fire.
    local localeCounts, restoreLocale = countMethod({ "Locale" }, "OnEvents")
    local proxy, calls = proxyAddOns()

    local ok, err = withGlobals({ C_AddOns = proxy }, function()
        handler(nil, "PLAYER_LOGIN", FX.CONST.ADDON_NAME)
    end)
    restoreLocale()
    assertTrue(ok, "dispatch raised: " .. tostring(err))

    assertEquals(0, seen, "dispatching PLAYER_LOGIN through the bootstrap delivers "
        .. "it to no other frame: a module that registers PLAYER_LOGIN in its "
        .. "OnEnable and waits for it waits for the session")
    assertEquals(0, calls.load, "the dispatch is the single consumer, not a loader fan-out")
    if localeCounts.Locale then
        assertEquals(0, localeCounts.Locale, "no raw PLAYER_LOGIN reaches a module hook")
    end
end)

-- ---------------------------------------------------- the exactly-once law --

test("every registered module is in the enable ledger and cannot enable twice",
function()
    local names = registeredNames()
    assertTrue(#names > 0, "the registry is populated by login")
    local counts, restore = countMethod(names, "OnEnable")
    for _, name in ipairs(names) do
        assertEquals(true, FX._enabledModules[name], name .. " is in the ledger")
        FX.EnableModule(name)
        FX.EnableModule(name)
    end
    restore()
    for _, name in ipairs(names) do
        if counts[name] then
            assertEquals(0, counts[name], name .. ": a repeat enable runs no OnEnable")
        end
    end
end)

-- ------------------------------------------------- the LoD-at-login path --

test("the login entry point enables every module of a class add-on exactly once",
function()
    local pick
    -- Only classes whose add-on registers modules: a data-only add-on would
    -- prove the load, not the enable law.
    for _, token in ipairs({ "WARLOCK", "HUNTER", "SHAMAN" }) do
        local name = FX.CLASS_ADDONS[token]
        if name and not C_AddOns.IsAddOnLoaded(name) then pick = token; break end
    end
    if not pick then
        print("[login-order] every class add-on is already loaded -- LoD pass skipped")
        return
    end
    local addonName = FX.CLASS_ADDONS[pick]

    -- The counting half of the seam: FX.RegisterModule is the ONLY door a
    -- class add-on's files use, so wrapping it sees each of the add-on's
    -- modules BEFORE the enable the loader's own pass runs on it.
    local realRegister = FX.RegisterModule
    local seenNames, counts, marks = {}, {}, {}
    FX.RegisterModule = function(name, mod)
        seenNames[#seenNames + 1] = name
        if mod and type(mod.OnEnable) == "function" then
            local real = mod.OnEnable
            counts[name] = 0
            marks[#marks + 1] = { mod = mod, real = real }
            local key = name
            mod.OnEnable = function(m, ...)
                counts[key] = counts[key] + 1
                return real(m, ...)
            end
        end
        return realRegister(name, mod)
    end

    local proxy, calls = proxyAddOns()
    local loaded
    local ok, err = withGlobals({ C_AddOns = proxy }, function()
        loaded = FX.LoadClassAddOn(pick)
    end)
    FX.RegisterModule = realRegister
    for _, mark in ipairs(marks) do mark.mod.OnEnable = mark.real end
    assertTrue(ok, "the load raised: " .. tostring(err))
    assertTrue(loaded, addonName .. " loaded through the login seam")

    assertTrue(#seenNames > 0, addonName .. " registers at least one module")
    assertEquals(1, calls.load, "one LoadAddOn call for one add-on")
    for _, name in ipairs(seenNames) do
        assertNotNil(FX.modules[name], name .. " reached the registry")
        assertEquals(true, FX._enabledModules[name], name .. " is in the ledger")
        assertEquals(1, counts[name], name .. ": enabled EXACTLY once, inside the load")
    end
    assertNotNil(FX.Data[titleCase(pick)], "its data table came with it")
    print(string.format("[login-order] %s: %d module(s), each enabled once at load",
        addonName, #seenNames))
end)

-- ------------------------------------- PLAYER_ENTERING_WORLD class change --

test("the PLAYER_ENTERING_WORLD class change enables once and registers events",
function()
    local handler = loginScript()
    local profileClass = FX._playerClass
    local target = (profileClass == "WARLOCK") and "HUNTER" or "WARLOCK"
    local toolsKey = titleCase(target)
    local tools = FX[toolsKey] and FX[toolsKey].Tools
    if not tools then
        print("[login-order] no Tools module for " .. target .. " -- change pass skipped")
        return
    end

    local names = registeredNames()
    local enables, restoreEnables = countMethod(names, "OnEnable")
    local waves, restoreWaves = countMethod(names, "OnClassChanged")
    local proxy, calls = proxyAddOns()
    local makeFrame, frames = proxyCreateFrame()
    local realRegister = FX.RegisterModule
    local seenNames, enableCounts, marks = {}, {}, {}
    FX.RegisterModule = function(name, mod)
        seenNames[#seenNames + 1] = name
        if mod and type(mod.OnEnable) == "function" then
            local real = mod.OnEnable
            enableCounts[name] = 0
            marks[#marks + 1] = { mod = mod, real = real }
            local key = name
            mod.OnEnable = function(m, ...)
                enableCounts[key] = enableCounts[key] + 1
                return real(m, ...)
            end
        end
        return realRegister(name, mod)
    end
    local savedUnitClass = _G.UnitClass
    _G.UnitClass = function() return nil, target end
    -- A fresh event surface: the state a first login of this class has (the
    -- Tools' event frame is built by EnableEvents, never at file load), so
    -- "the events register in THIS pass" is counted, not inherited from an
    -- earlier test's pass.
    tools._eventsEnabled = false
    tools._eventFrame = nil
    local framesBefore = frames.frames

    local ok, err = withGlobals({ C_AddOns = proxy, CreateFrame = makeFrame }, function()
        handler(nil, "PLAYER_ENTERING_WORLD")
    end)

    local classAfter = FX._playerClass
    for _, mark in ipairs(marks) do mark.mod.OnEnable = mark.real end
    FX.RegisterModule = realRegister
    restoreEnables()
    restoreWaves()
    -- (_G.UnitClass stays patched to `target` through the repeat-zone-in
    -- block below -- an un-patched read there would BE a class change and the
    -- wave assertions would be meaningless. It is restored before the final
    -- FX.RefreshPlayerClass.)
    assertTrue(ok, "the zone-in dispatch raised: " .. tostring(err))

    assertEquals(target, classAfter, "the zone-in re-read took the new class")
    for _, name in ipairs(names) do
        if enables[name] then
            assertEquals(0, enables[name],
                name .. ": a class change runs NO second OnEnable")
        end
        if waves[name] then
            assertEquals(1, waves[name], name .. ": the OnClassChanged wave ran once")
        end
    end
    for _, name in ipairs(seenNames) do
        if enableCounts[name] then
            assertEquals(1, enableCounts[name],
                name .. ": the new class's module enabled exactly once")
        end
    end
    assertTrue(tools._eventsEnabled,
        "the new class's events registered in that pass (Tools._eventsEnabled)")
    assertNotNil(tools._eventFrame, "on the Tools' own event frame")
    assertEquals(1, frames.frames - framesBefore,
        "that pass built exactly one frame: the event frame, on the zone-in "
        .. "pass (frames: " .. tostring(frames.frames - framesBefore) .. ")")
    assertTrue(FX._loginDone, "the login pass is not reopened by a zone-in")

    -- A second zone-in with the SAME class: nothing at all -- no load, no
    -- wave, no enable, no new frame, and the event frame is the same object.
    local eventFrame = tools._eventFrame
    local names2 = registeredNames()
    local enables2, restore2 = countMethod(names2, "OnEnable")
    local waves2, restoreWaves2 = countMethod(names2, "OnClassChanged")
    local proxy2, calls2 = proxyAddOns()
    local ok2, err2 = withGlobals({ C_AddOns = proxy2 }, function()
        handler(nil, "PLAYER_ENTERING_WORLD")
    end)
    restore2()
    restoreWaves2()
    assertTrue(ok2, "the repeat zone-in raised: " .. tostring(err2))
    assertEquals(0, calls2.load, "no add-on load on a no-change zone-in")
    -- The claim here is the Tools' event frame, asserted by identity below:
    -- a real zone-in also builds lazy surfaces elsewhere in the tree
    -- (Forte_Cooldown's item/enchant rescan path), so a frame count is not
    -- this test's evidence.
    for _, name in ipairs(names2) do
        if enables2[name] then assertEquals(0, enables2[name], name .. ": no enable") end
        if waves2[name] then assertEquals(0, waves2[name], name .. ": no wave") end
    end
    assertEquals(eventFrame, tools._eventFrame,
        "the same event frame: no second registration pass on a repeat zone-in")
    assertTrue(tools._eventsEnabled, "and still registered")

    -- Restore the profile class (the same discipline test_loader.lua uses):
    -- the event frame follows the class back down.
    _G.UnitClass = savedUnitClass
    FX.RefreshPlayerClass()
    assertEquals(profileClass, FX._playerClass, "the profile class token is restored")
    assertFalse(tools._eventsEnabled, "the restored class leaves the module silent")
end)

-- --------------------------------------------------- the missed-login path --

test("a missed PLAYER_LOGIN is carried by the first PLAYER_ENTERING_WORLD",
function()
    local handler = loginScript()
    -- An ISOLATED registry: the fallback enables everything registered, so
    -- the real modules are swapped out for synthetic ones and the real
    -- registry, ledger and flags are restored by reference at the end.
    local savedModules, savedOrder = FX.modules, FX._moduleOrder
    local savedLedger, savedLoginDone = FX._enabledModules, FX._loginDone
    FX.modules, FX._moduleOrder, FX._enabledModules = {}, {}, {}
    FX._loginDone = false

    local log = {}
    local function probe(letter)
        return { OnEnable = function() log[#log + 1] = letter end }
    end
    FX.RegisterModule("__FxLo_A", probe("A"))
    FX.RegisterModule("__FxLo_B", probe("B"))
    FX.RegisterModule("__FxLo_C", probe("C"))

    local proxy, calls = proxyAddOns()
    local ok, err = withGlobals({ C_AddOns = proxy }, function()
        assertEquals(0, #log,
            "registered before the pass: nothing enabled yet (FX._loginDone is false)")
        handler(nil, "PLAYER_ENTERING_WORLD")
        assertEquals(3, #log, "the zone-in ran the login pass")
        assertEquals("A", log[1], "in registration order")
        assertEquals("C", log[3], "in registration order")
        assertTrue(FX._loginDone, "the pass closed the seam")
        assertEquals(0, calls.load,
            "the class add-on of the profile class was already in: no loader call")
        -- The PLAYER_LOGIN that arrives late, and a second zone-in, are both
        -- inert: the pass is one-shot.
        handler(nil, "PLAYER_LOGIN", FX.CONST.ADDON_NAME)
        handler(nil, "PLAYER_ENTERING_WORLD")
        assertEquals(3, #log, "neither re-runs the login pass")
    end)

    FX.modules, FX._moduleOrder = savedModules, savedOrder
    FX._enabledModules, FX._loginDone = savedLedger, savedLoginDone
    assertTrue(ok, "the fallback pass raised: " .. tostring(err))
    assertTrue(FX._loginDone, "the real registry's login flag is back")
    for _, name in ipairs(registeredNames()) do
        assertEquals(true, FX._enabledModules[name], name .. " is back in the ledger")
    end
end)

-- ------------------------------------------- the ChatBar/nameplate surface --

test("the nameplate forbid/release protocol is not a declared surface: geometry stays",
function()
    -- docs/research/upstream-addons-2026-11-03.md §7.5 names
    -- `C_NamePlates.ForbidNamePlates` / `ReleaseNamePlatesForAddon` /
    -- `OnNamePlatesForbidden` / `C_NamePlatesAreForbidden` from the installed
    -- (closed-source) EllesmereUINameplates tree. Checked against OUR pinned
    -- catalog (docs/api/wow-addon-api-agents/skills/*/references/generated/
    -- forever.json, build 1.60.1.70707: 10254 declarations, no C_NamePlates
    -- namespace -- C_NamePlate/C_NamePlateManager only) and against
    -- scripts/api_lint.py, which flags `C_NamePlates.ForbidNamePlates` as an
    -- unknown namespace (rc=1). Row 8 of §9 says to prefer that protocol
    -- "where the catalog declares it": it does not, so Forte_ChatBar keeps the
    -- GetFramesRegion() geometry plan and a C_NamePlates call stays out of the
    -- tree (the lint would fail the gate on it).
    print("[login-order] sim surface: C_NamePlates=" .. tostring(_G.C_NamePlates)
        .. "  C_AddOns.GetAddOnList=" .. tostring(_G.C_AddOns and _G.C_AddOns.GetAddOnList)
        .. "  C_AddOns.GetAddOnMetadata="
        .. tostring(_G.C_AddOns and _G.C_AddOns.GetAddOnMetadata))
    assertNil(_G.C_NamePlates, "no C_NamePlates namespace in the sim's client surface")
    assertNotNil(_G.C_NamePlate, "the declared singular C_NamePlate surface is there")
    assertNil(FX.ChatBar,
        "Forte_ChatBar ships no code: there is no geometry plan to migrate")
    -- §5's "enabled-set truth" for a LoadOnDemand sibling (the question that
    -- leaves a `siblingTidyPlates()` answering "unknown") rides the DECLARED
    -- C_AddOns members -- every one of them is declared in the pinned 70707
    -- catalog and answers in the sim's client surface, so the probe can
    -- return a real verdict at launch. `GetAddOnList` is the one the note
    -- cites that our catalog does not declare.
    for _, member in ipairs({ "GetNumAddOns", "GetAddOnInfo", "GetAddOnEnableState",
    "GetAddOnMetadata", "IsAddOnLoaded", "IsAddOnLoadOnDemand", "DoesAddOnExist" }) do
        assertEquals("function", type(_G.C_AddOns and _G.C_AddOns[member]),
            "C_AddOns." .. member .. " is part of the client surface")
    end
end)

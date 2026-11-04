-- addon/Forte_Core/tests/test_testmode.lua
-- The demo pilot (`/fx test`, Core/TestMode.lua): the slash path, the fill of
-- BOTH fed frames through their own feeders, the scrub laws (a stop, a combat
-- start, a logout), the in-combat refusal, and the three prohibitions the
-- feature ships with -- no chat, no comms, no settings write -- measured, not
-- asserted. docs/research/upstream-addons-2026-11-03.md §6 "Test Mode" is the
-- feature law (the CooldownMaster port: gate every feed, scrub on every exit,
-- a demo entry carries no `dObj` and no `itemID`, keep the demo off
-- secret-prone reads); the donor law is the reason every synthetic name the
-- tests check is one the tests themselves put into the generated-data-shaped
-- pools.
--
-- The drives are the real ones: `FX.OnSlash("test")` (the real slash registry,
-- Init.lua), the frame's own OnEvent script for the combat and logout edges
-- (the binding law of PLAN §10.2 -- the frame is argument 1), and
-- `FX.Cooldown.Module:ProcessReadyPops` (the public pop path the 10 Hz ticker
-- drives). Like Forte_Cooldown/tests/test_timeline.lua and
-- Forte_Timer/tests/test_module.lua establish, the gate run's login sequence
-- does not reach Forte_Core's module loop, so the enable path is driven by hand
-- here. The C_Timer pumps are not reachable headless, so `T:Pump()` is driven
-- directly, and a hidden frame's OnUpdate is never relied on -- TestMode
-- registers no OnUpdate at all, which the first test measures. The pump
-- LIFECYCLE tests (FX7c: the ticker is a demo-lifetime resource, born at the
-- start and cancelled at every exit, never armed from the enable) spy
-- `C_Timer.NewTicker` itself -- a headless ticker never fires, so the
-- creation/cancel counts and the `_ticker` handle are the whole measurement.
--
-- The file runs LAST in the Forte_Core load list (the toc's test section)
-- because it enables the fed add-ons' modules, and the last file wins those
-- singletons (the Forte_Messages enable-order lesson of PLAN §7).

local FX = ForteXorcist
local T = FX.TestMode
local Engine = FX.Cooldown.Engine
local Rows = FX.Timer.Rows
local Registry = FX.Timer.Registry

-- --------------------------------------------------------------- the rig ---

--- The enable pass the login sequence does not deliver in the gate run.
local function enableAll()
    if not T._eventFrame then T:OnEnable() end
    if not FX.Cooldown.Module._eventFrame then FX.Cooldown.Module:OnEnable() end
    if not FX.Timer.Module.options then FX.Timer.Module:OnEnable() end
end

--- The donor pools, filled the way the generated data shapes them: names, not
--- ids. `Engine.tracked` rows are the `Engine:Build` shape (`name`,
--- `baseDuration`); the Timer's registry is built from Forte_Paladin's data by
--- the module's own Rebuild, and the fill reads it by name.
local function seedTracked(n)
    local made = {}
    for i = 1, n do
        local name = "DemoTest Spell " .. i
        Engine.tracked[name] = {
            name = name, dataId = 900000 + i, baseDuration = 8 + i * 2,
        }
        made[#made + 1] = name
    end
    return made
end

local function isTrackedName(name)
    return type(name) == "string" and Engine.tracked[name] ~= nil
end

local function taggedEntries()
    local names, n = {}, 0
    for name, e in pairs(Engine.entries) do
        if T.IsSynthetic(e) then
            n = n + 1
            names[n] = name
        end
    end
    return names, n
end

local function taggedRows()
    local names, n = {}, 0
    for i = 1, Rows.rows_n do
        local row = Rows.rows[i]
        if row and T.IsSynthetic(row) then
            n = n + 1
            names[n] = row.name
        end
    end
    return names, n
end

--- The exit law, measured over every container a synthetic row can live in.
local function survivingSyntheticRows()
    local offenders = {}
    for name, e in pairs(Engine.entries) do
        if T.IsSynthetic(e) then
            offenders[#offenders + 1] = "cooldown:" .. tostring(name)
        end
    end
    for i = 1, Rows.rows_n do
        local row = Rows.rows[i]
        if row and T.IsSynthetic(row) then
            offenders[#offenders + 1] = "timer:" .. tostring(row.name)
        end
    end
    return offenders
end

local function stopQuietly()
    if T.active then T:Stop("test") end
    -- The scrub is the product; belt-and-braces here keeps a failed assert in
    -- an earlier test from poisoning a later one.
    for name, e in pairs(Engine.entries) do
        if T.IsSynthetic(e) then Engine.entries[name] = nil end
    end
    for i = Rows.rows_n, 1, -1 do
        local row = Rows.rows[i]
        if row and T.IsSynthetic(row) then Rows:removeAt(i) end
    end
    Rows:Compact()
end

--- The store's whole content as a sorted signature. The settings layer is the
--- only writer of `db.profiles`, and a demo cycle must not touch it.
local function storeSignature()
    local lines = {}
    local profiles = (FX.db and FX.db.profiles and FX.db.profiles.byName) or {}
    for name in pairs(profiles) do lines[#lines + 1] = name end
    table.sort(lines)
    local out = {}
    for _, name in ipairs(lines) do
        local settings = profiles[name].settings or {}
        local modules = {}
        for m in pairs(settings) do modules[#modules + 1] = m end
        table.sort(modules)
        for _, m in ipairs(modules) do
            local keys = {}
            for k in pairs(settings[m] or {}) do keys[#keys + 1] = k end
            table.sort(keys)
            for _, k in ipairs(keys) do
                out[#out + 1] = string.format("%s.%s.%s=%s", name, m, k,
                    tostring(settings[m][k]))
            end
        end
    end
    return table.concat(out, "\n")
end

--- The send surface (the pair the two send owners call: Forte_Messages'
--- Announce:send reads C_ChatInfo.SendChatMessage, Forte_Warlock's Comms:Send
--- reads C_ChatInfo.SendAddonMessage, both at call time). Swapping them for a
--- counting stub is the measurement; the counters of the two modules are the
--- cross-check.
local function installSendSpies()
    local hits = { chat = 0, addon = 0 }
    local chat = _G.C_ChatInfo
    if type(chat) ~= "table" then return nil end
    local keepChat, keepAddon = chat.SendChatMessage, chat.SendAddonMessage
    chat.SendChatMessage = function()
        hits.chat = hits.chat + 1
    end
    chat.SendAddonMessage = function()
        hits.addon = hits.addon + 1
        return 0
    end
    return function()
        chat.SendChatMessage, chat.SendAddonMessage = keepChat, keepAddon
        return hits
    end
end

--- Spy the client's ticker surface: count the tickers created and the
--- `Cancel` calls. The headless sim fires no ticker callback, so the counts
--- and the `_ticker` handle ARE the lifecycle measurement; the fake ticker
--- carries only the `.Cancel` the product calls (pcall'd, TestMode.lua).
local function installPumpSpy()
    local hits = { created = 0, cancelled = 0 }
    local ct = _G.C_Timer
    if type(ct) ~= "table" or type(ct.NewTicker) ~= "function" then return nil end
    local keep = ct.NewTicker
    ct.NewTicker = function()
        hits.created = hits.created + 1
        local ticker = {}
        function ticker.Cancel() hits.cancelled = hits.cancelled + 1 end
        return ticker
    end
    return function()
        ct.NewTicker = keep
        return hits
    end
end

-- ----------------------------------------------------------------- module ---

test("the module is registered, off, and pumps without any OnUpdate",
function()
    assertNotNil(T, "FX.TestMode is loaded by Forte_Core")
    assertNotNil(FX.modules["TestMode"], "registered through FX.RegisterModule")
    assertEquals(false, T.active, "a session starts out of demo mode")
    assertEquals("off", T.reason)
    enableAll()
    assertNotNil(T._eventFrame)
    assertNotNil(T._eventFrame:GetScript("OnEvent"))
    -- The frame law of the whole project (the 2026-11-02 uiforever finding):
    -- a hidden frame gets no OnUpdate, so the pump is a ticker.
    assertNil(T._eventFrame:GetScript("OnUpdate"))
    -- FX7c: the enable creates NO pump. The mode is almost never on, so the
    -- ticker is a demo-lifetime resource, born at the Start -- a session out
    -- of demo mode must run no 1 Hz closure at all.
    assertNil(T._ticker, "the enable leaves the pump uncreated")
    assertEquals("function", type(FX.slashSubs["test"]),
        "/fx test rides FX.RegisterSlash")
    -- No settings key of ours exists anywhere: the mode is session-only, so it
    -- is not a registered default of any module.
    for _, module in ipairs(FX.Settings:GetModuleNames()) do
        assertEquals(nil, FX.Settings:GetDefault(module, "TestMode"),
            module .. " registers no TestMode key")
    end
end)

test("the feeders of both fed frames are registered once", function()
    enableAll()
    local names, n = {}, 0
    for _, f in ipairs(T.feeders) do
        n = n + 1
        names[f.Name] = (names[f.Name] or 0) + 1
        assertEquals("function", type(f.Fill), f.Name .. " fills")
        assertEquals("function", type(f.Scrub), f.Name .. " scrubs")
        assertEquals("function", type(f.Live), f.Name .. " counts")
    end
    assertEquals(2, n, "the Cooldown bar and the Spell Timer register")
    assertEquals(1, names["Cooldown"])
    assertEquals(1, names["SpellTimer"])
end)

-- ------------------------------------------------------------- the pump ----
--
-- FX7c: the 1 Hz re-fill pump is a DEMO-lifetime resource. It is created by
-- the Start (after the refusal checks -- a refused start arms nothing) and
-- cancelled by every exit -- the hand stop, the combat scrub, the disable.
-- The pre-fix code armed it in OnEnable, so every logged session beat a
-- closure once a second to pump a mode that is almost never on.

test("the start creates one pump, the stop cancels it and clears the handle",
function()
    enableAll()
    stopQuietly()
    seedTracked(0)
    assertNil(T._ticker, "no ticker out of the mode")
    local restore = installPumpSpy()
    assertNotNil(restore, "the client's ticker surface is present to spy")
    FX.OnSlash("test")
    assertTrue(T.active)
    assertNotNil(T._ticker, "the running mode owns the pump")
    FX.OnSlash("test")
    assertEquals(false, T.active)
    assertNil(T._ticker, "the stop cancelled the pump and cleared the handle")
    local hits = restore()
    assertEquals(1, hits.created, "exactly one ticker over one cycle")
    assertEquals(1, hits.cancelled, "exactly one cancel over one cycle")
end)

test("a combat scrub cancels the pump with the mode", function()
    enableAll()
    stopQuietly()
    seedTracked(0)
    local restore = installPumpSpy()
    assertNotNil(restore, "the client's ticker surface is present to spy")
    FX.OnSlash("test")
    assertNotNil(T._ticker, "the running mode owns the pump")
    -- The real script, on the real frame (PLAYER_REGEN_DISABLED
    -- @UnitDocumentation.lua:3884) -- the combat exit runs the same Stop.
    T._eventFrame:GetScript("OnEvent")(T._eventFrame, "PLAYER_REGEN_DISABLED")
    assertEquals(false, T.active)
    assertNil(T._ticker, "the combat scrub cleared the handle")
    local hits = restore()
    assertEquals(1, hits.created, "one ticker in, one out")
    assertEquals(1, hits.cancelled, "the combat exit cancelled the pump")
end)

test("three start/stop cycles create one pump each and leave none",
function()
    enableAll()
    stopQuietly()
    seedTracked(0)
    local restore = installPumpSpy()
    assertNotNil(restore, "the client's ticker surface is present to spy")
    for cycle = 1, 3 do
        FX.OnSlash("test")
        assertNotNil(T._ticker, "cycle " .. cycle .. " owns its pump")
        FX.OnSlash("test")
        assertNil(T._ticker, "cycle " .. cycle .. " cancelled its pump")
    end
    local hits = restore()
    assertEquals(3, hits.created, "exactly one ticker per start")
    assertEquals(3, hits.cancelled, "exactly one cancel per stop")
    assertNil(T._ticker, "the shipped state carries no ticker")
end)

test("the disable cancels a pump left running by the mode", function()
    enableAll()
    stopQuietly()
    seedTracked(0)
    local restore = installPumpSpy()
    assertNotNil(restore, "the client's ticker surface is present to spy")
    FX.OnSlash("test")
    assertNotNil(T._ticker, "the running mode owns the pump")
    T:OnDisable()
    assertEquals(false, T.active, "the disable stopped the mode")
    assertEquals("disabled", T.reason)
    assertNil(T._ticker, "and cancelled the pump")
    local hits = restore()
    assertEquals(1, hits.created, "one ticker in")
    assertEquals(1, hits.cancelled, "one cancel out, at the disable")
    T:OnEnable()   -- the suite's enable window: the shipped code re-enables
end)

-- ------------------------------------------------------------- the slash ----

test("/fx test starts the mode and fills the cooldown bar with own-class names",
function()
    enableAll()
    stopQuietly()
    local donors = seedTracked(9)
    local before = T.stats.starts
    FX.OnSlash("test")                       -- the real slash dispatch
    assertTrue(T.active, "the mode is on")
    assertEquals("on", T.reason)
    assertEquals(before + 1, T.stats.starts)
    local names, n = taggedEntries()
    assertTrue(n > 0, "the bar has synthetic entries (" .. n .. ")")
    -- The donor law: every synthetic name is a name of OUR tracked pool -- the
    -- generated class data, as the player's own spell list is built from it --
    -- never a name typed into a test or a command line, and the fill never
    -- reads the client for one (in the gate run the client knows no spells at
    -- all, so a client-sourced name is not even possible).
    for _, name in ipairs(names) do
        assertTrue(isTrackedName(name),
            "the donor is a tracked name, never a typed id: " .. tostring(name))
        local e = Engine.entries[name]
        assertNotNil(e)
        -- The synthetic-entry law: no data-object, no item id, so no consumer
        -- resolves the row against a live unit.
        assertEquals(nil, e.dObj)
        assertEquals(nil, e.itemID)
        assertTrue(e.endTime > e.start)
    end
    -- The demo is spread, not stacked: the ready moments are distinct.
    local seen = {}
    local distinct = 0
    for _, name in ipairs(names) do
        local r = math.floor(Engine.entries[name].endTime * 100)
        if not seen[r] then seen[r] = true; distinct = distinct + 1 end
    end
    assertTrue(distinct >= 2, "the fills are spread over the pump period")
end)

test("the same press fills the Spell Timer with registered names", function()
    enableAll()
    assertTrue(T.active, "the cycle of the test above is still running")
    local names, n = taggedRows()
    assertTrue(n > 0, "the panel has synthetic rows (" .. n .. ")")
    for _, name in ipairs(names) do
        assertTrue(type(Registry.entries[name]) == "table",
            "the row's name is in the Timer's registered data: "
            .. tostring(name))
    end
    for i = 1, Rows.rows_n do
        local row = Rows.rows[i]
        if row and T.IsSynthetic(row) then
            -- No unit is invented for a made-up row: the self/no-target key,
            -- and the two public legs (the announce stamp, the fade-warning
            -- threshold) are disarmed at the seam.
            assertEquals("none", row.targetKey)
            assertEquals(0, row.expireMsgAt)
            assertEquals(0, row.fadeWarn)
            assertEquals("test", row._source)
        end
    end
end)

test("the fill writes no setting and sends no chat", function()
    enableAll()
    stopQuietly()
    local before = storeSignature()
    local restore = installSendSpies()
    assertNotNil(restore, "the client's chat surface is present to spy")
    seedTracked(0)
    FX.OnSlash("test")
    FX.Cooldown.Module:ProcessReadyPops(GetTime() + 60)   -- the pops speak
    T:Pump()                                              -- the pump refills
    FX.OnSlash("test")                                    -- and the exit
    local hits = restore()
    assertEquals(0, hits.chat, "C_ChatInfo.SendChatMessage was not called")
    assertEquals(0, hits.addon, "C_ChatInfo.SendAddonMessage was not called")
    if FX.Warlock and FX.Warlock.Comms then
        assertEquals(0, FX.Warlock.Comms.counts.sent, "the comms sent nothing")
        assertEquals(0, FX.Warlock.Comms.counts.queued, "and queued nothing")
    end
    if FX.Messages and FX.Messages.Announce then
        assertEquals(0, FX.Messages.Announce.counts.sent,
            "the announce channel sent nothing")
    end
    assertEquals(before, storeSignature(), "the store is byte-identical")
    for _, module in ipairs(FX.Settings:GetModuleNames()) do
        assertEquals(nil, FX.Settings:Get(module, "TestMode"),
            module .. " stores no TestMode key")
    end
end)

-- ---------------------------------------------------------------- the exits --

test("a combat start stops the mode and scrubs every synthetic entry",
function()
    enableAll()
    stopQuietly()
    seedTracked(0)
    FX.OnSlash("test")
    assertTrue(T.active)
    local _, entries = taggedEntries()
    local _, rows = taggedRows()
    assertTrue(entries > 0 and rows > 0, "both frames are filled")
    -- The real script, on the real frame, with the real event name
    -- (PLAYER_REGEN_DISABLED @UnitDocumentation.lua:3884).
    local onEvent = T._eventFrame:GetScript("OnEvent")
    onEvent(T._eventFrame, "PLAYER_REGEN_DISABLED")
    assertEquals(false, T.active, "the mode is off")
    assertEquals("combat", T.reason, "and says why")
    local offenders = survivingSyntheticRows()
    assertEquals(0, #offenders, "nothing survived: " .. table.concat(offenders, ", "))
end)

test("a logout scrubs every synthetic entry", function()
    enableAll()
    stopQuietly()
    seedTracked(0)
    FX.OnSlash("test")
    assertTrue(T.active)
    local onEvent = T._eventFrame:GetScript("OnEvent")
    onEvent(T._eventFrame, "PLAYER_LOGOUT")
    assertEquals(false, T.active)
    assertEquals("logout", T.reason)
    local offenders = survivingSyntheticRows()
    assertEquals(0, #offenders, "nothing survived: " .. table.concat(offenders, ", "))
    onEvent(T._eventFrame, "PLAYER_LEAVING_WORLD")   -- the zone-out twin
    assertEquals(false, T.active)
    local second = survivingSyntheticRows()
    assertEquals(0, #second, "nothing survived: " .. table.concat(second, ", "))
end)

test("the second press stops the mode and scrubs every synthetic entry",
function()
    enableAll()
    stopQuietly()
    seedTracked(0)
    FX.OnSlash("test")
    assertTrue(T.active)
    FX.OnSlash("test")
    assertEquals(false, T.active)
    assertEquals("stopped", T.reason)
    local offenders = survivingSyntheticRows()
    assertEquals(0, #offenders,
        "the exit law, asserted over both containers: "
        .. table.concat(offenders, ", "))
end)

test("a full cycle leaves no _source = \"test\" entry anywhere", function()
    enableAll()
    stopQuietly()
    seedTracked(0)
    for cycle = 1, 3 do
        FX.OnSlash("test")
        T:Pump()
        FX.Cooldown.Module:ProcessReadyPops(GetTime() + 90)
        if cycle % 2 == 0 then
            FX.OnSlash("test")
        else
            T._eventFrame:GetScript("OnEvent")(T._eventFrame,
                "PLAYER_REGEN_DISABLED")
        end
        local offenders = survivingSyntheticRows()
        assertEquals(0, #offenders,
            "cycle " .. cycle .. " left tagged rows: "
            .. table.concat(offenders, ", "))
    end
    assertEquals(false, T.active)
end)

-- ------------------------------------------------------------- the gates ----

test("the mode refuses to start in combat and prints the reason", function()
    enableAll()
    stopQuietly()
    seedTracked(0)
    local printed = {}
    local realPrint = FX.Print
    FX.Print = function(...)
        printed[#printed + 1] = table.concat({ tostringall(...) }, " ")
    end
    local keep = T.readers
    T.readers = { inCombat = function() return true end }
    local ok, why = T:Start()
    FX.Print = realPrint
    assertEquals(false, ok)
    assertEquals("combat", why)
    assertEquals(false, T.active, "the mode did not start")
    local refusals = T.stats.refusals
    assertTrue(refusals >= 1)
    local sawReason = false
    for _, line in ipairs(printed) do
        if line:find("NOT started") and line:find("combat") then
            sawReason = true
        end
    end
    assertTrue(sawReason, "the refusal says why: " .. table.concat(printed, " | "))
    assertEquals(0, #survivingSyntheticRows(), "and filled nothing")
    assertNil(T._ticker, "and armed no pump")
    T.readers = keep
end)

test("a secret InCombatLockdown answer is not a refusal", function()
    enableAll()
    stopQuietly()
    seedTracked(0)
    local keep = T.readers
    -- The SecretState consumer law: only a PLAIN true seals. The sim's own
    -- secret marker is the sentinel the client hands a sealed read.
    T.readers = { inCombat = function()
        return _G.SECRET_VALUE ~= nil and _G.SECRET_VALUE or nil
    end }
    local ok = T:Start()
    T.readers = keep
    assertTrue(ok, "an unknown is not a reason to refuse a layout pass")
    stopQuietly()
    T.readers = keep
end)

test("the pump re-arms a donor whose window has run out", function()
    enableAll()
    stopQuietly()
    seedTracked(0)
    FX.OnSlash("test")
    local _, n = taggedEntries()
    assertTrue(n > 0)
    -- Drain the bar the way the Sweep does it, then beat the pump.
    for name, e in pairs(Engine.entries) do
        if T.IsSynthetic(e) then Engine.entries[name] = nil end
    end
    local refilled = T:Pump()
    assertTrue(refilled > 0, "the pump re-arms the pool")
    local _, alive = taggedEntries()
    assertTrue(alive > 0, "and the bar is full again")
    stopQuietly()
end)

test("a feed that is not the mode's survives: the tag is the only key",
function()
    enableAll()
    stopQuietly()
    seedTracked(0)
    -- A real entry, the shape the read path writes (`source = "read"`,
    -- read-certified), of a name the demo has no claim on: the scrub keys on
    -- the tag and on nothing else.
    Engine.entries["DemoTest Real"] = {
        name = "DemoTest Real", start = GetTime(), duration = 20,
        endTime = GetTime() + 20, predicted = false, source = "read",
        anchored = true,
    }
    FX.OnSlash("test")
    FX.OnSlash("test")
    assertNotNil(Engine.entries["DemoTest Real"],
        "the scrub is the tag, never the container")
    Engine.entries["DemoTest Real"] = nil
end)

test("/fx test status reports the mode without changing it", function()
    enableAll()
    stopQuietly()
    local printed = {}
    local realPrint = FX.Print
    FX.Print = function(...)
        printed[#printed + 1] = table.concat({ tostringall(...) }, " ")
    end
    FX.OnSlash("test status")
    FX.Print = realPrint
    assertEquals(false, T.active, "a report is not a start")
    local saw = false
    for _, line in ipairs(printed) do
        if line:find("Test Mode") then saw = true end
    end
    assertTrue(saw, "the report names the mode")
end)

test("the suite leaves the shipped state as it found it", function()
    stopQuietly()
    assertEquals(false, T.active)
    assertEquals(0, #survivingSyntheticRows())
    assertNil(T._ticker, "no pump ticker is left running")
    for name in pairs(Engine.tracked) do
        if name:find("^DemoTest") then Engine.tracked[name] = nil end
    end
    for name in pairs(Engine.entries) do
        if name:find("^DemoTest") then Engine.entries[name] = nil end
    end
    assertEquals(nil, T.readers, "no injected reader is left behind")
end)

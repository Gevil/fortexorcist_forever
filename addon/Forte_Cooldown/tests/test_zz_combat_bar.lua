-- addon/Forte_Cooldown/tests/test_combat_bar.lua
-- I2f combat-simulation round (PLAN §11.2 row I2f): ONE fight, start to
-- leave, driven through the REAL frame scripts on the live sim clock:
--   * A_Admin.SetInCombat(true/false) -- the pair the modules gate on
--     (PLAYER_REGEN_DISABLED/ENABLED are delivered by SetInCombat itself,
--     docs/reference/wow-ui-sim-specs/time-and-capture.md);
--   * A_Admin.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", castGUID,
--     spellID, castBarID) -- the catalog 4-slot payload, injected (cast
--     COMPLETION is GUI-loop-driven, headless runs must inject it,
--     docs/research/upstream-sim-2026-11-03.md §2.6);
--   * A_Admin.SetSpellCooldown / SetGCD -- the sim seeds the real cooldown
--     window of a cast (its reads are plain numbers in the Forever profile:
--     the sim produces NO secret values, the note §3.2);
--   * A_Admin.AdvanceTime(0.1) steps -- one C_Timer drain per call, so the
--     Module's real 10 Hz ticker and the 1 Hz read net run the whole fight;
--   * leave combat + PLAYER_REGEN_ENABLED -> the out-of-combat reconcile.
-- The assertions ride the manual clock (the enable-once opt-in: the first
-- SetManualClock of THIS addon's test process is ours -- every pre-existing
-- Forte_Cooldown test injects its clock, none of them enables it), so every
-- timestamp below is exact.
--
-- The secret half rides the suite's fakes (test_reconcile.lua's law): the sim
-- cannot mint a secret value, so PlainOrNil is wrapped so the string
-- sentinel classifies as nil -- the exact downstream contract of a live
-- secret read -- and the combat split is read off InCombatLockdown, which
-- the binary DOES follow (measured: true under SetInCombat(true)).
--
-- The hidden-frame law (the Splash's :572 comment, the 2026-11-02 uiforever
-- law): a hidden frame never receives OnUpdate. A bar hidden by HideCombat
-- spends NO draw work -- the tests assert the slot pool stays empty.

local FX = ForteXorcist
local Engine = FX.Cooldown.Engine
local M = FX.Cooldown.Module
local Display = FX.Cooldown.Display
local Splash = FX.Cooldown.Splash
local Settings = FX.Settings

local SECRET = "FXTEST-SECRET-VALUE"

-- The rebuild-debounce settle (Module.lua RESCAN/REBUILD debounces are
-- 0.5 s): after a SetInCombat the sim fires SPELLS_CHANGED (measured I2f);
-- pumping this much clock lets the debounced Rebuild land BEFORE the
-- scenario casts, so the fight runs on settled state.
local REBUILD_SETTLE = 0.75

-- The fight's cast set: the gate picks them; every helper and test below
-- closes over THESE declarations (a helper defined before a file-scope
-- local silently closes over a global of the same name -- the nil class).
local shortId, shortName, shortCd
local longId, longName, longCd

local function near(actual, expected)
    return assertTrue(math.abs(actual - expected) < 1e-6)
end

local clockOn = false
local function enableClock(base)
    if clockOn then return end
    local ok = pcall(A_Admin.SetManualClock, base)
    assertTrue(ok, "the manual-clock opt-in is this process's first")
    clockOn = true
    near(base, GetTime())
end

local function step(dt)
    local ok, err = pcall(A_Admin.AdvanceTime, dt)
    assertTrue(ok, "AdvanceTime raised: " .. tostring(err))
end

local function fire(event, ...)
    local ok, err = pcall(A_Admin.FireEvent, event, ...)
    assertTrue(ok, "FireEvent(" .. event .. ") raised: " .. tostring(err))
end

--- The real frame-script path (the test_reconcile.lua binding law: the
--- frame is argument 1 of the script).
local function dispatch(event, ...)
    local f = M._eventFrame
    assertNotNil(f, "the event frame is bound at OnEnable")
    local h = f:GetScript("OnEvent")
    assertNotNil(h, "the frame carries its OnEvent script")
    local ok, err = pcall(h, f, event, ...)
    assertTrue(ok, "the real OnEvent script raised: " .. tostring(err))
end

local function countKeys(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function countEntries()
    return countKeys(Engine.entries)
end

local function liveSlots()
    local n = 0
    for _ in pairs(Display._byName or {}) do n = n + 1 end
    return n
end

local function activeSplashes()
    local n = 0
    for _, slot in ipairs((Splash._icons) or {}) do
        if slot.active then n = n + 1 end
    end
    return n
end

local function freshStorage()
    local storage = {}
    Engine:AttachStorage(storage)
    return storage
end

local function allKnown() return true end

--- Drain the Engine the way the 10 Hz ticker does (Sweep owns removals),
--- then let the display release the slots on one Update pass.
local function drainEngine()
    local now = GetTime()
    local out = {}
    local popInfo = {}
    Engine:Sweep(now + 100000, out, popInfo)
    M:ProcessReadyPops(now + 100000)
    Display:Init()
    Display:Update(Engine:Sorted({}), now)
end

local realPlainOrNil = FX.Compat.PlainOrNil
local function patchPlain()
    FX.Compat.PlainOrNil = function(v)
        if v == SECRET then return nil end
        return realPlainOrNil(v)
    end
end
local function restorePlain()
    FX.Compat.PlainOrNil = realPlainOrNil
end

--- A spell the injected cast of which lands in Engine:OnCast as a tracked
--- window: one the Engine tracks with a base duration inside [minS, maxS]
--- whose id resolves (the RecordCastEvent resolve: C_Spell.GetSpellInfo by
--- id, the name through Locale.CanonicalName) back ONTO a tracked name, and
--- which the sim's player knows (the pristine IsPlayerSpell answers,
--- test_reconcile.lua's law). MEASURED (I2f census): the sim's class profile
--- knows a small hand-picked set, and only the rows of that set resolve
--- through C_Spell by the data id at all -- the picker walks the tracked
--- rows directly so a known row cannot slip through the data-side join.
local function pickSpell(minS, maxS, taken)
    for name, row in pairs(Engine.tracked) do
        local cd = row.baseDuration
        if cd and cd >= Engine.MIN_COOLDOWN
            and cd >= minS and cd <= maxS and not taken[name] then
            local okN, infoN = pcall(C_Spell.GetSpellInfo, row.dataId)
            local nm = okN and infoN and realPlainOrNil(infoN.name)
            if type(nm) == "string" then
                nm = (FX.Locale and FX.Locale.CanonicalName(nm)) or nm
                if nm == name and FX.Compat.IsPlayerSpell(row.dataId) then
                    taken[name] = true
                    local okI, infoI = pcall(C_Spell.GetSpellInfo, name)
                    local clientId = okI and infoI
                        and realPlainOrNil(infoI.spellID)
                    return clientId or row.dataId, name, cd
                end
            end
        end
    end
    return nil
end

--- Fire the short cast through the real frame script and ensure the row
--- rides: the sim fires SPELLS_CHANGED on its combat/combat-admin events
--- (SetInCombat, SetSpellCooldown, SetGCD -- I2f measured: each arms the
--- Module's 0.5 s rebuild debounce, and the debounced Rebuild WIPES live
--- entries by design). The scenario settles the storm after every such
--- mutation and re-opens its watched row when a wipe ate it -- the same
--- recovery the live client gives (the spell is still on cooldown, the
--- client re-fires the cast event never; a wiped row self-heals on the
--- next cast/read, which is the rebuild law).
local function castShort(guid)
    fire("UNIT_SPELLCAST_SUCCEEDED", "player", guid, shortId, 11)
    A_Admin.SetSpellCooldown(shortId, shortCd)
    step(REBUILD_SETTLE)
    if not Engine.entries[shortName] then
        fire("UNIT_SPELLCAST_SUCCEEDED", "player", guid .. "-reb",
            shortId, 11)
        step(0.1)
    end
end

--- The multi-row bar shape: a second tracked window entered through the
--- Engine's OWN public feed (the exact state a resolved cast event leaves).
--- The real-EVENT path is proven by the picked spell's casts; the timeline's
--- multi-row drawing laws live in test_timeline.lua.
local function seedWindow(name, at)
    local row = Engine.tracked[name]
    assertNotNil(row, "the synthetic window rides a tracked row")
    return Engine:OnCast(name, at)
end

-- ------------------------------------------------------------- shared state --
local saved = {}
local printed, busEvents

local function captureChat()
    printed = {}
    saved.realPrint = FX.Print
    FX.Print = function(msg) printed[#printed + 1] = tostring(msg) end
end
local function releaseChat()
    if saved.realPrint then FX.Print = saved.realPrint end
    saved.realPrint = nil
end

-- ------------------------------------------------------------------- gate ----
test("aa combat gate: the manual clock is ours, the lockdown follows SetInCombat",
function()
    assertNotNil(FX._playerClass)
    assertNotNil(M._eventFrame, "the module enabled at login")
    saved.class = FX._playerClass
    saved.storage = Engine.learned
    saved.dbDiag = FX.db and FX.db.diag and FX.db.diag.casts
    saved.splashEnable = FX.Cooldown.SplashSkin.Enable
    saved.enabled = Display.frameState.enabled
    saved.hideCombat = Display.frameState.hideCombat
    saved.hideZero = Display.frameState.hideZero

    local out, inb = countEntries(), 0
    assertTrue(out >= 0)
    saved.wallAtStart = GetTime()     -- the pre-enable wall reading
    enableClock(50000)
    saved.enabledAt = GetTime()

    local okIC = pcall(function() return InCombatLockdown() end)
    assertTrue(okIC, "the global InCombatLockdown is a callable in this build")
    assertFalse(InCombatLockdown(), "the run starts out of combat")
    A_Admin.SetInCombat(true)
    assertTrue(InCombatLockdown(), "SetInCombat(true) flips the lockdown")
    A_Admin.SetInCombat(false)
    assertFalse(InCombatLockdown())

    -- The fight's cast set: a short window that POPS inside the fight, a
    -- long one that rides to the leave-combat reconcile.
    freshStorage()
    assertNotNil(Engine:Build(FX._playerClass, allKnown))
    drainEngine()
    local taken = {}
    shortId, shortName, shortCd = pickSpell(5, 25, taken)
    assertNotNil(shortId,
        "the profile class knows a tracked 5..25 s cooldown")
    for _, maxS in ipairs({ 120, 400, 1200, 3600 }) do
        longId, longName, longCd = pickSpell(shortCd + 10, maxS, taken)
        if longId then break end
    end
    if not longName then
        -- No second known cast in the profile: the second concurrent row
        -- is a synthetic tracked window (the Engine's own OnCast feed).
        -- The name must survive a live Rebuild, so it must pass the
        -- MODULE's own known gate (a debounced SPELLS_CHANGED rebuild
        -- trims the tracked set to what the client says is known -- the
        -- I2f settle law).
        for name, row in pairs(Engine.tracked) do
            if row.baseDuration and row.baseDuration >= 30
                and row.baseDuration <= 400 and not taken[name]
                and M.IsKnown(name) then
                longName = name
                longCd = row.baseDuration
                break
            end
        end
    end
    assertEquals(0, countEntries(), "the drain left nothing live")
    assertEquals(0, liveSlots(), "the drain left no slot on the bar")
end)

-- ------------------------------------------------------------- the fight ----
-- Phase 1: in combat -- casts land as predictions, the seeded real windows
-- anchor them on the 1 Hz net, the short window POPS mid-fight (bus event +
-- splash + bar release), and a default install sends nothing.
test("in combat: real cast events drive the Engine, the bar and the pop path",
function()
    drainEngine()
    Splash:SetEnabled(true)
    Display:Init()
    Display:SetEnabled(true)
    Display:SetHideCombat(false)
    Display:SetHideZero(false)
    local d0 = M:InitCastDiag()
    d0.seen, d0.plainId, d0.secretId, d0.resolved, d0.unresolved = 0, 0, 0, 0, 0
    d0.inSeen, d0.inPlain, d0.inSecret, d0.inResolved, d0.inUnresolved =
        0, 0, 0, 0, 0

    captureChat()
    busEvents = {}
    local hb = FX.On("FX_COOLDOWN_READY",
        function(name, now, texPath, category)
            busEvents[#busEvents + 1] = { name = name, category = category }
        end)
    assertNotNil(hb)

    A_Admin.SetInCombat(true)
    fire("PLAYER_REGEN_DISABLED")           -- the combat-start half (idempotent)
    assertTrue(InCombatLockdown())
    -- MEASURED (I2f): SetInCombat(true) makes the sim fire SPELLS_CHANGED;
    -- the Module's rebuild debounce (0.5 s) then runs Engine:Build, and a
    -- Build WIPS live entries by design (the rebuild law). A scenario that
    -- casts inside the debounce window watches its row vanish silently --
    -- not the module's fault (a real SPELLS_CHANGED mid-fight is the same
    -- law, and learned durations survive it). So: settle the storm first,
    -- then fight.
    step(REBUILD_SETTLE)
    drainEngine()
    Display:Update(Engine:Sorted({}), GetTime())
    assertTrue(Display.anchor:IsShown(),
        "an enabled bar with HideCombat off stands through the fight")

    -- Beat 1: the short cast. The real 4-slot payload -> the real frame
    -- script -> RecordCastEvent -> Engine:OnCast: a PREDICTED window.
    local t0 = GetTime()
    castShort("Cast-Fx-1")
    local e = Engine.entries[shortName]
    assertNotNil(e, "the injected cast opened the tracked window")
    assertTrue(e.start >= t0, "the row opened at/after the cast")
    near(e.start + shortCd, e.endTime)
    assertEquals("cast", e.source)
    assertTrue(e.predicted, "the cast-event window is a prediction")
    assertTrue(d0.seen >= 1)
    assertTrue(d0.plainId >= 1)
    assertTrue(d0.inSeen >= 1,
        "InCombatLockdown says in-combat at event time")
    assertTrue(d0.inPlain >= 1)
    assertTrue(d0.resolved >= 1)
    assertEquals(0, d0.secretId)
    assertEquals(0, d0.unresolved)

    -- The 10 Hz ticker (a real C_Timer on the manual clock) binds the slot.
    step(0.1) step(0.1)
    assertNotNil(Engine.entries[shortName],
        "the row survives the ticker passes (no event of the fight rebuilds)")
    assertNotNil(Display._byName[shortName], "the bar shows the cooling spell")
    assertEquals(1, liveSlots())

    -- Beat 2: the long row rides the GCD. When the profile knows a second
    -- castable cooldown it enters through the SAME event path; where it
    -- does not (the sim profile knows one, measured), the second concurrent
    -- row is the Engine's own OnCast feed -- the state a resolved cast
    -- leaves -- and the leave-combat leg proves it self-heals on the
    -- reconcile without a read.
    A_Admin.SetGCD(1.5)
    step(REBUILD_SETTLE)          -- swallow the GCD's spellstorm, if any
    local t1 = GetTime()
    if longName then
        if longId then
            fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-Fx-2",
                longId, 12)
            A_Admin.SetSpellCooldown(longId, longCd)
        else
            seedWindow(longName, t1)
        end
        local le = Engine.entries[longName]
        assertNotNil(le)
        near(t1, le.start)
    end
    assertNil(Engine.entries["61304"], "the GCD sentinel is not a bar row")

    -- The 1 Hz net pass. MEASURED (I2f): the sim's C_Spell.GetSpellCooldown
    -- does not take a NAME (Compat.GetSpellCooldownInfo("Magma Seal")
    -- raises; GetSpellCooldownDuration returns no object), so the module's
    -- whole read ladder is blind against the sim profile and the
    -- prediction rides untouched. On the live client a plain read anchors
    -- it (Engine:OnRead, test_tiers.lua) -- a launch-day fact, not a sim
    -- fact. The sim-side assert: the prediction survives the passes, and
    -- every row of the fight rides the bar.
    for _ = 1, 10 do step(0.1) end
    local se = Engine.entries[shortName]
    assertNotNil(se, "the short window is still counting down")
    assertEquals("cast", se.source,
        "the sim's name-keyed reads raise: the ladder is blind, the cast"
        .. " stamp owns the row")
    assertTrue(se.predicted)
    assertEquals(longName and 2 or 1, liveSlots(),
        "the fight's rows ride the bar")

    -- The pop, in combat. The sim fires SPELLS_CHANGED repeatedly during
    -- ordinary clock (I2f measured: an plain AdvanceTime ride eats live
    -- rows -- every storm arms the module's 0.5 s rebuild debounce and
    -- Engine:Build WIPES entries by the rebuild law; the storm law itself
    -- is pinned by its own test below). Riding a 20 s window therefore
    -- needs the storm defused for the ride: the module seam M.Rebuild is
    -- swapped for the duration of the ride (the suite's seam convention),
    -- so the window rides its real edge and pops exactly once.
    -- (I2f measured: a plain clock ride takes the window to its edge with
    -- NO Rebuild call -- the rebuild storms ride the combat edges, pinned
    -- by the test below -- so the ride needs no seam at all.)
    local se2 = Engine.entries[shortName]
    assertNotNil(se2, "the watched row rides to its edge")
    local edge = se2.start + shortCd
    while GetTime() < edge do step(math.min(1.0, edge - GetTime())) end
    step(0.06)
    assertNil(Engine.entries[shortName], "the engine retired the entry")
    -- The pop's observable half in the fight: the Secondary Splash (the
    -- popInfo consumer) -- the bus event's payload law is pinned exactly
    -- by test_splash.lua's bus test, not repeated here (I2f rode the bus
    -- seam in this harness; the module's ProcessReadyPops->Fire path fires
    -- it -- the splash half is the fight-visible proof).
    assertTrue(activeSplashes() > 0,
        "the Secondary Splash pops the ready icon")
    assertTrue(Splash.anchor:IsShown(), "the splash window shows for the pop")
    local slot = Display._byName[shortName]
    assertTrue(slot == nil or not slot._shown,
        "the popped name releases its slot")

    -- A default install: the fight spoke to no chat channel (E1: the pop
    -- prints nothing; Forte_Messages is opt-in; no announce fired).
    assertEquals(0, #printed,
        "a default install prints nothing through a fight: "
        .. table.concat(printed, " | "))

    FX.Off(hb)
    releaseChat()
end)

-- The storm law, pinned as a fact (I2f, measured through this seam): the
-- sim fires SPELLS_CHANGED during ordinary combat clock; the Module's event
-- frame coalesces the burst into ONE debounced Rebuild, and Rebuild is
-- Build, and Build WIPES the live entries by design (learned durations
-- ride in storage; the visible rows restart from events/reads).
test("zz SPELLS_CHANGED storms ride the rebuild law", function()
    -- The law, pinned deterministically (I2f, measured through this seam):
    -- the sim fires SPELLS_CHANGED on the combat ENTER edge (the gate's
    -- event probe: `seen=SPELLS_CHANGED`); the Module's handler coalesces
    -- the burst into the debounced Rebuild; and Rebuild IS Build, and
    -- Build WIPES the live entries by design -- the visible rows restart
    -- from events/reads, the learned durations ride in storage. The cast
    -- scenarios above settle after every combat-edge mutation for exactly
    -- this reason.
    assertNotNil(shortId, "the gate picked the fight's spells")
    drainEngine()
    A_Admin.SetInCombat(true)
    castShort("Cast-Fx-storm")
    assertTrue(countEntries() > 0, "the watched row is live pre-rebuild")
    local realBuild = Engine.Build
    local trims = nil
    Engine.Build = function(self, ...)
        trims = countEntries()
        return realBuild(self, ...)
    end
    M:Rebuild()                       -- the debounced rebuild's own call
    Engine.Build = realBuild
    A_Admin.SetInCombat(false)
    step(REBUILD_SETTLE)
    assertNotNil(trims, "the rebuild ran Build")
    assertTrue(trims > 0,
        "Build found the live entries and trimmed them (the rebuild law)")
    assertEquals(0, countEntries(),
        "the rebuild leaves no live row: the bar restarts from events")
end)

-- Phase 2: leave combat -- PLAYER_REGEN_ENABLED's reconcile pass re-anchors
-- the live row from the seeded read, a BACKDATED seed shortens the row
-- (the capture law: stamps move, durations ride), the bar drains clean.
test("zz leave combat: the regen reconcile corrects the predicted row",
function()
    busEvents = {}
    local hb = FX.On("FX_COOLDOWN_READY", function(name)
        busEvents[#busEvents + 1] = name
    end)

    A_Admin.SetInCombat(false)             -- delivers PLAYER_REGEN_ENABLED
    fire("PLAYER_REGEN_ENABLED")           -- idempotent companion (the path)
    assertFalse(InCombatLockdown())
    -- The leave storm (SPELLS_CHANGED -> the debounced Rebuild) settles
    -- FIRST; the watched row is then opened deliberately on settled state.
    step(REBUILD_SETTLE)
    drainEngine()

    -- Open the watched row: the known short cast.
    castShort("Cast-Fx-3")
    step(0.1)
    local le = Engine.entries[shortName]
    assertNotNil(le, "the row is live on the settled leave state")
    local endBefore = le.endTime
    assertEquals("cast", le.source,
        "out of combat the sim's name-keyed reads are still blind (I2f):"
        .. " the regen pass left the cast stamp in charge")

    -- The reconcile, run through the module's own read pass with a PLAIN
    -- SpellCooldownInfo at the compat seam (the seam is the unit-test
    -- convention; the sim stores its SetSpellCooldown windows keyed by id,
    -- and readKey hands the pass the data NAME). Backdated stamp: the pass
    -- re-anchors the row EARLIER -- the capture law: stamps move,
    -- durations ride, the row lands on the plain truth.
    local realInfo = FX.Compat.GetSpellCooldownInfo
    local function fakeInfo(fn)
        FX.Compat.GetSpellCooldownInfo = function(key)
            if key == shortName then
                return { startTime = fn and (GetTime() - 5) or GetTime(),
                         duration = shortCd, isActive = true,
                         isOnGCD = false }
            end
            return nil
        end
    end
    fakeInfo(true)
    local t = GetTime()
    M:ReadAll()
    FX.Compat.GetSpellCooldownInfo = realInfo
    local re = Engine.entries[shortName]
    assertNotNil(re, "the reconciled row stays live")
    assertEquals("read", re.source, "the plain read certified the window")
    assertFalse(re.predicted)
    near(t - 5, re.start)
    near(re.start + shortCd, re.endTime)
    assertTrue(re.endTime <= endBefore - 4.0,
        "the leave-combat reconcile moved the row to the plain truth")

    -- The prediction path (the sim's one secret-proof seam): with the
    -- readers answered SECRET through the PlainOrNil fake, the out-of-
    -- combat pass must leave the predicted row UNHARMED -- a secret read
    -- is no answer (the Engine OnRead/OnReadActive law, test_tiers.lua).
    local dReal = FX.Compat.PlainOrNil
    local realInfo = FX.Compat.GetSpellCooldownInfo
    local realCharges = FX.Compat.GetSpellCharges
    local realDur = FX.Compat.GetSpellCooldownDurationObject
    FX.Compat.PlainOrNil = function(v)
        if v == SECRET then return nil end
        return dReal(v)
    end
    FX.Compat.GetSpellCooldownInfo = function(key)
        if key ~= shortName then return nil end
        return { startTime = SECRET, duration = SECRET,
                 isActive = true, isOnGCD = false }
    end
    FX.Compat.GetSpellCharges = function()
        return { currentCharges = SECRET, maxCharges = SECRET,
                 cooldownStartTime = SECRET, cooldownDuration = SECRET }
    end
    FX.Compat.GetSpellCooldownDurationObject = nil
    local before = Engine.entries[shortName].endTime
    local startBefore = Engine.entries[shortName].start
    M:ReadAll()
    local kept = Engine.entries[shortName]
    FX.Compat.PlainOrNil = dReal
    FX.Compat.GetSpellCooldownInfo = realInfo
    FX.Compat.GetSpellCharges = realCharges
    FX.Compat.GetSpellCooldownDurationObject = realDur
    assertNotNil(kept, "the secret pass removed the row")
    near(before, kept.endTime, "the secret pass moved the end")
    near(startBefore, kept.start)

    -- SetGCD alone never grows the bar: sentinel rows are no rows.
    local n0 = countEntries()
    A_Admin.SetGCD(1.5)
    M:ReadAll()
    assertEquals(n0, countEntries(), "the GCD is not a tracked row")

    -- Drain: the watched window ends, the row pops, the bar empties.
    local guard = 0
    while countEntries() > 0 and guard < 8000 do
        step(0.1); guard = guard + 1
    end
    assertNil(Engine.entries[shortName],
        "the live ticker popped the window on its own clock")
    step(0.2)
    Display:Update(Engine:Sorted({}), GetTime())
    assertEquals(0, liveSlots(), "the bar drained with the fight")

    FX.Off(hb)
end)

-- The hidden-frame law in the fight's own shape: a bar hidden by HideCombat
-- spends NO draw work -- the slot pool stays empty while entries run.
test("HideCombat: the out-of-combat hidden bar does no draw work", function()
    assertNotNil(shortId, "the gate picked the fight's spells")
    -- The UpdateVisibility law (Timeline.lua:1407): with HideCombat on the
    -- bar shows IFF InCombatLockdown() answers true -- in a fight it is the
    -- living bar, out of combat it is a hidden frame. The hidden-frame law:
    -- a hidden frame runs no draw pass (Update's early return at :2061 --
    -- the same law as the Splash's "a hidden window carries no ticker").
    drainEngine()
    Display:Init()          -- UpdateVisibility no-ops without the anchor
    Display:SetEnabled(true)
    Display:SetHideZero(false)
    Display:SetHideCombat(true)
    Display:Update(Engine:Sorted({}), GetTime())
    assertFalse(Display.anchor:IsShown(),
        "out of combat the HideCombat bar is the hidden frame")
    A_Admin.SetInCombat(true)
    step(REBUILD_SETTLE)
    castShort("Cast-Fx-4")
    step(0.1) step(0.1)
    assertNotNil(Engine.entries[shortName],
        "the row rides the fight on the settled state")
    M:ProcessReadyPops(GetTime())
    Display:Update(Engine:Sorted({}), GetTime())
    assertTrue(Display.anchor:IsShown(),
        "HideCombat keeps the bar through the fight (the bar is a combat UI)")
    local slot = Display._byName[shortName]
    assertNotNil(slot, "the fight bound the slot")
    local textInFight = slot.timeFS:GetText()

    A_Admin.SetInCombat(false)
    Display:Update(Engine:Sorted({}), GetTime())
    assertFalse(Display.anchor:IsShown(),
        "the bar hides the pass after the fight, live rows and all")
    -- The draw-work law: pump a whole second of clock -- a hidden bar runs
    -- no per-slot pass, so the icon's countdown text does not move. (The
    -- logical binding rides: identity survives the hide, the release is a
    -- drawn-pass act.)
    step(1.0)
    Display:Update(Engine:Sorted({}), GetTime())
    assertEquals(1, liveSlots(), "the name keeps its binding across the hide")
    assertEquals(textInFight, slot.timeFS:GetText(),
        "the hidden bar ran no per-slot draw pass across a second of clock")

    Display:SetHideCombat(saved.hideCombat)
    drainEngine()          -- a SHOWN bar (restored) releases the slots
    assertEquals(0, liveSlots())
end)

-- The secret half (the suite's fake, test_reconcile.lua's law): through the
-- REAL frame script, in combat, a secret spellID is counted in the in-combat
-- secret half, names no spell, and never touches the Engine.
test("in combat: a secret cast id is counted, resolves to nothing, inert",
function()
    drainEngine()
    local d0 = M:InitCastDiag()
    local seen0, inSeen0 = d0.seen, d0.inSeen
    local entries0 = countEntries()
    local secret0, inSecret0 = d0.secretId, d0.inSecret
    local resolved0, inResolved0 = d0.resolved, d0.inResolved
    local plain0 = d0.plainId
    A_Admin.SetInCombat(true)
    patchPlain()
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-Fx-sec", SECRET, 31)
    restorePlain()
    A_Admin.SetInCombat(false)
    assertEquals(seen0 + 1, d0.seen)
    assertEquals(inSeen0 + 1, d0.inSeen)
    assertEquals(secret0 + 1, d0.secretId,
        "the id classified secret through the PlainOrNil fake")
    assertEquals(inSecret0 + 1, d0.inSecret,
        "and landed in the IN-COMBAT secret half")
    assertEquals(plain0, d0.plainId, "never the plain half")
    assertEquals(resolved0, d0.resolved)
    assertEquals(inResolved0, d0.inResolved)
    assertEquals(entries0, countEntries(), "the Engine saw a nothing")
end)

-- ------------------------------------------------------------ teardown ----
test("zzz the suite leaves the module state as it found it", function()
    drainEngine()
    A_Admin.SetInCombat(false)
    Splash:SetEnabled(saved.splashEnable)
    if not saved.splashEnable and Splash.anchor then Splash.anchor:Hide() end
    Display:SetEnabled(saved.enabled)
    Display:SetHideCombat(saved.hideCombat)
    Display:SetHideZero(saved.hideZero)
    if saved.storage then Engine:AttachStorage(saved.storage) end
    Engine:Build(FX._playerClass, allKnown)
    M:ReadAll()
    assertEquals(0, countEntries(), "no fight row survives the suite")
    assertEquals(0, liveSlots())
    if saved.splashEnable ~= nil then
        assertEquals(saved.splashEnable, FX.Cooldown.SplashSkin.Enable)
    end
    assertEquals(saved.hideCombat, Display.frameState.hideCombat)
    assertEquals(saved.hideZero, Display.frameState.hideZero)
    releaseChat()
    -- The manual clock is a process-wide enable-once: the suite runs LAST in
    -- this add-on's process (file order), and a post-suite live-GetTime
    -- consumer reads GetTime(), so hand the clock back near the wall-clock
    -- reading the process started with. The deltas stay exact; nothing in
    -- this repo's Forte_Cooldown suite runs after this file.
    if clockOn and saved.enabledAt then
        local wall = saved.wallAtStart or 0
        local target = math.max(0, wall - saved.enabledAt)
        if target > 0 then pcall(A_Admin.AdvanceTime, target) end
    end
end)

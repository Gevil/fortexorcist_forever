-- =============================================================================
-- test_zzb_aspect_hunter.lua -- the aspect reminder after a /reload (bug
-- report 2026-11-13): a worn aspect is READ at PLAYER_ENTERING_WORLD and on
-- the player's own aura changes, not only at PLAYER_REGEN_ENABLED.
--
-- NAME LAW: sorts after test_zz_combat_hunter.lua and rides ITS manual-clock
-- opt-in (SetManualClock is enable-once and process-wide); when this file runs
-- alone it enables the clock itself. `C_Timer.After` fires on AdvanceTime.
--
-- WHAT RIDES REAL: the registered frame's OnEvent script (the module's real
-- `onToolEvent`), the real debounce timers, the real Reminder frame. WHAT IS
-- INJECTED: the aura reader (`FX.Hunter.DefaultAuraReader`, looked up by
-- Reconcile at call time), the tracker's combat predicate, and -- for the
-- registration leg only -- `CreateFrame` (a recording frame). The sim cannot
-- force a secret value, so "secret" is the reader's nil answer, the exact
-- downstream contract (DefaultAuraReader maps secret -> nil).
-- =============================================================================
local FX = ForteXorcist
local Tools = FX.Hunter.Tools
local Reminder = FX.Hunter.Reminder
local HAWK = "Aspect of the Hawk"

local function step(dt)
    local left = dt
    while left > 1e-9 do
        local d = math.min(0.1, left)
        local ok, err = pcall(A_Admin.AdvanceTime, d)
        assertTrue(ok, "AdvanceTime raised: " .. tostring(err))
        left = left - d
    end
end

local function ensureClock()
    if pcall(A_Admin.AdvanceTime, 0.01) then return end
    local ok, err = pcall(A_Admin.SetManualClock, 140000)
    assertTrue(ok, "SetManualClock raised: " .. tostring(err))
end

--- Run `fn(rig)` against a fresh tracker wired through the live event frame
--- and the real Reminder; hand every seam back afterwards, error or not.
local function withRig(fn)
    ensureClock()
    local saved = {
        aspects = Tools.Aspects,
        enabled = Tools._eventsEnabled == true,
        reader = FX.Hunter.DefaultAuraReader,
        remAspects = Reminder.Aspects,
    }
    if not Reminder.anchor then Reminder:Init() end

    local rig = { combat = false, worn = nil, secret = false,
        reads = 0, reconciles = 0 }
    local t = FX.Hunter.NewAspectTracker({
        names = Tools.aspectNames,
        inCombat = function() return rig.combat end,
    })
    local origReconcile = t.Reconcile
    t.Reconcile = function(self, ...)
        rig.reconciles = rig.reconciles + 1
        return origReconcile(self, ...)
    end
    rig.tracker = t
    FX.Hunter.DefaultAuraReader = function(name)
        rig.reads = rig.reads + 1
        if rig.secret then return nil end
        return name == rig.worn
    end
    Tools.Aspects = t
    Reminder:SetAspects(t)
    Reminder:Refresh()
    Tools:DisableEvents()
    Tools:EnableEvents()
    local f = Tools._eventFrame
    local script = f:GetScript("OnEvent")
    assertNotNil(script, "the enable path installs the real OnEvent script")
    rig.fire = function(event, ...) script(f, event, ...) end
    rig.shown = function() return Reminder.anchor:IsShown() end

    local ok, err = pcall(fn, rig)
    step(1.5)                       -- drain any armed debounce/late timer
    Tools.Aspects = saved.aspects
    Reminder:SetAspects(saved.remAspects)
    Reminder:HideNow()
    FX.Hunter.DefaultAuraReader = saved.reader
    if not saved.enabled then Tools:DisableEvents() end
    if not ok then error(err, 0) end
end

-- ------------------------------------------------------- tracker callback --
test("Reconcile notifies the listener only when current moves", function()
    local t = FX.Hunter.NewAspectTracker({
        names = Tools.aspectNames, inCombat = function() return false end })
    local seen = {}
    t:OnChange(function(cur, prev) seen[#seen + 1] = tostring(prev) .. ">" .. tostring(cur) end)
    local worn = HAWK
    local function read(name) return name == worn end
    t:Reconcile(read)                                   -- nil -> Hawk
    t:Reconcile(read)                                   -- same: silent
    worn = "Aspect of the Cheetah"
    t:Reconcile(read)                                   -- Hawk -> Cheetah
    worn = nil
    t:Reconcile(read)                                   -- Cheetah -> nil
    t:Reconcile(read)                                   -- still nil: silent
    t:OnCast(HAWK)
    t:Reconcile(function() return nil end)              -- unknown: unchanged
    assertEquals(3, #seen, table.concat(seen, " | "))
    assertEquals("nil>" .. HAWK, seen[1])
    assertEquals(HAWK .. ">Aspect of the Cheetah", seen[2])
    assertEquals("Aspect of the Cheetah>nil", seen[3])
    -- A raising listener never reaches the caller.
    t:OnChange(function() error("listener", 0) end)
    worn = HAWK
    assertEquals("adopted", t:Reconcile(read))
    t:OnChange(nil)
end)

-- --------------------------------------------------------------------- (a) --
test("PLAYER_ENTERING_WORLD adopts a worn aspect and hides the reminder", function()
    withRig(function(rig)
        assertNil(rig.tracker:Current(), "a fresh tracker knows nothing (post-reload)")
        assertTrue(rig.shown(), "the reminder blinks before the zone-in read")
        rig.worn = HAWK
        rig.fire("PLAYER_ENTERING_WORLD", false, true)
        assertEquals(HAWK, rig.tracker:Current(),
            "the aspect is read at PLAYER_ENTERING_WORLD")
        assertFalse(rig.shown(), "and the reminder hides at once")
    end)
end)

-- --------------------------------------------------------------------- (b) --
test("auras not loaded at the zone-in: the late pass corrects", function()
    withRig(function(rig)
        rig.worn = nil                       -- plain absent: not loaded yet
        rig.fire("PLAYER_ENTERING_WORLD", true, false)
        assertNil(rig.tracker:Current())
        assertTrue(rig.shown())
        local atPew = rig.reconciles
        assertEquals(1, atPew)
        rig.worn = HAWK                      -- the auras arrive
        step(0.5)
        assertNil(rig.tracker:Current(), "nothing fires before the ~1 s pass")
        step(0.7)
        assertEquals(HAWK, rig.tracker:Current(), "the late pass adopted it")
        assertFalse(rig.shown(), "and the reminder hid")
        step(5)
        assertEquals(2, rig.reconciles,
            "exactly the immediate and the late pass: the late pass never re-arms")
    end)
end)

test("auras not loaded at the zone-in: UNIT_AURA corrects before the late pass", function()
    withRig(function(rig)
        rig.fire("PLAYER_ENTERING_WORLD", true, false)
        assertTrue(rig.shown())
        rig.worn = HAWK
        rig.fire("UNIT_AURA", "player", { addedAuras = {} })
        step(0.3)
        assertEquals(HAWK, rig.tracker:Current())
        assertFalse(rig.shown())
        step(5)
        assertEquals(3, rig.reconciles, "PEW + UNIT_AURA + the one late pass")
        assertEquals(HAWK, rig.tracker:Current(), "the late pass only confirmed")
    end)
end)

-- --------------------------------------------------------------------- (c) --
test("an aspect cancelled out of combat brings the reminder back", function()
    withRig(function(rig)
        rig.worn = HAWK
        rig.fire("PLAYER_ENTERING_WORLD", false, true)
        assertEquals(HAWK, rig.tracker:Current())
        assertFalse(rig.shown())
        rig.worn = nil                       -- right-click cancel
        rig.fire("UNIT_AURA", "player", {})
        assertEquals(HAWK, rig.tracker:Current(), "the pass is debounced, not inline")
        step(0.3)
        assertNil(rig.tracker:Current(), "the aura change cleared the aspect")
        assertTrue(rig.shown(), "and the hidden reminder came back with no OnUpdate help")
        -- Switching to another aspect: name -> other, still no reminder.
        rig.worn = "Aspect of the Cheetah"
        rig.fire("UNIT_AURA", "player", {})
        step(0.3)
        assertEquals("Aspect of the Cheetah", rig.tracker:Current())
        assertFalse(rig.shown())
    end)
end)

-- --------------------------------------------------------------------- (d) --
test("in combat UNIT_AURA and PLAYER_ENTERING_WORLD read nothing", function()
    withRig(function(rig)
        rig.tracker:OnCast(HAWK)             -- the in-combat prediction
        rig.combat = true
        rig.worn = nil                       -- would clear if it were read
        for _ = 1, 5 do rig.fire("UNIT_AURA", "player", {}) end
        rig.fire("PLAYER_ENTERING_WORLD", false, false)
        step(2)
        assertEquals(0, rig.reads, "no aura read while in combat")
        assertEquals(0, rig.reconciles)
        assertEquals(HAWK, rig.tracker:Current(), "state unchanged")
    end)
end)

test("a secret read never clears the tracked aspect", function()
    withRig(function(rig)
        rig.tracker:OnCast(HAWK)
        rig.secret = true                    -- every read is "no knowledge"
        rig.fire("UNIT_AURA", "player", {})
        step(0.3)
        assertTrue(rig.reads > 0, "out of combat the pass does read")
        assertEquals(HAWK, rig.tracker:Current(), "but nil reads keep the aspect")
        assertFalse(rig.shown())
    end)
end)

-- --------------------------------------------------------------------- (e) --
test("a burst of 20 UNIT_AURA events is one reconcile", function()
    withRig(function(rig)
        for _ = 1, 20 do rig.fire("UNIT_AURA", "player", {}) end
        assertEquals(0, rig.reconciles, "nothing runs inline")
        step(0.3)
        assertEquals(1, rig.reconciles)
        assertEquals(#Tools.aspectNames, rig.reads,
            "one pass: one read per aspect (all plainly absent)")
        -- The flag self-cleared: the next burst earns its own pass.
        for _ = 1, 20 do rig.fire("UNIT_AURA", "player", {}) end
        step(0.3)
        assertEquals(2, rig.reconciles)
    end)
end)

-- --------------------------------------------------------------------- (f) --
test("UNIT_AURA for another unit is ignored", function()
    withRig(function(rig)
        rig.fire("UNIT_AURA", "target", {})
        rig.fire("UNIT_AURA", "pet", {})
        rig.fire("UNIT_AURA", nil, nil)
        step(2)
        assertEquals(0, rig.reconciles)
        assertEquals(0, rig.reads)
    end)
end)

-- --------------------------------------------------------------------- (g) --
test("registration happens in the enable path and the teardown undoes it", function()
    ensureClock()
    local saved = { frame = Tools._eventFrame, enabled = Tools._eventsEnabled,
        create = _G.CreateFrame, aspects = Tools.Aspects,
        reader = FX.Hunter.DefaultAuraReader }
    local unit, plain, script = {}, {}, nil
    local fake = {}
    function fake:RegisterUnitEvent(e, u) unit[e] = u end
    function fake:RegisterEvent(e) plain[e] = true end
    function fake:UnregisterUnitEvent(e, u) if unit[e] == u then unit[e] = nil end end
    function fake:UnregisterEvent(e) plain[e] = nil end
    function fake:SetScript(k, fn) if k == "OnEvent" then script = fn end end
    function fake:GetScript(k) if k == "OnEvent" then return script end end
    _G.CreateFrame = function() return fake end
    Tools._eventFrame, Tools._eventsEnabled = nil, false

    local t = FX.Hunter.NewAspectTracker({
        names = Tools.aspectNames, inCombat = function() return false end })
    local recon = 0
    local orig = t.Reconcile
    t.Reconcile = function(self, ...) recon = recon + 1; return orig(self, ...) end
    Tools.Aspects = t
    FX.Hunter.DefaultAuraReader = function() return false end

    local ok, err = pcall(function()
        assertNil(unit.UNIT_AURA, "nothing registers at load")
        Tools:EnableEvents()
        assertEquals("player", unit.UNIT_AURA,
            "UNIT_AURA is registered for the player only")
        assertTrue(plain.PLAYER_ENTERING_WORLD, "PLAYER_ENTERING_WORLD stays registered")
        assertTrue(plain.PLAYER_REGEN_ENABLED, "PLAYER_REGEN_ENABLED stays registered")
        assertNil(plain.UNIT_AURA, "and never as an all-units event")
        assertNotNil(script)
        -- A pass armed before the teardown does not run after it.
        script(fake, "UNIT_AURA", "player", {})
        Tools:DisableEvents()
        assertNil(unit.UNIT_AURA, "the teardown unregisters UNIT_AURA")
        assertNil(plain.PLAYER_ENTERING_WORLD)
        assertNil(script, "and silences the script")
        step(2)
        assertEquals(0, recon, "a pending pass is dropped by the teardown")
    end)
    _G.CreateFrame = saved.create
    Tools._eventFrame, Tools._eventsEnabled = saved.frame, saved.enabled
    Tools.Aspects = saved.aspects
    FX.Hunter.DefaultAuraReader = saved.reader
    if not ok then error(err, 0) end
end)

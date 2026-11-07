-- addon/Forte_Timer/tests/test_pump_and_unique.lua
-- Code-review-10 section (c) MT-4 + MT-5 + m7: the cast pump's three live
-- behaviours d490e2e shipped with NO test, all three of which are live-client
-- fixes (the owner's dungeon session, 2026-11-06).
--
--   * MT-4 -- `Casts.UNIQUE` (Core/Casts.lua): a single-target effect can
--     wear on ONE unit, so a fresh cast on a NEW target retires this spell's
--     rows on every other target (the live case: Hunter's Mark bars rode
--     dead targets for their full 120 s). The deDE leg is the review's i3:
--     the table is keyed by the CANONICAL name, and the pump's `job.name` is
--     `NameOf`'s canonicalized output -- on a localized client the localized
--     cast name resolves THROUGH `FX.Locale.CanonicalName` to the same key,
--     so the retirement fires there exactly as here.
--   * MT-5 -- the pump's pcall isolation + the hole-heal (live: one raising
--     job used to tear the queue and stop the pump: "attempt to index local
--     'job' (a nil value)" on every later pump): a raising job costs ITS
--     row, the rest of the queue runs, the queue heals dense, the `raised`
--     counter moves, and the chat report is once-per-distinct-message.
--   * m7 -- `raised` is inside InitStatus's key contract (the pump's
--     `InitStatus()` call before the increment is a no-op for a key the
--     contract does not enumerate).
--
-- The spine is driven PUBLIC (OnSent / OnSucceeded / Pump, the
-- test_expiry_identity.lua idiom) with an injected clock and an injected
-- name resolver; the poison is installed on `Rows.InsertFromCast`, the one
-- call the insert job makes.

local FX = ForteXorcist
local Rows = FX.Timer.Rows
local Casts = FX.Timer.Casts
local Laws = FX.Timer.Laws
local Registry = FX.Timer.Registry
local Reconcile = FX.Timer.Reconcile
local realInsert0, realPrint0 = FX.Timer.Rows.InsertFromCast, FX.Print

local MARK_ID, STING_ID = 14325, 425737

local function buildHunterRegistry()
    Registry:AttachStorage({})
    local n = Registry:Build("HUNTER")
    assertTrue(n and n > 0)
end

local liveOptions
local function quietRows()
    Rows:Clear()
    liveOptions = Rows.options
    Rows.options = {
        smooth = Laws.SMOOTH, maxOn = false, maxRows = 32, oneMax = true,
        maxTimeOn = true, maxTime = Laws.MAXTIME, groupID = true,
        outwands = true, blink = true, blinkAt = Laws.BLINK,
        hideLonger = false, hideTime = Laws.HIDE_TIME,
        expireMessage = false,
        onExpire = function() end,
    }
    return Rows
end
local function restoreRows()
    -- Idempotent (the legs run this at the body end AND in the pcall
    -- wrapper; the first run clears the capture and a second must not
    -- write nil back over the live options).
    if liveOptions == nil then return end
    Rows:Clear()
    Rows.options = liveOptions
    liveOptions = nil
end

--- The live client answers the target token for the registered set; the
--- casts name-resolve through the seam (the sim's profile class is not a
--- Hunter). Returns the save table.
local function installSpine()
    local saved = {
        resolveName = Casts.resolveName, now = Casts.now, onRow = Casts.onRow,
        UnitExists = _G.UnitExists, UnitName = _G.UnitName,
        UnitIsDead = _G.UnitIsDead, liveness = Reconcile.liveness,
    }
    Casts.resolveName = function(id)
        if id == MARK_ID then return "Hunter's Mark" end
        if id == STING_ID then return "Serpent Sting" end
        return nil
    end
    Casts.onRow = nil
    _G.UnitExists = function(token) return token == "target" end
    _G.UnitName = function(token)
        return token == "target" and "Vile Poacher" or nil
    end
    _G.UnitIsDead = function() return false end
    Reconcile.liveness = function() return nil end
    return saved
end
local function restoreSpine(saved)
    Casts.resolveName, Casts.now, Casts.onRow =
        saved.resolveName, saved.now, saved.onRow
    _G.UnitExists, _G.UnitName, _G.UnitIsDead =
        saved.UnitExists, saved.UnitName, saved.UnitIsDead
    Reconcile.liveness = saved.liveness
end

--- One complete cast: the SENT capture, the SUCCEEDED settle, the Pump that
--- lands the row.
local function castAtTarget(spellID, targetKey, now)
    Casts:OnSent(targetKey, spellID, now)
    Casts:OnSucceeded(spellID, now)
    Casts:Pump(now + Laws.SETTLE + 0.01)
end

-- ==================================================== MT-4: Casts.UNIQUE ==

test("MT-4: a Hunter's Mark on a NEW target retires the bars on the OLD ones",
function()
    local __ok, __err = pcall(function()
        buildHunterRegistry()
        quietRows()
        Casts:Init(Rows, Rows.options)
        Casts:Erase()
        local saved = installSpine()
        local clock = { 40000 }
        Casts.now = function() return clock[1] end
    
        castAtTarget(MARK_ID, "Vile Poacher", 40000)
        local first = Rows:Find("Hunter's Mark", "Vile Poacher")
        assertNotNil(first, "the mark row rides its first target")
        assertEquals(Laws.NORMAL, first.state)
    
        -- The recast on the NEXT mob (the live case: the pack pulls, the mark
        -- moves, the old bar is a stale window on a corpse).
        castAtTarget(MARK_ID, "River Crocolisk", 40050)
        local second = Rows:Find("Hunter's Mark", "River Crocolisk")
        assertNotNil(second, "the new target has its row")
        assertEquals(Laws.NORMAL, second.state)
        assertEquals(Laws.REMOVE, first.state,
            "the single-target effect retires the OLD target's row (Casts.UNIQUE)")
    
        -- A non-unique spell proves the band is per-spell, not a global sweep.
        castAtTarget(STING_ID, "Vile Poacher", 40100)
        castAtTarget(STING_ID, "River Crocolisk", 40110)
        local a = Rows:Find("Serpent Sting", "Vile Poacher")
        local b = Rows:Find("Serpent Sting", "River Crocolisk")
        assertNotNil(a); assertNotNil(b)
        assertEquals(Laws.NORMAL, a.state, "a DoT rides BOTH targets")
        assertEquals(Laws.NORMAL, b.state)
        restoreSpine(saved)
        Casts:Erase()
        restoreRows()
    
    end)
    Rows.InsertFromCast = realInsert0
    FX.Print = realPrint0
    restoreRows()
    if not __ok then error(__err, 0) end
end)

test("MT-4 / i3: the deDE client name canonicalizes to the key: the retirement fires on a localized client",
function()
    local __ok, __err = pcall(function()
        buildHunterRegistry()
        quietRows()
        Casts:Init(Rows, Rows.options)
        Casts:Erase()
        local saved = installSpine()
        local clock = { 41000 }
        Casts.now = function() return clock[1] end
        -- The deDE client: the feed's raw name is the localized string; the
        -- alias table (built from the data ids) canonicalizes it. The sim's
        -- profile is enUS, so the alias seam is installed -- the exact contract
        -- a deDE client's FX.Locale carries for this spell.
        local realCanon = FX.Locale.CanonicalName
        FX.Locale.CanonicalName = function(name)
            if name == "Jägermark" then return "Hunter's Mark" end
            return realCanon(name)
        end
        -- The feed seam now answers the CLIENT's name, not the canonical one.
        Casts.resolveName = function(id)
            if id == MARK_ID then return "Jägermark" end
            return nil
        end
        castAtTarget(MARK_ID, "Vile Poacher", 41000)
        local first = Rows:Find("Hunter's Mark", "Vile Poacher")
        assertNotNil(first, "the localized cast row keys the canonical name")
        castAtTarget(MARK_ID, "River Crocolisk", 41050)
        local second = Rows:Find("Hunter's Mark", "River Crocolisk")
        assertNotNil(second, "the recast row is there")
        assertEquals(Laws.REMOVE, first.state,
            "the deDE cast retires the old row: Casts.UNIQUE keys the CANONICAL"
            .. " name and job.name is NameOf's canonicalized output (review i3)")
        FX.Locale.CanonicalName = realCanon
        restoreSpine(saved)
        Casts:Erase()
        restoreRows()
    
    end)
    Rows.InsertFromCast = realInsert0
    FX.Print = realPrint0
    restoreRows()
    if not __ok then error(__err, 0) end
end)

-- ================================================ MT-5: the raise island ==

test("m7: 'raised' is inside the InitStatus key contract",
function()
    local __ok, __err = pcall(function()
        local st = Casts:InitStatus()
        assertEquals("number", type(st.raised),
            "InitStatus enumerates the pump's raise counter (the pump's"
            .. " InitStatus()-then-increment is a no-op for a key the contract"
            .. " does not list)")
        Casts.status = st
    
    end)
    Rows.InsertFromCast = realInsert0
    FX.Print = realPrint0
    restoreRows()
    if not __ok then error(__err, 0) end
end)

test("MT-5: a raising job costs its OWN row: the rest of the queue runs, the queue heals, the counters move, the chat line is once-per-distinct",
function()
    local __ok, __err = pcall(function()
        buildHunterRegistry()
        quietRows()
        Casts:Init(Rows, Rows.options)
        Casts:Erase()
        local saved = installSpine()
        local clock = { 42000 }
        Casts.now = function() return clock[1] end
        Casts:InitStatus()
        local raised0 = Casts.status.raised
    
        -- The poison: the insert job for STING_ID raises inside the pcall. The
        -- second job (Hunter's Mark) is the queue that must run behind it.
        local realInsert = Rows.InsertFromCast
        Rows.InsertFromCast = function(self, name, ...)
            if name == "Serpent Sting" then
                error("FXTEST-POISONED-INSERT", 0)
            end
            return realInsert(self, name, ...)
        end
        local printed, realPrint = {}, FX.Print
        FX.Print = function(text) printed[#printed + 1] = tostring(text) end
    
        -- One pump, two due jobs: the poison FIRST, a live cast AFTER it.
        Casts:OnSent("Vile Poacher", STING_ID, 42000)
        Casts:OnSucceeded(STING_ID, 42000)
        Casts:OnSent("Vile Poacher", MARK_ID, 42000)
        Casts:OnSucceeded(MARK_ID, 42000)
        local ok = pcall(Casts.Pump, Casts, 42000 + Laws.SETTLE + 0.01)
    
        assertTrue(ok, "the pump SURVIVES a raising job (the live 2026-11-06"
            .. " queue tear is the shape this leg refuses)")
        assertNil(Rows:Find("Serpent Sting", "Vile Poacher"),
            "the poisoned job costs its own row")
        assertNotNil(Rows:Find("Hunter's Mark", "Vile Poacher"),
            "the jobs BEHIND the poison ran in the same pump")
        assertEquals(1, Casts.status.raised - raised0,
            "the raise is counted")
        local failed = 0
        for _, line in ipairs(printed) do
            if line:find("cast job failed") then failed = failed + 1 end
        end
        assertEquals(1, failed, "one chat line for the first distinct failure")
    
        -- The queue HEALED dense: no nil hole is left behind the dead job, and a
        -- second pump of the same poison adds the count, not a second line
        -- (the _pumpErr dedupe).
        for i = 1, #Casts.pending do
            assertNotNil(Casts.pending[i],
                "the queue is dense at index " .. i .. " after the heal")
        end
        Casts:OnSent("River Crocolisk", STING_ID, 42050)
        Casts:OnSucceeded(STING_ID, 42050)
        local ok2 = pcall(Casts.Pump, Casts, 42050 + Laws.SETTLE + 0.01)
        assertTrue(ok2, "the pump runs the healed queue")
        assertEquals(2, Casts.status.raised - raised0,
            "the second raise counts")
        failed = 0
        for _, line in ipairs(printed) do
            if line:find("cast job failed") then failed = failed + 1 end
        end
        assertEquals(1, failed, "the SAME message reports once (the dedupe)")
    
        FX.Print = realPrint
        Rows.InsertFromCast = realInsert
        restoreSpine(saved)
        Casts:Erase()
        restoreRows()
    
    end)
    Rows.InsertFromCast = realInsert0
    FX.Print = realPrint0
    restoreRows()
    if not __ok then error(__err, 0) end
end)

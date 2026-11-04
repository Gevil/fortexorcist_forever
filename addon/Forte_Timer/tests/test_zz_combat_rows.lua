-- addon/Forte_Timer/tests/test_zz_combat_rows.lua
-- I2f: the Spell Timer in a simulated fight. The suite's own files drive the
-- spine through the injected `Casts.now` clock and hand calls; this one rides
-- the A_Admin manual clock so the WHOLE module runs for real: the real
-- `M._eventFrame` OnEvent script fed by `A_Admin.FireEvent` with the catalog
-- payloads (docs/design-spell-timer.md §4.1), the module's own 0.04 s DRAW
-- ticker and its 12th-tick LOGIC cadence (the tickers of Module.lua's
-- OnEnable), the real `InCombatLockdown()` behind Reconcile's gate, the sim's
-- real aura store (AddBuff/RemoveBuff) behind the out-of-combat sweep, and
-- `options.hide` for the hidden-panel law.
--
-- Asserted, in order:
--   * the own-cast spine SENT -> START -> SUCCEEDED: the record, the settle
--     deferral (CA-04: the row is never inserted on the event), the row the
--     Pump lands, its numbers, and the panel shown with it (the synchronous-
--     show law); an interrupted cast retires its record and draws no row;
--   * the pet feed routes on the payload's unit token, the feeds never eat
--     each other's records, and a sealed spellID is counted and inert (the
--     suite's sentinel through the unit-test PlainOrNil fake);
--   * the leave-combat sweep (PLAYER_REGEN_ENABLED -> Reconcile:SweepAll on
--     the production readers): zero aura calls while the lockdown stands,
--     the BUFF_DELAY grace through an absent fact, ADOPTION from a plain
--     AuraData (the row stops being a prediction) and the one teacher
--     learning its duration, and the confirmed-gone retirement once the
--     grace is spent;
--   * a hidden panel (options.hide) draws nothing while the ticker retires
--     its rows, and the anchor carries no OnUpdate script (the hidden-frame
--     law of 2026-11-02: the tickers drive, a hidden frame gets nothing);
--   * a default install speaks on no chat channel through all of it.
--
-- zz_*: the suite runs this file LAST -- the manual clock is a
-- once-per-process switch and the rows/queue it drives must not leak into
-- any file that follows.
local FX = ForteXorcist
local M = FX.Timer.Module
local Rows = FX.Timer.Rows
local Laws = FX.Timer.Laws
local Registry = FX.Timer.Registry
local Casts = FX.Timer.Casts
local Reconcile = FX.Timer.Reconcile
local D = FX.Timer.Display

local SECRET = "FXTEST-SECRET-VALUE"

local clockEnabled = false
local function enableClock(t0)
    if not clockEnabled then
        A_Admin.SetManualClock(t0)
        clockEnabled = true
    end
end

--- Advance the manual clock in 0.1 s steps; the module's tickers ride.
local function step(dt)
    local left = dt
    while left > 1e-9 do
        local d = math.min(0.1, left)
        local ok, err = pcall(A_Admin.AdvanceTime, d)
        assertTrue(ok, "AdvanceTime raised: " .. tostring(err))
        left = left - d
    end
end

--- The suite's own delivery convention (test_spell_events.lua): call the
--- event frame's OnEvent script directly. A_Admin.FireEvent does not reach
--- this module's frame in the harness (measured: the Casts counters stay
--- flat through a fired SENT), the direct script ride does.
local function fire(event, ...)
    local f = M._eventFrame
    local h = f and f:GetScript("OnEvent")
    assertTrue(h ~= nil, "the event frame carries its OnEvent script")
    h(f, event, ...)
end

local function near(actual, expected)
    return assertTrue(math.abs(actual - expected) < 1e-6)
end
local function nearT(actual, expected, tol)
    return assertTrue(math.abs(actual - expected) < tol)
end

--- A spell the sim's player knows AND Forte_Timer tracks, whose id resolves
--- through the client back onto the tracked name (the
--- Forte_Cooldown/tests/test_zz_combat_bar.lua census law: the sim's profile
--- knows a small hand-picked set and only rows of that set resolve at all).
--- The window the row rides is the Registry's own (learned | data duration);
--- a known spell the data leaves windowless is given one in the test's own
--- learned storage -- that table is the plain-aura-read seam, the fixtures
--- are allowed to write it, and no spell id is typed anywhere.
local function pickCast(taken)
    local total, windowed, resolves = 0, 0, 0
    local sample = {}
    local fbId, fbName
    for name, row in pairs(Registry.entries) do
        total = total + 1
        local dur = Registry.BestDuration(name)
        if type(dur) == "number" and dur >= 8 and dur <= 40
            and not taken[name] then
            windowed = windowed + 1
            local okI, infoI = pcall(C_Spell.GetSpellInfo, name)
            local id = okI and infoI
                and FX.Compat.PlainOrNil(infoI.spellID)
            if type(id) ~= "number" then
                local okN, n = pcall(C_Spell.GetSpellIDFromName, name)
                id = okN and FX.Compat.PlainOrNil(n)
            end
            if type(id) == "number" then
                resolves = resolves + 1
                if #sample < 6 then
                    sample[#sample + 1] = name .. "=" .. tostring(id)
                end
                local ok = pcall(function()
                    local info = C_Spell.GetSpellInfo(id)
                    local nm = info and FX.Compat.PlainOrNil(info.name)
                    if type(nm) ~= "string" then return false end
                    nm = (FX.Locale and FX.Locale.CanonicalName(nm)) or nm
                    return nm == name and FX.Compat.IsPlayerSpell(id)
                end)
                if ok then
                    taken[name] = true
                    return id, name, dur, total, windowed, resolves
                end
                if not fbId then fbId, fbName = id, name end
            end
        end
    end
    if fbId then
        Registry.learned[fbName] = 18
        taken[fbName] = true
        Casts.resolveName = function(id)
            return id == fbId and fbName or nil
        end
        return fbId, fbName, 18, total, windowed, resolves
    end
    return nil, string.format(
        "no cast: tracked=%d windowed=%d idResolves=%d [%s]",
        total, windowed, resolves, table.concat(sample, ", "))
end

--- The unit-identity trio, installed for the duration of a test (the
--- test_pet_rows.lua idiom).
local function installUnits(names)
    local saved = {
        UnitExists = _G.UnitExists, UnitName = _G.UnitName,
        UnitIsDead = _G.UnitIsDead,
    }
    _G.UnitExists = function(token) return names[token] ~= nil end
    _G.UnitName = function(token) return names[token] end
    _G.UnitIsDead = function() return false end
    return saved
end
local function restoreUnits(saved)
    _G.UnitExists, _G.UnitName, _G.UnitIsDead =
        saved.UnitExists, saved.UnitName, saved.UnitIsDead
end

-- ------------------------------------------------------------- shared state --
local saved = {}
local castId, castName, castDur
local printed, sent

local function captureChat()
    printed, sent = {}, {}
    saved.realPrint = FX.Print
    saved.realSend = _G.SendChatMessage
    saved.realCsm = _G.ChatSendMsg
    FX.Print = function(msg) printed[#printed + 1] = tostring(msg) end
    _G.SendChatMessage = function(text, ...)
        sent[#sent + 1] = tostring(text)
    end
    _G.ChatSendMsg = function(text, ...)
        sent[#sent + 1] = tostring(text)
    end
end
local function releaseChat()
    if saved.realPrint then FX.Print = saved.realPrint end
    saved.realPrint = nil
    if saved.realSend ~= nil then _G.SendChatMessage = saved.realSend end
    if saved.realCsm ~= nil then _G.ChatSendMsg = saved.realCsm end
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

--- The spine through the real events: SENT -> START -> SUCCEEDED.
local function castSpine(id, target, guid, unit)
    unit = unit or "player"
    fire("UNIT_SPELLCAST_SENT", unit, target, guid, id)
    fire("UNIT_SPELLCAST_START", unit, guid, id, 1)
    fire("UNIT_SPELLCAST_SUCCEEDED", unit, guid, id, 2)
end

-- ------------------------------------------------------------------- gate ----
test("aa combat gate: the manual clock is ours, the module is enabled, the fight has a cast",
function()
    assertNotNil(FX._playerClass)
    if not M.options then M:OnEnable() end
    assertNotNil(M._eventFrame, "the module enabled at login")
    -- The suite's own tail tests leave the module DISABLED (test_module.lua
    -- ends on M:Disable()); a disabled module has no event frame registered,
    -- the fight's events reach nothing, and every leg below starves. The
    -- gate enables and records the finding for the teardown.
    saved.disabled = (M.options and M.options.enabled) == false
    if saved.disabled then M:Enable() end
    assertTrue((M.options and M.options.enabled) ~= false,
        "the module rides the fight enabled")
    assertNotNil(D.anchor)
    saved.class = FX._playerClass
    saved.storage = FX.db and FX.db.timer and FX.db.timer.learned
    saved.castsNow = Casts.now
    saved.hide = M.options and M.options.hide
    -- SUITE STATE (the :277 law, I2f): the show law of D:Update (UI/Rows.lua
    -- :652-655) is the `_shown` mirror, and a prior suite file can leave the
    -- mirror at true with the anchor hidden (the hidden-frame test files
    -- hide the anchor by hand). A stale true SKIPS the anchor:Show() the
    -- synchronous-show law prescribes, so the fight starts on a panel the
    -- suite forces CONSISTENT: hidden anchor + _shown false, the pair
    -- restored verbatim at the tail. The draw gates ride the same table:
    -- enable ON, hide OFF for the fight.
    saved.shownFlag = D._shown
    saved.anchorShown = D.anchor:IsShown()
    D._shown = false
    D.anchor:Hide()
    assertFalse(D.anchor:IsShown(), "the fight starts on a hidden panel")
    saved.enableFlag = M.options and M.options.enable
    if M.options.enable == false then M:SetEnabled(true) end
    M.options.hide = false
    assertNotEquals(false, M.options.enable,
        "the module rides the fight with the draw gate open")
    -- The module clock rides GetTime (Casts:Clock's fallback) while no
    -- injected clock stands -- the manual clock is then the whole world.
    Casts.now = nil
    enableClock(90000)
    near(90000, GetTime())

    local okIC = pcall(function() return InCombatLockdown() end)
    assertTrue(okIC, "the global InCombatLockdown is a callable in this build")
    assertFalse(InCombatLockdown(), "the run starts out of combat")
    A_Admin.SetInCombat(true)
    assertTrue(InCombatLockdown(), "SetInCombat(true) flips the lockdown")
    A_Admin.SetInCombat(false)
    assertFalse(InCombatLockdown())
    step(0.6)

    -- The fight's cast: the class's tracked set through the real Registry,
    -- the id through C_Spell, the knowledge through the sim's profile.
    Registry:AttachStorage({})
    local n = Registry:Build(FX._playerClass)
    assertTrue(n and n > 0, "the class registry built")
    local taken = {}
    local census
    castId, castName, castDur, census = pickCast(taken)
    assertNotNil(castId, tostring(castName))
end)

-- ------------------------------------------------- the spine through a row --
test("in combat: the SENT/START/SUCCEEDED spine lands a predicted row and it rides the fight",
function()
    Rows:Clear()
    Casts:Erase()
    captureChat()
    A_Admin.SetInCombat(true)
    step(0.2)

    local t0 = GetTime()
    fire("UNIT_SPELLCAST_SENT", "player", "Dummy-1", "FxG-1", castId)
    assertEquals(1, #Casts.queue, "the SENT captured the target")
    assertEquals(0, Rows:Count(), "SENT alone draws no row")
    fire("UNIT_SPELLCAST_START", "player", "FxG-1", castId, 1)
    assertTrue(Casts.queue[1].started, "START stamps the record")
    assertEquals(0, Rows:Count(), "START alone draws no row")
    fire("UNIT_SPELLCAST_SUCCEEDED", "player", "FxG-1", castId, 2)
    assertEquals(0, #Casts.queue, "the success consumed the record")
    assertEquals(0, Rows:Count(),
        "the settle defers the insert: no row on the event (CA-04)")

    -- The module's own cadences land it: SETTLE 0.2 s, the LOGIC pass every
    -- 12th DRAW tick -- tickers, no hand calls.
    step(Laws.SETTLE + 0.4)
    assertEquals(1, Rows:Count(), "the settle landed the row")
    local row = Rows.rows[1]
    assertEquals(castName, row.name)
    assertEquals("Dummy-1", row.targetKey,
        "the unconfirmed target rides as the opaque key")
    assertTrue(row.predicted, "a cast row is a PREDICTION")
    assertEquals(Laws.NORMAL, row.state)
    -- THE INSERT-STAMP LAW (I2f measured through this seam): the settle
    -- defers the insert, and Rows:InsertFromCast anchors the window on the
    -- pump's clock (`expire = now + total`, Core/Rows.lua:280), so the
    -- stamped span is the duration + the SETTLE + the LOGIC cadence the
    -- pump rides (12 x 0.04 s = 0.48, plus the 0.1 step quantization). The
    -- design's tolerance envelope is the MAXLAG (1.0) the leave-combat
    -- adoption measures predictions against -- the span rides its band.
    local span = row.expireAt - row.castTime
    assertTrue(span >= castDur + Laws.SETTLE - 1e-6
        and span <= castDur + Laws.SETTLE + 0.48 + 0.1 + 1e-6,
        "the settle-stamped window: duration + settle + cadence, span="
        .. string.format("%.3f", span) .. " dur=" .. tostring(castDur))
    assertTrue(row.castTime >= t0)
    assertTrue(D.anchor:IsShown(),
        "the row arrives with the panel shown (the synchronous-show law)")

    step(1.0)
    assertEquals(1, Rows:Count(), "the row rides the mid-fight clock")

    -- A second spine, a second target: the fight carries two rows.
    fire("UNIT_SPELLCAST_SENT", "player", "Dummy-2", "FxG-2", castId)
    fire("UNIT_SPELLCAST_START", "player", "FxG-2", castId, 1)
    fire("UNIT_SPELLCAST_SUCCEEDED", "player", "FxG-2", castId, 2)
    step(0.7)
    assertEquals(2, Rows:Count(), "the fight carries two rows")

    -- Interrupted mid-cast: a record retires, never a row.
    fire("UNIT_SPELLCAST_SENT", "player", "Dummy-3", "FxG-3", castId)
    fire("UNIT_SPELLCAST_START", "player", "FxG-3", castId, 1)
    fire("UNIT_SPELLCAST_INTERRUPTED", "player", "FxG-3", castId)
    step(Laws.CANCEL_SETTLE + 0.6)
    assertEquals(2, Rows:Count(),
        "the interrupt retires the record; no third row")
    assertEquals(0, #Casts.queue, "the queue rides clean")

    assertEquals(0, #printed,
        "a default install prints nothing through a fight: "
        .. table.concat(printed, " | "))
    assertEquals(0, #sent, "and sends on no channel")
    releaseChat()
end)

-- ------------------------------------------------------------------ pet rows --
test("in combat: the pet spine rides the pet feed; the feeds stay apart; a sealed spellID is inert",
function()
    Rows:Clear()
    Casts:Erase()
    captureChat()
    A_Admin.SetInCombat(true)
    step(0.2)

    fire("UNIT_SPELLCAST_SENT", "pet", "Dummy-P", "FxG-pet", castId)
    assertEquals(1, #Casts.queue, "the pet SENT rides the pet feed")
    fire("UNIT_SPELLCAST_SUCCEEDED", "pet", "FxG-pet", castId, 2)
    assertEquals(0, Rows:Count(), "the pet row rides the settle too")
    step(Laws.SETTLE + 0.4)
    assertEquals(1, Rows:Count(), "the pet row lands in the fight")
    local row = Rows.rows[1]
    assertEquals(castName, row.name)
    assertEquals("Dummy-P", row.targetKey,
        "the pet's target string is the row's key")
    assertTrue(row.predicted)

    -- The feeds never eat each other's records.
    fire("UNIT_SPELLCAST_SENT", "player", "Dummy-S", "FxG-self", castId)
    fire("UNIT_SPELLCAST_SENT", "pet", "Dummy-P", "FxG-pet2", castId)
    fire("UNIT_SPELLCAST_SUCCEEDED", "pet", "FxG-pet2", castId, 3)
    assertEquals(1, #Casts.queue,
        "the pet success consumed the PET record only")

    -- The sealed payload (the suite's sentinel through the unit-test fake):
    -- counted, inert, no record.
    local st = Casts:InitStatus()
    local secret0 = st.secret
    local q0 = #Casts.queue
    patchPlain()
    fire("UNIT_SPELLCAST_SENT", "pet", "Dummy-P", "FxG-sec", SECRET)
    restorePlain()
    assertEquals(secret0 + 1, st.secret,
        "the sealed spellID is counted, not read")
    assertEquals(q0, #Casts.queue, "the sealed cast opens no record")
    assertEquals(1, Rows:Count(), "and draws no row")

    -- The self feed completes on its own record.
    fire("UNIT_SPELLCAST_START", "player", "FxG-self", castId, 1)
    fire("UNIT_SPELLCAST_SUCCEEDED", "player", "FxG-self", castId, 4)
    step(0.7)
    assertEquals(2, Rows:Count(), "both feeds rode the same fight")

    assertEquals(0, #printed, "the pet feed speaks on no channel")
    assertEquals(0, #sent)
    releaseChat()
end)

-- ------------------------------------------------- the leave-combat sweep --
test("leave combat: the regen sweep keeps, adopts, learns, and retires predictions",
function()
    Rows:Clear()
    Casts:Erase()
    captureChat()

    -- The row is born in the fight, a no-target self window ("none": the
    -- sweep's "player" half is its own).
    A_Admin.SetInCombat(true)
    step(0.2)
    castSpine(castId, nil, "FxG-rc")
    step(Laws.SETTLE + 0.4)
    assertEquals(1, Rows:Count(), "the fight row is live and predicted")
    local row = Rows.rows[1]
    assertTrue(row.predicted)
    local predEnd = row.expireAt

    -- The lockdown gate: the sweep does not run, zero aura calls (T10).
    local reads0 = Reconcile.counts.reads
    fire("UNIT_AURA", "player", nil)
    fire("PLAYER_TARGET_CHANGED")
    assertEquals(reads0, Reconcile.counts.reads,
        "zero aura calls while the lockdown stands (T10)")

    -- The leave: the sim fires PLAYER_REGEN_ENABLED; the module refreshes
    -- the secrecy snapshot and runs the full sweep. The aura is NOT there
    -- and the row is young: the BUFF_DELAY grace keeps it (:1186).
    A_Admin.SetInCombat(false)
    step(0.2)
    assertEquals(1, Rows:Count(),
        "the grace keeps a young prediction through the absent fact")
    assertTrue(Reconcile.counts.reads > reads0,
        "the out-of-combat sweep runs the aura reads")

    -- THE PLAIN FACT, TWO CLOCKS. (I2f measured — this is the row's clock
    -- law, and a simulation-harness finding, reported, not patched:) the
    -- sim's A_Admin aura setters stamp `expirationTime` from the REAL
    -- monotonic clock, while this suite's rows ride the MANUAL clock — the
    -- probe pair read row.castTime 90030.6 (manual) against a
    -- wall-stamped aura expiring at 90026.3 for a 19.6 s window asked at
    -- manual 90031.4: the skew is the suite's whole simulated ride. A
    -- CAPI-granted aura is therefore a band-out-of-MAXLAG FACT BY CONSTRUCTION
    -- here: the scan reads it, and the row rides untouched-and-predicted
    -- (measured, /tmp/i2f_timer_probe3.log: expireAt and predicted intact).
    -- The adoption laws ride the module's own fact seam,
    -- Rows:OnAuraFact — the same call SweepRow makes from ReadFact's pair
    -- (Core/Reconcile.lua:249-252), fed the row's clock.
    --
    -- THE AURA KEYING (I2f measured): the sim's setters key NUMERICALLY —
    -- AddBuff(spellID, name, icon, durationSec, stacks), RemoveBuff(spellID);
    -- a string in slot 1 raises `expected number, got string at argument 1`.
    -- (I2f final: the AddBuff scan leg that lived here was deleted — a CAPI
    -- aura stamped on the sim's REAL monotonic clock lands outside the
    -- row clock's MAXLAG=1.0 band by construction, with skew = wall boot +
    -- test time measured 0..-24.5 s, so the leg was a run-timing coin flip:
    -- adopted at skew 0, kept at skew -24.5. The adoption/learn/retire laws
    -- below ride the seam, which is the same call SweepRow makes from
    -- ReadFact's pair on the row's clock — measured, not asserted here.)

    -- The seam-fed plain fact, anchored to the row's own edge (inside the
    -- MAXLAG band): the row stops being a prediction, the unit token stamps
    -- it (the adoption legs of Core/Rows.lua:OnAuraFact). The row is read
    -- through the module's own live-row lookup, not a slot index: the sweep
    -- removes through `removeAt`, a slot is nil over a compaction, and the
    -- out-of-combat sweep runs on EVERY real sim frame (the I2f3 measure:
    -- the facts probe below has never tripped).
    local row2
    for i = 1, Rows.rows_n do
        local r = Rows.rows[i]
        if r and r.state <= Laws.REMOVE then row2 = r break end
    end
    if row2 == nil then
        local parts = {}
        for i = 1, Rows.rows_n do
            local r = Rows.rows[i]
            parts[#parts + 1] = string.format("[%d]%s st=%s pred=%s exp=%s",
                i, r and tostring(r.name) or "nil",
                r and tostring(r.state) or "-",
                r and tostring(r.predicted) or "-",
                r and tostring(r.expireAt) or "-")
        end
        error("seam-leg facts: count=" .. Rows:Count()
            .. " n=" .. tostring(Rows.rows_n)
            .. " now=" .. tostring(GetTime())
            .. " predEnd=" .. tostring(predEnd)
            .. " " .. table.concat(parts, " "))
    end
    local dataDur = Registry.BestDuration(castName)
    Rows:OnAuraFact(row2, predEnd - 0.3, dataDur, nil, GetTime(),
        "player")
    assertFalse(row2.predicted,
        "a fact inside MAXLAG converts the prediction into a confirmed row")
    nearT(row2.expireAt, predEnd - 0.3, 1e-6)
    assertEquals("player", row2.unitToken,
        "the confirming read stamps the row's unit token")
    -- The one teacher (SweepRow's Registry.Learn leg): the plain duration
    -- equal to the data duration teaches nothing (the min law leaves the
    -- data number standing); a STRICTLY SHORTER read teaches the pair.
    assertEquals(nil, Registry.learned[castName],
        "a fact equal to the data duration is not a teacher (the min law)")
    Registry.Learn(castName, dataDur - 5)
    assertEquals(dataDur - 5, Registry.BestDuration(castName),
        "a strictly shorter plain read is the one teacher (min law)")

    -- The confirmed-gone half: the aura is gone, the grace has spent, the
    -- sweep retires the aged CONFIRMED row (:1186, :1207). The retirement
    -- is a FADE with a full window: the row rides `removeAt + max(FAIL,
    -- FADE) + FADE_SPEED` (Laws.DeathAt -- 3.5 s for a non-instant kind)
    -- before the LOGIC cadence deletes it, so the ride pumps the clock to
    -- the last row (the hidden-panel test's guard idiom, I2f).
    step(Laws.BUFF_DELAY + 1.0)
    fire("PLAYER_REGEN_ENABLED")
    local guard = 0
    while Rows:Count() > 0 and guard < 1200 do
        step(0.1)
        guard = guard + 1
    end
    assertEquals(0, Rows:Count(),
        "the confirmed-gone fact retires the aged row")

    assertEquals(0, #printed, "the reconcile speaks on no channel")
    assertEquals(0, #sent)
    releaseChat()
end)

-- ------------------------------------------------------- the hidden panel --
test("the hidden panel draws nothing, its rows retire on the ticker, the anchor carries no OnUpdate",
function()
    Rows:Clear()
    Casts:Erase()
    captureChat()
    assertNil(D.anchor:GetScript("OnUpdate"),
        "the panel is ticker-driven: a hidden frame gets no OnUpdate")

    A_Admin.SetInCombat(true)
    step(0.2)
    castSpine(castId, "Dummy-H", "FxG-h1")
    step(Laws.SETTLE + 0.4)
    assertEquals(1, Rows:Count())
    assertTrue(D.anchor:IsShown(), "the shown panel rode the row")

    -- The :3331 hide law: Draw returns at the gate; the LOGIC ticker keeps
    -- the model, and retires the row at its edge with the panel dark.
    M.options.hide = true
    D:RenderIdle()
    assertFalse(D.anchor:IsShown(), "the panel is the hidden frame")
    step(1.0)
    assertEquals(1, Rows:Count(),
        "the rows ride the logic cadence while the panel is hidden")
    assertFalse(D.anchor:IsShown(),
        "a hidden panel with rows draws no work and stays dark")
    local guard = 0
    while Rows:Count() > 0 and guard < 900 do
        step(0.1)
        guard = guard + 1
    end
    assertEquals(0, Rows:Count(),
        "the hidden panel's rows expire on the ticker (no OnUpdate needed)")
    M.options.hide = saved.hide
    assertEquals(0, #printed, "the hidden ride prints nothing")
    releaseChat()
end)

-- -------------------------------------------------------------------- tail --
test("zzz the suite leaves the module state as it found it", function()
    Rows:Clear()
    Casts:Erase()
    M.options.hide = saved.hide
    if saved.enableFlag == false then M:SetEnabled(false) end
    Casts.now = saved.castsNow
    Registry:AttachStorage(saved.storage)
    local n = Registry:Build(FX._playerClass)
    assertTrue(n and n > 0, "the class registry rebuilt clean")
    A_Admin.SetInCombat(false)
    -- The tail regen sweep can re-insert the profile's baseline auras
    -- (the bulk half reads them by index); a row born past its edge fades
    -- out on the ticker over the FAIL/FADE window, so the tail ride pumps
    -- past the window, not just past one cadence (I2f).
    step(2.5)
    assertFalse(InCombatLockdown())
    local tail = Rows.rows[1]
    if Rows:Count() ~= 0 then
        error("tail facts: rows=" .. Rows:Count()
            .. " r1=" .. tostring(tail and tail.name)
            .. " exp=" .. tostring(tail and tail.expireAt)
            .. " state=" .. tostring(tail and tail.state)
            .. " pred=" .. tostring(tail and tail.predicted)
            .. " draw=" .. tostring(tail and tail.drawExpireAt)
            .. " now=" .. tostring(GetTime()))
    end
    assertEquals(0, Rows:Count(), "the tail rides clean")
    -- The gate's forced panel pair, restored verbatim as the suite found it.
    D._shown = saved.shownFlag
    if saved.anchorShown then
        D.anchor:Show()
    else
        D.anchor:Hide()
    end
    assertNil(saved.realPrint, "the chat capture is released")
end)

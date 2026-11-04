-- =============================================================================
-- test_zz_combat_warlock.lua — the I2f combat-simulation round for the
-- warlock tools (PLAN §2.10, §11.2 row I2f).
--
-- NAME LAW: the "zz_" prefix sorts this file LAST; it is the only test in
-- the set that enables the admin manual clock (process-wide, enable-once —
-- the existing warlock tests inject their own clock closures and never
-- touch the shared one). The clock handback law rides at the tail.
--
-- WHAT THIS ROUND DRIVES. The event payloads ride the module's OWN
-- exported parts in the frame script's arrangement: `drive(event, ...)`
-- dispatches each event to the exact calls Core/Tools.lua's onToolEvent
-- makes (SENT 4 slots unit/target/guid/spellID, START/SUCCEEDED 3, the
-- stop family, BAG_UPDATE_DELAYED / ITEM_COUNT_CHANGED → ReadItems,
-- UNIT_POWER_UPDATE → the power-source probe, PLAYER_REGEN_ENABLED → the
-- out-of-combat pass), with the resolution legs running the module's
-- exported seams (`WK.CastKey`, `WK.ResolveTargetName` — the same
-- functions the script calls). Why not the live frame script (the
-- SIM-PROFILE LAWS, measured this round): the class-gated module rides
-- UNWIRED at the login (the suite runs on the default profile — the
-- baseline's class-gate tests, test_warlock.lua:656, are designed for it;
-- `--class Warlock` flips five of them RED, a harness fact reported), and
-- the simulator's script registry is a login-window phenomenon: a
-- SetScript after the login phase is inert (probe /tmp/fxprobe14.dt.log
-- C=false_nil). The trackers' seams are the calls the script makes.
--
-- SIM-PROFILE LAWS MEASURED AND RIDDEN (wow-ui-sim v0.1.39, default
-- profile; the warlock-id resolution facts probed on the warlock profile,
-- /tmp/fxprobe11.dt.log — the same nameless-row shape the paladin profile
-- measures for hunter ids, /tmp/fxprobe6.dt.log):
--   * C_Item.GetItemCount answers the PLAIN ZERO for a name the bags do
--     not carry — the shard/healthstone bag reads take it as truth,
--     source "bag" (a read, not a planted count).
--   * UnitPower("player", Enum.PowerType.SoulShards=7) answers 0 on a
--     warlock profile; A_Admin.SetPower RAISES (no fixture) — the source
--     chain rides the reads only.
--   * C_Spell.GetSpellInfo resolves the family ids to NAMELESS rows
--     (20757, 698) — castKey answers nil and the resolved cast path rides
--     inert (asserted; the trackers' own seams carry the family legs).
--   * The comms speak through SendChatMessage — captured, zero on the
--     default solo install. FX.Print captured — zero.
--   * The tracker counters ride RELATIVE: the baseline files move the
--     live trackers (the shared module state), so every count assert
--     anchors on the gate's reading (measured: the absolute asserts read
--     the baseline's casts, 5 where the suite added 2).
-- =============================================================================
local FX = ForteXorcist
local M = FX.Warlock.Tools
local WK = FX.Warlock

local saved
local printCapture
local sendCapture
local casts0, ends0, starts0

-- ------------------------------------------------------------------ helpers
local function step(dt)
    local left = dt
    while left > 1e-9 do
        local d = math.min(0.1, left)
        local ok, err = pcall(A_Admin.AdvanceTime, d)
        assertTrue(ok, "AdvanceTime raised: " .. tostring(err))
        left = left - d
    end
end

-- The dispatcher the module's frame script is, through the module's
-- exported parts (the header's laws): same payload slots, same
-- resolution legs, same tracker calls. (I2f3 fix: the resolve exports
-- ride FX.Warlock.Tools — M.CastKey / M.ResolveTargetName — not the
-- FX.Warlock namespace.)
local function drive(event, a1, a2, a3, a4)
    if event == "BAG_UPDATE_DELAYED" or event == "ITEM_COUNT_CHANGED" then
        M:ReadItems()
    elseif event == "UNIT_POWER_UPDATE" then
        M.Shards:Read(nil, "power")
    elseif event == "PLAYER_REGEN_ENABLED" then
        M:ReadItems()
        M.Shards:Read()
    elseif event == "UNIT_SPELLCAST_SENT" then
        local key = M.CastKey(a4)
        local target = M.ResolveTargetName(a2)
        if key then
            M.Soulstone:OnCastSent(key, target)
            M.Summon:OnCastSent(key, target)
        end
    elseif event == "UNIT_SPELLCAST_START"
        or event == "UNIT_SPELLCAST_CHANNEL_START" then
        local key = M.CastKey(a3)
        if key then M.Summon:OnCastStart(key) end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local key = M.CastKey(a3)
        if key then
            M.Soulstone:OnCast(key)
            M.Summon:End(key, "succeeded")
            if key:find("^Create ") then M:ReadItems() end
        end
    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED"
        or event == "UNIT_SPELLCAST_INTERRUPTED"
        or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        local key = M.CastKey(a3)
        if key then
            M.Summon:End(key,
                event == "UNIT_SPELLCAST_FAILED" and "failed" or "cancelled")
        end
    else
        error("drive: the round carries no law for " .. tostring(event))
    end
end

local clockEnabled = false
local function enableClock(target)
    assertTrue(type(GetTime) == "function"
        and type(A_Admin.AdvanceTime) == "function"
        and type(A_Admin.SetManualClock) == "function",
        "the sim build carries the manual clock trio")
    -- (I2f3 probe: A_Admin.GetManualClockEnabledAt does NOT exist on this
    -- build (nil — the hand-off fact was wrong), and SetManualClock is
    -- enable-once (a second call raises "manual clock already enabled").
    -- The shape rides the proven Forte_Timer gate: enable once, assert the
    -- clock answers the base. The zz file is the run's last, and the clock
    -- has no off switch — the Forte_Timer suite's tail law: it rides on.)
    if not clockEnabled then
        local ok, err = pcall(A_Admin.SetManualClock, target)
        assertTrue(ok, "SetManualClock(" .. tostring(target) .. ") raised: "
            .. tostring(err))
        clockEnabled = true
    end
    local okG, t0 = pcall(GetTime)
    assertTrue(okG, "GetTime raised under the manual clock: " .. tostring(t0))
    assertTrue(math.abs(t0 - target) < 0.01,
        "the clock answers its base: t=" .. tostring(t0))
end

-- ---------------------------------------------------------------------- gate
test("zz combat gate: the module stands on the manual clock, unwired",
function()
    assertNotNil(M, "FX.Warlock.Tools exists")
    assertNotNil(M.Shards, "the shard counter exists")
    assertNotNil(M.Soulstone, "the soulstone tracker exists")
    assertNotNil(M.Healthstone, "the healthstone tracker exists")
    assertNotNil(M.Summon, "the summon tracker exists")
    -- The class-gate law (header): the default-profile login leaves the
    -- warlock module's frame unwired, and a late-opened frame carries an
    -- inert script — the dispatch rides the module's exported parts.
    assertNil(M._eventFrame,
        "the login left the class-gated module's frame unwired")
    assertTrue(M._eventsEnabled ~= true,
        "the module's events mirror rides off (the class-gate law)")
    printCapture = { lines = 0 }
    saved = {}
    saved.print = FX.Print
    FX.Print = function(...)
        printCapture.lines = printCapture.lines + 1
        print(...)
    end
    sendCapture = { lines = 0 }
    saved.send = _G.SendChatMessage
    _G.SendChatMessage = function(...)
        sendCapture.lines = sendCapture.lines + 1
    end
    enableClock(150000)
    -- (I2f3 measured on the hunter run: the lockdown surface is the GLOBAL
    -- InCombatLockdown() answering a plain bool — there is no
    -- FX.InCombatLockdown and no lockdown object on this build.)
    local okL, locked = pcall(InCombatLockdown)
    assertTrue(okL and FX.Compat.PlainOrNil(locked) == false,
        "the gate rides out of combat: InCombatLockdown answers plain false")
    assertTrue(#WK.soulstoneNames > 0, "the soulstone family has data names")
    assertTrue(#WK.summonNames > 0, "the summon family has data names")
    assertTrue(#WK.healthstoneNames > 0,
        "the healthstone item family has data names")
    -- Shared-module-state anchors (the baseline files rode first).
    casts0 = M.Soulstone.casts
    ends0, starts0 = M.Summon.ends, M.Summon.starts
    M.Soulstone:Clear()
    M.Summon:Stop("gate")
    M.Summon.channeling, M.Summon.last = false, nil
    -- (I2f3 measured: the baseline files leave INJECTED `now` closures on
    -- the live trackers (the stone stamped start=900000 while the manual
    -- clock rode 150000). The round rides the manual clock: claim the
    -- closures, restore the found state verbatim at zzz.)
    saved.ssNow, saved.snNow, saved.hsnNow =
        M.Soulstone.now, M.Summon.now, M.Healthstone.now
    M.Soulstone.now, M.Summon.now, M.Healthstone.now = nil, nil, nil
end)

test("in combat: the shard sources answer live, first-answer-wins", function()
    A_Admin.SetInCombat(true)
    step(0.2)
    drive("ITEM_COUNT_CHANGED")
    local count, source = M.Shards:Count()
    assertEquals(0, count,
        "C_Item.GetItemCount answers the plain zero for the absent shard "
        .. "bag item — a read, not a planted count")
    assertEquals("bag", source, "the bag source answers first")
    drive("UNIT_POWER_UPDATE", "player", 7)
    count, source = M.Shards:Count()
    assertTrue(source == "power" or source == "bag",
        "the UNIT_POWER_UPDATE half probes the power source alone; the "
        .. "source of record rides " .. tostring(source))
    assertEquals(0, count, "the profile's SoulShards power reads zero")
    drive("BAG_UPDATE_DELAYED")
    assertEquals("bag", select(2, M.Shards:Count()),
        "the bag events probe the bag source alone")
    drive("PLAYER_REGEN_ENABLED")
    assertNotNil(select(1, M.Shards:Count()),
        "the out-of-combat pass reads the sources in order")
end)

test("the soulstone window: adopted, replaced, ready after the expiry",
function()
    local name = WK.soulstoneNames[1]
    local duration = WK.DeriveSoulstoneSeconds()
    assertNotNil(duration,
        "the generated data (or the predicted 1800 s) sets the window")
    local now0 = GetTime()
    assertEquals(true, M.Soulstone:OnCastSent(name, "Probe Dummy"),
        "the family SENT claims the target (CA-12 channel-like law)")
    assertEquals("Probe Dummy", M.Soulstone.pending,
        "the target rides the pending record until the success")
    assertEquals(true, M.Soulstone:OnCast(name))
    assertEquals(true, M.Soulstone:Active(), "the stone is live")
    assertEquals("Probe Dummy", M.Soulstone:Target(),
        "the SENT target rode the window")
    local rem = M.Soulstone:Remaining()
    assertTrue(rem ~= nil and rem > duration - 1.0 and rem <= duration,
        "the window rides the data length off the clock")
    M.Soulstone:OnCastSent(name, "Probe Dummy 2")
    M.Soulstone:OnCast(name)
    assertEquals("Probe Dummy 2", M.Soulstone:Target(),
        "the newer stone replaces the tracked one")
    assertEquals(casts0 + 2, M.Soulstone.casts,
        "the two adopted casts rode the counter (relative to the gate)")
    local gone = M.Soulstone:Active(now0 + duration + 0.1)
    local live = M.Soulstone:Active()
    if gone ~= false or live ~= false then
        error("stone facts: gone=" .. tostring(gone) .. " live=" .. tostring(live)
            .. " active=" .. tostring(M.Soulstone.active)
            .. " dur=" .. tostring(M.Soulstone.duration)
            .. " start=" .. tostring(M.Soulstone.start)
            .. " now0=" .. tostring(now0) .. " now=" .. tostring(GetTime())
            .. " ready=" .. tostring(M.Soulstone:Ready()))
    end
    assertEquals(false, gone,
        "the observed end retires the window (no ticker needed)")
    assertEquals(false, M.Soulstone:Active(), "and the row is gone live")
    assertEquals(true, M.Soulstone:Ready(),
        "a window that ran out opens the ready-to-res window")
    assertNil(M.Soulstone:Remaining(), "no window, no remaining")
    M.Soulstone:Clear()
end)

test("the ritual channel: claimed by SENT, ended, self-expiring", function()
    local name = WK.summonNames[1]
    local channel = WK.DeriveSummonChannelSeconds()
    assertNotNil(channel,
        "the generated castMs of the ritual sets the channel (5 s)")
    assertEquals(true, M.Summon:OnCastSent(name, "Probe Dummy"),
        "the SENT begins the predicted channel and claims the target")
    assertEquals(true, M.Summon:Channeling(), "the channel rides")
    local fraction, remaining = M.Summon:Progress()
    assertNotNil(fraction, "the channel reports its progress")
    assertTrue(fraction >= 0 and fraction < 0.5
        and remaining > 0 and remaining <= channel,
        "just opened: the fraction rides the channel's head")
    assertEquals("Probe Dummy", M.Summon.target)
    assertEquals(true, M.Summon:End(name, "succeeded"))
    assertFalse(M.Summon:Channeling(), "the success ends the channel")
    assertEquals(ends0 + 1, M.Summon.ends,
        "the end counter rode (relative to the gate)")
    assertEquals("succeeded", M.Summon.last.outcome,
        "the outcome rides the last record")
    M.Summon:OnCastStart(name)
    assertEquals(true, M.Summon:Channeling(GetTime() + channel - 0.2),
        "inside the window the channel rides")
    assertEquals(false, M.Summon:Channeling(GetTime() + channel + 0.2),
        "past the window the prediction self-expires")
    assertEquals("expired", M.Summon.last.outcome,
        "the self-expiry records itself")
end)

test("the healthstone reads answer the profile's plain facts", function()
    local ok, err = pcall(M.ReadItems, M)
    assertTrue(ok, "the bag pass runs clean on this build: "
        .. tostring(err))
    local okC, count, present = pcall(function()
        return (M.Healthstone:Count())
    end)
    if not okC then
        error("hs facts: Count raised: " .. tostring(count))
    end
    count = M.Healthstone:Count()
    present = select(2, M.Healthstone:Count())
    assertEquals(0, count,
        "the stone family reads zero on the empty bags (the name-keyed "
        .. "C_Item.GetItemCount leg)")
    assertEquals(false, present, "the panel says: no stone")
    local ok2, verdict, v2 = pcall(M.Healthstone.ReadCooldown, M.Healthstone)
    assertTrue(ok2, "the cooldown pass runs clean: " .. tostring(verdict))
    assertTrue(verdict == nil or verdict == "cleared" or verdict == "secret",
        "the zero-filled cooldown read is the ready answer, not an anchor")
    local okR, rem = pcall(function()
        return M.Healthstone:CooldownRemaining()
    end)
    if not okR then
        error("hs facts: CooldownRemaining raised: " .. tostring(rem)
            .. " cdStart=" .. tostring(M.Healthstone.cdStart)
            .. " cdDuration=" .. tostring(M.Healthstone.cdDuration))
    end
    assertNil(rem, "no anchored cooldown, no countdown")
end)

test("the resolved cast path rides inert when rows resolve nameless",
function()
    -- The measured profile law: C_Spell.GetSpellInfo resolves the family
    -- ids to NAMELESS rows, so WK.CastKey answers nil at the seam and the
    -- dispatcher's tracker legs ride shut.
    local stoneId, ritualId
    for id, row in pairs(FX.Data.Warlock) do
        if type(row) == "table" then
            if row.name == "Create Soulstone" then stoneId = id end
            if row.name == "Ritual of Summoning" then ritualId = id end
        end
    end
    assertNotNil(stoneId, "the data carries Create Soulstone")
    assertNil(M.CastKey(stoneId),
        "the profile resolves the family id to no usable name")
    local castsA, startsA = M.Soulstone.casts, M.Summon.starts
    drive("UNIT_SPELLCAST_SENT", "player", "Probe Dummy", "FxW-1", stoneId)
    drive("UNIT_SPELLCAST_START", "player", "FxW-1", stoneId, 1)
    drive("UNIT_SPELLCAST_SUCCEEDED", "player", "FxW-1", stoneId, 2)
    drive("UNIT_SPELLCAST_SENT", "player", "Probe Dummy", "FxW-2", ritualId)
    drive("UNIT_SPELLCAST_CHANNEL_STOP", "player", "FxW-2", ritualId, nil, 1)
    assertEquals(castsA, M.Soulstone.casts,
        "the nameless resolution adopted no soulstone window")
    assertEquals(startsA, M.Summon.starts,
        "and opened no ritual channel")
    assertFalse(M.Soulstone:Active())
    assertFalse(M.Summon:Channeling())
end)

test("the comms speak on no channel and the round prints nothing", function()
    local ok
    if M.Comms then
        ok = pcall(M.Comms.AnnounceState, M.Comms)
    else
        ok = true -- the transport rides behind the class gate: nothing to say
    end
    assertTrue(ok, "the announce pass runs clean on this build")
    assertEquals(0, sendCapture.lines,
        "the default install with no group sent nothing ("
        .. tostring(sendCapture.lines) .. " sends)")
    assertEquals(0, printCapture.lines,
        "the round printed nothing (" .. tostring(printCapture.lines)
        .. " lines)")
end)

test("zzz the suite leaves the module state as it found it", function()
    A_Admin.SetInCombat(false)
    step(0.2)
    M.Soulstone:Clear()
    M.Summon:Stop("suite-end")
    M.Summon.channeling, M.Summon.start, M.Summon.duration = false, nil, nil
    M.Summon.name, M.Summon.target, M.Summon.last = nil, nil, nil
    M.Shards.count, M.Shards.source = nil, nil
    M.Healthstone.count, M.Healthstone.present = nil, nil
    M.Healthstone.cdStart, M.Healthstone.cdDuration = nil, nil
    M.Soulstone.now, M.Summon.now, M.Healthstone.now =
        saved.ssNow, saved.snNow, saved.hsnNow
    assertFalse(M.Soulstone:Active(), "the stone state is clean")
    assertFalse(M.Summon:Channeling(), "the channel is clean")
    assertNil(select(1, M.Shards:Count()), "the shard read rides unknown")
    _G.SendChatMessage = saved.send
    FX.Print = saved.print
    -- (I2f3: the handback math rode GetManualClockEnabledAt — the surface
    -- does not exist, SetManualClock is enable-once with no off switch,
    -- and this file is the run's last: the Forte_Timer tail law, the
    -- clock rides on.)
    assertNil(M._eventFrame, "the suite left no frame (the law state)")
    assertTrue(M._eventsEnabled ~= true,
        "the module's events mirror rides off")
end)

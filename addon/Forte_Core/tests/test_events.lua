-- addon/Forte_Core/tests/test_events.lua
-- The FX.On / FX.Off / FX.Fire bus (Core/Events.lua): registration order,
-- pcall isolation (a raising listener is reported and skipped -- the firer
-- breaks for NONE of it), Off semantics (exact handle, idempotent, unknown
-- handle false), the Fire-time snapshot (an Off from inside a listener does
-- not touch the running dispatch), and the contract's payload shape for
-- FX_COOLDOWN_READY / FX_TIMER_EXPIRED.

local FX = ForteXorcist

test("FX.On returns a handle and FX.Fire runs the listener once", function()
    local hits = 0
    local h = FX.On("FXTEST_PING", function() hits = hits + 1 end)
    assertNotNil(h, "On hands back a handle")
    local ran = FX.Fire("FXTEST_PING")
    assertEquals(1, hits)
    assertEquals(1, ran, "Fire reports how many listeners ran")
    FX.Off(h)
    assertEquals(0, FX.ListenerCount("FXTEST_PING"))
end)

test("dispatch order is registration order", function()
    local order = {}
    local hs = {}
    for i = 1, 4 do
        hs[i] = FX.On("FXTEST_ORDER", function() order[#order + 1] = i end)
    end
    FX.Fire("FXTEST_ORDER")
    assertEquals(4, #order)
    for i = 1, 4 do assertEquals(i, order[i]) end
    for i = 1, 4 do FX.Off(hs[i]) end
end)

test("a raising listener is isolated: the firer sees no error, peers all run",
function()
    local before, after = 0, 0
    local hBad = FX.On("FXTEST_RAISE", function()
        error("FXTEST-BOOM", 0)
    end)
    local h1 = FX.On("FXTEST_RAISE", function() before = before + 1 end)
    local h2 = FX.On("FXTEST_RAISE", function() after = after + 1 end)
    -- Report the failure through FX.Print (the bus's channel), not the test.
    local printed, realPrint = {}, FX.Print
    FX.Print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end
    local ok, ran = pcall(FX.Fire, "FXTEST_RAISE")
    FX.Print = realPrint
    assertTrue(ok, "a listener error never propagates to the firer")
    assertEquals(3, ran, "all three listeners were attempted")
    assertEquals(1, before)
    assertEquals(1, after)
    local joined = table.concat(printed, "\n")
    assertTrue(joined:find("FXTEST_RAISE", 1, true) ~= nil,
        "the failure is reported on the event name")
    FX.Off(hBad); FX.Off(h1); FX.Off(h2)
end)

test("FX.Off removes exactly the handle, is idempotent, answers unknowns",
function()
    local hits = 0
    local h = FX.On("FXTEST_OFF", function() hits = hits + 1 end)
    assertEquals(true, FX.Off(h), "first Off reports the removal")
    FX.Fire("FXTEST_OFF")
    assertEquals(0, hits)
    assertEquals(false, FX.Off(h), "a second Off is a no-op that says so")
    assertEquals(false, FX.Off({ id = 424441, event = "FXTEST_OFF" }),
        "an unknown handle is refused")
    assertEquals(false, FX.Off(nil))
    assertEquals(false, FX.Off("nonsense"))
end)

test("Fire snapshots the listener list: an Off inside a listener does not "
.. "skip peers of the running fire", function()
    local hits = {}
    local h2, h3
    local h1 = FX.On("FXTEST_SNAP", function()
        hits[1] = (hits[1] or 0) + 1
        FX.Off(h2)   -- remove the NEXT peer mid-dispatch
    end)
    h2 = FX.On("FXTEST_SNAP", function() hits[2] = (hits[2] or 0) + 1 end)
    h3 = FX.On("FXTEST_SNAP", function() hits[3] = (hits[3] or 0) + 1 end)
    FX.Fire("FXTEST_SNAP")
    assertEquals(1, hits[1])
    assertEquals(1, hits[2], "the removed peer still completes THIS fire")
    assertEquals(1, hits[3])
    FX.Fire("FXTEST_SNAP")
    assertEquals(1, hits[2], "and is gone from the next one")
    assertEquals(2, hits[1]); assertEquals(2, hits[3])
    FX.Off(h1); FX.Off(h3)
end)

test("Fire passes the payload verbatim; an event with no listeners is quiet",
function()
    local seen
    local h = FX.On("FXTEST_ARGS", function(a, b, c, d)
        seen = { a, b, c, d }
    end)
    FX.Fire("FXTEST_ARGS", "Rapid Fire", 1234.5, "Interface\\x", "Spell")
    assertEquals("Rapid Fire", seen[1])
    assertEquals(1234.5, seen[2])
    assertEquals("Interface\\x", seen[3])
    assertEquals("Spell", seen[4])
    FX.Off(h)
    assertEquals(0, FX.Fire("FXTEST_NOBODY"), "zero listeners, zero fuss")
end)

test("On refuses bad calls without touching the bus", function()
    assertNil(FX.On(nil, print))
    assertNil(FX.On("FXTEST_BAD", nil))
    assertNil(FX.On(42, function() end))
    assertEquals(0, FX.ListenerCount("FXTEST_BAD"))
end)

test("the contract names are the wire strings, and the contract is exactly "
.. "those six (E6: no SPLASH seam)", function()
    assertEquals("FX_COOLDOWN_READY", FX.EVENTS.COOLDOWN_READY)
    assertEquals("FX_TIMER_EXPIRED", FX.EVENTS.TIMER_EXPIRED)
    assertEquals("FX_TIMER_FADING", FX.EVENTS.TIMER_FADING)
    assertEquals("FX_TIMER_BROKEN", FX.EVENTS.TIMER_BROKEN)
    -- The soulstone pair (Wave 4, Options WL+Msg item 1): producer
    -- Forte_Warlock/Core/Tools.lua's tracker, listeners Forte_Messages'
    -- Sound rows and the Soulstone plate's Ready-look gate.
    assertEquals("FX_SOULSTONE_EXPIRED", FX.EVENTS.SOULSTONE_EXPIRED)
    assertEquals("FX_SOULSTONE_READY", FX.EVENTS.SOULSTONE_READY)
    assertNil(FX.EVENTS.SPLASH,
        "E6: the SplashKick seam is gone -- every declared event has a"
        .. " production producer and a production listener")
    local declared = 0
    for _ in pairs(FX.EVENTS) do declared = declared + 1 end
    assertEquals(6, declared)
end)

test("a ready-event round trip: the payload contract reaches the listener",
function()
    local got
    local h = FX.On(FX.EVENTS.COOLDOWN_READY,
        function(name, now, texPath, category)
            got = { name, now, texPath, category }
        end)
    FX.Fire(FX.EVENTS.COOLDOWN_READY, "Rapid Fire", 99.5, "Interface\\a", "Spell")
    FX.Off(h)
    assertNotNil(got)
    assertEquals("Rapid Fire", got[1])
    assertEquals(99.5, got[2])
    assertEquals("Interface\\a", got[3])
    assertEquals("Spell", got[4])
end)

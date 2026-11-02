-- Compat.PlainOrNil: the guard every secret-value read passes through.
local FX = ForteXorcist
local C = FX.Compat

test("PlainOrNil passes plain values and nil through", function()
    assertEquals(5, C.PlainOrNil(5))
    assertEquals("x", C.PlainOrNil("x"))
    assertEquals(false, C.PlainOrNil(false))
    assertNil(C.PlainOrNil(nil))
end)

test("PlainOrNil returns nil for a value issecretvalue flags", function()
    local real = _G.issecretvalue
    _G.issecretvalue = function(v) return v == "SECRET-SENTINEL" end
    local got = C.PlainOrNil("SECRET-SENTINEL")
    local plain = C.PlainOrNil(7)
    _G.issecretvalue = real
    assertNil(got)
    assertEquals(7, plain)
end)

-- CodeReview2 n5: callers of PlainOrNil run outside any pcall, so a raising
-- issecretvalue must not escape; it fails CLOSED (nil = unusable).
test("PlainOrNil fails closed when issecretvalue raises", function()
    local real = _G.issecretvalue
    _G.issecretvalue = function() error("FXTEST-ISS-RAISE", 0) end
    local ok, got = pcall(C.PlainOrNil, 42)
    _G.issecretvalue = real
    assertTrue(ok, "PlainOrNil must not raise")
    assertNil(got)
end)

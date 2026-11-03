-- addon/Forte_Core/tests/test_identity.lua
-- FX.Identity (Forte_Core/Core/Identity.lua), the name law of
-- docs/research/upstream-api-2026-11-03.md §2 (Atraeau b64aab0a: on Forever
-- a character is its first+last name; `Name-Realm` is dead, the realm half
-- a connection label): the canonical form is what comparisons and keys
-- ride, the raw spelling the game gave is what goes back out, the self
-- read is the fullest of the three name APIs. The secret classification
-- rides the suites' sentinel seam (the PlainOrNil gate is the ONLY gate
-- the runtime may use).

local FX = ForteXorcist
local I = FX.Identity

test("FX.Identity ships the layer surface", function()
    assertNotNil(I, "Forte_Core/Core/Identity.lua loaded")
    for _, fn in ipairs({ "Canonical", "WireName", "Same", "Remember",
        "Raw", "SelfName" }) do
        assertEquals("function", type(I[fn]), fn)
    end
end)

test("the canonical form: one player, every spelling; two players, never",
function()
    local aria = I.Canonical("Aria Dawnsong")
    assertNotNil(aria)
    assertEquals(aria, I.Canonical("aria dawnsong"), "case")
    assertEquals(aria, I.Canonical("  ARIA   DAWNSONG  "), "spacing")
    assertEquals(aria, I.Canonical("AriaDawnsong"), "the joined parts")
    assertEquals(aria, I.Canonical("Aria Dawnsong-Wildhammer"),
        "the realm label after the hyphen is the connection, not identity")
    assertEquals(I.Canonical("Aria-Wildhammer"), I.Canonical("aria"),
        "a lone name plus a label canonicalises to the name")
    assertNotEquals(I.Canonical("Aria One"), I.Canonical("Aria Two"),
        "two alts sharing a first name never collapse")
    assertNotEquals(I.Canonical("Aria Dawnsong"), I.Canonical("Aria Dawnsongg"))
end)

test("the canonical form refuses what is not a name", function()
    assertEquals(nil, I.Canonical(nil))
    assertEquals(nil, I.Canonical(42))
    assertEquals(nil, I.Canonical(""))
    assertEquals(nil, I.Canonical("   "), "whitespace is no name")
    assertEquals(nil, I.Canonical("-Wildhammer"),
        "a bare label has no name half")
    local SECRET = "FXTEST-SECRET-NAME"
    local realPlain = FX.Compat.PlainOrNil
    FX.Compat.PlainOrNil = function(v)
        if v == SECRET then return nil end
        return realPlain(v)
    end
    assertEquals(nil, I.Canonical(SECRET), "a secret names nobody")
    assertEquals(false, I.Same(SECRET, "Aria"))
    assertEquals(false, I.Same("Aria", SECRET))
    FX.Compat.PlainOrNil = realPlain
end)

test("Same: the comparison every comms law rides", function()
    assertTrue(I.Same("Aria Dawnsong", "ariadawnsong"))
    assertTrue(I.Same("Aria-Dawnsong", "aria"))     -- label folded
    assertFalse(I.Same("Aria Dawnsong", "Aria Two"))
    assertFalse(I.Same(nil, "Aria"), "a nil is never the same player")
    assertFalse(I.Same("Aria", nil))
end)

test("WireName: the space-free wire spelling of a two-part name", function()
    assertEquals("AriaDawnsong", I.WireName("Aria Dawnsong"))
    assertEquals("Aria", I.WireName("Aria-Wildhammer"),
        "the label never rides the wire")
    assertEquals("ariadawnsong", I.WireName("  aria dawnsong  "),
        "the client's casing is the client's; only spaces and the label go")
    assertEquals("AriaDawnsong", I.WireName("  Aria Dawnsong  "))
    assertEquals(nil, I.WireName(nil))
    assertEquals(nil, I.WireName(""))
end)

test("Remember/Raw: the game's spelling is remembered, first one wins",
function()
    local canon = I.Remember("Gvil")
    assertEquals("gvil", canon)
    assertEquals("Gvil", I.Raw(canon))
    I.Remember("gvil")                                -- a later spelling
    assertEquals("Gvil", I.Raw(canon),
        "the notation the game handed first is THE notation all session")
    assertEquals(nil, I.Remember(nil))
    assertEquals(nil, I.Raw("nobody-seen-this-session"))
    -- Same(a,b) and the raw lookup ride the same key:
    assertEquals("Gvil", I.Raw(I.Canonical("  GVIL ")))
end)

test("SelfName: the fullest of the three APIs, caching only good reads",
function()
    local saved = { UnitName = _G.UnitName,
        UnitNameUnmodified = _G.UnitNameUnmodified,
        UnitFullName = _G.UnitFullName }
    I._clearSelfName()
    _G.UnitNameUnmodified = function() error("locked") end
    _G.UnitFullName = function() return "Aria" end
    _G.UnitName = function() return "Aria Dawnsong" end
    assertEquals("Aria Dawnsong", I.SelfName(),
        "the answer with the most parts wins, from any of the three")
    I._clearSelfName()
    _G.UnitNameUnmodified = function() return "Aria Dawnsong", "Somewhere" end
    _G.UnitFullName = nil
    _G.UnitName = nil
    assertEquals("Aria Dawnsong", I.SelfName(),
        "the plain name, the server return ignored, parts kept")
    I._clearSelfName()
    _G.UnitNameUnmodified = function() error("x") end
    _G.UnitFullName = function() error("x") end
    _G.UnitName = function() error("x") end
    assertEquals(nil, I.SelfName(), "all three raising is a nil, not an error")
    _G.UnitName = function() return "Gvil" end
    assertEquals("Gvil", I.SelfName(), "the failed pass cached nothing")
    _G.UnitNameUnmodified = function() error("x") end
    _G.UnitFullName = function() error("x") end
    _G.UnitName = function() error("x") end
    assertEquals("Gvil", I.SelfName(), "a good read is a session constant")
    _G.UnitName, _G.UnitNameUnmodified, _G.UnitFullName =
        saved.UnitName, saved.UnitNameUnmodified, saved.UnitFullName
    I._clearSelfName()
end)

test("SelfName: the client's UNKNOWNOBJECT placeholder is a FAILED read",
function()
    local saved = { UnitName = _G.UnitName,
        UnitNameUnmodified = _G.UnitNameUnmodified,
        UnitFullName = _G.UnitFullName }
    I._clearSelfName()
    -- Early in loading the reads answer the localized placeholder, not
    -- nil (enUS "Unknown" in the live strings; the enGB "UNKNOWN" of the
    -- manager's review is the same law through the global comparison).
    _G.UnitNameUnmodified = function() return tostring(_G.UNKNOWNOBJECT) end
    _G.UnitFullName = function() return "UNKNOWN" end
    _G.UnitName = function() return "Unknown" end
    assertEquals(nil, I.SelfName(), "a placeholder names nobody")
    _G.UnitNameUnmodified = function() return "Aria Dawnsong" end
    _G.UnitFullName = nil
    _G.UnitName = nil
    assertEquals("Aria Dawnsong", I.SelfName(),
        "the placeholder pass cached nothing: the next good read wins")
    _G.UnitName, _G.UnitNameUnmodified, _G.UnitFullName =
        saved.UnitName, saved.UnitNameUnmodified, saved.UnitFullName
    I._clearSelfName()
end)

test("Same and Remember refuse the placeholder: it folds onto no one",
function()
    assertEquals(false, I.Same("Unknown", "Unknown"))
    assertEquals(false, I.Same("UNKNOWN", "unknown"))
    assertEquals(false, I.Same(tostring(_G.UNKNOWNOBJECT), "Aria"),
        "an early placeholder read is not a player")
    assertEquals(false, I.Same("Aria Dawnsong", "Unknown"))
    assertEquals(nil, I.Remember("Unknown"))
    -- The raw form of a real name is untouched by the law:
    assertEquals("unk", I.Canonical("Unk"), "a real name of a similar shape rides")
end)

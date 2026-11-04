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

-- ==================================================================== FX8 ==
-- `FX.Identity.NameOf(unit)` (PLAN §11.2 "Fix FX8"): the same fullest-plain-
-- name law SelfName runs for "player", for ANY unit token. The live probe on
-- uiforever (2026-11-04) measured the shape: `UnitName("player")` answers
-- ("Morvessa", "Ashveil") — the SECOND return is the SURNAME, not a realm —
-- `UnitFullName("player")` answers ("Morvessa Ashveil", "Nethergarde"),
-- `UnitNameUnmodified("player")` answers "Morvessa", and a CHAT_MSG_ADDON
-- sender reads "Morvessa Ashveil-Nethergarde". A reader that keeps only
-- `UnitName`'s first return names the same player `aria` while her own comms
-- lines name her `ariadawnsong`: the two never fold. NameOf is the read that
-- cannot split them. NO caching for non-player tokens (a group roster changes
-- between scans) — every one of these calls walks the APIs.

test("FX8 NameOf: the fullest plain name of a group token, from all three APIs",
function()
    local saved = { UnitName = _G.UnitName,
        UnitNameUnmodified = _G.UnitNameUnmodified,
        UnitFullName = _G.UnitFullName }
    _G.UnitName = function(unit)
        if unit == "party1" then return "Aria", "Dawnsong" end
        return nil
    end
    _G.UnitFullName = function(unit)
        if unit == "party1" then return "Aria Dawnsong", "Nethergarde" end
        return nil
    end
    _G.UnitNameUnmodified = function(unit)
        if unit == "party1" then return "Aria" end
        return nil
    end
    assertEquals("Aria Dawnsong", I.NameOf("party1"),
        "the answer with the most parts wins, from any of the three")
    assertEquals("Aria Dawnsong", I.NameOf("party1"),
        "a repeat pass re-reads: a token is not a session constant")
    -- The merge the probe paid for: the scan's name and the sender's name
    -- share one canonical key.
    assertEquals(I.Canonical("Aria Dawnsong"),
        I.Canonical(I.NameOf("party1")),
        "the roster row and the comms sender are ONE key")
    assertEquals(I.Canonical("Aria Dawnsong"),
        I.Canonical("Aria Dawnsong-Nethergarde"),
        "the sender's realm label is the connection, not identity")
    -- No caching: the SAME token, a changed roster.
    _G.UnitFullName = function(unit)
        if unit == "party1" then return "Zelda Sunstrider", "Nethergarde" end
        return nil
    end
    _G.UnitName = function(unit)
        if unit == "party1" then return "Zelda", "Sunstrider" end
        return nil
    end
    assertEquals("Zelda Sunstrider", I.NameOf("party1"),
        "the token was re-read: a cached group name is a stale peer")
    _G.UnitName, _G.UnitNameUnmodified, _G.UnitFullName =
        saved.UnitName, saved.UnitNameUnmodified, saved.UnitFullName
end)

test("FX8 NameOf: with ONLY UnitName on the surface, both returns join",
function()
    local saved = { UnitName = _G.UnitName,
        UnitNameUnmodified = _G.UnitNameUnmodified,
        UnitFullName = _G.UnitFullName }
    _G.UnitNameUnmodified = nil
    _G.UnitFullName = nil
    _G.UnitName = function(unit)
        if unit == "party1" then return "Aria", "Dawnsong" end
        return nil
    end
    assertEquals("Aria Dawnsong", I.NameOf("party1"),
        "the second return is the SURNAME: joining is the full name")
    _G.UnitName = function(unit)
        if unit == "party1" then return "Aria" end
        return nil
    end
    assertEquals("Aria", I.NameOf("party1"),
        "one return is one part: nothing to join")
    _G.UnitName = function(unit)
        if unit == "party1" then return "Aria", "" end
        return nil
    end
    assertEquals("Aria", I.NameOf("party1"), "an empty half is no part")
    _G.UnitName = function(unit)
        if unit == "party1" then return "Aria", tostring(_G.UNKNOWNOBJECT) end
        return nil
    end
    assertEquals("Aria", I.NameOf("party1"),
        "a placeholder half joins nothing: it names nobody")
    _G.UnitName = function(unit)
        if unit == "party1" then return nil, "Dawnsong" end
        return nil
    end
    assertEquals(nil, I.NameOf("party1"),
        "a name without its first half is no name")
    _G.UnitName, _G.UnitNameUnmodified, _G.UnitFullName =
        saved.UnitName, saved.UnitNameUnmodified, saved.UnitFullName
end)

test("FX8 NameOf: a placeholder, a secret, a raise, an absent surface — all nil",
function()
    local saved = { UnitName = _G.UnitName,
        UnitNameUnmodified = _G.UnitNameUnmodified,
        UnitFullName = _G.UnitFullName }
    _G.UnitNameUnmodified = function() return tostring(_G.UNKNOWNOBJECT) end
    _G.UnitFullName = function() return "UNKNOWN" end
    _G.UnitName = function() return "Unknown" end
    assertEquals(nil, I.NameOf("party1"), "the client's placeholder names nobody")
    _G.UnitNameUnmodified = function() error("locked") end
    _G.UnitFullName = function() error("locked") end
    _G.UnitName = function() error("locked") end
    assertEquals(nil, I.NameOf("party1"),
        "all three raising is a nil, never a propagated error")
    _G.UnitNameUnmodified = nil
    _G.UnitFullName = nil
    _G.UnitName = nil
    assertEquals(nil, I.NameOf("party1"), "no surface at all is no name")
    -- A token the APIs do not know: nil, and the scan drops the row.
    _G.UnitName = function() return nil end
    _G.UnitFullName = function() return nil end
    assertEquals(nil, I.NameOf("party9"), "an unknown token names nobody")
    -- The secret classification rides the gate: a secret name is no name.
    local SECRET = "FXTEST-SECRET-NAME"
    local realPlain = FX.Compat.PlainOrNil
    FX.Compat.PlainOrNil = function(v)
        if v == SECRET then return nil end
        return realPlain(v)
    end
    _G.UnitFullName = function() return SECRET, "Nethergarde" end
    _G.UnitName = function() return SECRET, SECRET end
    _G.UnitNameUnmodified = function() return SECRET end
    assertEquals(nil, I.NameOf("party1"), "a secret names nobody")
    _G.UnitName = function() return "Aria", "Dawnsong" end
    assertEquals("Aria Dawnsong", I.NameOf("party1"),
        "one plain read carries the name through the secret ones")
    FX.Compat.PlainOrNil = realPlain
    _G.UnitName, _G.UnitNameUnmodified, _G.UnitFullName =
        saved.UnitName, saved.UnitNameUnmodified, saved.UnitFullName
end)

test("FX8 NameOf: the arguments it refuses, and SelfName's unchanged law",
function()
    assertEquals(nil, I.NameOf(nil))
    assertEquals(nil, I.NameOf(42))
    assertEquals(nil, I.NameOf(""))
    -- SelfName still reads "player" through the same law and still caches
    -- good reads (the profile-key law): a raising pass, then the good read,
    -- then the APIs go dark and the cached name answers.
    local saved = { UnitName = _G.UnitName,
        UnitNameUnmodified = _G.UnitNameUnmodified,
        UnitFullName = _G.UnitFullName }
    I._clearSelfName()
    _G.UnitName = function(unit)
        if unit == "player" then return "Morvessa", "Ashveil" end
        return nil
    end
    _G.UnitFullName = function(unit)
        if unit == "player" then return "Morvessa Ashveil", "Nethergarde" end
        return nil
    end
    _G.UnitNameUnmodified = function(unit)
        if unit == "player" then return "Morvessa" end
        return nil
    end
    assertEquals("Morvessa Ashveil", I.SelfName(),
        "the self read names the player with the FULL name")
    assertEquals("morvessaashveil", I.Canonical(I.SelfName()))
    _G.UnitName = nil
    _G.UnitFullName = nil
    _G.UnitNameUnmodified = nil
    assertEquals("Morvessa Ashveil", I.SelfName(),
        "a good self read is a session constant")
    _G.UnitName, _G.UnitNameUnmodified, _G.UnitFullName =
        saved.UnitName, saved.UnitNameUnmodified, saved.UnitFullName
    I._clearSelfName()
end)

test("FX8 NameOf: the part count decides; on an equal count the token's own UnitName",
function()
    local saved = { UnitName = _G.UnitName,
        UnitNameUnmodified = _G.UnitNameUnmodified,
        UnitFullName = _G.UnitFullName }
    -- The headless sim's shape, and the client's own failure mode: one API
    -- answers the token (Aria), the others answer one SAME other name.
    _G.UnitName = function(unit)
        if unit == "party1" then return "Aria" end
        return nil
    end
    _G.UnitFullName = function() return "Thrynn", "SimRealm" end
    _G.UnitNameUnmodified = function() return "Thrynn" end
    assertEquals("Aria", I.NameOf("party1"),
        "an equal-count read of somebody else adds no information")
    -- The law of the header, the reason the part count is the judge: a client
    -- whose display settings hide the surname in UnitName is carried by the
    -- fuller UnitFullName, so the scan's name and the sender's stay one key.
    _G.UnitFullName = function() return "Aria Dawnsong", "Nethergarde" end
    assertEquals("Aria Dawnsong", I.NameOf("party1"),
        "the answer with the MOST parts wins over the token's own short one")
    _G.UnitName, _G.UnitNameUnmodified, _G.UnitFullName =
        saved.UnitName, saved.UnitNameUnmodified, saved.UnitFullName
end)

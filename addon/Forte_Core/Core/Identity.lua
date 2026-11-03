-- addon/Forte_Core/Core/Identity.lua
-- FX.Identity: the ONE player-name layer for every code path that compares
-- names, keys a table by a name, or hands a name back to the game.
--
-- THE LAW (docs/research/upstream-api-2026-11-03.md §2, Atraeau/WoW-Addons
-- b64aab0a "a character is its first and last name"): on Forever a
-- character is (first name, last name). There are no realms in the name
-- space, no hyphen in names (the hyphen used to mark a realm and is retired
-- with them), and `GetRealmName()` is a CONNECTION label — Blizzard's own
-- party moves shift players between world instances — never a component of
-- a character's identity. Three name APIs answer for one unit
-- (`UnitNameUnmodified` UnitDocumentation.lua:2522, `UnitFullName` :1223,
-- `UnitName` :2488, all `(unitName, unitServer)` at our 70707 pin) and
-- WHICH one is display-conditional is an explicit live-game unknown
-- (ShouldDisplaySurname is not in the catalog at all); the author's defence
-- — the one adopted here — is to ask all three and take the answer with
-- the MOST name parts, so no display setting can make one character look
-- like two.
--
-- Consequences carried by this file:
--   * CANONICAL FORM for every comparison and every table key:
--     case-insensitive, space-insensitive, hyphen-free, realm-suffix-free
--     (the label after a hyphen is the connection, classic `Name-Realm`
--     spelling). Two spellings of one player collapse; two players do not.
--   * the RAW SPELLING the game handed us is remembered per canonical
--     (first spelling wins, stable across the session) and is what goes
--     back OUT to the game (a whisper target, a comms target) — the
--     author's fromGame/toGame shape, which makes the question "does the
--     event layer spell names like UnitName does?" moot.
--   * every input is classified through FX.Compat.PlainOrNil FIRST (a
--     secret name string has type() == "string" and poisons any string op
--     done on it — the Database.lua CharacterKey hole this layer closes)
--     and every string operation runs inside a pcall.
--   * a failed/secret/absent read is NEVER cached.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist

FX.Identity = {}
local I = FX.Identity

--- PlainOrNil-classified string shape: nil on a secret, an absent, an
--- empty and a non-string value.
local function plainName(v)
    v = FX.Compat.PlainOrNil(v)
    if type(v) ~= "string" or v == "" then return nil end
    return v
end

--- A name read that is the client's OWN placeholder ("the unit has no
--- known name yet"): the `UNKNOWNOBJECT` value (enUS "Unknown" in the
--- live strings, a localized global) or its enUS literal. Early in
--- loading `UnitName("player")` can answer this placeholder instead of
--- nil; as a name it is the same poisoning as a secret, and for the
--- self-read it is a FAILED read: the profile key must not be built on
--- it, and it is never remembered (a later real read carries the
--- identity). The comparison helpers Canonical/WireName still accept it
--- as a value — the law names the SELF READ; only the comparison of
--- names (Same) refuses it, so a placeholder never folds onto a real
--- player's key.
local function isPlaceholderName(plain)
    if type(plain) ~= "string" then return false end
    local unk = _G.UNKNOWNOBJECT
    if type(unk) == "string" and unk ~= "" and plain == unk then
        return true
    end
    return plain:lower() == "unknown"
end

--- Drop the connection label: the classic `Name-Realm` / `Name-*Realm`
--- spelling carries the (mutable) world label after the first hyphen, and
--- Forever names carry no hyphen. Trim outer whitespace. Runs on plain
--- strings only — every caller classifies first; every caller runs this
--- inside a pcall.
local function stripRealm(name)
    name = name:gsub("%-.*$", "")
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    return name
end

--- The comparison key of a name: `aria dawnsong`, `Aria Dawnsong`,
--- `Aria-Dawnsong` and `Aria Dawnsong-Wildhammer` all canonicalise to the
--- one form. nil for a secret/absent/empty name and for a name that is
--- ONLY a realm label.
function I.Canonical(name)
    name = plainName(name)
    if not name then return nil end
    local ok, out = pcall(function()
        local s = stripRealm(name):gsub("%s+", ""):gsub("%-", ""):lower()
        if s == "" then return nil end
        return s
    end)
    if not ok then return nil end
    return out
end

--- The wire spelling of a name: realm label dropped, the parts joined so
--- the value survives a space-separated grammar (`%S+`), the client's own
--- casing kept for display. The receiving side re-matches it by
--- Canonical. nil on a secret/absent/empty name.
function I.WireName(name)
    name = plainName(name)
    if not name then return nil end
    local ok, out = pcall(function()
        local s = stripRealm(name):gsub("%s+", "")
        if s == "" then return nil end
        return s
    end)
    if not ok then return nil end
    return out
end

--- True only when both names classify and share a canonical form. A nil on
--- either side is never "the same player" as anything, and the client's
--- placeholder name (isPlaceholderName) is nobody: an early-loading
--- placeholder read must never fold onto a real player's key.
function I.Same(a, b)
    local ca, cb = plainName(a), plainName(b)
    if isPlaceholderName(ca) or isPlaceholderName(cb) then return false end
    ca, cb = I.Canonical(ca), I.Canonical(cb)
    if not ca or not cb then return false end
    return ca == cb
end

-- ---------------------------------------------------------- raw spellings --

-- canonical -> the first raw spelling the game gave for that identity.
-- Session-scoped (the file-local table): a /reload starts from what the
-- client spells today.
local rawByCanon = {}

--- Remember the spelling the game handed us (first spelling wins: the
--- identity's notation stays stable for the session). Returns the
--- canonical key, nil for an unclassifiable name.
function I.Remember(raw)
    if isPlaceholderName(plainName(raw)) then return nil end
    local canon = I.Canonical(raw)
    if not canon then return nil end
    if rawByCanon[canon] == nil then
        rawByCanon[canon] = raw
    end
    return canon
end

--- The spelling remembered for a canonical key — the one to hand back to
--- the game (a whisper target, an addon-message target). nil when this
--- session has never seen the player.
function I.Raw(canon)
    if type(canon) ~= "string" then return nil end
    return rawByCanon[canon]
end

-- ------------------------------------------------------------ self name ----

--- The own-name read: the fullest plain (realm-label-free) name the name
--- APIs give for "player" — the answer with the most whitespace-separated
--- parts wins, ties go to the earlier of UnitNameUnmodified > UnitFullName
--- > UnitName (the identity-restricted APIs first, the display-side
--- UnitName last). Every API call runs in its own pcall and every string
--- op runs inside the outer one; every value passes PlainOrNil. A good
--- read is a session constant (a mid-session nil can not orphan the
--- profile keyed from it); a failed/secret read caches NOTHING.
local selfCache
function I.SelfName()
    if selfCache then return selfCache end
    local ok, best = pcall(function()
        local picked, parts
        local function consider(v)
            v = FX.Compat.PlainOrNil(v)
            if type(v) ~= "string" then return end
            if isPlaceholderName(v) then return end
            v = stripRealm(v)
            if v == "" then return end
            local n = 0
            for _ in v:gmatch("%S+") do n = n + 1 end
            if n > 0 and (parts == nil or n > parts) then
                picked, parts = v, n
            end
        end
        local function try(fn)
            if type(fn) ~= "function" then return end
            local okC, name = pcall(fn, "player")
            if okC then consider(name) end
        end
        try(_G.UnitNameUnmodified)
        try(_G.UnitFullName)
        try(_G.UnitName)
        return picked
    end)
    if not ok then return nil end
    if type(best) ~= "string" or best == "" then return nil end
    selfCache = best
    return best
end

--- The test seam (and only that): forget the cached self-name — the
--- boundary a fresh login/bootstrap stands at.
function I._clearSelfName()
    selfCache = nil
end

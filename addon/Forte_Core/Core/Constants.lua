-- Forte_Core/Core/Constants.lua
ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist

FX.CONST = {
    ADDON_NAME = "Forte_Core",
    ADDON_DISPLAY = "ForteXorcist",
    VERSION = "0.1.0-dev",

    SLASH_COMMANDS = { "/fx", "/fortexorcist" },

    -- Must match the `## SavedVariables` line in Forte_Core.toc.
    SV_KEY = "ForteXorcistDB",

    HEX = {
        ACCENT = "C41F3B", -- cosmetic; original FX's purple-red. Change freely.
    },
}

-- The soulstone cast family, as NAME patterns -- ONE home (review 4 m7).
-- Two addons match on it: the always-loaded `Forte_Messages` (it announces
-- "Soulstoned >> %s << Use it well!" off the player's own cast events) and
-- the LoadOnDemand `Forte_Warlock/Core/Tools.lua` (it tracks the buff). The
-- dependency law forbids the first from referencing the second, so the list
-- lives in the one add-on both hard-depend on. Name-based by construction
-- (the WotLK-era "Soulstone Resurrection" name is in the spec, not in this
-- data set: pattern, not constant), and "Use Soulstone" is NOT in the family
-- -- Forte_Warlock/tests/test_tools.lua is the pattern's law.
--
-- H1b (docs/localization.md): the patterns are ENGLISH DATA NAMES, so they
-- are the pattern half of a family, never a comparison against a live client
-- name. Every consumer that holds a name the CLIENT said matches it through
-- `FX.MatchesFamily` below, which canonicalizes first.
FX.SoulstonePatterns = { "^Create Soulstone", "^Soulstone" }

--- The family gate: does a name the CLIENT said belong to the family of
--- English data-name `patterns`? A localized client names its spells in its
--- own language, so an English prefix compared against a live client name is
--- blind (H1b, docs/localization.md "Lookup-critical"): the incoming name is
--- canonicalized onto the DATA key by `FX.Locale.CanonicalName` first and the
--- patterns then run on that key, which is the same key space the patterns
--- were written in. The raw name is matched too -- the half of a family whose
--- name no generated data row carries (the spec's "Soulstone Resurrection",
--- the `^Create ` bag gate) has no alias to canonicalize through, and on an
--- English client that raw leg is exactly the old `find`. enUS:
--- `CanonicalName` is the identity, so the whole gate is bit-identical to
--- `name:find(pattern)`.
function FX.MatchesFamily(name, patterns)
    if type(name) ~= "string" then return false end
    local Locale = FX.Locale
    local key = (Locale and Locale.CanonicalName and Locale.CanonicalName(name))
        or name
    for i = 1, #patterns do
        local pattern = patterns[i]
        if key:find(pattern) then return true end
        if key ~= name and name:find(pattern) then return true end
    end
    return false
end

function FX.Colorize(hex, text)
    return string.format("|cff%s%s|r", hex, tostring(text))
end
function FX.ChatPrefix()
    return FX.Colorize(FX.CONST.HEX.ACCENT, "[" .. FX.CONST.ADDON_DISPLAY .. "]") .. " "
end

function FX.Print(...)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(FX.ChatPrefix() .. table.concat({ tostringall(...) }, " "))
    end
end

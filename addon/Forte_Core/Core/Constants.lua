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
FX.SoulstonePatterns = { "^Create Soulstone", "^Soulstone" }

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

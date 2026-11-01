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

-- Forte_Options/Pages/About.lua
-- The About page: version, provenance (the original by Xus, GPL-3.0),
-- credits and build/interface info. Static INFO rows only -- no bound keys.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
local O = FX.Options

local M = "About"
FX.Settings:Register(M, {})

local function buildInfo()
    local ok, version, build, date = pcall(GetBuildInfo)
    if ok and version then
        return tostring(version) .. (build and (" (build " .. tostring(build) .. ")") or "")
            .. (date and (", " .. tostring(date)) or "")
    end
    return "unknown"
end

O:RegisterPage({
    id = "About",
    module = M,
    title = "About",
    colour = O.C.GREY,
    build = function(b)
        b.Tips({
            "ForteXorcist for WoW Forever - rebuilt from the spirit of Xus's addon.",
            "This is NOT a port of the 2012 code (PLAN.md §1); the original stays",
            "the visual and functional law (docs/refs/).",
        })
        b.Section("About ForteXorcist", function(s)
            s.INFO({ label = "Addon version", value = FX.CONST.VERSION })
            s.INFO({ label = "Original", value = "original ForteXorcist by Xus (GPL-3.0)" })
            s.INFO({ label = "Credits", value = "CooldownMaster (MIT) · wowsims · mythicsim · wow-ui-sim" })
            s.INFO({ label = "Font", value = "URW Gothic Book (AGPL-3.0 + font exception)" })
            s.INFO({ label = "Interface", value = "16001 (WoW Forever, Retail 12.x engine)" })
            s.INFO({ label = "Build", value = buildInfo })
            s.INFO({ label = "Author", value = "Gevil - github.com/Gevil/fortexorcist_forever" })
        end, { tip = "Who, what, which build." })
    end,
})

-- Forte_Dev/Suites/Census.lua
-- Load census on the LIVE client: what scripts/gate.py's PROBE proves in the simulator (ALWAYS_MODULES,
-- the player's class add-on loaded and no other, data tables, version) -- asserted against the real
-- addon list. Keep the lists below in step with scripts/gate.py (ALWAYS_MODULES / ALWAYS_DATA / LOAD_PROBES).

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
local Dev = FX.Dev

local ALWAYS_MODULES = { "Cooldown", "Locale", "Log", "Messages", "Probe", "Splash", "TestMode", "Timer" }
-- Modules that may exist besides the gate's set: ours, and the Forte_Core error recorder (Q1).
local ALLOWED_EXTRA_MODULES = { Dev = true, Errors = true }
local CLASS_MODULES = {
    HUNTER = { "Hunter", "HunterUI", "HunterMelee", "HunterMeleeUI", "HunterSwingDemo" },
    WARLOCK = { "Warlock", "WarlockUI" },
}
local ALWAYS_DATA = { Items = true }
local OPTIONAL_DATA = { ItemProcs = true }   -- load-on-demand, pulled in by its own switch
local SHIPPED_ADDONS = { "Forte_Core", "Forte_Cooldown", "Forte_Timer", "Forte_Messages", "Forte_Options",
    "Forte_Items" }

local function listText(list, max)
    max = max or 8
    local parts = {}
    for i = 1, math.min(#list, max) do parts[i] = list[i] end
    local text = table.concat(parts, ",")
    if #list > max then text = text .. ",+" .. (#list - max) end
    return text
end

Dev.RegisterSuite("census", "ooc", function(T)
    T.check("census: core namespace", function()
        T.truthy(type(FX.CONST) == "table", "FX.CONST")
        T.truthy(type(FX.Compat) == "table", "FX.Compat")
        T.truthy(type(FX.modules) == "table", "FX.modules")
        T.truthy(type(FX.Data) == "table", "FX.Data")
    end)

    T.check("census: always-loaded modules registered and enabled", function()
        local missing = {}
        for _, name in ipairs(ALWAYS_MODULES) do
            if not FX.modules[name] then
                missing[#missing + 1] = name .. "(unregistered)"
            elseif not (FX._enabledModules and FX._enabledModules[name]) then
                missing[#missing + 1] = name .. "(not enabled)"
            end
        end
        T.eq(#missing, 0, "modules missing: " .. listText(missing))
    end)

    T.check("census: Forte_Options loaded", function()
        T.truthy(FX.Options ~= nil, "FX.Options")
    end)

    local token = Dev.classToken()
    local classAddon = token and FX.CLASS_ADDONS and FX.CLASS_ADDONS[token]

    T.check("census: the player's class add-on is loaded", function()
        if not token then T.skip("class token unknown") end
        if not classAddon then T.skip("no Forte add-on for class " .. token) end
        T.eq(Dev.isAddOnLoaded(classAddon), true, classAddon .. " loaded")
        T.truthy(FX.AddOnFilesRan(classAddon), classAddon .. " files ran")
    end)

    T.check("census: no other class add-on is loaded", function()
        if not FX.CLASS_ADDONS then T.skip("FX.CLASS_ADDONS absent") end
        local extra = {}
        for _, name in pairs(FX.CLASS_ADDONS) do
            if name ~= classAddon and Dev.isAddOnLoaded(name) == true then extra[#extra + 1] = name end
        end
        table.sort(extra)
        T.eq(#extra, 0, "extra class add-ons: " .. listText(extra))
    end)

    T.check("census: no unexpected modules", function()
        local want = {}
        for _, n in ipairs(ALWAYS_MODULES) do want[n] = true end
        for _, n in ipairs(CLASS_MODULES[token or ""] or {}) do want[n] = true end
        local extra = {}
        for name in pairs(FX.modules) do
            if not want[name] and not ALLOWED_EXTRA_MODULES[name] then extra[#extra + 1] = tostring(name) end
        end
        table.sort(extra)
        T.eq(#extra, 0, "unexpected modules: " .. listText(extra))
    end)

    T.check("census: class modules registered", function()
        local list = CLASS_MODULES[token or ""]
        if not list then T.skip("no class module list for " .. tostring(token)) end
        local missing = {}
        for _, name in ipairs(list) do
            if not FX.modules[name] then missing[#missing + 1] = name end
        end
        T.eq(#missing, 0, "class modules missing: " .. listText(missing))
    end)

    T.check("census: data tables are the always-loaded set + the player's class", function()
        local title = Dev.classTitle(token)
        local have = {}
        for name in pairs(FX.Data) do
            if not tostring(name):find("ByName", 1, true) then have[name] = true end
        end
        local problems = {}
        for name in pairs(ALWAYS_DATA) do
            if not have[name] then problems[#problems + 1] = "missing " .. name end
        end
        if classAddon and title and not have[title] then problems[#problems + 1] = "missing " .. title end
        for name in pairs(have) do
            if not ALWAYS_DATA[name] and not OPTIONAL_DATA[name] and name ~= title then
                problems[#problems + 1] = "extra " .. tostring(name)
            end
        end
        table.sort(problems)
        T.eq(#problems, 0, "data: " .. listText(problems))
    end)

    T.check("census: class data tables are populated", function()
        if not classAddon then T.skip("no Forte add-on for class " .. tostring(token)) end
        local title = Dev.classTitle(token)
        local rows, byName = FX.Data[title], FX.Data[title .. "ByName"]
        T.truthy(type(rows) == "table" and next(rows) ~= nil, "FX.Data." .. title)
        T.truthy(type(byName) == "table" and next(byName) ~= nil, "FX.Data." .. title .. "ByName")
    end)

    T.check("census: version string == FX.CONST.VERSION in every loaded Forte toc", function()
        local api = _G.C_AddOns
        if type(api) ~= "table" or type(api.GetAddOnMetadata) ~= "function" then
            T.skip("C_AddOns.GetAddOnMetadata absent")
        end
        T.truthy(type(FX.CONST.VERSION) == "string", "FX.CONST.VERSION")
        local names = {}
        for _, n in ipairs(SHIPPED_ADDONS) do names[#names + 1] = n end
        if classAddon then names[#names + 1] = classAddon end
        local bad = {}
        for _, name in ipairs(names) do
            if Dev.isAddOnLoaded(name) == true then
                local ok, v = pcall(api.GetAddOnMetadata, name, "Version")
                local plain = ok and Dev.plain(v)
                if plain ~= FX.CONST.VERSION then bad[#bad + 1] = name .. "=" .. Dev.S(plain, 12) end
            end
        end
        T.eq(#bad, 0, "toc version != " .. FX.CONST.VERSION .. ": " .. listText(bad, 4))
    end)
end)

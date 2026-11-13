-- Forte_Dev/Suites/Data.lua
-- Data sanity on the LIVE client, for the player's class: every generated spell id resolves through
-- C_Spell.GetSpellInfo to a name equal to the generated name (enUS), or to FX.L(generated name) on
-- another locale; and the spell-known checks answer plain booleans.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
local Dev = FX.Dev

local function sortedIds(rows)
    local ids = {}
    for id in pairs(rows) do
        if type(id) == "number" then ids[#ids + 1] = id end
    end
    table.sort(ids)
    return ids
end

--- Sorted spell ids of the player's class data (nil when there is none).
function Dev.classSpellIds()
    local title = Dev.classTitle()
    local rows = title and FX.Data and FX.Data[title]
    if type(rows) ~= "table" then return nil, title end
    return sortedIds(rows), title, rows
end

Dev.RegisterSuite("data", "ooc", function(T)
    T.check("data: every generated spell id resolves to the generated name", function()
        local ids, title, rows = Dev.classSpellIds()
        if not ids then T.skip("no class data table (" .. tostring(title) .. ")") end
        local api = _G.C_Spell
        if type(api) ~= "table" or type(api.GetSpellInfo) ~= "function" then T.skip("C_Spell.GetSpellInfo absent") end
        local english = not (FX.Locale and FX.Locale.IsEnglish) or FX.Locale.IsEnglish()
        local bad, unresolved = {}, 0
        for _, id in ipairs(ids) do
            local row = rows[id]
            local want = type(row) == "table" and row.name or nil
            if type(want) == "string" and not english and FX.L then want = FX.L(want) end
            local ok, info = pcall(api.GetSpellInfo, id)
            local got = ok and type(info) == "table" and Dev.plain(info.name) or nil
            if type(got) ~= "string" then
                unresolved = unresolved + 1
                bad[#bad + 1] = id .. ":unresolved"
            elseif got ~= want then
                bad[#bad + 1] = id .. ":" .. Dev.clip(tostring(want), 20) .. "~=" .. Dev.clip(got, 20)
            end
        end
        local first = {}
        for i = 1, math.min(#bad, 10) do first[i] = bad[i] end
        T.eq(#bad, 0, string.format("%d/%d mismatches (%d unresolved) first: %s", #bad, #ids, unresolved,
            table.concat(first, " ")))
        T.note(#ids .. " spell ids match" .. (english and "" or " (via FX.L)"))
    end)

    T.check("data: IsPlayerSpell / the compat known-check answer plain booleans", function()
        local ids = Dev.classSpellIds()
        if not ids or #ids == 0 then T.skip("no class spell ids") end
        local id = ids[1]
        local compat = FX.Compat.IsPlayerSpell(id)
        T.eq(type(compat), "boolean", "Compat.IsPlayerSpell")
        T.truthy(FX.Compat.isPlayerSpellSource ~= nil, "no spell-known source answered (the addon would track nothing)")
        local raw = _G.IsPlayerSpell
        if type(raw) == "function" then
            local ok, v = pcall(raw, id)
            T.truthy(ok, "IsPlayerSpell raised")
            T.eq(type(Dev.plain(v)), "boolean", "IsPlayerSpell result")
        end
        T.note("source " .. tostring(FX.Compat.isPlayerSpellSource) .. ", raw IsPlayerSpell "
            .. (type(raw) == "function" and "present" or "absent"))
    end)
end)

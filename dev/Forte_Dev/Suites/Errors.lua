-- Forte_Dev/Suites/Errors.lua
-- FX.Errors (Forte_Core's recorder, sibling Q1, contract PLAN §11.11): present; nothing recorded since
-- this load; a deliberate pcall'd error is NOT recorded. Every check skips while FX.Errors is absent.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
local Dev = FX.Dev

local function errors(T)
    local E = FX.Errors
    if type(E) ~= "table" then T.skip("FX.Errors absent (Forte_Core errors module not built yet)") end
    return E
end

local function listOf()
    local e = FX.db and FX.db.errors
    return type(e) == "table" and type(e.list) == "table" and e.list or nil
end

Dev.RegisterSuite("errors", "ooc", function(T)
    T.check("errors: FX.Errors exists with a numeric sinceLoad", function()
        local E = errors(T)
        T.eq(type(Dev.plain(E.sinceLoad)), "number", "FX.Errors.sinceLoad")
    end)

    T.check("errors: ForteXorcistDB.errors has the contract shape (sparse: absent until the first entry)", function()
        errors(T)
        local e = FX.db and FX.db.errors
        if e == nil then
            T.note("no errors stored (the table is created by the first entry)")
            return
        end
        T.truthy(type(e) == "table", "FX.db.errors")
        T.eq(type(e.list), "table", "errors.list")
        T.eq(type(e.session), "number", "errors.session")
    end)

    T.check("errors: sinceLoad is 0 at the start of the run", function()
        local E = errors(T)
        local n = Dev.plain(E.sinceLoad)
        T.eq(type(n), "number", "sinceLoad")
        if n ~= 0 then
            local list = listOf()
            local last = list and list[#list]
            T.fail("sinceLoad=" .. n .. " last: " .. Dev.S(type(last) == "table" and last.msg or "?", 100))
        end
    end)

    T.check("errors: a deliberate pcall'd error is not recorded", function()
        local E = errors(T)
        local before, list = Dev.plain(E.sinceLoad), listOf()
        local nBefore = list and #list
        local ok = pcall(error, "forte-dev deliberate pcall'd error")
        T.eq(ok, false, "pcall(error) result")
        T.eq(Dev.plain(E.sinceLoad), before, "sinceLoad after")
        local after = listOf()
        T.eq(after and #after, nBefore, "errors.list length after")
    end)
end)

-- Forte_Dev/Suites/Combat.lua
-- The combat suite: arms with `/fxdev selftest combat`, runs Dev.COMBAT_DELAY seconds after
-- PLAYER_REGEN_DISABLED (the owner makes the combat). READ assertions only: nothing is cast, targeted or
-- moved. Every API value is classified before anything touches it, and NO assertion compares a secret:
--   * FX.Compat.PlainOrNil neither raises nor passes a secret on UnitHealth('target'), a target aura read
--     and a cooldown read;
--   * the own cast ids captured while armed are plain.
-- An API that itself raises is not a failure here (it is the real restriction behaviour); it is noted.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
local Dev = FX.Dev

--- Read through `fn`, push the result through PlainOrNil, assert the contract. Returns raw, plain.
local function readCheck(T, label, fn, inspect)
    T.check(label, function()
        local ok, raw = pcall(fn)
        if not ok then
            T.note("api raised (" .. Dev.S(raw, 60) .. "): callers must pcall")
            return
        end
        local rawK = Dev.K(raw)
        local okPlain, plain = pcall(FX.Compat.PlainOrNil, raw)
        T.truthy(okPlain, "PlainOrNil raised")
        T.falsy(Dev.isSecret(plain), "PlainOrNil passed a secret through")
        local extra = ""
        if inspect and type(plain) == "table" then extra = " " .. inspect(plain) end
        T.note("raw=" .. rawK .. " plain=" .. Dev.K(plain) .. extra)
    end)
end

local function firstSpellId()
    local ids = Dev.classSpellIds()
    if not ids or #ids == 0 then return nil end
    for _, id in ipairs(ids) do
        if FX.Compat.IsPlayerSpell(id) then return id end
    end
    return ids[1]
end

Dev.RegisterSuite("combat", "combat", function(T)
    T.check("combat: the run happened in combat", function()
        if not Dev.inCombat() then T.skip("combat ended before the run; the reads below are out-of-combat reads") end
    end)

    T.check("combat: secret predicates (informational)", function()
        local C = FX.Compat
        T.note(string.format("cooldowns=%s auras=%s", Dev.K(C.ShouldCooldownsBeSecret and Dev.plain(C.ShouldCooldownsBeSecret())),
            Dev.K(C.ShouldAurasBeSecret and Dev.plain(C.ShouldAurasBeSecret()))))
    end)

    readCheck(T, "combat: UnitHealth('target') through PlainOrNil", function() return _G.UnitHealth("target") end)
    readCheck(T, "combat: UnitHealth('player') through PlainOrNil", function() return _G.UnitHealth("player") end)

    readCheck(T, "combat: target aura read through PlainOrNil", function()
        local api = _G.C_UnitAuras
        if type(api) ~= "table" or type(api.GetAuraDataByIndex) ~= "function" then error("C_UnitAuras absent", 0) end
        local aura = api.GetAuraDataByIndex("target", 1, "HARMFUL")
        if Dev.isSecret(aura) or type(aura) ~= "table" then return aura end
        -- fields of a plain aura table are classified one by one; a secret field must not survive PlainOrNil
        local name, id = Dev.plain(aura.name), Dev.plain(aura.spellId)
        if Dev.isSecret(name) or Dev.isSecret(id) then error("PlainOrNil passed an aura field through", 0) end
        return aura
    end, function(aura)
        return "name=" .. Dev.K(Dev.plain(aura.name)) .. " spellId=" .. Dev.K(Dev.plain(aura.spellId))
    end)

    readCheck(T, "combat: own spell cooldown read through PlainOrNil", function()
        local id = firstSpellId()
        if not id then error("no class spell id", 0) end
        local info = FX.Compat.GetSpellCooldownInfo(id)
        if Dev.isSecret(info) or type(info) ~= "table" then return info end
        local start, dur = Dev.plain(info.startTime), Dev.plain(info.duration)
        if Dev.isSecret(start) or Dev.isSecret(dur) then error("PlainOrNil passed a cooldown field through", 0) end
        return info
    end, function(info)
        return "start=" .. Dev.K(Dev.plain(info.startTime)) .. " dur=" .. Dev.K(Dev.plain(info.duration))
    end)

    T.check("combat: own cast spell ids are plain", function()
        local ring = Dev.state.castRing
        if not ring or #ring == 0 then T.skip("no own cast observed while armed (cast something in combat)") end
        local secret = 0
        for _, k in ipairs(ring) do
            if k:sub(1, 7) ~= "number:" then secret = secret + 1 end
        end
        T.eq(secret, 0, secret .. " of " .. #ring .. " own cast ids were not plain")
        T.note(#ring .. " own cast ids plain, last " .. ring[#ring])
    end)
end)

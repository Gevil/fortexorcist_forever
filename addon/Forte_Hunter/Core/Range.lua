-- addon/Forte_Hunter/Core/Range.lua
-- FX.Hunter.RangeMeter: the range / dead-zone ladder behind the Hunter
-- range light (docs/research/weaponswingtimer.md gap row 6 / §B16; the
-- PLAN.md "range / dead-zone light (8-35 yd, range APIs plain)"
-- commitment). The ladder is OWN code; WeaponSwingTimer SixxFix's
-- WeaponSwingTimer_Range.lua:339-433 (GPLv3, WatchYourSixx; original WST
-- by LeftHandedGlove) is the cited reference for the Forever-specific
-- facts it encodes: Wing Clip is the ONLY reliable 5-yd breakpoint
-- (Raptor Strike's range API reports true outside melee range, :152-160),
-- Auto Shot's 8-yd floor makes the dead zone (ranged-false + Scatter
-- true), CheckInteractDistance separates too-close from too-far
-- (:176-199). Changes: compact band set (no per-band user texts), the
-- non-Hunter generic-class ladder NOT ported, the legacy IsSpellInRange
-- fallback NOT ported (undeclared, §B16).
--
-- All reads are pcall-guarded and normalise true/1 -- "range checks are
-- NOT secret" (PLAN §2.4), so booleans pass; the spellbook rungs speak the
-- CLIENT's language (FX.L, the AGENTS.md locale law).
--
-- Every live read is behind an injectable reader (the tests construct a
-- meter with fakes; the UI ships the defaults below), so the band law is
-- a pure decision table.
--
-- Band -> display (the ForteXorcist palette, docs/research/
-- weaponswingtimer.md §5; the Timeline category colours):
--   melee    Debuff red      "MELEE"
--   deadzone Item yellow     "DEAD 5-8"
--   close    Spell orange    "8-15"
--   ranged   Potion green    "8-35" (the max from the live Auto Shot row)
--   far      Powerup cyan    "35+"
--   out      grey            "OUT"
--   none     grey            "" (hidden)

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
FX.Hunter = FX.Hunter or {}

local RangeMeter = {}
RangeMeter.__index = RangeMeter

--- The max ranged range: the live Auto Shot row (name-resolved via FX.L,
--- never a hand-typed id), floor-rounded; 35 is WST's data-pin fallback
--- (WeaponSwingTimer_Range.lua:201-211 + the Auto Shot MaxRange=35 row).
local MAX_RANGE_FALLBACK = 35

local function plainBool(v)
    if v == true then return true end
    if v == 1 then return true end
    if v == false then return false end
    if v == 0 then return false end
    return nil
end
RangeMeter.PlainBool = plainBool

--- Normalise a reader result: a plain true/false, the 1/0 numeric shape,
--- everything else = "no knowledge" (nil).
local function normBool(v)
    if v == nil then return nil end
    local ok, s = pcall(FX.Compat.PlainOrNil, v)
    if not ok then return nil end
    return plainBool(s)
end

--- Pcall a reader and normalise; a raising reader = no knowledge.
local function read(self, key, ...)
    local fn = self[key]
    if fn == nil then return nil end
    local ok, v = pcall(fn, ...)
    if not ok then return nil end
    return normBool(v)
end

--- The band ladder. Returns band, text.
function RangeMeter:GetBand()
    local exists = read(self, "targetReader")
    if exists ~= true then return nil, nil end
    local dead = read(self, "deadReader")
    if dead == true then return nil, nil end
    local can = read(self, "attackReader")
    if can == false then return nil, nil end
    -- The 5-yd rung: Wing Clip only (§B16: Raptor Strike lies on Forever).
    local melee = read(self, "meleeReader")
    if melee == true then return "melee", "MELEE" end
    local scatter = read(self, "scatterReader")
    local ranged = read(self, "rangedReader")
    if ranged == true then
        if scatter == true then return "close", "8-15" end
        return "ranged", "8-" .. tostring(self.maxRange)
    end
    if ranged == false then
        -- Auto Shot out: the 5-8 dead zone (Scatter in range), else
        -- CheckInteractDistance splits too-close from too-far.
        if scatter == true then return "deadzone", "DEAD 5-8" end
        local near = read(self, "closeReader")
        if near == true then return "deadzone", "DEAD 5-8" end
        local mark = read(self, "markReader")
        if mark == true then return "far", tostring(self.maxRange) .. "+" end
        if mark == false then return "out", "OUT" end
        return "out", "OUT"
    end
    -- ranged == nil: no knowledge (the native API is a launch probe and
    -- the spellbook rung may be mid-resolve) -- spell-ladder fallback.
    if scatter == true then return "close", "5-15" end
    local mark = read(self, "markReader")
    if mark == true then return "far", "IN 100" end
    if mark == false then return "out", "OUT" end
    return nil, nil
end

function FX.Hunter.NewRangeMeter(opts)
    opts = opts or {}
    return setmetatable({
        targetReader = opts.targetReader,   -- () -> target exists
        deadReader = opts.deadReader,       -- () -> target dead
        attackReader = opts.attackReader,   -- () -> player can attack
        meleeReader = opts.meleeReader,     -- () -> Wing Clip in range
        scatterReader = opts.scatterReader, -- () -> Scatter Shot in range
        markReader = opts.markReader,       -- () -> Hunter's Mark in range
        rangedReader = opts.rangedReader,   -- () -> Auto Shot/swing range
        closeReader = opts.closeReader,     -- () -> CheckInteractDistance
        maxRange = MAX_RANGE_FALLBACK,
    }, RangeMeter)
end

-- ------------------------------------------------------------- the seams --
-- The live readers (tests inject fakes). Every call pcall-guarded; every
-- result normalised by the meter. Client spell names ride FX.L.

local function spellBookInRange(englishName)
    local ns = _G.C_SpellBook
    if not (ns and ns.FindSpellBookSlotForSpell
        and ns.IsSpellBookItemInRange) then return nil end
    local ok, slot, bank = pcall(ns.FindSpellBookSlotForSpell,
        FX.L(englishName))
    if not ok or slot == nil then return nil end
    local ok2, res = pcall(ns.IsSpellBookItemInRange, slot, bank, "target")
    if not ok2 then return nil end
    return res
end

local function unitBool(fn, a, b)
    if type(fn) ~= "function" then return nil end
    local ok, v = (b == nil) and pcall(fn, a) or pcall(fn, a, b)
    return ok and v or nil
end

--- The native ranged rung: C_SwingTimer.IsTargetWithinSwingRange(Ranged)
--- primary (CAT-declared; the Enum touch is pcall-guarded for the
--- taint/secret shape), the spellbook Auto Shot rung as the fallback --
--- the WST NativeRangedInRange law (:162-174) with the legacy
--- IsSpellInRange leg dropped.
local function nativeRangedInRange()
    local ok, t = pcall(function()
        local e = _G.Enum and _G.Enum.PlayerSwingType
        return FX.Compat.PlainOrNil(e and e.Ranged)
    end)
    if ok and type(t) == "number" and _G.C_SwingTimer
        and _G.C_SwingTimer.IsTargetWithinSwingRange then
        local ok2, v = pcall(_G.C_SwingTimer.IsTargetWithinSwingRange, t)
        v = ok2 and FX.Compat.PlainOrNil(v) or nil
        local b = plainBool(v)
        if b ~= nil then return b end
    end
    return spellBookInRange("Auto Shot")
end

--- The live meter the UI drives.
FX.Hunter.RangeMeter = FX.Hunter.NewRangeMeter({
    targetReader = function()
        return unitBool(_G.UnitExists, "target")
    end,
    deadReader = function()
        return unitBool(_G.UnitIsDead, "target")
    end,
    attackReader = function()
        return unitBool(_G.UnitCanAttack, "player", "target")
    end,
    meleeReader = function() return spellBookInRange("Wing Clip") end,
    scatterReader = function() return spellBookInRange("Scatter Shot") end,
    markReader = function() return spellBookInRange("Hunter's Mark") end,
    rangedReader = nativeRangedInRange,
    closeReader = function()
        if type(_G.CheckInteractDistance) ~= "function" then return nil end
        local ok, v = pcall(_G.CheckInteractDistance, "target", 4)
        local b = ok and plainBool(FX.Compat.PlainOrNil(v)) or nil
        if b ~= nil then return b end
        ok, v = pcall(_G.CheckInteractDistance, "target", 1)
        return ok and plainBool(FX.Compat.PlainOrNil(v)) or nil
    end,
})

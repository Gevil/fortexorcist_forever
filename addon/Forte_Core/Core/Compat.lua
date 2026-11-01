-- Forte_Core/Core/Compat.lua
-- Shared flavor/version flags and secret-value-safe helpers. Every other Forte_*
-- module reads these instead of checking GetBuildInfo()/issecretvalue() itself.
--
-- Findings this is built on (see docs/ for the full writeup):
--  - WoW Forever runs the modern Retail 12.x engine (not the old 1.13.x Classic
--    codebase), under interface number 16001, confirmed live on this build.
--  - Registering COMBAT_LOG_EVENT_UNFILTERED on Forever throws
--    ADDON_ACTION_FORBIDDEN outright (CooldownMaster's Core/Compat.lua,
--    confirmed against the real client).
--  - Reading another unit's (or your own, in-combat) buffs/debuffs can throw or
--    return nothing while Forever's aura secrecy is active; always go through
--    PlainOrNil before branching on a read that might be "in combat" data.
--  - Blizzard's native Cooldown Manager (C_CooldownViewer) exists on Forever but
--    is deliberately NOT used as a data source here -- see
--    docs/why-not-blizzard-cdm.md for why CooldownMaster/EllesmereUI reached the
--    same conclusion.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist

FX.Compat = FX.Compat or {}
local Compat = FX.Compat

local _, _, _, tocversion = GetBuildInfo()
Compat.TOC_VERSION = tocversion or 0

-- Forever ships as interface 16001 (patch line 1.60.x) on the retail engine.
Compat.IS_FOREVER = Compat.TOC_VERSION >= 16000 and Compat.TOC_VERSION < 20000
Compat.IS_RETAIL = Compat.TOC_VERSION >= 100000 or Compat.IS_FOREVER

-- See header: Forever refuses the combat log event outright.
Compat.HAS_COMBAT_LOG = not Compat.IS_FOREVER

-- Deliberately not wired to a live C_CooldownViewer probe. See docs/why-not-blizzard-cdm.md.
Compat.HAS_BLIZZ_CDM = false

--- Returns `v`, or nil if `v` is a WoW 12.x "secret" value (or outright nil).
--- Never compare, branch on, or do arithmetic with a raw read of unit/combat
--- state without passing it through this first -- a bare `if x > 5` on a
--- secret number throws, not just returns a wrong answer.
function Compat.PlainOrNil(v)
    if v == nil then return nil end
    local iss = _G.issecretvalue
    if iss and iss(v) then return nil end
    return v
end

--- GetSpellCooldown across the old (multi-return) and C_Spell (table-return) APIs.
--- Forever ships C_Spell.GetSpellCooldown; the plain global is not guaranteed.
function Compat.GetSpellCooldown(spellID)
    if C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown(spellID)
        if not info then return 0, 0, false, 1 end
        return info.startTime, info.duration, info.isEnabled, info.modRate
    elseif type(GetSpellCooldown) == "function" then
        return GetSpellCooldown(spellID)
    end
    return 0, 0, false, 1
end

--- IsPlayerSpell across clients; stays a plain global on every flavor so far,
--- but kept as a wrapper so a future removal only needs fixing in one place.
function Compat.IsPlayerSpell(spellID)
    if type(IsPlayerSpell) == "function" then
        return IsPlayerSpell(spellID) and true or false
    end
    return false
end

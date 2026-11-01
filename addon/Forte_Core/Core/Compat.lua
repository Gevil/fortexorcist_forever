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

--- The raw SpellCooldownInfo table of C_Spell.GetSpellCooldown (startTime,
--- duration, isEnabled, isActive, modRate, activeCategory,
--- timeUntilEndOfStartRecovery, isOnGCD), nil where absent. The NeverSecret
--- isActive/isOnGCD booleans survive a combat lockdown of the numbers --
--- they are what the active-edge fallback (Engine:OnActiveEdge, PLAN §8
--- mitigation 2) keys on. Table fields may still be secret: compare the
--- NeverSecret booleans freely, route every number through PlainOrNil.
function Compat.GetSpellCooldownInfo(spellIdentifier)
    if C_Spell and C_Spell.GetSpellCooldown then
        return C_Spell.GetSpellCooldown(spellIdentifier)
    end
    return nil
end

--- The raw SpellChargeInfo table of C_Spell.GetSpellCharges (currentCharges,
--- maxCharges, cooldownStartTime, cooldownDuration, chargeModRate,
--- isActive), nil where absent. maxCharges and isActive are NeverSecret;
--- currentCharges, cooldownStartTime, cooldownDuration and chargeModRate
--- are secret-able in combat -- Engine:OnReadCharges guards them.
function Compat.GetSpellCharges(spellIdentifier)
    if C_Spell and C_Spell.GetSpellCharges then
        return C_Spell.GetSpellCharges(spellIdentifier)
    end
    return nil
end

--- IsPlayerSpell across clients; stays a plain global on every flavor so far,
--- but kept as a wrapper so a future removal only needs fixing in one place.
function Compat.IsPlayerSpell(spellID)
    if type(IsPlayerSpell) == "function" then
        return IsPlayerSpell(spellID) and true or false
    end
    return false
end

-- Item seams (Forte_Cooldown/Core/Items.lua). Existence verified twice:
-- pinned Forever catalog (docs/api items-inventory + combat catalogs,
-- 1.60.1.70532) and the wow-ui-sim probe (2026-11-01). SIM RESULT:
-- C_Item.{GetItemCooldown, GetItemInfoInstant, GetItemInfo, GetItemIconByID},
-- C_Container.{GetItemCooldown, GetContainerItemCooldown, GetContainerItemID,
-- GetContainerNumSlots, GetContainerItemInfo}, GetInventoryItemID and
-- GetInventoryItemCooldown all EXIST and return plain numbers (0/0/1 =
-- ready). C_Item.GetItemSpell and C_Spell.GetItemCooldown are ABSENT in the
-- sim profile build (catalog-listed, live-only) -- callers must nil-guard.
-- C_Item.GetItemCooldown accepts a raw itemID number as its ItemInfo
-- argument (measured in the sim; CooldownMaster passes numbers on the live
-- client too).

--- The equipped item id in an inventory slot (trinkets: 13/14), nil when
--- empty. GetInventoryItemID is the Blizzard paperdoll/bag path (verified
--- in the Camelot UI source) and is present in the sim.
function Compat.GetEquippedItemID(slot)
    if type(GetInventoryItemID) == "function" then
        return GetInventoryItemID("player", slot)
    end
    return nil
end

--- The item's display name via C_Item.GetItemInfo (async-backed; returns
--- nil for ids the client has never seen -- a live probe, see Items.lua
--- header). May raise on a junk id: call sites pcall it.
function Compat.GetItemInfoName(itemID)
    if C_Item and C_Item.GetItemInfo then
        return (C_Item.GetItemInfo(itemID))
    end
    return nil
end

--- The item's icon fileID (C_Item.GetItemIconByID), nil where absent.
function Compat.GetItemIcon(itemID)
    if C_Item and C_Item.GetItemIconByID then
        return C_Item.GetItemIconByID(itemID)
    end
    return nil
end

--- The item's on-use spell as (spellName, spellID), nil where the API is
--- absent (it is in the sim build) or the item has no use spell. Catalog
--- C_Item.GetItemSpell(itemInfo): the sim and CooldownMaster accept the
--- raw itemID.
function Compat.GetItemSpellInfo(itemID)
    if C_Item and C_Item.GetItemSpell then
        return C_Item.GetItemSpell(itemID)
    end
    return nil
end

--- Slots in a bag (0 = backpack). nil when the API is absent.
function Compat.GetContainerNumSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bag)
    end
    return nil
end

--- The item id in bag `bag` at 1-based `slot`, nil when empty/absent.
function Compat.GetContainerItemID(bag, slot)
    if C_Container and C_Container.GetContainerItemID then
        return C_Container.GetContainerItemID(bag, slot)
    end
    return nil
end

--- RAW item-cooldown read: (startTime, duration, enable). Equipped items
--- (slot non-nil) ride GetInventoryItemCooldown("player", slot) --
--- CooldownMaster's proven split: bag items poll by itemID via
--- C_Container.GetItemCooldown, equipped trinkets by inventory slot (a bag
--- copy of the same itemID shares its category cooldown, the slot is the
--- one instance you own). Returns (nil, nil, nil) when no API applies.
--- The catalog annotates NO SecretWhen… on these returns (only
--- SecretArguments=AllowedWhenUntainted), so they are expected plain --
--- that expectation is an open live probe (docs/design-combat-procs.md §5.7);
--- consumers MUST route every number through PlainOrNil regardless.
function Compat.GetItemCooldownInfo(itemID, slot)
    if slot ~= nil and type(GetInventoryItemCooldown) == "function" then
        return GetInventoryItemCooldown("player", slot)
    end
    if C_Container and C_Container.GetItemCooldown then
        return C_Container.GetItemCooldown(itemID)
    end
    if C_Item and C_Item.GetItemCooldown then
        return C_Item.GetItemCooldown(itemID)
    end
    return nil, nil, nil
end

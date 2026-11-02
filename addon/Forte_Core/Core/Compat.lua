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
--- issecretvalue runs FIRST: even `v == nil` is a comparison, and a secret
--- may wrap nil ("Secret NIL is not public nil", wow-ui-sim spec
--- base-spell-specialization-security.md:19). A plain nil passes through as nil.
--- issecretvalue itself runs in a pcall and fails CLOSED: if it raises we
--- cannot know, so the value is treated as unusable (nil). The guards that
--- call this run outside any pcall (CodeReview2 n5).
function Compat.PlainOrNil(v)
    local iss = _G.issecretvalue
    if iss then
        local ok, secret = pcall(iss, v)
        if not ok or secret then return nil end
    end
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

--- The raw LuaDurationObject of C_Spell.GetSpellCooldownDuration(spell,
--- ignoreGCD), nil where the API is absent. THE opportunistic exact anchor
--- of the cooldown read tiers (docs/research/secrets-unknowns.md §2): this
--- is the one cooldown-timing read with NO output-restriction annotation
--- (pinned catalog C_Spell.GetSpellCooldownDuration
--- @SpellDocumentation.lua:326 declares only
--- `SecretArguments = AllowedWhenTainted` and returns a LuaDurationObject),
--- and the duration-object family is the value type the restriction
--- machinery deliberately leaves non-secret. The object's methods, all in
--- the pinned catalog @LuaDurationObjectAPIDocumentation.lua:
---   :350 HasSecretValues() -> bool (`ReturnsNeverSecret = true`)
---   :270 GetRemainingDuration() -> **Seconds**
---   :318 GetTotalDuration()     -> **Seconds**
---   :302 GetStartTime() / :240 GetEndTime() -> FrameTime (GetTime() units)
--- SECONDS, not ms -- the same scale GetTime() and the Engine's
--- start/duration/endTime live on. The call is declared `MayReturnNothing`,
--- so nil is a normal answer; call sites pcall it (a live read can raise).
function Compat.GetSpellCooldownDurationObject(spellIdentifier, ignoreGCD)
    if C_Spell and C_Spell.GetSpellCooldownDuration then
        return C_Spell.GetSpellCooldownDuration(spellIdentifier,
            ignoreGCD and true or false)
    end
    return nil
end

--- Is the add-on restriction of `restrictionType` active right now?
--- C_RestrictedActions.IsAddOnRestrictionActive(type) -> bool
--- (pinned catalog @RestrictedActionsDocumentation.lua:54);
--- `AddOnRestrictionType` = {Combat=0, Encounter=1, ChallengeMode=2,
--- PvPMatch=3, Map=4, Chat=5} (@RestrictedActionsConstantsDocumentation.lua:18).
--- The clean-room native read of this surface (Forever 70707): it answers one
--- byte of a per-type state array (docs/research/secrets-unknowns.md §5).
--- nil where the API is absent -- the wow-ui-sim build does NOT ship
--- `C_RestrictedActions` (measured 2026-11-02: the table exists, the method is
--- no function), so the caller must treat nil as "unknown", never as false.
--- Call sites pcall (the call is `SecretArguments = AllowedWhenUntainted`).
function Compat.IsAddOnRestrictionActive(restrictionType)
    if C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive then
        return C_RestrictedActions.IsAddOnRestrictionActive(restrictionType)
    end
    return nil
end

--- Are cooldown reads going to come back secret right now?
--- C_Secrets.ShouldCooldownsBeSecret() -> bool
--- (pinned catalog @SecretPredicateAPIDocumentation.lua:128). nil where the
--- API is absent (the sim does not ship C_Secrets -- measured 2026-11-02).
function Compat.ShouldCooldownsBeSecret()
    if C_Secrets and C_Secrets.ShouldCooldownsBeSecret then
        return C_Secrets.ShouldCooldownsBeSecret()
    end
    return nil
end

--- Are aura reads going to come back secret right now?
--- C_Secrets.ShouldAurasBeSecret() -> bool
--- (pinned catalog @SecretPredicateAPIDocumentation.lua:118). nil where the
--- API is absent.
function Compat.ShouldAurasBeSecret()
    if C_Secrets and C_Secrets.ShouldAurasBeSecret then
        return C_Secrets.ShouldAurasBeSecret()
    end
    return nil
end

--- Which spell-known source last answered a Compat.IsPlayerSpell query:
--- "IsPlayerSpell", "IsSpellKnownOrInSpellBook", "IsSpellKnown", or nil
--- while none has answered. /fx status and the Module:Rebuild zero-tracked
--- notice read it (review M4).
Compat.isPlayerSpellSource = nil

--- Can the player cast this spell? Review M4: `IsPlayerSpell` has ZERO
--- declarations in the pinned Forever catalogs, so relying on it alone
--- silently tracks nothing when it is absent. The chain: the legacy global
--- when present, else C_SpellBook.IsSpellKnownOrInSpellBook
--- (spellID, [spellBank=Player], [includeOverrides=true]) -> bool
--- (SpellBookDocumentation.lua:754 in the pinned catalog), else
--- C_SpellBook.IsSpellKnown(spellID, [spellBank=Player]) -> bool
--- (SpellBookDocumentation.lua:737). Every link runs inside a pcall (a
--- tainted id raises on lookup) and its result passes PlainOrNil; a link
--- that is absent, raises, or yields a secret/nil moves to the next one.
--- Only the first link that ANSWERS decides, and records itself in
--- Compat.isPlayerSpellSource.
local knownSources
function Compat.IsPlayerSpell(spellID)
    if not knownSources then
        knownSources = {
            { name = "IsPlayerSpell",
                get = function() return _G.IsPlayerSpell end },
            { name = "IsSpellKnownOrInSpellBook",
                get = function()
                    return _G.C_SpellBook and _G.C_SpellBook.IsSpellKnownOrInSpellBook
                end },
            { name = "IsSpellKnown",
                get = function()
                    return _G.C_SpellBook and _G.C_SpellBook.IsSpellKnown
                end },
        }
    end
    local id = Compat.PlainOrNil(spellID)
    if id == nil then return false end
    for _, src in ipairs(knownSources) do
        local fn = src.get()
        if type(fn) == "function" then
            local ok, known = pcall(fn, id)
            local plain = ok and Compat.PlainOrNil(known)
            if plain ~= nil then
                Compat.isPlayerSpellSource = src.name
                return plain and true or false
            end
        end
    end
    return false
end

-- Item seams (Forte_Cooldown/Core/Items.lua). Evidence (review m2
-- corrected): the wow-ui-sim probe (2026-11-01: C_Item.{GetItemCooldown,
-- GetItemInfoInstant, GetItemInfo, GetItemIconByID, GetItemID},
-- C_Container.{GetItemCooldown, GetContainerItemCooldown,
-- GetContainerItemID, GetContainerNumSlots, GetContainerItemInfo},
-- GetInventoryItemID and GetInventoryItemCooldown all EXIST there and
-- return plain numbers (0/0/1 = ready)) and CooldownMaster shipping
-- GetInventoryItem{ID,Cooldown} on the live client
-- (docs/engine-notes.md:16). GetInventoryItemID/GetInventoryItemCooldown
-- are NOT in the pinned Forever catalogs (zero declarations; the closest
-- catalog entry is C_TooltipInfo.GetInventoryItemByID) -- the earlier
-- "verified twice, catalog included" claim here was false. C_Item.
-- GetItemSpell and C_Spell.GetItemCooldown are ABSENT in the sim profile
-- build (catalog-listed, live-only) -- callers must nil-guard. C_Item.
-- GetItemCooldown accepts a raw itemID number as its ItemInfo argument
-- (measured in the sim; CooldownMaster passes numbers on the live client
-- too).

--- The equipped item id in an inventory slot (trinkets: 13/14), nil when
--- empty. Primary: GetInventoryItemID("player", slot), the Blizzard
--- paperdoll/bag path proven by the wow-ui-sim probe and by CooldownMaster
--- on the live client -- NOT catalog-verified (review m2; see the item
--- seams note above). Fallback when that global is absent:
--- C_Item.GetItemID(ItemLocation:CreateFromEquipmentSlot(slot)) -- the
--- catalog declares C_Item.GetItemID(itemLocation) -> number
--- (ItemDocumentation.lua:550); ItemLocation:CreateFromEquipmentSlot is
--- Blizzard's own equipment-slot constructor, used all over the shipped
--- FrameXML (Blizzard_FrameXMLUtil/ItemUtil.lua:338, the Camelot
--- PaperDollFrame). The whole chain runs in one pcall (construct, lookup,
--- the empty-slot answer) and only a plain positive number is returned;
--- an empty slot yields nil.
function Compat.GetEquippedItemID(slot)
    if type(GetInventoryItemID) == "function" then
        return GetInventoryItemID("player", slot)
    end
    if C_Item and C_Item.GetItemID
        and ItemLocation and ItemLocation.CreateFromEquipmentSlot then
        local ok, id = pcall(function()
            local loc = ItemLocation:CreateFromEquipmentSlot(slot)
            return loc and C_Item.GetItemID(loc)
        end)
        local plain = ok and Compat.PlainOrNil(id)
        if type(plain) == "number" and plain > 0 then return plain end
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
--- Secrecy evidence (review m2): the catalog annotates NO SecretWhen… on
--- the C_Container/C_Item cooldown returns it does declare, and
--- GetInventoryItemCooldown is absent from the catalog entirely, so NO
--- catalog annotation backs the expected-plain reading -- it rests on the
--- wow-ui-sim probe and CooldownMaster, and the secrecy expectation is an
--- open live probe (docs/design-combat-procs.md §5.7); consumers MUST
--- route every number through PlainOrNil regardless.
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

--- The raw WeaponEnchantInfo table array of
--- C_Item.GetWeaponEnchantInfo(weaponSlot), nil where the API is absent.
--- Pinned Forever catalog: ItemDocumentation.lua:1140 (docs/api/
--- wow-addon-api-agents/skills/wow-api-items-inventory/references/
--- generated/forever.json:494); the struct (ItemDocumentation.lua:1967,
--- same catalog :688) carries hasEnchant bool, enchantType ItemEnchantType,
--- timeLeft number, charges number, enchantID number, enchantIconID number.
--- `timeLeft` is MILLISECONDS -- Blizzard's own shipped read divides it by
--- 1000 before adding it to GetTime() (Blizzard_BuffFrame/BuffFrame.lua:774-
--- 777, the Enum.WeaponSlot loop). `weaponSlot` rides Enum.WeaponSlot =
--- { MainHand = 0, OffHand = 1, Ranged = 2 } (pinned catalog enumeration,
--- same skill's forever.json:58). NO SecretWhen… annotation on the returns
--- at the pin -- expected plain, unmeasured by us; consumers MUST route
--- every field through PlainOrNil and pcall the call (Forte_Cooldown/Core/
--- Enchants.lua).
function Compat.GetWeaponEnchantInfo(weaponSlot)
    if C_Item and C_Item.GetWeaponEnchantInfo then
        return C_Item.GetWeaponEnchantInfo(weaponSlot)
    end
    return nil
end

--- The equipped item's icon (fileID) in inventory slot `invSlot`, nil
--- where the API is absent. Primary: the global GetInventoryItemTexture
--- (unit, slot) -- the Blizzard-shipped BuffFrame.lua:777 uses it on this
--- exact client, it is in the retail-baseline reference, and like
--- GetInventoryItemID/GetInventoryItemCooldown it has ZERO declarations in
--- the pinned Forever catalogs (review m2 family), so callers nil-guard
--- and fall back to GetItemIcon(GetEquippedItemID(slot)) -- the pair whose
--- GetItemIconByID half IS catalog-declared (the item seams note above).
function Compat.GetEquippedItemTexture(unit, invSlot)
    if type(GetInventoryItemTexture) == "function" then
        return GetInventoryItemTexture(unit, invSlot)
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- FX.SecretState -- the cached "are reads secret RIGHT NOW" mode switch
-- (docs/research/secrets-unknowns.md §5, ranked design change 1).
--
-- Six cheap per-type queries (`C_RestrictedActions.IsAddOnRestrictionActive`
-- over AddOnRestrictionType 0..5, NATIVE-verified on 70707 as one byte of a
-- per-type state array) plus the two zero-arg `C_Secrets.Should*BeSecret()`
-- predicates, cached in one table and recomputed on
-- `ADDON_RESTRICTION_STATE_CHANGED(type, state)`
-- (@RestrictedActionsDocumentation.lua:96) and
-- `PLAYER_REGEN_DISABLED`/`PLAYER_REGEN_ENABLED`
-- (@UnitDocumentation.lua:3884/:3890) -- the same event set the research note
-- prescribes, and the set Musca/EverAuras watch live. Refreshing is a handful
-- of zero/one-arg calls, so it runs on the event, never per value.
--
-- FIELD MEANINGS (all true / false / nil -- nil = the query is absent, raised
-- or answered with a secret value, i.e. UNKNOWN):
--   combat, encounter, challenge, pvp, map,chat  the six add-on restriction
--       types (AddOnRestrictionType 0..5).
--   cooldownsSecret  C_Secrets.ShouldCooldownsBeSecret()
--   aurasSecret      C_Secrets.ShouldAurasBeSecret()
--
-- CONSUMER LAW: this mode saves WORK (skip the numeric cooldown reads while
-- the engine says they come back secret) and labels the state in `/fx
-- status` for the launch-day evidence. It NEVER decides correctness -- the
-- field-level guard stays `Compat.PlainOrNil` at every read, because the
-- restriction is also driven by per-spell exceptions the mode cannot see
-- (docs/research/secrets-unknowns.md §2).
FX.SecretState = FX.SecretState or {}
local SecretState = FX.SecretState

-- { field, AddOnRestrictionType } -- the enum's six values, in the enum's
-- order (pinned catalog @RestrictedActionsConstantsDocumentation.lua:18).
SecretState.RESTRICTION_TYPES = {
    { field = "combat",    type = 0 },
    { field = "encounter", type = 1 },
    { field = "challenge", type = 2 },
    { field = "pvp",       type = 3 },
    { field = "map",       type = 4 },
    { field = "chat",      type = 5 },
}

--- Recompute the whole cache. `readers` is the test seam
--- ({ isActive(type)->bool, cooldownsSecret()->bool, aurasSecret()->bool });
--- production uses the Compat seams above. Every call runs in a pcall (a
--- restricted client raises; the sim does not ship C_RestrictedActions/
--- C_Secrets at all) and its result passes PlainOrNil before it is stored, so
--- a secret answer degrades to nil = unknown, never to a false "all plain".
function SecretState.Refresh(readers)
    readers = readers or {}
    local isActive = readers.isActive or Compat.IsAddOnRestrictionActive
    for _, spec in ipairs(SecretState.RESTRICTION_TYPES) do
        local active
        if isActive then
            -- `ok and PlainOrNil(v)` is NOT the idiom here: a raise makes
            -- `ok` false, `false and ...` is FALSE, and false is a perfectly
            -- good-looking "not restricted" answer. An unknown must be nil.
            local ok, value = pcall(isActive, spec.type)
            if ok then
                local plain = Compat.PlainOrNil(value)
                if plain ~= nil then active = plain and true or false end
            end
        end
        SecretState[spec.field] = active
    end
    local cbs = readers.cooldownsSecret or Compat.ShouldCooldownsBeSecret
    if cbs then
        local ok, value = pcall(cbs)
        if ok then
            local plain = Compat.PlainOrNil(value)
            if plain ~= nil then SecretState.cooldownsSecret = plain and true or false end
        end
    end
    local abs = readers.aurasSecret or Compat.ShouldAurasBeSecret
    if abs then
        local ok, value = pcall(abs)
        if ok then
            local plain = Compat.PlainOrNil(value)
            if plain ~= nil then SecretState.aurasSecret = plain and true or false end
        end
    end
    return SecretState
end

--- The one `/fx status` line: combat / encounter / cooldowns / auras. `nil`
--- in a slot is the honest "this client gives me no answer" (the wow-ui-sim
--- build ships neither C_RestrictedActions nor C_Secrets), which is itself
--- the launch-day datum the probe asks for.
function SecretState.StatusLine()
    return string.format("secret-state: combat=%s encounter=%s cooldowns=%s auras=%s",
        tostring(SecretState.combat), tostring(SecretState.encounter),
        tostring(SecretState.cooldownsSecret), tostring(SecretState.aurasSecret))
end

--- Convenience for read passes: the numeric cooldown reads are known to come
--- back secret. ONLY a plain `true` answers; unknown answers false, i.e. "do
--- not skip" -- the mode may save work, it never skips on a guess.
function SecretState.CooldownReadsAreSecret()
    return SecretState.cooldownsSecret == true
end

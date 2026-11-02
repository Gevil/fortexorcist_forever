-- Forte_Cooldown/Core/Enchants.lua
-- Weapon-enchant tracker of the cooldown engine: one timeline entry per
-- ENCHANTED WEAPON SLOT (main hand / off hand / ranged), kept beside spell
-- and item entries in the SAME Engine.entries table with the SAME entry
-- shape (name, start, duration, endTime, predicted, source, anchored) plus
-- the display tags `category` = "Buff" (the owner's ruling: an existing
-- Timeline colour, neither Timeline nor Options is touched) and `icon` (the
-- WEAPON's item texture, not an enchant graphic).
--
-- API law (owner ruling 2026-11-01, PLAN §9 item 3: the original's
-- `GetWeaponEnchantInfo` global has a replacement on Forever):
--  * `C_Item.GetWeaponEnchantInfo(weaponSlot)` -> table of WeaponEnchantInfo
--    -- pinned Forever catalog: docs/api/wow-addon-api-agents/skills/
--    wow-api-items-inventory/references/generated/forever.json:494, the
--    ItemDocumentation.lua:1140 declaration. Struct (same catalog :688 =
--    ItemDocumentation.lua:1967): `hasEnchant` bool, `enchantType`
--    ItemEnchantType, `timeLeft` number, `charges` number, `enchantID`
--    number, `enchantIconID` number.
--  * `timeLeft` is MILLISECONDS: Blizzard's own shipped read divides by
--    1000 before adding it to GetTime()
--    (Blizzard_BuffFrame/BuffFrame.lua:774-777, the
--    UpdateTemporaryEnchantmentBuffs loop over Enum.WeaponSlot). The same
--    law is applied here; `endTime = now + timeLeft / 1000`.
--  * `Enum.WeaponSlot` = { MainHand = 0, OffHand = 1, Ranged = 2 } (pinned
--    catalog enumeration, same skill's forever.json:58).
--  * `WEAPON_ENCHANT_CHANGED` -- the event that says a slot's enchant list
--    changed (poison applied, enchant burned off, zone resync; UniqueEvent,
--    no payload): same catalog :198 = ItemDocumentation.lua:1920. Module.lua
--    registers it and feeds a read pass; PLAYER_ENTERING_WORLD rides the
--    module's debounced rescan timer, the 1 Hz ReadAll net self-heals the
--    rest (an enchant burned mid-combat is caught by the next plain pass).
--
-- Secrecy model (identical to Core/Items.lua): the struct carries NO
-- SecretWhen… annotation at the pin (only SecretArguments =
-- AllowedWhenUntainted), so "these reads stay plain in combat" is the
-- expected, UNMEASURED reading -- every value rides PlainOrNil inside
-- OnReadSlot, every live call is pcall'd in ReadAll (a restricted client
-- RAISES on a read). A secret/raising read leaves the entry exactly as it
-- is: the entry keeps counting down from its last plain anchor. A plain
-- `hasEnchant == false` removes the entry SILENTLY (no ready pop -- the
-- enchant burning off is not a cooldown completing).
--
-- Duration law: weapon enchants are long (30 min - 1 h poisons/oils). The
-- bar's Max is 300 s, so a fresh 30-min entry PARKS at the right end until
-- under 5 minutes -- the original's behaviour for long cooldowns, kept.
-- A plain read reporting `timeLeft` under Engine.MIN_COOLDOWN lands the
-- window (endTime = now) so the Sweep retires it with the normal end
-- effect; `timeLeft == 0` with no entry (permanent enchant, no timer)
-- creates nothing.
--
-- Charges: poisons carried charges (the struct's `charges`). A plain
-- charges > 0 marks the entry with the engine's charge model in its
-- drained-bar shape { max = charges, current = 0, nextAt = nil }: Engine's
-- own laws exclude a charges>0 entry from the bar (it is "castable", not
-- cooling) and self-retire a full-bar entry at once -- both wrong for an
-- ACTIVE enchant whose icon must stay visible until the game says
-- `hasEnchant` is false. current = 0 keeps the icon on the bar with its
-- charge-count number (row `charges` = 0, `maxCharges` = the reported
-- count), and `0 >= max` is false, so the entry never self-sweeps: the
-- enchant reads own its lifecycle. The one residue -- a charge entry the
-- Sweep can never retire at its endTime -- is closed by ReadAll's landing
-- pass below.
--
-- Name law: the entry's DISPLAY name (`e.name`, what the Timeline prints in
-- the group string) is resolved from the plain `enchantID`: first
-- C_Spell.GetSpellInfo(enchantID).name (the enchantment's spell row -- the
-- classic enchant ids ARE spell ids, e.g. 1900 Enchant Weapon - Crusader),
-- then a ForteXorcist.Data.Items `procs` row with source == "enchant"
-- whose itemId is the effect_id (generated-file header, Forte_Items),
-- then the slot's plain label ("Main Hand Enchant" / "Off Hand Enchant" /
-- "Ranged Enchant"). Resolution is cached per id (false = "resolved: no
-- name"), so an id that resolves LATER (async spell cache) keeps the label
-- for the session -- acceptable: the slot is still identifiable, and a
-- changed name re-keys the entry cleanly.
--
-- Key law (CodeReview2 n3, 2026-11-02): the `Engine.entries` KEY is the
-- display name PLUS the slot -- `<name>#<MainHand|OffHand|Ranged>` -- while
-- `e.name` stays the bare display name. Keying by the name alone made the
-- SAME enchant on two weapon slots (one poison/oil on main hand and off
-- hand -- the dual-wield case) ONE entry: the `hasEnchant == false` /
-- sub-floor branch resolves its entry from the SLOT's state, so the earlier
-- slot's expiry landed the SHARED window and the Sweep retired the entry
-- out from under the slot that still had 28 minutes of enchant left. With a
-- slot-scoped key each slot owns its entry; `bySlot[*].entryKey` carries it.
-- Engine:Sweep pops `e.name`, so the "X ready" line and the Display's
-- `_ready` queue keep speaking the display name, never the key.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist

local Engine = FX.Cooldown.Engine
local Enchants = {}
Engine.Enchants = Enchants

Enchants.bySlot = {}  -- [slotKey] = { name = <display name>,
                       --   entryKey = <Engine.entries key, name.."#"..slotKey>,
                       --   enchantID = <plain id> }
Enchants.names = {}   -- [enchantID] = display name | false (no name known)

-- Resolved lazily (the TRINKET_SLOTS pattern, Core/Items.lua): Enum tables
-- exist at load on the real client, and a missing member degrades to the
-- documented catalog value, never to a nil slot id.
local SLOT_SPECS
local function slotSpecs()
    if not SLOT_SPECS then
        local WS = (type(_G.Enum) == "table" and _G.Enum.WeaponSlot) or {}
        SLOT_SPECS = {
            { key = "MainHand", label = "Main Hand Enchant",
                slot = WS.MainHand or 0, invSlot = _G.INVSLOT_MAINHAND or 16 },
            { key = "OffHand", label = "Off Hand Enchant",
                slot = WS.OffHand or 1, invSlot = _G.INVSLOT_OFFHAND or 17 },
            { key = "Ranged", label = "Ranged Enchant",
                slot = WS.Ranged or 2, invSlot = _G.INVSLOT_RANGED or 18 },
        }
    end
    return SLOT_SPECS
end

--- The enchant's display name for a plain enchantID, nil when nothing
--- resolves it (the caller falls back to the slot label). The C_Spell
--- lookup runs in a pcall and only a plain string leaves it (the
--- RecordCastEvent idiom -- an info table on a restricted client may raise
--- on the field read, and its fields may be secret). The Forte_Items
--- procs fallback is data-only: `source == "enchant"` rows carry the
--- effect_id as itemId (generated-file header).
function Enchants:ResolveName(enchantID, getName)
    if type(enchantID) ~= "number" then return nil end
    local hit = self.names[enchantID]
    if hit ~= nil then return hit or nil end
    local name
    if getName then
        -- pcall: the seam runs the live C_Spell.GetSpellInfo.
        local ok, resolved = pcall(getName, enchantID)
        local plain = ok and FX.Compat.PlainOrNil(resolved)
        if type(plain) == "string" and plain ~= "" then name = plain end
    end
    if not name then
        local data = FX.Data and FX.Data.Items
        local procs = data and data.procs
        if procs then
            for _, row in ipairs(procs) do
                if row.source == "enchant" and row.itemId == enchantID then
                    name = row.name
                    break
                end
            end
        end
    end
    self.names[enchantID] = name or false
    return name
end

--- The WEAPON's icon fileID for an inventory slot: Compat seam chain
--- GetInventoryItemTexture -> C_Item.GetItemIconByID(GetInventoryItemID).
--- GetInventoryItemTexture is not in the pinned generated catalogs (zero
--- declarations -- the GetInventoryItemID family, review m2; the
--- Blizzard-shipped BuffFrame.lua:777 uses it on this exact client), so the
--- seam is nil-guarded and the C_Item pair is the catalog-declared
--- fallback. Every call pcall'd; only a plain value leaves.
local function resolveIcon(invSlot, getTexture, getEquippedID, getIcon)
    if getTexture then
        local ok, tex = pcall(getTexture, "player", invSlot)
        local plain = ok and FX.Compat.PlainOrNil(tex)
        if plain ~= nil then return plain end
    end
    if getEquippedID and getIcon then
        local ok, itemID = pcall(getEquippedID, invSlot)
        if ok and FX.Compat.PlainOrNil(itemID) ~= nil then
            local ok2, icon = pcall(getIcon, itemID)
            local plain = ok2 and FX.Compat.PlainOrNil(icon)
            if plain ~= nil then return plain end
        end
    end
    return nil
end

--- Land an entry whose window has lapsed (ReadAll's landing pass / the
--- sub-floor read): the charge snapshot model is dropped (Sweep's charge
--- branch can never retire it -- nextAt nil, 0 >= max false) and the
--- window is landed so the NEXT Sweep retires it with the normal end
--- effect. Keeps the start + duration == endTime invariant.
local function landEntry(e, now)
    e.charges = nil
    e.duration = math.max(0.001, now - e.start)
    e.endTime = e.start + e.duration
end

--- One slot's live read result (the raw WeaponEnchantInfo table; every
--- field rides PlainOrNil HERE, so no caller can forget). A plain, real
--- enchant (hasEnchant true, timeLeft >= MIN_COOLDOWN) anchors the slot's
--- entry; a plain hasEnchant false removes it silently; a secret/absent
--- field changes nothing. Returns "anchored" | "cleared" | "secret" |
--- "ignored".
function Enchants:OnReadSlot(spec, info, now, getName, getTexture, getEquippedID, getIcon)
    local state = self.bySlot[spec.key]
    local entryKey = state and state.entryKey
    if info == nil then return "ignored" end

    local has = FX.Compat.PlainOrNil(info.hasEnchant)
    if type(has) ~= "boolean" then return "secret" end
    if not has then
        -- Enchant gone (burned, replaced, weapon un-equipped): the slot
        -- has nothing to show. Silent removal -- Engine.entries[n] = nil
        -- keeps the name out of the Sweep's pop list entirely. The key is
        -- SLOT-scoped (n3), so this removes THIS slot's entry and leaves a
        -- same-enchant entry on another slot alive.
        if entryKey then Engine.entries[entryKey] = nil end
        self.bySlot[spec.key] = nil
        return "cleared"
    end

    local timeLeftMs = FX.Compat.PlainOrNil(info.timeLeft)
    if type(timeLeftMs) ~= "number" then return "secret" end
    local remaining = timeLeftMs / 1000
    if remaining < Engine.MIN_COOLDOWN then
        -- Under the tracking floor: a permanent enchant (timeLeft 0 with
        -- no entry) creates nothing; a lapping entry is landed so the
        -- Sweep ends it with its normal effect. The landing is a slot-local
        -- operation -- with the shared name-key of review n3 it landed the
        -- OTHER slot's window too.
        local e = entryKey and Engine.entries[entryKey]
        if e then landEntry(e, now) end
        return "ignored"
    end

    local id = FX.Compat.PlainOrNil(info.enchantID)
    local name = self:ResolveName(id, getName) or spec.label
    local key = name .. "#" .. spec.key
    if entryKey and entryKey ~= key then
        Engine.entries[entryKey] = nil -- the slot re-keyed: retire the old
    end

    local e = Engine.entries[key] or { name = name }
    -- The key carries the slot; the entry keeps the bare display name.
    e.name = name
    e.start, e.duration, e.endTime = now, remaining, now + remaining
    e.predicted, e.source, e.anchored = false, "read", true
    e.category = "Buff"
    e.icon = resolveIcon(spec.invSlot, getTexture, getEquippedID, getIcon)
    local charges = FX.Compat.PlainOrNil(info.charges)
    if type(charges) == "number" and charges > 0 then
        e.charges = { max = charges, current = 0, nextAt = nil }
    else
        e.charges = nil
    end
    Engine.entries[key] = e
    self.bySlot[spec.key] = { name = name, entryKey = key, enchantID = id }
    return "anchored"
end

--- One read pass over the three weapon slots. `readers` overrides the
--- seams for tests ({ read = fn(weaponSlot) -> info, getName =
--- fn(enchantID) -> name, getTexture = fn(unit, invSlot) -> fileID,
--- getEquippedID = fn(invSlot) -> itemID, getIcon = fn(itemID) -> fileID });
--- production rides the FX.Compat seams. Every live read pcall'd: a raise
--- leaves that slot's entry exactly as it is. Ends with the landing pass:
--- a charge-model entry whose window has lapsed (the reads went secret,
--- so no plain read landed it) is landed for the next Sweep -- the charge
--- snapshot shape never self-retires (file header).
function Enchants:ReadAll(now, readers)
    now = now or GetTime()
    readers = readers or {}
    local read = readers.read or (FX.Compat and FX.Compat.GetWeaponEnchantInfo)
    local getName = readers.getName
        or (function()
            if C_Spell and C_Spell.GetSpellInfo then
                return function(id)
                    local info = C_Spell.GetSpellInfo(id)
                    return info and info.name
                end
            end
            return nil
        end)()
    local getTexture = readers.getTexture
        or (FX.Compat and FX.Compat.GetEquippedItemTexture)
    local getEquippedID = readers.getEquippedID
        or (FX.Compat and FX.Compat.GetEquippedItemID)
    local getIcon = readers.getIcon
        or (FX.Compat and FX.Compat.GetItemIcon)
    if read then
        for _, spec in ipairs(slotSpecs()) do
            local ok, info = pcall(read, spec.slot)
            if ok then
                self:OnReadSlot(spec, info, now, getName,
                    getTexture, getEquippedID, getIcon)
            end
        end
    end
    for _, spec in ipairs(slotSpecs()) do
        local st = self.bySlot[spec.key]
        local e = st and st.entryKey and Engine.entries[st.entryKey]
        if e and e.charges and now >= e.endTime then
            landEntry(e, now)
        end
    end
end

--- Live entry count for `/fx status` (the entry count IS the state: there
--- is no tracked set -- a slot has an entry exactly while it has a timed
--- enchant).
function Enchants:Count()
    local n = 0
    for _, spec in ipairs(slotSpecs()) do
        local st = self.bySlot[spec.key]
        if st and st.entryKey and Engine.entries[st.entryKey] then n = n + 1 end
    end
    return n
end

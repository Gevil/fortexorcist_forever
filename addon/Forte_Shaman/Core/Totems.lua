-- addon/Forte_Shaman/Core/Totems.lua
-- FX.Shaman: the Shaman's four elemental totem slots as Spell Timer rows.
--
-- The ported law, /tmp/fxref/Forte_Class/Shaman/Shaman.lua:
--   :76   index_to_group = {"TotemFire","TotemEarth","TotemWater","TotemAir"}
--         -- slot 1 Fire, 2 Earth, 3 Water, 4 Air: the same slot numbers the
--         -- client stamps in Blizzard_FrameXMLBase/Constants.lua:224-229
--         -- (MAX_TOTEMS = 4, FIRE/EARTH/WATER/AIR_TOTEM_SLOT = 1..4), which is
--         -- also why the element label is the row's group label: the four
--         -- elements are the four groups.
--   :77-93 SH_TotemUpdate(index) -- ONE ROW PER SLOT:
--         * GetTotemInfo(index) -> haveTotem, name, startTime, duration, icon
--           (the catalog's reader, Blizzard_APIDocumentationGenerated/
--           TotemDocumentation.lua:59; Blizzard's own consumers read it the
--           same way and derive the window as `startTime + duration`:
--           Blizzard_CooldownViewer/CooldownViewerItemData.lua:836-843,
--           Blizzard_UnitFrame/Mainline/TotemFrame.lua:29-38).
--         * a new totem in a slot that already shows one REMOVES the old row
--           (`ST.ST:remove(i)`, :84) before inserting the new one: the slot's
--           row is replaced IN PLACE, never stacked.
--         * an empty slot (the totem was destroyed, or it just expired) fades
--           the row: `ST:Fade(i, (st[i][1] - GetTime() < 0.75) and 2 or 3)`
--           (:87) -- a totem that was expiring by itself within 0.75 s fades
--           out gently (FADING), one killed early gets the red removed band
--           (REMOVE).
--   :96-104 the RegisterDelayedLoadEvent seed: read every slot once at load.
--
-- Forever law: `GetTotemInfo` is classified `SecretWhenTotemSlotSecret`
-- (TotemDocumentation.lua:62), so EVERY return may be a secret value; each one
-- goes through FX.Compat.PlainOrNil before it is compared or added (the
-- secret-value law). A sealed read answers NOTHING, and no answer is not
-- permission to touch the display: the tracker keeps whatever row it already
-- has -- the cast prediction Forte_Timer's cast spine put on the panel from
-- the shaman's own cast of the totem spell -- and mutates no row at all.
--
-- Row plumbing (addon/Forte_Timer/): the window arrives through
-- Core/Rows.lua's aura-fact path `InsertFromAura`, which already owns the
-- adopt/extend/refresh law for a fact that lands on a cast prediction; the
-- element token is the row's targetKey, so Core/Rows.lua:IdFor gives one group
-- per element and UI/Rows.lua labels that group with it.
ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
FX.Shaman = FX.Shaman or {}

-- --------------------------------------------------------------- the tracker --
local TotemTracker = {}
TotemTracker.__index = TotemTracker
FX.Shaman.TotemTracker = TotemTracker

-- Shaman.lua:76 + Constants.lua:224-229: slot -> element. The token doubles as
-- the row's targetKey (Laws.RowKey's target half) and as the group label.
local ELEMENTS = { "Fire", "Earth", "Water", "Air" }
local DEFAULT_SLOTS = 4        -- Constants.lua:224 MAX_TOTEMS (the 2012 loop bound too)
local FADE_LEAD = 0.75         -- Shaman.lua:87

local function canonicalName(name)
    if type(name) ~= "string" then return name end
    -- H1 (docs/class-port.md): the client's name is localized on a localized
    -- client; the data and the row key are the English name.
    local Locale = FX.Locale
    if Locale and Locale.CanonicalName then return Locale.CanonicalName(name) end
    return name
end

--- opts.rows: the row table the windows go into (FX.Timer.Rows in the game;
--- the tests inject their own). opts.now: the clock seam. opts.readSlot:
--- the slot-reader seam -- nil runs the real GetTotemInfo; tests inject a
--- deterministic one (the FX.Timer.Reconcile.readers convention).
function FX.Shaman.NewTotemTracker(opts)
    opts = opts or {}
    local self = setmetatable({
        rows = opts.rows,
        now = opts.now,
        readSlot = opts.readSlot,
        slots = {},          -- slot -> { name, expireAt }: what we show for it
        secretReads = 0,     -- sealed reads: counted, never acted on
        slotCount = 0,
    }, TotemTracker)
    return self
end

function TotemTracker:Time()
    local f = self.now
    if type(f) == "function" then return f() end
    return GetTime()
end

--- GetNumTotemSlots is catalog-declared (TotemDocumentation.lua:20) and is
--- absent from the simulator's frame of the API, so it is nil-guarded; the
--- fallback is the client's own MAX_TOTEMS.
function TotemTracker:SlotCount()
    if self.slotCount > 0 then return self.slotCount end
    local n
    if type(_G.GetNumTotemSlots) == "function" then
        local ok, v = pcall(_G.GetNumTotemSlots)
        n = ok and FX.Compat.PlainOrNil(v)
    end
    if type(n) ~= "number" or n < 1 then n = DEFAULT_SLOTS end
    self.slotCount = math.floor(n)
    return self.slotCount
end

--- The seal gate. ONLY a plain true answers "sealed": a C_Secrets query this
--- build does not ship answers nil and nil is not sealed (the same consumer
--- law Core/Rows.lua:identityIsSealed applies to UnitGUID; the sim does not
--- ship ShouldTotemSlotBeSecret at all). A raising query is sealed -- the
--- Core/SecretState.lua raise law.
function TotemTracker:SlotIsSealed(slot)
    local query = _G.C_Secrets and _G.C_Secrets.ShouldTotemSlotBeSecret
    if type(query) ~= "function" then return false end
    local ok, sealed = pcall(query, slot)
    if not ok then return true end
    return FX.Compat.PlainOrNil(sealed) == true
end

--- nil == the read tells us NOTHING (sealed, raising, absent): callers must
--- change no row. A table is the slot's state:
---   { present = false }                                 empty slot
---   { present = true, name, expireAt, total }           live totem
function TotemTracker:ReadSlot(slot)
    if type(self.readSlot) == "function" then
        local ok, record = pcall(self.readSlot, slot)
        if not ok then return nil end
        return record
    end
    if self:SlotIsSealed(slot) then return nil end
    local reader = _G.GetTotemInfo
    if type(reader) ~= "function" then return nil end
    -- (haveTotem, totemName, startTime, duration, icon, modRate, spellID)
    local ok, have, name, start, duration = pcall(reader, slot)
    if not ok then return nil end
    have = FX.Compat.PlainOrNil(have)
    name = FX.Compat.PlainOrNil(name)
    start = FX.Compat.PlainOrNil(start)
    duration = FX.Compat.PlainOrNil(duration)
    if have == nil and name == nil then return nil end
    if have == false or type(name) ~= "string" or name == "" then
        return { present = false }
    end
    if type(duration) ~= "number" or duration <= 0 then
        -- No window to draw: the row table's insert law refuses a
        -- non-positive total, so this read tells us nothing either.
        return nil
    end
    -- CooldownViewerItemData.lua:841: expirationTime = startTime + duration.
    -- A nil (sealed) start is read as "started now", not as the source's `0`
    -- -- the row's expire time rides the GetTime clock.
    local base = (type(start) == "number" and start) or self:Time()
    return { present = true, name = name, expireAt = base + duration,
             total = duration }
end

--- SH_TotemUpdate (`Shaman.lua:77-93`). `slot` is the PLAYER_TOTEM_UPDATE
--- payload (a possible secret number: classified before it is compared).
function TotemTracker:OnTotemUpdate(slot)
    slot = FX.Compat.PlainOrNil(slot)
    if type(slot) ~= "number" then return "ignored" end
    slot = math.floor(slot)
    if slot < 1 or slot > self:SlotCount() then return "ignored" end
    local rows = self.rows
    if not rows then return "no-rows" end

    local record = self:ReadSlot(slot)
    if record == nil then
        self.secretReads = self.secretReads + 1
        return "sealed"                      -- keep the row we have
    end

    local element = ELEMENTS[slot] or ("Totem" .. slot)
    local known = self.slots[slot]
    local now = self:Time()

    if record.present ~= true then
        -- The slot is empty: the totem is destroyed / expired. Fade law
        -- Shaman.lua:87 verbatim (FADING = it was expiring anyway).
        if known then
            local row = rows:Find(known.name, element)
            if row then
                rows:Fade(row, (row.expireAt - now < FADE_LEAD)
                    and FX.Timer.Laws.FADING or FX.Timer.Laws.REMOVE, now)
            end
            self.slots[slot] = nil
            return "cleared"
        end
        return "idle"
    end

    local name = canonicalName(record.name)
    if type(record.expireAt) ~= "number" or type(record.total) ~= "number"
        or record.total <= 0 then
        return "no-window"
    end

    -- Shaman.lua:83-86: the slot already showed a totem of a DIFFERENT spell
    -- -> its row goes now (ST.ST:remove(i)); the element group keeps exactly
    -- one row. Same spell = no removal: InsertFromAura's own adopt/extend/
    -- refresh law refreshes that row in place.
    if known and known.name ~= name then
        local old, index = rows:Find(known.name, element)
        if old then rows:removeAt(index) end
    end

    -- F-B (the totem dedupe, PLAN §11.1): the shaman's own cast of this totem
    -- spell put a PREDICTION row on the panel a moment ago, keyed by the cast's
    -- target ("none"), which the slot law above can not see (`rows:Find(name,
    -- element)` keys on the element). One totem, one row: hand the slot over --
    -- Forte_Timer's spine retires its own prediction of this spell, the
    -- Shaman.lua:84 `ST.ST:remove(i)` law, and the slot's row is what stands.
    local casts = FX.Timer and FX.Timer.Casts
    if casts and casts.RetireOwnedRows then
        casts:RetireOwnedRows(name, element, now)
    end

    local row, verdict = rows:InsertFromAura(name, element, record.expireAt,
        record.total, nil, nil, nil, now)
    if not row then return "no-window" end
    self.slots[slot] = { name = name, expireAt = record.expireAt }
    if known and known.name ~= name then return "replaced" end
    if known then return "refreshed" end
    return verdict == "inserted" and "inserted" or "refreshed"
end

--- True while this tracker is drawing `name` in one of its slots -- the answer
--- Forte_Timer's cast spine asks for before it draws a row of its own (the
--- `DeclareRows` probe). A slot the engine sealed is NOT this: the tracker
--- keeps the row it has and knows nothing new, and a totem the player cast 0.2
--- s ago has the prediction as its only in-combat signal.
function TotemTracker:IsShowing(name)
    if type(name) ~= "string" then return false end
    for slot = 1, self:SlotCount() do
        local known = self.slots[slot]
        if known and known.name == name then return true end
    end
    return false
end

--- The load seed: Shaman.lua:96-104 (RegisterDelayedLoadEvent) reads every
--- slot once when the module loads.
function TotemTracker:SeedAll()
    for slot = 1, self:SlotCount() do self:OnTotemUpdate(slot) end
end

function TotemTracker:StatusLine()
    local shown = {}
    for slot = 1, self:SlotCount() do
        local known = self.slots[slot]
        shown[#shown + 1] = string.format("%s=%s",
            string.lower(ELEMENTS[slot] or tostring(slot)),
            known and string.format("%s(%.1fs)", known.name,
                math.max(0, known.expireAt - self:Time())) or "none")
    end
    return "Shaman totems: " .. table.concat(shown, " ")
        .. (self.secretReads > 0 and string.format(" | sealed reads %d", self.secretReads) or "")
end

-- ------------------------------------------------------------------ module --
local M = {}
FX.Shaman.Totems = M

function M:Tracker()
    if self.tracker then return self.tracker end
    self.tracker = FX.Shaman.NewTotemTracker({
        rows = FX.Timer and FX.Timer.Rows,
    })
    return self.tracker
end

--- The event frame + the tracker. Frame and tracker are built for every
--- class (the tracker is inert state, and a real PLAYER_TOTEM_UPDATE is the
--- only thing that can move a row); the REGISTRATIONS are the shaman gate, so
--- a non-shaman is wired to nothing. Created inside OnEnable -- the event law
--- (docs/engine-notes.md; Core/Init.lua), never at file load.
function M:EnableEvents()
    if self._eventsEnabled then return end
    local f = self._eventFrame
    if not f then
        f = CreateFrame("Frame")
        self._eventFrame = f
    end
    -- The payload is the slot index (the catalog's PLAYER_TOTEM_UPDATE row,
    -- Blizzard_APIDocumentationGenerated/SpellBookDocumentation.lua:872-876;
    -- Blizzard_CooldownViewer/CooldownViewer.lua:1792-1796 reads it the same
    -- way). OnEvent gets (frame, event, ...): swallow the frame.
    f:SetScript("OnEvent", function(_, event, a1) M:OnEvent(event, a1) end)
    f:RegisterEvent("PLAYER_TOTEM_UPDATE")
    -- The seed pass at world entry (the Shaman.lua:96-104 port; Blizzard's
    -- own TotemFrame.lua:5-6 seeds on the same pair).
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    -- Leaving wipes the tracker's slot state (Forte_Timer/Module.lua:121-129
    -- clears the row table it trails).
    f:RegisterEvent("PLAYER_LEAVING_WORLD")
    self._eventsEnabled = true
    -- F-B (the totem dedupe): the same wiring that lets the slots move rows is
    -- what tells Forte_Timer's cast spine those rows are spoken for.
    self:DeclareRows()
end

--- The totem-summon spells of THIS CLASS'S OWN generated list: every English
--- data row whose name is a `… Totem` (the element slots' windows -- `Earth
--- Shock`, `Call of Flames`, `Astral Shift` are not; `Magma Totem`, `Stoneskin
--- Totem`, `Mudfish Totem` are). The data file is the source, never a hand list
--- (AGENTS.md: spell names/ids come from the generated data), and the list
--- rides every future generator run.
function M:SlotSpellNames()
    local names = {}
    local data = FX.Data and FX.Data.Shaman
    if type(data) ~= "table" then return names end
    for _, row in pairs(data) do
        local name = (type(row) == "table") and row.name or nil
        if type(name) == "string" and string.find(name, "Totem%d*$") then
            names[#names + 1] = name
        end
    end
    table.sort(names)
    return names
end

--- Tell Forte_Timer's cast spine which windows THIS module draws, so one
--- signal of a totem (the player's own cast, the second the client's slot
--- state) does not put two rows on the panel: while a slot of the tracker shows
--- the spell, the spine draws nothing (`Casts:DeclareOwnedRows`,
--- Forte_Timer/Core/Casts.lua). The answer the spine asks is the tracker's
--- CURRENT one, read through `self.tracker`, so a tracker being replaced needs
--- no re-declaration.
function M:DeclareRows()
    local casts = FX.Timer and FX.Timer.Casts
    if not casts or not casts.DeclareOwnedRows then return 0 end
    local self_ = self
    return casts:DeclareOwnedRows(self:SlotSpellNames(), "Shaman",
        function(name)
            local t = self_.tracker
            return t ~= nil and t:IsShowing(name) or false
        end)
end

--- The mirror: a shaman who stops being one (Core's class-change path) stops
--- gating the casts of the class he is not.
function M:UndeclareRows()
    local casts = FX.Timer and FX.Timer.Casts
    if casts and casts.UndeclareOwnedRows then
        casts:UndeclareOwnedRows("Shaman")
    end
end

function M:DisableEvents()
    local f = self._eventFrame
    if f and self._eventsEnabled then
        if f.UnregisterEvent then
            f:UnregisterEvent("PLAYER_TOTEM_UPDATE")
            f:UnregisterEvent("PLAYER_ENTERING_WORLD")
            f:UnregisterEvent("PLAYER_LEAVING_WORLD")
        end
        f:SetScript("OnEvent", nil)
    end
    self:UndeclareRows()
    self._eventsEnabled = false
end

function M:OnEvent(event, a1)
    if event == "PLAYER_TOTEM_UPDATE" then
        local verdict = self:Tracker():OnTotemUpdate(a1)
        if verdict == "inserted" or verdict == "replaced" then
            -- A new row in: one synchronous kick (the Module.lua:514 law --
            -- the ticker paints it within 0.04 s, the kick makes it land with
            -- the event that caused it).
            local module = FX.Timer and FX.Timer.Module
            if module and module.Kick then module:Kick() end
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        self:Tracker():SeedAll()
    elseif event == "PLAYER_LEAVING_WORLD" then
        self.tracker = nil
    end
end

function M:OnEnable()
    -- The whole wiring is shaman-only (the Forte_Hunter/Core/Tools.lua:467
    -- gate): a login of any other class builds no frame at all.
    if FX._playerClass ~= "SHAMAN" then return end
    self:EnableEvents()
end

--- Core FX.RefreshPlayerClass notification: the registrations follow the
--- class (the Forte_Hunter/Core/Tools.lua:455-462 shape).
function M:OnClassChanged(classFile)
    if classFile == "SHAMAN" then
        self:EnableEvents()
    else
        self:DisableEvents()
    end
end

--- One line for /fx status (the module prints; the Core loop calls).
function M:StatusLine()
    if not self.tracker then
        return "Shaman totems: idle (no tracker"
            .. (self._eventsEnabled and ", events on" or ", events off") .. ")"
    end
    return self.tracker:StatusLine()
end

function M:Status()
    FX.Print(M:StatusLine())
end

FX.RegisterModule("Shaman", M)

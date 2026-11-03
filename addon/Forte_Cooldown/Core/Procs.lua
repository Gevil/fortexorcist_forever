-- Forte_Cooldown/Core/Procs.lua
-- Proc tracker of the cooldown engine: one timeline entry per ITEM/WEAPON
-- PROC internal cooldown (the ICD), put on the bar the moment one of the
-- proc's auras is SEEN on the player. Off by default: the feature is the
-- `Cooldown.Procs` switch (docs/design-combat-procs.md P-B), and its data
-- add-on is load-on-demand, so a session that never switches it on parses
-- none of the 400 proc rows (docs/perf.md §4 fix 1, PLAN §11.1 H7).
--
-- WHAT AN ICD ENTRY IS. A proc has no cast to predict from (it fires off a
-- hit, so there is no UNIT_SPELLCAST_SUCCEEDED anchor -- docs/item-procs.md
-- "Caveats", the generated file's `trackable = "buff-window"` law), so there
-- is no spell to put on the bar. What the bar can show is the *internal*
-- cooldown the proc rides: the generated data's `icdMs` (docs/research/
-- forever-data-gaps.md G2: proc.icd_ms, 51 rows on this pin, 9 confirmed by
-- the 70707 store's AuraOptions.ICDMs). Seeing the proc buff is the fact
-- "the proc fired"; `icdMs` is the length. So the entry is the original
-- addon's `CD:AddHiddenCooldown(item, buff, sec)`
-- (/tmp/fxref/Forte_Cooldown/Forte_Cooldown.lua:1636-1693, the trinket-ICD
-- list `docs/class-port.md` S11 calls not portable) rebuilt on data instead
-- of on a hand-typed list -- a bar that runs `icdMs` from the proc and pops
-- ready when the proc may fire again.
--
-- THE TWO SEEN-ROUTES (the design's §3 channels; nothing else is trusted):
--  1. THE OUT-OF-COMBAT AURA SWEEP (`Scan`). `C_UnitAuras.GetUnitAuras
--     ("player", "HELPFUL")` lists the player's buffs, and `AuraData.spellId`
--     is the join key -- an ID, so no name/locale dependency (docs/
--     localization.md). Every field read is pcall'd and passes PlainOrNil:
--     the bulk list is declared `ConditionalSecretContents`, the aura getters
--     `SecretWhenUnitAuraRestricted` + `RequiresNonSecretAura`, and a sealed
--     read on this engine RAISES rather than returning nil
--     (docs/research/secrets-unknowns.md §2, Forte_Timer/Core/Reconcile.lua
--     "THE GATE" -- the same gate is `Procs:Gates()` here: the cached
--     aura-secrecy mode AND `InCombatLockdown`, because in combat a nil from
--     a sealed read can not be told from "no such aura", and an invented
--     absence must never cancel a live ICD window).
--  2. THE_AURA EVENTS (`OnUnitAura`). `UNIT_AURA` is
--     SecretWhenAurasRestricted and its payload is `unitTarget,
--     UnitAuraUpdateInfo{isFullUpdate, addedAuras, ...}`
--     (UnitAuraDocumentation.lua:644 / UnitConstantsDocumentation.lua:55) --
--     the generated item data's own law: "in combat watch aura
--     appear/disappear events only". So this is the in-combat half: the
--     pcall'd `spellId` of each `addedAuras` entry, and only a PLAIN id
--     speaks. A secret payload says nothing at all.
--  Both routes feed ONE rising-edge model (`Procs.seen`): an entry is created
--  when a proc aura goes absent -> present, and the entry is then driven by
--  the clock, never by another read. The design's gate-container /
--  AddAuraSound channels (§3.2/§3.3, the P-C/P-D probes) are NOT here: their
--  evidence is other addons' claims about item-source proc IDs that nobody
--  has exercised, and Q3 keeps the in-combat proc work behind the launch-day
--  probes (PLAN §11.1 rulings).
--
-- WHAT A READ MAY NOT DO. No number of an aura read ever reaches a widget
-- (docs/design-combat-procs.md §4 hard rule, docs/aura-secret-display.md):
-- the window's LENGTH is `icdMs` from the data and its START is GetTime() at
-- the edge -- both plain by construction. `entry.predicted = true` and
-- `source = "proc"`: a proc window is engine-inferred, never read-certified
-- (`anchored` is never set), so the Engine's read ladder leaves it alone and
-- `Sweep` retires it at its endTime with the normal ready pop.
--
-- The entry rides the SAME Engine.entries table with the SAME entry shape
-- (Core/Engine.lua header) plus the display tags `category = "Item"` (the
-- Timeline's ColourItem row) and `icon`. The KEY is `<data name>#<buffId>`
-- (the Core/Enchants.lua n3 law): the same item NAME carries several proc
-- auras (Signet Ring of the Bronze Dragonflight carries Timeworn Shot AND
-- Timeworn Strike across ten ids), and `Sweep` pops `e.name`, so the pop, the
-- splash and FX_COOLDOWN_READY keep speaking the display name, never the key.
--
-- Data: `ForteXorcist.Data.ItemProcs.procs` (the load-on-demand add-on
-- Forte_ItemProcs, pulled in at the first enable through
-- `FX.LoadAddOnOnDemand`) plus the always-loaded
-- `ForteXorcist.Data.Items.enchantProcs` (the 5 weapon-enchant proc rows --
-- the same `icdMs` law; Forte_Cooldown/Core/Enchants.lua owns their *timers*,
-- this owns their proc ICDs). Absent data tracks nothing: the scan is a
-- no-op, never an error.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist

local Engine = FX.Cooldown.Engine
local Procs = {}
Engine.Procs = Procs

Procs.enabled = false
Procs.tracked = {}   -- [key] = { key, name, buffId, itemId, source, icd, icon }
Procs.byBuff = {}    -- [spellId] = { tracked row, ... } (a buff id can ride
                     -- several items: the shared-proc-aura rows)
Procs.seen = {}      -- [spellId] = the frame time the aura was last seen plain
                     -- (the rising-edge model; cleared by the falling edge,
                     -- by Enable and by Rebuild)
-- Counted seams, printed by /fx status: the launch-day evidence for "which
-- seen-route is real on the live client, and how often is it sealed".
Procs.counts = { reads = 0, plain = 0, secret = 0, raised = 0,
    edges = 0, added = 0, events = 0, skipped = 0 }
--- The honest reach of the two seen-routes, printed on the `/fx status`
--- gate row (code-review-5 m10). There is NO party/raid half of this feed to
--- alias to a wider scan: the event route rides the Module's
--- `RegisterUnitEvent("UNIT_AURA", "player")` (Module.lua -- the player's
--- own aura list) and the sweep route is `GetUnitAuras("player", "HELPFUL")`
--- (`LiveReaders` below). Reading the counters below as party/raid evidence
--- is the misreading this string exists to block; widening the feed (a
--- party-unit registration + per-unit sweeps) is a design step, not a
--- documentation one (docs/design-combat-procs.md §3 channels).
Procs.coverage = "self only"

-- The injectable seams (the tests script them; the live defaults are below).
Procs.readers = nil
Procs.inCombat = nil

local function plain(v) return FX.Compat.PlainOrNil(v) end

local function TitleCase(classFile)
    if not classFile then return nil end
    return classFile:sub(1, 1):upper() .. classFile:sub(2):lower()
end

--- The mythicsim class token for the current class ("ClassHunter"); nil for
--- an unknown class, which lets every `classAllowlist` through (the
--- Core/Items.lua law: an unclassified player filters nothing).
local function classToken()
    local c = FX._playerClass
    return c and ("Class" .. TitleCase(c))
end

local function classAllows(row, token)
    local al = row.classAllowlist
    if not al or not token then return true end
    for _, t in ipairs(al) do
        if t == token then return true end
    end
    return false
end

--- THE GATE (the Reconcile.lua law). True when the sweep must not read an
--- aura: the cached aura-secrecy mode answering a plain `true`, or the
--- player being in combat (`InCombatLockdown` -- in combat the read is
--- sealed and a nil cannot be told from a seal). The mode's nil means "this
--- client gives me no answer", which is not a reason to skip work.
function Procs:Gates()
    local SS = FX.SecretState
    if SS and SS.aurasSecret == true then return true end
    local probe = self.inCombat
    if probe == nil then probe = InCombatLockdown end
    if type(probe) == "function" then
        local ok, combat = pcall(probe)
        if ok and plain(combat) then return true end
    end
    return false
end

--- The hoisted AuraData field reader (docs/perf.md §4 fix 4's shape: a
--- module-scope function handed the aura, so the sweep allocates no closure
--- per read). Reading a field of a SEALED proxy raises -- the caller's pcall
--- is the classifier, not a formality.
local function readSpellID(aura)
    return aura.spellId
end

--- The payload's `addedAuras` field, hoisted for the same reason (docs/perf.md
--- §4 fix 4): the event pass hands this to pcall with the payload as its
--- argument, so the pass allocates no closure per aura change.
local function readAddedAuras(info)
    return info.addedAuras
end

--- The counted, pcall'd bulk read. Returns (list, "ok"|"empty") when the
--- client ANSWERED (an empty/absent list is the "no buffs" fact the falling
--- edge needs), or (nil, "raise"|"secret"|"absent"|"absent-api") when it gave
--- no answer -- and "no answer" changes NOTHING (a seal is not an absence:
--- inventing one would cancel a running ICD window).
local function callBulk(self, fn)
    if type(fn) ~= "function" then return nil, "absent-api" end
    self.counts.reads = self.counts.reads + 1
    local okCall, list = pcall(fn, "player", "HELPFUL")
    if not okCall then
        self.counts.raised = self.counts.raised + 1
        return nil, "raise"
    end
    local iss = _G.issecretvalue
    if iss and iss(list) then
        self.counts.secret = self.counts.secret + 1
        return nil, "secret"
    end
    if list == nil then
        self.counts.plain = self.counts.plain + 1
        return nil, "empty"
    end
    if type(list) ~= "table" then
        self.counts.secret = self.counts.secret + 1
        return nil, "secret"
    end
    self.counts.plain = self.counts.plain + 1
    return list, "ok"
end

--- The proc icon: the item's own texture for an item row (the Core/Items.lua
--- `icon` tag; `nil` leaves the Timeline's spell-icon resolution, which has
--- nothing to resolve for an item name -- an item icon is the honest icon).
--- Enchant rows carry the enchant effect_id as itemId (the generated-file
--- law: "never match them against bag item ids"), so they get no icon.
local function resolveIcon(row)
    if row.source == "enchant" then return nil end
    local getIcon = FX.Compat and FX.Compat.GetItemIcon
    if type(row.itemId) ~= "number" or type(getIcon) ~= "function" then return nil end
    local ok, icon = pcall(getIcon, row.itemId)
    return ok and plain(icon) or nil
end

--- Rebuild the watched set from the loaded data. Rows qualify on a plain
--- numeric `buffId` (the aura's spell id -- the join key of both seen-routes)
--- and a plain `icdMs` whose seconds clear Engine.MIN_COOLDOWN (a 200 ms
--- Timeworn prock is GCD-band noise by the same law that keeps 1-3 s potion
--- categories out of Core/Items.lua). Returns the row count.
function Procs:Build()
    wipe(self.tracked)
    wipe(self.byBuff)
    wipe(self.seen)
    local data = FX.Data and FX.Data.ItemProcs
    local items = FX.Data and FX.Data.Items
    local token = classToken()
    local n = 0
    local function add(list)
        for _, row in ipairs(list or {}) do
            local buffID = plain(row.buffId)
            local icdMs = plain(row.icdMs)
            if type(buffID) == "number" and type(icdMs) == "number"
                and icdMs / 1000 >= Engine.MIN_COOLDOWN
                and type(row.name) == "string" and classAllows(row, token) then
                local key = row.name .. "#" .. buffID
                if not self.tracked[key] then
                    self.tracked[key] = {
                        key = key, name = row.name, buffId = buffID,
                        itemId = row.itemId, source = row.source,
                        icd = icdMs / 1000, icon = resolveIcon(row),
                    }
                    local rows = self.byBuff[buffID]
                    if not rows then rows = {} self.byBuff[buffID] = rows end
                    rows[#rows + 1] = self.tracked[key]
                    n = n + 1
                end
            end
        end
    end
    add(data and data.procs)             -- load-on-demand (Forte_ItemProcs)
    add(items and items.enchantProcs)    -- always-loaded (Forte_Items)
    return n
end

--- The seen edge: start the ICD window of every watched row that rides the
--- PLAIN spell id `buffID`. A window already running is NOT restarted: the
--- design's edge is the proc's *appearance*, and a refresh of the aura is not
--- a second proc (the ICD by definition runs from the proc, not from the
--- aura's refresh). Returns the number of entries created.
function Procs:OnProcSeen(buffID, now)
    local rows = type(buffID) == "number" and self.byBuff[buffID] or nil
    if not rows then return 0 end
    local created = 0
    for _, t in ipairs(rows) do
        if not Engine.entries[t.key] then
            Engine.entries[t.key] = {
                name = t.name,
                start = now, duration = t.icd, endTime = now + t.icd,
                predicted = true, source = "proc",
                category = "Item", icon = t.icon,
            }
            created = created + 1
        end
    end
    if created > 0 then
        self.counts.added = self.counts.added + created
    end
    return created
end

--- The out-of-combat sweep (the Module's 1 Hz read net drives it; the
--- PLAYER_REGEN_ENABLED pass is the one that reopens it after a fight).
--- One bulk read, the plain ids of the list against the watched set, and the
--- rising/falling edges off the previous complete pass. Returns the number
--- of entries created.
function Procs:Scan(now, readers)
    if not self.enabled then return 0 end
    if not next(self.tracked) then return 0 end
    if self:Gates() then return 0 end
    now = now or GetTime()
    local r = readers or self.readers
    if not r then
        r = Procs.LiveReaders and Procs.LiveReaders()
        self.readers = r
    end
    local list, how = callBulk(self, r and r.bulk)
    if how == "empty" then list = {}
    elseif list == nil then
        self.counts.skipped = self.counts.skipped + 1
        return 0
    end
    -- The pass answered: collect its plain spell ids. An id that will not
    -- read (a sealed element, a secret value) is not in the set -- the
    -- rising edge only ever fires on a POSITIVE plain fact; the falling edge
    -- only ever fires on a complete pass, and an id the pass could not read
    -- is not evidence of absence, so the pass is not treated as complete for
    -- it (it stays in `seen`, and its window runs out on its own clock).
    local seenNow = self._seenScratch
    if not seenNow then seenNow = {} self._seenScratch = seenNow end
    wipe(seenNow)
    for _, aura in ipairs(list) do
        local ok, id = pcall(readSpellID, aura)
        local spellID = ok and plain(id) or nil
        if type(spellID) == "number" then
            seenNow[spellID] = true
        else
            self.counts.secret = self.counts.secret + 1
        end
    end
    local created = 0
    for spellID in pairs(seenNow) do
        if not self.seen[spellID] then
            self.seen[spellID] = now
            self.counts.edges = self.counts.edges + 1
            created = created + self:OnProcSeen(spellID, now)
        end
    end
    -- The falling edge: an id the complete pass did not carry is gone, so
    -- the next proc is an edge again. Bounded by the watched-id count.
    for spellID in pairs(self.seen) do
        if not seenNow[spellID] then self.seen[spellID] = nil end
    end
    return created
end

--- The in-combat half: a `UNIT_AURA` for the player
--- (unitTarget, UnitAuraUpdateInfo). Every field of the payload is read
--- inside a pcall and only PLAIN values leave it -- the event is
--- SecretWhenAurasRestricted, so on a restricted client the whole pass
--- resolves to "no plain id, nothing changes". The event is throttled by
--- nature (one per aura change) and `OnProcSeen` is idempotent per running
--- window, so a burst cannot stack entries.
function Procs:OnUnitAura(unitTarget, updateInfo, now)
    if not self.enabled then return 0 end
    if type(unitTarget) == "string" and unitTarget ~= "player" then return 0 end
    if not next(self.tracked) then return 0 end
    self.counts.events = self.counts.events + 1
    now = now or GetTime()
    local ok, added = pcall(readAddedAuras, updateInfo)
    local list = ok and plain(added) or nil
    if type(list) ~= "table" then
        -- No plain addedAuras list: the payload said nothing usable. A full
        -- update (isFullUpdate) is the client saying "re-scan": the 1 Hz
        -- sweep is the re-scan, so there is nothing to do here.
        self.counts.skipped = self.counts.skipped + 1
        return 0
    end
    local created = 0
    for _, aura in ipairs(list) do
        local okID, id = pcall(readSpellID, aura)
        local spellID = okID and plain(id) or nil
        if type(spellID) == "number" and self.byBuff[spellID] then
            if not self.seen[spellID] then
                self.seen[spellID] = now
                self.counts.edges = self.counts.edges + 1
                created = created + self:OnProcSeen(spellID, now)
            end
        end
    end
    return created
end

--- The enable seam: the ONE public switch of the feature. `FX.Settings`
--- owns the value (`Cooldown.Procs`, the Cooldown page's checkbox); this is
--- the apply path the page's OnChange listener and `/fx` both drive.
--- Enabling pulls the load-on-demand data add-on in through
--- `FX.LoadAddOnOnDemand` -- idempotent, so the 200th enable of a session
--- costs one ledger read, and a session that never enables it never parses
--- a proc row. A failed load (the loader printed the reason once) leaves the
--- feature enabled-but-empty, never an error.
function Procs:SetEnabled(on)
    on = on and true or false
    self.enabled = on
    if not on then
        wipe(self.tracked)
        wipe(self.byBuff)
        wipe(self.seen)
        return false
    end
    FX.LoadAddOnOnDemand("Forte_ItemProcs")
    return self:Build()
end

function Procs:IsEnabled()
    return self.enabled and true or false
end

--- The stored shape of the one key this module reads (the pages' defaults
--- are the canonical source; an unregistered key reads as the shipped
--- default, OFF).
function Procs:ApplyStoredSettings()
    local st = FX.Settings
    if not st or not st.IsRegistered
        or not st:IsRegistered("Cooldown") then
        return self:SetEnabled(false)
    end
    return self:SetEnabled(st:Get("Cooldown", "Procs") and true or false)
end

--- Self-wiring (the Forte_Cooldown-must-work-without-Forte_Options law, the
--- Display:_WireSettings pattern): the page's checkbox writes the store,
--- this listener is what makes the write live.
function Procs:_WireSettings()
    local st = FX.Settings
    if not st or not st.OnChange or self._wired then return end
    self._wired = true
    st:OnChange("Cooldown", function(key, value)
        if key == "Procs" then self:SetEnabled(value) end
    end)
end

--- The Module's OnEnable hook: wire, apply the stored value, and (on an
--- enabled feature) watch the aura events. Registering the event happens in
--- the Module's frame, not here (no top-level RegisterEvent, AGENTS.md).
function Procs:Init()
    self:_WireSettings()
    return self:ApplyStoredSettings()
end

--- The Engine wipes `entries` at every `Engine:Build` (a rebuild, a class
--- change): the running windows are gone, and the `seen` model has to go
--- with them -- a watched id that is still `seen` with no window behind it
--- would swallow the next proc's edge.
function Procs:OnRebuild()
    wipe(self.seen)
    if self.enabled then return self:Build() end
    return 0
end

--- The live defaults: the catalog's bulk aura read, player + helpful
--- (`C_UnitAuras.GetUnitAuras` @UnitAuraDocumentation.lua:494; the
--- Forte_Timer/Core/Reconcile.lua `LiveReaders` shape).
function Procs.LiveReaders()
    return {
        bulk = function(unit, filter)
            if not (C_UnitAuras and C_UnitAuras.GetUnitAuras) then return nil end
            return C_UnitAuras.GetUnitAuras(unit, filter)
        end,
    }
end

--- Watched rows, live entries, the seen set and the read evidence
--- (Module:Status).
function Procs:Counts()
    local watched, live = 0, 0
    for _ in pairs(self.tracked) do watched = watched + 1 end
    for key in pairs(self.tracked) do
        if Engine.entries[key] then live = live + 1 end
    end
    return watched, live
end

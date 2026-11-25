-- addon/Forte_Hunter/Core/Hawks.lua
-- FX.Hunter.Hawks: the Summon Hawk tracker (PLAN §11.16) -- the hawks the
-- talent leaves behind as Spell Timer rows.
--
-- The model (upstream: wowsims/forever sim/hunter/summon_hawk.go): the cast
-- is a dive of at least DIVE_SECONDS, then a guardian hawk stands for its
-- lifetime; at most `summonMax` hawks are up at once, and a cast with every
-- slot taken replaces the hawk with the LEAST time left (upstream takes
-- turns round-robin, which is the older one). Hawks are guardians with no
-- unit token and no player aura, so nothing here reads the client: the only
-- input is our own plain UNIT_SPELLCAST_SUCCEEDED of the cast, fed by the
-- Hunter tools' ONE event frame (Core/Tools.lua onToolEvent -- the cast name
-- arrives already resolved and canonicalized onto the data key space, so a
-- localized client reaches this module under the English data name).
--
-- The numbers come from the generated data, never from this file: the
-- hawk lifetime is `summonDurationMs` and the slot count `summonMax` of the
-- `Summon Hawk` row (tools/spell_lists/hunter.json `_summons`, copied by
-- tools/gen_spell_data.py from the summon spell 1293248 and effect 3 of the
-- cast rank). The row carries no `durationMs`, so the cooldown bar's
-- Summon Hawk row (6 s shared cooldown with Arcane Shot) and the Timer's
-- registry are untouched.
--
-- Timer rows (the Shaman totem mechanism, Forte_Shaman/Core/Totems.lua):
-- one row per slot, `Summon Hawk 1` / `Summon Hawk 2`, keyed (name, "none")
-- so both are SELF rows (`Rows.IsSelfRow`: "Show timers on yourself" hides
-- them) and each has its own countdown. The rows are declared OWNED
-- (`Casts:DeclareOwnedRows`) so the cast spine draws no prediction of its
-- own and the aura sweep (Forte_Timer/Core/Reconcile.lua) leaves them alone
-- -- a hawk is not an aura on the player.
--
-- Active only while the player knows the spell: a Hunter without the talent
-- gets no rows, no owned-row declaration, no timer and no extra event.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
FX.Hunter = FX.Hunter or {}

local H = {}
FX.Hunter.Hawks = H

--- The data name of the cast (the generated data's English key space).
local SPELL = "Summon Hawk"
--- Seconds between the cast and the hawk standing: the dive's travel time to
--- the target. The upstream sim fit says "at least 1 s" (EV-0127) but the
--- owner saw the hawk appear "almost immediately, a very slight delay"
--- (live, 2026-11-25), so this is a short estimate; the real value grows with
--- the distance to the target, which the add-on cannot read.
local DIVE_SECONDS = 0.3
--- The Spell Timer colour band of a hawk row: the self-buff band. The name
--- shape alone would put `Summon Hawk N` into the Cooldown band (the
--- `^Summon` term, Forte_Timer/Core/Registry.lua), so the band is passed
--- explicitly at the insert.
local HAWK_KIND = "SelfBuff"
--- The owner label of the owned-row declaration.
local OWNER = "HunterHawks"

H.SPELL = SPELL
H.DIVE_SECONDS = DIVE_SECONDS
H.HAWK_KIND = HAWK_KIND

H.active = false
H.lifetime = nil        -- seconds, from the data
H.max = nil             -- slot count, from the data
H.slots = {}            -- [slot] = { expireAt }: the hawk last landed in it
H.pending = {}          -- dives in flight: { appearAt, dead, landed }
H.frame = nil           -- the Hunter tools' event frame (PLAYER_DEAD rides it)
H.now = nil             -- injectable clock; nil = GetTime()

function H:Clock()
    if self.now then return self.now() end
    return GetTime()
end

--- The row label / key of one slot.
local function rowName(slot)
    return SPELL .. " " .. slot
end
H.RowName = rowName

--- (lifetimeSeconds, slotCount) from the generated row, nil when the data
--- does not carry both (then the module stays inactive).
local function readData()
    local D = FX.Data
    local id = D and D.HunterByName and D.HunterByName[SPELL]
    local row = id and D.Hunter and D.Hunter[id]
    if type(row) ~= "table" or row.name ~= SPELL then return nil end
    local ms, cap = row.summonDurationMs, row.summonMax
    if type(ms) ~= "number" or ms <= 0 then return nil end
    if type(cap) ~= "number" or cap < 1 then return nil end
    return ms / 1000, math.floor(cap), id
end

--- Does the player know the spell? The Forte_Cooldown `isKnown` chain: the
--- data row ids (locale-independent) first, then the client's own rank
--- resolution by the client's name (a Rank 2 hunter knows 1293525, not the
--- data's Rank 4 id).
local function isKnown(dataId)
    local ids = {}
    local Locale = FX.Locale
    local ranked = Locale and Locale.RankIDsForName and Locale.RankIDsForName(SPELL)
    if type(ranked) == "table" then
        for i = 1, #ranked do ids[#ids + 1] = ranked[i] end
    end
    if dataId then ids[#ids + 1] = dataId end
    for i = 1, #ids do
        local ok, known = pcall(FX.Compat.IsPlayerSpell, ids[i])
        if ok and known == true then return true end
    end
    if not (C_Spell and C_Spell.GetSpellInfo) then return false end
    local ok, spellID = pcall(function()
        local info = C_Spell.GetSpellInfo(FX.L and FX.L(SPELL) or SPELL)
        return info and FX.Compat.PlainOrNil(info.spellID)
    end)
    if not ok or type(spellID) ~= "number" then return false end
    local okK, known = pcall(FX.Compat.IsPlayerSpell, spellID)
    return okK and known == true
end

local function timerRows()
    local T = FX.Timer
    local rows = T and T.Rows
    if rows and type(rows.InsertFromCast) == "function" then return rows end
    return nil
end

--- Seconds-after callback; false when the client has no timer surface.
local function armTimer(seconds, fn)
    if type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then
        return false
    end
    return (pcall(C_Timer.After, seconds, fn))
end

-- ------------------------------------------------------------ owned rows --
--- The names the Timer's cast spine and aura sweep must leave to us: the cast
--- name and every slot's row name.
local function ownedNames(cap)
    local names = { SPELL }
    for slot = 1, cap do names[#names + 1] = rowName(slot) end
    return names
end

function H:DeclareRows()
    local casts = FX.Timer and FX.Timer.Casts
    if not (casts and casts.DeclareOwnedRows) then return 0 end
    local me = self
    return casts:DeclareOwnedRows(ownedNames(self.max), OWNER,
        function() return me.active end)
end

function H:UndeclareRows()
    local casts = FX.Timer and FX.Timer.Casts
    if casts and casts.UndeclareOwnedRows then
        casts:UndeclareOwnedRows(OWNER)
    end
end

-- ----------------------------------------------------------------- state --
--- Drop every hawk, pending dive and Timer row of ours (death, loading
--- screen, deactivation).
function H:Clear()
    for i = 1, #self.pending do self.pending[i].dead = true end
    self.pending = {}
    local rows = timerRows()
    if rows then
        local removed = false
        for slot in pairs(self.slots) do
            local row, idx = rows:Find(rowName(slot), "none")
            if row then rows:removeAt(idx); removed = true end
        end
        if removed and rows.Compact then rows:Compact() end
    end
    self.slots = {}
end

--- (hawksUp, secondsUntilTheNextIsGone|nil) at `now`.
function H:Live(now)
    now = now or self:Clock()
    local n, soon = 0, nil
    for _, s in pairs(self.slots) do
        local left = s.expireAt - now
        if left > 0 then
            n = n + 1
            if soon == nil or left < soon then soon = left end
        end
    end
    return n, soon
end

--- The slot a hawk landing at `t` takes: the lowest free slot, else the one
--- with the least time left (ties: the lowest). Second return: replaced.
local function pickSlot(self, t)
    local best, bestLeft
    for i = 1, self.max do
        local s = self.slots[i]
        if s == nil or s.expireAt <= t then return i, false end
        local left = s.expireAt - t
        if bestLeft == nil or left < bestLeft then best, bestLeft = i, left end
    end
    return best, true
end

local function land(self, entry)
    if entry.dead or entry.landed or not self.active then return end
    entry.landed = true
    local t = entry.appearAt
    local slot = pickSlot(self, t)
    self.slots[slot] = { expireAt = t + self.lifetime }
    local rows = timerRows()
    if not rows then return end
    -- A replaced hawk's row restarts: the Rows insert law re-times the
    -- (name, "none") row in place or re-inserts it with the new window.
    local row = rows:InsertFromCast(rowName(slot), "none", self.lifetime, t, t,
        1, HAWK_KIND)
    if row then
        local module = FX.Timer and FX.Timer.Module
        if module and module.Kick then module:Kick() end
    end
end

--- Land every dive that is due at `now` (the timer lands its own entry; this
--- is the catch-up for readers that ask before it fired).
function H:Sync(now)
    now = now or self:Clock()
    local i = 1
    while i <= #self.pending do
        local e = self.pending[i]
        if e.appearAt <= now then
            table.remove(self.pending, i)
            land(self, e)
        else
            i = i + 1
        end
    end
end

--- Our own successful cast, by canonical data name. Returns true when a hawk
--- was scheduled.
function H:OnCast(name)
    if name ~= SPELL then return false end
    if not self:Refresh() then return false end
    local now = self:Clock()
    self:Sync(now)
    local entry = { appearAt = now + DIVE_SECONDS }
    self.pending[#self.pending + 1] = entry
    local me = self
    armTimer(DIVE_SECONDS, function()
        if entry.dead or entry.landed then return end
        for i = 1, #me.pending do
            if me.pending[i] == entry then table.remove(me.pending, i) break end
        end
        land(me, entry)
    end)
    return true
end

-- ------------------------------------------------------------- lifecycle --
--- (Re)evaluate "the data carries the numbers and the player knows the
--- spell": activates (owned rows declared, PLAYER_DEAD registered) or
--- deactivates (everything cleared and unregistered). Returns the state.
function H:Refresh()
    local life, cap, id = readData()
    local want = life ~= nil and isKnown(id)
    if want then
        if not self.active then
            self.active, self.lifetime, self.max = true, life, cap
            self:DeclareRows()
            local f = self.frame
            if f and f.RegisterEvent then f:RegisterEvent("PLAYER_DEAD") end
        else
            self.lifetime, self.max = life, cap
        end
    elseif self.active then
        self:Deactivate()
    end
    return self.active
end

function H:Deactivate()
    self:Clear()
    self.active = false
    self:UndeclareRows()
    local f = self.frame
    if f and f.UnregisterEvent then f:UnregisterEvent("PLAYER_DEAD") end
end

--- The Hunter tools enabled their event frame.
function H:Enable(frame)
    self.frame = frame
    self:Refresh()
end

--- The Hunter tools tore their frame down.
function H:Disable()
    if self.active then self:Deactivate() end
    self.frame = nil
end

--- PLAYER_ENTERING_WORLD: hawks do not survive a loading screen.
function H:OnWorldEnter()
    self:Clear()
    self:Refresh()
end

--- PLAYER_DEAD.
function H:OnPlayerDead()
    self:Clear()
end

--- The `/fx status` segment, nil while inactive.
function H:StatusSegment()
    if not self.active then return nil end
    local now = self:Clock()
    self:Sync(now)
    local n, soon = self:Live(now)
    if n == 0 then return string.format("hawks 0/%d", self.max) end
    return string.format("hawks %d/%d (next gone in %.1f s)", n, self.max, soon)
end

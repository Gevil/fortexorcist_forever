-- addon/Forte_Warlock/Core/Tools.lua
-- FX.Warlock.Tools: the original ForteXorcist's four warlock tools as
-- headless state trackers -- no frames, no options page (the groundwork
-- slice; every API/event claim is cited in docs/warlock-tools.md).
--
-- 1. SHARD COUNT (Shard Manager). This build's evidence says shards are a
--    BAG ITEM, not a power bar: the generated Warlock data has a
--    "shards-and-stones" family of `Create *` spells with no shard row, the
--    engine models them as bag reagents (wow-forever-sim
--    research/R17/r17-warlock.md:17-21 -- "carried count … full Felcloth Bag
--    21341", spent through `useReagents`) and the simulated warlock's power
--    bar 0 is MANA (`UnitPowerType("player")` -> 0, measured in the sim).
--    `Enum.PowerType.SoulShards` (PowerTypeConstantsDocumentation.lua:17,
--    value 7) + `UnitPower` do exist, so both sources are implemented and
--    probed in source order, first source that answers wins (the same chain
--    shape as FX.Compat.IsPlayerSpell). Read on BAG_UPDATE_DELAYED /
--    ITEM_COUNT_CHANGED / UNIT_POWER_UPDATE / PLAYER_REGEN_ENABLED.
--
-- 2. SOULSTONE TRACKER. The original scanned every raid member's
--    "Soulstone" aura (spec SS-05) -- on Forever aura reads are
--    out-of-combat-only, so the legal half is *our own* cast: a successful
--    own `Create Soulstone`-family cast makes a soulstone live on the
--    target named by the cast's UNIT_SPELLCAST_SENT payload, for a
--    PREDICTED window (PLAN §3.2).
--
-- 3. HEALTHSTONE SPY. Own-bag healthstone presence (`C_Item.GetItemCount`
--    over the generated `*Healthstone` names) + that item's cooldown
--    through the existing FX.Compat.GetItemCooldownInfo seam. The original
--   's raid-wide "spy" half was comms (HS-02) and its 6-bar panel is a UI
--    task, not this slice.
--
-- 4. SUMMON ASSISTANT (Ritual of Summoning). Only the *cast* half is legal
--    here: the ritual is a channeled cast, so its channel state is
--    cast-PREDICTED from our own cast events (spec CA-12 flags Ritual of
--    Summoning as channel-like so the SENT path claims the target; SU-02's
--    map-position sampling is NOT-feasible-on-Forever, so no roster list).
--
-- Secret-value law: every bag/unit/cooldown read passes
-- FX.Compat.PlainOrNil before any compare or arithmetic, the guards check
-- `type(x) == "number"`, and a secret (nil) read NEVER overwrites known
-- state. Names are matched against the generated data by NAME pattern --
-- no spell/item ID is hand-typed anywhere in this file (AGENTS.md, PLAN §8).

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
FX.Warlock = FX.Warlock or {}
local WK = FX.Warlock

-- ============================================================ value guards

--- A read that is a secret value, nil, or not a number answers nil.
local function plainNumber(v)
    local plain = FX.Compat.PlainOrNil(v)
    if type(plain) == "number" then return plain end
    return nil
end

--- A read that is a secret value, nil, or not a string answers nil.
local function plainString(v)
    local plain = FX.Compat.PlainOrNil(v)
    if type(plain) == "string" then return plain end
    return nil
end

-- ========================================================== data derivations

local function data()
    return FX.Data and FX.Data.Warlock
end

local function dataRow(name)
    local d = data()
    if not d or type(name) ~= "string" then return nil end
    local byName = FX.Data.WarlockByName
    local id = byName and byName[name]
    return id and d[id]
end

--- The generated data's item id for a NAME (the generated table is the only
--- source of ids; the value is only ever handed back to a C_* item seam,
--- never compared against a live read -- PLAN §8, ids drift per build).
function WK.DataItemID(name)
    local row = dataRow(name)
    return row and row.id
end

--- Sorted generated-data spell names matching any of `patterns`.
--- Generation-safe: a re-run of tools/gen_spell_data.py can only grow or
--- rename the list; the code never names an ID.
function WK.DeriveNames(patterns)
    local d = data()
    local names, seen = {}, {}
    if d then
        for _, spell in pairs(d) do
            local name = spell and spell.name
            if type(name) == "string" and not seen[name] then
                for _, pattern in ipairs(patterns) do
                    if name:find(pattern) then
                        seen[name] = true
                        names[#names + 1] = name
                        break
                    end
                end
            end
        end
    end
    table.sort(names)
    return names
end

--- The family's *item* names: the generated data's `Create X` rows are the
--- spells that make the item `X`, so they are excluded from an item-name
--- list (a stone-item count read of the spell name would answer 0 forever).
function WK.DeriveItemNames(patterns)
    local names = {}
    for _, name in ipairs(WK.DeriveNames(patterns)) do
        if not name:find("^Create ") then names[#names + 1] = name end
    end
    return names
end

--- The family gate for a name the CLIENT said: `FX.MatchesFamily`
--- (Forte_Core/Core/Constants.lua) canonicalizes the name onto the generated
--- data key first, so the English name patterns below -- which describe DATA
--- names, not client names -- match on every client (H1b,
--- docs/localization.md: on a localized client the raw English prefix
--- compare made every tracker deaf to its own family: `Seelenstein
--- erstellen` is not `^Create Soulstone`, so the soulstone window, the
--- ritual channel and the bag re-read all stayed shut).
function WK.MatchesAny(name, patterns)
    return FX.MatchesFamily(name, patterns)
end

--- One ms field of a data row in seconds, nil when the row is missing the
--- field, carries <= 0 (the data's "-1" = permanent) or a non-number.
local function dataSeconds(name, field)
    local row = dataRow(name)
    if not row then return nil end
    local ms = plainNumber(row[field])
    if ms and ms > 0 then return ms / 1000 end
    return nil
end

-- The families, as NAME patterns (the WotLK-era "Soulstone Resurrection"
-- name is in the spec, not in this data set: pattern, not constant name).
-- The soulstone family has ONE home -- `FX.SoulstonePatterns`, declared in
-- Forte_Core/Core/Constants.lua, which the always-loaded Forte_Messages
-- announces off (review 4 m7: the two watchers are legitimately separate,
-- this one tracks the buff and that one the cast, so the shared half is the
-- pattern list, and Forte_Core is the one add-on both hard-depend on).
WK.SoulstonePatterns = FX.SoulstonePatterns
WK.HealthstonePatterns = { "Healthstone$" }
WK.SummonPatterns = { "^Ritual of Summoning" }
WK.soulstoneNames = WK.DeriveNames(WK.SoulstonePatterns)
WK.healthstoneNames = WK.DeriveItemNames(WK.HealthstonePatterns)
WK.summonNames = WK.DeriveNames(WK.SummonPatterns)

--- The shard bag item, by NAME: the generated data has no shard row, the id
--- is build-sensitive, and the name is what the C_* item seams accept
--- (docs/warlock-tools.md, probe P1 covers the live shape).
WK.SHARD_ITEM_NAMES = { "Soul Shard" }

--- Soulstone window when the data carries none: 30 minutes, the Burning
--- Crusade-era value the original's 900 s (spec SS-01 `SS_TIME`, WotLK)
--- descends from. The `[20757] "Create Soulstone"` row has NO durationMs
--- (Data/Warlock.lua), so the number is PREDICTED, not read -- launch-day
--- probe P3 times it on the live client.
WK.SOULSTONE_SECONDS = 1800

function WK.DeriveSoulstoneSeconds()
    for _, name in ipairs(WK.soulstoneNames) do
        local seconds = dataSeconds(name, "durationMs")
        if seconds then return seconds end
    end
    return WK.SOULSTONE_SECONDS
end

--- The ritual's channeled length: the generated `castMs` of the summon
--- family (the `[698] "Ritual of Summoning"` row = 5000 ms).
function WK.DeriveSummonChannelSeconds()
    for _, name in ipairs(WK.summonNames) do
        local seconds = dataSeconds(name, "castMs")
        if seconds then return seconds end
    end
    return nil
end

-- =============================================================== ShardCounter

--- The live shard count read: the bag item. `C_Item.GetItemCount(itemInfo,
--- includeBank, includeUses, includeReagentBank, includeAccountBank) ->
--- count` (ItemDocumentation.lua:450); Blizzard's callers pass an itemID
--- (ItemUtil.lua:320) or an item-link string (MerchantFrame.lua:729) as the
--- same ItemInfo argument -- the shard NAME is that argument by the §8
--- no-hand-typed-ids rule. Only plain numbers are summed; every name that
--- answers nothing is skipped, and nil = "no reliable read".
---
--- H1b (docs/localization.md): the shard has NO generated data row, so there
--- is no itemID to hand the seam and the name is the only key available --
--- which makes it the one place in this file where the client-facing string
--- must be the CLIENT's: `FX.L(name)` (the Locale's item alias map is built
--- from the generated item ids, so a name the data set does not carry is its
--- own key and this is the identity on enUS as well as on a client whose item
--- alias for the shard has not arrived).
function WK.DefaultShardCountReader()
    if not (C_Item and C_Item.GetItemCount) then return nil end
    local total
    for _, name in ipairs(WK.SHARD_ITEM_NAMES) do
        local ok, count = pcall(C_Item.GetItemCount, FX.L(name))
        -- NOT `ok and plainNumber(count)`: a raise makes that FALSE, and
        -- `false ~= nil` is true -- the comparison below would then be a
        -- number/boolean compare, which RAISES on this client.
        local plain
        if ok then plain = plainNumber(count) end
        if plain ~= nil then total = (total or 0) + plain end
    end
    return total
end

--- The live shard count read: the power bar. `UnitPower(unitToken,
--- powerType[, unmodified]) -> power` (UnitDocumentation.lua:2731) is
--- SecretWhenUnitPowerRestricted, so the return passes PlainOrNil and the
--- numeric type guard below; a secret answers nil.
function WK.DefaultShardPowerReader()
    local enum = _G.Enum and _G.Enum.PowerType
    local powerType = enum and enum.SoulShards
    if powerType == nil then return nil end
    if type(UnitPower) ~= "function" then return nil end
    local ok, power = pcall(UnitPower, "player", powerType)
    if not ok then return nil end
    return plainNumber(power)
end

local ShardCounter = {}
ShardCounter.__index = ShardCounter

--- The two sources, in probe order. `field` is the instance's reader slot.
ShardCounter.SOURCES = {
    { name = "bag", field = "countReader" },
    { name = "power", field = "powerReader" },
}

--- Sample the sources; the FIRST one that answers with a plain, non-negative
--- number is the truth and is recorded as `source` (the /fx status label and
--- the launch-day answer to "how does this build model shards?").
--- `readers` = { bag = fn, power = fn } test overrides, `onlySource` probes a
--- single source (the bag events probe "bag", UNIT_POWER_UPDATE "power").
--- Returns `count, source`; count is nil when nothing answered -- and then
--- the last known count stands (a secret read never overwrites).
function ShardCounter:Read(readers, onlySource)
    for _, src in ipairs(self.SOURCES) do
        if onlySource == nil or onlySource == src.name then
            local reader = (readers and readers[src.name]) or self[src.field]
            if reader then
                local ok, value = pcall(reader)
                -- The `ok and plainNumber(...)` shape is a trap here: a raise
                -- makes it FALSE, `false ~= nil` is true and the `>= 0` below
                -- is then a number/boolean compare, which RAISES on this
                -- client (the Forte_Core/Core/Compat.lua SecretState law).
                local plain
                if ok then plain = plainNumber(value) end
                if plain ~= nil and plain >= 0 then
                    self.count, self.source = plain, src.name
                    return plain, src.name
                end
            end
        end
    end
    return nil, self.source
end

function ShardCounter:Count()
    return self.count, self.source
end

function ShardCounter:Snapshot()
    local count, source = self:Count()
    return { count = count, source = source }
end

function WK.NewShardCounter(opts)
    opts = opts or {}
    return setmetatable({
        countReader = opts.countReader,   -- bag-item source
        powerReader = opts.powerReader,   -- power-bar source
        count = nil,                      -- last plain count, nil = unknown
        source = nil,                     -- "bag" | "power", the answering source
    }, ShardCounter)
end

-- ============================================================ SoulstoneTracker

local SoulstoneTracker = {}
SoulstoneTracker.__index = SoulstoneTracker

function SoulstoneTracker:Clock()
    if self.now then return self.now() end
    return GetTime()
end

function SoulstoneTracker:IsFamily(name)
    return WK.MatchesAny(name, self.patterns)
end

--- Our own UNIT_SPELLCAST_SENT of a family spell (the event payload is
--- `(unitTarget, target, castGUID, spellID)`, UnitDocumentation.lua:4802 --
--- the target NAME is the 2nd field, the spellID the 4th). The name arrives
--- PlainOrNil-guarded by the handler (that field is ConditionalSecret).
--- A cast with no readable target is still a cast; its target stays nil.
function SoulstoneTracker:OnCastSent(name, targetName)
    if not self:IsFamily(name) then return false end
    self.pending = targetName
    return true
end

--- Our own UNIT_SPELLCAST_SUCCEEDED of a family spell: the stone is live on
--- `target` for `duration` seconds from here. The window is PREDICTED
--- (spec SS-05: the aura read that would anchor it is out-of-combat-only).
--- A newer stone replaces the tracked one -- a warlock carries one.
function SoulstoneTracker:OnCast(name, targetName)
    if not self:IsFamily(name) then return false end
    self.target = targetName or self.pending
    self.pending = nil
    self.name = name
    self.casts = self.casts + 1
    self.active, self.start = true, self:Clock()
    return true
end

--- Live-now predicate; observing the window end retires it (the next call
--- reports inactive), so no ticker is needed.
function SoulstoneTracker:Active(now)
    if not self.active then return false end
    now = now or self:Clock()
    if self.duration ~= nil and (now - self.start) >= self.duration then
        self:Clear()
        return false
    end
    return true
end

--- Seconds left of the stone window, nil when there is none (or the window
--- length is unknown -- a data row without a duration).
function SoulstoneTracker:Remaining(now)
    if not self:Active(now) then return nil end
    if self.duration == nil then return nil end
    now = now or self:Clock()
    return self.duration - (now - self.start)
end

function SoulstoneTracker:Target()
    return self.target
end

function SoulstoneTracker:Clear()
    self.active, self.start, self.target = false, nil, nil
end

function SoulstoneTracker:Snapshot()
    local active = self:Active()
    return {
        active = active,
        target = self.target,
        remaining = self:Remaining(),
        duration = self.duration,
        casts = self.casts,
    }
end

function WK.NewSoulstoneTracker(opts)
    opts = opts or {}
    return setmetatable({
        now = opts.now,                       -- injectable clock
        duration = opts.duration,             -- window seconds, nil = unknown
        patterns = opts.patterns or WK.SoulstonePatterns,
        active = false,
        start = nil,
        target = nil,   -- who carries the stone (nil = not read from SENT)
        pending = nil,  -- target claimed by SENT, consumed by SUCCEEDED
        name = nil,
        casts = 0,      -- adopted casts, for /fx status
    }, SoulstoneTracker)
end

-- ============================================================ HealthstoneTracker

--- Sum the healthstone family over the generated names, by NAME (see the
--- shard reader for the ItemInfo argument's provenance). H1b: the name the
--- client resolves is the CLIENT's -- `FX.L(name)`, the locale alias of the
--- data label (the identity on enUS). The stone's item COOLDOWN read below
--- needs no such leg: it goes by the generated row's itemID, which is
--- locale-free by construction.
function WK.DefaultHealthstoneCountReader()
    if not (C_Item and C_Item.GetItemCount) then return nil end
    local total
    for _, name in ipairs(WK.healthstoneNames) do
        local ok, count = pcall(C_Item.GetItemCount, FX.L(name))
        local plain
        if ok then plain = plainNumber(count) end -- (no `ok and …`: see the shard reader)
        if plain ~= nil then total = (total or 0) + plain end
    end
    return total
end

--- The most-occupied healthstone cooldown: one
--- FX.Compat.GetItemCooldownInfo(itemID) read per generated stone (bag
--- items read by itemID -- the split Forte_Cooldown/Core/Items.lua uses).
--- Returns the raw (start, duration, enable) of the stone that ends
--- latest, nil when no stone answered; OnReadCooldown is the guard.
function WK.DefaultHealthstoneCooldownReader()
    local read = FX.Compat and FX.Compat.GetItemCooldownInfo
    if not read then return nil end
    local bestStart, bestDuration, bestEnable, bestEnd
    for _, name in ipairs(WK.healthstoneNames) do
        local itemID = WK.DataItemID(name)
        if itemID ~= nil then
            local ok, start, duration, enable = pcall(read, itemID, nil)
            if ok then
                local s, d = plainNumber(start), plainNumber(duration)
                if s ~= nil and d ~= nil and s > 0 and d > 0 then
                    if bestEnd == nil or (s + d) > bestEnd then
                        bestStart, bestDuration = s, d
                        bestEnable, bestEnd = plainNumber(enable) or enable, s + d
                    end
                end
            end
        end
    end
    return bestStart, bestDuration, bestEnable
end

local HealthstoneTracker = {}
HealthstoneTracker.__index = HealthstoneTracker

function HealthstoneTracker:Clock()
    if self.now then return self.now() end
    return GetTime()
end

--- Refresh "has the warlock a healthstone in the bags". Returns the count,
--- nil for "no reliable read" (state untouched).
function HealthstoneTracker:ReadCounts(countReader)
    local reader = countReader or self.countReader
    if not reader then return nil end
    local ok, value = pcall(reader)
    local plain
    if ok then plain = plainNumber(value) end -- (no `ok and …`: see the shard reader)
    if plain == nil then return nil end
    self.count = plain
    self.present = plain > 0
    return plain
end

--- Raw item-cooldown read (the C_Item/C_Container triple). Every number
--- passes PlainOrNil and the type guard here, exactly as
--- Forte_Cooldown/Core/Items.lua:OnRead does. Answers "anchored" | "cleared"
--- | "secret" | "ignored" (a disabled timer).
function HealthstoneTracker:OnReadCooldown(start, duration, enable, now)
    start = plainNumber(start)
    duration = plainNumber(duration)
    enable = plainNumber(enable)
    if start == nil or duration == nil then return "secret" end
    if enable ~= nil and enable <= 0 then return "ignored" end
    now = now or self:Clock()
    if start > 0 and duration > 0 then
        self.cdStart, self.cdDuration, self.cdAt = start, duration, now
        return "anchored"
    end
    self.cdStart, self.cdDuration, self.cdAt = nil, nil, nil
    return "cleared"
end

--- One live pass through the injected (default: FX.Compat) read seam. The
--- read is pcall'd: a restricted client RAISES on a secret read.
function HealthstoneTracker:ReadCooldown(cooldownReader, now)
    local reader = cooldownReader or self.cooldownReader
    if not reader then return nil end
    local ok, start, duration, enable = pcall(reader)
    if not ok then return "secret" end
    return self:OnReadCooldown(start, duration, enable, now)
end

function HealthstoneTracker:Count()
    return self.count, self.present
end

--- true = a stone is known in the bags, false = known empty,
--- nil = never read reliably.
function HealthstoneTracker:Present()
    if self.count == nil then return nil end
    return self.count > 0
end

--- Seconds of item cooldown left, nil when ready/unknown. Observing the
--- window end clears it (no ticker).
function HealthstoneTracker:CooldownRemaining(now)
    if self.cdStart == nil or self.cdDuration == nil then return nil end
    now = now or self:Clock()
    local remaining = (self.cdStart + self.cdDuration) - now
    if remaining <= 0 then
        self.cdStart, self.cdDuration, self.cdAt = nil, nil, nil
        return nil
    end
    return remaining
end

function HealthstoneTracker:Snapshot()
    return {
        count = self.count,
        present = self:Present(),
        cooldownRemaining = self:CooldownRemaining(),
        cooldownDuration = self.cdDuration,
    }
end

function WK.NewHealthstoneTracker(opts)
    opts = opts or {}
    return setmetatable({
        now = opts.now,                         -- injectable clock
        countReader = opts.countReader,         -- bag count source
        cooldownReader = opts.cooldownReader,   -- FX.Compat.GetItemCooldownInfo shape
        count = nil,                            -- last plain count, nil = unknown
        present = nil,
        cdStart = nil, cdDuration = nil, cdAt = nil,
    }, HealthstoneTracker)
end

-- ================================================================ SummonTracker

local SummonTracker = {}
SummonTracker.__index = SummonTracker

function SummonTracker:Clock()
    if self.now then return self.now() end
    return GetTime()
end

function SummonTracker:IsFamily(name)
    return WK.MatchesAny(name, self.patterns)
end

--- The ritual's SENT event: the cast is on its way, and SENT is the only
--- cast event that carries a target name (CA-12: the original flags Ritual
--- of Summoning channel-like so the SENT path claims the target). The
--- channel is PREDICTED from here.
function SummonTracker:OnCastSent(name, targetName)
    if not self:IsFamily(name) then return false end
    if targetName ~= nil then self.target = targetName end
    return self:Begin(name)
end

--- UNIT_SPELLCAST_START / UNIT_SPELLCAST_CHANNEL_START.
function SummonTracker:OnCastStart(name)
    if not self:IsFamily(name) then return false end
    return self:Begin(name)
end

function SummonTracker:Begin(name)
    self.name = name
    if not self.channeling then
        self.channeling, self.start = true, self:Clock()
        self.duration = self.channelSeconds
        self.starts = self.starts + 1
    end
    return true
end

--- The channel is over: SUCCEEDED (the stone is thrown), STOP, FAILED,
--- INTERRUPTED, CHANNEL_STOP. `outcome` is recorded for the status line.
function SummonTracker:End(name, outcome)
    if not self:IsFamily(name) then return false end
    self:Stop(outcome)
    return true
end

function SummonTracker:Stop(outcome)
    if not self.channeling then return end
    self.last = {
        at = self:Clock(),
        name = self.name,
        target = self.target,
        outcome = outcome,
        channelled = self.duration ~= nil
            and (self:Clock() - self.start) or nil,
    }
    self.ends = self.ends + 1
    self.channeling, self.start, self.duration = false, nil, nil
    self.target = nil
end

--- Channelled right now? A prediction, so it self-expires at start + the
--- data's cast length when no stop event reaches us.
function SummonTracker:Channeling(now)
    if not self.channeling then return false end
    now = now or self:Clock()
    if self.duration ~= nil and (now - self.start) >= self.duration then
        self:Stop("expired")
        return false
    end
    return true
end

--- Fraction completed and seconds left of the channel, nil when idle.
function SummonTracker:Progress(now)
    if not self:Channeling(now) then return nil end
    if self.duration == nil then return nil end
    now = now or self:Clock()
    local elapsed = now - self.start
    if elapsed < 0 then elapsed = 0 end
    return elapsed / self.duration, self.duration - elapsed
end

function SummonTracker:Snapshot()
    local fraction, remaining = self:Progress()
    return {
        channeling = self:Channeling(),
        target = self.target,
        fraction = fraction,
        remaining = remaining,
        starts = self.starts,
        ends = self.ends,
        last = self.last,
    }
end

function WK.NewSummonTracker(opts)
    opts = opts or {}
    return setmetatable({
        now = opts.now,                                   -- injectable clock
        channelSeconds = opts.channelSeconds,             -- data castMs/1000
        patterns = opts.patterns or WK.SummonPatterns,
        channeling = false,
        start = nil, duration = nil,
        name = nil, target = nil,
        starts = 0, ends = 0,
        last = nil,   -- { at, name, target, outcome, channelled }
    }, SummonTracker)
end

-- ================================================================== module

FX.Warlock.Tools = {}
local M = FX.Warlock.Tools

--- Resolve a cast event's spellID to a plain spell name. The payload id is
--- catalog-annotated SecretWhenUnitSpellCastRestricted, so NO raw
--- comparison on it is legal and the info table's own fields may be
--- conditional-secret: lookup, truth test and field read run inside ONE
--- pcall and only a plain string leaves it (the Forte_Cooldown/Module.lua
--- and Forte_Hunter/Core/Tools.lua shape).
local function resolveCastName(spellID)
    if not (C_Spell and C_Spell.GetSpellInfo) then return nil end
    local ok, resolved = pcall(function()
        local info = C_Spell.GetSpellInfo(spellID)
        return info and FX.Compat.PlainOrNil(info.name)
    end)
    if ok and type(resolved) == "string" then return resolved end
    return nil
end
M.ResolveCastName = resolveCastName

--- UNIT_SPELLCAST_SENT's `target` field is ConditionalSecret
--- (UnitDocumentation.lua:4802), so only a plain string may name a
--- soulstone/ritual target.
local function resolveTargetName(target)
    return plainString(target)
end
M.ResolveTargetName = resolveTargetName

--- The data key of a resolved cast name (H1b, docs/localization.md): the
--- trackers' family gates (`^Create Soulstone`, `^Soulstone`,
--- `^Ritual of Summoning`) and the `^Create ` bag-refresh gate below are
--- ENGLISH DATA-NAME patterns, while `resolveCastName` answers the CLIENT's
--- name -- so on a localized client no cast of a tracked family spell was
--- ever recognized (no soulstone window, no ritual channel, no bag re-read).
--- Canonicalizing once at the seam puts every gate back on the key space the
--- patterns were written in; `M.ResolveCastName` stays the untouched
--- client-name seam. The identity on enUS.
local function castKey(spellID)
    local name = resolveCastName(spellID)
    if type(name) ~= "string" then return nil end
    local Locale = FX.Locale
    if Locale and Locale.CanonicalName then return Locale.CanonicalName(name) end
    return name
end
M.CastKey = castKey

--- The trackers, built from the generated data. The live read seams are
--- installed here (and only here) so every tracker can be rebuilt in a test
--- with fakes -- the module's own copies are the ones the event frame feeds.
M.Shards = WK.NewShardCounter({
    countReader = WK.DefaultShardCountReader,
    powerReader = WK.DefaultShardPowerReader,
})
M.Soulstone = WK.NewSoulstoneTracker({ duration = WK.DeriveSoulstoneSeconds() })
M.Healthstone = WK.NewHealthstoneTracker({
    countReader = WK.DefaultHealthstoneCountReader,
    cooldownReader = WK.DefaultHealthstoneCooldownReader,
})
M.Summon = WK.NewSummonTracker({ channelSeconds = WK.DeriveSummonChannelSeconds() })

-- ============================================================ group comms
-- The H6 transport (Core/Comms.lua) rides THIS module: the gate's load probe
-- expects the Warlock add-on to carry exactly `Warlock` + `WarlockUI`, so
-- Comms has no FX.RegisterModule of its own -- enable, class gate and status
-- all pass through here. (Core/Group.lua is its state model.)
M.Comms = FX.Warlock.Comms

--- One bag-driven pass: shard count (bag source) + healthstone presence and
--- item cooldown. Every read inside is pcall'd and secret-guarded.
function M:ReadItems()
    self.Shards:Read(nil, "bag")
    self.Healthstone:ReadCounts()
    self.Healthstone:ReadCooldown()
    -- The comms announce half: change-gated + rate-gated inside (the header
    -- rate law of Core/Comms.lua; solo sends never leave the client).
    if M.Comms then M.Comms:AnnounceState() end
end

--- The event frame's dispatcher. Payload orders are the catalog's (all
--- cited in docs/warlock-tools.md) and the frame is registered for
--- unit="player", so every cast event here is OUR OWN cast:
---   UNIT_SPELLCAST_SENT          (unit, target, castGUID, spellID)  -- id 4th
---   UNIT_SPELLCAST_START         (unit, castGUID, spellID, castBarID)
---   UNIT_SPELLCAST_SUCCEEDED     (unit, castGUID, spellID[, castBarID])
---   UNIT_SPELLCAST_STOP/FAILED   (unit, castGUID, spellID, castBarID)
---   UNIT_SPELLCAST_INTERRUPTED   (unit, castGUID, spellID, interruptedBy, castBarID)
---   UNIT_SPELLCAST_CHANNEL_START (unit, castGUID, spellID, castBarID)
---   UNIT_SPELLCAST_CHANNEL_STOP  (unit, castGUID, spellID, interruptedBy, castBarID)
--- The last two carry an extra field BEFORE castBarID: the spellID is a3 for
--- every one of them and `interruptedBy` is never touched.
local function onToolEvent(self, event, a1, a2, a3, a4)
    if event == "UNIT_SPELLCAST_SENT" then
        local name = castKey(a4)
        local target = resolveTargetName(a2)
        if name then
            self.Soulstone:OnCastSent(name, target)
            if self.Summon:OnCastSent(name, target) and M.Comms then
                M.Comms:OnSelfSummon("start", target)
            end
        end
    elseif event == "UNIT_SPELLCAST_START"
        or event == "UNIT_SPELLCAST_CHANNEL_START" then
        local name = castKey(a3)
        if name and self.Summon:OnCastStart(name) and M.Comms then
            M.Comms:OnSelfSummon("start", self.Summon.target)
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local name = castKey(a3)
        if not name then return end
        self.Soulstone:OnCast(name)
        if self.Summon:End(name, "succeeded") and M.Comms then
            M.Comms:OnSelfSummon("end")
        end
        if name:find("^Create ") then
            -- A `Create *` success is the moment the bag changes; the bag
            -- events confirm it a moment later.
            self:ReadItems()
        end
    elseif event == "UNIT_SPELLCAST_STOP"
        or event == "UNIT_SPELLCAST_FAILED"
        or event == "UNIT_SPELLCAST_INTERRUPTED"
        or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        local name = castKey(a3)
        if name and self.Summon:End(name, event == "UNIT_SPELLCAST_FAILED"
                and "failed" or "cancelled") and M.Comms then
            M.Comms:OnSelfSummon("end")
        end
    elseif event == "BAG_UPDATE_DELAYED" then
        self:ReadItems()
    elseif event == "ITEM_COUNT_CHANGED" then
        self:ReadItems()
    elseif event == "UNIT_POWER_UPDATE" then
        -- Registered as a unit event for "player"; the payload
        -- (UnitDocumentation.lua:4551) is not read at all.
        self.Shards:Read(nil, "power")
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Out of combat: the moment a plain read is legal again (PLAN §3.2).
        self:ReadItems()
        self.Shards:Read()
    end
end

--- The shard count, as the status line prints it ("?" = never read
--- reliably). Kept separate so the tests can assert the shape.
function M:ShardStatus()
    local count, source = self.Shards:Count()
    if count == nil then return "shards ?" end
    return string.format("shards %d[%s]", count, tostring(source))
end

function M:SoulstoneStatus()
    local snap = self.Soulstone:Snapshot()
    if not snap.active then return "soulstone none" end
    return string.format("soulstone %s %ds",
        snap.target ~= nil and snap.target or "(target unread)",
        math.floor(snap.remaining or 0))
end

function M:HealthstoneStatus()
    local snap = self.Healthstone:Snapshot()
    if snap.count == nil then return "healthstone ?" end
    return string.format("healthstone %d%s", snap.count,
        snap.cooldownRemaining ~= nil
            and string.format(" cd %.1fs", snap.cooldownRemaining) or "")
end

function M:SummonStatus()
    local snap = self.Summon:Snapshot()
    if snap.channeling then
        return string.format("ritual channeling%s %s",
            snap.target ~= nil and (" on " .. snap.target) or "",
            snap.remaining ~= nil and string.format("%.1fs", snap.remaining)
                or "…")
    end
    local last = snap.last
    if not last then return "ritual idle" end
    return string.format("ritual idle (last %s%s)",
        tostring(last.outcome),
        last.target ~= nil and (" on " .. tostring(last.target)) or "")
end

--- One `/fx status` line.
function M:StatusLine()
    return "Warlock: " .. table.concat({
        self:ShardStatus(),
        self:SoulstoneStatus(),
        self:HealthstoneStatus(),
        self:SummonStatus(),
    }, " | ")
end

--- Register the tools' events (idempotent while enabled). The frame is
--- created inside OnEnable/OnClassChanged, never at file load (the taint
--- rule, Forte_Core/Core/Init.lua). Every name below is verified in the
--- pinned Forever catalog first (docs/warlock-tools.md).
function M:EnableEvents()
    if self._eventsEnabled then return end
    local f = self._eventFrame
    if not f then
        f = CreateFrame("Frame")
        self._eventFrame = f
    end
    f:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
    f:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    f:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
    f:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
    f:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    f:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    f:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
    f:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
    f:RegisterEvent("BAG_UPDATE_DELAYED")
    f:RegisterEvent("ITEM_COUNT_CHANGED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    -- The frame is the script's first argument (the Forte_Cooldown/Module.lua
    -- shape): swallow it, then the event name and the payload.
    f:SetScript("OnEvent", function(_, event, a1, a2, a3, a4, a5)
        onToolEvent(M, event, a1, a2, a3, a4, a5)
    end)
    self._eventsEnabled = true
end

--- Tear the registrations back down (class changed away from WARLOCK;
--- Core FX.RefreshPlayerClass). SetScript(nil) is the part that silences
--- the module everywhere; the Unregister* calls are nil-guarded because
--- the simulator's frame emulation does not ship them (the Hunter
--- tools' proven shape).
function M:DisableEvents()
    local f = self._eventFrame
    if f and self._eventsEnabled then
        if f.UnregisterUnitEvent then
            f:UnregisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
            f:UnregisterUnitEvent("UNIT_SPELLCAST_START", "player")
            f:UnregisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
            f:UnregisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
            f:UnregisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
            f:UnregisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
            f:UnregisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
            f:UnregisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
            f:UnregisterUnitEvent("UNIT_POWER_UPDATE", "player")
        end
        if f.UnregisterEvent then
            f:UnregisterEvent("BAG_UPDATE_DELAYED")
            f:UnregisterEvent("ITEM_COUNT_CHANGED")
            f:UnregisterEvent("PLAYER_REGEN_ENABLED")
        end
        f:SetScript("OnEvent", nil)
    end
    self._eventsEnabled = false
end

function M:OnEnable()
    -- Event frame for warlocks only: the shared /fx bootstrap runs OnEnable
    -- for every player class.
    if FX._playerClass ~= "WARLOCK" then return end
    self:EnableEvents()
    -- The H6 comms (Core/Comms.lua): prefix registration, the CHAT_MSG_ADDON
    -- and GROUP_* frame. Rides this module's class gate (see above).
    if M.Comms then M.Comms:OnEnable() end
end

--- Core FX.RefreshPlayerClass notification (the uiforever T4 class guard):
--- the event frame follows the class.
function M:OnClassChanged(classFile)
    if classFile == "WARLOCK" then
        self:EnableEvents()
        if M.Comms then M.Comms:OnEnable() end
    else
        self:DisableEvents()
        if M.Comms then M.Comms:OnClassChanged(classFile) end
    end
end

--- `/fx status` integration: prints its own line (the Core status loop
--- calls every module's Status, Forte_Core/Core/Init.lua).
function M:Status()
    FX.Print(self:StatusLine())
    if M.Comms and M.Comms.StatusLine and M.Comms.group then
        FX.Print(M.Comms:StatusLine())
    end
end

FX.RegisterModule("Warlock", M)

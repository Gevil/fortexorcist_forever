-- addon/Forte_Timer/Core/Registry.lua
-- FX.Timer.Register: the declared-spell registry, keyed by spell NAME
-- (docs/design-spell-timer.md §3.1). It is the port of the original's
-- `Track[spell] = {notTarget, duration, ticks, type, texture, group, isBuff,
-- isShared, isUnique, isRefresh, keep}` (Forte_Timer.lua:606-617, spec ST-01)
-- rebuilt on Forever's data basis: the original's spell table was a hand-fed
-- registration DSL; ours is DERIVED from the generated class data
-- (`addon/Forte_<Class>/Data/<Class>.lua`, tools/gen_spell_data.py), so no
-- spell id, duration or name is ever hand-typed here (AGENTS.md, PLAN §10.2
-- rule 8).
--
-- Field law (§3.4, the same law Forte_Cooldown/Core/Engine.lua:171-177
-- `BestDuration` runs):
--     duration = learned[name] (seconds)   else   data.durationMs / 1000
-- `learned` is written ONLY by a plain aura read's duration/expirationTime
-- pair (Core/Reconcile.lua) -- a prediction never teaches, exactly the rule
-- `Engine:OnRead` enforces.
--
-- The dropped Track columns, on the record: `texture` (resolved live through
-- C_Spell.GetSpellTexture at draw time), and the 2012 glyph/talent/set
-- modifiers (`C_Glyph`: ZERO symbols on this client; talents are C_Traits).
-- `group`/`isShared`/`isUnique` (the shared-debuff eviction tables) are the
-- `mechanic`/`maxStack`/`dispel`/`isBuff` data fields docs/design-spell-timer.md
-- §3.4 asks the generator to emit; they are NOT in the data yet (owner open
-- question 5), so v1 registers one row per spell, keyed by name + target
-- (§3.3), with no shared-group eviction. When the fields land, `kind` and
-- `maxStack` are read here and nothing else moves.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
FX.Timer = FX.Timer or {}

local Registry = {}
FX.Timer.Registry = Registry

--- The live registry: [spellName] = { name, kind, duration, tickEvery,
--- maxStack, noTarget, dataId }.
Registry.entries = {}
--- [spellName] = seconds, learned from plain aura reads (persisted via
--- Registry:AttachStorage, the Engine's AttachStorage pattern).
Registry.learned = {}

--- Point the learned durations at a SavedVariables-backed table so they
--- survive reloads (launch-day probe P9).
function Registry:AttachStorage(tbl)
    self.learned = tbl
end

local function TitleCase(classFile)
    if not classFile then return nil end
    return classFile:sub(1, 1):upper() .. classFile:sub(2):lower()
end

--- The class's generated data table, nil when the class has none (the
--- Deathknight placeholder, an uninstalled class addon).
function Registry.DataFor(classFile)
    local key = TitleCase(classFile)
    if not key then return nil end
    return FX.Data and FX.Data[key]
end

-- The kind a generated row gets, decided from the data alone -- the v1 stand-in
-- for the original's per-spell registration (design §8.1: "ship them all"). The
-- rules are ordered and documented; a spell with a duration and no target-side
-- signal is a self-buff window (a Hunter's Bestial Wrath / Rapid Fire / aspect
-- window), a sting/mark/curve-shaped debuff name on a *targeted* damage spell
-- is a TargetDebuff. `Crowds` is the CC family (Stun/Charm/Root/Fear/Asphyxiate
-- shaped names); names with no signal keep the neutral `Default` row so the
-- colour law always has a colour.
local KIND_RULES = {
    { key = "Crowds", pattern = "Stun$|^Charm|^Root|^Fear|Asphyxiate|^Seduce|^Scatter|^Intimidation|^Terror|^Howl|^Bash|^Maim|^Kidney|^Freeze|^Poly" },
    { key = "SelfDebuff", pattern = "^Curse of Self" },
    { key = "TargetDebuff", pattern = "Sting$|Mark$|Curse$|Bane$|Corruption$|Agony$|Immolate$|Wound$|Serpent|Faerie|Windfury|Thunderfury|Demoralize|Expose|^Curse|^Bane|Immolation Aura|Concussive|Distracting|Tranquilizing|Viper|Scorpid|Black Arrow|Infectious" },
    { key = "Channel", pattern = "Channel|Volley|Rain of Fire|Blizzard|Trance" },
    { key = "Cooldown", pattern = "Cooldown" },
    { key = "Pet", pattern = "^Call Pet|Pet$" },
    { key = "SelfBuff", pattern = "Aspect|Wrath|Rage|Frenzy|Armor|Shield|Blessing|Aura$|Power|Sight|Sense|Form$|Stride|Dash|Prowl|Stealth|Deterrence|Discipline|Focus|Flare|Rapid Fire|Endurance|Meditation|Spirit|Barrier|Sanctuary|Freedom|Potion" },
}

local function kindFor(name)
    for _, rule in ipairs(KIND_RULES) do
        if name:find(rule.pattern) then return rule.key end
    end
    return "Default"
end

--- True when the row is a self / no-target window (the original's
--- `Track[spell][1] == 1` column, `ST_TrackedSuccess` :979-985: such a cast
--- carries guid "none" and a PRIOR_* group id, so it is exactly ONE row).
--- v1's rule: a spell whose generated row has no cooldown category and whose
--- name is a stance/aspect/window is self-only -- the safe form is explicit:
--- a registry entry is marked by the class lists it comes from, so v1 marks
--- NONE by default and the row key keeps the cast's own target (the design's
--- §3.3 law: "a self-buff is exactly one row because its targetKey is
--- 'none'", which the cast feed supplies when the SENT target is empty).
function Registry.IsNoTarget(name)
    local t = Registry.entries[name]
    return t ~= nil and t.noTarget == true
end

--- Build the registry from the generated data of `classFile` ("HUNTER", ...).
--- `filter(name)` is optional (tests, a curated default). Returns the count,
--- or nil + a reason when the class has no data -- the Engine's contract.
function Registry:Build(classFile, filter)
    wipe(self.entries)
    local data = Registry.DataFor(classFile)
    if not data then
        return nil, "no generated data for class " .. tostring(classFile)
    end
    local n = 0
    for id, spell in pairs(data) do
        local name = spell and spell.name
        local dur = spell and spell.durationMs
        -- durationMs is the Spell Timer's whole subject; `-1` is the data's
        -- "no cast/unknown" sentinel (Forte_Hunter/Data/Hunter.lua's Call Pet)
        -- and a 0/absent duration has no row to draw.
        if type(name) == "string" and type(dur) == "number" and dur > 0
            and (not filter or filter(name)) then
            self.entries[name] = {
                name = name,
                dataId = id,
                duration = dur / 1000,
                kind = kindFor(name),
                noTarget = false,
            }
            n = n + 1
        end
    end
    return n
end

--- Best known duration in seconds: learned beats generated (Engine:
--- BestDuration's law, Engine.lua:171-177).
function Registry.BestDuration(name)
    local learned = Registry.learned[name]
    if type(learned) == "number" and learned > 0 then return learned end
    local t = Registry.entries[name]
    return t and t.duration
end

--- Teach a duration. Called ONLY from a plain aura read (Core/Reconcile.lua),
--- never from a prediction (PLAN §3.2; the Engine's OnRead rule).
function Registry.Learn(name, seconds)
    if type(name) ~= "string" then return end
    if type(seconds) ~= "number" or seconds <= 0 then return end
    local t = Registry.entries[name]
    local base = t and t.duration
    if base and math.abs(seconds - base) < 0.001 then return end
    Registry.learned[name] = seconds
end

--- The kind a name draws with (the colour + fade class).
function Registry.KindFor(name)
    local t = Registry.entries[name]
    return (t and t.kind) or "Default"
end

--- Is this a spell we register (the port of the original's `Track[spell]`
--- gate: `ST_ScanForMissing` only adds auras of spells registered as OUR OWN
--- casts, Forte_Timer.lua:1103; the original was never a raid-debuff tracker,
--- spec ST-24)?
function Registry.IsTracked(name)
    return Registry.entries[name] ~= nil
end

function Registry:Counts()
    local n = 0
    for _ in pairs(self.entries) do n = n + 1 end
    local l = 0
    for _ in pairs(self.learned) do l = l + 1 end
    return n, l
end

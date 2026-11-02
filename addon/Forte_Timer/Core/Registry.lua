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

--- The class's generated data table, nil when the class has none (a class
--- addon that is not installed or not loaded).
function Registry.DataFor(classFile)
    local key = TitleCase(classFile)
    if not key then return nil end
    return FX.Data and FX.Data[key]
end

-- The kind a generated row gets, decided from the spell NAME ALONE -- the v1
-- stand-in for the original's per-spell registration type column (design §8.1:
-- "ship them all"). The colour intent is the original's palette (Skin rows,
-- Forte_Timer.lua:3371-3401): a curse is purple (`Curse`), a warlock bane is
-- teal (`Bane`), crowd control is green (`Crowds`), a heal is green
-- (`Heal`), a group buff is yellow (`Buff`), a self window is cyan
-- (`SelfBuff`), a pet tool is magenta (`Pet`), a target-side window is blue
-- (`TargetDebuff`), a self-inflicted window is red (`SelfDebuff`), a
-- channelling window is violet (`Channel`), a utility window is salmon
-- (`Cooldown`), and a name with no signal keeps the neutral orange
-- (`Default`) so the colour law always has a colour.
--
-- The table is ORDERED: the first band that matches wins, so the narrow
-- families (pet tools, curses, CC, heals, channels) run before the broad
-- target-debuff and self-buff families. Each band lists TERMS, not regexes:
-- a bare term is a plain substring, `^term` anchors the front, `term$` the
-- end, `^term$` the whole name.
--
-- Why terms: the table this replaces (2026-11-02) was a list of `|`-joined
-- REGEX patterns fed to `name:find(pattern)`. Lua patterns have no
-- alternation, so the `|` and the interior `$` are literal characters and
-- every multi-term rule was unmatchable: measured in the sim, ALL 366 tracked
-- spells of all nine generated classes fell to `Default`, which is why the
-- panel drew one colour for everything. `kindFor` is term-driven and
-- allocation-free; `tests/test_kinds.lua` holds the coverage floor per class.
local KIND_RULES = {
    { key = "Curse", terms = {
        "^Curse", "Curse$", "Amplify Curse", "^Hex of", "^Touch of Weakness",
    } },
    { key = "Bane", terms = { "^Bane" } },
    { key = "Pet", terms = {
        "^Pet", " Pet", "^Growl", "^Scrap", "^Claw", "^Bite", "^Cleave",
        "^Smite", "^Web$", "^Dust Cloud", "^Strider Kick", "^Tendon Rip",
        "^Wing Clip", "^Dismember", "^Pinch", "^Scorpid Poison", "^Swipe",
        "^Carve", "^Mine!", "^Thunderstomp", "^Lightning Breath",
        "^Poisoned Water", "^Spore Vince", "^Spore Wrap", "^Disease Cloud",
        "^Root Trample", "^Constrictor", "^Creeping Module", "^Death Guard",
        "^Wyvern Strike", "^Mend Pet", "^Feed Pet", "^Revive Pet",
    
        "^Shadow Cleave", "^Spore Wrap",} },
    { key = "Crowds", terms = {
        -- stuns / sleeps / banshees / charms / roots / taunts / interrupts
        "^Scatter", "^Intimidation", "^Charm", "^Freeze", "^Frozen",
        "^Frost Nova",
        "^Frostbomb", "^Ring of Frost", "^Deep Freeze", "^Black Ice",
        "^Poly", "^Bash", "^Batter", "^Maim", "^Kidney Shot", "^Cheap Shot",
        "^Gouge", "^Blind", "^Sap", "^Distract", "^Kick", "^Punch Harder",
        "^Rebuke", "^Pummel", "^Counterspell", "^Strike of", "^Shockwave",
        "^Concussion Blow", "^Thunder Clap", "^Cripple", "^Hamstring",
        "^Piercing Howl", "^Challenging Shout", "^Challenging Roar",
        "^Demoralizing Shout", "^Demoralizing Roar", "^Mocking Blow", "^Taunt",
        "^Disarm", "^Scatter", "^Hibernate", "^Entangling Roots",
        "^Nature's Grasp", "^Soothe Animal", "^Soothe Beasts", "^Shackle",
        "^Silence", "^Shackles", "^Psychic Scream", "^Confounding Flash",
        "^Chastise", "^Hammer of Justice", "^Hammer of Justice", "^Repentance",
        "^Turn Undead", "^Repent", "^Scare Beast", "^Tame Beast",
        "^Subjugate Demon", "^Seduction", "^Seduce", "^Cyclone",
        "^Asphyxiate", "^Freezing Trap", "^Frost Trap", "^Ensnaring Trap",
        "^Black Ice", "^Mind Soothe",
        "^Dread", "^Dread Spin", "^Druids of the Fang", "^Worm Burst",
        "^Worm Storm", "^Noxious Frenzy", "^Carnivous Gas", "^Spore Veil",
        "^Mind-numbing Poison", "^Numbing Poison",
        "^Fear$", "^Banish", "^Howl of Terror", "^Demonic Howl", "^Menace",
        "^Wrack", "^Fel Domination", "^Shield Bash", "^Enrage$", "^Tease",
        "^Blind$", "^Sap$",
    
        "^Holy Nova", "^Mana Burn", "^Fire Nova", "^Purge", "^Demon Charge", "^Meat hook", "^Meathook", "^Cower", "^Rebuke",} },
    { key = "Heal", terms = {
        "^Healing", "^Heal$", "^Regrowth", "^Rejuvenation", "^Rupture",
        "^Riptide", "^Tranquility", "^Wild Growth", "^Abolish", "^Cure",
        "^Cleanse", "^Pain Suppression", "^Gift of the Wild",
        "^Mark of the Wild", "^Avenging Wrath", "^Circle of Life",
        "^Siphon Life", "^Flash Heal", "^Greater Heal",
        "^Binding Heal", "^Chain Heal", "^Surge of Light", "^Holy Light",
        "^Holy Shock", "^Healing Light", "^Healing Wave", "^Healing Tide",
        "^Vampiric Embrace", "^Soulshatter",
    
        "^Circle of Healing", "^Wild Rejuvenation", "^Swiftmend", "^Rebirth", "^Dispel", "^Deliverance", "^Resurrection",} },
    { key = "Channel", terms = {
        "Channel", "^Volley", "^Rain of Fire", "^Blizzard", "^Trance",
        "Trance", "^Evocation", "^Drain Soul", "^Drain Life", "^Drain Mana",
        "^Soul Siphon", "^Siphon Mana", "^Hurricane", "^Consecration",
        "^Shadowguard", "^Shadowfiend", "^Homunculi", "^Healing Rain",
        "^Holy Water", "^Bloodtap", "^Frostplague Strike", "^Sniper Shot",
        "^Inferno", "^Infernal Effect", "^Eviserate", "^Runic Pen",
    } },
    { key = "Cooldown", terms = {
        "Totem", "^Call Pet", "^Dismiss Pet", "^Eyes of the Beast",
        "^Far Sight", "^Portal", "^Ritual", "^Summon", "^Unsummon",
        "^Healthstone", "^Gravyard", "^Soulstone",
        "Healthstone", "Soulstone", "Spellstone", "Firestone", "^Teleport",
        "^Create ", "^Use ", "^Cold Snap", "^Pick Pocket", "^Preparation",
        "^Reincarnation", "^Call of", "^Summon ",
    } },
    { key = "SelfDebuff", terms = {
        "^Health Funnel", "^Sacrifice", "^Hand of Sacrifice", "^Burning Rush",
        "^Blood Fury", "^Retaliate", "^Death Coil", "^Soul Siphon",
        "^Blood Leech", "^Blood Vortex", "^Blood Rage", "^Blood Sacrifice",
        "^Dark Pact", "^Pact of the", "^Shattered Illusions", "^Curse of Self",
    } },
    { key = "Buff", terms = {
        "^Blessing", "^Greater Blessing", "^Prayer of", "^Arcane Brilliance",
        "^Arcane Intellect", "^Mass Regeneration", "^Regeneration$",
        "^Mark of Valor", "^Battle Shout", "^Commanding Shout",
        "^Intimidating Shout", "^Rallying Cry", "^Battle Command",
        "^Ancestral Guidance", "^Voice of Truth", "^Salvation",
        "^Mass Salvation", "^Trueshot Aura", "^Divine Spirit",
    } },
    { key = "TargetDebuff", terms = {
        "Sting$", "Mark$", "Corruption$", "Agony$", "Immolate", "Wound",
        "^Serpent", "Faerie", "^Expose", "Expose Armor", "Sunder Armor",
        "Vulnerability", "Shock$", "Poison$", "Plague", "^Haunt",
        "^Shadow Word", "^Shadowflame", "^Death Coil", "^Deathsgrip",
        "^Death's Decree", "^Concussive", "^Distracting", "^Tranquilizing",
        "^Viper", "^Scorpid", "^Black Arrow", "Infectious",
        "^Siphon Mana", "^Spreading Pain",
        "^Malevolent", "^Torment", "^Punishment", "^Rune of", "^Unbalancing",
        "^Overpower", "^Mortal Strike", "^Shocking", "^Thunderfury",
        "^Demoralize", "^Shadow Word: Pain", "^Void Zone", "^Void Plague",
        "^Disease", "^Hex", "^Touch of", "^Blood Plague", "^Fleshrot",
        "^Bite of", "^Noxious", "^Serpent's", "^Carrion", "^Worm Burst",
        "^Blood Pet",
        "^Atrophic Poison", "^Crippling Poison", "^Occult Poison",
        "^Sebacious Poison", "^Blood Corruption", "^Hemorrhage", "^Flare",
        -- the generated DoT tails: a lasting window a class puts ON a target
        "^Moonfire", "^Sunfire", "^Insect Swarm", "^Rake", "^Rip$",
        "^Lacerate", "^Garrote", "^Deadly Poison", "^Shadow Spark",
        "^Unstable Affliction", "^Hellfire", "^Death Wish", "^Frostbrand",
        "^Righteous Judgement", "^Searing Blast", "^Living Flame",
        "^Flanking Strike", "^Abominable Strike",
        "^Heartstrike", "^Chaos Strike", "^Soul Reaper", "^Rend",
        "^Widow Sting", "^Disease Cloud", "^Frost Fever", "^Infected Bites",
        "^Immolation Trap", "^Explosive Trap", "^Black Arrow Trap",
        "Shot$", "Judgement", "^Exorcism", "^Redemption", "on Hands",
    } },
    { key = "SelfBuff", terms = {
        "Ward$", "^Aspect", "Aspect of", "^Armor", "^Ice Barrier",
        "^Mana Barrier", "^Mana Shield", "^Ice Block", "^Ice Barriers",
        "^Blink", "^Slow Fall", "^Amplify Magic", "^Dampen Magic",
        "^Seal of", "^Righteous Fury", "^Aura$", "^Wrath", "Wrath", "^Rage",
        "Rage$", "Frenzy", "Frenzy$", "^Power Word", "^Inner Fire",
        "^Inner Will", "^Divine Shield", "^Divine Protection",
        "^Shadow Protection", "^Shadowform", "^Spirit of", "^Levitate",
        "^Mind Vision", "^Fade", "^Dispersion", "^Shield Mastery",
        "^Shield Block", "^Shield Wall", "^Flurry", "^Clearcasting",
        "^Power Surge", "^Tidal Waves", "^Elemental Devastation",
        "^Bloodlust", "^Bloodrage", "^Blood Surge", "^Bloodthirst",
        "^Blood Pool", "^Blood Tap", "^Bloodburst", "^Dark Soul",
        "^Dark Transformation", "^Berserker Rage", "^Berserker Frenzy",
        "^Berserk", "Frenzy", "^Rabid", "^Bestial Wrath", "^Rapid Fire",
        "^Deterrence", "^Feign Death", "^Eagle Eye", "^Precision",
        "^Clever Strikes", "^Trick Shots", "^Heart of the Lion",
        "^Arcane Infused", "^Beast of the Unseen Path", "^Stalker's Ally",
        "^Enchant", "^Weapon Enchant", "^Sight", "^Sense", "Form$",
        "^Stride", "^Dash", "^Prowl", "^Stealth", "^Discipline", "^Focus",
        "^Endurance", "^Meditation", "^Barrier", "^Sanctuary", "^Freedom",
        "^Potion", "^Power Infusion", "^Raptor Strike", "^Raptor's",
        "^Fanaticism", "^Unyielding",
        "^Vindication", "^Crusader Strike", "^Avenging Shield", "^Blessed",
        "^Recklessness", "^Sprint", "^Blade Dance", "^Blade Flurry",
        "^Slice and Dice", "^Adrenaline Rush", "^Premeditation",
        "^Resilient", "^Remorseless", "^Evasion",
        "^Ghostly Strike", "^Glimpse of Madness", "^Sudden Death",
        "^Gladiator's Cunning", "^Spell Block", "^Single-Minded Fury",
        "^Victorious", "^Battle Forecast", "^Defensive Forecast",
        "^Forecast", "^Enraged", "^Regeneration", "^Survival Instincts",
        "^Barkskin", "^Thorns", "^Force of Nature", "^Innervate",
        "^Faerie Dragon", "^Soul Armor", "^Shadow Shield", "^Spellsteal",
        "^Chromatic Mutation", "^Frost Armor", "^Ice Armor", "^Molten Armor",
        "^Mage Armor", "^Infernalist", "^Demon Armor", "^Demon Skin",
        "^Demonic Brand", "^Demonic Grace", "^Demonic Circle",
        "^Demonic Knowledge", "^Black Hand", "^Astral Power",
        "^Fury of Stormrage", "^Frenzied Regeneration", "^Enrage",
        "^Blood Pact",
        -- the generated proc windows: a name that is only a buff of its own
        "^Backdraft", "^Decimation", "^Massive Destruction", "^Shadowburn",
        "^Vengeance", "^Wickedness", "^Shadow Trance", "^Dance of the Wicked",
        "^Infernal Armor", "^Arcane Power", "^Arcane Surge", "^Evoker",
        "^Frigid Power", "^Icy Veins", "^Temporal Anomaly",
        "^Chronostatic Preservation", "^Armor of Faith", "^Eye of the Void",
        "^Counterattack", "^Rapid Recuperation", "^Savage Roar",
        "^Main Gauche", "^Redirect", "^Riposte", "^Cheat Death",
        "^Cheating Death", "^Echoes of", "^Howling Blade", "^Rampage",
        "^Retaliation", "^Slammin", "^Sweeping Strikes", "^Sword and Board",
        "^Taste for Blood", "^Templar", "^Elemental Mastery",
        "^Way of", "^Feral Spirit", "^Earth Shield", "^Water Shield",
        "^Energized Shield", "^Regeneration", "^Windfury",
        "^Soul Fire", "^Soul Harvest", "^Shadow Spark",
    
        "Stance", "^Shot", "^Slam", "^Whirlwind", "^Intercept",
        "^Intervene", "^Revenge", "^Charge", "^Last Stand", "^Raging Blow",
        "^Victory Rush", "^Spearing Strike", "^Mongoose", "^Disengage",
        "^Conflagrate", "^Immolation Aura", "^Grimoire", "^Chaos Bolt",
        "^Metamorphosis", "^Netherwind", "^Displacement", "^Arcane Barrage",
        "^Rewind Time", "^Inner Focus", "^Primal Bite", "^Tree of Life",
        "^Shifting Power", "^Feral Charge", "^Nature's Swiftness",
        "^Vanish", "^Feint", "^Between the Eyes", "^Vigor", "^Cold Blood",
        "^Shadowstep", "^Lava Lash", "^Molten Blast", "^Ghost Wolf",
        "^Lightning Shield", "^Ancestral Spirit", "^Chain Lightning",
        "^Flametongue Weapon", "^Rockbiter Weapon", "^Fireblood",
        "^Revealed Flaw", "^Savage", "^Purify", "Slam$", "Aura",
        "^Shield of Righteousness", "^Hammer of the Righteous",
        "^Divine", "^Revoke",
    } },
}

--- One term of a band against one name: `^x` front-anchored, `x$` end-anchored,
--- `^x$` the whole name, plain substring otherwise. Every compare is plain
--- (no pattern characters), so a name with `-`, `%`, `(`, `!` or `:` in it
--- (the data has all five) can not break the match.
local function termMatches(name, term)
    local front = term:sub(1, 1) == "^"
    local back = term:sub(-1) == "$"
    local core = term
    if front then core = core:sub(2) end
    if back then core = core:sub(1, -2) end
    if core == "" then return false end
    if front and back then return name == core end
    if front then return name:sub(1, #core) == core end
    if back then
        return #name >= #core and name:sub(-#core) == core
    end
    return name:find(core, 1, true) ~= nil
end

local function kindFor(name)
    for _, rule in ipairs(KIND_RULES) do
        local terms = rule.terms
        for i = 1, #terms do
            if termMatches(name, terms[i]) then return rule.key end
        end
    end
    return "Default"
end

--- The kind bands in decision order (the page/tests read the vocabulary).
function Registry.KindBands()
    local out = {}
    for i, rule in ipairs(KIND_RULES) do out[i] = rule.key end
    out[#out + 1] = "Default"
    return out
end

--- The colour BAND a name's shape puts it in: the `KIND_RULES` decision,
--- before any registry entry exists. The diagnostics/tests read it (the
--- coverage census does); the renderer reads the registered entry's kind
--- through `Registry.KindFor` below.
function Registry._kindFor(name)
    return kindFor(name)
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

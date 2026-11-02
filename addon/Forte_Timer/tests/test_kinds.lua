-- addon/Forte_Timer/tests/test_kinds.lua
-- The kind vocabulary's COVERAGE. The renderer colours a row from the kind
-- the registry's name-shape rules give it (`Core/Registry.lua` `KIND_RULES`),
-- so a DoT, a curse, a crowd-control cast, a heal, a self window, a channel,
-- a pet spell and a group buff each paint the row the colour that says what
-- the cast IS. A spell that falls through to `Default` says nothing, and a
-- rule that can not match (the shipped table's regex-shaped strings -- `|`
-- has no meaning in a Lua pattern, and an interior `$` is literal) is the
-- same fall-through written down as a rule. So: every generated tracked
-- spell of every class must land on a real band.
--
-- Name shape only, exactly as the original's spell table is keyed by NAME:
-- this suite never reads, writes, prints or asserts a spell ID.

local FX = ForteXorcist
local Registry = FX.Timer.Registry
local Laws = FX.Timer.Laws

local CLASSES = { "Hunter", "Warlock", "Mage", "Priest", "Druid", "Rogue",
    "Warrior", "Shaman", "Paladin" }

-- The tracked list of one class: the registry's own seam in the game, the
-- generated class data in the simulator (where Forte_Timer's Data/ namespace
-- is not on the load path). Both sources are the GENERATED files; nothing
-- here hand-lists a spell.
local function trackedFor(cls)
    -- The generated data file of the class, never the live registry: the
    -- registry is built for the current class only, and a coverage census
    -- has to walk every class's generated list.
    local data = Registry.DataFor and Registry.DataFor(cls)
    local names = {}
    if type(data) == "table" then
        for _, sp in pairs(data) do
            if type(sp) == "table" and type(sp.name) == "string" then
                names[#names + 1] = sp.name
            end
        end
    end
    return names
end

test("the classifier reads the colour intent out of a spell name", function()
    assertEquals("TargetDebuff", Registry._kindFor("Serpent Sting"))
    assertEquals("TargetDebuff", Registry._kindFor("Hunter's Mark"))
    assertEquals("TargetDebuff", Registry._kindFor("Immolate"))
    assertEquals("TargetDebuff", Registry._kindFor("Immolation Trap"))
    assertEquals("TargetDebuff", Registry._kindFor("Earth Shock"))
    assertEquals("TargetDebuff", Registry._kindFor("Deadly Poison V"))
    assertEquals("TargetDebuff", Registry._kindFor("Moonfire"))
    assertEquals("TargetDebuff", Registry._kindFor("Expose Armor"))
    assertEquals("Curse", Registry._kindFor("Curse of the Elements"))
    assertEquals("Curse", Registry._kindFor("Curse of Exhaustion"))
    assertEquals("Curse", Registry._kindFor("Hex of Weakness"))
    assertEquals("Bane", Registry._kindFor("Bane of Doom"))
    assertEquals("Crowds", Registry._kindFor("Scatter Shot"))
    assertEquals("Crowds", Registry._kindFor("Freezing Trap"))
    assertEquals("Crowds", Registry._kindFor("Sap"))
    assertEquals("Crowds", Registry._kindFor("Thunder Clap"))
    assertEquals("Crowds", Registry._kindFor("Kidney Shot"))
    assertEquals("Heal", Registry._kindFor("Regrowth"))
    assertEquals("Heal", Registry._kindFor("Abolish Disease"))
    assertEquals("Buff", Registry._kindFor("Prayer of Fortitude"))
    assertEquals("SelfBuff", Registry._kindFor("Bestial Wrath"))
    assertEquals("SelfBuff", Registry._kindFor("Ice Block"))
    assertEquals("SelfBuff", Registry._kindFor("Seal of Command"))
    assertEquals("SelfBuff", Registry._kindFor("Backdraft"))
    assertEquals("SelfDebuff", Registry._kindFor("Health Funnel"))
    assertEquals("Pet", Registry._kindFor("Growl"))
    assertEquals("Pet", Registry._kindFor("Mend Pet"))
    assertEquals("Buff", Registry._kindFor("Blessing of Kings"))
    assertEquals("Channel", Registry._kindFor("Drain Soul"))
    assertEquals("Channel", Registry._kindFor("Blizzard"))
    assertEquals("Cooldown", Registry._kindFor("Mana Tide Totem"))
    assertEquals("Cooldown", Registry._kindFor("Portal: Stormwind"))
    assertEquals("Default", Registry._kindFor("Totally Made Up Nonsense"))
end)

test("regex shaped rules are not rules in Lua", function()
    -- `Stun$|^Charm` and every other `|`-joined string the first rules table
    -- shipped is LITERAL text to a Lua pattern: such a rule matched NOTHING,
    -- every class sat on Default, and every row painted the same orange. The
    -- term matcher reads a plain substring, a `^` prefix, a `$` suffix, or
    -- both for an exact name -- and nothing else.
    assertEquals(2, select(2, ("A|B"):find("|")))
    assertEquals("Default", Registry._kindFor("Zqwerty Nonexistent Name"))
    assertEquals("Crowds", Registry._kindFor("Charm"))
end)

test("the kind vocabulary is the skin vocabulary", function()
    -- A band whose skin entry does not exist paints Default and lies about
    -- the cast: the shipped `COLOR_KEY.Crowds = "Crowd"` was exactly this,
    -- because the skin spells the band `Crowds`.
    local s = FX.Timer.Skin
    for _, kind in ipairs(Registry.KindBands()) do
        local key = Laws.COLOR_KEY[kind] or "Default"
        local col = s[key]
        assertEquals("table", type(col))
        if type(col) == "table" then
            assertEquals("number", type(col[1]))
        end
    end
    assertEquals("Crowds", Laws.COLOR_KEY.Crowds)
end)

test("every generated tracked spell lands on a palette band", function()
    local total, defaulted, report, classes = 0, 0, {}, 0
    for _, cls in ipairs(CLASSES) do
        local spells = trackedFor(cls)
        if #spells > 0 then
            classes = classes + 1
            local n, d, miss = 0, 0, {}
            for _, sp in ipairs(spells) do
                local name = type(sp) == "table" and sp.name or sp
                if type(name) == "string" and name ~= "" then
                    n = n + 1
                    if Registry._kindFor(name) == "Default" then
                        d = d + 1
                        miss[#miss + 1] = name
                    end
                end
            end
            total = total + n
            defaulted = defaulted + d
            report[#report + 1] = cls .. " " .. d .. "/" .. n
                .. (d > 0 and ("[" .. table.concat(miss, ",") .. "]") or "")
        end
    end
    if classes == 0 then
        print("[kinds] SKIP: no generated class data is loaded in this run")
        return
    end
    local line = "[kinds] tracked=" .. total .. " Default=" .. defaulted
        .. " | " .. table.concat(report, " ")
    print(line)
    -- The harness captures a test's printout, so the census also lands in a
    -- file the run's operator can read.
    if io and io.open then
        local f = io.open("/tmp/kinds_report.txt", "w")
        if f then f:write(line .. "\n"); f:close() end
    end
    -- Measured in the simulator (run-tests Forte_Timer, 2026-11-02): every
    -- generated tracked spell of all nine classes -- 366 names -- lands on a
    -- real band. A band that can not match (the regex-shaped shipped rules,
    -- which left every class on Default) trips this at once.
    assertTrue(total > 100)
    assertEquals(0, defaulted,
        "spells with no colour intent: " .. table.concat(report, " "))
end)

-- addon/Forte_Cooldown/tests/test_shared_cooldowns.lua
-- Shared cooldowns (docs/research/live-hunter / live-shaman / live-mage
-- 2026-11-09): Engine:Build used to drop the generated rows' `shares` link
-- (only AddExtras copied it), and a pair link cannot express a GROUP (the four
-- Hunter traps' one 30 s lockout, the Shaman shocks). The engine now honours
-- `shares` for every tracked row and starts every OTHER tracked row of an
-- equal non-zero `cooldownCategory` (Core/Engine.lua file header: one hop, the
-- partner's own duration, never shortening a longer partner, pet/threat
-- categories never group).
--
-- Part 1 is the CENSUS: every class's generated data, built through the real
-- Build + AddExtras with everything known, lists every category group of >=2
-- tracked names. Each group is written out below, so each is deliberate and
-- any NEW group (a data refresh, a new spell) trips this test: the owner of
-- the change decides whether it is a real shared lockout and updates the
-- table (or adds the category to Engine.UNSHARED_CATEGORIES). The excluded
-- groups are pinned too.
-- Part 2 drives the behaviours through the real Module cast path (the
-- UNIT_SPELLCAST_SUCCEEDED 4-slot catalog payload on the module's own event
-- frame) with the shipped Hunter / Shaman data, plus synthetic rows for the
-- shapes the data cannot give (the 3-member shock group, a cyclic `shares`
-- ring).
--
-- Sharing law (test_engine.lua / test_m3a_engine_racials.lua): the Engine is
-- the session's one instance, so the file keeps its own storage, restores the
-- storage + the class build at the end, and every seam it takes (C_Spell,
-- fixture data) is handed back.

local FX = ForteXorcist
local Engine = FX.Cooldown.Engine
local M = FX.Cooldown.Module

local CLASSES = { "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE",
                  "SHAMAN", "WARLOCK", "WARRIOR" }
for _, c in ipairs(CLASSES) do FX.LoadClassAddOn(c) end

local originalStorage = Engine.learned

local function allKnown() return true end
local function near(actual, expected)
    return assertTrue(math.abs(actual - expected) < 1e-6)
end
local function titleCase(c) return c:sub(1, 1) .. c:sub(2):lower() end

local function build(classFile)
    Engine:AttachStorage({})
    local n = Engine:Build(classFile, allKnown)
    assertNotNil(n, "no generated data for " .. classFile)
    Engine:AddExtras(allKnown)
    wipe(Engine.entries)
end

local function countEntries()
    local n = 0
    for _ in pairs(Engine.entries) do n = n + 1 end
    return n
end

-- ------------------------------------------------------------------ census --
--- "<cat>=<name>|<name>" lines, ascending by category, for every group of >=2
--- tracked names. `byEngine` true: the engine's own `category` (what the group
--- rule acts on); false: the RAW generated category of the tracked rows.
local function groupsOf(classFile, byEngine)
    local data = FX.Data[titleCase(classFile)]
    local cats = {}
    for name, t in pairs(Engine.tracked) do
        local cat = byEngine and t.category
            or (not byEngine and data[t.dataId].cooldownCategory)
        if type(cat) == "number" and cat ~= 0 then
            cats[cat] = cats[cat] or {}
            table.insert(cats[cat], name)
        end
    end
    local keys = {}
    for cat, names in pairs(cats) do
        if #names >= 2 then keys[#keys + 1] = cat end
    end
    table.sort(keys)
    local out = {}
    for _, cat in ipairs(keys) do
        table.sort(cats[cat])
        out[#out + 1] = cat .. "=" .. table.concat(cats[cat], "|")
    end
    return out
end

-- The deliberate groups (Engine group rule). Sources: the class research
-- notes (docs/research/live-<class>-2026-11-09.md): Hunter traps 411 / Multi-
-- Shot+Aimed Shot 2 / Arcane Shot+Summon Hawk 1173 (Enchanted Flare+Flare is
-- one flare line); Shaman shocks 19 (Earth Shock 10414 / Flame Shock 10448 /
-- Frost Shock 10473 -- live 70862 store / review 2026-11-10: Earth Shock moved
-- off the 2171 decoy 408690 onto the learnable Rank 7 row, category 19, so the
-- engine now enforces a real THREE-spell shared 6 s lockout); Mage Ice Lance
-- 1240047 + Fire Blast 10199 on category 19 (the Rank 7 trainer row replaced
-- the Season-of-Discovery 400623 copy that tied it on level -- the same
-- shared 8 s group Ice Lance always carried), Fire/Frost Ward 56; Paladin
-- Divine Shield+Protection 37; Rogue Kidney Shot+Between the Eyes 270;
-- Warrior Overpower+Revenge 65, Pummel+Shield Bash 88, Mortal Strike+
-- Bloodthirst+Shield Slam 971; Druid Feral Charge+Skull Bash 2182.
local EXPECTED_GROUPS = {
    DRUID   = { "2182=Feral Charge|Skull Bash" },
    HUNTER  = { "2=Aimed Shot|Multi-Shot",
                "411=Explosive Trap|Freezing Trap|Frost Trap|Immolation Trap",
                "1173=Arcane Shot|Summon Hawk",
                "2368=Enchanted Flare|Flare" },
    MAGE    = { "19=Fire Blast|Ice Lance", "56=Fire Ward|Frost Ward" },
    PALADIN = { "37=Divine Protection|Divine Shield",
                -- live 70862 store / review 2026-11-10: Holy Strike 10333
                -- (cd 10 s, category 2404) shares the 2404 lockout with
                -- Hammer of the Righteous (docs/research/live-paladin-
                -- 2026-11-09.md, the Holy Strike row); both are tracked now.
                "2404=Hammer of the Righteous|Holy Strike" },
    PRIEST  = {},
    ROGUE   = { "270=Between the Eyes|Kidney Shot" },
    SHAMAN  = { "19=Earth Shock|Flame Shock|Frost Shock" },
    WARLOCK = {},
    WARRIOR = { "65=Overpower|Revenge", "88=Pummel|Shield Bash",
                "971=Bloodthirst|Mortal Strike|Shield Slam" },
}

-- The raw category groups the engine REFUSES (Engine.UNSHARED_CATEGORIES): the
-- pet/threat label 82 (Rogue Feint+Tease, Warlock Menace+Soothing Kiss), the
-- Hunter's pet abilities (19: Bite/Scorpid Poison; 63: Pinch/Tendon Rip/Web).
-- Live 70862 store / review 2026-11-10: the Druid entry LEFT -- Cower 16697
-- (the Hunter pet's Cower, category 82, which grouped with Growl) is the
-- druid's own Cower 9892 now, category 84, shared with no tracked row.
local EXPECTED_EXCLUDED = {
    -- (DRUID: Growl 82 stands alone now; Cower is 84)
    HUNTER  = { "19=Bite|Scorpid Poison", "63=Pinch|Tendon Rip|Web",
                "82=Disengage|Growl" },
    ROGUE   = { "82=Feint|Tease" },
    WARLOCK = { "82=Menace|Soothing Kiss" },
}

test("census: every category group of >=2 tracked names is deliberate", function()
    for _, classFile in ipairs(CLASSES) do
        build(classFile)
        local got = table.concat(groupsOf(classFile, true), "\n")
        local want = table.concat(EXPECTED_GROUPS[classFile], "\n")
        assertEquals(want, got, classFile .. ": the engine's category groups "
            .. "changed -- a new group must be a deliberate, verified shared "
            .. "lockout (update EXPECTED_GROUPS), a decoy goes to "
            .. "Engine.UNSHARED_CATEGORIES")
    end
end)

test("census: the refused category groups are pinned too", function()
    for _, classFile in ipairs(CLASSES) do
        build(classFile)
        -- raw groups minus the engine's: what UNSHARED_CATEGORIES removed.
        local engine = {}
        for _, g in ipairs(groupsOf(classFile, true)) do engine[g] = true end
        local refused = {}
        for _, g in ipairs(groupsOf(classFile, false)) do
            if not engine[g] then refused[#refused + 1] = g end
        end
        assertEquals(table.concat(EXPECTED_EXCLUDED[classFile] or {}, "\n"),
            table.concat(refused, "\n"),
            classFile .. ": the refused (pet/threat) category groups changed")
    end
end)

test("Build carries `shares` and `category` onto every tracked row", function()
    build("HUNTER")
    assertEquals(411, Engine.tracked["Freezing Trap"].category)
    assertEquals(2, Engine.tracked["Multi-Shot"].category)
    assertEquals("Arcane Shot", Engine.tracked["Summon Hawk"].shares)
    assertNil(Engine.tracked["Growl"].category, "the pet/threat label 82 groups nothing")
    assertNil(Engine.tracked["Bestial Wrath"].category, "a row without a category")
    -- A `shares` link on a NON-racial row rides Build (the live-hunter §3.2
    -- bug: only AddExtras copied it).
    local key = "Zzshares"
    FX.Data[key] = {
        [1] = { id = 1, name = "Alpha", cooldownMs = 10000, shares = "Beta" },
        [2] = { id = 2, name = "Beta", cooldownMs = 10000 },
    }
    Engine:AttachStorage({})
    Engine:Build("ZZSHARES", allKnown)
    FX.Data[key] = nil
    assertEquals("Beta", Engine.tracked["Alpha"].shares)
end)

-- ------------------------------------------------------ real Module cast path --
local ids = {}                -- fixture id -> name for the client seam
local castN = 0
local realCSpell

local function installSeam()
    realCSpell = _G.C_Spell
    _G.C_Spell = setmetatable({
        GetSpellInfo = function(x)
            if type(x) == "number" and ids[x] then
                return { spellID = x, name = ids[x] }
            end
            return realCSpell and realCSpell.GetSpellInfo
                and realCSpell.GetSpellInfo(x) or nil
        end,
    }, { __index = realCSpell })
end
local function removeSeam()
    _G.C_Spell = realCSpell
    realCSpell = nil
    wipe(ids)
end

local function enableModule()
    if not M._eventFrame then M:OnEnable() end
    assertNotNil(M._eventFrame, "the module's event frame is bound at OnEnable")
end

--- One resolved cast of `name` (the class's data id) through the module's own
--- frame script: (unit, castGUID, spellID, castBarID), the catalog's payload.
local function cast(classFile, name)
    local id = FX.Data[titleCase(classFile) .. "ByName"][name]
    assertNotNil(id, name .. " has no generated id")
    ids[id] = name
    castN = castN + 1
    local f = M._eventFrame
    local h = f:GetScript("OnEvent")
    assertNotNil(h, "the frame carries its OnEvent script")
    local ok, err = pcall(h, f, "UNIT_SPELLCAST_SUCCEEDED", "player",
        "Cast-FxShared-" .. castN, id, 11)
    assertTrue(ok, "the real OnEvent script raised: " .. tostring(err))
end

local function withClass(classFile, fn)
    enableModule()
    build(classFile)
    installSeam()
    local ok, err = pcall(fn)
    removeSeam()
    wipe(Engine.entries)
    assertTrue(ok, tostring(err))
end

test("a trap cast starts all four traps (one 30 s group)", function()
    withClass("HUNTER", function()
        cast("HUNTER", "Freezing Trap")
        local first = Engine.entries["Freezing Trap"]
        assertNotNil(first, "the cast trap has no bar")
        for _, trap in ipairs({ "Frost Trap", "Immolation Trap", "Explosive Trap" }) do
            local e = Engine.entries[trap]
            assertNotNil(e, trap .. " did not start with Freezing Trap")
            near(30, e.duration)
            near(first.start, e.start)
            assertTrue(e.predicted)
            assertEquals("cast", e.source)
        end
        assertEquals(4, countEntries(), "exactly the four traps")
        -- and from another member: Explosive Trap starts the other three.
        wipe(Engine.entries)
        cast("HUNTER", "Explosive Trap")
        assertEquals(4, countEntries())
        assertNotNil(Engine.entries["Freezing Trap"])
    end)
end)

test("Multi-Shot starts Aimed Shot, and back (shared 6 s, category 2)", function()
    withClass("HUNTER", function()
        cast("HUNTER", "Multi-Shot")
        local aimed = Engine.entries["Aimed Shot"]
        assertNotNil(aimed, "Multi-Shot did not start Aimed Shot")
        near(6, aimed.duration)
        assertEquals(2, countEntries(), "Arcane Shot (1173) is a different group")
        wipe(Engine.entries)
        cast("HUNTER", "Aimed Shot")
        assertNotNil(Engine.entries["Multi-Shot"])
        assertNil(Engine.entries["Arcane Shot"])
    end)
end)

test("the Summon Hawk <-> Arcane Shot pair survives the group rule", function()
    withClass("HUNTER", function()
        cast("HUNTER", "Arcane Shot")
        assertNotNil(Engine.entries["Summon Hawk"])
        assertNil(Engine.entries["Multi-Shot"])
        assertEquals(2, countEntries())
    end)
end)

test("a Flame Shock cast starts Frost Shock (the shipped category 19 rows)", function()
    withClass("SHAMAN", function()
        cast("SHAMAN", "Flame Shock")
        local frost = Engine.entries["Frost Shock"]
        assertNotNil(frost, "Flame Shock did not start Frost Shock")
        near(6, frost.duration)
        -- every OTHER tracked row of the data's category-19 group, no more
        local group = 0
        for _, t in pairs(Engine.tracked) do
            if t.category == 19 then group = group + 1 end
        end
        assertEquals(group, countEntries())
    end)
end)

-- Live 70862 store / review 2026-11-10: the shipped (not synthetic) rows of the
-- three groups the data refresh made real. Each cast starts exactly the
-- partners the census names, with the partner's own duration.
test("shipped Shaman data: Earth Shock starts BOTH other shocks, never Lightning Shield",
function()
    withClass("SHAMAN", function()
        cast("SHAMAN", "Earth Shock")
        for _, shock in ipairs({ "Flame Shock", "Frost Shock" }) do
            local e = Engine.entries[shock]
            assertNotNil(e, "Earth Shock did not start " .. shock)
            near(6, e.duration)
        end
        assertEquals(3, countEntries(), "the three shocks, no more")
        assertNil(Engine.entries["Lightning Shield"],
            "a shield is no shock (10432 carries no category)")
        -- and from the far end of the group
        wipe(Engine.entries)
        cast("SHAMAN", "Frost Shock")
        assertNotNil(Engine.entries["Earth Shock"])
        assertEquals(3, countEntries())
    end)
end)

test("shipped Mage data: Fire Blast 10199 and Ice Lance share the 8 s category 19",
function()
    withClass("MAGE", function()
        cast("MAGE", "Fire Blast")
        local lance = Engine.entries["Ice Lance"]
        assertNotNil(lance, "Fire Blast did not start Ice Lance")
        near(8, lance.duration)
        assertEquals(2, countEntries())
        wipe(Engine.entries)
        cast("MAGE", "Ice Lance")
        assertNotNil(Engine.entries["Fire Blast"])
        assertEquals(2, countEntries())
    end)
end)

test("shipped Paladin data: Holy Strike starts Hammer of the Righteous (category 2404)",
function()
    withClass("PALADIN", function()
        cast("PALADIN", "Holy Strike")
        local hammer = Engine.entries["Hammer of the Righteous"]
        assertNotNil(hammer, "Holy Strike did not start Hammer of the Righteous")
        assertEquals(2, countEntries())
    end)
end)

test("the 3-member shock group: any shock starts the other two", function()
    -- Shape of the pinned fix (Earth Shock on category 19): synthetic rows, so
    -- this holds whether or not the data pin has landed.
    local key = "Zzshock"
    FX.Data[key] = {
        [1] = { id = 1, name = "Earth Shock", cooldownMs = 6000, cooldownCategory = 19 },
        [2] = { id = 2, name = "Flame Shock", cooldownMs = 6000, cooldownCategory = 19 },
        [3] = { id = 3, name = "Frost Shock", cooldownMs = 6000, cooldownCategory = 19 },
        [4] = { id = 4, name = "Lightning Shield", cooldownMs = 10000 },
    }
    FX.Data[key .. "ByName"] = { ["Earth Shock"] = 1, ["Flame Shock"] = 2,
                                 ["Frost Shock"] = 3, ["Lightning Shield"] = 4 }
    local ok, err = pcall(function()
        for _, shock in ipairs({ "Earth Shock", "Flame Shock", "Frost Shock" }) do
            withClass("ZZSHOCK", function()
                cast("ZZSHOCK", shock)
                assertEquals(3, countEntries(), shock .. " must start all three")
                assertNil(Engine.entries["Lightning Shield"])
            end)
        end
    end)
    FX.Data[key], FX.Data[key .. "ByName"] = nil, nil
    assertTrue(ok, tostring(err))
end)

test("a partner already on a longer cooldown is not shortened", function()
    withClass("SHAMAN", function()
        local now = GetTime()
        -- A plain read anchors Frost Shock on a 60 s window (a talent-stretched
        -- cooldown); the learned 6 s is then forgotten so the partner's own
        -- duration (6 s) is SHORTER than what remains.
        assertEquals("anchored", Engine:OnRead("Frost Shock", now, 60, now))
        Engine.learned["Frost Shock"] = nil
        local before = Engine.entries["Frost Shock"]
        local endBefore = before.endTime
        cast("SHAMAN", "Flame Shock")
        assertNotNil(Engine.entries["Flame Shock"])
        assertTrue(Engine.entries["Frost Shock"] == before,
            "the running partner window was replaced")
        near(endBefore, Engine.entries["Frost Shock"].endTime)
        assertEquals("read", before.source)
        assertTrue(before.anchored, "the read certification survived")
        -- The converse: a partner with LESS time left is restarted.
        Engine.entries["Frost Shock"].endTime = now + 1
        cast("SHAMAN", "Flame Shock")
        assertTrue(Engine.entries["Frost Shock"].endTime > now + 1)
    end)
end)

test("the client read stays the truth for a predicted partner", function()
    withClass("HUNTER", function()
        cast("HUNTER", "Freezing Trap")
        local frost = Engine.entries["Frost Trap"]
        assertTrue(frost.predicted)
        -- A plain anchoring read (a 20 s real lockout) corrects the prediction.
        local now = GetTime()
        assertEquals("anchored", Engine:OnRead("Frost Trap", now, 20, now))
        near(20, frost.duration)
        assertFalse(frost.predicted)
        assertTrue(frost.anchored)
        -- A plain "ready" read after the grace clears a predicted partner.
        local later = Engine.entries["Explosive Trap"].start
            + Engine.PREDICTION_GRACE + 1
        assertEquals("cleared", Engine:OnRead("Explosive Trap", 0, 0, later))
        assertNil(Engine.entries["Explosive Trap"])
        -- ...and inside the grace the read-lag law still holds.
        assertEquals("ignored", Engine:OnRead("Immolation Trap", 0, 0,
            Engine.entries["Immolation Trap"].start + 0.1))
    end)
end)

test("no loop: a cyclic `shares` ring plus a category start each row once",
function()
    local key = "Zzring"
    FX.Data[key] = {
        [1] = { id = 1, name = "Ra", cooldownMs = 10000, shares = "Rb", cooldownCategory = 7 },
        [2] = { id = 2, name = "Rb", cooldownMs = 10000, shares = "Rc", cooldownCategory = 7 },
        [3] = { id = 3, name = "Rc", cooldownMs = 10000, shares = "Ra" },
        [4] = { id = 4, name = "Rd", cooldownMs = 10000, shares = "Rd" },
    }
    FX.Data[key .. "ByName"] = { Ra = 1, Rb = 2, Rc = 3, Rd = 4 }
    local realOnCast = Engine.OnCast
    local calls = {}
    local ok, err = pcall(function()
        withClass("ZZRING", function()
            Engine.OnCast = function(self, name, now, partner)
                calls[#calls + 1] = name .. (partner and "*" or "")
                return realOnCast(self, name, now, partner)
            end
            cast("ZZRING", "Ra")
            Engine.OnCast = realOnCast
            -- Ra: a pair link to Rb, Rc's link back to Ra, the 7 group with Rb.
            -- One hop: Rb and Rc start (once each), Rd (self-share) does not.
            table.sort(calls)
            assertEquals("Ra,Rb*,Rc*", table.concat(calls, ","))
            assertEquals(3, countEntries())
            assertNil(Engine.entries["Rd"])
            -- A self-share is no partner of itself.
            wipe(Engine.entries)
            calls = {}
            Engine.OnCast = function(self, name, now, partner)
                calls[#calls + 1] = name
                return realOnCast(self, name, now, partner)
            end
            cast("ZZRING", "Rd")
            Engine.OnCast = realOnCast
            assertEquals("Rd", table.concat(calls, ","))
        end)
    end)
    Engine.OnCast = realOnCast
    FX.Data[key], FX.Data[key .. "ByName"] = nil, nil
    assertTrue(ok, tostring(err))
end)

test("rows without a category (and the pet/threat label) are untouched", function()
    withClass("HUNTER", function()
        -- No category at all.
        cast("HUNTER", "Bestial Wrath")
        assertEquals(1, countEntries())
        wipe(Engine.entries)
        -- A one-member category.
        cast("HUNTER", "Rapid Fire")
        assertEquals(1, countEntries())
        wipe(Engine.entries)
        -- 82: Growl and Disengage share only the label; 19: the pet pair.
        cast("HUNTER", "Growl")
        assertEquals(1, countEntries())
        assertNil(Engine.entries["Disengage"])
        wipe(Engine.entries)
        cast("HUNTER", "Bite")
        assertEquals(1, countEntries())
        assertNil(Engine.entries["Scorpid Poison"])
    end)
    withClass("DRUID", function()
        cast("DRUID", "Growl")
        assertEquals(1, countEntries())
        assertNil(Engine.entries["Cower"])
    end)
    withClass("ROGUE", function()
        cast("ROGUE", "Feint")
        assertEquals(1, countEntries())
        assertNil(Engine.entries["Tease"])
    end)
end)

test("restore the session's class build and storage", function()
    wipe(Engine.entries)
    Engine:AttachStorage(originalStorage)
    if FX._playerClass then
        Engine:Build(FX._playerClass, M.IsKnown)
        Engine:AddExtras(M.IsKnown)
    end
    assertEquals(originalStorage, Engine.learned, "the session storage is handed back")
end)

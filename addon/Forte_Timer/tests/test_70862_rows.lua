-- addon/Forte_Timer/tests/test_70862_rows.lua
-- The Spell Timer's side of the live 70862 store / review 2026-11-10 data
-- refresh: the corrected picks that change WHICH rows the registry draws and
-- how long they run. Forte_Cooldown/tests/test_70707_overlay.lua pins the ids
-- themselves (the census of corrected picks); this file pins what the Timer
-- built from them, so a refresh that silently re-picks a decoy (Corruption
-- 1223963 at 12 s, Lightning Shield 28821 with no window, ...) goes RED on the
-- row the player would see.
--
-- The registry is rebuilt per class (the game seam) and handed back to the
-- profile class at the end: the framework has no teardown.

local FX = ForteXorcist
local Registry = FX.Timer.Registry

for _, cls in ipairs({ "WARLOCK", "SHAMAN", "ROGUE", "DRUID", "MAGE" }) do
    FX.LoadClassAddOn(cls)
end

--- name -> copy of the fields this file asserts, for one class's registry.
local function registryFor(classFile)
    Registry:AttachStorage({})
    local n = Registry:Build(classFile)
    assertTrue(n and n > 0, "no registry for " .. tostring(classFile))
    local out = {}
    for name, e in pairs(Registry.entries) do
        out[name] = { dataId = e.dataId, duration = e.duration,
                      tickEvery = e.tickEvery, maxStack = e.maxStack,
                      noTarget = e.noTarget }
    end
    return out
end

test("70862 Warlock: Corruption 11672 runs 18 s on a 3 s tick, Unstable Affliction 427717 18 s",
function()
    local w = registryFor("WARLOCK")
    assertNotNil(w["Corruption"], "Corruption is not tracked")
    assertEquals(11672, w["Corruption"].dataId)
    assertEquals(18, w["Corruption"].duration, "Corruption is 18 s, not the 12 s decoy")
    assertEquals(3, w["Corruption"].tickEvery)
    assertNotNil(w["Unstable Affliction"], "Unstable Affliction is not tracked")
    assertEquals(427717, w["Unstable Affliction"].dataId)
    assertEquals(18, w["Unstable Affliction"].duration)
    assertEquals(3, w["Unstable Affliction"].tickEvery)
    -- Summon Voidwalker 697 is permanent (-1): no Timer row, same as the
    -- Abyss Shard decoy it replaced (values identical).
    assertNil(w["Summon Voidwalker"], "a permanent summon drew a Timer row")
end)

test("70862 Shaman: Lightning Shield 10432 now draws a 600 s caster-side Timer row",
function()
    local s = registryFor("SHAMAN")
    local ls = s["Lightning Shield"]
    assertNotNil(ls, "Lightning Shield has no Timer row (28821's -1 sentinel is back?)")
    assertEquals(10432, ls.dataId)
    assertEquals(600, ls.duration)
    assertEquals(true, ls.noTarget)
    -- Earth Shock 10414: the 2 s window of the learnable Rank 7 row.
    assertNotNil(s["Earth Shock"])
    assertEquals(10414, s["Earth Shock"].dataId)
    assertEquals(2, s["Earth Shock"].duration)
end)

test("70862 Rogue: the new poison ranks and Venom are tracked, Venom paints SelfBuff",
function()
    local r = registryFor("ROGUE")
    for _, p in ipairs({ { "Deadly Poison II", 2819 }, { "Deadly Poison III", 11353 },
                         { "Deadly Poison IV", 11354 } }) do
        local e = r[p[1]]
        assertNotNil(e, p[1] .. " is not tracked")
        assertEquals(p[2], e.dataId)
        assertEquals(12, e.duration)
        assertEquals(3, e.tickEvery)
        assertEquals(5, e.maxStack)
        assertEquals("TargetDebuff", Registry._kindFor(p[1]))
    end
    assertNotNil(r["Mind-numbing Poison II"], "Mind-numbing Poison II is not tracked")
    assertEquals(8692, r["Mind-numbing Poison II"].dataId)
    assertEquals(12, r["Mind-numbing Poison II"].duration)
    assertEquals("Crowds", Registry._kindFor("Mind-numbing Poison II"))
    -- Venom 1310703: the 6 s self aura Shank casts. No term matched it before
    -- 2026-11-10 (Default band): `^Venom$` in SelfBuff, exact so the
    -- Venomhide Poison coat still classes by its "Poison$" TargetDebuff term.
    assertNotNil(r["Venom"], "Venom is not tracked")
    assertEquals(1310703, r["Venom"].dataId)
    assertEquals(6, r["Venom"].duration)
    assertEquals("SelfBuff", Registry._kindFor("Venom"))
    assertEquals("TargetDebuff", Registry._kindFor("Venomhide Poison"))
end)

test("70862 Druid: Thorns 9910 is the 600 s Rank 6 buff, Dash 9821 the 15 s window, Abolish Poison 2893",
function()
    local d = registryFor("DRUID")
    assertNotNil(d["Thorns"], "Thorns is not tracked")
    assertEquals(9910, d["Thorns"].dataId)
    assertEquals(600, d["Thorns"].duration)
    assertNotNil(d["Dash"], "Dash is not tracked")
    assertEquals(9821, d["Dash"].dataId)
    assertEquals(15, d["Dash"].duration)
    assertEquals(true, d["Dash"].noTarget)
    assertNotNil(d["Abolish Poison"], "Abolish Poison is not tracked")
    assertEquals(2893, d["Abolish Poison"].dataId)
    assertEquals(8, d["Abolish Poison"].duration)
    assertEquals(2, d["Abolish Poison"].tickEvery)
    -- Cower is a pure cooldown row (no window): the Timer draws nothing.
    assertNil(d["Cower"], "the druid Cower drew a Timer row")
end)

test("70862 Mage: Frost Armor 7301 is the 1800 s self window; Fire Blast has no window",
function()
    local m = registryFor("MAGE")
    assertNotNil(m["Frost Armor"], "Frost Armor is not tracked")
    assertEquals(7301, m["Frost Armor"].dataId)
    assertEquals(1800, m["Frost Armor"].duration)
    assertEquals(true, m["Frost Armor"].noTarget)
    assertNil(m["Fire Blast"], "Fire Blast (10199, a cooldown row) drew a Timer row")
end)

test("70862 kind bands: the new Warrior/Paladin rows land on the colour that says what they are",
function()
    -- Echo proc stacks, Shieldsworn, Reckless Swings and Gore Drinker are
    -- caster-side windows; Holy Strike / Holy Wrath / Light's Vigil are
    -- cast cadences; Holy Wrath no longer rides the "Wrath" self-buff term.
    for _, name in ipairs({ "Echo of Fury", "Echo of Command", "Echo of Righteousness",
                            "Echo of Justice", "Echo of Light", "Echo of Wisdom",
                            "Shieldsworn", "Reckless Swings", "Gore Drinker" }) do
        assertEquals("SelfBuff", Registry._kindFor(name), name)
    end
    for _, name in ipairs({ "Holy Strike", "Holy Wrath", "Light's Vigil" }) do
        assertEquals("Cooldown", Registry._kindFor(name), name)
    end
end)

test("restore the registry to the profile class", function()
    Registry:AttachStorage(FX.db and FX.db.timer and FX.db.timer.learned or {})
    Registry:Build(FX._playerClass)
end)

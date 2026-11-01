-- addon/Forte_Cooldown/tests/test_timeline.lua
-- wow-ui-sim tests for the Classic Cooldown Timer timeline (PLAN.md §3.5):
-- UI/TimelineMath.lua (frame-free math) and UI/Timeline.lua (registered as
-- FX.Cooldown.Display, one 250x24 bar). Replaces test_display.lua, whose
-- rows-based renderer is now the dormant UI/Rows.lua seed.
--
-- The Display is a pure renderer: these tests drive it with hand-made entry
-- tables and a fixed `now` -- no Engine, no events, no spell data. Init() is
-- called directly and is idempotent.
--
-- Geometry law (/tmp/fxref/Forte_Cooldown/Forte_Cooldown.lua): render loop
-- :500-526, overlap test :560, SetTimeTags custom path :1233-1295. The minute
-- label rule is `if v > 60` (:1267, :1286 -- STRICTLY greater; the uniform
-- tag branch at :1310 does the same), so the default tags 0 1 10 30 60 120
-- print as "0" "1" "10" "30" "60" "2" -- 60 s stays "60" (NOT "1"); 120 is
-- "2". Tags >= Max break out of the loop (:1257/:1278); the original then
-- draws the Max value itself at the right end (:1279-1293) -- Timeline
-- reproduces that extra end tag.

local FX = ForteXorcist
local Display = FX.Cooldown.Display
local TM = FX.Cooldown.TimelineMath
local S = FX.Cooldown.TimelineSkin

-- Positions round-trip through float32; compare with a tolerance (sizes like
-- 250/24 are integer-exact and use assertEquals).
local function near(actual, expected)
    return assertTrue(math.abs(actual - expected) < 1e-6)
end
local function near3(actual, expected)
    return assertTrue(math.abs(actual - expected) < 1e-3)
end

-- ---------------------------------------------------------------- TimelineMath --

test("TimelineMath.pos matches the power-scale formula", function()
    local W, H, Max, Loga = 250, 24, 300, 0.33
    local ih = H
    local f1 = (W - ih) / W
    local f2 = 1 - f1
    for _, t in ipairs({ 0, 1, 10, 30, 60, 120, 300, 600 }) do
        local v
        if t > Max then
            v = 1                                   -- parks at the right end
        else
            v = f1 * (t / Max) ^ Loga + f2
        end
        near(TM.pos(t, W, H, Max, Loga), v * W - ih * 0.5)
    end
end)

test("TimelineMath.tags: default custom tags drop >= Max, minute-label per the source", function()
    local W, H, Max, Loga = 250, 24, 300, 0.33
    local list = TM.tags("0 1 10 30 60 120 300 600", W, H, Max, Loga)
    -- Exactly the six tags below Max (300/600 break out at >= Max).
    assertEquals(6, #list)
    local values = { 0, 1, 10, 30, 60, 120 }
    -- `if v>60 then v=(v/60);end` -- STRICT > (original :1267, :1286), so the
    -- 60 tag keeps its seconds label.
    local labels = { "0", "1", "10", "30", "60", "2" }
    for i = 1, 6 do
        assertEquals(values[i], list[i].value)
        assertEquals(labels[i], list[i].label)
        near(list[i].x, TM.pos(values[i], W, H, Max, Loga))
    end
end)

test("TimelineMath.group merges > half-icon overlaps and splits the rest", function()
    local H = 24
    -- 3 px apart: previous centre (x+12) is past the current left edge ->
    -- overlap 15 > half icon (12) -> one group (original :560).
    local merged = TM.group({
        { name = "A", x = 100 },
        { name = "B", x = 103 },
    }, H)
    assertEquals(1, #merged)
    assertEquals(2, #merged[1])
    assertEquals("A", merged[1][1].name)
    assertEquals("B", merged[1][2].name)

    -- 30 px apart: overlap is negative -> two groups.
    local split = TM.group({
        { name = "A", x = 100 },
        { name = "B", x = 130 },
    }, H)
    assertEquals(2, #split)
    assertEquals(1, #split[1])
    assertEquals(1, #split[2])

    -- Chain: A~B overlap, B~C do not -> group sizes 2 + 1.
    local chain = TM.group({
        { name = "A", x = 100 },
        { name = "B", x = 110 },
        { name = "C", x = 200 },
    }, H)
    assertEquals(2, #chain)
    assertEquals(2, #chain[1])
    assertEquals(1, #chain[2])
end)

-- -------------------------------------------------------------------- Timeline --

local THREE = {
    { name = "Disengage",       start = 50,  duration = 26,  endTime = 70  },
    { name = "Concussive Shot", start = 90,  duration = 12,  endTime = 102 },
    { name = "Bestial Wrath",   start = 0,   duration = 120, endTime = 160 },
}

test("Init creates the 250x24 timeline anchor", function()
    Display:Init()
    assertNotNil(Display.anchor)
    assertNotNil(ForteXorcistCooldownAnchor)
    assertEquals("ForteXorcistCooldownAnchor", ForteXorcistCooldownAnchor:GetName())
    assertEquals(250, Display.anchor:GetWidth())
    assertEquals(24, Display.anchor:GetHeight())
    -- Idempotence: a second Init must not rebuild or error.
    Display:Init()
    assertNotNil(Display.anchor)
    -- The font probe recorded its verdict: the accepted file path, or nil
    -- (every string on its GameFontHighlightSmall template).
    print("[font] accepted=" .. tostring(Display.fontFile))
    local point = Display.tagFS[1]:GetPoint()
    assertEquals("CENTER", point)
end)

test("Icons are 24x24 and sit at TimelineMath.pos on the time axis", function()
    local now = 100
    Display:Update(THREE, now)

    assertEquals(3, #Display.slots)
    for i = 1, 3 do
        local slot = Display.slots[i]
        assertTrue(slot.frame:IsShown())
        assertEquals(24, slot.frame:GetWidth())
        assertEquals(24, slot.frame:GetHeight())
    end

    -- Slots are LEFT-anchored to the inset bar layer at TimelineMath.pos
    -- (the original's t10): the anchored x offsets ARE the pos values.
    local W, H, Max, Loga = S.Width, S.Height, S.Max, S.Loga
    for i = 1, 3 do
        local e = THREE[i]
        local _, _, _, xoff = Display.slots[i].frame:GetPoint()
        near3(xoff, TM.pos(e.endTime - now, W, H, Max, Loga))
    end

    -- t < 0 clamps to the left end (Disengage at -30 s); 60 s sits on the
    -- curve; the 1:00/4.0 texts ride on the icons (IconTime).
    assertEquals("1:00", Display.slots[3].timeFS:GetText())
    assertEquals("2.0", Display.slots[2].timeFS:GetText())

    -- Just-bound icons start their fade-in at Alpha (0.2).
    near3(Display.slots[1].frame:GetAlpha(), S.Alpha)
    -- First-sighting cast splashes took three pool slots.
    assertEquals(3, #Display.splashPool)
end)

test("Fade-in completes, splashes retire, pool stays (grow-only)", function()
    Display:Update(THREE, 100.4)
    near3(Display.slots[1].frame:GetAlpha(), S.AlphaMax)
    -- Splashes ended at 100.35 and hid; the pool kept its slots.
    assertFalse(Display.splashPool[1].frame:IsShown())
    assertEquals(3, #Display.splashPool)
    -- Re-rendering the SAME names must not grow the pool (no re-sightings).
    Display:Update(THREE, 100.5)
    assertEquals(3, #Display.splashPool)
end)

test("OnReady pulses the left end and dies after PulseSeconds", function()
    Display:OnReady("Disengage", 101)
    Display:Update({
        { name = "Disengage", start = 100, duration = 1, endTime = 101 },
    }, 101)
    -- The pulse lives at the left end: centre x = Inset + pos(0) + H/2 - W/2.
    local s = Display.pulsePool[1]
    assertNotNil(s)
    assertTrue(s.frame:IsShown())
    local _, _, _, xoff = s.frame:GetPoint()
    local expected = S.Inset + TM.pos(0, S.Width, S.Height, S.Max, S.Loga)
        + S.Height * 0.5 - S.Width * 0.5
    near3(xoff, expected)

    Display:Update({
        { name = "Disengage", start = 100, duration = 1, endTime = 101 },
    }, 101 + S.PulseSeconds + 0.1)
    assertFalse(s.frame:IsShown())
end)

test("Fewer entries hides spare slots; pool never shrinks", function()
    Display:Update({
        { name = "Disengage", start = 100, duration = 26, endTime = 126 },
    }, 110)
    assertTrue(Display.slots[1].frame:IsShown())
    assertFalse(Display.slots[2].frame:IsShown())
    assertFalse(Display.slots[3].frame:IsShown())
    assertEquals(3, #Display.slots)
end)

test("Slash handles lock, unlock and reset", function()
    assertTrue(Display:Slash("lock"))
    assertTrue(Display:Slash("unlock"))
    assertTrue(Display:Slash("reset"))
    assertFalse(Display:Slash("status"))
    assertFalse(Display:Slash(nil))
    -- Leave the default lock state in place for anything that runs after.
    Display:SetLocked(true)
end)

test("Overlapping icons cross-fade over ~1 s per member", function()
    -- Two entries whose positions land well under a half-icon apart: one
    -- group, focus rotating with the visibility ramp (render loop :608-637).
    local now = 1000
    local entries = {
        { name = "Alpha", start = 0, duration = 999, endTime = now + 20.0 },
        { name = "Bravo", start = 0, duration = 999, endTime = now + 20.35 },
    }
    local W, H, Max, Loga = S.Width, S.Height, S.Max, S.Loga
    local dx = math.abs(TM.pos(20.35, W, H, Max, Loga) - TM.pos(20.0, W, H, Max, Loga))
    assertTrue(dx < H * 0.5) -- genuinely more than a half-icon overlap

    -- Freshly bound: Alpha fully focused (times its 0.2 fade-in start),
    -- Bravo dark; the fade-in completes over FadeSeconds.
    Display:Update(entries, now)
    near3(Display.slots[1].frame:GetAlpha(), S.Alpha)
    near3(Display.slots[2].frame:GetAlpha(), 0)

    -- 0.5 s later the focus has rotated once and is mid-cross-fade.
    Display:Update(entries, now + 0.5)
    local a = Display.slots[1].frame:GetAlpha()
    local b = Display.slots[2].frame:GetAlpha()
    near3(a + b, 1.0)
    assertTrue(b > 0.2)

    -- One full CrossfadeSeconds in: focus has rotated again.
    Display:Update(entries, now + 1.0)
    a = Display.slots[1].frame:GetAlpha()
    b = Display.slots[2].frame:GetAlpha()
    near3(a + b, 1.0)
    assertTrue(b > 0.8)
end)

-- Segment fills (original bar.texture, :1441-1450 + alpha :1404-1406): every
-- visible cooldown owns an Aluminium slice from its group's left border
-- (previous visible icon's centre, 0 for the first group) to its own centre.
local function vOf(t)
    return (TM.pos(t, S.Width, S.Height, S.Max, S.Loga) + S.Height * 0.5) / S.Width
end

test("Segment fills span prev-icon centre to own centre with the alpha law", function()
    local W, H, Max, Loga = S.Width, S.Height, S.Max, S.Loga
    local now = 2000
    Display:Update({
        { name = "SegLeft", start = 0, duration = 999, endTime = now + 60  },
        { name = "SegRight", start = 0, duration = 999, endTime = now + 120 },
    }, now)
    local l, r = Display.slots[1], Display.slots[2]

    -- First visible segment: bar's left edge (0) to its own centre.
    near3(l._segL, 0)
    near3(l._segR, TM.pos(60, W, H, Max, Loga) + H * 0.5)
    near3(l._segVL, 0)
    near3(l._segV, vOf(60))

    -- Second: from the first icon's CENTRE to its own centre.
    near3(r._segL, TM.pos(60, W, H, Max, Loga) + H * 0.5)
    near3(r._segR, TM.pos(120, W, H, Max, Loga) + H * 0.5)
    near3(r._segVL, vOf(60))
    near3(r._segV, vOf(120))

    -- a = AlphaMax - (AlphaMax - Alpha) * t7: bright left, faint right.
    near3(l._segA, S.AlphaMax - (S.AlphaMax - S.Alpha) * vOf(60))
    near3(r._segA, S.AlphaMax - (S.AlphaMax - S.Alpha) * vOf(120))
    assertTrue(r._segA < l._segA)
    assertTrue(l._segV > l._segVL) -- TexCoord slice grows left -> right
end)

test("Overlap-group members share the group's segment left border", function()
    local now = 3000
    Display:Update({
        { name = "Alpha", start = 0, duration = 999, endTime = now + 20.0 },
        { name = "Bravo", start = 0, duration = 999, endTime = now + 20.35 },
    }, now)
    local a, b = Display.slots[1], Display.slots[2]
    -- First group: the left border is the bar's left edge for EVERY member
    -- (the t8/t12 propagation, :560-570) -- Bravo's segment covers Alpha's.
    near3(a._segL, 0)
    near3(b._segL, 0)
    near3(b._segVL, 0)
    assertTrue(b._segR > a._segR)
end)

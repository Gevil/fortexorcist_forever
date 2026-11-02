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

-- Slots bind by entry NAME (v4): the canonical handle for "the slot for
-- this name right now" is the Display's own name -> slot map. Index order
-- drives position only; identity is the name.
local function slotOf(name)
    return Display._byName[name]
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
        local slot = slotOf(THREE[i].name)
        assertNotNil(slot)
        assertTrue(slot.frame:IsShown())
        assertEquals(24, slot.frame:GetWidth())
        assertEquals(24, slot.frame:GetHeight())
    end

    -- Slots are LEFT-anchored to the inset bar layer at TimelineMath.pos
    -- (the original's t10): the anchored x offsets ARE the pos values.
    local W, H, Max, Loga = S.Width, S.Height, S.Max, S.Loga
    for i = 1, 3 do
        local e = THREE[i]
        local _, _, _, xoff = slotOf(e.name).frame:GetPoint()
        near3(xoff, TM.pos(e.endTime - now, W, H, Max, Loga))
    end

    -- t < 0 clamps to the left end (Disengage at -30 s); 60 s sits on the
    -- curve; the 1:00/4.0 texts ride on the icons (IconTime).
    assertEquals("1:00", slotOf("Bestial Wrath").timeFS:GetText())
    assertEquals("2.0", slotOf("Concussive Shot").timeFS:GetText())

    -- Just-bound icons start their fade-in at Alpha (0.2).
    near3(slotOf("Disengage").frame:GetAlpha(), S.Alpha)
    -- First-sighting cast splashes took three pool slots.
    assertEquals(3, #Display.splashPool)
end)

test("Fade-in completes, splashes retire, pool stays (grow-only)", function()
    Display:Update(THREE, 100 + S.FadeSeconds)
    near3(slotOf("Disengage").frame:GetAlpha(), S.AlphaMax)
    -- Splashes end at 100 + SplashSeconds and hid; the pool kept its slots.
    Display:Update(THREE, 100 + S.SplashSeconds + 0.01)
    assertFalse(Display.splashPool[1].frame:IsShown())
    assertEquals(3, #Display.splashPool)
    -- Re-rendering the SAME names must not grow the pool (no re-sightings).
    Display:Update(THREE, 100 + S.SplashSeconds + 0.1)
    assertEquals(3, #Display.splashPool)
end)

-- =============================================================== fade-in ==
-- The icon fade-in is the source's FRESH-VISIBILITY ramp, not an invented
-- 0.3 s cadence. /tmp/fxref/Forte_Cooldown/Forte_Cooldown.lua:
--   :625  `cd[n][14] = 0; -- set its visibilty to zero just to make sure`
--         (the focus hand-off starts the new member at zero),
--   :598  `cd[n][14] = 1;` inside the "correcting focus" init (a group with
--         no focus yet starts fully visible),
--   :611  `t14 = t14+(tim-cd[i][16]);` -- the focused bar's visibility
--         advances by the ELAPSED SECONDS, clamped at 1 (:612-614): a 0 -> 1
--         ramp is 1.0 s at 1/s,
--   :1402 `bar:SetAlpha(t14)` -- the frame alpha rides that visibility (our
--         port maps the 0..1 ramp onto Alpha .. AlphaMax, the vendored
--         endpoints).
test("Icon fade-in law: Alpha -> AlphaMax over the source's 1/s ramp (1.0 s)",
function()
    near3(S.FadeSeconds, 1.0)
    local now = 12000
    local feed = {
        { name = "FadeLaw", start = 0, duration = 120, endTime = now + 120 },
    }
    -- t = 0: the fresh visibility is 0 -> the fade-in starts AT Alpha.
    Display:Update(feed, now)
    near3(slotOf("FadeLaw").frame:GetAlpha(), S.Alpha)
    -- t = 0.5: halfway the 1.0 s ramp (0.2 + 0.8 * 0.5). The pre-fix 0.3 s
    -- window was over at 0.3, so this sample is the law's witness.
    Display:Update(feed, now + 0.5)
    near3(slotOf("FadeLaw").frame:GetAlpha(),
        S.Alpha + (S.AlphaMax - S.Alpha) * 0.5)
    assertTrue(slotOf("FadeLaw").frame:GetAlpha() < S.AlphaMax,
        "the fade is NOT over at half the window")
    -- t = 1.0: the ramp reaches 1 -> AlphaMax (and stays there).
    Display:Update(feed, now + 1.0)
    near3(slotOf("FadeLaw").frame:GetAlpha(), S.AlphaMax)
    Display:Update(feed, now + 3.0)
    near3(slotOf("FadeLaw").frame:GetAlpha(), S.AlphaMax)
    Display:Update({}, now + 3.1)
end)

-- ============================================================ splash law ==
-- The cast splash is the source's t15==-1 expiry visual, re-derived 1:1 from
-- /tmp/fxref/Forte_Cooldown/Forte_Cooldown.lua:
--   * window: CD_EndCooldown starts the bar at t14 = 1 (:354) and the draw
--     pass decays it -1/s, clamped (:629-632) -> SplashSeconds = 1.0 s
--     (the old 0.35 / SplashAlpha 0.7 came from the DISABLED secondary
--     splash-window instance, :1868-1874, not the in-bar splash);
--   * size: SplashFactor*ih*(1-t14) (:1381) with SplashFactor = 4 (:1812)
--     and ih = Height (IconSize[0] off, :1364, :1803) -> LINEAR ramp
--     0 -> 4*24 = 96 px over the window;
--   * alpha: bar:SetAlpha(t14) (:1403) -> SplashAlpha = 1.0 fading linearly
--     to 0; the whole frame (icon + spark) rides it;
--   * tint/blend: splashicon = the icon texture (:1382), vertex colour and
--     blend mode NEVER set -> white + BLEND (:1088-89); the 2.2x spark
--     (:1386-87) is Spark2 ADD (:1084-85), vertex colour FixIntensity(category)
--     (:1407, :1418); with Spark[0] (default true, :1822) the icon rides the
--     0.133..0.867 centre crop (:1388), else the full texture (:1391).
local function liveSplash()
    for i = 1, #Display.splashPool do
        local s = Display.splashPool[i]
        if s._endAt then return s end
    end
end

test("Splash law: size 0 -> 4x icon and alpha 1 -> 0, both linear over 1.0 s", function()
    -- Window constants straight from the source law.
    near3(S.SplashSeconds, 1.0)
    near3(S.SplashAlpha, 1.0)
    assertEquals(4, S.SplashFactor)
    local peak = S.SplashFactor * S.Height          -- 96 px at t14 = 0

    local now = 12345
    local feed = {
        { name = "SplashLaw", start = 0, duration = 60, endTime = now + 60 },
    }
    Display:Update(feed, now)
    local s = liveSplash()
    assertNotNil(s)

    -- t = 0: t14 = 1 -> size 0, frame alpha = SplashAlpha = 1.
    near3(s.tex:GetWidth(), S.SplashFactor * S.Height * (1 - 1.0))
    near3(s.tex:GetHeight(), 0)
    near3(s.frame:GetAlpha(), S.SplashAlpha)

    -- mid: t = SplashSeconds/2 -> t14 = 0.5: size 48, alpha 0.5. The spark
    -- rides 2.2x the splash size (:1386-87).
    Display:Update(feed, now + S.SplashSeconds * 0.5)
    near3(s.tex:GetWidth(), S.SplashFactor * S.Height * 0.5)
    near3(s.frame:GetAlpha(), S.SplashAlpha * 0.5)
    near3(s.spark:GetWidth(), s.tex:GetWidth() * S.SparkScale)

    -- end (just before the window closes): t14 -> 0 -> peak size, alpha -> 0.
    Display:Update(feed, now + S.SplashSeconds - 1e-6)
    near3(s.tex:GetWidth(), peak)
    near3(s.tex:GetHeight(), peak)
    near3(s.spark:GetWidth(), peak * S.SparkScale)
    assertTrue(s.frame:GetAlpha() < 1e-3)

    -- At SplashSeconds the bar gate t14 > 0 (:1371) retires the splash.
    Display:Update(feed, now + S.SplashSeconds + 1e-6)
    assertFalse(s.frame:IsShown())
    assertTrue(liveSplash() == nil)
end)

test("Splash tint/blend: white BLEND icon, Spark2 ADD glow FixIntensity-tinted, 0.133 crop", function()
    local now = 12445
    Display:Update({
        { name = "SplashTint", start = 0, duration = 60, endTime = now + 60 },
    }, now)
    local s = liveSplash()
    assertNotNil(s)
    -- splashicon: vertex colour never set in the source (:1088) -> white.
    local r, g, b = s.tex:GetVertexColor()
    near3(r, 1); near3(g, 1); near3(b, 1)
    -- The spark: Spark2 ADD (:1084-85) and FixIntensity(category) (:1407,
    -- :1418). Spell = (1, 0.5, 0): largest == 1 -> 0.7c + 0.3.
    assertEquals("Interface\\AddOns\\Forte_Core\\Textures\\Spark2",
        s.spark:GetTexture())
    local fr, fg, fb = s.spark:GetVertexColor()
    near3(fr, 0.7 * 1.00 + 0.3)
    near3(fg, 0.7 * 0.50 + 0.3)
    near3(fb, 0.7 * 0.00 + 0.3)
    -- Spark[0] on (default): the 0.133..0.867 centre crop (:1388). The sim
    -- GetTexCoord returns the four corners (ulX,ulY, blX,blY, urX,urY,
    -- brX,brY): every left corner carries L, every right corner R, the top
    -- edge T and the bottom edge B.
    local ulx, uly, blx, bly, urx, _, brx, bry = s.tex:GetTexCoord()
    near3(ulx, S.SplashCrop[1]); near3(blx, S.SplashCrop[1])
    near3(urx, S.SplashCrop[2]); near3(brx, S.SplashCrop[2])
    near3(uly, S.SplashCrop[1])                  -- top edge
    near3(bly, S.SplashCrop[2]); near3(bry, S.SplashCrop[2])  -- bottom edge
    assertTrue(s.spark:IsShown())
    Display:Update({}, now + S.SplashSeconds + 0.01)
end)

test("Pulse and cross-fade constants equal the source's 1/s visibility law", function()
    -- Expiry starts the bar at t14 = 1 (:354) and decays it -1/s clamped
    -- (:629-632): the splash window and the end-of-cooldown pulse share this
    -- 1.0 s. The source's ONLY alpha law for them is the linear
    -- bar:SetAlpha(t14) (:1403) -- there is no sin wave anywhere in the
    -- draw loop, so PulseCycle = 0 (off) and the spark rides the constant
    -- vertex alpha (:1418).
    near3(S.PulseSeconds, 1.0)
    assertEquals(0, S.PulseCycle)
    -- Focus rotation: the focused member's t14 ramps +1/s (:619) to 1, the
    -- hand-off (:621-633) hands a fresh 0 to the next member, and the
    -- outgoing side decays -1/s (:629-632) -- a 1.0 s dwell per member.
    near3(S.CrossfadeSeconds, 1.0)
    near3(S.SplashSeconds, S.PulseSeconds)  -- one shared source window
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

    -- Source expiry law (:1380-1403): frame alpha = t14 = SplashAlpha*1 at
    -- the window start (:354, :1403), the spark at CONSTANT alpha (no wave,
    -- PulseCycle 0; :1418) tinted FixIntensity(Spell) = (1.00, 0.65, 0.30)
    -- (:1407, :1418).
    near3(s.frame:GetAlpha(), S.SplashAlpha)
    near3(s.spark:GetAlpha(), S.SparkAlpha)
    local r, g, b = s.spark:GetVertexColor()
    near3(r, 1.00); near3(g, 0.65); near3(b, 0.30)

    -- Halfway: the linear t14 fade -- alpha = SplashAlpha * 0.5 (+- a tick).
    Display:Update({
        { name = "Disengage", start = 100, duration = 1, endTime = 101 },
    }, 101 + S.PulseSeconds * 0.5)
    near3(s.frame:GetAlpha(), S.SplashAlpha * 0.5)
    near3(s.spark:GetAlpha(), S.SparkAlpha)

    Display:Update({
        { name = "Disengage", start = 100, duration = 1, endTime = 101 },
    }, 101 + S.PulseSeconds + 0.1)
    assertFalse(s.frame:IsShown())
end)

test("Fewer entries hides spare slots; pool never shrinks", function()
    -- Pool-relative and slot-agnostic: the splash-law tests grew the pool
    -- and the free list hands out slots in release order, so asserting on
    -- fixed indices is meaningless -- the invariant is: EXACTLY the fed
    -- name's slot stays shown, the pool never shrinks.
    local poolBefore = #Display.slots
    Display:Update({
        { name = "Disengage", start = 100, duration = 26, endTime = 126 },
    }, 110)
    -- Disengage keeps ITS slot; every dropped name released its slot
    -- (hidden, on the free list) -- the pool itself never shrinks.
    assertTrue(slotOf("Disengage").frame:IsShown())
    local shown = 0
    for i = 1, #Display.slots do
        if Display.slots[i].frame:IsShown() then shown = shown + 1 end
    end
    assertEquals(1, shown)
    assertEquals(poolBefore, #Display.slots)
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
    -- Bravo dark; the fade-in completes over FadeSeconds (1.0 s).
    Display:Update(entries, now)
    near3(slotOf("Alpha").frame:GetAlpha(), S.Alpha)
    near3(slotOf("Bravo").frame:GetAlpha(), 0)

    -- 0.5 s later the focus has rotated once and is mid-cross-fade: the two
    -- GROUP visibilities sum to 1 (:619-632), and both ride the SAME fade-in
    -- factor, so the frame alphas sum to that factor -- 0.2 + 0.8*0.5 = 0.6
    -- on the 1.0 s ramp (a finished fade is what made this 1.0 pre-fix).
    Display:Update(entries, now + 0.5)
    local a = slotOf("Alpha").frame:GetAlpha()
    local b = slotOf("Bravo").frame:GetAlpha()
    near3(a + b, S.Alpha + (S.AlphaMax - S.Alpha) * 0.5)
    assertTrue(b > 0.2)

    -- One full CrossfadeSeconds in -- the fade-in has completed (t =
    -- FadeSeconds), so the cross-fade law shows bare: the alphas sum to 1.
    Display:Update(entries, now + 1.0)
    a = slotOf("Alpha").frame:GetAlpha()
    b = slotOf("Bravo").frame:GetAlpha()
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
    local l, r = slotOf("SegLeft"), slotOf("SegRight")

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
    local a, b = slotOf("Alpha"), slotOf("Bravo")
    -- First group: the left border is the bar's left edge for EVERY member
    -- (the t8/t12 propagation, :560-570) -- Bravo's segment covers Alpha's.
    near3(a._segL, 0)
    near3(b._segL, 0)
    near3(b._segVL, 0)
    assertTrue(b._segR > a._segR)
end)

-- The row contract the Engine/ItemsCD feed adds: `charges`/`maxCharges` (the
-- count printed on the icon) with `rechargeEnd` (the landing the icon rides),
-- `category` (a TimelineSkin.Colors key) and `icon` (a texture override).
-- Rows without them render exactly as before -- every test above is such a
-- row. The engine ships a charge row only while the bar is DRAINED
-- (charges = 0, Engine:Sorted), so a charges > 0 row exists on the hand-made
-- feeds (and in the screenshot scenario), never in play.

test("Charge rows print the count at the icon's top-right, charges-less rows hide it", function()
    local now = 5000
    Display:Update({
        { name = "Drained", start = 0, duration = 12, endTime = now + 12,
          charges = 0, maxCharges = 2, rechargeEnd = now + 12 },
        { name = "Partial", start = 0, duration = 12, endTime = now + 12,
          charges = 1, maxCharges = 3, rechargeEnd = now + 18 },
        { name = "PlainCast", start = 0, duration = 60, endTime = now + 60 },
    }, now)
    local drained, partial, plain =
        slotOf("Drained"), slotOf("Partial"), slotOf("PlainCast")

    -- The count, as text, on both charge rows; nothing on the charges-less one.
    assertTrue(drained.chargeFS:IsShown())
    assertEquals("0", drained.chargeFS:GetText())
    assertTrue(partial.chargeFS:IsShown())
    assertEquals("1", partial.chargeFS:GetText())
    assertFalse(plain.chargeFS:IsShown())

    for _, slot in ipairs({ drained, partial }) do
        -- v4: the count rides the icon's TOPRIGHT at (-1, -1). (v1 copied
        -- Blizzard's CooldownViewer.xml count corner, BOTTOMRIGHT (-2, 2)
        -- -- which overprinted the 3-4 character IconTime string printed at
        -- the BOTTOMLEFT; see the geometry test below.)
        local point, _, relPoint, xoff, yoff = slot.chargeFS:GetPoint()
        assertEquals("TOPRIGHT", point)
        assertEquals("TOPRIGHT", relPoint)
        near3(xoff, -1)
        near3(yoff, -1)
        -- A small number: the icon is bar-height (24), the count font is the
        -- icon font (10, OUTLINE) and the glyph box fits inside the icon.
        local _, size = slot.chargeFS:GetFont()
        assertTrue(size <= 12)
        assertTrue(slot.chargeFS:GetWidth() > 0)
        assertTrue(slot.chargeFS:GetWidth() <= slot.frame:GetWidth())
        assertTrue(slot.chargeFS:GetHeight() <= slot.frame:GetHeight())
        assertTrue(slot.chargeFS:GetLeft() >= slot.frame:GetLeft() - 1e-3)
        assertTrue(slot.chargeFS:GetRight() <= slot.frame:GetRight() + 1e-3)
        assertTrue(slot.chargeFS:GetTop() <= slot.frame:GetTop() + 1e-3)
        assertTrue(slot.chargeFS:GetBottom() >= slot.frame:GetBottom() - 1e-3)
    end

    -- White while charges > 0, Blizzard gold on a drained bar.
    local zr, zg, zb = drained.chargeFS:GetTextColor()
    near3(zr, S.ChargeZeroColor[1]); near3(zg, S.ChargeZeroColor[2])
    near3(zb, S.ChargeZeroColor[3])
    local wr, wg, wb = partial.chargeFS:GetTextColor()
    near3(wr, S.ChargeColor[1]); near3(wg, S.ChargeColor[2]); near3(wb, S.ChargeColor[3])
    assertFalse(zr == wr and zg == wg and zb == wb)
end)

test("A charge row rides rechargeEnd, not the last cast's window", function()
    local W, H, Max, Loga = S.Width, S.Height, S.Max, S.Loga
    local now = 6000
    -- The last cast lapsed long ago (endTime in the past); the NEXT charge
    -- lands in 12 s -- the icon must sit where 12 s belongs on the axis.
    Display:Update({
        { name = "RidesRecharge", start = now - 100, duration = 12,
          endTime = now - 88, charges = 0, maxCharges = 2, rechargeEnd = now + 12 },
    }, now)
    local slot = slotOf("RidesRecharge")
    local _, _, _, xoff = slot.frame:GetPoint()
    near3(xoff, TM.pos(12, W, H, Max, Loga))
    -- A charges-less row has no rechargeEnd and keeps riding endTime.
    Display:Update({
        { name = "PlainCast", start = now, duration = 45, endTime = now + 45 },
    }, now)
    _, _, _, xoff = slotOf("PlainCast").frame:GetPoint()
    near3(xoff, TM.pos(45, W, H, Max, Loga))
end)

test("Row category drives the segment, spark and time-text colours", function()
    local now = 7000
    Display:Update({
        { name = "GoldTrinket", start = 0, duration = 60, endTime = now + 60,
          category = "Item" },
        { name = "GreenPotion", start = 0, duration = 60, endTime = now + 90,
          category = "Potion" },
        { name = "NoCategory", start = 0, duration = 60, endTime = now + 120 },
        { name = "BogusCategory", start = 0, duration = 60, endTime = now + 150,
          category = "NotACategory" },
    }, now)

    local item, potion, plain, bogus =
        slotOf("GoldTrinket"), slotOf("GreenPotion"),
        slotOf("NoCategory"), slotOf("BogusCategory")

    -- The segment carries the RAW category colour (original :1403).
    local r, g, b = item.seg:GetVertexColor()
    local ic = S.Colors.Item
    near3(r, ic[1]); near3(g, ic[2]); near3(b, ic[3])
    r, g, b = potion.seg:GetVertexColor()
    local pc = S.Colors.Potion
    near3(r, pc[1]); near3(g, pc[2]); near3(b, pc[3])
    -- No category = Spell; an unknown category key falls back to Spell too.
    for _, slot in ipairs({ plain, bogus }) do
        r, g, b = slot.seg:GetVertexColor()
        local sc = S.Colors.Spell
        near3(r, sc[1]); near3(g, sc[2]); near3(b, sc[3])
    end

    -- The spark and the on-icon time text ride FixIntensity(category)
    -- (Forte_Core.lua :800-805), so they follow the same per-row colour.
    local function fix(c)
        local largest = math.max(math.max(c[1], c[2]), c[3])
        if largest == 1 then
            return 0.7 * c[1] + 0.3, 0.7 * c[2] + 0.3, 0.7 * c[3] + 0.3
        end
        return 0.7 * c[1] / largest + 0.3, 0.7 * c[2] / largest + 0.3,
            0.7 * c[3] / largest + 0.3
    end
    local er, eg, eb = fix(S.Colors.Item)
    r, g, b = item.spark:GetVertexColor()
    near3(r, er); near3(g, eg); near3(b, eb)
    r, g, b = item.timeFS:GetTextColor()
    near3(r, er); near3(g, eg); near3(b, eb)
    er, eg, eb = fix(S.Colors.Potion)
    r, g, b = potion.spark:GetVertexColor()
    near3(r, er); near3(g, eg); near3(b, eb)
    -- The two categories are genuinely different colours (not one tint).
    local ir, ig, ib = item.seg:GetVertexColor()
    local pr, pg, pb = potion.seg:GetVertexColor()
    assertFalse(ir == pr and ig == pg and ib == pb)
end)

test("row.icon overrides the spell-icon resolution", function()
    local now = 8000
    Display:Update({
        { name = "ItemRow", start = 0, duration = 60, endTime = now + 60,
          category = "Item", icon = "Interface\\Icons\\INV_Misc_Potion_01" },
        { name = "NoIconRow", start = 0, duration = 60, endTime = now + 90 },
    }, now)
    assertEquals("Interface\\Icons\\INV_Misc_Potion_01",
        slotOf("ItemRow").tex:GetTexture())
    -- A row without an icon keeps the spell lookup (nil here: the sim knows
    -- neither name) -- i.e. the override never invents a texture.
    local plainTex = slotOf("NoIconRow").tex:GetTexture()
    assertTrue(plainTex == nil
        or plainTex ~= "Interface\\Icons\\INV_Misc_Potion_01")
end)

-- ------------------------------------------------------------ name binding --
-- Regression (manager-found, 2026-11-01): slots used to bind by INDEX into
-- the soonest-first feed, so any shift of the list -- a cooldown finishing,
-- a new cast inserted mid-list -- re-ran the first-sighting branch on every
-- shifted slot: the fade-in restarted AND a fresh 4x cast splash spawned
-- (the v3 screenshot shows four enlarged splash icons behind the bar).
-- Slots are name-bound now: identity/texture/colour/fade/splash are
-- per-name, index order drives position only. Each test below asserts ZERO
-- splashes where the index code demonstrably produced one per shifted slot
-- (checked by reasoning through the old Update/BindSlot: slot i rebinding
-- to entries[i]'s new name early-returns on `slot._name == e.name` never).

local function activeSplashes()
    local c = 0
    for i = 1, #Display.splashPool do
        if Display.splashPool[i]._endAt then c = c + 1 end
    end
    return c
end

test("The soonest cooldown leaving shifts the bar: no new splash, fade + texture kept", function()
    local now = 20000
    local ABC = {
        { name = "ShiftA", start = 0, duration = 100, endTime = now + 30 },
        { name = "ShiftB", start = 0, duration = 100, endTime = now + 60 },
        { name = "ShiftC", start = 0, duration = 100, endTime = now + 120 },
    }
    Display:Update(ABC, now)
    assertEquals(3, activeSplashes())   -- three fresh casts, three splashes

    local slotB, slotC = slotOf("ShiftB"), slotOf("ShiftC")
    assertNotNil(slotB); assertNotNil(slotC)
    local fadeB, fadeC, texB, texC = slotB._fadeStart, slotC._fadeStart,
        slotB.tex, slotC.tex
    near3(fadeB, now)
    local poolSize = #Display.splashPool

    -- The splash pool's active count returns to 0 after SplashSeconds of
    -- advancing now; the pool itself keeps its (grow-only) size.
    Display:Update(ABC, now + S.SplashSeconds + 0.01)
    assertEquals(0, activeSplashes())
    assertEquals(poolSize, #Display.splashPool)

    -- A finishes and drops off the feed: B and C shift one index down.
    Display:Update({ ABC[2], ABC[3] }, now + 40)
    -- Index binding: BOTH shifted slots re-sight -> 2 splashes + restarted
    -- fades. Name binding: the shift is POSITIONAL -> zero splashes, fades
    -- untouched, same slot objects, same textures, A's slot released.
    assertEquals(0, activeSplashes())
    assertTrue(slotOf("ShiftB") == slotB)
    assertTrue(slotOf("ShiftC") == slotC)
    assertTrue(slotOf("ShiftB").tex == texB)
    assertTrue(slotOf("ShiftC").tex == texC)
    assertTrue(slotOf("ShiftB").frame:IsShown())
    assertTrue(slotOf("ShiftC").frame:IsShown())
    near3(slotOf("ShiftB")._fadeStart, fadeB)
    near3(slotOf("ShiftC")._fadeStart, fadeC)
    assertTrue(slotOf("ShiftA") == nil)
end)

test("A new cast inserted mid-list splashes exactly once, at its own centre", function()
    local W, H, Max, Loga = S.Width, S.Height, S.Max, S.Loga
    local now = 21000
    local A = { name = "InsA", start = 0, duration = 100, endTime = now + 30 }
    local B = { name = "InsB", start = 0, duration = 100, endTime = now + 60 }
    local C = { name = "InsC", start = 0, duration = 100, endTime = now + 120 }
    Display:Update({ A, B, C }, now)
    local settled = now + S.SplashSeconds + 0.01
    Display:Update({ A, B, C }, settled)
    assertEquals(0, activeSplashes())

    -- D sorts in between A (~30 s) and B (~60 s). Index binding re-sights
    -- slot2 (D), slot3 (C) and slot4 (B): 3 splashes. Name binding: exactly
    -- one -- D's.
    local D = { name = "InsD", start = 0, duration = 100, endTime = settled + 45 }
    Display:Update({ A, D, B, C }, settled)
    assertEquals(1, activeSplashes())

    -- The live splash is centred where D's icon sits.
    local live
    for i = 1, #Display.splashPool do
        local s = Display.splashPool[i]
        if s._endAt then live = s end
    end
    assertNotNil(live)
    local _, _, _, xoff = live.frame:GetPoint()
    local x = TM.pos(D.endTime - settled, W, H, Max, Loga)
    near3(xoff, x + H * 0.5 - (W - 2 * S.Inset) * 0.5)

    -- D's fade starts now; A's never restarted.
    near3(slotOf("InsD")._fadeStart, settled)
    near3(slotOf("InsA")._fadeStart, now)
end)

test("A name that left the bar and returns (a new cast) splashes again", function()
    local now = 22000
    local A = { name = "RetA", start = 0, duration = 30, endTime = now + 30 }
    local B = { name = "RetB", start = 0, duration = 60, endTime = now + 60 }
    Display:Update({ A, B }, now)
    -- A is done: B shifts down one index WITHOUT re-sighting. Index
    -- binding: B lands on A's slot -> 1 splash. Name binding: zero.
    Display:Update({ B }, now + S.SplashSeconds + 0.01)
    assertEquals(0, activeSplashes())
    Display:Update({ B }, now + 1)
    assertEquals(0, activeSplashes())
    -- A is cast again and returns to the feed: a fresh first sighting.
    Display:Update({ A, B }, now + 2)
    assertEquals(1, activeSplashes())
    -- ...and the pool quiets out again after SplashSeconds.
    Display:Update({ A, B }, now + 2 + S.SplashSeconds + 0.01)
    assertEquals(0, activeSplashes())
end)

test("The charge count at the icon's top-right is clear of the time text", function()
    local now = 23000
    -- The v3 collision: a 4-character time string printed at the 24 px
    -- icon's BOTTOMLEFT and the charge count at its BOTTOMRIGHT overprint
    -- ("40." over "0", 3-4 chars).
    Display:Update({
        { name = "GeomCharge", start = 0, duration = 60, endTime = now + 40.0,
          charges = 0, maxCharges = 3, rechargeEnd = now + 40.0 },
    }, now)
    local slot = slotOf("GeomCharge")
    assertNotNil(slot)
    assertTrue(slot.chargeFS:IsShown())
    assertEquals("40.0", slot.timeFS:GetText())   -- the wide 4-char string
    assertEquals("0", slot.chargeFS:GetText())
    local _, cSize = slot.chargeFS:GetFont()
    local _, tSize = slot.timeFS:GetFont()
    assertEquals(cSize, tSize)                    -- same font/size as v1

    local point, _, relPoint, xoff, yoff = slot.chargeFS:GetPoint()
    assertEquals("TOPRIGHT", point)
    assertEquals("TOPRIGHT", relPoint)
    near3(xoff, -1)
    near3(yoff, -1)

    -- No overprint: the count's box is clear of the time text's box. At
    -- sim font metrics (measured: 12 px line height for size-10 OUTLINE in
    -- the 24 px icon, digit 5.97, dot 3.86) the boxes graze inside the
    -- 1.5 px descender/ascender band -- zero ink overlap. The v1
    -- BOTTOMRIGHT anchor fails BOTH disjuncts here: its count box sank to
    -- the icon's bottom edge, 10 px below the time text's top, and its
    -- 4-character span overprinted the count by ~6 px.
    local clear = (slot.chargeFS:GetBottom() >= slot.timeFS:GetTop() - 1.5)
        or (slot.chargeFS:GetLeft() >= slot.timeFS:GetRight())
        or (slot.timeFS:GetLeft() >= slot.chargeFS:GetRight())
    assertTrue(clear)
end)

-- ======================================================== live settings ==
-- T9: every wired settings key must MOVE the live bar. These drive the
-- production seam exactly as the options window does -- FX.Settings:Set --
-- so they prove the OnChange wiring registered by Display:Init, the
-- KEYMAP routing and the Display setters' rebuild-what-moved behaviour.
-- Forte_Options loads in every gate run; its chunk-registered defaults are
-- the source of the values (Display:Init applied them at PLAYER_LOGIN).
-- Every test restores the defaults it moved (Reset writes the registered
-- default back THROUGH Set, so the live bar self-heals the same way).

local Settings = FX.Settings
local Engine = FX.Cooldown.Engine

local function shownTags()
    local n = 0
    for i = 1, #Display.tagFS do
        if Display.tagFS[i]:IsShown() then n = n + 1 end
    end
    return n
end

test("Settings Width/Height resize the bar and every pool member", function()
    Display:Init()
    Settings:Set("Cooldown", "Width", 320)
    Settings:Set("Cooldown", "Height", 30)
    assertEquals(320, Display.anchor:GetWidth())
    assertEquals(30, Display.anchor:GetHeight())
    -- The icons ride the bar height.
    local now = 30000
    Display:Update({
        { name = "SizedA", start = 0, duration = 120, endTime = now + 120 },
    }, now)
    local slot = slotOf("SizedA")
    assertEquals(30, slot.frame:GetWidth())
    assertEquals(30, slot.frame:GetHeight())
    near3(slot.spark:GetWidth(), 30 * S.SparkScale)
    -- Back to the defaults (registered 250/24): store AND bar agree.
    Settings:Reset("Cooldown", "Width")
    Settings:Reset("Cooldown", "Height")
    assertEquals(250, Display.anchor:GetWidth())
    assertEquals(24, Display.anchor:GetHeight())
    Display:Update({
        { name = "SizedA", start = 0, duration = 120, endTime = now + 121 },
    }, now + 1)
    assertEquals(24, slotOf("SizedA").frame:GetWidth())
    Display:Update({}, now + 2)
end)

test("Settings MaxTime/PowerScale/TimeTags move the curve and the tags", function()
    Display:Init()
    -- Defaults: tags 0 1 10 30 60 120 (< 300) + the Max end tag = 7.
    assertEquals(7, shownTags())
    local x10 = select(4, Display.tagFS[3]:GetPoint())   -- the "10" tag
    Settings:Set("Cooldown", "MaxTime", 60)
    -- Tags >= 60 break out: 0 1 10 30 + Max tag.
    assertEquals(5, shownTags())
    Settings:Reset("Cooldown", "MaxTime")
    assertEquals(7, shownTags())
    -- Loga steepens the curve: the "10" tag slides measurably left.
    Settings:Set("Cooldown", "PowerScale", 0.66)
    local x10b = select(4, Display.tagFS[3]:GetPoint())
    assertTrue(math.abs(x10 - x10b) > 10,
        "Loga moved the 10-tag by " .. tostring(math.abs(x10 - x10b)))
    Settings:Reset("Cooldown", "PowerScale")
    near3(select(4, Display.tagFS[3]:GetPoint()), x10)
    -- Custom tags: 0 5 15 + the Max tag.
    Settings:Set("Cooldown", "TimeTags", "0 5 15")
    assertEquals(4, shownTags())
    Settings:Reset("Cooldown", "TimeTags")
    assertEquals(7, shownTags())
    -- A shortened axis parks a 120 s cooldown at the right end (t > Max):
    -- the icon's LEFT offset is exactly W - H/2 there.
    local now = 30500
    Settings:Set("Cooldown", "MaxTime", 60)
    Display:Update({
        { name = "ParkedCD", start = 0, duration = 120, endTime = now + 120 },
    }, now)
    local _, _, _, xoff = slotOf("ParkedCD").frame:GetPoint()
    near3(xoff, S.Width - S.Height * 0.5)
    Settings:Reset("Cooldown", "MaxTime")
    Display:Update({}, now + 1)
end)

test("Settings category colours retint segments, sparks and time text", function()
    local now = 31000
    local custom = { 0.20, 1.00, 0.40, 1 }
    Display:Update({
        { name = "ColItem", start = 0, duration = 120, endTime = now + 120,
          category = "Item" },
        { name = "ColSpell", start = 0, duration = 120, endTime = now + 150 },
    }, now)
    local item, spell = slotOf("ColItem"), slotOf("ColSpell")
    -- A fresh bind after the change carries the new colour verbatim, and
    -- the bound rows ride on through the same pass (the pool never sees a
    -- feed that drops them -- a dropped row releases its slot for good).
    Settings:Set("Cooldown", "ColorItem", custom)
    Display:Update({
        { name = "FreshItem", start = 0, duration = 120, endTime = now + 90,
          category = "Item" },
        { name = "ColItem", start = 0, duration = 120, endTime = now + 120,
          category = "Item" },
        { name = "ColSpell", start = 0, duration = 120, endTime = now + 150 },
    }, now)
    -- The sim stores vertex colours as float32: compare with a float32-
    -- tolerant epsilon, not bit-equality on the quantised read-back.
    local function nearCol(a, b)
        return math.abs(a - b) < 1e-3
    end
    local r, g, b = slotOf("FreshItem").seg:GetVertexColor()
    assertTrue(nearCol(r, custom[1]) and nearCol(g, custom[2])
        and nearCol(b, custom[3]))
    -- A slot bound all along is retinted on the next pass (identity-cached
    -- _segSetCol busts when SetCategoryColor swaps the table).
    r, g, b = item.seg:GetVertexColor()
    assertTrue(nearCol(r, custom[1]) and nearCol(g, custom[2])
        and nearCol(b, custom[3]))
    -- The untouched category keeps its own colour (shared-table safety).
    r, g, b = spell.seg:GetVertexColor()
    local def = FX.Cooldown.TimelineSkin.Colors.Spell
    assertTrue(nearCol(r, def[1]) and nearCol(g, def[2])
        and nearCol(b, def[3]))
    Settings:Reset("Cooldown", "ColorItem")
    Display:Update({}, now + 1)
end)

test("Settings BarColor and BarTexture drive the fill; BarTexture the segments", function()
    Settings:Set("Cooldown", "BarColor", { 1, 0, 0, 0.44 })
    local r, g, b, a = Display.fill:GetVertexColor()
    near3(r, 1); near3(g, 0); near3(b, 0); near3(a, 0.44)
    Settings:Reset("Cooldown", "BarColor")
    -- A Forte-vendored texture path (known Blizzard texture paths resolve
    -- to numeric texture ids in the sim, so string round-trips use our own).
    local tex = "Interface\\AddOns\\Forte_Core\\Textures\\Border"
    Settings:Set("General", "BarTexture", tex)
    assertEquals(tex, Display.fill:GetTexture())
    local now = 31500
    Display:Update({
        { name = "TexSeg", start = 0, duration = 120, endTime = now + 120 },
    }, now)
    assertEquals(tex, slotOf("TexSeg").seg:GetTexture())
    Settings:Reset("General", "BarTexture")
    assertEquals(FX.Cooldown.TimelineSkin.BarTexture, Display.fill:GetTexture())
    Display:Update({}, now + 1)
end)

test("Settings Scale/Alpha (module) and FrameScale/FrameAlpha (global) compose", function()
    Display:Init()
    Settings:Set("Cooldown", "Scale", 1.5)
    Settings:Set("Cooldown", "Alpha", 0.5)
    near3(Display.anchor:GetScale(), 1.5)
    near3(Display.anchor:GetAlpha(), 0.5)
    Settings:Set("General", "FrameScale", 2.0)
    Settings:Set("General", "FrameAlpha", 0.4)
    near3(Display.anchor:GetScale(), 3.0)     -- 1.5 * 2.0
    near3(Display.anchor:GetAlpha(), 0.20)    -- 0.5 * 0.4
    Settings:Reset("Cooldown", "Scale")
    Settings:Reset("Cooldown", "Alpha")
    Settings:Reset("General", "FrameScale")
    Settings:Reset("General", "FrameAlpha")
    near3(Display.anchor:GetScale(), 1.0)
    near3(Display.anchor:GetAlpha(), 1.0)
end)

test("Settings Spark=false hides the running glow on every slot", function()
    local now = 32000
    Display:Update({
        { name = "SparkMe", start = 0, duration = 120, endTime = now + 120 },
    }, now)
    assertTrue(slotOf("SparkMe").spark:IsShown())
    Settings:Set("Cooldown", "Spark", false)
    assertFalse(slotOf("SparkMe").spark:IsShown())
    Settings:Set("Cooldown", "Spark", true)
    assertTrue(slotOf("SparkMe").spark:IsShown())
    Display:Update({}, now + 1)
end)

test("Settings Enable=false hides the bar; HideCombat follows the combat state", function()
    local now = 32500
    local feed = { { name = "VisA", start = 0, duration = 120, endTime = now + 120 } }
    Display:Update(feed, now)
    assertTrue(Display.anchor:IsShown())
    Settings:Set("Cooldown", "Enable", false)
    Display:Update(feed, now + 1)
    assertFalse(Display.anchor:IsShown())
    Settings:Set("Cooldown", "Enable", true)
    Display:Update(feed, now + 2)
    assertTrue(Display.anchor:IsShown())
    -- HideCombat = "hide when NOT in combat": stub the lockdown read.
    local real = InCombatLockdown
    Settings:Set("Cooldown", "HideCombat", true)
    _G.InCombatLockdown = function() return false end
    Display:Update(feed, now + 3)
    assertFalse(Display.anchor:IsShown())
    _G.InCombatLockdown = function() return true end
    Display:Update(feed, now + 4)
    assertTrue(Display.anchor:IsShown())
    _G.InCombatLockdown = real
    Settings:Reset("Cooldown", "HideCombat")
    Display:Update(feed, now + 5)
    assertTrue(Display.anchor:IsShown())
    Display:Update({}, now + 6)
end)

test("Settings IgnoreShort writes Engine.MIN_COOLDOWN (public field)", function()
    Settings:Set("Cooldown", "IgnoreShort", 8)
    near(Engine.MIN_COOLDOWN, 8)
    Settings:Reset("Cooldown", "IgnoreShort")
    near(Engine.MIN_COOLDOWN, 2.99)
end)

test("Settings AltTimeFormat switches the icon time text to m:ss", function()
    local now = 33000
    local feed = { { name = "AltFmt", start = 0, duration = 60, endTime = now + 45 } }
    Display:Update(feed, now)
    assertEquals("45.0", slotOf("AltFmt").timeFS:GetText())
    Settings:Set("General", "AltTimeFormat", true)
    Display:Update(feed, now)
    assertEquals("0:45", slotOf("AltFmt").timeFS:GetText())
    Settings:Reset("General", "AltTimeFormat")
    Display:Update(feed, now)
    assertEquals("45.0", slotOf("AltFmt").timeFS:GetText())
    Display:Update({}, now + 1)
end)

test("Settings BarFont re-validates and re-applies every fontstring live", function()
    local shipped = "Interface\\AddOns\\Forte_Core\\Fonts\\URWGothic-Book.ttf"
    local tag = Display.tagFS[1]
    -- Login already applied the stored default through this very seam,
    -- and the sim's [font] verdict accepted it (the game-font law of the
    -- "Init" test: the shipped file round-trips through CreateFont).
    assertTrue(tag:GetFont():lower() == shipped:lower())
    -- The options file is the same vendored file the page registers.
    assertEquals(shipped, Settings:Get("General", "BarFont"))
    -- SetBarFont routes through validateFontFile (CreateFont + SetFont
    -- pcall, the client's own acceptability verdict -- in the sim every
    -- path CreateFont takes is accepted, so what this proves is the live
    -- re-apply: the tag, title and every pooled time/count fontstring).
    Settings:Set("General", "BarFont", "Interface\\AddOns\\Forte_Core\\Fonts\\NOPE.ttf")
    assertTrue(tag:GetFont():lower()
        == "interface\\addons\\forte_core\\fonts\\nope.ttf")
    Settings:Reset("General", "BarFont")
    assertTrue(tag:GetFont():lower() == shipped:lower())
end)

test("ApplySettings pushes a whole table through the same seam", function()
    Display:ApplySettings({ Width = 260, MaxTime = 200, Spark = false })
    assertEquals(260, Display.anchor:GetWidth())
    near3(S.Max, 200)
    local now = 33500
    Display:Update({
        { name = "BulkA", start = 0, duration = 120, endTime = now + 120 },
    }, now)
    assertFalse(slotOf("BulkA").spark:IsShown())
    Display:ApplySettings({ Width = 250, MaxTime = 300, Spark = true })
    assertEquals(250, Display.anchor:GetWidth())
    near3(S.Max, 300)
    assertTrue(slotOf("BulkA").spark:IsShown())
    Display:Update({}, now + 1)
end)

test("Not-used-yet keys (FrameSnap, ShowTooltips) are inert and safe", function()
    -- Deliberately NOT in the Display KEYMAP: the Set must not move
    -- anything on the bar (documented in the pages' tips).
    local w0 = Display.anchor:GetWidth()
    local a0 = Display.anchor:GetAlpha()
    Settings:Set("General", "FrameSnap", true)
    Settings:Set("General", "ShowTooltips", false)
    assertEquals(w0, Display.anchor:GetWidth())
    near3(Display.anchor:GetAlpha(), a0)
    Settings:Reset("General", "FrameSnap")
    Settings:Reset("General", "ShowTooltips")
end)

-- ================================================================= m5 perf --

test("m5: two passes with unchanged state do not touch SetText at all", function()
    Display:Init()
    local now = 34000
    local feed = {
        { name = "QuietA", start = 0, duration = 120, endTime = now + 120.5 },
        { name = "QuietB", start = 0, duration = 46,  endTime = now + 45.6 },
    }
    Display:Update(feed, now)     -- binds, paints both icons once
    local a, b = slotOf("QuietA"), slotOf("QuietB")
    assertNotNil(a); assertNotNil(b)
    local ca, cb = 0, 0
    local origA, origB = a.timeFS.SetText, b.timeFS.SetText
    a.timeFS.SetText = function(fs, txt) ca = ca + 1; return origA(fs, txt) end
    b.timeFS.SetText = function(fs, txt) cb = cb + 1; return origB(fs, txt) end

    -- Two identical passes: zero format calls, zero SetText.
    Display:Update(feed, now)
    Display:Update(feed, now)
    assertEquals(0, ca)
    assertEquals(0, cb)

    -- The >= 60 icon (m:ss) rides whole seconds: 120.5 -> 120.2 stays
    -- "2:00", zero calls; the sub-minute icon crosses one tenth (45.6 ->
    -- 45.3) -- exactly one repaint.
    Display:Update(feed, now + 0.3)
    assertEquals(0, ca)
    assertEquals(1, cb)

    -- One full second later it is "1:59" -- exactly one repaint.
    Display:Update(feed, now + 1.1)
    assertEquals(1, ca)
    assertEquals("1:59", a.timeFS:GetText())

    -- The tenths icon crossed 44.6..44.5 -> "44.5", one repaint (2 total).
    assertEquals(2, cb)
    assertEquals("44.5", b.timeFS:GetText())

    a.timeFS.SetText = origA
    b.timeFS.SetText = origB
    Display:Update({}, now + 2)
end)

test("m5: TM.group reuses the caller's scratch tables pass over pass", function()
    local out = {}
    local e1 = { name = "GA", x = 100 }
    local e2 = { name = "GB", x = 103 }
    local e3 = { name = "GC", x = 200 }
    local g1 = TM.group({ e1, e2, e3 }, 24, out)
    assertTrue(g1 == out)                 -- the caller's table IS the result
    assertEquals(2, #g1)
    assertEquals(2, #g1[1])
    assertEquals("GC", g1[2][1].name)
    local sub1, sub2 = g1[1], g1[2]

    -- Second pass: identical structure -> the very same tables, no growth.
    local g2 = TM.group({ e1, e2, e3 }, 24, out)
    assertTrue(g2 == out)
    assertTrue(g2[1] == sub1 and g2[2] == sub2)
    assertEquals(2, #g2)
    assertEquals("GA", g2[1][1].name)
    assertEquals("GB", g2[1][2].name)

    -- A split pass (no overlap): both lists refilled, stale members gone.
    local g3 = TM.group({ e1, e3 }, 24, out)
    assertEquals(2, #g3)
    assertEquals(1, #g3[1])
    assertEquals(1, #g3[2])
    assertEquals("GA", g3[1][1].name)
    assertEquals("GC", g3[2][1].name)

    -- A shorter pass: stale groups drop off the live list.
    local g4 = TM.group({ e1 }, 24, out)
    assertEquals(1, #g4)
    assertEquals("GA", g4[1][1].name)

    -- The pure shape (no scratch) still returns fresh tables.
    local fresh = TM.group({ e1, e2, e3 }, 24)
    assertTrue(fresh ~= out)
    assertEquals(2, #fresh)
    assertEquals(2, #fresh[1])
end)

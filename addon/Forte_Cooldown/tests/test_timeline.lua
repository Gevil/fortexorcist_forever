-- addon/Forte_Cooldown/tests/test_timeline.lua
-- wow-ui-sim tests for the Classic Cooldown Timer timeline (PLAN.md §3.5):
-- UI/TimelineMath.lua (frame-free math) and UI/Timeline.lua (registered as
-- FX.Cooldown.Display, one 250x24 bar). Replaces test_display.lua, whose
-- rows-based renderer was forked into Forte_Timer's Spell Timer and whose
-- dormant seed file was deleted 2026-11-02.
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
    -- curve; the 1:00/0:02 texts ride on the icons (IconTime). The tenths
    -- print is off: the shipped General AltTimeFormat is ON (the original's
    -- TimeFormat = true, Forte_Core.lua:2487), so every time is m:ss.
    assertEquals("1:00", slotOf("Bestial Wrath").timeFS:GetText())
    assertEquals("0:02", slotOf("Concussive Shot").timeFS:GetText())

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
--     (:1407, :1418); with Spark[0] (default true, :1820) the icon rides the
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

-- CodeReview2 N1 (manager-verified 2026-11-02): the LIVE order is Sweep pops
-- the entry (gone from the feed) THEN OnReady(name). The pulse must still fire
-- from the departing slot; the test above masks this by keeping the row live.
test("a popped entry (gone from the feed) still pulses via OnReady", function()
    local function activePulses()
        local n = 0
        for _, p in ipairs(Display.pulsePool) do if p.frame:IsShown() then n = n + 1 end end
        return n
    end
    Display:Update({}, 199) -- clear any slots from earlier tests
    Display:Update({ { name = "Aimed Shot", start = 194, duration = 6, endTime = 200 } }, 199.5)
    local before = activePulses()
    Display:OnReady("Aimed Shot", 200)   -- Module order: entry already swept
    Display:Update({}, 200.05)           -- the feed no longer carries it
    assertEquals(before + 1, activePulses(), "the departing slot must spawn the ready pulse")
    assertNil(Display._ready["Aimed Shot"], "the queued pulse is consumed")
    Display:Update({}, 200 + S.PulseSeconds + 0.2)
    assertEquals(0, activePulses())
end)

-- CodeReview2 n2: spent pulse frames are reused; 20 sequential pops must not
-- grow the pool by 20.
test("ready pulses reuse spent pool frames (bounded pool)", function()
    Display:Update({}, 300)
    local t = 300
    for i = 1, 20 do
        Display:Update({ { name = "Multi-Shot", start = t - 6, duration = 6, endTime = t } }, t - 0.5)
        Display:OnReady("Multi-Shot", t)
        Display:Update({}, t + 0.05)                       -- live order: popped, then pulse
        Display:Update({}, t + S.PulseSeconds + 0.2)       -- pulse spent
        t = t + 10
    end
    assertTrue(#Display.pulsePool <= 3, "pool grew to " .. #Display.pulsePool)
end)

-- CodeReview3 m8: a sealed GetSpellTexture read leaves slot._texPath nil
-- (the secrecy law's own case). SetTexture(nil) leaves the icon empty, so
-- the ready-pulse rendered as a LONE ADD-blend spark flying the bar -- the
-- visual ghost. Such a pulse degrades to the spark-less flash; an icon-
-- carrying pulse keeps the source's full visual.
test("a nil-icon pulse rides the spark-less flash; an icon pulse keeps its glow",
function()
    Display:Update({}, 500)                      -- retire live pulses
    local function livePulses()
        local n = 0
        for _, p in ipairs(Display.pulsePool) do
            if p._endAt then n = n + 1 end
        end
        return n
    end
    local function livePulse()
        for _, p in ipairs(Display.pulsePool) do
            if p._endAt then return p end
        end
    end
    assertEquals(0, livePulses(), "clean slate")
    Display:SpawnPulse("Sealed Enchant", nil, { 1, 0.5, 0 }, 505)
    Display:Update({}, 500.05)
    assertEquals(1, livePulses(), "the sealed-icon pulse runs the fade law")
    local flash = livePulse()
    assertTrue(flash.frame:IsShown())
    assertFalse(flash.spark:IsShown(),
        "no LONE ADD-blend spark flies the bar (the m8 ghost)")
    Display:Update({}, 505 + S.PulseSeconds + 0.2)
    assertEquals(0, livePulses(), "the flash retires like every pulse")
    -- The icon-carrying pulse keeps the full pulse, spark on.
    Display:SpawnPulse("Real Icon", "Interface\\ICONS\\INV_Misc_Gem_03",
        { 1, 0.5, 0 }, 525)
    Display:Update({}, 520)
    local real = livePulse()
    assertNotNil(real)
    assertTrue(real.frame:IsShown())
    assertTrue(real.spark:IsShown(), "the icon pulse rides its 2.2x glow")
    Display:Update({}, 525 + S.PulseSeconds + 0.2)
    assertEquals(0, livePulses())
end)

-- CodeReview3 m2: the grow branch of AcquireSlot wrote the SHARED-
-- ENVIRONMENT global named `slot` (missing `local`). Every pool growth in
-- the suite so far went through that line, so the global is already set
-- before this test runs when the defect is present.
test("AcquireSlot leaks no global: _G.slot stays nil through pool growth",
function()
    Display:Init()
    assertEquals(nil, _G.slot, "the shared env has no `slot`")
    local a = Display:AcquireSlot()
    local b = Display:AcquireSlot()
    assertNotNil(a)
    assertNotNil(b)
    assertEquals(nil, _G.slot, "the grow branch leaks nothing")
    Display:ReleaseSlot(a)
    Display:ReleaseSlot(b)
    local c = Display:AcquireSlot()              -- the free-list branch
    assertTrue(c == a or c == b, "released slots are reused (LIFO)")
    assertEquals(nil, _G.slot, "the reuse branch leaks nothing")
    Display:ReleaseSlot(c)
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
    -- ("0:40" over "0", 3-4 chars). The string is m:ss because the shipped
    -- General AltTimeFormat is ON (Forte_Core.lua:2487).
    Display:Update({
        { name = "GeomCharge", start = 0, duration = 60, endTime = now + 40.0,
          charges = 0, maxCharges = 3, rechargeEnd = now + 40.0 },
    }, now)
    local slot = slotOf("GeomCharge")
    assertNotNil(slot)
    assertTrue(slot.chargeFS:IsShown())
    assertEquals("0:40", slot.timeFS:GetText())   -- the wide 4-char string
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

test("Settings AltTimeFormat: the shipped default IS m:ss; off gives the tenths",
function()
    -- Wave 4 item 3: the original ships `TimeFormat = true`
    -- (Forte_Core.lua:2487), so a fresh install prints m:ss for EVERY time
    -- and the key's live consumer is SetTimeFormatAlt. The test walks the
    -- default first -- a page default the consumer ignores is exactly the
    -- defect this row exists to catch.
    local now = 33000
    local feed = { { name = "AltFmt", start = 0, duration = 60, endTime = now + 45 } }
    assertEquals(true, Settings:GetDefault("General", "AltTimeFormat"))
    Settings:Reset("General", "AltTimeFormat")
    Display:Update(feed, now)
    assertEquals("0:45", slotOf("AltFmt").timeFS:GetText())
    -- The m:ss branch keys on the WHOLE SECOND: a half-second step that
    -- leaves the printed second alone costs no repaint...
    feed = { { name = "AltFmt", start = 0, duration = 60, endTime = now + 45.45 } }
    local slot = slotOf("AltFmt")
    local n = 0
    local orig = slot.timeFS.SetText
    slot.timeFS.SetText = function(fs, txt) n = n + 1; return orig(fs, txt) end
    Display:Update(feed, now + 0.15)
    assertEquals(0, n)
    -- ...and the step that crosses it costs exactly one.
    Display:Update(feed, now + 0.6)
    assertEquals(1, n)
    slot.timeFS.SetText = orig
    assertEquals("0:44", slot.timeFS:GetText())
    -- Off: the %0.1f branch of FW:SecToTimeD (Forte_Core.lua:1746-1761).
    local exact = { { name = "AltFmt", start = 0, duration = 60,
                      endTime = now + 45 } }
    Settings:Set("General", "AltTimeFormat", false)
    Display:Update(exact, now)
    assertEquals("45.0", slotOf("AltFmt").timeFS:GetText())
    Settings:Reset("General", "AltTimeFormat")
    Display:Update(exact, now)
    assertEquals("0:45", slotOf("AltFmt").timeFS:GetText())
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

-- Wave 6 'Options cosmetics' (docs/research/options-fidelity.md fix-list
-- item 9): the two Cooldown rows the survey's Sizing/Coloring blocks list as
-- missing. TextColor is the APPEARANCE block's "Bar text" (:1765, default
-- {1,1,1,0.20} :1838) -- the source's tag path rides it (SetTimeTags :1270,
-- :1289), and the icon time text keeps its OWN IconTextColor pair (:1837,
-- tested above). The IconSize pair is the FRAME SIZING block's third row
-- (:1760, the NU2 default {[0]=false, 36} :1805): gate OFF ships, so icons
-- ride the bar height (`ih = IconSize[0] and IconSize[1] or Height`, :1151,
-- :1364); gate ON, icons/glow/splash/pulse ride the value while the axis,
-- the tags and the segments keep riding Height (:502, :1236) -- the icons
-- grow IN PLACE.
test("Cosmetics: TextColor re-tints the time tags (the \"Bar text\" row)", function()
    Display:Init()
    Display:BuildTags()
    local tag = Display.tagFS[1]
    assertNotNil(tag, "the scale has tags to tint")
    local r, g, b, a = tag:GetTextColor()
    near3(r, 1); near3(g, 1); near3(b, 1)
    near3(a, FX.Settings:Get("Cooldown", "TextColor")[4])  -- default a 0.20
    Settings:Set("Cooldown", "TextColor", { 0.25, 0.75, 0.50, 0.90 })
    r, g, b, a = tag:GetTextColor()
    near3(r, 0.25); near3(g, 0.75); near3(b, 0.50); near3(a, 0.90)
    Settings:Reset("Cooldown", "TextColor")
    r, g, b, a = tag:GetTextColor()
    near3(r, 1); near3(b, 1); near3(a, 0.20)
end)

test("Cosmetics: the IconSize pair resizes the slots and pulses, not the axis", function()
    Display:Init()
    local now = 34000
    assertFalse(Settings:Get("Cooldown", "IconSizeOn"),
        "the gate ships OFF (:1805)")
    assertEquals(36, Settings:Get("Cooldown", "IconSize"))
    Display:Update({
        { name = "SizeA", start = 0, duration = 120, endTime = now + 120 },
    }, now)
    local slot = slotOf("SizeA")
    assertNotNil(slot)
    -- Gate off: the slot rides the bar height (the law :1151, :1364).
    assertEquals(24, slot.frame:GetWidth())
    assertEquals(24, slot.tex:GetWidth())
    -- Open the gate: the registered 36 shows on every pool part...
    Settings:Set("Cooldown", "IconSizeOn", true)
    assertEquals(36, slot.frame:GetWidth())
    assertEquals(36, slot.tex:GetHeight())
    near3(slot.spark:GetWidth(), 36 * S.SparkScale)
    near3(slot.alert:GetWidth(), 36 * S.AttentionScale)
    -- ...and the value moves with it.
    Settings:Set("Cooldown", "IconSize", 48)
    assertEquals(48, slot.frame:GetWidth())
    near3(slot.spark:GetWidth(), 48 * S.SparkScale)
    -- A slot BORN under the pair is born at its size, and the axis stays
    -- put: the curve rides the bar height (:502, :1236).
    local axis = slot._cx
    Display:Update({
        { name = "SizeA", start = 0, duration = 120, endTime = now + 120 },
        { name = "SizeB", start = 0, duration = 120, endTime = now + 200 },
    }, now)
    assertEquals(48, slotOf("SizeB").frame:GetWidth())
    assertEquals(axis, slotOf("SizeA")._cx)
    -- The ready pulse rides the size too (the source's spawn geometry).
    Display:OnReady("SizeB", now + 0.1)
    Display:Update({
        { name = "SizeA", start = 0, duration = 120, endTime = now + 120 },
    }, now + 0.05)
    local pulse = Display.pulsePool[1]
    assertNotNil(pulse, "the release spawned the pulse")
    assertEquals(48, pulse.tex:GetWidth())
    near3(pulse.spark:GetWidth(), 48 * S.SparkScale)
    -- Closing the gate rides every pool back onto the Height law.
    Settings:Reset("Cooldown", "IconSizeOn")
    assertEquals(24, slotOf("SizeA").frame:GetWidth())
    assertEquals(24, slot.tex:GetWidth())
    Settings:Reset("Cooldown", "IconSize")
    Display:Update({}, now + 5)
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

-- ------------------------------------------------- wave 4 (OptionsCD) rows --
-- The Cooldown page's SPECIFICS icon block (Forte_Cooldown.lua :1716-1719),
-- its SPLASH block (:1723-1724) and its TIME RANGE filters (:1729-1732),
-- driven through the same FX.Settings seam the options window uses.

test("Settings BarAlpha/BarAlphaMax move the icon and segment alpha range live",
function()
    -- The pair (`Alpha` :1818 / `AlphaMax` :1819, labels "Minimum/Maximum bar
    -- alpha" :1716-1717): a fresh icon starts at Alpha on the
    -- FRESH-VISIBILITY ramp (:1402 with :611-614), a settled one rides
    -- AlphaMax, and the segment fill rides AlphaMax-(AlphaMax-Alpha)*t7
    -- (:1404). Without the _alpha/_segSetA bust the applied value of an
    -- already-drawn slot is stale and the new numbers never reach frames.
    Display:Init()
    local now = 48000
    local feed = { { name = "AlphaPair", start = 0, duration = 999,
                     endTime = now + 200 } }
    Settings:Reset("Cooldown", "BarAlpha")
    Settings:Reset("Cooldown", "BarAlphaMax")
    Display:Update(feed, now)
    local slot = slotOf("AlphaPair")
    assertNotNil(slot)
    near3(slot.frame:GetAlpha(), 0.2)
    near3(slot.seg:GetAlpha(), 0.2)
    Settings:Set("Cooldown", "BarAlpha", 0.6)
    Display:Update(feed, now)                    -- the same instant, p = 0
    near3(slot.frame:GetAlpha(), 0.6)
    near3(slot.seg:GetAlpha(), 0.6)
    -- The ceiling is what a settled icon rides.
    Display:Update(feed, now + S.FadeSeconds)
    near3(slot.frame:GetAlpha(), 1.0)
    Settings:Set("Cooldown", "BarAlphaMax", 0.4)
    Display:Update(feed, now + S.FadeSeconds)
    near3(slot.frame:GetAlpha(), 0.4)
    near3(slot.seg:GetAlpha(), 0.4)
    Settings:Reset("Cooldown", "BarAlpha")
    Settings:Reset("Cooldown", "BarAlphaMax")
    Display:Update({}, now + S.FadeSeconds + 1)
end)

test("Settings IconTime shows/hides the icon text; IconTextColor rides its gate",
function()
    -- `IconTime` (:1718, default on :1835) and the CO2 `IconTextColor`
    -- = {[0]=false,1,1,1,1} (:1719, :1837): the source picks the custom
    -- colour on the [0] gate and the FixIntensity(category) tint off it
    -- (:1419-1425).
    Display:Init()
    local now = 48500
    local feed = { { name = "IconTxt", start = 0, duration = 60,
                     endTime = now + 45 } }
    Display:Update(feed, now)
    local slot = slotOf("IconTxt")
    assertNotNil(slot)
    assertTrue(slot.timeFS:IsShown(), "IconTime ships on (:1835)")
    local br, bg, bb = slot.timeFS:GetTextColor()   -- the category tint
    Settings:Set("Cooldown", "IconTextColor", { 0.25, 0.90, 0.10, 1 })
    local ar, ag, ab = slot.timeFS:GetTextColor()
    assertTrue(br == ar and bg == ag and bb == ab,
        "the [0] gate is off, so a custom colour alone is inert (:1837)")
    Settings:Set("Cooldown", "IconTextColorOn", true)
    local cr, cg, cb = slot.timeFS:GetTextColor()
    near3(cr, 0.25); near3(cg, 0.90); near3(cb, 0.10)
    -- The re-tint reaches a slot that was bound BEFORE the gate went on.
    Settings:Set("Cooldown", "IconTextColor", { 0.10, 0.20, 0.80, 1 })
    local dr, dg, db = slot.timeFS:GetTextColor()
    near3(dr, 0.10); near3(dg, 0.20); near3(db, 0.80)
    Settings:Set("Cooldown", "IconTextColorOn", false)
    local er, eg, eb = slot.timeFS:GetTextColor()
    assertTrue(er == br and eg == bg and eb == bb,
        "off rides the FixIntensity(category) tint again")
    -- The text gate: off takes the string off the live icons AND off a slot
    -- bound later (it is born hidden).
    Settings:Set("Cooldown", "IconTime", false)
    assertFalse(slot.timeFS:IsShown())
    Display:Update({ { name = "IconTxt2", start = 0, duration = 60,
                       endTime = now + 90 } }, now)
    assertFalse(slotOf("IconTxt2").timeFS:IsShown(),
        "a slot bound while the gate is off is born hidden")
    Settings:Reset("Cooldown", "IconTime")
    assertTrue(slot.timeFS:IsShown())
    assertTrue(slotOf("IconTxt2").timeFS:IsShown())
    Settings:Reset("Cooldown", "IconTextColor")
    Display:Update({}, now + 1)
end)

test("Settings Time Range filters drop rows off the bar, gates off by default",
function()
    -- The four NU2 rows :1729-1732: CD_TimeFilterDuration rides the row's
    -- TOTAL duration (the source's cd[i][4]) and CD_TimeFilterRemaining its
    -- live remaining (cd[i][2]), each behind its own [0] gate, defaults
    -- 0/3600/0/3600 with every gate OFF (:1826-1829).
    Display:Init()
    local now = 49000
    local feed = {
        { name = "RangeShort", start = 0, duration = 30, endTime = now + 30 },
        { name = "RangeLong", start = 0, duration = 600, endTime = now + 600 },
    }
    Display:Update(feed, now)
    assertNotNil(slotOf("RangeShort"), "every gate ships off")
    assertNotNil(slotOf("RangeLong"))
    Display:Update({}, now + 0.5)

    local function gateOn(key, value)
        Settings:Set("Cooldown", key .. "On", true)
        Settings:Set("Cooldown", key, value)
        Display:Update(feed, now)
    end
    local function gateOff(key)
        Settings:Reset("Cooldown", key .. "On")
        Settings:Reset("Cooldown", key)
        Display:Update({}, now + 0.5)
    end
    -- Minimum duration: the 30 s row is under a 120 s floor.
    gateOn("MinRange", 120)
    assertNil(slotOf("RangeShort"), "a 30 s row fails a 120 s floor")
    assertNotNil(slotOf("RangeLong"))
    gateOff("MinRange")
    -- Maximum duration: the 600 s row is over a 120 s ceiling.
    gateOn("MaxRange", 120)
    assertNil(slotOf("RangeLong"), "a 600 s row fails a 120 s ceiling")
    assertNotNil(slotOf("RangeShort"))
    gateOff("MaxRange")
    -- Minimum remaining / maximum remaining ride the LIVE remaining (30
    -- and 600 here), not the row's length.
    gateOn("MinRemaining", 100)
    assertNil(slotOf("RangeShort"), "30 s left is under a 100 s floor")
    assertNotNil(slotOf("RangeLong"))
    gateOff("MinRemaining")
    gateOn("MaxRemaining", 100)
    assertNil(slotOf("RangeLong"), "600 s left is over a 100 s ceiling")
    assertNotNil(slotOf("RangeShort"))
    gateOff("MaxRemaining")
    -- Both rows draw again with the gates off.
    Display:Update(feed, now)
    assertNotNil(slotOf("RangeShort"))
    assertNotNil(slotOf("RangeLong"))
    Display:Update({}, now + 0.5)
end)

test("Settings HideZero sees the filtered bar as empty (the filter is a view)",
function()
    -- `_lastCount` is the number of rows the bar DRAWS, so a bar whose every
    -- row the Time Range filter drops is, for the auto-hide law (:1348), a
    -- bar with no visible cooldown.
    Display:Init()
    local now = 49500
    local feed = {
        { name = "ZeroShort", start = 0, duration = 30, endTime = now + 30 },
    }
    Settings:Set("Cooldown", "HideZero", true)
    Settings:Set("Cooldown", "MinRangeOn", true)
    Settings:Set("Cooldown", "MinRange", 120)
    Display:Update(feed, now)
    assertNil(slotOf("ZeroShort"))
    assertFalse(Display.anchor:IsShown(),
        "the filter leaves the bar nothing to draw")
    Settings:Reset("Cooldown", "MinRangeOn")
    Settings:Reset("Cooldown", "MinRange")
    Display:Update(feed, now)
    assertTrue(Display.anchor:IsShown())
    Display:Update({}, now + 0.5)
    Settings:Reset("Cooldown", "HideZero")
end)

test("Settings Splash gates the expiry visual; SplashFactor scales it",
function()
    -- `Splash` (:1723, default on :1811) is the gate of the source's
    -- t15==-1 curve (`if s.Splash and t15 == -1`, :1380); this port renders
    -- that one curve as the cast splash AND the ready pulse, so the gate
    -- rules both. `SplashFactor` (:1724, default 4 :1812) is the bell's peak
    -- multiplier: size = SplashFactor * ih * (1 - t14) (:1381).
    Display:Init()
    local function liveSplashes()
        local n = 0
        for _, s in ipairs(Display.splashPool) do
            if s.frame:IsShown() then n = n + 1 end
        end
        return n
    end
    local function livePulses()
        local n = 0
        for _, p in ipairs(Display.pulsePool) do
            if p.frame:IsShown() then n = n + 1 end
        end
        return n
    end
    local now = 50000
    Display:Update({}, now)
    Settings:Set("Cooldown", "Splash", false)
    local pool0 = #Display.splashPool
    local feed = { { name = "SplashGate", start = 0, duration = 60,
                     endTime = now + 60 } }
    Display:Update(feed, now)
    assertNotNil(slotOf("SplashGate"))
    assertEquals(0, liveSplashes(), "the gate is off (:1380)")
    assertEquals(pool0, #Display.splashPool, "the pool is not even touched")
    Display:OnReady("SplashGate", now + 0.1)
    Display:Update(feed, now + 0.1)
    assertEquals(0, livePulses(), "the ready pulse is the same gated curve")
    Settings:Reset("Cooldown", "Splash")
    Display:Update({}, now + 1)
    -- Back on: a fresh name splashes, and the peak scale is the factor's.
    local feed2 = { { name = "SplashScale", start = 0, duration = 60,
                      endTime = now + 160 } }
    Settings:Set("Cooldown", "SplashFactor", 8)
    Display:Update(feed2, now + 2)
    local s = liveSplash()
    assertNotNil(s, "the gate is back on")
    Display:Update(feed2, now + 2 + S.SplashSeconds * 0.5)
    near3(s.tex:GetWidth(), 8 * S.Height * 0.5)
    Settings:Reset("Cooldown", "SplashFactor")
    Display:Update({}, now + 2 + S.SplashSeconds + 0.01)
end)

-- ================================================================= m5 perf --

test("m5: two passes with unchanged state do not touch SetText at all", function()
    Display:Init()
    -- This is the %0.1f branch's tenth-granularity key, so pin the branch:
    -- the shipped General AltTimeFormat is ON (Forte_Core.lua:2487) and its
    -- whole-second key is proven in the AltTimeFormat settings test.
    Settings:Set("General", "AltTimeFormat", false)
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
    Settings:Reset("General", "AltTimeFormat")
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

-- ================================================================= n6 perf --

-- CodeReview2 n6 (1/2): the m5 pass left groupSignature allocating a parts
-- table and a table.concat string per MULTI-MEMBER GROUP per 10 Hz pass. The
-- signature is the cross-fade state key, and the group lists are the
-- Display's own scratch, so the string now rides the group and is rebuilt
-- only when the membership moves.
test("n6: an unchanged overlap group costs no table.concat on the next pass", function()
    Display:Init()
    local now = 36000
    local a = { name = "SigA", start = 0, duration = 45, endTime = now + 40 }
    local b = { name = "SigB", start = 0, duration = 45, endTime = now + 41 }
    local feed = { a, b }
    Display:Update(feed, now)          -- binds + the first signature build
    assertNotNil(Display._xf["SigA|SigB"],
        "the two icons overlap into one cross-fade group")

    local real = table.concat
    local concats = 0
    table.concat = function(...) concats = concats + 1; return real(...) end
    Display:Update(feed, now)
    Display:Update(feed, now)
    table.concat = real
    assertEquals(0, concats,
        "a settled group must not rebuild its signature string per tick")
    assertNotNil(Display._xf["SigA|SigB"], "the cached key is the same one")

    -- The cache is per group AND per membership: a member joining rebuilds
    -- the signature exactly once (the cache is not sticky).
    local c = { name = "SigC", start = 0, duration = 45, endTime = now + 41.5 }
    concats = 0
    table.concat = function(...) concats = concats + 1; return real(...) end
    Display:Update({ a, b, c }, now)
    table.concat = real
    assertEquals(1, concats, "a changed membership rebuilds the signature once")
    assertNotNil(Display._xf["SigA|SigB|SigC"], "under a new key")

    -- Unchanged again: back to zero allocations.
    concats = 0
    table.concat = function(...) concats = concats + 1; return real(...) end
    Display:Update({ a, b, c }, now)
    table.concat = real
    assertEquals(0, concats)
    Display:Update({}, now + 1)
end)

-- CodeReview2 n6 (2/2): the template-fallback branch stored `_font = nil`,
-- so the dirty check never cached and SetFontTemplate re-ran on every
-- fontstring of every tag rebuild on the rejected-font path.
test("n6: the template-font fallback caches (no SetFontTemplate re-run)", function()
    Display:Init()
    local fs = Display.tagFS[1]
    assertNotNil(fs, "the tag fontstrings exist after Init")
    local saved = Display.fontFile
    -- The rejected-BarFont state the header documents: no accepted file, so
    -- every string rides the template branch.
    Display.fontFile = nil
    Display:BuildTags()                 -- applies the template once
    local real = fs.SetFontTemplate
    local calls = 0
    fs.SetFontTemplate = function(...) calls = calls + 1; return real(...) end
    Display:BuildTags()
    Display:BuildTags()
    fs.SetFontTemplate = real
    assertEquals(0, calls,
        "the sentinel key must cache the template state (n6)")
    -- The sentinel is a SECOND accepted key, not the only key: bringing the
    -- accepted file back moves past it and the string re-applies.
    Display.fontFile = saved
    local realSet = fs.SetFont
    local sets = 0
    fs.SetFont = function(...) sets = sets + 1; return realSet(...) end
    Display:BuildTags()
    fs.SetFont = realSet
    if saved then
        assertTrue(sets >= 1, "a real BarFont after the sentinel re-applies")
    end
end)

-- ==================================================== CD-31 Warn (attention) ==
-- CD-31 (spec §1.5): UNIT_SPELLCAST_FAILED for the player, mapped spellID ->
-- name, grabs attention on that spell's live cooldown row -- "you tried to
-- cast something that is cooling": the icon flashes (the source's
-- bar.icon.attentionspark, Forte_Cooldown.lua :1408-1415: the ADD-blend Spark2
-- shown while cd[i][20] > 1 at size 2.2*ih*t20, tinted FixIntensity(category))
-- and steals the group's cross-fade focus (CD_FocusTimer :860-877: the warned
-- row gets cd[i][15] = 1 and cd[i][14] = 1, EVERY other member of the group
-- cd[i][14] = cd[i][15] = 0). The window is `local focustime = 0.5` (:32)
-- stamped as cd[i][20] = 1 + focustime (:874) and decayed by the ELAPSED
-- SECONDS at 1/s (:528-530), so t20 rides 1.5 -> 1.0 over 0.5 s.
--
-- The event dispatch is the suite's established pattern (test_tiers.lua:619-
-- 640, test_enchants.lua:433-446): the module frame's own OnEvent handler,
-- called as the engine calls it, frame first (PLAN §10.2).

local WARN_ID = 410001          -- the spellID the stub resolves to "WarnB"

local function stubSpellInfo(map)
    local real = C_Spell and C_Spell.GetSpellInfo
    if C_Spell then C_Spell.GetSpellInfo = function(id) return map[id] end end
    return function() if C_Spell then C_Spell.GetSpellInfo = real end end
end

local function dispatchFailed(spellID)
    local f = Display._eventFrame
    assertNotNil(f, "Init registers the Display's own event frame")
    local handler = f:GetScript("OnEvent")
    assertEquals("function", type(handler), "Warn is on => the handler is installed")
    -- The pinned catalog's payload (@UnitDocumentation.lua:4713):
    -- unitTarget, castGUID, spellID, castBarID.
    handler(f, "UNIT_SPELLCAST_FAILED", "player", "FXTEST-GUID", spellID, 12)
end

local function liveAlerts()
    local n = 0
    for i = 1, #Display.slots do
        if Display.slots[i].alert:IsShown() then n = n + 1 end
    end
    return n
end

test("CD-31: the Warn checkbox installs / removes the UNIT_SPELLCAST_FAILED handler", function()
    Display:Init()
    assertNotNil(Display._eventFrame, "the frame exists after Init")
    assertNotNil(Display._eventFrame:GetScript("OnEvent"), "Warn defaults ON (:1821)")
    assertEquals(true, S.Warn)
    Settings:Set("Cooldown", "Warn", false)
    assertNil(Display._eventFrame:GetScript("OnEvent"),
        "the source's UnregisterToEvent branch (:957-959)")
    Settings:Set("Cooldown", "Warn", true)
    assertNotNil(Display._eventFrame:GetScript("OnEvent"), "back on (:956)")
end)

test("CD-31: a failed cast of a cooling spell flashes that icon and steals the focus", function()
    local now = 41000
    local A = { name = "WarnA", start = 0, duration = 999, endTime = now + 20.0 }
    local B = { name = "WarnB", start = 0, duration = 999, endTime = now + 20.35 }
    local feed = { A, B }
    local W, H, Max, Loga = S.Width, S.Height, S.Max, S.Loga
    local dx = math.abs(TM.pos(20.35, W, H, Max, Loga) - TM.pos(20.0, W, H, Max, Loga))
    assertTrue(dx < H * 0.5, "the two icons share one cross-fade group")

    Display:Update({}, 40900)
    assertEquals(0, liveAlerts(), "clean slate")
    Display:Update(feed, now)
    -- The fade-in completes over FadeSeconds; at exactly one CrossfadeSeconds
    -- the focus has handed off, so B is the lit member and A the dark one.
    Display:Update(feed, now + 1.0)
    local a, b = slotOf("WarnA"), slotOf("WarnB")
    near3(a.frame:GetAlpha(), 0.0, "A is the dark member")
    near3(b.frame:GetAlpha(), 1.0, "B holds the focus")

    -- The failed cast of B (the spell the player reached for, mid-cooldown).
    local restore = stubSpellInfo({ [WARN_ID] = { name = "WarnB" } })
    dispatchFailed(WARN_ID)
    restore()

    local t = now + 1.05
    Display:Update(feed, t)
    -- (1) THE FLASH: only B's attention spark is up, at the source's size
    -- 2.2*ih*t20 with t20 = 1 + (the seconds left of focustime) = 1.5 here.
    assertTrue(b.alert:IsShown(), "the warned icon flashes")
    assertFalse(a.alert:IsShown(), "the other icon does not")
    assertEquals(1, liveAlerts())
    near3(b.alert:GetWidth(), S.AttentionScale * S.Height * 1.5)
    near3(b.alert:GetHeight(), S.AttentionScale * S.Height * 1.5)
    -- The tint is FixIntensity(category) (:1412 rides the r,g,b the
    -- running spark got at :1407).
    local sc = S.Colors.Spell
    local er, eg, eb = 0.7 * sc[1] + 0.3, 0.7 * sc[2] + 0.3, 0.7 * sc[3] + 0.3
    local r, g, b2 = b.alert:GetVertexColor()
    near3(r, er); near3(g, eg); near3(b2, eb)
    -- (2) THE FOCUS STEAL: B is drawn FULL and every other member of the
    -- group is driven to zero (CD_FocusTimer :867-871), i.e. the alpha that
    -- the plain rotation would have given B (frac = 0.05) is replaced by 1.
    near3(b.frame:GetAlpha(), 1.0, "the warned icon took the focus")
    near3(a.frame:GetAlpha(), 0.0, "and the group's other members go dark")
    -- The window is focustime long: 0.25 s in the spark has contracted by
    -- 0.25 of the 2.2*ih base, and at 0.5 s it is gone (:1413 Hide).
    Display:Update(feed, t + S.WarnSeconds * 0.5)
    near3(b.alert:GetWidth(), S.AttentionScale * S.Height * 1.25)
    Display:Update(feed, t + S.WarnSeconds + 0.01)
    assertFalse(b.alert:IsShown(), "the attention window is focustime = 0.5 s")
    assertEquals(0, liveAlerts())
    Display:Update({}, t + 1.0)
end)

test("CD-31: Warn off, an unknown spellID and a spell that is NOT cooling all flash nothing", function()
    local now = 42000
    local feed = { { name = "WarnSolo", start = 0, duration = 999, endTime = now + 40 } }
    Display:Update({}, 41900)
    Display:Update(feed, now)
    local solo = slotOf("WarnSolo")
    assertTrue(solo.frame:IsShown())
    local restore = stubSpellInfo({ [WARN_ID] = { name = "WarnSolo" } })

    -- Warn OFF: the handler is gone (the source unregisters it, :957-959),
    -- and the handler body itself refuses to record the request.
    Settings:Set("Cooldown", "Warn", false)
    Display:CastFailed(WARN_ID)
    Display:Update(feed, now + 0.1)
    assertEquals(0, liveAlerts(), "the Warn gate is the flash's only door")
    Settings:Set("Cooldown", "Warn", true)

    -- An unresolvable spellID (a secret read / an unknown spell): no name,
    -- nothing to warn about.
    Display:CastFailed(999999999)
    Display:Update(feed, now + 0.2)
    assertEquals(0, liveAlerts(), "an unresolvable spellID is inert")

    -- A RESOLVED name that is not on the bar is not "cooling" (:938 scans the
    -- live rows only): the cast was of something else entirely.
    Display:CastFailed(-1)     -- resolves to nil through the stub map
    Display:Update(feed, now + 0.3)
    assertEquals(0, liveAlerts())
    restore()

    local restore2 = stubSpellInfo({ [WARN_ID] = { name = "NotOnTheBar" } })
    Display:CastFailed(WARN_ID)
    Display:Update(feed, now + 0.4)
    assertEquals(0, liveAlerts(), "only a live entry on the bar can flash")
    restore2()

    -- The same spell, live on the bar: the flash fires (the gate is what is
    -- under test, so this is the positive control).
    local restore3 = stubSpellInfo({ [WARN_ID] = { name = "WarnSolo" } })
    Display:CastFailed(WARN_ID)
    Display:Update(feed, now + 0.5)
    assertEquals(1, liveAlerts(), "a singleton takes the flash too (no group to steal)")
    restore3()
    Display:Update({}, now + 2.0)
    assertEquals(0, liveAlerts())
end)

test("CD-31: a BUFF / DEBUFF category row is excluded from the attention (:939)", function()
    local now = 43000
    Display:Update({}, 42900)
    Display:Update({
        { name = "WarnBuff", start = 0, duration = 999, endTime = now + 40,
          category = "Buff" },
    }, now)
    local restore = stubSpellInfo({ [WARN_ID] = { name = "WarnBuff" } })
    Display:CastFailed(WARN_ID)
    Display:Update({
        { name = "WarnBuff", start = 0, duration = 999, endTime = now + 40,
          category = "Buff" },
    }, now + 0.1)
    assertEquals(0, liveAlerts(), "the source skips FLAG_BUFF / FLAG_DEBUFF rows")
    restore()
    Display:Update({}, now + 1.0)
end)

-- ================================================= CD-30 right-click = options ==
-- CD-30 (spec §1.5): the bar's mouse release with the right button opens the
-- options window scrolled to this module (`FW:ScrollTo(FWL.COOLDOWN_TIMER)`,
-- Forte_Cooldown.lua :901-909), guarded by `FW:Moved()` (:902) so a drag never
-- opens it. FW:Moved() is the press-to-release cursor compare
-- (Forte_Core/Options.lua:659-662 against the stamp at :649-656).

test("CD-30: a right-button release on the bar opens the Cooldown page; a drag does not", function()
    Display:Init()
    local O = FX.Options
    assertNotNil(O, "Forte_Options loads in every gate run")
    local release = Display.anchor:GetScript("OnMouseUp")
    assertNotNil(release, "the bar carries the release handler")
    O:Close()

    -- A press and a release on the same pixel: the page opens on Cooldown.
    Display:_StampPress()
    release(Display.anchor, "RightButton")
    assertEquals(true, O:IsOpen())
    assertEquals("Cooldown", O.pageId)
    O:Close()
    assertFalse(O:IsOpen())

    -- A DRAG: the cursor travelled between the press stamp and the release,
    -- so Moved() is true and the window stays shut (:902).
    local realPos = GetCursorPosition
    Display:_StampPress()
    assertEquals(false, Display:Moved(), "no travel yet")
    _G.GetCursorPosition = function() return 400, 400 end
    Display._downX, Display._downY = 300, 300
    assertEquals(true, Display:Moved(), "the cursor travelled")
    release(Display.anchor, "RightButton")
    assertEquals(false, O:IsOpen(), "a drag never opens the options window")
    _G.GetCursorPosition = realPos

    -- The left button is the drag button, not the options button (:903).
    Display._downX, Display._downY = 100, 100
    _G.GetCursorPosition = function() return 100, 100 end
    release(Display.anchor, "LeftButton")
    assertEquals(false, O:IsOpen())
    _G.GetCursorPosition = realPos
    Display._downX, Display._downY = nil, nil
end)

-- The lock law (the source: the lock gates the DRAG START -- the one lock
-- check in the move path is FW:StartMoving's, Forte_Core/Options.lua:651,
-- and the row label is literally "Lock (disable dragging)",
-- Forte_Cooldown.lua:2114; a locked frame's release keeps firing, e.g. the
-- source's Forte_Soulstone.xml OnMouseUp). The bar SHIPS locked, so the
-- CD-30 seam is only real if the lock leaves the mouse alone.

test("The lock law: a locked bar's release opens the page, its drag starts no move",
function()
    Display:Init()
    local O = FX.Options
    O:Close()
    local f = Display.anchor
    local release = f:GetScript("OnMouseUp")
    local dragStart = f:GetScript("OnDragStart")
    local dragStop = f:GetScript("OnDragStop")
    Display:SetLocked(true)
    assertTrue(Display.cfg.locked, "the bar ships locked")
    assertFalse(f:IsMovable(), "the lock removes the drag")
    if f.IsMouseEnabled then
        -- (method-presence probe, the test_swing.lua:262 pattern) The lock
        -- law: it gates the dragging, it NEVER takes the frame's mouse --
        -- the row label is "Lock (disable dragging)".
        assertTrue(f:IsMouseEnabled(), "locked keeps the mouse: the seam is live")
    end
    local realPos = GetCursorPosition
    _G.GetCursorPosition = function() return 120, 120 end
    Display:_StampPress()
    release(f, "RightButton")
    assertTrue(O:IsOpen(), "a LOCKED bar opens the options window")
    assertEquals("Cooldown", O.pageId)
    O:Close()
    -- The belt: driving the drag script by hand while locked stamps the
    -- press (the stamp is unconditional, :649-656) and starts NO move;
    -- unlocked, the same driving starts it -- the zero above is the lock,
    -- not the rig.
    Display._downX, Display._downY = nil, nil
    local x0, y0 = f:GetLeft(), f:GetTop()
    dragStart(f, "LeftButton")
    assertNotNil(Display._downX, "the press stamps, lock or not")
    assertEquals(x0, f:GetLeft())
    assertEquals(y0, f:GetTop())
    if f.IsMoving then
        -- (method-presence probe, the test_swing.lua:262 pattern)
        assertFalse(f:IsMoving(), "locked: the script starts no move")
        Display:SetLocked(false)
        dragStart(f, "LeftButton")
        assertTrue(f:IsMoving(), "unlocked, the same driving starts the move")
        dragStop(f)
        assertFalse(f:IsMoving())
    end
    _G.GetCursorPosition = realPos
    Display._downX, Display._downY = nil, nil
    Display:SetLocked(true)
end)

-- ==================================================== CD-35 geometry modes ==
-- CD-35 (spec §1.5): `Vertical` (the icons bottom -> top along the bar) and
-- `Flip` (right -> left, tags mirrored). The source's draw loop picks the
-- icon's anchor POINT from exactly these two flags (:1427-1450), the tag pass
-- the same four points (:1260-1263), and the frame size swaps in frame.Update
-- (:1476-1479) -- the POSITION on the axis is TimelineMath.pos in all four
-- modes, which is what these tests measure.

test("CD-35 Vertical: the frame swaps to 24x250 and the icons run bottom -> top on pos()", function()
    Display:Init()
    local W, H, Max, Loga = S.Width, S.Height, S.Max, S.Loga
    local now = 44000
    local feed = {
        { name = "VertA", start = 0, duration = 999, endTime = now + 60 },
        { name = "VertB", start = 0, duration = 999, endTime = now + 120 },
    }
    Settings:Set("Cooldown", "Vertical", true)
    Display:Update(feed, now)

    -- frame.Update :1476-1479: SetWidth(Height + 2*d) / SetHeight(Width + 2*d)
    -- (the port keeps the 250x24 axis itself and insets the backdrop).
    assertEquals(H, Display.anchor:GetWidth())
    assertEquals(W, Display.anchor:GetHeight())

    for _, e in ipairs(feed) do
        local slot = slotOf(e.name)
        local point, _, relPoint, xoff, yoff = slot.frame:GetPoint()
        -- The source's non-flip Vertical branch: icon CENTER -> bar BOTTOM,
        -- offset (0, +t10) (:1446-1448).
        assertEquals("BOTTOM", point)
        assertEquals("BOTTOM", relPoint)
        near3(xoff, 0)
        near3(yoff, TM.pos(e.endTime - now, W, H, Max, Loga),
            e.name .. " rides pos() up the bar")
    end

    -- The time tags ride the same axis: the "60" tag (index 5 of the default
    -- list 0 1 10 30 60 120 + the Max tag) sits at its pos value on y.
    local tagY = { Display.tagFS[5]:GetPoint() }
    near3(tagY[5], S.Inset + TM.pos(60, W, H, Max, Loga) - W * 0.5)
    near3(tagY[4], 0)

    -- The segment slice runs up the bar: the first group spans the bar's
    -- BOTTOM (leftX = 0) to its own centre (:1433-1435).
    local segPoint, _, segRel, sx, sy = slotOf("VertA").seg:GetPoint()
    assertEquals("TOPLEFT", segPoint)
    assertEquals("TOPLEFT", segRel)
    near3(sx, 0)
    near3(sy, TM.pos(60, W, H, Max, Loga) + H * 0.5 - (W - 2 * S.Inset))
    local p2, _, _, _, y2 = slotOf("VertA").seg:GetPoint(2)
    assertEquals("BOTTOMRIGHT", p2)
    near3(y2, 0)

    -- The ready pulse rides the axis' origin end too (:1176-1181 anchor law).
    Display:OnReady("VertA", now + 1)
    Display:Update(feed, now + 1.05)
    local pulse
    for i = 1, #Display.pulsePool do
        local p = Display.pulsePool[i]
        if p._name == "VertA" and p._endAt then pulse = p end
    end
    assertNotNil(pulse, "the ready pulse is live")
    -- The splash/pulse frames are CENTRE-anchored (axisOffset lays the
    -- centre offset out on the current axis), not origin-anchored.
    local pp, _, _, px, py = pulse.frame:GetPoint()
    assertEquals("CENTER", pp)
    near3(px, 0)
    near3(py, S.Inset + TM.pos(0, W, H, Max, Loga) + H * 0.5 - W * 0.5)

    Settings:Reset("Cooldown", "Vertical")
    Display:Update({}, now + 3)
    -- Back to the horizontal law: the size and the anchors swap right back.
    assertEquals(W, Display.anchor:GetWidth())
    assertEquals(H, Display.anchor:GetHeight())
end)

test("CD-35 Flip: the icons run right -> left, mirrored exactly about the bar centre", function()
    Display:Init()
    local W, H, Max, Loga = S.Width, S.Height, S.Max, S.Loga
    local now = 45000
    local feed = {
        { name = "FlipA", start = 0, duration = 999, endTime = now + 60 },
        { name = "FlipB", start = 0, duration = 999, endTime = now + 120 },
    }
    local function centreX(obj)
        return (obj:GetLeft() + obj:GetRight()) * 0.5
    end
    -- The unflipped reference: the centres of the icons and of the "60" tag.
    Display:Update(feed, now)
    local baseA, baseB = centreX(slotOf("FlipA").frame),
        centreX(slotOf("FlipB").frame)
    local baseTag = centreX(Display.tagFS[5])
    local barCentre = centreX(Display.bar)
    Display:Update({}, now + 1)

    Settings:Set("Cooldown", "Flip", true)
    Display:Update(feed, now)
    for _, e in ipairs(feed) do
        local slot = slotOf(e.name)
        local point, _, relPoint, xoff, yoff = slot.frame:GetPoint()
        -- The source's Flip branch: icon CENTER -> bar RIGHT, (-t10, 0)
        -- (:1440-1442).
        assertEquals("RIGHT", point)
        assertEquals("RIGHT", relPoint)
        near3(xoff, -TM.pos(e.endTime - now, W, H, Max, Loga),
            e.name .. " rides pos() measured from the RIGHT end")
        near3(yoff, 0)
        -- The numeric mirror: the flipped centre is the unflipped centre
        -- reflected in the bar's centre.
        local base = (e.name == "FlipA") and baseA or baseB
        near3(centreX(slot.frame) - barCentre, -(base - barCentre))
    end
    -- The tags are mirrored the same way (:1263: "RIGHT",-d,0).
    near3(centreX(Display.tagFS[5]) - barCentre, -(baseTag - barCentre))
    local segPoint, _, _, sx = slotOf("FlipA").seg:GetPoint()
    assertEquals("TOPRIGHT", segPoint)
    near3(sx, 0)                       -- the first group's left border = 0
    local p2, _, _, x2 = slotOf("FlipA").seg:GetPoint(2)
    assertEquals("BOTTOMLEFT", p2)
    near3(x2, (W - 2 * S.Inset) - (TM.pos(60, W, H, Max, Loga) + H * 0.5))
    Settings:Reset("Cooldown", "Flip")
    Display:Update({}, now + 2)
end)

test("CD-35 Vertical + Flip: the axis runs top -> bottom with negated offsets", function()
    Display:Init()
    local W, H, Max, Loga = S.Width, S.Height, S.Max, S.Loga
    local now = 46000
    local feed = { { name = "VF", start = 0, duration = 999, endTime = now + 120 } }
    Settings:Set("Cooldown", "Vertical", true)
    Settings:Set("Cooldown", "Flip", true)
    Display:Update(feed, now)
    local point, _, relPoint, xoff, yoff = slotOf("VF").frame:GetPoint()
    -- The source's Vertical+Flip branch: icon CENTER -> bar TOP, (0, -t10)
    -- (:1427-1429).
    assertEquals("TOP", point)
    assertEquals("TOP", relPoint)
    near3(xoff, 0)
    near3(yoff, -TM.pos(120, W, H, Max, Loga))
    assertEquals(H, Display.anchor:GetWidth())
    assertEquals(W, Display.anchor:GetHeight())
    Settings:Reset("Cooldown", "Vertical")
    Settings:Reset("Cooldown", "Flip")
    Display:Update(feed, now + 1)
    local p3, _, _, x3, y3 = slotOf("VF").frame:GetPoint()
    assertEquals("LEFT", p3)
    -- The pass ran at now + 1, so this row has 119 s left on the axis.
    near3(x3, TM.pos(119, W, H, Max, Loga))
    near3(y3, 0)
end)

-- CD-35's third mode: `Hide` -- "Auto-hide when no cooldowns"
-- (Localization.lua :110-111; the Draw test at Forte_Cooldown.lua :1348,
-- `s.Hide and not cd:find(0,17)`, hides the whole scale while the cooldown
-- table is empty). The gate rides the Module's normal 10 Hz feed: the bar
-- shows again on the pass its first entry lands on, driven by nothing but
-- that feed.
test("CD-35 HideZero: no entries hides the bar, the first entry in the feed shows it", function()
    Display:Init()
    local now = 47000
    local feed = { { name = "ZeroA", start = 0, duration = 999, endTime = now + 90 } }
    Display:Update({}, now)
    assertTrue(Display.anchor:IsShown(), "the flag is OFF by default (:1813)")
    Settings:Set("Cooldown", "HideZero", true)
    Display:Update({}, now + 0.1)
    assertFalse(Display.anchor:IsShown(), "an empty bar is no bar at all")
    -- The Module's normal feed: the first entry arriving is what shows it.
    Display:Update(feed, now + 0.2)
    assertTrue(Display.anchor:IsShown())
    assertTrue(slotOf("ZeroA").frame:IsShown())
    -- The entry leaves -> the bar goes away again.
    Display:Update({}, now + 0.3)
    assertFalse(Display.anchor:IsShown())
    -- A SetEnabled/SetHideZero-style refresh between passes keeps the empty
    -- bar hidden (it reads the last feed size, not a stale "shown").
    Display:SetHideZero(true)
    assertFalse(Display.anchor:IsShown())
    Settings:Reset("Cooldown", "HideZero")
    Display:Update({}, now + 0.4)
    assertTrue(Display.anchor:IsShown())
end)

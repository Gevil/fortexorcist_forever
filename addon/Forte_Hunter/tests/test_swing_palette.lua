-- addon/Forte_Hunter/tests/test_swing_palette.lua
-- K4B (PLAN §11.4 row K4, `docs/reviews/code-review-8.md` Part B): the swing
-- bar's COLOUR PALETTE. `FX.Hunter.SwingPalettes = { default, colourblind }`
-- is an OVERLAY over `SwingSkin` -- a key a palette does not name keeps the
-- shipped (and hand-picked) value, which is what makes `default`
-- byte-identical to the art the bar has always drawn -- and
-- `UI/Swing.lua`'s `SetSwingPalette` paints every live signal texture from
-- it: the fill, the aim slice, the standing aim region, the clip mark (the
-- `safe` band included), the interlock's cast slice and its tint, the retry
-- slice, the weave line, the flight state -- plus the melee rail's fill,
-- which rides the palette's bar colour (UI/Melee.lua's one-truth law).
--
-- The legs:
--   1. `default` leaves EVERY texture colour exactly as today -- the shipped
--      triples and alphas, read off the textures themselves -- and its table
--      names NOTHING (the byte-identity law);
--   2. the shipped art's own family law survives the three new skin keys
--      (the region / the clip mark ride the aim hue, the interlock the clip
--      alpha -- derived, never typed twice);
--   3. the palette names every signal the bar draws;
--   4. `colourblind` recolours every live signal texture AND the rail, each
--      to the palette's own value, read off the textures' vertex colours;
--   5. the real settings round trip: `FX.Settings:Set` -> the OnChange fan ->
--      `SetSwingPalette` -> the store reads the word back AND the live frame
--      carries the pixels; the login seam (`ApplyStoredSettings`) too;
--   6. switching back restores the default pixels on every texture;
--   7. a hand-picked `BarColor` survives a trip through both palettes (the
--      BASE ∨ palette law -- a palette must never eat a player's colour);
--   8. the interlock tint carries its OWN alpha (and on the shipped skin the
--      two alphas are one number, so today's pixels do not move);
--   9. the flight state rides the palette's `FlyingColor` through the render
--      pass (the fill's two-value tint law is the render pass' to own);
--  10. the options page: the "Colour palette" row, its two items, its tip,
--      the section's recycle keys, the one registered default;
--  11. the live-client widget contract (found on uiforever 2026-11-04: the
--      Errors tab showed `attempt to call method 'SetFrameStrata' (a nil
--      value)` twice, with the DEFAULT settings): every method the render
--      passes call on a bar TEXTURE must be a Texture method --
--      `SetFrameStrata` is a FRAME method. The wow-ui-sim answers Frame
--      methods on Textures, which is why the whole suite was green while the
--      client threw. This leg poisons the Frame-only methods on every marker
--      texture, the way the real client ships them, and drives park/show
--      passes in all three modes with the weave line on and off, through
--      both palettes.
--
-- Every tracker is INJECTED (the test_swing2.lua / test_swing_modes.lua
-- clock + gate-reader shape); the colours are read off the REAL frame
-- textures through `GetVertexColor`, never off the skin table alone. Every
-- leg restores the shipped state (the palette, the store key, the bar colour,
-- the markers, the tracker, the rail off), so the files that run after this
-- one see the bar exactly as they always did.

local FX = ForteXorcist
local Tools = FX.Hunter.Tools
local Swing = FX.Hunter.Swing
local Melee = FX.Hunter.Melee
local S = FX.Hunter.SwingSkin
local P = FX.Hunter.SwingPalettes
local ST = FX.Settings

local function near3(actual, expected)
    return assertTrue(math.abs(actual - expected) < 1e-3)
end

--- The shipped bar colour as this file found it (the shared Spell tint):
--- restoreAll hands it back, so the pick test leaves nothing behind.
local SHIPPED_BAR = { S.BarColor[1], S.BarColor[2], S.BarColor[3],
    S.BarColor[4] or 1 }

-- The shipped art, transcribed from `UI/Swing.lua`'s `SwingSkin` (NOT read
-- off it: leg 1's whole point is that the palette feature moved today's
-- pixels not at all).
local SHIPPED = {
    AimColor = { 1, 0, 0, 1 },
    FlyingColor = { 1, 1, 1, 1 },
    RetryColor = { 1, 1, 0, 1 },
    AimRegionAlpha = 0.45,
    AimRegionRetryAlpha = 0.25,
    ClipRegionAlpha = 0.22,
    ClipInterlockColor = { 1, 1, 1, 1 },
    WeaveColor = { 0, 0.75, 1, 0.95 },
}

-- ------------------------------------------------------------- the seams --
local function fmt(c)
    return string.format("%.3f,%.3f,%.3f a%.3f", c[1], c[2], c[3], c[4])
end
local function colorOf(tex, name)
    if tex == nil then
        error("no texture named: " .. tostring(name or "?"), 2)
    end
    if type(tex.GetVertexColor) ~= "function" then
        -- A marker the render pass rebuilt as a pure mask widget answers no
        -- colour read in this build; the leg that DRAWS that marker pins its
        -- colour. The snapshot legs skip it (and count the reads, so the
        -- snapshot can not vacuate).
        return nil
    end
    local r, g, b, a = tex:GetVertexColor()
    return { r, g, b, a }
end
--- The texture's live vertex colour IS the palette's value.
--- (The runner prints only `expected X, got Y`, so the tuples and the label
--- ride INSIDE the compared strings -- that is the only channel the red
--- list has.)
local function nearColor(got, want)
    local wa = want[4] or 1
    return math.abs(got[1] - want[1]) < 1e-3
        and math.abs(got[2] - want[2]) < 1e-3
        and math.abs(got[3] - want[3]) < 1e-3
        and math.abs(got[4] - wa) < 1e-3
end
local function assertColor(tex, want, why)
    local got = colorOf(tex, why)
    if got == nil then return true end
    local wa = want[4] or 1
    if nearColor(got, want) then return true end
    return assertEquals(
        (why or "the texture") .. " wants ["
            .. string.format("%.3f,%.3f,%.3f a%.3f", want[1], want[2],
                want[3], wa) .. "]",
        (why or "the texture") .. " draws [" .. fmt(got) .. "]")
end
--- The texture MOVED its colour (the leg that proves a live repaint, not a
--- cache that never painted).
local function assertColorChanged(before, tex, why)
    local got = colorOf(tex, why)
    if got == nil or before == nil then return true end
    local moved = math.abs(got[1] - before[1]) + math.abs(got[2] - before[2])
        + math.abs(got[3] - before[3]) + math.abs(got[4] - before[4])
    return assertTrue(moved > 1e-3, (why or "the texture")
        .. " kept its colour: [" .. fmt(got) .. "] was [" .. fmt(before)
        .. "]")
end

--- Names WHICH texture is missing in the red list (the runner prints the
--- compared strings and drops the message).
local function assertPresent(obj, name)
    return assertEquals(name, name .. (obj and "" or " IS NIL"))
end
--- The bar's signal textures by the module's own name. The fill rides the
--- render pass's two-value law (the bar colour, the flight white), so the
--- leg that reads it puts the bar in a known phase first.
local function signalTextures()
    return {
        Swing.aim, Swing.cast, Swing.retry, Swing.aimRegion, Swing.clip,
        Swing.clipBand, Swing.weave,
    }
end
local SIGNAL_NAMES = { "aim", "cast", "retry", "aimRegion", "clip",
    "clipBand", "weave" }
local function snapshotAll()
    local out = { fill = colorOf(Swing.fill, "the fill") }
    local tex = signalTextures()
    for i = 1, #SIGNAL_NAMES do
        -- A nil here is loud and NAMED (the runner drops assert messages).
        assertPresent(tex[i], SIGNAL_NAMES[i])
        out[SIGNAL_NAMES[i]] = colorOf(tex[i])
    end
    return out
end
local function assertAllUnchanged(before, why)
    local now = snapshotAll()
    local read = 0
    for i = 1, #SIGNAL_NAMES do
        local name = SIGNAL_NAMES[i]
        if now[name] ~= nil and before[name] ~= nil then
            read = read + 1
            near3(now[name][1], before[name][1])
            near3(now[name][2], before[name][2])
            near3(now[name][3], before[name][3])
            near3(now[name][4], before[name][4])
        end
    end
    if now.fill ~= nil and before.fill ~= nil then
        read = read + 1
        near3(now.fill[1], before.fill[1]); near3(now.fill[2], before.fill[2])
        near3(now.fill[3], before.fill[3]); near3(now.fill[4], before.fill[4])
    end
    -- The snapshot can not vacuate: the fill plus five of the seven markers
    -- must have been readable for this leg to mean anything.
    return assertTrue(read >= 6,
        "readable textures in " .. (why or "the leg") .. ": " .. read)
end

Swing:Init()                       -- idempotent: the frame + the marker art
assertNotNil(Swing.anchor)
assertNotNil(Swing.aimRegion, "the standing aim region exists")
assertNotNil(P, "FX.Hunter.SwingPalettes exists")
assertNotNil(P.default, "the default palette is registered")
assertNotNil(P.colourblind, "the colour-blind palette is registered")

local function restoreAll()
    -- A leg that drove the login seam (which re-reads the fill-engine key)
    -- can leave the bar with NO fill texture: UI/Swing.lua:826-837 nils
    -- `fill` and rebuilds it, and a rebuild against a hidden bar yields nil.
    -- Drop the memo so the next `SetFillEngineMode` really rebuilds.
    if not Swing.fill then Swing._fillMode = nil end
    Swing:SetFillEngineMode("lua")
    assertPresent(Swing.fill, "the fill after the rebuild")
    Swing:Init()
    Swing:SetSwingPalette("default")
    ST:Reset("Hunter", "SwingPalette")
    Swing:SetBarColor(SHIPPED_BAR)
    Swing:SetBarMode("safe")
    Swing:SetShowAimWindow(true)
    Swing:SetShowClipRegion(true)
    Swing:SetShowWeaveLine(false)
    Swing:SetShowAimSlice(true)
    Swing:SetShowFlying(true)
    Swing:SetShowRetry(true)
    Swing:SetTracker(Tools.Swing)
    Swing:RenderIdle()
    if Melee and Melee.SetEnabled then Melee:SetEnabled(false) end
end

-- The geometry-law suite law (test_swing_modes.lua): the fill path is pinned
-- to the v2 lua path, so the fill's colour is the texture's vertex colour.
Swing:SetFillEngineMode("lua")
assertFalse(Swing:UsesEngineFill())

-- ==================================================== 1. default = today ==

test("palette default: every signal texture is today's colour, exactly",
function()
    Swing:RenderIdle()
    local now = snapshotAll()
    -- The two reds + the clip mark + the interlock slice are the SAME shipped
    -- red, at the shipped stepped alphas; the weave line is the shipped
    -- off-family cyan; the retry is the shipped Item yellow.
    for _, name in ipairs({ "aim", "cast", "aimRegion", "clip", "clipBand" }) do
        local c = now[name]
        near3(c[1], SHIPPED.AimColor[1])
        near3(c[2], SHIPPED.AimColor[2])
        near3(c[3], SHIPPED.AimColor[3])
    end
    near3(now.aim[4], SHIPPED.AimColor[4])            -- the live slice: full
    near3(now.cast[4], SHIPPED.AimColor[4])           -- the interlock slice
    near3(now.aimRegion[4], SHIPPED.AimRegionAlpha)   -- the region: stepped
    near3(now.clip[4], SHIPPED.ClipRegionAlpha)       -- the stripe: stepped
    near3(now.clipBand[4], SHIPPED.ClipRegionAlpha)   -- the band: stepped
    local w = now.weave
    near3(w[1], SHIPPED.WeaveColor[1]); near3(w[2], SHIPPED.WeaveColor[2])
    near3(w[3], SHIPPED.WeaveColor[3]); near3(w[4], SHIPPED.WeaveColor[4])
    local r = now.retry
    near3(r[1], SHIPPED.RetryColor[1]); near3(r[2], SHIPPED.RetryColor[2])
    near3(r[3], SHIPPED.RetryColor[3])
    -- The fill is the shipped bar colour (the shared Spell tint), full alpha.
    near3(now.fill[1], SHIPPED_BAR[1]); near3(now.fill[2], SHIPPED_BAR[2])
    near3(now.fill[3], SHIPPED_BAR[3]); near3(now.fill[4], SHIPPED_BAR[4])
    restoreAll()
end)

test("palette default: its table names NOTHING (the byte-identity law)",
function()
    -- `default` is empty BY DESIGN: every key falls through to the shipped
    -- skin, so the palette feature can not move today's pixels by existing.
    local named
    for key in pairs(P.default) do named = tostring(key) end
    assertNil(named, "the default palette names a key: " .. tostring(named))
    restoreAll()
end)

test("palette default: the three per-signal keys are DERIVED, not retyped",
function()
    -- The shipped family is ONE red at a stepped alpha, and the three keys
    -- the palette needs are DERIVED from it (the one-truth law of the
    -- `SwingSkin` block), so the shipped art can not drift from the hue it
    -- has always ridden.
    for i = 1, 3 do
        near3(S.AimRegionColor[i], S.AimColor[i])
        near3(S.ClipColor[i], S.AimColor[i])
    end
    near3(S.ClipInterlockAlpha, S.ClipRegionAlpha)
    near3(S.AimRegionAlpha, SHIPPED.AimRegionAlpha)
    near3(S.AimRegionRetryAlpha, SHIPPED.AimRegionRetryAlpha)
    near3(S.ClipRegionAlpha, SHIPPED.ClipRegionAlpha)
    restoreAll()
end)

-- ==================================================== 2. the palette keys ==

test("the colourblind palette names every signal the bar draws", function()
    -- A signal the palette forgets silently keeps the shipped red, which is
    -- the exact defect this palette exists to remove.
    for _, key in ipairs({ "BarColor", "AimColor", "AimRegionColor",
        "AimRegionAlpha", "AimRegionRetryAlpha", "ClipColor",
        "ClipRegionAlpha", "ClipInterlockColor", "ClipInterlockAlpha",
        "WeaveColor", "RetryColor", "FlyingColor" }) do
        assertNotNil(P.colourblind[key], "the palette names " .. key)
    end
    -- The ladder is BRIGHTNESS, not hue: the aim region is the heavier wash
    -- of its own hue family, and the interlock tint is the LIGHTER band
    -- inside the frozen bar (the ticket's law).
    local cb = P.colourblind
    assertTrue(cb.AimRegionAlpha > cb.ClipRegionAlpha,
        "the aim region is the stronger wash of the pair")
    assertTrue(cb.ClipInterlockAlpha > cb.ClipRegionAlpha,
        "the interlock tint is the lighter band inside the frozen bar")
    restoreAll()
end)

-- ========================================== 3. colourblind = a live repaint ==

test("palette colourblind: every live signal texture is recoloured, and the rail",
function()
    Melee:SetEnabled(true)              -- the rail's frame (off by default)
    assertNotNil(Melee.fill, "the rail built its fill")
    Swing:RenderIdle()
    local before = snapshotAll()
    local railBefore = colorOf(Melee.fill)
    Swing:SetSwingPalette("colourblind")
    local cb = P.colourblind
    local now = snapshotAll()

    -- Every signal MOVED, and each to the palette's own value.
    assertColorChanged(before.aim, Swing.aim, "the aim slice")
    assertColorChanged(before.cast, Swing.cast, "the interlock's slice")
    assertColorChanged(before.retry, Swing.retry, "the retry slice")
    assertColorChanged(before.aimRegion, Swing.aimRegion, "the aim region")
    assertColorChanged(before.clip, Swing.clip, "the clip stripe")
    assertColorChanged(before.clipBand, Swing.clipBand, "the clip band")
    assertColorChanged(before.weave, Swing.weave, "the weave line")
    assertColorChanged(before.fill, Swing.fill, "the fill")

    assertColor(Swing.aim, cb.AimColor, "the aim slice")
    assertColor(Swing.cast, cb.AimColor, "the interlock's cast slice")
    assertColor(Swing.retry, cb.RetryColor, "the retry slice")
    assertColor(Swing.weave, cb.WeaveColor, "the weave line")
    assertColor(Swing.fill, cb.BarColor, "the fill")
    -- The two markers the render pass tints, in their standing state (leg 8
    -- drives the interlock state).
    local reg = colorOf(Swing.aimRegion)
    near3(reg[1], cb.AimRegionColor[1]); near3(reg[2], cb.AimRegionColor[2])
    near3(reg[3], cb.AimRegionColor[3]); near3(reg[4], cb.AimRegionAlpha)
    for _, tex in ipairs({ Swing.clip, Swing.clipBand }) do
        local c = colorOf(tex)
        near3(c[1], cb.ClipColor[1]); near3(c[2], cb.ClipColor[2])
        near3(c[3], cb.ClipColor[3]); near3(c[4], cb.ClipRegionAlpha)
    end
    -- The rail rides the palette's BAR colour -- it never owns one.
    assertColorChanged(railBefore, Melee.fill, "the melee rail's fill")
    assertColor(Melee.fill, cb.BarColor, "the melee rail's fill")
    restoreAll()
end)

test("palette colourblind: a rail built AFTER the switch arrives in the palette",
function()
    -- The login order between the bar and the rail is not fixed: the rail
    -- may Init after the palette was chosen. It reads the live skin, so it
    -- must not arrive in the shipped orange.
    Melee:SetEnabled(false)
    Swing:SetSwingPalette("colourblind")
    Melee:SetEnabled(true)
    assertNotNil(Melee.fill)
    assertColor(Melee.fill, P.colourblind.BarColor, "the rail built late")
    restoreAll()
end)

-- ================================================ 4. the real settings path ==

test("the palette round trips Set -> Get -> the live pixels", function()
    assertEquals("default", Swing:GetSwingPalette())
    ST:Set("Hunter", "SwingPalette", "colourblind")
    assertEquals("colourblind", ST:Get("Hunter", "SwingPalette"))
    assertEquals("colourblind", Swing:GetSwingPalette())
    assertColor(Swing.aim, P.colourblind.AimColor,
        "the store write reached the live aim slice")
    assertColor(Swing.fill, P.colourblind.BarColor,
        "the store write reached the live fill")
    assertColor(Swing.weave, P.colourblind.WeaveColor,
        "the store write reached the live weave line")
    ST:Set("Hunter", "SwingPalette", "default")
    assertEquals("default", ST:Get("Hunter", "SwingPalette"))
    assertEquals("default", Swing:GetSwingPalette())
    assertColor(Swing.aim, SHIPPED.AimColor,
        "the second write reached the live aim slice")
    restoreAll()
end)

test("the palette applies from the store through the login seam", function()
    -- The seam applies `Enable` too, and with the store's Enable off it
    -- takes the frame DOWN (the fill texture with it) -- a different leg's
    -- subject. Pin it on for the duration of this one.
    ST:Set("Hunter", "Enable", true)
    Swing:Init()
    assertNotNil(Swing.fill, "the seam found the bar standing")
    ST:Set("Hunter", "SwingPalette", "colourblind")
    Swing:ApplyStoredSettings()          -- the login seam, verbatim
    assertEquals("colourblind", Swing:GetSwingPalette())
    assertColor(Swing.retry, P.colourblind.RetryColor,
        "the login pass painted the retry slice")
    assertColor(Swing.weave, P.colourblind.WeaveColor,
        "the login pass painted the weave line")
    assertColor(Swing.aimRegion, {
        P.colourblind.AimRegionColor[1], P.colourblind.AimRegionColor[2],
        P.colourblind.AimRegionColor[3], P.colourblind.AimRegionAlpha },
        "the login pass painted the aim region")
    restoreAll()
end)

test("switching back restores the default pixels on every texture",
function()
    Swing:RenderIdle()
    local before = snapshotAll()
    Swing:SetSwingPalette("colourblind")
    -- The palette really did move the pixels in between (the round trip is
    -- not an artefact of a cache that never painted).
    for i = 1, #SIGNAL_NAMES do
        local tex = signalTextures()[i]
        assertNotNil(tex, "the " .. SIGNAL_NAMES[i] .. " texture exists")
        assertColorChanged(before[SIGNAL_NAMES[i]], tex,
            SIGNAL_NAMES[i] .. " out leg")
    end
    assertColorChanged(before.fill, Swing.fill, "the fill out leg")
    Swing:SetSwingPalette("default")
    assertAllUnchanged(before, "the round trip")
    restoreAll()
end)

test("a hand-picked BarColor survives both palettes (the BASE ∨ palette law)",
function()
    -- The palette is an OVERLAY over the base skin: choosing the colour-blind
    -- set and giving it up must hand the player their own colour back, not
    -- the shipped default.
    local pick = { 0.2, 0.9, 0.4, 1 }
    Swing:SetBarColor(pick)
    assertColor(Swing.fill, pick, "the pick lands")
    Swing:SetSwingPalette("colourblind")
    assertColor(Swing.fill, P.colourblind.BarColor,
        "the palette's bar colour paints over the pick")
    Swing:SetSwingPalette("default")
    assertColor(Swing.fill, pick, "giving the palette back restores the pick")
    -- The SKIN carries it too: that is the read the melee rail's one-truth
    -- law (`barFillColor`) lives on.
    near3(S.BarColor[1], pick[1]); near3(S.BarColor[2], pick[2])
    near3(S.BarColor[3], pick[3])
    restoreAll()
end)

-- ==================================================== 5. the interlock tint ==

local function v2Tracker(clock, extra)
    local opts = {
        now = function() return clock[1] end,
        speedReader = function() return nil end,
        rangedType = 2,
        baseSpeed = 1.0,
        targetReader = function() return true end,
        deadReader = function() return false end,
        attackReader = function() return true end,
        speedSampler = function() return nil end,
        rangeReader = function() return nil end,
        castLenReader = function() return 2.0 end,
    }
    for k, v in pairs(extra or {}) do opts[k] = v end
    local t = FX.Hunter.NewSwingTracker(opts)
    t.shooting = true
    return t
end

--- Put the bar in the cast interlock (the frozen bar + the tinted clip
--- marker) in one mode, with the marker DRAWN. Returns {clock, tracker}.
local function driveInterlock(mode)
    local clock = { 9000 }
    local t = v2Tracker(clock)
    Swing:SetTracker(t)
    Swing:SetBarMode(mode)
    Swing:SetShowAimWindow(true)
    Swing:SetShowClipRegion(true)
    Swing:SetShowWeaveLine(false)
    Swing:RenderIdle()
    t:OnSwingStart(4.0, 2)                 -- a 4 s cycle; the 2.0 s cast fits
    Swing:Update(clock[1])
    clock[1] = 9001.0                      -- 3 s left: the press
    t:OnShotCast("SENT", "Aimed Shot", 20904, "GA")
    Swing:Update(9001.0)
    return { clock = clock, tracker = t }
end

test("the interlock tint carries its OWN alpha (colourblind)", function()
    Swing:SetSwingPalette("colourblind")
    local cb = P.colourblind
    for _, mode in ipairs({ "safe", "one", "elapsed" }) do
        driveInterlock(mode)
        -- The marker the mode DRAWS: the safe mode's band, the growing
        -- modes' stripe (J4).
        local tex = (mode == "safe") and Swing.clipBand or Swing.clip
        assertTrue(tex:IsShown(), mode .. ": the clip marker is drawn")
        local c = colorOf(tex)
        near3(c[1], cb.ClipInterlockColor[1])
        near3(c[2], cb.ClipInterlockColor[2])
        near3(c[3], cb.ClipInterlockColor[3])
        near3(c[4], cb.ClipInterlockAlpha)
        assertTrue(cb.ClipInterlockAlpha > cb.ClipRegionAlpha,
            "the tint is the lighter band inside the frozen bar")
        Swing:RenderIdle()
    end
    restoreAll()
end)

test("the interlock tint rides the shipped alpha on the default palette",
function()
    -- The new key must not move today's pixels: the shipped skin's two
    -- alphas are ONE number, so the tint is drawn the way it always was.
    near3(S.ClipInterlockAlpha, S.ClipRegionAlpha)
    driveInterlock("safe")
    assertColor(Swing.clipBand, {
        S.ClipInterlockColor[1], S.ClipInterlockColor[2],
        S.ClipInterlockColor[3], S.ClipInterlockAlpha },
        "the shipped interlock tint")
    local c = colorOf(Swing.clipBand)
    near3(c[4], S.ClipInterlockAlpha)
    -- And the cast slice is the shipped red: the frozen bar is the aim hue.
    assertColor(Swing.cast, SHIPPED.AimColor, "the shipped cast slice")
    Swing:RenderIdle()
    restoreAll()
end)

-- ======================================================= 6. the flight ====

test("the flight state rides the palette's FlyingColor through the render pass",
function()
    -- The fill's white is the render pass' to own (the two-value tint law:
    -- the bar colour, the flight colour), so it is proven in a cycle, not by
    -- the repaint.
    local clock = { 11000 }
    local t = v2Tracker(clock)
    Swing:SetTracker(t)
    Swing:SetShowFlying(true)
    Swing:RenderIdle()
    t:OnSwingStart(2.0, 2)                 -- aimLen 0.5 (base 1.0, ratio law)
    t:OnShotCast("START", "Auto Shot", 75, "G1")
    t:OnShotCast("SUCCEEDED", "Auto Shot", 75, "G1")   -- the shot left
    Swing:Update(clock[1])
    Swing:SetSwingPalette("colourblind")
    Swing:Update(clock[1])
    assertEquals("flying", Swing._phase, "the drive reached the flight phase")
    assertColor(Swing.fill, P.colourblind.FlyingColor,
        "the flight state is white in this palette too")
    clock[1] = 11001.0                     -- the next cycle: the bar colour
    t:OnSwingStart(2.0, 2)
    Swing:Update(clock[1])
    assertEquals("reload", Swing._phase)
    assertColor(Swing.fill, P.colourblind.BarColor, "the bar colour mid-cycle")
    -- The palette that does not name FlyingColor (neither) leaves the
    -- shipped white standing: the default's flight is white as it always was.
    Swing:SetSwingPalette("default")
    Swing:Update(clock[1])
    Swing:RenderIdle()
    t:OnShotCast("START", "Auto Shot", 75, "G1")
    t:OnShotCast("SUCCEEDED", "Auto Shot", 75, "G1")
    Swing:Update(11001.0)
    assertColor(Swing.fill, { 1, 1, 1, 1 }, "the shipped flight white")
    Swing:RenderIdle()
    restoreAll()
end)

-- ==================================================== 7. the page + default ==

test("the Hunter page carries the Colour palette row and one default",
function()
    if not (FX.Options and FX.Options.pages
        and FX.Options.pages["Hunter"]) then
        print("[palette] Forte_Options has no Hunter page -- skipped")
        return
    end
    local O = FX.Options
    O:Open("Hunter")
    local page = O.pagesBuilt["Hunter"]
    assertNotNil(page, "the page builds")
    local colour, row
    for _, sec in ipairs(page.sections) do
        if sec.title == "Coloring" then colour = sec end
        for _, w in ipairs(sec.widgets) do
            if w.spec and w.spec.key == "SwingPalette" then row = w.spec end
        end
    end
    O:Close()
    assertNotNil(colour, "the Coloring section exists")
    assertNotNil(row, "the SwingPalette row is on the page")
    assertEquals("Colour palette", row.label)
    local items = row.items or {}
    assertEquals(2, #items)
    assertEquals("default", items[1].value)
    assertEquals("Default", items[1].label)
    assertEquals("colourblind", items[2].value)
    assertEquals("Colour-blind friendly (brightness steps)", items[2].label)
    assertTrue(string.find(row.tip or "", "brightness", 1, true) ~= nil,
        "the tip says the ladder: " .. tostring(row.tip))
    -- Registered ONCE, with the shipped word as its default, and carried by
    -- the section's recycle list so the section's restore icon restores it
    -- with the colours.
    assertEquals("default", FX.Settings:GetDefault("Hunter", "SwingPalette"))
    -- The row is in the Coloring section's recycle `keys` list
    -- (Pages/Hunter.lua:245), which the builder folds into the section's
    -- restore icon; test_swing.lua's page-shape leg pins the section's row
    -- count, and the round-trip leg above pins the store -> pixels law the
    -- recycle rides. Here the row's own contract: it writes the store.
    ST:Set("Hunter", "SwingPalette", "colourblind")
    assertEquals("colourblind", Swing:GetSwingPalette())
    assertColor(Swing.aim, P.colourblind.AimColor, "the row wrote the bar")
    ST:Reset("Hunter", "SwingPalette")
    assertEquals("default", Swing:GetSwingPalette())
    restoreAll()
end)

test("the store's shipped word is the default palette (a new profile is today)",
function()
    assertEquals("default", ST:GetDefault("Hunter", "SwingPalette"))
    assertEquals("default", ST:Get("Hunter", "SwingPalette"))
    assertEquals("default", Swing:GetSwingPalette())
    restoreAll()
end)

-- ============================================== 8. the live-client contract ==

-- The FRAME-only methods a Texture does not have: the client throws on every
-- one of them (`attempt to call method 'SetFrameStrata' (a nil value)`). The
-- wow-ui-sim answers them on a Texture, which is why the whole suite was
-- green while uiforever and the real client threw -- so this leg poisons them
-- on every marker texture and drives the passes.
local FRAME_ONLY = {
    "SetFrameStrata", "SetFrameLevel", "EnableMouse", "SetMovable",
    "SetScript", "RegisterEvent", "SetBackdrop", "SetBackdropColor",
    "SetBackdropBorderColor", "SetClampedToScreen", "RegisterForDrag",
    "StartMoving", "StopMovingOrSizing", "SetUserForeground",
    "SetTiedToUpdateRect",
}
local function markerTextures()
    local out = { Swing.fill, Swing.aim, Swing.retry, Swing.cast,
        Swing.aimRegion, Swing.clip, Swing.clipBand, Swing.weave,
        Swing.spark }
    if Melee and Melee.fill then out[#out + 1] = Melee.fill end
    return out
end

test("no render pass speaks a Frame-only method to a Texture (the client law)",
function()
    local textures = markerTextures()
    local poisoned = 0
    local function poison()
        for i = 1, #textures do
            local tex = textures[i]
            for _, m in ipairs(FRAME_ONLY) do
                tex[m] = function()
                    error("a Texture has no " .. m .. " (the live client)", 2)
                end
                poisoned = poisoned + 1
            end
        end
    end
    local function heal()
        for i = 1, #textures do
            local tex = textures[i]
            for _, m in ipairs(FRAME_ONLY) do tex[m] = nil end
        end
    end
    local meleeWasOn = (Melee and Melee.state and Melee.state.enabled)
        and true or false
    poison()
    Melee:SetEnabled(true)
    local ok, why = true, nil
    local function run(label, fn, a)
        local passed, err = pcall(fn, Swing, a)
        if not passed then
            ok, why = false, label .. ": " .. tostring(err)
        end
    end
    for _, mode in ipairs({ "safe", "one", "elapsed" }) do
        for _, weave in ipairs({ true, false }) do
            for _, palette in ipairs({ "default", "colourblind" }) do
                if ok then
                    local label = mode .. "/weave=" .. tostring(weave)
                        .. "/" .. palette
                    Swing:SetBarMode(mode)
                    Swing:SetShowWeaveLine(weave)
                    Swing:SetSwingPalette(palette)
                    local clock = { 21000 }
                    local t = v2Tracker(clock, {
                        castLenReader = function() return 2.0 end })
                    Swing:SetTracker(t)
                    t:OnSwingStart(2.0, 2)
                    for _, t0 in ipairs({ 21000, 21000.5, 21001.0, 21001.8,
                        21002.4 }) do
                        run(label .. " Update " .. t0, Swing.Update, t0)
                    end
                    run(label .. " RenderIdle", Swing.RenderIdle)
                    -- The sentinel park: the setters force the next pass
                    -- with `false`, and the pass that follows is the one the
                    -- client crashed on with the shipped (weave OFF) settings.
                    Swing:SetShowWeaveLine(false)
                    run(label .. " the sentinel park", Swing.Update, 21003.0)
                    run(label .. " RenderIdle again", Swing.RenderIdle)
                    -- The palette switch itself, with the textures poisoned:
                    -- the repaint leg of the seam.
                    run(label .. " the repaint", Swing._RepaintPalette,
                        Swing)
                end
            end
        end
    end
    local passed, err = pcall(Melee.Refresh, Melee)
    if not passed then ok, why = false, "the rail's render pass: "
        .. tostring(err) end
    heal()
    Melee:SetEnabled(meleeWasOn)
    restoreAll()
    assertTrue(poisoned >= #FRAME_ONLY * 9,
        "the seam poisoned every marker texture: " .. poisoned)
    assertTrue(ok, "a Texture was spoken to as a Frame -- " .. tostring(why))
end)

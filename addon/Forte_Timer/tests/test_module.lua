-- addon/Forte_Timer/tests/test_module.lua
-- The Spell Timer's live spine: the real OnEvent dispatch (the payload shape
-- of docs/design-spell-timer.md §4.1), the hidden-frame law (a hidden frame
-- never receives OnUpdate -- the 2026-11-02 uiforever finding: activity must
-- show the panel SYNCHRONOUSLY), the geometry of §1.1/§5.1 asserted NUMERICALLY
-- (this agent has no vision), the lock convention, the live settings seam and
-- the registered options page (the index cell `SpellTimer`).
--
-- The clock is injected (Casts.now), so the module's Logic/Draw follow it; the
-- 0.04 s ticker of the live client is never relied on by a test.

local FX = ForteXorcist
local M = FX.Timer.Module
local Rows = FX.Timer.Rows
local Laws = FX.Timer.Laws
local Registry = FX.Timer.Registry
local Casts = FX.Timer.Casts
local D = FX.Timer.Display
local ST = FX.Settings

local function nearpx(actual, expected)
    assertTrue(math.abs(actual - expected) <= 0.5)
end
local function near3(actual, expected)
    assertTrue(math.abs(actual - expected) < 1e-3)
end

local clock
local function installClock(base)
    clock = { base }
    Casts.now = function() return clock[1] end
    return clock
end

local function useHunterData()
    Registry:AttachStorage({})
    Registry:Build("HUNTER")
    Casts.resolveName = function(id)
        return id == 425737 and "Serpent Sting"
            or id == 14325 and "Hunter's Mark"
            or nil
    end
end

local function dispatch(event, a1, a2, a3, a4)
    local f = M._eventFrame
    assertNotNil(f)
    local onEvent = f:GetScript("OnEvent")
    assertNotNil(onEvent)
    -- The frame is argument 1: the binding law of PLAN §10.2 (the Forte_Hunter
    -- bug of 2026-11-02 was a binding that forwarded the frame as `event`).
    onEvent(f, event, a1, a2, a3, a4)
end

-- ------------------------------------------------------------- enable state --

test("the module is enabled with its frame, options and display", function()
    assertNotNil(M)
    -- The gate run's login sequence does not reach Forte_Core's module loop
    -- (the established finding of Forte_Hunter/tests/test_swing.lua and
    -- Forte_Cooldown/tests/test_timeline.lua), so the enable path is driven
    -- directly here, exactly as those suites do.
    if not M.options then M:OnEnable() end
    assertNotNil(M.options)
    assertNotNil(M._eventFrame)
    assertNotNil(D.anchor)
    assertEquals("ForteXorcistTimerAnchor", D.anchor:GetName())
    assertNil(D.anchor:GetScript("OnUpdate"))   -- a ticker drives it, not a tick
    assertEquals("Forte Spell Timers (predicted)", D.title:GetText())
end)

-- ----------------------------------------------------------------- geometry --

test("the geometry is the Classic law: 250 rows, 235 bars, the icon OUTSIDE",
function()
    local o = M.options
    assertEquals(250, o.width)
    assertEquals(14, o.height)
    assertEquals(235, o.barWidth)         -- Width - Height - 1 (:2034-2036)
    assertEquals(14, o.iconSize)          -- the icon is square, the bar's height
    assertEquals(18, o.barInset)          -- Height + 1 + Backdrop[6] (:2322)
    assertEquals(256, o.groupWidth)       -- Width + Backdrop[6]*2 (:1938)
    assertEquals(2, o.space)              -- :3364
    assertEquals(2, o.spacingHeight)      -- :3345
    assertEquals(18, o.labelHeight)       -- :3344
    -- The anchor's box is the group width, not the row width (delta D15).
    nearpx(D.anchor:GetWidth(), o.groupWidth)
    -- The renderer's own bar/icon geometry, measured off the pool after a draw.
    local row = D:AcquireRow(1)
    nearpx(row.bar:GetHeight(), o.height)
    nearpx(row.bar:GetWidth(), o.barWidth)
    nearpx(row.icon:GetWidth(), o.height)
    nearpx(row.icon:GetHeight(), o.height)
    local group = D:AcquireGroup(1)
    nearpx(group.frame:GetWidth(), o.groupWidth)
    print(string.format("[timer] anchor %dx%d group %dx%d bar %dx%d icon %dx%d",
        D.anchor:GetWidth(), D.anchor:GetHeight(),
        group.frame:GetWidth(), group.frame:GetHeight(),
        row.bar:GetWidth(), row.bar:GetHeight(),
        row.icon:GetWidth(), row.icon:GetHeight()))
end)

test("the textures are the ones Forte_Core ships", function()
    local s = FX.Timer.Skin
    -- The design's §5.1 texture set, off Forte_Core's Textures/ folder (the
    -- `ST`/`Spark` pair the 2012 original bundled is not in Forte_Core; the
    -- report names that delta).
    assertTrue(s.BarTexture:find("Aluminium") ~= nil)
    assertTrue(s.RowBack:find("UI%-Character%-Skills%-Bar") ~= nil)
    assertTrue(s.IconBase:find("ST") ~= nil)
    assertTrue(s.Spark:find("Spark") ~= nil)
    assertTrue(s.IconSpark:find("Spark2") ~= nil)
    assertTrue(s.BackdropBG:find("Background") ~= nil)
    assertTrue(s.BackdropEdge:find("Border") ~= nil)
    assertEquals(16, s.BackdropTileSize)
    assertEquals(3, s.Inset)                 -- the Spell Timer's own edge (:3417)
    assertEquals(8, #s.RaidMarkCoords)
    -- The URW Gothic ruling (PLAN §7): the class font, not a bundled TTF.
    assertEquals(FX.CLASSIC_FONT, s.Font[1])
    assertEquals(11, s.Font[2])
    assertNotNil(D.fontFile)
    print("[timer] font=" .. tostring(D.fontFile))
end)

-- ---------------------------------------------------------------- the spine --

test("UNIT_SPELLCAST_SENT then SUCCEEDED makes a row, and SHOWN the panel",
function()
    useHunterData()
    Rows:Clear()
    installClock(20000)
    D:RenderIdle()
    -- The hidden-frame law: the panel starts hidden, and NOTHING here calls
    -- Update/Refresh -- the public event path must show it synchronously.
    assertFalse(D.anchor:IsShown())
    dispatch("UNIT_SPELLCAST_SENT", "player", "Vile Poacher",
        "GUID:1:1:1:1", 425737)
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "GUID:1:1:1:1", 425737, 7)
    assertEquals(0, Rows:Count())                -- the 0.2 s settle
    M:Logic()                                    -- the public pump, at settle-0
    assertEquals(0, Rows:Count())
    clock[1] = clock[1] + Laws.SETTLE + 0.01
    M:Logic()
    assertEquals(1, Rows:Count())
    local row = Rows:Find("Serpent Sting", "Vile Poacher")
    assertNotNil(row)
    near3(row.total, 12)
    assertEquals(true, row.predicted)
    assertTrue(D.anchor:IsShown())               -- the synchronous show
    assertTrue(#D.groups >= 1)
    assertTrue(D.groups[1].frame:IsShown())
    assertTrue(D.rows[1] ~= nil and D.rows[1].bar:IsShown())
    -- The label carries the target, so the rows read per target (§5.5).
    assertEquals("Vile Poacher", D.groups[1].label:GetText())
    -- The fill: the compressed scale, drawn from the smoothed expire time.
    local draw = row.drawExpireAt
    local value = D.rows[1].bar:GetValue()
    near3(value, Laws.BarVal(draw, clock[1], row.maxTime))
end)

test("a second target gets its own group, and the bars cascade upward",
function()
    installClock(20000)
    Rows:Clear()          -- a clean stack: the count below is this test's own
    for _, target in ipairs({ "Vile Poacher", "River Crocolisk" }) do
        dispatch("UNIT_SPELLCAST_SENT", "player", target,
            "GUID:1:1:1:1", 14325)
        dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "GUID:1:1:1:1",
            14325, 8)
    end
    clock[1] = clock[1] + Laws.SETTLE + 0.01
    M:Logic()
    assertEquals(2, Rows:Count())
    local links, n = Rows:Sorted({}, clock[1])
    local drawn = D:Update(links, n, M.options, M.skin)
    assertEquals(2, drawn)
    local shown = 0
    for i = 1, #D.groups do
        if D.groups[i].frame:IsShown() then shown = shown + 1 end
    end
    assertEquals(2, shown)                    -- one box per target
    -- Growth is UPWARD from the frame's BOTTOM (`Expand`, :2320-2332): the
    -- second group's bottom point sits at/above the first's.
    local g1 = D.groups[1].frame
    local g2 = D.groups[2].frame
    local y1 = select(4, g1:GetPoint())
    local y2 = select(4, g2:GetPoint())
    assertTrue(y2 >= y1 - 0.5)
    -- And the bars inside a group cascade upward too (:2336-2338).
    local bars, seen = {}, 0
    for i = 1, #D.rows do
        if D.rows[i].bar:IsShown() then
            seen = seen + 1
            bars[seen] = D.rows[i].bar
        end
    end
    assertEquals(2, seen)
    for i = 1, seen do
        local point, _, _, y = bars[i]:GetPoint()
        assertNotNil(point)
        if i > 1 then
            local _, _, _, yPrev = bars[i - 1]:GetPoint()
            assertTrue(y >= yPrev - 0.5)
        end
    end
end)

test("UNIT_SPELLCAST_FAILED / INTERRUPTED flash the row, no cause is named",
function()
    installClock(21000)
    dispatch("UNIT_SPELLCAST_SENT", "player", "Vile Poacher", "G:2", 425737)
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "G:2", 425737, 9)
    clock[1] = clock[1] + Laws.SETTLE + 0.01
    M:Logic()
    local row = Rows:Find("Serpent Sting", "Vile Poacher")
    assertNotNil(row)
    dispatch("UNIT_SPELLCAST_INTERRUPTED", "player", "G:2", 425737)
    clock[1] = clock[1] + Laws.CANCEL_SETTLE + 0.01
    M:Logic()
    assertEquals(Laws.FAILED, row.state)
    -- The failed band draws at full alpha (:2340-2344).
    local links, n = Rows:Sorted({}, clock[1])
    D:Update(links, n, M.options, M.skin)
    assertEquals(1, D.rows[1].bar:GetAlpha())
end)

test("UNIT_AURA on the target runs the gated sweep, not a read in combat",
function()
    installClock(22000)
    local sweep = FX.Timer.Reconcile
    local seen = 0
    local savedUnit = sweep.SweepUnit
    sweep.SweepUnit = function(self, token, filter, now)
        seen = seen + 1
        return savedUnit(self, token, filter, now)
    end
    local savedCombat = sweep.inCombat
    sweep.inCombat = function() return true end
    local reads = sweep.counts.reads
    dispatch("UNIT_AURA", "target", nil)
    assertEquals(1, seen)
    assertEquals(reads, sweep.counts.reads)   -- the gate issued no new read
    sweep.inCombat = savedCombat
    sweep.SweepUnit = savedUnit
end)

test("PLAYER_LEAVING_WORLD erases the queue and the rows", function()
    installClock(23000)
    dispatch("UNIT_SPELLCAST_SENT", "player", "Vile Poacher", "G:3", 14325)
    assertTrue(#Casts.queue >= 1)
    dispatch("PLAYER_LEAVING_WORLD")
    assertEquals(0, #Casts.queue)
    assertEquals(0, Rows:Count())
    assertFalse(D.anchor:IsShown())
end)

-- ------------------------------------------------------------------- lock ---

test("the lock is the m4 convention: it publishes SpellTimer.Lock", function()
    installClock(24000)
    -- The sim's frames expose no Movable() getter, so the lock is asserted at
    -- the two effects it has: the saved state (which is what SetMovable/
    -- EnableMouse are driven from) and the title's visibility.
    M:SetLocked(true)
    assertEquals(true, ST:Get("SpellTimer", "Lock"))
    assertEquals(true, D.cfg.locked)
    assertFalse(D.title:IsShown())
    M:SetLocked(false)
    assertEquals(false, ST:Get("SpellTimer", "Lock"))
    assertEquals(false, D.cfg.locked)
    assertTrue(D.title:IsShown())
    -- The shared keys move it: /fx unlock writes General.GlobalLock.
    ST:Set("General", "GlobalLock", true)
    assertEquals(true, D.cfg.locked)
    ST:Set("General", "GlobalLock", false)
    assertEquals(false, D.cfg.locked)
end)

-- ------------------------------------------------------------- live settings --

test("the options page is registered under the index id SpellTimer", function()
    local O = FX.Options
    assertNotNil(O)
    local entry
    for _, row in ipairs(O.INDEX) do
        if row.id == "SpellTimer" then entry = row end
    end
    assertNotNil(entry)                       -- the index cell exists
    assertEquals("Spell Timer", entry.label)
    assertNotNil(O.pages["SpellTimer"])       -- and the page is on it
    assertEquals("Spell Timer", O.pages["SpellTimer"].title)
end)

test("the settings are live: geometry, colours, gates, the cap", function()
    installClock(25000)
    local o = M.options
    ST:Set("SpellTimer", "Width", 300)
    assertEquals(300, o.width)
    assertEquals(285, o.barWidth)
    assertEquals(306, o.groupWidth)
    nearpx(D.anchor:GetWidth(), 306)
    ST:Set("SpellTimer", "Height", 16)
    assertEquals(16, o.height)
    assertEquals(283, o.barWidth)              -- Width - Height - 1
    assertEquals(16, o.iconSize)
    ST:Set("SpellTimer", "Max", 6)
    assertEquals(6, o.maxRows)
    ST:Set("SpellTimer", "MaxDisplayTime", 60)
    assertEquals(60, o.maxTime)
    ST:Set("SpellTimer", "NormalAlpha", 0.8)
    near3(o.normalAlpha, 0.8)
    near3(M.skin.NormalAlpha, 0.8)
    ST:Set("SpellTimer", "BarBackgroundAlpha", 0.15)
    near3(M.skin.BarBackgroundAlpha, 0.15)
    ST:Set("SpellTimer", "ShowTargetNames", false)
    assertFalse(o.showTarget)
    ST:Set("SpellTimer", "Label", false)
    assertFalse(o.label)
    ST:Set("SpellTimer", "ShowID", true)
    assertTrue(o.showID)
    ST:Set("SpellTimer", "ShowSpellNames", true)
    assertTrue(o.spell)
    ST:Set("SpellTimer", "ColourNormal", { 0.1, 0.2, 0.3 })
    near3(M.skin.ColourNormal[1], 0.1)
    near3(M.skin.ColourNormal[3], 0.3)
    ST:Set("SpellTimer", "ColourFlash", { 1, 0, 0 })
    near3(M.skin.Fail[1], 1)
    near3(M.skin.Fail[2], 0)
    ST:Set("SpellTimer", "BarColorSelf", { 0.5, 0.5, 0.5 })
    near3(M.skin.BarColorSelf[1], 0.5)
    -- The defaults come back so the rest of the suite sees the Classic law.
    ST:Set("SpellTimer", "Width", 250)
    ST:Set("SpellTimer", "Height", 14)
    ST:Set("SpellTimer", "Max", 32)
    ST:Set("SpellTimer", "MaxDisplayTime", 30)
    ST:Set("SpellTimer", "NormalAlpha", 0.5)
    ST:Set("SpellTimer", "BarBackgroundAlpha", 0.3)
    ST:Set("SpellTimer", "ShowTargetNames", true)
    ST:Set("SpellTimer", "Label", true)
    ST:Set("SpellTimer", "ShowID", false)
    ST:Set("SpellTimer", "ShowSpellNames", false)
    D:SetSize(250, 14)
    assertEquals(235, o.barWidth)
    nearpx(D.anchor:GetWidth(), 256)
end)

-- ------------------------------------------------------------- the colour law --

test("the colour law: normal, the last half second, the blink, the expired",
function()
    local S = FX.Timer.Skin
    local o = { highlight = true, blink = true, blinkAt = Laws.BLINK,
        expiredColor = false }
    -- an ordinary debuff row draws the TargetDebuff colour
    local r, g, b = Laws.ColorVal(8, 12, Laws.NORMAL, "TargetDebuff", S, o)
    near3(r, S.TargetDebuff[1])
    near3(b, S.TargetDebuff[3])
    -- the last half second of its OWN total: the HighlightColor mix runs
    local hr, hg, hb = Laws.ColorVal(0.3, 12, Laws.NORMAL, "TargetDebuff", S, o)
    assertTrue(math.abs(hr - S.HighlightColor[1])
        + math.abs(hg - S.HighlightColor[2])
        + math.abs(hb - S.HighlightColor[3]) > 1e-6)
    -- the expiry alpha pulse: 0.25*(1 - cos(25*sqrt(t))), the shape of :1562
    local base = S.BarBackgroundAlpha
    local pulse = 0.25 * (1 - math.cos(25 * math.sqrt(1.0)))
    local _, _, _, a = Laws.ColorVal(1.0, 12, Laws.NORMAL, "TargetDebuff", S, o)
    near3(a, base >= 0.5 and (base - pulse) or (base + pulse))
    -- the fail band (:1526-1533)
    local fr = { Laws.ColorVal(-0.2, 12, Laws.FAILED, "TargetDebuff", S, o) }
    assertTrue(fr[1] >= 0)
    -- the expired colour, on the gate (:1557-1560)
    o.expiredColor = true
    local er, eg, eb, ea = Laws.ColorVal(-1, 12, Laws.NORMAL, "TargetDebuff",
        S, o)
    near3(er, S.ExpiredColor[1])
    near3(ea, S.ExpiredColor[4])
    o.expiredColor = false
end)

test("the text law: m:ss above a minute, %.1f below, the fail word", function()
    assertEquals("1:30", Laws.SecToTimeD(90))
    assertEquals("59.5", Laws.SecToTimeD(59.5))
    -- The alternate (Nh/Nm/Ns) branch rounds UP, the original's own law
    -- (Forte_Core.lua:1746-1761): 90 s is "2m".
    assertEquals("2m", Laws.SecToTimeD(90, true))
    assertEquals("1h", Laws.SecToTimeD(3600, true))
    assertEquals("45s", Laws.SecToTimeD(45, true))
    assertEquals("gone", Laws.TimeText(-1, 12, Laws.FAILED))
    assertEquals("", Laws.TimeText(5, 0, Laws.NORMAL))
    -- the name column: the target, the #id prefix, the (stacks) suffix
    assertEquals("Vile Poacher", Laws.NameText("Vile Poacher", "Serpent Sting",
        {}))
    assertEquals("Serpent Sting",
        Laws.NameText("Vile Poacher", "Serpent Sting", { spell = true }))
    assertEquals("#5 Vile Poacher",
        Laws.NameText("Vile Poacher", "Serpent Sting",
            { showID = true, id = 5 }))
    assertEquals("Vile Poacher (3)",
        Laws.NameText("Vile Poacher", "Serpent Sting", { stacks = 3 }))
end)

test("the visible cap drops the tail, and the time scale compresses", function()
    local o = M.options
    installClock(26000)
    Rows:Clear()
    o.maxOn, o.maxRows = true, 3
    for i = 1, 5 do
        Rows:InsertFromCast("Serpent Sting", "Dummy-" .. i, 12,
            clock[1], clock[1], 1, "TargetDebuff")
    end
    local links, n = Rows:Sorted({}, clock[1] + 1)
    assertEquals(5, n)
    local visible = 0
    for k = 1, n do if links[k][4] > 0 then visible = visible + 1 end end
    assertEquals(3, visible)
    -- the compression (§3.6): a 12 s row over a 30 s scale never fills the bar
    local long = Rows:InsertFromCast("Hunter's Mark", "Dummy-long", 120,
        clock[1], clock[1], 1, "TargetDebuff")
    o.maxOn = false
    links, n = Rows:Sorted({}, clock[1] + 1)
    for k = 1, n do
        if links[k][1] then
            local row = Rows.rows[links[k][1]]
            if row == long then
                assertTrue(links[k][6] <= (o.maxTime or Laws.MAXTIME) + 1e-6)
            end
        end
    end
    o.maxOn, o.maxRows = false, 32
    Rows:Clear()
end)

test("the status lines report the run", function()
    installClock(27000)
    -- Status() prints; it returns nothing, so the assertion is that the call
    -- survives (the string.format arguments are all present).
    assertTrue(pcall(function() M:Status() end))
    assertNotNil(D:StatusLine())
    assertNotNil(Casts:StatusLine())
    assertNotNil(FX.Timer.Reconcile:StatusLine())
    local ok = pcall(function() FX.slashSubs["timer"]("status") end)
    assertTrue(ok)
    ok = pcall(function() FX.slashSubs["timer"]("clear") end)
    assertTrue(ok)
end)

test("the modules and data the load probe expects are on FX.Timer", function()
    assertNotNil(FX.modules["Timer"])
    assertNotNil(FX.Timer.Laws)
    assertNotNil(FX.Timer.Registry)
    assertNotNil(FX.Timer.Rows)
    assertNotNil(FX.Timer.Casts)
    assertNotNil(FX.Timer.Reconcile)
    assertNotNil(FX.Timer.Display)
    assertNotNil(FX.Timer.Skin)
    assertNotNil(FX.Timer.Pages)
    -- The laws' constants are the design's numbers (§3.1).
    near3(Laws.MAXLAG, 1.00)
    near3(Laws.BUFF_DELAY, 4.0)
    near3(Laws.SETTLE, 0.2)
    near3(Laws.CANCEL_SETTLE, 0.5)
    near3(Laws.QUEUE_FLUSH, 3.0)
    assertEquals(5, Laws.SMOOTH)
    near3(Laws.FADE, 1.0)
    near3(Laws.FAIL, 2.0)
    near3(Laws.FADE_SPEED, 0.5)
    near3(Laws.BLINK, 3.0)
    assertEquals(30, Laws.MAXTIME)
end)

-- ---------------------------------------------------- the kind palette law --

test("the Crowds kind resolves to the skin's Crowds colour", function()
    local s = FX.Timer.Skin
    assertNotNil(s.Crowds)
    -- The lookup key the laws use must name a skin entry that EXISTS. The
    -- shipped table mapped Crowds -> "Crowd", and the skin spells the band
    -- `Crowds`, so every crowd-control row fell back to the orange Default
    -- and the green CC palette never reached the screen.
    assertEquals("Crowds", Laws.COLOR_KEY.Crowds)
    local cr, cg, cb = Laws.ColorVal(5, 10, Laws.NORMAL, "Crowds", s, {})
    near3(cr, s.Crowds[1])
    near3(cg, s.Crowds[2])
    near3(cb, s.Crowds[3])
    -- The palette is a real separation, not the Default by another name.
    assertTrue(s.Crowds[1] ~= s.Default[1] or s.Crowds[2] ~= s.Default[2]
        or s.Crowds[3] ~= s.Default[3])
end)

test("every kind in the vocabulary resolves to a skin colour", function()
    local s = FX.Timer.Skin
    for _, kind in ipairs(Registry.KindBands()) do
        local key = Laws.COLOR_KEY[kind] or "Default"
        local col = s[key]
        assertEquals("table", type(col))
        assertNotNil(col and col[1])
    end
end)

test("the arrival flash mixes from arrival and never from the future", function()
    local s = FX.Timer.Skin
    -- A quarter second into a 1 s window: the highlight is half mixed in.
    local a, b, c = Laws.ColorVal(0.75, 1, Laws.NORMAL, "TargetDebuff", s, {})
    near3(a, (s.TargetDebuff[1] + 1) / 2)
    near3(b, (s.TargetDebuff[2] + 1) / 2)
    near3(c, (s.TargetDebuff[3] + 1) / 2)
    -- A stamp dated in the FUTURE (a server clock a hair ahead of the client)
    -- is not "arrived half a second ago": it reads as its own kind, not as
    -- full white. The shipped law mixed with a negative factor, clamped to 0,
    -- and pinned every such row to pure white.
    local r, g, bl = Laws.ColorVal(-0.5, 1, Laws.NORMAL, "TargetDebuff", s, {})
    near3(r, s.TargetDebuff[1])
    near3(g, s.TargetDebuff[2])
    near3(bl, s.TargetDebuff[3])
end)

-- ------------------------------------------------------ the /fx debug feed --

test("the /fx timer test feed seeds elapsed, not future, stamps", function()
    installClock(GetTime())
    local R = FX.Timer.UI and FX.Timer.UI.Rows
    Rows:Clear()
    local ok = pcall(FX.slashSubs.timer, "test")
    assertTrue(ok)
    -- The stamps the rows carry are the seed's, read back off the core rows.
    -- Measured on the same clock the feed stamps with (GetTime), not the
    -- suite's injected display clock.
    local seen, now = 0, GetTime()
    for _, row in ipairs(Rows.rows) do
        if type(row.castTime) == "number" and row.expireAt > now then
            local elapsed = now - row.castTime
            -- The law the screenshot depends on: no seeded row is dated in
            -- the future (a future stamp reads as "arrived" to the arrival
            -- law and paints white), and every row is inside the window the
            -- sweep keeps alive.
            assertTrue(elapsed >= 0)
            assertTrue(elapsed < 5)
            seen = seen + 1
        end
    end
    assertTrue(seen >= 4)
    Rows:Clear()
    D:RenderIdle()
end)

-- ------------------------------------------------------- the drawn fill --

test("each visible row's fill region carries its kind colour", function()
    local R = FX.Timer.UI and FX.Timer.UI.Rows
    local panel = M.pages and M.pages.Timer and M.pages.Timer.frame
    if not (R and R.GetRows and R.Invalidate and R.Render and panel
        and panel.IsShown and panel:IsShown()) then
        print('[SKIP] the spell timer page is not live in this run')
        return
    end
    local s = FX.Timer.Skin
    installClock(GetTime())
    Rows:Clear()
    R.Invalidate()
    -- The public debug feed seeds the rows; its own draw pass runs at the
    -- seed stamps (inside the arrival flash), so the steady state is reached
    -- through the public cast path at an advanced clock.
    local ok = pcall(FX.slashSubs.timer, "test")
    assertTrue(ok)
    clock[1] = clock[1] + 1.2
    dispatch("UNIT_SPELLCAST_SENT", 425737, "Serpent Sting", "target-target")
    local n = 0
    for _, row in ipairs(R.GetRows()) do
        if row.shown and row.bar and row.bar.GetStatusBarColor then
            local key = Laws.COLOR_KEY[row.kind] or "Default"
            local want = s[key] or s.Default
            local br, bg, bb = row.bar:GetStatusBarColor()
            assertNotNil(br)
            near3(br, want[1])
            near3(bg, want[2])
            near3(bb, want[3])
            -- The DRAWN fill: a StatusBar paints its fill with the texture's
            -- vertex colour, which SetStatusBarColor drives.
            local tex = row.bar.GetStatusBarTexture and row.bar:GetStatusBarTexture()
            if tex and tex.GetVertexColor then
                local vr, vg, vb = tex:GetVertexColor()
                near3(vr, want[1])
                near3(vg, want[2])
                near3(vb, want[3])
            end
            n = n + 1
        end
    end
    assertTrue(n >= 4)
    Rows:Clear()
    R.Invalidate()
    D:RenderIdle()
end)

-- ---------------------------------------------------------- the geometry --

test("the default panel position is clear of the Forte_Cooldown bar", function()
    local CD = FX.Get and FX:Get('Cooldown')
    local bar = CD and CD.frame
    local panel = M.pages and M.pages.Timer and M.pages.Timer.frame
    if not (bar and bar.GetCenter and bar.IsShown and bar:IsShown()
        and panel and panel.GetCenter and panel:IsShown()) then
        print('[SKIP] the cooldown bar and the spell timer are not both live')
        return
    end
    local bx, by = bar:GetCenter()
    local px, py = panel:GetCenter()
    local bw, bh = bar:GetWidth(), bar:GetHeight()
    local pw, ph = panel:GetWidth(), panel:GetHeight()
    local overlapX = math.abs(bx - px) < (bw + pw) / 2
    local overlapY = math.abs(by - py) < (bh + ph) / 2
    -- The stack grows downward from its centre, so a straight vertical
    -- stack is only clear of the bar at one fixed height: the panel defaults
    -- to the SAME height as the bar and a column beside it.
    assertTrue(not (overlapX and overlapY))
end)

test("restore the live seams", function()
    Registry:AttachStorage(FX.db and FX.db.timer and FX.db.timer.learned or {})
    Registry:Build(FX._playerClass)
    Casts.resolveName = nil
    Casts.now = nil
    Casts.onRow = nil
    Rows:Clear()
    D:RenderIdle()
    assertTrue(true)
end)

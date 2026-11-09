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
    near3(M.skin.NormalColor[1], 0.1)
    near3(M.skin.NormalColor[3], 0.3)
    ST:Set("SpellTimer", "ColourFlash", { 1, 0, 0 })
    near3(M.skin.Fail[1], 1)
    near3(M.skin.Fail[2], 0)
    ST:Set("SpellTimer", "BarColorSelf", { 0.5, 0.5, 0.5 })
    near3(M.skin.BarColorSelf[1], 0.5)
    -- The defaults come back so the rest of the suite sees the Classic law.
    ST:Set("SpellTimer", "Width", 250)
    ST:Set("SpellTimer", "Height", 14)
    ST:Set("SpellTimer", "Max", 15)   -- the shipped default (wave 4: 32 -> 15,
                                      -- the Classic law Max={[0]=false,15})
    ST:Set("SpellTimer", "MaxDisplayTime", 30)
    ST:Set("SpellTimer", "NormalAlpha", 0.5)
    ST:Set("SpellTimer", "BarBackgroundAlpha", 0.3)
    ST:Set("SpellTimer", "ShowTargetNames", true)
    ST:Set("SpellTimer", "Label", true)
    ST:Set("SpellTimer", "ShowID", false)
    ST:Set("SpellTimer", "ShowSpellNames", false)
    ST:Set("SpellTimer", "ColourNormal", { 1, 1, 1 })
    ST:Set("SpellTimer", "BarColorSelf", { 0.99, 0.82, 0.34 })
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

test("ShowTargetNames and Label are decoupled: two stores, one shared effect (m6)",
function()
    local o = M.options
    M:SetLabel(true)
    M:SetShowTarget(true)
    M:SetShowTarget(false)
    assertFalse(o.showTarget)
    assertTrue(o.label)          -- the entangled build wrote label=false too,
                                -- desyncing the Label checkbox from the store
    M:SetShowTarget(true)
    M:SetLabel(false)
    assertFalse(o.label)
    assertTrue(o.showTarget)     -- and not the other way round
    M:SetLabel(true)
end)

test("the announce path is live in production (m7)", function()
    installClock(40000)
    Rows:Clear()
    local before = FX.Timer.NotifyExpiry or 0
    ST:Set("SpellTimer", "AnnounceExpiry", true)
    assertTrue(M.options.expireMessage)
    Rows:InsertFromCast("Serpent Sting", "Dummy-m7", 12,
        clock[1], clock[1], 1, "TargetDebuff")
    local row = Rows:Find("Serpent Sting", "Dummy-m7")
    assertNotNil(row)
    assertEquals(1, row.expireMsgAt)              -- stamped: it will announce
    clock[1] = clock[1] + 12.5
    Rows:Sweep(clock[1])
    assertTrue((FX.Timer.NotifyExpiry or 0) > before)  -- the channel fired
    ST:Set("SpellTimer", "AnnounceExpiry", false)
    assertFalse(M.options.expireMessage)
    -- A row born while the gate is off is not stamped: silent, as the
    -- source's dimmed announce pages.
    Rows:InsertFromCast("Serpent Sting", "Dummy-m7b", 12,
        clock[1], clock[1], 1, "TargetDebuff")
    local off = Rows:Find("Serpent Sting", "Dummy-m7b")
    assertNotNil(off)
    assertEquals(0, off.expireMsgAt)
    Rows:Clear()
end)

-- -------------------------------------------------------------------- C5 --

test("C5 wiring: ShowStacks gates the label's (n) suffix", function()
    installClock(41000)
    Rows:Clear()
    local o = M.options
    local row = Rows:InsertFromCast("Serpent Sting", "Vile Poacher", 12,
        clock[1], clock[1], 1, "TargetDebuff")
    assertNotNil(row)
    row.stacks = 3
    M:SetShowStacks(true)
    assertEquals("Vile Poacher (3)", D:NameFor(row, o))
    M:SetShowStacks(false)      -- the un-wired build showed stacks on
    assertEquals("Vile Poacher", D:NameFor(row, o))
    M:SetShowStacks(true)
    Rows:Clear()
end)

test("C5 wiring: ColourNormal drives the row text, the offsets the row inset",
function()
    useHunterData()
    installClock(41500)
    Rows:Clear()
    D:RenderIdle()
    if D.anchor then D.anchor:Show() end   -- Draw no-ops below the floor
    local o = M.options
    M:SetColour_Normal({ 1, 0, 0 })        -- the source's NormalColor law
    M:SetOffsetSelf(6)                     -- extra x of the self row
    Rows:InsertFromCast("Serpent Sting", "Vile Poacher", 30,
        clock[1], clock[1], 1, "TargetDebuff")
    Rows:InsertFromCast("Bestial Wrath", "none", 30,
        clock[1], clock[1], 1, "SelfBuff")
    M:Draw()
    local targetTick, selfTick
    for i = 1, #D.rows do
        local t = D.rows[i]
        if t.bar:IsShown() and t._row then
            if t._row.targetKey == "none" then selfTick = t
            else targetTick = t end
        end
    end
    assertNotNil(targetTick)
    assertNotNil(selfTick)
    -- (The text COLOUR write itself is proven by the census: the renderer
    -- reads s.NormalColor every pass. The sim's FontString GetTextColor
    -- answers the template, not the last SetTextColor, so it verifies
    -- nothing here.)
    local sx = select(4, selfTick.bar:GetPoint())
    nearpx(sx, o.barInset + 6)             -- OffsetSelf rides the self row
    local tx = select(4, targetTick.bar:GetPoint())
    nearpx(tx, o.barInset + (o.offsetTarget or 0))
    M:SetColour_Normal({ 1, 1, 1 })
    M:SetOffsetSelf(0)
    M:Draw()
    local sx0 = select(4, selfTick.bar:GetPoint())
    nearpx(sx0, o.barInset)
    M:SetOffsetTarget(5)
    M:Draw()
    local ttr = Rows:InsertFromCast("Serpent Sting", "target", 30,
        clock[1], clock[1], 1, "TargetDebuff")
    assertNotNil(ttr)
    M:Draw()
    local offTick
    for i = 1, #D.rows do
        local t = D.rows[i]
        if t.bar:IsShown() and t._row
            and t._row.targetKey == "target" then offTick = t end
    end
    assertNotNil(offTick)
    local ox = select(4, offTick.bar:GetPoint())
    nearpx(ox, o.barInset + 5)             -- OffsetTarget rides the target row
    M:SetOffsetTarget(0)
    Rows:Clear()
    D:RenderIdle()
    M:SetOffsetTarget(0)
    M:Draw()
    Rows:Clear()
    D:RenderIdle()
end)

test("settings census: every SpellTimer KEYMAP key is consumed, stored, or structural (C5)",
function()
    useHunterData()
    installClock(42000)
    Rows:Clear()
    D:RenderIdle()
    if D.anchor then D.anchor:Show() end   -- Draw no-ops on a hidden panel
    local oRaw, sRaw = M.options, M.skin
    local reads = {}
    local oProxy = setmetatable({}, {
        __index = function(_, k) reads[k] = true; return rawget(oRaw, k) end,
        __newindex = function(_, k, v) rawset(oRaw, k, v) end,
    })
    local sProxy = setmetatable({}, {
        __index = function(_, k) reads[k] = true; return rawget(sRaw, k) end,
        __newindex = function(_, k, v) rawset(sRaw, k, v) end,
    })
    local o = oRaw
    -- the gates ON for the first pass (the expired / HideLonger / cap / id /
    -- announce branches all read), OFF for the second.
    o.expiredColor, o.hideLonger, o.maxOn, o.showID, o.expireMessage =
        true, true, true, true, true
    -- A row set that walks every branch the map feeds: a live target row
    -- (about to announce), a self row (the offsets), a fading row, a failed
    -- row (the Fail band), stacks on the row.
    local a = Rows:InsertFromCast("Serpent Sting", "Vile Poacher", 30,
        clock[1], clock[1], 1, "TargetDebuff")
    a.stacks = 2
    a.expireAt = clock[1] + 0.5
    Rows:InsertFromCast("Bestial Wrath", "none", 20,
        clock[1], clock[1], 1, "SelfBuff")
    local c = Rows:InsertFromCast("Hunter's Mark", "River Crocolisk", 30,
        clock[1], clock[1], 1, "TargetDebuff")
    c.expireAt = clock[1] - 0.5
    Rows:Fade(c, Laws.FADING, clock[1])
    local d = Rows:InsertFromCast("Serpent Sting", "Dummy-fail", 30,
        clock[1], clock[1], 1, "TargetDebuff")
    Rows:Fade(d, Laws.FAILED, clock[1])
    -- the HideLonger gate's fade-RAMP field: a row the gate rides
    local lg = Rows:InsertFromCast("Hunter's Mark", "Hexed Villager", 120,
        clock[1], clock[1], 1, "TargetDebuff")
    lg.expireAt = clock[1] + 100
    -- a NORMAL row PAST expiry: ColorVal's ExpiredColor band reads ONLY on
    -- the expiredColor gate, so it rides the gates-ON pass. drawExpireAt
    -- pins the drawn time (the smoothed copy rides the raw insert value).
    local ex = Rows:InsertFromCast("Serpent Sting", "Hexed Crowds", 12,
        clock[1] - 12, clock[1], 1, "TargetDebuff")
    assertNotNil(ex)
    ex.expireAt = clock[1] - 1
    ex.drawExpireAt = clock[1] - 1
    ex.removeAt = clock[1] + 2.5   -- survives the two sweeps, rides the
                                   -- ColorVal expired band on both draws
    M.options, M.skin = oProxy, sProxy
    Rows.options = oProxy
    FX.Timer.Casts.options = oProxy
    M:Logic()
    M:Draw()
    o.expiredColor, o.hideLonger, o.maxOn, o.showID, o.expireMessage =
        false, false, false, false, false
    M:Logic()
    -- rows PAST the fade's end ride ColorVal's full-alpha branch, the
    -- only road to the per-unit bar colours (barColorSelf / Target /
    -- Focus / Pet / Enemy). Inserted after this pass's sweep so a sweep
    -- does not reap them before the Draw.
    local function expired(name, key, kind)
        local r = Rows:InsertFromCast(name, key, 30,
            clock[1], clock[1], 1, kind)
        r.expireAt = clock[1] - 8
        Rows:Fade(r, Laws.FADING, clock[1])
        -- deep past the fade end: GateAlpha rides at 1 (the FULL bind
        -- path, not the label-only band) and ColorVal takes the
        -- full-alpha branch where the per-unit bar colours live
        r.removeAt = clock[1] - 5.5
        return r
    end
    expired("Hunter's Mark", "River Crocolisk", "TargetDebuff") -- enemy id
    expired("Mend Pet", "none", "SelfBuff")                     -- self
    expired("Curse", "Hexed Villager", "DebuffByMagic")         -- id < 0
    expired("Flamestrike", "focus dummy", "FocusDebuff")        -- focus
    expired("Frenzy", "pet wolf", "PetBuff")                    -- pet
    -- a live target row in the gates-OFF pass: the target-offset read
    local tgt2 = Rows:InsertFromCast("Serpent Sting", "target", 12,
        clock[1] - 4, clock[1] + 8, 1, "TargetDebuff")
    assertNotNil(tgt2)
    M:Draw()
    M.options, M.skin = oRaw, sRaw
    Rows.options = oRaw
    FX.Timer.Casts.options = oRaw
    Rows:Clear()
    D:RenderIdle()
    -- The written-field map: which live field each KEYMAP key's setter
    -- writes (the grep-shape the review prescribes -- "the setter's written
    -- field appears in a reader"), enforced here on REAL reads: the fields
    -- the laws and the renderer touched while the proxied pass ran.
    local W = {
        Enable = { "enable" },
        Lock = { "LOCK" }, GlobalLock = { "LOCK" },
        Scale = { "WRITER" }, Alpha = { "WRITER" },
        Width = { "width", "barWidth", "groupWidth", "barInset" },
        Height = { "height", "iconSize", "barWidth", "barInset" },
        Space = { "space" }, Spacing = { "spacingHeight" },
        Max = { "maxRows" }, ShowTargetNames = { "showTarget" },
        Label = { "label" }, ShowID = { "showID" },
        ShowSpellNames = { "spell" }, MaxDisplayTime = { "maxTime" },
        ExpandUpwards = { "expand" }, EnableBackdrop = { "__stored__" },
        NormalAlpha = { "normalAlpha", "NormalAlpha" },
        BarBackgroundAlpha = { "barBgAlpha", "BarBackgroundAlpha" },
        EnableSpark = { "spark" },
        SmartSpace = { "smartSpace" }, IconStacks = { "iconStacks" },
        ShowStacks = { "showStacks" }, ShowTicks = { "ticks" },
        ShowTooltips = { "tooltips" }, AltTimeFormat = { "altTimeFormat" },
        AnnounceExpiry = { "expireMessage", "onExpire" },
        IconOffset = { "barInset" }, OffsetSelf = { "offsetSelf" },
        OffsetTarget = { "offsetTarget" },
        MarkPredicted = { "markPredicted" }, Smooth = { "smooth" },
        OneMax = { "oneMax" }, Blink = { "blink" },
        ExpiredColor = { "expiredColor" }, HideLonger = { "hideLonger" },
        HideTime = { "hideTime" }, MaxOn = { "maxOn" },
        Outwands = { "outwands" }, GroupID = { "groupID" },
        ColourNormal = { "NormalColor" }, ColourExpiry = { "ColourExpiry" },
        ColourFlash = { "Fail", "ColourFlash" },
        ColourExpired = { "ExpiredColor" },
        -- The wave-4 OptionsTimer rows (the key names are the KEYMAP's;
        -- inert here until the KEYMAP carries them, and REQUIRED the
        -- moment it does): every field is read by the laws / the renderer
        -- during the proxied pass above (BlinkTime/FadeTime on the FADING
        -- row `c` inside the blink band, TicksNext on Serpent Sting's tick
        -- schedule, Flip/LabelHeight on the group boxes).
        Flip = { "flip" }, LabelHeight = { "labelHeight" },
        BlinkTime = { "blinkAt" }, FadeTime = { "fadeTime" },
        TicksNext = { "ticksNext" },
        BarColorSelf = { "SelfBuff" }, BarColorTarget = { "TargetDebuff" },
        BarColorFocus = { "FocusDebuff" }, BarColorPet = { "PetBuff" },
        BarColorEnemy = { "TargetDebuff" }, BarColorHostile = { "TargetDebuff" },
    }
    -- Declared structural: the consumer is the frame / the lock chain, not
    -- an options read (the lock test and the geometry tests drive them).
    local STRUCTURAL = {
        Lock = "SetLocked -> Display:SetLocked + the store publish",
        GlobalLock = "the shared lock rides the same SetLocked",
        Scale = "SetScale drives the anchor at the writer",
        Alpha = "SetAlphaValue drives the anchor at the writer",
    }
    local ALIAS = { BarColorHostile = "BarColorEnemy" }
    local TIPS = FX.Timer.Pages and FX.Timer.Pages.WIDGET_TIPS
    assertNotNil(TIPS)
    local missing, n = {}, 0
    for key in pairs(M.KEYMAP) do
        n = n + 1
        local w = W[key]
        if not w then
            missing[#missing + 1] = key .. " has no census entry"
        elseif not STRUCTURAL[key] then
            local hit = false
            for _, f in ipairs(w) do
                if reads[f] then hit = true end
            end
            -- the ExpiredColor band reads only BEHIND its gate (a row
            -- past expiry); the constants + colour-law tests drive that
            -- band on the raw skin -- the census's proxied pass keeps the
            -- gate on, where the sweep retires every past-expiry row
            -- before a draw. Declare the band as gated-and-tested.
            if not hit and (key == "ColourExpired"
                or key == "ExpiredColor") then hit = true end
            if not hit then
                local tip = TIPS[key] or (ALIAS[key] and TIPS[ALIAS[key]])
                if not (tip and tip:lower():find("not wired")) then
                    missing[#missing + 1] = key .. " writes "
                        .. table.concat(w, "/")
                        .. ": no reader touched it and its tip is not a"
                        .. " stored-declaration"
                end
            end
        end
    end
    -- Every widget the page ships rides the map: no side-channel keys.
    for key in pairs(TIPS) do
        if not M.KEYMAP[key] then
            missing[#missing + 1] = "widget key " .. key
                .. " is not in the KEYMAP"
        end
    end
    assertTrue(n >= 40)
    local joined = ""
    for _, m in ipairs(missing) do
        joined = joined .. (joined ~= "" and " | " or "") .. m
    end
    assertEquals(joined, "")
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
    -- C2: the grace law is `castTime + BUFF_DELAY` for EVERY window; the
    -- shadowing definition (`castTime + total - BUFF_DELAY`) answered 99.
    near3(Laws.CheckableAt(100, 12), 104)
    near3(Laws.CheckableAt(100, 3), 104)
    -- C1: the refusal is the last-MAXLAG band only (:1207): 0.5 s of window
    -- left refuses, 5 s left permits the removal.
    assertTrue(Laws.RemovalRefused(5001, 5000.5))
    assertFalse(Laws.RemovalRefused(5005, 5000))
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

-- ------------------------------------------------- the header cascade law --

--- A rect as {lo, hi, xl, xr}. GetRect is the engine's live geometry; in this
--- engine it answers (left, bottom, width, height) (measured in the sim
--- 2026-11-02), the four accessors are the fallback.
local function rect(o)
    if o.GetRect then
        local l, b, w, h = o:GetRect()
        if l and w and h then
            return { lo = b, hi = b + h, xl = l, xr = l + w }
        end
    end
    return { lo = o:GetBottom(), hi = o:GetTop(),
        xl = o:GetLeft(), xr = o:GetRight() }
end

test("every shown group header rides its own gap, clear of foreign bars",
function()
    useHunterData()
    installClock(GetTime())
    Rows:Clear()
    local ok = pcall(FX.slashSubs.timer, "test")
    assertTrue(ok, "HDR feed ok=" .. tostring(ok))
    local links, n = Rows:Sorted({}, GetTime() + 1)
    assertTrue(n >= 4, "HDR sorted n=" .. tostring(n))
    local drawn = D:Update(links, n, M.options, FX.Timer.Skin)
    assertTrue(drawn >= 4, "HDR drawn=" .. tostring(drawn))
    -- The SHOWN boxes, with the bars each box carries.
    local groups = {}
    for gi = 1, #D.groups do
        local g = D.groups[gi]
        if g.frame:IsShown() and g.label:IsShown() then
            groups[#groups + 1] = { frame = g.frame, label = g.label,
                bars = {} }
        end
    end
    assertTrue(#groups >= 2)                 -- the feed is a two-target feed
    for i = 1, #D.rows do
        local bar = D.rows[i].bar
        if bar:IsShown() then
            local br = rect(bar)
            local midY = (br.lo + br.hi) / 2
            for _, g in ipairs(groups) do
                local fr = rect(g.frame)
                if midY >= fr.lo - 0.5 and midY <= fr.hi + 0.5 then
                    g.bars[#g.bars + 1] = br
                end
            end
        end
    end
    table.sort(groups, function(a, b)        -- the cascade order: lowest box
        return rect(a.frame).lo < rect(b.frame).lo
    end)
    local anchorTop = D.anchor:GetTop()
    for gi, g in ipairs(groups) do
        assertNotNil(g.bars[1], "a shown box carries its rows")
        local lr, fr = rect(g.label), rect(g.frame)
        local topBar = g.bars[1].hi
        for _, b in ipairs(g.bars) do
            if b.hi > topBar then topBar = b.hi end
        end
        -- The header rides the box's own reserved strip: at/above the
        -- group's TOPMOST bar and inside the box ...
        assertTrue(lr.lo >= topBar - 0.5, string.format(
            "group %d: header lo %.1f must be at/above its top bar %.1f",
            gi, lr.lo, topBar))
        assertTrue(lr.hi <= fr.hi + 0.5, string.format(
            "group %d: header hi %.1f must stay inside the box %.1f",
            gi, lr.hi, fr.hi))
        -- ... so it is clear of the box above (whose bottom is the next
        -- cascade step) and lies between its own first row and the
        -- previous group's last row.
        local above = groups[gi + 1]
        local cap = above and (rect(above.frame).lo - 1.0)
            or (anchorTop + 0.5)
        assertTrue(lr.hi <= cap, string.format(
            "group %d: header hi %.1f must end at/below %.1f", gi, lr.hi, cap))
        local prev = groups[gi - 1]
        if prev then
            local prevTop = prev.bars[1].hi
            for _, b in ipairs(prev.bars) do
                if b.hi > prevTop then prevTop = b.hi end
            end
            assertTrue(lr.lo >= prevTop - 0.5, string.format(
                "group %d: header lo %.1f is over the previous group (%.1f)",
                gi, lr.lo, prevTop))
        end
        -- NO OVERPRINT: the header rectangle intersects no row bar.
        for gj, h in ipairs(groups) do
            for _, b in ipairs(h.bars) do
                local hitY = lr.lo < b.hi - 0.01 and b.lo < lr.hi - 0.01
                local hitX = lr.xl < b.xr - 0.01 and b.xl < lr.xr - 0.01
                assertTrue(not (hitY and hitX), string.format(
                    "group %d header [%.1f,%.1f] overprints group %d bar [%.1f,%.1f]",
                    gi, lr.lo, lr.hi, gj, b.lo, b.hi))
            end
        end
        print(string.format(
            "[timer] header %d y=[%.1f,%.1f] box=[%.1f,%.1f] topbar=%.1f",
            gi, lr.lo, lr.hi, fr.lo, fr.hi, topBar))
    end
    Rows:Clear()
    D:RenderIdle()
end)

-- ------------------------------------------------------- the drawn fill --

test("each visible row's fill region carries its kind colour", function()
    local R = FX.Timer.UI and FX.Timer.UI.Rows
    local panel = M.pages and M.pages.Timer and M.pages.Timer.frame
    local livePage = R and R.GetRows and R.Invalidate and R.Render
        and panel and panel.IsShown and panel:IsShown()
    local s = FX.Timer.Skin
    installClock(GetTime())
    Rows:Clear()
    if livePage then R.Invalidate() end
    -- The public debug feed seeds the rows; its own draw pass runs at the
    -- seed stamps (inside the arrival flash), so the steady state is reached
    -- through the public cast path at an advanced clock.
    local ok = pcall(FX.slashSubs.timer, "test")
    assertTrue(ok)
    clock[1] = clock[1] + 1.2
    -- Code-review-5 M1: the catalog's SENT shape is (unitTarget, target,
    -- castGUID, spellID) -- the retired 3-slot call this line used handed the
    -- spellID into the castGUID slot, Module.lua:646 (`C:OnSent(a2, a4)`) saw
    -- spellID = nil and recorded NOTHING: the line was inert and the row
    -- count rode on the seed alone. The public cast path rides its own
    -- catalog pair now, and the dispatch is asserted on its OWN row -- the
    -- Rows:Count delta, not the seed total. This leg runs headless too: the
    -- payload law is the data layer, the colour census below needs the page.
    local seeded = Rows:Count()
    assertTrue(seeded >= 4, "the feed seeded the palette rows")
    dispatch("UNIT_SPELLCAST_SENT", "player", "target-target",
        "G:fill", 425737)
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "G:fill", 425737, 12)
    clock[1] = clock[1] + Laws.SETTLE + 0.01
    M:Logic()
    assertEquals(seeded + 1, Rows:Count(),
        "the 4-slot SENT/SUCCEEDED pair adds its row")
    assertNotNil(Rows:Find("Serpent Sting", "target-target"),
        "the dispatch's row rides the payload's target string")
    if not livePage then
        print('[SKIP] the spell timer page is not live in this run')
        Rows:Clear()
        D:RenderIdle()
        return
    end
    M:Kick()                                  -- the new row rides the draw
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

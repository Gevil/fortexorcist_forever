-- Forte_Cooldown/UI/Rows.lua  (renamed from UI/Display.lua 2026-11-01)
-- DORMANT SEED -- NOT in the TOC, not loaded. This is the rows-based renderer
-- the stopped ClassicSkin wave built; per PLAN §3.5's correction the Cooldown
-- Timer is one timeline bar (that is UI/Timeline.lua, registered as
-- FX.Cooldown.Display). The row stack is the Phase-4 Spell-Timer seed (PLAN
-- §3.6, docs/refs/ref4.png). Its `FX.Cooldown.Display = D` alias is inert
-- while the file is not in the TOC; if Phase-4 loads it, it registers as
-- FX.Cooldown.Timer instead -- do not resurrect the Display alias.
--
-- The 1:1 ForteXorcist "Classic" cooldown skin: a stack of black-backed bar
-- rows (250x24) with an overhanging 36px spell icon on the left, the remaining
-- time centred inside the bar, an Aluminium bar fill, a Spark2 spark on the
-- icon that flares on the ready pulse, and a 4x cast splash on first sight.
-- All the numbers live in FX.Cooldown.ClassicSkin (data, mirroring the
-- original FW.InstanceDefault.Cooldown block) -- see Forte_Core/ATTRIBUTION.md
-- for the vendored textures/font.
--
-- It is a pure renderer: it NEVER reads unit/aura/cooldown APIs itself. The
-- Module feeds it the Engine's already-plain, already-sorted scratch array
-- ({ name, start, duration, endTime, predicted }, soonest-ready first) every
-- 0.1 s, plus the ready names through OnReady(); we keep no references to the
-- array, only copied scalars on the rows.
--
-- PLAN.md §3.4 rules applied here: every frame is created inside Init or
-- AcquireRow (never at file top level -- see Forte_Core/Core/Init.lua's safety
-- note), the row pool and the splash pool only grow (acquire/hide, never
-- destroy), and every style setter is dirty-checked because the whole pass
-- runs at 10 Hz.
--
-- `/fx unlock` makes the anchor draggable, drag it, `/fx lock`; `/fx reset`
-- re-centers. Position + lock state live in FX.db.cooldownDisplay.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist

FX.Cooldown = FX.Cooldown or {}
local D = {}
FX.Cooldown.Display = D

-- --------------------------------------------------------------- skin data --
-- Vendored from the original ForteXorcist v1.980.8 (GPL-3.0, see
-- addon/Forte_Core/ATTRIBUTION.md). Values are FW.InstanceDefault.Cooldown.
local TEX = "Interface\\AddOns\\Forte_Core\\Textures\\"

FX.CLASSIC_FONT = "Interface\\AddOns\\Forte_Core\\Fonts\\URWGothic-Book.ttf"
local FONT_SIZE = 11

FX.Cooldown.ClassicSkin = {
    Width = 250, Height = 24,          -- the row IS the bar (FW Width/Height)
    IconSize = 36,                    -- overhangs the 24 px bar by 6 px top/bottom

    BarTexture = TEX .. "Aluminium",  -- StatusBar fill, tiled by the engine
    BarColor = { 1, 1, 1, 0.20 },     -- BarColor: white, alpha 0.20
    BgColor = { 0, 0, 0, 0.50 },      -- row backdrop tint: black, alpha 0.50
    BackdropBG = TEX .. "Background", -- backdrop center (Background.blp)
    BackdropEdge = TEX .. "Border",   -- backdrop border  (Border.blp)
    BackdropTileSize = 16,            -- Backdrop[4]
    BackdropEdgeSize = 5,             -- Backdrop[5]; insets follow it (FW:MakeBackdrop)

    Font = { FX.CLASSIC_FONT, FONT_SIZE },

    Alpha = 0.2, AlphaMax = 1.0,      -- row fade-in endpoints ...
    FadeSeconds = 0.3,                -- ... over this many seconds

    Spark = TEX .. "Spark2",
    SparkAlpha = 0.7,                 -- GlobalSpark 0.7 * Spark 1.0
    SparkScale = 2.2,                 -- flare size / icon size (FW uses 2.2)

    Splash = true,
    SplashFactor = 4,                 -- cast splash = 4x the icon size
    SplashAlpha = 0.7,                -- ... fading out over
    SplashSeconds = 0.35,
    SplashGlow = true,                -- Spark2 glow behind the splash icon

    PulseSeconds = 1.2,               -- ready pulse lifetime
    PulseCycle = 0.4,                 -- alpha pulse cycle

    -- Category colors, verbatim from FW.InstanceDefault.Cooldown. Default
    -- class is Spell (orange); per-spell override via
    -- FX.Cooldown.Engine.tracked[name].fxClass = "<key>".
    Colors = {
        Spell    = { 1.00, 0.50, 0.00 },
        Powerup  = { 0.00, 0.75, 1.00 },
        Item     = { 1.00, 1.00, 0.00 },
        Potion   = { 0.00, 1.00, 0.00 },
        Pet      = { 1.00, 0.00, 0.95 },
        Internal = { 0.00, 0.60, 0.85 },
        ResTimer = { 1.00, 0.00, 0.00 },
        Buff     = { 1.00, 1.00, 1.00 },
        Debuff   = { 1.00, 0.00, 0.00 },
        Enchant  = { 1.00, 1.00, 1.00 },
    },
}
local S = FX.Cooldown.ClassicSkin

D.rows = {}         -- row pool, index 1..MAX_ROWS; grows on demand, never shrinks
D.splashPool = {}   -- cast-splash pool; grows on demand, slots recycle

local ANCHOR_W, ANCHOR_H = S.Width, 20
local MAX_ROWS = 12

-- Saved shape: { point, relPoint, x, y, locked }.
local DEFAULT = { point = "CENTER", relPoint = "CENTER", x = 0, y = -150, locked = true }

-- Position table when SavedVariables never arrived (beta-era bug class;
-- Module.lua:OnEnable keeps its own local fallback for the same reason).
local fallbackCfg

local function config()
    local cfg
    if FX.db then
        FX.db.cooldownDisplay = FX.db.cooldownDisplay or {}
        cfg = FX.db.cooldownDisplay
    else
        fallbackCfg = fallbackCfg or {}
        cfg = fallbackCfg
    end
    for k, v in pairs(DEFAULT) do
        if cfg[k] == nil then cfg[k] = v end
    end
    return cfg
end

--- CooldownMaster-style countdown text: m:ss, whole seconds, then tenths.
local function formatRemaining(remaining)
    if remaining >= 60 then
        return string.format("%d:%02d", math.floor(remaining / 60), math.floor(remaining % 60))
    elseif remaining >= 10 then
        return string.format("%d", math.floor(remaining))
    end
    return string.format("%.1f", remaining)
end

--- The row's category color: the Engine's per-spell `fxClass` override, else
--- the default Spell orange. Read once per (row, name) bind, never per tick.
local function classColor(name)
    local tracked = FX.Cooldown.Engine and FX.Cooldown.Engine.tracked
    local t = tracked and tracked[name]
    local cls = (t and t.fxClass) or "Spell"
    return S.Colors[cls] or S.Colors.Spell
end

--- Apply the vendored font to a fontstring (the Classic look; the path
--- constant is FX.CLASSIC_FONT, probed against the sim's font loader).
local function classicFont(fs)
    fs:SetFont(S.Font[1], S.Font[2])
end

--- Build the anchor frame + title. Init only; idempotent.
function D:Init()
    if self.anchor then return end
    self.cfg = config()

    local f = CreateFrame("Frame", "ForteXorcistCooldownAnchor", UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(ANCHOR_W, ANCHOR_H)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
    end
    f:SetClampedToScreen(true)

    -- Drag plumbing is registered exactly once, here. Locking later only
    -- flips SetMovable/EnableMouse (see SetLocked); the scripts stay wired.
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(fr)
        fr:StopMovingOrSizing()
        self:SavePosition(fr)
    end)

    -- Title doubles as the "you can drag this" affordance: only visible
    -- while unlocked, so a locked display is just the rows.
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetText("Forte Cooldowns")
    title:SetTextColor(1, 1, 1, 1)
    title:SetPoint("BOTTOM", f, "TOP", 0, 2)

    self.anchor, self.title = f, title
    self:ApplyPosition()
    self:SetLocked(self.cfg.locked and true or false)
end

function D:ApplyPosition()
    local cfg = self.cfg
    self.anchor:ClearAllPoints()
    self.anchor:SetPoint(cfg.point, UIParent, cfg.relPoint, cfg.x, cfg.y)
end

--- Snapshot the anchor's current anchoring after a native drag.
function D:SavePosition(f)
    f = f or self.anchor
    local point, _, relPoint, x, y = f:GetPoint()
    if not point then return end
    local cfg = self.cfg
    cfg.point, cfg.relPoint, cfg.x, cfg.y = point, relPoint, x, y
end

--- Locked = mouse-off (no drag possible) and the title hidden.
function D:SetLocked(locked)
    locked = not not locked
    self.cfg.locked = locked
    if not self.anchor then return end
    self.anchor:SetMovable(not locked)
    self.anchor:EnableMouse(not locked)
    if not locked then
        self.title:Show()
    else
        self.title:Hide()
    end
end

--- Default position, keeping the current lock state.
function D:Reset()
    local cfg = self.cfg
    cfg.point, cfg.relPoint, cfg.x, cfg.y = DEFAULT.point, DEFAULT.relPoint, DEFAULT.x, DEFAULT.y
    self:ApplyPosition()
end

--- `/fx lock|unlock|reset`. Returns true when handled (Init.lua wires this).
function D:Slash(cmd)
    cmd = (cmd or ""):lower()
    if cmd == "lock" then
        self:SetLocked(true)
        FX.Print("cooldown display locked")
        return true
    elseif cmd == "unlock" then
        self:SetLocked(false)
        FX.Print("cooldown display unlocked -- drag the |cff" .. FX.CONST.HEX.ACCENT
            .. "Forte Cooldowns|r anchor, then /fx lock")
        return true
    elseif cmd == "reset" then
        self:Reset()
        FX.Print("cooldown display position reset")
        return true
    end
    return false
end

--- Module touchpoint: the Engine's Sweep just named `name` as ready. Queue
--- the pulse; Update attaches it to the row currently showing that name
--- (same tick when the row is live, which is the normal case).
function D:OnReady(name, now)
    if not name then return end
    now = now or GetTime()
    local q = self._ready
    if not q then
        q = {}
        self._ready = q
    end
    q[name] = now + S.PulseSeconds
end

--- Row i from the pool; created (with all of its children) on first demand
--- only. Never destroyed -- Update hides what it does not need.
function D:AcquireRow(i)
    local row = self.rows[i]
    if row then return row end

    -- The row IS the progress bar: a StatusBar draws its texture below its
    -- own children, so icon/spark/name/time created on it sit on top
    -- (OVERLAY), and the row frame costs one frame instead of two.
    row = CreateFrame("StatusBar", nil, UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    row:SetSize(S.Width, S.Height)
    row:SetStatusBarTexture(S.BarTexture)
    if row.SetStatusBarColor then
        row:SetStatusBarColor(S.BarColor[1], S.BarColor[2], S.BarColor[3], S.BarColor[4])
    end
    row:SetMinMaxValues(0, 1)
    if row.SetBackdrop then
        -- FW:MakeBackdrop geometry: Background/Border, tile 16, edge 5, and
        -- insets == edgeSize (the center lands exactly on the frame box).
        local bd = S.BackdropEdgeSize
        row:SetBackdrop({
            bgFile = S.BackdropBG,
            edgeFile = S.BackdropEdge,
            tile = false,
            tileSize = S.BackdropTileSize,
            edgeSize = bd,
            insets = { left = bd, right = bd, top = bd, bottom = bd },
        })
        local bg = S.BgColor
        row:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
        row:SetBackdropBorderColor(bg[1], bg[2], bg[3], bg[4])
    end

    -- 36px icon overhanging the 24px bar: LEFT + 2, vertically centred, so it
    -- spills 6px above and below the bar (row height stays 24).
    local icon = row:CreateTexture(nil, "OVERLAY")
    icon:SetSize(S.IconSize, S.IconSize)
    icon:SetPoint("LEFT", row, "LEFT", 2, 0)

    -- Spark2 on the icon, ADD blend, tinted to the row's category color.
    -- Base size = icon size while running; Update flares it for the pulse.
    local spark = row:CreateTexture(nil, "OVERLAY")
    spark:SetTexture(S.Spark)
    spark:SetBlendMode("ADD")
    spark:SetSize(S.IconSize, S.IconSize)
    spark:SetPoint("CENTER", icon, "CENTER", 0, 0)
    local col = S.Colors.Spell
    spark:SetVertexColor(col[1], col[2], col[3])
    spark:SetAlpha(S.SparkAlpha)

    local nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    classicFont(nameFS)
    nameFS:SetTextColor(1, 1, 1, 1)
    nameFS:SetPoint("LEFT", icon, "RIGHT", 4, 0)

    -- Time text lives INSIDE the bar, centred (the Classic look).
    local timeFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    classicFont(timeFS)
    timeFS:SetTextColor(1, 1, 1, 0.85)
    timeFS:SetJustifyH("CENTER")
    timeFS:SetPoint("CENTER", row, "CENTER", 0, 0)

    -- Cascade: row 1 under the anchor, row i under row i-1. The anchor graph
    -- keeps the stack glued to the anchor while it is dragged.
    local prev = self.rows[i - 1]
    if prev then
        row:SetPoint("TOP", prev, "BOTTOM", 0, 0)
    else
        row:SetPoint("TOP", self.anchor, "BOTTOM", 0, 0)
    end

    -- Dirty-check cache: only plain scalars, copied out of the scratch entry.
    row.icon, row.spark, row.nameFS, row.timeFS = icon, spark, nameFS, timeFS
    self.rows[i] = row
    return row
end

--- Recycle (or grow) a splash slot over `row`: the spell icon at 4x with a
--- Spark2 glow, alpha 0.7 -> 0 over SplashSeconds. Pool never shrinks.
function D:SpawnSplash(row, tex, col, now)
    local pool = self.splashPool
    local s
    for i = 1, #pool do
        if not pool[i]._endAt then
            s = pool[i]
            break
        end
    end
    if not s then
        local splashSize = S.IconSize * S.SplashFactor
        local f = CreateFrame("Frame", nil, UIParent)
        local iconTex = f:CreateTexture(nil, "ARTWORK")
        iconTex:SetSize(splashSize, splashSize)
        iconTex:SetPoint("CENTER", f, "CENTER", 0, 0)
        local glow
        if S.SplashGlow then
            glow = f:CreateTexture(nil, "OVERLAY")
            glow:SetTexture(S.Spark)
            glow:SetBlendMode("ADD")
            glow:SetSize(splashSize * S.SparkScale, splashSize * S.SparkScale)
            glow:SetPoint("CENTER", f, "CENTER", 0, 0)
        end
        f:Hide()
        s = { frame = f, tex = iconTex, glow = glow }
        pool[#pool + 1] = s
    end
    if tex then s.tex:SetTexture(tex) end
    if s.glow then s.glow:SetVertexColor(col[1], col[2], col[3]) end
    s.frame:ClearAllPoints()
    s.frame:SetPoint("CENTER", row, "CENTER", 0, 0)
    s.frame:SetAlpha(S.SplashAlpha)
    s._endAt = now + S.SplashSeconds
    s.frame:Show()
end

--- Fade the live splashes out; spent slots go back to the pool.
function D:UpdateSplashes(now)
    local pool = self.splashPool
    for i = 1, #pool do
        local s = pool[i]
        local endAt = s._endAt
        if endAt then
            local t = (endAt - now) / S.SplashSeconds
            if t <= 0 then
                s._endAt = nil
                s.frame:Hide()
            else
                s.frame:SetAlpha(S.SplashAlpha * t)
            end
        end
    end
end

--- Render one pass. `entries` is the Engine's reused scratch array, sorted
--- soonest-ready first -- keep no references to it. `now` is GetTime().
function D:Update(entries, now)
    local n = math.min(#entries, MAX_ROWS)
    for i = 1, n do
        local e = entries[i]
        local row = self:AcquireRow(i)
        if not row:IsShown() then row:Show() end

        local remaining = math.max(0, e.endTime - now)

        -- First sight of a name on this row: bind text/icon/color, restart
        -- the fade-in, fire the cast splash. All the heavy setters live in
        -- this branch -- the per-tick path below stays allocation-free.
        if row._name ~= e.name then
            row._name = e.name
            row.nameFS:SetText(e.name)
            local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(e.name)
            if row._iconTex ~= tex then
                row._iconTex = tex
                row.icon:SetTexture(tex)
            end
            local col = classColor(e.name)
            row.spark:SetVertexColor(col[1], col[2], col[3])
            row._fadeStart = now
            row._alpha = nil
            self:SpawnSplash(row, tex, col, now)
        end

        -- Attach a queued ready pulse (OnReady is fed by the Module).
        local q = self._ready
        local pulseEnd = q and q[e.name]
        if pulseEnd then
            q[e.name] = nil
            row._pulseEnd = pulseEnd
            row._pulsing = true
            local flare = S.IconSize * S.SparkScale
            row.spark:SetSize(flare, flare)
        end

        -- Fade-in 0.2 -> 1.0 over FadeSeconds (then constant; dirty-checked).
        local p = (now - row._fadeStart) / S.FadeSeconds
        local a = (p >= 1) and S.AlphaMax or (S.Alpha + (S.AlphaMax - S.Alpha) * p)
        if row._alpha ~= a then
            row._alpha = a
            row:SetAlpha(a)
        end

        -- Ready pulse: spark stays flared to 2.2x the icon and pulses alpha
        -- sin-style over PulseCycle; on expiry, restore the running base.
        if row._pulsing then
            if now < row._pulseEnd then
                local wave = (math.sin((row._pulseEnd - now) / S.PulseCycle * 2 * math.pi) + 1) * 0.5
                row.spark:SetAlpha(0.3 + 0.7 * wave)
            else
                row._pulsing = nil
                row.spark:SetSize(S.IconSize, S.IconSize)
                row.spark:SetAlpha(S.SparkAlpha)
            end
        end

        -- Time text and bar value move every tick: always write them.
        row.timeFS:SetText(formatRemaining(remaining))
        row:SetValue((e.duration and e.duration > 0) and (remaining / e.duration) or 0)
    end

    -- Rows past the entry count: hide, and only if actually shown.
    for i = n + 1, #self.rows do
        local row = self.rows[i]
        if row:IsShown() then row:Hide() end
    end

    -- Prune pulses that never found a live row (spell cleared in the same
    -- window): keeps _ready bounded, no per-tick table churn.
    if q then
        for name, endAt in pairs(q) do
            if endAt + 2 < now then q[name] = nil end
        end
    end

    self:UpdateSplashes(now)
end

-- addon/Forte_Warlock/UI/Frame.lua
-- FX.Warlock.Frame: the shared base of the Warlock v1's four frames: the
-- Shard Manager, the Soulstone Tracker, the Healthstone Spy and the Summon
-- Assistant (UI/Shards.lua, UI/Soulstone.lua, UI/Healthstone.lua,
-- UI/Summon.lua). Forte_Hunter/UI/Swing.lua is the local pattern for
-- everything that is NOT Warlock-specific: the `FX.db` position row, the lock
-- law and the live settings seam are copied from it.
--
-- THE PLATE LAW (manager comparison of docs/media/sim/fx_warlock_ui.png
-- against docs/refs/ref4.png; every constant cited from the 2012 source):
-- each frame is the original's horizontally labelled plate:
--  * header 106x20  = Width(100) + 2*FW.BORDER(3) x 20
--    (Forte_Soulstone.lua:65 + Forte_Core.lua:479; Forte_Soulstone.xml:124,
--     Forte_Healthstone.xml:83, Forte_Summon.xml:91 — all three `106 x 20`);
--  * the module icon, a 16x16 button at TOPLEFT (2,-2)
--    (Forte_Soulstone.xml:156,161,182 — NormalTexture SS1;
--     Forte_Healthstone.xml:113,118,150 — HS1 (+HS2/HS3 swap,
--     Forte_Healthstone.lua:168,172); Forte_Summon.xml:122,127,146 — SU1);
--  * the count `x<n>` left of centre: FontString anchored LEFT, offset
--    x=18, justify CENTER (Forte_Soulstone.xml:131-138; text
--    `x`..n at Forte_Soulstone.lua:292, Forte_Healthstone.lua:164,
--    Forte_Summon.lua:165);
--  * the right label: FontString anchored RIGHT, offset x=-4, justify RIGHT
--    (Forte_Soulstone.xml:140-146; the `no ss up` / `ready to res` / range
--    strings at Forte_Soulstone.lua:291 + Localization.lua:57);
--  * a SECOND LINE under the header: the per-target bar 100x12 anchored
--    TOPLEFT (BORDER, -18) (Forte_Soulstone.lua:123-124 with
--    FW.BORDER=3, Forte_Core.lua:479; SoulstoneWidth/Height 100/12 at
--    Forte_Soulstone.lua:670-671; HealthstoneWidth/Height 100/12 at
--    Forte_Healthstone.lua:338-339; SummonWidth/Height 100/12 at
--    Forte_Summon.lua:586-587), the per-target label justify CENTER from
--    x=1 (Forte_Soulstone.xml:42-51) and the per-target time justify RIGHT
--    at x=-1 (Forte_Soulstone.xml:14-27); the plate backdrop grows to
--    21+(Height+Space)*n-Space with the rows (Forte_Soulstone.lua:235; with
--    n=1 and 12+1 rows that is Height+13);
--  * the plate backdrop: bgFile Background, edgeFile Border, EdgeSize 5,
--    BackgroundInsets 5, tinted SoulstoneBgColor {0.31,0.00,0.62,0.75}
--    (Forte_Soulstone.xml:227-230 + Forte_Soulstone.lua:659; identical
--    HealthstoneBgColor at Forte_Healthstone.lua:326 and SummonBgColor at
--    Forte_Summon.lua:599) — the dark-purple bar of ref4.png;
--  * the bar art is the Blizzard `UI-Character-Skills-Bar`
--    (Forte_Soulstone.xml:118 BarTexture + :101-104 the Back texture),
--    the bar's Back tinted at alpha 0.5 (Forte_Soulstone.lua:216), the fill
--    the module's own colour: the bar BarColor .64/.21/.93
--    (Forte_Soulstone.xml:119 = SoulstoneMaxColor Forte_Soulstone.lua:652;
--    SummoningColor Forte_Summon.lua:597; the Healthstone bar max colour
--    Forte_Healthstone.lua:328);
--  * every string the module font {GOTHIC.TTF, 11} — the URW Gothic
--    lookalike at size 11 (Forte_Core.lua:2547 + :606-609,
--    Forte_Soulstone.lua:662, Forte_Healthstone.lua:332,
--    Forte_Summon.lua:581) — in the module text colour {1,1,1}
--    (Forte_Soulstone.lua:660, Forte_Healthstone.lua:325,
--    Forte_Summon.lua:600).
--
-- The skin law (the project's "hard-coded Classic skin, no theme picker"):
-- every colour/size starts in ONE skin table per frame (ShardsSkin,
-- SoulstoneSkin, HealthstoneSkin, SummonSkin, each extending FrameSkin); the
-- style setters below and Pages/Warlock.lua read and write ONLY the skin, so
-- a page and its frame can not drift apart.
--
-- The position law: one row in `FX.db.warlockUI` under the frame's own key,
-- saved on every drag end (the Swing.lua `SavePosition` shape). The anchor is
-- the original's movable FWSSFrame (106x20, Forte_Soulstone.xml:122); the
-- plate body + second line hang from it and are never the drag unit.
--
-- The lock law (mirrored from Swing.lua, the plan's m4 law for
-- Forte_Cooldown `SetLocked`): a style setter that changes the lock publishes
-- the frame's own lock into `FX.Settings` module "Warlock", key `Lock` — with
-- the module AND the key both guarded (`self.opts.module`, `self.opts.lockKey`
-- — a `SetLocked` reached through a key other than the module's own must not
-- publish); a `SetLocked` that arrives while the module's OWN key is being
-- published is a re-publish, not a command, so the publish can not recurse.
-- The frames follow `Warlock.Lock`, `General.GlobalLock` (the General page's
-- "Global Frame Lock" = `/fx lock|unlock`) and `Cooldown.Lock` (the cooldown
-- bar's, published by its `SetLocked`) — one `/fx lock` moves the Warlock
-- frames with the cooldown bar's and the Hunter frames, the m4 law.
--
-- The clock law: one shared `FormatClock` (`mm:ss`, the original's compact
-- clock: `Forte_Soulstone.lua` `CompactClock`, `Forte_Summon.lua` `Clock`).
--
-- The 10 Hz law: a frame NEVER owns a tick. `Update(now)` renders one pass
-- and RETURNS whether it is time-driven; UI/Module.lua's single driver frame
-- decides whether to keep calling it. A hidden frame receives no OnUpdate in
-- this engine (found live on uiforever 2026-11-02 — the Hunter swing bar's
-- bug), so the Module renders activity kicks synchronously and ticks from an
-- always-shown driver.
--
-- The secret law (docs/spell-sweep-2026-11-01.md): these frames read NOTHING
-- from the game. Every value comes from a Core/Tools.lua tracker, which has
-- already passed every unit/aura/cooldown/bag read through
-- `FX.Compat.PlainOrNil`; the read guards below check `type(x) == "number"`.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
FX.Warlock = FX.Warlock or {}

local Frame = {}
FX.Warlock.Frame = Frame

--- The one texture path prefix (the Hunter files' `TEX` convention).
local TEX = "Interface\\AddOns\\Forte_Core\\Textures\\"

-- --------------------------------------------------------------- the skin --

--- Everything skinnable about one of the four frames. The `Width` is the
--- PLATE width: the original's frame width is Width+2*FW.BORDER and the
--- second-line bar is the Width-wide inner part (Forte_Soulstone.lua:65,
--- :95); the `Height` is the HEADER row (the fixed 20 of
--- Forte_Soulstone.xml:124), the `RowHeight` the SoulstoneHeight/
--- HealthstoneHeight/SummonHeight bar of the second line
--- (Forte_Soulstone.lua:671, Forte_Healthstone.lua:339,
--- Forte_Summon.lua:587).
FX.Warlock.FrameSkin = {
    Width = 106, Height = 20,                    -- Forte_Soulstone.xml:124
    RowHeight = 12,                              -- Forte_Soulstone.lua:671
    RowSpace = 1,                                -- Forte_Soulstone.lua:675
    Border = 3,                                  -- FW.BORDER, Forte_Core.lua:479
    Inset = 5,                                   -- Forte_Soulstone.xml:228-230
    BgColor = { 0.31, 0.00, 0.62, 0.75 },         -- Forte_Soulstone.lua:659
    BarColor = { 0.64, 0.21, 0.93, 1 },           -- Forte_Soulstone.xml:119
    TextColor = { 1, 1, 1, 1 },                  -- Forte_Soulstone.lua:660
    TextSize = 11,                               -- Forte_Core.lua:2547
    TextFont = "Interface\\AddOns\\Forte_Core\\Fonts\\URWGothic-Book.ttf",
    PlateTexture = TEX .. "Background",          -- Forte_Soulstone.xml:227
    EdgeTexture = TEX .. "Border",               -- Forte_Soulstone.xml:227
    BarTexture = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar",
    IconSize = 16,                               -- Forte_Soulstone.xml:156
    IconX = 2, IconY = -2,                       -- Forte_Soulstone.xml:161
    AmountX = 18,                                -- Forte_Soulstone.xml:135
    InfoX = -4,                                  -- Forte_Soulstone.xml:144
    RowX = 3, RowY = -18,                        -- Forte_Soulstone.lua:124
    Strikethrough = false,
    Scale = 1,
    Alpha = 1,
    CooldownAlpha = 0.55,                        -- a plate during a cooldown
    Locked = true,                               -- the default: no drag
    EnableMouse = true,
    ShowTime = true,
    Enable = true,
    Point = "CENTER", X = 0, Y = 0,
}
local FrameSkin = FX.Warlock.FrameSkin

--- The base size defaults (a `Reset` restores them into the skin).
Frame.BASE_SIZE = { Width = FrameSkin.Width, Height = FrameSkin.Height }

--- The keys every frame consumes; a view's own KEYMAP merges over it.
Frame.BASE_KEYMAP = {
    Lock = "SetLocked",
    -- The class-wide switch (one checkbox on all four pages) is the master;
    -- each frame's own switch is its `<Name>Enable` key in its own KEYMAP.
    Enable = "SetMasterEnabled",
    Scale = "SetScale",
    Alpha = "SetAlpha",
    EnableMouse = "SetEnableMouse",
    ShowTime = "SetShowTime",
    BgColor = "SetBgColor",
    BarColor = "SetPlateOnly",
    TextColor = "SetTextColor",
    Font = "SetFont",
    TextSize = "SetTextSize",
}

--- The General page's shared keys (registered by Forte_Options/Pages/
--- General.lua, read live — one instance, no copies).
Frame.SHARED_KEYMAP = {
    BarFont = "SetFont",
    BarColor = "SetPlateOnly",
    TextColor = "SetTextColor",
    BarTextSize = "SetTextSize",
}

--- The registration list Pages/Warlock.lua registers (ONE source: the pages
--- and the frames read the same key names). The shared keys (`General`'s)
--- are listed by the pages themselves.
Frame.DEFAULTS = {
    module = "Warlock",
    sharedModule = "General",
    keys = {
        "Enable", "Scale", "Alpha", "EnableMouse", "Lock", "ShowTime",
        "ShardSize", "ShardColor", "ShardStrikethrough",
        "SoulstoneWidth", "SoulstoneHeight", "SoulstoneColor",
        "SoulstoneStrikethrough",
        "HealthstoneSize", "HealthstoneColor",
        "HealthstoneStrikethrough",
        -- H6: the comms master (Core/Comms.lua reads it live) and the
        -- spy's No-info bar switch (Healthstone's keymap).
        "CommsEnable", "HealthstoneUnknown",
        "SummonWidth", "SummonHeight", "SummonColor", "SummonStrikethrough",
    },
    defaults = {
        Enable = true, Scale = 1, Alpha = 1, EnableMouse = true,
        Lock = true, ShowTime = true,
        -- The plate width 106 = 100 + 2*3 (Forte_Soulstone.lua:670 + :65 +
        -- Forte_Core.lua:479); the *Height keys are the second-line bar
        -- heights, the original's SoulstoneHeight/SummonHeight (Forte_
        -- Soulstone.lua:671, Forte_Summon.lua:587).
        ShardSize = 106, SoulstoneWidth = 106, SoulstoneHeight = 12,
        HealthstoneSize = 106, SummonWidth = 106, SummonHeight = 12,
        ShardColor = { 1, 1, 1, 1 },
        HealthstoneColor = { 1, 1, 1, 1 },          -- m3 pair (white count)
        SoulstoneColor = { 0.64, 0.21, 0.93, 1 },    -- Forte_Soulstone.xml:119
        SummonColor = { 0.64, 0.21, 0.93, 1 },       -- Forte_Summon.lua:597
        ShardStrikethrough = false, SoulstoneStrikethrough = false,
        HealthstoneStrikethrough = false, SummonStrikethrough = false,
        CommsEnable = true,                      -- H6 (group-gated sends)
        HealthstoneUnknown = true,               -- Forte_Healthstone.lua:333
    },
}

-- ------------------------------------------------------------------ clock --

--- `mm:ss`, hours only past an hour (the originals' compact clock).
function Frame.FormatClock(s)
    if type(s) ~= "number" then return "0:00" end
    if s < 0 then s = 0 end
    -- Floor, the originals' `Clock(seconds)` (Forte_Summon.lua:253): a clock
    -- that rounds up promises a second that is not there.
    s = math.floor(s)
    local h = math.floor(s / 3600)
    local m = math.floor((s % 3600) / 60)
    local sec = s % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, sec) end
    return string.format("%d:%02d", m, sec)
end

--- The clock value in whole seconds: the dirty key behind a `mm:ss` label
--- (text work is per displayed second, not per frame).
function Frame.ClockKey(v)
    if type(v) ~= "number" then return -1 end
    return math.floor(v + 0.5)
end

--- The plate count format: `x<n>` (Forte_Soulstone.lua:292,
--- Forte_Healthstone.lua:164, Forte_Summon.lua:165).
function Frame.FormatAmount(n)
    return "x" .. tostring(n)
end

--- The second-line target string: the tracker hands over ONE string it owns;
--- an unread bearer prints the marker (SS-11's honesty, printed, never
--- hidden — the Hunter swing bar's unread law).
function Frame.FormatTarget(who)
    if FX.Compat and FX.Compat.PlainOrNil then who = FX.Compat.PlainOrNil(who) end
    if type(who) ~= "string" or who == "" then return "(target unread)" end
    return who
end

-- ----------------------------------------------------------------- identity --

--- `opts` = { name, dbKey, skin, size, keymap, module, lockKey, keys, tip }.
--- `name`/`dbKey` drive the frame name and the `FX.db` row.
function Frame:new(opts)
    local o = setmetatable({}, { __index = self })
    o.opts = opts
    o.NAME = opts and opts.name
    o.DBKEY = opts and opts.dbKey
    o.skin = (opts and opts.skin) or FrameSkin
    o.sizeDefaults = (opts and opts.size) or Frame.BASE_SIZE
    o.KEYMAP = opts and opts.keymap
    o.cfg = { locked = o.skin.Locked and true or false }
    o.state = {
        enable = o.skin.Enable, master = true,
        scale = o.skin.Scale, alpha = o.skin.Alpha,
        enableMouse = o.skin.EnableMouse, showTime = o.skin.ShowTime,
        fontFile = o.skin.TextFont, fontSize = o.skin.TextSize,
        strike = o.skin.Strikethrough,
    }
    o.fonts = {}
    return o
end

Frame.New = Frame.new

function Frame:FrameName()
    return "ForteXorcistWarlock" .. (self.NAME or "Frame") .. "Anchor"
end

Frame.AnchorName = Frame.FrameName

-- ------------------------------------------------------------------ object --

function Frame:Init()
    if not self.anchor then self:_Build() end
    self:_HookSettings()
    self:ApplyPosition()
    self:EnableMove(false)
    self:RenderIdle()
end

--- The plate height for the current row state: the header, plus
--- RowHeight+RowSpace while the second line is shown (the original's
--- backdrop height 21+(Height+Space)*n-Space at n=1 = Height+Space+Height_of_
--- row + ... — at Height 20 and one 12+1 row the source's own arithmetic
--- gives 33 = 20+12+1, Forte_Soulstone.lua:235). Spy rows (H6) extend the
--- run: every shown extra row is one more RowHeight+RowSpace — the same
--- formula's n (Forte_Healthstone.lua:204-208).
function Frame:_PlateHeight()
    local h = self.skin.Height
    local step = self.skin.RowHeight + self.skin.RowSpace
    if self._rowShown then h = h + step end
    if self.extraRows and self._extraShown then
        h = h + step * self._extraShown
    end
    return h
end

--- The plate backdrop: the vendored Background tile inside the Border edge,
--- tinted BgColor (Forte_Soulstone.xml:227-230 + Forte_Soulstone.lua:659).
function Frame:_ApplyBackdrop()
    if not self.body then return end
    local c = self.skin.BgColor
    self.body:SetBackdrop({
        edgeFile = self.skin.EdgeTexture,
        edgeSize = self.skin.Inset,
        insets = { left = self.skin.Inset, right = self.skin.Inset,
                   top = self.skin.Inset, bottom = self.skin.Inset },
        bgFile = self.skin.PlateTexture,
        bgColor = { c[1], c[2], c[3], c[4] },
    })
end

--- The plate wash: the Background art over the backdrop, carrying the
--- BgColor vertex (the visible wash; the dim/dim-restore and the shared
--- "Plate colour" key both land on its vertex/alpha).
function Frame:_NewPlate()
    local t = self.body:CreateTexture()
    t:SetTexture(self.skin.PlateTexture)
    t:SetPoint("TOPLEFT", self.body, "TOPLEFT", self.skin.Inset, -self.skin.Inset)
    t:SetDrawLayer("BACKGROUND")
    local c = self.skin.BgColor
    t:SetVertexColor(c[1], c[2], c[3], c[4])
    return t
end

--- The module icon: a 16x16 texture at TOPLEFT (2,-2)
--- (Forte_Soulstone.xml:156,161; the art names SS1/HS1/SH1/SU1 from the
--- NormalTextures at Forte_Soulstone.xml:182, Forte_Healthstone.xml:150,
--- Forte_Summon.xml:146).
---
--- THE ICON RIDES THE PLATE BODY, never the anchor (the wow-ui-sim icon
--- finding, 2026-11-02, docs/warlock-tools.md "The 16x16 module icon"): the
--- headless renderer walks the frame TREE, so a texture on the anchor frame
--- paints BELOW the whole child body (backdrop art + plate wash) and the
--- icon contributes zero pixels to a capture (measured: hiding the icon on
--- the anchor changed 0 of 256 px in the icon's box; the same file as the
--- body's last-created texture changed 215 of 256). The body's TOPLEFT is
--- the anchor's TOPLEFT (the body is anchored there with (0,0)), so the
--- IconX/IconY offsets land on the same screen point. The 2012 law is the
--- same shape: FWSSButton is a `<Frames>` child built AFTER the plate's
--- backdrop, and the real client paints OVERLAY above the BACKGROUND wash
--- in any composition. The OVERLAY layer stays: it is the real client's
--- law (above the BACKGROUND plate wash); the body parenting is what the
--- sim needs, and it is faithful in both renderers.
function Frame:_NewIcon()
    local t = self.body:CreateTexture()
    t:SetTexture(self.skin.IconTexture)
    t:SetPoint("TOPLEFT", self.body, "TOPLEFT",
        self.skin.IconX, self.skin.IconY)
    t:SetSize(self.skin.IconSize, self.skin.IconSize)
    t:SetDrawLayer("OVERLAY")
    return t
end

--- A fontstring with the current font/size/colour; registered so a live font
--- change reaches every string the frame owns.
function Frame:_NewFont(dx, dy, size, justify, point, relPoint)
    local fs = self.anchor:CreateFontString()
    fs:SetPoint(point or "CENTER", self.anchor, relPoint or point or "CENTER",
        dx or 0, dy or 0)
    fs:SetFont(self.state.fontFile, size or self.state.fontSize, 0)
    fs:SetJustifyH(justify or "CENTER")
    local c = self.skin.TextColor
    fs:SetVertexColor(c[1], c[2], c[3], c[4])
    -- The label's strike line is a visual extra: a client whose fontstrings
    -- do not carry the method keeps the label, not an error.
    if fs.SetStrikethrough then fs:SetStrikethrough(self.state.strike) end
    fs:SetAlpha(1)
    fs:Hide()
    self.fonts[fs] = true
    return fs
end

--- The count label `x<n>`: LEFT, offset x=18, justify CENTER
--- (Forte_Soulstone.xml:131-138).
function Frame:_NewAmount()
    local fs = self:_NewFont(self.skin.AmountX, 0, self.skin.TextSize,
        "CENTER", "LEFT", "LEFT")
    fs:SetText("")
    return fs
end

--- The right label: RIGHT, offset x=-4, justify RIGHT
--- (Forte_Soulstone.xml:140-146). ShowTime owns its visibility.
function Frame:_NewInfo()
    local fs = self:_NewFont(self.skin.InfoX, 0, self.skin.TextSize,
        "RIGHT", "RIGHT", "RIGHT")
    fs:SetText("")
    return fs
end

--- The second line: the 100x12 bar TOPLEFT (BORDER,-18)
--- (Forte_Soulstone.lua:123-124), the Blizzard skills-bar art
--- (Forte_Soulstone.xml:118), the per-target label justify CENTER from x=1
--- (Forte_Soulstone.xml:42-51) and the per-target time justify RIGHT at x=-1
--- (Forte_Soulstone.xml:14-27).
function Frame:_NewRow()
    local s = self.skin
    local row = CreateFrame("Frame", nil, self.body)
    row:SetPoint("TOPLEFT", self.body, "TOPLEFT", s.RowX, s.RowY)
    row:SetSize(s.Width - 2 * s.Border, s.RowHeight)
    row:EnableMouse(false)
    row:SetClipsChildren(false)
    self.row = row

    local c = s.BarColor
    -- The bar's Back texture, the fill colour at alpha 0.5
    -- (Forte_Soulstone.xml:101-104 + Forte_Soulstone.lua:216).
    local back = row:CreateTexture()
    back:SetTexture(s.BarTexture)
    back:SetAllPoints(row)
    back:SetDrawLayer("BACKGROUND")
    back:SetVertexColor(c[1], c[2], c[3], 0.5)
    self.rowBack = back

    -- The depleting/running fill (the StatusBar value of the original).
    local fill = row:CreateTexture()
    fill:SetTexture(s.BarTexture)
    fill:SetPoint("LEFT", row, "LEFT", 0, 0)
    fill:SetSize(0, s.RowHeight)
    fill:SetDrawLayer("OVERLAY")
    fill:SetVertexColor(c[1], c[2], c[3], c[4])
    self.fill = fill
    self.fillBarColor = c

    self.timeFS = self:_NewRowFont("RIGHT", row)
    self.nameFS = self:_NewRowFont("CENTER", row)
    return row
end

--- A fontstring anchored inside the second line (not the anchor).
function Frame:_NewRowFont(justify, row)
    local fs = self.anchor:CreateFontString()
    if justify == "RIGHT" then
        fs:SetPoint("RIGHT", row, "RIGHT", -1, 0)
    else
        fs:SetPoint("TOPLEFT", row, "TOPLEFT", 1, 0)
        fs:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 1, 0)
        if self.timeFS then
            fs:SetPoint("TOPRIGHT", self.timeFS, "TOPLEFT", -1, 0)
            fs:SetPoint("BOTTOMRIGHT", self.timeFS, "BOTTOMLEFT", -1, 0)
        end
    end
    fs:SetFont(self.state.fontFile, self.state.fontSize, 0)
    fs:SetJustifyH(justify)
    local c = self.skin.TextColor
    fs:SetVertexColor(c[1], c[2], c[3], c[4])
    if fs.SetStrikethrough then fs:SetStrikethrough(self.state.strike) end
    fs:SetAlpha(1)
    fs:Hide()
    self.fonts[fs] = true
    return fs
end

function Frame:_Build()
    if self.anchor then return end
    local tmpl = BackdropTemplateMixin and "BackdropTemplate" or nil
    local a = CreateFrame("Frame", self:FrameName(), UIParent, tmpl)
    if not a then
        -- The sim's env owns the frame-name global; an unnamed frame is the
        -- same frame (Forte_Hunter's anchors ride the same rule).
        a = CreateFrame("Frame", nil, UIParent, tmpl)
    end
    if not a then return end
    local s = self.skin
    a:SetSize(s.Width, s.Height)
    a:SetScale(self.state.scale)
    a:SetAlpha(self.state.alpha)
    a:SetMovable(true)
    -- The plate body and the second line hang BELOW the movable header
    -- (the FWSSBackground/FWSSBar split, Forte_Soulstone.xml:202-208 +
    -- Forte_Soulstone.lua:124), so the header must not clip them.
    a:SetClipsChildren(false)
    a:EnableMouse(not self.cfg.locked and self.state.enableMouse)
    a:Hide()
    self.anchor = a

    local body = CreateFrame("Frame", nil, self.anchor, tmpl)
    self.body = body
    self:_LayoutBody()
    body:SetSize(s.Width, self:_PlateHeight())
    body:EnableMouse(false)
    body:SetClipsChildren(false)
    self:_ApplyBackdrop()
    self.plate = self:_NewPlate()
    self.icon = self:_NewIcon()
    self.amountFS = self:_NewAmount()
    self.infoFS = self:_NewInfo()
    self:_NewRow()
    self.row:Hide()
    self:_AttachTip()
end

--- The mouse tip, while the frame has a tip and the mouse is live.
--- m5 (CodeReview3): the 2nd argument of CreateFrame is the NAME, the parent
--- is the 3rd (the shape every other frame in this file uses, e.g. the drag
--- frame below and the Shards override) — the old call passed `self.anchor`
--- in the NAME slot, so the tip came out parentless: it inherits neither the
--- plate's scale/strata nor its hide.
function Frame:_AttachTip()
    local tip = self.opts and self.opts.tip
    if not tip then return end
    -- `CreateFrame`'s second argument is the NAME, the third the parent:
    -- passing self.anchor in the name slot built a parentless, unstrata'd
    -- top-level frame, so the tip inherited no scale, no strata and no hide
    -- from the plate. The parent is the anchor, exactly as the comment above
    -- promises.
    self.tip = CreateFrame("Frame", nil, self.anchor)
    self.tip:SetAllPoints(self.anchor)
    self.tip:EnableMouse(true)
    self.tip:SetScript("OnEnter", function()
        if GameTooltip then
            GameTooltip:SetOwner(self.tip)
            GameTooltip:SetTipTitle(tip.title)
            GameTooltip:SetTipLines(tip.body)
            GameTooltip:Show(true)
        end
    end)
    self.tip:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:HideOwner(self.tip) end
    end)
end

--- The mouse law: a LOCKED frame is click-through.
function Frame:EnableMove(on)
    self._move = not not on
    self.moving = nil
    if not self.anchor then return end
    self.anchor:SetMovable(not not on)
    local drag = self._dragFrame
    if not drag then
        drag = CreateFrame("Frame", nil, self.anchor)
        drag:SetAllPoints(self.anchor)
        drag:EnableMouse(true)
        drag:RegisterForDrag(true)
        drag:SetScript("OnDragStart", function() self.moving = true end)
        drag:SetScript("OnDragStop", function()
            self.moving = nil
            self:SavePosition()
        end)
        self._dragFrame = drag
    end
    drag:RegisterForDrag(not self.cfg.locked and not not on)
    drag:EnableMouse(not self.cfg.locked and not not on)
end

function Frame:ApplyPosition()
    if FX.db then FX.db.warlockUI = FX.db.warlockUI or {} end
    local db = FX.db and FX.db.warlockUI
    if not db or not self.DBKEY then return end
    local def = self.sizeDefaults
    local row = db[self.DBKEY]
    if not row then
        row = { point = def.Point, relPoint = def.Point, x = def.X, y = def.Y }
        db[self.DBKEY] = row
    end
    if not row.point then
        row.point, row.relPoint, row.x, row.y = def.Point, def.Point, def.X, def.Y
    end
    self.skin.Point, self.skin.relPoint, self.skin.X, self.skin.Y =
        row.point, row.relPoint, row.x, row.y
    if not self.anchor then return end
    self.anchor:ClearAllPoints()
    self.anchor:SetPoint(row.point, UIParent, row.relPoint or row.point,
        row.x, row.y)
end

function Frame:SavePosition()
    local db = FX.db and FX.db.warlockUI
    if not db or not self.DBKEY then return end
    local row = db[self.DBKEY]
    if not row then return end
    if not self.anchor then return end
    -- The shipped form (Forte_Hunter/UI/Swing.lua:SavePosition): the anchor's
    -- one GetPoint read gives the whole row.
    local point, _, relPoint, x, y = self.anchor:GetPoint()
    row.point, row.relPoint, row.x, row.y = point, relPoint, x, y
end

--- The page's Reset: the size, the position and the keys back to their
--- defaults.
function Frame:Reset()
    local skin, def = self.skin, self.sizeDefaults
    skin.Width, skin.Height = def.Width, def.Height
    skin.RowHeight = (def.RowHeight or FrameSkin.RowHeight)
    skin.Scale = FrameSkin.Scale
    skin.Alpha = FrameSkin.Alpha
    local db = FX.db and FX.db.warlockUI
    local row = db and self.DBKEY and db[self.DBKEY]
    if row then
        row.point, row.relPoint, row.x, row.y = def.Point, def.Point, def.X, def.Y
    end
    skin.Point, skin.relPoint, skin.X, skin.Y = def.Point, def.Point, def.X, def.Y
    if self.settings then
        for _, key in ipairs(self.opts.keys or {}) do
            self.settings:Reset(self.opts.module, key)
        end
    end
    self:SizeChanged()
    self:ApplyPosition()
end

function Frame:SetLocked(on)
    on = not not on
    self.cfg.locked = on
    self:EnableMove(self._move)
    self:ApplyMouse()
    if self._pubLock then return end
    local module, key = self.opts and self.opts.module, self.opts and self.opts.lockKey
    if self.settings and module and key and self.settings.Get
        and self.settings:Get(module, "Lock") ~= on then
        self._pubLock = true
        self.settings:Set(module, "Lock", on)
        self._pubLock = nil
    end
end

-- -------------------------------------------------------------------- size --

function Frame:SetSize(w, h)
    if type(w) ~= "number" or type(h) ~= "number" then return end
    self.skin.Width, self.skin.Height = w, h
    self:SizeChanged()
end

function Frame:SetWidth(w)
    if type(w) ~= "number" then return end
    self.skin.Width = w
    self:SizeChanged()
end

--- The `<Name>Height` keys drive the SECOND LINE bar height (the original's
--- SoulstoneHeight/SummonHeight are the bar heights,
--- Forte_Soulstone.lua:671, Forte_Summon.lua:587), not the header.
function Frame:SetRowHeight(h)
    if type(h) ~= "number" then return end
    self.skin.RowHeight = h
    self:SizeChanged()
end

--- The `<Name>Space` key: the row spacing of the bar list
--- (FWL.BAR_SPACING -> HealthstoneSpace, Forte_Healthstone.lua:300; the
--- row's own law is `SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -Space)`,
--- Forte_Healthstone.lua:296-301, so the gap between rows IS this number).
--- It rides the plate height (`_PlateHeight`'s step) and every row anchor.
function Frame:SetRowSpace(n)
    if type(n) ~= "number" then return end
    if n < 0 then n = 0 end
    self.skin.RowSpace = n
    -- Rows built before this keystroke keep the law they were built under
    -- (ExtraRow: `RowY - i*(RowHeight+RowSpace)`); re-anchor them so the
    -- spacing applies live (the row's law is the file's, :793/:830).
    if self.extraRows and self.body then
        local s = self.skin
        for i, e in ipairs(self.extraRows) do
            if e.row then
                e.row:ClearAllPoints()
                e.row:SetPoint("TOPLEFT", self.body, "TOPLEFT",
                    s.RowX, s.RowY - i * (s.RowHeight + s.RowSpace))
            end
        end
    end
    self:SizeChanged()
end

--- `<Name>Expand` (FWL.EXPAND_UP, Forte_Core.lua:243: "Determines if the
--- bar lists should be expanded upwards or downwards"): the bar list grows
--- UP from the anchor point instead of hanging below it. The 2012 panel
--- builds the list with `b:SetPoint("TOPLEFT", a, "TOPLEFT", 0,
--- -(HEADER_H + ROW_H))` growing down (Forte_Soulstone.lua:60-120 law);
--- expanding up is the same list with its BOTTOM edge pinned to the plate's
--- top, so the plate's header stays put and the rows stack above it.
function Frame:SetExpandUp(on)
    on = not not on
    if on == self._expandUp then return end
    self._expandUp = on
    self:_LayoutBody()
end

--- The body's one anchor, which is the whole of the expand law: down = the
--- body's TOPLEFT at the header's TOPLEFT (Forte_Soulstone.xml:202-208),
--- up = the body's BOTTOMLEFT pinned to the header's TOPLEFT, the list
--- growing over the space above the plate.
function Frame:_LayoutBody()
    if not self.body or not self.anchor then return end
    self.body:ClearAllPoints()
    if self._expandUp then
        self.body:SetPoint("BOTTOMLEFT", self.anchor, "TOPLEFT", 0, 0)
    else
        self.body:SetPoint("TOPLEFT", self.anchor, "TOPLEFT", 0, 0)
    end
end

--- `<Name>Details` (FWL.SHOW_BARS, Forte_Core.lua:274: "Show the bars. You
--- can hide them in case you only want to see the information on the
--- header."): the gate lives with the VIEW that owns the row run (the spy
--- law is `Settings.HealthstoneDetails and … and i <= hs.rows`,
--- Forte_Healthstone.lua:143), so the frame only remembers the switch and
--- answers `BarsWanted()`.
function Frame:SetShowBars(on)
    self._showBars = not not on
end

function Frame:BarsWanted()
    return self._showBars ~= false
end

--- `<Name>DetailsAuto` (FWL.AUTO_MINIMIZE, Forte_Core.lua:272: "automatically
--- hide the bars when not in a party or raid"). The view pairs it with
--- `BarsGrouped()`: the original's draw law is
--- `Details and (not DetailsAuto or STATES.GROUPED)`
--- (Forte_Healthstone.lua:143, Forte_Summon.lua:617).
function Frame:SetAutoMinimize(on)
    self._autoMin = not not on
end

--- The bars' show law, the two switches resolved: the original's
--- `Details and (not DetailsAuto or GROUPED)` verbatim in shape.
function Frame:BarsShownFor(grouped)
    if not self:BarsWanted() then return false end
    if self._autoMin and not grouped then return false end
    return true
end

--- The spy-bar colour ramp: the original's `ColorVal(v, i)`
--- (Forte_Healthstone.lua:104-111) mixes the row's value between a MIN and a
--- MAX colour -- `FW:MixColors` (Forte_Core.lua:2080-2084): `v == 0` is the
--- MIN colour, `v == 1` the MAX. Two ramps per plate: `main` (the Total bar)
--- and `unknown` (the No-info bar), keyed off the same key pair.
function Frame:SetColorRamp(which, lo, hi)
    if type(lo) ~= "table" or type(hi) ~= "table" then return end
    self._ramps = self._ramps or {}
    self._ramps[which] = { lo = lo, hi = hi }
    if which == "main" then self._ramp = self._ramps.main end
    self:RepaintRamps()
end

--- `FW:MixColors` verbatim (the clamp, then the per-channel lerp).
function Frame.MixColor(v, c1, c2)
    if v < 0 then v = 0 elseif v > 1 then v = 1 end
    return c1[1] * (1 - v) + c2[1] * v,
        c1[2] * (1 - v) + c2[2] * v,
        c1[3] * (1 - v) + c2[3] * v
end

--- Paint one bar pair (fill + its 0.5 Back, Forte_Healthstone.lua:149-150)
--- from a ramp at the bar's value. No ramp -> no touch: the plate keeps the
--- flat BarColor law the shared `BarColor` key drives.
function Frame:PaintRamp(fill, back, ramp, v)
    if not ramp or not fill then return end
    local r, g, b = Frame.MixColor(v or 0, ramp.lo, ramp.hi)
    fill:SetVertexColor(r, g, b, ramp.lo[4] or 1)
    if back then back:SetVertexColor(r, g, b, 0.5) end
end

--- Re-run the ramps over the bars at their current fractions (a colour key
--- changing must reach the bars that are already drawn).
function Frame:RepaintRamps()
    self:PaintRamp(self.fill, self.rowBack, self._ramps and self._ramps.main,
        self._fillFrac or 0)
    if self.extraRows then
        for _, e in ipairs(self.extraRows) do
            self:PaintRamp(e.fill, e.back,
                self._ramps and (self._ramps.unknown or self._ramps.main),
                e.frac or 0)
        end
    end
end

--- Every sized part follows the plate: the header, the body, the plate wash,
--- the second-line bar and fill (at its current fraction) and the frame's
--- own hook.
function Frame:SizeChanged()
    if not self.anchor then return end
    local s = self.skin
    local plateH = self:_PlateHeight()
    self.anchor:SetSize(s.Width, s.Height)
    if self.body then
        self.body:SetSize(s.Width, plateH)
    end
    if self.plate then
        self.plate:SetSize(s.Width - 2 * s.Inset, plateH - 2 * s.Inset)
    end
    local rowW = s.Width - 2 * s.Border
    if self.row then
        self.row:SetSize(rowW, s.RowHeight)
    end
    self.fillBarW = rowW
    if self.fill then
        self.fill:SetSize(self._fillW or 0, s.RowHeight)
    end
    -- The spy rows ride the same geometry (the ExtraRow law above).
    if self.extraRows then
        for i, e in ipairs(self.extraRows) do
            e.row:SetPoint("TOPLEFT", self.body, "TOPLEFT",
                s.RowX, s.RowY - i * (s.RowHeight + s.RowSpace))
            e.row:SetSize(rowW, s.RowHeight)
            e.fill:SetSize(e.fillW or 0, s.RowHeight)
        end
    end
    if self.SizeChangedHook then self:SizeChangedHook() end
end

--- Show/hide the second line and grow/shrink the plate with it
--- (Forte_Soulstone.lua:235: the backdrop height rides the row count).
function Frame:SetRowShown(on)
    on = not not on
    if on == self._rowShown then return end
    self._rowShown = on
    if self.row then
        if on then self.row:Show() else self.row:Hide() end
    end
    self:SizeChanged()
end

-- ------------------------------------------------------------- spy rows -----

--- One stacked spy row (H6): the original's bar run
--- `FWHSBar(i):SetPoint("TOPLEFT", FWHSBar(i-1), "BOTTOMLEFT", 0, -Space)`
--- (Forte_Healthstone.lua:296-301) — every row sits RowHeight+RowSpace below
--- the last, the base row (row 0) is the first. Built lazily; the row is a
--- child of the body like the base row, its bar art the same pair
--- (Back at alpha 0.5 + the fill), its labels the base row's font pair
--- (`_NewRowFont` rides the font registry).
function Frame:ExtraRow(i)
    if not self.extraRows then self.extraRows = {} end
    local e = self.extraRows[i]
    if e then return e end
    if not self.body then return nil end
    local s = self.skin
    local row = CreateFrame("Frame", nil, self.body)
    row:SetPoint("TOPLEFT", self.body, "TOPLEFT",
        s.RowX, s.RowY - i * (s.RowHeight + s.RowSpace))
    row:SetSize(s.Width - 2 * s.Border, s.RowHeight)
    row:EnableMouse(false)
    row:SetClipsChildren(false)
    local c = s.BarColor
    local back = row:CreateTexture()
    back:SetTexture(s.BarTexture)
    back:SetAllPoints(row)
    back:SetDrawLayer("BACKGROUND")
    back:SetVertexColor(c[1], c[2], c[3], 0.5)
    local fill = row:CreateTexture()
    fill:SetTexture(s.BarTexture)
    fill:SetPoint("LEFT", row, "LEFT", 0, 0)
    fill:SetSize(0, s.RowHeight)
    fill:SetDrawLayer("OVERLAY")
    fill:SetVertexColor(c[1], c[2], c[3], c[4])
    local e2 = { row = row, back = back, fill = fill, shown = false,
        frac = nil, name = nil, time = nil }
    e2.timeFS = self:_NewRowFont("RIGHT", row)
    e2.nameFS = self:_NewRowFont("CENTER", row)
    e2.timeFS:Hide()
    e2.nameFS:Hide()
    row:Hide()
    self.extraRows[i] = e2
    return e2
end

--- Show rows 1..n, hide the rest, and grow the plate with the count (the
--- original's backdrop height rides the row count, Forte_Soulstone.lua:235
--- with Forte_Healthstone.lua:204-208).
function Frame:SetExtraRowsShown(n)
    n = n or 0
    if n < 0 then n = 0 end
    if n == self._extraShown then return end
    self._extraShown = n
    for i = 1, math.max(n, self._extraRowsBuilt or 0) do
        local e = self.extraRows and self.extraRows[i]
        if e then
            e.shown = i <= n
            if e.shown then
                e.row:Show()
                if e.name ~= nil and e.name ~= "" then e.nameFS:Show() end
                if e.time ~= nil and e.time ~= "" then e.timeFS:Show() end
            else
                e.row:Hide()
                e.nameFS:Hide()
                e.timeFS:Hide()
            end
        end
    end
    self._extraRowsBuilt = math.max(self._extraRowsBuilt or 0,
        # (self.extraRows or {}))
    self:SizeChanged()
end

--- Write one spy row's texts (dirty-checked; the plate law's idiom).
function Frame:SetExtraRowText(e, name, time)
    if not e then return end
    name = name ~= nil and tostring(name) or ""
    time = time ~= nil and tostring(time) or ""
    if name ~= e.name then
        e.name = name
        e.nameFS:SetText(name)
        if e.shown then
            if name ~= "" then e.nameFS:Show() else e.nameFS:Hide() end
        end
    end
    if time ~= e.time then
        e.time = time
        e.timeFS:SetText(time)
        if e.shown then
            if time ~= "" then e.timeFS:Show() else e.timeFS:Hide() end
        end
    end
end

--- One spy row's bar fraction (the StatusBar value of the original's row,
--- HS_DrawHealthstone's `Bar:SetValue(val)`, Forte_Healthstone.lua:148).
function Frame:SetExtraRowFraction(e, f)
    if not e or not e.fill then return end
    if type(f) ~= "number" then f = 0 end
    if f < 0 then f = 0 elseif f > 1 then f = 1 end
    if f == e.frac then return end
    e.frac = f
    local w = (self.fillBarW
        or (self.skin.Width - 2 * self.skin.Border)) * f
    e.fillW = w
    e.fill:SetSize(w, self.skin.RowHeight)
    self:PaintRamp(e.fill, e.back,
        self._ramps and (self._ramps.unknown or self._ramps.main), f)
end

--- The fill's width for a fraction (0..1) of the second-line bar.
function Frame:SetFillFraction(f)
    if type(f) ~= "number" then f = 0 end
    if f < 0 then f = 0 elseif f > 1 then f = 1 end
    self._fillFrac = f
    if not self.fill then return end
    local w = (self.fillBarW
        or (self.skin.Width - 2 * self.skin.Border)) * f
    self._fillW = w
    self.fill:SetSize(w, self.skin.RowHeight)
    self:PaintRamp(self.fill, self.rowBack, self._ramp, f)
end

-- ------------------------------------------------------------------ colour --

--- The plate backdrop wash (Forte_Soulstone.lua:659 is its default).
function Frame:SetBgColor(col)
    if type(col) ~= "table" then return end
    local c = self.skin.BgColor
    c[1], c[2], c[3], c[4] = col[1] or 1, col[2] or 1, col[3] or 1, col[4] or 1
    if self.plate then
        self.plate:SetVertexColor(c[1], c[2], c[3], c[4])
    end
    self:_ApplyBackdrop()
end

--- The bar colour (the second-line fill + its 0.5 Back tint).
--- The bar fill colour. `key` names the key it arrived on: the frame's own
--- colour key (SoulstoneColor, SummonColor) is the specific answer and wins
--- over the General page's shared BarColor (the Reminder's shared-font law).
function Frame:SetBarColor(col, key)
    if type(col) ~= "table" then return end
    if key == "BarColor" then self._sharedBar = col else self._ownBar = col end
    local c = self.skin.BarColor
    c[1], c[2], c[3], c[4] = col[1] or 1, col[2] or 1, col[3] or 1, col[4] or 1
    self:ApplyBarColor()
end

--- The shared `Warlock.BarColor` is the icon PLATE wash: it recolours the
--- plate, never a bar fill (a plate colour can not repaint a bar).
function Frame:SetPlateOnly(col)
    if type(col) ~= "table" then return end
    local c = self.skin.BgColor
    c[1], c[2], c[3], c[4] = col[1] or 1, col[2] or 1,
        col[3] or 1, col[4] or 1
    if self.plate then
        self.plate:SetVertexColor(c[1], c[2], c[3], c[4])
    end
    self:_ApplyBackdrop()
end

--- The plate wash during a cooldown: the dim, not a colour.
function Frame:SetBarAlpha(a)
    if type(a) ~= "number" then return end
    self._plateAlpha = a
    if self.plate then self.plate:SetAlpha(a) end
end

function Frame:ApplyBarColor()
    local c = self._ownBar or self.fillBarColor
    if not c and self._sharedBar then c = self._sharedBar end
    c = c or self.skin.BarColor
    if self.fill and c then
        self.fill:SetVertexColor(c[1], c[2], c[3], c[4])
    end
    if self.rowBack and c then
        -- The bar's Back rides the fill colour at alpha 0.5
        -- (Forte_Soulstone.lua:216).
        self.rowBack:SetVertexColor(c[1], c[2], c[3], 0.5)
    end
    -- A plate that runs the spy-bar ramp (the Healthstone plate's
    -- `<Min|Max|Unknown*>Color` keys, ColorVal Forte_Healthstone.lua:104-111)
    -- owns its bar colours: the ramp re-paints over the flat answer.
    self:RepaintRamps()
end

--- The label colour, with the same own-over-shared law.
function Frame:SetTextColor(col, key)
    if type(col) ~= "table" then return end
    if key == "TextColor" then self._sharedText = col
    else self._ownText = col end
    local c = self.skin.TextColor
    c[1], c[2], c[3], c[4] = col[1] or 1, col[2] or 1, col[3] or 1, col[4] or 1
    self:ApplyTextColor()
end

function Frame:ApplyTextColor()
    local c = self._ownText or self._sharedText or self.skin.TextColor
    if type(c) ~= "table" then return end
    -- Every string the frame owns (the `_NewFont` registry): a client that
    -- re-colours a fontstring on SetFont needs the colour re-applied to all
    -- of them, not only to the one a setter happens to name.
    if self.fonts then
        for fs in pairs(self.fonts) do
            fs:SetVertexColor(c[1], c[2], c[3], c[4])
        end
    end
end

--- One label's colour (the Soulstone plate's ready look rides the Ready
--- colour, the plate's other labels ride the text colour). The font write
--- is `SetTextColor` (the Forte_Cooldown/UI/Timeline.lua:531 idiom -- on
--- this engine that is the FontString colour channel the GetTextColor read
--- answers, test_module.lua:491).
function Frame:SetStringColor(fs, c)
    if not fs or type(c) ~= "table" then return end
    fs:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
end

--- The plate's current label colour (the same answer ApplyTextColor paints).
function Frame:TextColour()
    return self._ownText or self._sharedText or self.skin.TextColor
end

function Frame:SetAlpha(a)
    if type(a) ~= "number" then return end
    self.state.alpha = a
    if self.anchor then self.anchor:SetAlpha(a) end
end

function Frame:SetScale(s)
    if type(s) ~= "number" then return end
    self.state.scale = s
    if self.anchor then self.anchor:SetScale(s) end
end

--- The eight FrameStrata names (`SetFrameStrata`,
--- SimpleFrameAPIDocumentation.lua:1293); the same eight the source's own
--- tip lists (Forte_Core/Localization.lua:441). Plain string literals.
local STRATA = { "background", "low", "medium", "high", "dialog",
    "fullscreen", "fullscreen_dialog", "tooltip" }
local function strataOrNil(value)
    if type(value) ~= "string" then return nil end
    local up = string.upper(value)
    local low = string.lower(up)
    for i = 1, #STRATA do
        if STRATA[i] == low then return up end
    end
    return nil
end

--- The Advanced page's strata row for this plate (`opts.advancedKey`:
--- `SoulstoneStrata` / `HealthstoneStrata` / `SummonStrata` /
--- `ShardStrata`). The source's per-module rows are
--- `Forte_Soulstone.lua:645`, `Forte_Healthstone.lua:316`,
--- `Forte_Summon.lua:573`, each applied by its own
--- `SetFrameStrata(FW.Settings.<Name>Strata)` (:71, :38, :67); the default
--- is the source's `Strata = "MEDIUM"` (Forte_Core.lua:2531). A name
--- outside the eight is ignored: the plate keeps the strata it has.
function Frame:SetStrata(name)
    local up = strataOrNil(name)
    if not up then return end
    self.state.strata = up
    if self.anchor and self.anchor.SetFrameStrata then
        self.anchor:SetFrameStrata(up)
    end
end

--- The stored mouse master; the lock law decides whether the frame takes the
--- mouse at all.
function Frame:SetEnableMouse(on)
    self.state.enableMouse = not not on
    self:ApplyMouse()
end

function Frame:ApplyMouse()
    if self.anchor then
        self.anchor:EnableMouse(not self.cfg.locked and self.state.enableMouse)
    end
    if self._dragFrame then
        self._dragFrame:EnableMouse(not self.cfg.locked and self._move
            and self.state.enableMouse)
        self._dragFrame:RegisterForDrag(not self.cfg.locked and self._move
            and self.state.enableMouse)
    end
end

function Frame:SetStrikethrough(on)
    on = not not on
    if on == self.state.strike then return end
    self.state.strike = on
    local strings = { self.amountFS, self.infoFS, self.nameFS, self.timeFS }
    if self.extraRows then
        for _, e in ipairs(self.extraRows) do
            strings[#strings + 1] = e.nameFS
            strings[#strings + 1] = e.timeFS
        end
    end
    for _, fs in ipairs(strings) do
        if fs and fs.SetStrikethrough then fs:SetStrikethrough(on) end
    end
end

function Frame:SetEnabled(on)
    self.state.enable = not not on
    if not self.state.enable then self:RenderIdle() end
end

function Frame:SetMasterEnabled(on)
    self.state.master = not not on
    if not self.state.master then self:RenderIdle() end
end

function Frame:Enabled()
    return self.state.master and self.state.enable
end

function Frame:SetShowTime(on)
    self.state.showTime = not not on
    self._timeKey = nil
    self:ApplyTextVisibility()
end

--- Which strings ShowTime owns. The plate law: the right label and the
--- second line's clock are the label text; the plate, the count and the
--- second line's target are the module's core readout.
function Frame:ApplyTextVisibility()
    if not self._shown then return end
    if self.amountFS then self.amountFS:Show() end
    if self.infoFS then
        if self.state.showTime then self.infoFS:Show() else self.infoFS:Hide() end
    end
    if self.nameFS and self._rowShown then self.nameFS:Show() end
    if self.timeFS then
        if self.state.showTime and self._rowShown then self.timeFS:Show()
        else self.timeFS:Hide() end
    end
end

--- The shared show/hide transition: the anchor rides the state, the strings
--- ride ShowTime. Dirty-checked: every style setter runs at most once per
--- change.
function Frame:SetShown(on)
    if not self.anchor then return end
    on = not not on
    if on == self._shown then return end
    self._shown = on
    if on then self.anchor:Show() else self.anchor:Hide() end
    self:ApplyTextVisibility()
end

--- The plate's own show answer (the mirror of SetShown -- the tests' and
--- `/fx status`' view of the plate, the anchor's Show/Hide is its effect).
function Frame:IsShown()
    return self._shown == true
end

-- ----------------------------------------------------------- the settings --

--- The frame's settings hook: one listener for its module (its `Lock`
--- included), one for the General page's shared keys. `FX.Settings` can not
--- exist while this addon's files load (Forte_Options is an OptionalDep), so
--- a frame without it is inert, exactly as Forte_Hunter/UI/Reminder.lua is.
function Frame:_HookSettings()
    self.settings = FX.Settings
    if not self.settings then return end
    -- m1 (CodeReview3): the single-registration convention (Module:244
    -- `_wired`, Window `_lockWired`, the Hunter page `wired`). Init runs on
    -- every UI:OnClassChanged("WARLOCK") -- each T4/T15 class round trip
    -- re-ran _InitViews -> Init -> _HookSettings, and FX.Settings appends
    -- listeners with no dedup, so each round trip added this frame's FOUR
    -- listeners again (unbounded growth, every Set firing all copies).
    -- The guard runs the apply-from-store pass once; a frame built while
    -- FX.Settings did not exist stays un-wired and wires on the next call.
    if self._wired then return end
    self._wired = true
    local km = {}
    for key, fn in pairs(Frame.BASE_KEYMAP) do km[key] = fn end
    if self.KEYMAP then
        for key, fn in pairs(self.KEYMAP) do km[key] = fn end
    end
    self._keymap = km
    local module = self.opts.module
    self.settings:OnChange(module, function(key, value)
        local fn = km[key]
        if fn and self[fn] then self[fn](self, value, key) end
    end)
    -- The stored values are applied once at build (the
    -- Forte_Hunter/UI/Reminder.lua idiom: a page change reaches the frame
    -- live from then on). The SHARED keys go first: a frame-specific key
    -- (`Warlock.ShardColor`) is the more specific answer and wins.
    local function apply(keys, mod, map)
        for _, key in ipairs(keys or {}) do
            local fn = map[key]
            if fn and self[fn] and self.settings.Get then
                local v = self.settings:Get(mod, key)
                if v ~= nil then self[fn](self, v, key) end
            end
        end
    end
    -- The General page's shared keys. The listener goes in unconditionally
    -- (`FX.Settings` keys listeners by module, so a module that registers
    -- after this addon is served from then on); the stored values are read
    -- only once the module exists (Forte_Options is an OptionalDep).
    local shared = self.opts.sharedModule
    local skm = self.SHARED_KEYMAP
    if shared and skm then
        self.settings:OnChange(shared, function(key, value)
            local fn = skm[key]
            if fn and self[fn] then self[fn](self, value, key) end
        end)
        if not self.settings.IsRegistered
            or self.settings:IsRegistered(shared) then
            apply({ "BarFont", "BarColor", "TextColor", "BarTextSize" },
                shared, skm)
        end
    end
    apply(self.opts.keys, module, km)
    apply({ "Lock", "Enable", "Scale", "Alpha", "EnableMouse", "ShowTime" },
        module, km)
    -- The Advanced page's shared strata key of THIS plate (the source's
    -- `<Name>Strata` row of its Advanced category: Forte_Soulstone.lua:645,
    -- Forte_Healthstone.lua:316, Forte_Summon.lua:573). One key per plate,
    -- named by the plate, applied like the shared `General` keys above.
    local akey = self.opts.advancedKey
    if akey then
        self.settings:OnChange("Advanced", function(key, value)
            if key == akey then self:SetStrata(value) end
        end)
        if not self.settings.IsRegistered
            or self.settings:IsRegistered("Advanced") then
            local v = self.settings.Get and self.settings:Get("Advanced", akey)
            if v ~= nil then self:SetStrata(v) end
        end
    end
    -- The shared lock law (mirrored from Forte_Hunter/UI/Swing.lua): the
    -- General page's Global Frame Lock (= /fx lock|unlock) and Forte_Cooldown's
    -- published Lock (its SetLocked publish IS its lock-change hook, plan m4)
    -- drive this frame's lock; the frame publishes its own back (SetLocked).
    self.settings:OnChange("General", function(key, value)
        if key == "GlobalLock" then self:SetLocked(value) end
    end)
    self.settings:OnChange("Cooldown", function(key, value)
        if key == "Lock" and not self._pubLock then self:SetLocked(value) end
    end)
    if self.settings.Get then
        local g = self.settings:Get("General", "GlobalLock")
        local c = self.settings:Get("Cooldown", "Lock")
        if g == true or c == true then self:SetLocked(true) end
    end
end

function Frame:OnEnable()
    self:_HookSettings()
end

function Frame:OnDisable()
    self:RenderIdle()
end

function Frame:OnClassChanged(class)
    if class ~= "WARLOCK" then self:RenderIdle() end
end

return Frame

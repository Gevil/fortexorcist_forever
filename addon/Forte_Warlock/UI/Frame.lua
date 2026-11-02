-- addon/Forte_Warlock/UI/Frame.lua
-- FX.Warlock.Frame: the shared base of the Warlock v1's four frames: the
-- Shard Manager, the Soulstone Tracker, the Healthstone Spy and the Summon
-- Assistant (UI/Shards.lua, UI/Soulstone.lua, UI/Healthstone.lua,
-- UI/Summon.lua). Forte_Hunter/UI/Swing.lua is the local pattern for
-- everything that is NOT Warlock-specific: the Classic skin of a small
-- anchored frame, the `FX.db` position row, the lock law and the live
-- settings seam are copied from it.
--
-- The skin law (the project's "hard-coded Classic skin, no theme picker"):
-- every colour/size starts in ONE skin table per frame (ShardsSkin,
-- SoulstoneSkin, HealthstoneSkin, SummonSkin, each extending FrameSkin); the
-- style setters below and Pages/Warlock.lua read and write ONLY the skin, so
-- a page and its frame can not drift apart. The Soulstone bar's colour is
-- `SoulstoneColor`, the original's own (the 2012 mod's
-- `SoulstoneColor = { .64, .21, .93, 1 }`, docs/warlock-tools.md), and the
-- Summon bar rides the class's summoning purple.
--
-- The position law: one row in `FX.db.warlockUI` under the frame's own key,
-- saved on every drag end (the Swing.lua `SavePosition` shape).
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

--- Everything skinnable about one of the four frames. The two plates override
--- Width/Height/Inset; the two bars override Height.
FX.Warlock.FrameSkin = {
    Width = 140, Height = 12,
    BgColor = { 0.12, 0.12, 0.12, 0.90 },          -- the plate backdrop
    BarColor = { 0.64, 0.21, 0.93, 0.85 },         -- the shared plate wash
    TextColor = { 1, 1, 1, 1 },
    TextSize = 11,
    TextFont = "Interface\\AddOns\\Forte_Core\\Fonts\\URWGothic-Book.ttf",
    Inset = 3,                                    -- the Aluminium edge inset
    Strikethrough = false,
    Scale = 1,
    Alpha = 1,
    CooldownAlpha = 0.55,                         -- a plate during a cooldown
    Locked = true,                                -- the default: no drag
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
    BarColor = "SetBarColor",
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
        "HealthstoneSize", "HealthstoneStrikethrough",
        "SummonWidth", "SummonHeight", "SummonColor", "SummonStrikethrough",
    },
    defaults = {
        Enable = true, Scale = 1, Alpha = 1, EnableMouse = true,
        Lock = true, ShowTime = true,
        ShardSize = 34, SoulstoneWidth = 140, SoulstoneHeight = 12,
        HealthstoneSize = 34, SummonWidth = 140, SummonHeight = 12,
        ShardColor = { 1, 1, 1, 1 },
        SoulstoneColor = { 0.64, 0.21, 0.93, 1 },
        SummonColor = { 0.64, 0.21, 0.93, 1 },
        ShardStrikethrough = false, SoulstoneStrikethrough = false,
        HealthstoneStrikethrough = false, SummonStrikethrough = false,
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

-- ----------------------------------------------------------------- identity --

--- `opts` = { name, dbKey, skin, size, keymap, module, lockKey, keys, tip,
--- textDy, strikes }. `name`/`dbKey` drive the frame name and the `FX.db` row.
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

--- A skinned plate texture (the Aluminium backdrop inside the frame).
function Frame:_NewPlate(w, h, inset, color)
    local t = self.anchor:CreateTexture()
    -- The skin names the plate art (the vendored Classic textures); the
    -- Aluminium backdrop is the fallback.
    t:SetTexture(self.skin.PlateTexture or (TEX .. "Aluminium"))
    t:SetPoint("CENTER", self.anchor, "CENTER", 0, 0)
    t:SetSize(w - 2 * inset, h - 2 * inset)
    t:SetDrawLayer("BACKGROUND")
    if color then t:SetVertexColor(color[1], color[2], color[3], color[4]) end
    return t
end

--- The per-view bar builder (the two timer bars); nil on a plate frame.
function Frame:_NewBar()
    return nil
end

--- A fontstring with the current font/size/colour; registered so a live font
--- change reaches every string the frame owns.
function Frame:_NewFont(dx, dy, size, justify)
    local fs = self.anchor:CreateFontString()
    fs:SetPoint("CENTER", self.anchor, "CENTER", dx or 0, dy or 0)
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

--- The frame's own label text (a bar's `Soulstone: …` / `Summoning …`; the
--- plates use `text` for the count and add their own label).
function Frame:_NewText(dy)
    local fs = self:_NewFont(0, dy, self.skin.TextSize + 1, "CENTER")
    -- Word-wrap knobs are client extras: a client whose fontstrings do not
    -- carry them keeps the single-line label.
    if fs.SetWordWraps then fs:SetWordWraps(false) end
    if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(true) end
    fs:SetText("")
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
    a:SetSize(self.skin.Width, self.skin.Height)
    a:SetScale(self.state.scale)
    a:SetAlpha(self.state.alpha)
    a:SetMovable(true)
    a:SetClipsChildren(true)
    a:SetBackdrop({
        edgeFile = self.skin.EdgeTexture or (TEX .. "Aluminium"),
        edgeSize = self.skin.Inset,
        insets = { left = self.skin.Inset, right = self.skin.Inset,
                   top = self.skin.Inset, bottom = self.skin.Inset },
        bgFile = TEX .. "Aluminium",
        bgColor = { self.skin.BgColor[1], self.skin.BgColor[2],
                    self.skin.BgColor[3], self.skin.BgColor[4] },
    })
    a:EnableMouse(not self.cfg.locked and self.state.enableMouse)
    a:Hide()
    self.anchor = a
    local plate = self:_NewPlate(self.skin.Width, self.skin.Height,
        self.skin.Inset, self.skin.BgColor)
    self.plate = plate
    self.bar = self:_NewBar()
    self.text = self:_NewText((self.opts and self.opts.textDy)
        or self.TEXT_DY)
    self:_AttachTip()
end

--- The mouse tip, while the frame has a tip and the mouse is live.
function Frame:_AttachTip()
    local tip = self.opts and self.opts.tip
    if not tip then return end
    self.tip = CreateFrame("Frame", self.anchor)
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

function Frame:SetHeight(h)
    if type(h) ~= "number" then return end
    self.skin.Height = h
    self:SizeChanged()
end

--- Every sized part follows the plate: the plate texture, the bar, the fill
--- (at its current fraction) and the frame's own hook (a plate refits its
--- icon).
function Frame:SizeChanged()
    if not self.anchor then return end
    self.anchor:SetSize(self.skin.Width, self.skin.Height)
    local ins = self.skin.Inset
    if self.plate then
        self.plate:SetSize(self.skin.Width - 2 * ins,
            self.skin.Height - 2 * ins)
    end
    local barW = self.skin.Width - 2 * ins
    local barH = self.barHeight or (self.skin.Height - 2 * ins)
    if self.bar then
        self.bar:SetSize(barW, barH)
        self.fillBarW = barW
        if self.fill then
            self.fill:SetSize(self._fillW or barW, barH)
        end
    end
    if self.SizeChangedHook then self:SizeChangedHook() end
end

--- The fill's width for a fraction (0..1) of the bar.
function Frame:SetFillFraction(f)
    if type(f) ~= "number" then f = 0 end
    if f < 0 then f = 0 elseif f > 1 then f = 1 end
    self._fillFrac = f
    if not self.fill then return end
    local w = (self.fillBarW or (self.skin.Width - 2 * self.skin.Inset)) * f
    self._fillW = w
    self.fill:SetSize(w, self.barHeight
        or (self.skin.Height - 2 * self.skin.Inset))
end

-- ------------------------------------------------------------------ colour --

--- The plate backdrop wash.
function Frame:SetBgColor(col)
    if type(col) ~= "table" then return end
    local c = self.skin.BgColor
    c[1], c[2], c[3], c[4] = col[1] or 1, col[2] or 1, col[3] or 1, col[4] or 1
    if self.plate then
        self.plate:SetVertexColor(c[1], c[2], c[3], c[4])
    end
end

--- The bar fill colour (the two timer bars); a plate frame has no fill.
--- The bar fill colour. `key` names the key it arrived on: the frame's own
--- colour key (SoulstoneColor, SummonColor) is the specific answer and wins
--- over the General page's shared BarColor (the Reminder's shared font law).
function Frame:SetBarColor(col, key)
    if type(col) ~= "table" then return end
    if key == "BarColor" then self._sharedBar = col else self._ownBar = col end
    local c = self.skin.BarColor
    c[1], c[2], c[3], c[4] = col[1] or 1, col[2] or 1, col[3] or 1, col[4] or 1
    self:ApplyBarColor()
end

--- The shared `Warlock.BarColor` is the icon PLATE wash: only a frame with a
--- plate and no fill consumes it, so a plate colour can not repaint a bar.
function Frame:SetPlateOnly(col)
    if self.fill then return end
    local c = self.skin.BarColor
    c[1], c[2], c[3], c[4] = col and col[1] or 1, col and col[2] or 1,
        col and col[3] or 1, col and col[4] or 1
    if self.plate then
        self.plate:SetVertexColor(c[1], c[2], c[3], c[4])
    end
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
    if self.text then
        self.text:SetVertexColor(c[1], c[2], c[3], c[4])
    end
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
    local strings = { self.text, self.sourceFS, self.cdText }
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

--- Which strings ShowTime owns. The base (bars): the frame's one label text.
function Frame:ApplyTextVisibility()
    if not self._shown then return end
    if self.text then
        if self.state.showTime then self.text:Show() else self.text:Hide() end
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

-- ----------------------------------------------------------- the settings --

--- The frame's settings hook: one listener for its module (its `Lock`
--- included), one for the General page's shared keys. `FX.Settings` can not
--- exist while this addon's files load (Forte_Options is an OptionalDep), so
--- a frame without it is inert, exactly as Forte_Hunter/UI/Reminder.lua is.
function Frame:_HookSettings()
    self.settings = FX.Settings
    if not self.settings then return end
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

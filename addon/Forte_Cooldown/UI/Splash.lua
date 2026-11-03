-- Forte_Cooldown/UI/Splash.lua
-- The Secondary Splash (spec CD-28): a SEPARATE, draggable window that runs
-- a ready cooldown's icon through the source's bell over the bar's 1.0 s
-- expiry window -- the icon fades IN then OUT while it grows to
-- 32*SecondSplashMax mid-window. Registered as FX.Cooldown.Splash; the
-- Module fires it from the ready-pop loop (Module:ProcessReadyPops) -- the
-- pop carries (name, now, texPath, cooldownDuration, category); the
-- bell window is FIXED, the duration rides the pop only as a receipt.
--
-- Source law (/tmp/fxref/Forte_Cooldown/Forte_Cooldown.lua, the Splash
-- frame's Draw :1008-1051):
--  * the frame is its own instance with its own defaults and option tree
--    (CD_NewSplashFrame :991-1071, instance registration :1540-1552);
--  * base icon 32 px, the frame sized 32*scale (:1028, :1043-44, :1061-62);
--  * the icon pool centres every icon on the frame (:967);
--  * the pop's curve is the BELL over the SAME 1.0 s expiry window the
--    bar's pulse uses -- t14 is set to 1 at the ready (:353-354) and the
--    render loop decays it -1/s (:632-635):
--      s1 = 0.5 - t14; s1 = 1 - 4*s1*s1     -- 0 at t14=1, 1 at 0.5, 0 at 0
--      icon alpha = s1 * s.alpha            (:1024-1027)
--      size  = 32*(scale + (SSM-scale)*s1)  (:1027)
--    -- the icon fades IN then OUT and peaks at 32*SecondSplashMax
--    mid-window; the Update frame alpha is s.alpha (:1060-62), so the
--    EFFECTIVE on-screen alpha is the source's product s1*s.alpha^2
--    (peak 0.49 at the shipped defaults);
--  * the unlocked-idle placeholder (:1040-1049): enabled, NOT locked and no
--    live splash (i==1) shows one icon at 32*scale with icon alpha
--    s.alpha (:1042-46, effective s.alpha^2 = 0.49) and the spark at
--    32*scale*2.2; locked+idle draws nothing;
--  * the backdrop plate: the bar's Backdrop texture at BgColor[4]*0.7
--    (CD-27; BgColor default {0,0,0,0.50} :1843, plate alpha 0.35);
--  * SplashGlow crops the icon to 0.133..0.867 and shows the ADD-blend
--    Spark2 overlay at 2.2x the icon, tinted FixIntensity(category)
--    (:978-988, :1031-1034); off = full crop, spark hidden (:983-984);
--  * SplashMax caps the simultaneous splashes at 8 (spec CD-28; the shipped
--    source caps it through the fixed NUM_SPLASH pool, CD-26);
--  * the defaults: Enable = FALSE (:1869 -- off by default), SecondSplashMax
--    = 4 (:1870), SplashGlow = true (:1871), alpha = 0.7 (:1872),
--    scale = 2 (:1873). The option tree (:1770-1780) is the page
--    Forte_Options/Pages/Splash.lua.
--  * CD-29 (secure click-to-cast on the icons) is OUT of scope: the
--    protected attributes are inert for an insecure frame in combat.
--
-- Frame law (Forte_Cooldown/UI/Timeline.lua + Forte_Hunter/UI/Swing.lua):
-- the frame is created inside Init (reached from OnEnable at PLAYER_LOGIN),
-- every style setter is dirty-checked, the slot pool only grows, and the
-- animation rides the anchor's OnUpdate ONLY while it is shown -- a hidden
-- frame never receives OnUpdate, so the first curve frame renders
-- SYNCHRONOUSLY inside OnReady, before the ticker takes over.
--
-- Lock law (m4): the LIVE lock state of this frame is the truth; SetLocked
-- publishes it into Splash.Lock. `/fx lock|unlock` moves
-- Cooldown.Lock + General.GlobalLock and this frame MIRRORS both keys
-- through FX.Settings:OnChange (the Forte_Hunter swing's seam) -- so the
-- splash window locks and unlocks with the bars without Forte_Core knowing
-- it exists. Position lives in FX.db.cooldownSplash.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
FX.Cooldown = FX.Cooldown or {}

local D = {}
FX.Cooldown.Splash = D

local TEX = "Interface\\AddOns\\Forte_Core\\Textures\\"

-- Vendored values, ForteXorcist v1.980.8 FW.InstanceDefault.Splash
-- (:1868-1874), GPL-3.0, see addon/Forte_Core/ATTRIBUTION.md.
FX.Cooldown.SplashSkin = {
    Enable = false,            -- :1869 (the original's default: OFF)
    SecondSplashMax = 4,       -- :1870 (the bell's peak: peak edge = 32*this)
    SplashMax = 8,             -- CD-28 (simultaneous splashes cap)
    SplashGlow = true,         -- :1871
    Alpha = 0.7,               -- :1872
    Scale = 2,                 -- :1873
    IconBase = 32,             -- the base icon edge, :1028
    Window = 1.0,              -- the bell's window: t14 decays 1 -> 0 at 1/s (:353-54, :632-35)
    SparkScale = 2.2,          -- spark size / icon size (:1031-32)
    Spark = TEX .. "Spark2",   -- the ADD-blend glow (:975)
    PlaceholderIcon = "Interface\\Icons\\Spell_Shadow_LastingAfflictions",
                               -- NewIcon's standing texture (:970)
    BackdropBG = TEX .. "Background",  -- the plate texture (:1860 Backdrop[1])
    PlateAlpha = 0.7,          -- BgColor[4] x THIS (:1843, CD-27)
    Crop = 0.133,              -- the glow texcoord crop (:980)
}
local S = FX.Cooldown.SplashSkin

local DEFAULT = { point = "CENTER", relPoint = "CENTER", x = 0, y = 140,
    locked = true }
local TICK_SECONDS = 0.1       -- the 10 Hz render rate (the Swing's law)

-- -------------------------------------------------------------- persistence --
local fallbackCfg
local function config()
    if FX.db then
        FX.db.cooldownSplash = FX.db.cooldownSplash or {}
        return FX.db.cooldownSplash
    end
    fallbackCfg = fallbackCfg or {}
    return fallbackCfg
end

local function cfgDefaults(cfg)
    for k, v in pairs(DEFAULT) do
        if cfg[k] == nil then cfg[k] = v end
    end
    return cfg
end

--- FW:FixIntensity, verbatim (Forte_Core.lua :796-805, the Timeline's copy):
--- the spark of a splash rides the category colour lifted toward white.
local function fixIntensity(r, g, b)
    local largest = math.max(math.max(r, g), b)
    if largest == 1 then
        return 0.7 * r + 0.3, 0.7 * g + 0.3, 0.7 * b + 0.3
    elseif largest > 0 and largest < 1 then
        return 0.7 * r / largest + 0.3, 0.7 * g / largest + 0.3, 0.7 * b / largest + 0.3
    end
    return 1, 1, 1
end

--- The category colour: the LIVE TimelineSkin table (the Cooldown page's
--- SetCategoryColor writes it), unknown categories falling back to Spell
--- (the Timeline's rowColor law).
local function categoryColor(category)
    local skin = FX.Cooldown and FX.Cooldown.TimelineSkin
    local colors = skin and skin.Colors
    return (colors and colors[category]) or (colors and colors.Spell)
    or { 1, 0.5, 0 }
end

--- The plate colour: the bar's BgColor at BgColor[4] * 0.7 (CD-27).
local function plateColor()
    local skin = FX.Cooldown and FX.Cooldown.TimelineSkin
    local bg = skin and skin.BgColor
    return (bg and bg[1]) or 0, (bg and bg[2]) or 0, (bg and bg[3]) or 0,
        ((bg and bg[4]) or 0.5) * S.PlateAlpha
end

-- ------------------------------------------------------------------- curve --
--- The normal icon size: base 32 x scale (the frame's own size,
--- :1028/:1043-44).
function D:NormalSize()
    return S.IconBase * S.Scale
end

--- The source's bell (Draw :1024-1025): `s1 = 1 - 4*(0.5 - t14)^2` -- 0 at
--- t14 = 1 (the pop's spawn frame), 1 at t14 = 0.5 (the peak), 0 at t14 = 0
--- (the window's end). t14 is the bar's expiry counter, set to 1 at the
--- ready (:353-54) and decayed -1/s (:632-35).
function D:Bell(t14)
    if t14 > 1 then t14 = 1 elseif t14 < 0 then t14 = 0 end
    local d = 0.5 - t14
    return 1 - 4 * d * d
end

--- The icon size on the bell (:1027): 32*(scale + (SSM - scale)*s1) -- the
--- 32*scale normal at the window's ends, 32*SecondSplashMax at the peak.
function D:BellSize(t14)
    return S.IconBase * (S.Scale + (S.SecondSplashMax - S.Scale) * self:Bell(t14))
end

--- t14 of a pop slot at clock `now`: 1 at the pop, 0 S.Window seconds
--- later (the source's cd[14] decay).
function D:SlotT14(slot, now)
    return 1 - (now - slot.startAt) / S.Window
end

-- -------------------------------------------------------------------- init --
function D:Init()
    if self.anchor then return end
    self.cfg = cfgDefaults(config())
    self._icons = self._icons or {}
    self._activeCount = self._activeCount or 0

    local f = CreateFrame("Frame", "ForteXorcistSplashAnchor", UIParent)
    f:SetSize(self:NormalSize(), self:NormalSize())
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    -- CD-30 (CodeReview6 M3: the wave-6 "right-click-to-options on every
    -- module frame" law -- the window is a module frame with its own page
    -- (Pages/Splash.lua, id `Splash`) and its mouse is live by the lock
    -- law, so its right release must reach the seam). The press stamp
    -- rides OnMouseDown (any button) as the source wires it
    -- (`<OnMouseDown>FW:StartMoving(self,button)`, Forte_Soulstone.xml
    -- :189-191): the engine fires OnDragStart only for the registered
    -- drag button, so a stamp riding only OnDragStart leaves the
    -- right-press unstamped and every later right-click reads against a
    -- stale stamp (M2's shape).
    f:SetScript("OnMouseDown", function() self:_StampPress() end)
    f:SetScript("OnDragStart", function(fr, button)
        -- The stamp FIRST, the lock check second (FW:StartMoving's order,
        -- Forte_Core/Options.lua:650-651): the lock gates the DRAG -- the
        -- row label is "Lock (disable dragging)" -- and never the mouse.
        self:_StampPress()
        if self.cfg and self.cfg.locked then return end
        fr:StartMoving(button)
    end)
    f:SetScript("OnDragStop", function(fr)
        fr:StopMovingOrSizing()
        self:SavePosition(fr)
    end)
    -- The release: (frame, mouseButtonName, upInside) per the catalog's
    -- OnMouseUp row (m2, CodeReview6).
    f:SetScript("OnMouseUp",
        function(_, button, upInside) self:OnMouseUp(button, upInside) end)

    -- The drag-handle label (the Timeline's title law: visible only while
    -- unlocked).
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetText("Forte Splash")
    title:SetTextColor(1, 1, 1, 1)
    title:SetPoint("BOTTOM", f, "TOP", 0, 2)

    self.anchor, self.title = f, title
    self._shown, self._ticking, self._acc = false, false, 0

    self:_WireSettings()
    self:ApplyStoredSettings()
    self:ApplyPosition()
    f:SetAlpha(S.Alpha)
    self:SetLocked(self.cfg.locked and true or false)
    -- The idle face (:1040-49): SetLocked's pump already opened an
    -- enabled, UNLOCKED window on its placeholder; a disabled/locked one
    -- starts hidden (a hidden frame receives no OnUpdate -- the
    -- 2026-11-02 uiforever law).
    if not self._shown then self.anchor:Hide() end
end

--- The module enable (FX.RegisterModule -> PLAYER_LOGIN).
function D:OnEnable()
    self:Init()
end

-- -------------------------------------------------------------- position --
function D:ApplyPosition()
    if not self.anchor then return end
    local cfg = self.cfg
    self.anchor:ClearAllPoints()
    self.anchor:SetPoint(cfg.point, UIParent, cfg.relPoint, cfg.x, cfg.y)
end

function D:SavePosition(f)
    f = f or self.anchor
    if not f then return end
    local point, _, relPoint, x, y = f:GetPoint()
    if not point then return end
    local cfg = self.cfg
    cfg.point, cfg.relPoint, cfg.x, cfg.y = point, relPoint, x, y
end

function D:Reset()
    local cfg = self.cfg
    cfg.point, cfg.relPoint, cfg.x, cfg.y =
        DEFAULT.point, DEFAULT.relPoint, DEFAULT.x, DEFAULT.y
    self:ApplyPosition()
end

--- Locked = NO drag (the lock law: the source's lock gates the dragging
--- only, the label is "Lock (disable dragging)", the frame's mouse stays
--- enabled so releases keep firing) + the title hidden; the publish to
--- Splash.Lock is the m4 law (the swing's shape).
function D:SetLocked(locked)
    locked = not not locked
    if self.cfg then self.cfg.locked = locked end
    local st = FX.Settings
    if st and st.IsRegistered and st:IsRegistered("Splash")
        and st:Get("Splash", "Lock") ~= locked then
        st:Set("Splash", "Lock", locked)
    end
    if not self.anchor then return end
    self.anchor:SetMovable(not locked)
    self.anchor:EnableMouse(true)
    if locked then self.title:Hide() else self.title:Show() end
    -- The idle face rides the lock (:1040 `not s.lock`): unlocking an
    -- enabled, idle window shows the placeholder; locking it hides the
    -- face (a live splash keeps the window shown -- Draw keeps drawing).
    self:Update(GetTime())
end

-- ------------------------------------------------------- right-click seam --
--- FW:StartMoving's press stamp (Forte_Core/Options.lua:649-656): the cursor
--- position at the moment of every press (the Cooldown bar's `_StampPress`,
--- Forte_Cooldown/UI/Timeline.lua, the same seam).
function D:_StampPress()
    if type(GetCursorPosition) ~= "function" then return end
    local x, y = GetCursorPosition()
    self._downX, self._downY = x, y
end

--- FW:Moved() (Forte_Core/Options.lua:659-662): did the cursor travel
--- between press and release? A drag must never open the options window
--- (CD-30). No cursor read (no press stamp, no cursor on this client) means
--- no travel, i.e. a click.
function D:Moved()
    if type(GetCursorPosition) ~= "function" then return false end
    local dx, dy = self._downX, self._downY
    if dx == nil or dy == nil then return false end
    local x, y = GetCursorPosition()
    if x == nil or y == nil then return false end
    return x ~= dx or y ~= dy
end

--- CD-30 on this window (CodeReview6 M3: the wave-6 "right-click-to-options
--- on every module frame" law, the Timeline's shape): a right-button
--- release opens the options window on the Secondary Splash page
--- (`O:RegisterPage{ id = "Splash" }`, Pages/Splash.lua); a release that
--- followed a drag is dropped by the Moved guard, and the release consumes
--- the press stamp on every exit (M2: the stamp is one pair's, never a
--- later release's).
function D:OnMouseUp(button, upInside)
    if button ~= "RightButton" then
        self._downX, self._downY = nil, nil
        return
    end
    local moved = self:Moved()
    self._downX, self._downY = nil, nil
    if moved then return end
    -- m2 (CodeReview6): a release the client reports OUTSIDE the frame
    -- (the catalog's 3rd OnMouseUp slot) is not a click on it; nil (a
    -- hand-driven script) = treated as inside.
    if upInside == false then return end
    -- `RightClickOptions` (General page, default true): off = the window
    -- is silent, the release is consumed, nothing opens.
    local st = FX.Settings
    if st and st.IsRegistered and st:IsRegistered("General")
        and st:Get("General", "RightClickOptions") == false then
        return
    end
    local O = FX.Options
    if not O or not O.Open then return end
    pcall(O.Open, O, "Splash")
end

-- ------------------------------------------------------------------ pool --
--- One splash slot: the backdrop plate (behind), the icon, the ADD-blend
--- spark (the source's icon = frame + texture + Spark2, :962-990). The pool
--- only grows, capped by SplashMax.
function D:_NewIcon()
    local frame = CreateFrame("Frame", nil, self.anchor)
    frame:SetPoint("CENTER", self.anchor, "CENTER", 0, 0)

    local plate = frame:CreateTexture(nil, "ARTWORK")
    plate:SetTexture(S.BackdropBG)
    plate:SetPoint("CENTER", frame, "CENTER", 0, 0)

    local tex = frame:CreateTexture(nil, "ARTWORK")
    tex:SetTexture(S.PlaceholderIcon)  -- NewIcon's standing icon (:970)
    tex:SetPoint("CENTER", frame, "CENTER", 0, 0)
    tex:SetVertexColor(1, 1, 1, 1)   -- the icon is untinted (:966-970)

    local spark = frame:CreateTexture(nil, "OVERLAY")
    spark:SetTexture(S.Spark)
    spark:SetBlendMode("ADD")        -- :975
    spark:SetPoint("CENTER", frame, "CENTER", 0, 0)

    -- The plate rides the bar's BgColor (CD-27); a pop re-applies it, the
    -- idle pump keeps it current through a BgColor change.
    local pr, pg, pb, pa = plateColor()
    plate:SetVertexColor(pr, pg, pb, pa)

    frame:Hide()
    return { frame = frame, plate = plate, tex = tex, spark = spark,
        active = false, placeholder = false, _size = nil, _alpha = nil,
        _glow = nil }
end

--- A free slot, or nil at the SplashMax cap (CD-28: at most SplashMax
--- simultaneous -- an over-cap pop is simply dropped).
function D:_AcquireIcon()
    local pool = self._icons
    for i = 1, #pool do
        if not pool[i].active then return pool[i] end
    end
    if #pool >= S.SplashMax then return nil end
    local slot = self:_NewIcon()
    pool[#pool + 1] = slot
    return slot
end

--- The SplashGlow law for one slot (:978-988): crop + spark. Dirty-checked
--- by the _glow key so a live toggle re-applies exactly once per slot.
function D:_ApplyGlow(slot)
    local glow = not not S.SplashGlow
    if slot._glow == glow then return end
    slot._glow = glow
    if glow then
        slot.tex:SetTexCoord(S.Crop, 1 - S.Crop, S.Crop, 1 - S.Crop)
        slot.spark:Show()
    else
        slot.tex:SetTexCoord(0, 1, 0, 1)
        slot.spark:Hide()
    end
end

function D:_Release(slot)
    if not slot.active then return end
    if slot == self._placeholder then self._placeholder = nil end
    slot.active = false
    slot.name, slot.placeholder = nil, nil
    slot.frame:Hide()
    self._activeCount = self._activeCount - 1
end

function D:_ReleaseIdle()
    if self._placeholder then self:_Release(self._placeholder) end
end

--- The placeholder's geometry (:1042-46): the 32*scale icon, the spark at
--- 2.2x, the ICON alpha at s.alpha (:1043) inside the window frame's own
--- s.alpha (:1060) -- the source's product, effective s.alpha^2.
--- Dirty-checked: the 10 Hz idle pump costs nothing until Scale /
--- SecondSplashMax / Alpha move.
function D:_RenderIdle(slot)
    local size = self:NormalSize()
    local alpha = S.Alpha
    if slot._size == size and slot._alpha == alpha then return end
    slot._size, slot._alpha = size, alpha
    slot.frame:SetAlpha(alpha)
    slot.tex:SetSize(size, size)
    local plate = size + 6                    -- the backdrop inset x2 (:1865)
    slot.plate:SetSize(plate, plate)
    slot.spark:SetSize(size * S.SparkScale, size * S.SparkScale)
end

--- True while a live SPLASH (never the placeholder) owns a slot: the
--- source's `i == 1` gate (:1040) only passes when the Draw loop drew no
--- splash into the row.
local function liveSplashes(self)
    local pool = self._icons
    for i = 1, #pool do
        local slot = pool[i]
        if slot.active and not slot.placeholder then return true end
    end
    return false
end

--- The idle face of the window, the source's :1040-1049 branch:
--- enabled + UNLOCKED + no live splash shows the one placeholder icon;
--- enabled + LOCKED + idle draws nothing -- the window hides (the rebuild
--- keeps a hidden frame ticker-less, so "draws nothing" = hidden);
--- disabled is hidden by SetEnabled. Runs from every state mover (Init,
--- SetEnabled, SetLocked, Update) so the face is always the CURRENT one.
function D:_RefreshIdle(now)
    if not self.anchor or not S.Enable then return end
    if liveSplashes(self) then
        -- A live splash owns the row: the placeholder branch cannot run
        -- (the source's `i == 1` gate, :1040).
        self:_ReleaseIdle()
        return
    end
    if self.cfg.locked then
        self:_ReleaseIdle()
        if self._shown then
            self._shown = false
            self.anchor:Hide()
            self:_StopTicking()
        end
        return
    end
    if not self._placeholder then
        local slot = self:_AcquireIcon()
        if not slot then return end        -- the cap is all live: no face
        slot.active, slot.placeholder, slot.startAt = true, true, now
        slot._size, slot._alpha = nil, nil
        self._activeCount = self._activeCount + 1
        self._placeholder = slot
        local pr, pg, pb, pa = plateColor()
        slot.plate:SetVertexColor(pr, pg, pb, pa)
        self:_ApplyGlow(slot)
        slot.frame:Show()
    end
    self:_RenderIdle(self._placeholder)
    if not self._shown then
        self._shown = true
        self.anchor:Show()
        self.title:Show()
        self:_StartTicking()
    end
end

-- ------------------------------------------------------------- the pop API --
--- One ready pop. `texPath` is the icon (a sealed read leaves it nil: the
--- pop then runs plate + spark on the slot's standing icon),
--- `cooldownDuration` rides the Module's pop signature but does not move
--- the curve (the bell window is the fixed 1.0 s), `category` the colour.
--- The first curve frame renders SYNCHRONOUSLY here (the hidden-frame
--- law): the window shows, the OnUpdate ticker only carries it.
function D:OnReady(name, now, texPath, cooldownDuration, category)
    if not S.Enable then return end
    if not self.anchor then return end
    now = now or GetTime()
    -- The source's Draw fills icons[1..] with live splashes BEFORE the
    -- :1040 placeholder branch can run -- a pop takes the idle
    -- placeholder's slot over, it never stacks next to it.
    self:_ReleaseIdle()
    local slot = self:_AcquireIcon()
    if not slot then return end

    slot.active, slot.name, slot.startAt = true, name, now
    slot._alpha = nil
    if texPath then slot.tex:SetTexture(texPath) end
    local pr, pg, pb, pa = plateColor()
    slot.plate:SetVertexColor(pr, pg, pb, pa)
    local col = categoryColor(category)
    slot.spark:SetVertexColor(fixIntensity(col[1], col[2], col[3]))  -- :1033
    slot._size = nil
    self:_ApplyGlow(slot)
    slot.frame:Show()
    self._activeCount = self._activeCount + 1

    if not self._shown then
        self._shown = true
        self.anchor:Show()
        if self.cfg.locked then self.title:Hide() else self.title:Show() end
    end
    self:_RenderSlot(slot, now)   -- the t14 = 1 frame, synchronously
    self:_StartTicking()
end

--- One slot's bell geometry at `now` (dirty-checked). The source's alpha
--- law verbatim: the WINDOW frame carries s.alpha (:1060, SetAlpha/Init)
--- and the ICON carries s1*s.alpha (:1027) -- the effective on-screen
--- alpha is the product s1*s.alpha^2; the sizes ride :1027 and the
--- :1031-32 2.2x spark.
function D:_RenderSlot(slot, now)
    local t14 = self:SlotT14(slot, now)
    local s1 = self:Bell(t14)
    local size = self:BellSize(t14)
    local alpha = s1 * S.Alpha
    if slot._size == size and slot._alpha == alpha then return end
    slot._size, slot._alpha = size, alpha
    slot.frame:SetAlpha(alpha)
    slot.tex:SetSize(size, size)
    local plate = size + 6                    -- the backdrop inset x2 (:1865)
    slot.plate:SetSize(plate, plate)
    local spark = size * S.SparkScale          -- :1031-32
    slot.spark:SetSize(spark, spark)
end

--- The render pass. `now` is optional (GetTime() by default) -- the tests
--- inject a clock. Returns true while the window runs (a live splashes or
--- a shown placeholder).
function D:Update(now)
    if not self.anchor or not S.Enable then return false end
    now = now or GetTime()
    local pool = self._icons
    for i = 1, #pool do
        local slot = pool[i]
        if slot.active and not slot.placeholder and now >= slot.startAt then
            -- A clock that has not reached the pop's startAt is the real
            -- GetTime() of a pump around synthetic-clock tests: it renders
            -- no history and retires nothing.
            -- The window's end: the source's cd[14] > 0 gate (:1017) --
            -- t14 <= 0 (1.0 s after the pop) stops drawing it.
            if now - slot.startAt >= S.Window then
                self:_Release(slot)
            else
                self:_RenderSlot(slot, now)
            end
        end
    end
    self:_RefreshIdle(now)
    return self._activeCount > 0
end

-- ----------------------------------------------------------------- ticker --
--- The 10 Hz script exists only while the window is shown (a hidden frame
--- never receives OnUpdate -- the 2026-11-02 uiforever law).
function D:_StartTicking()
    if not self.anchor or self._ticking then return end
    self._ticking = true
    self._acc = 0
    self.anchor:SetScript("OnUpdate", function(_, elapsed)
        local acc = (self._acc or 0) + (tonumber(elapsed) or 0)
        if acc < TICK_SECONDS then
            self._acc = acc
            return
        end
        self._acc = 0
        self:Update(GetTime())
    end)
end

function D:_StopTicking()
    if not self._ticking then return end
    self._ticking = false
    if self.anchor then self.anchor:SetScript("OnUpdate", nil) end
end

-- ---------------------------------------------------------------- setters --
function D:SetEnabled(on)
    S.Enable = not not on
    if not S.Enable then
        -- Off: every live pop is dropped and the window hides (the
        -- source's Update runs exactly this: `else self:Hide()`
        -- :1070-1071).
        if not self.anchor then return end
        local pool = self._icons
        for i = 1, #pool do
            self:_Release(pool[i])
        end
        self._placeholder = nil
        self._shown = false
        self.anchor:Hide()
        self:_StopTicking()
        return
    end
    -- On: the idle face arrives at once (:1040 gate -- unlocked shows the
    -- placeholder, locked stays hidden until a pop).
    self:Update(GetTime())
end

function D:SetSecondSplashMax(v)
    -- The bell's peak multiplier: the peak icon is 32*SecondSplashMax
    -- (:1027). It must stay a number; the source has no positivity gate.
    if type(v) == "number" then S.SecondSplashMax = v end
end

function D:SetSplashMax(v)
    if type(v) == "number" and v >= 1 then
        S.SplashMax = math.floor(v)
    end
end

function D:SetSplashGlow(on)
    S.SplashGlow = not not on
    local pool = self._icons
    for i = 1, #(pool or {}) do
        self:_ApplyGlow(pool[i])
    end
end

function D:SetAlpha(v)
    if type(v) == "number" and v > 0 then S.Alpha = v end
    if self.anchor then self.anchor:SetAlpha(S.Alpha) end
end

function D:SetScale(v)
    if type(v) == "number" and v > 0 then S.Scale = v end
    -- The frame size rides 32*scale (:1061-62); the live slots and the
    -- placeholder pick the new bell numbers up on their next render
    -- (BellSize / NormalSize read S).
    if self.anchor then self.anchor:SetSize(self:NormalSize(), self:NormalSize()) end
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

--- The Advanced page's strata row for this window (the source's
--- `SplashStrata`, Forte_Cooldown.lua:1793, applied by its own
--- `self:SetFrameStrata(FW.Settings.SplashStrata)` at :1067; default
--- `Strata = "MEDIUM"`, Forte_Core.lua:2531). A name outside the eight is
--- ignored: the window keeps the strata it has.
function D:SetStrata(name)
    local up = strataOrNil(name)
    if not up then return end
    S.Strata = up
    if self.anchor and self.anchor.SetFrameStrata then
        self.anchor:SetFrameStrata(up)
    end
end

-- --------------------------------------------------------- live settings --
--- options key -> setter (the Timeline's / the Swing's seam shape). Lock
--- rides SetLocked (the frame publishes it back); GlobalLock is the
--- General page's shared frame lock.
local KEYMAP = {
    Enable = "SetEnabled",
    Lock = "SetLocked",
    GlobalLock = "SetLocked",
    SecondSplashMax = "SetSecondSplashMax",
    SplashMax = "SetSplashMax",
    SplashGlow = "SetSplashGlow",
    Alpha = "SetAlpha",
    Scale = "SetScale",
    -- The Advanced page's shared strata row for this window (the source's
    -- `SplashStrata`, Forte_Cooldown.lua:1793).
    SplashStrata = "SetStrata",
}

--- The stored shape of the wired keys (the page's defaults are canonical).
--- Lock is deliberately NOT pulled: the live lock state on the frame is the
--- truth and SetLocked publishes it upward (the Timeline's m4 rule).
local STORED = {
    Splash = { "Enable", "SecondSplashMax", "SplashMax",
        "SplashGlow", "Alpha", "Scale" },
    Advanced = { "SplashStrata" },
}

function D:ApplySettings(tbl)
    for key, value in pairs(tbl or {}) do
        local m = KEYMAP[key]
        if m then self[m](self, value) end
    end
end

function D:ApplyStoredSettings()
    local st = FX.Settings
    if not st or not st.IsRegistered then return end
    for module, keys in pairs(STORED) do
        if st:IsRegistered(module) then
            local out = {}
            for i = 1, #keys do
                out[keys[i]] = st:Get(module, keys[i])
            end
            self:ApplySettings(out)
        end
    end
end

--- Live wiring, registered once from Init: our own module routes through
--- KEYMAP, and the two shared lock keys are mirrored so /fx lock|unlock
--- (which moves the Cooldown bar's lock and General's GlobalLock) also
--- locks/unlocks this window. SetLocked's store-inequality guard stops the
--- echo (the Forte_Hunter swing's seam verbatim).
function D:_WireSettings()
    local st = FX.Settings
    if not st or not st.OnChange or self._wired then return end
    self._wired = true
    st:OnChange("Splash", function(key, value)
        self:ApplySettings({ [key] = value })
    end)
    st:OnChange("Cooldown", function(key, value)
        if key == "Lock" then self:SetLocked(not not value) end
    end)
    st:OnChange("General", function(key, value)
        if key == "GlobalLock" then self:SetLocked(not not value) end
    end)
    st:OnChange("Advanced", function(key, value)
        self:ApplySettings({ [key] = value })
    end)
end

-- ---------------------------------------------------------------- lifecycle --
function D:Status()
    FX.Print(string.format(
        "Splash: %s | scale %.1f peak x%.1f window %.1fs cap %d | %d active | %s",
        S.Enable and "on" or "off",
        S.Scale, S.SecondSplashMax, S.Window, S.SplashMax,
        self._activeCount or 0,
        (self.cfg and self.cfg.locked) and "locked" or "unlocked"))
end

FX.RegisterModule("Splash", D)

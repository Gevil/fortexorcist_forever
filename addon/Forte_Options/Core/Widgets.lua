-- Forte_Options/Core/Widgets.lua
-- The option-row widget vocabulary of the options window (the original's
-- Options.lua surface, docs/reference-functional-spec.md §8.1 OP-02/OP-04,
-- shrunk to what the two live pages use):
--
--   W.CHK  checkbox            W.NUM  number box (min/max/step, Enter
--   W.SLD  slider                   confirms, Escape restores)
--   W.COL  colour swatch (ColorPickerFrame)    W.STR  edit box
--   W.INFO static grey value   W.HEADER  per-page module header bar
--   W.SECTION  collapsible section bar        W.TIP  one help line
--
-- Every bound widget row = [label ....... control][recycle]. The recycle
-- icon resets ONLY that key (Settings:GetDefault -> Settings:Set), matching
-- OP-04. Rows bind to (module, key) through FX.Settings; change listeners
-- registered by the pages do the live wiring (no page wires through here).
--
-- API law: only calls proven in the Forever Blizzard UI (wow-ui-sim
-- blizzard-ui snapshot) -- UICheckButtonTemplate, InputBoxTemplate,
-- UISliderTemplate, SetScript OnEnterPressed/OnEscapePressed (the
-- AccountSaveUI idiom), SetMinMaxValues/SetValueStep/SetValue (TextToSpeech
-- slider), ColorPickerFrame:SetupColorPickerAndShow + GetColorRGB/
-- GetColorAlpha (ChatConfigFrame idiom), atlas glyphs via inline
-- |A:name:W:H|a markup (TextureUtil.CreateAtlasMarkup).

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
FX.Options = FX.Options or {}

local W = {}
FX.Options.Widgets = W

-- ------------------------------------------------------------- constants --
W.C = {
    -- geometry (px)
    ROW_H = 20,            -- one option row
    ROW_GAP = 3,
    CTRL_H = 16,           -- shared control height (editbox/slider)
    LABEL_FS = 10, CTRL_FS = 10, HEAD_FS = 12, TIPS_FS = 11,
    NUM_W = 64, SLD_W = 150, STR_W = 220,
    CHK_SZ = 16, SWATCH_SZ = 14, ICON_W = 16, ICON_GAP = 3,
    SECTION_H = 22, SECTION_PAD = 6,
    HEAD_H = 24,

    -- colours
    GOLD = { 1, 0.82, 0, 1 },          -- option labels (the original's gold)
    GOLD_WHITE = { 1, 0.95, 0.75, 1 }, -- section titles
    GOLD_CHECK = { 1, 0.82, 0, 1 },    -- the checkbox's gold check mark
    WHITE = { 1, 1, 1, 1 },
    GREY = { 0.62, 0.62, 0.65, 1 },    -- path/info values, dim labels
    GREY_DARK = { 0.45, 0.45, 0.5, 1 },
    TIPS_YELLOW = { 1, 1, 0.3, 1 },
    SECTION_BG = { 0.17, 0.17, 0.30, 0.92 }, -- the dark navy section bar
    HEADER_TINT = 0.55,               -- module colour -> header bar blend

    -- atlas glyph markup sizes
    GLYPH_RESET = 12, GLYPH_LOCK = 12, GLYPH_CLOSE = 14,

    FONT_FILE = "Interface\\AddOns\\Forte_Core\\Fonts\\URWGothic-Book.ttf",
    FONT_SIZE = 11,
}
local C = W.C

-- ------------------------------------------------------------------ fonts --
-- Same validate-once round trip as Forte_Cooldown/UI/Timeline.lua: accepted
-- only when GetFont returns the file back; every fontstring then falls back
-- to its GameFont* template. The verdict is recorded on FX.Options.
local function validateFont()
    if FX.Options.fontFile ~= nil and FX.Options.fontVerified then
        return FX.Options.fontFile
    end
    local okCreate, fontObj = pcall(CreateFont, C.FONT_FILE, C.FONT_SIZE)
    local accepted
    if okCreate and fontObj then
        local probe = UIParent:CreateFontString(nil, "OVERLAY")
        if probe then
            local okSet = pcall(probe.SetFont, probe, C.FONT_FILE, C.FONT_SIZE)
            local got = okSet and probe:GetFont()
            probe:Hide()
            if type(got) == "string" and got:lower() == C.FONT_FILE:lower() then
                accepted = C.FONT_FILE
            end
        end
    end
    FX.Options.fontFile = accepted   -- nil => template fallback everywhere
    FX.Options.fontVerified = true
    return accepted
end
W.validateFont = validateFont

--- Set the validated file font on a fontstring (dirty-checked), restoring
--- the string's own template on rejection. The template is what the
--- fontstring was CREATED with, so the fallback keeps per-role sizing.
function W.applyFont(fs, size, flags)
    local file = validateFont()
    local key = tostring(size) .. "|" .. (flags or "") .. "|" .. (file or "tpl")
    if fs._fxFont == key then return end
    local ok = false
    if file then
        ok = pcall(fs.SetFont, fs, file, size, flags)
        if ok then ok = (fs:GetFont()) == file end
    end
    if not ok then
        if fs._fxTemplate then
            pcall(fs.SetFontTemplate, fs, fs._fxTemplate)
        end
        key = nil
    end
    fs._fxFont = key
end

--- Fontstring factory: template fallback baked in via _fxTemplate.
function W.fontString(parent, template, text, colour)
    local fs = parent:CreateFontString(nil, "OVERLAY", template)
    fs._fxTemplate = template
    W.applyFont(fs, C.LABEL_FS)
    fs:SetText(text or "")
    local col = colour or C.WHITE
    fs:SetTextColor(col[1], col[2], col[3], col[4])
    return fs
end

-- -------------------------------------------------------------- tooltips --
--- The shared tooltip idiom (AchievementUI: SetOwner/SetText/AddLine/Show).
function W.attachTip(obj, text, title)
    if not text then return end
    obj:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if title then
            GameTooltip:SetText(title, 1, 1, 1)
            GameTooltip:AddLine(text, nil, nil, nil, true)
        else
            GameTooltip:SetText(text, 1, 1, 1, nil, true)
        end
        GameTooltip:Show()
    end)
    obj:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

--- atlas glyph markup (TextureUtil.CreateAtlasMarkup idiom).
local function glyph(name, size)
    return "|A:" .. name .. ":" .. size .. ":" .. size .. "|a"
end
W.glyph = glyph

-- ------------------------------------------------------------- row frame --
--- A row of width `width` in parent, returning the frame. Callers anchor
--- rows themselves (the page builder owns the vertical cursor).
local function makeRow(parent, width)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width, C.ROW_H)
    return row
end

--- Shared tail: right-aligned recycle icon writing the per-key default.
--- Rows without a bound key (the About page's static INFO lines) get no
--- icon at all.
local function attachResetIcon(w, spec)
    if not spec.key then return end
    local btn = CreateFrame("Button", nil, w.row)
    btn:SetSize(C.ICON_W, C.ICON_W)
    btn:SetPoint("RIGHT", w.row, "RIGHT", 0, 0)
    btn:SetScript("OnClick", function()
        FX.Settings:Reset(spec.module, spec.key)
    end)
    w.resetText = W.fontString(btn, "GameFontHighlightSmall",
        glyph("common-icon-undo", C.GLYPH_RESET), C.GREY)
    w.resetText:SetPoint("CENTER", btn, "CENTER", 0, 0)
    W.attachTip(btn, "Reset '" .. tostring(spec.label)
        .. "' to the default value")
    w.resetBtn = btn
end

--- Shared label at the row's left. Bounded to the free row width (control
--- + recycle zone at the right) so a long label can never run over the
--- control; overflow collapses to one ellipsised line.
local function attachLabel(w, spec, colour)
    w.label = W.fontString(w.row, "GameFontHighlightSmall",
        spec.label or "", colour or C.GOLD)
    w.label:SetPoint("LEFT", w.row, "LEFT", 0, 0)
    w.label:SetWordWrap(true)
    w.label:SetNonSpaceWrap(true)
    pcall(w.label.SetMaxLines, w.label, 1, true)
    local avail = (w.row:GetWidth() or 0) - C.ICON_W - C.ICON_GAP - 8
    if avail > 8 then
        w.label:SetWidth(avail)
    end
    w.labelWidth = avail
end

--- Shared disabled state: grey the label, disable the control.
local function setEnabled(w, enabled)
    w.disabled = not enabled
    local col = enabled and (w.labelColour or C.GOLD) or C.GREY_DARK
    w.label:SetTextColor(col[1], col[2], col[3], col[4])
    if w.obj.SetEnabled then
        w.obj:SetEnabled(enabled)
    elseif enabled then
        w.obj:Enable()
    else
        w.obj:Disable()
    end
    if w.resetBtn then
        if enabled then w.resetBtn:Enable() else w.resetBtn:Disable() end
    end
end

--- The common handle skeleton; the per-type builder fills obj/refresh.
local function newWidget(parent, spec, width, labelColour)
    local w = { spec = spec, row = makeRow(parent, width), labelColour = labelColour }
    attachLabel(w, spec, labelColour)
    w.setEnabled = function(self, enabled) setEnabled(self, enabled) end
    return w
end

--- Right-side control zone: [control][gap][recycle]. Control's right edge
--- sits C.ICON_W + C.ICON_GAP from the row's right; callers pass their width.
local function anchorControl(w, obj, width)
    obj:SetSize(width, C.CTRL_H)
    obj:SetPoint("RIGHT", w.row, "RIGHT", -(C.ICON_W + C.ICON_GAP), 0)
    w.obj = obj
end

-- ------------------------------------------------------------------ CHK --
function W.CHK(parent, spec)
    local w = newWidget(parent, spec, spec.width)
    local cb = CreateFrame("CheckButton", nil, w.row, "UICheckButtonTemplate")
    anchorControl(w, cb, C.CHK_SZ)
    cb:SetSize(C.CHK_SZ, C.CHK_SZ)

    -- The gold check mark: try the Button-API tint first, then the texture
    -- region, and record what worked (reported + asserted in the tests).
    local tinted = "none"
    local g = C.GOLD_CHECK
    if pcall(cb.SetCheckedVertexColor, cb, g[1], g[2], g[3]) then
        tinted = "SetCheckedVertexColor"
    else
        local ok, got = pcall(function()
            local tex = cb.GetCheckedTexture and cb:GetCheckedTexture()
            if not tex then return false end
            tex:SetVertexColor(g[1], g[2], g[3])
            return true
        end)
        if ok and got == true then tinted = "GetCheckedTexture" end
    end
    W.checkedTint = tinted

    w.refresh = function()
        cb:SetChecked(not not FX.Settings:Get(spec.module, spec.key))
    end
    cb:SetScript("OnClick", function(self)
        -- CheckButtons do not auto-toggle in this widget set (StanceBar
        -- flips manually), so the setting is the single source of truth.
        FX.Settings:Set(spec.module, spec.key,
            not FX.Settings:Get(spec.module, spec.key))
    end)
    W.attachTip(cb, spec.tip, spec.label)
    attachResetIcon(w, spec)
    w.refresh()
    return w
end

-- ------------------------------------------------------------------ NUM --
--- Clamp to the row's declared range (OP-07: the widget clamps, the store
--- keeps exactly what the user approved).
local function clamp(value, lo, hi)
    if lo and value < lo then value = lo end
    if hi and value > hi then value = hi end
    return value
end
W._clamp = clamp

local function formatNumber(v)
    if type(v) ~= "number" then return tostring(v) end
    if math.floor(v) == v then return string.format("%d", v) end
    return string.format("%.2f", v)
end
W._formatNumber = formatNumber

function W.NUM(parent, spec)
    local w = newWidget(parent, spec, spec.width)
    local eb = CreateFrame("EditBox", nil, w.row, "InputBoxTemplate")
    anchorControl(w, eb, spec.numWidth or C.NUM_W)
    eb:SetAutoFocus(true)
    eb:SetJustifyH("RIGHT")
    eb:SetMaxLetters(10)

    local function commit()
        local v = tonumber((eb:GetText() or ""))
        if v == nil then
            w.refresh()
            return
        end
        FX.Settings:Set(spec.module, spec.key, clamp(v, spec.min, spec.max))
    end
    w.refresh = function()
        if eb.HasFocus and eb:HasFocus() then return end
        eb:SetText(formatNumber(FX.Settings:Get(spec.module, spec.key)))
    end
    eb:SetScript("OnEnterPressed", commit)
    eb:SetScript("OnEscapePressed", w.refresh)
    eb:SetScript("OnEditFocusLost", commit)
    -- Live filter: numbers, one dot, a leading minus (search-box sanitising
    -- idiom, ChatConfigFrame OnTextChanged).
    eb:SetScript("OnTextChanged", function(self, isUser)
        if not isUser then return end
        local t = self:GetText() or ""
        local clean = (t:gsub("[^0-9%.%-]", ""))
        -- Collapse everything after the FIRST dot to digits (the search-box
        -- sanitising idiom, ChatConfigFrame OnTextChanged).
        local int, frac = clean:match("^(%d*)%.(.*)$")
        if int ~= nil and frac ~= nil then
            clean = int .. "." .. (frac:gsub("%.", ""))
        end
        if clean ~= t then
            self:SetText(clean)
        end
    end)
    W.attachTip(eb, spec.tip, spec.label)
    attachResetIcon(w, spec)
    w.refresh()
    return w
end

-- ------------------------------------------------------------------ SLD --
function W.SLD(parent, spec)
    local w = newWidget(parent, spec, spec.width)
    local sl = CreateFrame("Slider", nil, w.row, "UISliderTemplate")
    anchorControl(w, sl, spec.sldWidth or C.SLD_W)
    sl:SetOrientation("HORIZONTAL")
    sl:SetMinMaxValues(spec.min, spec.max)
    sl:SetValueStep(spec.step or 1)

    w.refresh = function()
        w._loading = true
        sl:SetValue(FX.Settings:Get(spec.module, spec.key))
        w._loading = false
    end
    sl:SetScript("OnValueChanged", function(self)
        if w._loading then return end
        FX.Settings:Set(spec.module, spec.key, clamp(self:GetValue(), spec.min, spec.max))
    end)
    W.attachTip(sl, spec.tip, spec.label)
    attachResetIcon(w, spec)
    w.refresh()
    w.slider = sl
    return w
end

-- ------------------------------------------------------------------ COL --
--- Colour row: [label][r g b a text][swatch][recycle]. The picker is the
--- modern ColorPickerFrame (ChatConfigFrame's SetupColorPickerAndShow
--- info-table idiom); swatchFunc fires live during picks and on Okay, so
--- the setting tracks the wheel and the swatch preview updates live.
function W.COL(parent, spec)
    local w = newWidget(parent, spec, spec.width)

    local val = W.fontString(w.row, "GameFontHighlightSmall", "", C.GREY)
    val:SetJustifyH("RIGHT")
    val:SetPoint("RIGHT", w.row, "RIGHT", -(C.ICON_W + C.ICON_GAP + C.SWATCH_SZ + 8), 0)
    w.valueText = val

    local btn = CreateFrame("Button", nil, w.row)
    btn:SetSize(C.SWATCH_SZ + 6, C.SWATCH_SZ + 6)
    btn:SetPoint("RIGHT", w.row, "RIGHT", -(C.ICON_W + C.ICON_GAP), 0)
    local sw = btn:CreateTexture(nil, "ARTWORK")
    sw:SetPoint("TOPLEFT", btn, "TOPLEFT", 3, -3)
    sw:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -3, 3)
    sw:SetTexture("Interface\\AddOns\\Forte_Core\\Textures\\Aluminium")
    w.swatchTex = sw

    w.refresh = function()
        local c = FX.Settings:Get(spec.module, spec.key) or { 1, 1, 1, 1 }
        sw:SetVertexColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
        val:SetText(string.format("%.2f %.2f %.2f %.2f",
            c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1))
    end

    --- Read the picker and write the setting. Called from swatchFunc (live
    --- pick + Okay) and, with alpha, from opacityFunc.
    local function applyFromPicker()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        local a = ColorPickerFrame:GetColorAlpha()
        FX.Settings:Set(spec.module, spec.key, { r, g, b, a })
    end
    w.applyFromPicker = applyFromPicker

    btn:SetScript("OnClick", function(self)
        local c = FX.Settings:Get(spec.module, spec.key) or { 1, 1, 1, 1 }
        ColorPickerFrame:SetupColorPickerAndShow({
            r = c[1], g = c[2], b = c[3],
            hasOpacity = true,
            opacity = c[4] or 1,
            swatchFunc = applyFromPicker,
            opacityFunc = applyFromPicker,
            cancelFunc = function() w.refresh() end,
        })
    end)
    W.attachTip(btn, spec.tip, spec.label)
    attachResetIcon(w, spec)
    w.refresh()
    w.swatchBtn = btn
    return w
end

-- ------------------------------------------------------------------ STR --
function W.STR(parent, spec)
    local w = newWidget(parent, spec, spec.width)
    local eb = CreateFrame("EditBox", nil, w.row, "InputBoxTemplate")
    anchorControl(w, eb, spec.strWidth or C.STR_W)
    eb:SetAutoFocus(true)
    eb:SetJustifyH("LEFT")
    eb:SetMaxLetters(spec.maxLetters or 96)
    w.refresh = function()
        if eb.HasFocus and eb:HasFocus() then return end
        eb:SetText(tostring(FX.Settings:Get(spec.module, spec.key) or ""))
    end
    eb:SetScript("OnEnterPressed", function(self)
        FX.Settings:Set(spec.module, spec.key, self:GetText() or "")
    end)
    eb:SetScript("OnEscapePressed", w.refresh)
    eb:SetScript("OnEditFocusLost", function(self)
        FX.Settings:Set(spec.module, spec.key, self:GetText() or "")
    end)
    W.attachTip(eb, spec.tip, spec.label)
    attachResetIcon(w, spec)
    w.refresh()
    return w
end

-- ------------------------------------------------------------------ INFO --
--- Static value row: label + right-aligned grey value (font/texture paths,
--- the About page). Carries the recycle icon like every other option.
function W.INFO(parent, spec)
    local w = newWidget(parent, spec, spec.width)
    local val = W.fontString(w.row, "GameFontHighlightSmall", "", C.GREY)
    val:SetJustifyH("RIGHT")
    val:SetPoint("RIGHT", w.row, "RIGHT", -(C.ICON_W + C.ICON_GAP), 0)
    w.valueText = val
    w.obj = val                       -- the value text IS the (read-only)
                                      -- control of an INFO row
    w.refresh = function()
        local v = spec.value
        if type(v) == "function" then v = v() end
        val:SetText(tostring(v == nil and "" or v))
    end
    attachResetIcon(w, spec)
    w.refresh()
    return w
end

-- ------------------------------------------------------------------ TIPS --
--- One help line: yellow "!" marker + white text, full width. The body is
--- bounded to the line width (word-wrapped), so tips text can never run
--- past the section.
function W.TIPS_LINE(parent, text, width)
    local line = CreateFrame("Frame", nil, parent)
    line:SetSize(width, C.ROW_H)
    local bang = W.fontString(line, "GameFontNormal", "!", C.TIPS_YELLOW)
    bang:SetPoint("LEFT", line, "LEFT", 0, 0)
    local body = W.fontString(line, "GameFontNormalSmall", text, C.WHITE)
    body:SetPoint("LEFT", bang, "RIGHT", 8, 0)
    body:SetWordWrap(true)
    body:SetNonSpaceWrap(true)
    body:SetWidth(width - 8 - 8)
    line.body = body
    return line
end

-- -------------------------------------------------------------- SECTION --
--- A collapsible section bar: navy bar, +/- icon, gold-white title, recycle
--- at the far right (restores the whole category: spec.resetKeys). Bar click
--- toggles; the page recomputes content height via spec.onToggle.
function W.SECTION(parent, spec)
    local C = W.C
    local sec = {}
    local bar = CreateFrame("Button", nil, parent)
    bar:SetSize(spec.width, C.SECTION_H)
    bar:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    local art = bar:CreateTexture(nil, "BACKGROUND")
    art:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    art:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    local bg = C.SECTION_BG
    art:SetVertexColor(bg[1], bg[2], bg[3], bg[4])
    sec.bar, sec.art = bar, art

    local plus = W.fontString(bar, "GameFontHighlightSmall", glyph("common-icon-plus", 10), C.GOLD_WHITE)
    plus:SetPoint("LEFT", bar, "LEFT", 6, 0)
    sec.plus = plus
    sec.title = W.fontString(bar, "GameFontHighlightSmall", spec.title, C.GOLD_WHITE)
    sec.title:SetPoint("LEFT", plus, "RIGHT", 8, 0)

    local recycleBtn = CreateFrame("Button", nil, bar)
    recycleBtn:SetSize(C.ICON_W + 8, C.SECTION_H)
    recycleBtn:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    local recycle = W.fontString(recycleBtn, "GameFontHighlightSmall",
        glyph("common-icon-undo", C.GLYPH_RESET), C.GREY)
    recycle:SetPoint("CENTER", recycleBtn, "CENTER", 0, 0)
    sec.recycle = recycleBtn
    W.attachTip(recycleBtn, "Reset the whole '" .. spec.title .. "' category", spec.title)
    W.attachTip(bar, spec.tip, nil)

    sec.collapsed = spec.collapsed and true or false
    local function repaint()
        plus:SetText(glyph(sec.collapsed and "common-icon-plus"
            or "common-icon-minus", 10))
    end
    sec.repaint = repaint
    bar:SetScript("OnClick", function()
        sec.collapsed = not sec.collapsed
        repaint()
        if spec.onToggle then spec.onToggle(sec.collapsed) end
    end)
    if spec.onResetAll then
        recycleBtn:SetScript("OnClick", function() spec.onResetAll() end)
    else
        recycleBtn:Hide()
    end
    repaint()
    sec.row = bar
    return sec
end

-- --------------------------------------------------------------- HEADER --
--- The per-page module header bar: module-tinted full-width bar, gear plate
--- + lock icon left, bold page title centre, scale/alpha number fields and
--- the category recycle right. spec = { title, colour, onLock, isLocked,
--- scaleSpec, alphaSpec, onResetAll, width }
function W.HEADER(parent, spec)
    local C = W.C
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(spec.width, C.HEAD_H)
    local art = bar:CreateTexture(nil, "BACKGROUND")
    art:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    art:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    art:SetTexture("Interface\\AddOns\\Forte_Core\\Textures\\Aluminium")
    local col = spec.colour
    art:SetVertexColor(col[1] * C.HEADER_TINT, col[2] * C.HEADER_TINT,
        col[3] * C.HEADER_TINT, 0.95)

    -- Gear plate: the module-colour chip (the original's gear slot).
    local gear = bar:CreateTexture(nil, "ARTWORK")
    gear:SetTexture("Interface\\AddOns\\Forte_Core\\Textures\\Aluminium")
    gear:SetSize(14, 14)
    gear:SetPoint("LEFT", bar, "LEFT", 8, 0)
    gear:SetVertexColor(col[1], col[2], col[3], 1)

    -- Lock icon: click toggles the frame lock; gold = unlocked (movable).
    local lock = CreateFrame("Button", nil, bar)
    lock:SetSize(16, 16)
    lock:SetPoint("LEFT", gear, "RIGHT", 6, 0)
    local lockText = W.fontString(lock, "GameFontHighlightSmall",
        glyph("common-icon-move", C.GLYPH_LOCK), C.WHITE)
    lockText:SetPoint("CENTER", lock, "CENTER", 0, 0)
    lock:SetScript("OnClick", function()
        if spec.onLock then spec.onLock() end
    end)
    W.attachTip(lock, spec.lockTip or "Lock/unlock module frames")

    local title = W.fontString(bar, "GameFontNormalLarge", spec.title, C.WHITE)
    title:SetJustifyH("CENTER")
    title:SetPoint("CENTER", bar, "CENTER", 0, 0)

    local head = { bar = bar, lockText = lockText, title = title }
    head.setLockedVisual = function(locked)
        local c = locked and C.GREY or C.GOLD
        lockText:SetTextColor(c[1], c[2], c[3], c[4])
    end

    -- Right stack: [scale field] [alpha field] [category recycle].
    local recycleBtn = CreateFrame("Button", nil, bar)
    recycleBtn:SetSize(C.ICON_W + 8, C.HEAD_H)
    recycleBtn:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    local recycle = W.fontString(recycleBtn, "GameFontHighlightSmall",
        glyph("UI-RefreshButton", C.GLYPH_RESET), C.GOLD)
    recycle:SetPoint("CENTER", recycleBtn, "CENTER", 0, 0)
    W.attachTip(recycleBtn, "Restore ALL defaults of this category", spec.title)
    recycleBtn:SetScript("OnClick", function()
        if spec.onResetAll then spec.onResetAll() end
    end)
    head.recycle = recycleBtn

    if spec.scaleSpec then head.scale = W.NUM(bar, spec.scaleSpec) end
    if spec.alphaSpec then head.alpha = W.NUM(bar, spec.alphaSpec) end
    if head.scale then
        head.scale.row:SetPoint("RIGHT", recycle, "LEFT", -10, 0)
        head.scale.row:SetSize(head.scale.row:GetWidth(), C.HEAD_H)
        head.scale.label:SetText("scale")
        head.scale.label:SetPoint("LEFT", head.scale.row, "LEFT", 0, 0)
    end
    if head.alpha then
        head.alpha.row:SetPoint("RIGHT", (head.scale and head.scale.row or recycle), "LEFT", -10, 0)
        head.alpha.row:SetSize(head.alpha.row:GetWidth(), C.HEAD_H)
        head.alpha.label:SetText("alpha")
    end
    return head
end

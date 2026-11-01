-- Forte_Options/UI/Window.lua
-- The one options window in the original's shape (docs/refs/options-panel.png
-- is the visual law; PLAN §3.6, Phase 6; spec §8.1 OP-09..OP-11):
--
--   [ ForteXorcist v<ver> by Xus - <player>-<realm>          X ]
--   [ <Hunter: name x> ]                                      profile tabs
--   [ gear lock   <PAGE TITLE>            scale alpha refresh ] module header
--   [ scrollable content: Some Tips / sections / option rows            ]
--   [ module index: 4 columns of colour-coded buttons                   ]
--
-- Public surface:
--   FX.Options:Toggle() / :Open(pageId) / :Close() / :IsOpen()
--   FX.Options:SetPage(pageId)
--   FX.Options:RegisterPage(def)            (Pages/*.lua, load time)
--   /fx options and /fx config -> Toggle (FX.RegisterSlash seam).
-- ESC closes: the window's global frame name is pushed into UISpecialFrames
-- (UIParentPanelManager.CloseSpecialWindows hides every shown entry).
-- Position is remembered in FX.db.optionsPos after every drag.
--
-- Everything the geometry tests assert lives in O.C below.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
FX.Options = FX.Options or {}
local O = FX.Options
ForteXorcist.Options = O   -- the documented alias (ForteXorcist.Options:Open)
local W = O.Widgets
local WC = W.C

-- ------------------------------------------------------------- constants --
O.C = {
    WIN_W = 780, WIN_H = 650,
    TITLE_H = 26, TABS_H = 22, HEAD_H = WC.HEAD_H,
    PAD = 10,
    PANEL_BG = { 0.07, 0.08, 0.13, 0.90 },  -- dark navy body (defect 6)
    TITLE_BG = { 0.10, 0.11, 0.20, 1 },    -- title strip fill
    BORDER_TINT = { 0.75, 0.75, 0.80, 0.9 },
    ACCENT_RED = { 0.77, 0.12, 0.23, 1 },
    TAB_GOLD = { 1, 0.82, 0, 1 },

    INDEX_COLS = 4,
    INDEX_CELL_H = 44, INDEX_GAP = 6,
    INDEX_LABEL_FS = 10,

    HEAD_SCALE_RANGE = { 0.2, 5.0 },   -- OP-06 clamps
    HEAD_ALPHA_RANGE = { 0.1, 1.0 },

    WHEEL_STEP = 40,

    -- scroll indication (2026-11-01 defect pass): a 6px track on the
    -- viewport's right edge + an Aluminium thumb (UpdateScrollbar).
    SCROLL_W = 6,
    SCROLL_THUMB_W = 4,
    SCROLL_THUMB_MIN = 16,
    SCROLL_TRACK = { 0.04, 0.05, 0.08, 0.4 },   -- dark, alpha 0.4
    SCROLL_THUMB = { 0.72, 0.73, 0.78, 0.8 },   -- Aluminium tint, alpha 0.8

    -- Module index palette (module identity colours, spec §3.6 header tints)
    SLATE = { 0.35, 0.38, 0.55 },
    GREEN = { 0.15, 0.55, 0.30 },
    BROWN = { 0.65, 0.40, 0.10 },
    PURPLE = { 0.50, 0.25, 0.75 },
    BLUE = { 0.20, 0.35, 0.70 },
    RED = { 0.70, 0.15, 0.15 },
    GREY = { 0.45, 0.45, 0.48 },
}
local C = O.C

O.pages = O.pages or {}     -- [id] = def
O.PAGE_ORDER = O.PAGE_ORDER or {}

--- The full original module index, in the original's order. Only pages a
--- Pages/*.lua file registered are live; the rest render dimmed with the
--- 'not built yet' tooltip.
O.INDEX = O.INDEX or {
    { id = "General",      label = "General Options",    colour = C.SLATE },
    { id = "SpellTimer",   label = "Spell Timer",        colour = C.BROWN },
    { id = "Cooldown",     label = "Cooldown Timer",     colour = C.GREEN },
    { id = "Splash",       label = "Secondary Splash",   colour = C.GREEN },
    { id = "Soulstone",    label = "Soulstone Tracker",  colour = C.PURPLE },
    { id = "ShardSpy",     label = "Shard Spy",          colour = C.PURPLE },
    { id = "Healthstone",  label = "Healthstone Spy",    colour = C.GREEN },
    { id = "Summon",       label = "Summon Assistant",   colour = C.PURPLE },
    { id = "ShardManager", label = "Shard Manager",      colour = C.PURPLE },
    { id = "RaidMsg",      label = "Party/Raid Messages", colour = C.BLUE },
    { id = "SelfMsg",      label = "Self Messages",      colour = C.BLUE },
    { id = "Sound",        label = "Sound",              colour = C.BLUE },
    { id = "TalentSpy",    label = "Talent Spy",         colour = C.RED },
    { id = "Advanced",     label = "Advanced Options",   colour = C.SLATE },
    { id = "About",        label = "About",              colour = C.GREY },
}

--- Pages/*.lua entry point (load-time data only). def =
--- { id, title, colour, module, scaleKey, alphaKey, lockKey, build }
function O:RegisterPage(def)
    self.pages[def.id] = def
    for i = 1, #self.PAGE_ORDER do
        if self.PAGE_ORDER[i] == def.id then return end
    end
    self.PAGE_ORDER[#self.PAGE_ORDER + 1] = def.id
end

-- -------------------------------------------------------------- geometry --
-- WoW anchor law: with TOP/BOTTOM point pairs the y offset is UP-POSITIVE
-- (SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -h) moves the child h px DOWN;
-- SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, m) insets m px from the
-- bottom edge). Every TOPLEFT stack below therefore uses NEGATIVE y.
local function indexHeight()
    local rows = math.ceil(#O.INDEX / C.INDEX_COLS)
    return rows * C.INDEX_CELL_H + (rows + 1) * C.INDEX_GAP
end
O.indexHeight = indexHeight

--- The module-index frame's vertical inset from the window bottom edge.
C.INSET_BOTTOM = 8
C.INDEX_CLEAR = 6      -- gap kept between scroll content and the grid

--- The content viewport box, in window-local (y-from-top) coordinates.
function O:getContentBox()
    local top = C.TITLE_H + C.TABS_H + C.HEAD_H + 2
    -- bottom inset = grid's bottom inset + grid height + clearance gap:
    -- the scroll area ENDS ABOVE the module index (defect 7).
    local bottom = C.INSET_BOTTOM + indexHeight() + C.INDEX_CLEAR
    return C.PAD, top, C.WIN_W - 2 * C.PAD,
        C.WIN_H - top - bottom
end

-- ------------------------------------------------------------------ open --
local DEFAULT_POS = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 }

local function posStore()
    if FX.db then
        FX.db.optionsPos = FX.db.optionsPos or {}
        return FX.db.optionsPos
    end
    O._posFallback = O._posFallback or {}
    return O._posFallback
end

function O:SavePosition(f)
    f = f or self.window
    if not f then return end
    local point, _, relPoint, x, y = f:GetPoint()
    if not point then return end
    local p = posStore()
    p.point, p.relPoint, p.x, p.y = point, relPoint, x, y
    self.pos = p
end

function O:ApplyPosition()
    local w = self.window
    if not w then return end
    local p = posStore()
    local d = DEFAULT_POS
    w:ClearAllPoints()
    w:SetPoint(p.point or d.point, UIParent, p.relPoint or d.relPoint,
        p.x or d.x, p.y or d.y)
end

--- Build the shell once: panel frame, title bar, profile tab row, header
--- slot, content viewport, module index. Called from Open.
function O:Build()
    if self.window then return self.window end
    local fontFile = W.validateFont()
    self.fontFile = fontFile

    local f = CreateFrame("Frame", "ForteXorcistOptionsWindow", UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(C.WIN_W, C.WIN_H)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\AddOns\\Forte_Core\\Textures\\Background",
            edgeFile = "Interface\\AddOns\\Forte_Core\\Textures\\Border",
            tile = false, tileSize = 32, edgeSize = 8,
            insets = { left = 0, right = 0, top = 0, bottom = 0 },
        })
        f:SetBackdropColor(C.PANEL_BG[1], C.PANEL_BG[2], C.PANEL_BG[3], C.PANEL_BG[4])
        f:SetBackdropBorderColor(C.BORDER_TINT[1], C.BORDER_TINT[2],
            C.BORDER_TINT[3], C.BORDER_TINT[4])
    end
    f:SetClampedToScreen(true)

    -- ---- title bar ----------------------------------------------------
    -- A real 26px strip at the very top of the window (defect 4): dark
    -- fill, gold centred title, close X at the strip's right end.
    local TEX = "Interface\\AddOns\\Forte_Core\\Textures\\"
    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetSize(C.WIN_W - 16, C.TITLE_H)
    titleBar:SetPoint("TOPLEFT", f, "TOPLEFT", 8, 0)
    local strip = titleBar:CreateTexture(nil, "BACKGROUND")
    strip:SetTexture(TEX .. "Aluminium")
    strip:SetPoint("TOPLEFT", titleBar, "TOPLEFT", 0, 0)
    strip:SetPoint("BOTTOMRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
    strip:SetVertexColor(C.TITLE_BG[1], C.TITLE_BG[2], C.TITLE_BG[3],
        C.TITLE_BG[4])
    local name = (UnitName and UnitName("player")) or "?"
    local realm = ""
    if GetServerName then
        local ok, r = pcall(GetServerName)
        if ok and type(r) == "string" then realm = r end
    end
    local title = W.fontString(titleBar, "GameFontHighlightSmall",
        string.format("ForteXorcist v%s by Xus - %s-%s",
            FX.CONST.VERSION, name, realm), C.TAB_GOLD)
    title:SetJustifyH("CENTER")
    title:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
    self.titleFS, self.titleBar = title, titleBar

    -- The title bar is the drag handle (Timeline's RegisterForDrag law).
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    titleBar:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        self:SavePosition(f)
    end)
    f:SetMovable(true)

    -- Close button: the red x (common-icon-redx, CharacterCreate idiom).
    local close = CreateFrame("Button", nil, f)
    close:SetSize(18, 18)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -4)
    local closeText = W.fontString(close, "GameFontHighlightSmall",
        W.glyph("common-icon-redx", WC.GLYPH_CLOSE), C.ACCENT_RED)
    closeText:SetPoint("CENTER", close, "CENTER", 0, 0)
    close.glyphText = closeText
    close:SetScript("OnClick", function() self:Close() end)
    W.attachTip(close, "Close the options window")
    self.closeBtn = close

    -- ---- profile tabs row (one tab for this character) -----------------
    local tabs = CreateFrame("Frame", nil, f)
    tabs:SetSize(C.WIN_W - 16, C.TABS_H)
    tabs:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -C.TITLE_H)
    local classFile = (UnitClass and select(2, UnitClass("player")))
        or FX._playerClass or "?"
    classFile = tostring(classFile)
    local classLabel = classFile:sub(1, 1) .. classFile:sub(2):lower()
    local tabText = W.fontString(tabs, "GameFontHighlightSmall",
        string.format("%s: %s", classLabel, name), C.TAB_GOLD)
    tabText:SetPoint("LEFT", tabs, "LEFT", 6, 0)
    local tabX = W.fontString(tabs, "GameFontHighlightSmall",
        W.glyph("common-icon-redx", 10), C.ACCENT_RED)
    tabX:SetPoint("LEFT", tabText, "RIGHT", 6, 0)
    local function tabTip()
        GameTooltip:SetOwner(tabs, "ANCHOR_RIGHT")
        GameTooltip:SetText("Profile tabs", 1, 1, 1)
        GameTooltip:AddLine("profile switching is not built yet", nil, nil, nil, true)
        GameTooltip:Show()
    end
    tabs:EnableMouse(true)
    tabs:SetScript("OnEnter", tabTip)
    tabs:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.tabs = tabs

    -- ---- content viewport + scrollable child --------------------------
    local vpX, vpY, vpW, vpH = self:getContentBox()
    local viewport = CreateFrame("Frame", nil, f)
    viewport:SetSize(vpW, vpH)
    viewport:SetPoint("TOPLEFT", f, "TOPLEFT", vpX, -vpY)
    viewport:SetClipsChildren(true)
    viewport:EnableMouse(true)
    local content = CreateFrame("Frame", nil, viewport)
    content:SetWidth(vpW)
    content:SetPoint("TOPLEFT", viewport, "TOPLEFT", 0, 0)
    self._scroll = 0
    viewport:SetScript("OnMouseWheel", function(_, delta)
        self:Scroll(delta * C.WHEEL_STEP)
    end)
    self.viewport, self.content = viewport, content

    -- ---- scroll indication ---------------------------------------------
    -- A 6px dark track pinned to the viewport's right edge; the thumb's
    -- height is the viewport's share of the content height (min 16px) and
    -- its top offset follows the scroll offset. UpdateScrollbar hides the
    -- whole bar whenever the page fits (defect: no scroll indication).
    local sbTrack = CreateFrame("Frame", "ForteXorcistOptionsScrollTrack", f)
    sbTrack:SetSize(C.SCROLL_W, vpH)
    sbTrack:SetPoint("TOPRIGHT", viewport, "TOPRIGHT", 0, 0)
    local sbArt = sbTrack:CreateTexture(nil, "BACKGROUND")
    sbArt:SetPoint("TOPLEFT", sbTrack, "TOPLEFT", 0, 0)
    sbArt:SetPoint("BOTTOMRIGHT", sbTrack, "BOTTOMRIGHT", 0, 0)
    sbArt:SetTexture(TEX .. "Aluminium")
    sbArt:SetVertexColor(C.SCROLL_TRACK[1], C.SCROLL_TRACK[2],
        C.SCROLL_TRACK[3], C.SCROLL_TRACK[4])
    local sbThumb = CreateFrame("Frame", "ForteXorcistOptionsScrollThumb", sbTrack)
    sbThumb:SetSize(C.SCROLL_THUMB_W, C.SCROLL_THUMB_MIN)
    sbThumb:SetPoint("TOPLEFT", sbTrack, "TOPLEFT",
        (C.SCROLL_W - C.SCROLL_THUMB_W) / 2, 0)
    local thArt = sbThumb:CreateTexture(nil, "BACKGROUND")
    thArt:SetPoint("TOPLEFT", sbThumb, "TOPLEFT", 0, 0)
    thArt:SetPoint("BOTTOMRIGHT", sbThumb, "BOTTOMRIGHT", 0, 0)
    thArt:SetTexture(TEX .. "Aluminium")
    thArt:SetVertexColor(C.SCROLL_THUMB[1], C.SCROLL_THUMB[2],
        C.SCROLL_THUMB[3], C.SCROLL_THUMB[4])
    sbThumb:Hide()
    sbTrack:Hide()
    self.scrollTrack, self.scrollThumb = sbTrack, sbThumb

    -- ---- module index --------------------------------------------------
    self:BuildIndex(f)

    -- ESC closes (UIParentPanelManager.CloseSpecialWindows contract: array
    -- entries are GLOBAL FRAME NAMES, hidden via _G[name]:Hide()). The sim's
    -- native table is a proxy; tInsert on it is inert, direct indexing works.
    if type(UISpecialFrames) == "table" then
        local name = "ForteXorcistOptionsWindow"
        local present = false
        for i = 1, #UISpecialFrames do
            if UISpecialFrames[i] == name then present = true break end
        end
        if not present then
            UISpecialFrames[#UISpecialFrames + 1] = name
        end
        self.inSpecialFrames = true
    end

    self:ApplyPosition()
    self.window = f
    return f
end

--- 4 columns x N rows of full-width colour-coded buttons (icon chip + gold
--- label on a module-tinted Aluminium bar). Unbuilt pages: dimmed + 'not
--- built yet'.
function O:BuildIndex(f)
    local idx = CreateFrame("Frame", nil, f)
    idx:SetSize(C.WIN_W - 16, indexHeight())
    idx:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, C.INSET_BOTTOM)
    self.indexFrame = idx
    self.indexButtons = {}

    local cellW = (idx:GetWidth() - (C.INDEX_COLS + 1) * C.INDEX_GAP) / C.INDEX_COLS
    local TEX = "Interface\\AddOns\\Forte_Core\\Textures\\"
    for i, entry in ipairs(O.INDEX) do
        local col = (i - 1) % C.INDEX_COLS
        local row = math.floor((i - 1) / C.INDEX_COLS)
        local btn = CreateFrame("Button", nil, idx)
        btn:SetSize(cellW, C.INDEX_CELL_H)
        btn:SetPoint("TOPLEFT", idx, "TOPLEFT",
            C.INDEX_GAP + col * (cellW + C.INDEX_GAP),
            -(C.INDEX_GAP + row * (C.INDEX_CELL_H + C.INDEX_GAP)))
        local art = btn:CreateTexture(nil, "BACKGROUND")
        art:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
        art:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
        art:SetTexture(TEX .. "Aluminium")
        local c = entry.colour
        art:SetVertexColor(c[1] * 0.75, c[2] * 0.75, c[3] * 0.75, 0.95)
        local chip = btn:CreateTexture(nil, "ARTWORK")
        chip:SetTexture(TEX .. "Aluminium")
        chip:SetSize(12, 12)
        chip:SetPoint("TOPLEFT", btn, "TOPLEFT", 6, -6)
        chip:SetVertexColor(c[1], c[2], c[3], 1)
        local label = W.fontString(btn, "GameFontHighlightSmall", entry.label, WC.GOLD)
        label:SetJustifyH("CENTER")
        label:SetPoint("BOTTOM", btn, "BOTTOM", 0, 4)

        local built = self.pages[entry.id] ~= nil
        btn.pageId = entry.id
        if built then
            btn:SetScript("OnClick", function() self:SetPage(entry.id) end)
        else
            btn:Disable()
            art:SetAlpha(0.45)
            chip:SetAlpha(0.45)
            label:SetTextColor(0.6, 0.52, 0.2, 1)
        end
        W.attachTip(btn, built and ("Open the " .. entry.label .. " page")
            or "not built yet", entry.label)
        self.indexButtons[i] = btn
    end
end

-- ------------------------------------------------------------- page glue --
--- The page builder passed to a page's build(b): owns the vertical cursor
--- over the page frame and the section bookkeeping.
local function newBuilder(o, page)
    local vpW = o.viewport:GetWidth()
    local b = {
        page = page, o = o, y = 0, width = vpW,
        gutter = 6, sectionGap = 8, rowGap = WC.ROW_GAP,
    }

    local function place(frame, h)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", page.frame, "TOPLEFT", 0, -b.y)
        b.y = b.y + h + b.rowGap
    end
    b.place = place

    --- The page-opening "Some Tips" section: 3-4 help lines (s.TEXT law).
    function b.Tips(lines)
        return b.Section("Some Tips", function(s)
            for _, line in ipairs(lines) do s.TEXT(line) end
        end)
    end

    --- Section(title, fillFn(s), opts). fillFn adds rows through s.CHK/...
    function b.Section(title, fillFn, opts)
        opts = opts or {}
        local pad, y0, w = 0, b.y, b.width
        local secFrame = CreateFrame("Frame", nil, page.frame)
        secFrame:SetWidth(w)

        local bar = W.SECTION(secFrame, {
            title = title, width = w,
            collapsed = page.collapsed[title],
            tip = opts.tip,
            onToggle = function(collapsed)
                page.collapsed[title] = collapsed
                o:LayoutPage(page)
            end,
            onResetAll = (opts.module and opts.keys) and function()
                for _, k in ipairs(opts.keys) do
                    FX.Settings:Reset(opts.module, k)
                end
                o:RefreshPage(page)
            end or nil,
        })

        local content = CreateFrame("Frame", nil, secFrame)
        -- Polish pass defect 4: the bar and its content box are the SAME
        -- width (bar.width == content width); the rows keep their 12px
        -- visual inset as an inner offset, not a narrower content box.
        -- Rows begin BELOW the 22px section bar: at offset 0 every row 0
        -- sat on the bar and all sections overprinted (defect 1 pass).
        content:SetWidth(w)
        content:SetPoint("TOPLEFT", secFrame, "TOPLEFT", 0, -WC.SECTION_H)
        local INSET = 12

        local sec = {
            frame = secFrame, bar = bar, content = content, title = title,
            widgets = {}, collapsed = bar.collapsed, lines = {},
        }

        -- Row cursor inside the section content. Two columns (the
        -- original's shape): col 1 stacks at x = 0, col 2 at x = half
        -- width, each advancing its OWN y so every row anchors strictly
        -- below the previous row of its column (the old shared cursor
        -- reset col 2 to y 0 and overprinted it, defect 1).
        local colW = (content:GetWidth() - 2 * INSET - b.gutter) / 2
        local colX = { INSET, INSET + colW + b.gutter }
        local colY = { 0, 0 }
        local nextCol = 1
        local rowStep = WC.ROW_H + b.rowGap

        local function slot()
            local col = nextCol
            nextCol = (col == 1) and 2 or 1
            local y = colY[col]
            colY[col] = y + rowStep
            return colX[col], y, colW
        end

        local function cursorBottom()
            return math.max(colY[1], colY[2])
        end

        local function fullRow()
            local y = cursorBottom()
            colY[1], colY[2] = y + rowStep, y + rowStep
            return INSET, y, content:GetWidth() - 2 * INSET
        end

        local function addWidget(kind, spec)
            -- STR and INFO rows span the full row width (polish pass
            -- defect 3): their value region needs the whole width
            -- between the 38% label column and the recycle zone, which a
            -- 2-column cell cannot give (span > 1 = full-row law).
            if (kind == "STR" or kind == "INFO") and not spec.span then
                spec.span = 2
            end
            local x, y, w
            if spec.span and spec.span > 1 then x, y, w = fullRow()
            else x, y, w = slot() end
            -- The row frames are laid out by the column cursor: stamp the
            -- slot width so the row is not 0px wide (controls were pinned
            -- to a zero-width row's right edge = the label, defect 5).
            spec.width = spec.width or w
            local widget = W[kind](content, spec)
            widget.row:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y)
            sec.widgets[#sec.widgets + 1] = widget
            return widget
        end

        local s = {}
        for _, kind in ipairs({ "CHK", "NUM", "SLD", "COL", "STR", "INFO" }) do
            s[kind] = function(spec) return addWidget(kind, spec) end
        end
        --- Full-width help line (Tips law): plain left text inside the
        --- section's inner inset.
        function s.TEXT(text)
            local y = cursorBottom()
            colY[1], colY[2] = y + rowStep, y + rowStep
            local lineW = content:GetWidth() - 2 * INSET
            local line = W.TIPS_LINE(content, text, lineW)
            line:SetPoint("TOPLEFT", content, "TOPLEFT", INSET, -y)
            sec.lines[#sec.lines + 1] = line
            return line
        end
        fillFn(s)

        local contentH = cursorBottom()
        content:SetHeight(math.max(contentH, 1))
        local totalH = WC.SECTION_H + (bar.collapsed and 0 or contentH)
        secFrame:SetHeight(math.max(totalH, WC.SECTION_H))
        sec.contentH = contentH
        secFrame:SetPoint("TOPLEFT", page.frame, "TOPLEFT", 0, -y0)
        b.y = y0 + totalH + b.sectionGap
        page.sections[#page.sections + 1] = sec
        return sec
    end

    function b.TipRow(line)
        local w = b.width
        place(W.TIPS_LINE(page.frame, line, w), WC.ROW_H)
    end

    return b
end

--- Build (once) and show a page; rebuild the header for it.
function O:SetPage(pageId)
    local def = self.pages[pageId]
    if not def then return end
    if not self.window then return end
    self.pageId = pageId

    if not self.pagesBuilt then self.pagesBuilt = {} end
    local page = self.pagesBuilt[pageId]
    if not page then
        page = {
            id = pageId, def = def, collapsed = {},
            frame = CreateFrame("Frame", nil, self.content),
            sections = {},
        }
        page.frame:SetWidth(self.content:GetWidth())
        page.frame:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, 0)
        local b = newBuilder(self, page)
        def.build(b)
        page.contentH = b.y
        page.frame:SetHeight(math.max(b.y, 1))
        self.pagesBuilt[pageId] = page
    end
    for id, p in pairs(self.pagesBuilt) do
        if id == pageId then p.frame:Show() else p.frame:Hide() end
    end
    self:LayoutPage(page)
    self:BuildHeader(def)
    self._scroll = 0
    self:ApplyScroll()
end

--- Show/hide section content after a collapse and recompute the content
--- height the wheel scrolls through.
function O:LayoutPage(page)
    local total = 0
    for _, sec in ipairs(page.sections) do
        sec.bar.collapsed = page.collapsed[sec.title] and true or false
        sec.bar:repaint()
        if sec.bar.collapsed then
            sec.content:Hide()
            sec.frame:SetHeight(WC.SECTION_H)
        else
            sec.content:Show()
            sec.frame:SetHeight(WC.SECTION_H + sec.contentH)
        end
        total = total + sec.frame:GetHeight() + 8
    end
    self.contentHeight = total
    self.content:SetHeight(math.max(total, self.viewport:GetHeight()))
    -- Restack the section frames top-down (positions depend on collapses).
    local y = 0
    for _, sec in ipairs(page.sections) do
        sec.frame:ClearAllPoints()
        sec.frame:SetPoint("TOPLEFT", page.frame, "TOPLEFT", 0, -y)
        y = y + sec.frame:GetHeight() + 8
    end
    page.frame:SetHeight(math.max(y, 1))
    self:ApplyScroll()
end

function O:RefreshPage(page)
    for _, sec in ipairs(page.sections) do
        for _, widget in ipairs(sec.widgets) do
            widget.refresh()
        end
    end
    local h = self.header
    if h then
        if h.scale then h.scale.refresh() end
        if h.alpha then h.alpha.refresh() end
    end
end

--- The per-page module header bar (module-tinted, gear/lock left, title
--- centre, scale/alpha + category recycle right).
function O:BuildHeader(def)
    if self.header and self.header.bar then self.header.bar:Hide() end
    local head = W.HEADER(self.window, {
        title = def.title,
        barName = "ForteXorcistOptionsHeaderBar",
        colour = def.colour,
        width = C.WIN_W - 16,
        lockTip = def.lockKey and "Click to lock/unlock module frames"
            or "module frames are not movable from here",
        onLock = def.lockKey and function()
            FX.Settings:Set(def.module, def.lockKey,
                not FX.Settings:Get(def.module, def.lockKey))
        end or nil,
        onResetAll = function()
            FX.Settings:Reset(def.module)
            self:RefreshPage(self.pagesBuilt[self.pageId])
        end,
        scaleSpec = def.scaleKey and {
            module = def.module, key = def.scaleKey, label = "scale",
            name = "ForteXorcistOptionsHeaderScale",
            width = 96, numWidth = 48,
            min = C.HEAD_SCALE_RANGE[1], max = C.HEAD_SCALE_RANGE[2], step = 0.1,
            tip = "Frame scale (" .. C.HEAD_SCALE_RANGE[1] .. ".."
                .. C.HEAD_SCALE_RANGE[2] .. ")",
        } or nil,
        alphaSpec = def.alphaKey and {
            module = def.module, key = def.alphaKey, label = "alpha",
            name = "ForteXorcistOptionsHeaderAlpha",
            width = 96, numWidth = 48,
            min = C.HEAD_ALPHA_RANGE[1], max = C.HEAD_ALPHA_RANGE[2], step = 0.05,
            tip = "Frame alpha (" .. C.HEAD_ALPHA_RANGE[1] .. ".."
                .. C.HEAD_ALPHA_RANGE[2] .. ")",
        } or nil,
    })
    head.bar:SetPoint("TOPLEFT", self.window, "TOPLEFT", 8,
        -(C.TITLE_H + C.TABS_H))
    head.bar:SetSize(C.WIN_W - 16, C.HEAD_H)
    self.header = head
    local locked = def.lockKey and FX.Settings:Get(def.module, def.lockKey)
    head.setLockedVisual(locked and true or false)

    -- The lock icon tracks the setting. The listener is registered once per
    -- module (page switches rebuild the header; the listener resolves the
    -- live header through self.header).
    if def.lockKey then
        self._lockWired = self._lockWired or {}
        if not self._lockWired[def.module] then
            self._lockWired[def.module] = true
            local module, lockKey = def.module, def.lockKey
            FX.Settings:OnChange(module, function(key, value)
                local h = self.header
                if key == lockKey and h and h.setLockedVisual then
                    h.setLockedVisual(not not value)
                end
            end)
        end
    end
end

-- ---------------------------------------------------------------- scroll --
function O:Scroll(delta)
    if not self.content then return end
    local maxScroll = math.max(0, self.contentHeight - self.viewport:GetHeight())
    self._scroll = math.max(0, math.min(maxScroll, (self._scroll or 0) - delta))
    self:ApplyScroll()
end

function O:ApplyScroll()
    if not self.content then return end
    self.content:ClearAllPoints()
    -- Positive y offset moves UP in WoW anchors: scrolling reveals content
    -- below by moving the scroll child up by the scroll amount.
    self.content:SetPoint("TOPLEFT", self.viewport, "TOPLEFT",
        0, self._scroll or 0)
    self:UpdateScrollbar()
end

--- Track visible iff the content overflows the viewport. Thumb height =
--- viewportH/contentH x trackH (min C.SCROLL_THUMB_MIN); top offset =
--- scroll/maxScroll of the free span, so the thumb sits flush with the
--- track top at offset 0 and with the track bottom at max offset.
function O:UpdateScrollbar()
    local tr, th = self.scrollTrack, self.scrollThumb
    if not tr then return end
    local vpH = self.viewport:GetHeight()
    local contentH = self.contentHeight or 0
    local trackH = tr:GetHeight()
    local maxScroll = contentH - vpH
    if maxScroll <= 0 then
        tr:Hide()
        th:Hide()   -- the sim's IsShown does not read the parent chain
        return
    end
    tr:Show()
    local h = vpH / contentH * trackH
    if h < C.SCROLL_THUMB_MIN then h = C.SCROLL_THUMB_MIN end
    th:SetHeight(h)
    local frac = (self._scroll or 0) / maxScroll
    th:ClearAllPoints()
    th:SetPoint("TOPLEFT", tr, "TOPLEFT",
        (C.SCROLL_W - C.SCROLL_THUMB_W) / 2, -frac * (trackH - h))
    th:Show()
end

-- --------------------------------------------------------------- open/close --
function O:Open(pageId)
    self:Build()
    self.window:Show()
    self:SetPage(pageId or self.pageId or "General")
    self:ApplyPosition()
end

function O:Close()
    if not self.window then return end
    self:SavePosition()
    self.window:Hide()
end

function O:Toggle(pageId)
    if self:IsOpen() then self:Close() else self:Open(pageId) end
end

function O:IsOpen()
    return self.window ~= nil and self.window:IsShown()
end

-- ------------------------------------------------------------- slash seam --
-- /fx options and /fx config toggle the window (FX.RegisterSlash lands in
-- Forte_Core/Core/Init.lua). Registered at load time; Forte_Core is a hard
-- dependency, so the seam exists before this chunk runs.
FX.RegisterSlash("options", function() O:Toggle() end)
FX.RegisterSlash("config", function() O:Toggle() end)
FX.RegisterSlash("opt", function() O:Toggle() end)

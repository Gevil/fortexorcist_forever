-- addon/Forte_Messages/UI/Banner.lua
-- The optional ON-SCREEN self message. NEW, deliberately: the source search
-- (Core/Channel.lua's header carries the full evidence) found the original's
-- Self Messages to be chat-frame lines only -- no raid-warning frame, no
-- message frame anywhere in /tmp/fxref. The task asks for a "configurable
-- on-screen message ... with a duration" on the ready/expire events, and the
-- owner ruling (PLAN §9 2026-11-01) is to build what is needed and label
-- what is new; the pages label this banner new in their tips.
--
-- Laws it obeys:
--   * the hidden-frame law (the 2026-11-02 uiforever finding): a HIDDEN frame
--     never receives OnUpdate, so the frame is SHOWN synchronously at the
--     message itself, and the clock is the module's C_Timer ticker -- the
--     always-live driver, the Forte_Cooldown/Module.lua:525 /
--     Forte_Timer/Module.lua:579 pattern. No frame OnUpdate exists at all;
--   * the UI-test law: activity starts through the public path (FX.Fire of
--     the bus event) and the test asserts IsShown() -- this file exposes no
--     render function a test could be tempted to call;
--   * the font law: URW Gothic (FX.CLASSIC_FONT, the owner's ruling), set in
--     a pcall with the template as the fallback, exactly as
--     Forte_Options/Core/Widgets.lua:validateFont does for the window;
--   * no RegisterEvent, no CreateFrame at file load -- everything is created
--     from the module's OnEnable (the frame law).
--
-- The show law: Show(text, colour, seconds) stamps the window on the
-- module's clock; Update (the ticker) fades the last FADE_SECONDS out of it
-- and hides it at the end. Re-Show extends -- a fresh message owns the
-- window from now (no frame churn, the frame-pool law PLAN §3.4).

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
FX.Messages = FX.Messages or {}

local Banner = {}
FX.Messages.Banner = Banner

local TEXTURE_FONT = "Interface\\AddOns\\Forte_Core\\Fonts\\URWGothic-Book.ttf"
local FONT_SIZE = 16

Banner.DEFAULT = { point = "CENTER", relPoint = "CENTER", x = 0, y = -200 }
Banner.FADE_SECONDS = 0.5
Banner.counts = { shown = 0, expired = 0 }
Banner.active = false
Banner.now = nil          -- injectable clock (the tests freeze it)

function Banner:Clock()
    if self.now then return self.now() end
    return GetTime()
end

--- Build the frame. Called from the module's OnEnable only.
function Banner:Init()
    if self.frame then return self end
    local f = CreateFrame("Frame", "FXMessagesBanner", UIParent)
    f:SetSize(420, 30)
    f:ClearAllPoints()
    f:SetPoint(self.DEFAULT.point, UIParent, self.DEFAULT.relPoint,
        self.DEFAULT.x, self.DEFAULT.y)
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    fs:SetText("")
    fs:SetJustifyH("CENTER")
    fs:SetPoint("CENTER", f, "CENTER", 0, 0)
    local file = FX.CLASSIC_FONT
        or TEXTURE_FONT
    -- The Widgets.validateFont round trip: accepted only when GetFont hands
    -- the file back; the GameFont template carries the text otherwise.
    local okFont = pcall(fs.SetFont, fs, file, FONT_SIZE, "OUTLINE")
    if okFont then
        local okGet, got = pcall(fs.GetFont, fs)
        if not (okGet and type(got) == "string") then okFont = false end
    end
    if not okFont then
        pcall(fs.SetFontTemplate, fs, "GameFontHighlightLarge")
    end
    f:Hide()
    self.frame, self.text = f, fs
    self.active = false
    return self
end

--- Show one message for `seconds` (the per-event duration the task's
--- options expose). Synchronous: the frame is up before the call returns.
function Banner:Show(text, colour, seconds)
    if not self.frame then return false end
    seconds = tonumber(seconds) or 3
    if seconds < 0.5 then seconds = 0.5 end
    if seconds > 10 then seconds = 10 end
    local c = type(colour) == "table" and colour or { 1, 1, 0, 1 }
    self.text:SetText(tostring(text))
    pcall(self.text.SetTextColor, self.text,
        tonumber(c[1]) or 1, tonumber(c[2]) or 1, tonumber(c[3]) or 1,
        tonumber(c[4]) or 1)
    self.frame:SetAlpha(1)
    self.frame:Show()
    self.expireAt = self:Clock() + seconds
    self.active = true
    self.counts.shown = self.counts.shown + 1
    return true
end

--- The ticker pass. Fades the tail of the window and retires it. Returns
--- true while a window is live (the tests' liveness probe).
function Banner:Update(now)
    if not self.active then return false end
    now = now or self:Clock()
    local left = self.expireAt - now
    if left <= 0 then
        self.frame:Hide()
        self.frame:SetAlpha(1)
        self.active = false
        self.counts.expired = self.counts.expired + 1
        return false
    end
    local fade = self.FADE_SECONDS
    if left < fade then
        self.frame:SetAlpha(math.max(0, math.min(1, left / fade)))
    end
    return true
end

--- The last geometry a test can read (dump-tree pairs with these).
function Banner:Geometry()
    if not self.frame then return nil end
    return self.frame:GetWidth(), self.frame:GetHeight()
end

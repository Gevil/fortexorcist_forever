-- addon/Forte_Warlock/UI/Soulstone.lua
-- FX.Warlock.Soulstone: the Soulstone Tracker — the original's plate
-- (Forte_Soulstone.xml:122-146, every constant cited in UI/Frame.lua): the
-- SS1 icon at the plate's left (Forte_Soulstone.xml:182), the live-stone
-- count `x<n>` next to it (the count format of Forte_Soulstone.lua:292), the
-- right label `no ss up` while no stone is up (Forte_Soulstone.lua:291 with
-- Localization.lua:57) and the remaining clock while one is, and the second
-- line: the bearer's name at the bar's left, the `mm:ss` at its right
-- (Forte_Soulstone.xml:42-51, :14-27), the bar draining with the window.
--
-- All STATE lives in Core/Tools.lua's SoulstoneTracker (`docs/warlock-tools.md`
-- — the single-owner ledger, the expiry window, the one target string, the
-- "swept stone is a window, not a read"); this file is a pure renderer of
-- `:Active()`, `:Target()`, `:Remaining()`, `:Duration()` (PLAN §3.4 "pure
-- renderer").
--
-- Law line (docs/reference-functional-spec.md §4, SS-01…SS-06): the widget
-- runs its OWN timer — it is not a cooldown-bar entry — and it counts the
-- window DOWN from the tracked expiry, never from a fresh constant.
--
-- Show law: the PLATE is the module's standing readout — it rides the module
-- switch (the original's `SoulstoneEnable`, Forte_Soulstone.lua:55, and its
-- idle plate prints `no ss up`, Forte_Soulstone.lua:291). A warlock's login
-- is a KNOWN idle state (the module's PLAYER_ENTERING_WORLD kick), so the
-- plate has a claim from then on; the second line lives only while a window
-- does. This widens the pre-v2 "hidden while idle" law by the plate only —
-- the window, the fill and the second line retire exactly as before.
--
-- The target law: the tracker hands over ONE string it owns (the bearer
-- captured at the stone's STARTED cast); the frame never reads unit fields,
-- so it can not pick a secret value up. An unread bearer renders
-- `(target unread)` — SS-11's honesty, printed, never hidden.
--
-- The 10 Hz law: `Update` returns TRUE while a window is live, so
-- UI/Module.lua keeps the driver running for it; when the window expires the
-- second line retires with it, the plate staying on `no ss up`.
--
-- Skin/position/settings/lock/clock: the shared law in UI/Frame.lua.
-- Settings (module "Warlock"): SoulstoneWidth (the plate width),
-- SoulstoneHeight (the second-line bar height, the original's
-- SoulstoneHeight, Forte_Soulstone.lua:671), SoulstoneColor (the bar colour,
-- Forte_Soulstone.xml:119), SoulstoneStrikethrough; the shared keys ride
-- `General`.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
FX.Warlock = FX.Warlock or {}

local Frame = FX.Warlock.Frame
local Stone = Frame:new({
    name = "Soulstone",
    dbKey = "soulstone",
    size = { Width = 106, Height = 20, Point = "CENTER", X = 60, Y = -215 },
    module = "Warlock",
    sharedModule = "General",
    -- The Advanced page's strata row of this plate (the source's
    -- `SoulstoneStrata`, Forte_Soulstone.lua:645).
    advancedKey = "SoulstoneStrata",
    lockKey = "Lock",
    keys = { "SoulstoneWidth", "SoulstoneHeight", "SoulstoneColor",
             "SoulstoneStrikethrough", "SoulstoneExpand",
             "SoulstoneShowReady", "SoulstoneReadyColour" },
    keymap = {
        SoulstoneEnable = "SetEnabled",
        SoulstoneWidth = "SetWidth",             -- the plate width
        SoulstoneHeight = "SetRowHeight",        -- the bar height, :671
        SoulstoneColor = "SetBarColor",          -- Forte_Soulstone.xml:119
        SoulstoneStrikethrough = "SetStrikethrough",
        -- FWL.EXPAND_UP ("Determines if the bar lists should be expanded
        -- upwards or downwards", Forte_Core.lua:243-244), the original's
        -- `SoulstoneExpand` (Forte_Soulstone.lua:604, def false :674).
        SoulstoneExpand = "SetExpandUp",
        -- The READY-look gate: the original's `ShowReady`
        -- (Forte_Soulstone.lua:608, def false :667) over its `ReadyColor`
        -- (the "Resurrect" row, def {1,1,0} :651). The 2012 right label
        -- picks `no ss up` vs `ready to res` off exactly this pair
        -- (:309, FWL.READY_TO_RES Localization.lua:56).
        SoulstoneShowReady = "SetShowReady",
        SoulstoneReadyColour = "SetReadyColour",
    },
})
FX.Warlock.Soulstone = Stone

local TEX = "Interface\\AddOns\\Forte_Core\\Textures\\"

FX.Warlock.SoulstoneSkin = setmetatable({
    Width = 106, Height = 20,
    RowHeight = 12,                              -- Forte_Soulstone.lua:671
    IconTexture = TEX .. "SS1",                  -- Forte_Soulstone.xml:182
    BarColor = { 0.64, 0.21, 0.93, 1 },           -- Forte_Soulstone.xml:119
    -- The "Resurrect" colour (the original's ReadyColor, the ready-to-res
    -- label's tint, Forte_Soulstone.lua:651).
    ReadyColour = { 1.00, 1.00, 0.00, 1 },
    TextSize = 11,                               -- Forte_Core.lua:2547
}, { __index = FX.Warlock.FrameSkin })
Stone.skin = FX.Warlock.SoulstoneSkin
Stone.sizeDefaults = { Width = 106, Height = 20, Point = "CENTER",
                       X = 60, Y = -215 }

-- The plate's idle right label (Forte_Soulstone.lua:291 + Localization.lua:57).
Stone.NO_SS_UP = "no ss up"
-- The ready right label (`FWL.READY_TO_RES`, Localization.lua:56; the 2012
-- plate prints it in the `else` of its `s2 == s1` stone-count test,
-- Forte_Soulstone.lua:309 -- with no stone up and nothing ready it prints
-- `no ss up`).
Stone.READY_TO_RES = "ready to res"

--- The READY-look gate (the original's `ShowReady`, Forte_Soulstone.lua:608,
--- def false :667): with it off the idle plate never claims readiness.
function Stone:SetShowReady(on)
    self._showReady = not not on
    self._idleLabel = nil
end

--- The ready label's colour (the "Resurrect" colour row, def {1,1,0}
--- Forte_Soulstone.lua:651).
function Stone:SetReadyColour(col)
    if type(col) ~= "table" then return end
    self._readyColour = { col[1] or 1, col[2] or 1, col[3] or 1, col[4] or 1 }
    self._idleLabel = nil
end

-- ----------------------------------------------------------------- the art --

function Stone:SizeChangedHook()
    self:SetFillFraction(self._fillFrac or 1)
end

--- The plate's right label while a window runs: the compact remaining clock
--- (the plate's Time string, Forte_Soulstone.lua:291 — one tracked stone, so
--- the range collapses to its single endpoint).
function Stone:FormatInfo(remaining)
    return Frame.FormatClock(remaining)
end

-- ------------------------------------------------------------------ update --

--- One render pass; TRUE while a window is live (the driver keeps ticking).
function Stone:Update(now)
    local t = self.Tracker
    local live = false
    local remaining, duration, target
    if t and self:Enabled() and t:Active() then
        remaining = t:Remaining()
        if type(remaining) == "number" then
            live = true
            duration = t:Snapshot().duration
            target = t:Target()
        end
    end
    -- The plate rides the module switch (the standing `no ss up` readout).
    self:SetShown(self:Enabled() and self.state.master)
    if not self:Enabled() then return false end
    -- The second line lives with the window (SS-09's retire law).
    self:SetRowShown(live)
    -- The count slot: the live stones of the ledger, `x<n>`
    -- (Forte_Soulstone.lua:292) — one window tracked, x1 live, x0 idle.
    local n = live and "x1" or "x0"
    if n ~= self._amt then
        self._amt = n
        self.amountFS:SetText(n)
    end
    if live then
        self._idleLabel = nil
        -- The fill drains with the window (SS-01: "fills as the timer runs").
        local frac = 1
        if type(duration) == "number" and duration > 0 then
            frac = remaining / duration
            if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
        end
        if frac ~= self._frac then
            self._frac = frac
            self:SetFillFraction(frac)
        end
        local key = Frame.ClockKey(remaining)
        if key ~= self._timeKey then
            self._timeKey = key
            local clock = Frame.FormatClock(remaining)
            self.timeFS:SetText(clock)
            self.infoFS:SetText(self:FormatInfo(remaining))
        end
        local who = Frame.FormatTarget(target)
        if who ~= self._target then
            self._target = who
            self.nameFS:SetText(who)
        end
    else
        self._frac, self._timeKey, self._target = nil, nil, nil
        self:DrawIdleLabel(t)
    end
    self:ApplyTextVisibility()
    return live
end

--- The idle right label: `no ss up`, or the READY-look the original prints
--- when the warlock has no stone up and is ready to put a new one up
--- (Forte_Soulstone.lua:309, gated by `ShowReady` :608/:667 and tinted by the
--- "Resurrect" colour :651). The tracker owns the state (`:Ready()`: a
--- window ran out and no newer stone replaced it).
function Stone:DrawIdleLabel(t)
    local ready = self._showReady and t and t.Ready and t:Ready()
    local label = ready and self.READY_TO_RES or self.NO_SS_UP
    if label ~= self._idleLabel then
        self._idleLabel = label
        self.infoFS:SetText(label)
        if ready then
            self:SetStringColor(self.infoFS,
                self._readyColour or FX.Warlock.SoulstoneSkin.ReadyColour)
        else
            self:SetStringColor(self.infoFS, self:TextColour())
        end
    end
end

function Stone:RenderIdle()
    self._frac, self._timeKey, self._target, self._amt = nil, nil, nil, nil
    self._idleLabel = nil
    self:SetRowShown(false)
    self:SetShown(false)
    self.amountFS:SetText("")
    self.infoFS:SetText("")
    self.nameFS:SetText("")
    self.timeFS:SetText("")
end

--- The injected-tracker seam (tests, launch-day probes).
function Stone:SetTracker(tracker)
    self.Tracker = tracker
    self._frac, self._timeKey, self._target, self._amt = nil, nil, nil, nil
    self._idleLabel = nil
end

function Stone:StatusLine()
    local t = self.Tracker
    local active = t and t:Active()
    return string.format("Soulstone Tracker: %s%s | %dx%d | %s",
        active and "window" or self.NO_SS_UP,
        active and (" " .. Frame.FormatClock(t:Remaining())) or "",
        self.skin.Width, self.skin.Height,
        self:Enabled() and "on" or "off")
end

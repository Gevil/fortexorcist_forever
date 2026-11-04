-- scene: the Cooldown Timer bar -- spells going on cooldown IN SEQUENCE, the
-- icons sliding left along the power-scale axis, and the ready moments firing
-- the Timeline spark/pulse plus the Secondary Splash. Manual clock, 30 fps.
--
-- All the state is the Engine's own: `E:Build('HUNTER', ...)` from the
-- generated data, then `E:OnCast(name, startStamp)` -- a backdated stamp, the
-- way a capture loop seeds a cooldown that is already partly burned. The pops
-- run through the module's real ready path (M:ProcessReadyPops) and the
-- splash through S:Update: no display-side fakery.
--
-- Beats are FRACTIONS of the clip (FXD.SECONDS is the driver's clip length),
-- so the geometry peak frame always has a pop live on screen: the crop unions
-- the bar and the splash window, and the splash window is anchored to the
-- bar's top-right (a demo-scene placement, never an addon default) to keep the
-- box tight.
local X = ForteXorcist
local E = X.Cooldown.Engine
local D = X.Cooldown.Display
local S = X.Cooldown.Splash
local M = X.Cooldown.Module

local SECONDS = FXD.SECONDS or 5
local function at(frac) return math.floor(SECONDS * 30 * frac + 0.5) end

-- The long windows: the right-hand end of the axis.
local LONG = { { "Rapid Fire", 300 }, { "Freezing Trap", 280 }, { "Intimidation", 120 } }
-- The windows that pop ready INSIDE the clip, at these fractions of it.
local POPS = { { "Concussive Shot", 0.22 }, { "Multi-Shot", 0.44 },
               { "Viper Sting", 0.62 }, { "Mongoose Bite", 0.85 } }
-- Casts that ARRIVE mid-clip: the icon enters at the right end and slides.
local ARRIVALS = { { "Aimed Shot", 0.18 }, { "Kill Shot", 0.38 },
                   { "Raptor Strike", 0.58 }, { "Arcane Shot", 0.78 } }

local function cast(name)
    local t = E.tracked[name]
    if not t then ADD("untracked_" .. name) return nil end
    E:OnCast(name, GetTime())
    return t
end

FXD.SET = function()
    E:Build("HUNTER", function() return true end)
    E.OnRead = function() end
    if X.Settings and X.Settings.Set then X.Settings:Set("Splash", "Enable", true) end
    S:SetEnabled(true)
    if S.anchor and D.anchor then
        S.anchor:ClearAllPoints()
        S.anchor:SetPoint("BOTTOMRIGHT", D.anchor, "TOPRIGHT", 0, 12)
    end
    local function seed(name, left)
        local t = E.tracked[name]
        if t and (t.baseDuration or 0) >= left then
            E:OnCast(name, GetTime() + left - t.baseDuration)
            return 1
        end
        return 0
    end
    local n = 0
    for _, row in ipairs(LONG) do n = n + seed(row[1], row[2]) end
    for _, row in ipairs(POPS) do n = n + seed(row[1], row[2] * SECONDS) end
    local ch = E.tracked["Freezing Trap"]
    if ch then ch.maxCharges = 3 end
    FXD.Mark("seeded", n)
    FXD.Mark("tracked", (function()
        local k = 0
        for _ in pairs(E.tracked) do k = k + 1 end
        return k
    end)())
end

for _, row in ipairs(ARRIVALS) do
    local slot = at(row[2])
    rawset(FXD.EV, slot, function()
        ADD("arrive_" .. row[1])
        cast(row[1])
    end)
end

FXD.U = function()
    local t = GetTime()
    M:ProcessReadyPops(t + 0.001)
    D:Update(E:Sorted({}), t)
    S:Update(t)
    local n = 0
    for _ in pairs(D._byName) do n = n + 1 end
    FXD.Mark("icons", n)
    FXD.Mark("splash", (S.anchor and S.anchor.IsShown and S.anchor:IsShown()) and 1 or 0)
end

FXD.BOX = function()
    FXD.B(D.anchor)
    -- The splash window counts only while it is on screen; the peak frame has
    -- a pop live (see POPS), which is the frame the crop is measured from.
    if S.anchor and S.anchor.IsShown and S.anchor:IsShown() then
        FXD.B(S.anchor, 26)
    end
end

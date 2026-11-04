-- scene: the Hunter swing bar IN COMBAT -- the shipped event spine, nothing
-- injected: A_Admin.FireEvent("PLAYER_SWING", swingTime,
-- Enum.PlayerSwingType.Ranged) starts each swing (the tracker's
-- OnSwingStart gates on the Ranged swing type), and the shot is a real cast
-- of a shot-family spell (the tracker's SHOT_CAST_SET: Aimed / Multi-Shot /
-- Steady Shot) -- SENT, START, SUCCEEDED with one cast GUID. The bar then
-- draws its own loop: the orange reload fill, the red stand-still aim slice
-- (aimLen = the aim ratio of the swing), the white safe-to-move / flying
-- window after the shot lands.
--
-- The spell id is read out of the GENERATED class data by name; the swing
-- type rides the tracker's own measured rangedType. Beat times are fractions
-- of the clip (FXD.SECONDS), so the cycle always fills the frame.
local X = ForteXorcist
local T = X.Hunter.Tools
local SW = X.Hunter.Swing

local DATA = X.Data and (X.Data.Hunter or X.Data.HUNTER)
local function idof(name)
    if type(DATA) ~= "table" then return nil end
    for id, d in pairs(DATA) do
        if type(d) == "table" and d.name == name then return id end
    end
    return nil
end

local SECONDS = FXD.SECONDS or 6
local function at(frac) return math.floor(SECONDS * 30 * frac + 0.5) end
local CYCLE = { 0.03, 0.36, 0.69 }        -- a swing every ~2 s of the clip
local SWING_TIME = 2.0                  -- the payload's swing length

FXD.SET = function()
    A_Admin.SetInCombat(true)
    A_Admin.SetTarget("Ragnaros", 73, 1, true)
    -- The frames follow the class (OnClassChanged), and the scene owns the
    -- clock from here: make sure the bar exists before the first frame.
    if SW.Init then pcall(SW.Init, SW) end
    if SW.SetEnabled then SW:SetEnabled(true) end
    if SW.SetShowTime then SW:SetShowTime(true) end
    if SW.SetShowAimSlice then SW:SetShowAimSlice(true) end
    if SW.SetShowSafeWindow then SW:SetShowSafeWindow(true) end
    if SW.SetShowFlying then SW:SetShowFlying(true) end
    if SW.SetBaseSpeed then SW:SetBaseSpeed(2.0) end
    FXD.rt = (T and T.Swing and T.Swing.rangedType) or 2
    FXD.shot = idof("Multi-Shot")
    FXD.Mark("swingtype", FXD.rt)
    FXD.Mark("anchor", (SW.anchor and 1) or 0)
    FXD.Mark("shotid", FXD.shot or "none")
    if not FXD.shot then ADD("NOSHOTID") end
    for i, frac in ipairs(CYCLE) do
        local s = at(frac)
        rawset(FXD.EV, s, function()
            A_Admin.FireEvent("PLAYER_SWING", SWING_TIME, FXD.rt)
            ADD("swing" .. i)
        end)
        rawset(FXD.EV, s + 18, function()
            if FXD.shot then
                A_Admin.FireEvent("UNIT_SPELLCAST_SENT", "player", "Ragnaros",
                    "FXDSHOT" .. i, FXD.shot)
            end
        end)
        rawset(FXD.EV, s + 20, function()
            if FXD.shot then
                A_Admin.FireEvent("UNIT_SPELLCAST_START", "player",
                    "FXDSHOT" .. i, FXD.shot)
            end
        end)
        rawset(FXD.EV, s + 50, function()
            if FXD.shot then
                A_Admin.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player",
                    "FXDSHOT" .. i, FXD.shot, 1)
                ADD("shot" .. i)
            end
        end)
        rawset(FXD.EV, s + 56, function()
            A_Admin.FireEvent("PLAYER_SWING_RANGE_UPDATE", FXD.rt, true, false)
        end)
    end
end

FXD.U = function()
    if SW.Update then SW:Update(GetTime()) end
    FXD.Mark("phase", tostring(SW._phase))
    FXD.Mark("shown", (SW.anchor and SW.anchor.IsShown and SW.anchor:IsShown()) and 1 or 0)
end

FXD.BOX = function()
    FXD.B(SW.anchor)
end

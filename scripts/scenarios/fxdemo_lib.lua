-- fxdemo_lib.lua -- the driver library every scripts/scenarios/<clip>.lua runs on.
--
-- CONTRACT (a scene file defines these, the driver calls them):
--   FXD.SET()   state at clock 0 (trackers, casts, settings)      -- once
--   FXD.EV[k]   the scripted event beats of frame slot k          -- optional
--   FXD.U()     the module redraw pass (Kick/Update/Draw) + FXD.Mark facts
--   FXD.BOX()   call FXD.B(frame) for every frame the clip owns
--
-- The driver appends `FXD.SET() FXD.b={} FXD.U() FXD.BOX()`, then per frame
-- `for fk=0,K do FXD.Frame(fk) end FXD.BOX()`.
--
-- PUBLISHING (the only channel that survives this simulator): the scene's
-- crop boxes and proof facts travel as INERT MARKER FRAMES. A marker is a
-- plain frame (no textures, never shown on purpose) named `FXDB_<owner>` for a
-- box or `FXDM_<fact>` for a proof line, anchored TOPLEFT to UIParent at
-- px/scale with size px/scale. The run's --dump-tree then prints its DEVICE
-- PIXEL rect -- `ForteXorcistCooldownAnchor (421x40) x=589, y=832` from
-- GetRect l=349.074 b=193.556 -- which is exactly what --crop consumes.
-- scripts/demo/geometry.py reads the markers back and proves them against the
-- real frames. (A FontString readout does NOT work here: SetText on a frame
-- made in a --exec-lua chunk of any size leaves the string unsized --
-- measured 2026-11-03, seven variants -- so nothing in this pipeline uses text.)
--
-- GEOMETRY LAW (measured 2026-11-03, wow-ui-sim v0.1.39):
--   * f:GetRect() answers in UI UNITS of the current UIParent scale.
--   * screenshot --width W --height H --ui-scale S lays the UI out at W/S units
--     wide, writes a W x H image: 1 UI unit = S px.
--   * the same run's --dump-tree prints device px.
--   So a box is GetRect x S, with S measured (phys / UIParent width), never
--   assumed. The v2 clips cropped with UI-unit boxes at --ui-scale 1.6875, so
--   every crop sat up-left of its frame at 1/1.6875 of its size.
--
-- BLIZZARD FURNITURE: FXD.Clean() hides what the headless boot shows (tutorial
-- strip, chat, micro buttons, action bars, auras, minimap, the PTR
-- issue-report button). The headless renderer draws no cursor. geometry.py
-- fails a clip whose crop a visible Blizzard frame overlaps.
local min, max = math.min, math.max
FXD = { EV = {}, b = {}, mark = {} }

local UP = UIParent

-- Device pixels of the capture canvas, and px per UI unit (see the law).
local function phys()
    local w, h = GetPhysicalScreenSize()
    if type(w) ~= "number" or type(h) ~= "number" or w <= 0 then
        return UP:GetWidth(), UP:GetHeight(), 1
    end
    local uw, uh = UP:GetWidth(), UP:GetHeight()
    if uw <= 0 or uh <= 0 then return w, h, 1 end
    return w, h, ((w / uw) + (h / uh)) * 0.5
end
local PW, PH, SCALE = phys()
FXD.scale = SCALE

-- The marker host. It and its markers paint nothing (plain frames with no
-- regions), so they are free in the render and visible to the dump.
local host = CreateFrame("Frame", "FXDPROBE", UP)
host:SetPoint("TOPLEFT", UP, "TOPLEFT", 0, 0)
host:SetSize(1, 1)
FXD.host = host

local function clean(name)
    return (tostring(name):gsub("[^%w]", "_"):sub(1, 56))
end

-- marker <name> <x> <y> <w> <h>  (device px; the marker stores units)
local function marker(name, x, y, w, h)
    local m = FXD.mark[name]
    if not m then
        m = CreateFrame("Frame", name, host)
        FXD.mark[name] = m
    end
    m:ClearAllPoints()
    m:SetPoint("TOPLEFT", UP, "TOPLEFT", x / SCALE, y / SCALE)
    m:SetSize(max(1, w) / SCALE, max(1, h) / SCALE)
    return m
end

-- FXD.Mark <key> <value>: a proof fact the driver prints and asserts on.
function FXD.Mark(key, value)
    marker("FXDM_" .. clean(key) .. "_" .. clean(value), 0, 0, 2, 2)
end

-- The scenes' shorthand: one fact line per call (key=value pairs are fine).
function ADD(text) FXD.Mark("note", text) end

-- FXD.B <frame>: publish the frame's crop box (a small margin, in UI units).
FXD.PAD = 10
function FXD.B(f, pad)
    if type(f) ~= "table" or not f.GetRect then return nil end
    pad = pad or FXD.PAD
    local l, b, w, h = f:GetRect()
    local x = max(0, math.floor((l - pad) * SCALE + 0.5))
    local y = max(0, math.floor((UP:GetHeight() - b - h - pad) * SCALE + 0.5))
    local ww = min(math.floor(PW) - x, math.ceil((w + 2 * pad) * SCALE))
    local hh = min(math.floor(PH) - y, math.ceil((h + 2 * pad) * SCALE))
    if ww < 4 or hh < 4 then return nil end
    local name = f.GetName and f:GetName() or "?"
    table.insert(FXD.b, { x, y, ww, hh })
    marker("FXDB_" .. clean(name), x, y, ww, hh)
    return x, y, ww, hh
end

-- The Blizzard furniture a scene must never show (shipped frame names; names
-- this build does not have are skipped).
FXD.HIDDEN = {
    "NPE_TutorialMainFrame_Frame", "NPE_BaseInstruction_Frame",
    "NPE_CompleteFrame", "NPE_LoadedFrame",
    "AdventureMapFrame", "MapFrame", "WorldMapFrame", "Minimap",
    "MinimapClusterFrame", "VistaOverlayFrame", "TaskPOIFrame",
    "ChatFrame", "ChatFrameBG", "ChatFrameEditBox", "ChatFrameDockFrame",
    "PetPaperFrame", "PaperDollFrame", "PlayerFrame", "PlayerScoreboard",
    "HelpPlate", "HelpPlateBackground",
    "PTR_IssueReporter", "PTR_IssueReporterMainView", "UIPanelBugButton",
    "OpenIssueReport", "IssueReportButton", "BugSackFrame",
    "MainMenuBar", "MainBar",
    "ActionBar1", "ActionBar2", "ActionBar3", "ActionBar4", "ActionBar5",
    "ActionBar6", "BonusActionBarFrame", "PetActionBarFrame",
    "OverrideActionBar", "OverrideActionBarFrame",
    "BuffFrame", "PlayerAuras", "PlayerCastingBar", "CastingBar",
    "TargetFrame", "TargetCastingBar", "FocusFrame", "PartyFrame",
    "StancePanel", "ComboFrame", "LootFrame", "QuestFrame", "QueueFrame",
    "ReadyCheckFrame", "GameTooltip", "ItemRefTooltip", "AnchorTooltip",
    "AchievementMicroButton", "PlayerSpellsMicroButton",
    "CharactersMicroButton", "QuestLogMicroButton", "SpellBookMicroButton",
    "TalentsMicroButton", "AbilitiesMicroButton", "PvpMicroButton",
    "FriendsMicroButton", "CommunityMicroButton", "GameMenuMicroButton",
    "EncounterJournal", "TalentMicroButton",
}

-- Hide the furniture and publish how many were found.
function FXD.Clean()
    local hit = 0
    for _, n in ipairs(FXD.HIDDEN) do
        local g = _G[n]
        if type(g) == "table" and g.Hide then
            pcall(g.Hide, g)
            hit = hit + 1
        end
    end
    FXD.Mark("hidden", hit)
    return hit
end

-- The clock and the frame engine: one scripted 1/30 s step per frame slot.
FXD.dt = 1 / 30
A_Admin.SetManualClock(0)
FXD.Mark("canvas", PW .. "x" .. PH)
FXD.Mark("scale", string.format("%.4f", SCALE))

function FXD.Frame(k)
    local e = rawget(FXD.EV, k)
    if e then e() end
    A_Admin.AdvanceTime(FXD.dt)
    FXD.b = {}
    FXD.U()
end

FXD.Clean()

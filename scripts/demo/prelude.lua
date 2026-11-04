-- prelude.lua -- the boot chunk of every STATIC demo scene (scripts/demo/*.lua,
-- run by scripts/demo_media.sh's `scene`). It publishes the scene's crop boxes
-- and proof facts as inert marker frames, exactly like the clip driver library
-- scripts/scenarios/fxdemo_lib.lua, and hides the Blizzard furniture the
-- headless boot shows.
--
-- Publishing law (measured 2026-11-03, wow-ui-sim v0.1.39): a FontString built
-- in a --exec-lua chunk never takes its SetText, so facts and boxes travel as
-- marker FRAMES: `FXDB_<owner>` carries the crop rect in its geometry,
-- `FXDM_<fact>` carries text in its name, and the run's --dump-tree prints
-- both in DEVICE PIXELS -- the numbers `screenshot --crop` consumes.
--
-- GEOMETRY LAW: f:GetRect() answers in UI UNITS of the active UIParent scale;
-- `screenshot --width W --height H --ui-scale S` lays the UI out W/S units wide
-- and writes a W x H image, so 1 UI unit = S device px (measured: a 250x24 bar
-- at uiScale 1.6875 prints (421x40) x=589 y=832 from GetRect l=349.074
-- b=193.556; 349.074 * 1.6875 = 589.0). BX multiplies by the MEASURED factor; at
-- the default --ui-scale 1 that factor is 1.0, the historical 1:1 map.
local F, C = math.floor, math.ceil
local UP = UIParent

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

local host = CreateFrame("Frame", "FXDPROBE", UP)
host:SetPoint("TOPLEFT", UP, "TOPLEFT", 0, 0)
host:SetSize(1, 1)

local marks = {}
local function clean(name)
    return (tostring(name):gsub("[^%w]", "_"):sub(1, 56))
end
local function marker(name, x, y, w, h)
    local m = marks[name]
    if not m then
        m = CreateFrame("Frame", name, host)
        marks[name] = m
    end
    m:ClearAllPoints()
    m:SetPoint("TOPLEFT", UP, "TOPLEFT", x / SCALE, y / SCALE)
    m:SetSize(math.max(1, w) / SCALE, math.max(1, h) / SCALE)
    return m
end

-- ADD: one proof fact (scenes pass "n=4,rows=3" style strings).
local notes = 0
local function ADD(s)
    notes = notes + 1
    marker("FXDM_note" .. notes .. "_" .. clean(s), 0, 0, 2, 2)
end

-- BX: the crop box of one frame, +pad UI units of margin, published in DEVICE PX.
local function BX(f, pad)
    pad = pad or 12
    local l, b, w, h = f:GetRect()
    local x = math.max(0, F((l - pad) * SCALE + 0.5))
    local y = math.max(0, F((UP:GetHeight() - b - h - pad) * SCALE + 0.5))
    local ww = math.min(F(PW) - x, C((w + 2 * pad) * SCALE))
    local hh = math.min(F(PH) - y, C((h + 2 * pad) * SCALE))
    marker("FXDB_" .. clean(f.GetName and f:GetName() or "?"), x, y, ww, hh)
end

-- The Blizzard furniture the headless boot draws: a scene's crop must contain
-- ForteXorcist frames only (scripts/demo/geometry.py proves it).
for s in string.gmatch("NPE_TutorialMainFrame_Frame NPE_BaseInstruction_Frame "
    .. "AdventureMapFrame ChatFrame ChatFrameEditBox AchievementMicroButton "
    .. "PlayerSpellsMicroButton CharactersMicroButton QuestLogMicroButton "
    .. "SpellBookMicroButton TalentsMicroButton AbilitiesMicroButton "
    .. "PvpMicroButton FriendsMicroButton CommunityMicroButton "
    .. "GameMenuMicroButton HelpPlate PTR_IssueReporter Minimap MainBar "
    .. "ActionBar1 ActionBar2 BuffFrame PlayerFrame", "[%w_]+") do
    local g = _G[s]
    if g and g.Hide then g:Hide() end
end

marker("FXDM_canvas_" .. tostring(F(PW)) .. "x" .. tostring(F(PH)), 0, 0, 2, 2)
marker("FXDM_scale_" .. string.format("%.4f", SCALE), 0, 0, 2, 2)

-- Scenes work against a clock just ahead of the boot's last OnUpdate.
local T = GetTime() + 0.02

-- Forte_Dev/Panel.lua
-- The readable panel under the beacon: stamp, build, suite, pass/fail/skip counts, the first 12 failing
-- tests with their details (up to 3 wrapped lines each), the last 5 recorded errors (FX.db.errors.list),
-- the last 3 DevCommands results (ForteDevDB.commands). For the manager to read in
-- a crop of the top-left 30% x 45% of a screenshot. A plain frame + background texture + fontstring; no
-- OnUpdate, no mouse. `/fxdev panel off` hides it; the beacon row stays.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
local Dev = FX.Dev

local Panel = {}
Dev.Panel = Panel

Panel.WIDTH = 620
Panel.MAX_FAILS = 12
Panel.MAX_ERRORS = 5
Panel.MAX_COMMANDS = 3
Panel.FAIL_NAME_CLIP = 60          -- characters of a failing test's name
Panel.FAIL_DETAIL_CLIP = 160       -- = Dev.DETAIL_MAX: the whole stored detail, no panel-side "..."
Panel.FAIL_LINES = 3               -- wrapped lines one failure may take
Panel.CHARS_PER_LINE = 80          -- conservative wrap estimate: GameFontHighlightSmall in 608 units
Panel.LINE_HEIGHT = 12             -- UI units per wrapped line (small font), for the size estimate
Panel.CMD_VERB_CLIP = 50
Panel.CMD_DETAIL_CLIP = 100

--- Escape a dynamic string for a FontString ("|" starts an escape sequence).
local function esc(s)
    return (tostring(s):gsub("|", "||"))
end

--- Characters a line shows once colour escapes are gone and "||" is one pipe (for wrap estimates).
function Panel.VisibleLen(line)
    local s = tostring(line):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("||", "|")
    return #s
end

--- Estimated wrapped lines of the whole panel text (every "\n" line wraps at CHARS_PER_LINE).
function Panel.EstimateLines(text)
    local n = 0
    for line in (tostring(text) .. "\n"):gmatch("(.-)\n") do
        n = n + math.max(1, math.ceil(Panel.VisibleLen(line) / Panel.CHARS_PER_LINE))
    end
    return n
end

--- The panel text (pure; reads ForteDevDB / FX.db.errors only).
function Panel.Text()
    local db = Dev.DB()
    local st = Dev.state
    local run = st.lastRun or db.runs[#db.runs]
    local lines = {}
    lines[#lines + 1] = string.format("Forte_Dev  %s", esc(db.stamp))
    lines[#lines + 1] = string.format("build %s   class %s   runId %d   in combat %s   armed %s",
        esc(db.build), esc(tostring(Dev.classToken())), db.runId, tostring(Dev.inCombat()), tostring(st.armed))
    if type(run) == "table" then
        lines[#lines + 1] = string.format("run #%s  suite %s  pass %s  fail %s  skip %s%s", tostring(run.id),
            esc(tostring(run.suite)), tostring(run.pass), tostring(run.fail), tostring(run.skip),
            run.combat and "  (combat)" or "")
        local shown = 0
        for _, t in ipairs(type(run.tests) == "table" and run.tests or {}) do
            if type(t) == "table" and t.status == "fail" then
                shown = shown + 1
                if shown <= Panel.MAX_FAILS then
                    lines[#lines + 1] = "|cffff5555FAIL|r " .. esc(Dev.clip(tostring(t.name), Panel.FAIL_NAME_CLIP))
                        .. ": " .. esc(Dev.clip(tostring(t.detail), Panel.FAIL_DETAIL_CLIP))
                end
            end
        end
        if shown > Panel.MAX_FAILS then
            lines[#lines + 1] = "  +" .. (shown - Panel.MAX_FAILS) .. " more failures"
        end
    else
        lines[#lines + 1] = "no run yet (/fxdev selftest ooc)"
    end
    local e = FX.db and FX.db.errors
    local list = type(e) == "table" and type(e.list) == "table" and e.list or nil
    if list and #list > 0 then
        lines[#lines + 1] = "errors (last " .. math.min(#list, Panel.MAX_ERRORS) .. " of " .. #list .. "):"
        for i = math.max(1, #list - Panel.MAX_ERRORS + 1), #list do
            local x = list[i]
            if type(x) == "table" then
                lines[#lines + 1] = "|cffffaa55" .. esc(tostring(x.kind)) .. "|r " .. esc(Dev.clip(tostring(x.msg), 110))
                    .. " x" .. esc(tostring(x.count))
            end
        end
    elseif FX.Errors == nil then
        lines[#lines + 1] = "errors: FX.Errors absent"
    else
        lines[#lines + 1] = "errors: none recorded"
    end
    local cmds = type(db.commands) == "table" and db.commands or {}
    if #cmds > 0 then
        lines[#lines + 1] = "commands (last " .. math.min(#cmds, Panel.MAX_COMMANDS) .. " of " .. #cmds .. "):"
        for i = math.max(1, #cmds - Panel.MAX_COMMANDS + 1), #cmds do
            local c = cmds[i]
            if type(c) == "table" then
                lines[#lines + 1] = (c.ok and "|cff55ff55ok|r " or "|cffff5555FAIL|r ")
                    .. esc(Dev.clip(tostring(c.verb), Panel.CMD_VERB_CLIP)) .. ": "
                    .. esc(Dev.clip(tostring(c.detail), Panel.CMD_DETAIL_CLIP))
            end
        end
    end
    if st.lastError then lines[#lines + 1] = "dev error: " .. esc(st.lastError) end
    return table.concat(lines, "\n")
end

function Panel.Build()
    if Panel.frame then return Panel.frame end
    local f = _G.CreateFrame("Frame", "ForteDevPanel", _G.UIParent)
    f:SetFrameStrata("TOOLTIP")
    f:SetSize(Panel.WIDTH, 60)
    f:SetPoint("TOPLEFT", _G.UIParent, "TOPLEFT", 0, -8)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    bg:SetColorTexture(0, 0, 0, 0.75)
    local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -4)
    text:SetWidth(Panel.WIDTH - 12)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    Panel.frame, Panel.bg, Panel.text = f, bg, text
    return f
end

function Panel.Paint()
    Panel.Build()
    if not Dev.state.panelOn then
        Panel.frame:Hide()
        return
    end
    Panel.text:SetText(Panel.Text())
    local okH, h = pcall(Panel.text.GetStringHeight, Panel.text)
    h = okH and Dev.plain(h)
    Panel.frame:SetHeight((type(h) == "number" and h > 0 and h or 48) + 10)
    Panel.frame:Show()
end

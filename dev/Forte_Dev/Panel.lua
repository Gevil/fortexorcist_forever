-- Forte_Dev/Panel.lua
-- The readable panel under the beacon: stamp, build, suite, pass/fail/skip counts, the first 12 failing
-- tests with their details, the last 5 recorded errors (FX.db.errors.list). For the manager to read in
-- a crop of the top-left quarter of a screenshot. A plain frame + background texture + fontstring; no
-- OnUpdate, no mouse. `/fxdev panel off` hides it; the beacon row stays.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
local Dev = FX.Dev

local Panel = {}
Dev.Panel = Panel

Panel.WIDTH = 620
Panel.MAX_FAILS = 12
Panel.MAX_ERRORS = 5

--- Escape a dynamic string for a FontString ("|" starts an escape sequence).
local function esc(s)
    return (tostring(s):gsub("|", "||"))
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
                    lines[#lines + 1] = "|cffff5555FAIL|r " .. esc(Dev.clip(tostring(t.name), 60)) .. ": "
                        .. esc(Dev.clip(tostring(t.detail), 110))
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

-- Forte_Dev/Beacon.lua
-- The machine-readable beacon in the game's own screenshot (PLAN §11.11 contract): one row of 16 square
-- cells, 6 UI units each (96x6), anchored at UIParent TOPLEFT (0,0), strata TOOLTIP, each cell a solid
-- colour texture.
--   cell 0   magenta (1,0,1)     cell 15  cyan (0,1,1)       (the decoder's markers)
--   cells 1-14: black = 0, white = 1
--     1 in combat   2 in a group   3 selftest running   4 selftest finished since load
--     5 last run had a failure     6 FX.Errors.sinceLoad > 0
--     7-14 the low 8 bits of ForteDevDB.runId, cell 7 = most significant
-- "running" (cell 3) is 1 while a run executes AND while the combat suite is armed and waiting, so a
-- poller never mistakes an armed-but-unfired combat run for a finished one.
--
-- Plain frame + textures only, no OnUpdate, no events of its own: it is repainted by Dev.Repaint (run
-- events, PLAYER_REGEN_*, GROUP_ROSTER_UPDATE, /fxdev shot). Only REGION methods are called on the
-- textures (the real client throws on Frame-only methods on regions).

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
local Dev = FX.Dev

local Beacon = {}
Dev.Beacon = Beacon

Beacon.CELL = 6
Beacon.COUNT = 16
Beacon.cells = {}

local MAGENTA, CYAN = { 1, 0, 1 }, { 0, 1, 1 }
local BLACK, WHITE = { 0, 0, 0 }, { 1, 1, 1 }

--- Pure encoder. flags = { combat, group, running, finished, failed, errors } (booleans).
--- Returns cols[0..15] = { r, g, b }.
function Beacon.Encode(flags, runId)
    local function bit(on) return on and WHITE or BLACK end
    local cols = { [0] = MAGENTA }
    cols[1] = bit(flags.combat)
    cols[2] = bit(flags.group)
    cols[3] = bit(flags.running)
    cols[4] = bit(flags.finished)
    cols[5] = bit(flags.failed)
    cols[6] = bit(flags.errors)
    local low = math.floor(tonumber(runId) or 0) % 256
    for i = 0, 7 do
        local mask = 2 ^ (7 - i)
        cols[7 + i] = bit(math.floor(low / mask) % 2 == 1)
    end
    cols[15] = CYAN
    return cols
end

--- The live flags + runId.
function Beacon.Flags()
    local st = Dev.state
    local db = Dev.DB()
    local last = db.runs[#db.runs]
    local E = FX.Errors
    local errs = type(E) == "table" and Dev.plain(E.sinceLoad) or nil
    return {
        combat = Dev.inCombat(),
        group = Dev.inGroup(),
        running = (st.running or st.armed) and true or false,
        finished = st.finished and true or false,
        failed = type(last) == "table" and type(last.fail) == "number" and last.fail > 0,
        errors = type(errs) == "number" and errs > 0,
    }, db.runId
end

function Beacon.Build()
    if Beacon.frame then return Beacon.frame end
    local size = Beacon.CELL
    local f = _G.CreateFrame("Frame", "ForteDevBeacon", _G.UIParent)
    f:SetFrameStrata("TOOLTIP")
    f:SetSize(size * Beacon.COUNT, size)
    f:SetPoint("TOPLEFT", _G.UIParent, "TOPLEFT", 0, 0)
    for i = 0, Beacon.COUNT - 1 do
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetSize(size, size)
        t:SetPoint("TOPLEFT", f, "TOPLEFT", i * size, 0)
        t:SetColorTexture(0, 0, 0, 1)
        Beacon.cells[i] = t
    end
    f:Show()
    Beacon.frame = f
    return f
end

function Beacon.Paint()
    Beacon.Build()
    local flags, runId = Beacon.Flags()
    local cols = Beacon.Encode(flags, runId)
    for i = 0, Beacon.COUNT - 1 do
        local c = cols[i]
        Beacon.cells[i]:SetColorTexture(c[1], c[2], c[3], 1)
        -- Every channel is 0 or 1, so tinting the colour texture by the same colour is idempotent
        -- (c * c == c): it renders right whether or not the client multiplies the vertex colour in, and
        -- GetVertexColor reports the cell's colour (what the tests assert through the texture API).
        Beacon.cells[i]:SetVertexColor(c[1], c[2], c[3], 1)
    end
    Beacon.painted = cols
    return cols
end

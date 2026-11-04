-- scene: the Spell Timer's debuff rows, driven ONLY through the shipped event
-- spine: A_Admin.FireEvent("UNIT_SPELLCAST_SENT", unitTarget, target, castGUID,
-- spellID) and ("UNIT_SPELLCAST_SUCCEEDED", unitTarget, castGUID, spellID,
-- castBarID). The payload law is the module's own (Module:OnEvent):
-- unitTarget first, then the target token as an opaque key. `CastQueue`
-- resolves the id through C_Spell.GetSpellInfo, keeps the SENT record, and the
-- SUCCEEDED inserts the row SETTLE (0.2 s) later -- every row on screen is the
-- Engine's, swept by Rows:Sweep and drawn by Rows:Draw.
--
-- Which spells are the beats is DERIVED, never typed: the class data's spells
-- that carry a duration (the row's length) and that the runtime can resolve
-- and the Registry has registered. The set gate is the class registry's, so
-- the driver runs this clip under the class whose data is richest in timed
-- debuffs (Warlock -- Curse of Elements, Seed of Corruption, Immolate ...).
local X = ForteXorcist
local Mod = X.Timer.Module
local Rows = X.Timer.Rows
local Casts = X.Timer.Casts
local Registry = X.Timer.Registry

local CLASS = X._playerClass
-- FX.Data is keyed by the class's *file* name (`Warlock`, `Hunter`), the
-- player class is the uppercase form -- map one to the other.
local function classdata()
    local D = X.Data
    if type(D) ~= "table" then return nil end
    if type(D[CLASS]) == "table" then return D[CLASS] end
    local key = tostring(CLASS):sub(1, 1) .. tostring(CLASS):sub(2):lower()
    return type(D[key]) == "table" and D[key] or nil
end
local DATA = classdata()
if not DATA then ADD("nodata") end

local function durationof(d)
    for _, k in ipairs({ "durationMs", "auraDurationMs", "debuffDurationMs" }) do
        local v = d[k]
        if type(v) == "number" and v > 0 then return v end
    end
    return nil
end

-- The timed spells of this class the Registry knows AND the running client can
-- resolve by id -- the cast queue's own first gate is `C_Spell.GetSpellInfo(id)
-- .name` (Casts:NameOf), and a spell the client's build does not know is dropped
-- before a row can exist. ids drift per build (PLAN §8), so this is measured at
-- runtime, never assumed: the newest spells (Bane of Havoc, Soulstone
-- Resurrection ...) are the ones a pre-release catalogue answers nil for.
local function resolves(id, name)
    if type(C_Spell) ~= "table" or type(C_Spell.GetSpellInfo) ~= "function" then
        return true
    end
    local ok, info = pcall(C_Spell.GetSpellInfo, id)
    if not ok or type(info) ~= "table" then return false end
    local nm = X.Compat and X.Compat.PlainOrNil and X.Compat.PlainOrNil(info.name)
    return type(nm) == "string" and nm == name
end

local beats = {}
if DATA then
    for _, d in pairs(DATA) do
        if type(d) == "table" and type(d.name) == "string" and d.id then
            local dur = durationof(d)
            if dur and Registry and Registry.entries and Registry.entries[d.name]
                and resolves(d.id, d.name) then
                beats[#beats + 1] = { id = d.id, name = d.name, dur = dur }
            end
        end
    end
    table.sort(beats, function(a, b)
        return a.dur > b.dur or (a.dur == b.dur and a.name < b.name)
    end)
end
local ROWS = math.min(#beats, 5)
if ROWS < 2 then ADD("toofewtimed_" .. ROWS) end

-- The target token: a real name string the queue keys opaquely.
A_Admin.SetTarget("Ragnaros", 73, 1, true)
A_Admin.SetInCombat(true)

local SECONDS = FXD.SECONDS or 5
local function at(frac) return math.floor(SECONDS * 30 * frac + 0.5) end

FXD.SET = function()
    FXD.Mark("class", tostring(CLASS))
    FXD.Mark("timed", ROWS)
    FXD.Mark("regcount", (function()
        local n = 0
        for _ in pairs(Registry and Registry.entries or {}) do n = n + 1 end
        return n
    end)())
    -- One cast per beat, spaced across the clip; every row rides a cast GUID,
    -- so five live rows coexist on screen.
    for i = 1, ROWS do
        local b = beats[i]
        local slot = at(0.04 + (i - 1) * 0.14)
        local guid = "FXDT" .. i
        rawset(FXD.EV, slot, function()
            A_Admin.FireEvent("UNIT_SPELLCAST_SENT", "player", "Ragnaros", guid, b.id)
            ADD("sent_" .. b.name)
        end)
        rawset(FXD.EV, slot + 6, function()
            A_Admin.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", guid, b.id, 1)
            ADD("ok_" .. b.name)
        end)
    end
end

FXD.U = function()
    Mod:Logic()
    Mod:Kick()
    FXD.Mark("rows", Rows.rows_n)
    FXD.Mark("queued", #Casts.queue)
end

FXD.BOX = function()
    -- The rows frame is the UI module's; the model carries the reference once
    -- the panel has drawn. Under some classes the model's reference is not
    -- published, so the crop falls back to the shipped frame by name.
    local f = Rows.anchor
    if not f then f = _G.ForteXorcistTimerAnchor end
    FXD.B(f)
end

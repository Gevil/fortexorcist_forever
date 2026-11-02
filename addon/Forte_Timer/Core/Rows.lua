-- addon/Forte_Timer/Core/Rows.lua
-- FX.Timer.Rows: the live row table and its laws -- §3.2's row record, §3.3's
-- keying, §3.5's insert/reconcile numbers, §3.6's smoothing and the §1.9
-- lifetime machine. **Zero game API in this file**: every number arrives as an
-- argument from Module.lua / Core/Casts.lua / Core/Reconcile.lua, which is what
-- makes the whole law testable in the sim with an injected clock
-- (tests/test_rows.lua) and what keeps the secret-value rules in the two files
-- that read the game.
--
-- The row (design §3.2): a fixed-shape named table, not the original's 28-slot
-- positional tuple (which the source repeats at every insert site, spec
-- ST-13). Each field names the column it replaces:
--
--   name           col 8   the spell NAME (never an id)
--   targetKey      col 4+11  "none" (self/no-target) | the cast-target string
--                          while unconfirmed | the resolved unit token once an
--                          aura read confirmed it
--   groupKey       col 13  our monotonic per-target id (the CA:GiveID port) or
--                          a Laws.PRIOR_* sentinel for self/no-target
--   expireAt       col 1   the authoritative expiry (the fact or the prediction)
--   drawExpireAt   col 20  the smoothed value the renderer draws (:1046)
--   castTime       col 2   the cast instant (GetTime() units)
--   total          col 3   the window the bar is scaled against
--   state          col 14  -1..4, Laws.* values
--   kind           col 6   the spell type (the colour + fade class)
--   stacks         col 16  written ONLY by an aura read; a predicted row shows
--                          none (Forte_Timer.lua:2467-2471 draws from >0)
--   removeAt       col 17  stamped by Fade()
--   expireMsgAt    col 12  the expiry-message stamp (fires exactly once)
--   id             --      our row id (the CA:GiveID counter of the row itself)
--   hasteFactor    col 22  the frozen out-of-combat haste factor
--   predicted      new     true until an aura read adopts it (UI marking §5.5)
--   unitToken      col 27  the resolved unit token, nil while unconfirmed
--   maxTime        link col 6  the compression scale (:2192-2235)
--   hiddenSince    link col 7  the HideLonger gate's trip stamp (:2151-2162)
--   alpha          link col 4  the visibility computed per pass (:2146-2168)
--
-- The laws, verbatim numbers in Core/Laws.lua:
--   MAXLAG 1.00  the adopt/extend/refresh tolerance (:33, :899-905, :1159-1207)
--   BUFF_DELAY 4.0 the grace before a row may be judged gone (:69, :1186-1187)
--   removal refused while more than MAXLAG remains (:1207)
--   shorter by more than MAXLAG => REFRESH: fade the row, re-insert (:924, ST-25)
--   SMOOTH 5 the drawn-expire interpolation (:1046)

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
FX.Timer = FX.Timer or {}

local Rows = {}
FX.Timer.Rows = Rows

local Laws = FX.Timer.Laws

Rows.rows = {}          -- array 1..rows_n; holes are compacted by Sweep
Rows.rows_n = 0
Rows.byKey = {}         -- Laws.RowKey(name, targetKey) -> index
Rows.nextId = 1         -- the CA:GiveID port: monotonic, recycled from live rows
Rows.links = {}         -- the sort/draw link table, reused every pass
Rows.options = nil      -- set by Module.lua: the live options/gate table

-- ------------------------------------------------------------------- pool --
--- A fresh, fixed-shape row. Allocating only on a genuinely new (spell,
--- target) pair is the whole allocation story: the draw pass allocates nothing
--- (PLAN §3.4).
local function newRow()
    return {
        name = nil, targetKey = nil, groupKey = nil, id = nil,
        expireAt = 0, drawExpireAt = 0, castTime = 0, total = 0,
        state = Laws.NORMAL, kind = "Default", stacks = 0, removeAt = 0,
        expireMsgAt = 0, hasteFactor = 1, predicted = true, unitToken = nil,
        maxTime = 0, hiddenSince = 0, alpha = 1, raidMark = 0, tickEvery = nil,
    }
end

--- The per-target group id (the `CA:GiveID` port, Forte_Casting.lua:680-686:
--- monotonic, per-mob, recycled from live rows). Keyed on the targetKey, which
--- is the cast-target string (design §2: the SENT target string is kept as an
--- opaque key), the resolved unit token once confirmed, or "none" for a self
--- window -- in which case the caller uses a PRIOR_* sentinel instead
--- (Laws.SentinelGroupKey, the :979-985 law).
function Rows:IdFor(targetKey)
    self._ids = self._ids or {}
    local id = self._ids[targetKey]
    if not id then
        id = self.nextId
        self.nextId = self.nextId + 1
        self._ids[targetKey] = id
    end
    return id
end

--- Recycle a target's id when no row of its group survives (spec CA-20).
function Rows:ReleaseId(targetKey)
    if self._ids then self._ids[targetKey] = nil end
end

-- ------------------------------------------------------------------ index --
local function reindex(self)
    wipe(self.byKey)
    for i = 1, self.rows_n do
        local r = self.rows[i]
        if r then self.byKey[Laws.RowKey(r.name, r.targetKey)] = i end
    end
end

--- Close the holes `removeAt` left, keeping the array dense so every pass is a
--- plain 1..n loop.
local function compact(self)
    local n = 0
    local out = self.rows
    for i = 1, self.rows_n do
        local r = out[i]
        if r then
            n = n + 1
            out[n] = r
        end
    end
    for i = n + 1, self.rows_n do out[i] = nil end
    self.rows_n = n
    reindex(self)
end

--- Find a live row by (spell, target) -- the port of `ST_FindSimilarSimple`
--- (:832-841), which matches the spell and the caster identity.
function Rows:Find(name, targetKey)
    local i = self.byKey[Laws.RowKey(name, targetKey)]
    local r = i and self.rows[i]
    if r and r.state <= Laws.REMOVE then return r, i end
    return nil
end

--- Every live row of a spell name into `out` (the aura sweep's lookup: the
--- fact arrives keyed by spell, the rows are keyed by spell+target).
function Rows:AllForName(name, out)
    out = out or {}
    local n = 0
    for i = 1, self.rows_n do
        local r = self.rows[i]
        if r and r.name == name and r.state <= Laws.REMOVE then
            n = n + 1
            out[n] = r
        end
    end
    for i = n + 1, #out do out[i] = nil end
    return out, n
end

--- Append a fully-shaped row and index it. `row` arrives complete.
local function place(self, row)
    local n = self.rows_n + 1
    self.rows[n] = row
    self.rows_n = n
    self.byKey[Laws.RowKey(row.name, row.targetKey)] = n
    return row
end

-- ---------------------------------------------------------------- insert --
--- The insert of a settled own cast (§3.5's `insertFromCast`, the
--- `ST:AddNewTimer` law :888-940 with §3.3's (spell, target) keying).
---
--- `spell` the resolved name, `targetKey` the cast target ("none" for a
--- self/no-target window), `duration` seconds (Registry:BestDuration's
--- answer), `now` the insert instant (GetTime units), `castTime` the cast
--- instant (SETTLE defers the insert, so they differ; the col-2 cast-time
--- value), `hasteFactor` the frozen factor.
---
--- The insert loop's law (:896-935): a same-key row whose expiry matches
--- inside MAXLAG is CORRECTED in place (nothing new is drawn, `exact = true`
--- so no insert happens); a same-key row whose expiry does not match is
--- REMOVED and the row re-inserted (the refresh: a new icon, a new fade,
--- ST-25).
function Rows:InsertFromCast(spell, targetKey, duration, now, castTime,
        hasteFactor, kind)
    if type(spell) ~= "string" or type(duration) ~= "number"
        or duration <= 0 then
        return nil
    end
    targetKey = targetKey or "none"
    hasteFactor = (type(hasteFactor) == "number" and hasteFactor > 0)
        and hasteFactor or 1
    kind = kind or FX.Timer.Registry.KindFor(spell)
    local total = duration * hasteFactor
    local expire = now + total

    local existing, idx = self:Find(spell, targetKey)
    if existing then
        local verdict = Laws.ReconcileVerdict(expire, existing.expireAt)
        if verdict == "adopt" then
            -- :900-905 "exact match, just correct time"
            existing.expireAt = expire
            if math.abs(existing.drawExpireAt - expire) > Laws.MAXLAG then
                existing.total = total
                existing.drawExpireAt = expire
            end
            existing.castTime = castTime or now
            existing.hasteFactor = hasteFactor
            existing.kind = kind
            return existing, "adopted"
        end
        -- :924 `st:remove(i)` -- the window moved by more than MAXLAG: the
        -- old row is dropped (the source removes, it does not fade) and a
        -- fresh row is inserted below.
        self:removeAt(idx)
    end

    local row = newRow()
    row.name = spell
    row.targetKey = targetKey
    row.kind = kind
    row.total = total
    row.expireAt = expire
    row.drawExpireAt = expire
    row.castTime = castTime or now
    row.state = Laws.NORMAL
    row.stacks = 0
    row.removeAt = 0
    row.expireMsgAt = (self.options and self.options.expireMessage) and 1 or 0
    row.hasteFactor = hasteFactor
    row.predicted = true
    row.unitToken = nil
    row.alpha = 1
    row.hiddenSince = 0
    row.raidMark = 0
    row.id = self.nextId
    self.nextId = self.nextId + 1
    row.groupKey = (targetKey == "none")
        and Laws.SentinelGroupKey(kind) or self:IdFor(targetKey)
    place(self, row)
    return row, existing and "refreshed" or "inserted"
end

--- The insert of a *confirmed* aura (the `ST_ScanForMissing` (:1103),
--- `ST_TargetDebuffs` (:1225-1271) and `ST_PlayerBuffs` (:1272-1351) path): a
--- spell we registered whose real aura the sweep found with no row of its own.
function Rows:InsertFromAura(spell, targetKey, expire, total, stacks,
        unitToken, raidMark, now)
    if type(spell) ~= "string" then return nil end
    if type(expire) ~= "number" or type(total) ~= "number" or total <= 0 then
        return nil
    end
    targetKey = targetKey or "none"
    now = now or GetTime()
    local existing = self:Find(spell, targetKey)
    if existing then
        local verdict = self:OnAuraFact(existing, expire, total, stacks, now,
            unitToken, raidMark)
        return existing, verdict
    end
    local row = newRow()
    row.name = spell
    row.targetKey = targetKey
    row.kind = FX.Timer.Registry.KindFor(spell)
    row.total = total
    row.expireAt = expire
    row.drawExpireAt = expire
    row.castTime = now
    row.state = Laws.NORMAL
    row.stacks = (type(stacks) == "number" and stacks) or 0
    row.expireMsgAt = 0
    row.predicted = false
    row.unitToken = unitToken
    row.raidMark = (type(raidMark) == "number" and raidMark) or 0
    row.id = self.nextId
    self.nextId = self.nextId + 1
    row.groupKey = (targetKey == "none")
        and Laws.SentinelGroupKey(row.kind) or self:IdFor(targetKey)
    place(self, row)
    return row, "inserted"
end

-- ------------------------------------------------------------- reconciliation
--- The fact half of the law (§3.5's `onAuraFact`, the :1159-1207 quotes).
--- `factExpire`/`factTotal`/`stacks` arrive PLAIN: Core/Reconcile.lua has
--- already run every field through PlainOrNil and dropped a secret read
--- entirely (a secret read never overwrites known state).
---
---  adopt   |fact - row.expireAt| <= MAXLAG (:900-905, :1159-1164): the fact IS
---           the prediction. Fill the row in: the window, the stacks, the
---           target identity; the row stops being a prediction.
---  extend  the fact is longer (:1184 `if expire > st[i][1] ... then
---           st[i][1] = expire`) -- `total` is NOT rewritten, the source line.
---  refresh shorter by more than MAXLAG (:924, ST-25): fade the row REMOVED
---           (it keeps drawing, fading out) and insert a fresh row with the
---           fact's window, marked confirmed.
function Rows:OnAuraFact(row, factExpire, factTotal, stacks, now,
        unitToken, raidMark)
    if not row then return nil end
    if type(factExpire) ~= "number" then return nil end
    now = now or GetTime()
    local verdict, delta = Laws.ReconcileVerdict(factExpire, row.expireAt)
    if verdict == "adopt" then
        row.expireAt = factExpire
        row.predicted = false
        if type(factTotal) == "number" and factTotal > 0 then
            row.total = factTotal
        end
        if math.abs(row.drawExpireAt - factExpire) > Laws.MAXLAG then
            row.drawExpireAt = factExpire
        end
        if type(stacks) == "number" then row.stacks = stacks end
        if type(unitToken) == "string" then row.unitToken = unitToken end
        if type(raidMark) == "number" then row.raidMark = raidMark end
        return "adopt", delta
    elseif verdict == "extend" then
        row.expireAt = factExpire
        row.predicted = false
        if type(stacks) == "number" then row.stacks = stacks end
        if type(unitToken) == "string" then row.unitToken = unitToken end
        return "extend", delta
    end
    -- refresh (:924 + the ST-25 law "the row is removed and re-inserted: new
    -- icon, new fade")
    self:Fade(row, Laws.REMOVE, now)
    local fresh = newRow()
    fresh.name = row.name
    fresh.targetKey = row.targetKey
    fresh.kind = row.kind
    fresh.total = (type(factTotal) == "number" and factTotal > 0)
        and factTotal or math.max(0, factExpire - now)
    fresh.expireAt = factExpire
    fresh.drawExpireAt = factExpire
    fresh.castTime = now
    fresh.state = Laws.NORMAL
    fresh.predicted = false
    fresh.stacks = (type(stacks) == "number" and stacks) or 0
    fresh.hasteFactor = row.hasteFactor
    fresh.expireMsgAt = 0
    fresh.id = self.nextId
    self.nextId = self.nextId + 1
    fresh.groupKey = (row.targetKey == "none")
        and Laws.SentinelGroupKey(row.kind) or self:IdFor(row.targetKey)
    if type(unitToken) == "string" then fresh.unitToken = unitToken end
    if type(raidMark) == "number" then fresh.raidMark = raidMark end
    -- The refreshed row owns the (spell, target) key from now on; the old row
    -- stays in the array fading out, outside the index.
    self.byKey[Laws.RowKey(row.name, row.targetKey)] = nil
    place(self, fresh)
    return "refresh", delta
end

--- The "the aura is not there" half of the law. Two refusals come first:
---   * the grace (:1186-1187): a row is not checkable before
---     Laws.CheckableAt(castTime) -- the window's start plus BUFF_DELAY;
---   * the removal refusal (:1207, "dont remove if only maxlag left"): while
---     more than MAXLAG of its own window is left the row is never judged gone.
function Rows:OnAuraAbsent(row, now)
    if not row then return nil end
    now = now or GetTime()
    if now < Laws.CheckableAt(row.castTime, row.total) then
        return "grace"
    end
    if Laws.RemovalRefused(row.expireAt, now) then
        return "refused"
    end
    self:Fade(row, Laws.REMOVE, now)
    return "removed"
end

-- ------------------------------------------------------------- the machine --
--- `ST:Fade` (:1008-1017): stamp col 17 with now and col 14 with the mode; an
--- already-IGNORE row goes to zero instantly.
function Rows:Fade(row, mode, now)
    if not row then return end
    now = now or GetTime()
    if row.state == Laws.IGNORE then
        row.expireAt = 0
    elseif row.state ~= mode then
        row.removeAt = now
        row.state = mode
    end
end

--- One logic sweep: `ST_UpdateSpellTimers` (:1038-1077) as a port --
--- smoothing, the expiry message, the NORMAL -> FADING promotion and the
--- delete of a spent row. Deleting here is the source's own discipline
--- ("preferably only remove timers in this function and not outside", :1038).
function Rows:Sweep(now)
    local opts = self.options or {}
    local smooth = opts.smooth or Laws.SMOOTH
    local i = 1
    while i <= self.rows_n do
        local row = self.rows[i]
        if not row then
            i = i + 1
        else
            local remaining = row.expireAt - now
            -- :1046, the smoothing law
            row.drawExpireAt = Laws.Smooth(row.drawExpireAt, row.expireAt,
                smooth)
            -- :1049-1056, the expire message (col 12 stamps once -> 0)
            if row.expireMsgAt > 0 and remaining <= row.expireMsgAt
                and row.state <= Laws.NORMAL then
                row.expireMsgAt = 0
                FX.Timer.NotifyExpiry = (FX.Timer.NotifyExpiry or 0) + 1
                if opts.onExpire then opts.onExpire(row) end
            end
            if row.state == Laws.IGNORE then
                -- :1058-1063 an ignored row dies at zero
                if remaining <= 0 then
                    self:removeAt(i)
                else
                    i = i + 1
                end
            elseif row.state == Laws.NORMAL then
                -- :1064-1068 promote at expiry; the type picks instant vs fade
                if remaining <= 0 and row.total > 0 then
                    local mode = Laws.INSTANT_FADE[row.kind]
                        and Laws.FADING_INSTANT or Laws.FADING
                    self:Fade(row, mode, now)
                end
                i = i + 1
            else
                -- :1070-1076 keep a faded row for its band, then delete it
                if Laws.DeathAt(row.removeAt, row.kind) < now then
                    self:removeAt(i)
                else
                    i = i + 1
                end
            end
        end
    end
    if self._dirty then
        self._dirty = nil
        compact(self)
    end
end

function Rows:removeAt(i)
    local row = self.rows[i]
    if not row then return end
    self.rows[i] = nil
    self._dirty = true
    if self.byKey[Laws.RowKey(row.name, row.targetKey)] == i then
        self.byKey[Laws.RowKey(row.name, row.targetKey)] = nil
    end
end

--- Drop every row: the leave-world / class-change purge (the original's
--- leave-combat purge :2880-2884, the queue erase :776-777).
function Rows:Clear()
    for i = 1, self.rows_n do self.rows[i] = nil end
    self.rows_n = 0
    wipe(self.byKey)
    self._ids = nil
    self._dirty = nil
end

-- ------------------------------------------------------------- the link pass --
--- The draw pass's bookkeeping, the port of :2140-2241: build the link table
--- (row index, group key, drawn expire, visibility, hide-gate stamp, scale),
--- sort it, then apply the per-instance visible cap and the time-band
--- compression. Returns the reused link array plus its length: the renderer
--- takes the index array and touches no allocation (PLAN §3.4).
function Rows:Sorted(out, now)
    out = out or self.links
    local opts = self.options or {}
    local grouping = opts.groupID ~= false
    local n = 0
    for i = 1, self.rows_n do
        local row = self.rows[i]
        if row then
            n = n + 1
            local link = out[n]
            if not link then link = {}; out[n] = link end
            link[1] = i
            link[2] = row.groupKey
            link[3] = row.drawExpireAt
            link[6] = row.maxTime
            link[7] = row.hiddenSince
            -- the visibility of this row (:2146-2168 + the HideLonger gate);
            -- the gate's trip stamp rides the row (link col 7)
            opts.hiddenSince = row.hiddenSince
            local a = Laws.GateAlpha(row.state, row.expireAt, row.removeAt,
                now, opts)
            row.hiddenSince = opts.hiddenSince
            row.alpha = a
            link[4] = a
            link[5] = row.hiddenSince
        end
    end
    for i = n + 1, #out do out[i] = nil end
    table.sort(out, function(a, b)
        return Laws.CompareLinks(a, b, grouping, opts.outwands ~= false)
    end)

    -- the visible cap (:2192 `(not s.Max[0] or visible < s.Max[1]) and
    -- links[k][4] > 0`) + the time-band target (:2195-2212)
    local visible = 0
    local highest = 0
    local cap = (opts.maxTimeOn ~= false) and (opts.maxTime or Laws.MAXTIME)
    for k = 1, n do
        local link = out[k]
        local row = self.rows[link[1]]
        if (not opts.maxOn or visible < (opts.maxRows or 15)) and link[4] > 0 then
            visible = visible + 1
            if opts.oneMax ~= false and not opts.forceMax then
                if row.total > highest then
                    highest = math.min(cap or math.huge, row.total)
                end
            elseif opts.oneMax == false and not opts.forceMax then
                link[6] = math.min(cap or math.huge, row.total)
            end
        else
            link[4] = 0
            row.alpha = 0
        end
    end
    -- :2228-2241, the scale easing: links[k][6] += (target - links[k][6])/smooth
    local smooth = opts.smooth or Laws.SMOOTH
    for k = 1, n do
        local link = out[k]
        local row = self.rows[link[1]]
        if link[4] == 1 then
            local target
            if opts.forceMax then
                target = cap
            elseif opts.oneMax == false then
                target = math.min(cap or math.huge, row.total)
            else
                target = highest
            end
            link[6] = link[6] + (target - link[6]) / smooth
        end
        row.maxTime = link[6]
    end
    return out, n
end

function Rows:Count()
    local n = 0
    for i = 1, self.rows_n do if self.rows[i] then n = n + 1 end end
    return n
end

-- addon/Forte_Warlock/Core/Comms.lua
-- FX.Warlock.Comms: the group COMMS of the H6 trio — the wire protocol, the
-- legality gate, the rate limits and the roster scan — over the model in
-- Core/Group.lua. No frames (the plates are UI/*), no bag/unit reads (the
-- trackers in Core/Tools.lua feed the own-count half). The module table is
-- NOT registered with FX.RegisterModule: the gate's load probe expects the
-- Warlock add-on to carry exactly the `Warlock` + `WarlockUI` modules, so
-- this file rides the `Warlock` module's lifecycle (Core/Tools.lua enables,
-- class-gates and prints it).
--
-- THE WIRE (CA-24's protocol row, docs/reference-functional-spec.md:173,
-- the two-letter vocabulary of Forte_Core.lua:706-712: `SG`/`SH` shards —
-- the REMOVED Shard Spy's surviving half, FE-35 Forte_Core.lua:706,:1531 —
-- `HG`/`HS` healthstones, summon phases the SuS/SuC/SuE of
-- Forte_Casting.lua:44-46): every message is `<CMD><VER>` plus its tiny
-- payload, VER = "1". A decoder accepts the one version it speaks and
-- ignores everything else — a future build's message costs this build one
-- counted byte-run, never a state mutation.
--   HG1 / SG1          — query: "report your healthstones / shards"
--   HS1 <n> / SH1 <n>  — count answer, integer >= 0
--   SU1 <by> <target>  — "<by> started summoning <target>"
--   SE1 <by> <target>  — "<by> stopped summoning <target>"
-- The original sent the same facts as `SendAddonMessage("FX2", …, "RAID")`
-- (Forte_Core.lua:1908-1910) — same channel, same audience, this build's
-- prefix is its own (`C_ChatInfo.RegisterAddonMessagePrefix`,
-- ChatInfoDocumentation.lua:468, result `RegisterAddonMessagePrefixResult`:
-- Success 0 / DuplicatePrefix 1, ChatConstantsDocumentation.lua:132).
--
-- THE LEGALITY HALF — the Announce gate, same shape, same law
-- (addon/Forte_Messages/Core/Announce.lua:79-97 and docs/messages-sounds.md):
-- ONLY a plain `true` from `FX.SecretState.chat` (refreshed at the gate),
-- `C_ChatInfo.InChatMessagingLockdown` (ChatInfoDocumentation.lua:292) or
-- `C_ChatInfo.AreOutgoingAddonChatMessagesRestricted` (:10) skips a send —
-- the SecretState consumer law, an unknown never suppresses — and a skipped
-- send is SILENT and COUNTED (`/fx status` prints the ate-list). Every send
-- is pcall'd; a raising send is counted, never propagated. The channel is
-- RAID in a raid and PARTY in a party (the Announce:Group routing), and the
-- assignment's default is a LAW here, not a default: with no group there is
-- no channel, so solo sends never leave the client (counted `noGroup`).
-- The 12.x warning this design obeys: addon comms must FUNCTION without the
-- comms (wow-api-combat RETAIL-12-0-CHANGES.md:214-218) — every spy degrades
-- to its solo self (own count, own channel plate), the comms only ADD.
--
-- THE RATE LAW — never faster than the original's:
--   * a query answer at most once per 5 s per family (the original's
--     `FW.LastHSCheck + 5 < GetTime()` guard around its HS response,
--     Forte_Core.lua:2434-2441);
--   * a query burst on roster change at most once per 5 s (the original's
--     queries ride PARTY/RAID join events, Forte_Core.lua:2295,
--     Forte_Healthstone.lua:268);
--   * an own-count announce at most once per AnnounceGap (the user's
--     `HealthstoneInterval`, default 2 s -- the key is the spy's own
--     re-ask cadence, see the consumer below) per family and only on a
--     CHANGE (the original had no own-count broadcast at all — it answered
--     queries — and 2 s is its own HealthstoneInterval floor,
--     Forte_Healthstone.lua:330);
--   * the summon phases are one pair per cast, and the cast's channel is the
--     generated 5 000 ms (`Data/Warlock.lua [698] castMs`) — the event stream
--     is the rate limit, the original's SuS/SuC/SuE pair was per cast too.
--
-- THE INBOUND LAW: only our prefix, only plain names (CHAT_MSG_ADDON's
-- payload is (prefix, text, channel, sender, target, zoneChannelID, localID,
-- name, instanceID), ChatInfoDocumentation.lua:800, sender/target plain
-- cstrings), self-messages ignored (CA-24: `FW:SendData` echoes locally,
-- Forte_Core.lua:1906, so a self-echo must never re-enter the model), a
-- `SU`/`SE` whose `<by>` is not the sender is a claim about a third player
-- and is ignored, a malformed body is counted and dropped.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
FX.Warlock = FX.Warlock or {}
local WK = FX.Warlock

FX.Warlock.Comms = {}
local C = FX.Warlock.Comms

-- ------------------------------------------------------------------ the wire --

C.PREFIX = "FXWK"
C.VERSION = "1"

--- cmd -> shape. "q" query (no payload), "n" one count, "s" two names.
C.CMDS = {
    HG = "q", HS = "n", SG = "q", SH = "n", SU = "s", SE = "s",
}

--- The answer each query rides (HG1 asks for HS1, SG1 for SH1).
C.QUERY_ANSWER = { HG = "HS", SG = "SH" }

local MAX_COUNT = 9999          -- a count that needs four digits is a bug
local MAX_NAME = 64             -- folded player name, the 12.0 caps are below
local MAX_TEXT = 200            -- far under the chat line limit

local function plainString(v)
    local plain = FX.Compat.PlainOrNil(v)
    if type(plain) == "string" then return plain end
    return nil
end

--- `Encode(cmd, a, b)` — the wire string, nil on an input the decoder would
--- not accept (the two halves are exact mirrors by construction; the test
--- round-trips them). Names are trimmed of the wire's separators; a name
--- that cannot survive them is refused.
function C.Encode(cmd, a, b)
    local shape = C.CMDS[cmd]
    if not shape then return nil end
    local ver = C.VERSION
    if shape == "q" then
        return cmd .. ver
    end
    if shape == "n" then
        if type(a) ~= "number" or a < 0 or a > MAX_COUNT
            or math.floor(a) ~= a then return nil end
        return string.format("%s%s %d", cmd, ver, a)
    end
    local n1, n2 = plainString(a), plainString(b)
    if not n1 or not n2 then return nil end
    if n1:find("%s") or n2:find("%s") then return nil end
    if #n1 > MAX_NAME or #n2 > MAX_NAME then return nil end
    local out = string.format("%s%s %s %s", cmd, ver, n1, n2)
    if #out > MAX_TEXT then return nil end
    return out
end

--- `Decode(text)` -> `cmd, a, b`, nil on anything the grammar does not cover
--- (unknown cmd, foreign version, junk payload). The patterns carry NO `|`
--- (Lua patterns have no alternation); the digit/name classes are exact.
function C.Decode(text)
    if type(text) ~= "string" or #text == 0 or #text > MAX_TEXT then
        return nil
    end
    local cmd, ver, rest = text:match("^(%u%u)(%d)%s*(.*)$")
    if not cmd then return nil end
    local shape = C.CMDS[cmd]
    if not shape then return nil end
    if ver ~= C.VERSION then return nil end
    if shape == "q" then
        if rest ~= "" then return nil end
        return cmd
    end
    if shape == "n" then
        local digits = rest:match("^(%d+)$")
        if not digits then return nil end
        local n = tonumber(digits)
        if n == nil or n < 0 or n > MAX_COUNT then return nil end
        return cmd, n
    end
    local n1, n2 = rest:match("^(%S+)%s+(%S+)$")
    if not n1 or not n2 then return nil end
    if #n1 > MAX_NAME or #n2 > MAX_NAME then return nil end
    return cmd, n1, n2
end

-- ------------------------------------------------------------------ counters --

C.counts = {
    sent = 0,             -- accepted C_ChatInfo.SendAddonMessage calls
    lockedSkipped = 0,    -- the client says chat messaging is locked down
    offSkipped = 0,       -- the CommsEnable switch is off
    noGroupSkipped = 0,   -- solo: the law, not the setting, stopped the send
    rateSkipped = 0,      -- the rate law of the header stopped the send
    sendFailed = 0,       -- the call raised or the client refused (result > 0)
    received = 0,         -- CHAT_MSG_ADDON lines of OUR prefix
    selfIgnored = 0,      -- the sender is us (CA-24 self-echo law)
    foreignIgnored = 0,   -- sender != <by> on a summon phase
    malformedIgnored = 0, -- the decoder said no
}

--- The test seam: { inLockdown, outgoingRestricted, send, register, isRaid,
--- groupCount, selfName, rosterScan, now }. Production leaves every slot nil
--- and reads the real surface (the Announce.readers convention).
C.readers = {}
C._lastAt = {}            -- rate-gate stamps
C._lastSent = {}          -- the last announced value per family
C._lastTarget = nil       -- the target of the own summon start being tracked
C.prefixState = nil       -- "ok" | "duplicate" | "refused:<n>" | "noAPI" | "raised"
C.group = nil             -- the live model (Core/Group.lua), built at enable

function C:Clock()
    local r = self.readers
    if type(r.now) == "function" then return r.now() end
    return GetTime()
end

-- ------------------------------------------------------------- the gates ----

local function plainCall(fn, arg)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, arg)
    if not ok then return nil end
    local plain = FX.Compat.PlainOrNil(value)
    if plain == nil then return nil end
    return plain and true or false
end

--- True ONLY on a plain-true answer from any legal check (the SecretState
--- consumer law; the Announce:chatLocked shape, Announce.lua:84-97).
function C:chatLocked()
    local r = self.readers
    local SS = FX.SecretState
    if SS and SS.Refresh then pcall(SS.Refresh) end
    if SS and SS.chat == true then return true end
    if plainCall(r.inLockdown
        or (C_ChatInfo and C_ChatInfo.InChatMessagingLockdown)) then
        return true
    end
    if plainCall(r.outgoingRestricted
        or (C_ChatInfo and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted)) then
        return true
    end
    return false
end

--- The CommsEnable switch (module "Warlock"): an absent store (Forte_Options
--- is an OptionalDep) and an absent key both read ON; the group gate below is
--- what makes the shipped default "ON in a group, OFF solo".
function C:Enabled()
    local st = FX.Settings
    if st and st.Get then
        local v = st:Get("Warlock", "CommsEnable")
        if v == false then return false end
    end
    return true
end

--- RAID in a raid, PARTY in a party, nil with no group (the Announce:Group
--- routing, Announce.lua:110-124; the original sent "RAID" only
--- (Forte_Core.lua:1909) — the party leg is the strict superset).
function C:Channel()
    local r = self.readers
    if plainCall(r.isRaid or _G.IsInRaid) then return "RAID" end
    local members = r.groupCount
        and r.groupCount()
        or (type(_G.GetNumGroupMembers) == "function"
            and plainCall(_G.GetNumGroupMembers))
    if (tonumber(members) or 0) > 0 then return "PARTY" end
    return nil
end

--- The rate law: `key` may fire again after `gap` seconds. Stamps on yes.
function C:RateGate(key, gap)
    local now = self:Clock()
    local last = self._lastAt[key]
    if last ~= nil and (now - last) < gap then return false end
    self._lastAt[key] = now
    return true
end

--- The one send. Gate order: switch, lockdown, group, rate (the CALLER
--- stamps the rate key), wire, pcall. Returns the status word.
function C:Send(text, channel)
    if type(text) ~= "string" or text == "" then return "empty" end
    if not self:Enabled() then
        self.counts.offSkipped = self.counts.offSkipped + 1
        return "off"
    end
    if self:chatLocked() then
        self.counts.lockedSkipped = self.counts.lockedSkipped + 1
        return "locked"
    end
    if channel == nil then channel = self:Channel() end
    if channel == nil then
        self.counts.noGroupSkipped = self.counts.noGroupSkipped + 1
        return "noGroup"
    end
    local send = self.readers.send
        or (C_ChatInfo and C_ChatInfo.SendAddonMessage)
    if type(send) ~= "function" then
        self.counts.sendFailed = self.counts.sendFailed + 1
        return "noSend"
    end
    local ok, result = pcall(send, self.PREFIX, text, channel)
    if not ok then
        self.counts.sendFailed = self.counts.sendFailed + 1
        return "raised"
    end
    -- SendAddonMessageResult: 0 = Success (ChatConstantsDocumentation.lua:146).
    local plain = FX.Compat.PlainOrNil(result)
    if type(plain) == "number" and plain > 0 then
        self.counts.sendFailed = self.counts.sendFailed + 1
        return "refused"
    end
    self.counts.sent = self.counts.sent + 1
    return "sent"
end

function C:SendCmd(cmd, a, b)
    local text = self.Encode(cmd, a, b)
    if not text then return "badEncode" end
    return self:Send(text)
end

-- ------------------------------------------------------------- self identity --

function C:SelfName()
    local r = self.readers
    if type(r.selfName) == "function" then
        return plainString(r.selfName())
    end
    if type(r.selfName) == "string" then return r.selfName end
    if type(UnitName) ~= "function" then return nil end
    local ok, name = pcall(UnitName, "player")
    if not ok then return nil end
    return plainString(name)
end

--- The own-state readers, read through the Tools trackers (the comms NEVER
--- touches a bag API itself — Core/Tools.lua owns every read contract).
function C:SelfHealthstoneCount()
    local t = FX.Warlock.Tools
    local h = t and t.Healthstone
    if not h then return nil end
    local count = h:Count()
    if type(count) == "number" and count >= 0 then return count end
    return nil
end

function C:SelfShardCount()
    local t = FX.Warlock.Tools
    local s = t and t.Shards
    if not s then return nil end
    local count = s:Count()
    if type(count) == "number" and count >= 0 then return count end
    return nil
end

-- ------------------------------------------------------------- roster scan ---

local function plainNumberN(v)
    if type(v) == "number" and v >= 0 then return math.floor(v) end
    return nil
end

--- One roster pass: the `raidN`/`partyN` tokens of the documented pair
--- IsInRaid + GetNumGroupMembers (wow-api-group-lfg
--- RETAIL-BASELINE.md:56-57,60-62, the loop shape :204-222; the original's
--- FW:ForGroupMembers, Forte_Core.lua:957, is the same walk). Every read is
--- pcall'd and name-guarded (UnitName is SecretWhenUnitNameIdentity-
--- Restricted, UnitDocumentation.lua:2399 — a secret token names nobody and
--- simply drops out of the scan; UnitClass/UnitIsConnected/
--- UnitIsDeadOrGhost are the catalog's). The test seam is readers.rosterScan.
function C:ScanRoster()
    local r = self.readers
    if type(r.rosterScan) == "function" then
        local ok, rows = pcall(r.rosterScan)
        if ok and type(rows) == "table" then return rows end
        return nil
    end
    if type(_G.GetNumGroupMembers) ~= "function"
        or type(UnitName) ~= "function" then return nil end
    local inRaid = plainCall(_G.IsInRaid)
    local token = inRaid and "raid" or "party"
    local okN, n = pcall(_G.GetNumGroupMembers)
    n = okN and plainNumberN(tonumber(FX.Compat.PlainOrNil(n)))
    if not n then return nil end
    local rows = {}
    for i = 1, n do
        local unit = token .. i
        local ok, name = pcall(UnitName, unit)
        name = ok and plainString(name)
        if name then
            local class
            if type(UnitClass) == "function" then
                local okC, _, classFile = pcall(UnitClass, unit)
                if okC then
                    class = plainString(FX.Compat.PlainOrNil(classFile))
                end
            end
            local present, alive = true, true
            if type(UnitIsConnected) == "function" then
                local okP, v = pcall(UnitIsConnected, unit)
                v = okP and FX.Compat.PlainOrNil(v)
                -- Only a definitive false is an absence (Forte_Core.lua:1866).
                if v == false then present = false end
            end
            if type(UnitIsDeadOrGhost) == "function" then
                local okD, v = pcall(UnitIsDeadOrGhost, unit)
                v = okD and FX.Compat.PlainOrNil(v)
                if v == true then alive = false end
            end
            rows[#rows + 1] = {
                name = name, class = class, present = present, alive = alive,
            }
        end
    end
    return rows
end

--- Kick the spy views (the UI/Module.lua visibility law: activity renders
--- synchronously, never waits for a tick). nil-guarded: the comms runs with
--- the UI layer absent (a headless session).
function C:KickViews()
    local ui = FX.Warlock.UI
    if ui and ui.Kick then
        pcall(ui.Kick, ui, { "Healthstone", "Shards", "Summon" })
    end
end

-- ------------------------------------------------------------ inbound --------

--- One CHAT_MSG_ADDON line. Arguments are the catalog's first three
--- payload fields (prefix, text, sender), ChatInfoDocumentation.lua:800; the
--- rest of the payload is never touched. Returns a status word.
function C:OnAddonMessage(prefix, text, sender)
    local p = plainString(prefix)
    if p ~= self.PREFIX then return "foreignPrefix" end
    self.counts.received = self.counts.received + 1
    local who = plainString(sender)
    if not who then
        self.counts.malformedIgnored = self.counts.malformedIgnored + 1
        return "malformed"
    end
    if who == self:SelfName() then
        self.counts.selfIgnored = self.counts.selfIgnored + 1
        return "self"
    end
    local cmd, a, b = self.Decode(text)
    if not cmd then
        self.counts.malformedIgnored = self.counts.malformedIgnored + 1
        return "malformed"
    end
    local group = self.group
    if not group then return "noModel" end
    local changed = true
    if cmd == "HS" then
        changed = group:SetCount(who, "hs", a)
    elseif cmd == "SH" then
        changed = group:SetCount(who, "shards", a)
    elseif cmd == "HG" or cmd == "SG" then
        group:MarkAddon(who)
        local answer = self.QUERY_ANSWER[cmd]
        local own = (answer == "HS")
            and self:SelfHealthstoneCount() or self:SelfShardCount()
        if own ~= nil and self:RateGate("resp" .. answer, self.QUERY_MIN_GAP) then
            self:SendCmd(answer, own)
        end
    else
        -- A summon phase: the claim must be about its own sender.
        if a ~= who then
            self.counts.foreignIgnored = self.counts.foreignIgnored + 1
            return "foreign"
        end
        if cmd == "SU" then
            group:SummonStart(who, b)
        else
            group:SummonEnd(who, b)
        end
    end
    if not changed then
        self.counts.malformedIgnored = self.counts.malformedIgnored + 1
        return "malformed"
    end
    self:KickViews()
    return "applied"
end

-- ------------------------------------------------------------ outbound -------

C.QUERY_MIN_GAP = 5        -- Forte_Core.lua:2436 (FW.LastHSCheck + 5)
C.ANNOUNCE_MIN_GAP = 2     -- Forte_Healthstone.lua:330 (HealthstoneInterval)

--- The roster changed: re-scan, drop what left, ask the room (one query
--- burst per QUERY_MIN_GAP) and announce the own state. Called by the event
--- dispatcher on GROUP_ROSTER_UPDATE / GROUP_JOINED / GROUP_FORMED and by
--- the tests.
function C:OnRosterChanged()
    if not self.group then return end
    local rows = self:ScanRoster()
    if rows then
        self.group:SetRoster(rows)
        if #rows == 0 then self.group:Clear() end
    end
    self._lastSent.hs, self._lastSent.shards = nil, nil
    if self:RateGate("query", self.QUERY_MIN_GAP) then
        self:SendCmd("HG")
        self:SendCmd("SG")
    end
    self:AnnounceState()
    self:KickViews()
end

--- The group is gone: the model clears (the original drops the panels with
--- GROUPED, Forte_Healthstone.lua:13, Forte_Summon.lua:51), no send.
function C:OnGroupLeft()
    if self.group then self.group:Clear() end
    self._lastSent.hs, self._lastSent.shards = nil, nil
    self._lastTarget = nil
    self:KickViews()
end

--- The announce cadence, read live: the original's
--- `FW.Default.HealthstoneInterval` (the "Healthstone draw interval"
--- option, Forte_Healthstone.lua:610 with SetRange(0.5,5) at :318, def 2
--- :343) is the spy's re-ask cadence — `FW:Delay(FW.Default.
--- HealthstoneInterval, FWHS_Update)` (:113-116) — the rate at which the
--- spy restates itself. This build's spy restates its OWN counts on this
--- path, so the key paces exactly that: a short interval asks and is
--- answered more often, a long one lets the roster age. Clamped to the
--- original's own 0.5..5 (the option's SetRange), with the shipped default
--- as the floor of a missing store.
function C:AnnounceGap()
    local v
    if FX.Settings and FX.Settings.Get then
        local ok, got = pcall(FX.Settings.Get, FX.Settings, "Warlock",
            "HealthstoneInterval")
        if ok then v = FX.Compat.PlainOrNil(got) end
    end
    if type(v) ~= "number" then v = self.ANNOUNCE_MIN_GAP end
    if v < 0.5 then
        v = 0.5
    elseif v > 5 then
        v = 5
    end
    return v
end

--- Own counts may have moved (Core/Tools.lua calls this after every
--- ReadItems pass): announce on a CHANGE, per family, at most once per
--- AnnounceGap (the header's rate law, the user's HealthstoneInterval).
function C:AnnounceState()
    local gap = self:AnnounceGap()
    local hs = self:SelfHealthstoneCount()
    if hs ~= nil and hs ~= self._lastSent.hs
        and self:RateGate("announceHS", gap) then
        self._lastSent.hs = hs
        self:SendCmd("HS", hs)
    end
    local shards = self:SelfShardCount()
    if shards ~= nil and shards ~= self._lastSent.shards
        and self:RateGate("announceSH", gap) then
        self._lastSent.shards = shards
        self:SendCmd("SH", shards)
    end
end

--- Own ritual phase (Core/Tools.lua calls this at the SummonTracker's
--- Begin/End): `SU1 <self> <target>` on the start (a plain target is the
--- price — an unread target sends nothing, the name privacy is the
--- original's own: `if t ~= "" then FW:SummonStartMessage(u,t) end`,
--- Forte_Summon.lua:496-509), the paired `SE1` on the end. One pair per
--- cast: the channel's own 5 s is the rate limit (header law).
function C:OnSelfSummon(phase, target)
    target = plainString(target)
    if phase == "start" then
        self._lastTarget = target
        if not target then return "noTarget" end
        return self:SendCmd("SU", self:SelfName(), target)
    end
    if phase == "end" then
        local t = target or self._lastTarget
        self._lastTarget = nil
        if not t then return "noTarget" end
        return self:SendCmd("SE", self:SelfName(), t)
    end
    return "badPhase"
end

-- --------------------------------------------------------------- events ------

--- The event frame's dispatcher. The CHAT_MSG_ADDON payload order is the
--- catalog's (prefix, text, channel, sender, ...): the 3rd field is the
--- CHANNEL and the sender is the FOURTH — the one trap of this file, read
--- positions 1, 2 and 4.
local function onCommsEvent(self, event, a1, a2, a3, a4)
    if event == "CHAT_MSG_ADDON" then
        self:OnAddonMessage(a1, a2, a4)
    elseif event == "GROUP_ROSTER_UPDATE"
        or event == "GROUP_JOINED"
        or event == "GROUP_FORMED" then
        self:OnRosterChanged()
    elseif event == "GROUP_LEFT" then
        self:OnGroupLeft()
    end
end

--- RegisterPrefix once per session: C_ChatInfo.RegisterAddonMessagePrefix
--- (ChatInfoDocumentation.lua:468) returns RegisterAddonMessagePrefixResult
--- (Success 0, DuplicatePrefix 1 — ChatConstantsDocumentation.lua:132);
--- Success/Duplicate both mean "our prefix is listening". Runs inside
--- OnEnable/OnClassChanged, never at file load (the taint rule,
--- Forte_Core/Core/Init.lua).
function C:RegisterPrefix()
    local r = self.readers
    if self.prefixState then return self.prefixState end
    local register = r.register
        or (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix)
    if type(register) ~= "function" then
        self.prefixState = "noAPI"
        return self.prefixState
    end
    local ok, result = pcall(register, self.PREFIX)
    if not ok then
        self.prefixState = "raised"
    else
        local n = tonumber(FX.Compat.PlainOrNil(result))
        if n == 0 then
            self.prefixState = "ok"
        elseif n == nil then
            self.prefixState = "okUnlabelled"
        elseif n == 1 then
            self.prefixState = "duplicate"
        else
            self.prefixState = "refused:" .. tostring(n)
        end
    end
    return self.prefixState
end

--- The events (idempotent while enabled; the frame is created HERE, inside
--- OnEnable/OnClassChanged — the taint rule). Every event name is in the
--- pinned catalog: CHAT_MSG_ADDON (ChatInfoDocumentation.lua:800),
--- GROUP_ROSTER_UPDATE / GROUP_JOINED / GROUP_FORMED / GROUP_LEFT
--- (PartyInfoDocumentation.lua, the C_PartyInfo block).
function C:EnableEvents()
    if self._eventsEnabled then return end
    self:RegisterPrefix()
    local f = self._eventFrame
    if not f then
        f = CreateFrame("Frame")
        self._eventFrame = f
    end
    f:RegisterEvent("CHAT_MSG_ADDON")
    f:RegisterEvent("GROUP_ROSTER_UPDATE")
    f:RegisterEvent("GROUP_JOINED")
    f:RegisterEvent("GROUP_FORMED")
    f:RegisterEvent("GROUP_LEFT")
    -- OnEvent receives (frame, event, ...): the frame is swallowed, the
    -- payload fields arrive positionally (the Tools.lua convention).
    f:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
        onCommsEvent(C, event, a1, a2, a3, a4)
    end)
    self._eventsEnabled = true
end

--- Tools.lua's DisableEvents shape: SetScript(nil) is the silencing half,
--- the Unregister* calls are nil-guarded (the sim frame emulation).
function C:DisableEvents()
    local f = self._eventFrame
    if f and self._eventsEnabled then
        if f.UnregisterEvent then
            f:UnregisterEvent("CHAT_MSG_ADDON")
            f:UnregisterEvent("GROUP_ROSTER_UPDATE")
            f:UnregisterEvent("GROUP_JOINED")
            f:UnregisterEvent("GROUP_FORMED")
            f:UnregisterEvent("GROUP_LEFT")
        end
        f:SetScript("OnEvent", nil)
    end
    self._eventsEnabled = false
end

-- ------------------------------------------------------------- lifecycle -----

--- Driven by Core/Tools.lua (the `Warlock` module), class-gated there: this
--- runs for WARLOCK players only.
function C:OnEnable()
    if not self.group then self.group = WK.NewGroup() end
    self:EnableEvents()
end

function C:OnClassChanged(classFile)
    if classFile == "WARLOCK" then
        self:OnEnable()
    else
        self:DisableEvents()
        self:OnGroupLeft()
    end
end

--- One `/fx status` line (printed by the Warlock module's Status).
function C:StatusLine()
    local c = self.counts
    local members, queue = 0, 0
    if self.group then
        members = self.group:ActiveCount()
        queue = self.group:QueueCount()
    end
    return string.format(
        "Warlock comms: %s prefix=%s | %d members, %d queue | sent %d"
        .. " | locked %d | off %d | solo %d | rate %d | failed %d"
        .. " | rx %d self %d foreign %d junk %d",
        self:Enabled() and "on" or "off",
        tostring(self.prefixState),
        members, queue,
        c.sent, c.lockedSkipped, c.offSkipped, c.noGroupSkipped,
        c.rateSkipped, c.sendFailed,
        c.received, c.selfIgnored, c.foreignIgnored, c.malformedIgnored)
end

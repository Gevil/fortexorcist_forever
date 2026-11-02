-- addon/Forte_Messages/Core/Announce.lua
-- Party/Raid Messages: the original's announce engine, ported to the
-- Forever chat law. The routing is the original's (spec FE-17/CA-22):
--   * bit1 of a message row -> FW:ToGroup: RAID in a raid, PARTY in a party,
--     a local echo with no group, all behind the `OutputRaid` master switch
--     (/tmp/fxref/Forte_Core/Forte_Core.lua:2046-2056, default true :2518);
--   * bit2 -> FW:ToChannel: SAY / YELL / a channel, behind the `Output`
--     master (:2059-2071, default on :2519);
--   * the rows themselves are `{[0]=bits, [1]=text}` templates with %s
--     (Forte_Core.lua:2525-2527; the Warlock family's
--     "Soulstoned >> %s << Use it well!" is Forte_Class/Warlock/Warlock.lua:365
--     -- its shipped default is bits 0, i.e. OFF, which is exactly why the
--     "Soulstone used on X" row below defaults off too).
--
-- THE LEGALITY HALF (the P6 verify item PLAN §3.6 flagged; the evidence trail
-- is docs/messages-sounds.md):
--   * `C_ChatInfo.SendChatMessage(message, chatType, languageID, target)` is
--     the catalog call (pinned catalog @ChatInfoDocumentation.lua:563,
--     `HasRestrictions = true`, chatType a "SAY"/"YELL"/"CHANNELn"/... string);
--   * instances/encounters put addon chat into a CHAT MESSAGING LOCKDOWN:
--     docs/reference/wow-ui-sim-specs/chat-messaging-lockdown.md (the
--     `C_ChatInfo.InChatMessagingLockdown()` predicate, one plain bool) and
--     chat-lockdown-ready-checks.md (row169: the 12.0.x restrictions "apply
--     when in chat messaging lockdown"); EllesmereUI's live code documents
--     the bite -- inside a lockdown a tainted send is "silently swallowed"
--     (EUI_Chat_EditBox.lua:64-68) and its gate is the same pair we use
--     (EllesmereUIQoL_RaidTools.lua:837-840 `ChatLocked()`,
--     EllesmereUIQuestTracker_Forever.lua:710: check, then send);
--   * NeedRoll (installed, live) gates its outbox on exactly the pair
--     `C_ChatInfo.AreOutgoingAddonChatMessagesRestricted` +
--     `C_ChatInfo.InChatMessagingLockdown` (Core/Drops.lua:616,
--     Core/Init.lua:453-455);
--   * the cached project view is FX.SecretState.chat -- AddOnRestrictionType
--     Chat = 5 read through C_RestrictedActions.IsAddOnRestrictionActive
--     (Forte_Core/Core/Compat.lua RESTRICTION_TYPES + the pinned
--     @RestrictedActionsConstantsDocumentation.lua:18).
--
-- The gate law is the SecretState consumer law: ONLY a plain `true` skips
-- (an unknown answer from an absent/raising client is not a reason to
-- suppress -- Compat.lua:394-448, SecretState.CooldownReadsAreSecret
-- :460-465). A skipped send is silent and COUNTED (the task's
-- "silently skipped (and counted) when locked"), so `/fx messages` reports
-- what the lockdown ate. Every send is pcall'd: the sim documents a blocked
-- call as a raising call (chat-lockdown-ready-checks.md, SIMULATOR INFERENCE
-- row) and a live refusal must never break the event that triggered it.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
FX.Messages = FX.Messages or {}

local Announce = {}
FX.Messages.Announce = Announce

Announce.cfg = nil      -- the module's live settings view (bound at enable)
Announce.channelOut = nil  -- the module's Channel layer (local echo law)

Announce.counts = {
    sent = 0,            -- accepted C_ChatInfo.SendChatMessage calls
    lockedSkipped = 0,   -- SKIPPED because the client says chat is locked
    offSkipped = 0,      -- skipped by the OutputRaid / Output master gates
    noGroup = 0,         -- the no-group local echoes (ToGroup law)
    sendFailed = 0,      -- the call raised (the pcall caught it)
}
Announce.last = nil      -- { text, chatType, result } -- the status line's datum

-- The test seam: { inLockdown, outgoingRestricted, isActive, send, isRaid,
-- groupCount }. Production leaves every slot nil and reads the real surface.
Announce.readers = {}

local function plainCall(fn, arg)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, arg)
    if not ok then return nil end
    local plain = FX.Compat.PlainOrNil(value)
    if plain == nil then return nil end
    return plain and true or false
end

--- True ONLY on a plain-true answer from any legal check (the SecretState
--- consumer law -- nil/unknown never suppresses):
---   FX.SecretState.chat (the C_RestrictedActions Chat=5 snapshot, refreshed
---   right here so the answer is current), C_ChatInfo.InChatMessagingLockdown,
---   C_ChatInfo.AreOutgoingAddonChatMessagesRestricted.
function Announce:chatLocked()
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

--- The one send. chatType is the catalog's string ('SAY', 'YELL', 'PARTY',
--- 'RAID', 'CHANNEL1'..'CHANNEL10' -- ChatInfoDocumentation.lua:573).
function Announce:send(text, chatType)
    if type(text) ~= "string" or text == "" then return "empty" end
    local send = self.readers.send
        or (C_ChatInfo and C_ChatInfo.SendChatMessage)
    if type(send) ~= "function" then
        self.counts.sendFailed = self.counts.sendFailed + 1
        return "noSend"
    end
    local ok = pcall(send, text, chatType)
    self.last = { text = text, chatType = chatType, result = ok and "sent" or "raised" }
    if not ok then
        self.counts.sendFailed = self.counts.sendFailed + 1
        return "raised"
    end
    self.counts.sent = self.counts.sent + 1
    return "sent"
end

--- bit1: the group line (ToGroup law). gateKey is the row's own checkbox,
--- the master gate the `OutputRaid` switch.
function Announce:Group(text, gateKey)
    local cfg = self.cfg
    if not cfg or not cfg.OutputRaid or not cfg[gateKey] then
        self.counts.offSkipped = self.counts.offSkipped + 1
        return "off"
    end
    if self:chatLocked() then
        self.counts.lockedSkipped = self.counts.lockedSkipped + 1
        return "locked"
    end
    local r = self.readers
    local inRaid = plainCall(r.isRaid or _G.IsInRaid)
    local members = r.groupCount and r.groupCount()
        or (type(_G.GetNumGroupMembers) == "function"
            and plainCall(_G.GetNumGroupMembers))
    if inRaid then return self:send(text, "RAID") end
    if (tonumber(members) or 0) > 0 then return self:send(text, "PARTY") end
    -- No group: the original echoes it locally (Forte_Core.lua:2052-2053
    -- FW:Show), so the event is not swallowed by the absence of a party.
    self.counts.noGroup = self.counts.noGroup + 1
    if self.channelOut then self.channelOut:Show(text) end
    return "noGroup"
end

--- bit2: the say/yell/channel line (ToChannel law), gated by OutputEnable
--- plus the row's own channel checkbox. The channel string is
--- normalised to SAY / YELL / CHANNELn; anything else is refused (a rogue
--- string into a chatType is exactly the surface the lockdown bites).
function Announce:Channel(text, gateKey)
    local cfg = self.cfg
    if not cfg or not cfg.OutputEnable or not cfg[gateKey] then
        self.counts.offSkipped = self.counts.offSkipped + 1
        return "off"
    end
    if self:chatLocked() then
        self.counts.lockedSkipped = self.counts.lockedSkipped + 1
        return "locked"
    end
    local ch = type(cfg.OutputChannel) == "string"
        and (cfg.OutputChannel:upper():gsub("%s+", "")) or ""
    -- CHANNEL1..CHANNEL10, spelled WITHOUT `|` (Lua patterns carry no
    -- alternation operator -- a `|` inside a class is the literal pipe).
    if ch ~= "SAY" and ch ~= "YELL"
        and not ch:match("^CHANNEL[1-9]$")
        and not ch:match("^CHANNEL10$") then
        self.counts.offSkipped = self.counts.offSkipped + 1
        return "badChannel"
    end
    return self:send(text, ch)
end

--- Status lines for `/fx messages` (the gate-count half of the task).
function Announce:StatusLines()
    local c = self.counts
    return string.format(
        "announces: sent %d | locked-skipped %d | off-skipped %d | no-group echoes %d | failed %d",
        c.sent, c.lockedSkipped, c.offSkipped, c.noGroup, c.sendFailed)
end

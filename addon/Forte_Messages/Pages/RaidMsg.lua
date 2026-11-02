-- addon/Forte_Messages/Pages/RaidMsg.lua
-- The Party/Raid Messages page: it lights the `RaidMsg` index cell
-- (O.INDEX: { "RaidMsg", "Party/Raid", GREEN } -- Forte_Options/UI/
-- Window.lua:59). The routing is the original's: bit1 of a message row
-- sends FW:ToGroup (RAID in a raid, PARTY in a party), bit2 sends
-- FW:ToChannel (SAY/YELL/a channel) -- the two master switches `OutputRaid`
-- and `Output` are the original's own rows (Forte_Core.lua:2046-2071,
-- defaults :2518-2519), and each row carries its own group/channel switches
-- exactly like the row's `{[0]=bits}` bits (Forte_Core.lua:2525-2527).
--
-- LEGALITY (the page says it; docs/messages-sounds.md carries the evidence):
-- every send goes through C_ChatInfo.SendChatMessage and is gated on the
-- chat-messaging-lockdown checks first (Core/Announce.lua) -- inside an
-- instance a locked-down send is silently swallowed by the client
-- (EUI_Chat_EditBox.lua:64-68), so we do not pretend it went: the gate
-- skips it, counts it, and `/fx messages` reports the count. The three
-- announce rows all default OFF -- the pattern the original itself ships:
-- its SoulstoneSuccess row defaults to bits 0 (Forte_Class/Warlock/
-- Warlock.lua:365), and the task's opt-in law follows.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist

FX.Messages = FX.Messages or {}
FX.Messages.Pages = FX.Messages.Pages or {}
local P = FX.Messages.Pages

local M = "RaidMsg"

-- The CC fade/break rows -- the original's registrations verbatim:
-- ST:RegisterOnTimerFade(Fear/Banish/Enslave Demon/Seduction/Mesmerize --
-- Warlock.lua:246-250, Polymorph Mage.lua:92, Sap Rogue.lua:80) and the
-- shipped message rows (Warlock.lua:373,:387-391, Mage.lua:122, Rogue.lua:102).
-- The texts are verbatim (their first number IS the fade threshold --
-- ST_GetFadeTime, Forte_Timer.lua:1590-1603); the `{[0]=bits}` slot maps to
-- the party/channel checkboxes: Fear/Polymorph/Sap ship bits 0 (silent),
-- Banish/Enslave/Seduction ship bit 1 (party/raid ON -- the source's own
-- default, the legality gate guards the send). Mesmerize shares the
-- Seduction rows (ST:RegisterOnTimerFade(mesmerize,"SeduceFade"),
-- Warlock.lua:250). The rows are NAME-keyed, so every class loads them.
P.FADE_ROWS = {
    { prefix = "Fear", spell = "Fear", party = false,
        fade = ">> Fear on %s Fading in 3 seconds! <<",
        brk = ">> Fear on %s Broke Early! <<" },
    { prefix = "Banish", spell = "Banish", party = true,
        fade = ">> Banish on %s Fading in 3 seconds! <<",
        brk = ">> Banish on %s Broke Early! <<" },
    { prefix = "Enslave", spell = "Enslave Demon", party = true,
        fade = ">> Enslave on %s Fading in 3 seconds! <<",
        brk = ">> Enslave on %s Broke Early! <<" },
    { prefix = "Seduction", spell = "Seduction", party = true,
        fade = ">> Seduction on %s Fading in 3 seconds! <<",
        brk = ">> Seduction on %s Broke Early! <<" },
    { prefix = "Polymorph", spell = "Polymorph", party = false,
        fade = ">> Polymorph on %s Fading in 3 seconds! <<",
        brk = ">> Polymorph on %s Broke Early! <<" },
    { prefix = "Sap", spell = "Sap", party = false,
        fade = ">> Sap on %s Fading in 3 seconds! <<",
        brk = ">> Sap on %s Broke Early! <<" },
}
P.FADE_SPELL_KEYS = {
    Fear = "Fear", Banish = "Banish", ["Enslave Demon"] = "Enslave",
    Seduction = "Seduction", Mesmerize = "Seduction",
    Polymorph = "Polymorph", Sap = "Sap",
}

P.DEFAULTS = P.DEFAULTS or {}
P.DEFAULTS[M] = {
    -- The master switches (the original's OutputRaid :2518 default true,
    -- Output :2519 default on with the channel slot defaulting to SAY --
    -- the original's "MyProChannel" was a sample value, not a default).
    OutputRaid = true,
    OutputEnable = true,
    OutputChannel = "SAY",
    -- "<spell> ready" -- the CooldownLeft row (Forte_Core.lua:2527). The
    -- announce half is OPT-IN (off), the chat text is the original's.
    ReadyAnnounce = false,
    ReadyChannel = false,
    ReadyAnnounceText = ">> %s is ready <<",
    -- The timer-expiry announce -- the TimeLeft / TimeLeftNoTarg rows
    -- (Forte_Core.lua:2525-2526). Opt-in.
    ExpireAnnounce = false,
    ExpireChannel = false,
    ExpireAnnounceText = ">> %s on %s is fading <<",
    ExpireAnnounceNoTargetText = ">> %s is fading <<",
    -- "Soulstone used on X" -- the Warlock family's SoulstoneSuccess row,
    -- verbatim ("Soulstoned >> %s << Use it well!",
    -- Forte_Class/Warlock/Warlock.lua:365), shipped-default-off kept.
    SoulstoneAnnounce = false,
    SoulstoneChannel = false,
    SoulstoneAnnounceText = "Soulstoned >> %s << Use it well!",
}
do
    for _ = 1, #P.FADE_ROWS do
        local row = P.FADE_ROWS[_]
        P.DEFAULTS[M][row.prefix .. "FadeText"] = row.fade
        P.DEFAULTS[M][row.prefix .. "FadeParty"] = row.party
        P.DEFAULTS[M][row.prefix .. "FadeChannel"] = false
        P.DEFAULTS[M][row.prefix .. "BreakText"] = row.brk
        P.DEFAULTS[M][row.prefix .. "BreakParty"] = row.party
        P.DEFAULTS[M][row.prefix .. "BreakChannel"] = false
    end
end

P.WIDGET_TIPS = P.WIDGET_TIPS or {}
local TIPS = {}
P.WIDGET_TIPS[M] = TIPS
TIPS.OutputRaid = "The group master switch (the original's OutputRaid, "
    .. "Forte_Core.lua:2518): RAID in a raid, PARTY in a party, a local "
    .. "echo with no group. Applied live."
TIPS.OutputEnable = "The channel master switch (the original's Output, "
    .. "Forte_Core.lua:2519). Applied live."
TIPS.OutputChannel = "Where the channel half goes: SAY, YELL or CHANNEL1"
    .. "-CHANNEL10 (the ToChannel law, Forte_Core.lua:2059-2071). Anything "
    .. "else is refused. Applied live."
TIPS.ReadyAnnounce = "Announce to your party/raid when a tracked cooldown "
    .. "pops (the CooldownLeft text below; the original's own default is "
    .. "OFF). Applied live."
TIPS.ReadyChannel = "The SAY/YELL/channel twin of the switch above. "
    .. "Applied live."
TIPS.ReadyAnnounceText = "Template; %%s is the spell (the original's "
    .. "CooldownLeft, Forte_Core.lua:2527). Applied live."
TIPS.ExpireAnnounce = "Announce to your party/raid when a Spell Timer "
    .. "expires (the TimeLeft text below; opt-in). Applied live."
TIPS.ExpireChannel = "The SAY/YELL/channel twin. Applied live."
TIPS.ExpireAnnounceText = "Template; %%s1 the spell, %%s2 the target (the "
    .. "original's TimeLeft, Forte_Core.lua:2525). Applied live."
TIPS.ExpireAnnounceNoTargetText = "The no-target twin (TimeLeftNoTarg, "
    .. "Forte_Core.lua:2526). Applied live."
TIPS.SoulstoneAnnounce = "Announce to your party/raid when YOU create a "
    .. "soulstone for someone (the original's SoulstoneSuccess, Warlock.lua:"
    .. "365 -- the shipped default is OFF and stays OFF; opt-in). Applied "
    .. "live."
TIPS.SoulstoneChannel = "The SAY/YELL/channel twin. Applied live."
TIPS.SoulstoneAnnounceText = "The original's text, verbatim: Soulstoned >> "
    .. "%%s << Use it well! (Warlock.lua:365). Applied live."

function P.RegisterRaidMsgPage()
    local O = FX.Options
    if not O or not O.pages or not FX.Settings then return false end
    if not O.pages[M] then
        FX.Settings:Register(M, P.DEFAULTS[M])
        O:RegisterPage({
            id = M,
            module = M,
            title = "Party/Raid",
            colour = O.C.GREEN,
            build = function(b)
                b.Tips({
                    "Announcements go to your RAID in a raid and to your PARTY in a party (the ToGroup law), to SAY/YELL/a channel on the channel half (the ToChannel law).",
                    "Inside instances the client locks addon chat (chat-messaging-lockdown): the gate then skips the send, counts it, and /fx messages shows the count -- nothing pretends a swallowed line went.",
                    "Every announce row is opt-in: the shipped-default-OFF pattern is the original's own (SoulstoneSuccess bits 0, Warlock.lua:365).",
                    "No raid-target data is read anywhere in this module (the target is your own cast's, the names your own events carry).",
                })
                b.Section("Master switches", function(s)
                    s.CHK({ module = M, key = "OutputRaid",
                        label = "Allow party/raid announcements",
                        tip = TIPS.OutputRaid })
                    s.CHK({ module = M, key = "OutputEnable",
                        label = "Allow say/yell/channel announcements",
                        tip = TIPS.OutputEnable })
                    s.STR({ module = M, key = "OutputChannel",
                        label = "Channel", tip = TIPS.OutputChannel })
                end, {
                    module = M,
                    keys = { "OutputRaid", "OutputEnable", "OutputChannel" },
                    tip = "The two master switches (OutputRaid / Output).",
                })
                b.Section("Cooldown Ready", function(s)
                    s.CHK({ module = M, key = "ReadyAnnounce",
                        label = "Announce to group (opt-in)",
                        tip = TIPS.ReadyAnnounce })
                    s.CHK({ module = M, key = "ReadyChannel",
                        label = "Announce to channel (opt-in)",
                        tip = TIPS.ReadyChannel })
                    s.STR({ module = M, key = "ReadyAnnounceText",
                        label = "Text", tip = TIPS.ReadyAnnounceText })
                end, {
                    module = M,
                    keys = { "ReadyAnnounce", "ReadyChannel",
                        "ReadyAnnounceText" },
                    tip = "The CooldownLeft announce half.",
                })
                b.Section("Timer Expiry", function(s)
                    s.CHK({ module = M, key = "ExpireAnnounce",
                        label = "Announce to group (opt-in)",
                        tip = TIPS.ExpireAnnounce })
                    s.CHK({ module = M, key = "ExpireChannel",
                        label = "Announce to channel (opt-in)",
                        tip = TIPS.ExpireChannel })
                    s.STR({ module = M, key = "ExpireAnnounceText",
                        label = "Text", tip = TIPS.ExpireAnnounceText })
                    s.STR({ module = M, key = "ExpireAnnounceNoTargetText",
                        label = "Text (no target)",
                        tip = TIPS.ExpireAnnounceNoTargetText })
                end, {
                    module = M,
                    keys = { "ExpireAnnounce", "ExpireChannel",
                        "ExpireAnnounceText", "ExpireAnnounceNoTargetText" },
                    tip = "The TimeLeft announce half.",
                })
                for _ = 1, #P.FADE_ROWS do
                    local row = P.FADE_ROWS[_]
                    b.Section(row.spell .. " (CC fade/break)", function(s)
                        s.STR({ module = M,
                            key = row.prefix .. "FadeText",
                            label = "Fade text (its first number is the "
                                .. "warning lead)" })
                        s.CHK({ module = M,
                            key = row.prefix .. "FadeParty",
                            label = "Announce the fade to group" })
                        s.CHK({ module = M,
                            key = row.prefix .. "FadeChannel",
                            label = "Announce the fade to channel" })
                        s.STR({ module = M,
                            key = row.prefix .. "BreakText",
                            label = "Break text" })
                        s.CHK({ module = M,
                            key = row.prefix .. "BreakParty",
                            label = "Announce the break to group" })
                        s.CHK({ module = M,
                            key = row.prefix .. "BreakChannel",
                            label = "Announce the break to channel" })
                    end, {
                        module = M,
                        keys = { row.prefix .. "FadeText",
                            row.prefix .. "FadeParty",
                            row.prefix .. "FadeChannel",
                            row.prefix .. "BreakText",
                            row.prefix .. "BreakParty",
                            row.prefix .. "BreakChannel" },
                        tip = "The original's " .. row.spell
                            .. " fade/break rows (the fade text's first "
                            .. "number IS the warning lead, ST_GetFadeTime, "
                            .. "Forte_Timer.lua:1590-1603).",
                    })
                end
                b.Section("Soulstone", function(s)
                    s.CHK({ module = M, key = "SoulstoneAnnounce",
                        label = "Announce to group (opt-in)",
                        tip = TIPS.SoulstoneAnnounce })
                    s.CHK({ module = M, key = "SoulstoneChannel",
                        label = "Announce to channel (opt-in)",
                        tip = TIPS.SoulstoneChannel })
                    s.STR({ module = M, key = "SoulstoneAnnounceText",
                        label = "Text", tip = TIPS.SoulstoneAnnounceText })
                end, {
                    module = M,
                    keys = { "SoulstoneAnnounce", "SoulstoneChannel",
                        "SoulstoneAnnounceText" },
                    tip = "The SoulstoneSuccess announce half.",
                })
            end,
        })
    end
    return FX.Options.pages[M] ~= nil
end

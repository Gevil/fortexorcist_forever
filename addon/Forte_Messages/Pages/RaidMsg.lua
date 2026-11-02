-- addon/Forte_Messages/Pages/RaidMsg.lua
-- The Party/Raid Messages page: it lights the `RaidMsg` index cell
-- (O.INDEX: { "RaidMsg", "Party/Raid", GREEN } -- Forte_Options/UI/
-- Window.lua:59). The routing is the original's: bit1 of a message row
-- sends FW:ToGroup (RAID in a raid, PARTY in a party), bit2 sends
-- FW:ToChannel (SAY/YELL/a channel) -- the two master switches `OutputRaid`
-- and `Output` are the original's own rows (Forte_Core.lua:2046-2070,
-- defaults :2518-2519), and each row carries its own group/channel switches
-- exactly like the row's `{[0]=bits}` bits (Forte_Core.lua:2525-2527).
--
-- LEGALITY (the page says it; docs/messages-sounds.md carries the evidence):
-- every send goes through C_ChatInfo.SendChatMessage and is gated on the
-- chat-messaging-lockdown checks first (Core/Announce.lua) -- inside an
-- instance a locked-down send is silently swallowed by the client
-- (EUI_Chat_EditBox.lua:64-68), so we do not pretend it went: the gate
-- skips it, counts it, and `/fx messages` reports the count.
--
-- THE SHIPPED-DEFAULT LAW (the manager ruling of 2026-11-02 on review 4 E2):
-- EVERY group/channel announce on this page ships OFF -- the three announce
-- rows AND all twelve fade/break checkboxes. A default install therefore
-- never speaks to a party or a raid without one click per row. The verbatim
-- half is the TEXTS (and the texts' fade thresholds); the source's own
-- `{[0]=bits}` values ride each row's `bits` field and are named in that
-- row's section tip -- the source ships Banish/Enslave/Seduction party-ON
-- (Forte_Class/Warlock/Warlock.lua:372-373, :382-391), and ticking the box
-- restores that. The two master switches stay the original's (OutputRaid
-- true, Output on): with every row off, they gate nothing on their own.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist

FX.Messages = FX.Messages or {}
FX.Messages.Pages = FX.Messages.Pages or {}
local P = FX.Messages.Pages

local M = "RaidMsg"

-- The CC fade/break rows -- the original's registrations (ST:RegisterOnTimerFade
-- of Fear/Banish/Enslave Demon/Seduction/Mesmerize, Warlock.lua:246-250,
-- Polymorph Mage.lua:92, Sap Rogue.lua:80) and its message rows
-- (Warlock.lua:373,:387-391, Mage.lua:122, Rogue.lua:102). WHAT IS VERBATIM is
-- the TEXT (and the text's first number, which IS the fade threshold --
-- ST_GetFadeTime, Forte_Timer.lua:1590-1603) and the row's `{[0]=bits}` slot,
-- carried here as the row's `bits` field (0 silent, 1 group). WHAT IS NOT
-- VERBATIM is the SEND: every fade/break checkbox ships OFF, because a
-- default install must not speak to a party/raid the owner never opted into
-- (the manager ruling of 2026-11-02 on review 4 E2; the source's own party-ON
-- bits are recorded in the row's section tip).
--
-- The KEYS are the FOREVER names (the registry gate, review 4 E4): a fade
-- entry only bites when Forte_Timer has a row of that exact name, and rows
-- come from `FX.Timer.Registry:Build(FX._playerClass)` over the GENERATED
-- data (`addon/Forte_<Class>/Data/<Class>.lua`, the durationMs > 0 gate).
-- Forever names `Enslave Demon` **Subjugate Demon** (mythicsim
-- spells.jsonl: 1098/11725/11726, ClassFlags.Family 5 = Warlock; the generated
-- Warlock data carries `Subjugate Demon` 11726), so the Enslave row keys on
-- that name -- the TEXTS stay the original's (">> Enslave on %s …").
-- `Seduction`/`Mesmerize` are the Succubus pet's casts (the original's
-- `AddSpell(6358, 30, "Pet")` / `AddSpell(115268, 30, "Pet") -- Mesmerize`,
-- Warlock.lua:73-74), and the pair is INERT on this build because **the
-- spell is not in the Forever data** -- all 7503 rows of
-- `mythicsim-forever-engine/data/spells.jsonl` (client_build 1.60.1.70425)
-- were searched for the names `Seduction`, `Seduction`, `Mesmerize` (plus
-- the Succubus' other tools `Devour Magic`, `Spell Lock`, the charm family
-- `Clamp`/`Grip of the Dead` and the source's `Enslave Demon`): no row of
-- any of them, the source's ids 6358/6359 and 115268/115269 are absent, and
-- the file's only Succubus row is the form `Perm. Illusion Succubus` (8315).
-- The client's live table agrees: `C_Spell.GetSpellInfo(6358)` and
-- `(115268)` answer nil, and a scan of ids 1..1500000 finds no name
-- containing `Seduction`, `Seduction` or `Mesmeriz`. No data row means the
-- registry's `durationMs > 0` gate never sees the name, so Forte_Timer can
-- not have a row of it, the fade threshold is never read, and the two
-- sections can not fire -- the rows and their texts ship so the owner sees
-- the pair (the census, review 4 E2) and the tip names the real gate. The
-- gate BEHIND that is the cast feed: these are PET casts, and the Timer
-- registers the cast spine for `player` only. Mesmerize shares the
-- Seduction rows (ST:RegisterOnTimerFade(mesmerize,"SeduceFade"),
-- Warlock.lua:250).
P.FADE_ROWS = {
    { prefix = "Fear", spell = "Fear", bits = 0,
        fade = ">> Fear on %s Fading in 3 seconds! <<",
        brk = ">> Fear on %s Broke Early! <<",
        note = "The source ships these rows OFF (bits 0, Mage/Warlock :387)." },
    { prefix = "Banish", spell = "Banish", bits = 1,
        fade = ">> Banish on %s Fading in 3 seconds! <<",
        brk = ">> Banish on %s Broke Early! <<",
        note = "The source ships this ON (party bits 1, Warlock.lua:372-391) "
            .. "- tick to restore." },
    { prefix = "Enslave", spell = "Subjugate Demon", bits = 1,
        fade = ">> Enslave on %s Fading in 3 seconds! <<",
        brk = ">> Enslave on %s Broke Early! <<",
        note = "The source ships this ON (party bits 1, Warlock.lua:372-391) "
            .. "- tick to restore. Forever names the spell Subjugate Demon; "
            .. "the texts stay the original's." },
    { prefix = "Seduction", spell = "Seduction", bits = 1,
        fade = ">> Seduction on %s Fading in 3 seconds! <<",
        brk = ">> Seduction on %s Broke Early! <<",
        note = "The source ships this ON (party bits 1, Warlock.lua:372-391) "
            .. "- tick to restore. INERT on this build: no spell named "
            .. "Seduction, Seduction or Mesmerize exists in the Forever "
            .. "1.60.1.70425 data (all 7503 rows of mythicsim spells.jsonl "
            .. "searched; the source's ids 6358/115268 are absent), so "
            .. "Forte_Timer has no row of the name and the pair stays "
            .. "silent. The gate behind that is the cast feed: these are "
            .. "the Succubus pet's casts, and Forte_Timer's rows are the "
            .. "player's own casts. See docs/messages-sounds.md." },
    { prefix = "Polymorph", spell = "Polymorph", bits = 0,
        fade = ">> Polymorph on %s Fading in 3 seconds! <<",
        brk = ">> Polymorph on %s Broke Early! <<",
        note = "The source ships these rows OFF (bits 0, Mage.lua:122)." },
    { prefix = "Sap", spell = "Sap", bits = 0,
        fade = ">> Sap on %s Fading in 3 seconds! <<",
        brk = ">> Sap on %s Broke Early! <<",
        note = "The source ships these rows OFF (bits 0, Rogue.lua:102)." },
}
P.FADE_SPELL_KEYS = {
    Fear = "Fear", Banish = "Banish", ["Subjugate Demon"] = "Enslave",
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
        P.DEFAULTS[M][row.prefix .. "BreakText"] = row.brk
        -- E2 (review 4, manager ruling 2026-11-02): EVERY group/channel
        -- announce ships OFF. The source's `{[0]=bits}` value is the row's
        -- `bits` field (1 for Banish/Enslave/Seduction, Warlock.lua:372-373,
        -- :382-391) and is recorded in that row's section tip -- it is not a
        -- shipped default, because a fresh install must not talk to a
        -- party/raid the owner never asked it to talk to. The texts are the
        -- verbatim half; the SEND is the opt-in half.
        P.DEFAULTS[M][row.prefix .. "FadeParty"] = false
        P.DEFAULTS[M][row.prefix .. "BreakParty"] = false
        P.DEFAULTS[M][row.prefix .. "FadeChannel"] = false
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
    .. "-CHANNEL10 (the ToChannel law, Forte_Core.lua:2058-2070). Anything "
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
                    "Every announce row is opt-in: EVERY group and channel checkbox on this page ships OFF, so a default install sends nothing to anyone. The original's own bits ride each row's tip (Banish/Enslave/Seduction ship party-ON, Warlock.lua:372-391) - tick to restore.",
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
                            .. " fade/break rows (the texts verbatim; the "
                            .. "fade text's first number IS the warning "
                            .. "lead, ST_GetFadeTime, Forte_Timer.lua:"
                            .. "1590-1603). " .. (row.note or ""),
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

-- addon/Forte_Messages/Pages/SelfMsg.lua
-- The Self Messages page: it lights the `SelfMsg` index cell
-- (Forte_Options/UI/Window.lua O.INDEX -- the id is the cell's id, and the
-- cell law is RegisterPage -> RefreshIndexCells, Window.lua:339-350). The
-- module's defaults live HERE (the Forte_Timer/Pages/Timer.lua law: the
-- page file is the defaults home, and the module reads the same table, so
-- page and consumer can not drift).
--
-- The rows: per event (cooldown-ready pop / timer expiry) an enable, the
-- chat-line switch, the colour, the text template, and the on-screen banner
-- switches with their duration. The chat line is the original's Self
-- Messages shape ("They are shown in your 'default' chat frame",
-- /tmp/fxref/Forte_Core/Localization.lua:279; FW:Show is Forte_Core.lua:559
-- -- see Core/Channel.lua); the banner rows are labelled NEW (the original
-- ships no on-screen self-message frame -- the search and the ruling are in
-- Core/Channel.lua and UI/Banner.lua).
--
-- Load-order law (Forte_Hunter/Pages/Hunter.lua:20-27,
-- Forte_Timer/Pages/Timer.lua:14-19): NOTHING on FX.Settings / FX.Options is
-- touched at file load; the registration is one idempotent function the
-- module runs at PLAYER_LOGIN.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist

FX.Messages = FX.Messages or {}
FX.Messages.Pages = FX.Messages.Pages or {}
local P = FX.Messages.Pages

local M = "SelfMsg"

P.DEFAULTS = P.DEFAULTS or {}
P.DEFAULTS[M] = {
    -- The cooldown-ready pop (the FX_COOLDOWN_READY event). ReadyChat
    -- defaults OFF deliberately: Forte_Cooldown's own pop already prints
    -- "<name> ready" (Forte_Cooldown/Module.lua's ProcessReadyPops -- the
    -- original's line), so the templated chat line here is the richer,
    -- opt-in replacement, not a second line of the same news.
    ReadyEnable = true,
    ReadyChat = false,
    ReadyColor = { 1.00, 1.00, 0.00, 1.00 },
        -- Read yColor: {1.00, 1.00, 0.00} (Forte_Soulstone.lua:651) -- the
        -- original's "you are ready" message colour.
    ReadyText = ">> %s is ready <<",
        -- CooldownLeft ">> %s is ready in %s <<" (Forte_Core.lua:2527) at
        -- the ready moment (the Forever event fires AT the pop, the
        -- original announced a second BEFORE it -- docs/messages-sounds.md).
    ReadyBanner = false,      -- NEW (UI/Banner.lua); opt-in.
    ReadySeconds = 3,
    -- The timer expiry (the FX_TIMER_EXPIRED event). The ORIGINAL has no
    -- per-expiry message (its warning is the fade rows, RaidMsg's CC
    -- sections -- Forte_Timer.lua:1049-1056); these rows are the NEW opt-in
    -- half, default off, kept for the FX_TIMER_EXPIRED bus seam.
    ExpireEnable = false,
    ExpireChat = true,
    ExpireColor = { 1.00, 0.00, 1.00, 1.00 },
        -- SoulstoneMsgColor {[0]=true, 1.00, 0.00, 1.00}
        -- (Forte_Soulstone.lua:672) -- the original's expire-message colour.
    ExpireText = ">> %s on %s is fading <<",
        -- TimeLeft ">> %s on %s is fading in %s <<" (Forte_Core.lua:2525).
    ExpireNoTargetText = ">> %s is fading <<",
        -- TimeLeftNoTarg (Forte_Core.lua:2526), the no-target row.
    ExpireBanner = false,     -- NEW; opt-in.
    ExpireSeconds = 3,
    -- The ready-icon request to the Secondary Splash (FX_SPLASH). The
    -- splash itself is the Cooldown module's feature; this is the opt-in
    -- bus kick that asks for it on a pop. New plumbing, opt-in.
    SplashKick = false,
}

P.WIDGET_TIPS = P.WIDGET_TIPS or {}
local TIPS = {}
P.WIDGET_TIPS[M] = TIPS
TIPS.ReadyEnable = "Print the self message when one of your cooldowns pops "
    .. "ready (the Cooldown module's ready pop). Applied live."
TIPS.ReadyChat = "The line goes to your default chat frame in the colour "
    .. "below -- the original's Self Messages shape (Localization.lua:279, "
    .. "Forte_Core.lua:559). Off by default: Forte_Cooldown already prints "
    .. "\"<name> ready\" at a pop -- this is the richer replacement, not a "
    .. "second line. Applied live."
TIPS.ReadyColor = "The chat-line colour (default the original's ReadyColor "
    .. "{1,1,0}, Forte_Soulstone.lua:651). Applied live."
TIPS.ReadyText = "The line's template; %%s is the spell (the original's "
    .. "CooldownLeft shape, Forte_Core.lua:2527). Applied live."
TIPS.ReadyBanner = "NEW: also flash a centred on-screen banner. The original "
    .. "has no on-screen self message (Core/Channel.lua) -- opt-in. Applied "
    .. "live."
TIPS.ReadySeconds = "NEW: how long the on-screen banner stays (the original "
    .. "chat line has no duration -- chat does not expire). Applied live."
TIPS.ExpireEnable = "NEW opt-in: message when a Spell Timer row's window "
    .. "ENDS. The original has no per-expiry message (its warning is the "
    .. "fade rows on the Party/Raid page) -- default off. Applied live."
TIPS.ExpireChat = "The line goes to your default chat frame in the colour "
    .. "below. Applied live."
TIPS.ExpireColor = "The chat-line colour (default the original's "
    .. "SoulstoneMsgColor {1,0,1}, Forte_Soulstone.lua:672). Applied live."
TIPS.ExpireText = "Template; the first %%s is the spell, the second the "
    .. "target (the original's TimeLeft, Forte_Core.lua:2525). Applied live."
TIPS.ExpireNoTargetText = "The no-target twin (the original's "
    .. "TimeLeftNoTarg, Forte_Core.lua:2526). Applied live."
TIPS.ExpireBanner = "NEW: also flash a centred on-screen banner. Applied live."
TIPS.ExpireSeconds = "NEW: the banner's on-screen seconds. Applied live."
TIPS.SplashKick = "Ask the Secondary Splash to show the icon when a "
    .. "cooldown pops (the FX_SPLASH bus event; the splash lives in Forte_"
    .. "Cooldown). New plumbing, off by default. Applied live."

function P.RegisterSelfMsgPage()
    local O = FX.Options
    if not O or not O.pages or not FX.Settings then return false end
    if not O.pages[M] then
        FX.Settings:Register(M, P.DEFAULTS[M])
        O:RegisterPage({
            id = M,
            module = M,
            title = "Self Messages",
            colour = O.C.BLUE,
            build = function(b)
                b.Tips({
                    "Self messages are for YOU: they print in your default chat frame (the original's own law) and may flash a centred on-screen banner (new here).",
                    "A cooldown-ready pop and a Spell Timer expiry each have their own switch, colour, text and banner duration.",
                    "A chat line does not expire; the banner's duration row is the NEW on-screen half.",
                    "Party/raid traffic lives on the Party/Raid Messages page -- this page never sends anything to anyone else.",
                })
                b.Section("Cooldown Ready", function(s)
                    s.CHK({ module = M, key = "ReadyEnable",
                        label = "Message when a cooldown is ready",
                        tip = TIPS.ReadyEnable })
                    s.CHK({ module = M, key = "ReadyChat",
                        label = "Chat line", tip = TIPS.ReadyChat })
                    s.COL({ module = M, key = "ReadyColor",
                        label = "Chat colour", tip = TIPS.ReadyColor })
                    s.STR({ module = M, key = "ReadyText",
                        label = "Text", tip = TIPS.ReadyText })
                    s.CHK({ module = M, key = "ReadyBanner",
                        label = "On-screen banner (new)",
                        tip = TIPS.ReadyBanner })
                    s.NUM({ module = M, key = "ReadySeconds",
                        label = "Banner seconds", min = 0.5, max = 10,
                        step = 0.5, tip = TIPS.ReadySeconds })
                end, {
                    module = M,
                    keys = { "ReadyEnable", "ReadyChat", "ReadyColor",
                        "ReadyText", "ReadyBanner", "ReadySeconds" },
                    tip = "What you see when one of your cooldowns pops.",
                })
                b.Section("Timer Expiry", function(s)
                    s.CHK({ module = M, key = "ExpireEnable",
                        label = "Message when a timer expires",
                        tip = TIPS.ExpireEnable })
                    s.CHK({ module = M, key = "ExpireChat",
                        label = "Chat line", tip = TIPS.ExpireChat })
                    s.COL({ module = M, key = "ExpireColor",
                        label = "Chat colour", tip = TIPS.ExpireColor })
                    s.STR({ module = M, key = "ExpireText",
                        label = "Text", tip = TIPS.ExpireText })
                    s.STR({ module = M, key = "ExpireNoTargetText",
                        label = "Text (no target)",
                        tip = TIPS.ExpireNoTargetText })
                    s.CHK({ module = M, key = "ExpireBanner",
                        label = "On-screen banner (new)",
                        tip = TIPS.ExpireBanner })
                    s.NUM({ module = M, key = "ExpireSeconds",
                        label = "Banner seconds", min = 0.5, max = 10,
                        step = 0.5, tip = TIPS.ExpireSeconds })
                end, {
                    module = M,
                    keys = { "ExpireEnable", "ExpireChat", "ExpireColor",
                        "ExpireText", "ExpireNoTargetText", "ExpireBanner",
                        "ExpireSeconds" },
                    tip = "What you see when a Spell Timer row ends.",
                })
                b.Section("Splash", function(s)
                    s.CHK({ module = M, key = "SplashKick",
                        label = "Splash the icon on a ready pop",
                        tip = TIPS.SplashKick })
                end, {
                    module = M, keys = { "SplashKick" },
                    tip = "The ready pop as a big icon (Forte_Cooldown's "
                        .. "Secondary Splash).",
                })
            end,
        })
    end
    return FX.Options.pages[M] ~= nil
end

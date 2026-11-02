-- addon/Forte_Messages/Pages/Sound.lua
-- The Sound page: it lights the `Sound` index cell (O.INDEX:
-- { "Sound", "Sound", RED } -- Forte_Options/UI/Window.lua:56). The rows
-- are the original's `{[0]=on, [1]=path, [2]=times}` sound law rendered as
-- three keys per sound (Forte_Core.lua:2072-2078; spec FE-18 -- the `[2]`
-- slot is a REPEAT count, spec ST-38:3297 "it is a real FX signature sound").
-- There is no SND widget in Forte_Options/Core/Widgets.lua, so the path is
-- a STR row; the defaults are the original's shipped defaults --
-- ShaysBell.wav x2 (Forte_Timer.lua:3297) and the
-- SimonGame_Visual_GameStart.wav path the original ships a default for
-- (Forte_Timer.lua:3301). The cooldown-ready sound row is NEW and labelled
-- so: spec CD-33 -- the original's Cooldown module has NO ready sound of its
-- own (verified absence, Forte_Cooldown.lua:400-1000) -- it is opt-in
-- (default off), the owner ruling "build what we actually need, label what
-- is new" (PLAN §9 2026-11-01).

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist

FX.Messages = FX.Messages or {}
FX.Messages.Pages = FX.Messages.Pages or {}
local P = FX.Messages.Pages

local M = "Sound"

P.DEFAULTS = P.DEFAULTS or {}
P.DEFAULTS[M] = {
    -- The fade warning: the original's TimerFadeSound `{[0]=true,
    -- "Sound\\Spells\\ShaysBell.wav", 2}` verbatim (Forte_Timer.lua:3297),
    -- played at the FX_TIMER_FADING site (:1049-1056).
    TimerFadeEnable = true,
    TimerFadePath = "Sound\\Spells\\ShaysBell.wav",
    TimerFadeTimes = 2,
    -- The early break: the original's TimerBreakSound
    -- `{[0]=true, "Sound\\Spells\\SimonGame_Visual_LevelStart.wav", 4}`
    -- (Forte_Timer.lua:3298), played at the FX_TIMER_BROKEN site (:1207).
    TimerBreakEnable = true,
    TimerBreakPath = "Sound\\Spells\\SimonGame_Visual_LevelStart.wav",
    TimerBreakTimes = 4,
    -- The true-expiry bell: NEW opt-in (the original has no per-expiry
    -- sound -- the fade is its warning), default off.
    TimerExpireEnable = false,
    TimerExpirePath = "Sound\\Spells\\ShaysBell.wav",
    TimerExpireTimes = 2,
    -- The cooldown-ready sound: NEW (CD-33), opt-in.
    CooldownReadyEnable = false,
    CooldownReadyPath = "Sound\\Spells\\SimonGame_Visual_GameStart.wav",
    CooldownReadyTimes = 1,
    -- NO resist row (m4, review 4). The original's TimerResistSound
    -- (Forte_Timer.lua:3299, "Sound\\Spells\\SimonGame_Visual_BadPress.wav",
    -- 1) has no legal Forever signal: its site is a resisted aura
    -- APPLICATION, and the nearest event, UNIT_SPELLCAST_FAILED, names a CAST
    -- failure -- conflating them rings a resist bell on every failed cast.
    -- A row with no consumer is a control that changes nothing, so the
    -- decision lives where it belongs: docs/messages-sounds.md keeps the
    -- paragraph (and the path) until a legal resist signal exists.
}

P.WIDGET_TIPS = P.WIDGET_TIPS or {}
local TIPS = {}
P.WIDGET_TIPS[M] = TIPS
TIPS.TimerFadeEnable = "Play the fade bell when a crowd-control timer "
    .. "announces its own fade (the FX_TIMER_FADING site, Forte_Timer.lua:"
    .. "1049-1056 -- the original's TimerFadeSound). Applied live."
TIPS.TimerFadePath = "The sound file (the original's shipped default: "
    .. "Sound\\Spells\\ShaysBell.wav, Forte_Timer.lua:3297). Applied live."
TIPS.TimerFadeTimes = "How many times it plays -- the original's third "
    .. "slot is a repeat count (2 by default; spec ST-38:3297). Applied live."
TIPS.TimerBreakEnable = "Play the break sound when a crowd control ends "
    .. "EARLY (the aura sweep's :1207 site -- the original's "
    .. "TimerBreakSound, Forte_Timer.lua:3298). Applied live."
TIPS.TimerBreakPath = "The sound file (the original's shipped default: "
    .. "Sound\\Spells\\SimonGame_Visual_LevelStart.wav). Applied live."
TIPS.TimerBreakTimes = "Repeat count (the original's fourth slot of 4). "
    .. "Applied live."
TIPS.TimerExpireEnable = "NEW opt-in: a bell at the TRUE expiry. The "
    .. "original has none (its warning is the fade bell above) -- default "
    .. "off. Applied live."
TIPS.TimerExpirePath = "The sound file. Applied live."
TIPS.TimerExpireTimes = "Repeat count (the sound law's third slot). "
    .. "Applied live."
TIPS.CooldownReadyEnable = "NEW (spec CD-33): the original's Cooldown module "
    .. "has NO ready sound of its own -- this is our addition, off until you "
    .. "ask for it. Applied live."
TIPS.CooldownReadyPath = "The sound file (a path the original itself ships "
    .. "a default for, Forte_Timer.lua:3301). Applied live."
TIPS.CooldownReadyTimes = "Repeat count (the sound law's third slot). "
    .. "Applied live."

function P.RegisterSoundPage()
    local O = FX.Options
    if not O or not O.pages or not FX.Settings then return false end
    if not O.pages[M] then
        FX.Settings:Register(M, P.DEFAULTS[M])
        O:RegisterPage({
            id = M,
            module = M,
            title = "Sound",
            colour = O.C.RED,
            build = function(b)
                b.Tips({
                    "The sounds: the fade bell (ShaysBell x2) and the early-break sound (x4) are the original's, at its two sites -- the fade block (Forte_Timer.lua:1049-1056) and the aura-sweep break (:1207).",
                    "The true-expiry bell and the cooldown-ready sound are NEW, both opt-in. The original's resist sound has NO row here: its signal (a resisted aura application) has no legal Forever twin, and docs/messages-sounds.md keeps that decision and the path until one exists.",
                    "Repeat = how many times the sound plays per event: the original's own sound rows carry that count (the ShaysBell default is 2).",
                    "Paths are game sound files, e.g. Sound\\Spells\\ShaysBell.wav.",
                })
                b.Section("Timer Fade Warning", function(s)
                    s.CHK({ module = M, key = "TimerFadeEnable",
                        label = "Bell when a CC timer starts fading",
                        tip = TIPS.TimerFadeEnable })
                    s.STR({ module = M, key = "TimerFadePath",
                        label = "Sound file", tip = TIPS.TimerFadePath })
                    s.NUM({ module = M, key = "TimerFadeTimes",
                        label = "Repeat", min = 1, max = 9, step = 1,
                        tip = TIPS.TimerFadeTimes })
                end, {
                    module = M,
                    keys = { "TimerFadeEnable", "TimerFadePath",
                        "TimerFadeTimes" },
                    tip = "The original's TimerFadeSound, verbatim.",
                })
                b.Section("Timer Break (early)", function(s)
                    s.CHK({ module = M, key = "TimerBreakEnable",
                        label = "Sound when a CC breaks early",
                        tip = TIPS.TimerBreakEnable })
                    s.STR({ module = M, key = "TimerBreakPath",
                        label = "Sound file", tip = TIPS.TimerBreakPath })
                    s.NUM({ module = M, key = "TimerBreakTimes",
                        label = "Repeat", min = 1, max = 9, step = 1,
                        tip = TIPS.TimerBreakTimes })
                end, {
                    module = M,
                    keys = { "TimerBreakEnable", "TimerBreakPath",
                        "TimerBreakTimes" },
                    tip = "The original's TimerBreakSound, verbatim.",
                })
                b.Section("Timer Expiry (new, opt-in)", function(s)
                    s.CHK({ module = M, key = "TimerExpireEnable",
                        label = "Play a sound at a timer expiry (new)",
                        tip = TIPS.TimerExpireEnable })
                    s.STR({ module = M, key = "TimerExpirePath",
                        label = "Sound file", tip = TIPS.TimerExpirePath })
                    s.NUM({ module = M, key = "TimerExpireTimes",
                        label = "Repeat", min = 1, max = 9, step = 1,
                        tip = TIPS.TimerExpireTimes })
                end, {
                    module = M,
                    keys = { "TimerExpireEnable", "TimerExpirePath",
                        "TimerExpireTimes" },
                    tip = "NEW: the original warns at the fade, not at the "
                        .. "expiry; opt in here.",
                })
                b.Section("Cooldown Ready (new)", function(s)
                    s.CHK({ module = M, key = "CooldownReadyEnable",
                        label = "Play a sound at a ready pop (new)",
                        tip = TIPS.CooldownReadyEnable })
                    s.STR({ module = M, key = "CooldownReadyPath",
                        label = "Sound file", tip = TIPS.CooldownReadyPath })
                    s.NUM({ module = M, key = "CooldownReadyTimes",
                        label = "Repeat", min = 1, max = 9, step = 1,
                        tip = TIPS.CooldownReadyTimes })
                end, {
                    module = M,
                    keys = { "CooldownReadyEnable", "CooldownReadyPath",
                        "CooldownReadyTimes" },
                    tip = "NEW (CD-33): the original plays nothing at a "
                        .. "ready pop; opt in here.",
                })
            end,
        })
    end
    return FX.Options.pages[M] ~= nil
end

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
    -- The soulstone pair: the original's two `SND` rows on the Soulstone
    -- Tracker's Bar Coloring sub (Forte_Soulstone.lua:640-641), defaults
    -- verbatim at :677-678 -- `{[0]=true,
    -- "Interface\\AddOns\\Forte_Core\\Sounds\\SoulstoneExpire.mp3", 1}` and
    -- `{[0]=true, "Sound\\Spells\\SimonGame_Visual_GameTick.wav", 1}`. The
    -- labels are the original's FWL.EXPIRED / FWL.READY
    -- (Forte_Soulstone/Localization.lua:68-69).
    SoulstoneFadeEnable = true,
    SoulstoneFadePath = "Interface\\AddOns\\Forte_Core\\Sounds\\SoulstoneExpire.mp3",
    SoulstoneFadeTimes = 1,
    SoulstoneReadyEnable = true,
    SoulstoneReadyPath = "Sound\\Spells\\SimonGame_Visual_GameTick.wav",
    SoulstoneReadyTimes = 1,
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
TIPS.SoulstoneFadeEnable = "Play the original's Expired sound when a tracked "
    .. "soulstone's window runs out (the SND row Forte_Soulstone.lua:640, "
    .. "played at its :429-445 expiry site; the FX_SOULSTONE_EXPIRED site). "
    .. "Applied live."
TIPS.SoulstoneFadePath = "The sound file (the original's shipped default, "
    .. "Forte_Soulstone.lua:677). The file ships with this build as "
    .. "Forte_Core/Sounds/SoulstoneExpire.mp3 (vendored unmodified, see "
    .. "Forte_Core/ATTRIBUTION.md), so the stock path resolves; any game "
    .. "sound path plays. Applied live."
TIPS.SoulstoneFadeTimes = "Repeat count (the original's third slot: 1). "
    .. "Applied live."
TIPS.SoulstoneReadyEnable = "Play the original's Ready sound when the "
    .. "warlock is ready to put a new soulstone up (the SND row "
    .. "Forte_Soulstone.lua:641, played at its :461-464 cooldown-end site; "
    .. "the FX_SOULSTONE_READY site). Applied live."
TIPS.SoulstoneReadyPath = "The sound file (the original's shipped default: "
    .. "Sound\\Spells\\SimonGame_Visual_GameTick.wav, Forte_Soulstone.lua:678 "
    .. "-- a game sound, playable as shipped). Applied live."
TIPS.SoulstoneReadyTimes = "Repeat count (the original's third slot: 1). "
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
                -- The Soulstone Tracker's own pair, the original's FWL.EXPIRED
                -- and FWL.READY rows (Forte_Soulstone.lua:640-641) and its
                -- shipped defaults (:677-678), at its two play sites
                -- (:429-445 the window's expiry, :461-464 the warlock's
                -- stone-cooldown end -- one instant on this self-only port).
                b.Section("Soulstone Expired", function(s)
                    s.CHK({ module = M, key = "SoulstoneFadeEnable",
                        label = "Expired", tip = TIPS.SoulstoneFadeEnable })
                    s.STR({ module = M, key = "SoulstoneFadePath",
                        label = "Sound file", tip = TIPS.SoulstoneFadePath })
                    s.NUM({ module = M, key = "SoulstoneFadeTimes",
                        label = "Repeat", min = 1, max = 9, step = 1,
                        tip = TIPS.SoulstoneFadeTimes })
                end, {
                    module = M,
                    keys = { "SoulstoneFadeEnable", "SoulstoneFadePath",
                        "SoulstoneFadeTimes" },
                    tip = "The original's SoulstoneFadeSound, verbatim.",
                })
                b.Section("Soulstone Ready", function(s)
                    s.CHK({ module = M, key = "SoulstoneReadyEnable",
                        label = "Ready", tip = TIPS.SoulstoneReadyEnable })
                    s.STR({ module = M, key = "SoulstoneReadyPath",
                        label = "Sound file", tip = TIPS.SoulstoneReadyPath })
                    s.NUM({ module = M, key = "SoulstoneReadyTimes",
                        label = "Repeat", min = 1, max = 9, step = 1,
                        tip = TIPS.SoulstoneReadyTimes })
                end, {
                    module = M,
                    keys = { "SoulstoneReadyEnable", "SoulstoneReadyPath",
                        "SoulstoneReadyTimes" },
                    tip = "The original's SoulstoneReadySound, verbatim.",
                })
            end,
        })
    end
    return FX.Options.pages[M] ~= nil
end

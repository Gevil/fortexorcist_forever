-- addon/Forte_Messages/Core/Sounds.lua
-- The sound layer: the original's one sound law, `FW:PlaySound` -- the value
-- `{[0]=enabled, [1]=path, [2]=times}` played through `PlaySoundFile`
-- repeated `[2]` times (docs/reference-functional-spec.md FE-18;
-- /tmp/fxref/Forte_Core/Forte_Core.lua:2072-2078; the `[2]` slot is a REPEAT
-- COUNT, spec ST-38:3297 -- "it is a real FX signature sound").
--
-- What is original law and what is new (spec CD-33 is the law the two rows
-- below are built against):
--   * TimerExpire* -- the Spell Timer's expiry sound. The original plays
--     `TimerFadeSound` at exactly the moment a row's window ends
--     (Forte_Timer.lua:1049-1056), default
--     `{[0]=true, "Sound\\Spells\\ShaysBell.wav", 2}` (Forte_Timer.lua:3297).
--     Ported verbatim as the row's three flat keys.
--   * CooldownReady* -- NEW. The original's Cooldown module has NO ready
--     sound of its own (CD-33, verified absence at Forte_Cooldown.lua:400-1000
--     -- the panel's only sound is the options click); the owner ruling
--     (PLAN §9, §10.2.7 "do not fix or replicate the original's broken code;
--     build what we actually need") ships it as an explicit, OPT-IN addition,
--     default OFF, and the pages label it new. The default path is a path the
--     original itself ships a default for (SimonGame_Visual_GameStart.wav,
--     Forte_Timer.lua:3301) -- no invented asset.
--
-- PlaySoundFile is the original's call (Forte_Core.lua:2075) and the call a
-- working Forever addon makes on the live client (CooldownMaster
-- UI/ReadyFrames.lua:37 `pcall(PlaySoundFile, path, "SFX")`); it runs in a
-- pcall here exactly like that pcall, and the repeat loop breaks at the
-- first raise. `Sounds.playFn` is the test seam (the suite counts calls;
-- the sim has no audio device).

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
FX.Messages = FX.Messages or {}

local Sounds = {}
FX.Messages.Sounds = Sounds

-- The three flat keys per row ride the "Sound" settings module (Pages/
-- Sound.lua owns the defaults; cfg is the module's live view).
Sounds.rows = {
    -- The row's window FADES (the CC is about to drop): the original's
    -- TimerFadeSound, fired from the FX_TIMER_FADING site (:1049-1056).
    TimerFade     = { name = "TimerFade", enable = "TimerFadeEnable",
                      path = "TimerFadePath", times = "TimerFadeTimes" },
    -- The CC broke EARLY (aura gone with window left, the :1207 site): the
    -- original's TimerBreakSound (Forte_Timer.lua:3298 --
    -- SimonGame_Visual_LevelStart.wav x4, default ON).
    TimerBreak    = { name = "TimerBreak", enable = "TimerBreakEnable",
                      path = "TimerBreakPath", times = "TimerBreakTimes" },
    -- The true expiry bell: NOT the original's law (it has no per-expiry
    -- sound -- the fade is the warning), kept as the NEW opt-in, default off.
    TimerExpire   = { name = "TimerExpire", enable = "TimerExpireEnable",
                      path = "TimerExpirePath", times = "TimerExpireTimes" },
    CooldownReady = { name = "CooldownReady", enable = "CooldownReadyEnable",
                      path = "CooldownReadyPath",
                      times = "CooldownReadyTimes" },
    -- The soulstone pair: the original's SoulstoneFadeSound /
    -- SoulstoneReadySound (Forte_Soulstone.lua:640-641, defaults :677-678),
    -- at the tracker's window-end site -- the 2012 panel plays the Fade bell
    -- at the tracked stone's expiry (:429-445) and the Ready bell at the
    -- warlock's stone-cooldown end (:461-464); the header of
    -- Forte_Core/Core/Events.lua carries the seeding law that makes them one
    -- instant on this self-only port.
    SoulstoneFade   = { name = "SoulstoneFade", enable = "SoulstoneFadeEnable",
                        path = "SoulstoneFadePath",
                        times = "SoulstoneFadeTimes" },
    SoulstoneReady  = { name = "SoulstoneReady", enable = "SoulstoneReadyEnable",
                        path = "SoulstoneReadyPath",
                        times = "SoulstoneReadyTimes" },
}

Sounds.cfg = nil          -- bound by the module at enable
Sounds.counts = { played = 0, refused = 0, rows = {} }

--- The one play loop (Forte_Core.lua:2073-2077 verbatim in shape: gate on
--- [0], repeat [2] times, one file). Returns the number of plays issued.
function Sounds:playRow(row)
    local cfg = self.cfg
    if not cfg or not row then return 0 end
    if not cfg[row.enable] then return 0 end
    local path = cfg[row.path]
    if type(path) ~= "string" or path == "" then return 0 end
    local times = tonumber(cfg[row.times]) or 1
    if times < 1 then times = 1 end
    if times > 9 then times = 9 end   -- the original's rows top out at 4; 9 is the cap
    local play = self.playFn
    if not play then
        play = (type(_G.PlaySoundFile) == "function") and _G.PlaySoundFile or nil
    end
    if not play then self.counts.refused = self.counts.refused + 1 return 0 end
    local played = 0
    for _ = 1, math.floor(times) do
        local ok = pcall(play, path)
        if not ok then break end
        played = played + 1
    end
    self.counts.played = self.counts.played + played
    if row.name then
        local rows = self.counts.rows
        rows[row.name] = (rows[row.name] or 0) + played
    end
    return played
end

--- The row's window is fading (the Forte_Timer.lua:1055 `PlaySound
--- ("TimerFadeSound")` site, reached through FX_TIMER_FADING).
function Sounds:TimerFade()
    return self:playRow(self.rows.TimerFade)
end

--- The CC broke early (the FX_TIMER_BROKEN site; the original routes
--- TimerBreakSound through its ST_BreakMessages/ST_OnTimerBreak path).
function Sounds:TimerBreak()
    return self:playRow(self.rows.TimerBreak)
end

--- The true expiry (NEW opt-in, default off -- the original has no
--- per-expiry sound, reached through FX_TIMER_EXPIRED).
function Sounds:TimerExpired()
    return self:playRow(self.rows.TimerExpire)
end

--- A cooldown popped ready (NEW, CD-33 -- the original has none).
function Sounds:CooldownReady()
    return self:playRow(self.rows.CooldownReady)
end

--- A tracked soulstone's window ran out (the original's `SS` expiry branch
--- at Forte_Soulstone.lua:429-445, reached through FX_SOULSTONE_EXPIRED).
function Sounds:SoulstoneFade()
    return self:playRow(self.rows.SoulstoneFade)
end

--- The warlock is ready to put a new soulstone up (the original's
--- `Saved.Cooldowns[warlock]` end at Forte_Soulstone.lua:461-464, reached
--- through FX_SOULSTONE_READY).
function Sounds:SoulstoneReady()
    return self:playRow(self.rows.SoulstoneReady)
end

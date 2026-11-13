-- addon/Forte_Messages/Module.lua
-- The Messages module: it subscribes to the Forte_Core event bus
-- (Core/Events.lua), reads the three settings modules (SelfMsg / Sound /
-- RaidMsg -- the pages are the defaults home), and turns every event into
-- the Channel chat line, the Banner flash, the Sounds play and the
-- legality-gated Announce send. Hook points, in the module's own words:
--
--   * FX_COOLDOWN_READY: fired by Forte_Cooldown/Module.lua's ProcessReadyPops
--     (the :525 ticker path, the `if FX.Fire then` nil-guard) with
--     (name, now, texPath, category). Pure subscriber here -- Forte_Cooldown
--     is an OptionalDep and is NOT touched;
--   * FX_TIMER_EXPIRED: fired by FORTE_TIMER ITSELF, at its own expiry site
--     (Forte_Timer/Core/Rows.lua's Sweep, the `opts.onExpire(row)` block, the
--     :1049-1056 law, nil-guarded `FX.Fire`), with (row.name, row.targetKey,
--     row.kind). This module only SUBSCRIBES. (Review 4 E3: the earlier shape
--     here replaced the Timer's `options.onExpire` field with a wrapper at
--     enable time, which the real load order never ran -- Forte_Messages
--     enables before Forte_Timer's OnEnable builds `options`, and a Timer
--     re-enable rebuilds the table and drops the wrapper. The fire now lives
--     where the expiry happens, so no enable order can lose it; the seam the
--     wrap used to guard is the producer's own, and `M:_SubscribeToBus()` is
--     the seam the tests use to play an enable order.);
--   * FX_SOULSTONE_EXPIRED / FX_SOULSTONE_READY: fired by FORTE_WARLOCK
--     ITSELF, at its soulstone tracker's window-end site
--     (Forte_Warlock/Core/Tools.lua's `SoulstoneTracker:Expire`, the
--     nil-guarded `FX.Fire`), with (target, at). Pure subscriber here: this
--     module plays the original's two bells (Forte_Soulstone.lua:640-641) and
--     requires no class addon -- a session with no Forte_Warlock loaded has
--     no firer, plays nothing, and the rows sit silent.
--   * the soulstone announce: no FX_SOULSTONE *cast* event exists and Forte_Warlock
--     is a LoadOnDemand class addon (the dependency law: an always-loaded
--     addon never lists one), so this module listens to the PLAYER's own
--     UNIT_SPELLCAST_SENT / UNIT_SPELLCAST_SUCCEEDED on its own frame
--     (created inside OnEnable, the frame law), resolves the spellID through
--     C_Spell.GetSpellInfo in a pcall with PlainOrNil on every field (the
--     Forte_Cooldown/Module.lua:329-334 RecordCastEvent pattern -- the spellID
--     is never compared, only looked up), and family-matches the NAME
--     against the soulstone family patterns { "^Create Soulstone",
--     "^Soulstone" } -- ONE home for the list: `FX.SoulstonePatterns`
--     (Forte_Core/Core/Constants.lua), which Forte_Warlock/Core/Tools.lua:142
--     also reads (review 4 m7: the two watchers are legitimately separate --
--     Tools tracks the buff, this announces the cast -- so only the PATTERN
--     is shared, the shared home being the one hard dependency both addons
--     have; Forte_Warlock itself is NOT required, the dependency law). A
--     mage hears "Soulstone Resurrection" named the same way, which is
--     exactly the behaviour that pattern defines. The target is the SENT
--     payload's target name (SUCCEEDED carries no target) -- PlainOrNil'd,
--     used as a string, never compared.
--
-- Live wiring (the task's "keys wired live"): every settings Set reaches
-- the module through FX.Settings:OnChange (the Forte_Timer/Module.lua:254
-- law), so every checkbox/colour/template/path/duration applies on the
-- keystroke -- the pages' tips all say "Applied live" and the tests prove
-- it. Announce gates re-read FX.SecretState (pcall'd Refresh) at send time,
-- so a lockdown that started mid-fight is honoured by the very next send.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist

FX.Messages = FX.Messages or {}
local P = FX.Messages.Pages
local Channel = FX.Messages.Channel
local Sounds = FX.Messages.Sounds
local Announce = FX.Messages.Announce
local Banner = FX.Messages.Banner

local M = { name = "Messages", version = "1.0.1" }
FX.Messages.Module = M
FX.RegisterModule("Messages", M)

-- The three settings pages, in display order.
local SETTINGS_MODULES = { "SelfMsg", "Sound", "RaidMsg" }

local BANNER_TICK = 0.05   -- the fade cadence (the 0.04-0.1 draw law)

-- ---------------------------------------------------------------- settings --
-- The live view: every key the three pages ship, one flat table, validated
-- at the gate (the Forte_Timer ApplySettings law). Defaults are the PAGES'
-- tables (Forte_Messages/Pages/*.lua -- the single source), copied fresh.
local TYPES = nil          -- built from P.DEFAULTS below (key -> b/n/s/c)
local CFG = nil            -- M.cfg points here

local function freshCfg()
    local cfg = {}
    for _, def in pairs(P.DEFAULTS) do
        for key, value in pairs(def) do
            if type(value) == "table" then
                local copy = {}
                for i = 1, #value do copy[i] = value[i] end
                cfg[key] = copy
            else
                cfg[key] = value
            end
        end
    end
    return cfg
end

local function buildTypes()
    TYPES = {}
    for _, def in pairs(P.DEFAULTS) do
        for key, value in pairs(def) do
            local t = type(value)
            TYPES[key] = (t == "boolean" and "b") or (t == "number" and "n")
                or (t == "table" and "c") or "s"
        end
    end
end

--- One settings Set, validated by the default's own type. Returns whether
--- the live view moved. Colour values are COPIED (a settings table is the
--- store's; the live view must not alias it).
function M:ApplySetting(key, value)
    if not TYPES then buildTypes() end
    local t = TYPES[key]
    if not t then return false end
    if t == "b" then
        CFG[key] = not not value
    elseif t == "n" then
        local n = tonumber(value)
        if n then CFG[key] = n end
    elseif t == "s" then
        if type(value) == "string" and value ~= "" then CFG[key] = value end
    elseif t == "c" then
        if type(value) == "table" then
            local c = CFG[key]
            if type(c) ~= "table" then c = {}; CFG[key] = c end
            for i = 1, 4 do
                local v = tonumber(value[i])
                if v then c[i] = math.min(1, math.max(0, v)) end
            end
        end
    end
    -- The fade texts carry the thresholds (the ST_GetFadeTime law): a fade
    -- text edit re-publishes FX.Timer.FadeWarnings (future inserts re-stamp;
    -- live rows keep their insert-time column-12 stamp, the original's law).
    if type(key) == "string" and key:match("FadeText$") then
        self:RefreshFadeWarnings()
    end
    return true
end

--- The stored view at enable (the ApplyStoredSettings law): every key of
--- the settings module, straight off the store.
function M:ApplyStoredSettings(moduleName)
    local S = FX.Settings
    if not S or not S.IsRegistered or not S:IsRegistered(moduleName) then return end
    local def = P.DEFAULTS[moduleName]
    if not def then return end
    for key in pairs(def) do
        local ok, value = pcall(S.Get, S, moduleName, key)
        if ok then self:ApplySetting(key, value) end
    end
end

function M:OnApplySettings(tbl, moduleName)
    if type(tbl) ~= "table" then return end
    for key, value in pairs(tbl) do self:ApplySetting(key, value) end
end

-- ------------------------------------------------------------ the ready pop --
--- The module-side announce pre-check (the row's own checkbox, read HERE,
--- before the announce layer's gate is entered): the send is not even
--- attempted, and that skip is the SAME opt-out `Announce:Group` /
--- `Announce:Channel` / `Announce:Whisper` count in
--- `Announce.counts.offSkipped` when the row is off inside the gate. One
--- counter, one law — Announce.lua's header law is "a skipped send is silent
--- and COUNTED (… so `/fx messages` reports what the lockdown ate)": a
--- pre-check that counted nothing made that line read `off-skipped 0` for an
--- install whose every announce row is off, which is the instrument's whole
--- purpose inverted. Every announce pre-check in this file counts through
--- here, so one opt-out is exactly one off-skip in every report.
local function announceSkipped()
    Announce.counts.offSkipped = Announce.counts.offSkipped + 1
end

--- The FX_COOLDOWN_READY listener (name, now, texPath, category). The
--- chat/banner pair is the Self Messages half (the original's chat line --
--- Core/Channel.lua), the sound is the NEW opt-in (CD-33 -- Core/Sounds.lua),
--- the announce pair is the RaidMsg half (Core/Announce.lua gates it).
--- Event payload fields are PlainOrNil'd before any use (the secret law).
function M:OnCooldownReady(name, now, texPath, category)
    local plain = FX.Compat.PlainOrNil(name)
    if type(plain) ~= "string" then return end
    local cfg = self.cfg
    self.counts.ready = self.counts.ready + 1
    if cfg.ReadyEnable then
        local text = Channel.format(cfg.ReadyText, plain)
        if cfg.ReadyChat then Channel:Show(text, cfg.ReadyColor) end
        if cfg.ReadyBanner then Banner:Show(text, cfg.ReadyColor, cfg.ReadySeconds) end
    end
    Sounds:CooldownReady()
    if cfg.ReadyAnnounce then
        Announce:Group(Channel.format(cfg.ReadyAnnounceText, plain),
            "ReadyAnnounce")
    else
        announceSkipped()
    end
    if cfg.ReadyChannel then
        Announce:Channel(Channel.format(cfg.ReadyAnnounceText, plain),
            "ReadyChannel")
    else
        announceSkipped()
    end
end

-- --------------------------------------------------------- the timer seam --
--- The four bus subscriptions, factored out of `OnEnable` so a test can play
--- an enable ORDER (subscribe before vs after `Forte_Timer:OnEnable()`): the
--- Timer's own `FX_TIMER_EXPIRED` fire (Core/Rows.lua's expiry site) must
--- reach this module's `OnTimerExpired` in both orders (review 4 E3). The
--- `On` calls are idempotent by handle: the old handles are Off'd first, so a
--- re-subscribe never doubles a listener.
function M:_SubscribeToBus()
    local module = self
    if self.hReady then FX.Off(self.hReady) end
    if self.hExpire then FX.Off(self.hExpire) end
    if self.hFading then FX.Off(self.hFading) end
    if self.hBroken then FX.Off(self.hBroken) end
    if self.hSoulFade then FX.Off(self.hSoulFade) end
    if self.hSoulReady then FX.Off(self.hSoulReady) end
    self.hReady = FX.On(FX.EVENTS.COOLDOWN_READY,
        function(name, now, texPath, category)
            module:OnCooldownReady(name, now, texPath, category)
        end)
    self.hExpire = FX.On(FX.EVENTS.TIMER_EXPIRED,
        function(spell, target, kind)
            module:OnTimerExpired(spell, target, kind)
        end)
    self.hFading = FX.On(FX.EVENTS.TIMER_FADING,
        function(spell, target, kind, secondsLeft)
            module:OnTimerFading(spell, target, kind, secondsLeft)
        end)
    self.hBroken = FX.On(FX.EVENTS.TIMER_BROKEN,
        function(spell, target, kind)
            module:OnTimerBroken(spell, target, kind)
        end)
    self.hSoulFade = FX.On(FX.EVENTS.SOULSTONE_EXPIRED,
        function(target, at)
            module:OnSoulstoneExpired(target, at)
        end)
    self.hSoulReady = FX.On(FX.EVENTS.SOULSTONE_READY,
        function(target, at)
            module:OnSoulstoneReady(target, at)
        end)
end

--- The FX_SOULSTONE_EXPIRED listener (target, at): the original's
--- `FW:PlaySound("SoulstoneFadeSound")` at its tracked stone's expiry
--- (Forte_Soulstone.lua:445). The chat/banner half of that site is the
--- SelfMsg page's Soulstone rows, which ride the cast events; this listener
--- is the bell, so it plays and counts and nothing else.
function M:OnSoulstoneExpired(target, at)
    self.counts.soulstoneFade = self.counts.soulstoneFade + 1
    Sounds:SoulstoneFade()
end

--- The FX_SOULSTONE_READY listener (target, at): the original's
--- `FW:PlaySound("SoulstoneReadySound")` at the warlock's stone-cooldown end
--- (Forte_Soulstone.lua:463).
function M:OnSoulstoneReady(target, at)
    self.counts.soulstoneReady = self.counts.soulstoneReady + 1
    Sounds:SoulstoneReady()
end

--- The banner's pump clock (m5, review 4). The hidden-frame law forbids the
--- banner frame owning an OnUpdate, so the clock is a C_Timer; a `NewTicker`
--- is a session-lifetime cost, so the pump is a SELF-RESCHEDULING
--- `C_Timer.After` chain (the debounce idiom Forte_Cooldown/Module.lua:62,
--- :480, :502 ships -- `DeleteTicker` is not in the pinned catalog): it is
--- armed by the first `Banner:Show` and the chain STOPS the pass the banner
--- lapses, so an idle session runs no closure at all.
function M:_StartBannerPump()
    if self._bannerPumping then return end
    self._bannerPumping = true
    C_Timer.After(BANNER_TICK, function() M:_BannerPumpStep() end)
end

--- One pump step: the banner's own liveness answer drives the chain -- a live
--- window re-arms the next step, a lapsed one ends the chain (and with it
--- every closure this session pays for the banner). Public to the suite: a
--- test drives the step directly, it never calls a render function.
function M:_BannerPumpStep()
    if not self._bannerPumping then return false end
    if Banner:Update() then
        C_Timer.After(BANNER_TICK, function() M:_BannerPumpStep() end)
        return true
    end
    self._bannerPumping = false
    return false
end

--- The banner pump's live state (the tests' census, `/fx messages`).
function M:BannerPumpActive()
    return self._bannerPumping == true
end

--- The FX_TIMER_EXPIRED listener (spell, target, kind). The chat text picks
--- the target/no-target template (the original's two TimeLeft rows).
function M:OnTimerExpired(spell, target, kind)
    local plain = FX.Compat.PlainOrNil(spell)
    if type(plain) ~= "string" then return end
    local cfg = self.cfg
    self.counts.expired = self.counts.expired + 1
    local hasTarget = type(target) == "string" and target ~= ""
        and target ~= "none"
    local text, announceText
    if hasTarget then
        text = Channel.format(cfg.ExpireText, plain, target)
        announceText = Channel.format(cfg.ExpireAnnounceText, plain, target)
    else
        text = Channel.format(cfg.ExpireNoTargetText, plain)
        announceText = Channel.format(cfg.ExpireAnnounceNoTargetText, plain)
    end
    if cfg.ExpireEnable then
        if cfg.ExpireChat then Channel:Show(text, cfg.ExpireColor) end
        if cfg.ExpireBanner then
            Banner:Show(text, cfg.ExpireColor, cfg.ExpireSeconds)
        end
    end
    Sounds:TimerExpired()
    if cfg.ExpireAnnounce then
        Announce:Group(announceText, "ExpireAnnounce")
    else
        announceSkipped()
    end
    if cfg.ExpireChannel then
        Announce:Channel(announceText, "ExpireChannel")
    else
        announceSkipped()
    end
end

-- ------------------------------------------------------------ fade watch --
-- The fade/break renderer. FX_TIMER_FADING / FX_TIMER_BROKEN fire from
-- Forte_Timer's own passes (Core/Rows.lua's Sweep fade block, the
-- :1049-1056 law; OnAuraAbsent's removal, the :1207 law). Which spells have
-- a threshold, and what their rows say, is this module's settings data
-- (Pages/RaidMsg.lua P.FADE_ROWS / P.FADE_SPELL_KEYS -- the original's
-- registrations, name-keyed). Forte_Timer reads only the PLAIN numbers of
-- FX.Timer.FadeWarnings (Rows:FadeWarnFor), stamped into a row at insert
-- (the original's column 12): this module parses the threshold out of the
-- fade TEXT (the ST_GetFadeTime law, Forte_Timer.lua:1590-1603: the first
-- run of [%.%d] in the message text, fallback 0.1, 0 for an unregistered
-- spell) and keeps the registry live.
local function fadeSecondsFor(text)
    if type(text) ~= "string" then return nil end
    local run = text:match("[%.%d]+")     -- ST_GetFadeTime's run, verbatim
    return tonumber(run)
end

function M:RefreshFadeWarnings()
    if not FX.Timer then return end
    FX.Timer.FadeWarnings = FX.Timer.FadeWarnings or {}
    local keys = P.FADE_SPELL_KEYS
    for spell in pairs(keys) do
        local text = CFG[keys[spell] .. "FadeText"]
        local seconds = fadeSecondsFor(text)
        FX.Timer.FadeWarnings[spell] = seconds or 0.1
        -- H1b (docs/localization.md): the Forte_Timer row keys are the
        -- generated data's English names, and `Casts:NameOf` canonicalizes
        -- into that space -- so the English key above is the one the rows
        -- meet. The localized alias is published alongside it (identity on
        -- enUS, zero extra keys) for the producer that hands a row's client
        -- name straight to `Rows:FadeWarnFor`, so a German `Verwandlung` row
        -- gets the Polymorph threshold instead of 0 = "no fade warning".
        local localized = FX.L(spell)
        if localized ~= spell and FX.Timer.FadeWarnings[localized] == nil then
            FX.Timer.FadeWarnings[localized] = seconds or 0.1
        end
    end
end

--- The FADE_SPELL_KEYS lookup key of a spell name that arrives from the
--- Timer bus (H1b): the row keys are the data's English names, a bus payload
--- may be the client's, and `CanonicalName` folds the second onto the first
--- (the identity on enUS).
local function fadeKey(spell)
    if type(spell) ~= "string" then return spell end
    local Locale = FX.Locale
    if Locale and Locale.CanonicalName then return Locale.CanonicalName(spell) end
    return spell
end

local function targetWord(target)
    if type(target) == "string" and target ~= "" and target ~= "none" then
        return target
    end
    return "?"
end

--- FX_TIMER_FADING (spell, target, kind, secondsLeft): the fade bell
--- (TimerFadeSound, the :1055 law -- played for every row that has a
--- threshold, independent of the message's bits) + the spell's fade message
--- routed by its party/channel bits.
function M:OnTimerFading(spell, target, kind, secondsLeft)
    local plain = FX.Compat.PlainOrNil(spell)
    if type(plain) ~= "string" then return end
    local cfg = self.cfg
    local keys = P.FADE_SPELL_KEYS
    local prefix = keys and keys[fadeKey(plain)]
    if not prefix then return end
    self.counts.fading = self.counts.fading + 1
    Sounds:TimerFade()
    local text = Channel.format(cfg[prefix .. "FadeText"],
        targetWord(FX.Compat.PlainOrNil(target)))
    Announce:Group(text, prefix .. "FadeParty")
    Announce:Channel(text, prefix .. "FadeChannel")
end

--- FX_TIMER_BROKEN (spell, target, kind): the early-break sound
--- (TimerBreakSound) + the spell's break message (the original's
--- ST_BreakMessages -> "*Break" rows, the :1207-1211 site).
function M:OnTimerBroken(spell, target, kind)
    local plain = FX.Compat.PlainOrNil(spell)
    if type(plain) ~= "string" then return end
    local cfg = self.cfg
    local keys = P.FADE_SPELL_KEYS
    local prefix = keys and keys[fadeKey(plain)]
    if not prefix then return end
    self.counts.broken = self.counts.broken + 1
    Sounds:TimerBreak()
    local text = Channel.format(cfg[prefix .. "BreakText"],
        targetWord(FX.Compat.PlainOrNil(target)))
    Announce:Group(text, prefix .. "BreakParty")
    Announce:Channel(text, prefix .. "BreakChannel")
end

-- ------------------------------------------------------------- soulstone --
-- The soulstone family patterns, ONE home: `FX.SoulstonePatterns`, declared
-- in Forte_Core/Core/Constants.lua (the one hard dependency of both this
-- always-loaded add-on and the LoadOnDemand Forte_Warlock, whose
-- Core/Tools.lua reads the same table -- review 4 m7: the two watchers are
-- legitimately separate, Tools tracks the buff and this announces the cast,
-- so the shared half is the PATTERN list, not the watcher). Name-based by
-- construction: every class that gets the spell gets it.
local SOULSTONE_PATTERNS = FX.SoulstonePatterns

--- The family gate of the announce watch: the name that arrives here is the
--- CLIENT's (`spellNameFor` below resolves a spellID through
--- `C_Spell.GetSpellInfo`), and the family patterns are the ENGLISH DATA
--- NAMES, so a localized client's `Seelenstein erstellen` never announced
--- (H1b, docs/localization.md). `FX.MatchesFamily` canonicalizes onto the
--- data key first -- the identity on enUS, where this is the plain
--- `name:match` it always was.
local function isSoulstoneName(name)
    return FX.MatchesFamily(name, SOULSTONE_PATTERNS)
end

--- spellID -> name, the Forte_Cooldown RecordCastEvent shape: the id rides
--- PlainOrNil, the lookup is pcall'd (a tainted lookup may raise), only a
--- plain string leaves.
local function spellNameFor(spellID)
    local id = FX.Compat.PlainOrNil(spellID)
    if id == nil or not C_Spell or not C_Spell.GetSpellInfo then return nil end
    local ok, resolved = pcall(function()
        local info = C_Spell.GetSpellInfo(id)
        return info and FX.Compat.PlainOrNil(info.name)
    end)
    if ok and type(resolved) == "string" then return resolved end
    return nil
end

--- One player cast event for the soulstone watch. SENT carries
--- (unit, targetName, castGUID, spellID) and stamps the target; SUCCEEDED
--- carries (unit, castGUID, spellID) -- the spellID is resolved by name
--- there, and the target name is only ever the stamped plain string.
--- INTERRUPTED (unit, castGUID, spellID, interruptedBy, castBarID) is the
--- cast ending WITHOUT succeeding: the source's `SoulstoneCancel` half
--- (`CA:RegisterOnSelfCastCancel`, Warlock.lua:295) -- the 2012 combat log's
--- cancel is the modern cast bar's interrupt, the one legal event that
--- means it.
function M:OnCastForSoulstone(event, unit, a, b, c)
    local cfg = self.cfg
    -- The cheap gate: with every soulstone row off the watch is inert, and
    -- no spell name is resolved for a stone nobody asked to be told about.
    if not cfg.SoulstoneAnnounce and not cfg.SoulstoneChannel
        and not cfg.SoulstoneStartParty and not cfg.SoulstoneStartChannel
        and not cfg.SoulstoneCancelParty and not cfg.SoulstoneCancelChannel
        and not cfg.SoulstoneStartWhisper
        and not cfg.SoulstoneCancelWhisper
        and not cfg.SoulstoneSuccessWhisper then
        self._ssPending = nil
        return
    end
    if event == "UNIT_SPELLCAST_SENT" then
        local name = spellNameFor(c)   -- (unit, target, castGUID, spellID)
        local family = name and isSoulstoneName(name)
        self._ssPending = family and FX.Compat.PlainOrNil(a) or nil
        -- The start leg rides the SAME stamp the SUCCEEDED leg consumes:
        -- the SENT payload's target name is the row's `%s` and the
        -- whisper's receiver (no stamp, no whisper -- the Announce:Whisper
        -- law, no name, the "?" text word).
        if family then self:AnnounceSoulstone("Start", self._ssPending) end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local name = spellNameFor(b)   -- (unit, castGUID, spellID)
        local pending = self._ssPending
        self._ssPending = nil
        if name and isSoulstoneName(name) then
            local target = type(pending) == "string" and pending or "?"
            local text = Channel.format(cfg.SoulstoneAnnounceText, target)
            self.counts.soulstone = self.counts.soulstone + 1
            if cfg.SoulstoneAnnounce then
                Announce:Group(text, "SoulstoneAnnounce")
            else
                announceSkipped()
            end
            if cfg.SoulstoneChannel then
                Announce:Channel(text, "SoulstoneChannel")
            else
                announceSkipped()
            end
            Announce:Whisper(cfg.SoulstoneSuccessWhisperText,
                "SoulstoneSuccessWhisper", pending)
        end
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        local name = spellNameFor(b)   -- (unit, guid, spellID, by, barID)
        if not (name and isSoulstoneName(name)) then return end
        local pending = self._ssPending
        self._ssPending = nil
        self:AnnounceSoulstone("Cancel", pending)
    end
end

--- The `Start` / `Cancel` half of the source's soulstone rows
--- (Warlock.lua:294-295, the texts at :352-353): the party/channel pair, the
--- channel twin and the whisper to the cast's target. `kind` is the row's
--- name in the source's key space, so the gate keys are the page's keys.
--- THE OWN-BOX GATE (the shipped-default law, review 5 hazard): this leg is
--- gated by its own `Soulstone<Kind>Party/Channel/Whisper` boxes ONLY -- it
--- rides NONE of the pre-existing `SoulstoneAnnounce`/`SoulstoneChannel`
--- boxes (those gate the Success half) -- and with all three of its boxes
--- OFF (every one ships OFF, E2) the leg is inert: no count, no send, no
--- off-skip bookkeeping. A default install stands mute on the whole cast.
--- The exemption from the module-side off-count (`announceSkipped`,
--- `M:OnTimerExpired`) is deliberate and is what makes it inert: that
--- counter counts a SEND that was asked for and switched off, and this gate
--- is the leg's own LIVENESS check -- the `OnCastForSoulstone` cheap gate
--- above already returns on the same all-off reading, so a leg that is not
--- armed at all reports no skips. `AnnounceSoulstone` runs its boxes
--- unconditionally once it is armed, so each of its sends rides the counting
--- gate inside `Announce:Group`/`Channel`/`Whisper`.
function M:AnnounceSoulstone(kind, target)
    local cfg = self.cfg
    local partyKey, channelKey = "Soulstone" .. kind .. "Party",
        "Soulstone" .. kind .. "Channel"
    local whisperKey = "Soulstone" .. kind .. "Whisper"
    if not (cfg[partyKey] or cfg[channelKey] or cfg[whisperKey]) then
        return nil
    end
    local text = Channel.format(cfg["Soulstone" .. kind .. "Text"],
        targetWord(FX.Compat.PlainOrNil(target)))
    self.counts.soulstone = self.counts.soulstone + 1
    if cfg[partyKey] then Announce:Group(text, partyKey) end
    if cfg[channelKey] then Announce:Channel(text, channelKey) end
    Announce:Whisper(cfg["Soulstone" .. kind .. "WhisperText"],
        whisperKey, target)
end

-- ------------------------------------------------------ own-cast announce --
-- THE GENERAL CAST ANNOUNCE HOOK (wave 2b T2). The soulstone watch above is
-- the shape this one copies -- the SAME frame, the SAME pair of player cast
-- events, the SAME `spellNameFor` spellID resolve, the SAME SENT-stamps /
-- SUCCEEDED-sends target law -- widened from the one soulstone family to
-- the 20 `P.CAST_ROWS` of `Pages/RaidMsg.lua` (the Druid/Paladin/Warrior
-- `CA:CastShow` raid warnings, `docs/class-port.md` S17). Nothing about the
-- soulstone half moved; a row is a name key, so the family pattern list and
-- this key table are the two name gates of one hook.
--
-- The laws this hook obeys:
--   * EVERY send goes through the legality gate -- `Announce:Group` /
--     `Announce:Channel`, gate key = the row's own `<Prefix>CastParty` /
--     `<Prefix>CastChannel`. A lockdown answer skips and COUNTS; only a
--     plain lockdown skips (the SecretState consumer law, Core/Announce.lua).
--   * EVERY row ships OFF (the shipped-default law, the manager ruling of
--     2026-11-02 / review 4 E2): a fresh install stands mute in the raid.
--     The gate-key check below is what keeps the texts inert until a box
--     is ticked.
--   * The NAME key is canonicalized (`FX.Locale.CanonicalName`, H1b, the
--     `fadeKey` law): the cast event carries the CLIENT's name, the rows
--     are keyed on the generated data's English names, and a German
--     `Schildwall` must meet the Shield Wall row. The enUS identity.
--   * The Druid rows key on PLAIN spell names (the Q5 ruling of
--     2026-11-02): the 2012 `_FERAL/_BEAR/_CAT` form suffixes label the
--     form-paired bar rows, not announces.
--   * The specialization gate the source put on ONE row (Paladin.lua:139)
--     rides the row's `spec` field as the RECORDED gate; no gate is
--     enforced here, because the row's Forever key (`Avenging Wrath`) is
--     itself spec-specific on this build -- a cast of it means the spec.
--     Open item if a build ever shares that name.
--   * The target is only ever the stamped plain string from the SENT
--     payload, `"?"` when no stamp is in hand (the soulstone law); the
--     non-target rows' texts carry no `%s`, so the word is ignored there.
local CAST_ROWS, CAST_KEYS = P.CAST_ROWS, P.CAST_SPELL_KEYS

--- The CAST_SPELL_KEYS prefix of a cast name, the `fadeKey` shape:
--- canonicalize the client's name onto the data key, then ask the table.
local function castPrefixFor(name)
    if type(name) ~= "string" then return nil end
    local keys = CAST_KEYS
    if not keys then return nil end
    local Locale = FX.Locale
    local key = name
    if Locale and Locale.CanonicalName then key = Locale.CanonicalName(name) end
    return keys[key]
end

--- Is any of the 40 cast gate keys ticked? The cheap gate of the hook: 40
--- reads of a live table per cast event (a cast is at most a few a second)
--- beats resolving a spell name for a raid nobody asked to be told about.
function M:CastRowArmed(cfg)
    for _ = 1, #CAST_ROWS do
        local prefix = CAST_ROWS[_].prefix
        if cfg[prefix .. "CastParty"] or cfg[prefix .. "CastChannel"] then
            return true
        end
    end
    return false
end

--- One player cast event for the cast rows. SENT carries
--- (unit, targetName, castGUID, spellID) and stamps { row, target };
--- SUCCEEDED carries (unit, castGUID, spellID) and is where the announce
--- goes - the spellID is resolved by name, and the target is the stamp.
function M:OnCastForAnnounce(event, unit, a, b, c)
    local cfg = self.cfg
    if not self:CastRowArmed(cfg) then
        self._castPending = nil
        return
    end
    if event == "UNIT_SPELLCAST_SENT" then
        local prefix = castPrefixFor(spellNameFor(c))  -- (u, tgt, guid, id)
        self._castPending = prefix
            and { prefix = prefix, target = FX.Compat.PlainOrNil(a) } or nil
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local prefix = castPrefixFor(spellNameFor(b))  -- (u, guid, id)
        local pending = self._castPending
        self._castPending = nil
        if not prefix then return end
        local target = (pending and pending.prefix == prefix
            and type(pending.target) == "string" and pending.target) or "?"
        local text = Channel.format(cfg[prefix .. "CastText"], target)
        self.counts.cast = self.counts.cast + 1
        if cfg[prefix .. "CastParty"] then
            Announce:Group(text, prefix .. "CastParty")
        else
            announceSkipped()
        end
        if cfg[prefix .. "CastChannel"] then
            Announce:Channel(text, prefix .. "CastChannel")
        else
            announceSkipped()
        end
    end
end

-- ------------------------------------------------------- pet-cast announce --
-- THE WARLOCK PET ANNOUNCE HOOK (Wave 4, Options WL+Msg item 6). The
-- `OnCastForAnnounce` hook above, widened from the player's own casts to the
-- FELGUARD's: the same pair of cast events, the same `spellNameFor` resolve,
-- the same SENT-stamps / SUCCEEDED-sends target law, the same gate keys --
-- the rows being the nine `P.PET_ROWS` of the source's Warlock Pet
-- sub-category (Warlock.lua:305-328). The pet spine is the one Forte_Timer
-- already proves live (its `Module.lua` pet registration, wave 2b "PetRows
-- v2"): a pet Seduction is a real event stream on this client.
--
-- The target law is the SAME and no timer is needed for it: the source read
-- `UnitName("pettarget")` behind a half-second settle (`PetTargetDelay`,
-- Warlock.lua:366-369) because the 2012 combat log named no target; on this
-- interface the target name rides the SENT payload itself (the field
-- Forte_Timer's pet feed reads), so the row gets the name off the event and
-- `"?"` when the field is secret -- no unit read, no delay, no invented
-- name.
--
-- THE READY PAIR (`SpellLockReady` / `DevourMagicReady`, the source's two
-- `CD:RegisterOnCooldownReady` rows, Warlock.lua:271-276) rides the pet's
-- cast plus the cooldown the GENERATED DATA carries for the spell (Spell
-- Lock 30 000 ms, Devour Magic 8 000 ms, Data/Warlock.lua:163-164) -- the
-- numbers are never typed by hand, and with Forte_Warlock's data not loaded
-- (it is a LoadOnDemand class addon) the window can not be measured, so the
-- Ready rows do not fire: a row with no number behind it says so on the
-- page, and no constant is invented to fill it.
local PET_ROWS, PET_KEYS, PET_KINDS = P.PET_ROWS, P.PET_SPELL_KEYS,
    P.PET_ROW_KINDS

--- The pet row stem of a cast name: the data key first, the canonical form
--- second (the `castPrefixFor` law -- the client's localized name resolves
--- through `FX.Locale.CanonicalName` onto the English data name), and a
--- case/space-insensitive pass over the table's own keys third, so a
--- two-word spell ("Spell Lock", "Devour Magic") matches in every name
--- form the client hands out. The table's keys are the DATA's names, so the
--- third pass adds no new fact -- only a looser spelling of the same one.
local function petPrefixFor(name)
    if type(name) ~= "string" then return nil end
    local keys = PET_KEYS
    if not keys then return nil end
    if keys[name] then return keys[name] end
    local Locale = FX.Locale
    if Locale and Locale.CanonicalName then
        local key = Locale.CanonicalName(name)
        if type(key) == "string" and keys[key] then return keys[key] end
    end
    local needle = name:lower():gsub("[^%w]", "")
    for k, v in pairs(keys) do
        if k:lower():gsub("[^%w]", "") == needle then return v end
    end
    return nil
end

--- The plain numeric spellID of a cast payload field (a secret id is not a
--- data key, and no arithmetic runs on a value that is not a plain number).
local function plainSpellID(id)
    local plain = FX.Compat.PlainOrNil(id)
    if type(plain) == "number" then return plain end
    return nil
end

--- The generated data row of a pet cast: the English data NAME (the key
--- space `P.PET_SPELL_KEYS` is written in -- locale-free by construction)
--- and its `cooldownMs`. Nil with no data loaded: Forte_Warlock is a
--- LoadOnDemand class addon and the data table is its file's; this add-on
--- must not require it (the dependency law).
local function petDataRow(spellID)
    local data = FX.Data and FX.Data.Warlock
    if type(data) ~= "table" then return nil end
    local row = data[spellID]
    if type(row) ~= "table" then return nil end
    if type(row.name) ~= "string" then return nil end
    return row
end

--- Any of the 18 pet group/channel boxes ticked? The cheap gate (the
--- `CastRowArmed` law).
function M:PetRowArmed(cfg)
    for _ = 1, #PET_ROWS do
        local key = PET_ROWS[_].key
        if cfg[key .. "Party"] or cfg[key .. "Channel"] then return true end
    end
    return false
end

--- The source's `CA:CastShow("<Stem><Kind>")` for one pet row: the
--- party/channel pair, both behind their own box and the legality gate.
function M:AnnouncePet(stem, kind, target)
    local kinds = PET_KINDS and PET_KINDS[stem]
    local key = kinds and kinds[kind]
    if not key then return nil end
    local cfg = self.cfg
    local text = Channel.format(cfg[key .. "Text"],
        targetWord(FX.Compat.PlainOrNil(target)))
    self.counts.pet = self.counts.pet + 1
    local sent = 0
    if cfg[key .. "Party"] then
        Announce:Group(text, key .. "Party")
        sent = sent + 1
    else
        announceSkipped()
    end
    if cfg[key .. "Channel"] then
        Announce:Channel(text, key .. "Channel")
        sent = sent + 1
    else
        announceSkipped()
    end
    return sent
end

--- One PET cast event. The payload orders are the catalog's, identical to
--- the player's (the field positions Forte_Timer's pet feed reads):
---   UNIT_SPELLCAST_SENT      (unit, target, castGUID, spellID)
---   UNIT_SPELLCAST_SUCCEEDED (unit, castGUID, spellID, castBarID)
---   UNIT_SPELLCAST_FAILED    (unit, castGUID, spellID, failReason, …)
--- so the spellID is the 4th field on SENT and the 3rd on the rest.
function M:OnPetCastForAnnounce(event, unit, a, b, c)
    local cfg = self.cfg
    if not self:PetRowArmed(cfg) then
        self._petPending = nil
        return
    end
    if event == "UNIT_SPELLCAST_SENT" then
        local stem = petPrefixFor(spellNameFor(c))  -- (u, tgt, guid, id)
        self._petPending = stem
            and { stem = stem, target = FX.Compat.PlainOrNil(a) } or nil
        if stem then
            self:AnnouncePet(stem, "start", self._petPending.target)
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local stem = petPrefixFor(spellNameFor(b))  -- (u, guid, id)
        local pending = self._petPending
        self._petPending = nil
        if not stem then return end
        local target = (pending
            and type(pending.target) == "string" and pending.target) or "?"
        self:AnnouncePet(stem, "success", target)
        self:ArmPetReady(plainSpellID(b))
    elseif event == "UNIT_SPELLCAST_FAILED" then
        local stem = petPrefixFor(spellNameFor(b))  -- (u, guid, id, reason)
        self._petPending = nil
        if not stem then return end
        self:AnnouncePet(stem, "failed", "?")
    end
end

--- Arm the `Ready` half of a pet spell: the data row's own `cooldownMs`
--- from this cast. The one-shot timer is the banner pump's idiom (a
--- self-terminating `C_Timer.After`, pinned catalog
--- @TimerDocumentation.lua `C_Timer.After(seconds, callback)`) -- one
--- closure per pet cast, none while the pet is idle. `M.afterFn` is the
--- suite's seam (a 30-second real wait is not a test); production reads
--- C_Timer.
function M:ArmPetReady(spellID)
    if spellID == nil then return nil end
    local row = petDataRow(spellID)
    if not row or type(row.cooldownMs) ~= "number" then return nil end
    local seconds = row.cooldownMs / 1000
    if seconds <= 0 then return nil end
    local after = self.afterFn
    if not after and C_Timer and C_Timer.After then
        after = function(s, fn) return C_Timer.After(s, fn) end
    end
    if type(after) ~= "function" then return nil end
    local ok = pcall(after, seconds, function() M:OnPetReady(spellID) end)
    return ok and "armed" or "failed"
end

--- The `Ready` moment itself: the window armed by the pet's cast ran out.
--- Public to the suite -- the tests drive this step directly, exactly as
--- they drive `_BannerPumpStep`, never a real 30 s wait.
function M:OnPetReady(spellID)
    local row = petDataRow(plainSpellID(spellID) or spellID)
    if not row then return nil end
    local keys = PET_KEYS
    local stem = keys and keys[row.name]
    if not stem then return nil end
    self.counts.petReady = self.counts.petReady + 1
    return self:AnnouncePet(stem, "ready", "?")
end

-- ------------------------------------------------------------------ enable --
function M:OnEnable()
    if not TYPES then buildTypes() end
    CFG = freshCfg()
    self.cfg = CFG
    self.counts = { ready = 0, expired = 0, soulstone = 0, cast = 0,
        fading = 0, broken = 0, soulstoneFade = 0, soulstoneReady = 0,
        pet = 0, petReady = 0 }
    self.enabled = true

    -- The layers get the SAME live table: a settings Set is seen by all.
    Sounds.cfg = CFG
    Announce.cfg = CFG
    Announce.channelOut = Channel
    Banner:Init()
    -- m5 (review 4): the banner's pump clock is born with the first banner
    -- and dies when the window lapses -- never a session-lifetime ticker.
    Banner.onActive = function() M:_StartBannerPump() end

    -- The pages FIRST (they are the defaults home: registering them makes
    -- FX.Settings:Register see the tables, so ApplyStoredSettings below
    -- reads the store with the defaults in place -- the Forte_Timer
    -- OnEnable order, Module.lua:542-543).
    self:RegisterPages()

    -- Stored settings + the live wires (all three modules; the OnChange
    -- law Forte_Timer/Module.lua:252-265).
    for _ = 1, 3 do
        self:ApplyStoredSettings(SETTINGS_MODULES[_])
    end
    -- The fade registry, after the store (the thresholds parse from the
    -- STORED fade texts -- the ST_GetFadeTime reads FW.Settings[what][1]).
    self:RefreshFadeWarnings()
    local S = FX.Settings
    if S and S.OnChange and not self._wired then
        self._wired = true
        local module = self
        for i = 1, #SETTINGS_MODULES do
            local name = SETTINGS_MODULES[i]
            S:OnChange(name, function(key, value)
                module:ApplySetting(key, value)
            end)
        end
    end

    -- The bus subscriptions (the Forte_Core bus; FX.On exists by hard
    -- dependency -- Forte_Messages lists Forte_Core as its one Dependency).
    -- Factored out so the tests can play the enable ORDER (E3): the
    -- FX_TIMER_EXPIRED producer is Forte_Timer's own expiry site, so these
    -- listeners catch it whether they were installed before or after the
    -- Timer's OnEnable.
    local module = self
    self:_SubscribeToBus()

    -- The cast watches (the soulstone family, the 20 cast announce rows and
    -- the nine Warlock pet rows): one frame, created HERE (the frame law),
    -- on the player's own cast events -- both names verified in the pinned
    -- Forever catalog (UnitDocumentation, the cast events the Cooldown
    -- module also registers) before registration. The INTERRUPTED leg is the
    -- source's `CA:RegisterOnSelfCastCancel` half (Warlock.lua:295 -- the
    -- soulstone cast that ends WITHOUT succeeding), the same registration
    -- Forte_Timer/Module.lua:607 makes for the player. The PET legs are the
    -- pet cast spine Forte_Timer registers for the pet unit (its
    -- Module.lua:616-617, wave 2b "PetRows v2"), widened by FAILED because
    -- the source's pet rows include a Failed half (Warlock.lua:309,:317,
    -- :324) that the Timer's row feed has no use for.
    local f = CreateFrame("Frame")
    self._eventFrame = f   -- the tests' handle
    f:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
    f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    f:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    f:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "pet")
    f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "pet")
    f:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "pet")
    f:SetScript("OnEvent", function(_, event, unit, a, b, c)
        local plainUnit = FX.Compat.PlainOrNil(unit)
        -- The unit token is what routes the two feeds (the Timer's law).
        if plainUnit == "pet" then
            module:OnPetCastForAnnounce(event, unit, a, b, c)
            return
        end
        if type(plainUnit) == "string" and plainUnit ~= "player" then return end
        module:OnCastForSoulstone(event, unit, a, b, c)
        module:OnCastForAnnounce(event, unit, a, b, c)
    end)

    return true
end

--- The three pages, once, at PLAYER_LOGIN (the Forte_Hunter load-order law
--- -- nothing on FX.Options at file load). RegisterPage refreshes the
--- index cells itself (Forte_Options/UI/Window.lua), so the SelfMsg /
--- Sound / RaidMsg cells light on registration.
function M:RegisterPages()
    local P2 = FX.Messages.Pages
    local fns = { P2.RegisterSelfMsgPage, P2.RegisterSoundPage,
        P2.RegisterRaidMsgPage }
    local registered, total = 0, 0
    for i = 1, #fns do
        total = total + 1
        local ok, res = pcall(fns[i])
        if ok and res then registered = registered + 1 end
    end
    self.pages = { registered = registered, total = total }
    return registered
end

--- `/fx messages` (the Forte_Timer/Module.lua:723 RegisterSlash pattern).
FX.RegisterSlash("messages", function()
    M:Status()
end)

--- /fx messages.
function M:Status()
    local c = self.counts
    FX.Print(string.format(
        "messages: ready %d | expired %d | fading %d | broken %d | soulstones %d | casts %d | pet %d | petReady %d | chat %d | printed %d | banner %d | fade %d | break %d | ssExpired %d | ssReady %d | sounds %d",
        c.ready, c.expired, c.fading, c.broken, c.soulstone, c.cast,
        c.pet, c.petReady,
        Channel.counts.chat,
        Channel.counts.printed, Banner.counts.shown,
        Sounds.counts.rows.TimerFade or 0,
        Sounds.counts.rows.TimerBreak or 0,
        Sounds.counts.rows.SoulstoneFade or 0,
        Sounds.counts.rows.SoulstoneReady or 0,
        Sounds.counts.played))
    FX.Print(Announce:StatusLines())
    FX.Print(string.format(
        "pages %d/%d | banner %s | %d FX_TIMER_EXPIRED listener(s)",
        self.pages and self.pages.registered or 0,
        self.pages and self.pages.total or 3,
        self:BannerPumpActive() and "pump running" or "pump idle",
        FX.ListenerCount and FX.ListenerCount(FX.EVENTS.TIMER_EXPIRED) or -1))
end

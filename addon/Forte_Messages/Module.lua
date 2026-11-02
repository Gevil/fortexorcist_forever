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
--   * FX_TIMER_EXPIRED: Forte_Timer ships no bus fire, so this module WRAPS
--     the Timer's own expire seam -- options.onExpire (set to announceExpiry
--     in Forte_Timer/Module.lua:540, called as opts.onExpire(row) from
--     Core/Rows.lua's Sweep) -- from here, at enable time, chain-calling the
--     previous handler first and then firing the bus with
--     (row.name, row.targetKey, row.kind). Forte_Timer is not edited; if it
--     is absent the wrap is skipped (self.timerHook = "absent") and the bus
--     seam stays open for a later Timer-side fire;
--   * the soulstone announce: no FX_SOULSTONE event exists and Forte_Warlock
--     is a LoadOnDemand class addon (the dependency law: an always-loaded
--     addon never lists one), so this module listens to the PLAYER's own
--     UNIT_SPELLCAST_SENT / UNIT_SPELLCAST_SUCCEEDED on its own frame
--     (created inside OnEnable, the frame law), resolves the spellID through
--     C_Spell.GetSpellInfo in a pcall with PlainOrNil on every field (the
--     Forte_Cooldown/Module.lua:329-334 RecordCastEvent pattern -- the spellID
--     is never compared, only looked up), and family-matches the NAME
--     against the Warlock family's shipped patterns { "^Create Soulstone",
--     "^Soulstone" } (Forte_Warlock/Core/Tools.lua:142 -- the patterns are
--     copied as the family's law, the addon is not required; a mage hears
--     "Soulstone Resurrection" named the same way, which is exactly the
--     behaviour that pattern defines). The target is the SENT payload's
--     target name (SUCCEEDED carries no target) -- PlainOrNil'd, used as a
--     string, never compared.
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

local M = { name = "Messages", version = "0.1.0" }
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
    if cfg.SplashKick and FX.Fire then
        FX.Fire(FX.EVENTS.SPLASH, plain, FX.Compat.PlainOrNil(texPath))
    end
    if cfg.ReadyAnnounce then
        Announce:Group(Channel.format(cfg.ReadyAnnounceText, plain),
            "ReadyAnnounce")
    end
    if cfg.ReadyChannel then
        Announce:Channel(Channel.format(cfg.ReadyAnnounceText, plain),
            "ReadyChannel")
    end
end

-- ----------------------------------------------------------- the timer wrap --
--- The FX_TIMER_EXPIRED path: the Forte_Timer options.onExpire seam, wrapped
--- (NOT edited) at enable. The row is the Rows.lua table: .name, .targetKey
--- (the "none" sentinel = self/no target), .kind. The previous handler
--- (announceExpiry, Forte_Timer/Module.lua:472) is chain-called FIRST, so
--- the Timer's own behaviour is untouched by our presence.
-- The wrap registry: a FUNCTION carries no fields (indexing one raises), so
-- "is this our wrap?" lives in this weak-keyed table, not on the closure.
M.wrappedFns = setmetatable({}, { __mode = "k" })

function M:WrapTimerExpire()
    local TM = FX.Timer and FX.Timer.Module
    local opts = TM and TM.options
    if not opts or type(opts.onExpire) ~= "function" then
        self.timerHook = "absent"   -- no Forte_Timer loaded: bus seam open
        return
    end
    if self.wrappedFns[opts.onExpire] then
        self.timerHook = "wrapped"  -- idempotent enable
        return
    end
    local prev = opts.onExpire
    local module = self
    local wrapped = function(row)
        if prev then prev(row) end
        if type(row) == "table" and type(row.name) == "string"
            and FX.Fire and module.enabled then
            FX.Fire(FX.EVENTS.TIMER_EXPIRED, row.name,
                FX.Compat.PlainOrNil(row.targetKey),
                FX.Compat.PlainOrNil(row.kind))
        end
    end
    self.wrappedFns[wrapped] = true
    opts.onExpire = wrapped
    self.timerHook = "wrapped"
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
    end
    if cfg.ExpireChannel then
        Announce:Channel(announceText, "ExpireChannel")
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
    end
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
    local prefix = keys and keys[plain]
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
    local prefix = keys and keys[plain]
    if not prefix then return end
    self.counts.broken = self.counts.broken + 1
    Sounds:TimerBreak()
    local text = Channel.format(cfg[prefix .. "BreakText"],
        targetWord(FX.Compat.PlainOrNil(target)))
    Announce:Group(text, prefix .. "BreakParty")
    Announce:Channel(text, prefix .. "BreakChannel")
end

-- ------------------------------------------------------------- soulstone --
-- The Warlock family's shipped family patterns (Forte_Warlock/Core/Tools.
-- lua:142 -- law copied, the LoadOnDemand addon NOT required: the dependency
-- law). Name-based by construction: every class that gets the spell gets it.
local SOULSTONE_PATTERNS = { "^Create Soulstone", "^Soulstone" }

local function isSoulstoneName(name)
    for _ = 1, #SOULSTONE_PATTERNS do
        local pattern = SOULSTONE_PATTERNS[_]
        if name:match(pattern) then return true end
    end
    return false
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
function M:OnCastForSoulstone(event, unit, a, b, c)
    local cfg = self.cfg
    if not cfg.SoulstoneAnnounce and not cfg.SoulstoneChannel then
        self._ssPending = nil
        return
    end
    if event == "UNIT_SPELLCAST_SENT" then
        local name = spellNameFor(c)   -- (unit, target, castGUID, spellID)
        self._ssPending = (name and isSoulstoneName(name))
            and FX.Compat.PlainOrNil(a) or nil
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
            end
            if cfg.SoulstoneChannel then
                Announce:Channel(text, "SoulstoneChannel")
            end
        end
    end
end

-- ------------------------------------------------------------------ enable --
function M:OnEnable()
    if not TYPES then buildTypes() end
    CFG = freshCfg()
    self.cfg = CFG
    self.counts = { ready = 0, expired = 0, soulstone = 0,
        fading = 0, broken = 0 }
    self.enabled = true
    self.timerHook = "pending"

    -- The layers get the SAME live table: a settings Set is seen by all.
    Sounds.cfg = CFG
    Announce.cfg = CFG
    Announce.channelOut = Channel
    Banner:Init()

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
    local module = self
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

    -- The Timer seam, wrapped not edited (the header's contract).
    self:WrapTimerExpire()

    -- The banner clock: the always-live C_Timer ticker (the hidden-frame
    -- law -- the banner frame never owns an OnUpdate).
    C_Timer.NewTicker(BANNER_TICK, function()
        Banner:Update()
    end)

    -- The soulstone watch: one frame, created HERE (the frame law), on the
    -- player's own cast events -- both names verified in the pinned Forever
    -- catalog (UnitDocumentation, the cast events the Cooldown module also
    -- registers) before registration.
    local f = CreateFrame("Frame")
    self._eventFrame = f   -- the tests' handle
    f:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
    f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    f:SetScript("OnEvent", function(_, event, unit, a, b, c)
        local plainUnit = FX.Compat.PlainOrNil(unit)
        if type(plainUnit) == "string" and plainUnit ~= "player" then return end
        module:OnCastForSoulstone(event, unit, a, b, c)
    end)

    self:RegisterPages()
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
        "messages: ready %d | expired %d | fading %d | broken %d | soulstones %d | chat %d | printed %d | banner %d | fade %d | break %d | sounds %d",
        c.ready, c.expired, c.fading, c.broken, c.soulstone,
        Channel.counts.chat,
        Channel.counts.printed, Banner.counts.shown,
        Sounds.counts.rows.TimerFade or 0,
        Sounds.counts.rows.TimerBreak or 0, Sounds.counts.played))
    FX.Print(Announce:StatusLines())
    FX.Print(string.format("timer hook: %s | pages %d/%d",
        tostring(self.timerHook),
        self.pages and self.pages.registered or 0,
        self.pages and self.pages.total or 3))
end

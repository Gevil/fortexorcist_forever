-- addon/Forte_Hunter/tests/test_swing.lua
-- wow-ui-sim tests for the Hunter UI (UI/Swing.lua, UI/Reminder.lua,
-- Pages/Hunter.lua): the Auto Shot swing bar geometry driven by an injected
-- clock, its idle/ticker law, the aspect reminder's Missing() gate and
-- pulse, the live settings seam (FX.Settings -> the frames), the shared lock
-- convention, the class gate and the registered options page — incl. the
-- Iteration J slice γ page law: the BarMode picker's §7.1 rows, the
-- marker/rail tips, the section keys-list recycle law and the
-- ShowSafeWindow -> BarMode migration.
--
-- Every tracker here is INJECTED (Swing:SetTracker / Reminder:SetAspects):
-- no real time, no combat driving, no real aura read. The sim profile is not
-- a Hunter, so the UI module's login gate never fires in the gate run --
-- Init()/OnClassChanged("HUNTER") are driven directly (the established
-- pattern of Forte_Cooldown/tests/test_timeline.lua).

local FX = ForteXorcist
local Swing = FX.Hunter.Swing
local Reminder = FX.Hunter.Reminder
local UI = FX.Hunter.UI
local S = FX.Hunter.SwingSkin
local RS = FX.Hunter.ReminderSkin
local ST = FX.Settings

local function near(actual, expected)
    return assertTrue(math.abs(actual - expected) < 1e-6)
end
-- Frame geometry round-trips float32 in the sim; the acceptance's tolerance.
local function nearpx(actual, expected)
    return assertTrue(math.abs(actual - expected) <= 0.5)
end
local function near3(actual, expected)
    return assertTrue(math.abs(actual - expected) < 1e-3)
end

local function fakeTracker(nowBox)
    return FX.Hunter.NewSwingTracker({
        now = function() return nowBox[1] end,
        speedReader = function() return nil end,
        rangedType = 2,
    })
end

-- The whole file is the geometry-LAW suite: it reads the drawn fill width,
-- which is the v2 Lua SetSize law (the edge pass `Update`; PLAN §11.13: the
-- per-frame motion pass runs the same function, pinned in
-- test_swing_motion.lua). Wave I-3 added the engine-armed fill
-- beside it (UI/Swing.lua's Fill law; its default posture is this same lua
-- path, and the flip of that default is a launch-day probe), so the mode is
-- pinned here explicitly: this file keeps pinning the law no matter which
-- path the module defaults to. The engine path, its arms and its parity
-- with this law are tests/test_swing3.lua's subject.
Swing:SetFillEngineMode("lua")
assertFalse(Swing:UsesEngineFill())

-- ---------------------------------------------------------------- Swing bar --

test("Init builds the 200x12 swing bar, idempotent, hidden while idle", function()
    Swing:Init()
    assertNotNil(Swing.anchor)
    assertNotNil(ForteXorcistHunterSwingAnchor)
    assertEquals("ForteXorcistHunterSwingAnchor",
        ForteXorcistHunterSwingAnchor:GetName())
    assertEquals(200, Swing.anchor:GetWidth())
    assertEquals(12, Swing.anchor:GetHeight())
    -- Idempotence: a second Init rebuilds nothing.
    Swing:Init()
    assertEquals(200, Swing.anchor:GetWidth())
    -- Idle: no bar, no per-frame script, no fill.
    assertFalse(Swing.anchor:IsShown())
    assertNil(Swing.anchor:GetScript("OnUpdate"))
    assertEquals(0, Swing.fill:GetWidth())
    print("[swing] font=" .. tostring(Swing.fontFile))
end)

test("fill width = fraction x width at 0 / 0.5 / 1 (injected clock)", function()
    local clock = { 1000 }
    local t = fakeTracker(clock)
    Swing:SetTracker(t)
    -- The single-phase fallback mode: the pre-v2 geometry law.
    Swing:SetShowSafeWindow(false)
    t:OnSwingStart(2.0, 2)                       -- a 2.0 s ranged swing
    local W = S.Width
    assertEquals(200, W)

    -- fraction 0: the bar is up, the fill has zero width.
    assertTrue(Swing:Update(clock[1]))
    assertTrue(Swing.anchor:IsShown())
    nearpx(Swing.fill:GetWidth(), 0)
    nearpx(Swing.fill:GetHeight(), S.Height)

    -- fraction 0.5: half the bar.
    clock[1] = 1001
    assertTrue(Swing:Update(clock[1]))
    nearpx(Swing.fill:GetWidth(), W * 0.5)

    -- fraction -> 1: the fill spans (nearly) the whole bar. Progress
    -- finalises the swing exactly at start + duration, so the last sample
    -- is the instant BEFORE completion.
    clock[1] = 1001.9999
    assertTrue(Swing:Update(clock[1]))
    nearpx(Swing.fill:GetWidth(), W * ((clock[1] - 1000) / 2.0))
    nearpx(Swing.fill:GetWidth(), W)
    Swing:SetShowSafeWindow(true)
end)

test("the remaining text prints tenths and rides the right edge", function()
    local clock = { 1000 }
    local t = fakeTracker(clock)
    Swing:SetTracker(t)
    t:OnSwingStart(2.0, 2)
    Swing:Update(clock[1])
    -- 2.0 s left -> "2.0"
    assertEquals("2.0", Swing.text:GetText())
    clock[1] = 1001
    Swing:Update(clock[1])
    assertEquals("1.0", Swing.text:GetText())
    clock[1] = 1001.5
    Swing:Update(clock[1])
    assertEquals("0.5", Swing.text:GetText())
    -- Right-aligned inside the bar.
    assertEquals("RIGHT", Swing.text:GetJustifyH())
    local point = Swing.text:GetPoint()
    assertEquals("RIGHT", point)
    -- The text formatter's own law (m:ss past a minute, tenths below).
    assertEquals("59.9", Swing.FormatRemaining(59.94))
    assertEquals("60.0", Swing.FormatRemaining(59.96))
    assertEquals("1:00", Swing.FormatRemaining(60))
    assertEquals("1:30", Swing.FormatRemaining(90.2))
end)

test("the bar hides after completion and the OnUpdate script is gone", function()
    local clock = { 1000 }
    local t = fakeTracker(clock)
    Swing:SetTracker(t)
    t:OnSwingStart(2.0, 2)
    assertTrue(Swing:Update(clock[1]))
    assertTrue(Swing.anchor:IsShown())
    clock[1] = 1002                                -- completes exactly here
    assertFalse(Swing:Update(clock[1]))
    assertFalse(Swing.anchor:IsShown())
    assertNil(Swing.anchor:GetScript("OnUpdate"))
    assertFalse(Swing:Update(clock[1]))            -- stays idle
    assertFalse(Swing.anchor:IsShown())
    -- A fresh swing brings it back (single-phase fill law).
    Swing:SetShowSafeWindow(false)
    t:OnSwingStart(2.0, 2)
    assertTrue(Swing:Update(clock[1]))
    assertTrue(Swing.anchor:IsShown())
    nearpx(Swing.fill:GetWidth(), 0)
    Swing:SetShowSafeWindow(true)
end)

test("the OnUpdate (10 Hz edge pass + per-frame motion) exists only while a swing runs", function()
    local t = FX.Hunter.NewSwingTracker({
        now = function() return GetTime() end,
        speedReader = function() return nil end,
        rangedType = 2,
    })
    Swing:SetTracker(t)
    Swing:RenderIdle()
    assertNil(Swing.anchor:GetScript("OnUpdate"))   -- idle: no script
    t:OnSwingStart(600, 2)                          -- a long, live swing
    Swing:Kick()
    assertNotNil(Swing.anchor:GetScript("OnUpdate"))
    Swing:RenderIdle()
    assertNil(Swing.anchor:GetScript("OnUpdate"))   -- idle: the script is unset
    -- A kick while the tracker is still mid-swing restarts the ticker: the
    -- self-heal path (an event arrived, the swing is live, the bar renders).
    Swing:Kick()
    assertNotNil(Swing.anchor:GetScript("OnUpdate"))
    Swing:RenderIdle()
    assertNil(Swing.anchor:GetScript("OnUpdate"))
    -- Once the tracker itself reports idle, a kick is a no-op.
    t:OnSwingStart(1.0, 2)
    assertNil(t:Progress(GetTime() + 5))            -- observes completion
    Swing:Kick()
    assertNil(Swing.anchor:GetScript("OnUpdate"))
end)

-- Manager regression, found live on uiforever 2026-11-02: a hidden frame never
-- receives OnUpdate, so a bar that waits for its own OnUpdate to Show() itself
-- never appears in a client. The kick path alone (no Update call here) must
-- leave the bar shown with the right fill.
test("a kick on a live swing shows the bar immediately (no OnUpdate needed)", function()
    -- Real clock, exactly like the production tracker (StartTicking renders at GetTime()).
    local t = FX.Hunter.NewSwingTracker({
        now = function() return GetTime() end,
        speedReader = function() return nil end,
        rangedType = 2,
    })
    Swing:SetTracker(t)
    Swing:RenderIdle()
    assertFalse(Swing.anchor:IsShown())
    t:OnSwingStart(600, 2)                            -- a long, live swing
    Swing:Kick()                                      -- the event path, nothing else
    assertTrue(Swing.anchor:IsShown(), "the kick must render the bar itself")
    assertTrue(Swing.fill:GetWidth() >= 0)
    -- Same cleanup as the ticker test: idle again, script gone, text cleared.
    t.active = false
    Swing:RenderIdle()
    assertNil(Swing.anchor:GetScript("OnUpdate"))
end)

test("ShowTime off drops the text; the fill keeps running", function()
    local clock = { 1000 }
    local t = fakeTracker(clock)
    Swing:SetTracker(t)
    Swing:SetShowTime(false)
    Swing:SetShowSafeWindow(false)               -- the single-phase fill law
    t:OnSwingStart(2.0, 2)
    assertTrue(Swing:Update(clock[1]))
    assertFalse(Swing.text:IsShown())
    assertEquals("", Swing.text:GetText())
    clock[1] = 1001
    assertTrue(Swing:Update(clock[1]))
    nearpx(Swing.fill:GetWidth(), S.Width * 0.5)
    Swing:SetShowTime(true)
    clock[1] = 1001.5
    assertTrue(Swing:Update(clock[1]))
    assertTrue(Swing.text:IsShown())
    assertEquals("0.5", Swing.text:GetText())
    Swing:SetShowSafeWindow(true)
end)

test("Enable off hides the bar mid-swing", function()
    local clock = { 1000 }
    local t = fakeTracker(clock)
    Swing:SetTracker(t)
    t:OnSwingStart(2.0, 2)
    assertTrue(Swing:Update(clock[1]))
    assertTrue(Swing.anchor:IsShown())
    Swing:SetEnabled(false)
    assertFalse(Swing.anchor:IsShown())
    assertFalse(Swing:Update(clock[1]))
    Swing:SetEnabled(true)
    assertTrue(Swing:Update(clock[1]))
    assertTrue(Swing.anchor:IsShown())
end)

test("the dragged position persists into FX.db.hunterSwing", function()
    Swing.anchor:ClearAllPoints()
    Swing.anchor:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 137, -58)
    Swing:SavePosition()
    local cfg = FX.db and FX.db.hunterSwing
    assertNotNil(cfg)
    assertEquals("TOPLEFT", cfg.point)
    assertEquals("TOPLEFT", cfg.relPoint)
    nearpx(cfg.x, 137)
    nearpx(cfg.y, -58)
    Swing:Reset()
    assertEquals("CENTER", cfg.point)
    nearpx(cfg.x, 0)
    nearpx(cfg.y, -175)
    Swing:ApplyPosition()
    local point = Swing.anchor:GetPoint()
    assertEquals("CENTER", point)
end)

-- ---------------------------------------------------------------- Reminder --

test("Init builds the 32x32 reminder, hidden while no aspect is missing", function()
    if not Reminder.anchor then Reminder:Init() end
    assertNotNil(Reminder.anchor)
    assertNotNil(ForteXorcistHunterReminderAnchor)
    assertEquals("ForteXorcistHunterReminderAnchor",
        ForteXorcistHunterReminderAnchor:GetName())
    assertEquals(32, Reminder.anchor:GetWidth())
    assertEquals(32, Reminder.anchor:GetHeight())
    Reminder:Init()   -- the idempotence leg: Init guards on self.anchor
    assertEquals(32, Reminder.anchor:GetWidth())
    -- Click-through chrome: the frame never takes mouse input.
    local f = Reminder.anchor
    if f.GetMouseEnabled then
        assertEquals(false, f:GetMouseEnabled())
    end
    if f.IsMouseEnabled then
        assertEquals(false, f:IsMouseEnabled())
    end
    Reminder:HideNow()
    assertFalse(Reminder.anchor:IsShown())
    assertNil(Reminder.anchor:GetScript("OnUpdate"))
end)

test("the reminder shows ONLY while Missing() (out of combat, none worn)", function()
    local inCombat = false
    local fake = FX.Hunter.NewAspectTracker({
        names = FX.Hunter.Tools.aspectNames,
        inCombat = function() return inCombat end,
    })
    local saved = Reminder.Aspects
    Reminder:SetAspects(fake)

    Reminder:Refresh(1000)                 -- out of combat, nothing worn
    assertTrue(Reminder.anchor:IsShown())
    assertNotNil(Reminder.anchor:GetScript("OnUpdate"))   -- pulse runs

    inCombat = true
    Reminder:Refresh(1000.1)               -- in combat: silent
    assertFalse(Reminder.anchor:IsShown())
    assertNil(Reminder.anchor:GetScript("OnUpdate"))

    inCombat = false
    fake:OnCast("Aspect of the Hawk")
    Reminder:Refresh(1000.2)               -- an aspect is worn: silent
    assertFalse(Reminder.anchor:IsShown())

    fake:Reconcile(function() return false end)   -- the buff dropped
    Reminder:Refresh(1000.3)
    assertTrue(Reminder.anchor:IsShown())

    Reminder:StopTicking()
    Reminder:SetAspects(saved)
end)

test("the icon rides the last-known aspect, else the generic first", function()
    local fresh = FX.Hunter.NewAspectTracker({
        names = FX.Hunter.Tools.aspectNames,
        inCombat = function() return false end,
    })
    local saved = Reminder.Aspects
    Reminder:SetAspects(fresh)
    Reminder._lastAspect = nil
    -- Never cast one: the generic first aspect of the derived list.
    assertEquals(FX.Hunter.Tools.aspectNames[1], Reminder:IconName())
    fresh:OnCast("Aspect of the Cheetah")
    assertEquals("Aspect of the Cheetah", Reminder:IconName())
    fresh:Reconcile(function() return false end)     -- cleared
    assertNil(fresh:Current())
    -- The last-known aspect survives the clear (the icon stays familiar).
    assertEquals("Aspect of the Cheetah", Reminder:IconName())
    Reminder:SetAspects(saved)
end)

test("the pulse breathes between PulseMin and PulseMax", function()
    local fake = FX.Hunter.NewAspectTracker({
        names = FX.Hunter.Tools.aspectNames,
        inCombat = function() return false end,
    })
    local saved = Reminder.Aspects
    Reminder:SetAspects(fake)
    Reminder:Refresh(1000)
    assertTrue(Reminder.anchor:IsShown())
    Reminder:StopTicking()               -- drive the pulse by hand
    Reminder._anchor0 = 1000
    local a0 = Reminder:UpdateAlpha(1000)
    near(a0, RS.PulseMin)
    near3(Reminder.anchor:GetAlpha(), RS.PulseMin)
    local a1 = Reminder:UpdateAlpha(1000 + RS.PulsePeriod * 0.5)
    near(a1, RS.PulseMax)
    near3(Reminder.anchor:GetAlpha(), RS.PulseMax)
    -- Mid-breath sits strictly between the endpoints.
    local a2 = Reminder:UpdateAlpha(1000 + RS.PulsePeriod * 0.25)
    assertTrue(a2 > RS.PulseMin and a2 < RS.PulseMax)
    Reminder:HideNow()
    assertFalse(Reminder.anchor:IsShown())
    Reminder:SetAspects(saved)
end)

-- ------------------------------------------- MT-14: the icon by spell id --
-- Code-review-10 m2 + section (c) item 14: the reminder's icon lookup -- the
-- ID first (the name lookups fail for spells the client does not list), the
-- NAME second -- had no test, and the m2 fix is exactly the shape a test must
-- pin: `ipairs({ id, name })` with `id == nil` stores nothing at index 1, the
-- loop body never runs, and the function's own docstring ("then by name")
-- becomes a lie. The C_Spell surface is installed per leg.

local function installCSpell(answers)
    local saved = _G.C_Spell
    local seen = {}
    _G.C_Spell = {
        GetSpellTexture = function(key)
            seen[#seen + 1] = key
            local a = answers[key]
            if a then return a end
            return nil
        end,
    }
    return seen, function() _G.C_Spell = saved end
end

test("MT-14: the icon lookup tries the SPELL ID first, the name only as the fallback",
function()
    if not Reminder.anchor then Reminder:Init() end
    local byName = FX.Data and FX.Data.HunterByName
    assertNotNil(byName, "the derived name->id map is loaded")
    local name = FX.Hunter.Tools.aspectNames[1]
    local id = byName[name]
    assertNotNil(id, "the first aspect resolves through the data")
    local seen, restore = installCSpell({ [id] = "Interface\\TESTIDPATH" })
    local saved = Reminder.Aspects
    local fresh = FX.Hunter.NewAspectTracker({
        names = FX.Hunter.Tools.aspectNames,
        inCombat = function() return false end,
    })
    fresh:OnCast(name)
    Reminder:SetAspects(fresh)
    Reminder._tex = nil
    Reminder:ApplyIcon()
    restore()
    Reminder:SetAspects(saved)
    assertEquals(id, seen[1],
        "the FIRST key consulted is the spell id (the id-first law)")
end)

test("m2: a name the data map lacks still reaches the NAME leg (the ipairs nil-hole witness)",
function()
    if not Reminder.anchor then Reminder:Init() end
    local byName = FX.Data and FX.Data.HunterByName
    local name = "Aspect of the Testwing"     -- not in the derived map
    assertNil(byName[name], "the fixture is a name the data map lacks")
    -- The review's scenario is "the moment a tracker carries a name the
    -- data file lacks": the tracker adopts casts of its OWN roster names,
    -- so the roster carries the name the derived HunterByName map does not.
    local roster = { name }
    local family = FX.Hunter.Tools.aspectNames
    for i = 1, #family do roster[#roster + 1] = family[i] end
    local seen, restore = installCSpell({ [name] = "Interface\\TESTNAMEPATH" })
    local saved, savedTex = Reminder.Aspects, Reminder._tex
    local fresh = FX.Hunter.NewAspectTracker({
        names = roster,
        inCombat = function() return false end,
    })
    fresh:OnCast(name)
    assertTrue(fresh:Current() == name, "the tracker adopted the roster name")
    Reminder:SetAspects(fresh)
    Reminder._tex = nil
    Reminder:ApplyIcon()
    restore()
    Reminder:SetAspects(saved)
    Reminder._tex = savedTex
    assertEquals(1, #seen,
        "the id leg is skipped (no id) and the NAME leg RUNS -- the old"
        .. " `ipairs({ id, name })` with id == nil ran neither")
    assertEquals(name, seen[1], "and it consulted the name itself")
end)

test("MT-14: an icon neither path answers is the question mark, and the cache stays un-stamped",
function()
    if not Reminder.anchor then Reminder:Init() end
    local seen, restore = installCSpell({})   -- every lookup answers nil
    local saved, savedTex = Reminder.Aspects, Reminder._tex
    local fresh = FX.Hunter.NewAspectTracker({
        names = FX.Hunter.Tools.aspectNames,
        inCombat = function() return false end,
    })
    fresh:OnCast(FX.Hunter.Tools.aspectNames[1])
    Reminder:SetAspects(fresh)
    Reminder._tex = nil
    Reminder:ApplyIcon()
    local tex = Reminder.icon:GetTexture()
    local stamped = Reminder._tex
    restore()
    Reminder:SetAspects(saved)
    Reminder._tex = savedTex
    -- The cache stays un-stamped: a not-yet-ready spell DB is retried.
    assertNil(stamped,
        "a failed lookup must not stamp the name into the texture cache")
    -- Representation-independent art identity: the sim's GetTexture answers
    -- its own texture-registry NUMBER for the path, the real client echoes
    -- the string, so compare against a scratch texture set to the very art
    -- UNKNOWN_ICON names (equal by id in the sim, equal as the same string
    -- on the client -- the one comparison true on both).
    local probeTex = Reminder.anchor:CreateTexture()
    probeTex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    assertEquals(tostring(probeTex:GetTexture()), tostring(tex),
        "the honest 'icon unknown' is the question-mark art: "
        .. tostring(tex) .. " vs " .. tostring(probeTex:GetTexture()))
end)

test("MT-14: IconName's fallback is the first aspect THIS character knows",
function()
    if not Reminder.anchor then Reminder:Init() end
    local names = FX.Hunter.Tools.aspectNames
    local byName = FX.Data.HunterByName
    -- The sim profile is not a Hunter: IsPlayerSpell answers false for the
    -- whole aspect family, so the known-loop falls through to the generic
    -- first entry. Install a seam that knows exactly ONE aspect (the second
    -- of the list) and the loop must answer it -- the "Beast is not in every
    -- spellbook" law of the setter's own comment.
    local target = names[2]
    local targetId = byName[target]
    assertNotNil(targetId)
    local savedCompat = FX.Compat.IsPlayerSpell
    local savedAspects, savedLast = Reminder.Aspects, Reminder._lastAspect
    FX.Compat.IsPlayerSpell = function(id) return id == targetId end
    local fresh = FX.Hunter.NewAspectTracker({
        names = names,
        inCombat = function() return false end,
    })
    Reminder:SetAspects(fresh)
    Reminder._lastAspect = nil
    assertEquals(target, Reminder:IconName(),
        "nothing cast, nothing remembered: the first KNOWN aspect of the list")
    FX.Compat.IsPlayerSpell = savedCompat
    Reminder:SetAspects(savedAspects)
    Reminder._lastAspect = savedLast
end)

-- ================================================= the F2 migration fold ==
-- docs/reviews/code-review-8.md F2 (MAJOR): the retired `ShowSafeWindow`
-- key and `BarMode` drive ONE state through two setters, and the login
-- pass carries BOTH (Get answers an absent key with its registered
-- default), so `for key, value in pairs(tbl)` — a hash walk, not the
-- stored order — decided which one won. The fold: the legacy key is the
-- mode's word ONLY when the raw profile carries no BarMode of its own, and
-- after the fold has spoken the legacy key retires (the v2 prune cannot
-- reach a key with no registered default). Every leg drives the REAL login
-- path (`ApplyStoredSettings` -> `Get` -> `ApplySettings`); the raw profile
-- is reached through the store seam the settings tests use.
test("the ShowSafeWindow -> BarMode migration is a fold, not a pairs roll",
function()
    local ST = FX.Settings
    local raw = ST._store and ST._store("Hunter")
    assertTrue(type(raw) == "table", "the raw profile seam exists")
    local function wipe()
        for k in pairs(raw) do raw[k] = nil end
    end

    -- (a) The pre-slice-A profile: the legacy key is the profile's ONLY
    -- word. `off` is the `elapsed` mode, and the fold STORES that word and
    -- retires the legacy key, so the next login reads one word.
    wipe()
    raw.ShowSafeWindow = false
    Swing:ApplyStoredSettings()
    assertEquals("elapsed", Swing.state.barMode)
    assertEquals(false, Swing.state.showSafeWindow)
    assertNil(raw.ShowSafeWindow, "the legacy key retires on the fold")
    assertEquals("elapsed", raw.BarMode, "the folded word is stored")
    -- Idempotent: a second login on the folded profile says the same.
    Swing:ApplyStoredSettings()
    assertEquals("elapsed", Swing.state.barMode)

    -- (b) The profile that chose a mode AND still carries the legacy key
    -- (the review's exact scenario: off during Iteration I, One bar later).
    -- The chosen mode wins whatever the legacy word says, in BOTH insertion
    -- orders of the two keys.
    for order = 1, 2 do
        wipe()
        if order == 1 then
            raw.ShowSafeWindow = false
            raw.BarMode = "one"
        else
            raw.BarMode = "one"
            raw.ShowSafeWindow = false
        end
        Swing:ApplyStoredSettings()
        assertEquals("one", Swing.state.barMode,
            "order " .. order .. ": the chosen BarMode is the last word")
        assertTrue(Swing.state.showSafeWindow,
            "order " .. order .. ": the safe flag rides the mode")
        assertNil(raw.ShowSafeWindow, "order " .. order .. ": retired")
    end

    -- (c) The direct seam: a lone legacy word still means the mode (the
    -- live page row, the profile-switch fan-out), and a table carrying both
    -- reads the mode key in both insertion orders.
    Swing:ApplySettings({ ShowSafeWindow = true })
    assertEquals("safe", Swing.state.barMode)
    Swing:ApplySettings({ ShowSafeWindow = false })
    assertEquals("elapsed", Swing.state.barMode)
    Swing:ApplySettings({ BarMode = "one", ShowSafeWindow = true })
    assertEquals("one", Swing.state.barMode)
    Swing:ApplySettings({ ShowSafeWindow = true, BarMode = "one" })
    assertEquals("one", Swing.state.barMode)
    -- (d) K9 M1 (docs/reviews/code-review-9.md MAJOR 1): the profile
    -- with NEITHER word -- the fresh Hunter profile of a fresh install.
    -- The word reader used to answer `false` for an ABSENT legacy key
    -- (`(legacy == true or legacy == false) and legacy` is `(false) and
    -- nil` = false), the consumer gate is `legacy ~= nil`, and the
    -- wordless profile folded to `elapsed` AND GOT STAMPED -- the shipped
    -- Safe-window default never showed. No word: the registered default
    -- rides and the raw profile is NOT stamped. (The legs (a) and (b)
    -- pin the stamped halves: legacy false alone -> `elapsed` stamped,
    -- a stored BarMode over a legacy key -> the BarMode wins and the
    -- legacy key retires.)
    wipe()
    Swing:ApplyStoredSettings()
    assertEquals("safe", Swing.state.barMode,
        "a wordless profile boots in the shipped safe mode")
    assertTrue(Swing.state.showSafeWindow, "the safe flag rides the mode")
    assertNil(raw.BarMode, "no word is stamped into a fresh profile")
    assertNil(raw.ShowSafeWindow, "the retired key is not written back")
    -- (e) The legacy key ALONE, the `true` half: the mode is `safe`, the
    -- folded word is stamped and the key retires (leg (a) is the `false`
    -- half). A second login on the folded profile says the same.
    wipe()
    raw.ShowSafeWindow = true
    Swing:ApplyStoredSettings()
    assertEquals("safe", Swing.state.barMode, "legacy true is the safe mode")
    assertEquals("safe", raw.BarMode, "the legacy true stamps safe")
    assertNil(raw.ShowSafeWindow, "the legacy key retires on the fold")
    Swing:ApplyStoredSettings()
    assertEquals("safe", Swing.state.barMode)
    wipe()
    Swing:SetShowSafeWindow(true)
    Swing:SetBarMode("safe")
    assertEquals("safe", Swing.state.barMode)
end)

-- ----------------------------------------------------------- live settings --

test("Hunter settings drive the frames live", function()
    assertNotNil(ST)
    assertTrue(ST:IsRegistered("Hunter"))
    local w0 = Swing.anchor:GetWidth()
    ST:Set("Hunter", "Width", 320)
    assertEquals(320, Swing.anchor:GetWidth())
    ST:Set("Hunter", "Width", w0)
    assertEquals(w0, Swing.anchor:GetWidth())

    local h0 = Swing.anchor:GetHeight()
    ST:Set("Hunter", "Height", 20)
    assertEquals(20, Swing.anchor:GetHeight())
    ST:Set("Hunter", "Height", h0)
    assertEquals(h0, Swing.anchor:GetHeight())

    ST:Set("Hunter", "BarColor", { 1, 0, 0, 1 })
    local r, g, b = Swing.fill:GetVertexColor()
    near3(r, 1); near3(g, 0); near3(b, 0)
    -- Back to the registered default through the store (Reset writes the
    -- default THROUGH Set, so the bar self-heals the same way a recycle does).
    ST:Reset("Hunter", "BarColor")
    local d = FX.Hunter.SwingSkin.BarColor
    local r2, g2, b2 = Swing.fill:GetVertexColor()
    near3(r2, d[1]); near3(g2, d[2]); near3(b2, d[3])

    -- Enable off hides the bar live, on shows it on the next swing.
    local eclock = { 3000 }
    local et = fakeTracker(eclock)
    Swing:SetTracker(et)
    et:OnSwingStart(2.0, 2)
    assertTrue(Swing:Update(eclock[1]))
    assertTrue(Swing.anchor:IsShown())
    ST:Set("Hunter", "Enable", false)
    assertFalse(Swing.anchor:IsShown())
    assertFalse(Swing:Update(eclock[1]))
    assertNil(Swing.anchor:GetScript("OnUpdate"))
    ST:Set("Hunter", "Enable", true)
    assertTrue(Swing:Update(eclock[1]))
    assertTrue(Swing.anchor:IsShown())
    Swing:RenderIdle()

    -- The reminder's own keys.
    ST:Set("Hunter", "ReminderSize", 48)
    assertEquals(48, Reminder.anchor:GetWidth())
    assertEquals(48, Reminder.anchor:GetHeight())
    ST:Set("Hunter", "ReminderSize", 32)
    assertEquals(32, Reminder.anchor:GetWidth())
    ST:Set("Hunter", "ReminderColor", { 0, 1, 0, 1 })
    local ir, ig, ib = Reminder.icon:GetVertexColor()
    near3(ir, 0); near3(ig, 1); near3(ib, 0)
    ST:Set("Hunter", "ReminderColor", { 1, 1, 1, 1 })

    ST:Set("Hunter", "ShowTime", false)
    -- A live swing to drive the bar with the text option off.
    local clock = { 2000 }
    local t = fakeTracker(clock)
    Swing:SetTracker(t)
    t:OnSwingStart(2.0, 2)
    assertTrue(Swing:Update(clock[1]))
    assertTrue(Swing.anchor:IsShown())
    assertFalse(Swing.text:IsShown())
    ST:Set("Hunter", "ShowTime", true)
    clock[1] = 2001
    assertTrue(Swing:Update(clock[1]))
    assertTrue(Swing.text:IsShown())
    assertEquals("1.0", Swing.text:GetText())
    Swing:RenderIdle()

    ST:Set("Hunter", "EnableReminder", false)
    Reminder:Refresh()
    assertFalse(Reminder.anchor:IsShown())
    ST:Set("Hunter", "EnableReminder", true)
end)

test("the fill's default colour is the Cooldown Spell category, full alpha",
function()
    -- Polish pass 2026-11-02 defect 3: the 1,1,1 a 0.20 fill over the
    -- Aluminium texture was all but invisible. The default is now the
    -- Forte_Cooldown timeline's Spell category colour at FULL alpha.
    local sc = FX.Cooldown and FX.Cooldown.TimelineSkin
        and FX.Cooldown.TimelineSkin.Colors and FX.Cooldown.TimelineSkin.Colors.Spell
    assertNotNil(sc)
    local d = ST:GetDefault("Hunter", "BarColor")
    assertNotNil(d)
    near3(d[1], sc[1]); near3(d[2], sc[2]); near3(d[3], sc[3])
    near3(d[4], 1)                                   -- full alpha
    -- The module skin and the store default are ONE truth (the page reads
    -- the skin), and the live fill rides them.
    near3(FX.Hunter.SwingSkin.BarColor[2], sc[2])
    local r, g, b, a = Swing.fill:GetVertexColor()
    near3(r, sc[1]); near3(g, sc[2]); near3(b, sc[3]); near3(a, 1)
    -- The BACKGROUND default is untouched: the Classic black a 0.50.
    near3(ST:GetDefault("Hunter", "BgColor")[4], 0.50)
    print(string.format("[swing] fill=%.2f,%.2f,%.2f a=%.2f bgA=%.2f",
        r, g, b, a, ST:GetDefault("Hunter", "BgColor")[4]))
end)

test("the General BarFont drives the swing text live", function()
    local shipped = "Interface\\AddOns\\Forte_Core\\Fonts\\URWGothic-Book.ttf"
    assertNotNil(Swing.text)
    -- The options file is the vendored one the General page registers, and
    -- login applied it through this very seam (ApplyStoredSettings). The sim
    -- echoes the path from GetFont so this reads it back; the live client
    -- answers false/nil until the file has rendered once -- PLAN §11.12: the
    -- old law "GetFont must echo the path" was the bug (test_font_law.lua
    -- pins the pending case).
    assertEquals(shipped, ST:Get("General", "BarFont"))
    assertTrue(Swing.text:GetFont():lower() == shipped:lower())
    -- General -> Swing:SetFont -> validateFontFile (a raise rejects, nothing
    -- else) + applyFont (in the sim no path raises, so what this proves is
    -- the live re-apply of the bar's own fontstring).
    ST:Set("General", "BarFont", "Interface\\AddOns\\Forte_Core\\Fonts\\NOPE.ttf")
    assertTrue(Swing.text:GetFont():lower()
        == "interface\\addons\\forte_core\\fonts\\nope.ttf")
    ST:Reset("General", "BarFont")
    assertTrue(Swing.text:GetFont():lower() == shipped:lower())
    print("[swing] text font=" .. Swing.text:GetFont())
end)

test("Lock: the bar publishes Hunter.Lock; GlobalLock and the Cooldown bar move it", function()
    Swing:SetLocked(true)
    assertEquals(true, ST:Get("Hunter", "Lock"))
    -- Unlocked: the frame is movable (drag possible).
    ST:Set("Hunter", "Lock", false)
    assertFalse(Swing.cfg.locked)
    -- The General page's Global Frame Lock (=/fx lock|unlock) drives ours.
    ST:Set("General", "GlobalLock", false)
    assertFalse(Swing.cfg.locked)
    ST:Set("General", "GlobalLock", true)
    assertTrue(Swing.cfg.locked)
    assertEquals(true, ST:Get("Hunter", "Lock"))
    -- Forte_Cooldown's published lock state (its SetLocked publish is the
    -- lock-change hook, m4) is mirrored into the Hunter bar.
    local d = FX.Cooldown and FX.Cooldown.Display
    if d and d.SetLocked then
        d:SetLocked(false)
        assertFalse(Swing.cfg.locked)
        d:SetLocked(true)
        assertTrue(Swing.cfg.locked)
        assertTrue(Swing.anchor)
    end
    Swing:SetLocked(true)
end)

-- ----------------------------------------------------------------- gating --

test("the UI module follows the class (events, frames, page)", function()
    local savedClass = FX._playerClass
    -- To HUNTER first: the frame the disable path asserts on must exist.
    UI:OnClassChanged("HUNTER")
    assertNotNil(UI._eventFrame)
    assertNotNil(UI._eventFrame:GetScript("OnEvent"))
    assertNotNil(Swing.anchor)
    assertNotNil(Reminder.anchor)

    UI:OnClassChanged("WARLOCK")
    assertNil(UI._eventFrame:GetScript("OnEvent"))
    assertFalse(Swing.anchor:IsShown())
    assertFalse(Reminder.anchor:IsShown())
    assertNil(Swing.anchor:GetScript("OnUpdate"))
    assertNil(Reminder.anchor:GetScript("OnUpdate"))

    UI:OnClassChanged("HUNTER")
    assertNotNil(UI._eventFrame:GetScript("OnEvent"))
    -- The page registration: the page file's load-time fast path when
    -- Forte_Options loaded first, this call path when it did not.
    if FX.Options and FX.Options.pages then
        assertNotNil(FX.Options.pages["Hunter"])
        assertEquals("Hunter", FX.Options.pages["Hunter"].id)
        assertEquals("Hunter", FX.Options.pages["Hunter"].module)
    end
    UI:OnClassChanged(savedClass)
    assertNil(UI._eventFrame:GetScript("OnEvent"))
    assertEquals(savedClass, FX._playerClass)
end)

test("the Hunter page builds in the options window", function()
    if not (FX.Options and FX.Options.pages and FX.Options.pages["Hunter"]) then
        print("[page] Forte_Options has no Hunter page -- skipped")
        return
    end
    FX.Options:Open("Hunter")
    assertEquals(true, FX.Options:IsOpen())
    assertEquals("Hunter", FX.Options.pageId)
    local page = FX.Options.pagesBuilt["Hunter"]
    assertNotNil(page)
    -- Tips + Basics + Shot Cycle + Frame Sizing + Coloring + Range Light
    -- + Combat Alpha (swing v2 added Shot Cycle, Range Light, Combat Alpha).
    assertEquals(7, #page.sections)
    local counts = {}
    for i, sec in ipairs(page.sections) do counts[i] = #sec.widgets end
    assertEquals(0, counts[1])      -- Some Tips is text lines
    assertEquals(4, counts[2])      -- Enable, Lock, ShowTime, EnableReminder
    assertEquals(10, counts[3])     -- BarMode + the four slice-γ rows + the
                                    -- four v2 Show* keys + BaseSpeed
                                    -- (ShowSafeWindow's CHK rode here)
    assertEquals(3, counts[4])      -- Width, Height, ReminderSize
    assertEquals(4, counts[5])      -- SwingPalette (K4B), BarColor, BgColor,
                                    -- ReminderColor
    assertEquals(1, counts[6])      -- ShowRangeLight
    assertEquals(2, counts[7])      -- InCombatAlpha, OutOfCombatAlpha
    assertEquals(7, #page.sections[1].lines)
    assertNotNil(FX.Options.header)
    assertNotNil(FX.Options.header.bar)
    FX.Options:Close()
    assertEquals(false, FX.Options:IsOpen())
end)

-- The page's tips are the shipped defaults' only prose, and two of them
-- used to describe code that is not the code (code-review-5 m4, m5): the
-- Combat Alpha row stated the WeaponSwingTimer in-combat-only law against a
-- shipped default of 1.0 (UI/Swing.lua's skin comment: "parked VISIBLE"), and
-- the Latency row was pushed toward "Live" against a control whose state
-- field no render pass reads. A tip that contradicts its own key is a defect
-- the owner files as "the option does nothing", so the two rows are pinned
-- to the code they describe -- the same pin on every future tip edit.
test("the Hunter page's tips tell the truth about their keys", function()
    if not (FX.Options and FX.Options.pages and FX.Options.pages["Hunter"]) then
        print("[page] Forte_Options has no Hunter page -- skipped")
        return
    end
    FX.Options:Open("Hunter")
    local page = FX.Options.pagesBuilt["Hunter"]
    assertNotNil(page, "the page builds")
    local tips, labels = {}, {}
    for _, sec in ipairs(page.sections) do
        for _, w in ipairs(sec.widgets) do
            local spec = w.spec
            if spec and spec.key then
                tips[spec.key] = spec.tip or ""
                labels[spec.key] = spec.label or ""
            end
        end
    end
    FX.Options:Close()

    -- m4: the alpha pair's default IS visible (the store's default and the
    -- skin agree -- the alpha law of UI/Swing.lua's pair), so the tip has to
    -- say the shipped number and never the WST law the module does not ship.
    assertEquals(1.0, FX.Settings:GetDefault("Hunter", "OutOfCombatAlpha"))
    local ooc = tips["OutOfCombatAlpha"]
    assertNotNil(ooc, "the OutOfCombatAlpha row is on the page")
    assertContains(ooc, "1.0")
    assertContains(ooc, "VISIBLE")
    local inCombat = tips["InCombatAlpha"]
    assertContains(inCombat, "1.0")

    -- m5: the latency strip has no render consumer -- the state field its
    -- setter writes is read by nobody in the bar (UI/Swing.lua), which is the
    -- Gap-12 launch-probe law, not a live feature. The tip says "inert", the
    -- label says "needs launch probe", and NEITHER may claim "Live" while no
    -- render path reads it.
    local lat = tips["ShowLatency"]
    assertNotNil(lat, "the ShowLatency row is on the page")
    assertContains(lat, "inert")
    assertContains(labels["ShowLatency"], "launch probe")
    local function claimsLive(text)
        return text:find("Live", 1, true) ~= nil
    end
    assertFalse(claimsLive(lat), "the latency tip claims a live strip")
    assertFalse(claimsLive(labels["ShowLatency"]),
        "the latency label claims a live strip")
    -- And the claim the sibling rows DO make: the alpha pair is applied at
    -- the frame (UI/Swing.lua's _ApplyCombatAlpha leg).
    assertContains(inCombat, "Live")
end)

-- Iteration J slice γ (docs/research/wst-swing-design.md §7.8 γ): the Shot
-- Cycle section's rows. The mode picker carries §7.1's labels verbatim, the
-- four new rows are §7.3/§7.4/§7.5, ShowSafeWindow is GONE from the page and
-- from the registration, and every tip names the rotation question its signal
-- answers in plain words — the honesty law above, extended to the new rows.
test("the Shot Cycle rows are §7.1's picker, the §7.3/§7.4/§7.5 rows, and no ShowSafeWindow",
function()
    if not (FX.Options and FX.Options.pages and FX.Options.pages["Hunter"]) then
        print("[page] Forte_Options has no Hunter page -- skipped")
        return
    end
    FX.Options:Open("Hunter")
    local page = FX.Options.pagesBuilt["Hunter"]
    assertNotNil(page, "the page builds")
    local shot
    for _, sec in ipairs(page.sections) do
        if sec.title == "Shot Cycle" then shot = sec end
    end
    assertNotNil(shot, "the Shot Cycle section exists")
    local rows = {}
    for _, w in ipairs(shot.widgets) do
        assertNotNil(w.spec.key, "every Shot Cycle row is bound to a key")
        rows[w.spec.key] = w.spec
    end
    FX.Options:Close()

    -- §7.1: the key retires in the same cutover — no row, no default. Its
    -- pixels are the picker's `elapsed` item; the migration seam is asserted
    -- in the round-trip test below.
    assertNil(rows["ShowSafeWindow"], "the retired key has no row")
    assertNil(FX.Settings:GetDefault("Hunter", "ShowSafeWindow"),
        "the retired key has no registered default")

    -- The mode picker: §7.1's three items, values and labels verbatim.
    local mode = rows["BarMode"]
    assertNotNil(mode, "the BarMode row is on the page")
    assertEquals("Bar mode", mode.label)
    assertEquals(3, #(mode.items or {}))
    assertEquals("safe", mode.items[1].value)
    assertEquals("Safe window (shrinks toward the aim end)",
        mode.items[1].label)
    assertEquals("one", mode.items[2].value)
    assertEquals("One bar (fills toward the aim end)", mode.items[2].label)
    assertEquals("elapsed", mode.items[3].value)
    assertEquals("Single fill (cycle elapsed)", mode.items[3].label)

    -- The four rows, labels verbatim (§7.3 / §7.4 / §7.4 / §7.5).
    local function label(key)
        local spec = rows[key]
        assertNotNil(spec, "the " .. key .. " row is on the page")
        return spec.label
    end
    assertEquals("Aim window (right end, standing)", label("ShowAimWindow"))
    assertEquals("Clip region (a cast started here clips the shot)",
        label("ShowClipRegion"))
    assertEquals(
        "Melee-weave line (room for a 1.5 s GCD before the shot)",
        label("ShowWeaveLine"))
    assertEquals("Enable melee swing rail", label("EnableMeleeRail"))

    -- Every new tip names the rotation question it answers (the §7.0
    -- ranking): which way to read the fill (P2/P3), when to stand still
    -- (P2), can I cast without clipping (P1), is there room for a 1.5 s
    -- GCD (P4), is the main-hand swing up (P5).
    local function tip(key)
        local spec = rows[key]
        assertNotNil(spec, "the " .. key .. " row is on the page")
        return spec.tip or ""
    end
    assertContains(tip("BarMode"), "Safe window")
    assertContains(tip("BarMode"), "One bar")
    assertContains(tip("BarMode"), "Single fill")
    assertContains(tip("BarMode"), "Auto Shot")
    assertContains(tip("ShowAimWindow"), "When must I stop moving")
    assertContains(tip("ShowAimWindow"), "stand still")
    assertContains(tip("ShowClipRegion"), "Can I cast without clipping")
    assertContains(tip("ShowClipRegion"), "Start Aimed Shot")
    assertContains(tip("ShowClipRegion"), "delays your next Auto Shot")
    assertContains(tip("ShowWeaveLine"), "Is there room to weave")
    assertContains(tip("ShowWeaveLine"), "1.5 s global cooldown")
    assertContains(tip("EnableMeleeRail"), "main-hand swing")
    assertContains(tip("EnableMeleeRail"), "melee range")
    assertContains(tip("EnableMeleeRail"), "Raptor Strike")
    -- The honesty law, extended: each of the five rows rides a real live
    -- seam (UI/Swing.lua's KEYMAP for the four bar keys, FX.Hunter.Melee's
    -- self-wired ApplySettings for the rail), so each says "Live" — and
    -- none of them is the inert latency row, whose tip stays the one the
    -- test above pins.
    for _, key in ipairs({ "BarMode", "ShowAimWindow", "ShowClipRegion",
        "ShowWeaveLine", "EnableMeleeRail" }) do
        assertContains(tip(key), "Live", key .. " rides a live seam")
    end
end)

-- The section-recycle law: the Shot Cycle keys list IS the set of its rows
-- (Window.lua's onResetAll iterates it). Moving every row off its default
-- and clicking the section recycle lands every one of them back — on the
-- store AND on the live objects (the KEYMAP seam, not just the file).
test("the Shot Cycle keys list is the set: the section recycle lands every row on its default",
function()
    if not (FX.Options and FX.Options.pages and FX.Options.pages["Hunter"]) then
        print("[page] Forte_Options has no Hunter page -- skipped")
        return
    end
    FX.Options:Open("Hunter")
    local page = FX.Options.pagesBuilt["Hunter"]
    local shot
    for _, sec in ipairs(page.sections) do
        if sec.title == "Shot Cycle" then shot = sec end
    end
    assertNotNil(shot)
    local rec = shot.bar.recycle
    assertNotNil(rec, "the section carries its recycle")

    ST:Set("Hunter", "BarMode", "one")
    ST:Set("Hunter", "ShowAimWindow", false)
    ST:Set("Hunter", "ShowClipRegion", false)
    ST:Set("Hunter", "ShowWeaveLine", true)
    ST:Set("Hunter", "EnableMeleeRail", true)
    ST:Set("Hunter", "ShowAimSlice", false)
    ST:Set("Hunter", "ShowFlying", false)
    ST:Set("Hunter", "ShowRetry", false)
    ST:Set("Hunter", "ShowLatency", true)
    ST:Set("Hunter", "BaseSpeed", 3)
    rec:GetScript("OnClick")(rec)
    FX.Options:Close()

    assertEquals("safe", ST:Get("Hunter", "BarMode"))
    assertEquals(true, ST:Get("Hunter", "ShowAimWindow"))
    assertEquals(true, ST:Get("Hunter", "ShowClipRegion"))
    assertEquals(false, ST:Get("Hunter", "ShowWeaveLine"))
    assertEquals(false, ST:Get("Hunter", "EnableMeleeRail"))
    assertEquals(true, ST:Get("Hunter", "ShowAimSlice"))
    assertEquals(true, ST:Get("Hunter", "ShowFlying"))
    assertEquals(true, ST:Get("Hunter", "ShowRetry"))
    assertEquals(false, ST:Get("Hunter", "ShowLatency"))
    assertEquals(0, ST:Get("Hunter", "BaseSpeed"))
    -- The live objects followed the recycle, not just the store.
    assertEquals("safe", Swing.state.barMode)
    assertTrue(Swing.state.showAimWindow)
    assertTrue(Swing.state.showClipRegion)
    assertFalse(Swing.state.showWeaveLine)
    assertFalse(FX.Hunter.Melee.state.enabled)
    FX.Hunter.Melee:HideNow()
    Swing:RenderIdle()
end)

-- γ.1 + γ.3: the registered posture lives in the ONE registration; every new
-- key round-trips Set -> Get -> the live object; and the retired
-- ShowSafeWindow key migrates through UI/Swing.lua's SetShowSafeWindow seam
-- — a stored false reads back as the elapsed mode, true as safe.
test("the mode/marker/rail keys round-trip to the live objects; a stored ShowSafeWindow=false reads back as BarMode=elapsed",
function()
    assertNotNil(ST)
    assertEquals("safe", ST:GetDefault("Hunter", "BarMode"))
    assertEquals(true, ST:GetDefault("Hunter", "ShowAimWindow"))
    assertEquals(true, ST:GetDefault("Hunter", "ShowClipRegion"))
    assertEquals(false, ST:GetDefault("Hunter", "ShowWeaveLine"))
    assertEquals(false, ST:GetDefault("Hunter", "EnableMeleeRail"))
    assertNil(ST:GetDefault("Hunter", "ShowSafeWindow"))

    local Melee = FX.Hunter.Melee
    assertNotNil(Melee)
    Melee:EnableForClass()                          -- seed + wire, idempotent
    Melee.combatReader = function() return false end -- the sim is not in combat

    -- The mode picker rides the store to the bar.
    ST:Set("Hunter", "BarMode", "one")
    assertEquals("one", ST:Get("Hunter", "BarMode"))
    assertEquals("one", Swing.state.barMode)
    ST:Set("Hunter", "BarMode", "elapsed")
    assertEquals("elapsed", Swing.state.barMode)
    ST:Reset("Hunter", "BarMode")
    assertEquals("safe", ST:Get("Hunter", "BarMode"))
    assertEquals("safe", Swing.state.barMode)

    -- The three bar markers ride the same seam.
    ST:Set("Hunter", "ShowAimWindow", false)
    assertEquals(false, ST:Get("Hunter", "ShowAimWindow"))
    assertEquals(false, Swing.state.showAimWindow)
    ST:Reset("Hunter", "ShowAimWindow")
    assertTrue(Swing.state.showAimWindow)
    ST:Set("Hunter", "ShowClipRegion", false)
    assertEquals(false, Swing.state.showClipRegion)
    ST:Reset("Hunter", "ShowClipRegion")
    assertTrue(Swing.state.showClipRegion)
    ST:Set("Hunter", "ShowWeaveLine", true)
    assertEquals(true, ST:Get("Hunter", "ShowWeaveLine"))
    assertEquals(true, Swing.state.showWeaveLine)
    ST:Reset("Hunter", "ShowWeaveLine")
    assertFalse(Swing.state.showWeaveLine)

    -- The rail rides FX.Hunter.Melee's own self-wiring (slice β): on builds
    -- the frame, off hides it with no ticker (the off law), and outside the
    -- combat/melee gate it never shows.
    ST:Set("Hunter", "EnableMeleeRail", true)
    assertEquals(true, ST:Get("Hunter", "EnableMeleeRail"))
    assertEquals(true, Melee.state.enabled)
    assertNotNil(Melee.anchor, "enabling the rail builds the frame")
    assertFalse(Melee:Refresh(), "out of the gate the rail stays hidden")
    ST:Reset("Hunter", "EnableMeleeRail")
    assertEquals(false, Melee.state.enabled)
    assertFalse(Melee._shown)
    assertNil(Melee.anchor:GetScript("OnUpdate"))

    -- The migration (§7.1): the key is retired from the registration, so a
    -- stored value reaches the bar through KEYMAP's SetShowSafeWindow seam
    -- — a stored false IS the elapsed mode, true is safe, and the mode
    -- reads back on the live bar.
    ST:Set("Hunter", "ShowSafeWindow", false)
    assertEquals(false, ST:Get("Hunter", "ShowSafeWindow"))
    assertEquals("elapsed", Swing.state.barMode)
    ST:Set("Hunter", "ShowSafeWindow", true)
    assertEquals("safe", Swing.state.barMode)
    -- The key retires cleanly: drop the stored probe from the profile
    -- (the store seam, read-only elsewhere; the mode is already restored).
    assertNotNil(ST._store)
    ST._store("Hunter").ShowSafeWindow = nil

    Melee.combatReader = nil
    Melee:HideNow()
    Swing:RenderIdle()
end)

test("Status prints the swing bar, the reminder and the range light", function()
    local lines = {}
    local realPrint = FX.Print
    FX.Print = function(msg) lines[#lines + 1] = tostring(msg) end
    UI:Status()
    FX.Print = realPrint
    -- swing v2: the range light adds its line once its frame is built (the
    -- class-gate test above builds it through UI:OnClassChanged).
    assertTrue(#lines >= 2)
    assertContains(lines[1], "Swing bar")
    assertContains(lines[2], "Aspect reminder")
    local hasRange = false
    for _, l in ipairs(lines) do
        if l:find("Range light") then hasRange = true end
    end
    assertTrue(hasRange)
    assertContains(Swing:StatusLine(), "locked")
    assertContains(Reminder:StatusLine(), "icon=")
    -- Restore the shared state the geometry tests drove.
    Swing:SetTracker(FX.Hunter.Tools.Swing)
    Reminder:SetAspects(FX.Hunter.Tools.Aspects)
    Swing:RenderIdle()
    Reminder:HideNow()
    Swing:SetLocked(true)
end)

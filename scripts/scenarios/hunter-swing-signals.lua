-- scene: the Hunter swing bar in its DEFAULT Safe window mode driven by the
-- `/fx test` swing demo (Core/SwingDemo.lua), with the weave line switched
-- ON for the clip. Synthetic Auto Shot cycles (the demo's own 2.8 s cycle)
-- carry every shipped signal on the shipped art: the orange reload fill, the
-- dim clip band at the LEFT end (the fake Aimed Shot's 2.0 s length in `safe`
-- mode), the standing aim zone at the right end, the live red aim slice
-- inside it, the cyan weave line (1 px, GCD budget from the left), the
-- full-width red cast interlock while the cast runs, and the whole-bar white
-- flight after the shot leaves.
--
-- HOW IT RUNS. The mode is started the way `/fx test` does: the slash verb
-- calls FX.TestMode:Toggle, Toggle calls Start, Start's pump asks the
-- HunterSwing feeder, whose Fill swaps the demo's OWN SwingTracker into the
-- bar (the real tracker is never fed). The TestMode gate refuses a start in
-- combat, so the scene stands out of combat.
--
-- THE DRIVE. The demo's Beat seam is the test drive (test_swing_demo.lua:
-- a Beat lands AT its stamp's time; the Fill's cycle IS plan cycle 0), and
-- the demo's marks list is per-armed-cycle: a headless walk that keeps
-- landing on later cycles' stamps rides a marks list that has run out, and
-- the live-client 0.2 s ticker (which the tests do not have) pollutes the
-- manual clock with its own Beat(GetTime()) grid. So one clip cycle = one
-- armed cycle: at every 2.8 s cycle base the scene re-arms the demo through
-- its TestMode contract pair (Scrub + Fill at the base) and cancels the
-- ticker that pair's Fill arms (the clip's clock, not a ticker, owns the
-- beats), then walks that cycle's `SwingDemo.beatPlan` stamps with Beat.
-- Every cycle therefore carries the full stamped spine: the fresh swing
-- (Fill's own arming leg), the cast pair (the Fill cycle rides index 1 = a
-- cast cycle), the aim window, the fire, and the flight, at exact offsets
-- off the cycle base. Slots are integers of 1/30 s (slot k reads k/30).
local X = ForteXorcist
local SW = X.Hunter.Swing
local DEMO = X.Hunter.SwingDemo

local FPS = 30
local CYCLE = 2.8

--- The chat/message surfaces that can print text across the crop (the
--- TestMode start line rode ChatFrame1's message FontString: a 725x70 band
--- at device 59,884, deep into the bar's crop). The geometry gate sees only
--- top-level frames and the sim's chat frames report 0x0 rects, so the
--- scene hides and clears every one of them AFTER the Toggle printed
--- (nothing else prints while the clip runs: the demo never calls
--- FX.Print and synthetic rows are silent by the TestMode law).
local function silenceChat()
    local hit = 0
    local function cleanOne(g)
        if type(g) ~= "table" then return end
        if type(g.Clear) == "function" then pcall(g.Clear, g) end
        if type(g.Hide) == "function" then
            pcall(g.Hide, g)
            hit = hit + 1
        end
    end
    cleanOne(_G.DEFAULT_CHAT_FRAME)
    cleanOne(_G.UIErrorsFrame)
    cleanOne(_G.RaidWarningFrame)
    cleanOne(_G.RaidBossEmoteFrame)
    for name, g in pairs(_G) do
        if type(name) == "string"
            and (name:find("^ChatFrame") or name:find("^UIParentChatFrame")
                or name:find("^ChatFrameBG") or name:find("^PetBattleChatLog")
                or name:find("^BattlefieldChatLog")) then
            cleanOne(g)
        end
    end
    FXD.Mark("chathidden", hit)
end

FXD.SET = function()
    -- Out of combat: Test Mode's own gate is a refusal in a fight.
    A_Admin.SetInCombat(false)
    -- The bar: the shipped defaults (barMode "safe" IS the Safe window
    -- mode), every signal key on; the weave line is the one shipped-OFF
    -- signal this clip switches on.
    if SW.Init then pcall(SW.Init, SW) end
    if SW.SetEnabled then SW:SetEnabled(true) end
    SW:SetShowTime(true)
    SW:SetShowAimSlice(true)
    SW:SetShowSafeWindow(true)
    SW:SetShowFlying(true)
    SW:SetShowClipRegion(true)
    SW:SetShowAimWindow(true)
    SW:SetShowWeaveLine(true)
    FXD.Mark("mode", tostring(SW.state and SW.state.barMode))
    FXD.Mark("weave", tostring(SW.state and SW.state.showWeaveLine))
    -- `/fx test`'s own path: Toggle -> Start -> the HunterSwing feeder's
    -- Fill. FX.Print rides the chat frame; the pcall keeps a headless chat
    -- echo from killing the scene.
    pcall(X.TestMode.Toggle, X.TestMode)
    -- The start line is in the chat frame from this instant; the clip's
    -- frames must never see it.
    silenceChat()
    FXD.Mark("testmode", tostring(X.TestMode.active))
    FXD.Mark("demolive", tostring(DEMO and DEMO:Live()))
    ADD("class=" .. tostring(X._playerClass))

    local n = tonumber(FXD.SLOTS) or 270
    FXD.EV = {}
    local function slot(t)
        return math.ceil(t * FPS - 1e-9)
    end
    local function ev(k, fn)
        if k < 0 or k > n - 1 then return end
        local prev = rawget(FXD.EV, k)
        rawset(FXD.EV, k, function()
            if prev then prev() end
            fn()
        end)
    end
    -- One armed cycle: Scrub+Fill at the base (the TestMode contract pair;
    -- the Fill arms cycle index 1 = a cast cycle and swaps the tracker back
    -- in with a fresh OnSwingStart), the ticker that pair arms is cancelled
    -- (a headless ticker rides the manual clock and its Beat grid is not
    -- this clip's), then the cycle's stamp legs, Beat at each stamp's time.
    -- The 0.0 swing leg is the Fill's arming; the 0.1 reloadWitness and the
    -- 2.8 cycle-tail are render instants, not marks.
    --
    -- THE CAST CADENCE (the live demo's law: the Aimed Shot rides every
    -- THIRD cycle). The Fill always arms index 1 = the cast index, so a cast
    -- cycle is driven as-is; a non-cast cycle has its armed index moved to 2
    -- (stampsFor(2) carries no cast pair) and one off-stamp Beat 0.05 in
    -- re-arms the cycle's marks list from that index (the phase lock's
    -- `gap > 0` rebuild). Its castSent/castDone plan legs are filtered, so
    -- tracker.cast never opens and the interlock rides only the cast cycles.
    local function armCycle(base, cast)
        ev(slot(base), function()
            DEMO:Scrub()
            DEMO:Fill(base)
            if not cast then
                DEMO._index = 2
            end
            local tk = rawget(DEMO, "_ticker")
            if tk and tk.Cancel then
                pcall(tk.Cancel, tk)
                DEMO._ticker = nil
            end
        end)
        if not cast then
            ev(slot(base + 0.05), function()
                DEMO:Beat(base + 0.05)
            end)
        end
        -- beatPlan lays each cycle's stamps off its `from`, so the window
        -- MUST start AT the cycle base (a shifted from shifts every stamp
        -- and each Beat lands off the stamp grid, re-arming the cycle).
        for _, b in ipairs(DEMO.beatPlan(base, base + CYCLE)) do
            local kind = b.ev
            if kind ~= "swing" and kind ~= "tail"
                and kind ~= "reloadWitness"
                and (cast or (kind ~= "castSent" and kind ~= "castDone")) then
                ev(slot(b.t), function()
                    DEMO:Beat(b.t)
                end)
            end
        end
    end
    local cycles = 0
    for c = 0, math.ceil((n - 1) / 30 / CYCLE) do
        if c * CYCLE <= (n - 1) / 30 + 1e-9 then
            armCycle(c * CYCLE, (c % 3) == 0)
            cycles = cycles + 1
        end
    end
    ADD("cycles=" .. cycles)
end

FXD.U = function()
    if SW.Update then SW:Update(GetTime()) end
    FXD.Mark("phase", tostring(SW._phase))
    FXD.Mark("fill", string.format("%.0f", SW._fillIntent or -1))
    FXD.Mark("shown", (SW.anchor and SW.anchor.IsShown and SW.anchor:IsShown()) and 1 or 0)
end

FXD.BOX = function()
    FXD.B(SW.anchor)
end

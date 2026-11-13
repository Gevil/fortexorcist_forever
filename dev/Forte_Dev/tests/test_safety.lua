-- dev/Forte_Dev/tests/test_safety.lua
-- The dev loop's safety contract: no chat, no addon messages, nothing protected or gameplay, even
-- through a full ooc run + armed combat run + DevCommands + every verb. Tripwires on the globals.

local FX = ForteXorcist
local Dev = FX.Dev
local S = Dev.Selftest

local TRIPWIRES = { "SendChatMessage", "SendAddonMessage", "CastSpellByName", "CastSpellByID", "UseAction",
    "TargetUnit", "TargetLastTarget", "AssistUnit", "FollowUnit", "RunMacro", "RunMacroText", "JumpOrAscendStart",
    "MoveForwardStart", "UseContainerItem", "UseItemByName", "StartAttack" }
local CHAT_API = { "SendAddonMessage", "SendChatMessage", "SendAddonMessageLogged" }

test("no chat, no addon messages, nothing gameplay: full run, combat run and DevCommands", function()
    local saved, hits = {}, {}
    local function trip(name) return function() hits[#hits + 1] = name end end
    for _, name in ipairs(TRIPWIRES) do saved[name] = _G[name]; _G[name] = trip(name) end
    local savedChat = {}
    if type(_G.C_ChatInfo) == "table" then
        for _, name in ipairs(CHAT_API) do savedChat[name] = _G.C_ChatInfo[name]; _G.C_ChatInfo[name] = trip("C_ChatInfo." .. name) end
    end
    local savedDB, savedAfter, savedCombat, savedCmds, savedShot = _G.ForteDevDB, Dev.After, _G.InCombatLockdown,
        _G.ForteDevCommands, _G.Screenshot
    local savedState = {}
    for k, v in pairs(Dev.state) do savedState[k] = v end

    _G.ForteDevDB = nil
    Dev.InitDB()
    for k in pairs(Dev.state) do Dev.state[k] = nil end
    Dev.state.panelOn = true
    local timers = {}
    Dev.After = function(sec, fn) timers[#timers + 1] = { sec = sec, fn = fn } end
    _G.Screenshot = function() end
    _G.InCombatLockdown = function() return false end
    _G.ForteDevCommands = { "selftest ooc", "shot", "status", "panel off", "panel on", "run",
        { lua = "return 1" } }

    local okAll = Dev.Dispatch("selftest all")
    _G.InCombatLockdown = function() return true end
    Dev.HandleEvent("PLAYER_REGEN_DISABLED")
    for i = 1, #timers do timers[i].fn() end        -- the combat suite + the screenshot
    _G.InCombatLockdown = function() return false end
    Dev.RunCommands(true)
    for i = 1, #timers do pcall(timers[i].fn) end
    SlashCmdList["FORTEDEV"]("status")

    local db = _G.ForteDevDB
    local runs = #db.runs
    _G.ForteDevDB, Dev.After, _G.InCombatLockdown, _G.ForteDevCommands, _G.Screenshot =
        savedDB, savedAfter, savedCombat, savedCmds, savedShot
    for k in pairs(Dev.state) do Dev.state[k] = nil end
    for k, v in pairs(savedState) do Dev.state[k] = v end
    for _, name in ipairs(TRIPWIRES) do _G[name] = saved[name] end
    for name, fn in pairs(savedChat) do _G.C_ChatInfo[name] = fn end
    Dev.Repaint()

    assertEquals(0, #hits, "tripwires hit: " .. table.concat(hits, ","))
    assertTrue(okAll)
    assertTrue(runs >= 1, "the runs really happened (" .. runs .. ")")
end)

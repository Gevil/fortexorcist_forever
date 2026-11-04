-- scene: the four Warlock plates -- Soul Shards (shards burn as spells cast),
-- the Soulstone window (a fresh 600 s window stamps on the clock), the Summon
-- channel (a 5 s cast that completes on screen), the Healthstone count.
--
-- The trackers are the shipped ones with their documented test seams
-- (`NewShardCounter{countReader}`, `NewSoulstoneTracker{now, duration}`, ...),
-- installed through each view's `SetTracker`; the plates are drawn by the
-- UI module's own `Kick`, every frame.
local FX = ForteXorcist
local W = FX.Warlock
local UI = FX.Warlock.UI
local VIEWS = { "Shards", "Soulstone", "Healthstone", "Summon" }
local CK = GetTime

FXD.n = 7
local tr = {}

FXD.SET = function()
    A_Admin.SetInCombat(true)
    tr[1] = W.NewShardCounter({ countReader = function() return FXD.n end })
    tr[1]:Read()
    W.Shards:SetTracker(tr[1])
    tr[2] = W.NewSoulstoneTracker({ now = CK, duration = 600 })
    W.Soulstone:SetTracker(tr[2])
    tr[3] = W.NewHealthstoneTracker({ now = CK, countReader = function() return 2 end })
    tr[3]:ReadCounts()
    W.Healthstone:SetTracker(tr[3])
    tr[4] = W.NewSummonTracker({ now = CK, channelSeconds = 5 })
    W.Summon:SetTracker(tr[4])
    FXD.tr = tr
end

-- The beats: a stone created, a summon channel sent, two shards burned.
FXD.EV[6] = function()
    if tr[2].OnCast then tr[2]:OnCast("Create Soulstone", "Gevil") end
    ADD("stone;")
end
FXD.EV[18] = function()
    if tr[4].OnCastSent then tr[4]:OnCastSent("Ritual of Summoning", "Alice") end
    ADD("summon;")
end
FXD.EV[96] = function() FXD.n = 6; tr[1]:Read(); ADD("shard6;") end
FXD.EV[150] = function() FXD.n = 5; tr[1]:Read(); ADD("shard5;") end

FXD.U = function()
    UI:Kick(VIEWS)
    local shown = 0
    for _, name in ipairs(VIEWS) do
        local v = W[name]
        if v and v.anchor and v.anchor.IsShown and v.anchor:IsShown() then shown = shown + 1 end
    end
    ADD(string.format("plates=%d;", shown))
end

FXD.BOX = function()
    for _, name in ipairs(VIEWS) do
        local v = W[name]
        if v and v.anchor then FXD.B(v.anchor) end
    end
end

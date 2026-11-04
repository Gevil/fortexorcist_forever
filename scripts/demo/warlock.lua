-- scene (static PNG): the four Warlock plates together -- the Soul Shard
-- counter, the Healthstone row, the Soulstone timer, and the mid-channel
-- Ritual of Summoning bar. The state is built the way the module builds it:
-- the shipped tracker constructors fed the same seam readers the tests use,
-- installed with the module's own SetTracker seams, and drawn by
-- `modules.WarlockUI:Kick`. The crop boxes are published by scripts/demo/
-- prelude.lua's BX (device pixels), the gate is scripts/demo/geometry.py.
local W = ForteXorcist.Warlock
local CK = GetTime
local a = W.NewShardCounter({ countReader = function() return 7 end })
a:Read() W.Shards:SetTracker(a)
local b = W.NewSoulstoneTracker({ now = CK, duration = 600 })
b:OnCast("Create Soulstone", "Gevil") W.Soulstone:SetTracker(b)
local c = W.NewHealthstoneTracker({ now = CK, countReader = function() return 2 end })
c:ReadCounts() W.Healthstone:SetTracker(c)
local e = W.NewSummonTracker({ now = CK, channelSeconds = 5 })
e:OnCastSent("Ritual of Summoning", "Alice") W.Summon:SetTracker(e)
ForteXorcist.modules.WarlockUI:Kick({ "Shards", "Soulstone", "Healthstone", "Summon" })
ADD(string.format("c%ds%d;", e:Channeling() and 1 or 0, W.Summon.anchor:IsShown() and 1 or 0))
for _, key in ipairs({ "Shards", "Soulstone", "Healthstone", "Summon" }) do
    local anch = W[key] and W[key].anchor
    if anch then BX(anch) end
end

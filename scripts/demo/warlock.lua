local W=ForteXorcist.Warlock;local CK=GetTime
local a=W.NewShardCounter({countReader=function()return 7 end})a:Read()W.Shards:SetTracker(a)
local b=W.NewSoulstoneTracker({now=CK,duration=600})b:OnCast('Create Soulstone','Gevil')W.Soulstone:SetTracker(b)
local c=W.NewHealthstoneTracker({now=CK,countReader=function()return 2 end})c:ReadCounts()W.Healthstone:SetTracker(c)
local e=W.NewSummonTracker({now=CK,channelSeconds=5})e:OnCastSent('Ritual of Summoning','Alice')W.Summon:SetTracker(e)
ForteXorcist.modules.WarlockUI:Kick({'Shards','Soulstone','Healthstone','Summon'})
ADD(string.format('c%ds%d;',e:Channeling() and 1 or 0,W.Summon.anchor:IsShown() and 1 or 0))

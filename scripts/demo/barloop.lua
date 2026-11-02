local X=ForteXorcist;local E=X.Cooldown.Engine;local D=X.Cooldown.Display
E:Build('HUNTER',function()return true end)E.OnRead=function()end
local function AC(n,r)local t=E.tracked[n]if t then E:OnCast(n,T+r-t.baseDuration)end end
AC('Rapid Fire',260)AC('Concussive Shot',8)
local k=@K@
if k<24 then AC('Serpent Sting',11-k*0.45)else
 local p=T-(k-23.5)*0.083
 local t=E.tracked['Serpent Sting']E:OnCast('Serpent Sting',p-t.baseDuration)
 X.Cooldown.Module:ProcessReadyPops(p+0.001)end
D:Update(E:Sorted({}),T)
BX(ForteXorcistCooldownAnchor)

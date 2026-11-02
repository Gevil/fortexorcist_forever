local X=ForteXorcist;local E=X.Cooldown.Engine;local D=X.Cooldown.Display
E:Build('HUNTER',function()return true end)E.OnRead=function()end
local function AC(n,r)local t=E.tracked[n]if t then E:OnCast(n,T+r-t.baseDuration)end end
AC('Rapid Fire',260)AC('Concussive Shot',8)AC('Multi-Shot',3.5)
local ch=E.tracked['Freezing Trap']if ch then ch.maxCharges=3 end
for i=1,3 do AC('Freezing Trap',26)end
D:Update(E:Sorted({}),T)
local n=0;for k in pairs(D._byName)do n=n+1 end
ADD(string.format('n=%d;',n))BX(ForteXorcistCooldownAnchor)

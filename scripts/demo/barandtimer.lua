local X=ForteXorcist;local E=X.Cooldown.Engine;local D=X.Cooldown.Display;local R=X.Timer.Rows;local RG=X.Timer.Registry
E:Build('HUNTER',function()return true end)E.OnRead=function()end
local function AC(n,r)local t=E.tracked[n]if t then E:OnCast(n,T+r-t.baseDuration)end end
AC('Rapid Fire',260)AC('Concussive Shot',8)AC('Multi-Shot',3.5)AC('Intimidation',42)
local c=E.tracked['Freezing Trap']if c then c.maxCharges=3 end
for i=1,3 do AC('Freezing Trap',26)end
D:Update(E:Sorted({}),T)
for s in string.gmatch('NPE_TutorialMainFrame_Frame AdventureMapFrame ChatFrame','[%w_]+')do local g=_G[s]if g and g.Hide then g:Hide()end end
local N={'Serpent Sting','Intimidation','Concussive Shot'}
for i,n in ipairs(N)do local d=RG.BestDuration(n)
  if d then R:InsertFromCast(n,i%2==1 and'Ragnaros'or'Lady Pythas',d,T-2*i,T-2*i+0.6,100+i)end end
X.modules.Timer:Kick()
local n=0;for k in pairs(D._byName)do n=n+1 end
ADD(string.format('n=%d,rows=%d;',n,R.rows_n))BX(ForteXorcistCooldownAnchor)BX(ForteXorcistTimerAnchor)

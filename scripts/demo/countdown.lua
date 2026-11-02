local X=ForteXorcist;local R=X.Timer.Rows;local RG=X.Timer.Registry
local N={'Concussive Shot','Freezing Trap','Intimidation','Rapid Fire','Multi-Shot','Viper Sting'}
for i=1,6 do local d=RG.BestDuration(N[i])
if d then local el=0.8+(@K@)/12;local dd=d;if i==6 then dd=2.3 end
if dd>el then R:InsertFromCast(N[i],i%2==1 and'Dummy-1'or'Dummy-2',dd,T-el,T-el,1)end end end
X.modules.Timer:Kick()
ADD('r='..R.rows_n..';')BX(ForteXorcistTimerAnchor)

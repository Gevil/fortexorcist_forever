for s in string.gmatch('NPE_TutorialMainFrame_Frame AdventureMapFrame','[%w_]+')do local g=_G[s]if g and g.Hide then g:Hide()end end
local X=ForteXorcist;local E=X.Cooldown.Engine;local S=X.Cooldown.Splash
E:Build('HUNTER',function()return true end)E.OnRead=function()end
X.Settings:Set('Splash','Enable',true)
local p=T-@K@/12
E:OnCast('Rapid Fire',p-300)
X.Cooldown.Module:ProcessReadyPops(p+0.001)
S:Update(T)
local sl=S._icons[1]
if sl then
 ADD(string.format('w=%d;a=%.2f;',F(sl.tex:GetWidth()),sl.frame:GetAlpha()*S.anchor:GetAlpha()))
 BX(S.anchor)
else ADD('none;')BX(ForteXorcistSplashAnchor)end

local O=ForteXorcist.Options
for s in string.gmatch('NPE_TutorialMainFrame_Frame ChatFrame','[%w_]+')do local g=_G[s]if g and g.Hide then g:Hide()end end
O:Open('General')
local c=0;for k in pairs(O.pages)do c=c+1 end
ADD('p='..c..';')BX(ForteXorcistOptionsWindow)

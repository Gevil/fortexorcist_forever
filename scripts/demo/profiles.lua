local X=ForteXorcist
for s in string.gmatch('NPE_TutorialMainFrame_Frame ChatFrame','[%w_]+')do local g=_G[s]if g and g.Hide then g:Hide()end end
X.Options:Open('Profiles')
local l=X.Profiles.List()ADD('p='..#l..';'..table.concat(l,',')..';')BX(ForteXorcistOptionsWindow)

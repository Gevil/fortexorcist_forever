for s in string.gmatch('NPE_TutorialMainFrame_Frame AdventureMapFrame ChatFrame','[%w_]+')do local g=_G[s]if g and g.Hide then g:Hide()end end
ForteXorcist.OnSlash('timer test')
ADD('t='..ForteXorcist.Timer.Rows.rows_n..';')BX(ForteXorcistTimerAnchor)

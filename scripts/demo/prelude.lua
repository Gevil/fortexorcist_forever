local F,C=math.floor,math.ceil
local d=CreateFrame('Frame','FXD');d:SetPoint('TOPLEFT',UIParent,'TOPLEFT',4,4)local fs=d:CreateFontString(nil,'OVERLAY','GameFontNormalSmall');d:Show()
local P='FXD 'local function ADD(s)P=P..s;fs.SetText(fs,P)end
local UP=UIParent
local function BX(f)local l,b,w,h=f:GetRect()local W=UP:GetWidth()local U=UP:GetHeight()local x=math.max(0,F(l-12))local y=math.max(0,F(U-b-h-12))ADD(string.format('%d,%d,%d,%d;',x,y,math.min(W-x,C(w+24)),math.min(U-y,C(h+24))))end
local T=GetTime()+0.02

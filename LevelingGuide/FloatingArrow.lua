local _,ns=...
local Floating={};ns.FloatingArrow=Floating
function Floating.New(settings)
    local frame=CreateFrame("Frame","LevelingGuideFloatingArrow",UIParent,"BackdropTemplate")
    frame:SetSize(100,100);frame:SetMovable(true);frame:SetClampedToScreen(true)
    frame:EnableMouse(true);frame:RegisterForDrag("LeftButton");frame:SetFrameStrata("MEDIUM")
    frame:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=12,insets={left=3,right=3,top=3,bottom=3}})
    frame:SetBackdropColor(.05,.035,.02,.75);frame:SetBackdropBorderColor(.8,.65,.3,1)
    local saved=settings.arrowPosition or {}
    local valid={CENTER=true,TOP=true,TOPLEFT=true,TOPRIGHT=true,LEFT=true,RIGHT=true,BOTTOM=true,BOTTOMLEFT=true,BOTTOMRIGHT=true}
    frame:SetPoint(valid[saved.point] and saved.point or "CENTER",UIParent,valid[saved.point] and saved.point or "CENTER",type(saved.x)=="number" and saved.x or 0,type(saved.y)=="number" and saved.y or 100)
    local title=frame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    title:SetPoint("TOP",0,-8);title:SetText("WALK")
    local arrow=frame:CreateTexture(nil,"ARTWORK")
    arrow:SetSize(52,52);arrow:SetPoint("CENTER",0,0)
    arrow:SetTexture("Interface\\MINIMAP\\MinimapArrow");arrow:SetVertexColor(1,.82,.32)
    local distance=frame:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    distance:SetPoint("BOTTOM",0,8)
    frame:SetScript("OnDragStart",function() frame:StartMoving() end)
    frame:SetScript("OnDragStop",function()
        frame:StopMovingOrSizing()
        local point,_,_,x,y=frame:GetPoint(1)
        settings.arrowPosition={point=point,x=x,y=y}
    end)
    frame:SetScript("OnEnter",function()
        if GameTooltip then GameTooltip:SetOwner(frame,"ANCHOR_RIGHT");GameTooltip:SetText("LevelingGuide");GameTooltip:AddLine("Drag to move",1,1,1);GameTooltip:Show() end
    end)
    frame:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
    frame:Hide()
    local result={frame=frame}
    function result:Hide() frame:Hide() end
    function result:Update(nav,running)
        if not running or not nav or not (nav.visible or nav.pathPending or nav.arrived) then frame:Hide();return end
        frame:Show()
        title:SetText(nav.pathPending and "PATH" or nav.arrived and "ARRIVED" or nav.walking and "WALK" or "GO TO")
        if nav.visible and type(nav.rotation)=="number" then arrow:Show();arrow:SetRotation(nav.rotation) else arrow:Hide() end
        distance:SetText(nav.pathPending and "Wait..." or type(nav.distance)=="number" and (math.floor(math.max(0,nav.distance)+.5).." yd") or "")
    end
    return result
end

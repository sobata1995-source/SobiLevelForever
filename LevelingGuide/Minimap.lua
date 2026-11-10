-- Native minimap launcher; position is saved with the guide's UI settings.
local _, ns = ...
local Launcher = {}
ns.MinimapLauncher = Launcher
local function angle(y,x)
    if math.atan2 then return math.atan2(y,x) end
    if x>0 then return math.atan(y/x) end
    if x<0 then return math.atan(y/x)+(y>=0 and math.pi or -math.pi) end
    return y>0 and math.pi/2 or y<0 and -math.pi/2 or 0
end
function Launcher.New(controller, settings)
    if not Minimap then return nil end
    local button=CreateFrame("Button","SobiLevelForeverMinimap",Minimap)
    button:SetSize(31,31)
    button:SetFrameStrata("MEDIUM")
    button:RegisterForClicks("LeftButtonUp","RightButtonUp")
    button:RegisterForDrag("LeftButton")
    local background=button:CreateTexture(nil,"BACKGROUND")
    background:SetSize(25,25)
    background:SetPoint("TOPLEFT",4,-2)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    local icon=button:CreateTexture(nil,"ARTWORK")
    icon:SetSize(18,20)
    icon:SetPoint("TOPLEFT",7,-5)
    icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
    local rim=button:CreateTexture(nil,"OVERLAY")
    rim:SetSize(53,53)
    rim:SetPoint("TOPLEFT",0,0)
    rim:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local saved=settings.minimapAngle
    if type(saved)~="number" or saved~=saved or math.abs(saved)==math.huge then settings.minimapAngle=220 end
    local function position()
        local radius=Minimap:GetWidth()/2+12
        local radians=math.rad(settings.minimapAngle)
        button:ClearAllPoints()
        button:SetPoint("CENTER",Minimap,"CENTER",math.cos(radians)*radius,math.sin(radians)*radius)
    end
    local dragStopped=-math.huge
    button:SetScript("OnClick",function(_,which)
        if GetTime and GetTime()-dragStopped<.25 then return end
        if which=="RightButton" then controller:ShowUI();controller.ui:ShowRoutes()
        elseif which=="LeftButton" then
            if controller.ui:IsShown() then controller:HideUI() else controller:ShowUI() end
        end
    end)
    button:SetScript("OnDragStart",function()
        button:SetScript("OnUpdate",function()
            local x,y=GetCursorPosition()
            local cx,cy=Minimap:GetCenter()
            local scale=Minimap:GetEffectiveScale()
            if cx and cy and scale and scale>0 then
                settings.minimapAngle=math.deg(angle(y/scale-cy,x/scale-cx))
                position()
            end
        end)
    end)
    button:SetScript("OnDragStop",function()
        button:SetScript("OnUpdate",nil)
        dragStopped=GetTime and GetTime() or -math.huge
    end)
    button:SetScript("OnEnter",function()
        if not GameTooltip then return end
        GameTooltip:SetOwner(button,"ANCHOR_LEFT")
        GameTooltip:SetText("LevelingGuide",1,.82,.32)
        GameTooltip:AddLine("Left-click: Show / Hide",1,1,1)
        GameTooltip:AddLine("Right-click: Routes",1,1,1)
        GameTooltip:AddLine("Drag: Move",.7,.7,.7)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
    position()
    return button
end

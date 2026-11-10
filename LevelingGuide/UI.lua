-- SobiLevel Forever: native, dependency-free guide window.
-- Copyright (c) 2026 SobiLevel Forever contributors. See LICENSE.txt.
local addonName, ns = ...
ns.UI = ns.UI or {}

local UI = ns.UI
local WINDOW_WIDTH, WINDOW_HEIGHT = 400, 416
local BODY_HEIGHT, BODY_WIDTH = 190, 280
local ROUTE_ROWS, ROUTE_ROW_HEIGHT = 8, 46
local COLORS = {
    background = { .85, .76, .62, 1 },
    raised = { .55, .45, .32, 1 },
    border = { .72, .58, .34, 1 },
    gold = { 1, .82, .32, 1 },
    text = { 1, .94, .80, 1 },
    muted = { .75, .68, .53, 1 },
    green = { .42, .83, .62, 1 },
}
local BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 24,
    insets = { left = 5, right = 5, top = 5, bottom = 5 },
}

local function Secret(value)
    if type(issecretvalue) == "function" then
        local ok, result = pcall(issecretvalue, value)
        return not ok or result
    end
    return false
end

local function Number(value)
    if Secret(value) then return nil end
    local number = tonumber(value)
    if number and number == number and number ~= math.huge and number ~= -math.huge then return number end
end

local function Clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, Number(value) or minimum))
end

local function Text(value, fallback)
    if Secret(value) or value == nil then return fallback or "" end
    return tostring(value)
end

local function Call(self, method, ...)
    local callback = self.controller and self.controller[method]
    if type(callback) == "function" then return callback(self.controller, ...) end
end

local function Backdrop(frame, color, border)
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(unpack(color or COLORS.background))
    frame:SetBackdropBorderColor(unpack(border or COLORS.border))
end

local function Font(parent, template, color)
    local font = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    font:SetTextColor(unpack(color or COLORS.text))
    font:SetJustifyH("LEFT")
    font:SetJustifyV("TOP")
    return font
end

local function Tooltip(owner, title, detail)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(Text(title), unpack(COLORS.gold))
    if detail and detail ~= "" then
        GameTooltip:AddLine(Text(detail), .82, .86, .91, true)
    end
    GameTooltip:Show()
end

local function HideTooltip()
    if GameTooltip then GameTooltip:Hide() end
end

local function Button(parent, label, width, height, primary)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, height)
    button.primary = primary
    button.text = Font(button, "GameFontHighlightSmall", primary and COLORS.gold or COLORS.text)
    button.text:SetPoint("CENTER")
    button.text:SetJustifyH("CENTER")
    button.text:SetJustifyV("MIDDLE")
    button.text:SetText(label)
    button:SetScript("OnEnter", function(self)
        if self.tooltipTitle then Tooltip(self, self.tooltipTitle, self.tooltipText) end
    end)
    button:SetScript("OnLeave", function(self)
        HideTooltip()
    end)
    button:SetScript("OnMouseDown", function(self)
        if self:IsEnabled() then self.text:SetPoint("CENTER", 0, -1) end
    end)
    button:SetScript("OnMouseUp", function(self) self.text:SetPoint("CENTER", 0, 0) end)
    return button
end

local function EnableButton(button, enabled)
    button:SetEnabled(not not enabled)
    button:SetAlpha(enabled and 1 or .35)
end

local function KindLabel(kind)
    local names = {
        accept = "ACCEPT QUEST", turnin = "TURN IN QUEST", turnIn = "TURN IN QUEST",
        complete = "QUEST OBJECTIVE", quest = "QUEST", travel = "TRAVEL", ["goto"] = "TRAVEL",
        grind = "LEVELING", hearth = "HEARTHSTONE", flight = "FLIGHT PATH",
        train = "TRAINING", vendor = "SUPPLIES", note = "GUIDE NOTE",
        manual = "CHECKPOINT", level = "LEVEL CHECKPOINT",
    }
    return names[kind] or Text(kind, "GUIDE STEP"):upper()
end

function UI.New(controller)
    local self = setmetatable({ controller = controller, routeOffset = 0, routeChoices = {}, maxScroll = 0 }, { __index = UI })
    local frame = CreateFrame("Frame", "SobiLevelForeverWindow", UIParent, "BackdropTemplate")
    self.frame = frame
    frame:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    frame:SetPoint("RIGHT", UIParent, "RIGHT", -40, 0)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    Backdrop(frame)

    local accent = frame:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT", 14, -49)
    accent:SetPoint("TOPRIGHT", -14, -49)
    accent:SetHeight(2)
    accent:SetColorTexture(unpack(COLORS.gold))

    local banner = frame:CreateTexture(nil, "BACKGROUND")
    banner:SetPoint("TOPLEFT", 8, -8)
    banner:SetPoint("TOPRIGHT", -8, -8)
    banner:SetHeight(40)
    banner:SetColorTexture(.23, .035, .025, .95)

    local footer = frame:CreateTexture(nil, "BACKGROUND")
    footer:SetPoint("BOTTOMLEFT", 8, 8)
    footer:SetPoint("BOTTOMRIGHT", -8, 8)
    footer:SetHeight(52)
    footer:SetColorTexture(.08, .045, .025, .8)

    local header = CreateFrame("Frame", nil, frame)
    self.header = header
    header:SetPoint("TOPLEFT", 4, -4)
    header:SetPoint("TOPRIGHT", -35, -4)
    header:SetHeight(43)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() frame:StartMoving() end)
    header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local point, _, _, x, y = frame:GetPoint(1)
        Call(self, "SavePosition", point, x, y)
    end)
    header:SetScript("OnEnter", function() Tooltip(header, "LevelingGuide", "Drag this header to move the guide.") end)
    header:SetScript("OnLeave", HideTooltip)

    self.title = Font(frame, "GameFontNormal", COLORS.gold)
    self.title:SetPoint("TOPLEFT", 16, -14)
    self.title:SetText("LevelingGuide")
    self.subtitle = Font(frame, "GameFontHighlightSmall", COLORS.muted)
    self.subtitle:SetPoint("TOPLEFT", 16, -34)
    self.subtitle:SetWidth(235)
    self.subtitle:SetText("YOUR LEVELING GUIDE")

    self.modeBadge = Font(frame, "GameFontHighlightSmall", COLORS.green)
    self.modeBadge:SetPoint("TOPRIGHT", -43, -16)
    self.modeBadge:SetJustifyH("RIGHT")
    self.modeBadge:SetText("GUIDE")
    local close = Button(frame, "x", 21, 21)
    close:SetPoint("TOPRIGHT", -10, -10)
    close.tooltipTitle, close.tooltipText = "Hide guide", "Hide the window. Your route progress is kept."
    close:SetScript("OnClick", function()
        if self.controller and type(self.controller.HideUI) == "function" then Call(self, "HideUI") else self:Hide() end
    end)
    self.closeButton = close

    local progressBackground = frame:CreateTexture(nil, "BACKGROUND")
    progressBackground:SetPoint("TOPLEFT", 16, -56)
    progressBackground:SetSize(WINDOW_WIDTH - 32, 4)
    progressBackground:SetColorTexture(.10, .14, .19, 1)
    local progress = CreateFrame("StatusBar", nil, frame)
    progress:SetAllPoints(progressBackground)
    progress:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    progress:SetStatusBarColor(unpack(COLORS.gold))
    progress:SetMinMaxValues(0, 1)
    progress:SetValue(0)
    self.progress = progress

    self.routeTitle = Font(frame, "GameFontNormal", COLORS.text)
    self.routeTitle:SetPoint("TOPLEFT", 16, -72)
    self.routeTitle:SetWidth(WINDOW_WIDTH - 32)
    self.routeTitle:SetHeight(18)
    self.routeTitle:SetWordWrap(false)
    self.stepKind = Font(frame, "GameFontHighlightSmall", COLORS.gold)
    self.stepKind:SetPoint("TOPLEFT", 16, -97)
    self.stepKind:SetWidth(BODY_WIDTH)
    self.stepKind:SetHeight(13)

    local scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:SetPoint("TOPLEFT", 16, -116)
    scroll:SetSize(BODY_WIDTH, BODY_HEIGHT)
    scroll:EnableMouseWheel(true)
    local body = CreateFrame("Frame", nil, scroll)
    body:SetSize(BODY_WIDTH, BODY_HEIGHT)
    scroll:SetScrollChild(body)
    local stepText = Font(body, "GameFontHighlight", COLORS.text)
    stepText:SetPoint("TOPLEFT", 0, 0)
    stepText:SetWidth(BODY_WIDTH - 8)
    stepText:SetWordWrap(true)
    if stepText.SetNonSpaceWrap then stepText:SetNonSpaceWrap(true) end
    stepText:SetSpacing(3)
    self.bodyScroll, self.body, self.stepText = scroll, body, stepText

    local scrollTrack = frame:CreateTexture(nil, "ARTWORK")
    scrollTrack:SetPoint("TOPLEFT", 16 + BODY_WIDTH - 3, -116)
    scrollTrack:SetSize(2, BODY_HEIGHT)
    scrollTrack:SetColorTexture(.13, .18, .25, 1)
    local thumb = frame:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(2)
    thumb:SetColorTexture(unpack(COLORS.gold))
    self.scrollTrack, self.scrollThumb = scrollTrack, thumb
    scroll:SetScript("OnMouseWheel", function(_, delta)
        self:SetBodyScroll(scroll:GetVerticalScroll() - delta * 28)
    end)

    local arrowFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    arrowFrame:SetSize(80, 110)
    arrowFrame:SetPoint("TOPRIGHT", -16, -116)
    Backdrop(arrowFrame, { .7, .56, .34, 1 }, COLORS.gold)
    arrowFrame:EnableMouse(true)
    arrowFrame:SetScript("OnEnter", function()
        Tooltip(arrowFrame, self.navTitle or "Waypoint", self.navHint or "The arrow is shown when this step has a usable waypoint.")
    end)
    arrowFrame:SetScript("OnLeave", HideTooltip)
    arrowFrame:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then Call(self, "OpenMap") end
    end)
    local arrowLabel = Font(arrowFrame, "GameFontHighlightSmall", COLORS.muted)
    arrowLabel:SetPoint("TOP", 0, -7)
    arrowLabel:SetJustifyH("CENTER")
    arrowLabel:SetText("GO TO")
    local arrow = arrowFrame:CreateTexture(nil, "ARTWORK")
    arrow:SetSize(48, 48)
    arrow:SetPoint("TOP", 0, -24)
    arrow:SetTexture("Interface\\MINIMAP\\MinimapArrow")
    arrow:SetVertexColor(unpack(COLORS.gold))
    local distance = Font(arrowFrame, "GameFontHighlightSmall", COLORS.text)
    distance:SetPoint("BOTTOM", 0, 9)
    distance:SetWidth(76)
    distance:SetJustifyH("CENTER")
    distance:SetText("--")
    self.arrowFrame, self.arrow, self.distance, self.arrowLabel = arrowFrame, arrow, distance, arrowLabel

    self.bodyHint = Font(frame, "GameFontHighlightSmall", COLORS.muted)
    self.bodyHint:SetPoint("TOPLEFT", 16, -314)
    self.bodyHint:SetWidth(WINDOW_WIDTH - 32)
    self.bodyHint:SetHeight(30)
    self.bodyHint:SetWordWrap(true)
    self.bodyHint:SetSpacing(2)
    local hintHotspot = CreateFrame("Frame", nil, frame)
    hintHotspot:SetPoint("TOPLEFT", self.bodyHint, "TOPLEFT")
    hintHotspot:SetPoint("BOTTOMRIGHT", self.bodyHint, "BOTTOMRIGHT")
    hintHotspot:EnableMouse(true)
    hintHotspot:SetScript("OnEnter", function()
        if self.view and self.view.stepHint and self.view.stepHint ~= "" then Tooltip(hintHotspot, "Step details", self.view.stepHint) end
    end)
    hintHotspot:SetScript("OnLeave", HideTooltip)

    self.status = Font(frame, "GameFontHighlightSmall", COLORS.muted)
    self.status:SetPoint("TOPLEFT", 16, -344)
    self.status:SetWidth(WINDOW_WIDTH - 32)
    self.status:SetHeight(13)
    self.status:SetWordWrap(false)

    local previous = Button(frame, "Prev", 80, 24)
    previous:SetPoint("TOPLEFT", 16, -362)
    previous.tooltipTitle, previous.tooltipText = "Previous step", "Review the previous step in this route."
    previous:SetScript("OnClick", function() Call(self, "Prev") end)
    local skip = Button(frame, "Skip", 80, 24)
    skip:SetPoint("LEFT", previous, "RIGHT", 8, 0)
    skip.tooltipTitle, skip.tooltipText = "Skip step", "Skip this guide step. For an unaccepted optional quest, also skip its later unaccepted steps and unavailable dependent chain. Your game quests are unchanged."
    skip:SetScript("OnClick", function() Call(self, "Skip") end)
    local nextButton = Button(frame, "Next", 152, 24, true)
    nextButton:SetPoint("LEFT", skip, "RIGHT", 8, 0)
    nextButton.tooltipTitle, nextButton.tooltipText = "Next step", "Continue when this step is done. Quest progress can also advance automatically."
    nextButton:SetScript("OnClick", function() Call(self, "Next") end)
    self.prevButton, self.skipButton, self.nextButton = previous, skip, nextButton

    local routes = Button(frame, "Routes", 76, 18)
    routes:SetPoint("TOPLEFT", 16, -392)
    routes.tooltipTitle, routes.tooltipText = "Choose route", "Browse the available chapters and leveling routes."
    routes:SetScript("OnClick", function() self:ToggleRoutes() end)
    local pause = Button(frame, "Pause", 76, 18)
    pause:SetPoint("LEFT", routes, "RIGHT", 8, 0)
    pause.tooltipTitle, pause.tooltipText = "Pause or resume", "Control automatic guide progression."
    pause:SetScript("OnClick", function() Call(self, "TogglePause") end)
    local report = Button(frame, "Report", 76, 18)
    report:SetPoint("LEFT", pause, "RIGHT", 8, 0)
    report.tooltipTitle, report.tooltipText = "Report route issue", "Show diagnostic information for this route and step."
    report:SetScript("OnClick", function() Call(self, "Report") end)
    self.routesButton, self.pauseButton, self.reportButton = routes, pause, report
    local reset = Button(frame, "Reset", 76, 18)
    reset:SetPoint("LEFT", report, "RIGHT", 8, 0)
    reset.tooltipTitle, reset.tooltipText = "Reset guide", "Recover from skipped steps. Resets guide choices for this character after confirmation; completed game quests are kept."
    reset:SetScript("OnClick", function() Call(self, "ConfirmReset") end)
    self.resetButton = reset

    frame:SetScript("OnHide", function()
        if self.routePicker then self.routePicker:Hide() end
        HideTooltip()
    end)
    self:CreateRoutePicker()
    self:SetArrow(nil)
    self:Render({ routeTitle = "Choose your route", stepText = "Your guide will appear here.", stepHint = "", stepIndex = 0, totalSteps = 0, progress = 0 })
    return self
end

function UI:SetBodyScroll(offset)
    offset = Clamp(offset, 0, self.maxScroll)
    self.bodyScroll:SetVerticalScroll(offset)
    if self.maxScroll > 0 then
        local height = math.max(14, BODY_HEIGHT * BODY_HEIGHT / (BODY_HEIGHT + self.maxScroll))
        local shift = (BODY_HEIGHT - height) * offset / self.maxScroll
        self.scrollThumb:ClearAllPoints()
        self.scrollThumb:SetPoint("TOPLEFT", self.scrollTrack, "TOPLEFT", 0, -shift)
        self.scrollThumb:SetHeight(height)
        self.scrollTrack:Show()
        self.scrollThumb:Show()
    else
        self.scrollTrack:Hide()
        self.scrollThumb:Hide()
    end
end

function UI:Render(view)
    view = view or {}
    local renderKey = Text(view.routeID) .. "\031" .. Text(view.routeTitle)
        .. "\031" .. Text(view.stepIndex) .. "\031" .. Text(view.stepText)
    local changedStep = self.renderKey ~= renderKey
    self.renderKey = renderKey
    self.view = view
    local index, total = Number(view.stepIndex) or 0, Number(view.totalSteps) or 0
    local level = Number(view.playerLevel)
    local levelText = level and ("Level " .. level .. "  |  ") or ""
    self.subtitle:SetText(levelText .. (total > 0 and ("Step " .. math.max(1, index) .. " / " .. total) or "LEVELING ROUTES"))
    if view.areaTasks and #view.areaTasks > 1 then self.subtitle:SetText(levelText .. #view.areaTasks .. " nearby tasks") end
    self.routeTitle:SetText(Text(view.routeTitle, "Choose your route"))
    self.stepKind:SetText(KindLabel(view.stepKind))
    self.stepText:SetText(Text(view.stepText, "Choose a route to begin."))
    local height = math.max(BODY_HEIGHT, math.ceil(self.stepText:GetStringHeight()) + 4)
    self.body:SetHeight(height)
    self.maxScroll = math.max(0, height - BODY_HEIGHT)
    self:SetBodyScroll(changedStep and 0 or self.bodyScroll:GetVerticalScroll())
    self.bodyHint:SetText(Text(view.stepHint))
    self.status:SetText(Text(view.status))
    if view.efficiency and type(view.efficiency.rate)=="number" then
        self.status:SetText(Text(view.status).." | Est. "..math.floor(view.efficiency.rate+.5).." XP/min")
    end
    local statusColor = type(view.statusColor) == "table" and view.statusColor or COLORS.muted
    self.status:SetTextColor(statusColor.r or statusColor[1] or .57, statusColor.g or statusColor[2] or .64, statusColor.b or statusColor[3] or .73)
    self.progress:SetValue(Clamp(view.progress, 0, 1))
    local badge = view.paused and "PAUSED"
        or ((view.manualReview or view.conditionUnknown) and "REVIEW")
        or ((view.autoActive and not view.manual) and "AUTO") or "GUIDE"
    self.modeBadge:SetText(badge)
    if badge=="AUTO" and view.speedMode then self.modeBadge:SetText("SPEED") end
    self.modeBadge:SetTextColor(unpack(view.paused and COLORS.gold or COLORS.green))
    self.pauseButton.text:SetText(view.paused and "Resume" or "Pause")
    self.nextButton.text:SetText(view.canNext == false and "Auto" or view.manual and "Done" or "Next")
    EnableButton(self.prevButton, index > 1 and view.canPrev ~= false)
    EnableButton(self.skipButton, total > 0 and not view.complete)
    EnableButton(self.nextButton, total > 0 and not view.complete and view.canNext ~= false)
    if self.routePicker:IsShown() then
        local choices=Call(self,"GetRouteChoices")
        if type(choices)=="table" then self.routeChoices=choices end
        self:RefreshRouteRows()
    end
end

function UI:SetArrow(nav)
    nav = nav or {}
    local rotation, yards = Number(nav.rotation), Number(nav.distance)
    local available = nav.visible ~= false and not nav.unavailable and rotation ~= nil
    self.navTitle = Text(nav.label)
    if self.navTitle == "" then self.navTitle = "Waypoint" end
    local detail = Text(nav.text)
    local hint = Text(nav.hint, available and "Direction and distance to the current step's waypoint." or "This step has no usable waypoint on the current map.")
    self.navHint = (detail ~= "" and (detail .. "\n") or "") .. hint
    if nav.paused then
        self.navHint = self.navHint .. "\nYour own map pin is being respected. Resume to restore guide waypoint tracking."
    end
    self.navHint = self.navHint .. "\nClick to open the map."
    if self.view then
        self.bodyHint:SetText(detail ~= "" and detail or (available and "Follow the arrow. Click it to open the map." or nav.arrived and "You are at the destination. Follow the task instructions above." or "No exact map pin for this step. Read WHERE and the instructions above."))
    end
    if available then
        self.arrow:Show()
        self.arrow:SetAlpha(nav.arrived and .55 or 1)
        self.arrow:SetRotation(rotation)
    else
        self.arrow:Hide()
    end
    self.arrowLabel:SetText(nav.pathPending and "PATH" or nav.walking and not nav.arrived and "WALK" or nav.inventoryOnly and "BAGS" or nav.areaOnly and "EVENT" or nav.arrived and "HERE" or (available and "GO TO" or "NO PIN"))
    local distanceText
    if nav.pathPending then
        distanceText = "WAIT"
    elseif nav.inventoryOnly then
        distanceText = "USE ITEM"
    elseif nav.areaOnly then
        distanceText = "FOLLOW"
    elseif yards then
        local distance = math.max(0, yards)
        distanceText = distance >= 1000 and string.format("%.1fk yd", distance / 1000) or (math.floor(distance + .5) .. " yd")
    elseif nav.arrived then
        distanceText = "HERE"
    elseif nav.paused or detail == "Paused" then
        distanceText = "PAUSED"
    elseif nav.crossZone then
        distanceText = "MAP"
    elseif detail ~= "" then
        -- Full instructions and unverified coordinates belong in the tooltip,
        -- never in this 54px-wide compact distance field.
        distanceText = detail == "Open map" and "MAP" or "CHECK"
    end
    self.distance:SetText(Text(distanceText, "READ"))
    self.arrowFrame:SetAlpha((available or nav.arrived) and 1 or .55)
end

function UI:CreateRoutePicker()
    local picker = CreateFrame("Frame", "SobiLevelForeverRoutes", self.frame, "BackdropTemplate")
    self.routePicker = picker
    picker:SetSize(420, 452)
    picker:SetPoint("CENTER", self.frame, "CENTER", 0, 0)
    picker:SetFrameStrata("DIALOG")
    picker:SetClampedToScreen(true)
    picker:EnableMouse(true)
    picker:EnableMouseWheel(true)
    picker:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",edgeSize=24,insets={left=6,right=6,top=6,bottom=6}})
    picker:SetBackdropColor(.035,.022,.012,1)
    picker:SetBackdropBorderColor(.8,.65,.35,1)
    local title = Font(picker, "GameFontNormal", COLORS.gold)
    title:SetPoint("TOPLEFT", 14, -13)
    title:SetText("Choose a route")
    local close = Button(picker, "x", 20, 20)
    close:SetPoint("TOPRIGHT", -9, -9)
    close:SetScript("OnClick", function() picker:Hide() end)
    self.routeRows = {}
    for rowNumber = 1, ROUTE_ROWS do
        local row = CreateFrame("Button", nil, picker, "BackdropTemplate")
        row:SetSize(392, ROUTE_ROW_HEIGHT - 4)
        row:SetPoint("TOPLEFT", 14, -43 - (rowNumber - 1) * ROUTE_ROW_HEIGHT)
        row:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
        row:SetBackdropColor(.10,.065,.035,1)
        row:SetBackdropBorderColor(.35,.27,.15,1)
        row.title = Font(row, "GameFontHighlightSmall", COLORS.text)
        row.title:SetPoint("TOPLEFT", 10, -7)
        row.title:SetWidth(368)
        row.title:SetHeight(16)
        row.title:SetWordWrap(false)
        row.summary = Font(row, "GameFontHighlightSmall", COLORS.muted)
        row.summary:SetPoint("TOPLEFT", 10, -26)
        row.summary:SetWidth(368)
        row.summary:SetHeight(14)
        row.summary:SetWordWrap(false)
        row:SetScript("OnEnter", function(button)
            button:SetBackdropBorderColor(unpack(COLORS.gold))
            if button.choice then Tooltip(button, button.choice.title, button.choice.summary) end
        end)
        row:SetScript("OnLeave", function(button)
            button:SetBackdropBorderColor(unpack(button.selected and COLORS.gold or COLORS.border))
            HideTooltip()
        end)
        row:SetScript("OnClick", function(button)
            if not button.choice then return end
            local id = button.choice.id
            picker:Hide()
            HideTooltip()
            Call(self, "ChooseRoute", id)
        end)
        self.routeRows[rowNumber] = row
    end
    self.routeCount = Font(picker, "GameFontHighlightSmall", COLORS.muted)
    self.routeCount:SetPoint("BOTTOMLEFT", 14, 12)
    self.routeCount:SetWidth(250)
    self.routeCount:SetHeight(13)
    local up = Button(picker, "Up", 42, 19)
    up:SetPoint("BOTTOMRIGHT", -61, 9)
    up:SetScript("OnClick", function() self:ScrollRoutes(-1) end)
    local down = Button(picker, "Down", 42, 19)
    down:SetPoint("BOTTOMRIGHT", -14, 9)
    down:SetScript("OnClick", function() self:ScrollRoutes(1) end)
    self.routeUp, self.routeDown = up, down
    local reset = Button(picker, "Reset guide", 110, 24)
    reset:SetPoint("CENTER", 0, -20)
    reset:SetScript("OnClick", function() Call(self, "ConfirmReset") end)
    self.emptyRouteReset = reset
    self.emptyRouteText = Font(picker, "GameFontHighlight", COLORS.muted)
    self.emptyRouteText:SetPoint("CENTER", 0, 32)
    self.emptyRouteText:SetWidth(350)
    self.emptyRouteText:SetHeight(50)
    self.emptyRouteText:SetText("No unfinished routes for your level.\nSkipped too far? Reset the guide.")
    picker:SetScript("OnMouseWheel", function(_, delta) self:ScrollRoutes(-delta) end)
    picker:SetScript("OnHide", HideTooltip)
    picker:Hide()
end

function UI:RefreshRouteRows()
    local count = #self.routeChoices
    if count == 0 then
        self.emptyRouteReset:Show(); self.emptyRouteText:Show()
    else
        self.emptyRouteReset:Hide(); self.emptyRouteText:Hide()
    end
    self.routeOffset = Clamp(math.floor(self.routeOffset), 0, math.max(0, count - ROUTE_ROWS))
    for i, row in ipairs(self.routeRows) do
        local choice = self.routeChoices[self.routeOffset + i]
        row.choice = choice
        if choice then
            row.title:SetText(Text(choice.title, choice.id))
            row.summary:SetText(Text(choice.summary))
            row.selected = self.view and (self.view.routeID
                and choice.id == self.view.routeID
                or not self.view.routeID and choice.title == self.view.routeTitle)
            row:SetBackdropBorderColor(unpack(row.selected and COLORS.gold or COLORS.border))
            row.title:SetTextColor(unpack(row.selected and COLORS.gold or COLORS.text))
            row:Show()
        else
            row:Hide()
        end
    end
    self.routeCount:SetText(count == 0 and "No routes available" or (self.routeOffset + 1 .. "-" .. math.min(count, self.routeOffset + ROUTE_ROWS) .. " of " .. count .. "  |  Scroll"))
    EnableButton(self.routeUp, self.routeOffset > 0)
    EnableButton(self.routeDown, self.routeOffset + ROUTE_ROWS < count)
end

function UI:ScrollRoutes(delta)
    self.routeOffset = self.routeOffset + delta
    self:RefreshRouteRows()
end

function UI:ToggleRoutes()
    if self.routePicker:IsShown() then self.routePicker:Hide(); return end
    self:ShowRoutes()
end

function UI:ShowRoutes()
    self:Show()
    local choices = Call(self, "GetRouteChoices")
    self.routeChoices = type(choices) == "table" and choices or {}
    self.routeOffset = 0
    if self.view and self.view.routeID then
        for i, route in ipairs(self.routeChoices) do
            if route.id == self.view.routeID then self.routeOffset = math.max(0, i - ROUTE_ROWS); break end
        end
    end
    self:RefreshRouteRows()
    self.routePicker:Show()
end

function UI:Show() self.frame:Show() end
function UI:Hide() self.frame:Hide() end
function UI:IsShown() return self.frame:IsShown() end

function UI:SetScale(scale)
    self.frame:SetScale(Clamp(scale, .7, 1.5))
    if self.view then self:Render(self.view) end
end

function UI:SetPosition(point, x, y)
    local points = { TOP = true, TOPLEFT = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true, BOTTOM = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }
    point = points[point] and point or "RIGHT"
    self.frame:ClearAllPoints()
    self.frame:SetPoint(point, UIParent, point, Number(x) or -40, Number(y) or 0)
end

function UI:GetPosition()
    local point, _, _, x, y = self.frame:GetPoint(1)
    return point, x, y
end

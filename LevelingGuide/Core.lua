-- SobiLevel Forever: WoW Forever API adapter and automatic startup.
-- Copyright (c) 2026 SobiLevel Forever contributors. GPL-3.0-only.
local addonName, ns = ...
local Controller = { version = "0.3.4-beta", dirty = false, recentTurnIns = {}, requestedQuests = {} }
ns.Controller = Controller
local Adapter = {}
local frame = CreateFrame("Frame")
Controller.frame = frame

local function Secret(value)
    if type(issecretvalue) == "function" then
        local ok, result = pcall(issecretvalue, value)
        return not ok or result
    end
    return false
end

local function Read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok or Secret(value) then return nil end
    return value
end

local function Field(value, key)
    if Secret(value) or type(value) ~= "table" then return nil end
    return Read(function() return value[key] end)
end

local function Number(value, fallback)
    if Secret(value) or type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then return fallback end
    return value
end

local function Text(value, fallback)
    if Secret(value) or type(value) ~= "string" then return fallback end
    return value
end

local function Boolean(value)
    if not Secret(value) and type(value) == "boolean" then return value end
    return nil
end

local function Print(message)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cffE8B65CLevelingGuide:|r " .. message)
    end
end

local function Token(fn)
    return Read(function()
        if type(fn) ~= "function" then return nil end
        local _, token = fn("player")
        return token
    end)
end

function Adapter:Character()
    return { faction = Text(Read(UnitFactionGroup, "player")), class = Text(Token(UnitClass)), race = Text(Token(UnitRace)),
        level = Number(Read(UnitLevel, "player"), 1), xp = Number(Read(UnitXP, "player")), maxXP = Number(Read(UnitXPMax, "player")) }
end

function Adapter:Quest(id)
    local api = C_QuestLog or {}
    local on = Boolean(Read(api.IsOnQuest, id))
    local turned = Boolean(Read(api.IsQuestFlaggedCompleted, id))
    local complete = Boolean(Read(api.IsComplete, id))
    if Controller.recentTurnIns[id] then turned = true end
    local objectives, raw = {}, Read(api.GetQuestObjectives, id)
    if type(raw) == "table" and not Secret(raw) then
        local length = Number(Read(function() return #raw end), 0)
        for i = 1, math.min(100, length) do
            local objective = Field(raw, i)
            if objective then
                objectives[i] = { text = Text(Field(objective, "text")), finished = Boolean(Field(objective, "finished")),
                    numFulfilled = Number(Field(objective, "numFulfilled")), numRequired = Number(Field(objective, "numRequired")) }
            end
        end
    end
    return { on = on, turned = turned, complete = complete, objectives = objectives,
        title = Text(Read(api.GetTitleForQuestID, id)), known = on ~= nil and turned ~= nil and complete ~= nil }
end

function Adapter:AtLocation(step)
    return Controller.navigation and Controller.navigation:AtLocation(step)
end

function Adapter:DistanceTo(step)
    return Controller.navigation and Controller.navigation:DistanceTo(step)
end

function Adapter:DistanceBetween(a, b)
    return Controller.navigation and Controller.navigation:DistanceBetween(a, b)
end
function Adapter:WalkingDistanceTo(step)
    return Controller.navigation and Controller.navigation:WalkingDistanceTo(step)
end
function Adapter:WalkingDistanceBetween(a,b)
    return Controller.navigation and Controller.navigation:WalkingDistanceBetween(a,b)
end
function Adapter:ObservedQuestReward(id,level)
    local record=Controller.db and Controller.db.questRewardObservations and Controller.db.questRewardObservations[id]
    if type(record)=="table" and record.level==level then return Number(record.xp) end
end

function Adapter:ItemCount(id)
    return C_Item and Number(Read(C_Item.GetItemCount, id))
end

function Adapter:Money()
    return Number(Read(GetMoney))
end

function Adapter:SkillRank(id)
    local info = C_SkillInfo and Read(C_SkillInfo.GetSkillLineInfoByID, id)
    return Number(Field(info, "rank"))
end

ns.API = Adapter
function Adapter:AlreadyTrained(character)
    return Controller.training and Controller.training:AlreadyTrained(character) or false
end

local function NormalizeSavedVariables()
    if type(SobiLevelForeverDB) ~= "table" then SobiLevelForeverDB = {} end
    if type(SobiLevelForeverProgress) ~= "table" then SobiLevelForeverProgress = {} end
    local db = SobiLevelForeverDB
    db.schema = 1
    db.scale = math.max(.7, math.min(1.5, Number(db.scale, 1)))
    if type(db.position) ~= "table" then db.position = { point = "RIGHT", x = -40, y = 0 } end
    db.hidden = db.hidden == true
    -- Apply the requested training reminder preference once, without rewinding.
    if not SobiLevelForeverProgress.trainingReminderEnabledV1 then
        if type(SobiLevelForeverProgress.options) ~= "table" then SobiLevelForeverProgress.options = {} end
        SobiLevelForeverProgress.options.training = true
        SobiLevelForeverProgress.trainingReminderEnabledV1 = true
    end
    Controller.db, Controller.progress = db, SobiLevelForeverProgress
    if not SobiLevelForeverProgress.xpPriorityEnabledV1 then
        if type(SobiLevelForeverProgress.options)~="table" then SobiLevelForeverProgress.options={} end
        SobiLevelForeverProgress.options.speedLeveling=true
        SobiLevelForeverProgress.xpPriorityEnabledV1=true
    end
end

function Controller:SavePosition(point, x, y)
    self.db.position = { point = Text(point, "RIGHT"), x = Number(x, -40), y = Number(y, 0) }
end

function Controller:IsRunning()
    return self.initialized and not self.progress.paused and not self.db.hidden
end

function Controller:SetArrow(display)
    self.ui:SetArrow(display)
    if self.floatingArrow then self.floatingArrow:Update(display,self:IsRunning()) end
end

function Controller:UpdateNavigation()
    if self:IsRunning() then
        local step = self.engine:GetActionStep()
        if ns.Guidance then step = ns.Guidance.Resolve(self.engine:GetRoute(), step, self.engine.character) end
        self.navigation:UpdateTarget(step)
    else
        self.navigation:Stop()
    end
end

function Controller:Refresh()
    if not self.initialized then return end
    self.dirty = false
    local view = self.engine:Refresh()
    self.view = view
    self:UpdateNavigation()
    if ns.Guidance then
        local step = ns.Guidance.Resolve(self.engine:GetRoute(), self.engine:GetActionStep(), self.engine.character)
        ns.Guidance.Describe(step, view, step and step.questID and self.engine:Quest(step.questID))
    end
    self.ui:Render(view)
    self:SetArrow(self.progress.paused and { visible = false, unavailable = true, label = "Paused", text = "Paused" }
        or self.navigation:GetDisplay())
    local step = self.engine:GetStep()
    if step and step.questID and not self.requestedQuests[step.questID] and C_QuestLog then
        self.requestedQuests[step.questID] = true
        Read(C_QuestLog.RequestLoadQuestByID, step.questID)
    end
end

function Controller:Next()
    self.engine:Next(false)
    self:Refresh()
end

function Controller:Skip()
    self.engine:Next(true)
    self:Refresh()
end

function Controller:Prev()
    self.engine:Prev()
    self:Refresh()
end

function Controller:TogglePause()
    self:SetPaused(not self.progress.paused)
end

function Controller:SetPaused(paused)
    self.engine:SetPaused(paused)
    self:Refresh()
    if not paused and not self.db.hidden then self.navigation:Resume() end
end

function Controller:ChooseRoute(id)
    if self.engine:ChooseRoute(id) then
        self.db.hidden = false
        self.ui:Show()
        self:Refresh()
    end
end

function Controller:GetRouteChoices()
    return self.engine:GetRouteChoices()
end

function Controller:HideUI()
    self.db.hidden = true
    self.ui:Hide()
    if self.floatingArrow then self.floatingArrow:Hide() end
    self.navigation:Stop()
    Print("Guide hidden. Use /lg to show it again; your progress is saved.")
end

function Controller:ShowUI()
    self.db.hidden = false
    self.ui:Show()
    self:Refresh()
end

function Controller:OpenMap()
    local step = self.engine:GetActionStep()
    if ns.Guidance then step = ns.Guidance.Resolve(self.engine:GetRoute(), step, self.engine.character) end
    if not WorldMapFrame then Read(ToggleWorldMap) end
    if WorldMapFrame then
        Read(WorldMapFrame.Show, WorldMapFrame)
        if step and step.uiMapID then Read(WorldMapFrame.SetMapID, WorldMapFrame, step.uiMapID) end
    end
end

function Controller:DiagnosticText()
    local character, step, route = Adapter:Character(), self.engine:GetStep(), self.engine:GetRoute()
    local chapter = self.engine:Chapter()
    local build = Read(function()
        if not GetBuildInfo then return "unavailable" end
        local version, number, date, toc = GetBuildInfo()
        return tostring(version) .. " / " .. tostring(number) .. " / " .. tostring(toc) .. " / " .. tostring(date)
    end) or "unavailable"
    local mapID = C_Map and Number(Read(C_Map.GetBestMapForUnit, "player"))
    local lines = { "LevelingGuide " .. self.version, "Client: " .. build,
        "Character: " .. (character.faction or "?") .. " " .. (character.race or "?") .. " " .. (character.class or "?") .. " level " .. character.level,
        "Route: " .. (route and route.id or "none"),
        "Step: " .. (chapter and chapter.index or 0) .. " / " .. (route and #route.steps or 0),
        "Step ID: " .. (step and step.id or "none"), "Kind: " .. (step and step.kind or "none"),
        "Quest: " .. (step and step.questID or "none"), "Current map: " .. (mapID or "unknown"),
        "Waypoint map: " .. (step and step.uiMapID or "none"), "Coordinate frame: " .. (step and step.coordFrame or "none"),
        "Paused: " .. tostring(self.progress.paused), "Hidden: " .. tostring(self.db.hidden),
        "Group steps: " .. tostring(self.progress.options.group == true), "Dungeon steps: " .. tostring(self.progress.options.dungeons == true),
        "Guide source: Polestar " .. (ns.Data.provenance and ns.Data.provenance.commit or "unknown"),
        "Validation: local checks only; no live-client certification." }
    if step and step.questID then
        local q = Adapter:Quest(step.questID)
        lines[#lines + 1] = "Quest state: on=" .. tostring(q.on) .. ", complete=" .. tostring(q.complete) .. ", turnedIn=" .. tostring(q.turned)
        for i, objective in pairs(q.objectives) do
            lines[#lines + 1] = "Objective " .. i .. ": " .. tostring(objective.numFulfilled) .. "/" .. tostring(objective.numRequired)
                .. " finished=" .. tostring(objective.finished)
        end
    end
    local nav = self.navigation:GetDisplay()
    lines[#lines + 1] = "Navigation: " .. (nav.label or "none") .. "; unavailable=" .. tostring(nav.unavailable)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "What happened: [describe here]"
    lines[#lines + 1] = "Expected result: [describe here]"
    lines[#lines + 1] = "This report stays local until you copy and send it."
    return table.concat(lines, "\n")
end

function Controller:CreateReportWindow()
    local panel = CreateFrame("Frame", "SobiLevelForeverReport", UIParent, "BackdropTemplate")
    self.reportWindow = panel
    panel:SetSize(560, 420)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    panel:SetBackdropColor(.025, .039, .063, .99)
    panel:SetBackdropBorderColor(.52, .40, .20, 1)
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 18, -16)
    title:SetText("SobiLevel Forever - local test report")
    local instructions = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    instructions:SetPoint("TOPLEFT", 18, -39)
    instructions:SetWidth(520)
    instructions:SetJustifyH("LEFT")
    instructions:SetText("Ctrl+A, Ctrl+C to copy. Add what happened before sending it to your tester.")
    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 18, -68)
    scroll:SetPoint("BOTTOMRIGHT", -36, 48)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetWidth(490)
    edit:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
    edit:SetMaxLetters(30000)
    local measure = panel:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
    measure:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    measure:SetWidth(490)
    measure:SetWordWrap(true)
    measure:SetAlpha(0)
    edit:SetScript("OnEscapePressed", function(box) box:ClearFocus(); panel:Hide() end)
    edit:SetScript("OnTextChanged", function(box)
        measure:SetText(Text(Read(box.GetText, box), ""))
        local height = Number(Read(measure.GetStringHeight, measure), 260)
        box:SetHeight(math.max(260, height + 20))
    end)
    scroll:SetScrollChild(edit)
    panel.edit = edit
    local close = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    close:SetSize(90, 24)
    close:SetPoint("BOTTOMRIGHT", -18, 12)
    close:SetText("Close")
    close:SetScript("OnClick", function() edit:ClearFocus(); panel:Hide() end)
    panel:SetScript("OnHide", function() edit:ClearFocus() end)
    if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = "SobiLevelForeverReport" end
    panel:Hide()
end

function Controller:Report()
    if not self.reportWindow then self:CreateReportWindow() end
    local report = self:DiagnosticText()
    self.progress.lastReport = report
    self.reportWindow.edit:SetText(report)
    self.reportWindow:Show()
    self.reportWindow.edit:SetFocus()
    self.reportWindow.edit:HighlightText()
end

function Controller:ConfirmReset()
    if not StaticPopupDialogs or not StaticPopup_Show then
        Print("Reset dialog is unavailable. Your progress has been kept.")
        return
    end
    StaticPopupDialogs.SOBILEVEL_FOREVER_RESET = {
        text = "Reset LevelingGuide for this character? This clears manual skips and guide position, then selects a route using your level and active quests. Completed game quests are kept.",
        button1 = "Reset guide", button2 = "Cancel", timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        OnAccept = function()
            self.recentTurnIns, self.requestedQuests = {}, {}
            self.engine:Reset()
            self:ShowUI()
            Print("Guide progress reset for this character.")
        end,
    }
    StaticPopup_Show("SOBILEVEL_FOREVER_RESET")
end

function Controller:Slash(message)
    if not self.initialized then Print("Waiting for character login."); return end
    local command, argument = (message or ""):match("^%s*(%S*)%s*(.-)%s*$")
    command, argument = (command or ""):lower(), (argument or ""):lower()
    if command == "" or command == "show" then self:ShowUI()
    elseif command == "hide" then self:HideUI()
    elseif command == "pause" then self:SetPaused(true)
    elseif command == "resume" then self:ShowUI(); self:SetPaused(false)
    elseif command == "routes" then self:ShowUI(); self.ui:ShowRoutes()
    elseif command == "sync" then self.engine:Sync(); self:Refresh()
    elseif command == "report" or command == "debug" then self:Report()
    elseif command == "reset" then self:ConfirmReset()
    elseif command == "scale" then
        local scale = tonumber(argument)
        if scale and scale >= .7 and scale <= 1.5 then
            self.db.scale = scale
            self.ui:SetScale(scale)
        else Print("Use /lg scale 0.7 to 1.5 (for example: /lg scale 1.1).") end
    elseif command == "smart" then
        if argument == "on" or argument == "off" then
            self.engine:SetOption("smartRoute", argument == "on")
            self:Refresh()
            Print("Nearby quest routing " .. (argument == "on" and "enabled." or "disabled."))
        else Print("Use /lg smart on or /lg smart off.") end
    elseif command == "speed" then
        if argument=="on" or argument=="off" then
            self.engine:SetOption("speedLeveling",argument=="on");self:Refresh()
            Print("Speed guide "..(argument=="on" and "enabled." or "disabled."))
        else Print("Use /lg speed on or /lg speed off.") end
    elseif command == "group" or command == "dungeons" or command == "training" then
        if argument == "on" or argument == "off" then
            self.engine:SetOption(command, argument == "on")
            self:Refresh()
            Print((command == "group" and "Group" or command == "training" and "Training" or "Dungeon") .. " steps " .. (argument == "on" and "enabled." or "disabled."))
        else Print("Use /lg " .. command .. " on or /lg " .. command .. " off.") end
    else
        Print("/lg show, hide, pause, resume, routes, sync, report, reset, scale 0.7-1.5, group on|off, dungeons on|off, training on|off, smart on|off, speed on|off")
    end
end

function Controller:Initialize()
    if self.initialized then return end
    NormalizeSavedVariables()
    if not ns.Engine or not ns.Navigation or not ns.UI or not ns.Data or not ns.Data.routes then
        Print("Some addon files are missing. Reinstall the complete LevelingGuide folder.")
        return
    end
    self.navigation = ns.Navigation.New(self.progress)
    if ns.Training then self.training=ns.Training.New(self.progress) end
    self.engine = ns.Engine.New(ns.Data, self.progress, Adapter)
    self.ui = ns.UI.New(self)
    if ns.FloatingArrow then self.floatingArrow=ns.FloatingArrow.New(self.db) end
    self.ui:SetScale(self.db.scale)
    self.ui:SetPosition(self.db.position.point, self.db.position.x, self.db.position.y)
    if ns.MinimapLauncher then self.minimapButton=ns.MinimapLauncher.New(self,self.db) end
    self.initialized = true
    self.engine:Start()
    self:Refresh()
    if self.db.hidden then self.ui:Hide() else self.ui:Show() end
    if not self.db.welcomed then
        self.db.welcomed = true
        Print("Guide ready. /lg speed on enables core-quest routing. Training reminders include a Skip button.")
    end
end

SLASH_SOBILEVELFOREVER1 = "/slf"
SLASH_SOBILEVELFOREVER2 = "/sobilevel"
SLASH_SOBILEVELFOREVER3 = "/lg"
SlashCmdList.SOBILEVELFOREVER = function(message) Controller:Slash(message) end

local events = { "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT", "QUEST_ACCEPTED",
    "QUEST_TURNED_IN", "QUEST_REMOVED", "QUEST_LOG_UPDATE", "QUEST_WATCH_UPDATE", "QUEST_DATA_LOAD_RESULT",
    "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE", "UNIT_INVENTORY_CHANGED", "BAG_UPDATE_DELAYED", "PLAYER_MONEY",
    "SKILL_LINES_CHANGED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "PLAYER_MAP_CHANGED",
    "USER_WAYPOINT_UPDATED", "SUPER_TRACKING_CHANGED", "PLAYER_REGEN_ENABLED",
    "TRAINER_SHOW", "TRAINER_UPDATE", "TRAINER_CLOSED", "TRAINER_SERVICE_INFO_NAME_UPDATE", "SPELLS_CHANGED" }
for _, event in ipairs(events) do frame:RegisterEvent(event) end

frame:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "ADDON_LOADED" then
        if arg1 == addonName then
            NormalizeSavedVariables()
            if Read(IsLoggedIn) == true then Controller:Initialize() end
        end
        return
    elseif event == "PLAYER_LOGIN" then Controller:Initialize(); return end
    if not Controller.initialized then return end
    if Controller.training then Controller.training:OnEvent(event) end
    if event == "PLAYER_LOGOUT" then
        local point, x, y = Controller.ui:GetPosition()
        Controller:SavePosition(point, x, y)
        Controller.navigation:Stop()
        return
    elseif event == "USER_WAYPOINT_UPDATED" then Controller.navigation:OnWaypointChanged(); return
    elseif event == "SUPER_TRACKING_CHANGED" then Controller.navigation:OnSuperTrackingChanged(); return
    elseif event == "QUEST_TURNED_IN" then
        local id = Number(arg1)
        if id then
            Controller.recentTurnIns[id] = true
            Controller.progress.completedQuests[id] = true
            local xp=Number(arg2)
            local rewardLevel=Number(Read(UnitLevel,"player"))
            if xp and xp>=0 and rewardLevel==Controller.engine.character.level then
                if type(Controller.db.questRewardObservations)~="table" then Controller.db.questRewardObservations={} end
                Controller.db.questRewardObservations[id]={xp=xp,level=rewardLevel}
            end
            local policy=Controller.engine.speedPolicy
            if Controller.training and policy and policy.records[id] and policy.records[id].classQuest then Controller.training:Invalidate() end
        end
        Controller:Refresh()
        return
    elseif event == "QUEST_ACCEPTED" then
        local id = Number(arg1) -- Forever sends questID as the first and only quest argument.
        if id then
            Controller.recentTurnIns[id] = nil
            Controller.progress.completedQuests[id] = nil
            for key in pairs(Controller.progress.visitedTaskAreas or {}) do
                if type(key) == "string" and key:sub(1, #tostring(id) + 1) == tostring(id) .. ":" then
                    Controller.progress.visitedTaskAreas[key] = nil
                end
            end
        end
    elseif event == "QUEST_REMOVED" then
        -- Abandonment is not completion. Re-read the log without inventing a reward.
    elseif (event == "UNIT_INVENTORY_CHANGED" or event == "PLAYER_XP_UPDATE") and arg1 ~= "player" then return end
    Controller.dirty = true
end)

local arrowElapsed, refreshElapsed = 0, 0
frame:SetScript("OnUpdate", function(_, elapsed)
    if not Controller.initialized then return end
    arrowElapsed, refreshElapsed = arrowElapsed + elapsed, refreshElapsed + elapsed
    if refreshElapsed >= .25 and (Controller.dirty or (Controller:IsRunning() and refreshElapsed >= 1)) then
        refreshElapsed = 0
        Controller:Refresh()
    end
    if arrowElapsed >= .1 then
        arrowElapsed = 0
        if Controller:IsRunning() and Controller.ui:IsShown() then Controller:SetArrow(Controller.navigation:GetDisplay()) end
    end
end)

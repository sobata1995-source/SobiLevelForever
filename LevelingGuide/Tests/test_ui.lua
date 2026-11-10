-- UI behavior smoke tests. These mocks do not validate live WoW rendering.
unpack = table.unpack or unpack
local count = 0
local function check(value, message)
    assert(value, message)
    count = count + 1
end

local methods = {}
local function region(kind, parent)
    return setmetatable({ kind = kind, parent = parent, shown = true, enabled = true,
        scripts = {}, width = 100, height = 20, points = {}, scale = 1 }, { __index = function(_, key)
        assert(methods[key], "Unexpected UI API: " .. tostring(key))
        return methods[key]
    end })
end
function methods:SetSize(w, h) self.width, self.height = w, h end
function methods:SetWidth(w) self.width = w end
function methods:SetHeight(h) self.height = h end
function methods:SetPoint(...) self.points[1] = {...} end
function methods:ClearAllPoints() self.points = {} end
function methods:GetPoint()
    local p = self.points[1] or {"CENTER", UIParent, "CENTER", 0, 0}
    if type(p[2]) == "number" then return p[1], self.parent, p[1], p[2], p[3] end
    return unpack(p)
end
function methods:SetAllPoints(target) self.anchor = target end
function methods:Show() self.shown = true end
function methods:Hide()
    local wasShown = self.shown
    self.shown = false
    if wasShown and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods:IsShown() return self.shown end
function methods:SetFrameStrata(value) self.strata = value end
function methods:SetClampedToScreen(value) self.clamped = value end
function methods:SetMovable(value) self.movable = value end
function methods:EnableMouse(value) self.mouse = value end
function methods:EnableMouseWheel(value) self.wheel = value end
function methods:RegisterForDrag(...) self.dragButtons = {...} end
function methods:StartMoving() self.moving = true end
function methods:StopMovingOrSizing() self.moving = false end
function methods:SetBackdrop(value) self.backdrop = value end
function methods:SetBackdropColor(...) self.background = {...} end
function methods:SetBackdropBorderColor(...) self.border = {...} end
function methods:SetTextColor(...) self.color = {...} end
function methods:SetJustifyH(value) self.justifyH = value end
function methods:SetJustifyV(value) self.justifyV = value end
function methods:SetText(value) self.textValue = value end
function methods:SetWordWrap(value) self.wordWrap = value end
function methods:SetNonSpaceWrap(value) self.nonSpaceWrap = value end
function methods:SetSpacing(value) self.spacing = value end
function methods:GetStringHeight()
    return math.max(1, math.ceil(#(self.textValue or "") / math.max(1, self.width / 7))) * 16
end
function methods:CreateFontString() return region("FontString", self) end
function methods:CreateTexture() return region("Texture", self) end
function methods:SetColorTexture(...) self.fill = {...} end
function methods:SetTexture(value) self.texture = value end
function methods:SetVertexColor(...) self.vertexColor = {...} end
function methods:SetRotation(value) self.rotation = value end
function methods:SetScript(name, callback) self.scripts[name] = callback end
function methods:IsEnabled() return self.enabled end
function methods:SetEnabled(value) self.enabled = value end
function methods:SetAlpha(value) self.alpha = value end
function methods:SetStatusBarTexture(value) self.statusTexture = value end
function methods:SetStatusBarColor(...) self.statusColor = {...} end
function methods:SetMinMaxValues(low, high) self.minimum, self.maximum = low, high end
function methods:SetValue(value) self.value = value end
function methods:SetScrollChild(value) self.scrollChild = value end
function methods:SetVerticalScroll(value) self.scrollOffset = value end
function methods:GetVerticalScroll() return self.scrollOffset or 0 end
function methods:SetScale(value) self.scale = value end
function methods:SetOwner(value) self.owner = value end
function methods:AddLine(value) self.detail = value end
function CreateFrame(kind, name, parent)
    local value = region(kind, parent)
    if name then _G[name] = value end
    return value
end
UIParent = region("Frame")
GameTooltip = region("GameTooltip")
local secret = setmetatable({}, {__tostring = function() error("Secret string conversion") end})
function issecretvalue(value) return value == secret end

local ns = {}
assert(loadfile("LevelingGuide/UI.lua"))("LevelingGuide", ns)
local controller = { calls = {}, routes = {} }
for _, method in ipairs({"Prev", "Next", "Skip", "TogglePause", "ChooseRoute", "HideUI", "Report", "ConfirmReset", "SavePosition", "OpenMap"}) do
    controller[method] = function(self, ...) self.calls[#self.calls + 1] = {method, ...} end
end
function controller:GetRouteChoices() return self.routes end
for i = 1, 23 do controller.routes[i] = { id = "r" .. i, title = "Route " .. i, summary = "Levels " .. i } end
local ui = ns.UI.New(controller)
check(ui.frame.width == 400 and ui.frame.height == 416, "Window dimensions")
check(ui.modeBadge.textValue == "GUIDE", "Unknown initial tracking must not say AUTO")

local view = { routeID = "r1", routeTitle = "Starter", stepIndex = 1, totalSteps = 10,
    playerLevel = 4, stepKind = "goto", stepText = "Travel to the village.",
    stepHint = "Source route requires in-game validation.", progress = .2, status = "Ready", autoActive = true }
ui:Render(view)
check(ui.stepKind.textValue == "TRAVEL", "goto kind label")
check(ui.progress.value == .2 and ui.subtitle.textValue == "Level 4  |  Step 1 / 10", "Progress/level display")
check(not ui.prevButton.enabled and ui.nextButton.enabled, "First-step controls")
check(ui.modeBadge.textValue == "AUTO", "Explicit active automatic mode")
view.manual = true; ui:Render(view)
check(ui.nextButton.text.textValue == "Done" and ui.modeBadge.textValue == "GUIDE", "Manual step badge and Done")
view.manualReview = true; ui:Render(view)
check(ui.modeBadge.textValue == "REVIEW", "Review state is explicit")
view.paused = true; ui:Render(view)
check(ui.modeBadge.textValue == "PAUSED" and ui.pauseButton.text.textValue == "Resume", "Paused state")

view.stepText = string.rep("A long step that needs scrolling. ", 30)
view.stepIndex = 3; ui:Render(view)
check(ui.maxScroll > 0, "Long text uses scrollable body")
ui:SetBodyScroll(99999)
check(ui.bodyScroll:GetVerticalScroll() == ui.maxScroll, "Scroll upper limit")
view.stepIndex = 4; ui:Render(view)
check(ui.bodyScroll:GetVerticalScroll() == 0, "Mutated caller view still resets scrolling on next step")
view.stepText = "Short step."; view.playerLevel = secret; ui:Render(view)
check(ui.maxScroll == 0 and not ui.scrollThumb:IsShown(), "Short text hides scroll marker")
check(not ui.subtitle.textValue:find("Level", 1, true), "Restricted level is not coerced to text")
view.complete = true; ui:Render(view)
check(not ui.nextButton.enabled and not ui.skipButton.enabled, "Completed route controls")

ui.prevButton.scripts.OnClick(ui.prevButton)
check(controller.calls[#controller.calls][1] == "Prev", "Previous callback")
ui.pauseButton.scripts.OnClick(ui.pauseButton)
check(controller.calls[#controller.calls][1] == "TogglePause", "Pause callback")
ui.reportButton.scripts.OnClick(ui.reportButton)
check(controller.calls[#controller.calls][1] == "Report", "Report callback")
ui.resetButton.scripts.OnClick(ui.resetButton)
check(controller.calls[#controller.calls][1] == "ConfirmReset", "Reset requests confirmation")
ui.routeChoices = {}; ui:RefreshRouteRows()
check(ui.emptyRouteReset:IsShown() and ui.emptyRouteText:IsShown(), "Empty routes offers recovery")
ui.emptyRouteReset.scripts.OnClick(ui.emptyRouteReset)
check(controller.calls[#controller.calls][1] == "ConfirmReset", "Empty route reset requests confirmation")

ui:Hide(); ui:ShowRoutes()
check(ui.frame:IsShown() and ui.routePicker:IsShown(), "ShowRoutes opens hidden window")
check(ui.routeRows[1].choice.id == "r1" and ui.routeRows[8].choice.id == "r8", "First eight route rows")
ui:ScrollRoutes(99)
check(ui.routeOffset == 15 and ui.routeRows[8].choice.id == "r23", "All routes reachable and scroll clamped")
ui.routeRows[8].scripts.OnClick(ui.routeRows[8])
check(controller.calls[#controller.calls][1] == "ChooseRoute" and controller.calls[#controller.calls][2] == "r23", "Route ID callback")
check(not ui.routePicker:IsShown(), "Selection closes picker")
controller.routes = {{id = "s1", title = "Silithus"}, {id = "s2", title = "Silithus"}}
view.routeID, view.routeTitle = "s2", "Silithus"
ui:Render(view); ui:ShowRoutes()
check(not ui.routeRows[1].selected and ui.routeRows[2].selected, "Duplicate chapter titles selected strictly by route ID")
controller.routes = {}; ui:ShowRoutes()
check(ui.routeCount.textValue == "No routes available" and not ui.routeRows[1]:IsShown(), "Empty route list")
ui:Hide()
check(not ui.routePicker:IsShown(), "Hiding main window hides picker")

ui:SetArrow({visible = true, rotation = 1.2, distance = 1540, label = "Village"})
check(ui.arrow:IsShown() and ui.arrow.rotation == 1.2 and ui.distance.textValue == "1.5k yd", "Arrow and distance")
ui:SetArrow({visible = true, rotation = 0, distance = 3, arrived = true})
check(ui.arrowLabel.textValue == "HERE" and ui.distance.textValue == "3 yd", "Arrival display")
ui:SetArrow({visible = false, unavailable = true, text = "Open map"})
check(not ui.arrow:IsShown() and ui.distance.textValue == "MAP", "Cross-map/unavailable arrow")
ui:SetArrow({visible = false, unavailable = true, crossZone = true, text = "Travel to a very long zone name"})
check(ui.distance.textValue == "MAP" and ui.navHint:find("very long zone", 1, true), "Long map instructions stay in tooltip")
ui:SetArrow({visible = false, unavailable = true, text = "Source 51.0, 30.0. Coordinates unverified on Forever."})
check(ui.distance.textValue == "CHECK" and ui.navHint:find("Coordinates unverified", 1, true), "Source coordinates stay in tooltip")
ui:SetArrow({visible = false, unavailable = false, arrived = true, distance = 2})
check(ui.arrowLabel.textValue == "HERE" and not ui.arrow:IsShown(), "Arrival without arrow still says HERE")
ui.arrowFrame.scripts.OnMouseUp(ui.arrowFrame, "LeftButton")
check(controller.calls[#controller.calls][1] == "OpenMap", "Waypoint box opens map")
ui:SetArrow({rotation = secret, distance = secret})
check(not ui.arrow:IsShown() and ui.distance.textValue == "READ", "Restricted navigation inputs stay unknown")
ui:SetScale(.1); check(ui.frame.scale == .7, "Minimum scale")
ui:SetScale(9); check(ui.frame.scale == 1.5, "Maximum scale")
ui:SetPosition("TOPLEFT", 20, -50)
local point, x, y = ui:GetPosition()
check(point == "TOPLEFT" and x == 20 and y == -50, "Position restore")
ui.header.scripts.OnDragStop(ui.header)
local saved = controller.calls[#controller.calls]
check(saved[1] == "SavePosition" and saved[2] == "TOPLEFT" and saved[3] == 20 and saved[4] == -50, "Position persistence callback")
print("PASS UI smoke checks: " .. count)

ui:SetArrow({inventoryOnly=true,visible=false,unavailable=true,text="Use item"})
check(ui.arrowLabel.textValue == "BAGS" and ui.distance.textValue == "USE ITEM", "Bag action has explicit label")
ui:SetArrow({areaOnly=true,visible=false,unavailable=false,text="Stay with escort"})
check(ui.arrowLabel.textValue == "EVENT" and ui.distance.textValue == "FOLLOW", "Event marker explains next action")

ui:Render({stepIndex=1,totalSteps=10,playerLevel=6,areaTasks={{},{}},canNext=false})
check(ui.subtitle.textValue=="Level 6  |  2 nearby tasks", "Show grouped route status")
check(not ui.nextButton.enabled, "Prevent Next from completing unrelated source task")

assert(loadfile("LevelingGuide/FloatingArrow.lua"))("LevelingGuide",ns)
local arrowSettings={}
local floating=ns.FloatingArrow.New(arrowSettings)
floating:Update({visible=true,walking=true,rotation=1,distance=123},true)
check(floating.frame:IsShown(),"Floating walking arrow shown above player")
floating:Update({visible=true,rotation=1,distance=123},false)
check(not floating.frame:IsShown(),"Minimizing/pausing hides the floating arrow")
floating.frame.scripts.OnDragStop()
check(arrowSettings.arrowPosition~=nil,"Floating arrow position saved")

check(ui.routePicker.background[4]==1 and ui.routePicker.backdrop.bgFile=="Interface\\Buttons\\WHITE8X8","Routes fully masks underlying guide text")
for i,row in ipairs(ui.routeRows) do
 local titleTop=-row.title.points[1][3]
 local summaryTop=-row.summary.points[1][3]
 check(titleTop+row.title.height<=summaryTop,"Route name and levels have separate lines")
 check(summaryTop+row.summary.height<=row.height,"Route summary stays within its row")
 if i>1 then check(math.abs(row.points[1][3]-ui.routeRows[i-1].points[1][3])>=row.height,"Route rows do not overlap") end
end

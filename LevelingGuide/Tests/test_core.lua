-- Core integration regressions: real data + real Engine, minimal UI/Nav doubles.
-- Checks event contracts and local state; does not simulate the live WoW client.
local checks = 0
local function eq(label, actual, expected)
    checks = checks + 1
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function yes(label, value) eq(label, not not value, true) end
local function contains(label, text, part) yes(label, type(text) == "string" and text:find(part, 1, true)) end
local bundled = {}
assert(loadfile("LevelingGuide/Data/Routes.lua"))("LevelingGuide", bundled)
local secret = setmetatable({}, {__tostring = function() error("Attempted to stringify secret") end})

local function Harness(options)
    options = options or {}
    local model = { events = {}, requests = {}, quests = {}, items = {}, skills = {}, messages = {}, networkCalls = 0,
        loggedIn = options.loggedIn == true, character = options.character or {faction = "Alliance", race = "Human", class = "HUNTER", level = 1, xp = 0, maxXP = 100} }
    SobiLevelForeverDB = options.db
    SobiLevelForeverProgress = options.progress or {options={training=true}}
    SlashCmdList, UISpecialFrames = {}, {}
    DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) model.messages[#model.messages+1] = text end }
    function issecretvalue(value) return value == secret end
    function IsLoggedIn() return model.loggedIn end
    function UnitFactionGroup(unit) assert(unit == "player"); return model.character.faction end
    function UnitClass(unit) assert(unit == "player"); return "Localized class", model.character.class, 3 end
    function UnitRace(unit) assert(unit == "player"); return "Localized race", model.character.race, 1 end
    function UnitLevel(unit) assert(unit == "player"); return model.character.level end
    function UnitXP(unit) assert(unit == "player"); return model.character.xp end
    function UnitXPMax(unit) assert(unit == "player"); return model.character.maxXP end
    function GetMoney() return model.money or 0 end
    function GetBuildInfo() return "1.60.1", "70862", "Nov 7 2026", 16001 end
    C_Map = {GetBestMapForUnit = function(unit) assert(unit == "player"); return model.map or 1429 end}
    C_Item = {GetItemCount = function(id) return model.items[id] or 0 end}
    C_SkillInfo = {GetSkillLineInfoByID = function(id) return model.skills[id] end}
    local function q(id) return model.quests[id] or {} end
    C_QuestLog = {
        IsOnQuest = function(id) if q(id).on == nil then return false end; return q(id).on end,
        IsComplete = function(id) if q(id).complete == nil then return false end; return q(id).complete end,
        IsQuestFlaggedCompleted = function(id) if q(id).turned == nil then return false end; return q(id).turned end,
        GetQuestObjectives = function(id) return q(id).objectives end,
        GetTitleForQuestID = function(id) return q(id).title end,
        RequestLoadQuestByID = function(id) model.requests[#model.requests+1] = id end,
    }
    function CreateFrame(kind)
        assert(kind == "Frame", "Only Core event frame belongs in this minimal UI harness")
        local frame = {scripts = {}, events = {}}
        function frame:SetScript(name, callback) self.scripts[name] = callback end
        function frame:RegisterEvent(name) self.events[name] = true end
        return frame
    end
    -- A report must remain local. No outbound API is needed by this addon.
    local function outbound()
        model.networkCalls = model.networkCalls + 1
        error("Core unexpectedly sent data")
    end
    SendChatMessage, SendMail = outbound, outbound
    C_ChatInfo = {SendAddonMessage = outbound, SendAddonMessageLogged = outbound}
    local ns = {Data = bundled.Data}
    assert(loadfile("LevelingGuide/Engine.lua"))("LevelingGuide", ns)
    ns.Navigation = {New = function()
        local nav = {stops = 0, updates = 0, resumes = 0}
        function nav:UpdateTarget(step) self.target = step; self.updates = self.updates + 1 end
        function nav:Stop() self.target = nil; self.stops = self.stops + 1 end
        function nav:Resume() self.resumes = self.resumes + 1 end
        function nav:AtLocation() return false end
        function nav:GetDisplay() return {visible = self.target ~= nil, unavailable = self.target == nil, label = self.target and "Target" or ""} end
        function nav:OnWaypointChanged() self.waypointEvents = (self.waypointEvents or 0) + 1 end
        function nav:OnSuperTrackingChanged() self.trackingEvents = (self.trackingEvents or 0) + 1 end
        model.nav = nav
        return nav
    end}
    ns.UI = {New = function(controller)
        local ui = {shown = false, position = {"RIGHT", -40, 0}}
        function ui:SetScale(scale) self.scale = scale end
        function ui:SetPosition(point, x, y) self.position = {point, x, y} end
        function ui:GetPosition() return table.unpack(self.position) end
        function ui:Render(view) self.view = view end
        function ui:SetArrow(display) self.arrow = display end
        function ui:Show() self.shown = true end
        function ui:Hide() self.shown = false end
        function ui:IsShown() return self.shown end
        function ui:ShowRoutes() self.routesShown = true end
        model.ui = ui
        return ui
    end}
    assert(loadfile("LevelingGuide/Core.lua"))("LevelingGuide", ns)
    model.ns, model.controller = ns, ns.Controller
    function model:event(event, ...)
        self.controller.frame.scripts.OnEvent(self.controller.frame, event, ...)
    end
    function model:tick(elapsed)
        self.controller.frame.scripts.OnUpdate(self.controller.frame, elapsed or .3)
    end
    function model:accept(id)
        self.quests[id] = self.quests[id] or {}
        self.quests[id].on = true
        self:event("QUEST_ACCEPTED", id)
        self:tick()
    end
    return model
end

-- The first character starts at a real, class-compatible source quest.
local m = Harness()
eq("Core waits for addon/login", m.controller.initialized, nil)
m:event("ADDON_LOADED", "SomeOtherAddon")
eq("other addon ignored", m.controller.initialized, nil)
m:event("ADDON_LOADED", "LevelingGuide")
eq("own addon loaded before player login defers UI", m.controller.initialized, nil)
eq("saved variable schema created", SobiLevelForeverDB.schema, 1)
yes("fresh character progress exists", type(SobiLevelForeverProgress) == "table")
m.loggedIn = true; m:event("PLAYER_LOGIN")
yes("login initializes", m.controller.initialized)
eq("Human start chosen", m.controller.progress.routeID, "forever/alliance/human/01-elwynn-forest")
eq("real first Human quest", m.controller.engine:GetStep().questID, 783)
eq("real first action", m.controller.engine:GetStep().kind, "accept")
eq("UI shown at first login", m.ui.shown, true)
eq("locale-independent class token", m.ns.API:Character().class, "HUNTER")
eq("locale-independent race token", m.ns.API:Character().race, "Human")
eq("quest title requested on first view", m.requests[1], 783)
m.controller:Refresh()
eq("quest title request deduplicated", #m.requests, 1)
eq("reward-dialog event is not a completion event", m.controller.frame.events.QUEST_COMPLETE, nil)

-- Forever QUEST_ACCEPTED sends questID as the first argument, not a log index.
m.controller.recentTurnIns[783] = true
m:accept(783)
eq("accept clears reward cache by first argument", m.controller.recentTurnIns[783], nil)
eq("accepted first quest advances to turn-in", m.controller.engine:GetStep().kind, "turnin")
eq("turn-in is still the same quest", m.controller.engine:GetStep().questID, 783)
m.quests[783].complete = true; m:event("QUEST_LOG_UPDATE"); m:tick()
eq("complete objectives/reward dialog do not turn in", m.controller.engine:GetStep().questID, 783)
m.quests[783].on, m.quests[783].complete = false, false
m:event("QUEST_REMOVED", 783, false); m:tick()
eq("QUEST_REMOVED does not advance turn-in", m.controller.engine:GetStep().questID, 783)
eq("QUEST_REMOVED does not create reward history", m.ns.API:Quest(783).turned, false)
eq("abandonment produces blocked state", m.ui.view.status, "CHECK PREREQUISITES")
m.quests[783].on, m.quests[783].complete = true, true
m:event("QUEST_TURNED_IN", 783, 40, 0)
eq("turn-in event overrides temporarily stale history API", m.ns.API:Quest(783).turned, true)
eq("actual turn-in immediately advances", m.controller.engine:GetStep().questID, 7)

-- Follow actual early source actions, preserving filters and indexed objectives.
m:accept(7); eq("next real accept", m.controller.engine:GetStep().questID, 5261)
m:accept(5261); eq("early delivery waits for turn-in", m.controller.engine:GetStep().kind, "turnin")
m:event("QUEST_TURNED_IN", 5261, 40, 0)
eq("delivery opens wolf quest", m.controller.engine:GetStep().questID, 33)
m:accept(33)
eq("Hunter skips Warlock-only accept", m.controller.engine:GetStep().questID, 33)
eq("actual wolf objective index", m.controller.engine:GetStep().objectiveIndex, 1)
eq("class-only source row marked filter", m.controller.engine:Chapter().marks[7], "filter")
m.quests[33].objectives = {{text = "Tough Wolf Meat", numFulfilled = 2, numRequired = 8, finished = false}}
m:event("QUEST_WATCH_UPDATE", 33); m:tick()
contains("objective update renders real progress", m.ui.view.stepHint, "2/8")
eq("partial progress does not advance", m.controller.engine:GetStep().questID, 33)
m.quests[33].objectives[1].numFulfilled = 8
m.quests[33].objectives[1].finished = true
m:event("QUEST_LOG_UPDATE"); m:tick()
eq("indexed objective advances without rewarding quest", m.controller.engine:GetStep().questID, 18)
eq("objective did not invent turn-in", m.ns.API:Quest(33).turned, false)

-- Core preserves pause and hides/releases navigation through its adapter calls.
local index = m.controller.engine:Chapter().index
m.controller:SetPaused(true)
eq("pause stops target", m.nav.target, nil)
m:accept(18)
eq("paused event keeps saved index", m.controller.engine:Chapter().index, index)
m.controller:SetPaused(false)
eq("resume catches up real accept", m.controller.engine:GetStep().kind, "train")
yes("resume calls navigation resume", m.nav.resumes > 0)
m.controller:HideUI()
eq("hide stores preference", m.controller.db.hidden, true)
eq("hide stops navigation target", m.nav.target, nil)
eq("hide hides window", m.ui.shown, false)
m.controller:ShowUI()
eq("show restores window", m.ui.shown, true)
m:event("USER_WAYPOINT_UPDATED"); m:event("SUPER_TRACKING_CHANGED")
eq("waypoint event delegated", m.nav.waypointEvents, 1)
eq("supertracking event delegated", m.nav.trackingEvents, 1)

-- Unknown/secret answers remain unknown and never enter comparison/string logic.
m.quests[900001] = {on = secret, complete = false, turned = false, objectives = {{text = secret, numFulfilled = secret, numRequired = 2, finished = secret}}}
local unknown = m.ns.API:Quest(900001)
eq("secret on-quest state not treated as false", unknown.on, nil)
eq("secret quest state known=false", unknown.known, false)
eq("secret objective amount discarded", unknown.objectives[1].numFulfilled, nil)
eq("secret objective text discarded", unknown.objectives[1].text, nil)
m.skills[185] = {rank = 42, maxRank = 75}
eq("Forever skill attributes use rank", m.ns.API:SkillRank(185), 42)
m.items[6948] = 1
eq("C_Item inventory count read", m.ns.API:ItemCount(6948), 1)

-- Report generation stores a local copy and opens an editor without transmission.
local reportPanel = {shown = false, edit = {}}
function reportPanel:Show() self.shown = true end
function reportPanel.edit:SetText(text) self.text = text end
function reportPanel.edit:SetFocus() self.focused = true end
function reportPanel.edit:HighlightText() self.highlighted = true end
m.controller.reportWindow = reportPanel
m.controller:Report()
eq("report stored per character", m.controller.progress.lastReport, reportPanel.edit.text)
contains("report identifies exact source", reportPanel.edit.text, bundled.Data.provenance.commit)
contains("report states local handling", reportPanel.edit.text, "This report stays local")
yes("report editor shown", reportPanel.shown and reportPanel.edit.focused and reportPanel.edit.highlighted)
eq("report never transmits", m.networkCalls, 0)

-- A reload uses the same saved progress; it does not restart at step one.
m.controller:SetPaused(true); m.controller:HideUI()
m.ui.position = {"TOPLEFT", 17, -29}
m:event("PLAYER_LOGOUT")
eq("logout saves window position", m.controller.db.position.point, "TOPLEFT")
eq("logout saves x", m.controller.db.position.x, 17)
local savedDB, savedProgress = m.controller.db, m.controller.progress
local savedIndex = m.controller.engine:Chapter().index
local r = Harness({db = savedDB, progress = savedProgress, loggedIn = true})
r:event("ADDON_LOADED", "LevelingGuide")
yes("already logged-in addon load initializes", r.controller.initialized)
eq("reload restores route", r.controller.progress.routeID, "forever/alliance/human/01-elwynn-forest")
eq("reload restores index", r.controller.engine:Chapter().index, savedIndex)
eq("reload restores pause", r.controller.progress.paused, true)
eq("reload restores hide", r.controller.db.hidden, true)
eq("hidden reload opens no window", r.ui.shown, false)
eq("paused hidden reload owns no target", r.nav.target, nil)
eq("window position restored", r.ui.position[1], "TOPLEFT")
local originalEngine = r.controller.engine
r:event("PLAYER_LOGIN")
eq("duplicate login does not rebuild engine", r.controller.engine, originalEngine)

local d = Harness({loggedIn = true, character = {faction = "Alliance", race = "NightElf", class = "DRUID", level = 1, xp = 0, maxXP = 100}})
d:event("ADDON_LOADED", "LevelingGuide")
eq("Druid race starter", d.controller.progress.routeID, "forever/alliance/nightelf/01-teldrassil")
eq("Druid first real source quest", d.controller.engine:GetStep().questID, 456)
eq("Druid starter source min level", d.controller.engine:GetStep().minLevel, 1)

print("PASS Core/API integration checks: " .. checks)

-- Reward events are durable, while accepting again clears the remembered reward.
do
    local h = Harness({loggedIn=true})
    h:event("ADDON_LOADED", "LevelingGuide")
    h:event("QUEST_TURNED_IN", 999001)
    eq("reward event persisted immediately", h.controller.progress.completedQuests[999001], true)
    h:event("QUEST_ACCEPTED", 999001)
    eq("reaccept clears prior reward ledger", h.controller.progress.completedQuests[999001], nil)
    eq("reaccept clears transient reward", h.controller.recentTurnIns[999001], nil)
end
print("PASS durable reward-event regressions")

do
 local h=Harness({loggedIn=true})
 h:event("ADDON_LOADED","LevelingGuide")
 h:event("QUEST_TURNED_IN",999123,410,0)
 eq("record real server XP reward",h.controller.db.questRewardObservations[999123].xp,410)
 eq("reward observation uses known character level",h.controller.db.questRewardObservations[999123].level,h.controller.engine.character.level)
end
print("PASS server quest-reward observations")

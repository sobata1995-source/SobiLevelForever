-- Real Core + Engine + Navigation, with only WoW APIs and rendering mocked.
-- This checks ownership and event ordering, not native client behavior.
local checks = 0
local function eq(label, actual, expected)
    checks = checks + 1
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function near(label, actual, expected)
    checks = checks + 1
    assert(type(actual) == "number" and math.abs(actual - expected) < .000001, label .. ": wrong numeric value")
end
local function Vector(x, y)
    return {x = x, y = y, GetXY = function(self) return self.x, self.y end}
end
local function Point(map, x, y, z) return {uiMapID = map, position = Vector(x, y), z = z} end
local function Copy(point)
    return point and Point(point.uiMapID, point.position.x, point.position.y, point.z)
end
local function Step(kind, quest, x)
    return {kind = kind, questID = quest, uiMapID = x and 1, x = x, y = x and .8, text = kind, coordFrame = "live"}
end
local function Harness(options)
    options = options or {}
    local m = {
        frames = {}, quests = {}, pin = Copy(options.pin), tracking = options.tracking or {kind = "none"},
        pinWrites = 0, clearCalls = 0, trackWrites = 0, renders = 0, playerMap = 1,
        playerX = .1, playerY = .1, loggedIn = false, requests = {},
    }
    function m:Event(event, arg1, arg2, arg3)
        for _, frame in ipairs(self.frames) do
            if frame.events[event] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event, arg1, arg2, arg3) end
        end
    end
    function m:Tick(seconds)
        for _, frame in ipairs(self.frames) do
            if frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame, seconds or 1) end
        end
    end
    function m:Login()
        self:Event("ADDON_LOADED", "LevelingGuide")
        self.loggedIn = true
        self:Event("PLAYER_LOGIN")
    end
    function m:ManualPin(point)
        self.pin = Copy(point)
        self:Event("USER_WAYPOINT_UPDATED")
    end
    function m:ManualQuest(id)
        self.tracking = {kind = "quest", id = id}
        self:Event("SUPER_TRACKING_CHANGED")
    end
    issecretvalue = function() return false end
    CreateFrame = function()
        local frame = {events = {}, scripts = {}}
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:SetScript(event, callback) self.scripts[event] = callback end
        m.frames[#m.frames + 1] = frame
        return frame
    end
    SlashCmdList = {}
    DEFAULT_CHAT_FRAME = {AddMessage = function() end}
    SobiLevelForeverDB, SobiLevelForeverProgress = options.db or {}, options.progress or {}
    IsLoggedIn = function() return m.loggedIn end
    UnitFactionGroup = function() return "Horde" end
    UnitClass = function() return "Hunter", "HUNTER" end
    UnitRace = function() return "Orc", "Orc" end
    UnitLevel = function() return 1 end
    UnitXP = function() return 0 end
    UnitXPMax = function() return 100 end
    GetMoney = function() return 0 end
    GetPlayerFacing = function() return 0 end
    CreateVector2D = Vector
    UiMapPoint = {CreateFromCoordinates = Point}
    C_Item = {GetItemCount = function() return 0 end}
    C_SkillInfo = {GetSkillLineInfoByID = function() return nil end}
    local function QuestField(id, key)
        local quest = m.quests[id]
        return quest and quest[key] == true or false
    end
    C_QuestLog = {
        IsOnQuest = function(id) return QuestField(id, "on") end,
        IsComplete = function(id) return QuestField(id, "complete") end,
        IsQuestFlaggedCompleted = function(id) return QuestField(id, "turned") end,
        GetQuestObjectives = function(id) return m.quests[id] and m.quests[id].objectives end,
        GetTitleForQuestID = function(id) return "Quest " .. id end,
        RequestLoadQuestByID = function(id) m.requests[id] = (m.requests[id] or 0) + 1 end,
    }
    C_Map = {
        GetUserWaypoint = function() return Copy(m.pin) end,
        CanSetUserWaypointOnMap = function() return true end,
        SetUserWaypoint = function(point)
            m.pinWrites = m.pinWrites + 1
            if m.failPin then return false end
            m.pin = Copy(point)
            m:Event("USER_WAYPOINT_UPDATED")
            return true
        end,
        ClearUserWaypoint = function()
            m.clearCalls = m.clearCalls + 1
            m.pin = nil
            m:Event("USER_WAYPOINT_UPDATED")
        end,
        GetBestMapForUnit = function() return m.playerMap end,
        GetPlayerMapPosition = function() return Vector(m.playerX, m.playerY) end,
        GetWorldPosFromMapPos = function(_, vector) return 0, Vector(1000 - vector.y * 1000, 1000 - vector.x * 1000) end,
        GetMapInfo = function(id) return {name = "Map " .. id} end,
    }
    local function Track(kind, id)
        m.trackWrites = m.trackWrites + 1
        m.tracking = {kind = kind, id = id}
        m:Event("SUPER_TRACKING_CHANGED")
    end
    C_SuperTrack = {
        IsSuperTrackingUserWaypoint = function() return m.tracking.kind == "waypoint" end,
        IsSuperTrackingQuest = function() return m.tracking.kind == "quest" end,
        IsSuperTrackingMapPin = function() return false end,
        IsSuperTrackingContent = function() return false end,
        IsSuperTrackingAnything = function() return m.tracking.kind ~= "none" end,
        GetSuperTrackedQuestID = function() return m.tracking.id end,
        SetSuperTrackedUserWaypoint = function(enabled)
            if enabled then Track("waypoint") elseif m.tracking.kind == "waypoint" then Track("none") end
        end,
        SetSuperTrackedQuestID = function(id) Track("quest", id) end,
    }
    local ns = {}
    assert(loadfile("LevelingGuide/Engine.lua"))("LevelingGuide", ns)
    assert(loadfile("LevelingGuide/Navigation.lua"))("LevelingGuide", ns)
    ns.Data = {routeOrder = {"a", "b"}, starts = {Horde = {Orc = "a"}}, routes = {
        a = {id = "a", title = "Starting route", faction = "Horde", startLevel = 1, endLevel = 10,
            steps = {Step("accept", 10, .7), Step("complete", 10, .8), Step("turnin", 10, .9), Step("note")}},
        b = {id = "b", title = "Next route", faction = "Horde", startLevel = 10, endLevel = 20,
            steps = {Step("note", nil, .6)}},
    }}
    ns.UI = {New = function()
        local ui = {shown = false, position = {"RIGHT", -40, 0}}
        function ui:SetScale(scale) self.scale = scale end
        function ui:SetPosition(point, x, y) self.position = {point, x, y} end
        function ui:GetPosition() return self.position[1], self.position[2], self.position[3] end
        function ui:Render(view) self.view = view; m.renders = m.renders + 1 end
        function ui:SetArrow(display) self.arrow = display end
        function ui:Show() self.shown = true end
        function ui:Hide() self.shown = false end
        function ui:IsShown() return self.shown end
        function ui:ShowRoutes() self.routesShown = true end
        return ui
    end}
    assert(loadfile("LevelingGuide/Core.lua"))("LevelingGuide", ns)
    m.ns, m.controller = ns, ns.Controller
    return m
end

do
    local m = Harness({pin = Point(2, .12, .34, 7), tracking = {kind = "quest", id = 42}})
    eq("no pin changed before character login", m.pinWrites, 0)
    m:Login()
    local c = m.controller
    eq("automatic guide claims native pin", m.pin.uiMapID, 1)
    eq("initial claim exactly once", m.pinWrites, 1)
    eq("own event during startup does not relinquish", c.navigation.owns, true)
    eq("custom arrow uses measured yards", c.ui.arrow.text, nil)
    for i = 1, 20 do m:Tick(.1) end
    eq("sampling and refresh do not rewrite same point", m.pinWrites, 1)
    eq("quest load request is not repeated per tick", m.requests[10], 1)
    c:SetPaused(true)
    eq("pause restores original map", m.pin.uiMapID, 2)
    near("pause restores original point x", m.pin.position.x, .12)
    near("pause preserves original height", m.pin.z, 7)
    eq("pause restores prior quest selection", m.tracking.id, 42)
    eq("pause removes custom navigation", c.ui.arrow.visible, false)
    eq("paused guide has no waypoint ownership", c.navigation.owns, false)
    m.quests[10] = {on = true}
    m:Event("QUEST_ACCEPTED", 10)
    m:Tick(.3)
    eq("pause holds step despite quest acceptance", c.engine:Chapter().index, 1)
    eq("paused events leave restored pin alone", m.pin.uiMapID, 2)
    m:ManualPin(Point(3, .22, .44, 9))
    m:ManualQuest(99)
    c:SetPaused(false)
    eq("resume catches up accepted quest", c.engine:Chapter().index, 2)
    near("resume points at current objective", m.pin.position.x, .8)
    c:SetPaused(true)
    eq("later pause restores the newer manual point", m.pin.uiMapID, 3)
    near("later pause preserves newer point height", m.pin.z, 9)
    eq("later pause restores newer quest tracking", m.tracking.id, 99)
end

do
    local m = Harness({pin = Point(2, .1, .2), tracking = {kind = "waypoint"}})
    m:Login()
    local c = m.controller
    c:HideUI()
    eq("Hide hides visible guide", c.ui:IsShown(), false)
    eq("Hide restores original native pin", m.pin.uiMapID, 2)
    local writes = m.pinWrites
    m.quests[10] = {on = true, complete = true}
    m:Event("QUEST_LOG_UPDATE"); m:Tick(.3)
    eq("hidden guide does not reacquire on quest refresh", m.pinWrites, writes)
    eq("hidden refresh leaves old user pin", m.pin.uiMapID, 2)
    c:ShowUI()
    eq("Show restores guide frame", c.ui:IsShown(), true)
    eq("Show targets live turn-in step", c.engine:GetStep().kind, "turnin")
    near("Show uses live step coordinate", m.pin.position.x, .9)
    c:HideUI()
    eq("Hide after Show preserves original snapshot", m.pin.uiMapID, 2)
    local savedDB, savedProgress = c.db, c.progress
    local reload = Harness({db = savedDB, progress = savedProgress, pin = Copy(m.pin), tracking = m.tracking})
    reload:Login()
    eq("hidden preference survives reload", reload.controller.ui:IsShown(), false)
    eq("hidden reload never claims native pin", reload.pinWrites, 0)
    eq("hidden reload preserves saved route position", reload.controller.engine:Chapter().index, 3)
end

do
    local m = Harness({tracking = {kind = "quest", id = 41}})
    m:Login()
    local c = m.controller
    c:Next(); c:Next()
    eq("multiple manual steps reach turn-in", c.engine:GetStep().kind, "turnin")
    c.ui:SetPosition("TOPLEFT", 31, -49)
    m:Event("PLAYER_LOGOUT")
    eq("logout clears guide pin when no original pin existed", m.pin, nil)
    eq("logout restores original quest tracking", m.tracking.id, 41)
    eq("logout saves user position anchor", c.db.position.point, "TOPLEFT")
    eq("logout saves position offset", c.db.position.x, 31)
    eq("logout retains guide progress", c.progress.chapters.a.index, 3)
    local restored = Harness({db = c.db, progress = c.progress, tracking = m.tracking})
    restored:Login()
    eq("reload restores visible guide at saved step", restored.controller.engine:Chapter().index, 3)
    eq("reload restores UI position", restored.controller.ui.position[2], 31)
    near("reload uses saved turn-in target", restored.pin.position.x, .9)
    restored:Event("PLAYER_LOGOUT")
    eq("reloaded session cleanup also has no phantom original pin", restored.pin, nil)
end

do
    local m = Harness({pin = Point(2, .1, .2), tracking = {kind = "quest", id = 42}})
    m:Login()
    local c = m.controller
    m:ManualPin(Point(3, .3, .4))
    m:ManualQuest(99)
    local writes = m.pinWrites
    c:Next(); m:Tick(2)
    eq("manual pin override survives guide step and ticks", m.pinWrites, writes)
    eq("manual override retains chosen point", m.pin.uiMapID, 3)
    eq("manual override retains chosen supertracking", m.tracking.id, 99)
    eq("custom guide arrow may continue independently", c.navigation:GetDisplay().visible, true)
    eq("display exposes native pin override", c.navigation:GetDisplay().paused, true)
    m:Event("PLAYER_LOGOUT")
    eq("logout never overwrites a player's replacement pin", m.pin.uiMapID, 3)
    eq("logout never restores obsolete supertracking", m.tracking.id, 99)
    eq("logout did not secretly write stale pin", m.pinWrites, writes)
end

do
    local m = Harness({pin = Point(2, .1, .2), tracking = {kind = "quest", id = 42}})
    m:Login()
    local c = m.controller
    m:ManualQuest(99)
    c:Next()
    near("guide may still update its owned point", m.pin.position.x, .8)
    eq("next step does not steal manual quest tracking", m.tracking.id, 99)
    c:HideUI()
    eq("Hide restores original point after tracking-only override", m.pin.uiMapID, 2)
    eq("Hide retains newer quest after tracking-only override", m.tracking.id, 99)
end

do
    local m = Harness({pin = Point(2, .1, .2), progress = {paused = true}, tracking = {kind = "waypoint"}})
    m:Login()
    local c = m.controller
    eq("saved pause suppresses native pin claim at startup", m.pinWrites, 0)
    eq("saved pause is shown by UI", c.ui.arrow.label, "Paused")
    SlashCmdList.SOBILEVELFOREVER("resume")
    eq("explicit slash resume starts navigation", m.pin.uiMapID, 1)
    m:ManualPin(Point(3, .4, .5))
    c:Next()
    eq("overridden native point stays manual", m.pin.uiMapID, 3)
    SlashCmdList.SOBILEVELFOREVER("resume")
    near("explicit resume intentionally reclaims guide point", m.pin.position.x, .8)
    c:SetPaused(true)
    eq("pause after explicit reclaim restores latest manual point", m.pin.uiMapID, 3)
end

do
    local m = Harness({pin = Point(2, .1, .2)})
    m:Login()
    local c = m.controller
    c:Next(); c:Prev()
    eq("Prev enters review at older guide step", c.progress.review, true)
    near("Prev updates target to reviewed step", m.pin.position.x, .7)
    m.quests[10] = {on = true, complete = true}
    m:Event("QUEST_LOG_UPDATE"); m:Tick(.3)
    near("review target survives completion evidence", m.pin.position.x, .7)
    c:ChooseRoute("b")
    near("chapter selection points to selected route", m.pin.position.x, .6)
    c:HideUI()
    eq("chapter switching retains original user snapshot", m.pin.uiMapID, 2)
end

do
    local m = Harness({pin = Point(2, .1, .2)})
    m:Login()
    local c = m.controller
    c:Next(); c:Next()
    m:Event("QUEST_TURNED_IN", 10, 0, 0)
    eq("turn-in reaches coordinate-free guidance", c.engine:GetStep().kind, "note")
    eq("coordinate-free step releases old route pin", m.pin.uiMapID, 2)
    eq("coordinate-free step hides old arrow", c.ui.arrow.visible, false)
    local writes = m.pinWrites
    m:Tick(2)
    eq("coordinate-free step does not repeatedly restore pin", m.pinWrites, writes)
end

print("PASS: " .. checks .. " Core/Engine/Navigation lifecycle checks")

-- Deterministic navigation/ownership tests; native WoW rendering is not mocked
-- as proof of an in-game result. Run from the workspace root.
local checks = 0
local function eq(label, value, expected)
    checks = checks + 1
    assert(value == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(value))
end
local function near(label, value, expected)
    checks = checks + 1
    assert(type(value) == "number" and math.abs(value - expected) < .00001, label .. ": wrong numeric result")
end
local function Vector(x, y)
    return {x = x, y = y, GetXY = function(self) return self.x, self.y end}
end
local function Point(map, x, y, z) return {uiMapID = map, position = Vector(x, y), z = z} end
local function Copy(point)
    return point and Point(point.uiMapID, point.position.x, point.position.y, point.z)
end
local function Target(x, y, map, radius)
    return {uiMapID = map or 1, x = x, y = y, radius = radius, zone = "Test zone", text = "Use the road."}
end

local function Harness(point, tracking, progress, walker)
    local m = {
        point = Copy(point), tracking = tracking or {kind = "none"}, setCalls = 0, clearCalls = 0,
        superCalls = 0, currentMap = 1, px = .5, py = .5, facing = 0, worldWidth = 2000, worldHeight = 1000,
    }
    m.secret = setmetatable({}, {__tostring = function() error("secret read") end})
    issecretvalue = function(value) return value == m.secret end
    CreateVector2D = Vector
    UiMapPoint = {CreateFromCoordinates = Point}
    C_Map = {
        GetUserWaypoint = function()
            if m.pointError then error("point unreadable") end
            if m.secretPoint then return m.secret end
            return Copy(m.point)
        end,
        SetUserWaypoint = function(value)
            m.setCalls = m.setCalls + 1
            if m.setFails then return false end
            m.point = Copy(value)
            if m.nav then m.nav:OnWaypointChanged(); m.nav:OnSuperTrackingChanged() end
            return true
        end,
        ClearUserWaypoint = function()
            m.clearCalls = m.clearCalls + 1
            m.point = nil
            if m.nav then m.nav:OnWaypointChanged() end
        end,
        CanSetUserWaypointOnMap = function(map) return not m.disallowed end,
        GetBestMapForUnit = function() return m.currentMap end,
        GetPlayerMapPosition = function()
            if m.noPlayerPos then return nil end
            return Vector(m.px, m.py)
        end,
        GetWorldPosFromMapPos = function(map, pos)
            if m.noConversion then return nil end
            if m.secretPosition then return 0, m.secret end
            return 0, Vector(1000 - pos.y * m.worldHeight, 2000 - pos.x * m.worldWidth)
        end,
        GetMapInfo = function(map) return {name = "Native map " .. map} end,
        GetMapPosFromWorldPos = function(continent, vector, override)
            m.conversionInput = {continent, vector.x, vector.y, override}
            if m.eraConversionFails then return nil end
            return m.convertedMap or override, Vector(m.convertedX or .6, m.convertedY or .4)
        end,
    }
    GetPlayerFacing = function() return m.facing end
    local function SetTracking(kind, id, subtype)
        m.superCalls = m.superCalls + 1
        m.tracking = {kind = kind, id = id, subtype = subtype}
        if m.nav then m.nav:OnSuperTrackingChanged() end
    end
    C_SuperTrack = {
        IsSuperTrackingUserWaypoint = function() return m.tracking.kind == "waypoint" end,
        IsSuperTrackingQuest = function() return m.tracking.kind == "quest" end,
        IsSuperTrackingMapPin = function() return m.tracking.kind == "pin" end,
        IsSuperTrackingContent = function() return m.tracking.kind == "content" end,
        IsSuperTrackingAnything = function() return m.tracking.kind ~= "none" end,
        GetSuperTrackedQuestID = function() return m.tracking.id end,
        GetSuperTrackedMapPin = function() return m.tracking.subtype, m.tracking.id end,
        GetSuperTrackedContent = function() return m.tracking.subtype, m.tracking.id end,
        SetSuperTrackedUserWaypoint = function(enabled)
            if enabled then SetTracking("waypoint")
            elseif m.tracking.kind == "waypoint" then SetTracking("none") end
        end,
        SetSuperTrackedQuestID = function(id) SetTracking("quest", id) end,
        SetSuperTrackedMapPin = function(kind, id) SetTracking("pin", id, kind) end,
        SetSuperTrackedContent = function(kind, id) SetTracking("content", id, kind) end,
    }
    local ns = {}
    if walker then ns.TerrainRouter={New=function() return walker end} end
    assert(loadfile("LevelingGuide/Navigation.lua"))("LevelingGuide", ns)
    m.nav = ns.Navigation.New(progress)
    m.manualPoint = function(value)
        m.point = Copy(value)
        m.nav:OnWaypointChanged()
    end
    m.manualQuest = function(id)
        m.tracking = {kind = "quest", id = id}
        m.nav:OnSuperTrackingChanged()
    end
    return m
end

do
    local m = Harness(Point(2, .12, .34, 7), {kind = "waypoint"})
    m.nav:UpdateTarget(Target(.7, .8))
    eq("claim successful", m.nav.owns, true)
    eq("synchronous own events ignored", m.nav.overridden, false)
    eq("one waypoint write", m.setCalls, 1)
    for i = 1, 10 do m.nav:GetDisplay(); m.nav:AtLocation(Target(.7, .8)); m.nav:UpdateTarget(Target(.7, .8)) end
    eq("reads and unchanged target never rewrite pin", m.setCalls, 1)
    m.nav:UpdateTarget(Target(.8, .9))
    eq("new target written once", m.setCalls, 2)
    m.nav:Stop()
    eq("original map restored", m.point.uiMapID, 2)
    near("original x restored", m.point.position.x, .12)
    near("original y restored", m.point.position.y, .34)
    near("original z restored", m.point.z, 7)
    eq("original user waypoint tracking restored", m.tracking.kind, "waypoint")
    local writes = m.setCalls
    m.nav:Stop(); eq("stop idempotent", m.setCalls, writes)
end

do
    local m = Harness(nil, {kind = "quest", id = 42})
    m.nav:UpdateTarget(Target(.7, .8)); m.nav:UpdateTarget(Target(.8, .9)); m.nav:Stop()
    eq("no original pin means clear after several route points", m.point, nil)
    eq("original quest tracking restored", m.tracking.kind, "quest")
    eq("correct quest restored", m.tracking.id, 42)
    eq("own pin cleared once", m.clearCalls, 1)
end

do
    local m = Harness(Point(2, .1, .2), {kind = "waypoint"})
    m.nav:UpdateTarget(Target(.7, .8))
    m.manualPoint(Point(3, .44, .55))
    eq("manual point relinquishes ownership", m.nav.owns, false)
    m.nav:UpdateTarget(Target(.9, .9)); m.nav:GetDisplay()
    eq("route updates do not fight manual override", m.point.uiMapID, 3)
    eq("no extra set after override", m.setCalls, 1)
    m.nav:Resume()
    eq("explicit resume may reclaim", m.point.uiMapID, 1)
    m.nav:Stop()
    eq("resume saves new manual pin", m.point.uiMapID, 3)
    near("new manual x retained", m.point.position.x, .44)
end

do
    local m = Harness(Point(2, .1, .2), {kind = "waypoint"})
    m.nav:UpdateTarget(Target(.7, .8)); m.manualPoint(nil)
    m.nav:UpdateTarget(Target(.6, .6)); m.nav:Stop()
    eq("manual clearing respected", m.point, nil)
    eq("manual clear not replaced with old snapshot", m.setCalls, 1)
    local p = Harness(Point(2, .1, .2), {kind = "waypoint"})
    p.nav:UpdateTarget(Target(.7, .8))
    p.point = Point(4, .2, .3) -- simulate a missed notification
    p.nav:Stop()
    eq("stop rechecks current pin before restoring", p.point.uiMapID, 4)
end

do
    local m = Harness(Point(2, .1, .2), {kind = "quest", id = 42})
    m.nav:UpdateTarget(Target(.7, .8)); m.manualQuest(99)
    m.nav:UpdateTarget(Target(.8, .8))
    eq("new step does not steal user quest tracking", m.tracking.id, 99)
    m.nav:Stop()
    eq("pin restored after tracking override", m.point.uiMapID, 2)
    eq("new user quest not replaced with old quest", m.tracking.id, 99)
end

do
    local m = Harness(Point(2, .1, .2), {kind = "quest", id = 42})
    m.setFails = true
    m.nav:UpdateTarget(Target(.7, .8)); m.nav:Stop()
    eq("failed set never owns pin", m.nav.owns, false)
    eq("failed set preserves original point", m.point.uiMapID, 2)
    eq("failed set never changes supertracking", m.superCalls, 0)
    local p = Harness(Point(2, .1, .2))
    p.secretPoint = true; p.nav:UpdateTarget(Target(.7, .8))
    eq("unreadable current pin not overwritten", p.setCalls, 0)
    local q = Harness()
    q.nav:UpdateTarget(Target(.7, .8)); q.setFails = true
    q.nav:UpdateTarget(Target(.8, .8))
    eq("failed later step clears obsolete owned pin", q.point, nil)
end

do
    local m = Harness()
    local cases = {
        {"north", .5, .4, 0}, {"east", .55, .5, -math.pi / 2},
        {"south", .5, .6, -math.pi}, {"west", .45, .5, math.pi / 2},
    }
    for _, item in ipairs(cases) do
        m.nav:UpdateTarget(Target(item[2], item[3]))
        local d = m.nav:GetDisplay()
        eq(item[1] .. " visible", d.visible, true)
        near(item[1] .. " world distance", d.distance, 100)
        near(item[1] .. " arrow bearing", d.rotation, item[4])
        eq(item[1] .. " distance not overridden by quest text", d.text, nil)
    end
    m.facing = math.pi / 2; near("facing west toward west is straight", m.nav:GetDisplay().rotation, 0)
    m.nav:UpdateTarget(Target(.5, .4)); m.facing = math.pi * 1.5
    near("facing east toward north is left", m.nav:GetDisplay().rotation, math.pi / 2)
    m.nav:UpdateTarget(Target(.51, .5)); eq("default 35 yard arrival", m.nav:GetDisplay().arrived, true)
    eq("arrival hides arrow", m.nav:GetDisplay().visible, false)
    eq("at location confirmed", m.nav:AtLocation(Target(.51, .5)), true)
    eq("custom radius respected", m.nav:AtLocation(Target(.51, .5, 1, 10)), false)
    m.nav:UpdateTarget(Target(.55, .4)); near("rectangular map diagonal metric", m.nav:GetDisplay().distance, math.sqrt(20000))
end

do
    local m = Harness()
    m.nav:UpdateTarget(Target(.5, .4, 2))
    local d = m.nav:GetDisplay()
    eq("crosszone custom arrow hidden", d.visible, false)
    eq("crosszone no fabricated distance", d.distance, nil)
    eq("crosszone map prompt", d.label, "Open map")
    eq("crosszone map name", d.text, "Travel to Test zone")
    eq("crosszone native pin created", m.point.uiMapID, 2)
    eq("crosszone arrival unknown", m.nav:AtLocation(Target(.5, .4, 2)), nil)
    m.nav:UpdateTarget(Target(.5, .4)); m.noConversion = true
    eq("missing world conversion no distance", m.nav:GetDisplay().distance, nil)
    eq("missing world conversion no arrival", m.nav:AtLocation(Target(.5, .4)), nil)
    m.noConversion = false; m.secretPosition = true
    eq("secret world position no arrow", m.nav:GetDisplay().visible, false)
    m.secretPosition = false; m.facing = m.secret
    eq("secret facing no arrow", m.nav:GetDisplay().visible, false)
    near("known distance retained without facing", m.nav:GetDisplay().distance, 100)
end

do
    local m = Harness()
    local era = {uiMapID = 1429, x = .4214, y = .6726, coordFrame = "era", continentID = 0,
        worldX = -9496.3715258, worldY = 72.8075524, zone = "Elwynn Forest"}
    m.currentMap = 1429
    m.nav:UpdateTarget(era)
    near("Era converted x used for pin", m.point.position.x, .6)
    near("Era converted y used for pin", m.point.position.y, .4)
    eq("Era override map supplied", m.conversionInput[4], 1429)
    near("Era raw north axis unchanged", m.conversionInput[2], era.worldX)
    near("Era raw west axis unchanged", m.conversionInput[3], era.worldY)
    m.eraConversionFails = true; m.nav:UpdateTarget(era)
    eq("conversion failure removes owned native pin", m.point, nil)
    eq("conversion failure prevents arrow", m.nav:GetDisplay().visible, false)
    eq("conversion failure no arrival", m.nav:AtLocation(era), nil)
    eq("conversion failure manual map prompt", m.nav:GetDisplay().label, "Open map")
    eq("conversion failure labeled unverified", m.nav:GetDisplay().text:find("unverified", 1, true) ~= nil, true)
    m.eraConversionFails = false; m.convertedMap = 999
    m.nav:UpdateTarget(era); eq("wrong converted map not accepted", m.point, nil)
    m.convertedMap = nil; m.convertedX = 1.5
    m.nav:UpdateTarget(era); eq("out-of-bounds converted point not clamped", m.point, nil)
    m.convertedX = .6; m.nav:UpdateTarget(era)
    near("conversion availability resumes correct pin", m.point.position.x, .6)
end

do
    local m = Harness()
    m.nav:UpdateTarget(Target(.7, .8))
    m.nav:UpdateTarget(Target(1.1, .8))
    eq("invalid normalized position clears old route pin", m.point, nil)
    eq("invalid target hidden", m.nav:GetDisplay().visible, false)
    eq("invalid target cannot auto-arrive", m.nav:AtLocation(Target(0 / 0, .5)), nil)
    m.nav:UpdateTarget({uiMapID = 1, x = .5, y = .4, coordFrame = "future"})
    eq("unknown coordinate frame fails closed", m.point, nil)
    eq("unknown coordinate frame no distance", m.nav:GetDisplay().distance, nil)
end

print("PASS: " .. checks .. " navigation checks")

do
    local saved={}
    local m=Harness(nil,nil,saved)
    local start=Target(.5,.5)
    start.areaOnly,start.questID,start.objectiveIndex=true,99144,1
    m.nav:UpdateTarget(start)
    eq("event starting area acknowledged",m.nav:GetDisplay().areaOnly,true)
    eq("event starting pin released",m.nav.owns,false)
    m.px=.8
    eq("moving escort never sends player back to its start",m.nav:GetDisplay().visible,false)
    local reload=Harness(nil,nil,saved)
    reload.px=.8
    reload.nav:UpdateTarget(start)
    eq("event area remembered across reload",reload.nav:GetDisplay().areaOnly,true)
    reload.nav:UpdateTarget({inventoryOnly=true})
    eq("inventory task has no fake geographic arrow",reload.nav:GetDisplay().inventoryOnly,true)
end
print("PASS event-area persistence and inventory-only navigation")

do
 local m=Harness()
 near("route distance uses world yards",m.nav:DistanceTo(Target(.6,.5)),200)
 near("task-to-task route distance",m.nav:DistanceBetween(Target(.6,.5),Target(.5,.5)),200)
 eq("do not compare points on different maps",m.nav:DistanceBetween(Target(.6,.5),Target(.5,.5,2)),nil)
end
print("PASS routing distances use compatible world coordinates")

do
 local walker={pending=false}
 function walker:Stop() end
 function walker:GetLeg(from,goal)
  if self.pending then return nil,nil,"Finding walking path..." end
  return {map=from.map,x=from.x+100,y=from.y},600,nil
 end
 local m=Harness(nil,nil,nil,walker)
 m.nav:UpdateTarget(Target(.6,.5))
 local display=m.nav:GetDisplay()
 eq("walking route mode",display.walking,true)
 near("arrow follows next corner rather than final waypoint",display.rotation,0)
 near("display walking distance, not direct distance",display.distance,600)
 m.nav:UpdateTarget(Target(.505,.5))
 eq("wall-adjacent goal is not automatically reached",m.nav:AtLocation(Target(.505,.5)),false)
 walker.pending=true
 eq("pending terrain path never displays straight fallback",m.nav:GetDisplay().visible,false)
end
print("PASS Navigation integrates path corners and walking arrival distance")

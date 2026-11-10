-- SobiLevel Forever: map navigation and temporary native-waypoint ownership.
-- Walking-map routing supplies intermediate corners; geometric helpers also serve area grouping.
local addonName, ns = ...
local Navigation = {}
ns.Navigation = Navigation
local Instance = {}
Instance.__index = Instance
local EPSILON = 0.000001
local TWO_PI = 2 * math.pi

local function Secret(value)
    if type(issecretvalue) == "function" then
        local ok, result = pcall(issecretvalue, value)
        return not ok or result
    end
    return false
end

local function Call(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, a, b, c = pcall(fn, ...)
    if not ok or Secret(a) or Secret(b) or Secret(c) then return false end
    return true, a, b, c
end

local function Field(object, key)
    if Secret(object) or (type(object) ~= "table" and type(object) ~= "userdata") then return nil end
    local ok, value = Call(function() return object[key] end)
    if ok then return value end
end

local function Number(value)
    return not Secret(value) and type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function Text(value)
    return not Secret(value) and type(value) == "string" and value or nil
end

local function VectorXY(vector)
    local method = Field(vector, "GetXY")
    if type(method) == "function" then
        local ok, x, y = Call(method, vector)
        if ok and Number(x) and Number(y) then return x, y end
        return nil
    end
    local x, y = Field(vector, "x"), Field(vector, "y")
    if Number(x) and Number(y) then return x, y end
end

local function ValidTarget(step)
    local mapID, x, y = Field(step, "uiMapID"), Field(step, "x"), Field(step, "y")
    if not Number(mapID) or mapID <= 0 or mapID ~= math.floor(mapID)
        or not Number(x) or not Number(y) or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    local radius = Field(step, "radius")
    if not Number(radius) or radius <= 0 then radius = 35 end
    local target = {
        uiMapID = mapID, x = x, y = y, radius = radius,
        text = Text(Field(step, "text")), zone = Text(Field(step, "zone")),
        navigationHint = Text(Field(step, "navigationHint")),
        areaOnly = Field(step, "areaOnly") == true,
    }
    local coordFrame = Text(Field(step, "coordFrame"))
    local worldZ = Field(step, "worldZ")
    if Number(worldZ) then target.worldZ = worldZ end
    if target.areaOnly then
        local questID, objectiveIndex = Field(step, "questID"), Field(step, "objectiveIndex")
        if Number(questID) and Number(objectiveIndex) then
            target.areaVisitKey = tostring(questID) .. ":" .. tostring(objectiveIndex) .. ":" .. tostring(mapID)
        end
    end
    if coordFrame == "era" then
        target.sourceX, target.sourceY = x, y
        local continent = Field(step, "continentID")
        local worldX, worldY = Field(step, "worldX"), Field(step, "worldY")
        if Number(continent) and Number(worldX) and Number(worldY) and C_Map then
            local vectorOK, vector = Call(CreateVector2D, worldX, worldY)
            if vectorOK and vector then
                local conversionOK, liveMap, livePoint = Call(C_Map.GetMapPosFromWorldPos, continent, vector, mapID)
                local liveX, liveY = VectorXY(livePoint)
                if conversionOK and liveMap == mapID and liveX and liveY
                    and liveX >= 0 and liveX <= 1 and liveY >= 0 and liveY <= 1 then
                    target.x, target.y = liveX, liveY
                    return target
                end
            end
        end
        -- Era normalized coordinates can point somewhere different in Forever.
        target.unavailableCoordinates = true
    elseif coordFrame ~= nil and coordFrame ~= "live" then
        target.unavailableCoordinates = true
        target.sourceX, target.sourceY = x, y
    end
    return target
end

local function SamePoint(a, b)
    if not a or not b then return a == b end
    if a.uiMapID ~= b.uiMapID or math.abs(a.x - b.x) > EPSILON
        or math.abs(a.y - b.y) > EPSILON then return false end
    if a.z == nil or b.z == nil then return a.z == b.z end
    return math.abs(a.z - b.z) <= EPSILON
end

local function ReadUserPoint()
    if not C_Map then return false end
    local ok, point = Call(C_Map.GetUserWaypoint)
    if not ok then return false end
    if point == nil then return true, nil end
    local mapID = Field(point, "uiMapID")
    local x, y = VectorXY(Field(point, "position"))
    local zOK, z = Call(function() return point.z end)
    if not zOK or not Number(mapID) or not x or not y or (z ~= nil and not Number(z)) then return false end
    return true, {uiMapID = mapID, x = x, y = y, z = z}
end

local function MakePoint(point)
    if not UiMapPoint then return nil end
    local ok, result = Call(UiMapPoint.CreateFromCoordinates, point.uiMapID, point.x, point.y, point.z)
    if ok then return result end
end

local function TrackingIs(fn)
    local ok, result = Call(fn)
    return ok and result == true
end

local function SnapshotTracking()
    if not C_SuperTrack then return {kind = "unknown"} end
    local api = C_SuperTrack
    if TrackingIs(api.IsSuperTrackingUserWaypoint) then return {kind = "waypoint"} end
    if TrackingIs(api.IsSuperTrackingQuest) then
        local ok, id = Call(api.GetSuperTrackedQuestID)
        if ok and Number(id) and id > 0 then return {kind = "quest", id = id} end
    end
    if TrackingIs(api.IsSuperTrackingMapPin) then
        local ok, kind, id = Call(api.GetSuperTrackedMapPin)
        if ok and Number(kind) and Number(id) then return {kind = "pin", pinType = kind, id = id} end
    end
    if TrackingIs(api.IsSuperTrackingContent) then
        local ok, kind, id = Call(api.GetSuperTrackedContent)
        if ok and Number(kind) and Number(id) then return {kind = "content", contentType = kind, id = id} end
    end
    local ok, any = Call(api.IsSuperTrackingAnything)
    return {kind = ok and any == false and "none" or "unknown"}
end

local function RestoreTracking(snapshot, pointRestored)
    if not C_SuperTrack or not snapshot then return end
    if snapshot.kind == "waypoint" and pointRestored then
        Call(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
        return
    end
    Call(C_SuperTrack.SetSuperTrackedUserWaypoint, false)
    if snapshot.kind == "quest" then
        Call(C_SuperTrack.SetSuperTrackedQuestID, snapshot.id)
    elseif snapshot.kind == "pin" then
        Call(C_SuperTrack.SetSuperTrackedMapPin, snapshot.pinType, snapshot.id)
    elseif snapshot.kind == "content" then
        Call(C_SuperTrack.SetSuperTrackedContent, snapshot.contentType, snapshot.id)
    end
end

function Navigation.New(progress)
    if progress and type(progress.visitedTaskAreas) ~= "table" then progress.visitedTaskAreas = {} end
    return setmetatable({owns = false, ownsTracking = false, writing = false, overridden = false,
        visitedTaskAreas = progress and progress.visitedTaskAreas or {},
        walker = ns.TerrainRouter and ns.TerrainRouter.New()}, Instance)
end

function Instance:OnWaypointChanged()
    if self.writing or not self.owns then return end
    local readable, current = ReadUserPoint()
    if not readable or not SamePoint(current, self.ownedPoint) then
        -- An explicit removal is an override too. Never recreate it on a tick.
        self.owns, self.ownsTracking, self.overridden = false, false, true
        self.ownedPoint, self.savedPoint, self.savedTracking = nil, nil, nil
    end
end

function Instance:OnSuperTrackingChanged()
    if self.writing or not self.owns or not self.ownsTracking then return end
    if not C_SuperTrack or not TrackingIs(C_SuperTrack.IsSuperTrackingUserWaypoint) then
        self.ownsTracking = false
        self.trackingOverridden = true
    end
end

function Instance:Release()
    if not self.owns then return end
    local readable, current = ReadUserPoint()
    if not readable or not SamePoint(current, self.ownedPoint) then
        self:OnWaypointChanged()
        return
    end
    local restoreTracking = self.ownsTracking and not self.trackingOverridden
        and C_SuperTrack and TrackingIs(C_SuperTrack.IsSuperTrackingUserWaypoint)
    self.writing = true
    local restored = false
    if self.savedPoint then
        local point = MakePoint(self.savedPoint)
        if point then
            local ok, wasSet = Call(C_Map.SetUserWaypoint, point)
            restored = ok and wasSet == true
        end
    end
    if not restored then Call(C_Map.ClearUserWaypoint) end
    if restoreTracking then RestoreTracking(self.savedTracking, restored) end
    self.writing = false
    self.owns, self.ownsTracking = false, false
    self.ownedPoint, self.savedPoint, self.savedTracking = nil, nil, nil
end

function Instance:Claim()
    if not self.target or self.target.unavailableCoordinates or self.overridden or not C_Map or not UiMapPoint
        or type(C_Map.GetUserWaypoint) ~= "function" or type(C_Map.SetUserWaypoint) ~= "function"
        or type(C_Map.ClearUserWaypoint) ~= "function" then return end
    -- Recheck ownership even if a third party's event was missed.
    self:OnWaypointChanged()
    if self.overridden then return end
    local allowed, canSet = Call(C_Map.CanSetUserWaypointOnMap, self.target.uiMapID)
    if allowed and canSet == false then self:Release(); return end
    local readable, previous = ReadUserPoint()
    if not readable then return end
    local point = MakePoint(self.target)
    if not point then return end
    local savedPoint, savedTracking
    if self.owns then
        -- nil is a meaningful original snapshot: the player had no pin.
        savedPoint, savedTracking = self.savedPoint, self.savedTracking
    else
        savedPoint, savedTracking = previous, SnapshotTracking()
    end
    self.writing = true
    local ok, wasSet = Call(C_Map.SetUserWaypoint, point)
    if ok and wasSet == true then
        local currentReadable, current = ReadUserPoint()
        -- Record the accepted point (including any native numeric conversion).
        if currentReadable and current and current.uiMapID == self.target.uiMapID
            and math.abs(current.x - self.target.x) <= .0001
            and math.abs(current.y - self.target.y) <= .0001 then
            self.savedPoint, self.savedTracking = savedPoint, savedTracking
            self.owns, self.ownedPoint = true, current
            if not self.trackingOverridden and C_SuperTrack then
                local trackingSet = Call(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
                self.ownsTracking = trackingSet and TrackingIs(C_SuperTrack.IsSuperTrackingUserWaypoint)
            end
        else
            self.owns, self.ownsTracking, self.overridden = false, false, true
            self.ownedPoint, self.savedPoint, self.savedTracking = nil, nil, nil
        end
    end
    self.writing = false
    if not ok or wasSet ~= true then
        -- A previous step's native pin must not remain as the route's new pin.
        self:Release()
    end
end

function Instance:UpdateTarget(step)
    self.instruction = step
    local target = ValidTarget(step)
    if not target then
        if self.walker then self.walker:Stop() end
        self:Release()
        self.target = nil
        return
    end
    local old = self.target
    local changed = not old or old.uiMapID ~= target.uiMapID or old.x ~= target.x or old.y ~= target.y
        or old.unavailableCoordinates ~= target.unavailableCoordinates
    self.target = target
    if changed and self.walker then self.walker:Stop() end
    if target.unavailableCoordinates then self:Release()
    elseif changed then self:Claim() end
end

function Instance:Resume()
    self:Release()
    self.overridden, self.trackingOverridden = false, false
    self:Claim()
end

function Instance:Stop()
    if self.walker then self.walker:Stop() end
    self:Release()
    self.target = nil
    self.instruction = nil
    self.overridden, self.trackingOverridden = false, false
end

local function MapName(target)
    if target.zone and target.zone ~= "" then return target.zone end
    if C_Map then
        local ok, info = Call(C_Map.GetMapInfo, target.uiMapID)
        if ok then
            local name = Text(Field(info, "name"))
            if name and name ~= "" then return name end
        end
    end
    return "map " .. tostring(target.uiMapID)
end

local function Measure(target, allowCrossZone)
    if target.unavailableCoordinates then return nil, "coordinates" end
    if not C_Map then return nil, "position" end
    local mapOK, currentMap = Call(C_Map.GetBestMapForUnit, "player")
    if not mapOK or not Number(currentMap) then return nil, "position" end
    if currentMap ~= target.uiMapID and not allowCrossZone then return nil, "crosszone" end
    local posOK, playerPos = Call(C_Map.GetPlayerMapPosition, currentMap, "player")
    if not posOK or not playerPos then return nil, "position" end
    local px, py = VectorXY(playerPos)
    if not px or not py then return nil, "position" end
    local vectorOK, goalVector = Call(CreateVector2D, target.x, target.y)
    if not vectorOK or not goalVector then return nil, "position" end
    local firstOK, playerContinent, playerWorld = Call(C_Map.GetWorldPosFromMapPos, currentMap, playerPos)
    local secondOK, goalContinent, goalWorld = Call(C_Map.GetWorldPosFromMapPos, target.uiMapID, goalVector)
    if not firstOK or not secondOK or not Number(playerContinent) then
        return nil, "position"
    end
    if playerContinent ~= goalContinent then return nil, "crosszone" end
    local pn, pw = VectorXY(playerWorld)
    local gn, gw = VectorXY(goalWorld)
    if not pn or not pw or not gn or not gw then return nil, "position" end
    local north, west = gn - pn, gw - pw
    return math.sqrt(north * north + west * west), nil, north, west
end

local function Atan2(y, x)
    if math.atan2 then return math.atan2(y, x) end
    -- Portable Lua 5.1 fallback; do not depend on math.atan's 5.3+ second arg.
    if x > 0 then return math.atan(y / x) end
    if x < 0 then return math.atan(y / x) + (y >= 0 and math.pi or -math.pi) end
    if y > 0 then return math.pi / 2 end
    if y < 0 then return -math.pi / 2 end
    return 0
end

local function WalkingEndpoints(target, north, west)
    if not C_Map or not north or not west then return nil end
    local vectorOK, vector = Call(CreateVector2D,target.x,target.y)
    if not vectorOK then return nil end
    local ok,map,world = Call(C_Map.GetWorldPosFromMapPos,target.uiMapID,vector)
    local x,y=VectorXY(world)
    if not ok or not Number(map) or not x or not y then return nil end
    local from={map=map,x=x-north,y=y-west}
    local goal={map=map,x=x,y=y,z=target.worldZ}
    if type(UnitPosition)=="function" then
        local readable,px,py,z,instance=pcall(UnitPosition,"player")
        if readable and Number(px) and Number(py) and Number(z) and Number(instance)
            and instance==map and math.abs(px-from.x)<10 and math.abs(py-from.y)<10 then from.z=z end
    end
    return from,goal
end

function Instance:AtLocation(step)
    local target = ValidTarget(step)
    if not target then return nil end
    local distance,_,north,west = Measure(target, self.walker ~= nil)
    if distance == nil then return nil end
    if self.walker then
        local from,goal=WalkingEndpoints(target,north,west)
        if not from then return nil end
        local nextPoint,walkingDistance=self.walker:GetLeg(from,goal)
        if not nextPoint or not walkingDistance then return nil end
        distance=walkingDistance
    end
    return distance <= target.radius
end

function Instance:DistanceTo(step)
    local target = ValidTarget(step)
    if not target then return nil end
    local distance = Measure(target)
    return distance
end

function Instance:DistanceBetween(a, b)
    local first, second = ValidTarget(a), ValidTarget(b)
    if not first or not second or first.uiMapID ~= second.uiMapID then return nil end
    local _, _, northA, westA = Measure(first)
    local _, _, northB, westB = Measure(second)
    if not northA or not northB or not westA or not westB then return nil end
    return math.sqrt((northA-northB)^2 + (westA-westB)^2)
end

function Instance:WalkingDistanceTo(step)
    if not ns.TerrainRouter or not ns.TerrainRouter.WalkingCost then return nil end
    local target=ValidTarget(step)
    if not target then return nil end
    local _,_,north,west=Measure(target,true)
    local from,goal=WalkingEndpoints(target,north,west)
    if not from then return nil end
    return ns.TerrainRouter.WalkingCost(from,goal)
end

function Instance:WalkingDistanceBetween(a,b)
    if not ns.TerrainRouter or not ns.TerrainRouter.WalkingCost then return nil end
    local first,second=ValidTarget(a),ValidTarget(b)
    if not first or not second then return nil end
    local _,_,an,aw=Measure(first,true)
    local _,_,bn,bw=Measure(second,true)
    local _,from=WalkingEndpoints(first,an,aw)
    local _,goal=WalkingEndpoints(second,bn,bw)
    if not from or not goal or from.map~=goal.map then return nil end
    return ns.TerrainRouter.WalkingCost(from,goal)
end

function Instance:GetDisplay()
    local target = self.target
    local result = {visible = false, unavailable = true, label = "", text = "", arrived = nil}
    if not target then
        if self.instruction and Field(self.instruction, "inventoryOnly") == true then
            result.inventoryOnly = true
            result.label, result.text = "Bags", "Item action: follow the instructions above in your bags."
        end
        return result
    end
    -- UI text is a distance override; ordinary guidance leaves it nil so the
    -- UI can show yards/arrival. Longer instructions belong in the tooltip.
    result.text = nil
    result.hint = (target.text and (target.text .. "\n") or "") .. "Straight-line bearing, not a walking route."
    if target.navigationHint then result.hint = target.navigationHint .. "\n" .. result.hint end
    result.paused = self.overridden or false
    local distance, reason, north, west = Measure(target, self.walker ~= nil)
    if target.areaOnly and target.areaVisitKey and (self.visitedTaskAreas[target.areaVisitKey]
        or (not self.walker and distance and distance <= target.radius)) then
        self.visitedTaskAreas[target.areaVisitKey] = true
        self:Release()
        result.areaOnly, result.unavailable = true, false
        result.label = "Event area reached"
        result.text = "You reached the event area. Follow the event instructions and stay with the NPC; the guide is waiting for quest progress."
        return result
    end
    if reason == "coordinates" then
        result.label = "Open map"
        result.text = string.format("%s: source %.1f, %.1f. Coordinates unverified on Forever.",
            MapName(target), target.sourceX * 100, target.sourceY * 100)
        return result
    end
    if reason == "crosszone" then
        result.label = "Open map"
        result.text = "Travel to " .. MapName(target)
        result.crossZone = true
        return result
    end
    if distance == nil then
        result.label = "Distance unknown"
        result.text = "Position unavailable. Open the map for " .. MapName(target) .. "."
        return result
    end
    if self.walker then
        local from,goal=WalkingEndpoints(target,north,west)
        local nextPoint,walkingDistance,routeReason
        if from then nextPoint,walkingDistance,routeReason=self.walker:GetLeg(from,goal) end
        if not nextPoint or not walkingDistance then
            result.label="Walking route"
            result.text=routeReason or "Walking position unavailable. Open map."
            result.pathPending=self.walker.pending==true
            return result
        end
        distance,north,west=walkingDistance,nextPoint.x-from.x,nextPoint.y-from.y
        result.walking=true
        result.hint="Follow the next corner of the calculated walking path."
        if target.navigationHint then result.hint=target.navigationHint.."\n"..result.hint end
        if target.areaOnly and target.areaVisitKey and distance<=target.radius then
            self.visitedTaskAreas[target.areaVisitKey]=true
            self:Release()
            result.areaOnly,result.unavailable=true,false
            result.label,result.text="Event area reached","Follow the event instructions and stay with the NPC."
            return result
        end
    end
    result.distance = distance
    result.arrived = distance <= target.radius
    result.label = result.arrived and "Arrived" or (tostring(math.floor(distance + .5)) .. " yd")
    if result.arrived then result.unavailable = false; return result end
    local facingOK, facing = Call(GetPlayerFacing)
    if not facingOK or not Number(facing) then
        result.text = "Direction unavailable. Open the map for " .. MapName(target) .. "."
        return result
    end
    result.rotation = (Atan2(west, north) - facing + math.pi) % TWO_PI - math.pi
    result.visible, result.unavailable = true, false
    return result
end

return Navigation

-- SobiLevel adapter for the separately attributed GPL walking-map router.
local _, ns = ...
local Terrain = {}
ns.TerrainRouter = Terrain
local Instance = {}; Instance.__index = Instance
local function number(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function distance(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2) end
local function now() return type(GetTime)=="function" and GetTime() or 0 end
local function point(p) return type(p)=="table" and number(p.x) and number(p.y) end
local costs,pendingCosts={},0

-- Low-priority cost searches share the router's frame budget with the arrow.
function Terrain.WalkingCost(from,goal)
    local engine=SobiLevelNavEngine
    if not point(from) or not point(goal) or from.map~=goal.map or not engine or type(engine.FindCost)~="function" then return nil end
    local key=from.map..":"..math.floor(from.x/16)..":"..math.floor(from.y/16)..":"..tostring(from.z and math.floor(from.z/4) or "")
        ..":"..string.format("%.1f:%.1f:%s",goal.x,goal.y,tostring(goal.z or ""))
    local entry=costs[key]
    if entry and now()-entry.at<30 then return entry.yards end
    if pendingCosts>=4 then return nil end
    for old,value in pairs(costs) do if now()-value.at>30 then costs[old]=nil end end
    entry={at=now()};costs[key]=entry;pendingCosts=pendingCosts+1
    local ok=pcall(engine.FindCost,goal.map,{x=from.x,y=from.y,z=from.z},{x=goal.x,y=goal.y,z=goal.z},function(cost,reason,job)
        pendingCosts=math.max(0,pendingCosts-1)
        if type(cost)=="number" and type(job)=="table" and number(job.yards) and job.yards>=0 then entry.yards=job.yards end
    end,{style="roads",profile=UnitFactionGroup and UnitFactionGroup("player"),waterWalking=false})
    if not ok then pendingCosts=math.max(0,pendingCosts-1) end
    return entry.yards
end

function Terrain.New()
    return setmetatable({serial=0,index=2,retryAt=0},Instance)
end

function Instance:Engine()
    if type(SobiLevelNavEngine)=="table" then return SobiLevelNavEngine end
    if InCombatLockdown and InCombatLockdown() then return nil,"Load after combat" end
    if now() < (self.loadRetry or 0) then return nil,"Restart game to load walking maps" end
    self.loadRetry=now()+10
    if C_AddOns and type(C_AddOns.LoadAddOn)=="function" then pcall(C_AddOns.LoadAddOn,"SobiLevelNav") end
    if type(SobiLevelNavEngine)=="table" then return SobiLevelNavEngine end
    return nil,"Walking maps unavailable; restart the game"
end

function Instance:Stop()
    self.serial=self.serial+1
    if self.job and SobiLevelNavEngine and SobiLevelNavEngine.Cancel then pcall(SobiLevelNavEngine.Cancel,self.job) end
    self.job,self.points,self.key,self.pending=nil,nil,nil,nil
end

function Instance:Request(engine, from, goal, key)
    self:Stop()
    self.key,self.pending,self.start,self.requestAt=key,true,{x=from.x,y=from.y},now()
    local serial=self.serial
    local faction=UnitFactionGroup and UnitFactionGroup("player")
    local ok,job=pcall(engine.Find,goal.map,{x=from.x,y=from.y,z=from.z},{x=goal.x,y=goal.y,z=goal.z},function(points,reason)
        if serial~=self.serial then return end
        self.pending=false
        if type(points)=="table" and #points>=2 then
            for _,p in ipairs(points) do if not point(p) or (p.map and p.map~=goal.map) then self.points=nil;self.reason="Invalid walking route";self.retryAt=now()+10;return end end
            self.points,self.index,self.reason=points,2,nil
        else self.points=nil;self.reason="No walking route ("..tostring(reason or "unknown").."). Open map.";self.retryAt=now()+10 end
    end,{profile=faction,style="roads",waterWalking=false})
    if ok then self.job=job else self.pending=false;self.reason="Walking route failed. Open map.";self.retryAt=now()+10 end
end

function Instance:GetLeg(from,goal)
    if not point(from) or not point(goal) or from.map~=goal.map then return nil,nil,"Position unavailable" end
    local engine,reason=self:Engine()
    if not engine or type(engine.Find)~="function" then return nil,nil,reason or "Walking maps unavailable" end
    local key=goal.map..":"..string.format("%.2f:%.2f:%s",goal.x,goal.y,tostring(goal.z or ""))
    if self.key~=key or (not self.points and not self.pending and now()>=self.retryAt) then self:Request(engine,from,goal,key) end
    if self.pending then return nil,nil,"Finding walking path..." end
    local points=self.points
    if not points then return nil,nil,self.reason or "No walking route. Open map." end
    while self.index<#points and distance(from,points[self.index])<=3 do self.index=self.index+1 end
    -- A later corner can be used only when the collision grid confirms sight.
    if type(engine.Sight)=="function" then
        for i=math.min(self.index+4,#points),self.index+1,-1 do
            local p=points[i]
            local ok,visible=pcall(engine.Sight,goal.map,from.x,from.y,from.z,p.x,p.y,p.z,UnitFactionGroup and UnitFactionGroup("player"))
            if ok and visible==true then self.index=i;break end
        end
    end
    local nextPoint=points[self.index]
    -- If the player leaves the corridor, discard it and request a fresh route.
    local near=math.huge
    for i=math.max(2,self.index-4),math.min(#points,self.index+8) do
        local a,b=points[i-1],points[i]
        local dx,dy=b.x-a.x,b.y-a.y
        local denominator=dx*dx+dy*dy
        local t=denominator>0 and math.max(0,math.min(1,((from.x-a.x)*dx+(from.y-a.y)*dy)/denominator)) or 0
        near=math.min(near,distance(from,{x=a.x+t*dx,y=a.y+t*dy}))
    end
    if near>25 and now()-(self.requestAt or 0)>=3 then self:Request(engine,from,goal,key);return nil,nil,"Recalculating walking path..." end
    local remaining=distance(from,nextPoint)
    for i=self.index,#points-1 do remaining=remaining+distance(points[i],points[i+1]) end
    return nextPoint,remaining,nil
end

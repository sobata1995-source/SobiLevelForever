-- Exhaustive static coverage plus quest-state contracts for every bundled row.
local ns = {}
assert(loadfile("LevelingGuide/Data/Routes.lua"))("LevelingGuide", ns)
assert(loadfile("LevelingGuide/Engine.lua"))("LevelingGuide", ns)
local routes, count, questRows, talks = ns.Data.routes, 0, 0, 0
local function valid(point)
    if point.x == nil then return end
    assert(type(point.uiMapID) == "number" and point.uiMapID > 0)
    assert(point.x >= 0 and point.x <= 1 and point.y >= 0 and point.y <= 1)
    assert(point.coordFrame == "live" or point.coordFrame == "era")
    if point.coordFrame == "era" then assert(point.continentID and point.worldX and point.worldY) end
end
for _, route in pairs(routes) do
    local ids = {}
    for index, step in ipairs(route.steps) do
        count = count + 1
        assert(step.index == index and not ids[step.id]); ids[step.id] = true
        valid(step)
        for _, target in ipairs(step.objectiveTargets or {}) do
            valid(target)
            assert(target.questID == step.questID and target.objectiveIndex > 0)
        end
        if step.questID then assert(type(step.questTitle) == "string" and step.questTitle ~= "") end
        if step.sourceKind == "talk" and step.questID then
            talks = talks + 1
            assert(step.kind == "complete", "Quest conversations must auto-track")
        end
        if step.kind == "accept" or step.kind == "complete" or step.kind == "turnin" then
            questRows = questRows + 1
            local task = {}; for k,v in pairs(step) do task[k]=v end
            -- Test the completion contract independently of entry filters/gates.
            task.conditions,task.races,task.classes,task.faction=nil,nil,nil,nil
            local q = {known=true,on=true,complete=false,turned=false,objectives={}}
            local api = {Character=function() return {level=60,class="HUNTER",race="Orc",faction="Horde"} end,
                Quest=function(_, id) if id == task.questID then return q else return {known=true,turned=true} end end}
            local engine = ns.Engine.New({routes={a={steps={task}}}}, {routeID="a"}, api)
            local done = engine:StepState(task)
            assert(done == (task.kind == "accept"), "Active incomplete quest: "..route.id.."/"..step.id)
            q.complete=true; engine.questCache={}
            done=engine:StepState(task)
            assert(done == (task.kind ~= "turnin"), "Ready is not rewarded: "..route.id.."/"..step.id)
            q.turned=true; q.on=false; engine.questCache={}
            assert(engine:StepState(task), "Rewarded quest must advance")
        end
    end
end
local chains=0
for faction, starts in pairs(ns.Data.starts) do
    for race, id in pairs(starts) do
        chains=chains+1
        local visited={}
        while id do
            assert(not visited[id], "Route cycle: "..race); visited[id]=true
            local route=assert(routes[id], "Missing chapter")
            assert(route.faction == faction)
            if not route.next then
                local finish=false
                for _, s in ipairs(route.steps) do if s.kind=="level" and s.level==60 then finish=true end end
                assert(finish and route.endLevel==60, "Chain stops before 60")
            end
            id=route.next
        end
    end
end
assert(chains==10 and count==9237 and talks==36)
print("PASS all "..count.." route rows, "..questRows.." quest state contracts, "..talks.." conversations and "..chains.." level-60 chains")

local mapped, inventory=0,0
for _,route in pairs(routes) do
    for _,step in ipairs(route.steps) do
        if step.kind=="complete" and step.objectiveTargets then
            if step.inventoryOnly then
                inventory=inventory+1
            else
                local point=false
                for _,target in ipairs(step.objectiveTargets) do if target.x then point=true end end
                if point then mapped=mapped+1 end
            end
        end
        if step.questID==99411 and step.sourceKind=="use" then
            assert(step.x and step.text:find("Use",1,true), "Feeding Kyle keeps item-use instruction and gains a real position")
        end
    end
end
assert(mapped>=92 and inventory==11)
print("PASS all supplemented task destinations and eleven inventory actions")

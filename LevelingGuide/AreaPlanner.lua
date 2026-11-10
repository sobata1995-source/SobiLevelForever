-- Bounded, quest-state-aware routing on one map. Straight-line estimates only.
local _, ns = ...
local Planner = {}
ns.AreaPlanner = Planner
local WORK = {kill=true, collect=true, talk=true, interact=true}
local function number(n) return type(n)=="number" and n==n and n>=0 and n<math.huge end

function Planner.Build(engine)
    local api, chapter, route = engine.api, engine:Chapter(), engine:GetRoute()
    if not route or not chapter or not api.DistanceTo or not api.DistanceBetween then return end
    local base, recovery = engine:GetPlannedActionStep()
    if not base or not base.questID or base.escort or (base.kind~="complete" and base.kind~="accept" and base.kind~="turnin") then return end
    if type(base.classes)=="table" then return end -- Preserve class-unlock milestones.
    if base.kind=="complete" and not WORK[base.sourceKind] then return end
    local baseDistance=api:DistanceTo(base)
    if not number(baseDistance) then return end
    local tasks, seen, canAccept = {}, {}, true
    if recovery and baseDistance<=1200 then
        local key=base.kind..":"..base.questID..":"..(base.objectiveIndex or 0)
        tasks[#tasks+1]={step=base,index=chapter.index,distance=baseDistance,key=key,recovering=true}
        seen[key]=true
    end
    for index=chapter.index,math.min(chapter.index+160,#route.steps) do
        local step=route.steps[index]
        if index>chapter.index and step.kind~="accept" and step.kind~="turnin" and step.kind~="complete" and step.kind~="goto" then
            if not (step.kind=="train" and engine.state.options.training~=true) then canAccept=false end
        end
        if step.questID and not chapter.marks[index] and not engine:IsFiltered(step)
            and not step.escort and not (type(step.group)=="number" and step.group>1 and engine.state.options.group~=true)
            and engine:BlockAllowed(step,true)==true then
            local quest=engine:Quest(step.questID)
            local eligible=false
            if quest.known==true and not quest.turned then
                if step.kind=="complete" and WORK[step.sourceKind] and step.objectiveIndex and quest.on==true and quest.complete==false then
                    local done,kind=engine:StepState(step,true)
                    eligible=not done and kind=="quest"
                elseif step.kind=="turnin" and quest.on==true and quest.complete==true then eligible=true
                elseif step.kind=="accept" and canAccept and index<=chapter.index+80 and quest.on==false then
                    eligible=engine:AcceptAvailability(step)==true
                end
            end
            if eligible then
                local distance=api:DistanceTo(step)
                local key=step.kind..":"..step.questID..":"..(step.objectiveIndex or 0)
                if number(distance) and distance<=1200 and not seen[key] then
                    seen[key]=true
                    tasks[#tasks+1]={step=step,index=index,distance=distance,key=key}
                end
            end
        end
    end
    if #tasks==0 then return end
    -- Finish adjacent hub interactions first; otherwise batch field objectives
    -- before travelling back to a quest giver while nearby work remains.
    local hasWork=false
    for _,task in ipairs(tasks) do if task.step.kind=="complete" then hasWork=true end end
    local pool={}
    for _,task in ipairs(tasks) do
        if not hasWork or task.step.kind=="complete" or task.distance<=40
            or (ns.QuestEfficiency and engine.state.options.speedLeveling~=false and task.step.kind=="turnin") then pool[#pool+1]=task end
    end
    table.sort(pool,function(a,b) if a.distance==b.distance then return a.index<b.index end return a.distance<b.distance end)
    while #pool>12 do table.remove(pool) end
    local first=1
    local byEfficiency=false
    if ns.QuestEfficiency then first,byEfficiency=ns.QuestEfficiency.Choose(engine,pool) end
    if not byEfficiency then
        for i,task in ipairs(pool) do
            if task.key==engine.lastAreaTask and task.distance<=pool[1].distance+90 then first=i;break end
        end
    end
    local ordered={table.remove(pool,first)}
    local distances={}
    local function between(a,b)
        local key=a.key.."/"..b.key
        if distances[key]==nil then
            local value=api:DistanceBetween(a.step,b.step)
            distances[key]=number(value) and value or math.huge
            distances[b.key.."/"..a.key]=distances[key]
        end
        return distances[key]
    end
    while #pool>0 do
        local best,cost=1,math.huge
        for i,task in ipairs(pool) do local d=between(ordered[#ordered],task);if d<cost then best,cost=i,d end end
        ordered[#ordered+1]=table.remove(pool,best)
    end
    -- Improve the estimated open path; keep the active first target stable.
    for _=1,2 do
        for i=2,#ordered-1 do for j=i+1,#ordered do
            local old=between(ordered[i-1],ordered[i])+(ordered[j+1] and between(ordered[j],ordered[j+1]) or 0)
            local new=between(ordered[i-1],ordered[j])+(ordered[j+1] and between(ordered[i],ordered[j+1]) or 0)
            if new+1<old then local a,b=i,j;while a<b do ordered[a],ordered[b]=ordered[b],ordered[a];a,b=a+1,b-1 end end
        end end
    end
    local nearby={}
    for _,task in ipairs(ordered) do if between(ordered[1],task)<=220 then nearby[#nearby+1]=task end end
    engine.lastAreaTask=ordered[1].key
    return {selected=ordered[1],tasks=nearby,queue=ordered,recovering=ordered[1].recovering==true}
end

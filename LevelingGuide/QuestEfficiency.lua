-- Forecasts, not measured completion times. Reward/source provenance is bundled.
-- Kill XP/level scaling follow the published Polestar model and game rules.
local _,ns=...
local Efficiency={};ns.QuestEfficiency=Efficiency
local function finite(n) return type(n)=="number" and n==n and n>=0 and n<math.huge end
local function killXP(level,mob)
    local base=5*level+45
    if mob>=level then return base*(1+.05*math.min(4,mob-level)) end
    local gray=level<=5 and 0 or level<=39 and level-math.floor(level/10)-5 or level<=59 and level-math.floor(level/5)-1 or level-9
    if mob<=gray then return 0 end
    local zero=level<=7 and 5 or level<=9 and 6 or level<=11 and 7 or level<=15 and 8 or level<=19 and 9 or level<=29 and 11
        or level<=39 and 12 or level<=44 and 13 or level<=49 and 14 or level<=54 and 15 or level<=59 and 16 or 17
    return math.max(0,(5*mob+45)*(1-(level-mob)/zero))
end
local function findPoint(engine,id,index,kind)
    local route=engine:GetRoute()
    if not route then return end
    for _,step in ipairs(route.steps) do
        if step.questID==id and step.kind==kind and (not index or step.objectiveIndex==index) and step.x
            and not engine:IsFiltered(step) then return step end
    end
end
function Efficiency.Estimate(engine,task)
    local step,api=task.step,engine.api
    if not step.questID or (step.kind~="complete" and step.kind~="turnin") or not api.WalkingDistanceTo or not api.WalkingDistanceBetween then return end
    local model=ns.QuestEfficiencyData and ns.QuestEfficiencyData[step.questID]
    local quest=engine:Quest(step.questID)
    if not model or not finite(model.xp) or model.xp==0 or not finite(model.level) or model.level<1 or quest.on~=true or quest.turned then return end
    local walking=api:WalkingDistanceTo(step)
    if not finite(walking) then return end
    local level=engine.character.level
    local over=level-model.level
    local share=over<=5 and 1 or over>=10 and .1 or ({.8,.6,.4,.2})[over-5]
    local xp,work=model.xp*share,0
    if api.ObservedQuestReward then
        local observed=api:ObservedQuestReward(step.questID,level)
        if finite(observed) then xp=observed end
    end
    if step.kind=="turnin" then
        if quest.complete~=true then return end
    else
        if type(quest.objectives)~="table" or #quest.objectives~=model.objectiveCount then return end
        local mobs,points={},{}
        for index,objective in ipairs(quest.objectives) do
            if not objective.finished then
                if not finite(objective.numRequired) or not finite(objective.numFulfilled) or objective.numRequired<=0 then return end
                local remaining=math.max(0,objective.numRequired-objective.numFulfilled)
                if remaining>0 then
                    local data=model.objectives[index]
                    if not data then return end
                    if data.killsPerUnit then
                        local mob=data.mobLevel
                        if not finite(mob) or mob<1 or mob>level+3 then return end
                        local key=data.npcID or ("objective"..index)
                        local kills=remaining*data.killsPerUnit*1.043
                        if not mobs[key] or mobs[key].kills<kills then mobs[key]={kills=kills,level=mob} end
                    else work=work+6*remaining end
                    local point=index==step.objectiveIndex and step or findPoint(engine,step.questID,index,"complete")
                    if not point then return end
                    if point~=step then points[#points+1]=point end
                end
            end
        end
        for _,mob in pairs(mobs) do
            local delta=mob.level-level
            local factor=delta>=0 and 1+.1*delta or math.max(.5,1+.05*delta)
            work=work+mob.kills*(11+19*(math.min(60,level)-1)/59)*factor
            xp=xp+mob.kills*killXP(level,mob.level)
        end
        local previous=step
        for _,point in ipairs(points) do
            local length=api:WalkingDistanceBetween(previous,point)
            if not finite(length) then return end
            walking=walking+length;previous=point
        end
        local handin=findPoint(engine,step.questID,nil,"turnin")
        if not handin then return end
        local home=api:WalkingDistanceBetween(previous,handin)
        if not finite(home) then return end
        walking=walking+home
    end
    local seconds=math.max(6,work+walking/7+6)
    return {rate=xp*60/seconds,xp=xp,seconds=seconds,walking=walking,basis="estimate"}
end
function Efficiency.Choose(engine,tasks)
    if engine.state.options.speedLeveling==false then return 1,false end
    for _,task in ipairs(tasks) do task.efficiency=Efficiency.Estimate(engine,task) end
    -- Missing timing/path coverage never silently demotes the source's next task.
    if not tasks[1].efficiency then return 1,false end
    local best,comparable=1,0
    for i,task in ipairs(tasks) do
        if task.efficiency then
            comparable=comparable+1
            if task.efficiency.rate>tasks[best].efficiency.rate*1.15 then best=i end
        end
    end
    if comparable<2 then return 1,false end
    for i,task in ipairs(tasks) do
        if task.key==engine.lastAreaTask and task.efficiency and task.efficiency.rate>=tasks[best].efficiency.rate*.85 then return i,true end
    end
    return best,true
end

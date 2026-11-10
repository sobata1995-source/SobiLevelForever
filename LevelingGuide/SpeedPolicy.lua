-- Conservative speed-guide pruning: keep the dependency closure of core quests.
local _,ns=...
local Policy={};ns.SpeedPolicy=Policy
local PROFESSIONS={[164]=true,[165]=true,[171]=true,[182]=true,[185]=true,[186]=true,[197]=true,[202]=true,[333]=true,[356]=true,[393]=true}
local function contains(list,value)
    if type(list)~="table" then return true end
    for _,v in ipairs(list) do if v==value then return true end end
    return false
end
function Policy.Build(engine)
    local records={}
    for _,route in pairs(engine.data.routes) do
        if engine:IsRouteEligible(route) then
            for _,step in ipairs(route.steps) do
                if step.questID and contains(step.classes,engine.character.class) and contains(step.races,engine.character.race) then
                    local row=records[step.questID]
                    if not row then row={dependencies={},skills={},optional=false,profession=false,classQuest=false,group=false,core=false};records[step.questID]=row end
                    if step.professionID then row.skills[step.professionID]=true end
                    row.classQuest=row.classQuest or type(step.classes)=="table"
                    row.optional=row.optional or step.optional==true
                    row.profession=row.profession or step.professionID~=nil or (step.questTitle or ""):find("Camping 101:",1,true)~=nil
                    row.group=row.group or (type(step.group)=="number" and step.group>1)
                    if step.kind=="accept" then row.accept=step;row.hasMandatoryAccept=row.hasMandatoryAccept or not step.optional end
                    for _,key in ipairs({"requiresAny","requiresAll"}) do for _,id in ipairs(step[key] or {}) do row.dependencies[id]=true end end
                    for _,condition in ipairs(step.conditions or {}) do
                        if condition.k=="skill" and not condition.neg and condition.skillLine then row.skills[condition.skillLine]=true end
                        if condition.k=="dungeon" and not condition.neg and engine.state.options.dungeons~=true then row.group=true end
                        if condition.k=="group" and not condition.neg and engine.state.options.group~=true then row.group=true end
                        if not condition.neg and (condition.k=="turnedin" or condition.k=="complete" or condition.k=="onquest") then
                            if type(condition.q)=="table" then for _,id in ipairs(condition.q) do row.dependencies[id]=true end
                            elseif type(condition.q)=="number" then row.dependencies[condition.q]=true end
                        end
                    end
                end
            end
        end
    end
    local keep={}
    local function protect(id)
        if keep[id] then return end
        keep[id]=true
        local row=records[id]
        if row then for dependency in pairs(row.dependencies) do protect(dependency) end end
    end
    for id,row in pairs(records) do
        if row.classQuest or ((not row.optional or row.hasMandatoryAccept) and not row.profession and not row.group) then protect(id) end
    end
    local skills={}
    for id in pairs(keep) do if records[id] then for skill in pairs(records[id].skills) do skills[skill]=true end end end
    return {records=records,keep=keep,skills=skills}
end
function Policy.Excluded(engine,step)
    if engine.state.options.speedLeveling==false then return false end
    if not engine.speedPolicy then engine.speedPolicy=Policy.Build(engine) end
    if not step.questID then
        return step.kind=="train" and PROFESSIONS[step.skillLineID]==true and not engine.speedPolicy.skills[step.skillLineID]
    end
    local row=engine.speedPolicy.records[step.questID]
    if not row or engine.speedPolicy.keep[step.questID] then return false end
    -- Finished work is still worth handing in; do not abandon anything in-game.
    local quest=engine:Quest(step.questID)
    if quest.turned or (quest.on and quest.complete) then return false end
    return row.optional or row.profession or row.group
end

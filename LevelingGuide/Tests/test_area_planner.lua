local ns={}
assert(loadfile("LevelingGuide/Engine.lua"))("LevelingGuide",ns)
assert(loadfile("LevelingGuide/AreaPlanner.lua"))("LevelingGuide",ns)
local function task(kind,q,x,oi)
    return {id="s"..q..kind,kind=kind,questID=q,questTitle="Quest "..q,sourceKind=kind=="complete" and "kill" or kind,
        objectiveIndex=oi,uiMapID=1,x=x,y=0,coordFrame="live"}
end
local function harness()
    local model={quests={},px=0,missingPosition=false}
    local steps={task("complete",1,.9,1),task("turnin",1,.95),task("complete",2,.1,1),task("complete",3,.15,1),task("turnin",2,.95)}
    local api={}
    function api:Character() return {faction="Horde",race="Orc",class="HUNTER",level=6} end
    function api:Quest(id) return model.quests[id] or {known=true,on=false,complete=false,turned=false} end
    function api:DistanceTo(step)
        if model.missingPosition or step.uiMapID~=1 or not step.x then return nil end
        return math.abs(step.x-model.px)*1000
    end
    function api:DistanceBetween(a,b) if a.uiMapID~=b.uiMapID then return nil end return math.abs(a.x-b.x)*1000 end
    model.engine=ns.Engine.New({routes={a={id="a",faction="Horde",steps=steps}}},{routeID="a"},api)
    model.steps=steps
    for id=1,3 do model.quests[id]={known=true,on=true,complete=false,turned=false,objectives={{finished=false}}} end
    return model
end
do
    local m=harness();m.engine:Start()
    assert(m.engine:GetActionStep().questID==2,"Pick closer active quest instead of fixed distant source order")
    assert(#m.engine.areaPlan.tasks==2,"Batch nearby quests in the same area")
    assert(m.engine:Chapter().index==1,"Do not rewrite saved source cursor")
    assert(m.engine:View().canNext==false,"Next cannot mark an unrelated source step complete")
    m.engine:Next(false)
    assert(m.engine:Chapter().index==1 and not m.engine:Chapter().marks[1])
    m.quests[2].complete=true;m.quests[2].objectives[1].finished=true;m.engine:Refresh()
    assert(m.engine:GetActionStep().questID==3,"Do adjacent field work before distant turn-in")
    m.engine:SetOption("smartRoute",false)
    assert(m.engine:GetActionStep().questID==1,"Allow original guide order")
end
do
    local m=harness();m.quests[2].complete=true;m.steps[5].x=.02;m.engine:Start()
    assert(m.engine:GetActionStep().kind=="turnin" and m.engine:GetActionStep().questID==2,"Ready hand-in at an adjacent NPC is useful now")
end
do
    local m=harness();m.steps[3].uiMapID=2;m.quests[3].known=false;m.engine:Start()
    assert(m.engine:GetActionStep().questID==1,"Never optimize unknown quest state or another map")
    m.missingPosition=true;m.engine:Refresh()
    assert(not m.engine.areaPlan,"Missing world positions fall back to source order")
end
do
    local m=harness();m.steps[3].escort=true;m.steps[4].conditions={{k="turnedin",q=99}}
    m.engine:Start();assert(m.engine:GetActionStep().questID==1,"Respect escorts and unmet conditions")
    assert(not m.engine:Chapter().blocks["4"],"Do not latch speculative future conditions")
end
do
    local m=harness();m.engine:Start();m.engine:Next(true)
    assert(m.engine:Chapter().marks[3]=="skip" and not m.engine:Chapter().marks[1],"Skip applies to displayed nearby task only")
end
print("PASS nearby quest grouping, readiness, distance, progression and fallback regressions")

do
 local m=harness()
 m.engine:Chapter().index=2
 m.steps[1].x=.01
 m.engine:Start()
 local action,recovering=m.engine:GetActionStep()
 assert(action.questID==1 and action.kind=="complete" and recovering,"Retain closer unfinished objectives during hand-in recovery")
 m.engine:Next(false)
 assert(m.engine:Chapter().index==2,"Never mark premature hand-in complete")
end
print("PASS grouped route preserves unfinished hand-in recovery")

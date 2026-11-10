local ns={}
assert(loadfile("LevelingGuide/Engine.lua"))("LevelingGuide",ns)
assert(loadfile("LevelingGuide/QuestEfficiency.lua"))("LevelingGuide",ns)
ns.QuestEfficiencyData={
 [1]={xp=100,level=7,objectiveCount=1,modeled=true,objectives={{kind="kill",count=4,killsPerUnit=1,npcID=10,mobLevel=7}}},
 [2]={xp=1000,level=7,objectiveCount=1,modeled=true,objectives={{kind="kill",count=4,killsPerUnit=1,npcID=20,mobLevel=7}}},
}
local steps={
 {kind="complete",sourceKind="kill",questID=1,objectiveIndex=1,x=.1,y=.1},
 {kind="turnin",questID=1,x=.2,y=.1},
 {kind="complete",sourceKind="kill",questID=2,objectiveIndex=1,x=.3,y=.1},
 {kind="turnin",questID=2,x=.4,y=.1},
}
local quests={}
for id=1,2 do quests[id]={known=true,on=true,complete=false,turned=false,objectives={{text="Target",numFulfilled=0,numRequired=4,finished=false}}} end
local missing=false
local api={
 Character=function() return {class="HUNTER",faction="Horde",race="Orc",level=7} end,
 Quest=function(_,id) return quests[id] end,
 WalkingDistanceTo=function(_,step) if not missing then return 70 end end,
 WalkingDistanceBetween=function(_,a,b) if not missing then return 70 end end,
}
local engine=ns.Engine.New({routes={a={steps=steps}}},{routeID="a"},api)
local tasks={{step=steps[1],distance=10,key="a"},{step=steps[3],distance=20,key="b"}}
local selected,ranked=ns.QuestEfficiency.Choose(engine,tasks)
assert(ranked and selected==2,"Favor better total XP/time when comparable workloads and paths are known")
assert(tasks[2].efficiency.basis=="estimate","Never label modeled time as measured")
assert(tasks[2].efficiency.walking==140,"Include both arrival and hand-in walking")
assert(tasks[2].efficiency.xp>1000,"Include expected kill XP, not just reward XP")
quests[2].objectives[1].numFulfilled=3
engine.questCache={}
local nearDone=ns.QuestEfficiency.Estimate(engine,tasks[2])
assert(nearDone.seconds<tasks[2].efficiency.seconds,"Use remaining work instead of charging completed objectives again")
missing=true
selected,ranked=ns.QuestEfficiency.Choose(engine,tasks)
assert(selected==1 and not ranked,"Unknown path costs preserve the baseline route")
missing=false
ns.QuestEfficiencyData[1]=nil
selected,ranked=ns.QuestEfficiency.Choose(engine,tasks)
assert(selected==1 and not ranked,"An unmeasured baseline task is not silently demoted")
ns.QuestEfficiencyData[1]={xp=100,level=7,objectiveCount=1,modeled=true,objectives={{kind="kill",killsPerUnit=1,npcID=10,mobLevel=7}}}
quests[2].complete=true;engine.questCache={}
local reward=ns.QuestEfficiency.Estimate(engine,{step=steps[4]})
assert(reward.xp==1000 and reward.seconds==16,"A ready hand-in needs travel and interaction only")
engine.state.options.speedLeveling=false
selected,ranked=ns.QuestEfficiency.Choose(engine,tasks)
assert(selected==1 and not ranked)
assert(loadfile("LevelingGuide/QuestEfficiencyData.lua"))("LevelingGuide",ns)
local count=0
for _,model in pairs(ns.QuestEfficiencyData) do assert(type(model.xp)=="number" and model.xp>=0);count=count+1 end
assert(count==2021)
print("PASS 2021 XP rewards, forecast ranking, remaining work, walking costs and safe unknown-data fallback")

engine.state.options.speedLeveling=true
ns.QuestEfficiencyData[1]={xp=100,level=7,objectiveCount=2,modeled=false,objectives={[2]={kind="collect",killsPerUnit=1,npcID=10,mobLevel=7}}}
quests[1].objectives={{finished=true},{finished=false,numFulfilled=0,numRequired=4}}
engine.questCache={}
local second={kind="complete",sourceKind="collect",questID=1,objectiveIndex=2,x=.1,y=.1}
assert(ns.QuestEfficiency.Estimate(engine,{step=second}),"A finished objective needs no remaining-time estimate")
api.ObservedQuestReward=function(_,id,level) if id==2 then return 900 end end
local observed=ns.QuestEfficiency.Estimate(engine,{step=steps[4]})
assert(observed.xp==900,"Prefer a server-observed reward at the same level")
print("PASS completed unknown objectives and real reward overrides")

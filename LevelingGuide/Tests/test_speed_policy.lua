local ns={}
assert(loadfile("LevelingGuide/Engine.lua"))("LevelingGuide",ns)
assert(loadfile("LevelingGuide/SpeedPolicy.lua"))("LevelingGuide",ns)
local steps={
 {kind="accept",questID=1,optional=true,questTitle="Optional detour"},
 {kind="accept",questID=2,optional=true,questTitle="Required prerequisite"},
 {kind="accept",questID=3,requiresAny={2},questTitle="Main chain"},
 {kind="accept",questID=4,questTitle="Camping 101: Cooking"},
 {kind="accept",questID=5,optional=true,classes={"HUNTER"},questTitle="Hunter ability"},
 {kind="accept",questID=6,group=3,questTitle="Elite detour"},
}
local quests={}
local api={Character=function() return {class="HUNTER",race="Skyborne",faction="Horde",level=7} end,
 Quest=function(_,id) return quests[id] or {known=true,on=false,complete=false,turned=false} end}
local engine=ns.Engine.New({routes={a={id="a",faction="Horde",steps=steps}}},{routeID="a"},api)
assert(engine:IsFiltered(steps[1]),"Omit optional detour")
assert(not engine:IsFiltered(steps[2]),"Keep optional prerequisite of core chain")
assert(not engine:IsFiltered(steps[3]),"Keep core chain")
assert(engine:IsFiltered(steps[4]),"Omit unneeded profession trip")
assert(not engine:IsFiltered(steps[5]),"Keep class progression")
assert(engine:IsFiltered(steps[6]),"Omit solo-unfriendly group content")
assert(not engine:IsFiltered({kind="train",text="Train your class abilities"}),"Training remains enabled and skippable")
quests[1]={known=true,on=true,complete=true,turned=false};engine.questCache={}
assert(not engine:IsFiltered(steps[1]),"Do not throw away an already finished optional hand-in")
engine:SetOption("speedLeveling",false)
assert(not engine:IsFiltered(steps[4]),"Allow full-guide mode")
print("PASS speed pruning, prerequisite closure, class quests and ready rewards")

engine:SetOption("speedLeveling",true)
assert(engine:IsFiltered({kind="train",skillLineID=185,text="Train Cooking"}),"Skip irrelevant profession training")
assert(not engine:IsFiltered({kind="train",skillLineID=762,text="Train Riding"}),"Keep movement training")
assert(loadfile("LevelingGuide/Data/Routes.lua"))("LevelingGuide",ns)
local profiles=0
for faction,starts in pairs(ns.Data.starts) do
 for race,routeID in pairs(starts) do
  for _,class in ipairs({"HUNTER","WARRIOR","MAGE","PRIEST","WARLOCK","ROGUE","DRUID","SHAMAN","PALADIN"}) do
   local real=ns.Engine.New(ns.Data,{routeID=routeID},{Character=function() return {faction=faction,race=race,class=class,level=7} end})
   local policy=ns.SpeedPolicy.Build(real)
   for id in pairs(policy.keep) do
    local record=policy.records[id]
    if record then for dependency in pairs(record.dependencies) do assert(policy.keep[dependency],"Speed pruning broke a required chain") end end
   end
   profiles=profiles+1
  end
 end
end
assert(profiles==90)
print("PASS speed prerequisite closure across all 90 faction/race/class test profiles")

local ns={}
assert(loadfile("LevelingGuide/Engine.lua"))("LevelingGuide",ns)
local function route(id,faction,low,high,quest,races)
    return {id=id,title=id,faction=faction,startLevel=low,endLevel=high,races=races,steps={{kind="accept",questID=quest}}}
end
local data={routes={done=route("done","Alliance",1,10,1),rewarded=route("rewarded","Alliance",1,10,2),now=route("now","Alliance",1,10,3),old=route("old","Alliance",1,5,4),future=route("future","Alliance",10,20,5),wrongSide=route("wrongSide","Horde",1,10,6),wrongRace=route("wrongRace","Alliance",1,10,7,{"Dwarf"})},routeOrder={"done","rewarded","now","old","future","wrongSide","wrongRace"}}
local engine=ns.Engine.New(data,{routeID="now",chapters={done={index=2}}},{
 Character=function() return {level=7,faction="Alliance",race="Human",class="HUNTER"} end,
 Quest=function(_,id) return {known=true,on=id==3,turned=id==2,complete=false} end,
})
local choices=engine:GetRouteChoices()
assert(#choices==5,"Show all faction/race-compatible chapters, including future and completed routes")
local summaries={}
for _,choice in ipairs(choices) do summaries[choice.id]=choice.summary end
assert(summaries.future:find("Upcoming",1,true),"Future chapters show their level and Upcoming status")
assert(summaries.done:find("Done",1,true) and summaries.rewarded:find("Done",1,true),"Completed chapters remain visible and labelled")
assert(summaries.old:find("Earlier",1,true),"Earlier chapters remain visible")
engine.state.routeID="old"
engine.state.chapters.old={index=1}
engine.api.Quest=function(_,id) return {known=true,on=id==4,turned=id==2,complete=false} end
choices=engine:GetRouteChoices()
local preserved=false
for _,choice in ipairs(choices) do if choice.id=="old" then preserved=choice.summary:find("Active quests",1,true)~=nil end end
assert(preserved,"Keep current chapter with active unfinished quests even after outlevelling it")
engine.state.routeID="now"
engine.state.chapters.old.index=2
choices=engine:GetRouteChoices()
preserved=false
for _,choice in ipairs(choices) do if choice.id=="old" then preserved=true end end
assert(preserved,"An active quest overrides an accidental finished cursor in another chapter")
assert(loadfile("LevelingGuide/Data/Routes.lua"))("LevelingGuide",ns)
local count=0
for faction,starts in pairs(ns.Data.starts) do
 for race,routeID in pairs(starts) do
  local profile={faction=faction,race=race,class="HUNTER",level=7}
  local real=ns.Engine.New(ns.Data,{routeID=routeID},{Character=function() return profile end,Quest=function() return {known=true,on=false,turned=false,complete=false} end})
  for _,choice in ipairs(real:GetRouteChoices()) do
   local chapter=ns.Data.routes[choice.id]
   assert(chapter.faction==faction)
  end
  count=count+1
 end
end
assert(count==10)
print("PASS all-level route menu, progress labels and all Alliance/Horde race starts")

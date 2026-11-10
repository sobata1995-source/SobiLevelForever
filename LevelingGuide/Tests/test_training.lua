local ns={}
assert(loadfile("LevelingGuide/ClassTrainerIDs.lua"))("LevelingGuide",ns)
assert(loadfile("LevelingGuide/Training.lua"))("LevelingGuide",ns)
local level,npc,filters,rows=6,251376,true,{}
UnitGUID=function() return "Creature-0-0-0-0-"..npc.."-00000001" end
UnitClass=function() return "Hunter","HUNTER" end
UnitLevel=function() return level end
GetTrainerServiceTypeFilter=function() return filters end
GetNumTrainerServices=function() return #rows end
GetTrainerServiceInfo=function(i) return rows[i][1],rows[i][2],1,rows[i][3] end
local progress={};local tracker=ns.Training.New(progress)
tracker:OnEvent("TRAINER_CLOSED")
assert(not tracker:AlreadyTrained({class="HUNTER",level=6}),"A visit alone is not training")
rows={{"Known skill","used",6},{"New skill","available",6},{"Future skill","unavailable",8}}
tracker:OnEvent("TRAINER_SHOW")
assert(not tracker:AlreadyTrained({class="HUNTER",level=6}),"Available skills must prevent automatic skip")
rows[2][2]="used";tracker:OnEvent("TRAINER_UPDATE")
assert(tracker:AlreadyTrained({class="HUNTER",level=6}),"Confirm a fully trained catalogue")
assert(tracker:AlreadyTrained({class="HUNTER",level=7}),"Remember no new catalogue skills before next threshold")
assert(not tracker:AlreadyTrained({class="HUNTER",level=8}),"New training level is not automatically complete")
assert(not tracker:AlreadyTrained({class="WARRIOR",level=6}),"Evidence is class-specific")
local reloaded=ns.Training.New(progress)
assert(reloaded:AlreadyTrained({class="HUNTER",level=6}),"Evidence survives reload")
rows[2][2]="unavailable";tracker:OnEvent("TRAINER_UPDATE")
assert(not tracker:AlreadyTrained({class="HUNTER",level=6}),"Missing prerequisites for eligible skill are not completion")
filters=false
local unknown=ns.Training.New({});unknown:OnEvent("TRAINER_SHOW")
assert(not unknown:AlreadyTrained({class="HUNTER",level=6}),"Hidden service filters cannot prove training")
filters=true;npc=999999
rows={{"Future","unavailable",8}}
unknown:OnEvent("TRAINER_SHOW")
assert(not unknown:AlreadyTrained({class="HUNTER",level=6}),"A profession or unknown trainer cannot clear class training")
assert(loadfile("LevelingGuide/Engine.lua"))("LevelingGuide",ns)
local task={kind="train",text="Train your class abilities"}
local engine=ns.Engine.New({routes={a={steps={task}}}},{routeID="a"},{Character=function() return {class="HUNTER",level=6} end,AlreadyTrained=function() return true end})
local done,reason=engine:StepState(task)
assert(done and reason=="trained","Engine skips only positively confirmed training")
print("PASS trainer identity, catalogue state, pending skills, thresholds and saved evidence")

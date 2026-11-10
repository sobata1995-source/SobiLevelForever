local ns={}
assert(loadfile("LevelingGuide/TerrainRouter.lua"))("LevelingGuide",ns)
local time,callback,cancelled=0,nil,0
GetTime=function() return time end
UnitFactionGroup=function() return "Horde" end
InCombatLockdown=function() return false end
SobiLevelNavEngine={
 Find=function(map,from,to,cb,opts) callback=cb;assert(opts.style=="roads");return {} end,
 Cancel=function() cancelled=cancelled+1 end,
 Sight=function() return false end,
}
local router=ns.TerrainRouter.New()
local from={map=2991,x=0,y=0,z=10}
local goal={map=2991,x=100,y=0,z=10}
local p,length,reason=router:GetLeg(from,goal)
assert(not p and reason:find("Finding",1,true),"Never use a direct arrow while calculating")
callback({{map=2991,x=0,y=0},{map=2991,x=0,y=50},{map=2991,x=100,y=50},{map=2991,x=100,y=0}},200)
p,length=router:GetLeg(from,goal)
assert(p.x==0 and p.y==50 and length==200,"Follow first obstacle-avoiding corner, not the destination")
p,length=router:GetLeg({map=2991,x=0,y=50},goal)
assert(p.x==100 and p.y==50 and length==150,"Advance to the next corner after reaching it")
local old=callback
router:GetLeg(from,{map=2991,x=200,y=0})
old({{x=0,y=0},{x=999,y=999}},100)
assert(not router.points,"Ignore stale response for previous goal")
callback(nil,"unreachable")
p,length,reason=router:GetLeg(from,{map=2991,x=200,y=0})
assert(not p and reason:find("unreachable",1,true),"An unreachable goal must never fall back through obstacles")
time=15
router:GetLeg(from,goal)
callback({{x=0,y=0},{x=0,y=50},{x=100,y=50},{x=100,y=0}},200)
time=20
p,length,reason=router:GetLeg({map=2991,x=-100,y=-100},goal)
assert(not p and reason:find("Recalculating",1,true),"Replan when the player leaves the corridor")
router:Stop()
assert(not router.points and not router.pending and cancelled>0)
assert(not router:GetLeg({map=0,x=0,y=0},goal),"Never mix instance coordinate frames")
print("PASS terrain corners, pending/failure safety, cancellation and deviation replanning")

local ns = {}
assert(loadfile("LevelingGuide/Data/Routes.lua"))("LevelingGuide", ns)
assert(loadfile("LevelingGuide/Guidance.lua"))("LevelingGuide", ns)
local route = ns.Data.routes["forever/horde/skyborne/01-zephras-isle"]
local step = route.steps[45]
assert(step.kind == "train" and not step.x)
for class, id in pairs({HUNTER=251376, WARRIOR=251964, ROGUE=251389, SHAMAN=251374, DRUID=251373}) do
    local target = ns.Guidance.Resolve(route, step, {class=class})
    assert(target.x and target.y and target.uiMapID == 2521 and target.coordFrame == "live")
    local found = false
    for _, source in ipairs(route.steps) do
        if source.npcID == id and source.x == target.x and source.y == target.y then found = true end
    end
    assert(found, "Must use that class trainer's recorded position")
    local view = {stepText=step.text, stepHint="Manual step"}
    ns.Guidance.Describe(target, view)
    assert(view.stepText:find(target.npcName,1,true) and view.stepText:find("Done",1,true))
end
assert(not step.x, "Never mutate completion data")
assert(ns.Guidance.Resolve(route, step, {class="MAGE"}) == step, "Unknown trainer must not use another class")
local later = {kind="train", blockTitle="Valanaar"}
assert(ns.Guidance.Resolve(route,later,{class="HUNTER"}) == later, "Never send later training back to starter village")
print("PASS class trainer guidance regressions")

for kind, label in pairs({accept="ACCEPT QUEST", complete="DO QUEST", turnin="TURN IN QUEST"}) do
    local step = {kind=kind, questID=123, questTitle="Source quest name", npcName="Quest NPC", text="Kill wolves"}
    local view = {stepText=step.text, stepHint="2/8"}
    ns.Guidance.Describe(step, view, {title="In-game quest name", on=true, complete=false})
    assert(view.questTitle == "In-game quest name")
    assert(view.stepText:find(label,1,true) and view.stepText:find("In-game quest name",1,true))
    if kind == "complete" then assert(view.stepText:find("Kill wolves",1,true) and view.stepText:find("2/8",1,true)) end
    if kind == "turnin" then assert(view.stepText:find("NOT READY",1,true)) end
    local fallback = {}
    ns.Guidance.Describe(step, fallback, {})
    assert(fallback.questTitle == "Source quest name")
end
print("PASS explicit quest names, actions, objectives and localized-title fallback")

local itemView = {}
ns.Guidance.Describe({kind="accept",questID=184,questTitle="Furlbrow's Deed",itemID=1971,itemName="Westfall Deed"},itemView)
assert(itemView.stepText:find("Use Westfall Deed",1,true))
assert(not itemView.stepText:find("Talk to the quest giver",1,true))
print("PASS item-start quests do not invent an NPC destination")

for _, routeID in ipairs({"forever/horde/skyborne/01-zephras-isle", "forever/alliance/skyborne/01-zephras-isle"}) do
    local found=false
    for _,step in ipairs(ns.Data.routes[routeID].steps) do
        if step.questID==96101 and step.kind=="turnin" then
            local target=step.objectiveTargets[2]
            assert(target.x and target.y and target.uiMapID==2521)
            assert(step.objectiveTargets[1].optional==true and not target.optional)
            local view={}
            ns.Guidance.Describe(target,view,{title="The Great Outdoors",objectives={{},{text="Gain Boosted Rest"}}})
            assert(view.stepText:find("/sit",1,true) and view.stepText:find("Boosted Rest",1,true))
            found=true
        end
    end
    assert(found)
end
print("PASS Great Outdoors campfire coordinates and explicit sitting instructions")

local multipleView={}
ns.Guidance.Describe({kind="complete",questID=123,questTitle="Restocking the Larders",objectiveIndex=1},multipleView,
    {title="Restocking the Larders",objectives={
        {text="0/3 Small Egg",numFulfilled=0,numRequired=3,finished=false},
        {text="Strider Meat",numFulfilled=2,numRequired=8,finished=false},
    }})
assert(multipleView.stepText:find("0/3 Small Egg",1,true))
assert(multipleView.stepText:find("2/8 Strider Meat",1,true))
local _,count=multipleView.stepText:gsub("0/3","")
assert(count==1,"Never duplicate a native objective counter")
assert(multipleView.stepText:find("> 0/3",1,true),"Mark the arrow's current objective")
print("PASS all current quest objectives displayed with unduplicated counters")

local grouped={areaTasks={{step={questID=1,kind="complete",questTitle="Eggs"}},{step={questID=2,kind="complete",questTitle="Hippogryphs"}}}}
ns.Guidance.Describe({kind="complete",questID=1,questTitle="Eggs",text="Collect eggs"},grouped)
assert(grouped.stepText:find("NEARBY QUESTS",1,true) and grouped.stepText:find("Hippogryphs",1,true))
print("PASS nearby quest names are visible in the guide")

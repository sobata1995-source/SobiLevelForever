-- Player-flow regressions for the guide engine, with real bundled-data smoke.
local checks = 0
local function eq(label, actual, expected)
    checks = checks + 1
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function truth(label, value) eq(label, not not value, true) end
local function Route(id, steps, nextID)
    return {id = id, title = id, faction = "Horde", startLevel = 1, endLevel = 60, steps = steps, next = nextID}
end
local function Data(steps)
    return {routes = {a = Route("a", steps)}, routeOrder = {"a"}}
end
local function Harness(data, progress, character)
    local ns = {}
    assert(loadfile("LevelingGuide/Engine.lua"))("LevelingGuide", ns)
    local model = {
        quests = {}, items = {}, skills = {}, money = 0, location = false,
        character = character or {race = "Orc", class = "HUNTER", faction = "Horde", level = 1, xp = 0, maxXP = 100},
        writes = 0,
    }
    local api = {}
    function api:Character()
        local copy = {}; for key, value in pairs(model.character) do copy[key] = value end
        return copy
    end
    function api:Quest(id)
        model.questReads = (model.questReads or 0) + 1
        return model.quests[id] or {known = true, on = false, complete = false, turned = false}
    end
    function api:ItemCount(id) return model.items[id] end
    function api:SkillRank(id) return model.skills[id] end
    function api:Money() return model.money end
    function api:AtLocation() return model.location end
    for _, operation in ipairs({"AcceptQuest", "TurnInQuest", "AbandonQuest", "ChooseReward", "MovePlayer"}) do
        api[operation] = function() model.writes = model.writes + 1; error("engine changed gameplay") end
    end
    model.progress = progress or {options={training=true}}
    model.engine = ns.Engine.New(data, model.progress, api)
    return model
end

do
    local condition = {{k = "onquest", q = 10}}
    local m = Harness(Data({
        {kind = "turnin", questID = 10, conditions = condition, blockID = 1},
        {kind = "accept", questID = 11, conditions = condition, blockID = 1},
        {kind = "note", text = "Continue", blockID = 2},
    }))
    m.quests[10] = {known = true, on = true, complete = true, turned = false}
    m.engine:Start(); eq("turn-in waits before history flag", m.engine:GetStep().questID, 10)
    m.quests[10] = {known = true, on = false, complete = false, turned = true}
    m.engine:Refresh()
    eq("latched onquest block keeps follow-up accept", m.engine:GetStep().questID, 11)
    local saved = m.progress
    local restored = Harness(m.engine.data, saved)
    restored.quests[10] = m.quests[10]
    restored.engine:Start()
    eq("block latch survives reload", restored.engine:GetStep().questID, 11)
    restored.quests[11] = {known = true, on = true, complete = false, turned = false}
    restored.engine:Refresh()
    eq("follow-up accept auto advances", restored.engine:GetStep().kind, "note")
end

do
    local conditions = {{k = "skill", skillLine = 43, op = ">=", n = 1}}
    local m = Harness(Data({
        {kind = "note", conditions = conditions, blockID = 4},
        {kind = "accept", questID = 22, conditions = conditions, blockID = 4},
        {kind = "note", blockID = 5},
    }))
    local view = m.engine:Start()
    eq("unknown skill condition requires review", view.status, "CHECK THIS STEP")
    eq("unknown condition not silently skipped", m.engine:Chapter().index, 1)
    m.engine:Next(false)
    eq("Done explicitly latches reviewed block", m.engine:GetStep().questID, 22)
    eq("reviewed following accept remains actionable", m.engine:View().status, "TRACKING QUEST")
    eq("guide Done never learns skill or accepts quest", m.writes, 0)
end

do
    local m = Harness(Data({
        {kind = "complete", questID = 30, objectiveIndex = 2},
        {kind = "turnin", questID = 30},
        {kind = "note"},
    }))
    m.quests[30] = {known = true, on = true, complete = false, turned = false, objectives = {
        {finished = true, numFulfilled = 5, numRequired = 5},
        {finished = false, numFulfilled = 2, numRequired = 5, text = "Collect proof"},
    }}
    m.engine:Start()
    eq("unrelated finished objective does not advance", m.engine:Chapter().index, 1)
    truth("partial objective shows actual count", m.engine:View().stepHint:find("2/5", 1, true))
    m.quests[30].objectives[2].numFulfilled = 5
    m.engine:Refresh()
    eq("specific objective complete moves to turn-in", m.engine:Chapter().index, 2)
    m.quests[30].complete = true -- reward dialog/objective ready, no turn-in history
    m.engine:Refresh()
    eq("reward dialog never counts as turned in", m.engine:Chapter().index, 2)
    m.quests[30].on, m.quests[30].complete = false, false -- abandoned
    m.engine:Refresh()
    eq("abandonment never counts as turned in", m.engine:Chapter().index, 2)
    eq("abandoned quest clearly blocked", m.engine:View().status, "CHECK PREREQUISITES")
    m.quests[30].turned = true
    m.engine:Refresh()
    eq("actual turn-in advances", m.engine:GetStep().kind, "note")
end

do
    local m = Harness(Data({
        {kind = "accept", questID = 40, minLevel = 5, requiresAny = {41, 42}, requiresAll = {43}},
        {kind = "note"},
    }))
    m.engine:Start(); eq("low level accept blocked", m.engine:View().status, "CHECK PREREQUISITES")
    m.character.level = 5; m.quests[42] = {known = true, turned = true, on = false, complete = false}
    m.engine:Refresh(); eq("all prerequisite still required", m.engine:Chapter().index, 1)
    m.quests[43] = {known = true, turned = true, on = false, complete = false}
    m.engine:Refresh(); eq("prerequisites permit accept but do not auto accept", m.engine:View().status, "TRACKING QUEST")
    eq("accept remains until log evidence", m.engine:Chapter().index, 1)
    m.quests[40] = {known = true, turned = false, on = true, complete = false}
    m.engine:Refresh(); eq("actual acceptance advances", m.engine:Chapter().index, 2)
    eq("no gameplay mutations", m.writes, 0)
    local p = Harness(Data({{kind = "accept", questID = 50, closedBy = {51}}, {kind = "note"}}))
    p.quests[51] = {known = true, turned = false, on = true, complete = false}
    p.engine:Start(); eq("alternate active quest closes obsolete accept", p.engine:Chapter().index, 2)
    eq("closed reason retained", p.engine:Chapter().marks[1], "closed")
end

do
    local m = Harness(Data({
        {kind = "note", classes = {"MAGE"}},
        {kind = "note", races = {"Tauren"}},
        {kind = "note", faction = "Alliance"},
        {kind = "note", text = "Hunter / Orc"},
    }))
    m.engine:Start(); eq("class race faction irrelevant steps skipped", m.engine:Chapter().index, 4)
    eq("filters recorded", m.engine:Chapter().marks[1], "filter")
    local level = Harness(Data({{kind = "level", level = 10, levelFraction = .5}, {kind = "note"}}))
    level.character.level, level.character.xp = 10, 49
    level.engine:Start(); eq("fractional XP threshold waits", level.engine:Chapter().index, 1)
    level.character.xp = 50; level.engine:Refresh()
    eq("fractional XP threshold advances at correct boundary", level.engine:Chapter().index, 2)
    local maxed = Harness(Data({{kind = "level", level = 60}, {kind = "note"}}))
    maxed.character.level, maxed.character.maxXP = 60, 0
    maxed.engine:Start(); eq("level cap zero maxXP safe", maxed.engine:Chapter().index, 2)
end

do
    local data = {routes = {
        a = Route("a", {{kind = "level", level = 1}}, "b"),
        b = Route("b", {{kind = "note", text = "Next zone"}}),
    }, routeOrder = {"a", "b"}}
    local m = Harness(data)
    m.engine:Start(); eq("completed chapter chains", m.progress.routeID, "b")
    eq("prior chapter completion retained", m.progress.chapters.a.index, 2)
    local p = Harness(Data({{kind = "accept", questID = 60}, {kind = "note", text = "Current step"}}))
    p.quests[60] = {known = true, on = true, complete = false, turned = false}
    p.engine:Start(); p.engine:Prev()
    eq("Prev enters review", p.progress.review, true)
    p.engine:Refresh(); eq("review prevents immediate auto forward", p.engine:Chapter().index, 1)
    p.engine:Next(false); eq("Next exits review to progression", p.engine:Chapter().index, 2)
end

do
    local m = Harness(Data({{kind = "accept", questID = 70}, {kind = "turnin", questID = 70}, {kind = "note"}}))
    m.engine:Start(); m.engine:Next(false)
    eq("manual Next affects guide only", m.engine:Chapter().marks[1], "manual")
    eq("quest not actually accepted by Next", m.engine:Quest(70).on, false)
    m.engine:Next(true)
    eq("skip recorded separately", m.engine:Chapter().marks[2], "skip")
    eq("quest not actually turned in by Skip", m.engine:Quest(70).turned, false)
    eq("Next Skip no game writes", m.writes, 0)
    local p = Harness(Data({{kind = "accept", questID = 71}, {kind = "note"}}))
    p.engine:Start(); p.engine:SetPaused(true)
    p.quests[71] = {known = true, on = true, complete = false, turned = false}
    p.engine:Refresh(); eq("pause holds auto progress", p.engine:Chapter().index, 1)
    p.engine:SetPaused(false); eq("resume catches up accepted quest", p.engine:Chapter().index, 2)
end

do
    local data = Data({
        {kind = "note", conditions = {{k = "group"}}, blockID = 1},
        {kind = "note", conditions = {{k = "dungeon"}}, blockID = 2},
        {kind = "note", conditions = {{k = "group", neg = true}}, blockID = 3, text = "Solo fallback"},
    })
    local m = Harness(data); m.engine:Start()
    eq("solo defaults omit group and dungeon branches", m.engine:Chapter().index, 3)
    eq("solo fallback remains", m.engine:GetStep().text, "Solo fallback")
    local p = Harness(data, {options = {group = true, dungeons = true}})
    p.engine:Start(); eq("group option includes group branch", p.engine:Chapter().index, 1)
    p.engine:Next(false); eq("dungeon option includes dungeon branch", p.engine:Chapter().index, 2)
    p.engine:Next(false); eq("group mode omits negative solo fallback", p.engine:GetStep(), nil)
end

do
    local data = Data({{kind = "note"}, {kind = "complete", questID = 80}, {kind = "note"}})
    local m = Harness(data); m.engine:Start(); m.engine:Next(true); m.engine:SetPaused(true)
    local p = Harness(data, m.progress)
    p.engine:Start()
    eq("saved step resumes after reload", p.engine:Chapter().index, 2)
    eq("pause survives reload", p.progress.paused, true)
    eq("skip mark survives reload", p.engine:Chapter().marks[1], "skip")
    p.engine:SetPaused(false); p.engine:Next(true)
    p.quests[80] = {known = true, on = true, complete = false, turned = false}
    eq("Sync finds unfinished active quest", p.engine:Sync(), true)
    eq("Sync revisits skipped quest step", p.engine:Chapter().index, 2)
    eq("Sync removes only revisited skip", p.engine:Chapter().marks[2], nil)
    eq("Sync preserves unrelated prior skip", p.engine:Chapter().marks[1], "skip")
    p.quests[80].complete = true; p.engine:Refresh()
    eq("synced quest then auto advances normally", p.engine:Chapter().index, 3)
end

do
    local m = Harness(Data({{kind = "complete", questID = 90}, {kind = "note"}}))
    m.quests[90] = {known = false}
    m.engine:Start(); eq("unknown quest state is review not complete", m.engine:View().status, "CHECK THIS STEP")
    m.quests[90] = {known = true, on = true, complete = false, turned = false}
    m.engine:Refresh(); eq("newly available quest state refreshed", m.engine:View().status, "TRACKING QUEST")
    m.quests[90].complete = true; m.engine:Refresh()
    eq("cached quest state does not block later completion", m.engine:Chapter().index, 2)
end

do
    local data = Data({
        {kind = "note", text = "Current instruction"},
        {kind = "complete", questID = 95, blockID = 2, conditions = {{k = "onquest", q = 96}}},
        {kind = "note"},
    })
    local m = Harness(data)
    m.quests[95] = {known = true, on = true, complete = false, turned = false}
    m.engine:Start()
    eq("Sync does not match currently inapplicable objective", m.engine:Sync(), false)
    eq("Sync does not latch future false condition", m.engine:Chapter().blocks["2"], nil)
    m.quests[96] = {known = true, on = true, complete = false, turned = false}
    m.engine:Next(false)
    eq("condition may become applicable after Sync", m.engine:GetStep().questID, 95)
    local p = Harness(data)
    p.quests[95] = {known = true, on = true, complete = true, turned = false}
    p.quests[96] = {known = true, on = true, complete = false, turned = false}
    p.engine:Start(); p.engine:Sync()
    eq("Sync does not latch speculative true condition", p.engine:Chapter().blocks["2"], nil)
    p.quests[95].complete, p.quests[96].on = false, false
    p.engine:Next(false)
    eq("condition may become inapplicable after Sync", p.engine:Chapter().index, 3)
end

do
    local data = {routeOrder = {"a", "b"}, starts = {Horde = {Orc = "b"}}, routes = {
        a = Route("a", {{kind = "accept", questID = 98}}),
        b = Route("b", {{kind = "note", text = "Exact race start"}}),
    }}
    local m = Harness(data)
    m.engine:Start()
    eq("level one uses exact race start", m.progress.routeID, "b")
    eq("level one does not scan unrelated quest history", m.questReads or 0, 0)
end

do
    local data = Data({
        {kind = "accept", questID = 100, optional = true},
        {kind = "complete", questID = 100},
        {kind = "turnin", questID = 100},
        {kind = "accept", questID = 101, requiresAll = {100}},
        {kind = "complete", questID = 101},
        {kind = "turnin", questID = 101},
        {kind = "accept", questID = 102, requiresAny = {100, 101}},
        {kind = "complete", questID = 102},
        {kind = "note", text = "Continue the main route"},
    })
    local m = Harness(data)
    m.engine:Start(); m.engine:Next(true)
    eq("optional Skip omits its objectives and dependent chain", m.engine:Chapter().index, 9)
    truth("root optional intent retained", m.progress.skippedQuests[100])
    truth("dependent intent propagated", m.progress.skippedQuests[101])
    eq("optional objective skip recorded", m.engine:Chapter().marks[2], "skippedQuest")
    eq("optional turn-in skip recorded", m.engine:Chapter().marks[3], "skippedQuest")
    eq("all skipped alternatives suppress follow-up", m.engine:Chapter().marks[7], "skippedQuest")
    m.quests[100] = {known = true, on = true, complete = false, turned = false}
    eq("accepting a previously skipped optional quest allows Sync", m.engine:Sync(), true)
    eq("Sync returns to accepted optional objective", m.engine:Chapter().index, 2)
    eq("Sync clears later skipped quest marks", m.engine:Chapter().marks[4], nil)
    m.quests[100].complete = true; m.engine:Refresh()
    eq("accepted optional objective can complete normally", m.engine:Chapter().index, 3)
    m.quests[100].on, m.quests[100].turned = false, true
    m.engine:Refresh()
    eq("completing optional root restores its dependent accept", m.engine:Chapter().index, 4)
    eq("restored dependent accept waits for real acceptance", m.engine:View().status, "TRACKING QUEST")
end

do
    local m = Harness(Data({
        {kind = "accept", questID = 110, optional = true},
        {kind = "accept", questID = 111, requiresAny = {110, 112}},
        {kind = "note"},
    }))
    m.engine:Start(); m.engine:Next(true)
    eq("one unskipped alternative keeps follow-up in guide", m.engine:Chapter().index, 2)
    eq("unfulfilled alternative still requires prerequisite", m.engine:View().status, "CHECK PREREQUISITES")
    m.quests[112] = {known = true, on = false, complete = false, turned = true}
    m.engine:Refresh()
    eq("rewarded alternative permits follow-up", m.engine:View().status, "TRACKING QUEST")
    local p = Harness(Data({
        {kind = "accept", questID = 120}, {kind = "complete", questID = 120}, {kind = "turnin", questID = 120},
    }))
    p.engine:Start(); p.engine:Next(true)
    eq("ordinary mandatory Skip does not skip whole quest", p.engine:Chapter().index, 2)
    eq("ordinary mandatory Skip has no optional quest intent", p.progress.skippedQuests[120], nil)
end

do
    local m = Harness(Data({
        {kind = "accept", questID = 130, optional = true, requiresAll = {131}},
        {kind = "complete", questID = 130}, {kind = "turnin", questID = 130}, {kind = "note"},
    }))
    m.quests[131] = {known = true, on = false, complete = false, turned = true}
    m.engine:Start(); m.engine:Next(true)
    eq("explicit optional Skip remains a user decision with fulfilled prerequisite", m.engine:Chapter().index, 4)
    local done = m.engine:StepState(m.engine:GetRoute().steps[2])
    eq("explicit optional intent is not confused with inherited skips", done, true)
end

do
    local m = Harness(Data({
        {kind = "accept", questID = 140, closedBy = {141}},
        {kind = "complete", questID = 140}, {kind = "turnin", questID = 140}, {kind = "note"},
    }))
    m.quests[141] = {known = true, on = true, complete = false, turned = false}
    m.engine:Start()
    eq("alternate quest closure omits impossible later stages", m.engine:Chapter().index, 4)
    m.quests[140] = {known = true, on = true, complete = false, turned = false}
    eq("actual active quest can recover from prior closure", m.engine:Sync(), true)
    eq("closedBy recovery returns to real active objective", m.engine:Chapter().index, 2)
    eq("recovered active quest is not blocked by old closure", m.engine:View().status, "TRACKING QUEST")
end

do
    local m = Harness(Data({
        {kind = "accept", questID = 150, optional = true, professionID = 164, professionName = "Blacksmithing", professionRank = 50},
        {kind = "note"},
    }))
    m.engine:Start()
    eq("unknown profession requires manual prerequisite check", m.engine:View().status, "CHECK PREREQUISITES")
    truth("unknown profession identifies required skill and rank", m.engine:View().stepHint:find("Blacksmithing rank 50", 1, true))
    m.skills[164] = 49; m.engine:Refresh()
    eq("known insufficient profession rank blocks accept", m.engine:View().status, "CHECK PREREQUISITES")
    eq("profession gate never skips or accepts automatically", m.engine:Chapter().index, 1)
    m.skills[164] = 50; m.engine:Refresh()
    eq("profession at required rank permits acceptance", m.engine:View().status, "TRACKING QUEST")
    eq("valid profession still waits for actual quest acceptance", m.engine:Chapter().index, 1)
end

-- Actual data: verify race starts through the engine, not just table presence;
-- evaluate every bundled goal and check chapter links terminate.
do
    local ns = {}
    assert(loadfile("LevelingGuide/Data/Routes.lua"))("LevelingGuide", ns)
    local data = ns.Data
    do
        local id = data.starts.Alliance.Human
        local route, first, objective, turnin = data.routes[id]
        for index, step in ipairs(route.steps) do
            if step.questID == 91741 and step.kind == "accept" then first = index end
            if step.questID == 91743 and step.kind == "complete" then objective = step end
            if step.questID == 91743 and step.kind == "turnin" then turnin = step end
        end
        assert(first and objective and turnin, "Human optional chain fixtures missing")
        local m = Harness(data, {routeID = id, chapters = {[id] = {index = first}}},
            {faction = "Alliance", race = "Human", class = "HUNTER", level = 1, xp = 0, maxXP = 100})
        m.engine:Start(); m.engine:Next(true)
        truth("actual optional book chain propagates first dependency", m.progress.skippedQuests[92124])
        truth("actual optional book chain propagates second dependency", m.progress.skippedQuests[91743])
        local objectiveDone, objectiveReason = m.engine:StepState(objective)
        eq("actual later book collection omitted after optional Skip", objectiveDone, true)
        eq("actual later book collection has intentional skip reason", objectiveReason, "skippedQuest")
        local turninDone = m.engine:StepState(turnin)
        eq("actual later book turn-in omitted after optional Skip", turninDone, true)
    end
    for faction, starts in pairs(data.starts) do
        for race, id in pairs(starts) do
            local m = Harness(data, nil, {faction = faction, race = race, class = "HUNTER", level = 1, xp = 0, maxXP = 100})
            m.engine:Start()
            eq("real starter selection " .. faction .. " " .. race, m.progress.routeID, id)
        end
    end
    local evaluated = 0
    for _, id in ipairs(data.routeOrder) do
        local route = data.routes[id]
        local race = route.races and route.races[1] or (route.faction == "Horde" and "Orc" or "Human")
        local m = Harness(data, {routeID = id}, {faction = route.faction, race = race, class = "HUNTER", level = 40, xp = 25, maxXP = 100})
        for _, step in ipairs(route.steps) do
            local ok, done, reason = pcall(m.engine.StepState, m.engine, step)
            assert(ok, "Actual route failed " .. id .. " " .. tostring(step.id) .. ": " .. tostring(done))
            assert(type(done) == "boolean" and type(reason) == "string", "Invalid step status in " .. id)
            evaluated = evaluated + 1
        end
        local visited, nextID = {}, id
        while nextID do
            assert(not visited[nextID], "Chapter cycle at " .. nextID)
            visited[nextID] = true
            local nextRoute = assert(data.routes[nextID], "Missing linked chapter " .. nextID)
            assert(nextRoute.faction == route.faction, "Cross-faction chapter link " .. nextID)
            nextID = nextRoute.next
        end
    end
    eq("all bundled goals evaluate without runtime errors", evaluated, data.provenance.stepCount)
    truth("actual data smoke exercised more than 9000 goals", evaluated > 9000)
end

print("PASS: " .. checks .. " engine flow checks plus every bundled goal")

-- Generic training is an optional reminder, not evidence of unlearned spells.
do
    local steps = {{kind="train", text="Train your class abilities"}, {kind="note", text="Continue questing"}}
    local m = Harness(Data(steps), {options={training=false}})
    m.engine:Start()
    eq("disabled setting skips generic training reminder", m.engine:GetStep().text, "Continue questing")
    eq("training is not recorded as learned", m.engine:Chapter().marks[1], "trainingOptional")
    local enabled = Harness(Data(steps), {options={training=true}})
    enabled.engine:Start()
    eq("explicit reminder setting keeps trainer step", enabled.engine:GetStep().kind, "train")
    enabled.engine:SetOption("training", false)
    eq("disabling reminder releases current trainer step", enabled.engine:GetStep().kind, "note")
end

-- Positive reward history survives reloads; objectives and abandonment do not.
do
    local data = Data({{kind="turnin", questID=900}, {kind="note", text="Next task"}})
    local m = Harness(data)
    m.quests[900] = {turned=true, on=false, complete=false, known=true}
    m.engine:Start()
    eq("observed reward saved per character", m.progress.completedQuests[900], true)
    local restored = Harness(data, m.progress)
    restored.quests[900] = {known=false}
    restored.engine:Start()
    eq("reward history survives missing API data after reload", restored.engine:Quest(900).turned, true)
    restored.quests[900] = {on=true, turned=false, complete=false, known=true}
    restored.engine:Refresh()
    eq("active reaccepted quest overrides saved reward", restored.engine:Quest(900).turned, false)
    local other = Harness(data)
    other.engine:Start()
    eq("another character does not inherit reward history", other.progress.completedQuests[900], nil)
    local ready = Harness(data)
    ready.quests[900] = {on=true, turned=false, complete=true, known=true}
    ready.engine:Start()
    eq("ready to turn in is never saved as rewarded", ready.progress.completedQuests[900], nil)
    ready.quests[900] = {on=false, turned=false, complete=false, known=true}
    ready.engine:Refresh()
    eq("abandonment is never saved as rewarded", ready.progress.completedQuests[900], nil)
end

-- An unfinished turn-in recovers actual outstanding objectives without rewinding.
do
    local steps = {
        {kind="complete", questID=901, objectiveIndex=1, text="Kill wolves", x=.2, y=.3, uiMapID=1},
        {kind="complete", questID=901, objectiveIndex=2, text="Collect pelts", x=.4, y=.5, uiMapID=1},
        {kind="turnin", questID=901, text="Turn in", x=.8, y=.9, uiMapID=1},
        {kind="note", text="Next quest"},
    }
    local m = Harness(Data(steps), {routeID="a",chapters={a={index=3}}})
    m.quests[901] = {on=true, complete=false, turned=false, known=true, objectives={{finished=true},{finished=false}}}
    m.engine:Start()
    local action, recovering = m.engine:GetActionStep()
    eq("recover unfinished objective only", action.objectiveIndex, 2)
    eq("recover objective destination, not turn-in destination", action.x, .4)
    eq("recovery active", recovering, true)
    eq("recovery preserves planned cursor", m.engine:Chapter().index, 3)
    m.engine:Next(false)
    eq("Done cannot falsely hand in recovery quest", m.engine:Chapter().index, 3)
    m.quests[901].complete=true
    m.engine:Refresh()
    eq("ready quest now points to hand-in", m.engine:GetActionStep().kind, "turnin")
    m.quests[901].turned=true; m.quests[901].on=false
    m.engine:Refresh()
    eq("reward automatically selects next task", m.engine:GetStep().text, "Next quest")
    local missing = Harness(Data({steps[3], steps[4]}))
    missing.quests[901] = {on=true, complete=false, turned=false, known=true}
    missing.engine:Start()
    eq("missing objective data never points to hand-in", missing.engine:GetActionStep().x, nil)
    eq("missing objective data asks to finish quest", missing.engine:GetActionStep().kind, "complete")
end

-- Travel is obsolete only with positive evidence for every following task.
do
    local steps = {{kind="goto", blockID=1}, {kind="accept", blockID=1, questID=902}, {kind="note", blockID=2, text="Continue"}}
    local m = Harness(Data(steps))
    m.quests[902] = {on=true, complete=false, turned=false, known=true}
    m.engine:Start()
    eq("do not travel back to accept an active quest", m.engine:GetStep().text, "Continue")
    local unknown = Harness(Data(steps))
    unknown.quests[902] = {known=false}
    unknown.engine:Start()
    eq("unknown state cannot skip travel", unknown.engine:GetStep().kind, "goto")
    local pending = Harness(Data({steps[1], steps[2], {kind="accept", blockID=1, questID=903}}))
    pending.quests[902] = {on=true, complete=false, turned=false, known=true}
    pending.engine:Start()
    eq("new quest in same area preserves necessary travel", pending.engine:GetStep().kind, "goto")
    local handin = Harness(Data({steps[1], {kind="turnin", blockID=1, questID=902}}))
    handin.quests[902] = {on=true, complete=true, turned=false, known=true}
    handin.engine:Start()
    eq("ready hand-in still requires travel", handin.engine:GetStep().kind, "goto")
end
print("PASS saved quest history, recovery navigation and obsolete-travel regressions")

-- Whole-quest checkpoints pick the remaining corrected objective dynamically.
do
    local target1={kind="complete",questID=950,objectiveIndex=1,text="First",x=.1,y=.1,uiMapID=1}
    local target2={kind="complete",questID=950,objectiveIndex=2,text="Explore cave",x=.2,y=.2,uiMapID=1}
    local task={kind="complete",questID=950,text="Finish quest",objectiveTargets={target1,target2}}
    local m=Harness(Data({task,{kind="turnin",questID=950}}))
    m.quests[950]={known=true,on=true,turned=false,complete=false,objectives={{finished=true},{finished=false}}}
    m.engine:Start()
    eq("whole goal picks remaining event objective", m.engine:GetActionStep().text, "Explore cave")
    eq("whole goal uses event destination", m.engine:GetActionStep().x, .2)
    m.quests[950].objectives[2].finished=true; m.quests[950].complete=true
    m.engine:Refresh()
    eq("whole goal automatically advances when ready", m.engine:GetActionStep().kind, "turnin")
end
print("PASS dynamic corrected whole-quest destinations")

do
    local optional={kind="complete",questID=96101,objectiveIndex=1,optional=true}
    local required={kind="complete",questID=96101,objectiveIndex=2,text="Gain Boosted Rest",x=.417,y=.448,uiMapID=2521}
    local m=Harness(Data({{kind="turnin",questID=96101,objectiveTargets={optional,required}}}))
    m.quests[96101]={known=true,on=true,complete=false,turned=false,objectives={{finished=false},{finished=false}}}
    m.engine:Start()
    eq("mandatory campfire buff takes priority over optional sitting counter",m.engine:GetActionStep().objectiveIndex,2)
    eq("campfire recovery keeps destination",m.engine:GetActionStep().x,.417)
end
print("PASS optional campfire objective never hides required buff")

do
 local m=Harness(Data({{kind="train",text="Train your class abilities"},{kind="note",text="Continue"}}),{options={}})
 m.engine:Start()
 eq("training reminders enabled by default",m.engine:GetStep().kind,"train")
 m.engine:Next(true)
 eq("Skip moves past training without changing character skills",m.engine:GetStep().text,"Continue")
end

do
 local m=Harness(Data({{kind="accept",questID=990},{kind="complete",questID=990,objectiveIndex=1},{kind="turnin",questID=990},{kind="note",text="Current"}}),{routeID="a",chapters={a={index=4}}})
 m.quests[990]={known=true,on=false,turned=true,complete=false}
 m.engine:Start();m.engine:Prev()
 eq("Prev never reopens rewarded quest at first row",m.engine:Chapter().index,4)
 eq("Prev disabled if only rewarded quests precede current row",m.engine:View().canPrev,false)
 local ready=Harness(Data({{kind="complete",questID=991,objectiveIndex=1},{kind="turnin",questID=991},{kind="note",text="Current"}}),{routeID="a",chapters={a={index=3}}})
 ready.quests[991]={known=true,on=true,turned=false,complete=true,objectives={{finished=true}}}
 ready.engine:Start();ready.engine:Prev()
 eq("Prev still allows an unclaimed hand-in",ready.engine:Chapter().index,2)
 ready.engine:Prev()
 eq("Prev skips fulfilled objective before that hand-in",ready.engine:Chapter().index,2)
end
print("PASS Prev hides rewarded quests and fulfilled objectives without hiding ready hand-ins")

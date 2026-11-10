-- SobiLevel Forever: deterministic guide progress, independent of the WoW UI.
-- Copyright (c) 2026 SobiLevel Forever contributors. GPL-3.0-only.
local _, ns = ...
local Engine = {}
ns.Engine = Engine

local function Number(value, fallback)
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
        return fallback
    end
    return value
end

local function Contains(list, value)
    if type(list) ~= "table" then return true end
    for _, entry in ipairs(list) do if entry == value then return true end end
    return false
end

local function Call(self, key, ...)
    local fn = self.api[key]
    if type(fn) == "function" then return fn(self.api, ...) end
end

local function Compare(value, op, expected)
    if value == nil or expected == nil then return nil end
    if op == ">=" or op == nil then return value >= expected end
    if op == "<" then return value < expected end
    if op == ">" then return value > expected end
    if op == "<=" then return value <= expected end
    if op == "==" or op == "=" then return value == expected end
    if op == "~=" or op == "!=" then return value ~= expected end
    return nil
end

function Engine.New(data, progress, api)
    local self = setmetatable({ data = data, state = progress, api = api or {}, questCache = {} }, { __index = Engine })
    if type(progress.chapters) ~= "table" then progress.chapters = {} end
    if type(progress.options) ~= "table" then progress.options = {} end
    if progress.options.training == nil then progress.options.training = true end
    if progress.options.speedLeveling == nil then progress.options.speedLeveling = true end
    if type(progress.skippedQuests) ~= "table" then progress.skippedQuests = {} end
    if type(progress.closedQuests) ~= "table" then progress.closedQuests = {} end
    if type(progress.completedQuests) ~= "table" then progress.completedQuests = {} end
    progress.schema = 1
    progress.paused = progress.paused == true
    progress.review = progress.review == true
    self:ReadCharacter()
    return self
end

function Engine:ReadCharacter()
    self.character = Call(self, "Character") or self.character or {}
    if self.character.race == "Undead" then self.character.race = "Scourge" end
    self.character.level = Number(self.character.level, 1)
    local maxXP = Number(self.character.maxXP, 0)
    local fraction = maxXP > 0 and Number(self.character.xp, 0) / maxXP or 0
    self.levelValue = self.character.level + math.max(0, math.min(.999999, fraction))
end

function Engine:Quest(id)
    if not id then return { known = false } end
    if not self.questCache[id] then
        local source = Call(self, "Quest", id) or { known = false }
        local quest = {}
        for key, value in pairs(source) do quest[key] = value end
        if quest.turned == true then self.state.completedQuests[id] = true end
        -- An active quest is authoritative (including a reaccepted repeatable).
        -- Never persist objective completion: abandonment must remain unfinished.
        if quest.on ~= true and self.state.completedQuests[id] == true then
            quest.turned = true
        end
        self.questCache[id] = quest
    end
    return self.questCache[id]
end

function Engine:IsRouteEligible(route)
    return route and (not route.faction or route.faction == self.character.faction)
        and Contains(route.races, self.character.race)
end

function Engine:Chapter(id)
    id = id or self.state.routeID
    if not id then return nil end
    local chapter = self.state.chapters[id]
    if type(chapter) ~= "table" then
        chapter = { index = 1, marks = {}, blocks = {} }
        self.state.chapters[id] = chapter
    end
    chapter.index = math.max(1, math.floor(Number(chapter.index, 1)))
    if type(chapter.marks) ~= "table" then chapter.marks = {} end
    if type(chapter.blocks) ~= "table" then chapter.blocks = {} end
    return chapter
end

function Engine:GetRoute()
    return self.data.routes[self.state.routeID]
end

function Engine:GetStep()
    local route, chapter = self:GetRoute(), self:Chapter()
    return route and chapter and route.steps[chapter.index] or nil
end

function Engine:GetPlannedActionStep()
    local step = self:GetStep()
    if not step or self.state.review or not step.questID then return step, false end
    local handIn = step.kind == "turnin"
    if not handIn and not (step.kind == "complete" and not step.objectiveIndex) then return step, false end
    local quest = self:Quest(step.questID)
    if quest.turned or quest.on ~= true or quest.complete ~= false then return step, false end
    -- Corrected per-objective destinations also fill holes in whole-quest goals.
    for _, target in ipairs(step.objectiveTargets or {}) do
        local objective = quest.objectives and quest.objectives[target.objectiveIndex]
        if objective and not target.optional then
            local done = objective.finished == true
                or (type(objective.numRequired) == "number" and objective.numRequired > 0
                    and type(objective.numFulfilled) == "number" and objective.numFulfilled >= objective.numRequired)
            if not done then return target, handIn end
        end
    end
    -- A planned turn-in is not a destination until its objectives are done.
    -- Keep the chapter cursor intact; recover only this quest's unfinished work.
    local route = self:GetRoute()
    for _, candidate in ipairs(route.steps) do
        if candidate.kind == "complete" and candidate.questID == step.questID
            and candidate ~= step and (candidate.objectiveIndex or candidate.x)
            and not self:IsFiltered(candidate) and self:BlockAllowed(candidate, true) == true then
            local done = self:StepState(candidate, true)
            if not done then return candidate, handIn end
        end
    end
    if not handIn then return step, false end
    local task = {}
    for key, value in pairs(step) do task[key] = value end
    task.kind, task.text = "complete", "Finish the remaining objectives in your quest log before returning to the quest giver."
    task.x, task.y, task.uiMapID, task.detail = nil, nil, nil, nil
    return task, true
end

function Engine:GetActionStep()
    if self.areaPlan then return self.areaPlan.selected.step, self.areaPlan.recovering end
    return self:GetPlannedActionStep()
end

function Engine:TravelAlreadySatisfied(step)
    if not step.blockID then return false end
    local route, chapter, found = self:GetRoute(), self:Chapter(), false
    for i = chapter.index + 1, #route.steps do
        local nextStep = route.steps[i]
        if nextStep.blockID ~= step.blockID then break end
        if not self:IsFiltered(nextStep) then
            if nextStep.questID and (nextStep.kind == "accept" or nextStep.kind == "complete" or nextStep.kind == "turnin") then
                -- Only positive quest evidence makes this journey obsolete.
                local q = self:Quest(nextStep.questID)
                local satisfied = q.turned == true
                    or (nextStep.kind == "accept" and q.on == true)
                    or (nextStep.kind == "complete" and q.on == true and q.complete == true)
                if not satisfied and nextStep.kind == "complete" and q.on == true and nextStep.objectiveIndex then
                    local objective = q.objectives and q.objectives[nextStep.objectiveIndex]
                    satisfied = objective and (objective.finished == true
                        or (type(objective.numRequired) == "number" and objective.numRequired > 0
                            and type(objective.numFulfilled) == "number" and objective.numFulfilled >= objective.numRequired))
                end
                if not satisfied then return false end
                found = true
            elseif nextStep.kind ~= "goto" then
                return false -- Do not discard travel needed for another activity.
            end
        end
    end
    return found
end

function Engine:RecommendRoute()
    self:ReadCharacter()
    self.questCache = {}
    local starts = self.data.starts and self.data.starts[self.character.faction]
    local startID = starts and starts[self.character.race]
    if self.character.level == 1 and startID and self:IsRouteEligible(self.data.routes[startID]) then return startID end
    local bestID, bestScore
    for _, id in ipairs(self.data.routeOrder or {}) do
        local route = self.data.routes[id]
        if self:IsRouteEligible(route) then
            local low = Number(route.startLevel, 1)
            local high = Number(route.endLevel, 60)
            local score = -math.abs(self.character.level - low)
            if self.character.level < low then score = score - 1000 end
            if self.character.level > high then score = score - 100 end
            local seen = {}
            for _, step in ipairs(route.steps or {}) do
                if step.questID and not seen[step.questID] then
                    seen[step.questID] = true
                    local quest = self:Quest(step.questID)
                    if quest.on and Contains(step.classes, self.character.class) and Contains(step.races, self.character.race) then
                        score = score + 200
                    end
                end
            end
            if not bestScore or score > bestScore then bestID, bestScore = id, score end
        end
    end
    return bestID
end

function Engine:Start()
    if not self:IsRouteEligible(self:GetRoute()) then
        self.state.routeID = self:RecommendRoute()
        self.state.review = false
        if self.character.level > 1 then
            self.state.notice = "Starting from your current level. Check earlier quest prerequisites; Routes lets you choose another chapter."
        end
    end
    self:Chapter()
    return self:Refresh()
end

function Engine:ChooseRoute(id)
    if not self:IsRouteEligible(self.data.routes[id]) then return false end
    self.state.routeID, self.state.review, self.state.notice = id, false, nil
    self:Chapter()
    self:Refresh()
    return true
end

function Engine:Condition(condition)
    local kind, value = condition.k, nil
    if kind == "onquest" then
        local ids = type(condition.q) == "table" and condition.q or { condition.q }
        value = false
        local unknown = false
        for _, id in ipairs(ids) do
            local quest = self:Quest(id)
            if quest.on == true then value = true; break end
            if quest.on == nil then unknown = true end
        end
        if not value and unknown then value = nil end
    elseif kind == "complete" then
        local quest = self:Quest(condition.q)
        if quest.on ~= nil and quest.complete ~= nil then value = quest.on and quest.complete end
    elseif kind == "turnedin" then
        value = self:Quest(condition.q).turned
    elseif kind == "group" then
        value = self.state.options.group == true
    elseif kind == "dungeon" then
        value = self.state.options.dungeons == true
    elseif kind == "level" then
        value = Compare(self.levelValue, condition.op, Number(condition.n, 0) + Number(condition.frac, 0))
    elseif kind == "money" then
        value = Compare(Call(self, "Money"), condition.op, condition.n)
    elseif kind == "skill" then
        value = Compare(Call(self, "SkillRank", condition.skillLine, condition.name), condition.op, condition.n or 1)
    elseif kind == "has" then
        value = Compare(Call(self, "ItemCount", condition.item), condition.op, condition.n or 1)
    end
    if value ~= nil and condition.neg then value = not value end
    return value
end

function Engine:BlockAllowed(step, readOnly)
    if type(step.conditions) ~= "table" or #step.conditions == 0 then return true end
    local chapter = self:Chapter()
    local key = tostring(step.blockID or chapter.index)
    if chapter.blocks[key] ~= nil then return chapter.blocks[key] end
    local unknown = false
    for _, condition in ipairs(step.conditions) do
        local allowed = self:Condition(condition)
        if allowed == false then
            if not readOnly then chapter.blocks[key] = false end
            return false
        end
        if allowed == nil then unknown = true end
    end
    if unknown then return nil end
    -- A quest turn-in may change the block's condition before its follow-up accept.
    -- Latch once for the whole block, including through reloads.
    if not readOnly then chapter.blocks[key] = true end
    return true
end

function Engine:IsFiltered(step)
    return not Contains(step.classes, self.character.class) or not Contains(step.races, self.character.race)
        or (step.faction and step.faction ~= self.character.faction)
        or (ns.SpeedPolicy and ns.SpeedPolicy.Excluded(self,step)) or false
end

function Engine:AcceptAvailability(step)
    for _, id in ipairs(step.closedBy or {}) do
        local quest = self:Quest(id)
        if quest.on or quest.turned then return "closed" end
    end
    if step.minLevel and self.character.level < step.minLevel then
        return false, "Requires level " .. step.minLevel .. ". Gain XP, or use Skip to move past this guide step."
    end
    if step.professionID then
        local rank = Call(self, "SkillRank", step.professionID, step.professionName)
        local required = Number(step.professionRank, 1)
        if rank == nil or rank < required then
            return false, "Requires " .. (step.professionName or "profession #" .. step.professionID) .. " rank " .. required
                .. ". Check your profession; Skip this optional quest if it does not apply to you."
        end
    end
    local any = step.requiresAny
    if type(any) == "table" and #any > 0 then
        local found, unknown = false, false
        for _, id in ipairs(any) do
            local turned = self:Quest(id).turned
            if turned then found = true end
            if turned == nil then unknown = true end
        end
        if not found then
            return false, unknown and "Prerequisite history is unavailable. Check the quest giver before using Done."
                or "A prerequisite quest must be turned in first. Check earlier steps or another chapter."
        end
    end
    for _, id in ipairs(step.requiresAll or {}) do
        if not self:Quest(id).turned then
            return false, "Prerequisite quest #" .. id .. " must be turned in first."
        end
    end
    return true
end

function Engine:QuestWasSkipped(id, visiting)
    local decision = self.state.skippedQuests[id]
    if not decision then return false end
    local quest = self:Quest(id)
    if quest.on or quest.turned then return false end
    if decision == true then return true end
    if type(decision) ~= "table" then return false end
    visiting = visiting or {}
    if visiting[id] then return false end
    visiting[id] = true
    local skipped = false
    for _, prerequisite in ipairs(decision.requiresAll or {}) do
        if self:QuestWasSkipped(prerequisite, visiting) then skipped = true; break end
    end
    if type(decision.requiresAny) == "table" and #decision.requiresAny > 0 then
        local allSkipped = true
        for _, prerequisite in ipairs(decision.requiresAny) do
            if not self:QuestWasSkipped(prerequisite, visiting) then allSkipped = false; break end
        end
        skipped = skipped or allSkipped
    end
    visiting[id] = nil
    return skipped
end

function Engine:QuestWasClosed(id)
    local alternatives = self.state.closedQuests[id]
    if type(alternatives) ~= "table" then return false end
    local quest = self:Quest(id)
    if quest.on or quest.turned then return false end
    for _, alternative in ipairs(alternatives) do
        local other = self:Quest(alternative)
        if other.on or other.turned then return true end
    end
    return false
end

function Engine:SkippedQuestStep(step, readOnly)
    if not step.questID then return false end
    local quest = self:Quest(step.questID)
    if quest.on or quest.turned then return false end
    if self:QuestWasSkipped(step.questID) then return true end
    if step.kind ~= "accept" then return false end
    local skip = false
    for _, id in ipairs(step.requiresAll or {}) do
        if self:QuestWasSkipped(id) then skip = true; break end
    end
    if type(step.requiresAny) == "table" and #step.requiresAny > 0 then
        local allSkipped = true
        for _, id in ipairs(step.requiresAny) do
            if not self:QuestWasSkipped(id) then allSkipped = false; break end
        end
        skip = skip or allSkipped
    end
    if skip and not readOnly then
        -- Remember why this quest was skipped. If the player later does its
        -- prerequisite, an inherited skip must no longer exclude the follow-up.
        self.state.skippedQuests[step.questID] = { requiresAny = step.requiresAny, requiresAll = step.requiresAll }
    end
    return skip
end

function Engine:StepState(step, readOnly)
    if self:IsFiltered(step) then return true, "filter" end
    if step.kind=="train" and step.text=="Train your class abilities" and Call(self,"AlreadyTrained",self.character)==true then
        return true,"trained","Current training already confirmed."
    end
    if step.kind == "train" and step.text == "Train your class abilities" and self.state.options.training ~= true then
        return true, "trainingOptional", "Class-training reminders are off. Enable with /lg training on."
    end
    local allowed = self:BlockAllowed(step, readOnly)
    if allowed == false then return true, "condition" end
    if allowed == nil then
        return false, "review", "This route condition cannot be checked. Review the step, then use Done or Skip."
    end
    if self:SkippedQuestStep(step, readOnly) then
        return true, "skippedQuest", "You skipped this optional quest or its prerequisite. Accepting it later lets Sync restore its active steps."
    end
    if step.questID and self:QuestWasClosed(step.questID) then
        return true, "closed", "An active or rewarded alternative quest replaces this step."
    end
    local quest = step.questID and self:Quest(step.questID) or nil
    if step.kind == "accept" then
        if quest and (quest.on or quest.turned) then return true, "auto" end
        local available, reason = self:AcceptAvailability(step)
        if available == "closed" then
            if not readOnly then self.state.closedQuests[step.questID] = step.closedBy end
            return true, "closed"
        end
        if not available then return false, "blocked", reason end
        return false, "quest", step.optional and "Optional quest: accept it, or Skip if you do not want to do it."
            or "Accept this quest from the quest giver. The guide advances when it appears in your quest log."
    elseif step.kind == "turnin" then
        if quest and quest.turned then return true, "auto" end
        if not quest or quest.known == false then return false, "review", "Quest history is unavailable. Verify the turn-in, then use Done." end
        if not quest.on then return false, "blocked", "This quest is not in your log. Check the earlier accept step, or Skip if it is unavailable." end
        if not quest.complete then return false, "quest", "Finish the quest objectives, then return to the quest giver." end
        return false, "quest", "Turn in the quest and choose your reward. Opening the reward dialog does not finish this step."
    elseif step.kind == "complete" then
        if quest and (quest.turned or quest.complete) then return true, "auto" end
        if not quest or quest.known == false then return false, "review", "Quest data is unavailable. Check the objective in your quest log." end
        if not quest.on then return false, "blocked", "Accept the quest before doing this objective. Use Prev or Routes to review earlier steps." end
        if step.objectiveIndex then
            local objective = quest.objectives and quest.objectives[step.objectiveIndex]
            if objective and objective.finished == true then return true, "auto" end
            if objective then
                local fulfilled, required = Number(objective.numFulfilled, 0), Number(objective.numRequired, 0)
                if required > 0 and fulfilled >= required then return true, "auto" end
                local progress = required > 0 and (" (" .. fulfilled .. "/" .. required .. ")") or ""
                return false, "quest", (objective.text or "Complete this quest objective.") .. progress
            end
            return false, "quest", "Objective details are loading or differ in this build. Check the quest log; Done is available if needed."
        end
        return false, "quest", "Complete the quest objectives. Progress is read from your quest log."
    elseif step.kind == "level" then
        local required = Number(step.level, step.minLevel or 1) + Number(step.levelFraction, 0)
        if self.levelValue >= required then return true, "auto" end
        return false, "level", "Continue questing or defeat suitable enemies until this XP checkpoint is reached."
    elseif step.kind == "goto" then
        if self:TravelAlreadySatisfied(step) then return true, "obsoleteTravel" end
        local arrived = Call(self, "AtLocation", step)
        if arrived == true then return true, "auto" end
        if arrived == nil then return false, "manual", "Use the map and the travel instructions. Press Done when you arrive." end
        return false, "travel", "Follow the waypoint using roads and safe terrain. This is straight-line guidance."
    elseif step.kind == "collect" and step.itemID then
        local count = Call(self, "ItemCount", step.itemID)
        if count and count >= (step.count or 1) then return true, "auto" end
        return false, "manual", "Collect the listed items, then use Done if the inventory count is unavailable."
    end
    return false, "manual", "Carry out this step yourself, then press Done."
end

function Engine:Advance()
    if self.state.paused or self.state.review then return end
    local visited = {}
    for _ = 1, 500 do
        local route, chapter = self:GetRoute(), self:Chapter()
        if not route or not chapter then return end
        local step = route.steps[chapter.index]
        if not step then
            if not route.next then return end
            if visited[route.next] or not self:IsRouteEligible(self.data.routes[route.next]) then
                self.state.notice = "The next chapter could not be opened. Use Routes to select a chapter."
                return
            end
            visited[self.state.routeID] = true
            self.state.routeID = route.next
        else
            local done, reason = self:StepState(step)
            if chapter.marks[chapter.index] then done = true end
            if not done then return end
            chapter.marks[chapter.index] = chapter.marks[chapter.index] or reason or "auto"
            chapter.index = chapter.index + 1
        end
    end
    -- Continue on the next refresh; never lock the client in a long transition loop.
end

function Engine:Refresh()
    self:ReadCharacter()
    self.questCache = {}
    self:Advance()
    self.areaPlan = nil
    if ns.AreaPlanner and self.state.options.smartRoute ~= false and not self.state.paused and not self.state.review then
        self.areaPlan = ns.AreaPlanner.Build(self)
    end
    return self:View()
end

function Engine:View()
    local route, chapter = self:GetRoute(), self:Chapter()
    local step, recovering = self:GetActionStep()
    if not route then
        return { routeTitle = "No matching route", stepIndex = 0, totalSteps = 0, stepText = "Choose a route from Routes.",
            stepHint = "Routes are available for supported Alliance and Horde characters.", progress = 0,
            playerLevel = self.character.level, status = "ROUTE NEEDED", paused = self.state.paused, complete = true }
    end
    local count = #route.steps
    if not step then
        local atCap = self.character.level >= 60
        return { routeID = route.id, routeTitle = route.title, stepIndex = count, totalSteps = count, progress = 1,
            playerLevel = self.character.level, stepKind = "note", complete = true, paused = self.state.paused,
            stepText = atCap and "Level 60 reached. Your leveling guide is complete!" or "You reached the end of this route.",
            stepHint = atCap and "You can review any chapter from Routes."
                or (self.state.notice or "If you are below level 60, finish available quests or gain the remaining XP. Routes can reopen earlier chapters."),
            status = atCap and "LEVEL 60" or "ROUTE COMPLETE", statusColor = { .42, .83, .62 } }
    end
    local _, kind, hint = self:StepState(step, self.areaPlan and self.areaPlan.selected.index ~= chapter.index)
    local status = { quest = "TRACKING QUEST", blocked = "CHECK PREREQUISITES", level = "GAIN EXPERIENCE",
        travel = "TRAVEL", manual = "MANUAL STEP", review = "CHECK THIS STEP" }
    local paused, review = self.state.paused, self.state.review
    local detail = step.detail or ""
    if step.optional then detail = "Optional. " .. detail end
    if self.state.notice then detail = detail .. "\n" .. self.state.notice end
    if detail ~= "" then hint = detail .. "\n" .. (hint or "") end
    if paused then hint = "Guide paused. Resume when you are ready.\n" .. (hint or "") end
    if review then hint = "Reviewing an earlier step. Next returns to guide progression.\n" .. (hint or "") end
    if recovering then hint = "Finish this quest first. The guide will send you to hand it in when it is ready.\n" .. (hint or "") end
    return { routeID = route.id, routeTitle = route.title, stepIndex = chapter.index, totalSteps = count,
        stepText = step.text or step.questTitle or "Follow this guide step.", stepKind = step.kind, stepHint = hint or "",
        progress = count > 0 and math.min(1, (chapter.index - 1) / count) or 0, playerLevel = self.character.level,
        status = paused and "PAUSED" or review and "REVIEWING" or status[kind] or "GUIDE STEP",
        statusColor = (kind == "blocked" or kind == "review") and { 1, .71, .35 } or { .57, .64, .73 },
        paused = paused, manual = kind == "manual" or kind == "review", manualReview = review or kind == "review",
        autoActive = not paused and not review and (kind == "quest" or kind == "travel" or kind == "level"),
        areaTasks = self.areaPlan and self.areaPlan.tasks,
        canPrev = self:PreviousReviewIndex() ~= nil,
        efficiency = self.areaPlan and self.areaPlan.selected.efficiency,
        speedMode = ns.SpeedPolicy ~= nil and self.state.options.speedLeveling ~= false,
        canNext = not self.areaPlan or self.areaPlan.selected.index == chapter.index,
        recovering = recovering, complete = false }
end

function Engine:Next(skip)
    local chapter, step = self:Chapter(), self:GetStep()
    if not chapter or not step then return end
    if self.areaPlan and self.areaPlan.selected.index ~= chapter.index then
        if skip then chapter.marks[self.areaPlan.selected.index] = "skip"
        else self.state.notice = "This nearby task updates automatically from quest progress." end
        return self:Refresh()
    end
    local _, recovering = self:GetActionStep()
    if recovering and not skip then
        self.state.notice = "This quest is not ready to turn in. Complete its objectives; the guide will continue automatically."
        return self:Refresh()
    end
    if not skip and self:BlockAllowed(step) == nil then
        chapter.blocks[tostring(step.blockID or chapter.index)] = true
    end
    if skip and step.kind == "accept" and step.optional and step.questID then
        self.state.skippedQuests[step.questID] = true
    end
    chapter.marks[chapter.index] = skip and "skip" or "manual"
    chapter.index, self.state.review, self.state.notice = chapter.index + 1, false, nil
    return self:Refresh()
end

function Engine:PreviousReviewIndex()
    local chapter,route=self:Chapter(),self:GetRoute()
    if not chapter or not route then return nil end
    for index=chapter.index-1,1,-1 do
        local step=route.steps[index]
        local mark=chapter.marks[index]
        if step and mark~="filter" and mark~="condition" and mark~="closed" and mark~="trainingOptional"
            and not self:IsFiltered(step) and self:BlockAllowed(step,true)~=false then
            local quest=step.questID and self:Quest(step.questID)
            local finished=quest and quest.turned==true
            if not finished and step.kind=="complete" then finished=self:StepState(step,true)==true end
            if not finished then return index end
        end
    end
end

function Engine:Prev()
    self.areaPlan=nil
    local chapter=self:Chapter()
    if not chapter then return end
    self:ReadCharacter();self.questCache={}
    local index=self:PreviousReviewIndex()
    if not index then self.state.notice="No earlier unfinished quest steps.";return self:View() end
    chapter.index,self.state.review,self.state.notice=index,true,nil
    return self:View()
end

function Engine:SetPaused(paused)
    self.state.paused = paused == true
    return self:Refresh()
end

function Engine:Sync()
    self:ReadCharacter()
    self.questCache = {}
    local chapter, route = self:Chapter(), self:GetRoute()
    if not chapter or not route then return false end
    chapter.blocks = {}
    local first
    for i, step in ipairs(route.steps) do
        if not self:IsFiltered(step) and step.questID and (step.kind == "complete" or step.kind == "turnin") then
            local quest = self:Quest(step.questID)
            if quest.on then
                local done = self:StepState(step, true)
                if not done then first = i; break end
            end
        end
    end
    if first then
        chapter.index = first
        -- A manual completion never changes game quest state. Sync may revisit it.
        for i = first, #route.steps do
            if route.steps[i].questID then chapter.marks[i] = nil end
        end
        self.state.notice = "Matched an active quest in this chapter. Prev lets you review earlier steps."
    else
        self.state.notice = "No unfinished active quest matched this chapter. Choose another chapter from Routes if needed."
    end
    self.state.review = false
    self:Refresh()
    return first ~= nil
end

function Engine:Reset()
    self.state.chapters, self.state.routeID, self.state.review, self.state.notice = {}, nil, false, nil
    self.state.skippedQuests = {}
    self.state.closedQuests = {}
    self.state.paused = false
    return self:Start()
end

function Engine:SetOption(key, value)
    if key ~= "group" and key ~= "dungeons" and key ~= "training" and key ~= "smartRoute" and key ~= "speedLeveling" then return false end
    self.speedPolicy=nil
    self.state.options[key] = value == true
    local chapter = self:Chapter()
    if chapter then chapter.blocks = {} end
    self.state.notice = "Route preference changed for upcoming steps. Use Prev or Routes to revisit skipped sections."
    self:Refresh()
    return true
end

function Engine:IsRouteFinished(route,chapter)
    if chapter and Number(chapter.index,1)>#route.steps then return true end
    local seen,any={},false
    for _,step in ipairs(route.steps) do
        if not self:IsFiltered(step) then
            if step.kind=="level" and self.levelValue<Number(step.level,1)+Number(step.levelFraction,0) then return false end
            if step.questID and not seen[step.questID] then
                seen[step.questID],any=true,true
                if self:Quest(step.questID).turned~=true then return false end
            end
        end
    end
    return any
end

function Engine:GetRouteChoices()
    self:ReadCharacter()
    self.questCache={}
    local result={}
    for _,id in ipairs(self.data.routeOrder or {}) do
        local route=self.data.routes[id]
        if self:IsRouteEligible(route) then
            local low,high=Number(route.startLevel,1),Number(route.endLevel,60)
            local level=self.character.level
            local chapter=self.state.chapters[id]
            local inRange=level>=low and level<=high
            local activeCurrent=false
            if not inRange and level>=low and id==self.state.routeID and chapter and Number(chapter.index,1)<=#route.steps then
                for _,step in ipairs(route.steps) do
                    if step.questID and not self:IsFiltered(step) then
                        local quest=self:Quest(step.questID)
                        if quest.on==true and quest.turned~=true then activeCurrent=true;break end
                    end
                end
            end
            if (inRange or activeCurrent) and not self:IsRouteFinished(route,chapter) then
                local summary=route.faction.." | Levels "..low.."-"..high
                if activeCurrent then summary=summary.." | Active quests" end
                if chapter then summary=summary.." | Step "..math.min(Number(chapter.index,1),#route.steps).."/"..#route.steps end
                result[#result+1]={id=id,title=route.title,summary=summary}
            end
        end
    end
    return result
end

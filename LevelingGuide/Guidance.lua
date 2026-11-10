-- Presentation and navigation targets; never changes route completion conditions.
local _, ns = ...
local Guidance = {}
ns.Guidance = Guidance

-- Trainers identified by the bundled Zephras Isle class introductions.
local trainers = {
    HUNTER = {251376, "Tai'ree Farsight", "Beside Rorian in Thendal Village."},
    WARRIOR = {251964, "Blademaster Ren", "Inside the watchtower in Thendal Village."},
    ROGUE = {251389, "Akeri Duskblade", "Inside the watchtower in Thendal Village."},
    SHAMAN = {251374, "Windshaper Boro", "Beside Rorian in Thendal Village."},
    DRUID = {251373, "Xyton Silverwind", "Ground floor of the tree behind Rorian in Thendal Village."},
}

function Guidance.Resolve(route, step, character)
    if not step then return nil end
    if step.kind ~= "train" or step.x or not route or not route.id:find("skyborne/01-zephras-isle", 1, true) then return step end
    -- These are the starting-village trainers, not destinations for later towns.
    if not step.blockTitle or not step.blockTitle:find("Thendal", 1, true) then return step end
    local trainer = trainers[character and character.class]
    if not trainer then return step end
    for _, candidate in ipairs(route.steps) do
        if candidate.npcID == trainer[1] and candidate.x and candidate.y and candidate.uiMapID then
            local target = {}
            for key, value in pairs(step) do target[key] = value end
            for _, key in ipairs({"uiMapID", "x", "y", "coordFrame", "continentID", "worldX", "worldY"}) do target[key] = candidate[key] end
            target.npcName, target.locationHint = trainer[2], trainer[3]
            target.text = "Visit " .. trainer[2] .. " and learn your available class abilities."
            target.radius = 8
            return target
        end
    end
    return step
end

function Guidance.Describe(step, view, quest)
    if not step or not view then return end
    local lines = {view.stepText or step.text or ""}
    local questTitle = quest and quest.title
    if type(questTitle) ~= "string" or questTitle == "" then questTitle = step.questTitle end
    if step.questID then
        questTitle = questTitle or ("Quest #" .. step.questID)
        view.questTitle, view.questID = questTitle, step.questID
        local actions = {accept = "ACCEPT QUEST", complete = "DO QUEST", turnin = "TURN IN QUEST"}
        local action = actions[step.kind] or "QUEST TASK"
        local color = step.kind == "turnin" and "|cff70ef90" or "|cffffd36a"
        lines = {color .. action .. ":\n" .. questTitle .. "|r"}
        if step.kind == "complete" then
            local objective = quest and quest.objectives and step.objectiveIndex and quest.objectives[step.objectiveIndex]
            lines[#lines + 1] = "OBJECTIVE: " .. (objective and objective.text or step.text or "Complete the objectives in your quest log.")
            if step.inventoryOnly and step.text then lines[#lines + 1] = "HOW: " .. step.text end
        elseif step.kind ~= "accept" and step.kind ~= "turnin" then
            lines[#lines + 1] = step.text or "Follow this quest task."
        end
    end
    if step.kind == "train" then
        lines[1] = step.npcName and ("TRAIN: Talk to " .. step.npcName) or "TRAIN: Visit your class trainer"
        lines[#lines + 1] = "Open the trainer's window and learn the available abilities. Then press Done."
    elseif step.kind == "accept" then
        if step.itemID or step.startItemID then
            lines[#lines + 1] = "OPEN YOUR BAGS: Right-click " .. (step.itemName or step.startItemName or ("item #" .. (step.itemID or step.startItemID))) .. " to start this quest."
        elseif step.objectID then
            lines[#lines + 1] = "Interact with " .. (step.objectName or "the marked quest object") .. " and accept this quest."
        else
            lines[#lines + 1] = "Talk to " .. (step.npcName or "the quest giver") .. " and accept this quest."
        end
    elseif step.kind == "turnin" then
        lines[#lines + 1] = "Talk to " .. (step.npcName or "the quest giver") .. " and turn in this quest."
        if quest and quest.on and not quest.complete then
            lines[#lines + 1] = "NOT READY: Finish this quest's objectives before returning to the NPC."
        end
    end
    if step.actionHint then lines[#lines + 1] = "HOW: " .. step.actionHint end
    if step.blockTitle then lines[#lines + 1] = "WHERE: " .. step.blockTitle end
    if step.locationHint then lines[#lines + 1] = step.locationHint end
    if step.navigationHint then lines[#lines + 1] = step.navigationHint end
    if step.x and step.y and step.coordFrame == "live" then
        lines[#lines + 1] = string.format("DESTINATION: %.1f, %.1f — follow the arrow.", step.x * 100, step.y * 100)
    elseif step.inventoryOnly then
        lines[#lines + 1] = "BAGS: Carry out the item action above. No travel is needed for this action."
    elseif not step.x then
        lines[#lines + 1] = "No exact destination recorded. Use the location instructions above; no direction can be calculated."
    end
    if view.stepHint and view.stepHint ~= "" then lines[#lines + 1] = view.stepHint end
    view.stepText = table.concat(lines, "\n\n")
    -- Keep full context in the existing Step details tooltip.
    view.stepHint = view.stepText
    local compact = {lines[1]}
    if step.kind == "train" then
        compact[#compact + 1] = "Train, then Done."
    elseif step.kind == "accept" then
        if step.itemID or step.startItemID then
            compact[#compact + 1] = "Use " .. (step.itemName or step.startItemName or "quest item") .. "."
        else
            compact[#compact + 1] = "Talk to " .. (step.npcName or step.objectName or "the quest giver") .. "."
        end
    elseif step.kind == "turnin" then
        compact[#compact + 1] = "Return to " .. (step.npcName or "the quest giver") .. "."
        if quest and quest.on and not quest.complete then compact[#compact + 1] = "NOT READY" end
    elseif step.kind == "complete" then
        local objective = quest and quest.objectives and step.objectiveIndex and quest.objectives[step.objectiveIndex]
        local task = objective and objective.text or step.text or "Finish the quest objectives."
        local itemActions = {
            [1046] = "Check your bags for Dartol's Rod.",
            [5149] = "Combine doll pieces.", [5051] = "Combine charm halves.",
            [3786] = "Grow 10 Morrowgrain.", [3804] = "Grow 10 Morrowgrain.",
            [91899] = "Open the crate.", [91904] = "Open the crate.",
            [6022] = "Collect 7 Living Rot, then use Mortar and Pestle.",
            [96873] = "Disenchant Hexed Pendants.",
        }
        if step.questTitle == "The Great Outdoors" then task = "/sit; wait for Boosted Rest."
        elseif step.inventoryOnly then task = itemActions[step.questID] or step.text or task
        elseif step.sourceKind == "use" and step.itemName then task = "Use " .. step.itemName .. "."
        elseif step.sourceKind == "talk" and step.npcName then task = "Talk to " .. step.npcName .. "."
        end
        -- The quest title is already above; keep only the action below it.
        local suffix = task:find(" — ", 1, true)
        if suffix then task = task:sub(1, suffix - 1) end
        local sentence = task:match("^(.-[.!?])%s")
        if sentence then task = sentence end
        local objectives = quest and quest.objectives
        local multiple = type(objectives) == "table" and #objectives > 1
        local specialAction = step.inventoryOnly or step.actionHint or step.sourceKind == "use" or step.sourceKind == "talk"
        if not multiple or specialAction then compact[#compact + 1] = task end
        local progress = view.stepHint:match("%d+/%d+")
        if objective and type(objective.numRequired) == "number" and objective.numRequired > 0
            and type(objective.numFulfilled) == "number" then
            progress = objective.numFulfilled .. "/" .. objective.numRequired
        end
        if multiple then
            local rows = {}
            for index, entry in ipairs(objectives) do
                local label = entry.text or ("Objective " .. index)
                -- Native objective text can already contain its counter.
                if not label:match("%d+%s*/%s*%d+") and type(entry.numRequired) == "number"
                    and entry.numRequired > 0 and type(entry.numFulfilled) == "number" then
                    label = entry.numFulfilled .. "/" .. entry.numRequired .. " " .. label
                end
                local marker = entry.finished and "[Done] " or (index == step.objectiveIndex and "> " or "")
                rows[#rows + 1] = marker .. label
            end
            compact[#compact + 1] = table.concat(rows, "\n")
        elseif progress and not task:match("%d+%s*/%s*%d+") then
            compact[#compact + 1] = progress
        end
    end
    local location = step.blockTitle
    if step.x and step.y and step.coordFrame == "live" then
        location = (location and (location .. " — ") or "") .. string.format("%.1f, %.1f", step.x * 100, step.y * 100)
    end
    if location then compact[#compact + 1] = location end
    if view.areaTasks and #view.areaTasks > 1 then
        local nearby, seen = {}, {[step.questID or 0]=true}
        for _, entry in ipairs(view.areaTasks) do
            local other=entry.step
            if other.questID and not seen[other.questID] then
                seen[other.questID]=true
                local action=other.kind=="accept" and "Accept: " or other.kind=="turnin" and "Turn in: " or "Do: "
                nearby[#nearby+1]=action .. (other.questTitle or ("Quest #" .. other.questID))
                if #nearby>=4 then break end
            end
        end
        if #nearby>0 then compact[#compact+1]="NEARBY QUESTS\n"..table.concat(nearby,"\n") end
    end
    view.stepText = table.concat(compact, "\n\n")
end

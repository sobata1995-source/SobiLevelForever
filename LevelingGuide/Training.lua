-- Evidence from the real class trainer's complete visible service catalogue.
local _,ns=...
local Training={};ns.Training=Training
local Instance={};Instance.__index=Instance
local function safe(fn,...)
    if type(fn)~="function" then return end
    local ok,a,b,c,d=pcall(fn,...)
    if not ok then return end
    for _,v in pairs({a,b,c,d}) do if issecretvalue and issecretvalue(v) then return end end
    return a,b,c,d
end
function Training.New(progress)
    return setmetatable({progress=progress,active=false},Instance)
end
function Instance:Snapshot()
    if not self.active then return end
    local guid=safe(UnitGUID,"npc")
    local id=type(guid)=="string" and tonumber(guid:match("%-(%d+)%-%x+$"))
    local _,class=safe(UnitClass,"player")
    local allowed=id and ns.ClassTrainerClasses and ns.ClassTrainerClasses[id]
    if not allowed or not allowed[class] then return end
    -- A hidden available/unavailable filter makes a zero count ambiguous.
    if safe(GetTrainerServiceTypeFilter,"available")~=true or safe(GetTrainerServiceTypeFilter,"unavailable")~=true then return end
    local level=safe(UnitLevel,"player")
    local count=safe(GetNumTrainerServices)
    if type(level)~="number" or type(count)~="number" or count<1 or count>1000 then return end
    local pending,used,future,maxUsed=0,0,nil,0
    for index=1,count do
        -- Forever trainer UI: name, serviceType, texture, requiredLevel.
        local name,status,_,required=safe(GetTrainerServiceInfo,index)
        if type(name)~="string" or name=="" then return end
        if status=="available" then pending=pending+1
        elseif status=="unavailable" then
            if type(required)~="number" then return end
            if required<=level then pending=pending+1 else future=math.min(future or required,required) end
        elseif status=="used" then
            used=used+1
            if type(required)=="number" then maxUsed=math.max(maxUsed,required) end
        else return end -- incomplete/collapsed/unknown catalogue: no proof
    end
    if pending>0 then
        self.progress.trainingEvidence={class=class,atLevel=level,complete=false,trainer=id}
    elseif future or (used>0 and maxUsed>=level and safe(GetTrainerServiceTypeFilter,"used")==true) then
        self.progress.trainingEvidence={class=class,atLevel=level,validThrough=future and future-1 or level,complete=true,trainer=id}
    end
end
function Instance:OnEvent(event)
    if event=="TRAINER_SHOW" then self.active=true;self:Snapshot()
    elseif event=="TRAINER_CLOSED" then self:Snapshot();self.active=false
    elseif self.active and (event=="TRAINER_UPDATE" or event=="TRAINER_SERVICE_INFO_NAME_UPDATE" or event=="SPELLS_CHANGED") then self:Snapshot() end
end
function Instance:AlreadyTrained(character)
    local proof=self.progress.trainingEvidence
    return type(proof)=="table" and proof.complete==true and proof.class==character.class
        and type(proof.atLevel)=="number" and type(proof.validThrough)=="number"
        and character.level>=proof.atLevel and character.level<=proof.validThrough
end
function Instance:Invalidate()
    self.progress.trainingEvidence=nil
end

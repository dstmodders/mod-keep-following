local _IS_KEY_LSHIFT_DOWN = false

local KeepFollowing = Class(function(self, inst)
    self.inst = inst

    self.debug = false
    self.isclient = false
    self.isdst = false
    self.isfollowing = false
    self.ismastersim = false
    self.isnear = false
    self.leader = nil
    self.tasktime = 0.3

    --replaced by GetModConfigData
    self.targetdistance = 2.5

    self:AddInputHandlers()

    inst:StartUpdatingComponent(self)
end)

local function IsMoveButtonDown()
    return TheInput:IsControlPressed(CONTROL_MOVE_UP)
        or TheInput:IsControlPressed(CONTROL_MOVE_DOWN)
        or TheInput:IsControlPressed(CONTROL_MOVE_LEFT)
        or TheInput:IsControlPressed(CONTROL_MOVE_RIGHT)
end

function KeepFollowing:InGame()
    return self.inst and self.inst.HUD and not self.inst.HUD:HasInputFocus()
end

function KeepFollowing:CanBeLeader(entity)
    if entity == self.inst then
        return false
    end

    return entity:HasTag("player")
        or entity:HasTag("chester")
        or entity:HasTag("critter")
        or entity:HasTag("glommer")
        or entity:HasTag("hutch")
        or entity:HasTag("pig")
end

function KeepFollowing:SetLeader(entity)
    if self:CanBeLeader(entity) then
        self.leader = entity
        self:DebugString(string.format("new leader %s", self.leader:GetDisplayName()))
    end
end

function KeepFollowing:GetLeader()
    return self.leader
end

function KeepFollowing:GetLeaderUnderMouse()
    local entity = TheInput:GetWorldEntityUnderMouse()

    if entity and self:CanBeLeader(entity) then
        return entity
    end

    return nil
end

function KeepFollowing:IsFollowing()
    return self.leader and self.isfollowing
end

function KeepFollowing:StartFollowing(entity)
    local distance
    local head

    if not self:IsFollowing() then
        self:SetLeader(entity)
    end

    if self.leader and self.inst.components.locomotor ~= nil then
        distance = math.sqrt(self.inst:GetDistanceSqToPoint(self.leader:GetPosition()))

        if not self:IsFollowing() then
            self.isfollowing = true

            self:DebugString(string.format(
                "started following leader. Distance: %0.2f. Target: %0.2f",
                distance,
                self.targetdistance
            ))
        end

        self.inst:DoTaskInTime(self.tasktime, function()
            if self:IsFollowing() then
                if distance >= self.targetdistance then
                    self.isnear = false
                    self.inst.components.locomotor:GoToPoint(self.inst:GetPositionAdjacentTo(entity, self.targetdistance - 0.25))
                elseif not self.isnear and distance < self.targetdistance then
                    self.isnear = true
                    self.inst.components.locomotor:GoToPoint(self.inst:GetPositionAdjacentTo(entity, self.targetdistance - 0.25))
                    self:DebugString(string.format("near leader. Distance: %0.2f", distance))
                end

                self:StartFollowing(entity)
            end
        end)
    end
end

function KeepFollowing:StopFollowing()
    if self.leader then
        self:DebugString(string.format("stopped following %s", self.leader:GetDisplayName()))
        self.inst:CancelAllPendingTasks()
        self.isfollowing = false
        self.leader = nil
    end
end

function KeepFollowing:AddInputHandlers()
    TheInput:AddKeyDownHandler(KEY_LSHIFT, function()
        if self:InGame() then
            _IS_KEY_LSHIFT_DOWN = true
        end
    end)

    TheInput:AddKeyUpHandler(KEY_LSHIFT, function()
        if self:InGame() then
            _IS_KEY_LSHIFT_DOWN = false
        end
    end)

    TheInput:AddKeyHandler(function()
        if self:InGame() and IsMoveButtonDown() then
            if self:IsFollowing() then
                self:StopFollowing()
            end
        end
    end)

    TheInput:AddMouseButtonHandler(function(button, down, x, y)
        if self:InGame() and _IS_KEY_LSHIFT_DOWN and button == 1000 and down then
            local leader = KeepFollowing:GetLeaderUnderMouse()
            if leader then
                self:StopFollowing()
                self:StartFollowing(leader)
            end
        end
    end)
end

function KeepFollowing:EnableDebug()
    self.debug = true
end

function KeepFollowing:DisableDebug()
    self.debug = false
end

function KeepFollowing:DebugString(string)
    if self.debug then
        print(string.format("Mod (%s): %s", self.modname, tostring(string)))
    end
end

return KeepFollowing

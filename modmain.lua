--Globals
local ACTIONS = GLOBAL.ACTIONS
local CONTROL_MOVE_DOWN = GLOBAL.CONTROL_MOVE_DOWN
local CONTROL_MOVE_LEFT = GLOBAL.CONTROL_MOVE_LEFT
local CONTROL_MOVE_RIGHT = GLOBAL.CONTROL_MOVE_RIGHT
local CONTROL_MOVE_UP = GLOBAL.CONTROL_MOVE_UP
local KEY_LCTRL = GLOBAL.KEY_LCTRL
local KEY_LSHIFT = GLOBAL.KEY_LSHIFT
local TheInput = GLOBAL.TheInput

--Other
local _DEBUG = GetModConfigData("debug")

local function DebugString(string)
    if _DEBUG then
        print(string.format("Mod (%s): %s", modname, tostring(string)))
    end
end

local function IsDST()
    return GLOBAL.TheSim:GetGameID() == "DST"
end

local function IsClient()
    return IsDST() and GLOBAL.TheNet:GetIsClient()
end

local function IsMoveButtonDown()
    return TheInput:IsControlPressed(CONTROL_MOVE_UP)
        or TheInput:IsControlPressed(CONTROL_MOVE_DOWN)
        or TheInput:IsControlPressed(CONTROL_MOVE_LEFT)
        or TheInput:IsControlPressed(CONTROL_MOVE_RIGHT)
end

local function IsOurAction(action)
    return action == ACTIONS.FOLLOW
        or action == ACTIONS.PUSH
        or action == ACTIONS.TENTFOLLOW
        or action == ACTIONS.TENTPUSH
end

local function OnPlayerActivated(player)
    player:AddComponent("keepfollowing")

    player.components.keepfollowing.isclient = IsClient()
    player.components.keepfollowing.isdst = IsDST()
    player.components.keepfollowing.modname = modname

    --GetModConfigData
    player.components.keepfollowing.targetdistance = GetModConfigData("target_distance")

    if _DEBUG then
        player.components.keepfollowing:EnableDebug()
    end

    DebugString(string.format("player %s activated", player:GetDisplayName()))

    TheInput:AddKeyHandler(function()
        if player.components.keepfollowing:InGame() and IsMoveButtonDown() then
            if player.components.keepfollowing:IsFollowing() then
                player.components.keepfollowing:StopFollowing()
            end

            if player.components.keepfollowing:IsPushing() then
                player.components.keepfollowing:StopPushing()
            end
        end
    end)

    DebugString("added movement keys handler")
end

local function OnPlayerDeactivated(player)
    player:RemoveComponent("keepfollowing")

    DebugString(string.format("player %s deactivated", player:GetDisplayName()))
end

local function AddPlayerPostInit(onActivatedFn, onDeactivatedFn)
    DebugString(string.format("game ID - %s", GLOBAL.TheSim:GetGameID()))

    if IsDST() then
        env.AddPrefabPostInit("world", function(world)
            world:ListenForEvent("playeractivated", function(world, player)
                if player == GLOBAL.ThePlayer then
                    onActivatedFn(player)
                end
            end)

            world:ListenForEvent("playerdeactivated", function(world, player)
                if player == GLOBAL.ThePlayer then
                    onDeactivatedFn(player)
                end
            end)
        end)
    else
        env.AddPlayerPostInit(function(player)
            onActivatedFn(player)
        end)
    end

    DebugString("AddPrefabPostInit fired")
end

local function ActionFollow(act)
    if not act.doer or not act.target or not act.doer.components.keepfollowing then
        return false
    end

    local keepfollowing = act.doer.components.keepfollowing
    keepfollowing:StopFollowing()
    keepfollowing:StartFollowing(act.target)

    return true
end

local function ActionPush(act)
    if not act.doer or not act.target or not act.doer.components.keepfollowing then
        return false
    end

    local keepfollowing = act.doer.components.keepfollowing
    keepfollowing:StopPushing()
    keepfollowing:StartPushing(act.target)

    return true
end

local function ActionTentFollow(act)
    if not act.doer or not act.target or not act.doer.components.keepfollowing then
        return false
    end

    local keepfollowing = act.doer.components.keepfollowing
    local leader = keepfollowing:GetTentSleeper(act.target)

    if leader then
        keepfollowing:StopFollowing()
        keepfollowing:StartFollowing(leader)
    end

    return true
end

local function ActionTentPush(act)
    if not act.doer or not act.target or not act.doer.components.keepfollowing then
        return false
    end

    local keepfollowing = act.doer.components.keepfollowing
    local leader = keepfollowing:GetTentSleeper(act.target)

    if leader then
        keepfollowing:StopPushing()
        keepfollowing:StartPushing(leader)
    end

    return true
end

local function PlayerControllerPostInit(self, player)
    local ThePlayer = GLOBAL.ThePlayer

    if player ~= ThePlayer then
        return
    end

    local OldGetLeftMouseAction = self.GetLeftMouseAction
    local OldOnLeftClick = self.OnLeftClick

    local function NewGetLeftMouseAction(self)
        local act = OldGetLeftMouseAction(self)

        if act and act.target then
            local keepfollowing = act.doer.components.keepfollowing

            if act.target:HasTag("tent") and act.target:HasTag("hassleeper") then
                if TheInput:IsKeyDown(KEY_LSHIFT) and not TheInput:IsKeyDown(KEY_LCTRL) then
                    act.action = ACTIONS.TENTFOLLOW
                elseif TheInput:IsKeyDown(KEY_LSHIFT) and TheInput:IsKeyDown(KEY_LCTRL) then
                    act.action = ACTIONS.TENTPUSH
                end
            end

            if keepfollowing:CanBeLeader(act.target) then
                if TheInput:IsKeyDown(KEY_LSHIFT) and not TheInput:IsKeyDown(KEY_LCTRL) then
                    act.action = ACTIONS.FOLLOW
                elseif TheInput:IsKeyDown(KEY_LSHIFT) and TheInput:IsKeyDown(KEY_LCTRL) then
                    act.action = ACTIONS.PUSH
                end
            end
        end

        self.LMBaction = act

        return self.LMBaction
    end

    local function NewOnLeftClick(self, down)
        if not down or TheInput:GetHUDEntityUnderMouse() or self:IsAOETargeting() then
            return OldOnLeftClick(self, down)
        end

        local act = self:GetLeftMouseAction()
        if act then
            if IsOurAction(act.action) then
                return act.action.fn(act)
            end
        end

        OldOnLeftClick(self, down)
    end

    self.GetLeftMouseAction = NewGetLeftMouseAction
    self.OnLeftClick = NewOnLeftClick
end

AddAction("FOLLOW", "Follow", ActionFollow)
AddAction("PUSH", "Push", ActionPush)
AddAction("TENTFOLLOW", "Follow player in", ActionTentFollow)
AddAction("TENTPUSH", "Push player in", ActionTentPush)

AddComponentPostInit("playercontroller", PlayerControllerPostInit)

AddPlayerPostInit(OnPlayerActivated, OnPlayerDeactivated)

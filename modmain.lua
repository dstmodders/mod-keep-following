----
-- Modmain.
--
-- **Source Code:** [https://github.com/dstmodders/mod-keep-following](https://github.com/dstmodders/mod-keep-following)
--
-- @author [Depressed DST Modders](https://github.com/dstmodders)
-- @copyright 2019-2024
-- @license MIT
-- @release 0.22.0-alpha
----
local _G = GLOBAL
local require = _G.require

_G.MOD_KEEP_FOLLOWING_TEST = false

--- Globals
-- @section globals

local ACTIONS = _G.ACTIONS
local BufferedAction = _G.BufferedAction
local CONTROL_ACTION = _G.CONTROL_ACTION
local CONTROL_PRIMARY = _G.CONTROL_PRIMARY
local CONTROL_SECONDARY = _G.CONTROL_SECONDARY
local TheInput = _G.TheInput

--- SDK
-- @section sdk

local SDK

SDK = require("keepfollowing/sdk/sdk/sdk")
SDK.Load(env, "keepfollowing/sdk", {
    "Config",
    "Debug",
    "DebugUpvalue",
    "Entity",
    "Input",
    "Method",
    "ModMain",
    "Player",
    "RPC",
    "Thread",
    "World",
})

--- Debugging
-- @section debugging

SDK.Debug.SetIsEnabled(GetModConfigData("debug") and true or false)
SDK.Debug.ModConfigs()

--- Actions
-- @section actions

local _PUSH_WITH_RMB = GetModConfigData("push_with_rmb")
local _REVERSE_BUTTONS = GetModConfigData("reverse_buttons")

local function AddClientAction(id, str, fn)
    -- Note: Use this function instead of the built-in AddAction. AddAction writes into ACTIONS.
    -- This mod is client-only, and the game numbers a character's inherent actions by walking
    -- pairs(ACTIONS). Those extra keys change that order on the client, so built-in actions show up
    -- on the wrong characters.
    local modname = env.modname
    local action = _G.Action()

    action.id = id
    action.str = str
    action.fn = fn
    action.mod_name = modname

    local mod_ids = _G.ACTION_MOD_IDS
    if mod_ids[modname] == nil then
        mod_ids[modname] = {}
    end
    table.insert(mod_ids[modname], action.id)
    action.code = #mod_ids[modname]

    local by_code = _G.MOD_ACTIONS_BY_ACTION_CODE
    if by_code[modname] == nil then
        by_code[modname] = {}
    end
    by_code[modname][action.code] = action

    _G.STRINGS.ACTIONS[action.id] = action.str

    return action
end

local ACTION_FOLLOW = AddClientAction("MOD_KEEP_FOLLOWING_FOLLOW", "Follow", function(act)
    local keepfollowing = SDK.Utils.Chain.Get(act, "doer", "components", "keepfollowing")
    if keepfollowing and act.doer and act.target then
        keepfollowing:Stop()
        keepfollowing:StartFollowing(act.target)
        return true
    end
    return false
end)

local ACTION_PUSH = AddClientAction("MOD_KEEP_FOLLOWING_PUSH", "Push", function(act)
    local keepfollowing = SDK.Utils.Chain.Get(act, "doer", "components", "keepfollowing")
    if keepfollowing and act.doer and act.target then
        keepfollowing:Stop()
        keepfollowing:StartPushing(act.target)
        return true
    end
    return false
end)

local ACTION_TENT_FOLLOW = AddClientAction(
    "MOD_KEEP_FOLLOWING_TENT_FOLLOW",
    "Follow player in",
    function(act)
        local keepfollowing = SDK.Utils.Chain.Get(act, "doer", "components", "keepfollowing")
        if keepfollowing and act.doer and act.target then
            local leader = SDK.Entity.GetTentSleeper(act.target)
            if leader then
                keepfollowing:Stop()
                keepfollowing:StartFollowing(leader)
                return true
            end
        end
        return false
    end
)

local ACTION_TENT_PUSH = AddClientAction(
    "MOD_KEEP_FOLLOWING_TENT_PUSH",
    _PUSH_WITH_RMB ~= _REVERSE_BUTTONS and "Push player" or "Push player in",
    function(act)
        local keepfollowing = SDK.Utils.Chain.Get(act, "doer", "components", "keepfollowing")
        if keepfollowing and act.doer and act.target then
            local leader = SDK.Entity.GetTentSleeper(act.target)
            if leader then
                keepfollowing:Stop()
                keepfollowing:StartPushing(leader)
                return true
            end
        end
        return false
    end
)

--- Player
-- @section player

SDK.OnPlayerActivated(function(world, player)
    player:AddComponent("keepfollowing")
    local keepfollowing = player.components.keepfollowing
    if keepfollowing then
        keepfollowing.is_master_sim = world.ismastersim
        keepfollowing.world = world

        -- GetModConfigData
        local configs = {
            "follow_distance",
            "follow_distance_keeping",
            "follow_method",
            "push_lag_compensation",
            "push_mass_checking",
            "target_entities",
        }

        for _, config in ipairs(configs) do
            keepfollowing.config[config] = GetModConfigData(config)
        end
    end
end)

SDK.OnPlayerDeactivated(function(_, player)
    player:RemoveComponent("keepfollowing")
end)

--- Components
-- @section components

local function IsOurAction(action)
    return action == ACTION_FOLLOW
        or action == ACTION_PUSH
        or action == ACTION_TENT_FOLLOW
        or action == ACTION_TENT_PUSH
end

SDK.OnLoadComponent("playeractionpicker", function(__self, player)
    if player ~= _G.ThePlayer then
        return
    end

    local _KEY_ACTION = SDK.Config.GetModKeyConfigData("key_action")
    local _KEY_PUSH = SDK.Config.GetModKeyConfigData("key_push")

    --
    -- Overrides
    --

    SDK.OverrideMethod(__self, "DoGetMouseActions", function(original_fn, self, position, __target)
        local lmb, rmb = original_fn(self, position, __target)
        if TheInput:IsKeyDown(_KEY_ACTION) then
            local keepfollowing = player.components.keepfollowing
            local buffered = self.inst:GetBufferedAction()

            -- We could have used lmb.target. However, the PlayerActionPicker has
            -- leftclickoverride and rightclickoverride so we can't trust that. A good example
            -- is Woodie's Weregoose form which overrides mouse actions.
            local target = TheInput:GetWorldEntityUnderMouse()
            if not target then
                return lmb, rmb
            end

            -- You are probably wondering why we need this check? Isn't it better to just show
            -- our actions without the buffered action check?
            --
            -- There are so many mods out there "in the wild" which also do different in-game
            -- actions and don't bother checking for interruptions in their scheduler tasks
            -- (threads). For example, ActionQueue Reborn will always try to force their action
            -- if entities have already been selected. We can adapt our mod for such cases to
            -- improve compatibility but this is the only bulletproof way to cover the most.
            if
                buffered
                and not IsOurAction(buffered.action)
                and buffered.action ~= ACTIONS.WALKTO
            then
                return lmb, rmb
            end

            if _REVERSE_BUTTONS then -- To avoid ACTIONS.WALKTO becoming rmb
                lmb, rmb = rmb, lmb
            end

            if target:HasTag("tent") and target:HasTag("hassleeper") then
                if _PUSH_WITH_RMB then
                    lmb = BufferedAction(player, target, ACTION_TENT_FOLLOW)
                elseif TheInput:IsKeyDown(_KEY_PUSH) then
                    lmb = BufferedAction(player, target, ACTION_TENT_PUSH)
                elseif not TheInput:IsKeyDown(_KEY_PUSH) then
                    lmb = BufferedAction(player, target, ACTION_TENT_FOLLOW)
                end
            end

            if keepfollowing:CanBeLeader(target) then
                if _PUSH_WITH_RMB then
                    lmb = BufferedAction(player, target, ACTION_FOLLOW)
                elseif TheInput:IsKeyDown(_KEY_PUSH) and keepfollowing:CanBePushed(target) then
                    lmb = BufferedAction(player, target, ACTION_PUSH)
                elseif not TheInput:IsKeyDown(_KEY_PUSH) then
                    lmb = BufferedAction(player, target, ACTION_FOLLOW)
                end
            end

            if _PUSH_WITH_RMB then
                if target:HasTag("tent") and target:HasTag("hassleeper") then
                    rmb = BufferedAction(player, target, ACTION_TENT_PUSH)
                end

                if keepfollowing:CanBeLeader(target) and keepfollowing:CanBePushed(target) then
                    rmb = BufferedAction(player, target, ACTION_PUSH)
                end
            end

            if _REVERSE_BUTTONS then
                lmb, rmb = rmb, lmb
            end
        end
        return lmb, rmb
    end, SDK.OVERRIDE.ORIGINAL_NONE)
end)

SDK.OnLoadComponent("playercontroller", function(__self, player)
    if player ~= _G.ThePlayer then
        return
    end

    local _COMPATIBILITY = GetModConfigData("compatibility")

    --
    -- Helpers
    --

    local function KeepFollowingStop()
        local keepfollowing = player.components.keepfollowing
        if keepfollowing then
            keepfollowing:Stop()
        end
    end

    -- We ignore ActionQueue(DST) mod here intentionally. Our mod won't work with theirs if the same
    -- action key is used. So there is no point to mess with their functions anyway.
    --
    -- From an engineering perspective, the method which ActionQueue(DST) mod uses for overriding
    -- PlayerController:OnControl() should never be used. Technically, we can fix this issue by
    -- either using the same approach or using the global input handler when ActionQueue(DST) mod is
    -- enabled. However, I don't see any valid reason to do that.
    local function ClearActionQueueRebornEntities()
        local actionqueuer = player.components.actionqueuer
        if
            not actionqueuer
            or not actionqueuer.ClearActionThread
            or not actionqueuer.ClearSelectionThread
            or not actionqueuer.ClearSelectedEntities
        then
            return
        end

        actionqueuer:ClearActionThread()
        actionqueuer:ClearSelectionThread()
        actionqueuer:ClearSelectedEntities()
    end

    local function OurMouseAction(act)
        if not act then
            KeepFollowingStop()
            return false
        end

        local action = act.action
        if IsOurAction(action) then
            ClearActionQueueRebornEntities()
            if action.fn(act) then
                return true
            end
        else
            KeepFollowingStop()
        end

        return false
    end

    --
    -- Overrides
    --

    SDK.OverrideMethod(__self, "OnControl", function(original_fn, self, control, down)
        if SDK.Input.IsControlMove(control) or control == CONTROL_ACTION then
            KeepFollowingStop()
        end

        if _COMPATIBILITY == "alternative" then
            if control == CONTROL_PRIMARY and not down then
                if TheInput:GetHUDEntityUnderMouse() or self:IsAOETargeting() then
                    return original_fn(self, control, down)
                end
                OurMouseAction(self:GetLeftMouseAction())
            elseif control == CONTROL_SECONDARY and not down then
                if TheInput:GetHUDEntityUnderMouse() or self:IsAOETargeting() then
                    return original_fn(self, control, down)
                end
                OurMouseAction(self:GetRightMouseAction())
            end
        end

        original_fn(self, control, down)
    end, SDK.OVERRIDE.ORIGINAL_NONE)

    if _COMPATIBILITY == "recommended" then
        SDK.OverrideMethod(__self, "OnLeftClick", function(original_fn, self, down)
            if
                not down
                and not self:IsAOETargeting()
                and not TheInput:GetHUDEntityUnderMouse()
                and OurMouseAction(self:GetLeftMouseAction())
            then
                return
            end
            original_fn(self, down)
        end, SDK.OVERRIDE.ORIGINAL_NONE)

        SDK.OverrideMethod(__self, "OnRightClick", function(original_fn, self, down)
            if
                not down
                and not self:IsAOETargeting()
                and not TheInput:GetHUDEntityUnderMouse()
                and OurMouseAction(self:GetRightMouseAction())
            then
                return
            end
            original_fn(self, down)
        end, SDK.OVERRIDE.ORIGINAL_NONE)
    end
end)

SDK.OnLoadClass("widgets/targetindicator", function(__self, owner, target)
    local _TARGET_INDICATOR_USAGE = SDK.Config.GetModConfigData("target_indicator_usage")

    if _TARGET_INDICATOR_USAGE ~= "binded" then
        return
    end

    local _KEY_ACTION = SDK.Config.GetModKeyConfigData("key_action")
    local _KEY_PUSH = SDK.Config.GetModKeyConfigData("key_push")

    --
    -- Helpers
    --

    local function GetOurMouseActions(player, __target)
        local keepfollowing = player.components.keepfollowing
        local lmb, rmb
        if TheInput:IsKeyDown(_KEY_ACTION) then
            if keepfollowing:CanBeLeader(__target) then
                if _PUSH_WITH_RMB then
                    lmb = BufferedAction(player, __target, ACTION_FOLLOW)
                elseif TheInput:IsKeyDown(_KEY_PUSH) and keepfollowing:CanBePushed(__target) then
                    lmb = BufferedAction(player, __target, ACTION_PUSH)
                elseif not TheInput:IsKeyDown(_KEY_PUSH) then
                    lmb = BufferedAction(player, __target, ACTION_FOLLOW)
                end
            end

            if _PUSH_WITH_RMB then
                if keepfollowing:CanBeLeader(__target) and keepfollowing:CanBePushed(__target) then
                    rmb = BufferedAction(player, __target, ACTION_PUSH)
                end
            end

            if _REVERSE_BUTTONS then
                lmb, rmb = rmb, lmb
            end
        end
        return lmb, rmb
    end

    --
    -- Overrides
    --

    SDK.OverrideMethod(__self, "OnMouseButton", function(original_fn, self, button, down, x, y)
        local lmb, rmb = GetOurMouseActions(owner, target)
        if lmb and down and button == _G.MOUSEBUTTON_LEFT then
            lmb:Do()
        end
        if rmb and down and button == _G.MOUSEBUTTON_RIGHT then
            rmb:Do()
        end
        original_fn(self, button, down, x, y)
    end, SDK.OVERRIDE.ORIGINAL_NONE)

    SDK.OverrideMethod(__self, "OnRawKey", function(original_fn, self, key, down)
        local player_name = self.name
        local new_text = player_name
        local lmb, rmb = GetOurMouseActions(owner, target)
        if lmb and rmb then
            new_text = string.format(
                " %s %s\n %s %s",
                lmb.action.str,
                player_name,
                rmb.action.str,
                player_name
            )
        elseif lmb then
            new_text = string.format(" %s %s", lmb.action.str, player_name)
        elseif rmb then
            new_text = string.format(" %s %s", rmb.action.str, player_name)
        end
        self.name_label:SetString(new_text)
        original_fn(self, key, down)
    end, SDK.OVERRIDE.ORIGINAL_NONE)
end)

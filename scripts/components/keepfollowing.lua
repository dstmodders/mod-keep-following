----
-- Component `keepfollowing`.
--
-- Includes functionality for following and pushing a leader.
--
-- **Source Code:** [https://github.com/dstmodders/mod-keep-following](https://github.com/dstmodders/mod-keep-following)
--
-- @classmod KeepFollowing
--
-- @author Victor Popkov
-- @copyright 2019
-- @license MIT
-- @release 0.21.0
----
local Utils = require("keepfollowing/utils")

local _FOLLOWING_PATH_THREAD_ID = "following_path_thread"
local _FOLLOWING_THREAD_ID = "following_thread"
local _PUSHING_THREAD_ID = "pushing_thread"
local _TENT_FIND_INVISIBLE_PLAYER_RANGE = 50

--- Constructor.
-- @function _ctor
-- @tparam EntityScript inst Player instance
-- @usage ThePlayer:AddComponent("keepfollowing")
local KeepFollowing = Class(function(self, inst)
    self:DoInit(inst)
end)

--- Helpers
-- @section helpers

local function IsOnPlatform(world, inst)
    if
        Utils.ChainValidate(world, "Map", "GetPlatformAtPoint")
        and Utils.ChainValidate(inst, "GetPosition")
    then
        return world.Map:GetPlatformAtPoint(Utils.ChainGet(inst:GetPosition(), "Get", true))
                and true
            or false
    end
end

local function IsPassable(world, pos)
    return Utils.ChainValidate(world, "Map", "IsPassableAtPoint")
            and Utils.ChainValidate(pos, "Get")
            and world.Map:IsPassableAtPoint(pos:Get())
        or false
end

local function GetClosestPosition(entity1, entity2)
    local distance = entity1.Physics:GetRadius() + entity2.Physics:GetRadius()
    return entity1:GetPositionAdjacentTo(entity2, distance)
end

local function WalkToPoint(self, pt)
    Utils.WalkToPoint(self.inst, pt)
    if _G.ModKeepFollowingDebug then
        self.debug_rpc_counter = self.debug_rpc_counter + 1
    end
end

--- General
-- @section general

--- Checks if the player is idle.
-- @treturn boolean
function KeepFollowing:IsIdle()
    if self.inst.sg then
        return self.inst.sg:HasStateTag("idle")
            or (self.inst:HasTag("idle") and self.inst:HasTag("nopredict"))
    end
    return self.inst.AnimState:IsCurrentAnimation("idle_pre")
        or self.inst.AnimState:IsCurrentAnimation("idle_loop")
        or self.inst.AnimState:IsCurrentAnimation("idle_pst")
end

--- Checks if player is on platform state.
-- @treturn boolean
function KeepFollowing:IsOnPlatform()
    return IsOnPlatform(self.world, self.inst)
end

--- Stops both following and pushing.
--
-- General wrapper to call `StopFollowing` and/or `StopPushing` based on the current state.
--
-- @treturn boolean
function KeepFollowing:Stop()
    if Utils.IsHUDFocused(self.inst) then
        if self:IsFollowing() then
            self:StopFollowing()
            return true
        end

        if self:IsPushing() then
            self:StopPushing()
            return true
        end
    end
    return false
end

--- Movement prediction
-- @section movement-prediction

local function MovementPrediction(inst, enable)
    if enable then
        local x, _, z = inst.Transform:GetWorldPosition()
        SendRPCToServer(RPC.LeftClick, ACTIONS.WALKTO.code, x, z)
        inst:EnableMovementPrediction(true)
        return true
    elseif inst.components and inst.components.locomotor then
        inst.components.locomotor:Stop()
        inst:EnableMovementPrediction(false)
        return false
    end
end

--- Enables/Disables movement prediction.
-- @tparam boolean enable
-- @treturn boolean
function KeepFollowing:MovementPrediction(enable)
    local is_enabled = MovementPrediction(self.inst, enable)
    self:DebugString("Movement prediction:", is_enabled and "enabled" or "disabled")
    return is_enabled
end

--- Leader
-- @section leader

--- Gets leader.
-- @treturn EntityScript
function KeepFollowing:GetLeader()
    return self.leader
end

--- Checks if leader is on platform.
-- @treturn boolean
function KeepFollowing:IsLeaderOnPlatform()
    return IsOnPlatform(self.world, self.leader)
end

--- Checks if an entity can be followed.
--
-- Checks whether an entity is valid and has either a `locomotor` or `balloon` tag.
--
-- @tparam EntityScript entity An entity as a potential leader to follow
-- @treturn boolean
function KeepFollowing:CanBeFollowed(entity) -- luacheck: only
    return Utils.ChainGet(entity, "entity", "IsValid", true)
            and (entity:HasTag("locomotor") or entity:HasTag("balloon"))
        or false
end

--- Checks if an entity can be pushed.
-- @tparam EntityScript entity An entity as a potential leader to push
-- @treturn boolean
function KeepFollowing:CanBePushed(entity)
    if not self.inst or not entity or not entity.Physics then
        return false
    end

    -- Ghosts should be able to push other players and ignore the mass difference checking. The
    -- point is to provide light.
    if self.inst:HasTag("playerghost") and entity:HasTag("player") then
        return true
    end

    local collision_group = Utils.ChainGet(entity, "Physics", "GetCollisionGroup", true)
    if
        collision_group == COLLISION.FLYERS -- different flyers don't collide with characters
        or collision_group == COLLISION.SANITY -- Shadow Creatures also don't collide
        or entity:HasTag("bird") -- so does birds
    then
        return false
    end

    if not self.config.push_mass_checking then
        return true
    end

    -- Mass is the key factor for pushing. For example, players have a mass of 75 while most bosses
    -- have a mass of 1000. Some entities just act as "unpushable" like Moleworm (99999) and
    -- Gigantic Beehive (999999). However, if Klei's physics is correct then even those entities can
    -- be pushed but it will take an insane amount of time...
    --
    -- So far the only entities with a high mass that still can be useful to be pushed are bosses
    -- like Bearger or Toadstool. They both have a mass of 1000 which makes a perfect ceil value for
    -- us to disable pushing.
    local entity_mass = entity.Physics:GetMass()
    local inst_mass = self.inst.Physics:GetMass()
    local mass_diff = math.abs(entity_mass - inst_mass)

    -- 925 = 1000 (boss) - 75 (player)
    if mass_diff > 925 then
        return false
    end

    -- When the player becomes a ghost his mass becomes 1. In that case, we just set the ceil
    -- difference to 10 (there is no point to push something with a mass higher than that) to allow
    -- pushing Frogs, Saladmanders and Critters as they all have a mass of 1.
    if inst_mass == 1 and mass_diff > 10 then
        return false
    end

    return true
end

--- Checks if an entity can be a leader.
-- @tparam EntityScript entity An entity as a potential leader
-- @treturn boolean
function KeepFollowing:CanBeLeader(entity)
    return entity ~= self.inst and self:CanBeFollowed(entity) or false
end

--- Sets leader.
--
-- Verifies if the passed entity can become a leader using `CanBeLeader` and sets it.
--
-- @tparam EntityScript leader An entity as a potential leader
-- @treturn boolean
function KeepFollowing:SetLeader(leader)
    if self:CanBeLeader(leader) then
        self.leader = leader
        self:DebugString(
            string.format(
                "New leader: %s. Distance: %0.2f",
                leader:GetDisplayName(),
                math.sqrt(self.inst:GetDistanceSqToPoint(leader:GetPosition()))
            )
        )
        return true
    elseif leader == self.inst then
        self:DebugError("You", "can't become a leader")
    else
        local _entity = leader == self.inst and "You" or nil
        _entity = _entity == nil and leader.GetDisplayName and leader:GetDisplayName() or "Entity"
        self:DebugError(_entity, "can't become a leader")
    end
    return false
end

--- Tent
-- @section tent

local function FindClosestInvisiblePlayerInRange(x, y, z, range)
    local closest, dist_sq
    local range_sq = range * range
    for _, v in ipairs(AllPlayers) do
        if not v.entity:IsVisible() then
            dist_sq = v:GetDistanceSqToPoint(x, y, z)
            if dist_sq < range_sq then
                range_sq = dist_sq
                closest = v
            end
        end
    end
    return closest, closest ~= nil and range_sq or nil
end

--- Gets a tent sleeper.
-- @tparam EntityScript tent A tent, Siesta Lean-to, etc.
-- @treturn EntityScript A sleeper (a player)
function KeepFollowing:GetTentSleeper(tent)
    local player
    local sleepingbag = Utils.ChainGet(tent, "components", "sleepingbag")
    if sleepingbag then
        self:DebugString("Component sleepingbag is available")
        player = sleepingbag.sleeper
    else
        self:DebugString("Component sleepingbag is not available")
    end

    if not player and tent:HasTag("tent") and tent:HasTag("hassleeper") then
        self:DebugString("Looking for sleepers...")
        local x, y, z = tent.Transform:GetWorldPosition()
        player = FindClosestInvisiblePlayerInRange(x, y, z, _TENT_FIND_INVISIBLE_PLAYER_RANGE)
    end

    if player and player:HasTag("sleeping") then
        self:DebugString("Found sleeper:", player:GetDisplayName())
        return player
    end
end

--- Following
-- @section following

local function GetDefaultMethodNextPosition(self, target)
    local pos = self.leader_positions[1]
    if pos then
        local inst_dist_sq = self.inst:GetDistanceSqToPoint(pos)
        local inst_dist = math.sqrt(inst_dist_sq)

        -- This represents the distance where the gathered points (leaderpositions) will be
        -- ignored/removed. There is no real point to step on each coordinate and we still need to
        -- remove the past ones. Smaller value gives more precision, especially near the corners.
        -- However, when lag compensation is off the movement becomes less smooth. I don't recommend
        -- using anything < 1 diameter.
        local step = self.inst.Physics:GetRadius() * 3
        local is_leader_near = self.inst:IsNear(self.leader, target + step)

        if
            not self.is_leader_near and is_leader_near
            or (is_leader_near and self.config.follow_distance_keeping)
        then
            self.leader_positions = {}
            return self.inst:GetPositionAdjacentTo(self.leader, target)
        end

        if not is_leader_near and inst_dist > step then
            return pos
        else
            table.remove(self.leader_positions, 1)
            pos = GetDefaultMethodNextPosition(self, target)
            return pos
        end
    end
end

local function GetClosestMethodNextPosition(self, target, is_leader_near)
    if not is_leader_near or self.config.follow_distance_keeping then
        local pos = self.inst:GetPositionAdjacentTo(self.leader, target)

        if IsPassable(self.world, pos) then
            return pos
        end

        if self:IsLeaderOnPlatform() ~= self:IsOnPlatform() then
            pos = GetClosestPosition(self.inst, self.leader)
        end

        return pos
    end
end

local function ResetFollowingFields(self)
    -- general
    self.leader = nil
    self.start_time = nil

    -- following
    self.following_path_thread = nil
    self.following_thread = nil
    self.is_following = false
    self.is_leader_near = false
    self.leader_positions = {}

    -- debugging
    self.debug_rpc_counter = 0
end

--- Checks if following state.
-- @treturn boolean
function KeepFollowing:IsFollowing()
    return self.leader and self.is_following
end

--- Starts the following thread.
--
-- Starts the thread to follow the leader based on the chosen method in the configurations. When the
-- "default" following method is used it starts the following path thread as well by calling the
-- `StartFollowingPathThread` to gather path coordinates of a leader.
function KeepFollowing:StartFollowingThread()
    local pos, pos_prev, is_leader_near, stuck

    local stuck_frames = 0
    local radius_inst = self.inst.Physics:GetRadius()
    local radius_leader = self.leader.Physics:GetRadius()
    local target = self.config.follow_distance + radius_inst + radius_leader

    self.following_thread = Utils.ThreadStart(_FOLLOWING_THREAD_ID, function()
        if not self.leader or not self.leader.entity:IsValid() then
            self:DebugError("Leader doesn't exist anymore")
            self:StopFollowing()
            return
        end

        is_leader_near = self.inst:IsNear(self.leader, target)

        if self.config.follow_method == "default" then
            -- default: player follows a leader step-by-step
            pos = GetDefaultMethodNextPosition(self, target)
            if pos then
                if self:IsIdle() or (not pos_prev or pos_prev ~= pos) then
                    pos_prev = pos
                    stuck = false
                    stuck_frames = 0
                    WalkToPoint(self, pos)
                elseif not stuck and pos_prev ~= pos then
                    stuck_frames = stuck_frames + 1
                    if stuck_frames * FRAMES > 0.5 then
                        pos_prev = pos
                        stuck = true
                    end
                elseif
                    not self:IsIdle()
                    and stuck
                    and pos_prev == pos
                    and #self.leader_positions > 1
                then
                    table.remove(self.leader_positions, 1)
                end
            end
        elseif self.config.follow_method == "closest" then
            -- closest: player goes to the closest target point from a leader
            pos = GetClosestMethodNextPosition(self, target, is_leader_near)
            if pos then
                if self:IsIdle() or (not pos_prev or pos:DistSq(pos_prev) > 0.1) then
                    pos_prev = pos
                    WalkToPoint(self, pos)
                end
            end
        end

        self.is_leader_near = is_leader_near

        Sleep(FRAMES)
    end, function()
        return self.inst and self.inst:IsValid() and self:IsFollowing()
    end, function()
        if self.config.follow_method == "default" then
            self:StartFollowingPathThread()
        end
    end, function()
        ResetFollowingFields(self)
    end)
end

--- Starts the following path thread.
--
-- Starts the thread to follow the leader based on the following method in the configurations.
function KeepFollowing:StartFollowingPathThread()
    local pos, pos_prev

    self.following_path_thread = Utils.ThreadStart(_FOLLOWING_PATH_THREAD_ID, function()
        if not self.leader or not self.leader.entity:IsValid() then
            self:DebugError("Leader doesn't exist anymore")
            self:StopFollowing()
            return
        end

        pos = self.leader:GetPosition()

        if self:IsLeaderOnPlatform() ~= self:IsOnPlatform() then
            pos = GetClosestPosition(self.inst, self.leader)
        end

        if not pos_prev then
            table.insert(self.leader_positions, pos)
            pos_prev = pos
        end

        if IsPassable(self.world, pos) == IsPassable(self.world, pos_prev) then
            -- 1 is the most optimal value so far
            if
                pos:DistSq(pos_prev) > 1
                and pos ~= pos_prev
                and self.leader_positions[#self.leader_positions] ~= pos
            then
                table.insert(self.leader_positions, pos)
                pos_prev = pos
            end
        end

        Sleep(FRAMES)
    end, function()
        return self.inst and self.inst:IsValid() and self:IsFollowing()
    end, function()
        self:DebugString("Started gathering path coordinates...")
    end)
end

--- Starts following a leader.
--
-- Stores the movement prediction state and handles the behaviour accordingly on a non-master shard.
-- Sets a leader using `SetLeader`, resets fields and starts the following thread by calling
-- `StartFollowingThread`.
--
-- @tparam EntityScript leader A leader to follow
-- @treturn boolean
function KeepFollowing:StartFollowing(leader)
    if self.is_following then
        self:DebugError("Already following")
        return false
    end

    if self.config.push_lag_compensation and not self.is_master_sim then
        local state = self.movement_prediction_state
        if state ~= nil then
            self:MovementPrediction(state)
            self.movement_prediction_state = nil
        end
    end

    if self:SetLeader(leader) then
        self:DebugString("Started following...")

        -- fields (general)
        self.start_time = os.clock()

        -- fields (pushing)
        self.following_path_thread = nil
        self.following_thread = nil
        self.is_following = true
        self.is_leader_near = false
        self.leader_positions = {}

        -- fields (debugging)
        self.debug_rpc_counter = 0

        -- start
        self:StartFollowingThread()

        return true
    end

    return false
end

--- Stops following.
-- @treturn boolean
function KeepFollowing:StopFollowing()
    if not self.is_following then
        self:DebugError("Not following")
        return false
    end

    if not self.leader then
        self:DebugError("No leader")
        return false
    end

    if not self.following_thread then
        self:DebugError("No active thread")
        return false
    end

    self:DebugString(
        string.format(
            "Stopped following %s. RPCs: %d. Time: %2.4f",
            self.leader:GetDisplayName(),
            self.debug_rpc_counter,
            os.clock() - self.start_time
        )
    )

    self.is_following = false

    return true
end

--- Pushing
-- @section pushing

local function ResetPushingFields(self)
    -- general
    self.leader = nil
    self.start_time = nil

    -- pushing
    self.is_pushing = false
    self.pushing_thread = nil

    -- debugging
    self.debug_rpc_counter = 0
end

--- Checks if pushing state.
-- @treturn boolean
function KeepFollowing:IsPushing()
    return self.leader and self.is_pushing
end

--- Starts the pushing thread.
--
-- Starts the thread to push the leader.
function KeepFollowing:StartPushingThread()
    local pos, pos_prev

    self.pushing_thread = Utils.ThreadStart(
        _PUSHING_THREAD_ID,
        function()
            if not self.leader or not self.leader.entity:IsValid() then
                self:DebugError("Leader doesn't exist anymore")
                self:StopPushing()
                return
            end

            pos = self.leader:GetPosition()

            if self:IsIdle() or (not pos_prev or pos_prev ~= pos) then
                pos_prev = pos
                WalkToPoint(self, pos)
            end

            Sleep(FRAMES)
        end,
        function()
            return self.inst and self.inst:IsValid() and self:IsPushing()
        end,
        nil,
        function()
            ResetPushingFields(self)
        end
    )
end

--- Starts pushing a leader.
--
-- Stores the movement prediction state and handles the behaviour accordingly on a non-master shard.
-- Sets a leader using `SetLeader`, prepares fields and starts the pushing thread by calling
-- `StartPushingThread`.
--
-- @tparam EntityScript leader A leader to push
-- @treturn boolean
function KeepFollowing:StartPushing(leader)
    if self.config.push_lag_compensation and not self.is_master_sim then
        if self.movement_prediction_state == nil then
            self.movement_prediction_state = Utils.IsLocomotorAvailable(self.inst)
        end

        if self.movement_prediction_state then
            self:MovementPrediction(false)
        end
    end

    if self.is_pushing then
        self:DebugError("Already pushing")
        return false
    end

    if self:SetLeader(leader) then
        self:DebugString("Started pushing...")

        -- fields (general)
        self.start_time = os.clock()

        -- fields (pushing)
        self.is_pushing = true
        self.pushing_thread = nil

        -- fields (debugging)
        self.debug_rpc_counter = 0

        -- start
        self:StartPushingThread()

        return true
    end

    return false
end

--- Stops pushing.
-- @treturn boolean
function KeepFollowing:StopPushing()
    if self.config.push_lag_compensation and not self.is_master_sim then
        self:MovementPrediction(self.movement_prediction_state)
        self.movement_prediction_state = nil
    end

    if not self.is_pushing then
        self:DebugError("Not pushing")
        return false
    end

    if not self.leader then
        self:DebugError("No leader")
        return false
    end

    if not self.pushing_thread then
        self:DebugError("No active thread")
        return false
    end

    self:DebugString(
        string.format(
            "Stopped pushing %s. RPCs: %d. Time: %2.4f",
            self.leader:GetDisplayName(),
            self.debug_rpc_counter,
            os.clock() - self.start_time
        )
    )

    self.is_pushing = false

    return true
end

--- Initialization
-- @section initialization

--- Initializes.
--
-- Sets default fields, adds debug methods and starts the component.
--
-- @tparam EntityScript inst Player instance
function KeepFollowing:DoInit(inst)
    Utils.AddDebugMethods(self)

    -- general
    self.inst = inst
    self.is_client = false
    self.is_dst = false
    self.is_master_sim = TheWorld.ismastersim
    self.leader = nil
    self.movement_prediction_state = nil
    self.name = "KeepFollowing"
    self.start_time = nil
    self.world = TheWorld

    -- following
    self.following_path_thread = nil
    self.following_thread = nil
    self.is_following = false
    self.is_leader_near = false
    self.leader_positions = {}

    -- pushing
    self.is_pushing = false
    self.pushing_thread = nil

    -- debugging
    self.debug_rpc_counter = 0

    -- config
    self.config = {
        follow_distance = 2.5,
        follow_distance_keeping = false,
        follow_method = "default",
        push_lag_compensation = true,
        push_mass_checking = true,
    }

    -- update
    inst:StartUpdatingComponent(self)

    -- tests
    if _G.MOD_KEEP_FOLLOWING_TEST then
        self._FindClosestInvisiblePlayerInRange = FindClosestInvisiblePlayerInRange
        self._IsOnPlatform = IsOnPlatform
        self._IsPassable = IsPassable
        self._MovementPrediction = MovementPrediction
    end

    self:DebugInit(self.name)
end

return KeepFollowing

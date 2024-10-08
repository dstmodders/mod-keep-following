----
-- Component `keepfollowing`.
--
-- Includes functionality for following and pushing a leader.
--
-- _Below is the list of some self-explanatory methods which have been added using SDK._
--
-- **Getters:**
--
--   - `GetLeader`
--   - `IsFollowing`
--   - `IsPushing`
--
-- **Source Code:** [https://github.com/dstmodders/mod-keep-following](https://github.com/dstmodders/mod-keep-following)
--
-- @classmod KeepFollowing
--
-- @author [Depressed DST Modders](https://github.com/dstmodders)
-- @copyright 2019-2024
-- @license MIT
-- @release 0.22.0-alpha
----
local SDK = require("keepfollowing/sdk/sdk/sdk")

local _FOLLOWING_PATH_THREAD_ID = "following_path_thread"
local _FOLLOWING_THREAD_ID = "following_thread"
local _PUSHING_THREAD_ID = "pushing_thread"
local _WORMHOLE_TRAVEL_THREAD_ID = "wormhole_travel_thread"

--- Lifecycle
-- @section lifecycle

--- Constructor.
-- @function _ctor
-- @tparam EntityScript inst Player instance
-- @usage ThePlayer:AddComponent("keepfollowing")
local KeepFollowing = Class(function(self, inst)
    SDK.Debug.AddMethods(self)
    SDK.Method.SetClass(self).AddToString("KeepFollowing").AddGetters({
        is_following = "IsFollowing",
        is_pushing = "IsPushing",
        is_wormhole_travelling = "IsWormholeTravelling",
        leader = "GetLeader",
    })

    -- general
    self.inst = inst
    self.leader = nil
    self.movement_prediction_state = nil
    self.start_time = nil

    -- wormhole
    self.is_wormhole_travelling = false
    self.is_wormhole_travel_successful = false
    self.last_leader_pos = nil
    self.leader_id = nil
    self.wormhole_travel_thread = nil

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
        target_entities = "default",
    }

    -- update
    inst:StartUpdatingComponent(self)

    self:DebugInit(tostring(self))
end)

--- Helpers
-- @section helpers

local function HidePlayer(inst)
    inst = inst or ThePlayer
    local body = SDK.Player.Inventory.GetEquippedBodyItem(inst)
    if body and body:HasTag("shell") then
        SendRPCToServer(RPC.UseItemFromInvTile, ACTIONS.USEITEM.code, body)
    else
        local head = SDK.Player.Inventory.GetEquippedHeadItem(inst)
        if head and head:HasTag("hide") then
            SendRPCToServer(RPC.UseItemFromInvTile, ACTIONS.USEITEM.code, head)
        else
            return
        end
    end
end

local function IsHiding(inst)
    return inst
        and (inst.sg and inst.sg:HasStateTag("hiding") or inst.HasTag and inst:HasTag("hiding"))
end

local function WalkToPoint(self, pt)
    if not SDK.Player.WalkToPoint(pt, self.inst) then
        SDK.RPC.WalkToPoint(pt)
    end

    if SDK.Debug then
        self.debug_rpc_counter = self.debug_rpc_counter + 1
    end
end

--- General
-- @section general

--- Stops both following and pushing.
--
-- General wrapper to call `StopFollowing` and/or `StopPushing` based on the current state.
--
-- @treturn boolean
function KeepFollowing:Stop()
    if not SDK.Player.IsHUDHasInputFocus(self.inst) then
        if self:IsFollowing() then
            self:StopFollowing()
            return true
        end

        if self:IsPushing() then
            self:StopPushing()
            return true
        end

        if self:IsWormholeTravelling() then
            self:StopWormholeTravel()
            return true
        end
    end
    return false
end

--- Leader
-- @section leader

--- Checks if an entity can be followed.
--
-- Checks whether an entity is valid and has either a `locomotor` or `balloon` tag. It also respects
-- the "Target Entities" configuration options.
--
-- @tparam EntityScript entity An entity as a potential leader to follow
-- @treturn boolean
function KeepFollowing:CanBeFollowed(entity)
    if
        not SDK.Utils.Chain.Get(entity, "entity", "IsValid", true)
        or not entity:HasTag("locomotor")
        or entity:HasTag("balloon")
    then
        return false
    end

    local target_entities = self.config.target_entities

    if target_entities == "default" then
        return true
    elseif target_entities == "friendly" then
        return not entity:HasTag("hostile")
    elseif target_entities == "players" then
        return entity:HasTag("player")
    end

    return false
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

    local collision_group = SDK.Utils.Chain.Get(entity, "Physics", "GetCollisionGroup", true)
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
        self.leader_id = self.leader.userid
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

--- Wormhole
-- @section wormhole

local function JumpThroughWormhole(self, wormhole)
    local player = self.inst
    if player and wormhole then
        local action = BufferedAction(player, wormhole, ACTIONS.JUMPIN)
        local playercontroller = player.components.playercontroller
        local wormhole_pos = wormhole:GetPosition()
        action.preview_cb = function()
            SendRPCToServer(
                RPC.LeftClick,
                ACTIONS.JUMPIN.code,
                wormhole_pos.x,
                wormhole_pos.z,
                wormhole
            )
        end
        if playercontroller and playercontroller.locomotor then
            playercontroller:DoAction(action)
        else
            SendRPCToServer(
                RPC.LeftClick,
                ACTIONS.JUMPIN.code,
                wormhole_pos.x,
                wormhole_pos.z,
                wormhole
            )
        end
        if SDK.Debug then
            self.debug_rpc_counter = self.debug_rpc_counter + 1
        end
    end
end

local function LocateNearbyWormhole(pos)
    local wormhole
    local entities = TheSim:FindEntities(pos.x, pos.y, pos.z, 2, { "teleporter" }, {})
    local wormhole_prefabs = { "wormhole", "tentacle_pillar_hole", "pocketwatch_portal_entrance" }
    for _, entity in pairs(entities) do
        for _, prefab in pairs(wormhole_prefabs) do
            if entity.prefab == prefab then
                wormhole = entity
                break
            end
        end
    end
    return wormhole
end

local function LocatePlayerByID(id)
    local target
    for _, player in pairs(AllPlayers) do
        if player.userid == id then
            target = player
            break
        end
    end
    return target
end

local function ResetWormholeFields(self)
    self.is_wormhole_travelling = false
    self.is_wormhole_travel_successful = false
    self.last_leader_pos = nil
    self.leader_id = nil
    self.wormhole_travel_thread = nil
end

--- Starts the wormhole travel thread.
--
-- Starts the thread to travel through the wormhole in which a leader has jumped into and resumes
-- following.
function KeepFollowing:StartWormholeTravelThread()
    local wormhole, pos, is_correct_side, was_jumping, player_pos
    self.is_wormhole_travelling = true
    self.wormhole_travel_thread = SDK.Thread.Start(
        _WORMHOLE_TRAVEL_THREAD_ID,
        function()
            if not self.leader_id then
                self:DebugError("No ID can be used to find the leader")
                self:StopWormholeTravel()
                return
            end

            if
                was_jumping
                and (
                    not self.inst.entity:IsVisible()
                    or self.inst:GetDistanceSqToPoint(player_pos) > 3 * 3
                )
            then
                -- We use "3" as the distance because that is the MAX_JUMPIN_DIST variable provided
                -- in SGwilson.lua at the "jumpin" state.
                self:DebugString("Detected user jumped through the wormhole")
                self.is_wormhole_travel_successful = true
            end

            was_jumping = SDK.Player.IsWormholeJumping(self.inst)
            player_pos = self.inst:GetPosition()
            if self.is_wormhole_travel_successful then
                self:DebugString(string.format("Locating player by id: %s", self.leader_id))
                local player = LocatePlayerByID(self.leader_id)
                if player then
                    local player_name = player.GetDisplayName and player:GetDisplayName()
                    self:DebugString(string.format("Found player: %s", player_name))
                    self:SetLeader(player)
                else
                    self:DebugError(
                        string.format("Unable to locate player with id: %s", self.leader_id)
                    )
                end
                self:StopWormholeTravel()
                return
            end

            if was_jumping then
                Sleep(FRAMES)
                return
            end

            if wormhole and wormhole.entity:IsValid() and is_correct_side then
                self:DebugString(
                    string.format("Attempting to jump through wormhole %s", tostring(wormhole))
                )
                JumpThroughWormhole(self, wormhole)
                Sleep(1)
            elseif wormhole and not wormhole.entity:IsValid() then
                self:DebugError("Wormhole not valid anymore")
                self:StopWormholeTravel()
                return
            end

            pos = self.leader_positions[#self.leader_positions - 1]
            if pos and not is_correct_side then
                WalkToPoint(self, pos)
                if self.inst:GetDistanceSqToPoint(pos) < 0.5 * 0.5 then
                    is_correct_side = true
                end
            elseif not pos then
                is_correct_side = true
            end

            if self.last_leader_pos and not wormhole then
                wormhole = LocateNearbyWormhole(self.last_leader_pos)
                if not wormhole then
                    self:DebugError("Could not locate wormhole at last position")
                    self:StopWormholeTravel()
                    return
                end
            elseif not self.last_leader_pos then
                self:DebugError("No known last position for leader")
                self:StopWormholeTravel()
                return
            end

            Sleep(FRAMES)
        end,
        function()
            return self.inst and self.inst:IsValid() and self:IsWormholeTravelling()
        end,
        nil,
        function()
            ResetWormholeFields(self)
        end
    )
end

--- Stops wormhole travelling.
-- @treturn boolean
function KeepFollowing:StopWormholeTravel()
    if not self.wormhole_travel_thread then
        self:DebugError("No active thread")
        return false
    end

    self:DebugString(
        string.format(
            "Stopped wormhole travel for leader ID %s. RPCs: %d.",
            tostring(self.leader_id),
            self.debug_rpc_counter
        )
    )

    ResetWormholeFields(self)
    self.is_wormhole_travelling = false

    return true
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

        if SDK.World.IsPointPassable(pos) then
            return pos
        end

        if SDK.Player.IsOnPlatform(self.leader) ~= SDK.Player.IsOnPlatform(self.inst) then
            pos = SDK.Entity.GetPositionNearEntities(self.inst, self.leader)
        end

        return pos
    end
end

local function ResetFollowingFields(self)
    -- general
    self.leader = nil
    self.start_time = nil

    -- wormhole
    self.leader_id = nil

    -- following
    self.following_path_thread = nil
    self.following_thread = nil
    self.is_following = false
    self.is_leader_near = false
    self.leader_positions = {}

    -- debugging
    self.debug_rpc_counter = 0
end

--- Starts the following thread.
--
-- Starts the thread to follow the leader based on the chosen method in the configurations. When the
-- "default" following method is used it starts the following path thread as well by calling the
-- `StartFollowingPathThread` to gather path coordinates of a leader.
function KeepFollowing:StartFollowingThread()
    local pos, pos_prev, is_leader_near, stuck, was_jumping, leader_pos

    local stuck_frames = 0
    local radius_inst = self.inst.Physics:GetRadius()
    local radius_leader = self.leader.Physics:GetRadius()
    local target = self.config.follow_distance + radius_inst + radius_leader

    self.following_thread = SDK.Thread.Start(_FOLLOWING_THREAD_ID, function()
        if self:IsWormholeTravelling() then
            Sleep(FRAMES)
            return
        elseif
            was_jumping
            and self.leader
            and (
                not self.leader.entity:IsValid()
                or not self.leader.entity:IsVisible()
                or not self.leader.entity:IsAwake()
                or self.leader:GetDistanceSqToPoint(leader_pos) > 3 * 3
            )
        then
            self:DebugString("Detected leader jumping through wormhole")
            self.last_leader_pos = leader_pos
            self.leader_id = self.leader.userid
            self:StartWormholeTravelThread()
            was_jumping = nil
            leader_pos = nil
            return
        end

        if not self.leader or not self.leader.entity:IsValid() then
            self:DebugError("Leader doesn't exist anymore")
            self:StopFollowing()
            return
        end

        was_jumping = SDK.Player.IsWormholeJumping(self.leader)
        leader_pos = self.leader and self.leader.entity:IsValid() and self.leader:GetPosition()
            or nil
        is_leader_near = self.inst:IsNear(self.leader, target)

        if self.config.follow_method == "default" then
            -- default: player follows a leader step-by-step
            pos = GetDefaultMethodNextPosition(self, target)
            if pos then
                if SDK.Player.IsIdle(self.inst) or (not pos_prev or pos_prev ~= pos) then
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
                    not SDK.Player.IsIdle(self.inst)
                    and stuck
                    and pos_prev == pos
                    and #self.leader_positions > 1
                then
                    table.remove(self.leader_positions, 1)
                end
            elseif SDK.Player.IsIdle(self.inst) and not IsHiding(self.inst) then
                HidePlayer(self.inst)
            end
        elseif self.config.follow_method == "closest" then
            -- closest: player goes to the closest target point from a leader
            pos = GetClosestMethodNextPosition(self, target, is_leader_near)
            if pos then
                if SDK.Player.IsIdle(self.inst) or (not pos_prev or pos:DistSq(pos_prev) > 0.1) then
                    pos_prev = pos
                    WalkToPoint(self, pos)
                end
            elseif SDK.Player.IsIdle(self.inst) and not IsHiding(self.inst) then
                HidePlayer(self.inst)
            end
        end

        self.is_leader_near = is_leader_near

        Sleep(FRAMES)
    end, function()
        return self.inst and self.inst:IsValid() and self.leader and self:IsFollowing()
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
    local pos, pos_prev, was_jumping

    self.following_path_thread = SDK.Thread.Start(_FOLLOWING_PATH_THREAD_ID, function()
        if self:IsWormholeTravelling() then
            was_jumping = nil
            Sleep(FRAMES)
            return
        end

        if not self.leader or not self.leader.entity:IsValid() then
            if was_jumping then
                Sleep(1)
                was_jumping = nil
                return
            end
            self:DebugError("Leader doesn't exist anymore")
            self:StopFollowing()
            return
        end
        was_jumping = SDK.Player.IsWormholeJumping(self.leader)

        pos = self.leader:GetPosition()

        if SDK.Player.IsOnPlatform(self.leader) ~= SDK.Player.IsOnPlatform(self.inst) then
            pos = SDK.Entity.GetPositionNearEntities(self.inst, self.leader)
        end

        if not pos_prev then
            table.insert(self.leader_positions, pos)
            pos_prev = pos
        end

        if SDK.World.IsPointPassable(pos) == SDK.World.IsPointPassable(pos_prev) then
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
        return self.inst and self.inst:IsValid() and self.leader and self:IsFollowing()
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

    if self.config.push_lag_compensation and not SDK.World.IsMasterSim() then
        local state = self.movement_prediction_state
        if state ~= nil then
            SDK.Player.SetMovementPrediction(state)
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

--- Starts the pushing thread.
--
-- Starts the thread to push the leader.
function KeepFollowing:StartPushingThread()
    local pos, pos_prev

    self.pushing_thread = SDK.Thread.Start(
        _PUSHING_THREAD_ID,
        function()
            if not self.leader or not self.leader.entity:IsValid() then
                self:DebugError("Leader doesn't exist anymore")
                self:StopPushing()
                return
            end

            pos = self.leader:GetPosition()

            if SDK.Player.IsIdle(self.inst) or (not pos_prev or pos_prev ~= pos) then
                pos_prev = pos
                WalkToPoint(self, pos)
            end

            Sleep(FRAMES)
        end,
        function()
            return self.inst and self.inst:IsValid() and self.leader and self:IsPushing()
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
    if self.config.push_lag_compensation and not SDK.World.IsMasterSim() then
        if self.movement_prediction_state == nil then
            self.movement_prediction_state = SDK.Player.HasMovementPrediction(self.inst)
        end

        if self.movement_prediction_state then
            SDK.Player.SetMovementPrediction(false)
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
    if self.config.push_lag_compensation and not SDK.World.IsMasterSim() then
        SDK.Player.SetMovementPrediction(self.movement_prediction_state)
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

return KeepFollowing

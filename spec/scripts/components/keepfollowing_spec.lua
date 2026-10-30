require "busted.runner"()

describe("KeepFollowing", function()
    -- setup
    local match
    local _os

    -- before_each initialization
    local inst, leader
    local KeepFollowing, keepfollowing

    setup(function()
        -- match
        match = require "luassert.match"

        -- debug
        DebugSpyTerm()
        DebugSpyInit(spy)

        -- globals
        _os = _G.os

        _G.ACTIONS = {
            BLINK = { code = 14 },
            LOOKAT = { code = 78 },
            WALKTO = { code = 163 },
        }
        _G.COLLISION = {
            FLYERS = 2048,
            SANITY = 4096,
        }
        _G.RPC = {
            LeftClick = {},
        }
        _G.MOD_KEEP_FOLLOWING_TEST = true
    end)

    teardown(function()
        -- debug
        DebugSpyTerm()

        -- globals
        _G.ACTIONS = nil
        _G.AllPlayers = nil
        _G.COLLISION = nil
        _G.KillThreadsWithID = nil
        _G.os = _os
        _G.scheduler = nil
        _G.SendRPCToServer = nil
        _G.MOD_KEEP_FOLLOWING_TEST = false
        _G.TheWorld = nil
    end)

    before_each(function()
        -- globals
        _G.AllPlayers = mock({
            {
                GUID = 100000,
                entity = { IsVisible = ReturnValueFn(false) },
                GetDisplayName = ReturnValueFn("Willow"),
                GetDistanceSqToPoint = ReturnValueFn(27),
                HasTag = ReturnValueFn(false),
            },
            {
                GUID = 100001,
                entity = { IsVisible = ReturnValueFn(false) },
                GetDisplayName = ReturnValueFn("Wilson"),
                GetDistanceSqToPoint = ReturnValueFn(9),
                HasTag = function(_, tag)
                    return tag == "sleeping"
                end,
            },
            {
                GUID = 100002,
                entity = { IsVisible = ReturnValueFn(true) },
                GetDisplayName = ReturnValueFn("Wendy"),
                GetDistanceSqToPoint = ReturnValueFn(9),
                HasTag = ReturnValueFn(false),
            },
        })
        _G.KillThreadsWithID = spy.new(Empty)
        _G.os = mock({
            clock = ReturnValueFn(2),
        })
        _G.scheduler = mock({
            GetCurrentTask = ReturnValueFn(nil),
        })
        _G.SendRPCToServer = spy.new(Empty)
        _G.TheWorld = mock({
            Map = {
                GetPlatformAtPoint = ReturnValueFn({}),
            },
        })

        -- initialization
        inst = mock({
            components = {
                locomotor = {
                    Stop = Empty,
                },
            },
            EnableMovementPrediction = ReturnValueFn(Empty),
            GetDisplayName = ReturnValueFn("Wendy"),
            GetDistanceSqToPoint = ReturnValueFn(9),
            GetPosition = ReturnValueFn({
                Get = ReturnValuesFn(1, 0, -1),
            }),
            HasTag = spy.new(ReturnValueFn(false)),
            Physics = {
                GetMass = ReturnValueFn(1),
            },
            StartUpdatingComponent = Empty,
            Transform = {
                GetWorldPosition = ReturnValuesFn(1, 0, -1),
            },
        })

        leader = mock({
            GetDisplayName = ReturnValueFn("Wilson"),
            GetPosition = ReturnValueFn({
                Get = ReturnValuesFn(1, 0, -1),
            }),
        })

        KeepFollowing = require "components/keepfollowing"
        keepfollowing = KeepFollowing(inst)

        -- debug
        DebugSpyClear()
    end)

    insulate("initialization", function()
        before_each(function()
            -- initialization
            inst = {
                StartUpdatingComponent = spy.new(Empty),
            }

            KeepFollowing = require "components/keepfollowing"
            keepfollowing = KeepFollowing(inst)
        end)

        local function AssertDefaults(self)
            -- general
            assert.is_equal(_G.TheWorld, self.world)
            assert.is_equal(_G.TheWorld.ismastersim, self.is_master_sim)
            assert.is_equal(inst, self.inst)
            assert.is_false(self.is_client)
            assert.is_false(self.is_dst)
            assert.is_nil(self.leader)
            assert.is_nil(self.movement_prediction_state)
            assert.is_nil(self.start_time)

            -- following
            assert.is_nil(self.following_path_thread)
            assert.is_nil(self.following_thread)
            assert.is_false(self.is_following)
            assert.is_false(self.is_leader_near)
            assert.is_same({}, self.leader_positions)

            -- pushing
            assert.is_false(self.is_pushing)
            assert.is_nil(self.pushing_thread)

            -- debugging
            assert.is_equal(0, self.debug_rpc_counter)

            -- config
            assert.is_table(self.config)
            assert.is_equal(2.5, self.config.follow_distance)
            assert.is_false(self.config.follow_distance_keeping)
            assert.is_equal("default", self.config.follow_method)
            assert.is_true(self.config.push_lag_compensation)
            assert.is_true(self.config.push_mass_checking)
        end

        describe("using the constructor", function()
            before_each(function()
                keepfollowing = KeepFollowing(inst)
            end)

            it("should have the default fields", function()
                AssertDefaults(keepfollowing)
            end)
        end)

        describe("using DoInit()", function()
            before_each(function()
                KeepFollowing:DoInit(inst)
            end)

            it("should have the default fields", function()
                AssertDefaults(KeepFollowing)
            end)
        end)
    end)

    local function TestIsOnPlatform(fn, world_fn, inst_fn)
        local world, _inst

        before_each(function()
            world = world_fn()
            _inst = inst_fn()
        end)

        describe("when some of the world chain fields are missing", function()
            it("should return nil", function()
                AssertChainNil(function()
                    fn()
                end, world, "Map", "GetPlatformAtPoint")
            end)
        end)

        describe("when some of inst chain fields are missing", function()
            it("should return nil", function()
                AssertChainNil(function()
                    fn()
                end, _inst, "GetPosition", "Get")
            end)
        end)

        describe("when both world and inst are set", function()
            local GetPlatformAtPoint, GetPosition

            before_each(function()
                GetPlatformAtPoint = world.Map.GetPlatformAtPoint
                GetPosition = _inst.GetPosition
            end)

            it("should call self.inst:GetPosition()", function()
                assert.spy(GetPosition).was_called(0)
                fn()
                assert.spy(GetPosition).was_called(1)
                assert.spy(GetPosition).was_called_with(match.is_ref(_inst))
            end)

            it("should call self.world.Map:GetPlatformAtPoint()", function()
                assert.spy(GetPlatformAtPoint).was_called(0)
                fn()
                assert.spy(GetPlatformAtPoint).was_called(1)
                assert.spy(GetPlatformAtPoint).was_called_with(
                    match.is_ref(world.Map),
                    1,
                    0,
                    -1
                )
            end)

            it("should return true", function()
                fn()
            end)
        end)
    end

    describe("helper", function()
        describe("IsOnPlatform", function()
            local world, _inst

            before_each(function()
                world = mock({
                    Map = {
                        GetPlatformAtPoint = ReturnValueFn({}),
                    },
                })

                _inst = mock({
                    GetPosition = ReturnValueFn({
                        Get = ReturnValuesFn(1, 0, -1),
                    }),
                })
            end)

            TestIsOnPlatform(function()
                return keepfollowing._IsOnPlatform(world, _inst)
            end, function()
                return world
            end, function()
                return _inst
            end)
        end)

        describe("IsPassable", function()
            local world, pos

            before_each(function()
                world = {
                    Map = {
                        IsPassableAtPoint = spy.new(ReturnValueFn(true)),
                    },
                }

                pos = {
                    Get = spy.new(ReturnValuesFn(1, 0, -1)),
                }
            end)

            describe("when some passed world fields are missing", function()
                it("should return false", function()
                    AssertChainNil(function()
                        assert.is_false(keepfollowing._IsPassable(world, pos))
                    end, world, "Map", "IsPassableAtPoint")
                end)
            end)

            describe("when some passed pos fields are missing", function()
                it("should return false", function()
                    AssertChainNil(function()
                        assert.is_false(keepfollowing._IsPassable(world, pos))
                    end, pos, "Get")
                end)
            end)

            it("should call pos:Get()", function()
                assert.spy(pos.Get).was_called(0)
                keepfollowing._IsPassable(world, pos)
                assert.spy(pos.Get).was_called(1)
                assert.spy(pos.Get).was_called_with(match.is_ref(pos))
            end)

            it("should call world.Map:IsPassableAtPoint()", function()
                assert.spy(world.Map.IsPassableAtPoint).was_called(0)
                keepfollowing._IsPassable(world, pos)
                assert.spy(world.Map.IsPassableAtPoint).was_called(1)
                assert.spy(world.Map.IsPassableAtPoint).was_called_with(
                    match.is_ref(world.Map),
                    1,
                    0,
                    -1
                )
            end)

            it("should return true", function()
                assert.is_true(keepfollowing._IsPassable(world, pos))
            end)
        end)
    end)

    describe("general", function()
        TestIsOnPlatform(function()
            return keepfollowing:IsOnPlatform()
        end, function()
            return keepfollowing.world
        end, function()
            return keepfollowing.inst
        end)
    end)

    describe("movement prediction", function()
        local function TestMovementPrediction(enable_fn, disable_fn, inst_fn)
            local _inst

            before_each(function()
                _inst = inst_fn()
            end)

            describe("when enabling", function()
                it("should call SendRPCToServer()", function()
                    assert.spy(_G.SendRPCToServer).was_called(0)
                    enable_fn()
                    assert.spy(_G.SendRPCToServer).was_called(1)
                    assert.spy(_G.SendRPCToServer).was_called_with(
                        match.is_ref(_G.RPC.LeftClick),
                        _G.ACTIONS.WALKTO.code,
                        1,
                        -1
                    )
                end)

                it("should call inst:EnableMovementPrediction() with true", function()
                    assert.spy(_inst.EnableMovementPrediction).was_called(0)
                    enable_fn()
                    assert.spy(_inst.EnableMovementPrediction).was_called(1)
                    assert.spy(_inst.EnableMovementPrediction).was_called_with(
                        match.is_ref(_inst),
                        true
                    )
                end)

                it("should return true", function()
                    assert.is_true(enable_fn())
                end)
            end)

            describe("when disabling", function()
                it("shouldn't call SendRPCToServer()", function()
                    assert.spy(_G.SendRPCToServer).was_called(0)
                    disable_fn()
                    assert.spy(_G.SendRPCToServer).was_called(0)
                end)

                it("should call locomotor:Stop()", function()
                    assert.spy(_inst.components.locomotor.Stop).was_called(0)
                    disable_fn()
                    assert.spy(_inst.components.locomotor.Stop).was_called(1)
                    assert.spy(_inst.components.locomotor.Stop).was_called_with(
                        match.is_ref(_inst.components.locomotor)
                    )
                end)

                it("should call inst:EnableMovementPrediction() with false", function()
                    assert.spy(_inst.EnableMovementPrediction).was_called(0)
                    disable_fn()
                    assert.spy(_inst.EnableMovementPrediction).was_called(1)
                    assert.spy(_inst.EnableMovementPrediction).was_called_with(
                        match.is_ref(_inst),
                        false
                    )
                end)

                it("should return false", function()
                    assert.is_false(disable_fn())
                end)
            end)
        end

        describe("local", function()
            local _inst

            before_each(function()
                _inst = mock({
                    components = {
                        locomotor = {
                            Stop = Empty,
                        },
                    },
                    EnableMovementPrediction = ReturnValueFn(Empty),
                    Transform = {
                        GetWorldPosition = ReturnValuesFn(1, 0, -1),
                    },
                })
            end)

            describe("MovementPrediction", function()
                local enable_fn = function()
                    return keepfollowing._MovementPrediction(_inst, true)
                end

                local disable_fn = function()
                    return keepfollowing._MovementPrediction(_inst, false)
                end

                TestMovementPrediction(enable_fn, disable_fn, function()
                    return _inst
                end)
            end)
        end)

        describe("MovementPrediction", function()
            local enable_fn = function()
                return keepfollowing:MovementPrediction(true)
            end

            local disable_fn = function()
                return keepfollowing:MovementPrediction(false)
            end

            TestMovementPrediction(enable_fn, disable_fn, function()
                return keepfollowing.inst
            end)

            describe("when enabling", function()
                it("should debug string", function()
                    DebugSpyClear("DebugString")
                    enable_fn()
                    DebugSpyAssertWasCalled("DebugString", 1, { "Movement prediction:", "enabled" })
                end)
            end)

            describe("when disabling", function()
                it("should debug string", function()
                    DebugSpyClear("DebugString")
                    disable_fn()
                    DebugSpyAssertWasCalled("DebugString", 1, {
                        "Movement prediction:",
                        "disabled"
                    })
                end)
            end)
        end)
    end)

    describe("leader", function()
        local entity

        before_each(function()
            entity = mock({
                entity = {
                    IsValid = ReturnValueFn(true),
                },
                GetDisplayName = ReturnValueFn("Wilson"),
                GetPosition = ReturnValuesFn(1, 0, -1),
                Physics = {
                    GetCollisionGroup = ReturnValueFn(0),
                    GetMass = ReturnValueFn(1),
                },
                HasTag = ReturnValueFn(false),
            })
        end)

        describe("should have the getter", function()
            describe("getter", function()
                it("GetLeader", function()
                    AssertGetter(keepfollowing, "leader", "GetLeader")
                end)
            end)
        end)

        describe("IsLeaderOnPlatform", function()
            describe("when some self.world chain fields are missing", function()
                it("should return nil", function()
                    AssertChainNil(function()
                        assert.is_nil(keepfollowing:IsLeaderOnPlatform())
                    end, keepfollowing, "world", "Map", "GetPlatformAtPoint")
                end)
            end)

            describe("when some self.leader chain fields are missing", function()
                it("should return nil", function()
                    AssertChainNil(function()
                        assert.is_nil(keepfollowing:IsLeaderOnPlatform())
                    end, keepfollowing, "leader", "GetPosition", "Get")
                end)
            end)

            describe("when both self.world and self.leader are set", function()
                local GetPlatformAtPoint, GetPosition

                before_each(function()
                    GetPlatformAtPoint = keepfollowing.world.Map.GetPlatformAtPoint
                    keepfollowing.leader = leader
                    GetPosition = keepfollowing.leader.GetPosition
                end)

                it("should call self.leader:GetPosition()", function()
                    assert.spy(GetPosition).was_called(0)
                    keepfollowing:IsLeaderOnPlatform()
                    assert.spy(GetPosition).was_called(1)
                    assert.spy(GetPosition).was_called_with(match.is_ref(keepfollowing.leader))
                end)

                it("should call self.world.Map:GetPlatformAtPoint()", function()
                    assert.spy(GetPlatformAtPoint).was_called(0)
                    keepfollowing:IsLeaderOnPlatform()
                    assert.spy(GetPlatformAtPoint).was_called(1)
                    assert.spy(GetPlatformAtPoint).was_called_with(
                        match.is_ref(keepfollowing.world.Map),
                        1,
                        0,
                        -1
                    )
                end)

                it("should return true", function()
                    assert.is_true(keepfollowing:IsLeaderOnPlatform())
                end)
            end)
        end)

        describe("CanBeFollowed", function()
            local function TestHasValidTag(tag, result)
                describe('and has a "' .. tag .. '" tag', function()
                    before_each(function()
                        entity.HasTag = spy.new(function(_, entity_tag)
                            return entity_tag == tag
                        end)
                    end)

                    if result then
                        it("should return true", function()
                            assert.is_true(keepfollowing:CanBeFollowed(entity))
                        end)
                    else
                        it("should return false", function()
                            assert.is_false(keepfollowing:CanBeFollowed(entity))
                        end)
                    end
                end)
            end

            describe("when some chain fields are missing", function()
                it("should return false", function()
                    AssertChainNil(function()
                        assert.is_false(keepfollowing:CanBeFollowed(entity))
                    end, entity, "entity", "IsValid")
                end)
            end)

            describe("when an entity.entity:IsValid() is false", function()
                before_each(function()
                    entity.entity.IsValid = spy.new(ReturnValueFn(false))
                end)

                TestHasValidTag("locomotor", false)
                TestHasValidTag("balloon", false)

                describe("and doesn't have a corresponding tag", function()
                    before_each(function()
                        entity.entity.IsValid = spy.new(ReturnValueFn(false))
                    end)

                    it("should return false", function()
                        assert.is_false(keepfollowing:CanBeFollowed(entity))
                    end)
                end)
            end)

            describe("when entity.entity:IsValid() is true", function()
                before_each(function()
                    entity.entity.IsValid = spy.new(ReturnValueFn(true))
                end)

                TestHasValidTag("locomotor", true)
                TestHasValidTag("balloon", true)

                describe("and doesn't have a corresponding tag", function()
                    before_each(function()
                        entity.entity.IsValid = spy.new(ReturnValueFn(false))
                    end)

                    it("should return false", function()
                        assert.is_false(keepfollowing:CanBeFollowed(entity))
                    end)
                end)
            end)
        end)

        describe("CanBePushed", function()
            local function TestCollisionGroup(name, group, called)
                called = called ~= nil and called or 1

                describe("and the passed entity has a " .. name .. " collision group", function()
                    before_each(function()
                        entity.Physics.GetCollisionGroup = spy.new(
                            ReturnValueFn(group)
                        )
                    end)

                    it("should call entity.Physics:GetCollisionGroup()", function()
                        assert.spy(entity.Physics.GetCollisionGroup).was_called(0)
                        keepfollowing:CanBePushed(entity)
                        assert.spy(entity.Physics.GetCollisionGroup).was_called(called)
                        assert.spy(entity.Physics.GetCollisionGroup).was_called_with(
                            match.is_ref(entity.Physics)
                        )
                    end)

                    it("should return false", function()
                        assert.is_false(keepfollowing:CanBePushed(entity))
                    end)
                end)
            end

            describe("when there is no passed entity", function()
                it("should return false", function()
                    assert.is_false(keepfollowing:CanBePushed())
                end)
            end)

            describe("when entity.Physics is not set", function()
                before_each(function()
                    entity.Physics = nil
                end)

                it("should return false", function()
                    assert.is_false(keepfollowing:CanBePushed(entity))
                end)
            end)

            describe("when self.inst is not set", function()
                before_each(function()
                    keepfollowing.inst = nil
                end)

                it("should return false", function()
                    assert.is_false(keepfollowing:CanBePushed(entity))
                end)
            end)

            describe('when self.inst has a "playerghost" tag', function()
                before_each(function()
                    keepfollowing.inst.HasTag = spy.new(function(_, tag)
                        return tag == "playerghost"
                    end)
                end)

                it("should call self.inst:HasTag()", function()
                    assert.spy(keepfollowing.inst.HasTag).was_called(0)
                    keepfollowing:CanBePushed(entity)
                    assert.spy(keepfollowing.inst.HasTag).was_called(1)
                    assert.spy(keepfollowing.inst.HasTag).was_called_with(
                        match.is_ref(keepfollowing.inst),
                        "playerghost"
                    )
                end)

                describe('and the passed entity has a "player" tag', function()
                    before_each(function()
                        entity.HasTag = spy.new(function(_, tag)
                            return tag == "player"
                        end)
                    end)

                    it("should call entity:HasTag()", function()
                        assert.spy(entity.HasTag).was_called(0)
                        keepfollowing:CanBePushed(entity)
                        assert.spy(entity.HasTag).was_called(1)
                        assert.spy(entity.HasTag).was_called_with(match.is_ref(entity), "player")
                    end)

                    it("should return true", function()
                        assert.is_true(keepfollowing:CanBePushed(entity))
                    end)
                end)

                TestCollisionGroup("FLYERS", _G.COLLISION.FLYERS)
                TestCollisionGroup("SANITY", _G.COLLISION.SANITY)
            end)

            describe('when the passed entity has a "bird" tag', function()
                before_each(function()
                    entity.HasTag = spy.new(function(_, tag)
                        return tag == "bird"
                    end)
                end)

                it("should call entity:HasTag()", function()
                    assert.spy(entity.HasTag).was_called(0)
                    keepfollowing:CanBePushed(entity)
                    assert.spy(entity.HasTag).was_called(1)
                    assert.spy(entity.HasTag).was_called_with(match.is_ref(entity), "bird")
                end)

                it("should return false", function()
                    assert.is_false(keepfollowing:CanBePushed(entity))
                end)
            end)

            describe('when the mass difference is <= 925', function()
                before_each(function()
                    entity.Physics.GetMass = spy.new(ReturnValueFn(1000))
                    keepfollowing.inst.Physics.GetMass = spy.new(ReturnValueFn(75))
                end)

                it("should return true", function()
                    assert.is_true(keepfollowing:CanBePushed(entity))
                end)
            end)

            describe('when the mass difference is > 925', function()
                before_each(function()
                    entity.Physics.GetMass = spy.new(ReturnValueFn(9999))
                    keepfollowing.inst.Physics.GetMass = spy.new(ReturnValueFn(75))
                end)

                it("should return false", function()
                    assert.is_false(keepfollowing:CanBePushed(entity))
                end)
            end)

            describe('when self.inst mass is 1 (player is a ghost)', function()
                before_each(function()
                    keepfollowing.inst.Physics.GetMass = spy.new(ReturnValueFn(1))
                end)

                describe('and the mass difference is <= 10', function()
                    before_each(function()
                        entity.Physics.GetMass = spy.new(ReturnValueFn(10))
                    end)

                    it("should return true", function()
                        assert.is_true(keepfollowing:CanBePushed(entity))
                    end)
                end)

                describe('and the mass difference is > 10', function()
                    before_each(function()
                        entity.Physics.GetMass = spy.new(ReturnValueFn(75))
                    end)

                    it("should return false", function()
                        assert.is_false(keepfollowing:CanBePushed(entity))
                    end)
                end)
            end)
        end)

        describe("CanBeLeader", function()
            local function TestEntityAndInstAreSame()
                describe('and self.inst is the same as the passed entity', function()
                    before_each(function()
                        keepfollowing.inst = entity
                    end)

                    it("shouldn't call self:CanBeFollowed()", function()
                        assert.spy(keepfollowing.CanBeFollowed).was_called(0)
                        keepfollowing:CanBeLeader(entity)
                        assert.spy(keepfollowing.CanBeFollowed).was_called(0)
                    end)

                    it("should return false", function()
                        assert.is_false(keepfollowing:CanBeLeader(entity))
                    end)
                end)
            end

            local function TestCanBeFollowedIsCalled()
                it("should call self:CanBeFollowed()", function()
                    assert.spy(keepfollowing.CanBeFollowed).was_called(0)
                    keepfollowing:CanBeLeader(entity)
                    assert.spy(keepfollowing.CanBeFollowed).was_called(1)
                    assert.spy(keepfollowing.CanBeFollowed).was_called_with(
                        match.is_ref(keepfollowing),
                        match.is_ref(entity)
                    )
                end)
            end

            describe('when self:CanBeFollowed() returns true', function()
                before_each(function()
                    keepfollowing.CanBeFollowed = spy.new(ReturnValueFn(true))
                end)

                TestEntityAndInstAreSame()
                TestCanBeFollowedIsCalled()

                it("should return true", function()
                    assert.is_true(keepfollowing:CanBeLeader(entity))
                end)
            end)

            describe('when self:CanBeFollowed() returns false', function()
                before_each(function()
                    keepfollowing.CanBeFollowed = spy.new(ReturnValueFn(false))
                end)

                TestEntityAndInstAreSame()
                TestCanBeFollowedIsCalled()

                it("should return false", function()
                    assert.is_false(keepfollowing:CanBeLeader(entity))
                end)
            end)
        end)

        describe("SetLeader", function()
            local function TestNotValidLeader(fn, msg)
                it("should debug error", function()
                    DebugSpyClear("DebugError")
                    fn()
                    DebugSpyAssertWasCalled("DebugError", 1, msg)
                end)

                it("shouldn't set self.leader", function()
                    assert.is_nil(keepfollowing.leader)
                    fn()
                    assert.is_nil(keepfollowing.leader)
                end)

                it("should return false", function()
                    assert.is_false(fn())
                end)
            end

            before_each(function()
                keepfollowing.inst.GetDistanceSqToPoint = ReturnValueFn(9)
            end)

            describe("when an entity can become a leader", function()
                before_each(function()
                    keepfollowing.CanBeLeader = spy.new(ReturnValueFn(true))
                end)

                it("should debug string", function()
                    DebugSpyClear("DebugString")
                    keepfollowing:SetLeader(entity)
                    DebugSpyAssertWasCalled("DebugString", 1, "New leader: Wilson. Distance: 3.00")
                end)

                it("should set self.leader", function()
                    assert.is_nil(keepfollowing.leader)
                    keepfollowing:SetLeader(entity)
                    assert.is_equal(entity, keepfollowing.leader)
                end)

                it("should return true", function()
                    assert.is_true(keepfollowing:SetLeader(entity))
                end)
            end)

            describe("when the player sets himself/herself", function()
                TestNotValidLeader(function()
                    return keepfollowing:SetLeader(keepfollowing.inst)
                end, { "You", "can't become a leader" })
            end)

            describe("when an entity can't become a leader", function()
                before_each(function()
                    keepfollowing.CanBeLeader = spy.new(ReturnValueFn(false))
                end)

                describe("and has a GetDisplayName()", function()
                    before_each(function()
                        entity.GetDisplayName = ReturnValueFn("Wilson")
                    end)

                    TestNotValidLeader(function()
                        return keepfollowing:SetLeader(entity)
                    end, { "Wilson", "can't become a leader" })
                end)

                describe("and doesn't have a GetDisplayName()", function()
                    before_each(function()
                        entity.GetDisplayName = nil
                    end)

                    TestNotValidLeader(function()
                        return keepfollowing:SetLeader(entity)
                    end, { "Entity", "can't become a leader" })
                end)
            end)
        end)
    end)

    describe("tent", function()
        describe("local", function()
            describe("FindClosestInvisiblePlayerInRange", function()
                describe("when there is an invisible player in the range", function()
                    it("should return the player and the squared range", function()
                        local closest, range_sq = keepfollowing
                            ._FindClosestInvisiblePlayerInRange(1, 0, -1, 27)
                        assert.is_equal(100001, closest.GUID)
                        assert.is_equal(9, range_sq)
                        assert.is_false(closest.entity:IsVisible())
                    end)
                end)

                describe("when there is no invisible player in the range", function()
                    it("should return nil values", function()
                        local closest, range_sq = keepfollowing
                            ._FindClosestInvisiblePlayerInRange(1, 0, -1, 3)
                        assert.is_nil(closest)
                        assert.is_nil(range_sq)
                    end)
                end)
            end)
        end)

        describe("GetTentSleeper", function()
            local entity

            before_each(function()
                entity = {
                    components = {
                        sleepingbag = {
                            sleeper = _G.AllPlayers[2],
                        },
                    },
                    GetDisplayName = spy.new(ReturnValueFn("Tent")),
                    HasTag = spy.new(function(_, tag)
                        return tag == "tent" or tag == "hassleeper"
                    end),
                    Transform = {
                        GetWorldPosition = ReturnValuesFn(1, 0, -1),
                    },
                }
            end)

            describe('when the "sleepingbag" component is available', function()
                before_each(function()
                    entity.components.sleepingbag.sleeper = _G.AllPlayers[2]
                end)

                describe("and some chain fields are missing", function()
                    it("should return nil", function()
                        AssertChainNil(function()
                            keepfollowing:GetTentSleeper(entity)
                        end, entity, "components", "sleepingbag", "sleeper")
                    end)
                end)

                it("should debug strings", function()
                    DebugSpyClear("DebugString")
                    keepfollowing:GetTentSleeper(entity)
                    DebugSpyAssertWasCalled("DebugString", 2, "Component sleepingbag is available")
                    DebugSpyAssertWasCalled("DebugString", 2, { "Found sleeper:", "Wilson" })
                end)

                it("should return sleeper", function()
                    assert.is_equal(_G.AllPlayers[2], keepfollowing:GetTentSleeper(entity))
                end)
            end)

            describe('when the "sleepingbag" component is not available', function()
                before_each(function()
                    entity.components.sleepingbag = nil
                end)

                describe('and the passed entity has no "tent" and "hassleeper" tags', function()
                    before_each(function()
                        entity.HasTag = spy.new(ReturnValueFn(false))
                    end)

                    it("should debug string", function()
                        DebugSpyClear("DebugString")
                        keepfollowing:GetTentSleeper(entity)
                        DebugSpyAssertWasCalled(
                            "DebugString",
                            1,
                            "Component sleepingbag is not available")
                    end)

                    it("should return nil", function()
                        assert.is_nil(keepfollowing:GetTentSleeper(entity))
                    end)
                end)

                describe('and the passed entity has "tent" and "hassleeper" tags', function()
                    it("should debug strings", function()
                        DebugSpyClear("DebugString")
                        keepfollowing:GetTentSleeper(entity)
                        DebugSpyAssertWasCalled(
                            "DebugString",
                            3,
                            "Component sleepingbag is not available"
                        )
                        DebugSpyAssertWasCalled("DebugString", 3, "Looking for sleepers...")
                        DebugSpyAssertWasCalled("DebugString", 3, { "Found sleeper:", "Wilson" })
                    end)

                    it("should return sleeper", function()
                        assert.is_equal(_G.AllPlayers[2], keepfollowing:GetTentSleeper(entity))
                    end)
                end)
            end)
        end)
    end)

    describe("following", function()
        describe("StartFollowing", function()
            before_each(function()
                keepfollowing.config = {}
                keepfollowing.MovementPrediction = spy.new(Empty)
                keepfollowing.StartFollowingThread = spy.new(Empty)
            end)

            local function TestNoPushLagCompensation(state)
                it("shouldn't set a new self.movement_prediction_state value", function()
                    assert.is_equal(state, keepfollowing.movement_prediction_state)
                end)

                it("shouldn't call self:StartFollowing()", function()
                    assert.spy(keepfollowing.MovementPrediction).was_called(0)
                    keepfollowing:StartFollowing(leader)
                    assert.spy(keepfollowing.MovementPrediction).was_called(0)
                end)
            end

            describe("when push lag compensation is enabled", function()
                before_each(function()
                    keepfollowing.config.push_lag_compensation = true
                end)

                describe("and is a master simulation", function()
                    before_each(function()
                        keepfollowing.is_master_sim = true
                    end)

                    describe("when the previous movement prediction state is true", function()
                        before_each(function()
                            keepfollowing.movement_prediction_state = true
                        end)

                        TestNoPushLagCompensation(true)

                        it("should return false", function()
                            assert.is_false(keepfollowing:StartFollowing(leader))
                        end)
                    end)

                    describe("when the previous movement prediction state is false", function()
                        before_each(function()
                            keepfollowing.movement_prediction_state = false
                        end)

                        TestNoPushLagCompensation(false)

                        it("should return false", function()
                            assert.is_false(keepfollowing:StartFollowing(leader))
                        end)
                    end)
                end)

                describe("and is a not master simulation", function()
                    before_each(function()
                        keepfollowing.is_master_sim = false
                    end)

                    describe("when the previous movement prediction state is true", function()
                        before_each(function()
                            keepfollowing.movement_prediction_state = true
                        end)

                        it("should unset self.movement_prediction_state", function()
                            assert.is_true(keepfollowing.movement_prediction_state)
                            keepfollowing:StartFollowing(leader)
                            assert.is_nil(keepfollowing.movement_prediction_state)
                        end)

                        it("should call self:MovementPrediction()", function()
                            assert.spy(keepfollowing.MovementPrediction).was_called(0)
                            keepfollowing:StartFollowing(leader)
                            assert.spy(keepfollowing.MovementPrediction).was_called(1)
                            assert.spy(keepfollowing.MovementPrediction).was_called_with(
                                match.is_ref(keepfollowing),
                                true
                            )
                        end)

                        it("should return false", function()
                            assert.is_false(keepfollowing:StartFollowing(leader))
                        end)
                    end)

                    describe("when the previous movement prediction state is false", function()
                        before_each(function()
                            keepfollowing.movement_prediction_state = false
                        end)

                        it("should unset self.movement_prediction_state", function()
                            assert.is_false(keepfollowing.movement_prediction_state)
                            keepfollowing:StartFollowing(leader)
                            assert.is_nil(keepfollowing.movement_prediction_state)
                        end)

                        it("should call self:MovementPrediction()", function()
                            assert.spy(keepfollowing.MovementPrediction).was_called(0)
                            keepfollowing:StartFollowing(leader)
                            assert.spy(keepfollowing.MovementPrediction).was_called(1)
                            assert.spy(keepfollowing.MovementPrediction).was_called_with(
                                match.is_ref(keepfollowing),
                                false
                            )
                        end)

                        it("should return false", function()
                            assert.is_false(keepfollowing:StartFollowing(leader))
                        end)
                    end)
                end)
            end)

            describe("when push lag compensation is disabled", function()
                before_each(function()
                    keepfollowing.config.push_lag_compensation = false
                end)

                describe("and is a master simulation", function()
                    before_each(function()
                        keepfollowing.is_master_sim = true
                    end)

                    describe("when the previous movement prediction state is true", function()
                        before_each(function()
                            keepfollowing.movement_prediction_state = true
                            keepfollowing.MovementPrediction = spy.new(Empty)
                        end)

                        TestNoPushLagCompensation(true)

                        it("should return false", function()
                            assert.is_false(keepfollowing:StartFollowing(leader))
                        end)
                    end)

                    describe("when the previous movement prediction state is false", function()
                        before_each(function()
                            keepfollowing.movement_prediction_state = false
                            keepfollowing.MovementPrediction = spy.new(Empty)
                        end)

                        TestNoPushLagCompensation(false)

                        it("should return false", function()
                            assert.is_false(keepfollowing:StartFollowing(leader))
                        end)
                    end)
                end)

                describe("and is a not master simulation", function()
                    before_each(function()
                        keepfollowing.is_master_sim = false
                    end)

                    describe("when the previous movement prediction state is true", function()
                        before_each(function()
                            keepfollowing.movement_prediction_state = true
                            keepfollowing.MovementPrediction = spy.new(Empty)
                        end)

                        TestNoPushLagCompensation(true)

                        it("should return false", function()
                            assert.is_false(keepfollowing:StartFollowing(leader))
                        end)
                    end)

                    describe("when the previous movement prediction state is false", function()
                        before_each(function()
                            keepfollowing.movement_prediction_state = false
                            keepfollowing.MovementPrediction = spy.new(Empty)
                        end)

                        TestNoPushLagCompensation(false)

                        it("should return false", function()
                            assert.is_false(keepfollowing:StartFollowing(leader))
                        end)
                    end)
                end)
            end)

            describe("when a valid leader", function()
                before_each(function()
                    keepfollowing.CanBeLeader = spy.new(ReturnValueFn(true))
                end)

                it("should debug strings", function()
                    DebugSpyClear("DebugString")
                    keepfollowing:StartFollowing(leader)
                    DebugSpyAssertWasCalled("DebugString", 2, "New leader: Wilson. Distance: 3.00")
                    DebugSpyAssertWasCalled("DebugString", 2, "Started following...")
                end)

                it("should call self:StartFollowingThread()", function()
                    assert.spy(keepfollowing.StartFollowingThread).was_called(0)
                    keepfollowing:StartFollowing(leader)
                    assert.spy(keepfollowing.StartFollowingThread).was_called(1)
                    assert.spy(keepfollowing.StartFollowingThread).was_called_with(
                        match.is_ref(keepfollowing)
                    )
                end)

                it("should return true", function()
                    assert.is_true(keepfollowing:StartFollowing(leader))
                end)
            end)

            describe("when a not valid leader", function()
                before_each(function()
                    keepfollowing.CanBeLeader = spy.new(ReturnValueFn(false))
                end)

                it("should debug error", function()
                    DebugSpyClear("DebugError")
                    keepfollowing:StartFollowing(leader)
                    DebugSpyAssertWasCalled("DebugError", 1, { "Wilson", "can't become a leader" })
                end)

                it("shouldn't call self:StartFollowingThread()", function()
                    assert.spy(keepfollowing.StartFollowingThread).was_called(0)
                    keepfollowing:StartFollowing(leader)
                    assert.spy(keepfollowing.StartFollowingThread).was_called(0)
                end)

                it("should return false", function()
                    assert.is_false(keepfollowing:StartFollowing(leader))
                end)
            end)
        end)

        describe("StopFollowing", function()
            before_each(function()
                -- threads
                keepfollowing.following_path_thread = {
                    id = "following_path_thread",
                    SetList = spy.new(Empty),
                }

                keepfollowing.following_thread = {
                    id = "following_thread",
                    SetList = spy.new(Empty),
                }

                -- fields (general)
                keepfollowing.leader = leader
                keepfollowing.start_time = 1

                -- fields (following)
                keepfollowing.is_following = true
                keepfollowing.is_leader_near = false
                keepfollowing.leader_positions = { {} }

                -- fields (debugging)
                keepfollowing.debug_rpc_counter = 1
            end)

            local function TestError(error)
                it("should debug error", function()
                    DebugSpyClear("DebugError")
                    keepfollowing:StopFollowing()
                    DebugSpyAssertWasCalled("DebugError", 1, error)
                end)

                it("should return false", function()
                    assert.is_false(keepfollowing:StopFollowing())
                end)
            end

            describe("when not following", function()
                before_each(function()
                    keepfollowing.is_following = false
                end)

                TestError("Not following")
            end)

            describe("when no leader", function()
                before_each(function()
                    keepfollowing.leader = nil
                end)

                TestError("No leader")
            end)

            describe("when no thread", function()
                before_each(function()
                    keepfollowing.following_thread = nil
                end)

                TestError("No active thread")
            end)

            it("should debug string", function()
                DebugSpyClear("DebugString")
                keepfollowing:StopFollowing()
                DebugSpyAssertWasCalled(
                    "DebugString",
                    1,
                    "Stopped following Wilson. RPCs: 1. Time: 1.0000"
                )
            end)

            it("should return true", function()
                assert.is_true(keepfollowing:StopFollowing())
            end)
        end)
    end)

    describe("pushing", function()
        describe("StartFollowing", function()
            before_each(function()
                keepfollowing.config = {}
                keepfollowing.MovementPrediction = spy.new(Empty)
                keepfollowing.StartPushingThread = spy.new(Empty)
            end)

            local function TestNoPushLagCompensation(state)
                it("shouldn't set a new self.movement_prediction_state value", function()
                    assert.is_equal(state, keepfollowing.movement_prediction_state)
                end)

                it("shouldn't call self:StartPushing()", function()
                    assert.spy(keepfollowing.MovementPrediction).was_called(0)
                    keepfollowing:StartPushing(leader)
                    assert.spy(keepfollowing.MovementPrediction).was_called(0)
                end)
            end

            describe("when push lag compensation is enabled", function()
                before_each(function()
                    keepfollowing.config.push_lag_compensation = true
                end)

                describe("and is a master simulation", function()
                    before_each(function()
                        keepfollowing.is_master_sim = true
                    end)

                    describe("when the previous movement prediction state is true", function()
                        before_each(function()
                            keepfollowing.movement_prediction_state = true
                        end)

                        TestNoPushLagCompensation(true)

                        it("should return false", function()
                            assert.is_false(keepfollowing:StartPushing(leader))
                        end)
                    end)

                    describe("when the previous movement prediction state is false", function()
                        before_each(function()
                            keepfollowing.movement_prediction_state = false
                        end)

                        TestNoPushLagCompensation(false)

                        it("should return false", function()
                            assert.is_false(keepfollowing:StartPushing(leader))
                        end)
                    end)
                end)

                describe("and is a not master simulation", function()
                    before_each(function()
                        keepfollowing.is_master_sim = false
                    end)

                    describe("when the previous movement prediction state is true", function()
                        before_each(function()
                            keepfollowing.movement_prediction_state = true
                        end)

                        it("should set self.movement_prediction_state", function()
                            assert.is_true(keepfollowing.movement_prediction_state)
                            keepfollowing:StartPushing(leader)
                            assert.is_true(keepfollowing.movement_prediction_state)
                        end)

                        it("should call self:MovementPrediction()", function()
                            assert.spy(keepfollowing.MovementPrediction).was_called(0)
                            keepfollowing:StartPushing(leader)
                            assert.spy(keepfollowing.MovementPrediction).was_called(1)
                            assert.spy(keepfollowing.MovementPrediction).was_called_with(
                                match.is_ref(keepfollowing),
                                false
                            )
                        end)

                        it("should return false", function()
                            assert.is_false(keepfollowing:StartPushing(leader))
                        end)
                    end)

                    describe("when the previous movement prediction state is false", function()
                        before_each(function()
                            keepfollowing.movement_prediction_state = false
                        end)

                        it("should set self.movement_prediction_state", function()
                            assert.is_false(keepfollowing.movement_prediction_state)
                            keepfollowing:StartPushing(leader)
                            assert.is_false(keepfollowing.movement_prediction_state)
                        end)

                        it("shouldn't call self:MovementPrediction()", function()
                            assert.spy(keepfollowing.MovementPrediction).was_called(0)
                            keepfollowing:StartPushing(leader)
                            assert.spy(keepfollowing.MovementPrediction).was_called(0)
                        end)

                        it("should return false", function()
                            assert.is_false(keepfollowing:StartPushing(leader))
                        end)
                    end)
                end)
            end)

            describe("when push lag compensation is disabled", function()
                before_each(function()
                    keepfollowing.config.push_lag_compensation = false
                end)

                describe("and is a master simulation", function()
                    before_each(function()
                        keepfollowing.is_master_sim = true
                    end)

                    describe("when the previous movement prediction state is true", function()
                        before_each(function()
                            keepfollowing.movement_prediction_state = true
                            keepfollowing.MovementPrediction = spy.new(Empty)
                        end)

                        it("shouldn't call self:MovementPrediction()", function()
                            assert.spy(keepfollowing.MovementPrediction).was_called(0)
                            keepfollowing:StartPushing(leader)
                            assert.spy(keepfollowing.MovementPrediction).was_called(0)
                        end)

                        it("should return false", function()
                            assert.is_false(keepfollowing:StartPushing(leader))
                        end)
                    end)

                    describe("when the previous movement prediction state is false", function()
                        before_each(function()
                            keepfollowing.movement_prediction_state = false
                            keepfollowing.MovementPrediction = spy.new(Empty)
                        end)

                        it("shouldn't call self:MovementPrediction()", function()
                            assert.spy(keepfollowing.MovementPrediction).was_called(0)
                            keepfollowing:StartPushing(leader)
                            assert.spy(keepfollowing.MovementPrediction).was_called(0)
                        end)

                        it("should return false", function()
                            assert.is_false(keepfollowing:StartPushing(leader))
                        end)
                    end)
                end)

                describe("and is a not master simulation", function()
                    before_each(function()
                        keepfollowing.is_master_sim = false
                    end)

                    describe("when the previous movement prediction state is true", function()
                        before_each(function()
                            keepfollowing.movement_prediction_state = true
                            keepfollowing.MovementPrediction = spy.new(Empty)
                        end)

                        it("shouldn't call self:MovementPrediction()", function()
                            assert.spy(keepfollowing.MovementPrediction).was_called(0)
                            keepfollowing:StartPushing(leader)
                            assert.spy(keepfollowing.MovementPrediction).was_called(0)
                        end)

                        it("should return false", function()
                            assert.is_false(keepfollowing:StartPushing(leader))
                        end)
                    end)

                    describe("when the previous movement prediction state is false", function()
                        before_each(function()
                            keepfollowing.movement_prediction_state = false
                            keepfollowing.MovementPrediction = spy.new(Empty)
                        end)

                        it("shouldn't call self:MovementPrediction()", function()
                            assert.spy(keepfollowing.MovementPrediction).was_called(0)
                            keepfollowing:StartPushing(leader)
                            assert.spy(keepfollowing.MovementPrediction).was_called(0)
                        end)

                        it("should return false", function()
                            assert.is_false(keepfollowing:StartPushing(leader))
                        end)
                    end)
                end)
            end)

            describe("when a valid leader", function()
                before_each(function()
                    keepfollowing.CanBeLeader = spy.new(ReturnValueFn(true))
                end)

                it("should debug strings", function()
                    DebugSpyClear("DebugString")
                    keepfollowing:StartPushing(leader)
                    DebugSpyAssertWasCalled("DebugString", 2, "New leader: Wilson. Distance: 3.00")
                    DebugSpyAssertWasCalled("DebugString", 2, "Started pushing...")
                end)

                it("should call self:StartPushingThread()", function()
                    assert.spy(keepfollowing.StartPushingThread).was_called(0)
                    keepfollowing:StartPushing(leader)
                    assert.spy(keepfollowing.StartPushingThread).was_called(1)
                    assert.spy(keepfollowing.StartPushingThread).was_called_with(
                        match.is_ref(keepfollowing)
                    )
                end)

                it("should return true", function()
                    assert.is_true(keepfollowing:StartPushing(leader))
                end)
            end)

            describe("when a not valid leader", function()
                before_each(function()
                    keepfollowing.CanBeLeader = spy.new(ReturnValueFn(false))
                end)

                it("should debug error", function()
                    DebugSpyClear("DebugError")
                    keepfollowing:StartPushing(leader)
                    DebugSpyAssertWasCalled("DebugError", 1, { "Wilson", "can't become a leader" })
                end)

                it("shouldn't call self:StartPushingThread()", function()
                    assert.spy(keepfollowing.StartPushingThread).was_called(0)
                    keepfollowing:StartPushing(leader)
                    assert.spy(keepfollowing.StartPushingThread).was_called(0)
                end)

                it("should return false", function()
                    assert.is_false(keepfollowing:StartPushing(leader))
                end)
            end)
        end)

        describe("StopPushing", function()
            before_each(function()
                -- thread
                keepfollowing.pushing_thread = {
                    id = "pushing_thread",
                    SetList = spy.new(Empty),
                }

                -- fields (general)
                keepfollowing.leader = leader
                keepfollowing.start_time = 1

                -- fields (pushing)
                keepfollowing.is_pushing = true

                -- fields (debugging)
                keepfollowing.debug_rpc_counter = 1
            end)

            local function TestError(error)
                it("should debug error", function()
                    DebugSpyClear("DebugError")
                    keepfollowing:StopPushing()
                    DebugSpyAssertWasCalled("DebugError", 1, error)
                end)

                it("should return false", function()
                    assert.is_false(keepfollowing:StopPushing())
                end)
            end

            describe("when not following", function()
                before_each(function()
                    keepfollowing.is_pushing = false
                end)

                TestError("Not pushing")
            end)

            describe("when no leader", function()
                before_each(function()
                    keepfollowing.leader = nil
                end)

                TestError("No leader")
            end)

            describe("when no thread", function()
                before_each(function()
                    keepfollowing.pushing_thread = nil
                end)

                TestError("No active thread")
            end)

            it("should debug string", function()
                DebugSpyClear("DebugString")
                keepfollowing:StopPushing()
                DebugSpyAssertWasCalled(
                    "DebugString",
                    2,
                    "Stopped pushing Wilson. RPCs: 1. Time: 1.0000"
                )
            end)

            it("should return true", function()
                assert.is_true(keepfollowing:StopPushing())
            end)
        end)
    end)
end)

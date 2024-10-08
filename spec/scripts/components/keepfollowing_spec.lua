require("busted.runner")()

describe("KeepFollowing", function()
    -- setup
    local match
    local _os

    -- before_each initialization
    local inst, leader
    local KeepFollowing, keepfollowing

    setup(function()
        -- match
        match = require("luassert.match")

        -- debug
        DebugSpyInit()

        -- globals
        _G.MOD_KEEP_FOLLOWING_TEST = true

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

        -- os
        _os = _G.os
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
        _G.KillThreadsWithID = spy.new(Empty)
        _G.SendRPCToServer = spy.new(Empty)

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

        _G.os = mock({
            clock = ReturnValueFn(2),
        })

        _G.scheduler = mock({
            GetCurrentTask = ReturnValueFn(nil),
        })

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

        KeepFollowing = require("components/keepfollowing")
        keepfollowing = KeepFollowing(inst)

        DebugSpyClear()
    end)

    insulate("initialization", function()
        before_each(function()
            -- initialization
            inst = {
                StartUpdatingComponent = spy.new(Empty),
            }

            KeepFollowing = require("components/keepfollowing")
            keepfollowing = KeepFollowing(inst)
        end)

        local function AssertDefaults(self)
            -- general
            assert.is_equal(inst, self.inst)
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
                    AssertClassGetter(keepfollowing, "leader", "GetLeader")
                end)
            end)
        end)

        describe("CanBeFollowed", function()
            before_each(function()
                entity.entity.IsValid = spy.new(ReturnValueFn(true))
                entity.HasTag = spy.new(function(_, tag)
                    if tag == "locomotor" then
                        return true
                    end
                    return false
                end)
            end)

            it("should return false if the entity is invalid", function()
                entity.entity.IsValid = spy.new(ReturnValueFn(false))
                assert.is_false(keepfollowing:CanBeFollowed(entity))
                assert.spy(entity.entity.IsValid).was_called(1)
                assert.spy(entity.HasTag).was_called(0)
            end)

            it('should return false if the entity doesn\'t have the "locomotor" tag', function()
                entity.HasTag = spy.new(function(_, tag)
                    if tag == "locomotor" then
                        return false
                    end
                    return true
                end)
                assert.is_false(keepfollowing:CanBeFollowed(entity))
                assert.spy(entity.entity.IsValid).was_called(1)
                assert.spy(entity.HasTag).was_called(1)
            end)

            it('should return false if the entity has the "balloon" tag', function()
                local HasTag = entity.HasTag
                entity.HasTag = spy.new(function(_, tag)
                    if tag == "balloon" then
                        return true
                    end
                    return HasTag(entity, tag)
                end)
                assert.is_false(keepfollowing:CanBeFollowed(entity))
                assert.spy(entity.entity.IsValid).was_called(1)
                assert.spy(entity.HasTag).was_called(2)
            end)

            it('should return true if the "target_entities" configuration is "default"', function()
                keepfollowing.config.target_entities = "default"
                assert.is_true(keepfollowing:CanBeFollowed(entity))
                assert.spy(entity.entity.IsValid).was_called(1)
                assert.spy(entity.HasTag).was_called(2)
            end)

            it(
                'should return true if the "target_entities" configuration is "friendly" and entity is not hostile',
                function()
                    local HasTag = entity.HasTag
                    keepfollowing.config.target_entities = "friendly"
                    entity.HasTag = spy.new(function(_, tag)
                        if tag == "hostile" then
                            return false
                        end
                        return HasTag(entity, tag)
                    end)
                    assert.is_true(keepfollowing:CanBeFollowed(entity))
                    assert.spy(entity.entity.IsValid).was_called(1)
                    assert.spy(entity.HasTag).was_called(3)
                end
            )

            it(
                'should return true if the "target_entities" configuration is "players" and entity is a player',
                function()
                    local HasTag = entity.HasTag
                    keepfollowing.config.target_entities = "players"
                    entity.HasTag = spy.new(function(_, tag)
                        if tag == "player" then
                            return true
                        end
                        return HasTag(entity, tag)
                    end)
                    assert.is_true(keepfollowing:CanBeFollowed(entity))
                    assert.spy(entity.entity.IsValid).was_called(1)
                    assert.spy(entity.HasTag).was_called(3)
                end
            )
        end)

        describe("CanBePushed", function()
            local function TestCollisionGroup(name, group, called)
                called = called ~= nil and called or 1

                describe("and the passed entity has a " .. name .. " collision group", function()
                    before_each(function()
                        entity.Physics.GetCollisionGroup = spy.new(ReturnValueFn(group))
                    end)

                    it("should call entity.Physics:GetCollisionGroup()", function()
                        assert.spy(entity.Physics.GetCollisionGroup).was_called(0)
                        keepfollowing:CanBePushed(entity)
                        assert.spy(entity.Physics.GetCollisionGroup).was_called(called)
                        assert
                            .spy(entity.Physics.GetCollisionGroup)
                            .was_called_with(match.is_ref(entity.Physics))
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
                    assert
                        .spy(keepfollowing.inst.HasTag)
                        .was_called_with(match.is_ref(keepfollowing.inst), "playerghost")
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

            describe("when the mass difference is <= 925", function()
                before_each(function()
                    entity.Physics.GetMass = spy.new(ReturnValueFn(1000))
                    keepfollowing.inst.Physics.GetMass = spy.new(ReturnValueFn(75))
                end)

                it("should return true", function()
                    assert.is_true(keepfollowing:CanBePushed(entity))
                end)
            end)

            describe("when the mass difference is > 925", function()
                before_each(function()
                    entity.Physics.GetMass = spy.new(ReturnValueFn(9999))
                    keepfollowing.inst.Physics.GetMass = spy.new(ReturnValueFn(75))
                end)

                it("should return false", function()
                    assert.is_false(keepfollowing:CanBePushed(entity))
                end)
            end)

            describe("when self.inst mass is 1 (player is a ghost)", function()
                before_each(function()
                    keepfollowing.inst.Physics.GetMass = spy.new(ReturnValueFn(1))
                end)

                describe("and the mass difference is <= 10", function()
                    before_each(function()
                        entity.Physics.GetMass = spy.new(ReturnValueFn(10))
                    end)

                    it("should return true", function()
                        assert.is_true(keepfollowing:CanBePushed(entity))
                    end)
                end)

                describe("and the mass difference is > 10", function()
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
                describe("and self.inst is the same as the passed entity", function()
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
                    assert
                        .spy(keepfollowing.CanBeFollowed)
                        .was_called_with(match.is_ref(keepfollowing), match.is_ref(entity))
                end)
            end

            describe("when self:CanBeFollowed() returns true", function()
                before_each(function()
                    keepfollowing.CanBeFollowed = spy.new(ReturnValueFn(true))
                end)

                TestEntityAndInstAreSame()
                TestCanBeFollowedIsCalled()

                it("should return true", function()
                    assert.is_true(keepfollowing:CanBeLeader(entity))
                end)
            end)

            describe("when self:CanBeFollowed() returns false", function()
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
                    AssertDebugSpyWasCalled("DebugError", 1, msg)
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
                    AssertDebugSpyWasCalled("DebugString", 1, "New leader: Wilson. Distance: 3.00")
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
                end, {
                    "You",
                    "can't become a leader",
                })
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
                    end, {
                        "Wilson",
                        "can't become a leader",
                    })
                end)

                describe("and doesn't have a GetDisplayName()", function()
                    before_each(function()
                        entity.GetDisplayName = nil
                    end)

                    TestNotValidLeader(function()
                        return keepfollowing:SetLeader(entity)
                    end, {
                        "Entity",
                        "can't become a leader",
                    })
                end)
            end)
        end)
    end)

    describe("following", function()
        describe("StartFollowing", function()
            before_each(function()
                _G.SDK.Player.SetMovementPrediction = spy.new(Empty)
                keepfollowing.config = {}
                keepfollowing.StartFollowingThread = spy.new(Empty)
            end)

            local function TestNoPushLagCompensation(state)
                it("shouldn't set a new self.movement_prediction_state value", function()
                    assert.is_equal(state, keepfollowing.movement_prediction_state)
                end)

                it("shouldn't call self:StartFollowing()", function()
                    assert.spy(_G.SDK.Player.SetMovementPrediction).was_called(0)
                    keepfollowing:StartFollowing(leader)
                    assert.spy(_G.SDK.Player.SetMovementPrediction).was_called(0)
                end)
            end

            describe("when push lag compensation is enabled", function()
                before_each(function()
                    keepfollowing.config.push_lag_compensation = true
                end)

                describe("and is a master simulation", function()
                    before_each(function()
                        _G.SDK.World.IsMasterSim = spy.new(ReturnValueFn(true))
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
                        _G.SDK.World.IsMasterSim = spy.new(ReturnValueFn(false))
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
                            assert.spy(_G.SDK.Player.SetMovementPrediction).was_called(0)
                            keepfollowing:StartFollowing(leader)
                            assert.spy(_G.SDK.Player.SetMovementPrediction).was_called(1)
                            assert.spy(_G.SDK.Player.SetMovementPrediction).was_called_with(true)
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
                            assert.spy(_G.SDK.Player.SetMovementPrediction).was_called(0)
                            keepfollowing:StartFollowing(leader)
                            assert.spy(_G.SDK.Player.SetMovementPrediction).was_called(1)
                            assert.spy(_G.SDK.Player.SetMovementPrediction).was_called_with(false)
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
                        _G.SDK.World.IsMasterSim = spy.new(ReturnValueFn(true))
                    end)

                    describe("when the previous movement prediction state is true", function()
                        before_each(function()
                            _G.SDK.Player.SetMovementPrediction = spy.new(Empty)
                            keepfollowing.movement_prediction_state = true
                        end)

                        TestNoPushLagCompensation(true)

                        it("should return false", function()
                            assert.is_false(keepfollowing:StartFollowing(leader))
                        end)
                    end)

                    describe("when the previous movement prediction state is false", function()
                        before_each(function()
                            _G.SDK.Player.SetMovementPrediction = spy.new(Empty)
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
                        _G.SDK.World.IsMasterSim = spy.new(ReturnValueFn(false))
                    end)

                    describe("when the previous movement prediction state is true", function()
                        before_each(function()
                            _G.SDK.Player.SetMovementPrediction = spy.new(Empty)
                            keepfollowing.movement_prediction_state = true
                        end)

                        TestNoPushLagCompensation(true)

                        it("should return false", function()
                            assert.is_false(keepfollowing:StartFollowing(leader))
                        end)
                    end)

                    describe("when the previous movement prediction state is false", function()
                        before_each(function()
                            _G.SDK.Player.SetMovementPrediction = spy.new(Empty)
                            keepfollowing.movement_prediction_state = false
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
                    AssertDebugSpyWasCalled("DebugString", 2, "New leader: Wilson. Distance: 3.00")
                    AssertDebugSpyWasCalled("DebugString", 2, "Started following...")
                end)

                it("should call self:StartFollowingThread()", function()
                    assert.spy(keepfollowing.StartFollowingThread).was_called(0)
                    keepfollowing:StartFollowing(leader)
                    assert.spy(keepfollowing.StartFollowingThread).was_called(1)
                    assert
                        .spy(keepfollowing.StartFollowingThread)
                        .was_called_with(match.is_ref(keepfollowing))
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
                    AssertDebugSpyWasCalled("DebugError", 1, { "Wilson", "can't become a leader" })
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
                    AssertDebugSpyWasCalled("DebugError", 1, error)
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
                AssertDebugSpyWasCalled(
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
                _G.SDK.Player.SetMovementPrediction = spy.new(Empty)
                keepfollowing.config = {}
                keepfollowing.StartPushingThread = spy.new(Empty)
            end)

            local function TestNoPushLagCompensation(state)
                it("shouldn't set a new self.movement_prediction_state value", function()
                    assert.is_equal(state, keepfollowing.movement_prediction_state)
                end)

                it("shouldn't call self:StartPushing()", function()
                    assert.spy(_G.SDK.Player.SetMovementPrediction).was_called(0)
                    keepfollowing:StartPushing(leader)
                    assert.spy(_G.SDK.Player.SetMovementPrediction).was_called(0)
                end)
            end

            describe("when push lag compensation is enabled", function()
                before_each(function()
                    keepfollowing.config.push_lag_compensation = true
                end)

                describe("and is a master simulation", function()
                    before_each(function()
                        _G.SDK.World.IsMasterSim = spy.new(ReturnValueFn(true))
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
                        _G.SDK.World.IsMasterSim = spy.new(ReturnValueFn(false))
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
                            assert.spy(_G.SDK.Player.SetMovementPrediction).was_called(0)
                            keepfollowing:StartPushing(leader)
                            assert.spy(_G.SDK.Player.SetMovementPrediction).was_called(1)
                            assert.spy(_G.SDK.Player.SetMovementPrediction).was_called_with(false)
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
                            assert.spy(_G.SDK.Player.SetMovementPrediction).was_called(0)
                            keepfollowing:StartPushing(leader)
                            assert.spy(_G.SDK.Player.SetMovementPrediction).was_called(0)
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
                        _G.SDK.World.IsMasterSim = spy.new(ReturnValueFn(true))
                    end)

                    describe("when the previous movement prediction state is true", function()
                        before_each(function()
                            _G.SDK.Player.SetMovementPrediction = spy.new(Empty)
                            keepfollowing.movement_prediction_state = true
                        end)

                        it("shouldn't call self:MovementPrediction()", function()
                            assert.spy(_G.SDK.Player.SetMovementPrediction).was_called(0)
                            keepfollowing:StartPushing(leader)
                            assert.spy(_G.SDK.Player.SetMovementPrediction).was_called(0)
                        end)

                        it("should return false", function()
                            assert.is_false(keepfollowing:StartPushing(leader))
                        end)
                    end)

                    describe("when the previous movement prediction state is false", function()
                        before_each(function()
                            _G.SDK.Player.SetMovementPrediction = spy.new(Empty)
                            keepfollowing.movement_prediction_state = false
                        end)

                        it("shouldn't call self:MovementPrediction()", function()
                            assert.spy(_G.SDK.Player.SetMovementPrediction).was_called(0)
                            keepfollowing:StartPushing(leader)
                            assert.spy(_G.SDK.Player.SetMovementPrediction).was_called(0)
                        end)

                        it("should return false", function()
                            assert.is_false(keepfollowing:StartPushing(leader))
                        end)
                    end)
                end)

                describe("and is a not master simulation", function()
                    before_each(function()
                        _G.SDK.World.IsMasterSim = spy.new(ReturnValueFn(false))
                    end)

                    describe("when the previous movement prediction state is true", function()
                        before_each(function()
                            _G.SDK.Player.SetMovementPrediction = spy.new(Empty)
                            keepfollowing.movement_prediction_state = true
                        end)

                        it("shouldn't call self:MovementPrediction()", function()
                            assert.spy(_G.SDK.Player.SetMovementPrediction).was_called(0)
                            keepfollowing:StartPushing(leader)
                            assert.spy(_G.SDK.Player.SetMovementPrediction).was_called(0)
                        end)

                        it("should return false", function()
                            assert.is_false(keepfollowing:StartPushing(leader))
                        end)
                    end)

                    describe("when the previous movement prediction state is false", function()
                        before_each(function()
                            _G.SDK.Player.SetMovementPrediction = spy.new(Empty)
                            keepfollowing.movement_prediction_state = false
                        end)

                        it("shouldn't call self:MovementPrediction()", function()
                            assert.spy(_G.SDK.Player.SetMovementPrediction).was_called(0)
                            keepfollowing:StartPushing(leader)
                            assert.spy(_G.SDK.Player.SetMovementPrediction).was_called(0)
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
                    AssertDebugSpyWasCalled("DebugString", 2, "New leader: Wilson. Distance: 3.00")
                    AssertDebugSpyWasCalled("DebugString", 2, "Started pushing...")
                end)

                it("should call self:StartPushingThread()", function()
                    assert.spy(keepfollowing.StartPushingThread).was_called(0)
                    keepfollowing:StartPushing(leader)
                    assert.spy(keepfollowing.StartPushingThread).was_called(1)
                    assert
                        .spy(keepfollowing.StartPushingThread)
                        .was_called_with(match.is_ref(keepfollowing))
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
                    AssertDebugSpyWasCalled("DebugError", 1, { "Wilson", "can't become a leader" })
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
                    AssertDebugSpyWasCalled("DebugError", 1, error)
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
                AssertDebugSpyWasCalled(
                    "DebugString",
                    1,
                    "Stopped pushing Wilson. RPCs: 1. Time: 1.0000"
                )
            end)

            it("should return true", function()
                assert.is_true(keepfollowing:StopPushing())
            end)
        end)
    end)
end)

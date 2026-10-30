----
-- Different mod utilities.
--
-- Includes different utilities used throughout the whole mod.
--
-- In order to become an utility the solution should either:
--
-- 1. Be a non-mod specific and isolated which can be reused in my other mods.
-- 2. Be a mod specific and isolated which can be used between classes/modules.
--
-- **Source Code:** [https://github.com/victorpopkov/dst-mod-keep-following](https://github.com/victorpopkov/dst-mod-keep-following)
--
-- @module Utils
--
-- @author Victor Popkov
-- @copyright 2019
-- @license MIT
-- @release 0.21.0
----
local Utils = {}

-- base (to store original functions after overrides)
local BaseGetModInfo

--- Helpers
-- @section helpers

local function DebugError(...)
    return _G.ModKeepFollowingDebug and _G.ModKeepFollowingDebug:DebugError(...)
end

local function DebugString(...)
    return _G.ModKeepFollowingDebug and _G.ModKeepFollowingDebug:DebugString(...)
end

--- Debugging
-- @section debugging

--- Adds debug methods to the destination class.
--
-- Checks the global environment if the `ModKeepFollowingDebug` (`Debug`) is available and adds the
-- corresponding methods from there. Otherwise, adds all the corresponding functions as empty ones.
--
-- @tparam table dest Destination class
function Utils.AddDebugMethods(dest)
    local methods = {
        "DebugError",
        "DebugInit",
        "DebugString",
        "DebugStringStart",
        "DebugStringStop",
        "DebugTerm",
    }

    if _G.ModKeepFollowingDebug then
        for _, v in pairs(methods) do
            dest[v] = function(_, ...)
                if _G.ModKeepFollowingDebug and _G.ModKeepFollowingDebug[v] then
                    return _G.ModKeepFollowingDebug[v](_G.ModKeepFollowingDebug, ...)
                end
            end
        end
    else
        for _, v in pairs(methods) do
            dest[v] = function() end
        end
    end
end

--- General
-- @section general

--- Checks if HUD has an input focus.
-- @tparam EntityScript inst Player instance
-- @treturn boolean
function Utils.IsHUDFocused(inst)
    return not Utils.ChainGet(inst, "HUD", "HasInputFocus", true)
end

--- Chain
-- @section chain

--- Gets chained field.
--
-- Simplifies the last chained field retrieval like:
--
--    return TheWorld
--        and TheWorld.net
--        and TheWorld.net.components
--        and TheWorld.net.components.shardstate
--        and TheWorld.net.components.shardstate.GetMasterSessionId
--        and TheWorld.net.components.shardstate:GetMasterSessionId
--
-- Or it's value:
--
--    return TheWorld
--        and TheWorld.net
--        and TheWorld.net.components
--        and TheWorld.net.components.shardstate
--        and TheWorld.net.components.shardstate.GetMasterSessionId
--        and TheWorld.net.components.shardstate:GetMasterSessionId()
--
-- It also supports net variables and tables acting as functions.
--
-- @usage Utils.ChainGet(TheWorld, "net", "components", "shardstate", "GetMasterSessionId") -- (function) 0x564445367790
-- @usage Utils.ChainGet(TheWorld, "net", "components", "shardstate", "GetMasterSessionId", true) -- (string) D000000000000000
-- @tparam table src
-- @tparam string|boolean ...
-- @treturn function|userdata|table
function Utils.ChainGet(src, ...)
    if src and (type(src) == "table" or type(src) == "userdata") then
        local args = { ... }
        local execute = false

        if args[#args] == true then
            table.remove(args, #args)
            execute = true
        end

        local previous = src
        for i = 1, #args do
            if src[args[i]] then
                previous = src
                src = src[args[i]]
            else
                return
            end
        end

        if execute and previous then
            if type(src) == "function" then
                return src(previous)
            elseif type(src) == "userdata" or type(src) == "table" then
                if type(src.value) == "function" then
                    -- netvar
                    return src:value()
                elseif getmetatable(src.value) and getmetatable(src.value).__call then
                    -- netvar (for testing)
                    return src.value(src)
                elseif getmetatable(src) and getmetatable(src).__call then
                    -- table acting as a function
                    return src(previous)
                end
            end
            return
        end

        return src
    end
end

--- Validates chained fields.
--
-- Simplifies the chained fields checking like below:
--
--    return TheWorld
--        and TheWorld.net
--        and TheWorld.net.components
--        and TheWorld.net.components.shardstate
--        and TheWorld.net.components.shardstate.GetMasterSessionId
--        and true
--        or false
--
-- @usage Utils.ChainValidate(TheWorld, "net", "components", "shardstate", "GetMasterSessionId") -- (boolean) true
-- @tparam table src
-- @tparam string|boolean ...
-- @treturn boolean
function Utils.ChainValidate(src, ...)
    return Utils.ChainGet(src, ...) and true or false
end

--- Locomotor
-- @section locomotor

--- Checks if the locomotor is available.
--
-- Can be used to check whether the movement prediction (lag compensation) is enabled or not as the
-- locomotor component is not available when it's disabled.
--
-- @tparam EntityScript inst Player instance
-- @treturn boolean
function Utils.IsLocomotorAvailable(inst)
    return Utils.ChainGet(inst, "components", "locomotor") ~= nil
end

--- Walks to a certain point.
--
-- Prepares a `WALKTO` action for `PlayerController.DoAction` when the locomotor component is
-- available. Otherwise sends the corresponding `RPC.LeftClick`.
--
-- @tparam EntityScript inst Player instance
-- @tparam Vector3 pt Destination point
function Utils.WalkToPoint(inst, pt)
    local player_controller = Utils.ChainGet(inst, "components", "playercontroller")
    if not player_controller then
        DebugError("Player controller is not available")
        return
    end

    if player_controller.locomotor then
        player_controller:DoAction(BufferedAction(inst, nil, ACTIONS.WALKTO, nil, pt))
    else
        SendRPCToServer(RPC.LeftClick, ACTIONS.WALKTO.code, pt.x, pt.z)
    end
end

--- Modmain
-- @section modmain

--- Hide the modinfo changelog.
--
-- Overrides the global `KnownModIndex.GetModInfo` to hide the changelog if it's included in the
-- description.
--
-- @tparam string modname
-- @tparam boolean enable
-- @treturn boolean
function Utils.HideChangelog(modname, enable)
    if modname and enable and not BaseGetModInfo then
        BaseGetModInfo = _G.KnownModIndex.GetModInfo
        _G.KnownModIndex.GetModInfo = function(self, known_modname)
            if
                known_modname == modname
                and self.savedata
                and self.savedata.known_mods
                and self.savedata.known_mods[modname]
            then
                local TrimString = _G.TrimString
                local modinfo = self.savedata.known_mods[modname].modinfo
                if modinfo and type(modinfo.description) == "string" then
                    local changelog = modinfo.description:find("v" .. modinfo.version, 0, true)
                    if type(changelog) == "number" then
                        modinfo.description = TrimString(modinfo.description:sub(1, changelog - 1))
                    end
                end
            end
            return BaseGetModInfo(self, known_modname)
        end
        return true
    elseif BaseGetModInfo then
        _G.KnownModIndex.GetModInfo = BaseGetModInfo
        BaseGetModInfo = nil
    end
    return false
end

--- Thread
-- @section thread

--- Starts a new thread.
--
-- Just a convenience wrapper for the `StartThread`.
--
-- @tparam string id Thread ID
-- @tparam function fn Thread function
-- @tparam function whl While function
-- @tparam[opt] function init Initialization function
-- @tparam[opt] function term Termination function
-- @treturn table
function Utils.ThreadStart(id, fn, whl, init, term)
    return StartThread(function()
        DebugString("Thread started")
        if init then
            init()
        end
        while whl() do
            fn()
        end
        if term then
            term()
        end
        Utils.ThreadClear()
    end, id)
end

--- Clears a thread.
-- @tparam table thread Thread
function Utils.ThreadClear(thread)
    local task = scheduler:GetCurrentTask()
    if thread or task then
        if thread and not task then
            DebugString("[" .. thread.id .. "]", "Thread cleared")
        else
            DebugString("Thread cleared")
        end

        thread = thread ~= nil and thread or task
        KillThreadsWithID(thread.id)
        thread:SetList(nil)
    end
end

return Utils

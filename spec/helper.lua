--
-- Packages
--

package.path = "./scripts/?.lua;" .. package.path

--
-- SDK
--

local SDK

SDK = require("keepfollowing/sdk/sdk/sdk")
SDK.SetIsSilent(true).Load(
    {
        modname = "mod-keep-following",
        AddPrefabPostInit = function() end,
    },
    "keepfollowing/sdk",
    {
        "Config",
        "Debug",
        "DebugUpvalue",
        "Entity",
        "Input",
        "Method",
        "ModMain",
        "Player",
        "RPC",
        "Test",
        "Thread",
        "World",
    }
)

_G.SDK = SDK

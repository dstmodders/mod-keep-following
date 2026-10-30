name = "Keep Following"
version = "0.21.0"
description = [[Version: ]]
    .. version
    .. "\n\n"
    .. [[By default, Shift +  (LMB) on the player or supported entities to keep following. Shift + Ctrl +  (LMB) to keep pushing.]]
    .. "\n\n"
    .. [[You can also use the above key combinations on a Tent/Siesta Lean-to used by another player to keep following or pushing him.]]
    .. "\n\n"
    .. [[v]]
    .. version
    .. [[:]]
    .. "\n"
    .. [[- Added compatibility configuration]]
    .. "\n"
    .. [[- Changed following configurations]]
    .. "\n"
    .. [[- Improved interruptions behaviour]]
    .. "\n"
    .. [[- Improved keybinds configurations]]
    .. "\n"
    .. [[- Improved mouse overrides]]
author = "Demonblink"
api_version = 10
forumthread = ""

-- Advanced Controls is using the default 0 priority. We need to load our mod after theirs, so its
-- "Attack actions only key" wouldn't interfere with us. The "1835465557" part is the workshop ID of
-- this mod so other mods had enough "space for manoeuvre" in loading priority.
priority = -0.011835465557

icon = "modicon.tex"
icon_atlas = "modicon.xml"

all_clients_require_mod = false
client_only_mod = true
dont_starve_compatible = false
dst_compatible = true
reign_of_giants_compatible = false
shipwrecked_compatible = false

folder_name = folder_name or "dst-mod-keep-following"
if not folder_name:find("workshop-") then
    name = name .. " (dev)"
end

--
-- Helpers
--

local function AddConfig(label, name, options, default, hover)
    return { label = label, name = name, options = options, default = default, hover = hover or "" }
end

local function AddSection(title)
    return AddConfig(title, "", { { description = "", data = 0 } }, 0)
end

local function CreateKeyList()
    -- helpers
    local function AddDisabled(t)
        t[#t + 1] = { description = "Disabled", data = false }
    end

    local function AddKey(t, key)
        t[#t + 1] = { description = key, data = "KEY_" .. key:gsub(" ", ""):upper() }
    end

    local function AddKeysByName(t, names)
        for i = 1, #names do
            AddKey(t, names[i])
        end
    end

    local function AddAlphabetKeys(t)
        local string = ""
        for i = 1, 26 do
            AddKey(t, string.char(64 + i))
        end
    end

    local function AddTypewriterNumberKeys(t)
        for i = 1, 10 do
            AddKey(t, "" .. (i % 10))
        end
    end

    local function AddTypewriterModifierKeys(t)
        AddKeysByName(t, { "Alt", "Ctrl", "Shift" })
    end

    local function AddTypewriterKeys(t)
        AddAlphabetKeys(t)
        AddKeysByName(t, {
            "Slash",
            "Backslash",
            "Period",
            "Semicolon",
            "Left Bracket",
            "Right Bracket",
        })
        AddKeysByName(t, { "Space", "Tab", "Backspace", "Enter" })
        AddTypewriterModifierKeys(t)
        AddKeysByName(t, { "Tilde" })
        AddTypewriterNumberKeys(t)
        AddKeysByName(t, { "Minus", "Equals" })
    end

    local function AddFunctionKeys(t)
        for i = 1, 12 do
            AddKey(t, "F" .. i)
        end
    end

    local function AddArrowKeys(t)
        AddKeysByName(t, { "Up", "Down", "Left", "Right" })
    end

    local function AddNavigationKeys(t)
        AddKeysByName(t, { "Insert", "Delete", "Home", "End", "Page Up", "Page Down" })
    end

    -- key list
    local key_list = {}

    AddDisabled(key_list)
    AddArrowKeys(key_list)
    AddFunctionKeys(key_list)
    AddTypewriterKeys(key_list)
    AddNavigationKeys(key_list)
    AddKeysByName(key_list, { "Escape", "Pause", "Print" })

    return key_list
end

--
-- Configuration
--

local key_list = CreateKeyList()

local boolean = {
    { description = "Yes", data = true },
    { description = "No", data = false },
}

local compatibilities = {
    {
        description = "Recommended",
        data = "recommended",
        hover = "Recommended: overrides both on control and on left/right clicks",
    },
    {
        description = "Alternative",
        data = "alternative",
        hover = "Alternative: overrides only on control",
    },
}

local follow_methods = {
    {
        description = "Default",
        data = "default",
        hover = "Default: player follows a leader step-by-step",
    },
    {
        description = "Closest",
        data = "closest",
        hover = "Closest: player goes to the closest target point from a leader",
    },
}

local follow_distances = {
    { description = "1.5m", data = 1.5 },
    { description = "2.5m", data = 2.5 },
    { description = "3.5m", data = 3.5 },
}

local follow_distance_keeping = {
    {
        description = "Yes",
        data = true,
        hover = "Yes: move away from a leader within the follow distance",
    },
    { description = "No", data = false, hover = "No: stay still within the follow distance" },
}

local push_with_rmb = {
    {
        description = "Yes",
        data = true,
        hover = 'Yes: the "push key" becomes disabled in favour of the RMB',
    },
    { description = "No", data = false, hover = 'No: the "push key" is used for pushing' },
}

local push_mass_checking = {
    {
        description = "Yes",
        data = true,
        hover = "Yes: limits pushing to entities with an appropriate mass difference",
    },
    { description = "No", data = false, hover = "No: no limitations for the mass difference" },
}

configuration_options = {
    AddSection("Keybinds"),
    AddConfig(
        "Action key",
        "key_action",
        key_list,
        "KEY_SHIFT",
        "Key used for both following and pushing"
    ),
    AddConfig(
        "Push key",
        "key_push",
        key_list,
        "KEY_CTRL",
        "Key used in combination with an action key for pushing"
    ),

    AddSection("General"),
    AddConfig(
        "Compatibility",
        "compatibility",
        compatibilities,
        "recommended",
        "Which compatibility mode should be used?\nMay fix some issues with other mods"
    ),

    AddSection("Following"),
    AddConfig(
        "Follow method",
        "follow_method",
        follow_methods,
        "default",
        "Which follow method should be used?"
    ),
    AddConfig(
        "Follow distance",
        "follow_distance",
        follow_distances,
        2.5,
        "How close can you approach the leader?"
    ),
    AddConfig(
        "Follow distance keeping",
        "follow_distance_keeping",
        follow_distance_keeping,
        false,
        "Should the follower keep the distance from the leader?"
    ),

    AddSection("Pushing"),
    AddConfig(
        "Push with RMB",
        "push_with_rmb",
        push_with_rmb,
        false,
        "Should the  (RMB) in combination with an action key be used for pushing?"
    ),
    AddConfig(
        "Push mass checking",
        "push_mass_checking",
        push_mass_checking,
        true,
        "Should the mass difference checking be enabled?\nIgnored for pushing players as a ghost"
    ),
    AddConfig(
        "Push lag compensation",
        "push_lag_compensation",
        boolean,
        true,
        "Should the lag compensation be automatically disabled while pushing?"
    ),

    AddSection("Other"),
    AddConfig(
        "Hide changelog",
        "hide_changelog",
        boolean,
        true,
        "Should the changelog in the mod description be hidden?\nMods should be reloaded to take effect"
    ),
    AddConfig("Debug", "debug", boolean, false, "Should the debug mode be enabled?"),
}

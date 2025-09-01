data:extend{

    {
        type = "custom-input",
        name = "input-toggle-robots-build-closest-first",
        key_sequence = "CONTROL + T",
        consuming = "game-only"
    },
    {
        type = "shortcut",
        name = "shortcut-toggle-robots-build-closest-first",
        action = "lua",
        associated_control_input = "input-toggle-robots-build-closest-first",
        icon = "__Robots_Build_Closest_First__/graphics/shortcutIcon-32.png",
        icon_size = 32,
        small_icon = "__Robots_Build_Closest_First__/graphics/shortcutIcon-24.png",
        small_icon_size = 24,
        toggleable = true,
    }
}
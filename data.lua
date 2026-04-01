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
        localised_name = {"shortcut.shortcut-toggle-robots-build-closest-first"},
        action = "lua",
        associated_control_input = "input-toggle-robots-build-closest-first",
        icon = "__Robots_Build_Closest_First__/graphics/shortcut_icon_56.png",
        icon_size = 56,
        small_icon = "__Robots_Build_Closest_First__/graphics/shortcut_icon_24.png",
        small_icon_size = 24,
        toggleable = true,
    }
}
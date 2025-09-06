local def = require("defines")
data:extend({
    {
        type = "string-setting",
        name = def.limited_radius_setting,
        setting_type = "runtime-per-user",
        default_value = "limit off",
        allowed_values = {
            "10x10",
            "20x20",
            "30x30",
            "40x40",
            "50x50",
            "60x60",
            "70x70",
            "80x80",
            "90x90",
            "100x100",
            "110x110",
            "120x120",
            "limit off"
        },
        order = "a"
    },
    {
        type = "bool-setting",
        name = def.use_limit_when_off_setting,
        setting_type = "runtime-per-user",
        default_value = true,
        order = "b"
    },
})
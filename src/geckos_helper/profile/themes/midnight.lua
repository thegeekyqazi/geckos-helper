-- Pure black with the wallpaper's accent; easy on OLED and at night.
local t = default()
t.bg           = "#000000"
t.surface      = "#0b0b0d"
t.surface_high = "#151518"
t.border       = alpha(palette.primary, 0.25)
t.user_bubble  = alpha(palette.primary, 0.18)
t.composer_bg  = "#111114"
t.tool_bg      = "#0b0b0d"
t.code_bg      = "#111114"
return t

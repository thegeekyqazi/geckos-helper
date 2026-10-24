-- Frosted glass: see-through panel with a light edge and sheen; Hyprland blurs
-- what's behind it. Accents follow the wallpaper.
local t = default()
local light = "#ffffff"
local ink   = "#10121a"
t.bg            = alpha(mix(ink, palette.primary_container, 0.18), 0.62)
t.popup         = alpha(mix(ink, palette.primary_container, 0.2), 0.96)
t.surface       = alpha(light, 0.08)
t.surface_high  = alpha(light, 0.14)
t.border        = alpha(light, 0.28)
t.border_width  = 1.5
t.sheen         = alpha(light, 0.10)
t.shadow        = false
t.text          = "#f4f5fa"
t.text_muted    = alpha("#f4f5fa", 0.70)
t.accent        = lighten(palette.primary, 0.05)
t.on_accent     = palette.on_primary
t.user_bubble   = alpha(light, 0.16)
t.on_user_bubble = "#ffffff"
t.tool_bg       = alpha(light, 0.06)
t.code_bg       = alpha(ink, 0.35)
t.composer_bg   = alpha(light, 0.10)
t.permission_bg = alpha(palette.tertiary_container, 0.75)
t.radius        = 26
t.card_radius   = 16
return t

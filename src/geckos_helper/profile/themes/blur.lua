-- Blurry: a dark, heavily blurred backdrop of whatever is behind the panel,
-- no edges or sheen. Accents follow the wallpaper.
local t = default()
local ink = "#0a0b10"
t.bg            = alpha(ink, 0.64)
t.surface       = alpha("#ffffff", 0.06)
t.surface_high  = alpha("#ffffff", 0.11)
t.border        = alpha("#ffffff", 0.06)
t.border_width  = 0
t.shadow        = false
t.text          = "#eef0f6"
t.text_muted    = alpha("#eef0f6", 0.62)
t.user_bubble   = alpha(palette.primary, 0.28)
t.on_user_bubble = "#ffffff"
t.tool_bg       = alpha("#ffffff", 0.05)
t.code_bg       = alpha(ink, 0.45)
t.composer_bg   = alpha("#ffffff", 0.08)
t.permission_bg = alpha(palette.tertiary_container, 0.8)
return t

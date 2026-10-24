-- Default theme: follows end-4's wallpaper colors, laid out like a modern chat app.
-- Copy this file to ~/.config/geckos-helper/themes/<name>.lua to make your own.
local p = palette
return {
    -- surfaces
    bg            = p.surface_container_lowest,
    surface       = p.surface_container_low,
    surface_high  = p.surface_container,
    border        = alpha(p.outline_variant, 0.5),
    -- text
    text          = p.on_surface,
    text_muted    = p.on_surface_variant,
    -- accents
    accent        = p.primary,
    on_accent     = p.on_primary,
    -- messages
    user_bubble    = p.surface_container_high,
    on_user_bubble = p.on_surface,
    tool_bg        = alpha(p.surface_container, 0.8),
    permission_bg  = p.tertiary_container,
    on_permission  = p.on_tertiary_container,
    error_bg       = p.error_container,
    on_error       = p.on_error_container,
    composer_bg    = p.surface_container,
    code_bg        = p.surface_container_high,
    -- shape and type ("" font = end-4's main font)
    radius        = 22,   -- panel corners
    card_radius   = 14,
    bubble_radius = 20,
    font          = "",
    mono_font     = "",
    font_size     = 15,
    -- layout
    width         = 470,
    side          = "left",  -- or "right"
    -- identity
    assistant_name = "Gecko",
    avatar         = "🦎",
    -- desktop mascot: "always", "busy" (only while working / waiting) or "off"
    mascot         = "always",
    mascot_corner  = "bottom-right",  -- top-left, top-right, bottom-left, bottom-right
    mascot_size    = 52,
}

# Panel themes (Lua)

Themes are Lua files that return a table of design tokens. Put yours in
`~/.config/geckos-helper/themes/<name>.lua`; a file with the same name as a bundled
theme replaces it. The panel updates as soon as you save.

See-through themes (`glass`, `blur`) use semi-transparent colors (`alpha(c, 0.4)`); Hyprland blurs
what's behind Gecko's panels (a layer rule `gecko end4-patch` installs).

Switch themes with the palette button in the panel header (right-click goes
back), Ctrl+T inside the panel, or `gecko theme next` / `gecko theme <name>`.

## Start from the default

```lua
-- ~/.config/geckos-helper/themes/sunset.lua
local t = default()          -- the default theme's tokens
t.accent      = "#ff8a5c"
t.user_bubble = mix(palette.primary_container, "#ff8a5c", 0.3)
t.radius      = 28
t.side        = "right"
return t
```

## What a theme can use

| Global | What it is |
|-|-|
| `palette` | end-4's wallpaper colors, M3 names in snake_case: `primary`, `on_surface`, `surface_container_high`, `outline_variant`, … |
| `dark` | `true` when the wallpaper scheme is dark |
| `mix(a, b, t)` | blend two colors, `t` from 0 to 1 |
| `alpha(c, a)` | color with opacity `a` |
| `lighten(c, amt)` / `darken(c, amt)` | shift lightness by `amt` (0 to 1) |
| `default()` | a fresh copy of the default theme's table |

Themes run in a sandbox: no `io`, `os`, `require` or file access.

## Tokens

| Token | Used for |
|-|-|
| `bg`, `surface`, `surface_high`, `border` | panel background, cards, hovers, outlines |
| `text`, `text_muted` | main and secondary text |
| `accent`, `on_accent` | send button, icons, highlights |
| `user_bubble`, `on_user_bubble` | your messages |
| `tool_bg`, `code_bg` | tool rows and their output |
| `permission_bg`, `on_permission` | approval cards |
| `error_bg`, `on_error` | errors |
| `composer_bg` | the message box |
| `radius`, `card_radius`, `bubble_radius` | corner rounding in pixels |
| `font`, `mono_font`, `font_size` | `""` font means end-4's font |
| `width`, `side` | panel width in pixels, `"left"` or `"right"` |
| `popup` | menus and the / palette (keep it nearly opaque in see-through themes) |
| `sheen` | a light gradient over the panel (glass); `"transparent"` for none |
| `border_width`, `shadow` | edge width in pixels; `false` turns off the drop shadow |
| `assistant_name`, `avatar` | name and emoji shown on replies (and on the mascot) |
| `mascot`, `mascot_corner`, `mascot_size` | desktop mascot: `"always"`, `"busy"` or `"off"`; corner like `"bottom-right"`; size in pixels |

Missing tokens fall back to end-4's colors. If a theme has an error, the panel
keeps the last working theme and shows the error at the top.

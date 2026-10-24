# Gecko's Helper ↔ Gecko's dots

Two projects for the [end-4](https://github.com/end-4/dots-hyprland) desktop:

- **[Gecko's Helper](https://github.com/thegeekyqazi/geckos-helper)**: the AI. A desktop agent
  that runs on Claude Code (your subscription, no API key): panel, quick ask, mascot,
  approvals and injection guard, watchers, recipes, inbox, calendar access, Obsidian
  projects, attachments, and Gecko's tools for your devices.
- **Gecko's dots**: everything else. Music card and island, desktop widgets, wallpaper sync,
  desktop config, and (planned) the phone connection.

**Rule of thumb:** if a feature needs the AI, it belongs in Helper; if it works without
AI, it belongs in the dots.

**Each works without the other.** Helper runs on plain end-4 and detects the dots at
runtime; the dots run without Helper (the calendar widget falls back to a plain month).

## What they share

| | Written by | Read by | Notes |
|-|-|-|-|
| `~/.local/state/quickshell/user/todo.json` | end-4, Helper (`todo_*` tools, `/todo`), dots To-Do widget | all three | end-4's file. Everyone writes it **in place** (file watchers lose renamed files) and watches it for changes. |
| `~/.local/state/quickshell/user/desktopnotes.txt` | dots Notes widget, Helper (`notes_*`, `/note`) | both | JSON list of `{id, content, attachments, createdAt}`. Helper only offers notes when `~/.config/quickshell/nowplaying-desktop` exists. |
| `~/.local/state/geckos-helper/calendar.json` | Helper (every 10 min) | dots calendar widget (`GeckoCalendar.qml`) | `{"updated", "errors", "events": [{date, title, start, end, all_day, calendar, color, location}]}`, one entry per day an event touches. |
| `~/.local/state/quickshell/user/generated/colors.json` | end-4 | both | Wallpaper colors. Both follow them. |

## Commands across the line

- Dots → Helper: `qs -c gecko ipc call gecko <calendar|open|toggle|ask "...">` (the calendar
  widget opens Gecko's calendar on click).
- Helper → dots: `qs -c nowplaying ipc call nowplaying <playPause|next|toggleIsland|…>`
  (listed in Gecko's tools context only when the music widgets are installed).

## Config each one owns

| | Helper | Dots |
|-|-|-|
| Quickshell config | `~/.config/quickshell/gecko` | `~/.config/quickshell/nowplaying`, `nowplaying-desktop` |
| Settings | `~/.config/geckos-helper/` | `~/.config/nowplaying/` |
| Services | `geckos-helper`, `geckos-helper-ui`, context timer | `nowplaying`, `nowplaying-desktop` |
| Hyprland | its own marked block in `custom/keybinds.lua` (Super+A, Super+Space, Super+Alt+K) and `custom/rules.lua` (blur for `quickshell:gecko.*`) | its own marked block in `custom/keybinds.lua` (Super+Ctrl+M) |
| end-4 patches | to-do reload, bar ✦ button → Gecko (`gecko end4-patch`) | none (reads end-4's config instead) |

Changing a shared file's format? Update both projects and this file in both repos.

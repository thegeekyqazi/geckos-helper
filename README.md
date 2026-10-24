# Gecko's Helper

A desktop agent for the [end-4 / illogical-impulse](https://github.com/end-4/dots-hyprland)
Hyprland shell. It drives the coding-agent CLIs you already pay for (Claude Code
first; Codex and OpenCode planned) instead of API keys. It gives them safe,
toggleable access to your desktop: to-dos, notifications, calendar, Obsidian
vault, media and system info.

> Status: **early but usable**. The panel (Super+A), the daemon, the desktop MCP server,
> the context generator and a terminal client work. See the roadmap.

## The panel

`qs -c gecko`, a separate Quickshell config that reuses end-4's own widgets and
wallpaper colors through symlinks, so it looks native but end-4 updates never
overwrite it. It replaces end-4's left sidebar on **Super+A** (Super+B / Super+O
still open end-4's).

- Streaming replies with markdown, collapsible tool cards, "thinking" blocks
- Permission cards: **Allow**, **Allow for this chat**, **Deny**
- Model picker in the composer; the star sets the default for new chats (Sonnet out of the box)
- **Themes in Lua** with live reload and a theme switcher button; see [docs/THEMES.md](docs/THEMES.md)
- **Hand-off**: copy a chat, or a short model-written brief, to paste into Claude.ai
  (panel menu, `gecko handoff [--brief]`, or just ask Gecko to hand it off)
- Chat history, capability switches, kill switch, 5-hour / 7-day usage bars
- Ctrl+N new chat, Ctrl+H history, Ctrl+T next theme, Ctrl+O wider panel, Esc closes
- `qs -c gecko ipc call gecko ask "..."` sends a prompt from a script or keybind

## How it fits together

```
┌──────────────┐  unix socket  ┌─────────────────────────┐  stream-json  ┌────────────┐
│  Quickshell  │ ◄───────────► │  gecko daemon (systemd) │ ◄───────────► │ claude -p  │
│  sidebar UI  │   JSON lines  │  • chats & history      │               │ (codex,    │
│  gecko chat  │               │  • permission prompts   │               │  opencode) │
└──────────────┘               │  • kill switch          │               └─────┬──────┘
                               └─────────────────────────┘                     │ MCP (stdio)
                                                               ┌───────────────▼──────────┐
                                                               │ gecko MCP server         │
                                                               │ todo · notifications ·   │
                                                               │ calendar · obsidian ·    │
                                                               │ media · system · handoff │
                                                               └──────────────────────────┘
```

- **Separate profile.** The agent runs in `~/.local/share/geckos-helper/workspace`,
  so its chat history doesn't mix with your normal Claude Code sessions. It gets
  its own settings (`~/.config/geckos-helper/claude-settings.json`, layered on top
  of yours with `--settings`) and a system prompt that is *appended* to Claude
  Code's (`--append-system-prompt-file`), never replacing it. Set
  `inherit_settings = false` to stop loading your `~/.claude` settings, hooks
  and CLAUDE.md.
- **Permission prompts go to you.** Claude runs with `--permission-prompt-tool stdio`, so
  every "may I run this?" comes to the daemon and on to the UI as an
  approve/deny request. The read-only desktop tools are pre-approved in the
  profile settings; anything that writes asks first.
- **Context file.** `gecko context` writes a short, hand-picked description of
  this machine: installed tools from [`profile/tools.toml`](src/geckos_helper/profile/tools.toml),
  MCP servers, skills, disabled capabilities, and what's new this week. A daily
  systemd timer regenerates it.
- **Event names follow ACP.** Backends translate each CLI's output into
  [Agent Client Protocol](https://agentclientprotocol.com) session-update events,
  so ACP agents (`opencode acp`, codex-acp) can be added without UI changes.

## Security model

- **Notifications, calendar entries, clipboard, web pages and files are data, not
  instructions.** MCP tools wrap third-party text in `<untrusted-content>`, and
  the system prompt tells the agent never to act on it. Nothing runs automatically
  because a notification arrived.
- **Per-capability toggles:** `gecko caps <name> on|off`. Every tool checks its
  toggle on every call, so turning one off takes effect mid-chat. Clipboard
  reading is off by default.
- **Kill switch:** `gecko kill on` stops every running agent and blocks all
  desktop tools, even if the daemon is down. Bind it to a key in
  `~/.config/hypr/custom/keybinds.lua`:
  `hl.bind("SUPER+ALT+K", hl.dsp.exec_cmd("~/.local/bin/gecko kill toggle"), {description = "Gecko kill switch"})`
- **Action log:** every write a tool makes is appended to
  `~/.local/state/geckos-helper/actions.jsonl`.
- **No retry loops:** after you deny an action, an identical request in the same
  turn is denied automatically and the agent is told not to work around it.
- **"Allow for this chat"** remembers the tool for that chat only; for shell
  commands it remembers the exact command, never a whole program.

## Install

Requires [uv](https://docs.astral.sh/uv/), Python 3.14 and Claude Code logged in.

```sh
./install.sh          # installs `gecko`, the panel, keybinds, end-4 add-ons and systemd units
gecko chat            # talk to it in the terminal
gecko ask "what's due this week in my vault?"
gecko caps            # list capability toggles
gecko model opus --default   # or pick it in the panel
gecko kill toggle
gecko end4-patch      # re-apply the end-4 add-ons after an end-4 update
./uninstall.sh        # removes everything it added, keeps your data
```

Config lives in `~/.config/geckos-helper/config.toml` (agent path, model,
Obsidian vault, calendar feeds).

### Calendar

Calendars are read from `.ics` feeds. For a Microsoft 365 / Outlook calendar
(e.g. a university account), publish it from Outlook on the web
(Settings › Calendar › Shared calendars › Publish a calendar) and add the ICS link:

```toml
[[calendar.ics]]
name = "University"
url = "https://outlook.office365.com/owa/calendar/.../calendar.ics"
```

## Roadmap

- [x] Daemon, Claude Code backend, permission round-trip, chat resume
- [x] Desktop MCP server, capability toggles, kill switch, action log
- [x] Context file generator + daily timer
- [x] Quickshell panel on Super+A with tool cards, approve/deny, history, model picker, usage meter
- [x] end-4 to-do widget picks up agent edits (small re-appliable patch)
- [ ] Scheduler: cron-style and event-triggered background tasks, activity inbox, usage budget
- [ ] Injection classifier for untrusted content
- [ ] Writable calendar: local store synced both ways (vdirsyncer) with Google + Outlook (DavMail) + a richer calendar widget
- [ ] Obsidian project tracking: ideas → projects → auto-generated to-dos, progress reviews
- [ ] Desktop context buttons (clipboard, focused window, screenshot region), quick-ask keybind
- [ ] Codex and OpenCode backends (ACP)
- [ ] Voice input (whisper.cpp)

## License

MIT

# Developing Gecko's Helper

Notes for working on the code (people or AI sessions). User-facing docs are the
README, [THEMES.md](THEMES.md), [RECIPES.md](RECIPES.md) and [PROJECTS.md](PROJECTS.md).

## Architecture

```
Quickshell panel (qs -c gecko)  ──unix socket, JSON lines──►  gecko daemon (systemd user)
  quickshell/gecko/gecko/*.qml                                   src/geckos_helper/daemon.py
                                                                   │ stream-json
                                                                   ▼
                                                     claude -p (one process per chat)
                                                                   │ MCP stdio
                                                                   ▼
                                                     gecko MCP server (mcp_server.py)
                                                     desktop tools, each behind a capability
```

- **Daemon** (`daemon.py`): socket server on `$XDG_RUNTIME_DIR/geckos-helper.sock`. Every
  request is `{"id", "op", ...}` and handled by `op_<name>`; events are broadcast to all
  clients as `{"event": ...}`. It owns chats, permission prompts, the injection guard, the
  scheduler (watchers, recipes, triggers), the theme renderer and the calendar feed.
- **Backend** (`backends/claude.py`): long-running `claude -p --input-format stream-json
  --output-format stream-json --permission-prompt-tool stdio`. Permission prompts arrive as
  `control_request: can_use_tool` and are answered with `control_response`. Events are
  translated to ACP-style names (`agent_message_chunk`, `tool_call`, `permission_request`…)
  so ACP agents (OpenCode, Codex) can be added as more backends.
- **Profile**: the agent runs in `~/.local/share/geckos-helper/workspace` (separate Claude
  history and auto-memory), with `--settings ~/.config/geckos-helper/claude-settings.json`
  layered on the user's settings and `--append-system-prompt-file` (profile/system-prompt.md
  + the generated tools context).
- **MCP server** (`mcp_server.py`): tools wrap `desktop/*` modules. `gated(capability,
  writes=)` checks the kill switch and capability on every call, logs writes, and refuses
  writes when `GECKO_READONLY=1` (unattended runs). Third-party text is wrapped with
  `untrusted()`.
- **Unattended runs** (`profiles.unattended_argv`): watchers and recipes run read-only
  (WebSearch, domain-limited WebFetch, read-only gecko tools, `--permission-mode dontAsk`,
  strict MCP with the read-only server). Results are scanned by `guard.py`.
- **Panel**: separate Quickshell config built by `quickshell/install-ui.sh`:
  `~/.config/quickshell/gecko/` = copied `shell.qml` + symlinks to `quickshell/gecko/gecko`
  and to end-4's `modules/common`, `services`, `assets` (reuses end-4 widgets and theme).
  `Gecko.qml` is the socket client and state; `Theme.qml` reads the Lua-rendered
  `~/.local/state/geckos-helper/theme.json`.

## Where things live

| Path | What |
|-|-|
| `~/.config/geckos-helper/` | `config.toml`, `claude-settings.json`, `permission-rules.json`, `themes/`, `recipes/`, Google OAuth client |
| `~/.local/share/geckos-helper/` | `chats.db` (chats, transcripts, FTS, inbox), workspace, attachments, watchers, recipe state, calendar cache, MCP configs |
| `~/.local/state/geckos-helper/` | `state.json` (kill switch, capabilities, defaults), action and activity logs, `theme.json`, `calendar.json` feed, Google token, tainted chats |

## Working on it

- `uv run gecko …` in the repo; `./install.sh` installs the editable tool, the panel,
  systemd units, keybinds and end-4 add-ons. After changing Python, restart the daemon:
  `systemctl --user restart geckos-helper`. QML hot-reloads; `shell.qml` changes need
  `./quickshell/install-ui.sh`.
- Test MCP tools in-process: `await mcp_server.server.call_tool(name, args)`.
- Drive the panel without touching the screen: `qs -c gecko ipc call gecko <open|close|ask|prefill|history|settings|activity|memory|calendar|inbox|projects|quickAsk>`.
- Commit small, one logical change per commit.

## Gotchas (each cost real time)

- **QML property names** starting with `on` + capital (`onAccent`) are read as signal
  handlers and silently become undefined. Use `accentText` etc.
- **Inline components** can't see ids outside themselves; pass signals or properties.
- **`Layout.maximumWidth: parent.width - N`** inside a RowLayout caused a 100% CPU layout
  loop that froze input. Check CPU after panel changes.
- **File watchers** (`FileView.watchChanges`) lose files that are replaced by rename.
  Write shared files (todo.json, desktop notes, theme.json, calendar.json) **in place**.
- **MCP clients strip the environment**; `desktop/system.py` finds Hyprland's socket itself.
  Child processes of the MCP server must get `stdin=DEVNULL` (stdin is the MCP pipe).
- **Hyprland config is Lua** (`hl.bind`, `hl.unbind`, `hl.layer_rule`). Gecko keeps marked
  blocks in `~/.config/hypr/custom/keybinds.lua` and `rules.lua`.
- **end-4 add-ons** (`end4.py`) patch end-4's files (to-do watch, bar button). Writing them
  makes end-4 hot-reload, which once popped a dialog that froze the desktop: ask the user
  before running `gecko end4-patch`. end-4 updates overwrite the patches.
- **`qs ipc call … prefill "/"`** mangles a bare `/`; use `/x` when testing.
- Don't `pkill -f "gecko daemon"` from a shell whose command line contains that text.
- After a crash, git objects can be left empty; `sync` after commits.

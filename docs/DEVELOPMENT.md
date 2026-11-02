# Developing Gecko's Helper

Notes for working on the code (people or AI sessions). User-facing docs are the
README, [THEMES.md](THEMES.md), [RECIPES.md](RECIPES.md) and [PROJECTS.md](PROJECTS.md).

Gecko's Helper is the AI half; [Gecko's dots](INTEGRATION.md) is the optional desktop
half. Rule: if it needs the AI it goes here, otherwise in the dots. **Helper must keep
working on plain end-4 without the dots**: detect dots features at runtime (see
`desktop/notes.available()`), never require them.

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

## Safety regression tests

Interactive permission modes live in `permissions.py`. The daemon validates mode IDs,
pins new-chat choices in SQLite `chats.permission_mode`, and saves only the new-chat
default in `state.json`. Legacy NULL modes use `config.toml`'s configured mode, not the
UI default. `manual` normalizes to `default`; launches use Claude's native `manual`.
`permissions`, `set_permission_mode` and `set_default_permission_mode` are socket ops.
Chat/default changes broadcast `chat_updated.permission_mode` / `default_permission_mode`.
Send/startup and mode changes share a per-chat lock. Changes reject busy/starting chats;
idle changes close the backend, expire approvals and clear chat-scoped allows before
persisting. Resume uses the existing session ID and selected native mode. No native
auto/bypass behavior is emulated by Gecko; exceptions still reaching the host retain
normal approval handling. A `dontAsk` callback is denied even with taint/saved allows.
Unattended profiles do not read interactive permission defaults. Gecko has no OS sandbox.

`PermissionPicker.qml` is shared by composer and settings. The UI waits for successful
mode-change responses and clears its busy flag on rejection/disconnect. It ignores late
chat-change responses if another chat has been opened. Backend errors (including unavailable
Auto mode) are shown rather than downgrading or escalating silently.

Run `python -m unittest discover -s tests -v` in the project's Python environment.
The suite uses temporary files and mocked desktop/agent integrations; process-lifecycle
checks launch only local Python fixtures, never Claude or external services. It covers
vault boundaries, kill/capability checks, background budgets/cancellation, recipe parsing,
schedules, trigger fanout, injection scanning, approval scope/lifecycle and online handoff
evidence/limits/preview behavior. Handoff tests mock the model and clipboard.

`node tests/ui_state.mjs` checks the actual QML request and sizing functions with synthetic
state: preview/error/offline handling, edited copy, separate width/zoom and size bounds.
It does not render Qt or operate the desktop. For visual QA, use an isolated Quickshell
config with synthetic chat state and a private XDG_STATE_HOME; never test against personal
chats, notes or calendars. The panel source is symlinked live, so stage QML edits in a
worktree and check its logs/CPU after activation. Do not reload the main end-4 shell.

`tests/permission_picker_input.qml` adds real QtTest mouse clicks for the composer and
Settings pickers at 705px/150% and 360px/200%. Copy it into the isolated config with a
staged `qs.gecko` module, disabled socket and end-4 test stubs. It refuses to run outside
`XDG_RUNTIME_DIR=/tmp/gecko-ui-qa/runtime` and `XDG_STATE_HOME=/tmp/gecko-ui-qa/state`.
Use `QT_QPA_PLATFORM=offscreen QSG_RHI_BACKEND=software timeout 12s qs -p <copied-fixture>`.
Its `/tmp/gecko-ui-qa/permission-click-matrix.json` must have every `passed` value true.
Checks include visible bounded popup height, all six choices, scrolling/clicking the last
choice, selection/close, and preserving the saved-mode display after a rejected change.
Do not replace these with closed-control screenshots: a popup can be logically visible
with zero height. Size ComboBox popups from content plus padding, not their implicitHeight.

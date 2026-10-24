"""Static config (config.toml, user-edited) and live state (state.json, toggled from the UI)."""

import json
import os
import tomllib
from pathlib import Path
from typing import Any

from . import paths

DEFAULT_CONFIG = """\
# Gecko's Helper config. Changes apply to new chats.

[agents.claude]
path = "~/.local/bin/claude"
model = "sonnet"           # default for new chats; `gecko model <name> --default` changes it
models = ["sonnet", "opus", "haiku"]  # shown in the model picker
# true: also load your normal ~/.claude settings, hooks and CLAUDE.md.
# false: only the sidebar profile's own settings.
inherit_settings = true
permission_mode = "default"
idle_timeout_minutes = 15  # stop an idle agent process (the chat can be resumed)

[desktop]
terminal = "kitty"
obsidian_vault = "~/stuff/Obsidian/Vault 0"
obsidian_inbox = "Projects/Ideas.md"  # where /idea and captured ideas go, relative to the vault
projects_folder = "Projects"          # new project and goal notes (plus Projects Hub.md)
weather_city = ""                   # empty = located from your IP, like end-4's bar

[budget]
# Background work (watchers, recipes) pauses before it eats into your own chats.
max_unattended_runs_per_day = 40
pause_above_five_hour = 0.8   # pause while the 5-hour usage window is 80%+ used
pause_above_seven_day = 0.9

[guard]
# Tool results are scanned for prompt injection. A borderline result (one weak
# signal) gets a second opinion from Haiku; turn off to save usage.
model_check = true

# Google Calendar (read/write): see README, then `gecko calendar login`.
[calendar.google]
calendars = []   # names or ids to show; empty = all your Google calendars
write_to = ""    # calendar for new events; empty = your primary calendar

# Read-only calendar feeds (.ics). For Outlook: Settings > Calendar >
# Shared calendars > Publish a calendar > copy the ICS link.
# [[calendar.ics]]
# name = "University"
# url = "https://outlook.office365.com/owa/calendar/.../calendar.ics"
"""

# Every desktop capability the MCP server exposes. Toggled from the UI or `gecko caps`.
CAPABILITIES: dict[str, str] = {
    "todo_read": "Read your end-4 to-do list",
    "todo_write": "Add, complete and remove to-dos",
    "notifications_read": "Read recent notifications (treated as untrusted)",
    "notifications_send": "Send desktop notifications",
    "system_info": "Battery, focused window, workspaces, memory, disk",
    "media_control": "See and control the media player",
    "clipboard_read": "Read the current clipboard",
    "clipboard_write": "Copy text to the clipboard (e.g. a hand-off brief)",
    "obsidian_read": "Search and read your Obsidian vault",
    "obsidian_write": "Create notes and append ideas in the vault",
    "calendar_read": "Read events from your calendars",
    "calendar_write": "Add, change and delete events on your Google Calendar",
    "handoff": "Open a full Claude Code session in a terminal",
    "chat_search": "Search your past Gecko chats",
    "weather": "Current weather and the forecast",
    "watchers": "Create and manage background watchers",
    "projects": "Track projects, goals and ideas in your Obsidian vault",
    "recipes": "Create, enable and run recipes; read the inbox",
    "notes": "Read and write your desktop sticky notes",
}
DEFAULT_OFF = {"clipboard_read"}


def load_config() -> dict[str, Any]:
    paths.ensure_dirs()
    if not paths.CONFIG_FILE.exists():
        paths.CONFIG_FILE.write_text(DEFAULT_CONFIG)
    defaults = tomllib.loads(DEFAULT_CONFIG)
    user = tomllib.loads(paths.CONFIG_FILE.read_text())
    return _merge(defaults, user)


def _merge(base: dict, over: dict) -> dict:
    out = dict(base)
    for k, v in over.items():
        out[k] = _merge(base[k], v) if isinstance(v, dict) and isinstance(base.get(k), dict) else v
    return out


def expand(p: str) -> Path:
    return Path(os.path.expanduser(p))


def load_state() -> dict[str, Any]:
    state = {"killed": False, "capabilities": {}}
    try:
        state |= json.loads(paths.STATE_FILE.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        pass
    caps = {name: name not in DEFAULT_OFF for name in CAPABILITIES}
    caps |= {k: bool(v) for k, v in state["capabilities"].items() if k in CAPABILITIES}
    state["capabilities"] = caps
    return state


def save_state(state: dict[str, Any]) -> None:
    paths.ensure_dirs()
    tmp = paths.STATE_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(state, indent=2))
    tmp.replace(paths.STATE_FILE)


def set_killed(on: bool) -> None:
    state = load_state()
    state["killed"] = on
    save_state(state)


def default_model(agent: str = "claude") -> str:
    """The UI-chosen default (state.json) wins over config.toml."""
    return load_state().get("default_models", {}).get(agent) or load_config()["agents"][agent]["model"]


def set_default_model(model: str, agent: str = "claude") -> None:
    state = load_state()
    state.setdefault("default_models", {})[agent] = model
    save_state(state)


def set_capability(name: str, on: bool) -> None:
    if name not in CAPABILITIES:
        raise KeyError(name)
    state = load_state()
    state["capabilities"][name] = on
    save_state(state)

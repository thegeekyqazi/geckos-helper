"""Where Gecko's Helper keeps its files (XDG layout)."""

import os
from pathlib import Path

HOME = Path.home()


def _xdg(var: str, default: str) -> Path:
    return Path(os.environ.get(var) or HOME / default)


CONFIG_DIR = _xdg("XDG_CONFIG_HOME", ".config") / "geckos-helper"
DATA_DIR = _xdg("XDG_DATA_HOME", ".local/share") / "geckos-helper"
STATE_DIR = _xdg("XDG_STATE_HOME", ".local/state") / "geckos-helper"
RUNTIME_DIR = Path(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}")

CONFIG_FILE = CONFIG_DIR / "config.toml"
CLAUDE_SETTINGS = CONFIG_DIR / "claude-settings.json"  # the sidebar profile; yours to edit
STATE_FILE = STATE_DIR / "state.json"  # kill switch + capability toggles
SOCKET = RUNTIME_DIR / "geckos-helper.sock"

# The agent's working directory. Claude Code keys its session history by cwd,
# so running here keeps sidebar chats out of your normal ~/.claude history.
WORKSPACE = DATA_DIR / "workspace"
CHATS_DB = DATA_DIR / "chats.db"
CONTEXT_FILE = DATA_DIR / "context.md"
SYSTEM_PROMPT_FILE = DATA_DIR / "system-prompt.generated.md"
MCP_CONFIG_FILE = DATA_DIR / "mcp.json"
ACTION_LOG = STATE_DIR / "actions.jsonl"

PROFILE_DIR = Path(__file__).parent / "profile"

# end-4 (illogical-impulse) data
END4_TODO = _xdg("XDG_STATE_HOME", ".local/state") / "quickshell/user/todo.json"
END4_NOTIFICATIONS = _xdg("XDG_CACHE_HOME", ".cache") / "quickshell/notifications/notifications.json"


def ensure_dirs() -> None:
    for d in (CONFIG_DIR, DATA_DIR, STATE_DIR, WORKSPACE):
        d.mkdir(parents=True, exist_ok=True)

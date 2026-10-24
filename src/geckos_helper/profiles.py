"""Agent profiles. `unattended` is for anything that runs without you watching
(watchers now, recipes later). Several independent layers keep it read-only:

1. Built-in tools: only WebSearch, plus WebFetch limited to domains you listed.
2. Permission mode dontAsk: anything not pre-allowed is denied, never prompted.
3. Only the gecko MCP server (--strict-mcp-config), started with GECKO_READONLY=1,
   so the server itself refuses every write even if something above slipped.
4. No user settings, hooks or CLAUDE.md (--setting-sources ""), no saved session.
"""

import json

from . import paths
from .config import expand, load_config

READONLY_MCP_CONFIG = paths.DATA_DIR / "mcp-readonly.json"
READ_ONLY_GECKO_TOOLS = [
    "mcp__gecko__calendar_events", "mcp__gecko__calendar_list", "mcp__gecko__system_status",
    "mcp__gecko__todo_list", "mcp__gecko__obsidian_search", "mcp__gecko__obsidian_read",
    "mcp__gecko__obsidian_open_tasks", "mcp__gecko__media_now_playing", "mcp__gecko__chat_search",
    "mcp__gecko__weather", "mcp__gecko__goal_list", "mcp__gecko__watch_list",
]


def write_readonly_mcp_config(python: str) -> None:
    cfg = {"mcpServers": {"gecko": {"command": python, "args": ["-m", "geckos_helper", "mcp"],
                                    "env": {"GECKO_READONLY": "1"}}}}
    READONLY_MCP_CONFIG.write_text(json.dumps(cfg, indent=2))


def unattended_argv(model: str = "haiku", fetch_domains: list[str] | None = None) -> list[str]:
    claude = str(expand(load_config()["agents"]["claude"]["path"]))
    builtin = ["WebSearch"] + (["WebFetch"] if fetch_domains else [])
    allowed = ["WebSearch", *READ_ONLY_GECKO_TOOLS] + [f"WebFetch(domain:{d})" for d in fetch_domains or []]
    return [claude, "-p", "--model", model,
            "--tools", ",".join(builtin), "--allowedTools", ",".join(allowed),
            "--permission-mode", "dontAsk", "--setting-sources", "",
            "--strict-mcp-config", "--mcp-config", str(READONLY_MCP_CONFIG),
            "--no-session-persistence"]

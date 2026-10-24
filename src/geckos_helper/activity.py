"""Audit trail: what Gecko did, who decided, and what's scheduled.

Two append-only logs are merged for the Activity page:
    actions.jsonl   every write a desktop tool made (written by the MCP server)
    activity.jsonl  permission decisions, watcher runs, project updates (written by the daemon)
"""

import json
import time
from typing import Any

from . import paths

ACTIVITY_LOG = paths.STATE_DIR / "activity.jsonl"


def log(kind: str, **data: Any) -> dict:
    paths.ensure_dirs()
    entry = {"ts": time.time(), "kind": kind, **data}
    with ACTIVITY_LOG.open("a") as f:
        f.write(json.dumps(entry) + "\n")
    return entry


def _read(path, limit: int) -> list[dict]:
    try:
        lines = path.read_text().splitlines()[-limit:]
    except FileNotFoundError:
        return []
    out = []
    for line in lines:
        try:
            out.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return out


def recent(limit: int = 200) -> list[dict]:
    actions = [{**a, "kind": "action"} for a in _read(paths.ACTION_LOG, limit)]
    entries = actions + _read(ACTIVITY_LOG, limit)
    entries.sort(key=lambda e: e.get("ts", 0), reverse=True)
    return entries[:limit]

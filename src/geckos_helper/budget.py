"""Usage budget for unattended runs (watchers, recipes, triggers).

Background work shares your Claude subscription with your own chats, so it stops
before it eats into them: a daily cap on runs, and a pause while the 5-hour or
7-day usage windows are nearly used. Set in [budget] in config.toml.
"""

import json
import time
from datetime import datetime

from . import activity
from .config import load_config

UNATTENDED_KINDS = ("watcher", "recipe")


def runs_today() -> int:
    midnight = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0).timestamp()
    try:
        lines = activity.ACTIVITY_LOG.read_text().splitlines()
    except FileNotFoundError:
        return 0
    n = 0
    for line in reversed(lines):
        try:
            e = json.loads(line)
        except json.JSONDecodeError:
            continue
        if e.get("ts", 0) < midnight:
            break
        n += e.get("kind") in UNATTENDED_KINDS
    return n


def check(usage: dict) -> tuple[bool, str]:
    """(allowed, reason). `usage` is the latest subscription utilization (0..1)."""
    b = load_config().get("budget", {})
    if (usage.get("five_hour") or 0) >= b.get("pause_above_five_hour", 0.8):
        return False, f"5-hour usage at {usage['five_hour']:.0%}"
    if (usage.get("seven_day") or 0) >= b.get("pause_above_seven_day", 0.9):
        return False, f"7-day usage at {usage['seven_day']:.0%}"
    cap = b.get("max_unattended_runs_per_day", 40)
    if (n := runs_today()) >= cap:
        return False, f"{n} unattended runs today (cap {cap})"
    return True, ""


def status(usage: dict) -> dict:
    ok, reason = check(usage)
    return {"ok": ok, "reason": reason, "runs_today": runs_today(),
            "cap": load_config().get("budget", {}).get("max_unattended_runs_per_day", 40)}

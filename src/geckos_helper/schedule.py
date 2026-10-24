"""When scheduled things run. Shared by watchers and recipes.

A schedule is a dict with any of:
    every_minutes  15+         run every N minutes (first run right away)
    daily_at       ["07:30"]   run at these times every day
    weekly_at      ["sun 18:00"]
"""

import time
from datetime import datetime, timedelta

DAYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]


def _hm(t: str) -> tuple[int, int]:
    h, m = t.strip().split(":")
    return int(h), int(m)


def validate(s: dict) -> None:
    if not (s.get("every_minutes") or s.get("daily_at") or s.get("weekly_at")):
        raise ValueError("Give every_minutes, daily_at (['07:30']) or weekly_at (['sun 18:00'])")
    if s.get("every_minutes") and s["every_minutes"] < 15:
        raise ValueError("every_minutes must be at least 15")
    for t in s.get("daily_at") or []:
        _hm(t)
    for t in s.get("weekly_at") or []:
        day, hm = t.split()
        if day[:3].lower() not in DAYS:
            raise ValueError(f"weekly_at day must be one of {DAYS}, got {day!r}")
        _hm(hm)


def next_run(s: dict, last: float | None, created: float | None = None, now: float | None = None) -> float | None:
    now = now or time.time()
    if s.get("every_minutes"):
        return last + s["every_minutes"] * 60 if last else now
    ref = last or created or now
    base = datetime.fromtimestamp(max(ref, now - 60))
    candidates = []
    for t in s.get("daily_at") or []:
        h, m = _hm(t)
        at = base.replace(hour=h, minute=m, second=0, microsecond=0)
        while at.timestamp() <= ref:
            at += timedelta(days=1)
        candidates.append(at.timestamp())
    for t in s.get("weekly_at") or []:
        day, hm = t.split()
        h, m = _hm(hm)
        at = base.replace(hour=h, minute=m, second=0, microsecond=0)
        at += timedelta(days=(DAYS.index(day[:3].lower()) - at.weekday()) % 7)
        while at.timestamp() <= ref:
            at += timedelta(days=7)
        candidates.append(at.timestamp())
    return min(candidates) if candidates else None


def describe(s: dict) -> str:
    parts = []
    if m := s.get("every_minutes"):
        parts.append(f"every {m // 60} h" if m % 60 == 0 else f"every {m} min")
    if s.get("daily_at"):
        parts.append("daily at " + ", ".join(s["daily_at"]))
    if s.get("weekly_at"):
        parts.append("weekly " + ", ".join(t.capitalize() for t in s["weekly_at"]))
    return "; ".join(parts) or "manual"

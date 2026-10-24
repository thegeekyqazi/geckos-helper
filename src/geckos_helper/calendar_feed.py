"""A shared calendar file for desktop widgets: ~/.local/state/geckos-helper/calendar.json

    {"updated": 1792850000, "events": [
        {"date": "2026-10-26", "title": "CP363 Database I", "start": "2026-10-26T10:30:00-04:00",
         "end": "...", "all_day": false, "calendar": "Laurier", "color": "#7aa2f7", "location": "..."}]}

One entry per day an event touches (multi-day all-day events repeat), covering the
previous month to two months ahead. The daemon rewrites it every 10 minutes; widgets
watch it (written in place so file watchers keep following it).
"""

import json
import time
from datetime import date, datetime, timedelta

from . import paths
from .desktop import calendar

FEED = paths.STATE_DIR / "calendar.json"


def _days(e: dict) -> list[str]:
    if not e.get("all_day"):
        return [datetime.fromisoformat(e["start"]).astimezone().date().isoformat()]
    start = date.fromisoformat(e["start"][:10])
    end = date.fromisoformat((e.get("end") or e["start"])[:10])  # exclusive for all-day
    n = max(1, (end - start).days)
    return [(start + timedelta(days=i)).isoformat() for i in range(n)]


def write() -> int:
    today = date.today()
    first = (today.replace(day=1) - timedelta(days=1)).replace(day=1)
    evs = calendar.events(days=(today - first).days + 62, start=first)
    out = [{"date": d, **{k: e.get(k) for k in ("title", "start", "end", "all_day", "calendar", "color", "location")}}
           for e in evs for d in _days(e)]
    paths.ensure_dirs()
    FEED.write_text(json.dumps({"updated": time.time(), "errors": calendar.last_errors, "events": out}))
    return len(out)

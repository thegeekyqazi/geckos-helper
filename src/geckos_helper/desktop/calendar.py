"""Read-only calendar from .ics feeds (e.g. a published Outlook calendar).

Feeds are cached for 15 minutes. Google Calendar (read/write) is a later provider.
"""

import time
from datetime import date, datetime, timedelta

import httpx
import icalendar
import recurring_ical_events

from .. import paths
from ..config import load_config

CACHE_SECONDS = 15 * 60
_cache_dir = paths.DATA_DIR / "calendar-cache"


def _feed(name: str, url: str) -> icalendar.Calendar:
    _cache_dir.mkdir(parents=True, exist_ok=True)
    cached = _cache_dir / f"{name}.ics"
    if not cached.exists() or time.time() - cached.stat().st_mtime > CACHE_SECONDS:
        try:
            r = httpx.get(url.replace("webcal://", "https://"), timeout=20, follow_redirects=True)
            r.raise_for_status()
            cached.write_bytes(r.content)
        except httpx.HTTPError:
            if not cached.exists():
                raise
    return icalendar.Calendar.from_ical(cached.read_bytes())


def _iso(v) -> str:
    return v.isoformat(timespec="minutes") if isinstance(v, datetime) else v.isoformat()


def feeds() -> list[dict]:
    return load_config().get("calendar", {}).get("ics", [])


def events(days: int = 7, start: date | None = None) -> list[dict]:
    start = start or date.today()
    end = start + timedelta(days=days)
    out = []
    for feed in feeds():
        cal = _feed(feed["name"], feed["url"])
        for ev in recurring_ical_events.of(cal).between(start, end):
            out.append({
                "calendar": feed["name"],
                "title": str(ev.get("SUMMARY", "")),
                "start": _iso(ev.decoded("DTSTART")),
                "end": _iso(ev.decoded("DTEND")) if ev.get("DTEND") else None,
                "location": str(ev.get("LOCATION", "")) or None,
            })
    out.sort(key=lambda e: e["start"])
    return out

"""Calendars behind one interface. Each provider gives events; some can be written to.

    ICS feeds   read-only (e.g. the published Laurier Outlook calendar), cached 15 min
    Google      read and write, after `gecko calendar login`

A CalDAV provider (DavMail, for Outlook write access) can be added later the same way.
Events carry the calendar's name, id, color and whether it is writable.
"""

import logging
import time
from datetime import date, datetime, timedelta
from typing import Any

import httpx
import icalendar
import recurring_ical_events

from .. import paths
from ..config import load_config
from . import calendar_google as google

log = logging.getLogger("gecko.calendar")

CACHE_SECONDS = 15 * 60
_cache_dir = paths.DATA_DIR / "calendar-cache"
DEFAULT_COLORS = ["#7aa2f7", "#e0af68", "#9ece6a", "#f7768e", "#bb9af7", "#2ac3de"]
last_errors: list[str] = []  # provider failures from the most recent events() call


def _iso(v) -> str:
    return v.isoformat(timespec="minutes") if isinstance(v, datetime) else v.isoformat()


class ICSProvider:
    writable = False

    def __init__(self, name: str, url: str, color: str):
        self.name, self.id, self.url, self.color = name, f"ics:{name}", url, color

    def _feed(self) -> icalendar.Calendar:
        _cache_dir.mkdir(parents=True, exist_ok=True)
        cached = _cache_dir / f"{self.name}.ics"
        if not cached.exists() or time.time() - cached.stat().st_mtime > CACHE_SECONDS:
            try:
                r = httpx.get(self.url.replace("webcal://", "https://"), timeout=20, follow_redirects=True)
                r.raise_for_status()
                cached.write_bytes(r.content)
            except httpx.HTTPError:
                if not cached.exists():
                    raise
        return icalendar.Calendar.from_ical(cached.read_bytes())

    def events(self, start: date, end: date) -> list[dict]:
        out = []
        for ev in recurring_ical_events.of(self._feed()).between(start, end):
            s = ev.decoded("DTSTART")
            out.append({"id": str(ev.get("UID", "")), "title": str(ev.get("SUMMARY", "")), "start": _iso(s),
                        "end": _iso(ev.decoded("DTEND")) if ev.get("DTEND") else None,
                        "location": str(ev.get("LOCATION", "")) or None,
                        "all_day": not isinstance(s, datetime)})
        return out


class GoogleProvider:
    writable = True

    def __init__(self, cal: dict):
        self.name, self.id, self.color, self.primary = cal["name"], cal["id"], cal["color"], cal["primary"]
        self.writable = cal["writable"]

    def events(self, start: date, end: date) -> list[dict]:
        return google.events(self.id, datetime.combine(start, datetime.min.time()),
                             datetime.combine(end, datetime.min.time()))


_google_cals: tuple[float, list[dict]] = (0, [])


def _google_calendars() -> list[dict]:
    global _google_cals
    if time.time() - _google_cals[0] > CACHE_SECONDS:
        _google_cals = (time.time(), google.calendars())
    return _google_cals[1]


def providers() -> list:
    cfg = load_config().get("calendar", {})
    out: list = [ICSProvider(f["name"], f["url"], f.get("color") or DEFAULT_COLORS[i % len(DEFAULT_COLORS)])
                 for i, f in enumerate(cfg.get("ics", []))]
    if google.logged_in():
        wanted = cfg.get("google", {}).get("calendars", [])
        try:
            out += [GoogleProvider(c) for c in _google_calendars()
                    if not wanted or c["id"] in wanted or c["name"] in wanted]
        except Exception as e:
            last_errors.append(f"Google: {e}")
    return out


def configured() -> bool:
    return bool(load_config().get("calendar", {}).get("ics")) or google.logged_in()


def events(days: int = 7, start: date | None = None) -> list[dict]:
    start = start or date.today()
    end = start + timedelta(days=days)
    last_errors.clear()
    out = []
    for p in providers():
        try:
            for e in p.events(start, end):
                out.append({**e, "calendar": p.name, "calendar_id": p.id, "color": p.color, "writable": p.writable})
        except Exception as e:  # one broken feed shouldn't hide the others
            log.warning("calendar %s: %s", p.name, e)
            last_errors.append(f"{p.name}: {e}")
    out.sort(key=lambda e: e["start"])
    return out


def _writable(calendar: str | None) -> GoogleProvider:
    """The calendar to write to: the one named, else [calendar.google] write_to, else primary."""
    target = calendar or load_config().get("calendar", {}).get("google", {}).get("write_to", "")
    cals = [p for p in providers() if p.writable]
    if not cals:
        raise RuntimeError("No writable calendar. Connect Google with `gecko calendar login`.")
    for p in cals:
        if target and target in (p.name, p.id):
            return p
    if target:
        raise ValueError(f"No writable calendar named {target!r}; options: {[p.name for p in cals]}")
    return next((p for p in cals if getattr(p, "primary", False)), cals[0])


def _span(e: dict) -> tuple[datetime, datetime] | None:
    if e.get("all_day") or not e.get("end"):
        return None
    return datetime.fromisoformat(e["start"]).astimezone(), datetime.fromisoformat(e["end"]).astimezone()


def conflicts(start: str, end: str) -> list[dict]:
    """Timed events on any calendar that overlap start..end (ISO datetimes)."""
    s, e = datetime.fromisoformat(start).astimezone(), datetime.fromisoformat(end).astimezone()
    day = s.date()
    out = []
    for ev in events(days=(e.date() - day).days + 1, start=day):
        span = _span(ev)
        if span and span[0] < e and s < span[1]:
            out.append({k: ev[k] for k in ("title", "start", "end", "calendar")})
    return out


def add_event(title: str, start: str, end: str, location: str = "", description: str = "",
              calendar: str | None = None) -> dict[str, Any]:
    p = _writable(calendar)
    clashes = conflicts(start, end) if len(start) > 10 else []
    created = google.add(p.id, title, start, end, location, description)
    return {"created": created, "calendar": p.name, "conflicts": clashes}


def update_event(event_id: str, calendar: str | None = None, **fields: str) -> dict:
    p = _writable(calendar)
    return {**google.update(p.id, event_id, **fields), "calendar": p.name}


def delete_event(event_id: str, calendar: str | None = None) -> str:
    p = _writable(calendar)
    google.delete(p.id, event_id)
    return f"deleted from {p.name}"


def calendars() -> list[dict]:
    return [{"name": p.name, "id": p.id, "writable": p.writable, "color": p.color} for p in providers()]

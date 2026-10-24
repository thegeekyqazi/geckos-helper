"""Event triggers that start recipes. Polled by the daemon every 30 seconds.

    battery_below      value = 15            on battery and below 15%
    file_added         value = "~/Downloads" a new file appears in the folder
    event_soon         value = 15            a calendar event starts within 15 minutes
    notification_from  value = "Discord"     a new notification from that app

A trigger only ever starts a read-only recipe; what it passes along (file names,
notification text, event titles) is treated as untrusted. Each recipe waits at
least COOLDOWN between trigger runs.
"""

import json
import logging
import time
from datetime import datetime, timedelta

from . import paths, recipes
from .config import expand
from .desktop import calendar, system

log = logging.getLogger("gecko.triggers")
COOLDOWN = 10 * 60
IGNORED_SUFFIXES = (".part", ".crdownload", ".tmp", ".download")


class Triggers:
    def __init__(self) -> None:
        self.battery_low = False
        self.seen_files: dict[str, set[str]] = {}
        self.fired_events: set[str] = set()
        self.last_notification = time.time() * 1000  # only notifications after startup
        self.last_calendar_check = 0.0
        self.upcoming: list[dict] = []
        self.last_fired: dict[str, float] = {}

    def poll(self) -> list[tuple[dict, str]]:
        """(recipe, why) pairs to run now."""
        active = [(r, t) for r in recipes.load() if r.get("enabled") for t in r.get("triggers", [])]
        if not active:
            return []
        fired = []
        for r, t in active:
            try:
                if why := getattr(self, f"_{t['type']}")(t.get("value")):
                    fired.append((r, why))
            except AttributeError:
                log.warning("recipe %s: unknown trigger %s", r["id"], t.get("type"))
            except Exception:
                log.exception("trigger %s", t)
        self._after_poll()
        out = []
        for r, why in fired:
            if time.time() - self.last_fired.get(r["id"], 0) >= COOLDOWN:
                self.last_fired[r["id"]] = time.time()
                out.append((r, why))
        return out

    def _battery_below(self, value) -> str | None:
        bat = system.battery()
        if not bat:
            return None
        low = bat["status"] == "Discharging" and bat["percent"] < int(value or 15)
        fire = low and not self.battery_low
        if low or bat["status"] != "Discharging" or bat["percent"] > int(value or 15) + 5:
            self.battery_low = low
        return f"Battery is at {bat['percent']}% and discharging." if fire else None

    def _file_added(self, value) -> str | None:
        folder = expand(value or "~/Downloads")
        names = {p.name for p in folder.iterdir() if not p.name.startswith(".")
                 and not p.name.endswith(IGNORED_SUFFIXES)} if folder.is_dir() else set()
        key = str(folder)
        new = names - self.seen_files[key] if key in self.seen_files else set()
        self.seen_files[key] = names
        return f"New file(s) in {folder}: " + ", ".join(sorted(new)[:10]) if new else None

    def _event_soon(self, value) -> str | None:
        minutes = int(value or 15)
        if time.time() - self.last_calendar_check > 300:
            self.last_calendar_check = time.time()
            self.upcoming = [e for e in calendar.events(days=2) if not e.get("all_day")]
        now = datetime.now().astimezone()
        for e in self.upcoming:
            start = datetime.fromisoformat(e["start"]).astimezone()
            key = f"{e['calendar']}:{e['id']}:{e['start']}"
            if now < start <= now + timedelta(minutes=minutes) and key not in self.fired_events:
                self.fired_events.add(key)
                where = f" at {e['location']}" if e.get("location") else ""
                return f"Event starting {start:%H:%M}: {e['title']}{where} ({e['calendar']} calendar)."
        return None

    def _notification_from(self, value) -> str | None:
        try:
            items = json.loads(paths.END4_NOTIFICATIONS.read_text())
        except (FileNotFoundError, json.JSONDecodeError):
            return None
        new = [n for n in items if n.get("time", 0) > self.last_notification
               and str(value or "").lower() in (n.get("appName") or "").lower()]
        self._newest_notification = max([n.get("time", 0) for n in items] + [self.last_notification])
        if not new:
            return None
        return "New notification(s): " + " | ".join(f"{n.get('appName')}: {n.get('summary')} {n.get('body', '')}"[:300]
                                                     for n in new[:5])

    def _after_poll(self) -> None:
        if hasattr(self, "_newest_notification"):
            self.last_notification = self._newest_notification

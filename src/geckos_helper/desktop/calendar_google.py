"""Google Calendar provider (read and write) over the Calendar REST API.

Setup: create an OAuth "Desktop app" client in your own Google Cloud project, save
its JSON as ~/.config/geckos-helper/google-client.json, then run `gecko calendar login`.
The token is kept in ~/.local/state/geckos-helper/google-token.json (mode 600).
"""

import os
from urllib.parse import quote
from datetime import date, datetime
from typing import Any

import httpx
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials

from .. import paths

CLIENT_FILE = paths.CONFIG_DIR / "google-client.json"
TOKEN_FILE = paths.STATE_DIR / "google-token.json"
SCOPES = [
    "https://www.googleapis.com/auth/calendar.events",
    "https://www.googleapis.com/auth/calendar.calendarlist.readonly",
]
API = "https://www.googleapis.com/calendar/v3"


def login() -> None:
    """Interactive browser sign-in; stores a refresh token."""
    from google_auth_oauthlib.flow import InstalledAppFlow

    if not CLIENT_FILE.exists():
        raise FileNotFoundError(f"Save your OAuth client JSON as {CLIENT_FILE} first")
    creds = InstalledAppFlow.from_client_secrets_file(str(CLIENT_FILE), SCOPES).run_local_server(port=0)
    _save(creds)


def _save(creds: Credentials) -> None:
    paths.ensure_dirs()
    TOKEN_FILE.write_text(creds.to_json())
    os.chmod(TOKEN_FILE, 0o600)


def logged_in() -> bool:
    return TOKEN_FILE.exists()


def _token() -> str:
    creds = Credentials.from_authorized_user_file(str(TOKEN_FILE), SCOPES)
    if not creds.valid:
        creds.refresh(Request())
        _save(creds)
    return creds.token


def _api(method: str, path: str, **kw: Any) -> Any:
    r = httpx.request(method, API + path, headers={"Authorization": f"Bearer {_token()}"}, timeout=20, **kw)
    r.raise_for_status()
    return r.json() if r.content else None


def _cid(calendar_id: str) -> str:
    return quote(calendar_id, safe="")  # ids like "en.canadian#holiday@group…" contain '#'


def calendars() -> list[dict]:
    items = _api("GET", "/users/me/calendarList")["items"]
    return [{"id": c["id"], "color": c.get("backgroundColor"),
             "name": c.get("summaryOverride") or ("Google" if c.get("primary") else c["summary"]),
             "primary": c.get("primary", False), "writable": c.get("accessRole") in ("owner", "writer")}
            for c in items]


def _when(v: dict) -> str:
    return v.get("dateTime") or v.get("date")


def events(calendar_id: str, start: datetime, end: datetime) -> list[dict]:
    data = _api("GET", f"/calendars/{_cid(calendar_id)}/events", params={
        "timeMin": start.astimezone().isoformat(), "timeMax": end.astimezone().isoformat(),
        "singleEvents": "true", "orderBy": "startTime", "maxResults": 250})
    return [{"id": e["id"], "title": e.get("summary", "(no title)"), "start": _when(e["start"]),
             "end": _when(e["end"]), "location": e.get("location"), "all_day": "date" in e["start"],
             "description": e.get("description")}
            for e in data.get("items", []) if e.get("status") != "cancelled"]


def _time(value: str) -> dict:
    """'2026-10-27' -> all-day; ISO datetime -> timed (local timezone if none given)."""
    if len(value) == 10:
        return {"date": date.fromisoformat(value).isoformat()}
    dt = datetime.fromisoformat(value)
    return {"dateTime": (dt if dt.tzinfo else dt.astimezone()).isoformat()}


def add(calendar_id: str, title: str, start: str, end: str, location: str = "", description: str = "") -> dict:
    body = {"summary": title, "start": _time(start), "end": _time(end)}
    if location:
        body["location"] = location
    if description:
        body["description"] = description
    e = _api("POST", f"/calendars/{_cid(calendar_id)}/events", json=body)
    return {"id": e["id"], "link": e.get("htmlLink")}


def update(calendar_id: str, event_id: str, **fields: str) -> dict:
    body: dict[str, Any] = {}
    for key, api_key in (("title", "summary"), ("location", "location"), ("description", "description")):
        if fields.get(key):
            body[api_key] = fields[key]
    for key in ("start", "end"):
        if fields.get(key):
            body[key] = _time(fields[key])
    e = _api("PATCH", f"/calendars/{_cid(calendar_id)}/events/{event_id}", json=body)
    return {"id": e["id"], "link": e.get("htmlLink")}


def delete(calendar_id: str, event_id: str) -> None:
    _api("DELETE", f"/calendars/{_cid(calendar_id)}/events/{event_id}")

"""Desktop sticky notes, shared with the Notes widget of the desktop widgets
(~/.local/state/quickshell/user/desktopnotes.txt: a JSON list of
{id, content, attachments, createdAt}).
"""

import json
import random
import time

from .. import paths

NOTES_FILE = paths.HOME / ".local/state/quickshell/user/desktopnotes.txt"


def _load() -> list[dict]:
    try:
        return json.loads(NOTES_FILE.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return []


def _save(items: list[dict]) -> None:
    NOTES_FILE.parent.mkdir(parents=True, exist_ok=True)
    NOTES_FILE.write_text(json.dumps(items))  # in place, so the widget's watcher sees it


def list_notes() -> list[dict]:
    return [{"id": n["id"], "content": n.get("content", ""), "created": n.get("createdAt")} for n in _load()]


def add(content: str) -> dict:
    now = int(time.time() * 1000)
    note = {"id": f"{now}-{random.randint(0, 9999)}", "content": content, "attachments": [], "createdAt": now}
    _save(_load() + [note])
    return {"id": note["id"], "content": content}


def update(note_id: str, content: str) -> dict:
    items = _load()
    for n in items:
        if n["id"] == note_id:
            n["content"] = content
            _save(items)
            return {"id": note_id, "content": content}
    raise KeyError(f"No note {note_id}")


def delete(note_id: str) -> str:
    items = _load()
    kept = [n for n in items if n["id"] != note_id]
    if len(kept) == len(items):
        raise KeyError(f"No note {note_id}")
    _save(kept)
    return "deleted"

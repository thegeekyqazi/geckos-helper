"""Chat history: our own index of chats plus a compact transcript for the UI.

The agent keeps its own full session (Claude: ~/.claude/projects/<workspace>/);
we store the agent's session id so a chat can be resumed.
"""

import json
import sqlite3
import time
import uuid
from typing import Any

from . import paths

SCHEMA = """
CREATE TABLE IF NOT EXISTS chats (
    id TEXT PRIMARY KEY, title TEXT, agent TEXT, session_id TEXT,
    cwd TEXT, created REAL, updated REAL, model TEXT
);
CREATE TABLE IF NOT EXISTS entries (
    chat_id TEXT, ts REAL, kind TEXT, data TEXT
);
CREATE INDEX IF NOT EXISTS entries_chat ON entries(chat_id, ts);
"""

# Events worth keeping in the transcript (streaming chunks are not).
TRANSCRIPT_KINDS = {"user_message", "agent_message", "tool_call", "tool_call_update", "permission_request",
                    "turn_end", "error"}


class Store:
    def __init__(self) -> None:
        paths.ensure_dirs()
        self.db = sqlite3.connect(paths.CHATS_DB)
        self.db.row_factory = sqlite3.Row
        self.db.executescript(SCHEMA)
        cols = {r["name"] for r in self.db.execute("PRAGMA table_info(chats)")}
        if "model" not in cols:  # added after 0.1
            self.db.execute("ALTER TABLE chats ADD COLUMN model TEXT")

    def create(self, agent: str, model: str, title: str = "New chat", cwd: str | None = None) -> dict:
        now = time.time()
        chat = {"id": uuid.uuid4().hex[:12], "title": title, "agent": agent, "session_id": None,
                "cwd": cwd, "created": now, "updated": now, "model": model}
        self.db.execute("INSERT INTO chats (id, title, agent, session_id, cwd, created, updated, model) "
                        "VALUES (:id,:title,:agent,:session_id,:cwd,:created,:updated,:model)", chat)
        self.db.commit()
        return chat

    def get(self, chat_id: str) -> dict | None:
        row = self.db.execute("SELECT * FROM chats WHERE id=?", (chat_id,)).fetchone()
        return dict(row) if row else None

    def list(self, limit: int = 50) -> list[dict]:
        rows = self.db.execute("SELECT * FROM chats ORDER BY updated DESC LIMIT ?", (limit,))
        return [dict(r) for r in rows]

    def update(self, chat_id: str, **fields: Any) -> None:
        fields["updated"] = time.time()
        cols = ", ".join(f"{k}=:{k}" for k in fields)
        self.db.execute(f"UPDATE chats SET {cols} WHERE id=:id", {**fields, "id": chat_id})
        self.db.commit()

    def delete(self, chat_id: str) -> None:
        self.db.execute("DELETE FROM chats WHERE id=?", (chat_id,))
        self.db.execute("DELETE FROM entries WHERE chat_id=?", (chat_id,))
        self.db.commit()

    def append(self, chat_id: str, kind: str, data: dict) -> None:
        if kind not in TRANSCRIPT_KINDS:
            return
        self.db.execute("INSERT INTO entries VALUES (?,?,?,?)", (chat_id, time.time(), kind, json.dumps(data)))
        self.db.commit()

    def transcript(self, chat_id: str) -> list[dict]:
        rows = self.db.execute("SELECT ts, kind, data FROM entries WHERE chat_id=? ORDER BY ts", (chat_id,))
        return [{"ts": r["ts"], "kind": r["kind"], **json.loads(r["data"])} for r in rows]

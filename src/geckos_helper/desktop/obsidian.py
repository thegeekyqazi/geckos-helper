"""Obsidian vault access through the markdown files themselves (no running app needed).

Tasks use the Obsidian Tasks plugin format, which the vault already has installed:
    - [ ] Write report 📅 2026-10-30 ⏫
"""

import re
from datetime import date
from pathlib import Path

from ..config import expand, load_config

TASK_RE = re.compile(r"^\s*[-*] \[(?P<state>.)\] (?P<text>.+)$")
DUE_RE = re.compile(r"📅 (\d{4}-\d{2}-\d{2})")


def vault() -> Path:
    v = expand(load_config()["desktop"]["obsidian_vault"])
    if not (v / ".obsidian").is_dir():
        raise FileNotFoundError(f"No Obsidian vault at {v}")
    return v


def _resolve(rel: str) -> Path:
    root = vault().resolve()
    p = (root / rel).resolve()
    if root not in p.parents and p != root:
        raise ValueError("Path is outside the vault")
    return p


def _notes():
    root = vault()
    for p in root.rglob("*.md"):
        if not any(part.startswith(".") for part in p.relative_to(root).parts):
            yield p


def search(query: str, limit: int = 20) -> list[dict]:
    """Case-insensitive search over note titles and contents."""
    q = query.lower()
    root = vault()
    hits = []
    for p in _notes():
        text = p.read_text(errors="replace")
        idx = text.lower().find(q)
        if q in p.stem.lower() or idx >= 0:
            snippet = text[max(0, idx - 80): idx + 160].replace("\n", " ") if idx >= 0 else text[:160]
            hits.append({"path": str(p.relative_to(root)), "snippet": snippet.strip()})
            if len(hits) >= limit:
                break
    return hits


def read(rel: str) -> str:
    return _resolve(rel).read_text(errors="replace")


def write(rel: str, content: str, overwrite: bool = False) -> str:
    p = _resolve(rel if rel.endswith(".md") else rel + ".md")
    if p.exists() and not overwrite:
        raise FileExistsError(f"{rel} exists; pass overwrite=true or use append")
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content)
    return str(p.relative_to(vault()))


def append(rel: str, content: str) -> str:
    p = _resolve(rel if rel.endswith(".md") else rel + ".md")
    p.parent.mkdir(parents=True, exist_ok=True)
    existing = p.read_text() if p.exists() else ""
    sep = "" if not existing or existing.endswith("\n") else "\n"
    p.write_text(existing + sep + content.rstrip("\n") + "\n")
    return str(p.relative_to(vault()))


def capture_idea(text: str, tags: list[str] | None = None) -> str:
    inbox = load_config()["desktop"]["obsidian_inbox"]
    tag_str = " ".join(f"#{t.lstrip('#')}" for t in tags or [])
    return append(inbox, f"- {date.today().isoformat()} {text} {tag_str}".rstrip())


def open_tasks(limit: int = 100) -> list[dict]:
    root = vault()
    tasks = []
    for p in _notes():
        for n, line in enumerate(p.read_text(errors="replace").splitlines(), 1):
            m = TASK_RE.match(line)
            if m and m["state"] == " ":
                due = DUE_RE.search(m["text"])
                tasks.append({"note": str(p.relative_to(root)), "line": n,
                              "task": m["text"].strip(), "due": due[1] if due else None})
    tasks.sort(key=lambda t: (t["due"] is None, t["due"] or ""))
    return tasks[:limit]

"""Gecko's long-term memory is Claude Code's own auto-memory for the Gecko workspace:
markdown files in ~/.claude/projects/<workspace>/memory/ with a MEMORY.md index,
which Claude loads into every session and maintains itself. This module only lets
the panel show, open and delete those files.
"""

import re
from pathlib import Path

from . import paths


def memory_dir() -> Path:
    slug = re.sub(r"[/.]", "-", str(paths.WORKSPACE))
    return paths.HOME / ".claude/projects" / slug / "memory"


def _frontmatter(text: str) -> dict[str, str]:
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if not m:
        return {}
    return dict(re.findall(r"^(\w+):\s*\"?(.*?)\"?\s*$", m[1], re.M))


def list_memories() -> list[dict]:
    d = memory_dir()
    out = []
    for p in sorted(d.glob("*.md")) if d.is_dir() else []:
        if p.name == "MEMORY.md":
            continue
        text = p.read_text(errors="replace")
        fm = _frontmatter(text)
        body = re.sub(r"^---\n.*?\n---\n", "", text, count=1, flags=re.S).strip()
        out.append({"file": p.name, "name": fm.get("name", p.stem), "description": fm.get("description", ""),
                    "type": fm.get("type", ""), "body": body, "mtime": p.stat().st_mtime})
    return out


def delete(file: str) -> None:
    p = memory_dir() / Path(file).name  # name only: never leave the memory dir
    p.unlink()
    index = memory_dir() / "MEMORY.md"
    if index.exists():  # drop its line from the index too
        lines = [l for l in index.read_text().splitlines() if f"({p.name})" not in l]
        index.write_text("\n".join(lines) + "\n")

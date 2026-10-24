"""Projects and goals as Obsidian notes, in the vault's own style.

A tracked note has frontmatter (for Gecko and Dataview) and the body lines the
user already uses (**Category:** / **Status:**), a 🎯 Goal, a 📋 Plan of
Obsidian Tasks checkboxes and a 📈 Progress Log:

    ---
    type: project            # or goal
    status: active           # idea | active | on-hold | done
    category: 💻 Tech & Projects
    created: 2026-10-24
    due: 2026-12-01
    tags: [project, active]
    ---
    # 📦 Inventory Prediction
    **Category:** 💻 Tech & Projects
    **Status:** 🟡 Active
    ...

New ones go in [desktop] projects_folder (default "Projects"); existing notes can
be adopted where they are. Ideas live as a list in the ideas note
([desktop] obsidian_inbox, default "Projects/Ideas.md"). "Projects Hub.md" in the
projects folder gets a progress table regenerated after every change.
"""

import re
from datetime import date
from pathlib import Path

from ..config import load_config
from .obsidian import TASK_RE, vault

STATUSES = {"idea": "⬜ Idea", "active": "🟡 Active", "on-hold": "⏸️ On hold", "done": "✅ Done"}
DUE_RE = re.compile(r"📅 (\d{4}-\d{2}-\d{2})")
HUB_BEGIN, HUB_END = "<!-- gecko:projects -->", "<!-- /gecko:projects -->"
FRONT_RE = re.compile(r"^---\n(.*?)\n---\n", re.S)


def folder() -> Path:
    return vault() / load_config()["desktop"].get("projects_folder", "Projects")


def ideas_note() -> Path:
    return vault() / load_config()["desktop"]["obsidian_inbox"]


def _slug(title: str) -> str:
    return re.sub(r'[\\/:*?"<>|#^\[\]]', "", title).strip()[:80] or "Project"


def _front(text: str) -> dict[str, str]:
    m = FRONT_RE.match(text)
    return dict(re.findall(r"^(\w+):[ \t]*(.*?)[ \t]*$", m[1], re.M)) if m else {}


def _set_front(text: str, fields: dict[str, str]) -> str:
    m = FRONT_RE.match(text)
    lines = m[1].split("\n") if m else []
    keys = [l.split(":", 1)[0] for l in lines]
    for k, v in fields.items():
        if k in keys:
            lines[keys.index(k)] = f"{k}: {v}"
        else:
            lines.append(f"{k}: {v}")
    body = text[m.end():] if m else text
    return "---\n" + "\n".join(lines) + "\n---\n" + body


def _tracked_notes() -> list[Path]:
    """Notes in the projects folder plus any note marked type: project/goal elsewhere."""
    root = vault()
    found = []
    for p in root.rglob("*.md"):
        rel = p.relative_to(root)
        if any(part.startswith(".") for part in rel.parts) or p.name == "Projects Hub.md":
            continue
        if p == ideas_note():
            continue
        head = p.read_text(errors="replace")[:600]
        if _front(head).get("type") in ("project", "goal"):
            found.append(p)
    return sorted(found)


def summary(p: Path) -> dict:
    text = p.read_text(errors="replace")
    fm = _front(text)
    tasks = [m for line in text.splitlines() if (m := TASK_RE.match(line))]
    open_tasks = [t["text"].strip() for t in tasks if t["state"] == " "]
    open_tasks.sort(key=lambda t: (DUE_RE.search(t) is None, DUE_RE.search(t)[1] if DUE_RE.search(t) else ""))
    log = re.findall(r"^- (\d{4}-\d{2}-\d{2}):", text.split("## 📈 Progress Log", 1)[-1], re.M) \
        if "## 📈 Progress Log" in text else []
    return {"title": p.stem, "file": str(p.relative_to(vault())), "kind": fm.get("type", "project"),
            "status": fm.get("status", "idea"), "category": fm.get("category", ""), "due": fm.get("due") or None,
            "done": sum(t["state"].lower() == "x" for t in tasks), "total": len(tasks),
            "next": open_tasks[0] if open_tasks else "", "open_tasks": open_tasks[:10],
            "last_update": max(log) if log else fm.get("created")}


def list_projects(status: str = "", kind: str = "") -> list[dict]:
    out = [summary(p) for p in _tracked_notes()]
    return [s for s in out if (not status or s["status"] == status) and (not kind or s["kind"] == kind)]


def _find(name: str) -> Path:
    notes = _tracked_notes()
    for p in notes:
        if p.stem.lower() == name.removesuffix(".md").lower() or str(p.relative_to(vault())) == name:
            return p
    for p in notes:
        if name.lower() in p.stem.lower():
            return p
    raise FileNotFoundError(f"No tracked project or goal named {name!r}")


def _task(step: str) -> str:
    return step if step.lstrip().startswith("- [") else f"- [ ] {step}"


def create(title: str, goal: str, tasks: list[str], category: str = "💻 Tech & Projects",
           status: str = "active", due: str = "", kind: str = "project", icon: str = "📦") -> str:
    if status not in STATUSES:
        raise ValueError(f"status must be one of {list(STATUSES)}")
    folder().mkdir(parents=True, exist_ok=True)
    p = folder() / f"{_slug(title)}.md"
    if p.exists():
        raise FileExistsError(f"{p.name} exists; use project_update")
    today = date.today().isoformat()
    front = {"type": kind, "status": status, "category": category, "created": today,
             "due": due, "tags": f"[{kind}, {status}]"}
    body = (f"# {icon} {title}\n\n**Category:** {category}  \n**Status:** {STATUSES[status]}\n\n---\n\n"
            f"## 🎯 Goal\n{goal.strip()}\n\n## 📋 Plan\n" + "\n".join(_task(t) for t in tasks) +
            "\n\n## 💡 Ideas & Notes\n> Brain dump here\n\n## 📈 Progress Log\n"
            f"- {today}: Created\n\n---\n\n*Back to [[Projects Hub]]*\n")
    p.write_text(_set_front("", front).replace("---\n---\n", "---\n---\n", 1) + body)
    rebuild_hub()
    return str(p.relative_to(vault()))


def adopt(note: str, kind: str = "project", status: str = "active", category: str = "") -> dict:
    """Start tracking an existing note where it is (adds frontmatter and a progress log)."""
    p = vault() / note if (vault() / note).exists() else next(
        (q for q in vault().rglob("*.md") if q.stem.lower() == note.removesuffix(".md").lower()), None)
    if not p:
        raise FileNotFoundError(f"No note {note!r}")
    text = p.read_text()
    cat = category or (re.search(r"\*\*Category:\*\*\s*(.+?)\s*$", text, re.M) or [None, ""])[1]
    text = _set_front(text, {"type": kind, "status": status, "category": cat,
                             "created": _front(text).get("created", date.today().isoformat()),
                             "tags": f"[{kind}, {status}]"})
    text = _sync_status_line(text, status)
    if "## 📈 Progress Log" not in text:
        text = _insert_before_footer(text, f"## 📈 Progress Log\n- {date.today().isoformat()}: Tracked by Gecko\n")
    p.write_text(text)
    rebuild_hub()
    return summary(p)


FOOTER_RE = re.compile(r"\n---\n+\*Back to \[\[[^\]]+\]\]\*\s*$")


def _insert_before_footer(text: str, section: str) -> str:
    """Add a section above the note's "*Back to [[Hub]]*" footer, or at the end."""
    m = FOOTER_RE.search(text)
    if m:
        return text[:m.start()].rstrip("\n") + "\n\n" + section.rstrip("\n") + "\n" + text[m.start():]
    return text.rstrip("\n") + "\n\n" + section


def _sync_status_line(text: str, status: str) -> str:
    return re.sub(r"(\*\*Status:\*\*\s*).*$", rf"\g<1>{STATUSES[status]}", text, count=1, flags=re.M)


def update(name: str, note: str = "", complete_task: str = "", add_tasks: list[str] | None = None,
           status: str = "", due: str = "") -> dict:
    p = _find(name)
    text = p.read_text()
    today = date.today().isoformat()
    if complete_task:
        lines = text.split("\n")
        for i, line in enumerate(lines):
            m = TASK_RE.match(line)
            if m and m["state"] == " " and complete_task.lower() in m["text"].lower():
                lines[i] = line.replace("- [ ]", "- [x]", 1) + f" ✅ {today}"
                break
        else:
            raise ValueError(f"No open task matching {complete_task!r}")
        text = "\n".join(lines)
        note = note or f"Done: {complete_task}"
    if add_tasks:
        new = "\n".join(_task(t) for t in add_tasks)
        plan = re.search(r"^## 📋[^\n]*\n", text, re.M)  # "📋 Plan", "📋 First Steps"…
        if plan:
            nxt = re.search(r"^(## |---$)", text[plan.end():], re.M)
            end = plan.end() + (nxt.start() if nxt else len(text) - plan.end())
            text = text[:plan.end()] + text[plan.end():end].rstrip("\n") + "\n" + new + "\n\n" + text[end:].lstrip("\n")
        else:
            text = _insert_before_footer(text, "## 📋 Plan\n" + new + "\n")
    if status:
        if status not in STATUSES:
            raise ValueError(f"status must be one of {list(STATUSES)}")
        kind = _front(text).get("type", "project")
        text = _sync_status_line(_set_front(text, {"status": status, "tags": f"[{kind}, {status}]"}), status)
        note = note or f"Status → {STATUSES[status]}"
    if due:
        text = _set_front(text, {"due": due})
    if note:
        if "## 📈 Progress Log" not in text:
            text = _insert_before_footer(text, "## 📈 Progress Log\n")
        head, _, rest = text.partition("## 📈 Progress Log\n")
        log, sep, tail = rest.partition("\n---")
        text = head + "## 📈 Progress Log\n" + log.rstrip("\n") + f"\n- {today}: {note}\n" + (sep + tail if sep else "")
    p.write_text(text)
    rebuild_hub()
    return summary(p)


def next_actions(limit: int = 10) -> list[dict]:
    """Open plan tasks from active projects and goals, due-dated ones first."""
    items = []
    for s in list_projects(status="active"):
        for t in s["open_tasks"]:
            due = DUE_RE.search(t)
            items.append({"project": s["title"], "task": t, "due": due[1] if due else None})
    items.sort(key=lambda i: (i["due"] is None, i["due"] or ""))
    return items[:limit]


# --- ideas ---------------------------------------------------------------------

IDEA_RE = re.compile(r"^- (?:(\d{4}-\d{2}-\d{2}) )?(.+)$")


def ideas() -> list[dict]:
    p = ideas_note()
    if not p.exists():
        return []
    out = []
    for i, line in enumerate(p.read_text().splitlines()):
        m = IDEA_RE.match(line)
        if m and m[2].strip() and not line.startswith("- [") and not m[2].startswith("~~"):
            out.append({"line": i, "date": m[1], "idea": m[2].strip()})
    return out


def promote(idea_line: int, title: str, goal: str, tasks: list[str], **kw) -> str:
    """Create a project from an idea and strike the idea through with a link to it."""
    path = create(title, goal, tasks, **kw)
    p = ideas_note()
    lines = p.read_text().splitlines()
    m = IDEA_RE.match(lines[idea_line])
    if m:
        lines[idea_line] = f"- {m[1] + ' ' if m[1] else ''}~~{m[2].strip()}~~ → [[{Path(path).stem}]]"
        p.write_text("\n".join(lines) + "\n")
    return path


# --- hub -----------------------------------------------------------------------

def rebuild_hub() -> None:
    hub = folder() / "Projects Hub.md"
    rows = ["| Project | Category | Status | Progress | Next |", "|---|---|---|---|---|"]
    order = {"active": 0, "idea": 1, "on-hold": 2, "done": 3}
    for s in sorted(list_projects(), key=lambda s: (order.get(s["status"], 9), s["title"].lower())):
        prog = f"{s['done']}/{s['total']}" if s["total"] else "–"
        nxt = DUE_RE.sub("", s["next"]).strip()[:60]
        rows.append(f"| [[{s['title']}]] | {s['category']} | {STATUSES.get(s['status'], s['status'])} | {prog} | {nxt} |")
    table = f"{HUB_BEGIN}\n" + "\n".join(rows) + f"\n{HUB_END}"
    if hub.exists() and HUB_BEGIN in hub.read_text():
        text = hub.read_text()
        start, end = text.index(HUB_BEGIN), text.index(HUB_END) + len(HUB_END)
        hub.write_text(text[:start] + table + text[end:])
    else:
        folder().mkdir(parents=True, exist_ok=True)
        hub.write_text("# 🗂️ Projects Hub\n\n> Kept up to date by Gecko's Helper. Edit the project notes, not the "
                       f"table.\n\n## 📊 Progress Tracker\n\n{table}\n\n## 💡 Ideas\n![[Ideas]]\n")

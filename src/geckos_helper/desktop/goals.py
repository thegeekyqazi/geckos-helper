"""Goals as Obsidian notes: a goal, why it matters, a plan of steps and a progress log.

    <vault>/Gecko/Goals/Pass CP312.md

    ---
    goal: Pass CP312
    status: active
    deadline: 2026-12-15
    created: 2026-10-24
    ---
    ## Why
    ...
    ## Plan
    - [ ] Review recursion 📅 2026-10-25
    - [x] Finish Quiz 3 ✅ 2026-10-30
    ## Progress
    - 2026-10-24: Plan created

Steps use the Obsidian Tasks format, so they also show up in the vault's task views
and in obsidian_open_tasks.
"""

import re
from datetime import date

from .obsidian import TASK_RE, vault

GOALS_DIR = "Gecko/Goals"


def _slug(title: str) -> str:
    return re.sub(r'[\\/:*?"<>|#^\[\]]', "", title).strip()[:80] or "Goal"


def _path(title_or_file: str):
    root = vault() / GOALS_DIR
    name = title_or_file.removesuffix(".md")
    exact = root / f"{_slug(name)}.md"
    if exact.exists():
        return exact
    for p in root.glob("*.md"):  # loose match on the title
        if name.lower() in p.stem.lower():
            return p
    raise FileNotFoundError(f"No goal named {title_or_file!r}")


def _step_line(step: str) -> str:
    return step if step.lstrip().startswith("- [") else f"- [ ] {step}"


def create(title: str, why: str, steps: list[str], deadline: str | None = None) -> str:
    root = vault() / GOALS_DIR
    root.mkdir(parents=True, exist_ok=True)
    p = root / f"{_slug(title)}.md"
    if p.exists():
        raise FileExistsError(f"Goal {title!r} already exists; use goal_update")
    today = date.today().isoformat()
    front = [f"goal: {title}", "status: active", f"created: {today}"] + ([f"deadline: {deadline}"] if deadline else [])
    p.write_text("---\n" + "\n".join(front) + "\n---\n\n## Why\n" + why.strip() + "\n\n## Plan\n"
                 + "\n".join(_step_line(s) for s in steps) + f"\n\n## Progress\n- {today}: Plan created\n")
    return str(p.relative_to(vault()))


def summary(p) -> dict:
    text = p.read_text(errors="replace")
    fm = dict(re.findall(r"^(\w+):\s*(.*)$", text.split("---")[1], re.M)) if text.startswith("---") else {}
    plan = text.split("## Plan", 1)[1].split("\n## ", 1)[0] if "## Plan" in text else ""
    steps = [m for line in plan.splitlines() if (m := TASK_RE.match(line))]
    done = [s for s in steps if s["state"].lower() == "x"]
    nxt = next((s["text"] for s in steps if s["state"] == " "), "")
    return {"title": fm.get("goal", p.stem), "file": str(p.relative_to(vault())), "status": fm.get("status", "active"),
            "deadline": fm.get("deadline"), "done": len(done), "total": len(steps), "next": nxt}


def list_goals(include_done: bool = False) -> list[dict]:
    root = vault() / GOALS_DIR
    goals = [summary(p) for p in sorted(root.glob("*.md"))] if root.is_dir() else []
    return [g for g in goals if include_done or g["status"] != "done"]


def update(goal: str, note: str = "", complete_step: str = "", add_steps: list[str] | None = None,
           status: str = "") -> dict:
    p = _path(goal)
    text = p.read_text()
    today = date.today().isoformat()
    if complete_step:
        lines = text.split("\n")
        for i, line in enumerate(lines):
            m = TASK_RE.match(line)
            if m and m["state"] == " " and complete_step.lower() in m["text"].lower():
                lines[i] = line.replace("- [ ]", "- [x]", 1) + f" ✅ {today}"
                break
        else:
            raise ValueError(f"No open step matching {complete_step!r}")
        text = "\n".join(lines)
    if add_steps:
        head, sep, rest = text.partition("\n## Progress")
        text = head.rstrip("\n") + "\n" + "\n".join(_step_line(s) for s in add_steps) + "\n" + sep + rest
    if status:
        text = re.sub(r"^status: .*$", f"status: {status}", text, count=1, flags=re.M)
    if note:
        text = text.rstrip("\n") + f"\n- {today}: {note}\n"
    p.write_text(text)
    return summary(p)

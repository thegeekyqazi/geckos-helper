"""Saved permission rules ("Always allow" / "Always deny").

Stored in ~/.config/geckos-helper/permission-rules.json as a list of
    {"match": "<pattern>", "action": "allow" | "deny"}
Patterns are shell-style globs matched against a call key: the tool name
(`mcp__gecko__todo_add`, `WebFetch`) or, for shell commands, `Bash:<command>`
(`Bash:git status*`). The last matching rule wins, so put exceptions after
broader rules.
"""

import fnmatch
import json

from . import paths

RULES_FILE = paths.CONFIG_DIR / "permission-rules.json"


def call_key(tool: str, inp: dict) -> str:
    return f"Bash:{inp.get('command', '')}" if tool == "Bash" else tool


def load() -> list[dict]:
    try:
        rules = json.loads(RULES_FILE.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return []
    return [r for r in rules if r.get("action") in ("allow", "deny") and r.get("match")]


def save(rules: list[dict]) -> None:
    paths.ensure_dirs()
    RULES_FILE.write_text(json.dumps(rules, indent=2) + "\n")


def decide(tool: str, inp: dict) -> str | None:
    """'allow', 'deny', or None when no rule matches (ask the user)."""
    keys = (call_key(tool, inp), exact_key(tool, inp))
    action = None
    for r in load():
        if any(fnmatch.fnmatchcase(key, r["match"]) for key in keys):
            action = r["action"]
    return action


def exact_key(tool: str, inp: dict) -> str:
    if tool == "Bash":
        return call_key(tool, inp)
    return f"{tool}:{json.dumps(inp, sort_keys=True, separators=(',', ':'), ensure_ascii=False)}"


def exact_pattern(tool: str, inp: dict) -> str:
    """New one-click Always rules include the complete input, not just the tool."""
    key = exact_key(tool, inp)
    return "".join(f"[{c}]" if c in "*?[" else c for c in key)


def add(match: str, action: str) -> list[dict]:
    rules = [r for r in load() if r["match"] != match]
    rules.append({"match": match, "action": action})
    save(rules)
    return rules


def remove(index: int) -> list[dict]:
    rules = load()
    rules.pop(index)
    save(rules)
    return rules

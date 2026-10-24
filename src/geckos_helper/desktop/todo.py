"""end-4 to-do list (~/.local/state/quickshell/user/todo.json: [{content, done}])."""

import json

from .. import paths


def _load() -> list[dict]:
    try:
        return json.loads(paths.END4_TODO.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return []


def _save(items: list[dict]) -> None:
    paths.END4_TODO.parent.mkdir(parents=True, exist_ok=True)
    # Written in place, not via rename: the to-do widgets' file watchers follow the inode
    paths.END4_TODO.write_text(json.dumps(items))


def list_items(include_done: bool = False) -> list[dict]:
    return [{"index": i, **it} for i, it in enumerate(_load()) if include_done or not it.get("done")]


def add(content: str) -> dict:
    items = _load()
    items.append({"content": content, "done": False})
    _save(items)
    return {"index": len(items) - 1, "content": content}


def set_done(index: int, done: bool = True) -> dict:
    items = _load()
    items[index]["done"] = done
    _save(items)
    return {"index": index, **items[index]}


def remove(index: int) -> dict:
    items = _load()
    gone = items.pop(index)
    _save(items)
    return gone

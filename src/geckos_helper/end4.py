"""Small, idempotent add-ons to end-4 files. end-4 updates overwrite them, so
`install.sh` (or `gecko end4-patch`) re-applies them; `check()` reports what's missing.
"""

from . import paths

QS_II = paths.HOME / ".config/quickshell/ii"
MARK = "// gecko: reload on external change"

# end-4's Todo service reads todo.json only at startup; watch it so edits made
# by the agent show up in the widget immediately.
TODO_QML = QS_II / "services/Todo.qml"
TODO_ANCHOR = "        id: todoFileView\n"
TODO_PATCH = f"        {MARK}\n        watchChanges: true\n        onFileChanged: reload()\n"


def todo_patched() -> bool:
    return TODO_QML.exists() and MARK in TODO_QML.read_text()


def apply() -> list[str]:
    done = []
    if TODO_QML.exists() and not todo_patched():
        text = TODO_QML.read_text()
        if TODO_ANCHOR not in text:
            raise RuntimeError(f"{TODO_QML} changed upstream; the to-do patch needs updating")
        TODO_QML.write_text(text.replace(TODO_ANCHOR, TODO_ANCHOR + TODO_PATCH, 1))
        done.append("todo watch")
    return done


def revert() -> None:
    if todo_patched():
        TODO_QML.write_text(TODO_QML.read_text().replace(TODO_PATCH, "", 1))


# Super+A opens Gecko instead of end-4's left sidebar (Super+B / Super+O still open it).
KEYBINDS = paths.HOME / ".config/hypr/custom/keybinds.lua"
BIND_BEGIN = "-- >>> geckos-helper (managed by install.sh; edit outside this block)"
BIND_END = "-- <<< geckos-helper"
BIND_BLOCK = f"""{BIND_BEGIN}
hl.unbind("SUPER + A")
hl.bind("SUPER + A", hl.dsp.exec_cmd("qs -c gecko ipc call gecko toggle"), {{ description = "Gecko's Helper: toggle panel" }})
hl.bind("SUPER + ALT + K", hl.dsp.exec_cmd("~/.local/bin/gecko kill toggle"), {{ description = "Gecko's Helper: kill switch" }})
{BIND_END}
"""


def _strip_block(text: str) -> str:
    if BIND_BEGIN not in text:
        return text
    start = text.index(BIND_BEGIN)
    end = text.index(BIND_END, start) + len(BIND_END)
    return (text[:start] + text[end:].lstrip("\n")).rstrip("\n") + "\n"


def install_keybinds() -> None:
    text = KEYBINDS.read_text() if KEYBINDS.exists() else ""
    text = _strip_block(text)
    KEYBINDS.write_text(text.rstrip("\n") + "\n\n" + BIND_BLOCK)


def remove_keybinds() -> None:
    if KEYBINDS.exists():
        KEYBINDS.write_text(_strip_block(KEYBINDS.read_text()))


def check() -> list[str]:
    return [] if todo_patched() else ["end-4 to-do widget won't see agent edits until you run `gecko end4-patch`"]

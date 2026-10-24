"""Small, idempotent add-ons to end-4 files. end-4 updates overwrite them, so
`install.sh` (or `gecko end4-patch`) re-applies them; `check()` reports what's missing.
"""

from . import paths

QS_II = paths.HOME / ".config/quickshell/ii"
GECKO_TOGGLE = 'Quickshell.execDetached(["qs", "-c", "gecko", "ipc", "call", "gecko", "toggle"])'


class Patch:
    """Replace `old` with `new` in one end-4 file; `new` carries a gecko marker."""

    def __init__(self, name: str, rel: str, old: str, new: str):
        self.name, self.file, self.old, self.new = name, QS_II / rel, old, new

    def applied(self) -> bool:
        return self.file.exists() and self.new in self.file.read_text()

    def apply(self) -> bool:
        if not self.file.exists() or self.applied():
            return False
        text = self.file.read_text()
        if self.old not in text:
            raise RuntimeError(f"{self.file} changed upstream; the '{self.name}' patch needs updating")
        self.file.write_text(text.replace(self.old, self.new, 1))
        return True

    def revert(self) -> None:
        if self.applied():
            self.file.write_text(self.file.read_text().replace(self.new, self.old, 1))


PATCHES = [
    # end-4's Todo service reads todo.json only at startup; watch it so the agent's
    # edits show up in the widget immediately.
    Patch("todo watch", "services/Todo.qml", "        id: todoFileView\n",
          "        id: todoFileView\n        // gecko: reload on external change\n"
          "        watchChanges: true\n        onFileChanged: reload()\n"),
    # The bar's AI button (and clicking the bar's left end) opens Gecko; right-click
    # the button for end-4's own sidebar.
    Patch("bar button", "modules/ii/bar/LeftSidebarButton.qml",
          "    onPressed: {\n        GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen;\n    }\n",
          "    onPressed: { // gecko: open Gecko's Helper; right-click for end-4's sidebar\n"
          f"        {GECKO_TOGGLE};\n    }}\n"
          "    altAction: () => { GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen; }\n"),
    Patch("bar button import", "modules/ii/bar/LeftSidebarButton.qml",
          "import QtQuick\nimport qs\n", "import QtQuick\nimport Quickshell // gecko\nimport qs\n"),
    Patch("bar left click", "modules/ii/bar/BarContent.qml",
          "            if (event.button === Qt.LeftButton)\n"
          "                GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen;\n",
          "            if (event.button === Qt.LeftButton) // gecko: open Gecko's Helper\n"
          f"                {GECKO_TOGGLE};\n"),
]


def apply() -> list[str]:
    return [p.name for p in PATCHES if p.apply()]


def revert() -> None:
    for p in PATCHES:
        p.revert()


# Super+A opens Gecko instead of end-4's left sidebar (Super+B / Super+O still open it).
KEYBINDS = paths.HOME / ".config/hypr/custom/keybinds.lua"
BIND_BEGIN = "-- >>> geckos-helper (managed by install.sh; edit outside this block)"
BIND_END = "-- <<< geckos-helper"
BIND_BLOCK = f"""{BIND_BEGIN}
hl.unbind("SUPER + A")
hl.bind("SUPER + A", hl.dsp.exec_cmd("qs -c gecko ipc call gecko toggle"), {{ description = "Gecko: Toggle assistant panel" }})
hl.bind("SUPER + Space", hl.dsp.exec_cmd("qs -c gecko ipc call gecko quickAsk"), {{ description = "Gecko: Quick ask (type / for commands)" }})
hl.bind("SUPER + ALT + K", hl.dsp.exec_cmd("~/.local/bin/gecko kill toggle"), {{ description = "Gecko: Kill switch (stop agents, block desktop access)" }})
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


# Layer rules for Gecko's surfaces so see-through themes (glass, blur) get a real blur
# of what's behind them. Opaque themes look the same either way.
RULES = paths.HOME / ".config/hypr/custom/rules.lua"
RULES_BLOCK = f"""{BIND_BEGIN}
hl.layer_rule({{ match = {{ namespace = "quickshell:gecko.*" }}, blur = true }})
hl.layer_rule({{ match = {{ namespace = "quickshell:gecko.*" }}, ignore_alpha = 0.15 }})
hl.layer_rule({{ match = {{ namespace = "quickshell:gecko.*" }}, xray = false }})
{BIND_END}
"""


def install_rules() -> None:
    text = RULES.read_text() if RULES.exists() else ""
    RULES.write_text(_strip_block(text).rstrip("\n") + "\n\n" + RULES_BLOCK)


def remove_rules() -> None:
    if RULES.exists():
        RULES.write_text(_strip_block(RULES.read_text()))


def check() -> list[str]:
    missing = [p.name for p in PATCHES if p.file.exists() and not p.applied()]
    return [f"end-4 add-ons missing ({', '.join(missing)}); run `gecko end4-patch`"] if missing else []

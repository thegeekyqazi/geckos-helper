"""Panel themes written in Lua.

A theme is a .lua file that returns a table of tokens (colors, radii, fonts, layout).
Bundled themes live in profile/themes; yours go in ~/.config/geckos-helper/themes
and win on a name clash. The daemon evaluates the current theme in a sandbox and
writes ~/.local/state/geckos-helper/theme.json, which the panel watches.

Inside a theme these globals are available:
    palette   end-4's wallpaper colors (snake_case M3 names, e.g. palette.primary)
    dark      true when the wallpaper scheme is dark
    mix(a, b, t)  alpha(c, a)  lighten(c, amt)  darken(c, amt)   color helpers ("#rrggbb")
    default()     the default theme's table, to tweak instead of starting over
"""

import colorsys
import json
from pathlib import Path
from typing import Any

from lupa import LuaRuntime, lua_type

from . import paths
from .config import load_state, save_state

BUNDLED = paths.PROFILE_DIR / "themes"
USER = paths.CONFIG_DIR / "themes"
OUTPUT = paths.STATE_DIR / "theme.json"
PALETTE = paths.HOME / ".local/state/quickshell/user/generated/colors.json"
UNSAFE_GLOBALS = ("io", "os", "require", "dofile", "loadfile", "load", "package", "debug", "collectgarbage",
                  "python")


def available() -> dict[str, Path]:
    themes = {p.stem: p for p in sorted(BUNDLED.glob("*.lua"))}
    if USER.is_dir():
        themes |= {p.stem: p for p in sorted(USER.glob("*.lua"))}
    return themes


def current_name() -> str:
    name = load_state().get("theme", "default")
    return name if name in available() else "default"


def set_current(name: str) -> None:
    if name not in available():
        raise KeyError(f"No theme named {name!r}")
    state = load_state()
    state["theme"] = name
    save_state(state)


def cycle(step: int = 1) -> str:
    names = list(available())
    name = names[(names.index(current_name()) + step) % len(names)]
    set_current(name)
    return name


# --- color helpers exposed to Lua -------------------------------------------

def _rgb(c: str) -> tuple[float, float, float, float]:
    c = c.lstrip("#")
    if len(c) == 8:  # #aarrggbb (Qt style)
        a, c = int(c[:2], 16) / 255, c[2:]
    else:
        a = 1.0
    return int(c[0:2], 16) / 255, int(c[2:4], 16) / 255, int(c[4:6], 16) / 255, a


def _hex(r: float, g: float, b: float, a: float = 1.0) -> str:
    to = lambda v: f"{round(max(0, min(1, v)) * 255):02x}"
    return f"#{to(a) if a < 1 else ''}{to(r)}{to(g)}{to(b)}"


def mix(a: str, b: str, t: float) -> str:
    ca, cb = _rgb(a), _rgb(b)
    return _hex(*(x + (y - x) * t for x, y in zip(ca, cb)))


def alpha(c: str, a: float) -> str:
    r, g, b, _ = _rgb(c)
    return _hex(r, g, b, a)


def _lightness(c: str, amt: float) -> str:
    r, g, b, a = _rgb(c)
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    return _hex(*colorsys.hls_to_rgb(h, max(0, min(1, l + amt)), s), a)


def lighten(c: str, amt: float) -> str:
    return _lightness(c, amt)


def darken(c: str, amt: float) -> str:
    return _lightness(c, -amt)


# --- evaluation ---------------------------------------------------------------

def _palette() -> dict[str, str]:
    try:
        return json.loads(PALETTE.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def _to_py(v: Any) -> Any:
    if lua_type(v) == "table":
        keys = list(v.keys())
        if keys and all(isinstance(k, int) for k in keys):
            return [_to_py(v[k]) for k in sorted(keys)]
        return {str(k): _to_py(v[k]) for k in keys}
    return v


def _run(path: Path, palette: dict[str, str]) -> dict[str, Any]:
    lua = LuaRuntime(register_eval=False, register_builtins=False, unpack_returned_tuples=True,
                     max_memory=64 * 2**20)
    g = lua.globals()
    for name in UNSAFE_GLOBALS:
        g[name] = None
    g.palette = lua.table_from(palette)
    r, gr, b, _ = _rgb(palette.get("background", "#000000"))
    g.dark = 0.2126 * r + 0.7152 * gr + 0.0722 * b < 0.5
    g.mix, g.alpha, g.lighten, g.darken = mix, alpha, lighten, darken
    g.default = lambda: _run_table(lua, BUNDLED / "default.lua")
    result = lua.execute(path.read_text(), path.name)
    if lua_type(result) != "table":
        raise ValueError(f"{path.name} must return a table")
    return _to_py(result)


def _run_table(lua: LuaRuntime, path: Path):
    return lua.execute(path.read_text(), path.name)


def render() -> dict[str, Any]:
    """Evaluate the current theme and write theme.json. Errors keep the last good tokens."""
    themes = available()
    name = current_name()
    out: dict[str, Any] = {"name": name, "themes": list(themes), "error": None}
    try:
        out["tokens"] = _run(themes[name], _palette())
    except Exception as e:  # a broken user theme must not break the panel
        out["error"] = f"{name}.lua: {e}"
        try:
            out["tokens"] = json.loads(OUTPUT.read_text())["tokens"]
        except (FileNotFoundError, json.JSONDecodeError, KeyError):
            out["tokens"] = {}
    paths.ensure_dirs()
    tmp = OUTPUT.with_suffix(".tmp")
    tmp.write_text(json.dumps(out, indent=1))
    tmp.replace(OUTPUT)
    return out


def signature() -> tuple:
    """Changes whenever the rendered theme could change."""
    files = [available().get(current_name()), BUNDLED / "default.lua", PALETTE]
    return (current_name(), *(f.stat().st_mtime if f and f.exists() else 0 for f in files))

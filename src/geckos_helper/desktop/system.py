"""System information, notifications, media and clipboard."""

import json
import os
import shutil
import subprocess
from datetime import datetime
from pathlib import Path

from .. import paths


def _run(*cmd: str) -> str:
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=5,
                              stdin=subprocess.DEVNULL).stdout.strip()
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return ""


def _hypr_env() -> None:
    """MCP clients may start us with a stripped environment; find Hyprland's socket."""
    if "HYPRLAND_INSTANCE_SIGNATURE" not in os.environ:
        sockets = sorted((paths.RUNTIME_DIR / "hypr").glob("*/.socket.sock"), key=lambda p: p.stat().st_mtime)
        if sockets:
            os.environ["HYPRLAND_INSTANCE_SIGNATURE"] = sockets[-1].parent.name


def _hypr(*args: str) -> dict:
    _hypr_env()
    try:
        return json.loads(_run("hyprctl", *args, "-j") or "{}")
    except json.JSONDecodeError:
        return {}


def battery() -> dict | None:
    for bat in Path("/sys/class/power_supply").glob("BAT*"):
        read = lambda f: (bat / f).read_text().strip() if (bat / f).exists() else None
        return {"percent": int(read("capacity") or 0), "status": read("status")}
    return None


def system_info() -> dict:
    window = _hypr("activewindow")
    workspace = _hypr("activeworkspace")
    mem = dict(line.split(":", 1) for line in Path("/proc/meminfo").read_text().splitlines())
    kb = lambda k: int(mem[k].split()[0])
    disk = shutil.disk_usage(paths.HOME)
    return {
        "time": datetime.now().astimezone().isoformat(timespec="minutes"),
        "battery": battery(),
        "focused_window": {k: window.get(k) for k in ("class", "title")} if window else None,
        "workspace": workspace.get("name"),
        "memory_used_gb": round((kb("MemTotal") - kb("MemAvailable")) / 1e6, 1),
        "memory_total_gb": round(kb("MemTotal") / 1e6, 1),
        "home_disk_free_gb": round(disk.free / 1e9, 1),
        "uptime": _run("uptime", "-p"),
    }


def recent_notifications(limit: int = 20) -> list[dict]:
    try:
        items = json.loads(paths.END4_NOTIFICATIONS.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return []
    items.sort(key=lambda n: n.get("time", 0), reverse=True)
    return [
        {
            "app": n.get("appName"),
            "summary": n.get("summary"),
            "body": n.get("body"),
            "time": datetime.fromtimestamp(n["time"] / 1000).isoformat(timespec="minutes") if n.get("time") else None,
        }
        for n in items[:limit]
    ]


def send_notification(title: str, body: str = "", urgency: str = "normal") -> None:
    subprocess.run(["notify-send", "-a", "Gecko's Helper", "-u", urgency, title, body],
                   check=True, timeout=5, stdin=subprocess.DEVNULL)


def media_status() -> dict:
    fmt = "{{status}}\t{{artist}}\t{{title}}\t{{playerName}}"
    out = _run("playerctl", "metadata", "--format", fmt)
    if not out:
        return {"playing": False}
    status, artist, title, player = (out.split("\t") + [""] * 4)[:4]
    return {"status": status, "artist": artist, "title": title, "player": player}


MEDIA_ACTIONS = {"play", "pause", "play-pause", "next", "previous", "stop"}


def media_control(action: str) -> dict:
    if action not in MEDIA_ACTIONS:
        raise ValueError(f"action must be one of {sorted(MEDIA_ACTIONS)}")
    _run("playerctl", action)
    return media_status()


def clipboard() -> str:
    return _run("wl-paste", "--no-newline")

"""Hand a task over to a full interactive Claude Code session in a terminal."""

import shlex
import subprocess

from .config import expand, load_config


def open_claude_code(task: str, cwd: str) -> str:
    cfg = load_config()
    directory = expand(cwd)
    if not directory.is_dir():
        raise NotADirectoryError(str(directory))
    claude = str(expand(cfg["agents"]["claude"]["path"]))
    prompt = f"(Handed off from Gecko's Helper)\n\n{task}"
    cmd = [*shlex.split(cfg["desktop"]["terminal"]), "--directory", str(directory), claude, prompt]
    subprocess.Popen(cmd, start_new_session=True, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return f"Opened Claude Code in {directory}"

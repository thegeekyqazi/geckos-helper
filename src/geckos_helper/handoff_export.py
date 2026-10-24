"""Context hand-off: package a chat so you can continue it somewhere else (e.g. Claude.ai).

Two forms:
    transcript  the conversation as markdown, built locally (instant, free)
    brief       a short self-contained hand-off written by a small model from the transcript
"""

import asyncio
import subprocess

from .config import expand, load_config
from .store import Store

BRIEF_PROMPT = """Write a hand-off brief so another AI assistant (with no access to this
conversation, my computer or my tools) can continue helping me. Include: my goal, what
was found or decided, current state, open questions and the exact next steps. Keep facts
and specifics (names, dates, paths, numbers); drop chit-chat. Use short markdown sections.
Output only the brief.

<transcript>
{transcript}
</transcript>"""

MAX_TRANSCRIPT = 120_000  # characters handed to the brief writer


def transcript(store: Store, chat_id: str) -> str:
    chat = store.get(chat_id) or {}
    lines = [f"# {chat.get('title', 'Chat')}", ""]
    for e in store.transcript(chat_id):
        match e["kind"]:
            case "user_message":
                lines += ["**Me:**", e["text"], ""]
            case "agent_message":
                lines += ["**Assistant:**", e["text"], ""]
            case "tool_call":
                lines += [f"> _used {e['title']}_", ""]
    return "\n".join(lines).strip() + "\n"


async def brief(store: Store, chat_id: str, model: str = "haiku") -> str:
    text = transcript(store, chat_id)[-MAX_TRANSCRIPT:]
    claude = str(expand(load_config()["agents"]["claude"]["path"]))
    proc = await asyncio.create_subprocess_exec(
        claude, "-p", "--model", model, "--tools", "", "--setting-sources", "",
        "--strict-mcp-config", "--no-session-persistence",
        stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
    out, err = await asyncio.wait_for(proc.communicate(BRIEF_PROMPT.format(transcript=text).encode()), 180)
    if proc.returncode:
        raise RuntimeError(f"brief failed: {err.decode(errors='replace')[-500:]}")
    return out.decode().strip() + "\n"


def to_clipboard(text: str) -> None:
    subprocess.run(["wl-copy"], input=text.encode(), check=True, timeout=5)

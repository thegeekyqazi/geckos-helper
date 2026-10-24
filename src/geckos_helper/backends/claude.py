"""Claude Code backend: one long-running `claude -p` process per chat, spoken to in stream-json.

Permission prompts come back to us as `control_request: can_use_tool` messages
(`--permission-prompt-tool stdio`), which the daemon forwards to the UI.
"""

import asyncio
import json
import uuid
from typing import Any

from .. import paths
from ..config import expand
from . import Emit

STREAM_LIMIT = 32 * 1024 * 1024
STDERR_LOG = paths.STATE_DIR / "claude-stderr.log"


def _tool_title(name: str, inp: dict) -> str:
    if name == "Bash":
        return f"Ran `{inp.get('command', '')[:120]}`"
    if name in ("Read", "Edit", "Write"):
        return f"{name} {inp.get('file_path', '')}"
    if name.startswith("mcp__"):
        _, server, tool = name.split("__", 2)
        return f"{server}: {tool}"
    return name


def _result_text(content: Any) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(c.get("text", "") for c in content if isinstance(c, dict))
    return ""


class ClaudeBackend:
    def __init__(self, emit: Emit, cfg: dict, session_id: str | None = None, extra_dirs: list[str] = ()):
        self.emit = emit
        self.cfg = cfg
        self.session_id = session_id
        self.extra_dirs = list(extra_dirs)
        self.proc: asyncio.subprocess.Process | None = None
        self._reader: asyncio.Task | None = None
        self.busy = False
        self._pending_inputs: dict[str, dict] = {}

    @property
    def alive(self) -> bool:
        return self.proc is not None and self.proc.returncode is None

    def argv(self) -> list[str]:
        c = self.cfg
        argv = [
            str(expand(c["path"])), "-p",
            "--input-format", "stream-json", "--output-format", "stream-json",
            "--verbose", "--include-partial-messages",
            "--permission-prompt-tool", "stdio",
            "--permission-mode", c.get("permission_mode", "default"),
            "--append-system-prompt-file", str(paths.SYSTEM_PROMPT_FILE),
            "--mcp-config", str(paths.MCP_CONFIG_FILE),
            "--settings", str(paths.CLAUDE_SETTINGS),
            "--add-dir", str(paths.DATA_DIR / "attachments"),  # attached files are read from here
        ]
        if c.get("model"):
            argv += ["--model", c["model"]]
        if not c.get("inherit_settings", True):
            # Skip ~/.claude settings, hooks and CLAUDE.md; --settings still applies.
            argv += ["--setting-sources", "project"]
        if self.session_id:
            argv += ["--resume", self.session_id]
        for d in self.extra_dirs:
            argv += ["--add-dir", d]
        return argv

    async def _start(self) -> None:
        with STDERR_LOG.open("ab") as err:
            self.proc = await asyncio.create_subprocess_exec(
                *self.argv(), cwd=paths.WORKSPACE, limit=STREAM_LIMIT,
                stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE, stderr=err,
            )
        self._reader = asyncio.create_task(self._read())
        await self._send({"type": "control_request", "request_id": str(uuid.uuid4()),
                          "request": {"subtype": "initialize"}})

    async def _send(self, obj: dict) -> None:
        assert self.proc and self.proc.stdin
        self.proc.stdin.write((json.dumps(obj) + "\n").encode())
        await self.proc.stdin.drain()

    async def prompt(self, content: str | list[dict]) -> None:
        """content: plain text, or a list of content blocks (text, images) for attachments."""
        if not self.alive:
            await self._start()
        self.busy = True
        await self._send({"type": "user", "message": {"role": "user", "content": content}})

    async def respond_permission(self, request_id: str, allow: bool, message: str = "") -> None:
        if allow:
            resp = {"behavior": "allow", "updatedInput": self._pending_inputs.pop(request_id, {})}
        else:
            self._pending_inputs.pop(request_id, None)
            resp = {"behavior": "deny", "message": message or "The user denied this action."}
        await self._send({"type": "control_response", "response": {
            "subtype": "success", "request_id": request_id, "response": resp}})

    async def interrupt(self) -> None:
        if self.alive:
            await self._send({"type": "control_request", "request_id": str(uuid.uuid4()),
                              "request": {"subtype": "interrupt"}})

    async def close(self) -> None:
        if self.alive:
            assert self.proc and self.proc.stdin
            self.proc.stdin.close()
            try:
                await asyncio.wait_for(self.proc.wait(), 5)
            except TimeoutError:
                self.proc.terminate()
        if self._reader:
            await asyncio.gather(self._reader, return_exceptions=True)

    async def _read(self) -> None:
        assert self.proc and self.proc.stdout
        try:
            async for raw in self.proc.stdout:
                try:
                    msg = json.loads(raw)
                except json.JSONDecodeError:
                    continue
                await self._handle(msg)
        finally:
            await self.proc.wait()
            if self.proc.returncode not in (0, None) and self.busy:
                err = STDERR_LOG.read_text(errors="replace")[-2000:]
                await self.emit("error", {"message": f"claude exited with {self.proc.returncode}: {err}"})
            self.busy = False
            await self.emit("closed", {})

    async def _handle(self, msg: dict) -> None:
        t = msg.get("type")
        if t == "system" and msg.get("subtype") == "init":
            self.session_id = msg["session_id"]
            await self.emit("session_ready", {"session_id": self.session_id})
        elif t == "stream_event":
            delta = msg["event"].get("delta") or {}
            if delta.get("type") == "text_delta":
                await self.emit("agent_message_chunk", {"text": delta["text"]})
            elif delta.get("type") == "thinking_delta":
                await self.emit("agent_thought_chunk", {"text": delta["thinking"]})
        elif t == "assistant" and not msg.get("parent_tool_use_id"):
            for block in msg["message"].get("content", []):
                if block["type"] == "text" and block["text"].strip():
                    await self.emit("agent_message", {"text": block["text"]})
                elif block["type"] == "tool_use":
                    await self.emit("tool_call", {"id": block["id"], "name": block["name"],
                                                  "input": block["input"],
                                                  "title": _tool_title(block["name"], block["input"])})
        elif t == "user" and not msg.get("parent_tool_use_id"):
            content = msg["message"].get("content")
            for block in content if isinstance(content, list) else []:
                if block.get("type") == "tool_result":
                    await self.emit("tool_call_update", {
                        "id": block["tool_use_id"],
                        "status": "failed" if block.get("is_error") else "completed",
                        "output": _result_text(block.get("content"))[:4000]})
        elif t == "control_request" and msg["request"].get("subtype") == "can_use_tool":
            req = msg["request"]
            self._pending_inputs[msg["request_id"]] = req.get("input", {})
            await self.emit("permission_request", {
                "request_id": msg["request_id"], "tool": req["tool_name"], "input": req.get("input", {}),
                "title": req.get("description") or _tool_title(req["tool_name"], req.get("input", {}))})
        elif t == "rate_limit_event":
            windows = msg.get("rate_limit_info", {}).get("unifiedWindows", {})
            await self.emit("usage", {k: v.get("utilization") for k, v in windows.items()})
        elif t == "result":
            self.busy = False
            await self.emit("turn_end", {"is_error": msg.get("is_error", False),
                                         "cost_usd": msg.get("total_cost_usd"),
                                         "duration_ms": msg.get("duration_ms"),
                                         "result": msg.get("result")})

"""Agent backends. Each one turns an agent CLI's own output into the shared events below.

Event names follow the Agent Client Protocol (ACP) session updates, so an
ACP-based backend (OpenCode's `opencode acp`, codex-acp) can plug in later
without the UI changing:

    session_ready         {session_id}
    agent_message_chunk   {text}
    agent_thought_chunk   {text}
    agent_message         {text}                 full text of one message
    tool_call             {id, name, input, title}
    tool_call_update      {id, status, output}   status: completed | failed
    permission_request    {request_id, tool, input, title}
    usage                 {five_hour, seven_day}  subscription utilization 0..1
    turn_end              {is_error, cost_usd, duration_ms, result}
    error                 {message}
    closed                {}
"""

from collections.abc import Awaitable, Callable
from typing import Any, Protocol

Emit = Callable[[str, dict[str, Any]], Awaitable[None]]


class Backend(Protocol):
    async def prompt(self, text: str) -> None: ...
    async def respond_permission(self, request_id: str, allow: bool, message: str = "") -> None: ...
    async def interrupt(self) -> None: ...
    async def close(self) -> None: ...
    @property
    def alive(self) -> bool: ...

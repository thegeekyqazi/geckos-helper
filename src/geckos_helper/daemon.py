"""The always-running daemon. The Quickshell UI and the `gecko` CLI are clients.

Wire format on $XDG_RUNTIME_DIR/geckos-helper.sock: one JSON object per line.
    client -> daemon   {"id": 1, "op": "send", "chat": "...", "text": "..."}
    daemon -> client   {"reply": 1, "ok": true, ...}          answer to a request
    daemon -> client   {"event": "agent_message_chunk", "chat": "...", ...}   broadcast
"""

import asyncio
import contextlib
import json
import logging
import os
import time
from typing import Any

from . import config, context, paths
from .backends.claude import ClaudeBackend
from .store import Store

log = logging.getLogger("gecko")


class Daemon:
    def __init__(self) -> None:
        self.store = Store()
        self.clients: set[asyncio.StreamWriter] = set()
        self.backends: dict[str, ClaudeBackend] = {}
        self.last_active: dict[str, float] = {}
        self.pending: dict[str, str] = {}  # permission request_id -> chat id
        self.usage: dict[str, Any] = {}

    # --- events ----------------------------------------------------------

    async def broadcast(self, msg: dict) -> None:
        line = (json.dumps(msg) + "\n").encode()
        for w in list(self.clients):
            try:
                w.write(line)
                await w.drain()
            except (ConnectionError, RuntimeError):
                self.clients.discard(w)

    def emitter(self, chat_id: str):
        async def emit(kind: str, data: dict) -> None:
            if kind == "session_ready":
                self.store.update(chat_id, session_id=data["session_id"])
            elif kind == "permission_request":
                self.pending[data["request_id"]] = chat_id
            elif kind == "usage":
                self.usage = data
            elif kind == "closed":
                self.backends.pop(chat_id, None)
            self.store.append(chat_id, kind, data)
            self.last_active[chat_id] = time.time()
            await self.broadcast({"event": kind, "chat": chat_id, **data})

        return emit

    # --- operations ------------------------------------------------------

    def backend_for(self, chat: dict) -> ClaudeBackend:
        if chat["id"] not in self.backends:
            cfg = config.load_config()
            if chat["agent"] != "claude":
                raise ValueError(f"Agent '{chat['agent']}' is not supported yet")
            extra = [chat["cwd"]] if chat.get("cwd") else []
            self.backends[chat["id"]] = ClaudeBackend(
                self.emitter(chat["id"]), cfg["agents"]["claude"], chat.get("session_id"), extra)
        return self.backends[chat["id"]]

    async def op_send(self, req: dict) -> dict:
        if config.load_state()["killed"]:
            raise PermissionError("Kill switch is on. Turn it off with `gecko kill off`.")
        chat = self.store.get(req["chat"]) if req.get("chat") else None
        if not chat:
            title = req["text"].strip().splitlines()[0][:60] or "New chat"
            chat = self.store.create(req.get("agent", "claude"), title, req.get("cwd"))
            await self.broadcast({"event": "chat_created", "chat": chat["id"], **chat})
        backend = self.backend_for(chat)
        await self.emitter(chat["id"])("user_message", {"text": req["text"]})
        await backend.prompt(req["text"])
        self.store.update(chat["id"])
        return {"chat": chat["id"]}

    async def op_permission(self, req: dict) -> dict:
        chat_id = self.pending.pop(req["request_id"])
        backend = self.backends[chat_id]
        await backend.respond_permission(req["request_id"], bool(req["allow"]), req.get("message", ""))
        await self.broadcast({"event": "permission_resolved", "chat": chat_id,
                              "request_id": req["request_id"], "allow": bool(req["allow"])})
        return {}

    async def op_stop(self, req: dict) -> dict:
        if b := self.backends.get(req["chat"]):
            await b.interrupt()
        return {}

    async def op_chats(self, req: dict) -> dict:
        chats = self.store.list(req.get("limit", 50))
        for c in chats:
            c["running"] = c["id"] in self.backends
        return {"chats": chats}

    async def op_history(self, req: dict) -> dict:
        return {"chat": self.store.get(req["chat"]), "entries": self.store.transcript(req["chat"])}

    async def op_delete(self, req: dict) -> dict:
        if b := self.backends.pop(req["chat"], None):
            await b.close()
        self.store.delete(req["chat"])
        return {}

    async def op_status(self, req: dict) -> dict:
        state = config.load_state()
        return {"killed": state["killed"], "capabilities": state["capabilities"],
                "running": list(self.backends), "usage": self.usage, "pid": os.getpid()}

    async def op_kill(self, req: dict) -> dict:
        on = bool(req["on"])
        config.set_killed(on)
        if on:
            await asyncio.gather(*(b.close() for b in list(self.backends.values())))
            self.backends.clear()
        context.generate_lite()
        await self.broadcast({"event": "kill_switch", "on": on})
        return {"killed": on}

    async def op_capability(self, req: dict) -> dict:
        config.set_capability(req["name"], bool(req["on"]))
        context.generate_lite()
        await self.broadcast({"event": "capability", "name": req["name"], "on": bool(req["on"])})
        return {}

    async def op_context(self, req: dict) -> dict:
        text = await asyncio.to_thread(context.generate)
        return {"context": text}

    # --- plumbing --------------------------------------------------------

    async def handle_client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        self.clients.add(writer)
        try:
            async for line in reader:
                try:
                    req = json.loads(line)
                    handler = getattr(self, f"op_{req['op']}")
                    reply = {"reply": req.get("id"), "ok": True, **await handler(req)}
                except Exception as e:  # report every failure to the client
                    log.exception("request failed")
                    reply = {"reply": req.get("id") if isinstance(req, dict) else None,
                             "ok": False, "error": f"{type(e).__name__}: {e}"}
                writer.write((json.dumps(reply) + "\n").encode())
                await writer.drain()
        except ConnectionError:
            pass
        finally:
            self.clients.discard(writer)
            writer.close()

    async def reap_idle(self) -> None:
        while True:
            await asyncio.sleep(60)
            timeout = config.load_config()["agents"]["claude"]["idle_timeout_minutes"] * 60
            for chat_id, b in list(self.backends.items()):
                if not b.busy and time.time() - self.last_active.get(chat_id, 0) > timeout:
                    await b.close()
                    self.backends.pop(chat_id, None)

    async def serve(self) -> None:
        paths.ensure_dirs()
        context.write_agent_files()
        context.generate_lite()
        with contextlib.suppress(FileNotFoundError):
            paths.SOCKET.unlink()
        server = await asyncio.start_unix_server(self.handle_client, path=str(paths.SOCKET), limit=16 * 2**20)
        os.chmod(paths.SOCKET, 0o600)
        log.info("listening on %s", paths.SOCKET)
        asyncio.create_task(self.reap_idle())
        async with server:
            await server.serve_forever()


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    asyncio.run(Daemon().serve())

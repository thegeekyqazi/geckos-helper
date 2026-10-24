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

from . import activity, config, context, handoff_export, memory, paths, rules, theme, watchers
from .backends.claude import ClaudeBackend
from .desktop import goals
from .store import Store

log = logging.getLogger("gecko")


DENIED = ("The user denied this action. Do not retry it or work around it; "
          "say what you were trying to do and ask how they want to proceed.")


def call_key(tool: str, inp: dict) -> str:
    return f"{tool}:{json.dumps(inp, sort_keys=True)}"


def rule_key(tool: str, inp: dict) -> str:
    """What "allow for this chat" remembers: the tool, and for Bash the exact command.

    Allowing a whole program (e.g. every `rm`) would be too broad for a one-click approval.
    """
    if tool == "Bash":
        return f"Bash:{inp.get('command', '')}"
    return tool


class Daemon:
    def __init__(self) -> None:
        self.store = Store()
        self.clients: set[asyncio.StreamWriter] = set()
        self.backends: dict[str, ClaudeBackend] = {}
        self.last_active: dict[str, float] = {}
        self.pending: dict[str, str] = {}  # permission request_id -> chat id
        # "Allow for this chat" approvals: chat id -> rule keys (see rule_key)
        self.chat_allows: dict[str, set[str]] = {}
        # Calls the user denied this turn: an identical retry is denied without asking again
        self.turn_denials: dict[str, set[str]] = {}
        self.request_info: dict[str, dict] = {}  # request_id -> the permission_request
        self.usage: dict[str, Any] = {}
        self.watcher_lock = asyncio.Lock()

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
                if auto := self.auto_decision(chat_id, data):
                    allow, by = auto
                    note = " You already asked for this exact action." if by == "repeat" else ""
                    await self.backends[chat_id].respond_permission(data["request_id"], allow, DENIED + note)
                    activity.log("permission", decision="allow" if allow else "deny", by=by,
                                 tool=data["tool"], title=data["title"], chat=chat_id)
                    return
                self.pending[data["request_id"]] = chat_id
                self.request_info[data["request_id"]] = data
            elif kind == "user_message":
                self.turn_denials.pop(chat_id, None)
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
            agent_cfg = {**cfg["agents"]["claude"], "model": chat.get("model") or config.default_model()}
            extra = [chat["cwd"]] if chat.get("cwd") else []
            self.backends[chat["id"]] = ClaudeBackend(
                self.emitter(chat["id"]), agent_cfg, chat.get("session_id"), extra)
        return self.backends[chat["id"]]

    async def op_send(self, req: dict) -> dict:
        if config.load_state()["killed"]:
            raise PermissionError("Kill switch is on. Turn it off with `gecko kill off`.")
        chat = self.store.get(req["chat"]) if req.get("chat") else None
        if not chat:
            title = req["text"].strip().splitlines()[0][:60] or "New chat"
            agent = req.get("agent", "claude")
            chat = self.store.create(agent, req.get("model") or config.default_model(agent), title, req.get("cwd"))
            # nonce lets the client that sent this adopt the new chat id
            await self.broadcast({"event": "chat_created", **chat, "chat": chat["id"], "nonce": req.get("nonce")})
        backend = self.backend_for(chat)
        await self.emitter(chat["id"])("user_message", {"text": req["text"]})
        await backend.prompt(req["text"])
        self.store.update(chat["id"])
        return {"chat": chat["id"]}

    def auto_decision(self, chat_id: str, data: dict) -> tuple[bool, str] | None:
        """(allow, decided_by) when a request needs no prompt; saved rules first."""
        tool, inp = data["tool"], data["input"]
        if call_key(tool, inp) in self.turn_denials.get(chat_id, ()):
            return False, "repeat"
        if decision := rules.decide(tool, inp):
            return decision == "allow", "rule"
        if rule_key(tool, inp) in self.chat_allows.get(chat_id, ()):
            return True, "chat"
        return None

    async def op_permission(self, req: dict) -> dict:
        """allow: bool; scope: "once" (default), "chat" (this chat) or "always" (saved rule)."""
        chat_id = self.pending.pop(req["request_id"])
        backend = self.backends[chat_id]
        info = self.request_info.pop(req["request_id"], {})
        tool, inp = info.get("tool", ""), info.get("input", {})
        if not req["allow"] and info:
            self.turn_denials.setdefault(chat_id, set()).add(call_key(tool, inp))
        if req["allow"] and req.get("scope") == "chat" and info:
            self.chat_allows.setdefault(chat_id, set()).add(rule_key(tool, inp))
        if req.get("scope") == "always" and info:
            rules.add(rules.exact_pattern(tool, inp), "allow" if req["allow"] else "deny")
        activity.log("permission", decision="allow" if req["allow"] else "deny",
                     by=req.get("scope", "once"), tool=tool, title=info.get("title", ""), chat=chat_id)
        message = DENIED + (f" They said: {req['message']}" if req.get("message") else "")
        await backend.respond_permission(req["request_id"], bool(req["allow"]), message)
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
            c["busy"] = c["running"] and self.backends[c["id"]].busy
        return {"chats": chats}

    async def op_models(self, req: dict) -> dict:
        agent = req.get("agent", "claude")
        return {"models": config.load_config()["agents"][agent]["models"],
                "default": config.default_model(agent)}

    async def op_set_model(self, req: dict) -> dict:
        """Switch a chat's model; the agent restarts with --resume on the next message."""
        self.store.update(req["chat"], model=req["model"])
        if (b := self.backends.get(req["chat"])) and not b.busy:
            await b.close()
            self.backends.pop(req["chat"], None)
        await self.broadcast({"event": "chat_updated", "chat": req["chat"], "model": req["model"]})
        return {}

    async def op_set_default_model(self, req: dict) -> dict:
        config.set_default_model(req["model"], req.get("agent", "claude"))
        await self.broadcast({"event": "default_model", "model": req["model"]})
        return {}

    async def op_history(self, req: dict) -> dict:
        chat = self.store.get(req["chat"])
        b = self.backends.get(req["chat"])
        pending = [rid for rid, c in self.pending.items() if c == req["chat"]]
        return {"chat": chat, "entries": self.store.transcript(req["chat"]),
                "busy": bool(b and b.busy), "pending_permissions": pending}

    async def op_delete(self, req: dict) -> dict:
        if b := self.backends.pop(req["chat"], None):
            await b.close()
        self.store.delete(req["chat"])
        return {}

    async def op_status(self, req: dict) -> dict:
        state = config.load_state()
        return {"killed": state["killed"], "capabilities": state["capabilities"],
                "capability_descriptions": config.CAPABILITIES, "default_model": config.default_model(),
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

    async def op_theme(self, req: dict) -> dict:
        """No args: current theme. name=...: switch to it. step=1/-1: cycle saved themes."""
        if req.get("name"):
            theme.set_current(req["name"])
        elif req.get("step"):
            theme.cycle(int(req["step"]))
        out = await asyncio.to_thread(theme.render)
        return {"name": out["name"], "themes": out["themes"], "error": out["error"]}

    async def op_export(self, req: dict) -> dict:
        """Copy a chat to the clipboard to continue elsewhere. mode: transcript | brief."""
        if req.get("mode") == "brief":
            text = await handoff_export.brief(self.store, req["chat"])
        else:
            text = handoff_export.transcript(self.store, req["chat"])
        await asyncio.to_thread(handoff_export.to_clipboard, text)
        return {"chars": len(text)}

    async def op_search(self, req: dict) -> dict:
        return {"results": self.store.search(req["query"], req.get("limit", 30))}

    async def op_memories(self, req: dict) -> dict:
        """No args: list Gecko's memories. remove=<file>: delete one."""
        if req.get("remove"):
            memory.delete(req["remove"])
        return {"memories": memory.list_memories(), "dir": str(memory.memory_dir())}

    async def op_watchers(self, req: dict) -> dict:
        """No args: list. remove=<id>, pause=<id>/resume=<id>, run=<id> (run now)."""
        if req.get("remove"):
            watchers.remove(req["remove"])
        elif req.get("pause") or req.get("resume"):
            watchers.update(req.get("pause") or req["resume"], paused=bool(req.get("pause")))
        elif req.get("run"):
            w = next(w for w in watchers.load() if w["id"] == req["run"])
            asyncio.create_task(self.run_watcher(w))
        return {"watchers": [watchers.describe(w) for w in watchers.load()]}

    async def op_goals(self, req: dict) -> dict:
        try:
            return {"goals": await asyncio.to_thread(goals.list_goals)}
        except FileNotFoundError:  # no vault configured
            return {"goals": []}

    async def op_rules(self, req: dict) -> dict:
        """No args: list. match+action: add. remove=<index>: delete."""
        if "remove" in req:
            rules.remove(int(req["remove"]))
        elif req.get("match"):
            rules.add(req["match"], req["action"])
        return {"rules": rules.load()}

    async def op_activity(self, req: dict) -> dict:
        return {"entries": activity.recent(req.get("limit", 200))}

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

    async def watch_theme(self) -> None:
        """Re-render when the theme file, the default theme or end-4's palette changes."""
        last = None
        while True:
            try:
                sig = theme.signature()
                if sig != last:
                    last = sig
                    out = await asyncio.to_thread(theme.render)
                    if out["error"]:
                        log.warning("theme: %s", out["error"])
            except Exception:
                log.exception("theme watcher")
            await asyncio.sleep(1.5)

    async def run_watcher(self, w: dict) -> None:
        async with self.watcher_lock:  # one at a time, so they don't pile up on usage
            await self.broadcast({"event": "watcher_running", "on": True, "name": w["name"]})
            try:
                entry = await watchers.run(w)
            finally:
                await self.broadcast({"event": "watcher_running", "on": False})
        await self.broadcast({"event": "activity", **entry, "kind": "watcher"})

    async def schedule_watchers(self) -> None:
        """Run due watchers; skip while the 5-hour usage window is nearly used up."""
        while True:
            await asyncio.sleep(30)
            try:
                if (self.usage.get("five_hour") or 0) > 0.9:
                    continue
                for w in watchers.due():
                    watchers.update(w["id"], last_run=time.time())  # don't re-queue while running
                    asyncio.create_task(self.run_watcher(w))
            except Exception:
                log.exception("watcher scheduler")

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
        asyncio.create_task(self.watch_theme())
        asyncio.create_task(self.schedule_watchers())
        async with server:
            await server.serve_forever()


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    asyncio.run(Daemon().serve())

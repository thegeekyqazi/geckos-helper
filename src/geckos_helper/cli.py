"""`gecko` command: runs the daemon/MCP server and offers a terminal client."""

import argparse
import asyncio
import itertools
import json
import sys

from . import config, paths


class Client:
    def __init__(self) -> None:
        self.ids = itertools.count(1)
        self.waiting: dict[int, asyncio.Future] = {}
        self.events: asyncio.Queue = asyncio.Queue()

    async def connect(self) -> None:
        self.reader, self.writer = await asyncio.open_unix_connection(str(paths.SOCKET), limit=16 * 2**20)
        asyncio.create_task(self._pump())

    async def _pump(self) -> None:
        async for line in self.reader:
            msg = json.loads(line)
            if "reply" in msg and msg["reply"] in self.waiting:
                self.waiting.pop(msg["reply"]).set_result(msg)
            elif "event" in msg:
                await self.events.put(msg)
        await self.events.put({"event": "disconnected"})

    async def call(self, op: str, **kw) -> dict:
        rid = next(self.ids)
        fut = asyncio.get_running_loop().create_future()
        self.waiting[rid] = fut
        self.writer.write((json.dumps({"id": rid, "op": op, **kw}) + "\n").encode())
        await self.writer.drain()
        msg = await fut
        if not msg["ok"]:
            raise RuntimeError(msg["error"])
        return msg


DIM, BOLD, YEL, RED, END = "\033[2m", "\033[1m", "\033[33m", "\033[31m", "\033[0m"


async def run_turn(client: Client, text: str, chat: str | None, auto: str | None) -> str:
    """Send one message and render events until the turn ends. Returns the chat id."""
    chat = (await client.call("send", text=text, chat=chat))["chat"]
    while True:
        ev = await client.events.get()
        if ev.get("chat") not in (chat, None):
            continue
        kind = ev["event"]
        if kind == "agent_message_chunk":
            print(ev["text"], end="", flush=True)
        elif kind == "agent_message":
            print()
        elif kind == "tool_call":
            print(f"{DIM}⚙ {ev['title']}{END}")
        elif kind == "tool_call_update" and ev["status"] == "failed":
            print(f"{DIM}  ✗ {ev['output'][:200]}{END}")
        elif kind == "permission_request":
            print(f"{YEL}? Allow: {ev['title']}{END}")
            if ev.get("warning"):
                print(f"{RED}  ⚠ {ev['warning']}{END}")
            print(f"{DIM}  {json.dumps(ev['input'])[:300]}{END}")
            if auto:
                allow = auto == "yes"
                print(f"  -> {'allowed' if allow else 'denied'} (--{'yes' if allow else 'no'})")
            else:
                answer = await asyncio.to_thread(input, "  [y/N] ")
                allow = answer.strip().lower() in ("y", "yes")
            await client.call("permission", request_id=ev["request_id"], allow=allow)
        elif kind == "usage":
            pass
        elif kind == "guard_alert":
            print(f"{RED}⚠ Possible prompt injection in {ev['source']}: {', '.join(ev['reasons'])}{END}")
        elif kind == "error":
            print(f"{RED}{ev['message']}{END}")
        elif kind == "turn_end":
            cost = ev.get("cost_usd")
            print(f"{DIM}— done in {ev.get('duration_ms', 0) / 1000:.1f}s"
                  f"{f', ${cost:.4f} API-equivalent' if cost else ''}{END}")
            return chat
        elif kind in ("closed", "disconnected"):
            print(f"{RED}agent stopped{END}")
            return chat


async def cmd_chat(args) -> None:
    client = Client()
    await client.connect()
    chat = args.chat
    if args.text:
        await run_turn(client, " ".join(args.text), chat, args.auto)
        return
    print(f"{BOLD}Gecko's Helper{END} {DIM}(Ctrl-D to quit){END}")
    while True:
        try:
            text = await asyncio.to_thread(input, f"{BOLD}> {END}")
        except EOFError:
            return
        if text.strip():
            chat = await run_turn(client, text, chat, args.auto)


async def cmd_simple(op: str, **kw) -> dict:
    client = Client()
    await client.connect()
    return await client.call(op, **kw)


def main() -> None:
    p = argparse.ArgumentParser(prog="gecko", description="Gecko's Helper")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("daemon", help="run the background daemon")
    sub.add_parser("mcp", help="run the desktop MCP server on stdio (agents start this)")
    c = sub.add_parser("context", help="regenerate the tools context file")
    c.add_argument("--lite", action="store_true", help="skip re-listing MCP servers")
    for name in ("chat", "ask"):
        a = sub.add_parser(name, help="chat in the terminal" if name == "chat" else "send one message")
        a.add_argument("text", nargs="*" if name == "chat" else "+")
        a.add_argument("--chat", help="continue this chat id")
        a.add_argument("--yes", dest="auto", action="store_const", const="yes", help="approve every prompt")
        a.add_argument("--no", dest="auto", action="store_const", const="no", help="deny every prompt")
    sub.add_parser("chats", help="list chats")
    sub.add_parser("status", help="daemon status")
    k = sub.add_parser("kill", help="kill switch: stop agents and block desktop access")
    k.add_argument("state", choices=["on", "off", "toggle"])
    m = sub.add_parser("model", help="show models, or switch a chat's model / the default")
    m.add_argument("name", nargs="?")
    m.add_argument("--default", action="store_true", help="make it the default for new chats")
    m.add_argument("--chat", help="switch this chat to the model")
    hx = sub.add_parser("handoff", help="copy a chat to the clipboard to continue elsewhere")
    hx.add_argument("chat", nargs="?", help="chat id (default: most recent)")
    hx.add_argument("--brief", action="store_true", help="have a small model write a hand-off brief")
    cal = sub.add_parser("calendar", help="calendars: login (Google), list, or show the next days")
    cal.add_argument("action", choices=["login", "list", "show"], nargs="?", default="show")
    cal.add_argument("--days", type=int, default=3)
    th = sub.add_parser("theme", help="show, switch (name) or cycle (next/prev) panel themes")
    th.add_argument("name", nargs="?")
    ep = sub.add_parser("end4-patch", help="(re)apply the end-4 add-ons and keybinds after an end-4 update")
    ep.add_argument("--revert", action="store_true", help="remove them")
    cp = sub.add_parser("caps", help="list or toggle capabilities")
    cp.add_argument("name", nargs="?")
    cp.add_argument("state", nargs="?", choices=["on", "off"])
    args = p.parse_args()

    try:
        match args.cmd:
            case "daemon":
                from .daemon import main as daemon_main
                daemon_main()
            case "mcp":
                from .mcp_server import main as mcp_main
                mcp_main()
            case "context":
                from . import context
                print(context.generate_lite() if args.lite else context.generate())
            case "chat" | "ask":
                asyncio.run(cmd_chat(args))
            case "chats":
                for c in asyncio.run(cmd_simple("chats"))["chats"]:
                    print(f"{c['id']}  {'●' if c['running'] else ' '} {c['title']}")
            case "status":
                print(json.dumps(asyncio.run(cmd_simple("status")), indent=2))
            case "kill":
                on = (not config.load_state()["killed"]) if args.state == "toggle" else args.state == "on"
                try:
                    asyncio.run(cmd_simple("kill", on=on))
                except (FileNotFoundError, ConnectionRefusedError):
                    config.set_killed(on)  # works even when the daemon is down
                print(f"kill switch {'ON: agents stopped, desktop access blocked' if on else 'off'}")
            case "model":
                if args.name and args.chat:
                    asyncio.run(cmd_simple("set_model", chat=args.chat, model=args.name))
                if args.name and (args.default or not args.chat):
                    config.set_default_model(args.name)
                print(f"default: {config.default_model()}  available: "
                      + ", ".join(config.load_config()["agents"]["claude"]["models"]))
            case "handoff":
                async def handoff():
                    client = Client()
                    await client.connect()
                    chat = args.chat or (await client.call("chats", limit=1))["chats"][0]["id"]
                    r = await client.call("export", chat=chat, mode="brief" if args.brief else "transcript")
                    print(f"copied {r['chars']} characters; paste into Claude.ai or anywhere")
                asyncio.run(handoff())
            case "calendar":
                from .desktop import calendar, calendar_google
                if args.action == "login":
                    calendar_google.login()
                    print("Google Calendar connected. Calendars: "
                          + ", ".join(c["name"] for c in calendar.calendars()))
                elif args.action == "list":
                    for c in calendar.calendars():
                        print(f"{'rw' if c['writable'] else 'ro'}  {c['name']}  ({c['id']})")
                else:
                    for e in calendar.events(args.days):
                        print(f"{e['start'][:16].replace('T', ' ')}  {e['title']}  [{e['calendar']}]")
                    for err in calendar.last_errors:
                        print(f"error: {err}")
            case "theme":
                from . import theme
                if args.name in ("next", "prev"):
                    theme.cycle(1 if args.name == "next" else -1)
                elif args.name:
                    theme.set_current(args.name)
                out = theme.render()  # the daemon also picks the change up within 2s
                print(f"theme: {out['name']}  available: {', '.join(out['themes'])}")
                if out["error"]:
                    print(f"error: {out['error']}")
            case "end4-patch":
                from . import end4
                if args.revert:
                    end4.revert()
                    end4.remove_keybinds()
                    end4.remove_rules()
                    print("removed the end-4 add-ons and keybinds")
                else:
                    applied = end4.apply()
                    end4.install_keybinds()
                    end4.install_rules()
                    print("applied: " + ", ".join(applied + ["keybinds", "layer rules"]))
            case "caps":
                if args.name and args.state:
                    try:
                        asyncio.run(cmd_simple("capability", name=args.name, on=args.state == "on"))
                    except (FileNotFoundError, ConnectionRefusedError):
                        config.set_capability(args.name, args.state == "on")
                state = config.load_state()
                for name, desc in config.CAPABILITIES.items():
                    print(f"{'on ' if state['capabilities'][name] else 'off'}  {name:20} {desc}")
    except (FileNotFoundError, ConnectionRefusedError):
        sys.exit("The Gecko daemon isn't running. Start it: systemctl --user start geckos-helper")
    except RuntimeError as e:
        sys.exit(str(e))
    except KeyboardInterrupt:
        pass

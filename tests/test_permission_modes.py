import asyncio
import sqlite3
import tempfile
import unittest
from pathlib import Path
from unittest.mock import AsyncMock, Mock, patch

from geckos_helper import config, daemon, paths, permissions, profiles
from geckos_helper.backends.claude import ClaudeBackend
from geckos_helper.store import Store


class NativeModeTests(unittest.TestCase):
    def test_native_modes_are_not_emulated_with_allowed_tools(self):
        for mode in permissions.IDS:
            argv = ClaudeBackend(AsyncMock(), {"path": "/fixture/claude", "permission_mode": mode}).argv()
            self.assertEqual(argv[argv.index("--permission-mode") + 1],
                             "manual" if mode == "default" else mode)
            self.assertNotIn("--allowedTools", argv)
            self.assertNotIn("--dangerously-skip-permissions", argv)
        self.assertEqual(permissions.validate("manual"), "default")
        with self.assertRaises(ValueError):
            ClaudeBackend(AsyncMock(), {"path": "fixture", "permission_mode": "full-auto"}).argv()

    def test_unattended_profile_never_inherits_full_access(self):
        with patch.object(profiles, "load_config", return_value={"agents": {"claude": {
                "path": "/fixture/claude", "permission_mode": "bypassPermissions"}}}):
            argv = profiles.unattended_argv()
        self.assertEqual(argv[argv.index("--permission-mode") + 1], "dontAsk")
        self.assertIn("--strict-mcp-config", argv)
        self.assertNotIn("bypassPermissions", argv)

    def test_default_mode_survives_reload_without_rewriting_capabilities(self):
        with tempfile.TemporaryDirectory() as td, patch.object(paths, "ensure_dirs"), \
                patch.object(paths, "STATE_FILE", Path(td) / "state.json"), \
                patch.object(paths, "CONFIG_FILE", Path(td) / "config.toml"):
            self.assertEqual(config.default_permission_mode(), "default")
            config.set_capability("clipboard_read", False)
            config.set_default_permission_mode("bypassPermissions")
            self.assertEqual(config.default_permission_mode(), "bypassPermissions")
            self.assertFalse(config.load_state()["capabilities"]["clipboard_read"])
            before = paths.STATE_FILE.read_text()
            with self.assertRaises(ValueError):
                config.set_default_permission_mode("invalid")
            self.assertEqual(paths.STATE_FILE.read_text(), before)

    def test_migrates_legacy_database_and_persists_chat_choice(self):
        with tempfile.TemporaryDirectory() as td, patch.object(paths, "ensure_dirs"), \
                patch.object(paths, "CHATS_DB", Path(td) / "chats.db"):
            db = sqlite3.connect(paths.CHATS_DB)
            db.execute("CREATE TABLE chats (id TEXT PRIMARY KEY, title TEXT, agent TEXT, session_id TEXT, "
                       "cwd TEXT, created REAL, updated REAL, model TEXT)")
            db.execute("INSERT INTO chats (id, title) VALUES ('legacy', 'Fixture')")
            db.commit()
            db.close()
            store = Store()
            self.assertIsNone(store.get("legacy")["permission_mode"])
            store.update("legacy", permission_mode="acceptEdits")
            store.db.close()
            store = Store()
            self.assertEqual(store.get("legacy")["permission_mode"], "acceptEdits")
            store.db.close()


class ModeLifecycleTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        with patch.object(daemon, "Store"), patch.object(daemon, "load_taint", return_value={}):
            self.d = daemon.Daemon()
        self.d.broadcast = AsyncMock()
        self.chat = {"id": "fixture", "agent": "claude", "model": "sonnet", "session_id": "session",
                     "permission_mode": "default"}
        self.d.store.get.return_value = self.chat
        self.d.store.create.return_value = self.chat
        self.b = Mock(busy=False, cfg={"permission_mode": "default"})
        self.b.close = AsyncMock()
        self.b.prompt = AsyncMock()
        self.d.backends["fixture"] = self.b

    async def test_idle_change_closes_agent_clears_chat_allows_and_preserves_session(self):
        self.d.chat_allows["fixture"] = {"Bash:fixture"}
        with patch.object(daemon.activity, "log"):
            r = await self.d.op_set_permission_mode({"chat": "fixture", "mode": "bypassPermissions"})
        self.assertEqual(r["mode"], "bypassPermissions")
        self.b.close.assert_awaited_once()
        self.assertNotIn("fixture", self.d.backends)
        self.assertNotIn("fixture", self.d.chat_allows)
        self.d.store.update.assert_called_once_with("fixture", permission_mode="bypassPermissions")
        self.assertEqual(self.chat["session_id"], "session")

    async def test_busy_or_starting_agent_cannot_change_mode(self):
        self.b.busy = True
        with self.assertRaisesRegex(ValueError, "Stop"):
            await self.d.op_set_permission_mode({"chat": "fixture", "mode": "bypassPermissions"})
        self.b.busy = False
        lock = self.d.chat_locks["fixture"]
        async with lock:
            with self.assertRaisesRegex(ValueError, "Wait"):
                await self.d.op_set_permission_mode({"chat": "fixture", "mode": "plan"})
        self.b.close.assert_not_awaited()
        self.d.store.update.assert_not_called()

    async def test_unknown_mode_or_chat_cannot_change_agent(self):
        with self.assertRaises(ValueError):
            await self.d.op_set_permission_mode({"chat": "fixture", "mode": "invalid"})
        self.d.store.get.return_value = None
        with self.assertRaisesRegex(ValueError, "Unknown chat"):
            await self.d.op_set_permission_mode({"chat": "missing", "mode": "plan"})
        self.b.close.assert_not_awaited()

    async def test_default_change_does_not_change_existing_chat(self):
        with patch.object(config, "set_default_permission_mode") as save, \
                patch.object(config, "default_permission_mode", return_value="bypassPermissions"):
            await self.d.op_set_default_permission_mode({"mode": "bypassPermissions"})
        save.assert_called_once_with("bypassPermissions")
        self.d.store.update.assert_not_called()
        self.b.close.assert_not_awaited()
        self.assertEqual(self.d.chat_permission_mode(self.chat), "default")

    async def test_new_chat_pins_selected_mode_before_launch(self):
        self.d.store.get.return_value = self.chat
        with patch.object(config, "load_state", return_value={"killed": False}), \
                patch.object(config, "default_model", return_value="sonnet"), \
                patch.object(daemon.attachments, "validate", return_value=[]), \
                patch.object(daemon.attachments, "summary", return_value=[]), \
                patch.object(daemon.asyncio, "to_thread", new_callable=AsyncMock, return_value="fixture"), \
                patch.object(daemon.access, "require"):
            await self.d.op_send({"text": "fixture", "permission_mode": "plan"})
        self.d.store.update.assert_any_call("fixture", permission_mode="plan")
        self.assertEqual(self.chat["permission_mode"], "plan")
        self.b.prompt.assert_awaited_once_with("fixture")

    async def test_send_holds_mode_lock_while_preparing_attachments(self):
        started = asyncio.Event()
        release = asyncio.Event()

        async def prepare(*args):
            started.set()
            await release.wait()
            return "fixture"

        with patch.object(config, "load_state", return_value={"killed": False}), \
                patch.object(daemon.attachments, "validate", return_value=[]), \
                patch.object(daemon.attachments, "summary", return_value=[]), \
                patch.object(daemon.asyncio, "to_thread", side_effect=prepare), \
                patch.object(daemon.access, "require"):
            task = asyncio.create_task(self.d.op_send({"chat": "fixture", "text": "fixture"}))
            await started.wait()
            try:
                with self.assertRaisesRegex(ValueError, "Wait"):
                    await self.d.op_set_permission_mode({"chat": "fixture", "mode": "bypassPermissions"})
            finally:
                release.set()
                await task
        self.b.close.assert_not_awaited()

    async def test_invalid_send_never_creates_a_chat(self):
        with patch.object(config, "load_state", return_value={"killed": False}), \
                patch.object(daemon.attachments, "validate", return_value=[]):
            with self.assertRaises(ValueError):
                await self.d.op_send({"text": "fixture", "permission_mode": "invalid"})
        self.d.store.create.assert_not_called()

    async def test_dont_ask_denies_even_when_tainted_or_saved_allow_exists(self):
        self.b.cfg["permission_mode"] = "dontAsk"
        self.d.taint["fixture"] = {"source": "fixture"}
        with patch.object(config, "load_state", return_value={"killed": False}), \
                patch.object(daemon.rules, "decide", return_value="allow"):
            self.assertEqual(self.d.auto_decision("fixture", {"tool": "Bash", "input": {}}),
                             (False, "dontAsk"))

    async def test_native_auto_or_bypass_exceptions_still_ask_the_user(self):
        for mode in ("auto", "bypassPermissions", "plan", "acceptEdits", "default"):
            self.b.cfg["permission_mode"] = mode
            with patch.object(config, "load_state", return_value={"killed": False}), \
                    patch.object(daemon.rules, "decide", return_value=None):
                self.assertIsNone(self.d.auto_decision("fixture", {"tool": "AskUserQuestion", "input": {}}))

    async def test_resumed_agent_receives_persisted_mode(self):
        self.d.backends.clear()
        self.chat["permission_mode"] = "acceptEdits"
        cfg = {"agents": {"claude": {"path": "fixture", "permission_mode": "default"}}}
        with patch.object(config, "load_config", return_value=cfg):
            b = self.d.backend_for(self.chat)
        self.assertEqual(b.cfg["permission_mode"], "acceptEdits")
        self.assertEqual(b.session_id, "session")

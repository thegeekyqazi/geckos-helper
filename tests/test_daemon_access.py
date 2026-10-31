import unittest
from unittest.mock import AsyncMock, Mock, patch

from geckos_helper import config, daemon


async def immediate(fn,*args): return fn(*args)


class DaemonAccessTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.state={'killed':False,'capabilities':{key:True for key in config.CAPABILITIES}}
        for p in (patch.object(config,'load_state',side_effect=lambda:self.state),
                  patch.object(daemon,'Store'),patch.object(daemon,'load_taint',return_value={}),
                  patch.object(daemon.asyncio,'to_thread',side_effect=immediate)):
            p.start(); self.addCleanup(p.stop)
        self.d=daemon.Daemon()
        self.d.broadcast=AsyncMock()

    async def test_quick_actions_obey_kill_and_each_capability(self):
        for action,cap,module,name in [('todo','todo_write',daemon.todo,'add'),('note','notes',daemon.notes,'add'),('idea','obsidian_write',daemon.obsidian,'capture_idea')]:
            for killed in (False,True):
                self.state['killed']=killed
                self.state['capabilities'][cap]=False
                with self.subTest(action=action,killed=killed),patch.object(module,name) as write,patch.object(daemon.notes,'available',return_value=True):
                    with self.assertRaises(PermissionError):
                        await self.d.op_quick({'action':action,'text':'fixture'})
                    write.assert_not_called()

    async def test_allowed_shortcut_still_works(self):
        with patch.object(daemon.todo,'add',return_value={'text':'fixture'}),patch.object(daemon.activity,'log'):
            self.assertEqual((await self.d.op_quick({'action':'todo','text':'fixture'}))['result']['text'],'fixture')

    async def test_clipboard_capture_cannot_bypass_disabled_capability(self):
        self.state['capabilities']['clipboard_read']=False
        with patch.object(daemon.attachments,'capture') as capture:
            for kind in ('clipboard','selection'):
                with self.assertRaises(PermissionError):await self.d.op_capture({'kind':kind})
            capture.assert_not_called()

    async def test_inbox_and_export_do_not_bypass_access(self):
        self.state['killed']=True
        with self.assertRaises(PermissionError):await self.d.op_inbox({'add_todos':'fixture','todos':['fixture']})
        with patch.object(daemon.handoff_export,'brief') as brief:
            with self.assertRaises(PermissionError):await self.d.op_export({'chat':'fixture','mode':'brief'})
            brief.assert_not_called()
        self.d.store.inbox.assert_not_called()

    async def test_calendar_and_projects_reads_are_gated(self):
        self.state['killed']=True
        with patch.object(daemon.calendar,'events') as events,patch.object(daemon.projects,'list_projects') as projects:
            with self.assertRaises(PermissionError):await self.d.op_calendar({})
            with self.assertRaises(PermissionError):await self.d.op_projects({})
            events.assert_not_called();projects.assert_not_called()

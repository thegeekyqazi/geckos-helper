import asyncio
import tempfile
import unittest
from pathlib import Path
from unittest.mock import AsyncMock, Mock, patch

from geckos_helper.backends.claude import ClaudeBackend
from geckos_helper.backends import claude


class BackendShutdownTests(unittest.IsolatedAsyncioTestCase):
    async def test_kill_during_spawn_cannot_start_a_late_agent(self):
        started=asyncio.Event();release=asyncio.Event()
        proc=Mock(returncode=None)
        async def spawn(*args,**kwargs):
            started.set();await release.wait();return proc
        async def stop(p):p.returncode=-15
        with tempfile.TemporaryDirectory() as td,patch.object(claude,'STDERR_LOG',Path(td)/'stderr.log'),patch.object(claude.access,'require'),patch.object(claude.asyncio,'create_subprocess_exec',side_effect=spawn),patch.object(claude.agent_process,'stop',side_effect=stop):
            b=ClaudeBackend(AsyncMock(),{})
            b.argv=lambda:['fixture']
            prompt=asyncio.create_task(b.prompt('fixture'))
            await started.wait()
            closing=asyncio.create_task(b.close())
            await asyncio.sleep(0)
            release.set()
            await closing
            with self.assertRaises(PermissionError):await prompt
            self.assertIsNotNone(proc.returncode)
            self.assertIsNone(b._reader)

    async def test_stopped_backend_cannot_be_reused(self):
        b=ClaudeBackend(AsyncMock(),{})
        await b.close()
        with patch.object(claude.access,'require'),self.assertRaises(PermissionError):
            await b.prompt('fixture')

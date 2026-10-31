import asyncio
import os
import sys
import unittest
from unittest.mock import patch

from geckos_helper import agent_process


class AgentProcessTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        p=patch.object(agent_process.access,'require')
        p.start();self.addCleanup(p.stop)

    async def test_normal_completion_reaps_process(self):
        out,err,status=await agent_process.run([sys.executable,'-c','import sys; print(sys.stdin.read())'],'fixture',3)
        self.assertEqual(status,0)
        self.assertEqual(out.strip(),b'fixture')
        self.assertEqual(agent_process.ACTIVE,set())

    async def test_timeout_reaps_real_process(self):
        spawned=[]
        original=asyncio.create_subprocess_exec
        async def spawn(*args,**kwargs):
            proc=await original(*args,**kwargs);spawned.append(proc);return proc
        with patch.object(agent_process.asyncio,'create_subprocess_exec',side_effect=spawn):
            with self.assertRaises(TimeoutError):
                await agent_process.run([sys.executable,'-c','import time; time.sleep(60)'],'',0.05)
        self.assertIsNotNone(spawned[0].returncode)
        with self.assertRaises(ProcessLookupError):os.kill(spawned[0].pid,0)

    async def test_stop_all_handles_cancellation_during_spawn(self):
        original=asyncio.create_subprocess_exec
        spawning=asyncio.Event();release=asyncio.Event();spawned=[]
        async def spawn(*args,**kwargs):
            spawning.set();await release.wait()
            proc=await original(*args,**kwargs);spawned.append(proc);return proc
        with patch.object(agent_process.asyncio,'create_subprocess_exec',side_effect=spawn):
            job=asyncio.create_task(agent_process.run([sys.executable,'-c','import time; time.sleep(60)'],'',60))
            await spawning.wait()
            stop=asyncio.create_task(agent_process.stop_all())
            await asyncio.sleep(0)
            release.set()
            await asyncio.wait_for(stop,4)
            self.assertTrue(job.cancelled())
        self.assertIsNotNone(spawned[0].returncode)
        self.assertEqual(agent_process.ACTIVE,set())

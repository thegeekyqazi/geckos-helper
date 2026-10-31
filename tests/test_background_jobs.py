import asyncio
import unittest
from unittest.mock import AsyncMock, patch

from geckos_helper import config, daemon


class BackgroundTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.state={'killed':False,'capabilities':{'watchers':True,'recipes':True}}
        for p in (patch.object(config,'load_state',side_effect=lambda:self.state),
                  patch.object(daemon,'Store'),patch.object(daemon,'load_taint',return_value={}),
                  patch.object(daemon.activity,'log')):
            p.start();self.addCleanup(p.stop)
        self.d=daemon.Daemon();self.d.broadcast=AsyncMock();self.d.budget_ok=lambda:True
        self.item={'id':'fixture','name':'Fixture','prompt':'Fixture'}

    async def test_killed_and_budget_exhausted_jobs_never_run(self):
        with patch.object(daemon.watchers,'run',new_callable=AsyncMock) as run:
            self.state['killed']=True
            await self.d.run_watcher(self.item)
            self.state['killed']=False;self.d.budget_ok=lambda:False
            await self.d.run_watcher(self.item)
            run.assert_not_called()
            with self.assertRaises(PermissionError):self.d.queue_background('watcher',self.item)

    async def test_budget_rechecked_after_waiting_and_no_duplicate_queue(self):
        await self.d.watcher_lock.acquire()
        with patch.object(daemon.watchers,'run',new_callable=AsyncMock) as run:
            self.d.queue_background('watcher',self.item)
            self.d.queue_background('watcher',self.item)
            self.assertEqual(len(self.d.background_tasks),1)
            tasks=list(self.d.background_tasks.values())
            self.d.budget_ok=lambda:False
            self.d.watcher_lock.release()
            await asyncio.gather(*tasks)
            run.assert_not_called()

    async def test_kill_cancels_running_and_queued_jobs(self):
        started=asyncio.Event()
        async def run(item):
            started.set();await asyncio.Event().wait()
        with patch.object(daemon.watchers,'run',side_effect=run),patch.object(config,'set_killed',side_effect=lambda on:self.state.update(killed=on)),patch.object(daemon.context,'generate_lite'),patch.object(daemon.agent_process,'stop_all',new_callable=AsyncMock) as stop:
            self.d.queue_background('watcher',self.item)
            self.d.queue_background('watcher',{**self.item,'id':'queued'})
            tasks=list(self.d.background_tasks.values())
            await started.wait()
            await self.d.op_kill({'on':True})
            self.assertTrue(all(t.cancelled() for t in tasks))
            self.assertEqual(self.d.background_tasks,{})
            stop.assert_awaited_once()

    async def test_final_budget_slot_does_not_start_next_job(self):
        remaining=[True]
        self.d.budget_ok=lambda:remaining[0]
        async def run(item):
            remaining[0]=False
            return {'name':item['name']}
        with patch.object(daemon.watchers,'run',side_effect=run) as launch:
            self.d.queue_background('watcher',self.item)
            self.d.queue_background('watcher',{**self.item,'id':'second'})
            await asyncio.gather(*list(self.d.background_tasks.values()))
            self.assertEqual(launch.await_count,1)

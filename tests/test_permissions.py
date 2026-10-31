import unittest
from unittest.mock import AsyncMock, Mock, patch

from geckos_helper import daemon, rules


class RuleTests(unittest.TestCase):
    def test_new_always_rule_only_matches_exact_arguments(self):
        name='mcp__gecko__calendar_delete_event'
        pattern=rules.exact_pattern(name,{'event_id':'fixture[*]?'})
        with patch.object(rules,'load',return_value=[{'match':pattern,'action':'allow'}]):
            self.assertEqual(rules.decide(name,{'event_id':'fixture[*]?'}),'allow')
            self.assertIsNone(rules.decide(name,{'event_id':'other'}))

    def test_explicit_broad_rules_and_last_match_still_work(self):
        name='mcp__gecko__fixture'
        with patch.object(rules,'load',return_value=[{'match':name,'action':'allow'},
                    {'match':rules.exact_pattern(name,{'x':1}),'action':'deny'}]):
            self.assertEqual(rules.decide(name,{'x':1}),'deny')
            self.assertEqual(rules.decide(name,{'x':2}),'allow')


class PermissionLifecycleTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        with patch.object(daemon,'Store'),patch.object(daemon,'load_taint',return_value={}):
            self.d=daemon.Daemon()
        self.d.broadcast=AsyncMock()
        self.d.pending={'fixture':'chat'};self.d.request_info={'fixture':{'tool':'fixture'}}
        self.d.backends={'chat':Mock()}
        self.d.chat_allows={'chat':{'fixture'}}

    async def test_closed_agent_expires_pending_approvals(self):
        await self.d.emitter('chat')('closed',{})
        self.assertEqual(self.d.pending,{})
        self.assertEqual(self.d.request_info,{})
        self.assertEqual(self.d.chat_allows,{'chat':{'fixture'}})
        resolved=[c.args[0] for c in self.d.broadcast.await_args_list if c.args[0]['event']=='permission_resolved']
        self.assertEqual(resolved[0]['request_id'],'fixture')
        with self.assertRaisesRegex(ValueError,'expired'):
            await self.d.op_permission({'request_id':'fixture','allow':False})

    async def test_kill_overrides_saved_allows(self):
        with patch.object(daemon.config,'load_state',return_value={'killed':True}),patch.object(rules,'decide',return_value='allow'):
            self.assertEqual(self.d.auto_decision('chat',{'tool':'fixture','input':{}}),(False,'kill_switch'))

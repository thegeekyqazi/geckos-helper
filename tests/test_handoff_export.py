import unittest
from unittest.mock import AsyncMock, Mock, patch

from geckos_helper import config, daemon, handoff_export as export


async def immediate(fn, *args):
    return fn(*args)


class HandoffTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.entries = [
            {'kind': 'user_message', 'text': 'GOAL: diagnose sample config; never edit it',
             'attachments': [{'kind': 'image', 'name': 'sample.png', 'path': '/missing/sample.png'}]},
            {'kind': 'tool_call', 'id': 'read1', 'name': 'Read', 'title': 'Read sample',
             'input': {'file_path': '/missing/settings.toml'}},
            {'kind': 'tool_call_update', 'id': 'read1', 'status': 'completed', 'output': 'UNIQUE_EVIDENCE: width=470'},
            {'kind': 'tool_call_update', 'id': 'write2', 'status': 'failed', 'output': 'Denied by user; no changes'},
            {'kind': 'error', 'message': 'Validation unavailable'},
            {'kind': 'agent_message', 'text': 'Proposed change only. RECENT_STATE'},
        ]
        self.store = Mock()
        self.store.get.return_value = {'title': 'Synthetic chat'}
        self.store.transcript.return_value = self.entries
        self.runner = AsyncMock(return_value=(b'## User goal\nExplain the config using supplied evidence.', b'', 0))
        p = patch.object(export.agent_process, 'run', self.runner)
        p.start(); self.addCleanup(p.stop)
        p = patch.object(export, 'load_config', return_value={'agents': {'claude': {'path': '/fake/claude'}}})
        p.start(); self.addCleanup(p.stop)

    async def test_evidence_and_unavailable_attachments_survive_without_reading_files(self):
        with patch('pathlib.Path.read_text', side_effect=AssertionError('No files may be read')):
            result = await export.prepare(self.store, 'fixture')
        for snippet in ('UNIQUE_EVIDENCE', 'Denied by user; no changes', '(failed)',
                        'sample.png', 'contents NOT included', 'no access', 'Paths below are references'):
            self.assertIn(snippet, result['text'])
        prompt = self.runner.call_args.args[1]
        for snippet in ('GOAL:', 'UNIQUE_EVIDENCE', '/missing/settings.toml', 'RECENT_STATE'):
            self.assertIn(snippet, prompt)
        self.assertEqual(self.runner.call_args.kwargs['capability'], 'clipboard_write')
        argv = self.runner.call_args.args[0]
        self.assertEqual(argv[argv.index('--tools') + 1], '')

    async def test_long_source_preserves_original_goal_recent_state_and_reports_loss(self):
        self.entries.insert(1, {'kind': 'agent_message', 'text': 'middle ' * 30_000})
        result = await export.prepare(self.store, 'fixture')
        prompt = self.runner.call_args.args[1]
        self.assertIn('GOAL:', prompt)
        self.assertIn('RECENT_STATE', prompt)
        self.assertIn(export.OMISSION, prompt)
        self.assertIn('Conversation shortened', result['text'])

    async def test_long_evidence_and_attachment_lists_disclose_omissions(self):
        self.entries[2]['output'] = 'BEGIN_RESULT' + 'x' * 40_000 + 'END_RESULT'
        self.entries[0]['attachments'] *= 2  # duplicate metadata is only exported once
        result = await export.prepare(self.store, 'fixture')
        self.assertIn('BEGIN_RESULT', result['text'])
        self.assertIn('END_RESULT', result['text'])
        self.assertIn('evidence appendix shortened', result['text'])
        self.assertEqual(result['text'].count('sample.png'), 2)  # name and path, one item

    async def test_model_failure_or_empty_result_does_not_produce_fake_brief(self):
        for result in ((b'', b'fixture failure', 1), (b'  ', b'', 0)):
            self.runner.return_value = result
            with self.assertRaises(RuntimeError):
                await export.prepare(self.store, 'fixture')

    def test_raw_transcript_keeps_evidence_and_does_not_require_model(self):
        result = export.transcript(self.store, 'fixture')
        self.assertIn('UNIQUE_EVIDENCE', result)
        self.assertIn('contents NOT included', result)
        self.runner.assert_not_called()
        self.store.get.return_value = None
        with self.assertRaises(ValueError):
            export.transcript(self.store, 'missing')

    async def test_preview_never_copies_and_edited_copy_rechecks_access(self):
        with patch.object(daemon, 'Store', return_value=self.store), patch.object(daemon, 'load_taint', return_value={}):
            d = daemon.Daemon()
        state = {'killed': False, 'capabilities': {'clipboard_write': True}}
        with (patch.object(config, 'load_state', side_effect=lambda: state),
              patch.object(export, 'to_clipboard') as copy,
              patch.object(daemon.asyncio, 'to_thread', side_effect=immediate)):
            result = await d.op_export({'chat': 'fixture', 'mode': 'brief', 'preview': True})
            self.assertIn('no access', result['text'])
            copy.assert_not_called()
            await d.op_copy_handoff({'text': 'User edited preview'})
            copy.assert_called_once_with('User edited preview')
            state['killed'] = True
            with self.assertRaises(PermissionError):
                await d.op_copy_handoff({'text': 'Do not copy'})
            copy.assert_called_once()
            state['killed'] = False
            state['capabilities']['clipboard_write'] = False
            with self.assertRaises(PermissionError):
                await d.op_copy_handoff({'text': 'Do not copy'})
            for invalid in ('', '  ', None, 'x' * 1_000_001):
                with self.assertRaises(ValueError):
                    await d.op_copy_handoff({'text': invalid})

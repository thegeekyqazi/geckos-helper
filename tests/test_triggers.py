import tempfile
import unittest
from datetime import datetime, timedelta
from pathlib import Path
from unittest.mock import patch

from geckos_helper import triggers


def recipe(rid, kind, value):
    return {'id':rid,'enabled':True,'triggers':[{'type':kind,'value':value}]}


class TriggerTests(unittest.TestCase):
    def setUp(self):
        self.state=patch.object(triggers,'load_state',return_value={'killed':False})
        self.state.start()
        self.addCleanup(self.state.stop)

    def test_shared_folder_fans_out_once_per_recipe(self):
        with tempfile.TemporaryDirectory() as td:
            items=[recipe('a','file_added',td),recipe('b','file_added',td)]
            t=triggers.Triggers()
            with patch.object(triggers.recipes,'load',return_value=items):
                self.assertEqual(t.poll(),[])
                (Path(td)/'fixture.md').write_text('fixture')
                self.assertEqual([r['id'] for r,why in t.poll()],['a','b'])
                self.assertEqual(t.poll(),[])

    def test_battery_thresholds_are_independent(self):
        items=[recipe('a','battery_below',15),recipe('b','battery_below',15),recipe('c','battery_below',10)]
        t=triggers.Triggers()
        with patch.object(triggers.recipes,'load',return_value=items),patch.object(triggers.system,'battery',return_value={'status':'Discharging','percent':9}):
            self.assertEqual([r['id'] for r,why in t.poll()],['a','b','c'])
            self.assertEqual(t.poll(),[])

    def test_event_thresholds_do_not_consume_each_other(self):
        items=[recipe('a','event_soon',15),recipe('b','event_soon',15),recipe('c','event_soon',10)]
        t=triggers.Triggers()
        event={'calendar':'Fixture','id':'fixture','start':(datetime.now().astimezone()+timedelta(minutes=5)).isoformat(),'title':'Fixture'}
        with patch.object(triggers.recipes,'load',return_value=items),patch.object(triggers.calendar,'events',return_value=[event]):
            self.assertEqual([r['id'] for r,why in t.poll()],['a','b','c'])

    def test_kill_does_not_consume_trigger_events(self):
        with patch.object(triggers,'load_state',return_value={'killed':True}),patch.object(triggers.recipes,'load') as load:
            self.assertEqual(triggers.Triggers().poll(),[])
            load.assert_not_called()

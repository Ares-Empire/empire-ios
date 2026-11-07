"""Fast checks for assertion and catalog failure modes; no simulator required."""
import json
import itertools
import os
from pathlib import Path
import tempfile
import signal
import subprocess
import sys
import time
import unittest
from unittest.mock import patch

from run import Catalog, Runner, SmokeFailure, WORK, cleanup, command
from scenarios.aresium import cents


class RunnerTests(unittest.TestCase):
    def setUp(self):
        WORK.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=WORK)
        self.addCleanup(self.temp.cleanup)
        self.runner = Runner('owned-test-id', 'Empire', 'sample.bundle', Path(self.temp.name), 'en')

    def test_noop_tap_cannot_pass_an_already_true_assertion(self):
        before = [{'AXLabel': 'Provinces', 'type': 'StaticText'}]
        self.runner.pending = ('tap province', before)
        with self.assertRaisesRegex(SmokeFailure, 'already true before'):
            self.runner.expect('Provinces')

    def test_tap_requires_observed_change_even_when_axe_reports_success(self):
        before = [{'AXLabel': 'Settings', 'type': 'Button',
                   'frame': dict(x=10, y=10, width=44, height=44)}]
        self.runner.tree = before
        with patch.object(self.runner, 'describe', return_value=before), patch('run.command', return_value=(0, 'success')):
            self.runner.tap('Settings', type='Button')
            with self.assertRaisesRegex(SmokeFailure, 'Unverified action'):
                self.runner.tap('Settings')
            with self.assertRaisesRegex(SmokeFailure, 'Unverified final action'):
                self.runner.finish()

    def test_first_describe_error_is_retried_and_real_transition_clears_pending(self):
        after = [{'AXLabel': 'Provinces', 'type': 'StaticText'}]
        self.runner.pending = ('tap province', [])
        outcomes = itertools.chain([SmokeFailure('remote automation session timeout')], itertools.repeat(after))
        with patch.object(self.runner, 'describe', side_effect=outcomes):
            self.runner.wait_for('Provinces', timeout=3)
        self.assertIsNone(self.runner.pending)

    def test_absence_assertion_requires_previous_presence(self):
        self.runner.pending = ('tap Close', [{'AXLabel': 'Provinces'}])
        with patch.object(self.runner, 'describe', return_value=[]):
            self.runner.expect('Provinces', present=False)
        self.assertIsNone(self.runner.pending)

    def test_identifier_value_and_type_are_all_checked(self):
        selector = self.runner.selector(id='field', type='TextField', value='typed')
        self.assertFalse(self.runner.matches([{'AXUniqueId': 'field', 'type': 'Button', 'AXValue': 'typed'}], selector))
        self.assertFalse(self.runner.matches([{'AXUniqueId': 'field', 'type': 'TextField', 'AXValue': ''}], selector))
        self.assertTrue(self.runner.matches([{'AXUniqueId': 'field', 'type': 'TextField', 'AXValue': 'typed note'}], selector))

    def test_offscreen_content_cannot_satisfy_presence(self):
        tree = [{'AXLabel': 'Far below', 'frame': dict(x=0, y=1500, width=100, height=20)}]
        self.assertFalse(self.runner.matches(tree, self.runner.selector('Far below')))

    def test_zero_application_frame_does_not_hide_real_sheet_controls(self):
        tree = [{'type': 'Application', 'AXLabel': None, 'pid': 123,
                 'frame': dict(x=0, y=0, width=0, height=0), 'children': [
                     {'AXLabel': 'Light', 'type': 'Button',
                      'frame': dict(x=20, y=230, width=360, height=50)}]}]
        self.assertTrue(self.runner.matches(tree, self.runner.selector('Light', type='Button')))
        self.assertTrue(self.runner.matches(tree, self.runner.selector('Empire', type='Application', pid=123)))
        self.assertFalse(self.runner.matches(tree, self.runner.selector('Empire', type='Application', pid=456)))

    def test_empty_axe_tree_cannot_replace_last_valid_snapshot(self):
        self.runner.tree = [{'type': 'Application', 'AXLabel': 'Empire'}]
        with patch('run.command', return_value=(0, '[]')):
            with self.assertRaisesRegex(SmokeFailure, 'no application tree'):
                self.runner.describe()
        self.assertEqual(self.runner.tree[0]['AXLabel'], 'Empire')

    def test_selected_category_uses_its_own_checkmark(self):
        selector = self.runner.selector('Sample category', child_id='checkmark')
        self.assertFalse(self.runner.matches([{'AXLabel': 'Sample category'}], selector))
        self.assertTrue(self.runner.matches([{'AXLabel': 'Sample category', 'children': [
            {'AXUniqueId': 'checkmark', 'type': 'Image'}]}], selector))

    def test_command_does_not_wait_for_inherited_stdout_to_close(self):
        code = ('import subprocess,sys; p=subprocess.Popen([sys.executable,"-c","import time; time.sleep(30)"], '
                'start_new_session=True); print(p.pid,flush=True)')
        started = time.monotonic()
        _, output = command([sys.executable, '-c', code], timeout=2)
        child = int(output.strip())
        try:
            self.assertLess(time.monotonic() - started, 3)
        finally:
            os.kill(child, signal.SIGKILL)

    def test_command_timeout_reaps_the_command(self):
        started = time.monotonic()
        with self.assertRaises(subprocess.TimeoutExpired):
            command([sys.executable, '-c', 'import time; time.sleep(30)'], timeout=.1)
        self.assertLess(time.monotonic() - started, 2)

    def test_delete_is_attempted_even_when_shutdown_times_out(self):
        with patch('run.command', side_effect=[subprocess.TimeoutExpired('shutdown', 45), (0, '')]) as run_command, patch('builtins.print'):
            self.assertTrue(cleanup('owned-device', 'smoke-owned-name'))
        self.assertEqual(run_command.call_args_list[1].args[0], ['xcrun', 'simctl', 'delete', 'owned-device'])

    def test_missing_and_ambiguous_german_fail_and_table_resolves_conflict(self):
        catalog = Catalog('Aresus', 'de')
        with self.assertRaisesRegex(SmokeFailure, 'No German catalog entry'):
            catalog.label('smoke missing translation')
        with self.assertRaisesRegex(SmokeFailure, 'Ambiguous German'):
            catalog.label('Done')
        self.assertEqual(catalog.label('Done', table='Shared'), 'Fertig')
        self.assertEqual(catalog.label('Done', table='Localizable'), 'Erledigt')
        self.assertEqual(catalog.label('Made-up sample title', literal=True), 'Made-up sample title')

    def test_waiting_count_uses_catalog_plural_forms_in_both_languages(self):
        key = '%lld quick notes waiting to be sent'
        self.assertEqual(Catalog('Arestoteles', 'en').label(key, count=1), '1 quick note waiting to be sent')
        self.assertEqual(Catalog('Arestoteles', 'de').label(key, count=1), '1 Notiz wartet auf das Senden')
        self.assertEqual(Catalog('Arestoteles', 'de').label(key, count=2), '2 Notizen warten auf das Senden')

    def test_payment_and_overview_amounts_use_the_app_language(self):
        for label, language, expected in [('1, Sample shop, −40.66', 'en', 4066),
                                          ('1, Sample shop, −40,66', 'de', 4066),
                                          ('Sample category, €3,030', 'en', 303000),
                                          ('Sample category, 3.030 €', 'de', 303000)]:
            with self.subTest(label=label):
                self.assertEqual(cents(label, language), expected)

    def test_failure_report_keeps_step_and_ui_even_if_capture_fails(self):
        self.runner.current = '3: expected changed screen'
        self.runner.tree = [{'AXLabel': 'Visible sample'}]
        with patch.object(self.runner, 'describe', side_effect=SmokeFailure('AXe unavailable')), patch('run.command', side_effect=SmokeFailure('capture unavailable')), patch('builtins.print'):
            report = self.runner.failure('wrong screen')
        self.assertEqual(report['step'], self.runner.current)
        self.assertEqual(report['visible_labels'], ['Visible sample'])
        self.assertEqual(len(report['capture_errors']), 2)
        self.assertEqual(json.loads(Path(report['describe_ui']).read_text()), self.runner.tree)


if __name__ == '__main__':
    unittest.main()

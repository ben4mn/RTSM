"""Pure adversarial evidence tests; no browser, game, or retained-report mutation."""
import copy
import tempfile
import unittest
from pathlib import Path

from analyze_live_browser_multiplayer import lobby_tap_actions
from beta2_browser_evidence import INITIAL_OFF_HARNESS, beta2_gates, initial_scout_policy_off
from test_beta2_browser_evidence import fixture, write


def tap(purpose, when):
    return {'id': purpose, 'kind': 'tap', 'purpose': purpose, 'unix': when,
            'x': 100, 'y': 100, 'native_api': 'CDP.Input.dispatchTouchEvent', 'contact_id': 0,
            'dispatches': [
                {'type': 'touchStart', 'touchPoints': [{'id': 0, 'x': 100, 'y': 100}],
                 'started_unix': when-3, 'acknowledged_unix': when-2, 'acknowledged': True},
                {'type': 'touchEnd', 'touchPoints': [], 'started_unix': when-1,
                 'acknowledged_unix': when, 'acknowledged': True}]}


class LobbyTests(unittest.TestCase):
    def bundle(self, role, aliases=True):
        labels = (['create_private_room', 'start_matched_game'] if aliases else ['lobby_create', 'lobby_start']) if role == 'host' else (['join_private_room'] if aliases else ['lobby_join'])
        operations = ['host', 'room_start'] if role == 'host' else ['join']
        inputs = [tap(label, 1000+i*1000) for i, label in enumerate(labels)]
        wire = [{'unix': row['unix']+50, 'packet': {'op': op}} for row, op in zip(inputs, operations)]
        return inputs, wire

    def test_canonical_and_exact_aliases_for_both_roles(self):
        for role in ('host', 'guest'):
            for aliases in (False, True):
                self.assertTrue(lobby_tap_actions(role, *self.bundle(role, aliases), strict_native=True))

    def test_alias_does_not_replace_native_causal_evidence(self):
        for role in ('host', 'guest'):
            for mutate in (
                lambda i,w: i[0].update(purpose='arbitrary_label'),
                lambda i,w: i[0].update(kind='click'),
                lambda i,w: i[0].pop('dispatches'),
                lambda i,w: i[0]['dispatches'][1].update(acknowledged=False),
                lambda i,w: w[0]['packet'].update(op='search'),
                lambda i,w: w[0].update(unix=i[0]['unix']-1),
                lambda i,w: w[0].update(unix=i[0]['unix']+5001),
                lambda i,w: w[0].update(unix=str(w[0]['unix'])),
                lambda i,w: w.clear(),
            ):
                inputs, wire = self.bundle(role); mutate(inputs, wire)
                self.assertFalse(lobby_tap_actions(role, inputs, wire, strict_native=True))

    def test_legacy_canonical_behavior_preserved_without_new_aliases(self):
        for role in ('host', 'guest'):
            inputs, wire = self.bundle(role, False)
            for row in inputs: row.pop('dispatches')
            self.assertTrue(lobby_tap_actions(role, inputs, wire))
            self.assertFalse(lobby_tap_actions(role, *self.bundle(role, True)))


class InitialPolicyTests(unittest.TestCase):
    def bundle(self):
        ui = {'op': 'command', 'command': 'train', 'type': 4, 'sequence': 1, 'match': 7}
        paid = {'op': 'command', 'command': 'allocate', 'sequence': 2, 'match': 7}
        return {
            'row': {'action': 'scout_train', 'policy_held': True, 'started_unix': 1000, 'finished_unix': 1500},
            'starts': [{'unix': 2000}], 'policy': [{'unix': 2100, 'sent': True}],
            'origins': [{'serial': 1, 'packet': ui, 'source': 'game_ui_or_engine'}, {'serial': 2, 'packet': paid, 'source': 'paid_policy'}],
            'wire': [{'unix': 1100, 'packet': ui}, {'unix': 2100, 'packet': paid}],
            'invocation': {'harness_sha256': INITIAL_OFF_HARNESS}}

    def test_initial_scout_actions_and_later_classified_policy(self):
        for action in ('scout_train', 'scout_birth'):
            bundle = self.bundle(); bundle['row']['action'] = action
            self.assertTrue(initial_scout_policy_off(**bundle))

    def test_rejects_missing_held_source_or_first_start(self):
        for mutate in (
            lambda b: b['row'].update(action='workshop_open'),
            lambda b: b['row'].update(policy_held=False),
            lambda b: b['row'].pop('policy_held'),
            lambda b: b['invocation'].update(harness_sha256='a'*64),
            lambda b: b['invocation'].clear(),
            lambda b: b['starts'].clear(),
            lambda b: b['starts'][0].update(unix='2000'),
            lambda b: b['starts'][0].update(unix=True),
            lambda b: b['starts'][0].update(unix=2000.0),
            lambda b: b['row'].update(finished_unix=2000),
            lambda b: b['row'].update(finished_unix=2001),
            lambda b: b['row'].update(started_unix=2200, finished_unix=2300),
        ):
            bundle = self.bundle(); mutate(bundle)
            self.assertFalse(initial_scout_policy_off(**bundle))

    def test_prior_policy_and_ambiguous_or_missing_origins_fail_closed(self):
        for mutate in (
            lambda b: b['policy'].append({'unix': 900, 'sent': True}),
            lambda b: b['policy'].append({'unix': 1700, 'sent': True}),
            lambda b: b['wire'][1].update(unix=900),
            lambda b: b['wire'][1].update(unix=1700),
            lambda b: b['wire'].pop(),
            lambda b: b['origins'].pop(0),
            lambda b: b['origins'].append(copy.deepcopy(b['origins'][0])),
            lambda b: b['origins'][0].update(source='unknown'),
            lambda b: b['origins'][0].update(serial=99),
            lambda b: b['wire'].append({'unix': 800, 'packet': {'op': 'command', 'sequence': 99}}),
            lambda b: b['starts'][0].update(unix=3000),
        ):
            bundle = self.bundle(); mutate(bundle)
            self.assertFalse(initial_scout_policy_off(**bundle))

    def test_complete_both_slot_fixture_and_later_pause_boundary(self):
        for slot in (0, 1):
            with tempfile.TemporaryDirectory() as tmp:
                folder=Path(tmp); files, invocation, role=fixture(folder, slot)
                invocation['harness_sha256']=INITIAL_OFF_HARNESS
                files['policy-starts.jsonl']=[{'unix':125000,'reason':'Begin paid policy after initial native Scout births'}]
                files['policy-pauses.jsonl']=[{'unix':126000,'reason':'Hold normal scripts before later isolated UI proof'}]
                write(folder, files)
                self.assertTrue(all(beta2_gates(folder, invocation, role, slot).values()))
                for changed in ([], [{'unix':135000,'reason':'Too late to cover the Workshop opening stage'}]):
                    mutant=copy.deepcopy(files); mutant['policy-pauses.jsonl']=changed;write(folder,mutant)
                    self.assertFalse(beta2_gates(folder,invocation,role,slot)['beta2_policy_pauses_disclosed'])
                mutant=copy.deepcopy(files);mutant['policy-starts.jsonl'].append({'unix':130500,'reason':'Restart overlaps the later isolated Workshop stage'});write(folder,mutant)
                self.assertFalse(beta2_gates(folder,invocation,role,slot)['beta2_policy_pauses_disclosed'])


if __name__ == '__main__':
    unittest.main()

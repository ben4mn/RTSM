"""Pure synthetic protocol counterexamples; no browser or game launch."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from protocol_evidence import protocol_number, protocol_declared, sealed_protocol
from analyze_live_browser_multiplayer import analyze, protocol3_gates
from beta2_browser_evidence import beta2_gates
from test_beta2_browser_evidence import fixture, write


class ProtocolEvidenceTests(unittest.TestCase):
    def test_wire_integral_numbers_and_explicit_release_declaration(self):
        for value in (2, 2.0, 3, 3.0):
            self.assertEqual(protocol_number(value), int(value))
        for value in (None, True, False, '3', 3.5, float('inf'), float('nan'), 4):
            self.assertIsNone(protocol_number(value))
        self.assertTrue(protocol_declared({'protocol': 2}))
        self.assertTrue(protocol_declared({'protocol': 3, 'expected_protocol': 3}))
        for invocation in ({}, {'protocol': 3}, {'protocol': 3, 'expected_protocol': 2}, {'protocol': True}):
            self.assertFalse(protocol_declared(invocation))

    def test_sealed_exact_version_bytes_and_strict_metadata(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            invocation = {'protocol': 3, 'expected_protocol': 3}
            self.assertFalse(sealed_protocol(folder, invocation, {}))
            self.assertTrue(sealed_protocol(folder, {'protocol': 2}, {}))
            for value in (3, 3.0, 2, '3', True, None):
                raw = json.dumps({'network_protocol': value}).encode()
                (folder / 'sealed-version.json').write_bytes(raw)
                hashes = {'version.json': hashlib.sha256(raw).hexdigest()}
                self.assertEqual(sealed_protocol(folder, invocation, hashes), type(value) is int and value == 3)
                self.assertFalse(sealed_protocol(folder, invocation, {}))
                self.assertFalse(sealed_protocol(folder, invocation, {'version.json': '0' * 64}))

    def test_actual_room_matched_and_public_flags_are_mandatory(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            invocation = {'protocol': 3, 'expected_protocol': 3}
            original = {
                'host-terminal.json': {'matched': {'op': 'matched', 'protocol': 3, 'match': 7, 'slot': 0, 'civilizations': [1, 2]}, 'last': {'match': 7, 'site': {'state': 2, 'owner': 0, 'clock_ticking': False, 'garrison_paused': True, 'neutralizing': False}}},
                'host-sent.jsonl': [{'packet': {'op': 'host', 'protocol': 3}}],
                'host-transport.jsonl': [{'packet': {'op': 'room', 'protocol': 3}}, {'packet': {'op': 'matched', 'protocol': 3, 'match': 7, 'slot': 0, 'civilizations': [1, 2]}}],
                'host-snapshots.jsonl': [{'packet': {'match': 7, 'site': {'state': 2, 'owner': 0, 'clock_ticking': True, 'garrison_paused': False, 'neutralizing': False}}}],
            }
            write(folder, original)
            self.assertTrue(all(protocol3_gates(folder, invocation, 'host').values()))
            for key, value in [('match', 6), ('slot', 1), ('civilizations', [0, 0])]:
                files = copy.deepcopy(original)
                files['host-transport.jsonl'][1]['packet'][key] = value
                write(folder, files)
                self.assertFalse(protocol3_gates(folder, invocation, 'host')['protocol3_actual_bidirectional_handshake'])
            for value in (None, 2, '3', True, 3.5):
                for branch in ('request', 'room', 'matched', 'terminal'):
                    files = copy.deepcopy(original)
                    packet = files['host-sent.jsonl'][0]['packet'] if branch == 'request' else files['host-terminal.json']['matched'] if branch == 'terminal' else files['host-transport.jsonl'][0 if branch == 'room' else 1]['packet']
                    packet['protocol'] = value
                    write(folder, files)
                    self.assertFalse(protocol3_gates(folder, invocation, 'host')['protocol3_actual_bidirectional_handshake'])
            for key in ('clock_ticking', 'garrison_paused', 'neutralizing'):
                for value in (None, 0, 1, 'false'):
                    files = copy.deepcopy(original)
                    files['host-terminal.json']['last']['site'][key] = value
                    write(folder, files)
                    self.assertFalse(protocol3_gates(folder, invocation, 'host')['protocol3_authoritative_public_clock_flags'])
            for fields in ({'clock_ticking': True}, {'neutralizing': True}, {'owner': -1}, {'state': 0}):
                files = copy.deepcopy(original)
                files['host-terminal.json']['last']['site'].update(fields)
                write(folder, files)
                self.assertFalse(protocol3_gates(folder, invocation, 'host')['protocol3_authoritative_public_clock_flags'])

    def test_protocol3_keeps_paid_mobile_gates_for_both_slots(self):
        for slot in (0, 1):
            with tempfile.TemporaryDirectory() as temp:
                folder = Path(temp)
                files, invocation, role = fixture(folder, slot)
                invocation.update(protocol=3, expected_protocol=3)
                write(folder, files)
                self.assertTrue(all(beta2_gates(folder, invocation, role, slot).values()))
                files[role + '-beta2-ui.jsonl'] = [row for row in files[role + '-beta2-ui.jsonl'] if row['action'] != 'siege_train']
                write(folder, files)
                self.assertFalse(all(beta2_gates(folder, invocation, role, slot).values()))

    def test_required3_rejects_complete_invocation_downgrade(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            (folder / 'invocation.json').write_text(json.dumps({'protocol': 2, 'expected_protocol': 2}))
            report = analyze(folder, expected_protocol=3)
            self.assertIn('required release protocol mismatch', report['failures'])


if __name__ == '__main__':
    unittest.main()

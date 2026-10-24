"""Synthetic receipt validation; no browser, game or network is launched."""
import json
import tempfile
import unittest
from pathlib import Path

from analyze_live_browser_multiplayer import local_gates


class LocalBrowserEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='pocket-evidence-unit-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.endpoint = 'ws://127.0.0.1:12345/match'
        self.invocation = {'match_url': self.endpoint}
        hashes = {name: '1' * 64 for name in ('index.js', 'index.pck', 'index.wasm')}
        self.write('local-source-initial.json', {'artifact': {'files': hashes}, 'authority': {'source_revision': 'abcdef'}, 'server_pid': 71})
        self.write('local-source-final.json', {'completed': True, 'production_artifacts_unchanged': True, 'private_runtime_unchanged': True})
        self.write('local-authority-ready.json', {'match_url': self.endpoint, 'source_revision': 'abcdef', 'pid': 71})
        self.rows('host-socket_route.jsonl', [{'requested': 'wss://game.4mn.org/match', 'resolved': self.endpoint, 'blocked': False}])
        self.rows('host-endpoint-guard.jsonl', [{'url': self.endpoint, 'allowed': True}])
        self.rows('host-asset-bytes.jsonl', [{'file': name, 'expected': value, 'sha256': value, 'bytes': 10} for name, value in hashes.items()])
        self.command = {'op': 'command', 'command': 'attack_move', 'match': 1, 'sequence': 9, 'ids': [17], 'position': [0, 1152]}
        self.evidence = {'packet': self.command, 'source': 'game_ui_or_engine', 'serial': 7}
        self.rows('host-command_origin.jsonl', [self.evidence])
        self.rows('host-sent.jsonl', [{'packet': self.command}])
        screenshots = ['before.png', 'armed.png', 'after.png']
        for name in screenshots:
            (self.root / name).write_bytes(b'SYNTHETIC RECEIPT FIXTURE')
        self.rows('host-attack-ui.jsonl', [{'passed': True, 'evidence': self.evidence, 'screenshots': screenshots}])
        self.rows('host-browser-input.jsonl', [{'kind': 'click', 'purpose': purpose} for purpose in ('observed_attack_hud_button', 'attack_move_ground_destination')])

    def write(self, name, data):
        (self.root / name).write_text(json.dumps(data), encoding='utf-8')

    def rows(self, name, data):
        (self.root / name).write_text(''.join(json.dumps(row) + '\n' for row in data), encoding='utf-8')

    def gates(self):
        return local_gates(self.root, self.invocation, 'host')

    def test_complete_source_and_input_receipts(self):
        self.assertTrue(all(self.gates().values()))

    def test_a_key_or_policy_command_cannot_substitute_for_attack_hud(self):
        self.rows('host-browser-input.jsonl', [{'kind': 'press', 'key': 'a'}])
        self.assertFalse(self.gates()['actual_attack_hud_generated_attack_move'])
        self.rows('host-browser-input.jsonl', [{'kind': 'click', 'purpose': purpose} for purpose in ('observed_attack_hud_button', 'attack_move_ground_destination')])
        self.evidence['source'] = 'paid_policy'
        self.rows('host-command_origin.jsonl', [self.evidence])
        self.assertFalse(self.gates()['actual_attack_hud_generated_attack_move'])

    def test_public_endpoint_or_blocked_route_fails_local_claim(self):
        self.invocation['match_url'] = 'wss://game.4mn.org/match'
        self.assertFalse(self.gates()['owned_authority_endpoint'])
        self.invocation['match_url'] = self.endpoint
        self.rows('host-endpoint-guard.jsonl', [{'url': 'wss://game.4mn.org/match', 'allowed': False}])
        self.assertFalse(self.gates()['no_unapproved_socket_reached_browser_transport'])

    def test_missing_engine_bytes_or_source_integrity_fails(self):
        self.rows('host-asset-bytes.jsonl', [])
        self.assertFalse(self.gates()['loaded_engine_bytes_match_sealed_export'])
        self.write('local-source-final.json', {'completed': True, 'production_artifacts_unchanged': False, 'private_runtime_unchanged': True})
        self.assertFalse(self.gates()['sealed_local_source_unchanged'])

    def test_missing_manifest_does_not_match_null_asset_hashes(self):
        self.write('local-source-initial.json', {})
        self.rows('host-asset-bytes.jsonl', [{'file': name, 'bytes': 10} for name in ('index.js', 'index.wasm', 'index.pck')])
        self.assertFalse(self.gates()['loaded_engine_bytes_match_sealed_export'])

    def test_screenshot_escape_or_absent_wire_receipt_fails(self):
        self.rows('host-sent.jsonl', [])
        self.assertFalse(self.gates()['actual_attack_hud_generated_attack_move'])
        self.rows('host-sent.jsonl', [{'packet': self.command}])
        self.rows('host-attack-ui.jsonl', [{'passed': True, 'evidence': self.evidence, 'screenshots': ['../before.png', 'armed.png', 'after.png']}])
        self.assertFalse(self.gates()['actual_attack_hud_generated_attack_move'])


if __name__ == '__main__':
    unittest.main()

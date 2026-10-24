"""Synthetic receipt validation; no browser, game or network is launched."""
import json
import hashlib
import tempfile
import unittest
from pathlib import Path

from analyze_live_browser_multiplayer import analyze, local_gates, civilization_gates, screen_gates, counter_lesson, touch_gates, public_gates


class LocalBrowserEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='pocket-evidence-unit-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.endpoint = 'ws://127.0.0.1:12345/match'
        self.invocation = {'match_url': self.endpoint}
        hashes = {name: '1' * 64 for name in ('index.js', 'index.pck', 'index.wasm')}
        self.write('local-source-initial.json', {'artifact': {'files': hashes}, 'authority': {'source_revision': 'abcdef'}, 'server_pid': 71})
        self.write('local-source-final.json', {'completed': True, 'production_artifacts_unchanged': True, 'private_runtime_unchanged': True, 'artifact_failures': []})
        self.write('local-authority-ready.json', {'match_url': self.endpoint, 'source_revision': 'abcdef', 'pid': 71, 'protocol': 2})
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

    def test_owned_server_proof_is_correlated_to_response_id_hash_and_length(self):
        self.rows('host-asset-bytes.jsonl', [])
        served = [{'request_id': str(i), 'method': 'GET', 'file': name, 'sha256': '1'*64, 'bytes': 10}
                  for i, name in enumerate(('index.js', 'index.wasm', 'index.pck'))]
        self.write('local-source-final.json', {'completed': True, 'production_artifacts_unchanged': True, 'private_runtime_unchanged': True, 'artifact_failures': [], 'served': served})
        self.rows('host-asset-server-proof.jsonl', [dict(row, status=200) for row in served])
        self.assertTrue(self.gates()['loaded_engine_bytes_match_sealed_export'])
        served[-1]['bytes'] = 9
        self.write('local-source-final.json', {'served': served})
        self.assertFalse(self.gates()['loaded_engine_bytes_match_sealed_export'])

    def test_touch_evidence_requires_actual_tap_receipts(self):
        self.invocation['input_mode'] = 'touch'
        self.assertFalse(self.gates()['actual_attack_hud_generated_attack_move'])
        self.rows('host-browser-input.jsonl', [{'kind': 'tap', 'purpose': purpose} for purpose in ('observed_attack_hud_button', 'attack_move_ground_destination')])
        self.assertTrue(self.gates()['actual_attack_hud_generated_attack_move'])

    def touch_fixture(self):
        self.invocation['input_mode'] = 'touch'
        self.write('host-browser-capabilities.json', {'width': 844, 'height': 390, 'max_touch_points': 1, 'coarse_pointer': True})
        command = {'op': 'command', 'command': 'train', 'type': 0, 'target': 3, 'match': 7, 'sequence': 1}
        evidence = {'serial': 1, 'source': 'game_ui_or_engine', 'packet': command}
        before = {'match': 7, 'tick': 10, 'time': 2, 'bank': {'food': 250, 'wood': 200, 'gold': 100}, 'player': {'population_reserved': 0}, 'stats': {'resources_gathered': 0}, 'actors': [{'id': 3, 'owner': 0, 'kind': 'building', 'type': 0, 'state': 2, 'queue': {'repeat': False, 'items': []}}]}
        after = json.loads(json.dumps(before))
        after.update(tick=11, time=2.2)
        after['bank']['food'] = 210
        after['stats']['resources_gathered'] = 10
        after['player']['population_reserved'] = 1
        after['actors'][0]['queue']['items'] = [0]
        images = [{'name': name, 'sha256': hashlib.sha256((self.root / name).read_bytes()).hexdigest(), 'unix': stamp} for name, stamp in (('before.png', 1000), ('after.png', 1100))]
        tap = {'kind': 'tap', 'purpose': 'paid_recruit_villager', 'unix': 1010, 'x': 600, 'y': 300}
        attempt = {'attempt': 'recruit-1', 'passed': True, 'input_mode': 'touch', 'policy_ever': False, 'slot': 0, 'input': tap, 'evidence': evidence, 'before': before, 'after': after, 'captures': images}
        self.rows('host-recruit-ui.jsonl', [attempt])
        self.rows('host-recruit-snapshots.jsonl', [{'attempt': 'recruit-1', 'stage': stage, 'packet': packet} for stage, packet in (('before', before), ('after', after))])
        self.rows('host-captures.jsonl', images)
        self.rows('host-recruit-reviews.jsonl', [{'attempt': 'recruit-1', 'passed': True, 'reviewed': True, 'unix': 1200, 'input_mode': 'touch', 'captures': images, 'observed': {'unit': 'Villager', 'cost_food': 50, 'queue_count': 1, 'before_bank': before['bank'], 'after_bank': after['bank']}}])
        self.rows('policy-starts.jsonl', [{'unix': 1300}])
        self.rows('host-command_origin.jsonl', [evidence])
        self.rows('host-sent.jsonl', [{'unix': 1010, 'packet': command}, {'unix': 50, 'packet': {'op': 'host'}}, {'unix': 100, 'packet': {'op': 'room_start'}}])
        self.rows('host-browser-input.jsonl', [tap, {'kind': 'tap', 'purpose': 'lobby_create', 'unix': 50}, {'kind': 'tap', 'purpose': 'lobby_start', 'unix': 100}, {'kind': 'tap', 'purpose': 'result_main_menu', 'unix': 2100}])
        self.write('host-terminal.json', {'received_unix': 2000})
        self.rows('host-screen-reviews.jsonl', [{'check': 'menu_return', 'passed': True, 'image': {'unix': 2200}}])
        return attempt

    def test_touch_paid_recruitment_accounts_for_normal_deposits_and_requires_pre_policy_review(self):
        self.touch_fixture()
        self.assertTrue(all(touch_gates(self.root, self.invocation, 'host').values()))
        self.rows('policy-starts.jsonl', [{'unix': 1100}])
        self.assertFalse(touch_gates(self.root, self.invocation, 'host')['actual_tap_paid_recruitment_reviewed_before_policy'])

    def test_touch_paid_recruitment_rejects_policy_wrong_cost_missing_queue_and_invented_snapshots(self):
        for mutation in ('policy', 'cost', 'queue', 'reservation', 'snapshot', 'review', 'mouse'):
            with self.subTest(mutation=mutation):
                attempt = self.touch_fixture()
                if mutation == 'policy': attempt['evidence']['source'] = 'paid_policy'
                elif mutation == 'cost': attempt['after']['bank']['food'] += 1
                elif mutation == 'queue': attempt['after']['actors'][0]['queue']['items'] = []
                elif mutation == 'reservation': attempt['after']['player']['population_reserved'] = 0
                elif mutation == 'snapshot': self.rows('host-recruit-snapshots.jsonl', [])
                elif mutation == 'review': self.rows('host-recruit-reviews.jsonl', [])
                elif mutation == 'mouse': attempt['input']['kind'] = 'click'
                self.rows('host-recruit-ui.jsonl', [attempt])
                self.assertFalse(touch_gates(self.root, self.invocation, 'host')['actual_tap_paid_recruitment_reviewed_before_policy'])

    def test_touch_lobby_menu_capabilities_and_no_mouse_fallback_are_independent_gates(self):
        self.touch_fixture()
        self.rows('host-browser-input.jsonl', [{'kind': 'click', 'purpose': 'lobby_create', 'unix': 50}])
        gates = touch_gates(self.root, self.invocation, 'host')
        self.assertFalse(gates['no_mouse_pointer_fallback'])
        self.assertFalse(gates['actual_tap_lobby_protocol_actions'])
        self.assertFalse(gates['actual_tap_terminal_menu_return'])
        self.write('host-browser-capabilities.json', {'width': 844, 'height': 390, 'max_touch_points': 0})
        self.assertFalse(touch_gates(self.root, self.invocation, 'host')['native_touch_844x390_context'])

    def test_touch_payment_requires_nonnegative_per_resource_deposits(self):
        for bank, deposits, valid in (({'food': 225, 'wood': 200, 'gold': 75}, 0, False),
                                     ({'food': 225, 'wood': 175, 'gold': 100}, 0, False),
                                     ({'food': 215, 'wood': 195, 'gold': 100}, 10, False),
                                     ({'food': 203, 'wood': 204, 'gold': 103}, 10, True)):
            with self.subTest(bank=bank):
                attempt = self.touch_fixture()
                attempt['after']['bank'] = bank
                attempt['after']['stats']['resources_gathered'] = deposits
                self.rows('host-recruit-ui.jsonl', [attempt])
                self.rows('host-recruit-snapshots.jsonl', [{'attempt': attempt['attempt'], 'stage': stage, 'packet': packet} for stage, packet in (('before', attempt['before']), ('after', attempt['after']))])
                reviews = [json.loads(line) for line in (self.root / 'host-recruit-reviews.jsonl').read_text().splitlines()]
                reviews[0]['observed']['after_bank'] = bank
                self.rows('host-recruit-reviews.jsonl', reviews)
                self.assertEqual(touch_gates(self.root, self.invocation, 'host')['actual_tap_paid_recruitment_reviewed_before_policy'], valid)

    def public_fixture(self):
        self.invocation.update(protocol=2, url='https://game.4mn.org/', match_url='wss://game.4mn.org/match', source_revision='a'*12)
        hashes = {name: '1'*64 for name in ('index.js', 'version.json', 'index.wasm', 'index.pck')}
        headers = {'etag': 'W/"release-size"', 'last-modified': 'date', 'content-type': 'application/octet-stream', 'content-encoding': 'gzip'}
        postflight = {'status': 'PASS_READ_ONLY_POSTFLIGHT', 'request': {'protocol': 2, 'source_revision': 'a'*40, 'web_manifest_sha256': '2'*64}, 'public_files': {name: {'sha256': sha} for name, sha in hashes.items()}, 'requests': []}
        (self.root / 'public-postflight-headers').mkdir(exist_ok=True)
        for name in ('index.pck', 'index.wasm'):
            postflight['requests'].append({'url': 'https://game.4mn.org/'+name, 'status': 200, 'ssl_verify_result': 0, 'sha256': hashes[name], 'bytes_decoded': 100, 'headers_file': name+'.headers'})
            (self.root / 'public-postflight-headers' / (name+'.headers')).write_text('HTTP/2 200\n'+'\n'.join(key+': '+value for key,value in headers.items()))
        proof = {'artifact': {'files': hashes, 'manifest_sha256': '2'*64}, 'postflight': postflight}
        self.write('public-source.json', proof)
        self.rows('host-socket_route.jsonl', [])
        self.rows('host-transport.jsonl', [{'event': 'open', 'url': 'wss://game.4mn.org/match'}])
        self.rows('host-assets.jsonl', [{'url': 'https://game.4mn.org/'+name, 'status': 200, 'headers': headers} for name in ('index.pck', 'index.wasm')])
        self.rows('host-asset-bytes.jsonl', [{'file': name, 'expected': hashes[name], 'sha256': hashes[name], 'bytes': 100} for name in ('index.js', 'version.json')])
        return proof

    def test_public_provenance_requires_exact_endpoint_revision_and_direct_small_body_hashes(self):
        self.public_fixture()
        self.assertTrue(all(public_gates(self.root, self.invocation, 'host').values()))
        self.invocation['source_revision'] = ''
        self.assertFalse(public_gates(self.root, self.invocation, 'host')['public_postflight_matches_sealed_artifacts'])
        self.rows('host-asset-bytes.jsonl', [])
        self.assertFalse(public_gates(self.root, self.invocation, 'host')['public_loaded_version_and_javascript_bytes_verified'])
        self.rows('host-socket_route.jsonl', [{'resolved': 'ws://127.0.0.1:1/match'}])
        self.assertFalse(public_gates(self.root, self.invocation, 'host')['public_exact_endpoint_no_redirect'])

    def test_public_missing_protocol_and_manifest_hashes_fail_closed(self):
        proof = self.public_fixture()
        self.invocation.pop('protocol')
        self.assertFalse(public_gates(self.root, self.invocation, 'host')['public_postflight_matches_sealed_artifacts'])
        self.invocation['protocol'] = 2
        proof['artifact']['files'].pop('index.pck')
        proof['postflight']['requests'][0].pop('sha256')
        self.write('public-source.json', proof)
        gates = public_gates(self.root, self.invocation, 'host')
        self.assertFalse(gates['public_postflight_matches_sealed_artifacts'])
        self.assertFalse(gates['public_engine_response_provenance'])

    def test_public_both_missing_or_malformed_manifest_digests_fail_closed(self):
        for bad in (None, '', 'not-a-digest', 'a' * 63):
            with self.subTest(bad=bad):
                proof = self.public_fixture()
                proof['artifact']['manifest_sha256'] = bad
                proof['postflight']['request']['web_manifest_sha256'] = bad
                self.write('public-source.json', proof)
                self.assertFalse(public_gates(self.root, self.invocation, 'host')['public_postflight_matches_sealed_artifacts'])

    def test_captured_body_mismatch_cannot_be_masked_by_validators_or_other_valid_bodies(self):
        self.public_fixture()
        bodies = [json.loads(line) for line in (self.root / 'host-asset-bytes.jsonl').read_text().splitlines()]
        bodies += [{'file': 'index.pck', 'expected': '1' * 64, 'sha256': '0' * 64, 'bytes': 100, 'match': False},
                   {'file': 'index.pck', 'expected': '1' * 64, 'sha256': '1' * 64, 'bytes': 100, 'match': True}]
        self.rows('host-asset-bytes.jsonl', bodies)
        self.assertFalse(public_gates(self.root, self.invocation, 'host')['public_engine_response_provenance'])
        self.assertFalse(local_gates(self.root, self.invocation, 'host')['loaded_engine_bytes_match_sealed_export'])

    def test_controller_client_artifact_error_cannot_be_omitted_from_analysis(self):
        self.public_fixture()
        self.write('invocation.json', self.invocation)
        error = {'type': 'artifact-bytes', 'file': 'index.pck', 'match': False}
        self.write('controller-state.json', {'host': {'errors': [error]}})
        report = analyze(self.root)
        self.assertFalse(report['clients']['host']['gates']['no_console_or_socket_errors'])
        self.assertIn({'type': 'controller-client', 'detail': error}, report['clients']['host']['errors'])

    def test_public_large_body_validator_correlation_fails_closed(self):
        for mutation in ('hash', 'tls', 'missing', 'headers', 'escaped_path'):
            with self.subTest(mutation=mutation):
                proof = self.public_fixture()
                response = proof['postflight']['requests'][0]
                if mutation == 'hash': response['sha256'] = '0'*64
                elif mutation == 'tls': response['ssl_verify_result'] = 1
                elif mutation == 'escaped_path': response['headers_file'] = '../22.headers'
                elif mutation == 'missing': (self.root / 'public-postflight-headers/index.pck.headers').unlink()
                elif mutation == 'headers': self.rows('host-assets.jsonl', [])
                self.write('public-source.json', proof)
                self.assertFalse(public_gates(self.root, self.invocation, 'host')['public_engine_response_provenance'])

    def kingdom_fixture(self):
        own = {'id': 1, 'key': 'verdant-league', 'name': 'Verdant League'}
        self.invocation.update(protocol=2, input_mode='mouse', civilization_expectations={'host': own, 'guest': {'id': 2, 'key': 'sunstride-clans', 'name': 'Sunstride Clans'}})
        matched = {'match': 1, 'slot': 0, 'civilizations': [1, 2]}
        packet = {'match': 1, 'civilizations': [1, 2], 'player': {'civilization': 1}, 'battle': {'losses_by_matchup': [[2, 3, 4]]}, 'stats': {'army_trained': 8, 'units_lost': 4, 'buildings_lost': 0, 'resources_gathered': 900}}
        self.write('host-terminal.json', {'received_unix': 1, 'matched': matched, 'ended': {'match': 1, 'winner': 0, 'reason': 'Sacred hold'}, 'last': packet})
        self.rows('host-sent.jsonl', [{'packet': {'op': 'host', 'protocol': 2, 'civilization': 1}}])
        self.rows('host-transport.jsonl', [{'packet': {'op': 'room', 'players': 2, 'civilizations': [1, 2]}}])
        self.rows('host-snapshots.jsonl', [{'packet': packet}])
        captures = [{'name': name, 'sha256': hashlib.sha256((self.root / name).read_bytes()).hexdigest(), 'unix': 1} for name in ('before.png', 'armed.png', 'after.png')]
        self.rows('host-captures.jsonl', captures)
        self.rows('host-civilization-ui.jsonl', [{'performed': True, 'selected': own, 'captures': captures}])
        self.rows('host-civilization-identity.jsonl', [{'passed': True, 'reviewed': True, 'observed_name': own['name'], 'selected': own, 'matched': matched}])
        self.rows('host-browser-input.jsonl', [{'kind': 'click', 'purpose': purpose} for purpose in ('civilization_picker_open', 'civilization_picker_choice', 'civilization_picker_confirm')])
        lesson = counter_lesson(packet, 0)
        self.rows('host-screen-reviews.jsonl', [
            {'check': 'result_review', 'passed': True, 'image': captures[0], 'observed': {'result': 'VICTORY', 'reason': 'Sacred hold', 'counts': {'Army Produced': 8, 'Units Lost': 4, 'Buildings Lost': 0, 'Resources Gathered': 900}, 'lesson_status': lesson['status'], 'lesson_text': lesson['text']}},
            {'check': 'menu_return', 'passed': True, 'image': captures[1], 'observed': {'actions': ['New Game', 'Join a friend']}}])
        return packet

    def test_civilization_claim_needs_received_protocol_identity_and_reviewed_pixels(self):
        self.kingdom_fixture()
        self.assertTrue(all(civilization_gates(self.root, self.invocation, 'host').values()))
        self.rows('host-sent.jsonl', [{'packet': {'op': 'host', 'protocol': 1, 'civilization': 1}}])
        self.assertFalse(civilization_gates(self.root, self.invocation, 'host')['protocol2_actual_civilization_request'])
        self.rows('host-civilization-identity.jsonl', [])
        self.assertFalse(civilization_gates(self.root, self.invocation, 'host')['reviewed_picker_matches_received_civilization'])

    def test_signature_names_and_terminal_identity_do_not_follow_intended_choice(self):
        packet = self.kingdom_fixture()
        self.assertIn('Enemy Outriders landed final blows on 4 of your Longbows', counter_lesson(packet, 0)['text'])
        packet['civilizations'] = [0, 2]
        self.rows('host-snapshots.jsonl', [{'packet': packet}])
        self.assertFalse(civilization_gates(self.root, self.invocation, 'host')['civilization_identity_stable_through_terminal'])

    def test_result_review_requires_exact_counts_and_eligible_lesson_or_explicit_none(self):
        self.kingdom_fixture()
        self.assertTrue(all(screen_gates(self.root, 'host').values()))
        reviews = json.loads((self.root / 'host-screen-reviews.jsonl').read_text().splitlines()[0])
        reviews['observed']['lesson_status'] = 'none'; reviews['observed']['lesson_text'] = ''
        self.rows('host-screen-reviews.jsonl', [reviews])
        self.assertFalse(screen_gates(self.root, 'host')['reviewed_result_counts_and_eligible_lesson'])
        packet = self.kingdom_fixture(); packet['battle']['losses_by_matchup'] = [[2, 3, 2]]
        self.assertEqual(counter_lesson(packet, 0), {'status': 'none', 'text': '', 'eligible': []})
        packet['battle']['losses_by_matchup'] = [[2, 3, 4], [2, 3, 1]]
        self.assertIsNone(counter_lesson(packet, 0))


if __name__ == '__main__':
    unittest.main()

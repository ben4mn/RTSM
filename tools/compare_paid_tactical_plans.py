#!/usr/bin/env python3
"""Compare paired tactical receipts without hiding changed combat outcomes."""
import argparse
import json
from pathlib import Path


def canonical(value):
    if isinstance(value, dict):
        return {key: canonical(item) for key, item in value.items()
                if key not in ('id', 'target', 'user_data_dir', 'runtime_source_hashes')}
    if isinstance(value, list):
        return [canonical(item) for item in value]
    return value


def load_cases(folder):
    return {path.name: json.loads(path.read_text()) for path in sorted(folder.glob('map*.json'))}


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--baseline', type=Path, required=True)
parser.add_argument('--candidate', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--expected-source-change', action='append', default=[])
args = parser.parse_args()
before, after = load_cases(args.baseline), load_cases(args.candidate)
if not before or before.keys() != after.keys():
    raise SystemExit('Matrices must contain identical nonempty case sets')
before_hashes = next(iter(before.values()))['runtime_source_hashes']
after_hashes = next(iter(after.values()))['runtime_source_hashes']
if before_hashes.keys() != after_hashes.keys():
    raise SystemExit('Loaded source coverage differs between matrices')
for cases, hashes in [(before, before_hashes), (after, after_hashes)]:
    if any(data['runtime_source_hashes'] != hashes for data in cases.values()):
        raise SystemExit('A matrix contains more than one source snapshot')
changed_source = [path for path in before_hashes if before_hashes[path] != after_hashes[path]]
if sorted(changed_source) != sorted(args.expected_source_change):
    raise SystemExit(f'Unexpected loaded source changes: {changed_source}')

economic_fields = ['initial_resources', 'initial_workers', 'paid_ready_at', 'opening_seconds',
                   'deposits', 'bank_after_opening', 'opening_stats', 'ages', 'economic_bonus_active',
                   'paid_army_cost', 'initial_tactical_units']
metric_fields = ['first_hit', 'last_hit', 'tactical_seconds', 'end', 'survivors', 'remaining_hp',
                 'damage', 'hits', 'counter_hits', 'kills', 'target_changes', 'largest_hit_gap',
                 'navigation_failures', 'navigation_stall_unit_seconds', 'unanswered_orders',
                 'severe_friendly_overlap_pair_seconds']
rows = []
for name, old in before.items():
    new = after[name]
    changed_fields = [key for key in old if key not in ('runtime_source_hashes', 'user_data_dir')
                      and canonical(old[key]) != canonical(new.get(key))]
    changed_economy = [key for key in economic_fields if canonical(old[key]) != canonical(new[key])]
    if changed_economy:
        raise SystemExit(f'{name}: paid opening or controlled deployment changed: {changed_economy}')
    rows.append({'case': name, 'map': old['map'], 'plan': old['plan'], 'changed_fields': changed_fields,
                 'paid_opening_and_deployment_identical': True,
                 'before': {key: old[key] for key in metric_fields},
                 'after': {key: new[key] for key in metric_fields},
                 'before_final_units': old['final_unit_diagnostics'],
                 'after_final_units': new['final_unit_diagnostics']})
user_dirs = [data['user_data_dir'] for data in [*before.values(), *after.values()]]
if len(user_dirs) != len(set(user_dirs)):
    raise SystemExit('Paired cases reused a preference directory')
receipt = {'scope': 'Matched paid tactical fixtures; process IDs/user directories excluded from behavior comparison. All changed fields are disclosed.',
           'before_source_hashes': before_hashes, 'after_source_hashes': after_hashes,
           'changed_source': changed_source, 'distinct_private_user_directories': len(user_dirs), 'cases': rows}
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps({'cases': len(rows), 'changed_source': changed_source,
                  'behavior_changed_cases': sum(bool(row['changed_fields']) for row in rows),
                  'paid_opening_and_deployment_identical': True}))

#!/usr/bin/env python3
"""Run presentation regressions from frozen source with private preferences.

Headless correctness checks only; wall duration is not a rendering benchmark.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--project', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--case', action='append', default=[], help='res:// scene or SceneTree script; repeat for sequential checks')
parser.add_argument('--import-assets', action='store_true')
parser.add_argument('--compare-map', type=Path, help='Prior probe_presentation_map_integrity.json to compare')
parser.add_argument('--timeout', type=float, default=180)
args = parser.parse_args()
source = args.project.resolve()
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)
godot = os.environ.get('GODOT_BIN', '/Applications/Godot.app/Contents/MacOS/Godot')
cases = args.case or ['res://tools/probe_presentation_map_integrity.tscn']


def source_hashes():
    return {str(p.relative_to(source)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(source.rglob('*'))
            if p.is_file() and '.godot' not in p.parts and p.suffix in ('.gd', '.tscn', '.godot', '.gdshader', '.py')}


initial_hashes = source_hashes()
results = []
private_user_dirs = {}
for index, case in enumerate(cases):
    name = Path(case).stem
    user_dir = 'aoem-presentation-probes/' + uuid.uuid4().hex
    private_user_dirs[name] = user_dir
    with tempfile.TemporaryDirectory(prefix='aoem-presentation-case-') as temporary:
        project = Path(temporary)
        (source / '.godot').mkdir(exist_ok=True)
        for entry in source.iterdir():
            if entry.name not in ('project.godot', 'override.cfg', '.git', 'output', 'builds'):
                (project / entry.name).symlink_to(entry, target_is_directory=entry.is_dir())
        config = (source / 'project.godot').read_text()
        config = '\n'.join(line for line in config.splitlines() if not line.startswith(('config/use_custom_user_dir=', 'config/custom_user_dir_name=')))
        config = config.replace('[application]', '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="' + user_dir + '"', 1)
        (project / 'project.godot').write_text(config + '\n')
        env = os.environ.copy()
        env.update(AOEM_SIM_TIME_SCALE='1', AOEM_MAP_ARCHETYPE='0')
        if index == 0 and args.import_assets:
            with (output / 'import.log').open('w') as stream:
                status = subprocess.run([godot, '--headless', '--editor', '--import', '--path', str(project), '--quit'], stdout=stream, stderr=subprocess.STDOUT, env=env, timeout=args.timeout)
            text = (output / 'import.log').read_text()
            if status.returncode or 'ERROR:' in text:
                raise RuntimeError('Import failed; see import.log')
        report = output / (name + '.json')
        if report.exists(): report.unlink()
        command = [godot, '--headless', '--path', str(project)]
        command += ['--script', case] if case.endswith('.gd') else [case]
        command += ['--', '--output=' + str(report)]
        log = output / (name + '.log')
        with log.open('w') as stream:
            status = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, env=env, timeout=args.timeout)
        text = log.read_text()
        if status.returncode or 'ERROR:' in text or '[PASS]' not in text:
            raise RuntimeError(f'{name} failed; see {log}')
        results.append({'case': case, 'passed': True, 'log': str(log), 'report': str(report) if report.exists() else None,
                        'warnings': [line for line in text.splitlines() if 'WARNING:' in line]})
        print('PASS', name, flush=True)

if initial_hashes != source_hashes():
    raise RuntimeError('Source changed during the isolated checks')
comparison = None
if args.compare_map:
    old = json.loads(args.compare_map.read_text())
    new = json.loads((output / 'probe_presentation_map_integrity.json').read_text())
    before = {(r['map'], r['seed']): r for r in old['cases']}
    after = {(r['map'], r['seed']): r for r in new['cases']}
    if len(before) != 9 or before.keys() != after.keys():
        raise RuntimeError('Expected nine matching map/seed pairs')
    changed = [key for key in before if before[key]['mechanics'] != after[key]['mechanics']]
    if changed: raise RuntimeError(f'Presentation changed map mechanics: {changed}')
    comparison = {'mechanics_identical': True, 'pairs': len(before),
                  'presentation_changed_pairs': [list(key) for key in before if before[key]['presentation'] != after[key]['presentation']],
                  'before_source_hashes': old['source_hashes'], 'after_source_hashes': new['source_hashes'],
                  'distinct_preference_dirs': old['user_data_dir'] != new['user_data_dir']}
    print('PASS nine paired map mechanics and routes', flush=True)
(output / 'source-receipt.json').write_text(json.dumps({'source_project': str(source), 'source_hashes': initial_hashes,
    'source_unchanged': True, 'private_user_dirs': private_user_dirs, 'checks': results, 'map_comparison': comparison}, indent=2) + '\n')

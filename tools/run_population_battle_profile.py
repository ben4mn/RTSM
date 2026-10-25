"""Freeze a source tree and run the exact-population battle, optionally instrumented.

Instrumentation modifies only the frozen copy. Buckets are inclusive and add CPU
overhead; compare uninstrumented runs for acceptance. Production feature removes
debug telemetry branches but this native editor binary is not a Web export.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--instrument', action='store_true')
parser.add_argument('--headless', action='store_true')
parser.add_argument('--seconds', type=float, default=15.0)
parser.add_argument('--compare-base', help='Paired run: restore only the four indexing edits from this Git revision for the before case. Scout data, UI, fixture and assets remain identical.')
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)

TARGETS = {
    'scripts/main/main.gd': ['_process', '_update_fog_of_war', '_update_fog_entity_visibility', '_update_minimap', '_on_selection_changed', '_update_progression_hint', '_on_unit_died'],
    'scripts/units/unit_base.gd': ['_process', '_draw', '_process_moving', '_process_attacking', '_update_friendly_separation', '_try_auto_attack', '_update_sprite_motion'],
    'scripts/units/villager.gd': ['_process', '_check_visible_economic_threats', '_get_visible_economic_threats', '_process_gathering', '_find_and_go_to_dropoff'],
    'scripts/units/auto_targeting.gd': ['_nearest_unit', '_nearest_building'],
    'scripts/map/live_unit_index.gd': ['update', 'near', 'units_reveal', '_refresh_parent_transforms'],
    'scripts/map/pathfinding.gd': ['get_path', 'get_tile_path', 'get_tile_path_to_any'],
    'scripts/map/game_map.gd': ['_process', 'update_resource_visibility_for_player', 'is_entity_visible_to_player', 'is_tile_visible_to_player'],
    'scripts/managers/fog_manager.gd': ['_process', '_update_visibility', '_apply_fog_delta'],
    'scripts/ui/unit_occlusion_overlay.gd': ['_process', '_begin_scan', '_scan_units', '_points_covered'],
    'scripts/ui/hud.gd': ['_process', 'apply_mobile_layout', 'update_minimap', '_update_train_buttons'],
    'scripts/managers/strategy_controller.gd': ['_process', '_refresh'],
    'scripts/ui/strategy_overview.gd': ['_refresh_producers', '_refresh_details'],
    'scripts/buildings/building_base.gd': ['_process'],
}

def instrument(path, methods):
    text = path.read_text(encoding='utf-8')
    for method in methods:
        pattern = re.compile(r'^(static )?func ' + re.escape(method) + r'\((.*?)\)(\s*->\s*[^:\n]+)?\s*:\n', re.M | re.S)
        match = pattern.search(text)
        if not match:
            raise ValueError(f'Missing method {path}:{method}')
        static, params, result = match.groups()
        names = re.findall(r'(?:^|,)\s*(\w+)\s*:', params)
        result_type = result.split('->')[1].strip() if result else 'void'
        original = '__perf_' + path.stem + method
        call = f'{original}({", ".join(names)})'
        wrapper = match.group() + '\tvar _perf_start: int = Time.get_ticks_usec()\n'
        wrapper += '\t' + (f'var _perf_result: {result_type} = ' if result_type != 'void' else '') + call + '\n'
        wrapper += f'\tpreload("res://tools/performance_buckets.gd").record("{path.stem}.{method}", Time.get_ticks_usec() - _perf_start)\n'
        if result_type != 'void': wrapper += '\treturn _perf_result\n'
        wrapper += '\n\n' + match.group().replace('func ' + method, 'func ' + original, 1)
        text = text[:match.start()] + wrapper + text[match.end():]
    path.write_text(text, encoding='utf-8', newline='\n')

with tempfile.TemporaryDirectory(prefix='population-battle-') as directory:
    frozen = Path(directory)
    for name in ('scripts', 'scenes', 'assets', 'addons', 'tools', '.godot', 'web'):
        shutil.copytree(ROOT / name, frozen / name, ignore=shutil.ignore_patterns('__pycache__', 'node_modules'))
    shutil.copy2(ROOT / 'project.godot', frozen / 'project.godot')
    for name in ('icon.svg', 'icon.svg.import'):
        if (ROOT / name).exists(): shutil.copy2(ROOT / name, frozen / name)
    config = (frozen / 'project.godot').read_text(encoding='utf-8')
    # Match export sanitization: the editor bridge/debug UI is not production.
    config = re.sub(r'^MCPGameBridge=.*\n', '', config, flags=re.M)
    config = re.sub(r'^DebugBootstrap=.*\n', '', config, flags=re.M)
    config = re.sub(r'^config/(?:use_custom_user_dir|custom_user_dir_name)=.*\n', '', config, flags=re.M)
    before_files = ['scripts/map/game_map.gd', 'scripts/units/unit_base.gd', 'scripts/units/auto_targeting.gd', 'scripts/buildings/building_base.gd']
    candidate = {name: (frozen / name).read_bytes() for name in before_files}
    phases = ['before', 'after'] if args.compare_base else ['candidate']
    for phase in phases:
        destination = args.output / phase if args.compare_base else args.output
        destination.mkdir(parents=True, exist_ok=True)
        for name in before_files:
            contents = subprocess.check_output(['git', 'show', f'{args.compare_base}:{name}'], cwd=ROOT) if phase == 'before' else candidate[name]
            (frozen / name).write_bytes(contents)
        private_config = config.replace('[application]', '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="aoem-battle-probe/' + uuid.uuid4().hex + '"', 1)
        (frozen / 'project.godot').write_text(private_config, encoding='utf-8')
        sources = sorted(list((frozen / 'scripts').rglob('*.gd')) + list((frozen / 'scenes').rglob('*.tscn')) + [frozen / 'project.godot', frozen / 'tools/probe_population_battle.gd', frozen / 'tools/probe_native_busy_front.gd', frozen / 'tools/performance_buckets.gd'])
        receipt = {'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(), 'instrumented': args.instrument, 'production_feature_env': 'production', 'phase': phase, 'baseline_runtime_files': before_files if phase == 'before' else [], 'baseline_revision': args.compare_base, 'source_sha256': {str(path.relative_to(frozen)).replace('\\', '/'): hashlib.sha256(path.read_bytes()).hexdigest() for path in sources}, 'seconds': args.seconds}
        if args.instrument:
            if args.compare_base: raise ValueError('Use separate diagnostic runs for instrumentation, not paired acceptance')
            for name, methods in TARGETS.items(): instrument(frozen / name, methods)
            index_path = frozen / 'scripts/map/live_unit_index.gd'
            index_source = index_path.read_text(encoding='utf-8')
            sort_line = '\tresult.sort_custom(func(a: UnitBase, b: UnitBase) -> bool: return b.is_greater_than(a))'
            if sort_line in index_source:
                index_source = index_source.replace(sort_line, '\tvar _sort_start: int = Time.get_ticks_usec()\n' + sort_line + '\n\tpreload("res://tools/performance_buckets.gd").record("live_unit_index.order_sort", Time.get_ticks_usec() - _sort_start)')
                index_path.write_text(index_source, encoding='utf-8', newline='\n')
        (destination / 'source-receipt.json').write_text(json.dumps(receipt, indent=2), encoding='utf-8')
        env = dict(os.environ, GODOT_EDITOR_CUSTOM_FEATURES='production', AOEM_BUSY_OUTPUT=str(destination.resolve()), AOEM_BATTLE_SECONDS=str(args.seconds))
        command = [os.environ['GODOT_BIN'], '--path', str(frozen)]
        command += ['--headless'] if args.headless else ['--position', '-24000,-24000', '--resolution', '1280x720', '--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy']
        command += ['res://tools/probe_population_battle.tscn']
        with (destination / 'run.log').open('w', encoding='utf-8') as log:
            completed = subprocess.run(command, cwd=frozen, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=180)
        log_text = (destination / 'run.log').read_text(encoding='utf-8')
        if completed.returncode or 'SCRIPT ERROR' in log_text or 'ERROR:' in log_text:
            print(log_text[-5000:])
            raise SystemExit(completed.returncode or 1)
        report = json.loads((destination / 'population-battle.json').read_text(encoding='utf-8'))
        if not report['production_feature'] or report.get('failures') or any(frame['population'] != [100, 100] for frame in report['timeline']):
            raise RuntimeError('Production feature, input acceptance or sustained population failed; inspect report')
        print(json.dumps({'phase': phase, 'frames': report['frames'], 'population': report['population'], 'inputs': len(report['input']), 'failures': report.get('failures', [])}), flush=True)

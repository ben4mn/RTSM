#!/usr/bin/env python3
"""Prepare, focus-check and measure one isolated macOS paid battle.

Run modes separately; imports never run in the timed native process. See
docs/dense_battle_native_2026-10-22.md for scope and reproducible commands.
"""
from pathlib import Path
import argparse, hashlib, json, math, os, platform, shutil, signal, subprocess, tempfile, time, uuid
ROOT = Path(__file__).resolve().parents[1]
HERE = Path(__file__).resolve().parent
HARNESS = ['probe_dense_paid_native.gd', 'probe_dense_paid_native.gd.uid',
           'probe_dense_paid_native.tscn', 'dense_paid_policy.gd', 'dense_paid_policy.gd.uid']

def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def percentile(values, f):
    values = sorted(values)
    return values[max(0, math.ceil(len(values)*f)-1)] if values else None

def summarize_frames(rows):
    values = [row[1] for row in rows]
    seconds = sum(values)/1000
    streak = largest_streak = 0
    previous=None
    for row in rows:
        if previous is not None and row[0]-previous-row[1]/1000>1e-6: streak=0
        streak = streak+1 if row[1] > 33.333333 else 0
        largest_streak = max(largest_streak, streak)
        previous=row[0]
    return {'frames':len(rows), 'summed_frame_seconds':seconds,
            'frame_ms':{key: percentile(values, f) for key,f in [('p50',.5),('p90',.9),('p95',.95),('p99',.99)]},
            'maximum_frame_ms':max(values,default=None),
            'thresholds':{str(limit):{'frames':sum(v > limit for v in values),'percent':100*sum(v > limit for v in values)/len(values) if values else None} for limit in [16.666667,25,33.333333,50]},
            'longest_consecutive_over33ms_frames':largest_streak,
            'engine_time_process_ms_p95':percentile([r[2] for r in rows],.95),
            'engine_time_physics_ms_p95':percentile([r[3] for r in rows],.95),
            'draw_calls_p95':percentile([r[4] for r in rows],.95)}

def analyze(output):
    raw=json.loads((output/'raw.json').read_text())
    errors=list(raw['failures'])
    rows=raw['frames']
    dense=[r for r in rows if r[5]>=16 and r[7]]
    active=[r for r in rows if r[7]]
    first_hit=(raw['first_hit_us']-raw['sample_started_us'])/1e6 if raw['first_hit_us'] and raw['sample_started_us'] else None
    established_dense=[r for r in dense if first_hit is not None and r[0]>=first_hit+2.0]
    if raw.get('initial_banks') != [{'food':250,'wood':250,'gold':100}]*2: errors.append('Initial banks differ from ordinary paid start')
    if raw.get('economic_bonus_active'): errors.append('AI economic bonus active')
    if raw.get('sample_start_workers') != [10,10]: errors.append('Paid ten-worker economies incomplete')
    if any(u['hp'] != u['max_hp'] for u in raw.get('sample_start_units',[])): errors.append('Roster not at full health before order')
    if raw.get('ages') != [2,2]: errors.append('Paid Feudal transition incomplete')
    if not raw.get('focused_at_start'): errors.append('Window not focused at sample start')
    if any(e['phase']=='measured' and not e['focused'] for e in raw['focus_events']): errors.append('Focus lost during sample')
    if raw.get('sample_start_units'):
        roster=[sum(u['owner']==owner and u['role']==role for u in raw['sample_start_units']) for owner in [0,1] for role in [1,2,3]]
        if roster != [6,4,2]*2: errors.append(f'Paid roster mismatch: {roster}')
    for owner in [0,1]:
        for role,count in [(1,6),(2,4),(3,2)]:
            for action in ['queued','trained']:
                actual=sum(e['owner']==owner and e['role']==role and e['action']==action for e in raw['queues'])
                if actual!=count: errors.append(f'Paid queue mismatch {owner}:{role}:{action}={actual}')
        for resource in ['food','wood','gold']:
            if raw.get('initial_banks'):
                expected=raw['initial_banks'][owner][resource]+sum(e['delta'] for e in raw['bank_ledger'] if e['owner']==owner and e['resource']==resource)
                if expected != raw['final_banks'][owner][resource]: errors.append(f'Bank ledger mismatch {owner}:{resource}')
    expected_camera=raw.get('environment',{}).get('camera')
    if any(e['camera']!=expected_camera or any(abs(z-.952)>0.00001 for z in e['zoom']) for e in raw['presence']): errors.append('Camera or zoom changed')
    expected_viewport=raw.get('environment',{}).get('viewport')
    expected_window=raw.get('environment',{}).get('window')
    expected_scale=raw.get('environment',{}).get('content_scale_factor')
    if any(e['viewport']!=expected_viewport or e['window']!=expected_window or e['content_scale_factor']!=expected_scale or e['time_scale']!=1 for e in raw['presence']): errors.append('Viewport/window/content scale/time scale drift')
    wall=(raw['sample_ended_us']-raw['sample_started_us'])/1e6
    game=raw.get('sample_end_game_seconds',0)-raw.get('sample_start_game_seconds',0)
    if abs(game-wall)>max(.1,wall*.01): errors.append(f'Game/wall clock drift: game={game},wall={wall}')
    if sum(r[1] for r in dense)<5000 or len(dense)<150: errors.append('Insufficient dense-active sample: need5wallsec and150frames')
    if raw.get('navigation_failures'): errors.append(f'Navigation failures: {raw["navigation_failures"]}')
    result={'scope':'Render-completion cadence of a native desktop debug build at phone-sized viewport; not display presentation, GPU duration, physical phone or Web timing. Engine TIME_PROCESS is an aggregate frame monitor, not pure script CPU. Default renderer/VSync and ordinary runtime diagnostics stay active. Muted audio; fixed purchasing policy, not standard strategic AI.',
            'classification':'Active = a military damage event in preceding1s. Dense = active plus at least16 military units on screen (visibility/position cached2Hz). Quiet frames remain in full window and cannot hide dense subset.',
            'environment':raw.get('environment'), 'paid_ready_at':raw.get('paid_ready_at'),
            'sample_start_game_seconds':raw.get('sample_start_game_seconds'), 'sample_end_game_seconds':raw.get('sample_end_game_seconds'),
            'first_hit_after_sample_start_seconds':(raw['first_hit_us']-raw['sample_started_us'])/1e6 if raw['first_hit_us'] and raw['sample_started_us'] else None,
            'whole':summarize_frames(rows), 'active':summarize_frames(active), 'dense':summarize_frames(dense), 'established_dense':summarize_frames(established_dense),
            'actual_sample_wall_seconds':wall, 'actual_sample_game_seconds':game,
            'dense_adequate':sum(r[1] for r in dense)>=5000 and len(dense)>=150,
            'presence':raw['presence'], 'commands':raw['commands'], 'observer':raw['observer'],
            'damage_events':len(raw['damage_events']), 'damage_total':sum(e['damage'] for e in raw['damage_events']),
            'established_dense_definition':'Dense-active frames at least2s after first real damage; separates initial encounter work from established fighting.',
            'remaining_military':len(raw.get('sample_end_units',[])), 'errors':errors,
            'documentation':['https://docs.godotengine.org/en/4.6/classes/class_renderingserver.html#signals','https://docs.godotengine.org/en/4.6/classes/class_performance.html'],
            'raw_sha256':sha(output/'raw.json')}
    (output/'summary.json').write_text(json.dumps(result,indent=2)+'\n')
    return result

def engine_processes():
    text=subprocess.check_output(['ps','-axo','pid=,comm='],text=True)
    result=[]
    for line in text.splitlines():
        fields=line.strip().split(None,1)
        if len(fields)==2 and Path(fields[1]).name.lower().startswith('godot'):
            result.append({'pid':int(fields[0]),'command':fields[1]})
    return result


def write_json(path, data):
    path.write_text(json.dumps(data, indent=2) + '\n')


def require_isolation():
    processes = engine_processes()
    if processes:
        raise RuntimeError(f'Other Godot processes are running: {processes}')
    return processes


def prepare(args, output):
    project = args.project.resolve()
    revision = subprocess.check_output(['git', 'rev-parse', args.revision], cwd=project, text=True).strip()
    stage = Path(tempfile.mkdtemp(prefix='aoem-dense-native-'))
    archive = stage / 'source.tar'
    with archive.open('wb') as handle:
        subprocess.run(['git', 'archive', revision], cwd=project, stdout=handle, check=True)
    subprocess.run(['tar', '-xf', str(archive), '-C', str(stage)], check=True)
    archive.unlink()
    if (project / '.godot').is_dir():
        shutil.copytree(project / '.godot', stage / '.godot')
    for name in HARNESS:
        shutil.copy2(HERE / name, stage / 'tools' / name)
    text = (stage / 'project.godot').read_text()
    text = '\n'.join(line for line in text.splitlines() if not line.startswith(('config/use_custom_user_dir=', 'config/custom_user_dir_name=')))
    text = text.replace('[application]', '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="aoem-dense-native/' + uuid.uuid4().hex + '"', 1)
    (stage / 'project.godot').write_text(text + '\n')
    files = [stage / 'project.godot'] + [stage / 'tools' / name for name in HARNESS]
    files += list((stage / 'scripts').rglob('*.gd'))
    files += list((stage / 'scenes').rglob('*.tscn'))
    files.append(stage / 'tools/fixtures/tactical_paid_opening.gd')
    files += [p for p in (stage / 'assets').rglob('*') if p.is_file() and p.suffix != '.import']
    metadata = {'revision': revision, 'stage': str(stage), 'platform': platform.platform(),
                'godot_app': str(args.godot_app.resolve()), 'files': {str(p.relative_to(stage)): sha(p) for p in files},
                'runner_sha256': sha(Path(__file__)), 'width': args.width, 'height': args.height, 'duration': args.duration,
                'scope': 'Frozen Git revision plus current diagnostic harness. Private preferences. macOS LaunchServices native debug build; no runtime/renderer changes.'}
    write_json(output / 'source.json', metadata)
    print(json.dumps({'prepared': str(stage), 'manifest': str(output / 'source.json'), 'revision': revision}), flush=True)


def owned_processes(stage):
    rows = subprocess.check_output(['ps', '-axo', 'pid=,comm=,args='], text=True).splitlines()
    result = []
    for row in rows:
        parts = row.strip().split(None, 2)
        if len(parts) == 3 and Path(parts[1]).name.lower().startswith('godot') and str(stage) in parts[2]:
            result.append(int(parts[0]))
    return result


def terminate_owned(stage):
    # open -W is a launcher, not the game process. A timeout must close only this
    # private benchmark, never an unrelated editor or client.
    for pid in owned_processes(stage):
        try: os.kill(pid, signal.SIGTERM)
        except ProcessLookupError: pass
    deadline = time.monotonic() + 3
    while owned_processes(stage) and time.monotonic() < deadline:
        time.sleep(.1)
    for pid in owned_processes(stage):
        try: os.kill(pid, signal.SIGKILL)
        except ProcessLookupError: pass


def execute(args, output):
    source = json.loads((output / 'source.json').read_text())
    stage = Path(source['stage'])
    mismatches = [f for f, expected in source['files'].items() if not (stage / f).is_file() or sha(stage / f) != expected]
    if mismatches:
        raise RuntimeError(f'Frozen source differs or is missing: {mismatches}')
    if args.mode == 'analyze':
        print(json.dumps(analyze(output), indent=2))
        return
    receipt = {'before': require_isolation(), 'mode': args.mode,
               'during': 'Exclusive native slot must be coordinated externally; no continuous process monitor during measured frames.'}
    write_json(output / f'{args.mode}-isolation.json', receipt)
    app = Path(source['godot_app'])
    engine = app / 'Contents/MacOS/Godot'
    if args.mode == 'import':
        command = [str(engine), '--headless', '--editor', '--path', str(stage), '--quit']
        with (output / 'import.log').open('w') as handle:
            result = subprocess.run(command, stdout=handle, stderr=subprocess.STDOUT, timeout=120)
        log = (output / 'import.log').read_text()
        receipt['after'] = require_isolation()
        write_json(output / 'import-isolation.json', receipt)
        if result.returncode or 'SCRIPT ERROR' in log or 'Parse Error' in log:
            raise RuntimeError('Import failed; inspect import.log')
        print('Import complete. Run the separate focus mode before any paid measurement.')
        return
    if platform.system() != 'Darwin':
        raise RuntimeError('This validated runner uses macOS LaunchServices; other native platforms are outside its current scope')
    if args.mode == 'run':
        focus_path = output / 'focus.json'
        if not focus_path.is_file():
            raise RuntimeError('Run --mode focus successfully first; paid warmup was not started')
        focus = json.loads(focus_path.read_text())
        if not focus.get('focused') or focus.get('probe_sha256') != source['files']['tools/probe_dense_paid_native.gd']:
            raise RuntimeError('Focus preflight did not pass for this frozen probe')
        if time.time() - focus_path.stat().st_mtime > 600:
            raise RuntimeError('Focus receipt is older than10minutes; repeat --mode focus before paid warmup')
        if (output / 'raw.json').exists():
            raise RuntimeError('raw.json already exists; use a new output directory to preserve the previous attempt')
    env_args = []
    for key, value in {'AOEM_AI_DIFFICULTY': '1', 'AOEM_MAP_ARCHETYPE': '0', 'AOEM_MAP_SEED': '101',
                       'AOEM_POPULATION_LIMIT': '30', 'AOEM_SIM_TIME_SCALE': '3'}.items():
        env_args += ['--env', key + '=' + value]
    label = 'focus' if args.mode == 'focus' else 'native'
    command = ['open', '-n', '-W', '-a', str(app), *env_args, '--args', '--path', str(stage),
               '--log-file', str(output / f'{label}.log'), 'res://tools/probe_dense_paid_native.tscn', '--',
               f'--output={output}', f'--width={source["width"]}', f'--height={source["height"]}', f'--duration={source["duration"]}']
    if args.mode == 'focus':
        command.append('--focus-only')
        (output / 'focus.json').unlink(missing_ok=True)
    write_json(output / f'{label}-launch.json', {'command': command, 'source_revision': source['revision'], 'mode': args.mode})
    started = time.monotonic()
    try:
        with (output / f'{label}-launch.log').open('w') as handle:
            subprocess.run(command, stdout=handle, stderr=subprocess.STDOUT, timeout=30 if args.mode == 'focus' else args.timeout, check=True)
    except (subprocess.TimeoutExpired, subprocess.CalledProcessError):
        terminate_owned(stage)
        raise
    finally:
        receipt['after'] = engine_processes()
        receipt['wall_seconds'] = time.monotonic() - started
        write_json(output / f'{args.mode}-isolation.json', receipt)
    if receipt['after']:
        raise RuntimeError(f'Godot process remains after execution: {receipt["after"]}')
    log = (output / f'{label}.log').read_text()
    if 'SCRIPT ERROR' in log or 'ERROR:' in log:
        raise RuntimeError(f'Engine error; inspect {label}.log. Timing is invalid.')
    if args.mode == 'focus':
        focus = json.loads((output / 'focus.json').read_text())
        print(json.dumps(focus, indent=2))
        if not focus.get('focused'):
            raise RuntimeError('Native window was not focused. No paid setup ran; do not weaken the gate or alter security settings.')
    else:
        raw = json.loads((output / 'raw.json').read_text())
        for filename, expected in raw.get('source_hashes', {}).items():
            if sha(stage / filename) != expected:
                raise RuntimeError(f'Loaded source mismatch: {filename}')
        summary = analyze(output)
        print(json.dumps({key: summary[key] for key in ['errors', 'whole', 'active', 'dense', 'established_dense']}, indent=2))
        if summary['errors']:
            raise RuntimeError('Measured run rejected by validity gates; inspect summary.json')


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--mode', choices=['prepare', 'import', 'focus', 'run', 'analyze'], default='prepare')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--project', type=Path, default=ROOT)
    parser.add_argument('--revision', default='HEAD', help='Git revision frozen by prepare; never silently measures uncommitted runtime edits')
    parser.add_argument('--godot-app', type=Path, default=Path('/Applications/Godot.app'))
    parser.add_argument('--width', type=int, default=844)
    parser.add_argument('--height', type=int, default=390)
    parser.add_argument('--duration', type=float, default=30)
    parser.add_argument('--timeout', type=int, default=600)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if args.mode == 'prepare':
        if (output / 'source.json').exists():
            parser.error('source.json already exists; use a fresh output directory')
        prepare(args, output)
    else:
        execute(args, output)


if __name__ == '__main__':
    main()

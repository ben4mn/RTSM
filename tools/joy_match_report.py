#!/usr/bin/env python3
"""Run headless AI-vs-AI skirmishes and report match length, economy and combat pacing.

Both players are AIControllers paying real costs (see tools/probe_joy_match.gd).
This is a measurement tool, not a test: it always exits 0 unless a match process fails.

  GODOT_BIN=~/aoem-dev/bin/godot python3 tools/joy_match_report.py --matches 4 \
      --difficulty medium --civs french,english --map open_plains --seed-base 100 \
      --max-seconds 1800 --out output/joy/baseline.json
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import statistics
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
CIVS = {'french': 0, 'english': 1, 'mongols': 2}
MAPS = {'open_plains': 0, 'river_crossings': 1, 'woodland_flanks': 2}
DIFFICULTIES = {'easy': 0, 'medium': 1, 'hard': 2}

parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument('--matches', type=int, default=4)
parser.add_argument('--difficulty', choices=DIFFICULTIES, default='medium')
parser.add_argument('--civs', default='french,english', help='comma list; match i plays civs[i] vs civs[i+1], cycling')
parser.add_argument('--map', default='open_plains', help='comma list of archetypes, cycled per match')
parser.add_argument('--seed-base', type=int, default=100, help='match i uses seed-base + i')
parser.add_argument('--max-seconds', type=float, default=1800, help='game-time cap per match')
parser.add_argument('--pop', type=int, default=100, help='population limit (game default 100)')
parser.add_argument('--jobs', type=int, default=4)
parser.add_argument('--out', type=Path, required=True, help='aggregate JSON; raw per-match files go beside it')
parser.add_argument('--keep-events', action='store_true', help='keep the full event log in the aggregate file')
parser.add_argument('--difficulty1', choices=DIFFICULTIES, default=None, help='give seat 1 its own level (e.g. easy vs hard)')
parser.add_argument('--swap-alternate', action='store_true', help='odd matches play the same kingdoms from swapped seats')
args = parser.parse_args()
civs = [name.strip() for name in args.civs.split(',') if name.strip()]
maps = [name.strip() for name in args.map.split(',') if name.strip()]
for name in civs:
    if name not in CIVS:
        parser.error(f'unknown civ {name}; choose from {sorted(CIVS)}')
for name in maps:
    if name not in MAPS:
        parser.error(f'unknown map {name}; choose from {sorted(MAPS)}')
godot = os.environ.get('GODOT_BIN', 'godot')
out = args.out if args.out.is_absolute() else ROOT / args.out
raw_dir = out.with_suffix('')
raw_dir.mkdir(parents=True, exist_ok=True)


def run_match(index: int) -> dict:
    swap = 1 if args.swap_alternate and index % 2 == 1 else 0
    pair = index // 2 if args.swap_alternate else index
    civ, opp = civs[pair % len(civs)], civs[(pair + 1) % len(civs)]
    map_name, seed = maps[pair % len(maps)], args.seed_base + pair
    name = f'match{index:02d}-{civ}-vs-{opp}-{map_name}-seed{seed}' + ('-swapped' if swap else '')
    report, log = raw_dir / f'{name}.json', raw_dir / f'{name}.log'
    report.unlink(missing_ok=True)
    command = [godot, '--headless', '--fixed-fps', '60', '--path', str(ROOT), 'res://tools/probe_joy_match.tscn', '--',
               f'--seed={seed}', f'--difficulty={DIFFICULTIES[args.difficulty]}', f'--civ={CIVS[civ]}', f'--opp={CIVS[opp]}',
               f'--map={MAPS[map_name]}', f'--pop={args.pop}', f'--max-seconds={args.max_seconds}', f'--output={report}',
               f'--swap={swap}', f'--difficulty1={DIFFICULTIES[args.difficulty1] if args.difficulty1 else -1}']
    environment = os.environ.copy()
    # Environment overrides in main.gd/game_manager.gd must not skew a run; a
    # private HOME keeps parallel matches away from saved player preferences.
    for key in ('AOEM_AI_DIFFICULTY', 'AOEM_SIM_TIME_SCALE', 'AOEM_MAP_SEED', 'AOEM_MAP_ARCHETYPE', 'AOEM_POPULATION_LIMIT'):
        environment.pop(key, None)
    with tempfile.TemporaryDirectory(prefix='joy-match-') as home, log.open('w') as stream:
        environment.update(XDG_DATA_HOME=home, XDG_CONFIG_HOME=home)
        try:
            code = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, env=environment,
                                  timeout=max(900.0, args.max_seconds * 1.5)).returncode
        except subprocess.TimeoutExpired:
            return {'name': name, 'error': 'wall timeout', 'log': str(log)}
    if not report.exists():
        return {'name': name, 'error': f'no report (exit {code})', 'log': str(log)}
    data = json.loads(report.read_text())
    data['name'] = name
    data['script_errors'] = log.read_text(errors='replace').count('SCRIPT ERROR')
    previous = [{} for _ in data['players']]
    for sample in data['timeline']:  # gathered totals -> per-minute income
        for player_id, player in enumerate(sample['players']):
            player['gathered_per_minute'] = {key: value - previous[player_id].get(key, 0) for key, value in player['gathered'].items()}
            previous[player_id] = player.pop('gathered')
    if not args.keep_events:
        data.pop('events', None)
    return data


def mean(values: list) -> float | None:
    values = [value for value in values if value is not None and value >= 0]
    return round(statistics.fmean(values), 1) if values else None


def spread(values: list) -> dict:
    values = [value for value in values if value is not None and value >= 0]
    if not values:
        return {'n': 0}
    return {'n': len(values), 'mean': round(statistics.fmean(values), 1), 'median': round(statistics.median(values), 1),
            'min': round(min(values), 1), 'max': round(max(values), 1)}


def at_minute(match: dict, minute: int, getter) -> list:
    for sample in match['timeline']:
        if sample['t'] == minute * 60:
            return [getter(player) for player in sample['players']]
    return []


def aggregate(matches: list[dict]) -> dict:
    players = [player for match in matches for player in match['players']]
    decided = [match for match in matches if match['winner'] >= 0]
    reasons: dict = {}
    wins_by_civ: dict = {}
    for match in matches:
        reasons[match['win_reason']] = reasons.get(match['win_reason'], 0) + 1
        if match['winner'] >= 0:
            civ = match['players'][match['winner']]['civ']
            wins_by_civ[civ] = wins_by_civ.get(civ, 0) + 1
    totals = lambda key: {name: sum(player['totals'][key].get(name, 0) for player in players)  # noqa: E731
                          for name in sorted({name for player in players for name in player['totals'][key]})}
    per_minute = {}
    for minute in (3, 5, 8, 10, 12, 15, 20):
        rows = [row for match in matches for row in at_minute(match, minute, lambda p: (
            p['villagers'], sum(count for unit, count in p['military'].items() if unit != 'scout'), sum(p['resources'].values()), sum(p['gathered_per_minute'].values()), p['idle_villagers']))]
        if rows:
            per_minute[f'{minute}m'] = {'samples': len(rows), 'villagers': mean([r[0] for r in rows]), 'military': mean([r[1] for r in rows]),
                                        'banked': mean([r[2] for r in rows]), 'income_per_minute': mean([r[3] for r in rows]),
                                        'idle_villagers': mean([r[4] for r in rows])}
    # Round 2 E telemetry: army mix, Town Center wins, length spread, seats, levels.
    line_shares = []
    for player in players:
        army = {unit: count for unit, count in player['totals']['trained'].items() if unit not in ('villager', 'scout', 'trader')}
        total = sum(army.values())
        if total >= 6:
            line_shares.append(max(army.values()) / total)
    lengths = sorted(match['length_seconds'] for match in matches)
    p90 = lengths[min(len(lengths) - 1, int(round(0.9 * (len(lengths) - 1))))] if lengths else None
    tc_wins = sum(1 for match in decided if 'Town Center' in str(match['win_reason']))
    plays_by_civ: dict = {}
    for match in decided:
        for player in match['players']:
            plays_by_civ[player['civ']] = plays_by_civ.get(player['civ'], 0) + 1
    wins_by_level: dict = {}
    for match in decided:
        levels = [match.get('difficulty'), match.get('difficulty_seat1', match.get('difficulty'))]
        level = levels[match['winner']]
        wins_by_level[str(level)] = wins_by_level.get(str(level), 0) + 1
    return {
        'matches': len(matches), 'decided': len(decided), 'win_reasons': reasons, 'wins_by_civ': wins_by_civ,
        'civ_win_rate': {civ: round(wins_by_civ.get(civ, 0) / plays, 2) for civ, plays in plays_by_civ.items()},
        'town_center_win_share': round(tc_wins / len(decided), 2) if decided else None,
        'match_length_p90': p90,
        'wins_by_level': wins_by_level,
        'top_line_share': spread([round(share, 2) for share in line_shares]),
        'wins_by_slot': [sum(1 for match in decided if match['winner'] == slot) for slot in (0, 1)],
        'match_length_seconds': spread([match['length_seconds'] for match in matches]),
        'decided_length_seconds': spread([match['length_seconds'] for match in decided]),
        'speedup': spread([match['speedup'] for match in matches]),
        'first_military_unit_seconds': spread([player['totals']['first_military_time'] for player in players]),
        'first_combat_seconds': spread([match['first_combat_time'] for match in matches]),
        'first_building_lost_seconds': spread([match['first_building_lost_time'] for match in matches]),
        'age2_seconds': spread([player['age_times'].get('2') for player in players]),
        'age3_seconds': spread([player['age_times'].get('3') for player in players]),
        'peak_army': spread([player['totals']['peak_army'] for player in players]),
        'average_float_total': spread([player['average_float'].get('total') for player in players]),
        'average_float_by_resource': {name: mean([player['average_float'].get(name) for player in players]) for name in ('food', 'wood', 'gold')},
        'peak_float_total': spread([player['peak_float'] for player in players]),
        'units_trained': totals('trained'), 'units_lost': totals('lost'),
        'buildings_built': totals('buildings_built'), 'buildings_lost': totals('buildings_lost'),
        'attacks_launched_per_player': mean([player['totals']['attacks_launched'] for player in players]),
        'by_minute_per_player': per_minute,
    }


started = time.monotonic()
with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as executor:
    results = list(executor.map(run_match, range(args.matches)))
good = [match for match in results if 'error' not in match]
for match in results:
    if 'error' in match:
        print(f"{match['name']}: ERROR {match['error']} (see {match['log']})")
        continue
    sides = ' | '.join(
        f"P{i} {p['civ']} age{p['age']} ages@{p['age_times']} mil1@{p['totals']['first_military_time']:.0f}s peak{p['totals']['peak_army']} "
        f"lost{p['units_lost']} float~{p['average_float'].get('total', 0):.0f} abilities={p.get('abilities', {})} "
        f"tech={[t for t in p['totals'].get('researched', []) if t in ('chivalry', 'yeomen', 'yam')]}" for i, p in enumerate(match['players']))
    print(f"{match['name']}: winner=P{match['winner']} ({match['win_reason']}) {match['length_seconds']:.0f}s "
          f"x{match['speedup']} combat@{match['first_combat_time']:.0f}s errors={match['script_errors']}\n    {sides}")
summary = aggregate(good) if good else {}
payload = {'config': {**{key: str(value) if isinstance(value, Path) else value for key, value in vars(args).items()},
                      'wall_seconds': round(time.monotonic() - started, 1)},
           'scope': 'Headless AI-vs-AI at fixed 60 fps, real costs, no grants. Float = banked unspent resources sampled every 5 s.',
           'aggregate': summary, 'matches': results}
out.write_text(json.dumps(payload, indent=1) + '\n')
print('AGGREGATE ' + json.dumps(summary, indent=1))
print(f'saved {out}')
raise SystemExit(1 if len(good) < len(results) else 0)

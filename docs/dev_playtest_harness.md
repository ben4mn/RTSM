# Developer playtest harness

Two tools for running and measuring matches quickly. Neither changes normal play.

## A. Browser dev hooks (`window.PocketDev`)

Code: `scripts/managers/dev_hooks.gd` (one call each from `main.gd` and `main_menu.gd`,
plus a welcome-gate bypass in `web/pocket_launch.js`).

**Gate.** Active only when the page hostname is `localhost` or `127.0.0.1` **and** the
URL has `?dev=1`. Otherwise nothing is installed: `window.PocketDev` is `undefined` and
the launch flow is untouched. Commands are additionally refused in online matches.

### URL parameters

`http://localhost:8791/<worktree>/index.html?dev=1&autostart=1&civ=english&difficulty=medium&speed=2&skip_tutorial=1`

| Param | Values | Notes |
|---|---|---|
| `dev` | `1` | Required for everything below. |
| `autostart` | `1` | Skip the "Play now" gate and the menu; start a solo skirmish (once per page load). |
| `civ` | `french` `english` `mongols` | Player civilization. |
| `opp` | same | Rival civilization. Omitted = the game's normal seeded pick. |
| `map` | `open_plains` `river_crossings` `woodland_flanks` | Map archetype. |
| `difficulty` | `easy` `medium` `hard` | AI difficulty. |
| `seed` | integer | Map seed. Omitted = random. |
| `speed` | `1` `2` `3` | Initial game speed. |
| `pop` | `20` `30` `40` `60` `100` | Population limit. |
| `skip_tutorial` | `1` | Turn opening tips off. |

Omitted parameters keep the saved menu preference. Autostart settings are not saved.

### Console API

All calls are synchronous and return plain objects.

- `PocketDev.state()` — snapshot: `time`, `speed`, `paused`, `fps`, `map`, `seed`,
  `difficulty`, `first_combat_time`, `first_building_lost_time`, `sacred_site`
  (`phase`, `owner`, `remaining`, `capture_progress`, `tile`…), `selection`, `camera`
  (`tile`, `world`, `zoom`), `result` (`winner`, `reason`; `null` until game over) and
  `players[0..1]`: `civ`, `age`, `age_times`, `resources`, `pop`, `pop_cap`, `units`
  and `buildings` (counts by type), `buildings_under_construction`, `villagers`,
  `idle_villagers`, `villager_tasks` (per resource / `build`), `military` (non-villager,
  non-scout), `units_lost`, `units_killed`, `buildings_lost`, `buildings_destroyed`,
  `resources_gathered`, and `totals` (`trained`/`lost`/`buildings_built`/`buildings_lost`
  by type, `gathered` by resource, `first_military_time`, `peak_army`, `researched`,
  `attacks_launched`).
- `PocketDev.events(sinceIndex)` — `{next, events}`; append-only log. Pass the previous
  `next` to poll. Each event has `i`, `t` (game seconds), `type`, and details. Types:
  `unit_trained`, `unit_died` (`killer` = attacking unit or defending building type),
  `building_placed`, `building_completed`, `building_destroyed`, `age_up`,
  `tech_researched`, `attack_started` (AI attack wave), `under_attack` (per player,
  10 s cooldown), `sacred_captured`, `sacred_contested`, `sacred_neutralized`,
  `game_over`, `dev_cmd`.
- `PocketDev.cmd(name, ...args)` — tester helpers. Positional args or one object.

| Command | Example | Effect |
|---|---|---|
| `camera_to` | `cmd('camera_to','enemy')`, `cmd('camera_to',[44,44])`, `cmd('camera_to',{x:44,y:44,zoom:0.6})` | Target: `'home'`, `'enemy'`, `'sacred'` or a tile. Optional zoom. |
| `set_speed` | `cmd('set_speed',3)` | 0.5–3. |
| `pause` | `cmd('pause',true)` | Opens/closes the normal pause menu. |
| `reveal_map` | `cmd('reveal_map',true)` | Cosmetic: hides the fog layer and shows enemy units/buildings. The fog simulation and the minimap are unchanged. |
| `give` | `cmd('give',{food:500,gold:300})`, `cmd('give',{wood:200},1)` | Add resources (second arg = player, default 0). |
| `spawn` | `cmd('spawn','archer',5,0,'home')`, `cmd('spawn',{unit:'cavalry',count:4,player:1,near:'sacred'})` | Units: `villager infantry archer cavalry scout siege`. `near`: `'home'`/`'enemy'` (relative to that player), `'p0'`, `'p1'`, `'sacred'` or a tile. Adds population room if housing is full. Max 40 per call. |
| `screenshot_safe_ui` | `cmd('screenshot_safe_ui',true)` | `true` hides the HUD for clean captures, `false` restores it. |

`PocketDev.help()` lists commands and parameters.

### Example (automation agent)

```js
// after navigating to ...?dev=1&autostart=1&civ=english&difficulty=medium&speed=3&skip_tutorial=1
PocketDev.cmd('reveal_map', true);
PocketDev.cmd('spawn', 'archer', 6, 0, 'home');
PocketDev.cmd('spawn', {unit: 'infantry', count: 6, player: 1, near: 'p0'});
let cursor = 0;
const poll = () => { const r = PocketDev.events(cursor); cursor = r.next; return r.events; };
PocketDev.state().players[0].units;   // {archer: 6, scout: 1, villager: 2}
```

The page throttles heavily while its tab or the browser pane is hidden; front the tab
when you need game time to advance.

## B. Headless match report (`tools/joy_match_report.py`)

Runs real AI-vs-AI skirmishes (`tools/probe_joy_match.tscn`): player 1 is the normal
opponent, player 0 is a second `AIController` paying through the human build/train/age
transactions. No grants. Fixed 60 fps, `Engine.time_scale` 1, as fast as the box allows
(about 3x real time per process), `--jobs` processes in parallel.

```sh
bash .claude/dev.sh sync
bash .claude/dev.sh ssh "GODOT_BIN=\$HOME/aoem-dev/bin/godot python3 tools/joy_match_report.py \
  --matches 4 --difficulty medium --civs french,english --map open_plains \
  --seed-base 100 --max-seconds 1800 --out output/joy/baseline.json"
```

| Option | Default | Notes |
|---|---|---|
| `--matches` | 4 | Match `i` uses seed `seed-base + i`. |
| `--difficulty` | `medium` | Both AIs. |
| `--civs` | `french,english` | Match `i` plays `civs[i]` vs `civs[i+1]`, cycling. |
| `--map` | `open_plains` | Comma list, cycled per match. |
| `--max-seconds` | 1800 | Game-time cap; unresolved matches report `winner: -1`. |
| `--pop` | 100 | Population limit. |
| `--jobs` | 4 | Parallel Godot processes. |
| `--out` | required | Aggregate JSON. Raw per-match JSON (with full event log) and logs go in the sibling folder of the same name. |
| `--keep-events` | off | Keep full event logs in the aggregate file too. |

Per match: winner, win reason, length, wall-clock speed-up, first combat / first building
lost, a 60 s timeline per player (villagers, idle villagers, military by type, banked
resources, income per minute, age, population, buildings), sacred-site state per sample
plus ownership events, and per player: age-up times, first military unit, units
trained/lost by type, buildings built/lost, peak army, average and peak float.

**Float** is banked unspent food+wood+gold, sampled every 5 s — a "nothing to spend on"
signal. The aggregate block (`AGGREGATE` in stdout, `aggregate` in the file) gives
mean/median/min/max across matches and a per-minute table averaged over all players.

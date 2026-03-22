# CLAUDE.md

This file provides guidance to Claude Code when working in this repository.

## Project Snapshot

- Engine: Godot `4.6`
- Genre: isometric RTS prototype inspired by Age of Empires with mobile-first controls
- Main entry scene: `res://scenes/ui/main_menu.tscn`
- Core gameplay scene: `res://scenes/main/main.tscn`
- Player IDs: `0` = human, `1` = AI

## Core Runtime Topology

### Autoloads

- `GameManager` -> `res://scripts/managers/game_manager.gd`
- `ResourceManager` -> `res://scripts/managers/resource_manager.gd`
- `MCPGameBridge` -> `res://addons/godot_mcp/game_bridge/mcp_game_bridge.gd`

### Main scene orchestration

`res://scripts/main/main.gd` is the main runtime entry point for match setup and gameplay wiring. It:

- waits for `GameMap.map_ready`
- initializes players and starting resources
- spawns the starting town center and villagers
- wires HUD, selection, AI, fog of war, and sacred-site victory flow

## Key Files By Domain

- Match flow and scene wiring: `scripts/main/main.gd`
- Global state and win conditions: `scripts/managers/game_manager.gd`
- Economy and resources: `scripts/managers/resource_manager.gd`
- Map generation, pathfinding, and fog:
  - `scripts/map/map_generator.gd`
  - `scripts/map/game_map.gd`
  - `scripts/map/pathfinding.gd`
  - `scripts/managers/fog_manager.gd`
- Units and villager behavior:
  - `scripts/units/unit_base.gd`
  - `scripts/units/villager.gd`
- Buildings and production:
  - `scripts/buildings/building_base.gd`
  - `scripts/buildings/production_queue.gd`
  - `scripts/buildings/building_placement.gd`
- UI and menus:
  - `scripts/ui/hud.gd`
  - `scripts/ui/build_menu.gd`
  - `scripts/ui/main_menu.gd`
- AI opponent:
  - `scripts/ai/ai_controller.gd`
- Data-driven balance:
  - `scripts/data/unit_data.gd`
  - `scripts/data/building_data.gd`
  - `scripts/map/map_data.gd`

## Local Run / Sanity Commands

```bash
/Applications/Godot.app/Contents/MacOS/Godot --version
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 1
/Applications/Godot.app/Contents/MacOS/Godot --path .
```

## MCP Setup For Test / Play Loops

This project already has MCP wiring:

- `.mcp.json` uses `@satelliteoflove/godot-mcp`
- Godot addon code lives in `addons/godot_mcp/`
- The addon is enabled in `project.godot` under `[editor_plugins]`

If the addon needs reinstalling:

```bash
npx @satelliteoflove/godot-mcp --install-addon /Users/ben/Documents/1_Projects/aoem
```

Useful MCP commands:

- `run_project`
- `get_input_map`
- `execute_input_sequence`
- `capture_game_screenshot`
- `get_debug_output`
- `get_performance_metrics`
- `stop_project`

## Input Actions

From `project.godot`:

- `select` (left click / tap)
- `command` (right click)
- `cancel` (`Esc`)
- `train_unit` (`Q`)
- `toggle_build_menu` (`B`)
- `idle_villager` (`.`)
- `pause` (`P`)
- `center_selection` (`Space`)
- `camera_up`, `camera_down`, `camera_left`, `camera_right` (`WASD` or arrows)
- `select_all_military` (`M`)
- `find_army` (`F`)
- `select_tc` (`H`)

## Working Conventions

- Keep gameplay tuning and balance changes in `scripts/data/*.gd` when possible.
- Preserve the typed GDScript style used across the codebase.
- Prefer existing signals and manager APIs over hard-coded node dependencies.
- Respect player IDs: `0` is the human player, `1` is the AI.
- Use `GameMap.tile_to_world()` and `GameMap.world_to_tile()` for coordinate conversion.

## Validation Checklist

- Main menu starts and launches a match.
- Villager training and build placement still work.
- Resource gathering and drop-off still work.
- AI still builds, trains, and attacks.
- Sacred-site timer and game-over flows still trigger.
- No new runtime errors appear in debug output.

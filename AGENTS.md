# AOEM Codex Agent Guide

This is the Codex-oriented project guide (the equivalent of a per-project `CLAUDE.md`).

## Project Snapshot

- Engine: Godot `4.6`
- Genre: Isometric RTS prototype inspired by Age of Empires (mobile-first controls)
- Main entry scene: `res://scenes/ui/main_menu.tscn`
- Core gameplay scene: `res://scenes/main/main.tscn`

## Core Runtime Topology

- Autoloads in `project.godot`:
  - `GameManager` -> `res://scripts/managers/game_manager.gd`
  - `ResourceManager` -> `res://scripts/managers/resource_manager.gd`
  - `MCPGameBridge` -> `res://addons/godot_mcp/game_bridge/mcp_game_bridge.gd`
- Main scene orchestration: `res://scripts/main/main.gd`
  - Waits for `GameMap.map_ready`
  - Initializes players/resources
  - Spawns starting TC + villagers
  - Wires HUD, selection, AI, fog, sacred-site victory

## Key Files By Domain

- Match flow and wiring: `scripts/main/main.gd`
- Global state and win conditions: `scripts/managers/game_manager.gd`
- Economy/resources: `scripts/managers/resource_manager.gd`
- Map generation/pathfinding/fog:
  - `scripts/map/map_generator.gd`
  - `scripts/map/game_map.gd`
  - `scripts/map/pathfinding.gd`
  - `scripts/managers/fog_manager.gd`
- Unit and villager behavior:
  - `scripts/units/unit_base.gd`
  - `scripts/units/villager.gd`
- Buildings and production:
  - `scripts/buildings/building_base.gd`
  - `scripts/buildings/production_queue.gd`
  - `scripts/buildings/building_placement.gd`
- UI/HUD/menu:
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

- Verify engine:
  - `/Applications/Godot.app/Contents/MacOS/Godot --version`
- Fast boot sanity check:
  - `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 1`
- Open editor for manual play:
  - `/Applications/Godot.app/Contents/MacOS/Godot --path .`

## MCP Setup For Test/Play Loops

This project already has MCP wiring:

- MCP client config: `.mcp.json`
  - Uses `@satelliteoflove/godot-mcp`
- Godot addon code in repo: `addons/godot_mcp/`
- Godot addon enabled in `project.godot` under `[editor_plugins]`

If addon ever needs reinstall:

- `npx @satelliteoflove/godot-mcp --install-addon /Users/ben/Documents/1_Projects/aoem`

### Useful MCP Commands (for autonomous gameplay checks)

- `run_project` (start game)
- `get_input_map` (discover input actions)
- `execute_input_sequence` (simulate actions like camera pan/shortcuts)
- `capture_game_screenshot` (state verification)
- `get_debug_output` (runtime errors/logs)
- `get_performance_metrics` (FPS/frame timings)
- `stop_project` (clean stop)

## Input Actions In This Project

From `project.godot`:

- `select` (left click/tap)
- `command` (right click)
- `cancel` (`Esc`)
- `train_unit` (`Q`)
- `toggle_build_menu` (`B`)
- `idle_villager` (`.`)
- `pause` (`P`)
- `center_selection` (`Space`)
- `camera_up/down/left/right` (`WASD` or arrows)
- `select_all_military` (`M`)
- `find_army` (`F`)
- `select_tc` (`H`)

## Working Conventions

- Keep gameplay data changes in `scripts/data/*.gd` when possible.
- Preserve typed GDScript style used across the codebase.
- Prefer wiring through existing signals over hard-coding node dependencies.
- Respect player IDs:
  - `0` = human
  - `1` = AI
- For map/world conversions, use `GameMap.tile_to_world()` and `GameMap.world_to_tile()` instead of duplicating formulas.

## Pre-PR Validation Checklist

- Game starts from main menu and loads into skirmish scene.
- Villager training/build placement still works.
- Resource gathering and drop-off still works.
- AI still builds/trains/attacks.
- Sacred site timer and game-over flows still trigger.
- No new runtime errors in debug output.

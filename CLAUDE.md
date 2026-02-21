# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AOEM is a Godot 4.6 isometric RTS prototype inspired by Age of Empires mobile gameplay.

- Engine: Godot `4.6`
- Main menu scene: `res://scenes/ui/main_menu.tscn`
- Main gameplay scene: `res://scenes/main/main.tscn`
- Players: `0` = human, `1` = AI

## Core Architecture

### Autoloads

- `GameManager` -> `res://scripts/managers/game_manager.gd`
- `ResourceManager` -> `res://scripts/managers/resource_manager.gd`
- `MCPGameBridge` -> `res://addons/godot_mcp/game_bridge/mcp_game_bridge.gd`

### Main Runtime Wiring

`res://scripts/main/main.gd` is the gameplay orchestrator and is the first file to inspect for behavior changes.

It wires:

- map generation + pathfinding (`GameMap`)
- unit/building spawning and tracking
- selection and command routing
- HUD events/actions
- AI controller integration
- fog of war and minimap updates
- sacred-site victory + game-over flow

### Important Files By Area

- Global game state: `scripts/managers/game_manager.gd`
- Economy/resources: `scripts/managers/resource_manager.gd`
- AI: `scripts/ai/ai_controller.gd`
- Map generation and navigation:
  - `scripts/map/map_data.gd`
  - `scripts/map/map_generator.gd`
  - `scripts/map/game_map.gd`
  - `scripts/map/pathfinding.gd`
- Units:
  - `scripts/units/unit_base.gd`
  - `scripts/units/villager.gd`
- Buildings:
  - `scripts/buildings/building_base.gd`
  - `scripts/buildings/production_queue.gd`
  - `scripts/buildings/building_placement.gd`
- UI:
  - `scripts/ui/hud.gd`
  - `scripts/ui/build_menu.gd`
  - `scripts/ui/main_menu.gd`
- Data definitions:
  - `scripts/data/unit_data.gd`
  - `scripts/data/building_data.gd`

## Local Commands

```bash
# Godot version
/Applications/Godot.app/Contents/MacOS/Godot --version

# Fast boot sanity check (headless)
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 1

# Open editor
/Applications/Godot.app/Contents/MacOS/Godot --path .
```

## MCP Setup And Usage

### Current project setup

- `.mcp.json` already uses `@satelliteoflove/godot-mcp`
- Godot addon exists in `addons/godot_mcp/`
- Plugin is enabled in `project.godot`

### Reinstall addon (if needed)

```bash
npx @satelliteoflove/godot-mcp --install-addon /Users/ben/Documents/1_Projects/aoem
```

### High-value MCP tools for this project

- `run_project`
- `stop_project`
- `get_debug_output`
- `capture_game_screenshot`
- `get_performance_metrics`
- `get_input_map`
- `execute_input_sequence`

Use these for tight edit -> run -> inspect loops instead of manual relay.

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
- `camera_up/down/left/right` (`WASD` or arrow keys)
- `select_all_military` (`M`)
- `find_army` (`F`)
- `select_tc` (`H`)

## Coding Conventions

- Keep tunable balance in `scripts/data/*.gd`.
- Preserve typed GDScript style and explicit signal wiring.
- Prefer existing manager APIs/signals over adding new global state.
- Reuse `GameMap.tile_to_world()` and `GameMap.world_to_tile()` for coordinate conversions.

## Validation Checklist Before Finishing Changes

- Main menu starts and launches match.
- Unit selection + move/attack/gather still works.
- Villager gather/drop-off loop still works.
- Build placement and construction still works.
- AI still trains/constructs/attacks.
- Sacred-site timer and victory flow still work.
- No new errors in debug output.

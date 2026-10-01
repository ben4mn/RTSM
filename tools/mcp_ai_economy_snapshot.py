#!/usr/bin/env python3
"""Capture per-worker/building state from one deterministic AI match."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import time
from pathlib import Path
from typing import Any

from mcp_smoke_test import MCPClient


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-path", type=Path, default=Path("."))
    parser.add_argument("--difficulty", type=int, default=1)
    parser.add_argument("--seed", type=int, default=202)
    parser.add_argument("--capture-at", type=float, default=180.0)
    parser.add_argument("--time-scale", type=float, default=3.0)
    parser.add_argument("--server-cmd", default="npx -y @satelliteoflove/godot-mcp@2.16.1")
    parser.add_argument("--out", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    project = args.project_path.resolve()
    env = os.environ.copy()
    env["AOEM_AI_DIFFICULTY"] = str(args.difficulty)
    env["AOEM_MAP_SEED"] = str(args.seed)
    env["AOEM_SIM_TIME_SCALE"] = str(args.time_scale)
    editor_log = Path("/tmp/aoem-ai-economy-snapshot-editor.log")
    log_handle = editor_log.open("w", encoding="utf-8")
    editor: subprocess.Popen[str] | None = None
    client: MCPClient | None = None

    def tool_text(name: str, arguments: dict[str, Any], timeout: float = 25.0) -> str:
        assert client is not None
        return client.text_from_content(client.call_tool(name, arguments, timeout=timeout))

    def properties(path: str) -> dict[str, Any]:
        assert client is not None
        return client.parse_json_text(
            tool_text("node", {"action": "get_properties", "node_path": path})
        )

    def find_paths(root_path: str, type_name: str) -> list[str]:
        text = tool_text(
            "node",
            {"action": "find", "root_path": root_path, "type": type_name},
        )
        return [
            line.strip().split(" ", 1)[0]
            for line in text.splitlines()
            if line.strip().startswith("/root/")
        ]

    try:
        editor = subprocess.Popen(
            [
                "/Applications/Godot.app/Contents/MacOS/Godot",
                "--headless",
                "--path",
                str(project),
                "-e",
            ],
            cwd=project,
            env=env,
            stdout=log_handle,
            stderr=subprocess.STDOUT,
            text=True,
        )
        time.sleep(8.0)
        client = MCPClient(args.server_cmd, request_timeout=25.0, verbose=False)
        client.initialize()
        tool_text("editor", {"action": "run", "scene_path": "res://scenes/main/main.tscn"})
        deadline = time.monotonic() + 30.0
        while time.monotonic() < deadline:
            state = client.parse_json_text(tool_text("editor", {"action": "get_state"}))
            if bool(state.get("is_playing", False)):
                break
            time.sleep(0.5)
        else:
            raise RuntimeError("scene did not start")

        main_state: dict[str, Any] = {}
        while float(main_state.get("balance_elapsed_seconds", 0.0)) < args.capture_at:
            time.sleep(2.0)
            main_state = properties("/root/Main")

        unit_paths = find_paths("/root/Main/GameMap/UnitsContainer", "Area2D")
        building_paths = find_paths("/root/Main/GameMap/BuildingsContainer", "Area2D")
        resource_paths = find_paths("/root/Main/GameMap/ResourcesContainer", "Area2D")
        units: list[dict[str, Any]] = []
        for path in unit_paths:
            props = properties(path)
            if int(props.get("player_owner", -1)) != 1:
                continue
            units.append(
                {
                    "path": path,
                    "unit_type": props.get("unit_type"),
                    "state": props.get("current_state"),
                    "carried_type": props.get("carried_resource_type"),
                    "carried_amount": props.get("carried_amount"),
                    "gather_target": props.get("gather_target"),
                    "dropoff_target": props.get("dropoff_target"),
                    "build_target": props.get("build_target"),
                    "move_target": props.get("move_target"),
                    "position": props.get("position"),
                    "path": props.get("path"),
                    "path_index": props.get("path_index"),
                    "navigation_active": props.get("_navigation_active"),
                    "navigation_goal": props.get("_navigation_goal"),
                    "navigation_failed_repaths": props.get("_navigation_failed_repaths"),
                    "navigation_stall_repaths": props.get("_navigation_stall_repaths"),
                    "gather_offset": props.get("_gather_offset"),
                    "gather_last_known_position": props.get("_gather_last_known_position"),
                    "gather_last_known_instance_id": props.get("_gather_last_known_instance_id"),
                    "unreachable_resource_ids_until": props.get("_unreachable_resource_ids_until"),
                }
            )
        buildings: list[dict[str, Any]] = []
        for path in building_paths:
            props = properties(path)
            if int(props.get("player_owner", -1)) != 1:
                continue
            buildings.append(
                {
                    "path": path,
                    "building_type": props.get("building_type"),
                    "state": props.get("state"),
                    "build_progress": props.get("build_progress"),
                    "farm_remaining": props.get("farm_remaining"),
                    "position": props.get("position"),
                }
            )
        resources: list[dict[str, Any]] = []
        for path in resource_paths:
            props = properties(path)
            resource_type = props.get("resource_type")
            if resource_type not in {"food", "wood", "gold", "stone"}:
                continue
            resources.append(
                {
                    "path": path,
                    "resource_type": resource_type,
                    "remaining": props.get("remaining"),
                    "tile_position": props.get("tile_position"),
                    "position": props.get("position"),
                    "visible": props.get("visible"),
                }
            )
        ai_state = properties("/root/Main/AIController")
        result = {
            "main": main_state,
            "ai": ai_state,
            "units": units,
            "buildings": buildings,
            "resources": resources,
        }
        encoded = json.dumps(result, indent=2, sort_keys=True)
        print(encoded)
        if args.out is not None:
            args.out.resolve().write_text(encoded + "\n", encoding="utf-8")
        return 0
    finally:
        if client is not None:
            try:
                tool_text("editor", {"action": "stop"}, timeout=5.0)
            except Exception:
                pass
            try:
                client.stop()
            except Exception:
                pass
        if editor is not None and editor.poll() is None:
            editor.terminate()
            try:
                editor.wait(timeout=5.0)
            except subprocess.TimeoutExpired:
                editor.kill()
        log_handle.close()


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Phone-oriented deterministic MCP playability checks for AOEM.

Validates touch-driven command flow and progression UX without depending on
desktop right-click workflows.
"""

from __future__ import annotations

import argparse
import base64
import json
import struct
import sys
import time
from dataclasses import dataclass
from typing import Any

from mcp_smoke_test import MCPClient, MCPError, parse_log_messages, summarize_errors


PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


@dataclass
class CheckResult:
    name: str
    passed: bool
    detail: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run deterministic phone playability checks via MCP.")
    parser.add_argument("--server-cmd", default="npx -y @satelliteoflove/godot-mcp", help="MCP server command")
    parser.add_argument("--scene", default="res://scenes/main/main.tscn", help="Scene path to run")
    parser.add_argument("--startup-timeout", type=float, default=25.0, help="Seconds to wait for playing state")
    parser.add_argument("--request-timeout", type=float, default=25.0, help="Default MCP request timeout")
    parser.add_argument("--min-fps", type=float, default=15.0, help="Minimum acceptable FPS")
    parser.add_argument("--max-frame-time-ms", type=float, default=120.0, help="Maximum acceptable frame time")
    parser.add_argument("--verbose", action="store_true", help="Verbose MCP notifications/stderr")
    return parser.parse_args()


def parse_png_size_from_image_content(content: list[dict[str, Any]]) -> tuple[int, int]:
    image_part: dict[str, Any] | None = None
    for part in content:
        if part.get("type") == "image":
            image_part = part
            break
    if image_part is None:
        raise MCPError("No image content returned")
    data_b64 = image_part.get("data", "")
    if not data_b64:
        raise MCPError("Image content missing base64 payload")
    raw = base64.b64decode(data_b64)
    if len(raw) < 24 or raw[:8] != PNG_SIGNATURE:
        raise MCPError("Screenshot payload is not a valid PNG")
    width, height = struct.unpack(">II", raw[16:24])
    return int(width), int(height)


def touch_tap(x: int, y: int, start_ms: int, index: int = 0) -> list[dict[str, Any]]:
    return [
        {
            "action_name": f"pointer:screen_touch:{index}:{x}:{y}:1",
            "index": index,
            "position": {"x": x, "y": y},
            "pressed": True,
            "start_ms": start_ms,
            "duration_ms": 0,
        },
        {
            "action_name": f"pointer:screen_touch:{index}:{x}:{y}:0",
            "index": index,
            "position": {"x": x, "y": y},
            "pressed": False,
            "start_ms": start_ms + 70,
            "duration_ms": 0,
        },
    ]


def touch_drag(
    x0: int,
    y0: int,
    x1: int,
    y1: int,
    start_ms: int,
    index: int = 0,
) -> list[dict[str, Any]]:
    return [
        {
            "action_name": f"pointer:screen_touch:{index}:{x0}:{y0}:1",
            "index": index,
            "position": {"x": x0, "y": y0},
            "pressed": True,
            "start_ms": start_ms,
            "duration_ms": 0,
        },
        {
            "action_name": f"pointer:screen_drag:{index}:{x1}:{y1}:{x1 - x0}:{y1 - y0}",
            "index": index,
            "position": {"x": x1, "y": y1},
            "relative": {"x": x1 - x0, "y": y1 - y0},
            "start_ms": start_ms + 110,
            "duration_ms": 0,
        },
        {
            "action_name": f"pointer:screen_touch:{index}:{x1}:{y1}:0",
            "index": index,
            "position": {"x": x1, "y": y1},
            "pressed": False,
            "start_ms": start_ms + 190,
            "duration_ms": 0,
        },
    ]


def main() -> int:
    args = parse_args()
    results: list[CheckResult] = []
    client = MCPClient(args.server_cmd, request_timeout=args.request_timeout, verbose=args.verbose)
    project_running = False

    def record(name: str, passed: bool, detail: str) -> None:
        results.append(CheckResult(name=name, passed=passed, detail=detail))
        status = "PASS" if passed else "FAIL"
        print(f"[{status}] {name}: {detail}")

    def tool_text(name: str, arguments: dict[str, Any], timeout: float | None = None) -> str:
        content = client.call_tool(name, arguments, timeout=timeout)
        return client.text_from_content(content)

    def get_new_errors(clear: bool = True) -> list[dict[str, Any]]:
        text = tool_text("editor", {"action": "get_log_messages", "clear": clear, "limit": 200})
        return parse_log_messages(text)

    def capture_screenshot_size() -> tuple[int, int]:
        last_error: Exception | None = None
        for attempt in range(4):
            if attempt > 0:
                time.sleep(0.5 * attempt)
            try:
                content = client.call_tool("editor", {"action": "screenshot_game", "max_width": 0}, timeout=30.0)
                return parse_png_size_from_image_content(content)
            except Exception as exc:  # noqa: BLE001
                last_error = exc
        raise MCPError(f"Failed to capture screenshot size: {last_error}")

    def run_touch_scenario(name: str, inputs: list[dict[str, Any]], timeout: float = 30.0) -> None:
        sequence_text = tool_text("input", {"action": "sequence", "inputs": inputs}, timeout=timeout)
        _ = capture_screenshot_size()
        scenario_errors = get_new_errors(clear=True)
        if scenario_errors:
            record(name, False, f"Runtime errors: {summarize_errors(scenario_errors)}")
            raise MCPError(f"runtime errors during {name}")
        record(name, True, sequence_text)

    def node_properties(path: str, retries: int = 4) -> dict[str, Any]:
        last_error: Exception | None = None
        for attempt in range(retries):
            if attempt > 0:
                time.sleep(0.2 * attempt)
            try:
                text = tool_text("node", {"action": "get_properties", "node_path": path}, timeout=20.0)
                payload = client.parse_json_text(text)
                if isinstance(payload, dict) and "properties" in payload and isinstance(payload["properties"], dict):
                    return payload["properties"]
                if isinstance(payload, dict):
                    return payload
                return {}
            except Exception as exc:  # noqa: BLE001
                last_error = exc
        raise MCPError(f"Failed to read node properties for {path}: {last_error}")

    def vec2_xy(value: Any) -> tuple[float, float]:
        if isinstance(value, dict):
            return float(value.get("x", 0.0)), float(value.get("y", 0.0))
        if isinstance(value, (list, tuple)) and len(value) >= 2:
            return float(value[0]), float(value[1])
        return 0.0, 0.0

    def camera_position() -> tuple[float, float]:
        props = node_properties("/root/Main/GameMap/Camera2D")
        return vec2_xy(props.get("position", {"x": 0.0, "y": 0.0}))

    try:
        client.initialize()
        tools = client.list_tools()
        tool_names = {tool.get("name") for tool in tools}
        required = {"editor", "input", "project", "node"}
        missing = sorted(required - tool_names)
        if missing:
            record("tooling_available", False, f"Missing required MCP tools: {', '.join(missing)}")
            raise MCPError("required tools unavailable")
        record("tooling_available", True, "editor/input/project/node tools discovered")

        addon_status = client.parse_json_text(tool_text("project", {"action": "addon_status"}))
        if not bool(addon_status.get("connected", False)):
            record("addon_connection", False, "Not connected to Godot editor with godot_mcp enabled.")
            raise MCPError("addon not connected")
        record(
            "addon_connection",
            True,
            "connected (server=%s addon=%s)"
            % (addon_status.get("server_version"), addon_status.get("addon_version")),
        )

        _ = get_new_errors(clear=True)
        tool_text("editor", {"action": "run", "scene_path": args.scene})
        project_running = True

        startup_deadline = time.monotonic() + args.startup_timeout
        while time.monotonic() < startup_deadline:
            state = client.parse_json_text(tool_text("editor", {"action": "get_state"}))
            if state.get("is_playing", False):
                break
            time.sleep(0.4)
        else:
            record("startup_to_gameplay", False, "Game did not enter playing state before timeout")
            raise MCPError("startup timeout")

        screen_w, screen_h = capture_screenshot_size()
        startup_errors = get_new_errors(clear=True)
        if startup_errors:
            record("startup_to_gameplay", False, f"Runtime errors after startup: {summarize_errors(startup_errors)}")
            raise MCPError("startup runtime errors")
        record("startup_to_gameplay", True, f"screen={screen_w}x{screen_h}")

        center_x = int(screen_w * 0.5)
        center_y = int(screen_h * 0.5)
        map_target_x = int(screen_w * 0.64)
        map_target_y = int(screen_h * 0.58)
        gather_x = int(screen_w * 0.34)
        gather_y = int(screen_h * 0.48)
        build_button_x = int(screen_w * 0.88)
        build_button_y = int(screen_h * 0.92)
        cancel_button_x = int(screen_w * 0.50)
        cancel_button_y = int(screen_h * 0.92)
        minimap_left = 8
        minimap_bottom = screen_h - 8

        run_touch_scenario(
            "touch_select_move_smoke",
            touch_tap(center_x, center_y, 0) + touch_tap(map_target_x, map_target_y, 260),
            timeout=35.0,
        )

        run_touch_scenario(
            "touch_villager_gather_smoke",
            [{"action_name": "idle_villager", "start_ms": 0, "duration_ms": 0}]
            + touch_tap(center_x, center_y, 200)
            + touch_tap(gather_x, gather_y, 420),
            timeout=35.0,
        )

        run_touch_scenario(
            "touch_build_place_cancel_smoke",
            touch_tap(build_button_x, build_button_y, 0)
            + touch_tap(center_x, center_y, 260)
            + touch_tap(cancel_button_x, cancel_button_y, 560)
            + [{"action_name": "cancel", "start_ms": 800, "duration_ms": 0}],
            timeout=40.0,
        )

        minimap_inset_candidates = [0, 24, 48, 72]
        minimap_delta_threshold = 8.0
        minimap_observations: list[str] = []
        minimap_moved = False
        for inset in minimap_inset_candidates:
            start_x = int(minimap_left + 24)
            start_y = int(minimap_bottom - inset - 24)
            end_x = int(minimap_left + 188)
            end_y = int(minimap_bottom - inset - 188)
            if end_y < 0:
                continue

            camera_before_x, camera_before_y = camera_position()
            run_touch_scenario(
                f"touch_minimap_reposition_smoke_inset_{inset}",
                touch_drag(start_x, start_y, end_x, end_y, 0),
                timeout=35.0,
            )
            camera_after_x, camera_after_y = camera_position()
            dx = camera_after_x - camera_before_x
            dy = camera_after_y - camera_before_y
            moved = abs(dx) + abs(dy)
            minimap_observations.append("touch(inset=%d)=%.1f" % (inset, moved))
            if moved >= minimap_delta_threshold:
                minimap_moved = True
                break

            mouse_fallback_inputs: list[dict[str, Any]] = [
                {
                    "action_name": f"pointer:mouse_button:1:{start_x}:{start_y}:1",
                    "button_index": 1,
                    "button_mask": 1,
                    "pressed": True,
                    "position": {"x": start_x, "y": start_y},
                    "start_ms": 0,
                    "duration_ms": 0,
                },
                {
                    "action_name": f"pointer:mouse_motion:{end_x}:{end_y}:{end_x - start_x}:{end_y - start_y}:1",
                    "position": {"x": end_x, "y": end_y},
                    "relative": {"x": end_x - start_x, "y": end_y - start_y},
                    "button_mask": 1,
                    "start_ms": 120,
                    "duration_ms": 0,
                },
                {
                    "action_name": f"pointer:mouse_button:1:{end_x}:{end_y}:0",
                    "button_index": 1,
                    "button_mask": 0,
                    "pressed": False,
                    "position": {"x": end_x, "y": end_y},
                    "start_ms": 200,
                    "duration_ms": 0,
                },
            ]
            mouse_before_x, mouse_before_y = camera_position()
            run_touch_scenario(f"minimap_mouse_fallback_smoke_inset_{inset}", mouse_fallback_inputs, timeout=30.0)
            mouse_after_x, mouse_after_y = camera_position()
            mdx = mouse_after_x - mouse_before_x
            mdy = mouse_after_y - mouse_before_y
            mouse_moved = abs(mdx) + abs(mdy)
            minimap_observations.append("mouse(inset=%d)=%.1f" % (inset, mouse_moved))
            if mouse_moved >= minimap_delta_threshold:
                minimap_moved = True
                break

        if not minimap_moved:
            detail = "No camera movement from minimap interaction (%s)" % ", ".join(minimap_observations)
            record("touch_minimap_camera_delta", False, detail)
            raise MCPError("minimap interaction did not move camera")
        record("touch_minimap_camera_delta", True, ", ".join(minimap_observations))

        hint_props = node_properties("/root/Main/HUD/Root/ProgressionHintPanel/ProgressionHintLabel")
        hint_text = str(hint_props.get("text", "")).strip()
        if hint_text == "":
            record("progression_hint_validation", False, "Progression hint label text is empty")
            raise MCPError("missing progression hint text")
        record("progression_hint_validation", True, hint_text)

        perf = client.parse_json_text(tool_text("editor", {"action": "get_performance"}))
        fps = float(perf.get("fps", 0.0))
        frame_time_ms = float(perf.get("frame_time_ms", 0.0))
        perf_ok = fps >= args.min_fps and frame_time_ms <= args.max_frame_time_ms
        if not perf_ok:
            record(
                "performance_guardrail",
                False,
                f"fps={fps:.2f} (<{args.min_fps:.2f}) or frame_time_ms={frame_time_ms:.2f} (>{args.max_frame_time_ms:.2f})",
            )
            raise MCPError("performance below threshold")
        record("performance_guardrail", True, f"fps={fps:.2f}, frame_time_ms={frame_time_ms:.2f}")

        final_errors = get_new_errors(clear=True)
        if final_errors:
            record("runtime_errors", False, summarize_errors(final_errors))
            raise MCPError("runtime errors present at end of phone playability run")
        record("runtime_errors", True, "none")

    except Exception as exc:  # noqa: BLE001
        if not results or results[-1].passed:
            record("playability_runtime", False, str(exc))
    finally:
        if project_running:
            try:
                tool_text("editor", {"action": "stop"})
            except Exception:  # noqa: BLE001
                pass
        client.stop()

    passed = sum(1 for result in results if result.passed)
    failed = len(results) - passed
    print("")
    print("Phone Playability Summary")
    print(f"- Total checks: {len(results)}")
    print(f"- Passed: {passed}")
    print(f"- Failed: {failed}")
    if failed > 0:
        print("- Status: FAIL")
        return 1
    print("- Status: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())

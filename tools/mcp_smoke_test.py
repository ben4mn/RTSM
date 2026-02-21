#!/usr/bin/env python3
"""Deterministic MCP smoke harness for AOEM.

Runs a fixed set of playtest checks through godot-mcp using stdio JSON-RPC.
"""

from __future__ import annotations

import argparse
import json
import select
import shlex
import subprocess
import sys
import threading
import time
from collections import deque
from dataclasses import dataclass
from typing import Any


PROTOCOL_VERSION = "2024-11-05"


class MCPError(RuntimeError):
    """Raised for MCP transport or tool invocation failures."""


@dataclass
class CheckResult:
    name: str
    passed: bool
    detail: str


class MCPClient:
    def __init__(self, server_cmd: str, request_timeout: float, verbose: bool) -> None:
        self.server_cmd = server_cmd
        self.request_timeout = request_timeout
        self.verbose = verbose
        self._next_id = 1
        self._stderr_lines: deque[str] = deque(maxlen=200)
        self._stderr_lock = threading.Lock()
        self.process = subprocess.Popen(
            shlex.split(server_cmd),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
        self._stderr_thread = threading.Thread(target=self._drain_stderr, daemon=True)
        self._stderr_thread.start()

    def _drain_stderr(self) -> None:
        assert self.process.stderr is not None
        while True:
            line = self.process.stderr.readline()
            if line == "":
                return
            with self._stderr_lock:
                self._stderr_lines.append(line.rstrip("\n"))
            if self.verbose:
                print(f"[mcp-stderr] {line.rstrip()}")

    def _send(self, payload: dict[str, Any]) -> None:
        if self.process.stdin is None:
            raise MCPError("MCP stdin is unavailable")
        self.process.stdin.write(json.dumps(payload) + "\n")
        self.process.stdin.flush()

    def _read_message(self, timeout: float) -> dict[str, Any]:
        if self.process.stdout is None:
            raise MCPError("MCP stdout is unavailable")

        deadline = time.monotonic() + timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise MCPError("Timed out waiting for MCP response")

            ready, _, _ = select.select([self.process.stdout.fileno()], [], [], min(0.2, remaining))
            if not ready:
                continue

            line = self.process.stdout.readline()
            if line == "":
                code = self.process.poll()
                raise MCPError(f"MCP server exited unexpectedly (code={code})")

            line = line.strip()
            if not line:
                continue

            try:
                message = json.loads(line)
            except json.JSONDecodeError:
                if self.verbose:
                    print(f"[mcp-stdout] Non-JSON line ignored: {line}")
                continue

            if self.verbose and "id" not in message:
                print(f"[mcp-notify] {line}")
            return message

    def request(self, method: str, params: dict[str, Any] | None = None, timeout: float | None = None) -> dict[str, Any]:
        request_id = self._next_id
        self._next_id += 1
        self._send(
            {
                "jsonrpc": "2.0",
                "id": request_id,
                "method": method,
                "params": params or {},
            }
        )

        started = time.monotonic()
        limit = timeout if timeout is not None else self.request_timeout
        while True:
            elapsed = time.monotonic() - started
            remaining = limit - elapsed
            if remaining <= 0:
                raise MCPError(f"Timed out waiting for response to {method}")

            msg = self._read_message(timeout=remaining)
            if msg.get("id") == request_id:
                return msg

    def notify(self, method: str, params: dict[str, Any] | None = None) -> None:
        self._send(
            {
                "jsonrpc": "2.0",
                "method": method,
                "params": params or {},
            }
        )

    def initialize(self) -> None:
        response = self.request(
            "initialize",
            {
                "protocolVersion": PROTOCOL_VERSION,
                "capabilities": {},
                "clientInfo": {"name": "aoem-mcp-smoke", "version": "1.0"},
            },
            timeout=max(45.0, self.request_timeout),
        )
        if "error" in response:
            raise MCPError(f"initialize failed: {response['error']}")
        self.notify("notifications/initialized", {})

    def list_tools(self) -> list[dict[str, Any]]:
        response = self.request("tools/list", {})
        if "error" in response:
            raise MCPError(f"tools/list failed: {response['error']}")
        result = response.get("result", {})
        return result.get("tools", [])

    def call_tool(self, name: str, arguments: dict[str, Any], timeout: float | None = None) -> list[dict[str, Any]]:
        response = self.request(
            "tools/call",
            {"name": name, "arguments": arguments},
            timeout=timeout,
        )
        if "error" in response:
            raise MCPError(f"tools/call {name} failed: {response['error']}")

        result = response.get("result", {})
        if result.get("isError", False):
            text = self.text_from_content(result.get("content", []))
            raise MCPError(f"Tool '{name}' returned error: {text}")
        return result.get("content", [])

    @staticmethod
    def text_from_content(content: list[dict[str, Any]]) -> str:
        text_parts = [part.get("text", "") for part in content if part.get("type") == "text"]
        return "\n".join([t for t in text_parts if t])

    @staticmethod
    def parse_json_text(text: str) -> Any:
        try:
            return json.loads(text)
        except json.JSONDecodeError as exc:
            raise MCPError(f"Expected JSON text but got: {text[:160]}") from exc

    def stop(self) -> None:
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()

    def stderr_tail(self) -> str:
        with self._stderr_lock:
            return "\n".join(self._stderr_lines)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run deterministic AOEM MCP smoke checks.")
    parser.add_argument(
        "--server-cmd",
        default="npx -y @satelliteoflove/godot-mcp",
        help="Command used to start the MCP server.",
    )
    parser.add_argument(
        "--scene",
        default="res://scenes/main/main.tscn",
        help="Scene path to run for the smoke test.",
    )
    parser.add_argument(
        "--startup-timeout",
        type=float,
        default=20.0,
        help="Seconds to wait for the game to enter playing state.",
    )
    parser.add_argument(
        "--request-timeout",
        type=float,
        default=20.0,
        help="Default timeout in seconds for each MCP request.",
    )
    parser.add_argument(
        "--min-fps",
        type=float,
        default=15.0,
        help="Minimum acceptable FPS for the smoke run.",
    )
    parser.add_argument(
        "--max-frame-time-ms",
        type=float,
        default=120.0,
        help="Maximum acceptable frame time (ms) for the smoke run.",
    )
    parser.add_argument(
        "--phase4-sim-seconds",
        type=float,
        default=75.0,
        help="Seconds to keep the match running for Phase 4 economy/AI stability checks.",
    )
    parser.add_argument(
        "--allow-version-mismatch",
        action="store_true",
        help="Do not fail if addon/server versions differ.",
    )
    parser.add_argument(
        "--keep-running",
        action="store_true",
        help="Do not send editor stop command at the end of the run.",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Print MCP notifications and stderr lines.",
    )
    return parser.parse_args()


def summarize_errors(messages: list[dict[str, Any]], limit: int = 3) -> str:
    if not messages:
        return "none"

    snippets: list[str] = []
    for msg in messages[:limit]:
        text = str(msg.get("message", "")).strip().replace("\n", " ")
        file_name = str(msg.get("file", ""))
        line = msg.get("line", 0)
        if file_name:
            snippets.append(f"{file_name}:{line} {text}")
        else:
            snippets.append(text)
    if len(messages) > limit:
        snippets.append(f"... +{len(messages) - limit} more")
    return " | ".join(snippets)


def parse_log_messages(text: str) -> list[dict[str, Any]]:
    stripped = text.strip()
    if stripped == "" or stripped == "No log messages":
        return []

    payload: Any
    try:
        payload = json.loads(stripped)
    except json.JSONDecodeError:
        return [{"message": stripped}]

    if isinstance(payload, dict):
        messages = payload.get("messages", [])
        if isinstance(messages, list):
            return [msg for msg in messages if isinstance(msg, dict)]
        return []

    if isinstance(payload, list):
        return [msg for msg in payload if isinstance(msg, dict)]

    return []


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

    def capture_scenario_screenshot(check_name: str) -> None:
        screenshot_content = client.call_tool(
            "editor",
            {"action": "screenshot_game", "max_width": 640},
            timeout=30.0,
        )
        has_image = any(part.get("type") == "image" for part in screenshot_content)
        if not has_image:
            raise MCPError(f"{check_name}: no screenshot image content returned")

    def run_input_scenario(check_name: str, inputs: list[dict[str, Any]], timeout: float = 30.0) -> None:
        sequence_text = tool_text(
            "input",
            {
                "action": "sequence",
                "inputs": inputs,
            },
            timeout=timeout,
        )
        capture_scenario_screenshot(check_name)
        scenario_errors = get_new_errors(clear=True)
        if scenario_errors:
            record(check_name, False, f"Runtime errors: {summarize_errors(scenario_errors)}")
            raise MCPError(f"runtime errors during {check_name}")
        record(check_name, True, f"{sequence_text}; screenshot captured")

    try:
        client.initialize()

        tools = client.list_tools()
        tool_names = {tool.get("name") for tool in tools}
        required = {"editor", "input", "project"}
        missing = sorted(required - tool_names)
        if missing:
            record("tooling_available", False, f"Missing required MCP tools: {', '.join(missing)}")
            raise MCPError("required tools unavailable")
        record("tooling_available", True, "editor/input/project tools discovered")

        addon_status_text = tool_text("project", {"action": "addon_status"})
        addon_status = client.parse_json_text(addon_status_text)
        connected = bool(addon_status.get("connected", False))
        versions_match = bool(addon_status.get("versions_match", False))
        if not connected:
            record(
                "addon_connection",
                False,
                "Not connected to Godot editor. Open AOEM in Godot with the godot_mcp plugin enabled.",
            )
            raise MCPError("addon not connected")
        if versions_match or args.allow_version_mismatch:
            detail = (
                f"connected (server={addon_status.get('server_version')}, "
                f"addon={addon_status.get('addon_version')}, versions_match={versions_match})"
            )
            record("addon_connection", True, detail)
        else:
            record(
                "addon_connection",
                False,
                (
                    f"Version mismatch (server={addon_status.get('server_version')}, "
                    f"addon={addon_status.get('addon_version')})."
                ),
            )
            raise MCPError("addon version mismatch")

        # Clear pre-existing captured errors before scenario checks.
        _ = get_new_errors(clear=True)

        tool_text("editor", {"action": "run", "scene_path": args.scene})
        project_running = True

        startup_deadline = time.monotonic() + args.startup_timeout
        playing = False
        state: dict[str, Any] = {}
        while time.monotonic() < startup_deadline:
            state_text = tool_text("editor", {"action": "get_state"})
            state = client.parse_json_text(state_text)
            if state.get("is_playing", False):
                playing = True
                break
            time.sleep(0.5)

        if not playing:
            record("startup_to_gameplay", False, f"Game did not enter playing state within {args.startup_timeout:.1f}s")
            raise MCPError("startup timeout")

        screenshot_content: list[dict[str, Any]] = []
        screenshot_error: str = ""
        # Give rendering a brief warm-up window after play starts.
        for attempt in range(3):
            if attempt > 0:
                time.sleep(0.6 * attempt)
            try:
                screenshot_content = client.call_tool(
                    "editor",
                    {"action": "screenshot_game", "max_width": 640},
                    timeout=30.0,
                )
                break
            except MCPError as exc:
                screenshot_error = str(exc)
                if "Screenshot request timed out" not in screenshot_error:
                    raise

        if not screenshot_content:
            record("startup_to_gameplay", False, f"Failed to capture screenshot: {screenshot_error}")
            raise MCPError("missing screenshot payload")

        has_image = any(part.get("type") == "image" for part in screenshot_content)
        if not has_image:
            record("startup_to_gameplay", False, "No screenshot image content returned")
            raise MCPError("missing screenshot payload")

        startup_errors = get_new_errors(clear=True)
        if startup_errors:
            record("startup_to_gameplay", False, f"Runtime errors after startup: {summarize_errors(startup_errors)}")
            raise MCPError("runtime errors during startup")
        record("startup_to_gameplay", True, f"scene playing and screenshot captured ({state.get('current_scene')})")

        input_map_text = tool_text("input", {"action": "get_map"})
        required_camera_actions = ["camera_up", "camera_down", "camera_left", "camera_right"]
        missing_camera_actions = [action for action in required_camera_actions if f"{action}:" not in input_map_text]
        if missing_camera_actions:
            record("camera_movement_smoke", False, f"Missing input actions: {', '.join(missing_camera_actions)}")
            raise MCPError("missing camera actions")

        camera_sequence_text = tool_text(
            "input",
            {
                "action": "sequence",
                "inputs": [
                    {"action_name": "camera_right", "start_ms": 0, "duration_ms": 350},
                    {"action_name": "camera_down", "start_ms": 450, "duration_ms": 350},
                    {"action_name": "camera_left", "start_ms": 900, "duration_ms": 350},
                    {"action_name": "camera_up", "start_ms": 1350, "duration_ms": 350},
                ],
            },
            timeout=30.0,
        )
        camera_errors = get_new_errors(clear=True)
        if camera_errors:
            record("camera_movement_smoke", False, f"Runtime errors: {summarize_errors(camera_errors)}")
            raise MCPError("runtime errors during camera check")
        record("camera_movement_smoke", True, camera_sequence_text)

        selection_sequence_text = tool_text(
            "input",
            {
                "action": "sequence",
                "inputs": [
                    {"action_name": "select", "start_ms": 0, "duration_ms": 0},
                    {"action_name": "command", "start_ms": 120, "duration_ms": 0},
                ],
            },
            timeout=20.0,
        )
        selection_errors = get_new_errors(clear=True)
        if selection_errors:
            record("selection_command_smoke", False, f"Runtime errors: {summarize_errors(selection_errors)}")
            raise MCPError("runtime errors during selection/command check")
        record("selection_command_smoke", True, selection_sequence_text)

        build_sequence_text = tool_text(
            "input",
            {
                "action": "sequence",
                "inputs": [
                    {"action_name": "toggle_build_menu", "start_ms": 0, "duration_ms": 0},
                    {"action_name": "train_unit", "start_ms": 250, "duration_ms": 0},
                    {"action_name": "toggle_build_menu", "start_ms": 500, "duration_ms": 0},
                ],
            },
            timeout=20.0,
        )
        build_errors = get_new_errors(clear=True)
        if build_errors:
            record("build_menu_and_production_smoke", False, f"Runtime errors: {summarize_errors(build_errors)}")
            raise MCPError("runtime errors during build/production check")
        record("build_menu_and_production_smoke", True, build_sequence_text)

        phase2_required_actions = [
            "idle_villager",
            "select_all_military",
            "find_army",
            "toggle_build_menu",
            "cancel",
        ]
        missing_phase2_actions = [action for action in phase2_required_actions if f"{action}:" not in input_map_text]
        if missing_phase2_actions:
            record("phase2_action_bindings", False, f"Missing input actions: {', '.join(missing_phase2_actions)}")
            raise MCPError("missing phase2 actions")
        record("phase2_action_bindings", True, "Touch/HUD/build-placement actions detected in input map")

        run_input_scenario(
            "phase2_touch_select_move_smoke",
            [
                {"action_name": "select", "start_ms": 0, "duration_ms": 0},
                {"action_name": "select", "start_ms": 220, "duration_ms": 0},
            ],
            timeout=25.0,
        )

        run_input_scenario(
            "phase2_touch_villager_gather_smoke",
            [
                {"action_name": "idle_villager", "start_ms": 0, "duration_ms": 0},
                {"action_name": "select", "start_ms": 180, "duration_ms": 0},
                {"action_name": "select", "start_ms": 360, "duration_ms": 0},
            ],
            timeout=25.0,
        )

        run_input_scenario(
            "phase2_hud_shortcuts_smoke",
            [
                {"action_name": "idle_villager", "start_ms": 0, "duration_ms": 0},
                {"action_name": "select_all_military", "start_ms": 220, "duration_ms": 0},
                {"action_name": "find_army", "start_ms": 420, "duration_ms": 0},
            ],
            timeout=25.0,
        )

        run_input_scenario(
            "phase2_invalid_placement_feedback_smoke",
            [
                {"action_name": "toggle_build_menu", "start_ms": 0, "duration_ms": 0},
                {"action_name": "select", "start_ms": 220, "duration_ms": 0},
                {"action_name": "select", "start_ms": 420, "duration_ms": 0},
                {"action_name": "cancel", "start_ms": 650, "duration_ms": 0},
                {"action_name": "toggle_build_menu", "start_ms": 900, "duration_ms": 0},
            ],
            timeout=30.0,
        )

        phase3_required_actions = [
            "patrol_command",
            "toggle_stance",
            "select_all_military",
            "command",
        ]
        missing_phase3_actions = [action for action in phase3_required_actions if f"{action}:" not in input_map_text]
        if missing_phase3_actions:
            record("phase3_action_bindings", False, f"Missing input actions: {', '.join(missing_phase3_actions)}")
            raise MCPError("missing phase3 actions")
        record("phase3_action_bindings", True, "Patrol + stance + army command actions detected in input map")

        run_input_scenario(
            "phase3_patrol_command_smoke",
            [
                {"action_name": "select_all_military", "start_ms": 0, "duration_ms": 0},
                {"action_name": "patrol_command", "start_ms": 220, "duration_ms": 0},
                {"action_name": "command", "start_ms": 460, "duration_ms": 0},
                {"action_name": "find_army", "start_ms": 760, "duration_ms": 0},
            ],
            timeout=30.0,
        )

        run_input_scenario(
            "phase3_stance_attack_move_smoke",
            [
                {"action_name": "select_all_military", "start_ms": 0, "duration_ms": 0},
                {"action_name": "toggle_stance", "start_ms": 220, "duration_ms": 0},
                {"action_name": "command", "start_ms": 440, "duration_ms": 0},
                {"action_name": "toggle_stance", "start_ms": 720, "duration_ms": 0},
                {"action_name": "command", "start_ms": 940, "duration_ms": 0},
            ],
            timeout=30.0,
        )

        phase4_wait_ms = int(max(30.0, args.phase4_sim_seconds) * 1000.0)
        remaining_ms = phase4_wait_ms
        phase4_segment_ms = 22000
        segment_count = 0
        while remaining_ms > 0:
            segment_count += 1
            current_ms = min(phase4_segment_ms, remaining_ms)
            sequence_text = tool_text(
                "input",
                {
                    "action": "sequence",
                    "inputs": [
                        {"action_name": "find_army", "start_ms": 0, "duration_ms": 0},
                        {"action_name": "idle_villager", "start_ms": max(250, current_ms - 420), "duration_ms": 0},
                    ],
                },
                timeout=max(current_ms / 1000.0 + 10.0, 30.0),
            )
            segment_errors = get_new_errors(clear=True)
            if segment_errors:
                record(
                    "phase4_long_simulation_smoke",
                    False,
                    f"Runtime errors during segment {segment_count}: {summarize_errors(segment_errors)}",
                )
                raise MCPError("runtime errors during phase4 long simulation")
            remaining_ms -= current_ms
            if args.verbose:
                print(f"[phase4] segment {segment_count} complete: {sequence_text}")

        capture_scenario_screenshot("phase4_long_simulation_smoke")
        phase4_errors = get_new_errors(clear=True)
        if phase4_errors:
            record("phase4_long_simulation_smoke", False, f"Runtime errors: {summarize_errors(phase4_errors)}")
            raise MCPError("runtime errors during phase4 long simulation")
        record(
            "phase4_long_simulation_smoke",
            True,
            f"Completed {segment_count} segment(s) across {phase4_wait_ms / 1000.0:.1f}s; screenshot captured",
        )

        phase4_perf_text = tool_text("editor", {"action": "get_performance"})
        phase4_perf = client.parse_json_text(phase4_perf_text)
        phase4_fps = float(phase4_perf.get("fps", 0.0))
        phase4_frame_time_ms = float(phase4_perf.get("frame_time_ms", 0.0))
        phase4_perf_ok = phase4_fps >= args.min_fps and phase4_frame_time_ms <= args.max_frame_time_ms
        if not phase4_perf_ok:
            record(
                "phase4_performance_guardrail",
                False,
                (
                    f"fps={phase4_fps:.2f} (<{args.min_fps:.2f}) or "
                    f"frame_time_ms={phase4_frame_time_ms:.2f} (>{args.max_frame_time_ms:.2f})"
                ),
            )
            raise MCPError("phase4 performance below threshold")
        record(
            "phase4_performance_guardrail",
            True,
            f"fps={phase4_fps:.2f}, frame_time_ms={phase4_frame_time_ms:.2f}",
        )

        perf_text = tool_text("editor", {"action": "get_performance"})
        perf = client.parse_json_text(perf_text)
        fps = float(perf.get("fps", 0.0))
        frame_time_ms = float(perf.get("frame_time_ms", 0.0))
        perf_ok = fps >= args.min_fps and frame_time_ms <= args.max_frame_time_ms
        if not perf_ok:
            record(
                "performance_guardrail",
                False,
                (
                    f"fps={fps:.2f} (<{args.min_fps:.2f}) or "
                    f"frame_time_ms={frame_time_ms:.2f} (>{args.max_frame_time_ms:.2f})"
                ),
            )
            raise MCPError("performance below threshold")
        record("performance_guardrail", True, f"fps={fps:.2f}, frame_time_ms={frame_time_ms:.2f}")

        final_errors = get_new_errors(clear=True)
        if final_errors:
            record("runtime_errors", False, summarize_errors(final_errors))
            raise MCPError("runtime errors present at end of run")
        record("runtime_errors", True, "none")

    except Exception as exc:  # noqa: BLE001
        if not results or results[-1].passed:
            record("smoke_runtime", False, str(exc))
        if args.verbose:
            print(f"[debug] terminating due to: {exc}")
    finally:
        if project_running and not args.keep_running:
            try:
                _ = tool_text("editor", {"action": "stop"})
            except Exception:  # noqa: BLE001
                pass
        client.stop()

    passed = sum(1 for result in results if result.passed)
    failed = len(results) - passed
    print("")
    print("Smoke Summary")
    print(f"- Total checks: {len(results)}")
    print(f"- Passed: {passed}")
    print(f"- Failed: {failed}")

    if failed > 0:
        print("- Status: FAIL")
        stderr_tail = client.stderr_tail()
        if stderr_tail:
            print("- MCP stderr (tail):")
            print(stderr_tail)
        return 1

    print("- Status: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())

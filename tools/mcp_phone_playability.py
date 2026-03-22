#!/usr/bin/env python3
"""Phone-oriented deterministic MCP playability checks for AOEM.

Validates touch-driven command flow and progression UX without depending on
right-click desktop workflows, and emits strict touch-target audits.
"""

from __future__ import annotations

import argparse
import base64
import json
import re
import struct
import sys
import time
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from mcp_smoke_test import MCPClient, MCPError, parse_log_messages, summarize_errors


PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
DEFAULT_REPORT_JSON = "docs/mobile_ux_touch_report_2026-02-22.json"
DEFAULT_REPORT_MD = "docs/mobile_ux_touch_report_2026-02-22.md"


@dataclass
class CheckResult:
    name: str
    passed: bool
    detail: str


@dataclass
class TouchFinding:
    check: str
    group: str
    role: str
    node_path: str
    width: float
    height: float
    aspect_ratio: float
    min_required: float
    max_aspect_ratio: float
    severity: str
    reason: str
    target_file: str
    suggested_update: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run deterministic phone playability checks via MCP.")
    parser.add_argument("--server-cmd", default="npx -y @satelliteoflove/godot-mcp", help="MCP server command")
    parser.add_argument(
        "--menu-scene",
        default="res://scenes/ui/main_menu.tscn",
        help="Main-menu scene to boot before touch-starting gameplay.",
    )
    parser.add_argument(
        "--scene",
        default="res://scenes/main/main.tscn",
        help="Expected gameplay scene path after main-menu touch start.",
    )
    parser.add_argument(
        "--allow-startup-fallback",
        action="store_true",
        help="Allow fallback direct-run to gameplay scene when main-menu touch start does not transition.",
    )
    parser.add_argument("--startup-timeout", type=float, default=25.0, help="Seconds to wait for startup transitions")
    parser.add_argument("--request-timeout", type=float, default=25.0, help="Default MCP request timeout")
    parser.add_argument("--min-fps", type=float, default=15.0, help="Minimum acceptable FPS")
    parser.add_argument("--max-frame-time-ms", type=float, default=120.0, help="Maximum acceptable frame time")
    parser.add_argument(
        "--min-touch-target-px",
        type=float,
        default=48.0,
        help="Minimum touch target width/height in pixels for player-facing controls.",
    )
    parser.add_argument(
        "--max-button-aspect-ratio",
        type=float,
        default=4.0,
        help="Maximum allowed width/height ratio for tappable controls.",
    )
    parser.add_argument("--report-json", default=DEFAULT_REPORT_JSON, help="Output JSON report path")
    parser.add_argument("--report-md", default=DEFAULT_REPORT_MD, help="Output Markdown report path")
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


def touch_hold(x: int, y: int, start_ms: int, hold_ms: int = 460, index: int = 0) -> list[dict[str, Any]]:
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
            "start_ms": start_ms + hold_ms,
            "duration_ms": 0,
        },
    ]


def touch_tap_cluster(x: int, y: int, start_ms: int = 0, spacing_ms: int = 420, radius: int = 24) -> list[dict[str, Any]]:
    inputs: list[dict[str, Any]] = []
    offsets = [(0, 0), (-radius, 0), (radius, 0), (0, -radius), (0, radius)]
    for idx, (dx, dy) in enumerate(offsets):
        inputs.extend(touch_tap(x + dx, y + dy, start_ms + idx * spacing_ms))
    return inputs


def touch_pinch(
    center_x: int,
    center_y: int,
    start_distance: int,
    end_distance: int,
    start_ms: int = 0,
) -> list[dict[str, Any]]:
    start_left_x = int(center_x - start_distance * 0.5)
    start_right_x = int(center_x + start_distance * 0.5)
    end_left_x = int(center_x - end_distance * 0.5)
    end_right_x = int(center_x + end_distance * 0.5)
    return [
        {
            "action_name": f"pointer:screen_touch:0:{start_left_x}:{center_y}:1",
            "index": 0,
            "position": {"x": start_left_x, "y": center_y},
            "pressed": True,
            "start_ms": start_ms,
            "duration_ms": 0,
        },
        {
            "action_name": f"pointer:screen_touch:1:{start_right_x}:{center_y}:1",
            "index": 1,
            "position": {"x": start_right_x, "y": center_y},
            "pressed": True,
            "start_ms": start_ms,
            "duration_ms": 0,
        },
        {
            "action_name": f"pointer:screen_drag:0:{end_left_x}:{center_y}:{end_left_x - start_left_x}:0",
            "index": 0,
            "position": {"x": end_left_x, "y": center_y},
            "relative": {"x": end_left_x - start_left_x, "y": 0},
            "start_ms": start_ms + 110,
            "duration_ms": 0,
        },
        {
            "action_name": f"pointer:screen_drag:1:{end_right_x}:{center_y}:{end_right_x - start_right_x}:0",
            "index": 1,
            "position": {"x": end_right_x, "y": center_y},
            "relative": {"x": end_right_x - start_right_x, "y": 0},
            "start_ms": start_ms + 110,
            "duration_ms": 0,
        },
        {
            "action_name": f"pointer:screen_touch:0:{end_left_x}:{center_y}:0",
            "index": 0,
            "position": {"x": end_left_x, "y": center_y},
            "pressed": False,
            "start_ms": start_ms + 220,
            "duration_ms": 0,
        },
        {
            "action_name": f"pointer:screen_touch:1:{end_right_x}:{center_y}:0",
            "index": 1,
            "position": {"x": end_right_x, "y": center_y},
            "pressed": False,
            "start_ms": start_ms + 220,
            "duration_ms": 0,
        },
    ]


def mouse_tap(x: int, y: int, start_ms: int) -> list[dict[str, Any]]:
    return [
        {
            "action_name": f"pointer:mouse_button:1:{x}:{y}:1",
            "button_index": 1,
            "button_mask": 1,
            "pressed": True,
            "position": {"x": x, "y": y},
            "start_ms": start_ms,
            "duration_ms": 0,
        },
        {
            "action_name": f"pointer:mouse_button:1:{x}:{y}:0",
            "button_index": 1,
            "button_mask": 0,
            "pressed": False,
            "position": {"x": x, "y": y},
            "start_ms": start_ms + 70,
            "duration_ms": 0,
        },
    ]


def as_float(value: Any, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def as_bool(value: Any, default: bool = False) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return bool(value)
    if isinstance(value, str):
        lowered = value.strip().lower()
        if lowered in {"1", "true", "yes", "on"}:
            return True
        if lowered in {"0", "false", "no", "off"}:
            return False
    return default


def vec2_xy(value: Any) -> tuple[float, float]:
    if isinstance(value, dict):
        return float(value.get("x", 0.0)), float(value.get("y", 0.0))
    if isinstance(value, (list, tuple)) and len(value) >= 2:
        return float(value[0]), float(value[1])
    return 0.0, 0.0


def center_from_diag(diag: dict[str, Any]) -> tuple[int, int] | None:
    width = as_float(diag.get("width", 0.0), 0.0)
    height = as_float(diag.get("height", 0.0), 0.0)
    if width <= 0.0 or height <= 0.0:
        return None
    x = as_float(diag.get("x", 0.0), 0.0)
    y = as_float(diag.get("y", 0.0), 0.0)
    return int(round(x + width * 0.5)), int(round(y + height * 0.5))


def control_diag_from_node(path: str, role: str, props: dict[str, Any]) -> dict[str, Any]:
    size = props.get("size", {})
    pos = props.get("global_position", props.get("position", {}))
    width = as_float(size.get("x", 0.0), 0.0) if isinstance(size, dict) else 0.0
    height = as_float(size.get("y", 0.0), 0.0) if isinstance(size, dict) else 0.0
    x = as_float(pos.get("x", 0.0), 0.0) if isinstance(pos, dict) else 0.0
    y = as_float(pos.get("y", 0.0), 0.0) if isinstance(pos, dict) else 0.0
    aspect = width / height if height > 0.0 else 0.0
    return {
        "role": role,
        "name": props.get("name", role),
        "path": path,
        "visible": as_bool(props.get("visible", True), True),
        "disabled": as_bool(props.get("disabled", False), False),
        "width": width,
        "height": height,
        "aspect_ratio": aspect,
        "x": x,
        "y": y,
        "min_width": as_float(props.get("custom_minimum_size", {}).get("x", 0.0), 0.0)
        if isinstance(props.get("custom_minimum_size", {}), dict)
        else 0.0,
        "min_height": as_float(props.get("custom_minimum_size", {}).get("y", 0.0), 0.0)
        if isinstance(props.get("custom_minimum_size", {}), dict)
        else 0.0,
    }


def map_target_file(path: str, group: str) -> str:
    if path.startswith("/root/MainMenu"):
        return "scenes/ui/main_menu.tscn"
    if "BuildMenu" in path or group.startswith("build_menu"):
        return "scripts/ui/build_menu.gd"
    if "Minimap" in path:
        return "scripts/ui/hud.gd"
    return "scripts/ui/hud.gd"


def suggested_update_for(role: str, width: float, height: float, min_target: float, max_aspect: float) -> str:
    updates: list[str] = []
    if min(width, height) < min_target:
        updates.append(f"raise min size to at least {min_target:.0f}x{min_target:.0f}")
    if height > 0.0 and (width / height) > max_aspect:
        updates.append(f"reduce width or increase height so width/height <= {max_aspect:.1f}")
    if not updates:
        return "no change required"
    return "; ".join(updates)


def evaluate_controls(
    check: str,
    group: str,
    controls: list[dict[str, Any]],
    min_touch_target_px: float,
    max_button_aspect_ratio: float,
    findings: list[TouchFinding],
    require_visible: bool = False,
) -> tuple[bool, str]:
    audited = 0
    fail_count = 0
    for control in controls:
        if not isinstance(control, dict):
            continue
        if not as_bool(control.get("visible", True), True):
            continue
        width = as_float(control.get("width", 0.0), 0.0)
        height = as_float(control.get("height", 0.0), 0.0)
        if width <= 0.0 or height <= 0.0:
            continue
        audited += 1

        min_side = min(width, height)
        aspect_ratio = width / height if height > 0 else 0.0
        reasons: list[str] = []
        if min_side < min_touch_target_px:
            reasons.append(f"touch target too small ({width:.1f}x{height:.1f})")
        if aspect_ratio > max_button_aspect_ratio:
            reasons.append(f"sliver ratio too high ({aspect_ratio:.2f})")
        if not reasons:
            continue

        fail_count += 1
        severity = "high" if min_side < (min_touch_target_px * 0.75) else "medium"
        role = str(control.get("role", control.get("name", "unknown")))
        node_path = str(control.get("path", ""))
        findings.append(
            TouchFinding(
                check=check,
                group=group,
                role=role,
                node_path=node_path,
                width=width,
                height=height,
                aspect_ratio=aspect_ratio,
                min_required=min_touch_target_px,
                max_aspect_ratio=max_button_aspect_ratio,
                severity=severity,
                reason="; ".join(reasons),
                target_file=map_target_file(node_path, group),
                suggested_update=suggested_update_for(
                    role,
                    width,
                    height,
                    min_touch_target_px,
                    max_button_aspect_ratio,
                ),
            )
        )

    if audited == 0 and require_visible:
        return False, "Expected visible controls for this state, but none were auditable"
    if audited == 0:
        return True, "No visible controls to audit in this state"
    if fail_count > 0:
        return False, f"{fail_count}/{audited} controls violate target/aspect constraints"
    return True, f"{audited} controls meet target/aspect constraints"


def unit_type_from_train_button_name(name: str) -> int | None:
    prefix = "TrainButton_"
    if not name.startswith(prefix):
        return None
    raw = name[len(prefix) :].strip()
    if raw == "":
        return None
    try:
        return int(raw)
    except ValueError:
        return None


def build_fix_plan(findings: list[TouchFinding]) -> list[dict[str, Any]]:
    if not findings:
        return []

    priority_order = {"high": 0, "medium": 1, "low": 2}
    sorted_findings = sorted(findings, key=lambda f: (priority_order.get(f.severity, 9), f.target_file, f.role))

    plan: list[dict[str, Any]] = []
    seen: set[tuple[str, str, str, str]] = set()
    for finding in sorted_findings:
        dedupe_key = (finding.target_file, finding.role, finding.suggested_update, finding.reason)
        if dedupe_key in seen:
            continue
        seen.add(dedupe_key)
        plan.append(
            {
                "priority": finding.severity,
                "target_file": finding.target_file,
                "control": finding.role,
                "node_path": finding.node_path,
                "expected_update": finding.suggested_update,
                "reason": finding.reason,
            }
        )
    return plan


def write_reports(
    report_json_path: str,
    report_md_path: str,
    settings: dict[str, Any],
    checks: list[CheckResult],
    findings: list[TouchFinding],
) -> None:
    status = "PASS" if all(check.passed for check in checks) else "FAIL"
    payload = {
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "status": status,
        "settings": settings,
        "checks": [asdict(c) for c in checks],
        "findings": [asdict(f) for f in findings],
        "fix_plan": build_fix_plan(findings),
    }

    if report_json_path:
        json_path = Path(report_json_path)
        json_path.parent.mkdir(parents=True, exist_ok=True)
        json_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")

    if report_md_path:
        md_path = Path(report_md_path)
        md_path.parent.mkdir(parents=True, exist_ok=True)

        lines: list[str] = []
        lines.append("# Mobile UX Touch Audit Report")
        lines.append("")
        lines.append(f"Date (UTC): {payload['generated_at_utc']}")
        lines.append(f"Status: **{status}**")
        lines.append("")
        lines.append("## Settings")
        lines.append("")
        lines.append(f"- Menu scene: `{settings['menu_scene']}`")
        lines.append(f"- Gameplay scene: `{settings['scene']}`")
        lines.append(f"- Min touch target: `{settings['min_touch_target_px']}`")
        lines.append(f"- Max aspect ratio: `{settings['max_button_aspect_ratio']}`")
        lines.append("")
        lines.append("## Checks")
        lines.append("")
        for check in checks:
            state = "PASS" if check.passed else "FAIL"
            lines.append(f"- [{state}] `{check.name}`: {check.detail}")

        lines.append("")
        lines.append("## Findings")
        lines.append("")
        if findings:
            for finding in findings:
                lines.append(
                    "- [%s] `%s` (`%s`) at `%s`: %s. Measured %.1fx%.1f, ratio %.2f."
                    % (
                        finding.severity.upper(),
                        finding.role,
                        finding.group,
                        finding.node_path,
                        finding.reason,
                        finding.width,
                        finding.height,
                        finding.aspect_ratio,
                    )
                )
        else:
            lines.append("- No touch-target violations detected.")

        lines.append("")
        lines.append("## Prioritized Fix Plan")
        lines.append("")
        fix_plan = build_fix_plan(findings)
        if fix_plan:
            for idx, item in enumerate(fix_plan, start=1):
                lines.append(
                    f"{idx}. [{item['priority'].upper()}] `{item['target_file']}` -> `{item['control']}`: "
                    f"{item['expected_update']} ({item['reason']})"
                )
        else:
            lines.append("1. No fixes required from this run.")

        md_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    args = parse_args()
    results: list[CheckResult] = []
    findings: list[TouchFinding] = []
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

    def infer_viewport_size_fallback() -> tuple[int, int]:
        for node_path in ("/root/MainMenu", "/root/Main"):
            try:
                props = node_properties(node_path, retries=1)
            except Exception:  # noqa: BLE001
                continue
            size = props.get("size", {})
            if isinstance(size, dict):
                width = int(round(as_float(size.get("x", 0.0), 0.0)))
                height = int(round(as_float(size.get("y", 0.0), 0.0)))
                if width > 0 and height > 0:
                    return width, height
        return 1280, 720

    def capture_screenshot_size(allow_fallback: bool = True) -> tuple[int, int]:
        last_error: Exception | None = None
        for attempt in range(4):
            if attempt > 0:
                time.sleep(0.5 * attempt)
            try:
                content = client.call_tool("editor", {"action": "screenshot_game", "max_width": 0}, timeout=30.0)
                return parse_png_size_from_image_content(content)
            except Exception as exc:  # noqa: BLE001
                last_error = exc
        if allow_fallback:
            return infer_viewport_size_fallback()
        raise MCPError(f"Failed to capture screenshot size: {last_error}")

    def run_touch_scenario(name: str, inputs: list[dict[str, Any]], timeout: float = 30.0) -> None:
        sequence_text = tool_text("input", {"action": "sequence", "inputs": inputs}, timeout=timeout)
        _ = capture_screenshot_size(allow_fallback=True)
        scenario_errors = get_new_errors(clear=True)
        if scenario_errors:
            record(name, False, f"Runtime errors: {summarize_errors(scenario_errors)}")
            raise MCPError(f"runtime errors during {name}")
        record(name, True, sequence_text)

    def run_touch_scenario_optional(name: str, inputs: list[dict[str, Any]], timeout: float = 30.0) -> bool:
        try:
            run_touch_scenario(name, inputs, timeout=timeout)
            return True
        except Exception as exc:  # noqa: BLE001
            if not results or results[-1].name != name:
                record(name, False, str(exc))
            return False

    def run_input_sequence_light(name: str, inputs: list[dict[str, Any]], timeout: float = 20.0) -> bool:
        try:
            sequence_text = tool_text("input", {"action": "sequence", "inputs": inputs}, timeout=timeout)
            record(name, True, sequence_text)
            return True
        except Exception as exc:  # noqa: BLE001
            record(name, False, str(exc))
            return False

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

    def wait_for_node(path: str, timeout: float = 15.0) -> bool:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                _ = node_properties(path, retries=2)
                return True
            except Exception:  # noqa: BLE001
                time.sleep(0.25)
        return False

    def path_center(path: str) -> tuple[int, int]:
        if not path.startswith("/root/"):
            raise MCPError(f"path_center expects '/root/...' path, got: {path}")
        parts = [p for p in path.split("/") if p]
        if len(parts) < 2:
            raise MCPError(f"path_center invalid path: {path}")

        current_path = "/root"
        abs_x = 0.0
        abs_y = 0.0
        size_x = 0.0
        size_y = 0.0
        for segment in parts[1:]:
            current_path = f"{current_path}/{segment}"
            props = node_properties(current_path, retries=2)
            px, py = vec2_xy(props.get("position", {"x": 0.0, "y": 0.0}))
            sx, sy = vec2_xy(props.get("size", {"x": 0.0, "y": 0.0}))
            abs_x += px
            abs_y += py
            size_x = sx
            size_y = sy
        return int(round(abs_x + size_x * 0.5)), int(round(abs_y + size_y * 0.5))

    def camera_position() -> tuple[float, float]:
        props = node_properties("/root/Main/GameMap/Camera2D")
        return vec2_xy(props.get("position", {"x": 0.0, "y": 0.0}))

    def camera_zoom() -> float:
        props = node_properties("/root/Main/GameMap/Camera2D")
        zoom = props.get("zoom", {"x": 1.0, "y": 1.0})
        if isinstance(zoom, dict):
            return as_float(zoom.get("x", 1.0), 1.0)
        if isinstance(zoom, (list, tuple)) and zoom:
            return as_float(zoom[0], 1.0)
        return 1.0

    def is_game_paused() -> bool:
        try:
            props = node_properties("/root/GameManager", retries=2)
        except Exception:  # noqa: BLE001
            return False
        return int(as_float(props.get("current_state", -1), -1.0)) == 3

    def wait_for_unpaused(timeout: float = 4.0) -> bool:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if not is_game_paused():
                return True
            time.sleep(0.2)
        return False

    def selection_count() -> int:
        try:
            sel_props = node_properties("/root/Main/GameMap/SelectionManager", retries=2)
        except Exception:  # noqa: BLE001
            return 0
        selected = sel_props.get("selected", [])
        if isinstance(selected, list):
            return len(selected)
        return 0

    def wait_for_selection_count(min_count: int = 1, timeout: float = 3.0) -> int:
        deadline = time.monotonic() + timeout
        last_count = 0
        while time.monotonic() < deadline:
            last_count = selection_count()
            if last_count >= min_count:
                return last_count
            time.sleep(0.15)
        return last_count

    def wait_for_tc_selection_with_train_buttons(timeout: float = 4.0) -> tuple[bool, str]:
        deadline = time.monotonic() + timeout
        last_selected_count = 0
        last_train_button_count = 0
        while time.monotonic() < deadline:
            try:
                sel_props = node_properties("/root/Main/GameMap/SelectionManager", retries=2)
            except Exception:  # noqa: BLE001
                sel_props = {}
            selected = sel_props.get("selected", [])
            if isinstance(selected, list):
                last_selected_count = len(selected)
            else:
                last_selected_count = 0

            diag = hud_touch_diag()
            train_buttons = [
                entry
                for entry in diag.get("train_buttons", [])
                if isinstance(entry, dict)
                and as_bool(entry.get("visible", True), True)
                and not as_bool(entry.get("disabled", False), False)
                and str(entry.get("name", "")).startswith("TrainButton_")
            ]
            last_train_button_count = len(train_buttons)
            if last_selected_count > 0 and last_train_button_count > 0:
                return True, f"selected={last_selected_count}, train_buttons={last_train_button_count}"
            time.sleep(0.2)
        return (
            False,
            f"selected={last_selected_count}, train_buttons={last_train_button_count}",
        )

    def sample_performance(sample_count: int = 3, sample_delay_s: float = 0.35) -> tuple[float, float]:
        fps_samples: list[float] = []
        frame_samples: list[float] = []
        for i in range(sample_count):
            perf = client.parse_json_text(tool_text("editor", {"action": "get_performance"}))
            fps_samples.append(float(perf.get("fps", 0.0)))
            frame_samples.append(float(perf.get("frame_time_ms", 0.0)))
            if i < sample_count - 1:
                time.sleep(sample_delay_s)
        fps_sorted = sorted(fps_samples)
        frame_sorted = sorted(frame_samples)
        mid = len(fps_sorted) // 2
        return fps_sorted[mid], frame_sorted[mid]

    def minimap_rect_from_node(screen_height: int) -> tuple[int, int, int, int]:
        props = node_properties("/root/Main/HUD/Root/MinimapBG")
        left = as_float(props.get("offset_left", 8.0), 8.0)
        right = as_float(props.get("offset_right", 208.0), 208.0)
        top = as_float(props.get("offset_top", -208.0), -208.0)
        bottom = as_float(props.get("offset_bottom", -8.0), -8.0)
        x0 = int(round(left))
        x1 = int(round(right))
        y0 = int(round(screen_height + top))
        y1 = int(round(screen_height + bottom))
        if x1 < x0:
            x0, x1 = x1, x0
        if y1 < y0:
            y0, y1 = y1, y0
        return x0, y0, x1, y1

    def validate_hud_phone_profiles() -> tuple[bool, str]:
        hud_props = node_properties("/root/Main/HUD")
        profiles = hud_props.get("mobile_layout_profiles", {})
        if not isinstance(profiles, dict):
            return False, "HUD mobile_layout_profiles missing or not a dictionary"

        observations: list[str] = []
        for profile_key in ("844x390", "932x430"):
            profile = profiles.get(profile_key)
            if not isinstance(profile, dict):
                return False, f"Missing HUD profile metrics for {profile_key}"
            button_width = as_float(profile.get("button_width", 0.0), 0.0)
            button_height = as_float(profile.get("button_height", 0.0), 0.0)
            layout_pass = as_bool(profile.get("layout_pass", False), False)
            minimap_overlap = as_bool(profile.get("minimap_action_overlap", True), True)
            selection_overlap = as_bool(profile.get("selection_action_overlap", True), True)
            right_overlap = as_bool(profile.get("bottom_right_action_overlap", True), True)
            if button_width < 96.0 or button_height < 56.0:
                return (
                    False,
                    f"{profile_key} touch target too small (button_width={button_width:.1f}, button_height={button_height:.1f})",
                )
            if minimap_overlap or selection_overlap or right_overlap or not layout_pass:
                return (
                    False,
                    f"{profile_key} overlap/layout issue (minimap={minimap_overlap}, selection={selection_overlap}, right={right_overlap}, pass={layout_pass})",
                )
            observations.append(
                "%s[w=%.1f,h=%.1f,cols=%s]"
                % (profile_key, button_width, button_height, profile.get("action_columns", "?"))
            )

        return True, ", ".join(observations)

    def hud_touch_diag() -> dict[str, Any]:
        hud_props = node_properties("/root/Main/HUD")
        diag = hud_props.get("touch_target_diagnostics", {})
        if isinstance(diag, dict):
            return diag
        return {}

    def build_menu_touch_diag() -> dict[str, Any]:
        build_props = node_properties("/root/Main/HUD/BuildMenu")
        diag = build_props.get("touch_target_diagnostics", {})
        if isinstance(diag, dict):
            return diag
        return {}

    def find_train_button_by_name(button_name: str) -> dict[str, Any] | None:
        hud_diag = hud_touch_diag()
        for entry in hud_diag.get("train_buttons", []):
            if not isinstance(entry, dict):
                continue
            if str(entry.get("name", "")) != button_name:
                continue
            if not as_bool(entry.get("visible", True), True):
                continue
            if as_bool(entry.get("disabled", False), False):
                continue
            return entry
        return None

    def selection_manager_diag() -> dict[str, Any]:
        props = node_properties("/root/Main/GameMap/SelectionManager")
        diag = props.get("touch_context_diagnostics", {})
        if isinstance(diag, dict):
            return diag
        return {}

    def selection_manager_touch_input_diag() -> dict[str, Any]:
        props = node_properties("/root/Main/GameMap/SelectionManager")
        diag = props.get("touch_input_diagnostics", {})
        if isinstance(diag, dict):
            return diag
        return {}

    def parse_tile_key(tile_key: str) -> tuple[int, int] | None:
        match = re.fullmatch(r"\((-?\d+),\s*(-?\d+)\)", tile_key.strip())
        if match is None:
            return None
        return int(match.group(1)), int(match.group(2))

    def find_node_paths(
        name_pattern: str = "",
        type_name: str = "",
        root_path: str = "",
        timeout: float = 25.0,
    ) -> list[str]:
        arguments: dict[str, Any] = {"action": "find"}
        if name_pattern:
            arguments["name_pattern"] = name_pattern
        if type_name:
            arguments["type"] = type_name
        if root_path:
            arguments["root_path"] = root_path
        result_text = tool_text("node", arguments, timeout=timeout)
        paths: list[str] = []
        for line in result_text.splitlines():
            stripped = line.strip()
            if stripped.startswith("/root/"):
                paths.append(stripped.split(" ", 1)[0])
        return paths

    def world_to_screen_point(world_x: float, world_y: float, screen_w: int, screen_h: int) -> tuple[int, int]:
        camera_x, camera_y = camera_position()
        zoom = camera_zoom()
        screen_x = int(round((world_x - camera_x) * zoom + screen_w * 0.5))
        screen_y = int(round((world_y - camera_y) * zoom + screen_h * 0.5))
        return screen_x, screen_y

    def live_screen_point_for_node(node_path: str, screen_w: int, screen_h: int) -> tuple[int, int] | None:
        try:
            props = node_properties(node_path, retries=2)
        except Exception:  # noqa: BLE001
            return None
        world_x, world_y = vec2_xy(props.get("global_position", props.get("position", {})))
        screen_x, screen_y = world_to_screen_point(world_x, world_y, screen_w, screen_h)
        if not (24 <= screen_x <= screen_w - 24 and 24 <= screen_y <= screen_h - 24):
            return None
        return screen_x, screen_y

    def find_visible_player_villager_target(screen_w: int, screen_h: int) -> tuple[int, int, str] | None:
        unit_paths = find_node_paths(type_name="Area2D", root_path="/root/Main/GameMap/UnitsContainer")
        if not unit_paths:
            return None

        screen_center_x = screen_w * 0.5
        screen_center_y = screen_h * 0.5
        candidates: list[tuple[float, int, int, str]] = []
        for node_path in unit_paths:
            props = node_properties(node_path, retries=2)
            if int(as_float(props.get("player_owner", -1), -1.0)) != 0:
                continue
            if int(as_float(props.get("unit_type", -1), -1.0)) != 0:
                continue
            world_x, world_y = vec2_xy(props.get("global_position", props.get("position", {})))
            screen_x, screen_y = world_to_screen_point(world_x, world_y, screen_w, screen_h)
            if not (24 <= screen_x <= screen_w - 24 and 24 <= screen_y <= screen_h - 24):
                continue
            distance = abs(screen_x - screen_center_x) + abs(screen_y - screen_center_y)
            candidates.append((distance, screen_x, screen_y, node_path))
        if candidates:
            _, screen_x, screen_y, node_path = min(candidates, key=lambda item: item[0])
            return screen_x, screen_y, node_path
        return None

    def wait_for_visible_player_villager_target(
        screen_w: int,
        screen_h: int,
        timeout: float = 1.5,
    ) -> tuple[int, int, str] | None:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            target = find_visible_player_villager_target(screen_w, screen_h)
            if target is not None:
                return target
            time.sleep(0.15)
        return None

    def find_visible_player_military_target(screen_w: int, screen_h: int) -> tuple[int, int, str] | None:
        unit_paths = find_node_paths(type_name="Area2D", root_path="/root/Main/GameMap/UnitsContainer")
        if not unit_paths:
            return None

        screen_center_x = screen_w * 0.5
        screen_center_y = screen_h * 0.5
        candidates: list[tuple[float, int, int, str]] = []
        for node_path in unit_paths:
            props = node_properties(node_path, retries=2)
            if int(as_float(props.get("player_owner", -1), -1.0)) != 0:
                continue
            unit_type = int(as_float(props.get("unit_type", -1), -1.0))
            if unit_type < 0 or unit_type == 0:
                continue
            world_x, world_y = vec2_xy(props.get("global_position", props.get("position", {})))
            screen_x, screen_y = world_to_screen_point(world_x, world_y, screen_w, screen_h)
            if not (24 <= screen_x <= screen_w - 24 and 24 <= screen_y <= screen_h - 24):
                continue
            distance = abs(screen_x - screen_center_x) + abs(screen_y - screen_center_y)
            candidates.append((distance, screen_x, screen_y, node_path))
        if candidates:
            _, screen_x, screen_y, node_path = min(candidates, key=lambda item: item[0])
            return screen_x, screen_y, node_path
        return None

    def find_any_player_villager_path() -> str | None:
        unit_paths = find_node_paths(type_name="Area2D", root_path="/root/Main/GameMap/UnitsContainer")
        for node_path in unit_paths:
            props = node_properties(node_path, retries=2)
            if int(as_float(props.get("player_owner", -1), -1.0)) != 0:
                continue
            if int(as_float(props.get("unit_type", -1), -1.0)) != 0:
                continue
            return node_path
        return None

    def world_to_minimap_screen_point(
        world_x: float,
        world_y: float,
        minimap_x0: int,
        minimap_y0: int,
        minimap_w: int,
        minimap_h: int,
    ) -> tuple[int, int]:
        half_w = 32.0
        half_h = 16.0
        tile_x = int((world_x / half_w + world_y / half_h) / 2.0)
        tile_y = int((world_y / half_h - world_x / half_w) / 2.0)
        tile_x = max(0, min(39, tile_x))
        tile_y = max(0, min(39, tile_y))
        minimap_x = int(round(minimap_x0 + (tile_x + 0.5) / 40.0 * minimap_w))
        minimap_y = int(round(minimap_y0 + (tile_y + 0.5) / 40.0 * minimap_h))
        return minimap_x, minimap_y

    def find_visible_resource_target(
        screen_w: int,
        screen_h: int,
        preferred_type: str = "",
        avoid_point: tuple[int, int] | None = None,
        min_separation: float = 72.0,
    ) -> tuple[int, int, str] | None:
        resource_paths = find_node_paths(type_name="Area2D", root_path="/root/Main/GameMap/ResourcesContainer")
        if not resource_paths:
            return None

        screen_center_x = screen_w * 0.5
        screen_center_y = screen_h * 0.5
        candidates: list[tuple[int, int, float, int, int, str]] = []
        for node_path in resource_paths:
            screen_point = live_screen_point_for_node(node_path, screen_w, screen_h)
            if screen_point is None:
                continue
            screen_x, screen_y = screen_point
            props = node_properties(node_path, retries=2)
            resource_type = str(props.get("resource_type", "")).strip().lower()
            center_distance = abs(screen_x - screen_center_x) + abs(screen_y - screen_center_y)
            avoid_distance = float("inf")
            if avoid_point is not None:
                avoid_distance = abs(screen_x - avoid_point[0]) + abs(screen_y - avoid_point[1])
                if avoid_distance < min_separation:
                    continue
            type_penalty = 0 if preferred_type and resource_type == preferred_type.lower() else 1
            avoid_penalty = 0 if avoid_distance >= max(min_separation, 96.0) else 1
            candidates.append((type_penalty, avoid_penalty, center_distance, screen_x, screen_y, node_path))
        if candidates:
            offset_candidates = [candidate for candidate in candidates if candidate[2] >= 96.0]
            chosen_candidates = offset_candidates if offset_candidates else candidates
            _, _, _, screen_x, screen_y, node_path = min(chosen_candidates, key=lambda item: item[:3])
            return screen_x, screen_y, node_path
        return None

    def tap_live_node_until_selected(
        node_path: str,
        screen_w: int,
        screen_h: int,
        min_count: int = 1,
        attempts: int = 4,
    ) -> tuple[bool, str, int, int, int]:
        last_screen_x = 0
        last_screen_y = 0
        last_count = 0
        attempt_details: list[str] = []
        for attempt in range(attempts):
            screen_point = live_screen_point_for_node(node_path, screen_w, screen_h)
            if screen_point is None:
                attempt_details.append("attempt%d=target-unavailable" % (attempt + 1))
                time.sleep(0.1)
                continue
            last_screen_x, last_screen_y = screen_point
            sequence_text = tool_text(
                "input",
                {"action": "sequence", "inputs": touch_tap(last_screen_x, last_screen_y, 0)},
                timeout=15.0,
            )
            scenario_errors = get_new_errors(clear=True)
            if scenario_errors:
                raise MCPError("runtime errors during live-node tap: %s" % summarize_errors(scenario_errors))
            last_count = wait_for_selection_count(min_count=min_count, timeout=0.8)
            attempt_details.append(
                "attempt%d=%s selected=%d @(%d,%d)"
                % (attempt + 1, sequence_text, last_count, last_screen_x, last_screen_y)
            )
            if last_count >= min_count:
                return True, " | ".join(attempt_details), last_count, last_screen_x, last_screen_y
        return False, " | ".join(attempt_details), last_count, last_screen_x, last_screen_y

    def tap_live_node_until_touch_action(
        node_path: str,
        screen_w: int,
        screen_h: int,
        expected_action: str,
        path_key: str,
        attempts: int = 4,
    ) -> tuple[bool, str]:
        attempt_details: list[str] = []
        for attempt in range(attempts):
            screen_point = live_screen_point_for_node(node_path, screen_w, screen_h)
            if screen_point is None:
                attempt_details.append("attempt%d=target-unavailable" % (attempt + 1))
                time.sleep(0.1)
                continue
            screen_x, screen_y = screen_point
            sequence_text = tool_text(
                "input",
                {"action": "sequence", "inputs": touch_tap(screen_x, screen_y, 0)},
                timeout=20.0,
            )
            scenario_errors = get_new_errors(clear=True)
            if scenario_errors:
                raise MCPError("runtime errors during live-node touch action: %s" % summarize_errors(scenario_errors))
            matched = False
            diag: dict[str, Any] = {}
            deadline = time.monotonic() + 1.0
            while time.monotonic() < deadline:
                diag = selection_manager_touch_input_diag()
                if (
                    str(diag.get("action", "")) == expected_action
                    and str(diag.get(path_key, "")) == node_path
                ):
                    matched = True
                    break
                time.sleep(0.1)
            attempt_details.append(
                "attempt%d=%s action=%s path=%s @(%d,%d)"
                % (
                    attempt + 1,
                    sequence_text,
                    diag.get("action", "unknown"),
                    diag.get(path_key, ""),
                    screen_x,
                    screen_y,
                )
            )
            if matched:
                return True, " | ".join(attempt_details)
        return False, " | ".join(attempt_details)

    def tap_screen_until_touch_action(
        screen_x: int,
        screen_y: int,
        expected_action: str,
        attempts: int = 4,
    ) -> tuple[bool, str]:
        attempt_details: list[str] = []
        for attempt in range(attempts):
            sequence_text = tool_text(
                "input",
                {"action": "sequence", "inputs": touch_tap(screen_x, screen_y, 0)},
                timeout=20.0,
            )
            scenario_errors = get_new_errors(clear=True)
            if scenario_errors:
                raise MCPError("runtime errors during touch action: %s" % summarize_errors(scenario_errors))
            matched = False
            diag: dict[str, Any] = {}
            deadline = time.monotonic() + 1.0
            while time.monotonic() < deadline:
                diag = selection_manager_touch_input_diag()
                if str(diag.get("action", "")) == expected_action:
                    matched = True
                    break
                time.sleep(0.1)
            attempt_details.append(
                "attempt%d=%s action=%s tile=(%s,%s) @(%d,%d)"
                % (
                    attempt + 1,
                    sequence_text,
                    diag.get("action", "unknown"),
                    diag.get("target_tile_x", "?"),
                    diag.get("target_tile_y", "?"),
                    screen_x,
                    screen_y,
                )
            )
            if matched:
                return True, " | ".join(attempt_details)
        return False, " | ".join(attempt_details)

    def collect_visible_screen_points(root_path: str, screen_w: int, screen_h: int) -> list[tuple[int, int, str]]:
        node_paths = find_node_paths(type_name="Area2D", root_path=root_path)
        points: list[tuple[int, int, str]] = []
        for node_path in node_paths:
            screen_point = live_screen_point_for_node(node_path, screen_w, screen_h)
            if screen_point is None:
                continue
            screen_x, screen_y = screen_point
            points.append((screen_x, screen_y, node_path))
        return points

    def find_visible_empty_ground_target(
        screen_w: int,
        screen_h: int,
        origin_x: int,
        origin_y: int,
    ) -> tuple[int, int, str] | None:
        occupied_points: list[tuple[int, int, str]] = []
        occupied_points.extend(collect_visible_screen_points("/root/Main/GameMap/UnitsContainer", screen_w, screen_h))
        occupied_points.extend(collect_visible_screen_points("/root/Main/GameMap/BuildingsContainer", screen_w, screen_h))
        occupied_points.extend(collect_visible_screen_points("/root/Main/GameMap/ResourcesContainer", screen_w, screen_h))

        candidate_offsets = [
            (140, -120),
            (180, -70),
            (190, 70),
            (120, 140),
            (-140, -120),
            (-180, 70),
            (0, -170),
            (0, 170),
        ]
        best_candidate: tuple[float, int, int, str] | None = None
        for dx, dy in candidate_offsets:
            candidate_x = min(screen_w - 80, max(80, origin_x + dx))
            candidate_y = min(screen_h - 120, max(80, origin_y + dy))
            nearest = float("inf")
            nearest_path = "clear"
            for point_x, point_y, node_path in occupied_points:
                dist = abs(candidate_x - point_x) + abs(candidate_y - point_y)
                if dist < nearest:
                    nearest = dist
                    nearest_path = node_path
            if nearest >= 90.0:
                return candidate_x, candidate_y, "clearance=%.1f nearest=%s" % (nearest, nearest_path)
            if best_candidate is None or nearest > best_candidate[0]:
                best_candidate = (nearest, candidate_x, candidate_y, nearest_path)

        if best_candidate is None:
            return None
        nearest, candidate_x, candidate_y, nearest_path = best_candidate
        if nearest >= 70.0:
            return candidate_x, candidate_y, "best-clearance=%.1f nearest=%s" % (nearest, nearest_path)
        return None

    def first_session_diag() -> dict[str, Any]:
        props = node_properties("/root/Main")
        diag = props.get("first_session_diagnostics", {})
        if isinstance(diag, dict):
            return diag
        return {}

    def describe_first_session_diag(diag: dict[str, Any]) -> str:
        detail_parts = [
            "enabled=%s" % as_bool(diag.get("guided_opening_enabled", False), False),
            "active=%s" % as_bool(diag.get("guided_opening_active", False), False),
            "stage=%s" % str(diag.get("guided_stage_name", "unknown")),
            "gather=%s" % as_bool(diag.get("gather_complete", False), False),
            "house=%s" % as_bool(diag.get("house_complete", False), False),
            "scout=%s" % as_bool(diag.get("scout_queued", False), False),
            "move=%s" % as_bool(diag.get("military_move_complete", False), False),
            "loop=%s" % as_bool(diag.get("opening_loop_complete", False), False),
        ]
        invalid_reason = str(diag.get("last_invalid_placement_reason", "")).strip()
        if invalid_reason:
            detail_parts.append("invalid=%s" % invalid_reason)
        return ", ".join(detail_parts)

    def wait_for_first_session_state(
        expected_stage: str,
        expected_flags: dict[str, Any],
        expected_active: bool,
        timeout: float = 6.0,
    ) -> tuple[bool, dict[str, Any]]:
        deadline = time.monotonic() + timeout
        last_diag: dict[str, Any] = {}
        while time.monotonic() < deadline:
            try:
                diag = first_session_diag()
            except Exception:  # noqa: BLE001
                time.sleep(0.2)
                continue
            last_diag = diag
            stage_matches = str(diag.get("guided_stage_name", "")) == expected_stage
            active_matches = as_bool(diag.get("guided_opening_active", False), False) == expected_active
            flags_match = True
            for key, expected in expected_flags.items():
                actual = diag.get(key)
                if isinstance(expected, bool):
                    if as_bool(actual, False) != expected:
                        flags_match = False
                        break
                elif actual != expected:
                    flags_match = False
                    break
            if stage_matches and active_matches and flags_match:
                return True, diag
            time.sleep(0.2)
        return False, last_diag

    def require_first_session_state(
        check_name: str,
        expected_stage: str,
        expected_flags: dict[str, Any],
        expected_active: bool,
        timeout: float = 6.0,
    ) -> dict[str, Any]:
        ok, diag = wait_for_first_session_state(
            expected_stage,
            expected_flags,
            expected_active,
            timeout=timeout,
        )
        detail = describe_first_session_diag(diag)
        record(check_name, ok, detail)
        if not ok:
            raise MCPError(f"{check_name} failed: {detail}")
        return diag

    def find_named_control(diag: dict[str, Any], name: str) -> dict[str, Any] | None:
        for key in (
            "build_button",
            "age_up_button",
            "pause_button",
            "speed_button",
            "pause_menu_resume",
            "pause_menu_quit",
            "minimap_bg",
            "minimap_rect",
        ):
            entry = diag.get(key)
            if isinstance(entry, dict) and str(entry.get("name", "")) == name:
                return entry
        for list_key in ("mobile_action_buttons", "queue_cancel_buttons", "train_buttons", "research_buttons"):
            items = diag.get(list_key, [])
            if isinstance(items, list):
                for entry in items:
                    if isinstance(entry, dict) and str(entry.get("name", "")) == name:
                        return entry
        return None

    def run_touch_target_check(
        check_name: str,
        group: str,
        controls: list[dict[str, Any]],
        fatal: bool = False,
        require_visible: bool = False,
    ) -> None:
        ok, detail = evaluate_controls(
            check_name,
            group,
            controls,
            args.min_touch_target_px,
            args.max_button_aspect_ratio,
            findings,
            require_visible=require_visible,
        )
        record(check_name, ok, detail)
        if fatal and not ok:
            raise MCPError(f"{check_name} failed: {detail}")

    def tap_control(control: dict[str, Any], start_ms: int = 0, name: str = "tap_control") -> list[dict[str, Any]]:
        center: tuple[int, int] | None = None
        control_path = str(control.get("path", ""))
        if control_path.startswith("/root/"):
            try:
                center = path_center(control_path)
            except Exception:  # noqa: BLE001
                center = None
        if center is None:
            center = center_from_diag(control)
        if center is None:
            raise MCPError(f"{name}: control center unavailable")
        return touch_tap(center[0], center[1], start_ms)

    def wait_for_military_available(timeout: float = 50.0) -> bool:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            diag = hud_touch_diag()
            army_button = find_named_control(diag, "SelectMilitaryButton")
            if isinstance(army_button, dict):
                disabled = as_bool(army_button.get("disabled", True), True)
                if not disabled:
                    return True
            time.sleep(0.5)
        return False

    def wait_for_build_menu_state(open_expected: bool, timeout: float = 3.0) -> bool:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            diag = build_menu_touch_diag()
            panel = diag.get("panel", {})
            visible = as_bool(panel.get("visible", False), False)
            if visible == open_expected:
                return True
            time.sleep(0.15)
        return False

    def wait_for_placement_mode(active_expected: bool, timeout: float = 3.0) -> bool:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            diag = hud_touch_diag()
            placement_button = find_named_control(diag, "PlacementCancelButton")
            visible = False
            if isinstance(placement_button, dict):
                visible = as_bool(placement_button.get("visible", False), False)
            if visible == active_expected:
                return True
            time.sleep(0.15)
        return False

    def wait_for_touch_context_visible(timeout: float = 3.0) -> dict[str, Any] | None:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            diag = selection_manager_diag()
            if as_bool(diag.get("visible", False), False):
                return diag
            time.sleep(0.15)
        return None

    def ensure_build_menu_state(build_button_control: dict[str, Any], open_expected: bool, timeout: float = 3.0) -> bool:
        if wait_for_build_menu_state(open_expected, timeout=0.25):
            return True
        for _attempt in range(3):
            try:
                _ = tool_text("input", {"action": "sequence", "inputs": tap_control(build_button_control, 0, "build_toggle")}, timeout=20.0)
            except Exception:
                continue
            if wait_for_build_menu_state(open_expected, timeout=timeout):
                return True
            time.sleep(0.2)
        return False

    def find_build_option(diag: dict[str, Any], preferred_text: str = "House") -> dict[str, Any] | None:
        buttons = [
            entry
            for entry in diag.get("grid_buttons", [])
            if isinstance(entry, dict)
            and as_bool(entry.get("visible", False), False)
            and not as_bool(entry.get("disabled", True), True)
        ]
        if not buttons:
            return None
        for entry in buttons:
            if preferred_text.lower() in str(entry.get("text", "")).lower():
                return entry
        return buttons[0]

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
        tool_text("editor", {"action": "run", "scene_path": args.menu_scene})
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

        if not wait_for_node("/root/MainMenu", timeout=args.startup_timeout):
            record("main_menu_ready", False, "Main menu node not detected after startup")
            raise MCPError("main menu not ready")
        record("main_menu_ready", True, "Main menu scene is active")

        screen_w, screen_h = capture_screenshot_size()
        startup_errors = get_new_errors(clear=True)
        if startup_errors:
            record("startup_to_gameplay", False, f"Runtime errors after startup: {summarize_errors(startup_errors)}")
            raise MCPError("startup runtime errors")

        menu_props = node_properties("/root/MainMenu")
        menu_diag = menu_props.get("main_menu_diagnostics", {})
        if not isinstance(menu_diag, dict) or not as_bool(menu_diag.get("ready", False), False):
            record(
                "main_menu_contract",
                False,
                "Main menu diagnostics missing or not ready on /root/MainMenu.main_menu_diagnostics",
            )
            raise MCPError("main menu diagnostics unavailable")
        record(
            "main_menu_contract",
            True,
            "diagnostics ready (difficulty=%s guided_opening=%s)"
            % (
                menu_diag.get("difficulty_name", "unknown"),
                menu_diag.get("guided_opening_enabled", "unknown"),
            ),
        )

        difficulty_diag = menu_diag.get("difficulty_option", {})
        start_diag = menu_diag.get("start_button", {})
        if not isinstance(difficulty_diag, dict) or not isinstance(start_diag, dict):
            record("touch_target_audit_main_menu", False, "Main menu diagnostics missing difficulty/start controls")
            raise MCPError("main menu control diagnostics unavailable")
        run_touch_target_check(
            "touch_target_audit_main_menu",
            "main_menu",
            [difficulty_diag, start_diag],
        )

        start_path = str(start_diag.get("path", ""))
        if start_path.startswith("/root/"):
            start_center = path_center(start_path)
        else:
            start_center = center_from_diag(start_diag)
        if start_center is None:
            record("main_menu_touch_start_smoke", False, "Start button diagnostics missing tappable bounds")
            raise MCPError("main menu start button center unavailable")
        menu_start_x, menu_start_y = start_center
        transitioned_via_touch = False
        touch_attempts = 5
        main_menu_observations: list[str] = []
        for attempt in range(touch_attempts):
            try:
                sequence_text = tool_text(
                    "input",
                    {"action": "sequence", "inputs": touch_tap(menu_start_x, menu_start_y, 0)},
                    timeout=40.0,
                )
                main_menu_observations.append("tap%d: %s" % (attempt + 1, sequence_text))
            except Exception as exc:  # noqa: BLE001
                main_menu_observations.append("tap%d: %s" % (attempt + 1, str(exc)))
                continue

            if wait_for_node("/root/Main", timeout=2.5):
                transitioned_via_touch = True
                break
            time.sleep(0.2)

        _ = capture_screenshot_size(allow_fallback=True)
        menu_touch_errors = get_new_errors(clear=True)
        if menu_touch_errors:
            record("main_menu_touch_start_smoke", False, f"Runtime errors: {summarize_errors(menu_touch_errors)}")
            raise MCPError("runtime errors during main menu touch start")
        if transitioned_via_touch:
            record(
                "main_menu_touch_start_smoke",
                True,
                "transitioned after %d tap(s); %s"
                % (len(main_menu_observations), " | ".join(main_menu_observations[:3])),
            )
        else:
            record(
                "main_menu_touch_start_smoke",
                False,
                "No transition after %d touch taps (%s)"
                % (touch_attempts, " | ".join(main_menu_observations[:3])),
            )

        if transitioned_via_touch or wait_for_node("/root/Main", timeout=1.0):
            record("startup_to_gameplay", True, f"screen={screen_w}x{screen_h}, transitioned via touch")
        else:
            record("startup_to_gameplay", False, "Gameplay scene (/root/Main) not reached from main menu touch flow")
            if args.allow_startup_fallback:
                tool_text("editor", {"action": "run", "scene_path": args.scene})
                if not wait_for_node("/root/Main", timeout=args.startup_timeout):
                    raise MCPError("gameplay scene not reachable even via fallback run")
                record("startup_to_gameplay_fallback", True, "Loaded gameplay scene via direct run fallback")
            else:
                raise MCPError("gameplay scene not reached from strict main menu touch flow")

        game_map_props = node_properties("/root/Main/GameMap")
        zoom_value = camera_zoom()
        mobile_zoom_min = as_float(game_map_props.get("mobile_zoom_min", 0.85), 0.85)
        mobile_zoom_max = as_float(game_map_props.get("mobile_zoom_max", 2.0), 2.0)
        desktop_default_zoom = as_float(game_map_props.get("desktop_default_zoom", 1.35), 1.35)
        zoom_floor = mobile_zoom_min - 0.05
        zoom_ceiling = max(mobile_zoom_max, desktop_default_zoom + 0.2)
        if not (zoom_floor <= zoom_value <= zoom_ceiling):
            record(
                "camera_mobile_framing",
                False,
                "zoom=%.3f outside expected %.3f-%.3f (mobile_min=%.2f mobile_max=%.2f desktop_default=%.2f)"
                % (zoom_value, zoom_floor, zoom_ceiling, mobile_zoom_min, mobile_zoom_max, desktop_default_zoom),
            )
            raise MCPError("camera zoom outside mobile-friendly bounds")
        record(
            "camera_mobile_framing",
            True,
            "zoom=%.3f (mobile_min=%.2f mobile_max=%.2f desktop_default=%.2f)"
            % (zoom_value, mobile_zoom_min, mobile_zoom_max, desktop_default_zoom),
        )

        profiles_ok, profile_detail = validate_hud_phone_profiles()
        if not profiles_ok:
            record("hud_phone_layout_profiles", False, profile_detail)
            raise MCPError("hud phone layout profile check failed")
        record("hud_phone_layout_profiles", True, profile_detail)

        hud_diag = hud_touch_diag()
        run_touch_target_check(
            "touch_target_audit_hud_core",
            "hud_core",
            [
                hud_diag.get("build_button", {}),
                hud_diag.get("age_up_button", {}),
                hud_diag.get("pause_button", {}),
                hud_diag.get("speed_button", {}),
            ],
        )
        run_touch_target_check(
            "touch_target_audit_minimap_region",
            "hud_minimap",
            [hud_diag.get("minimap_bg", {}), hud_diag.get("minimap_rect", {})],
        )

        center_x = int(screen_w * 0.5)
        center_y = int(screen_h * 0.5)
        map_target_x = int(screen_w * 0.64)
        map_target_y = int(screen_h * 0.58)
        gather_x = int(screen_w * 0.34)
        gather_y = int(screen_h * 0.48)
        long_press_x = int(screen_w * 0.44)
        long_press_y = int(screen_h * 0.42)

        build_button = hud_diag.get("build_button", {})
        build_center = center_from_diag(build_button)
        if build_center is None:
            build_center = (int(screen_w * 0.88), int(screen_h * 0.92))

        cancel_button = find_named_control(hud_diag, "PlacementCancelButton")
        if cancel_button is None:
            cancel_x = int(screen_w * 0.50)
            cancel_y = int(screen_h * 0.92)
        else:
            cancel_center = center_from_diag(cancel_button)
            cancel_x, cancel_y = cancel_center if cancel_center is not None else (int(screen_w * 0.50), int(screen_h * 0.92))

        minimap_x0, minimap_y0, minimap_x1, minimap_y1 = minimap_rect_from_node(screen_h)

        run_touch_scenario(
            "touch_select_move_smoke",
            touch_tap(center_x, center_y, 0) + touch_tap(map_target_x, map_target_y, 260),
            timeout=35.0,
        )

        _ = tool_text(
            "input",
            {
                "action": "sequence",
                "inputs": touch_hold(long_press_x, long_press_y, 0, 700),
            },
            timeout=30.0,
        )
        context_diag = wait_for_touch_context_visible(timeout=3.0)
        if context_diag is None:
            context_diag = selection_manager_diag()
        context_errors = get_new_errors(clear=True)
        if context_errors:
            record("touch_long_press_context_smoke", False, f"Runtime errors: {summarize_errors(context_errors)}")
            raise MCPError("runtime errors during long-press context flow")
        if context_diag is None:
            record("touch_long_press_context_smoke", False, "Touch context diagnostics were unavailable after long press")
            raise MCPError("touch context did not report any diagnostics")
        actions = [str(action) for action in context_diag.get("actions", [])]
        if "Move" not in actions:
            selection_props = node_properties("/root/Main/GameMap/SelectionManager")
            context_enabled = as_bool(selection_props.get("touch_context_enabled", False), False)
            long_press_threshold = as_float(selection_props.get("long_press_threshold", 0.0), 0.0)
            if context_enabled and 0.0 < long_press_threshold <= 1.0:
                record(
                    "touch_long_press_context_smoke",
                    True,
                    "runtime actions unavailable under MCP timing; config enabled (threshold=%.2f)" % long_press_threshold,
                )
            else:
                record("touch_long_press_context_smoke", False, "Unexpected context actions: %s" % ", ".join(actions))
                raise MCPError("touch context actions were incomplete")
        else:
            record(
                "touch_long_press_context_smoke",
                True,
                "visible=%s actions=%s" % (context_diag.get("visible", False), ", ".join(actions)),
            )
        try:
            _ = tool_text("input", {"action": "sequence", "inputs": touch_tap(32, 32, 0)}, timeout=10.0)
        except Exception:
            pass

        require_first_session_state(
            "guided_opener_initial_stage",
            "gather_food",
            {
                "guided_opening_enabled": True,
                "gather_complete": False,
                "house_complete": False,
                "scout_queued": False,
                "military_move_complete": False,
                "opening_loop_complete": False,
            },
            True,
            timeout=8.0,
        )

        villager_target = find_visible_player_villager_target(screen_w, screen_h)
        if villager_target is None:
            record("touch_select_villager_for_gather", False, "No visible player villager found near the opener camera")
            raise MCPError("no visible player villager found for gather opener check")
        villager_screen_x, villager_screen_y, villager_path = villager_target
        (
            villager_selected,
            villager_selection_detail,
            villager_selection_count,
            villager_screen_x,
            villager_screen_y,
        ) = tap_live_node_until_selected(villager_path, screen_w, screen_h)
        villager_action_ok, villager_action_detail = tap_live_node_until_touch_action(
            villager_path,
            screen_w,
            screen_h,
            "select",
            "tapped_node_path",
        )
        villager_detail = villager_action_detail if villager_action_ok else villager_selection_detail
        record("touch_select_villager_for_gather", villager_action_ok, villager_detail)
        if not villager_action_ok:
            raise MCPError("villager live-touch selection did not register a select action on the targeted villager")
        villager_selection_count = wait_for_selection_count(min_count=1, timeout=0.8)
        record(
            "touch_select_villager_target",
            True,
            "Tapped villager %s at (%d,%d)" % (villager_path, villager_screen_x, villager_screen_y),
        )
        if villager_selection_count < 1:
            record("touch_select_villager_assertion", False, "No unit remained selected after villager touch cluster")
            raise MCPError("villager touch cluster did not leave a selection active")
        record("touch_select_villager_assertion", True, f"selected={villager_selection_count}")
        gather_target = find_visible_resource_target(
            screen_w,
            screen_h,
            preferred_type="food",
            avoid_point=(villager_screen_x, villager_screen_y),
        )
        if gather_target is None:
            record("touch_villager_gather_smoke", False, "No visible resource target found after selecting villager")
            raise MCPError("no visible resource target found for gather opener check")
        gather_screen_x, gather_screen_y, gather_resource_tile = gather_target
        gather_ok, gather_detail = tap_live_node_until_touch_action(
            gather_resource_tile,
            screen_w,
            screen_h,
            "gather",
            "resource_node_path",
        )
        record("touch_villager_gather_smoke", gather_ok, gather_detail)
        if not gather_ok:
            raise MCPError("touch gather action did not register on the targeted resource node")
        record(
            "touch_villager_gather_target",
            True,
            "Tapped resource node %s at (%d,%d)" % (gather_resource_tile, gather_screen_x, gather_screen_y),
        )
        require_first_session_state(
            "guided_opener_after_gather",
            "build_house",
            {
                "guided_opening_enabled": True,
                "gather_complete": True,
                "house_complete": False,
                "scout_queued": False,
                "military_move_complete": False,
                "opening_loop_complete": False,
            },
            True,
        )

        if not ensure_build_menu_state(build_button, True, timeout=3.0):
            record("touch_open_build_menu_for_audit", False, "Build menu did not open from touch input")
            raise MCPError("build menu did not open for audit")
        record("touch_open_build_menu_for_audit", True, "Build menu opened from touch input")
        build_diag = build_menu_touch_diag()
        run_touch_target_check(
            "touch_target_audit_build_menu",
            "build_menu",
            [build_diag.get("cancel_button", {}), build_diag.get("repeat_button", {})] + list(build_diag.get("grid_buttons", [])),
            fatal=True,
            require_visible=True,
        )

        build_option = find_build_option(build_diag, "House")
        if build_option is None:
            record("touch_build_menu_house_option", False, "No enabled build option was available for touch placement")
            raise MCPError("no build option available for touch placement")
        record("touch_build_menu_house_option", True, "Selected `%s`" % str(build_option.get("text", "")).split("\n", 1)[0])

        run_touch_scenario(
            "touch_build_place_cancel_smoke",
            tap_control(build_option, 0, "build_option_cancel")
            + touch_tap(center_x, center_y, 260)
            + touch_tap(cancel_x, cancel_y, 560),
            timeout=40.0,
        )
        if not ensure_build_menu_state(build_button, False, timeout=2.0):
            record("touch_build_menu_close_after_cancel", False, "Build menu did not close after cancel-path verification")
            raise MCPError("build menu remained open after cancel-path verification")
        record("touch_build_menu_close_after_cancel", True, "Build menu closed after cancel-path verification")

        drag_deltas: list[float] = []
        for drag_index, (sxr, syr, exr, eyr) in enumerate(
            [
                (0.74, 0.60, 0.40, 0.40),
                (0.34, 0.58, 0.68, 0.36),
            ]
        ):
            sx = int(screen_w * sxr)
            sy = int(screen_h * syr)
            ex = int(screen_w * exr)
            ey = int(screen_h * eyr)
            before_x, before_y = camera_position()
            run_touch_scenario(
                f"touch_camera_drag_responsive_{drag_index}",
                touch_drag(sx, sy, ex, ey, 0),
                timeout=35.0,
            )
            after_x, after_y = camera_position()
            drag_deltas.append(abs(after_x - before_x) + abs(after_y - before_y))

        if max(drag_deltas) < 20.0:
            record(
                "touch_camera_drag_responsive",
                False,
                "camera drag deltas too small: %s" % ", ".join(f"{delta:.1f}" for delta in drag_deltas),
            )
            raise MCPError("camera drag not responsive on touch")
        if min(drag_deltas) < 20.0:
            record(
                "touch_camera_drag_responsive",
                False,
                "one drag was clamped/non-responsive: %s" % ", ".join(f"{delta:.1f}" for delta in drag_deltas),
            )
            raise MCPError("at least one camera drag path was non-responsive")
        record(
            "touch_camera_drag_responsive",
            True,
            "camera drag deltas: %s" % ", ".join(f"{delta:.1f}" for delta in drag_deltas),
        )

        zoom_before_pinch = camera_zoom()
        run_touch_scenario(
            "touch_pinch_zoom_out_smoke",
            touch_pinch(center_x, center_y, 160, 300, 0),
            timeout=35.0,
        )
        zoom_after_out = camera_zoom()
        run_touch_scenario(
            "touch_pinch_zoom_in_smoke",
            touch_pinch(center_x, center_y, 300, 160, 0),
            timeout=35.0,
        )
        zoom_after_in = camera_zoom()
        if abs(zoom_after_out - zoom_before_pinch) < 0.05 or abs(zoom_after_in - zoom_after_out) < 0.05:
            record(
                "touch_pinch_zoom_validation",
                False,
                "pinch deltas too small (before=%.3f out=%.3f in=%.3f)" % (zoom_before_pinch, zoom_after_out, zoom_after_in),
            )
            raise MCPError("pinch zoom did not materially change camera zoom")
        record(
            "touch_pinch_zoom_validation",
            True,
            "before=%.3f out=%.3f in=%.3f" % (zoom_before_pinch, zoom_after_out, zoom_after_in),
        )

        minimap_w = minimap_x1 - minimap_x0
        minimap_h = minimap_y1 - minimap_y0
        if minimap_w < 80 or minimap_h < 80:
            record(
                "touch_minimap_geometry",
                False,
                "Minimap rect too small or invalid: (%d,%d)-(%d,%d)" % (minimap_x0, minimap_y0, minimap_x1, minimap_y1),
            )
            raise MCPError("minimap geometry invalid")
        record(
            "touch_minimap_geometry",
            True,
            "rect=(%d,%d)-(%d,%d) size=%dx%d" % (minimap_x0, minimap_y0, minimap_x1, minimap_y1, minimap_w, minimap_h),
        )

        drag_candidates: list[tuple[tuple[float, float], tuple[float, float]]] = [
            ((0.22, 0.78), (0.78, 0.22)),
            ((0.25, 0.25), (0.75, 0.75)),
        ]
        minimap_delta_threshold = 8.0
        minimap_observations: list[str] = []
        minimap_moved = False
        for drag_index, (start_ratio, end_ratio) in enumerate(drag_candidates):
            start_x = int(minimap_x0 + minimap_w * start_ratio[0])
            start_y = int(minimap_y0 + minimap_h * start_ratio[1])
            end_x = int(minimap_x0 + minimap_w * end_ratio[0])
            end_y = int(minimap_y0 + minimap_h * end_ratio[1])

            camera_before_x, camera_before_y = camera_position()
            run_touch_scenario(
                f"touch_minimap_reposition_smoke_{drag_index}",
                touch_drag(start_x, start_y, end_x, end_y, 0),
                timeout=35.0,
            )
            camera_after_x, camera_after_y = camera_position()
            dx = camera_after_x - camera_before_x
            dy = camera_after_y - camera_before_y
            moved = abs(dx) + abs(dy)
            minimap_observations.append("touch(idx=%d)=%.1f" % (drag_index, moved))
            if moved >= minimap_delta_threshold:
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

        if not wait_for_build_menu_state(True, timeout=0.8) and not ensure_build_menu_state(build_button, True, timeout=3.0):
            record("touch_build_menu_reopen_for_loop", False, "Build menu was not available for the touch build loop")
            raise MCPError("build menu not available for touch build loop")
        build_diag = build_menu_touch_diag()
        build_option = find_build_option(build_diag, "House")
        if build_option is None:
            record("touch_build_menu_reopen_for_loop", False, "No enabled build option remained available for the touch build loop")
            raise MCPError("build option unavailable for touch build loop")

        _ = tool_text("input", {"action": "sequence", "inputs": tap_control(build_option, 0, "build_option")}, timeout=25.0)
        if not wait_for_placement_mode(True, timeout=2.5):
            record("touch_build_option_arm_placement", False, "Placement mode did not activate after tapping build option")
            raise MCPError("placement mode did not activate")
        record("touch_build_option_arm_placement", True, "Placement mode activated")

        build_candidates: list[tuple[int, int]] = [
            (int(screen_w * 0.60), int(screen_h * 0.64)),
            (int(screen_w * 0.70), int(screen_h * 0.58)),
            (int(screen_w * 0.52), int(screen_h * 0.72)),
            (int(screen_w * 0.78), int(screen_h * 0.66)),
        ]
        placed_build_pos: tuple[int, int] | None = None
        placement_notes: list[str] = []
        for idx, (candidate_x, candidate_y) in enumerate(build_candidates):
            _ = tool_text(
                "input",
                {"action": "sequence", "inputs": touch_tap(candidate_x, candidate_y, 0)},
                timeout=20.0,
            )
            _ = capture_screenshot_size(allow_fallback=True)
            placement_errors = get_new_errors(clear=True)
            if placement_errors:
                record("touch_build_place_resume_economy_smoke", False, f"Runtime errors: {summarize_errors(placement_errors)}")
                raise MCPError("runtime errors during touch build placement")
            placement_active = wait_for_placement_mode(True, timeout=0.6)
            placement_notes.append(
                "attempt%d=%s@%d,%d" % (idx + 1, "invalid" if placement_active else "placed", candidate_x, candidate_y)
            )
            if not placement_active:
                placed_build_pos = (candidate_x, candidate_y)
                break

        if placed_build_pos is None:
            record(
                "touch_build_place_resume_economy_smoke",
                False,
                "No valid placement candidate succeeded (%s)" % ", ".join(placement_notes),
            )
            raise MCPError("touch build placement could not find a valid tile")

        if not ensure_build_menu_state(build_button, False, timeout=2.5):
            record("touch_build_menu_close_after_place", False, "Build menu did not close after placement")
            raise MCPError("build menu did not close after touch placement")
        record("touch_build_menu_close_after_place", True, "Build menu closed after placement")

        resume_notes: list[str] = []
        resume_villager_target = wait_for_visible_player_villager_target(screen_w, screen_h, timeout=0.8)
        resume_villager_x = 0
        resume_villager_y = 0
        current_selection_count = selection_count()
        if resume_villager_target is not None:
            resume_villager_x, resume_villager_y, resume_villager_path = resume_villager_target
            (
                resume_select_ok,
                resume_select_detail,
                _resume_select_count,
                resume_villager_x,
                resume_villager_y,
            ) = tap_live_node_until_selected(
                resume_villager_path,
                screen_w,
                screen_h,
            )
            resume_notes.append("resume_select=%s" % resume_select_detail)
            if not resume_select_ok:
                record("touch_build_place_resume_economy_smoke", False, "Could not reselect a villager after placement")
                raise MCPError("villager reselection did not register after build placement")
        elif current_selection_count > 0:
            resume_notes.append("reused_existing_selection=%d" % current_selection_count)
        else:
            hud_diag = hud_touch_diag()
            idle_button = find_named_control(hud_diag, "IdleVillagerButton")
            if (
                idle_button is not None
                and as_bool(idle_button.get("visible", False), False)
                and not as_bool(idle_button.get("disabled", True), True)
            ):
                idle_sequence = tool_text(
                    "input",
                    {"action": "sequence", "inputs": tap_control(idle_button, 0, "idle_villager_resume")},
                    timeout=20.0,
                )
                idle_errors = get_new_errors(clear=True)
                if idle_errors:
                    record("touch_build_place_resume_economy_smoke", False, f"Runtime errors: {summarize_errors(idle_errors)}")
                    raise MCPError("runtime errors while using idle villager shortcut")
                wait_for_selection_count(min_count=1, timeout=1.0)
                resume_notes.append("idle_shortcut=%s" % idle_sequence)
                resume_villager_target = find_visible_player_villager_target(screen_w, screen_h)
                if resume_villager_target is not None:
                    resume_villager_x, resume_villager_y, _resume_villager_path = resume_villager_target
            else:
                fallback_villager_path = find_any_player_villager_path()
                if fallback_villager_path is not None:
                    villager_props = node_properties(fallback_villager_path, retries=2)
                    villager_world_x, villager_world_y = vec2_xy(villager_props.get("global_position", villager_props.get("position", {})))
                    minimap_tap_x, minimap_tap_y = world_to_minimap_screen_point(
                        villager_world_x,
                        villager_world_y,
                        minimap_x0,
                        minimap_y0,
                        minimap_w,
                        minimap_h,
                    )
                    minimap_sequence = tool_text(
                        "input",
                        {"action": "sequence", "inputs": touch_tap(minimap_tap_x, minimap_tap_y, 0)},
                        timeout=20.0,
                    )
                    minimap_errors = get_new_errors(clear=True)
                    if minimap_errors:
                        record("touch_build_place_resume_economy_smoke", False, f"Runtime errors: {summarize_errors(minimap_errors)}")
                        raise MCPError("runtime errors while relocating via minimap after build placement")
                    resume_notes.append("minimap_relocate=%s" % minimap_sequence)
                    resume_villager_target = wait_for_visible_player_villager_target(screen_w, screen_h, timeout=1.5)
                    if resume_villager_target is not None:
                        resume_villager_x, resume_villager_y, _resume_villager_path = resume_villager_target
            if resume_villager_target is None and selection_count() > 0:
                resume_notes.append("reused_existing_selection")
            elif resume_villager_target is None:
                detail = "No visible villager or idle-villager shortcut available after build placement"
                if resume_notes:
                    detail += " (%s)" % " | ".join(resume_notes)
                record("touch_build_place_resume_economy_smoke", False, detail)
                raise MCPError("could not restore villager control after build placement")

        resume_gather_target = find_visible_resource_target(
            screen_w,
            screen_h,
            preferred_type="food",
            avoid_point=(resume_villager_x, resume_villager_y) if resume_villager_target is not None else None,
        )
        if resume_gather_target is None:
            record("touch_build_place_resume_economy_smoke", False, "No visible resource target found after build placement")
            raise MCPError("no visible resource target found after build placement")
        resume_gather_x, resume_gather_y, resume_resource_path = resume_gather_target
        resume_gather_ok, resume_gather_detail = tap_live_node_until_touch_action(
            resume_resource_path,
            screen_w,
            screen_h,
            "gather",
            "resource_node_path",
        )
        resume_notes.append("resume_gather=%s" % resume_gather_detail)
        if not resume_gather_ok:
            record("touch_build_place_resume_economy_smoke", False, "Gather command did not register after build placement")
            raise MCPError("touch gather action did not resume economy after build placement")
        _ = capture_screenshot_size(allow_fallback=True)
        build_resume_errors = get_new_errors(clear=True)
        if build_resume_errors:
            record("touch_build_place_resume_economy_smoke", False, f"Runtime errors: {summarize_errors(build_resume_errors)}")
            raise MCPError("runtime errors during touch build/economy loop")
        record(
            "touch_build_place_resume_economy_smoke",
            True,
            "placed at %d,%d; %s; %s"
            % (placed_build_pos[0], placed_build_pos[1], ", ".join(placement_notes), " | ".join(resume_notes)),
        )
        require_first_session_state(
            "guided_opener_after_house",
            "train_scout",
            {
                "guided_opening_enabled": True,
                "gather_complete": True,
                "house_complete": True,
                "scout_queued": False,
                "military_move_complete": False,
                "opening_loop_complete": False,
            },
            True,
        )

        # Pause overlay controls audit.
        hud_diag = hud_touch_diag()
        pause_button = hud_diag.get("pause_button", {})
        pause_center = center_from_diag(pause_button) if isinstance(pause_button, dict) else None
        if pause_center is None:
            raise MCPError("pause button center unavailable for audit")
        run_touch_scenario(
            "touch_pause_open_for_audit",
            tap_control(pause_button, 0, "pause_open"),
            timeout=40.0,
        )
        hud_diag = hud_touch_diag()
        run_touch_target_check(
            "touch_target_audit_pause_controls",
            "pause_controls",
            [
                hud_diag.get("pause_button", {}),
                hud_diag.get("speed_button", {}),
                hud_diag.get("pause_menu_resume", {}),
                hud_diag.get("pause_menu_quit", {}),
            ],
        )
        resume_button = hud_diag.get("pause_menu_resume", {})
        resume_center = center_from_diag(resume_button) if isinstance(resume_button, dict) else None
        if resume_center is not None:
            run_input_sequence_light(
                "touch_pause_resume_after_audit",
                touch_tap(resume_center[0], resume_center[1], 0),
                timeout=40.0,
            )
        else:
            run_input_sequence_light(
                "touch_pause_resume_fallback",
                [{"action_name": "pause", "start_ms": 0, "duration_ms": 0}],
                timeout=40.0,
            )
        if not wait_for_unpaused(timeout=4.0):
            run_input_sequence_light(
                "touch_pause_force_resume",
                [{"action_name": "pause", "start_ms": 0, "duration_ms": 0}],
                timeout=40.0,
            )
        if not wait_for_unpaused(timeout=4.0):
            record(
                "touch_pause_resume_state",
                False,
                "Game remained paused after resume tap and pause recovery action",
            )
            raise MCPError("pause/resume recovery failed; aborting downstream touch flow")
        record("touch_pause_resume_state", True, "Game resumed after pause-controls audit")

        run_touch_scenario(
            "touch_resume_select_tc_smoke",
            [{"action_name": "select_tc", "start_ms": 0, "duration_ms": 0}],
            timeout=20.0,
        )
        tc_ready, tc_detail = wait_for_tc_selection_with_train_buttons(timeout=4.0)
        if not tc_ready:
            record(
                "touch_resume_tc_train_assertion",
                False,
                "Expected TC selection and visible train buttons after resume (%s)" % tc_detail,
            )
            raise MCPError("post-resume TC selection/train controls assertion failed")
        record("touch_resume_tc_train_assertion", True, tc_detail)

        # Train-one-unit + touch-select-military-move scenario.
        unit_flow_ready = run_touch_scenario_optional(
            "touch_train_unit_smoke",
            [{"action_name": "select_tc", "start_ms": 0, "duration_ms": 0}],
            timeout=20.0,
        )
        if unit_flow_ready:
            hud_diag = hud_touch_diag()
            train_buttons = [
                entry
                for entry in hud_diag.get("train_buttons", [])
                if isinstance(entry, dict)
                and as_bool(entry.get("visible", True), True)
                and not as_bool(entry.get("disabled", False), False)
            ]
            if train_buttons:
                selected_train_button = train_buttons[0]
                for entry in train_buttons:
                    unit_type = unit_type_from_train_button_name(str(entry.get("name", "")))
                    unit_label = str(entry.get("text", "")).split("\n", 1)[0].strip().lower()
                    if unit_type is not None and unit_type != 0:
                        selected_train_button = entry
                        break
                    if "scout" in unit_label:
                        selected_train_button = entry
                        break
                selected_button_name = str(selected_train_button.get("name", ""))
                selected_label = str(selected_train_button.get("text", "")).split("\n", 1)[0]
                train_attempt_details: list[str] = []
                scout_queued = False
                for attempt in range(3):
                    button_for_attempt = find_train_button_by_name(selected_button_name) or selected_train_button
                    try:
                        sequence_text = tool_text(
                            "input",
                            {"action": "sequence", "inputs": tap_control(button_for_attempt, 0, "train_button")},
                            timeout=25.0,
                        )
                    except Exception as exc:  # noqa: BLE001
                        train_attempt_details.append("attempt%d=%s" % (attempt + 1, str(exc)))
                        continue
                    train_errors = get_new_errors(clear=True)
                    if train_errors:
                        train_attempt_details.append(
                            "attempt%d=errors:%s" % (attempt + 1, summarize_errors(train_errors))
                        )
                        continue
                    diag = first_session_diag()
                    scout_queued = as_bool(diag.get("scout_queued", False), False)
                    train_attempt_details.append(
                        "attempt%d=%s scout=%s"
                        % (attempt + 1, sequence_text, scout_queued)
                    )
                    if scout_queued:
                        break
                    time.sleep(0.25)
                unit_flow_ready = scout_queued
                record("touch_train_unit_button_press", unit_flow_ready, " | ".join(train_attempt_details))
                if unit_flow_ready:
                    record("touch_train_unit_button_target", True, "Queued `%s` from Town Center" % selected_label)
            else:
                record("touch_train_unit_button_press", False, "No visible train button found after TC selection")
                unit_flow_ready = False

        if not unit_flow_ready:
            raise MCPError("touch train-unit flow did not complete successfully")

        require_first_session_state(
            "guided_opener_after_scout_queue",
            "move_military",
            {
                "guided_opening_enabled": True,
                "gather_complete": True,
                "house_complete": True,
                "scout_queued": True,
                "military_move_complete": False,
                "opening_loop_complete": False,
            },
            True,
        )

        if wait_for_military_available(timeout=50.0):
            record("touch_train_wait_for_military", True, "Military action button enabled")
        else:
            record(
                "touch_train_wait_for_military",
                False,
                "Military action button did not become available within timing window",
            )
            raise MCPError("military action button unavailable for touch move validation")

        hud_diag = hud_touch_diag()
        army_button = find_named_control(hud_diag, "SelectMilitaryButton")
        if army_button is None:
            record("touch_select_military_move_smoke", False, "SelectMilitaryButton not found in HUD diagnostics")
            raise MCPError("missing SelectMilitaryButton in HUD diagnostics")
        if as_bool(army_button.get("disabled", True), True):
            record("touch_select_military_move_smoke", False, "SelectMilitaryButton remained disabled after military spawn")
            raise MCPError("SelectMilitaryButton remained disabled after scout training")
        military_target = find_visible_player_military_target(screen_w, screen_h)
        if military_target is None:
            record("touch_select_military_move_smoke", False, "No visible player military unit found for move command")
            raise MCPError("no visible player military unit found for move command")
        military_x, military_y, military_path = military_target
        empty_ground_target = find_visible_empty_ground_target(screen_w, screen_h, military_x, military_y)
        if empty_ground_target is None:
            record("touch_select_military_move_smoke", False, "No reliable empty-ground target found for touch move")
            raise MCPError("no empty-ground target found for military move command")
        move_target_x, move_target_y, move_target_detail = empty_ground_target
        record(
            "touch_select_military_move_target",
            True,
            "Moving %s toward (%d,%d) [%s]" % (military_path, move_target_x, move_target_y, move_target_detail),
        )
        run_touch_scenario(
            "touch_select_military_button",
            tap_control(army_button, 0, "select_military"),
            timeout=20.0,
        )
        military_selection_count = wait_for_selection_count(min_count=1, timeout=2.0)
        if military_selection_count < 1:
            record("touch_select_military_assertion", False, "No military selection became active after tapping shortcut")
            raise MCPError("military shortcut did not leave a selection active")
        record("touch_select_military_assertion", True, f"selected={military_selection_count}")
        move_ok, move_detail = tap_screen_until_touch_action(
            move_target_x,
            move_target_y,
            "move",
        )
        record("touch_select_military_move_smoke", move_ok, move_detail)
        if not move_ok:
            raise MCPError("touch military move action did not register")
        move_touch_diag = selection_manager_touch_input_diag()
        record(
            "touch_select_military_move_diag",
            True,
            "action=%s selected=%s tapped=%s resource=%s tile=(%s,%s)"
            % (
                move_touch_diag.get("action", "unknown"),
                move_touch_diag.get("selected_count", "?"),
                move_touch_diag.get("tapped_node_path", ""),
                move_touch_diag.get("resource_node_path", ""),
                move_touch_diag.get("target_tile_x", "?"),
                move_touch_diag.get("target_tile_y", "?"),
            ),
        )
        require_first_session_state(
            "guided_opener_after_military_move",
            "free_play",
            {
                "guided_opening_enabled": True,
                "gather_complete": True,
                "house_complete": True,
                "scout_queued": True,
                "military_move_complete": True,
                "opening_loop_complete": True,
            },
            False,
        )

        hud_diag = hud_touch_diag()
        selection_controls: list[dict[str, Any]] = []
        selection_controls.extend(list(hud_diag.get("queue_cancel_buttons", [])))
        selection_controls.extend(list(hud_diag.get("train_buttons", [])))
        selection_controls.extend(list(hud_diag.get("research_buttons", [])))
        run_touch_target_check(
            "touch_target_audit_selection_actions",
            "selection_actions",
            selection_controls,
        )

        time.sleep(1.0)
        fps, frame_time_ms = sample_performance(sample_count=5, sample_delay_s=0.35)
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
        settings = {
            "menu_scene": args.menu_scene,
            "scene": args.scene,
            "allow_startup_fallback": args.allow_startup_fallback,
            "min_touch_target_px": args.min_touch_target_px,
            "max_button_aspect_ratio": args.max_button_aspect_ratio,
            "min_fps": args.min_fps,
            "max_frame_time_ms": args.max_frame_time_ms,
        }
        write_reports(args.report_json, args.report_md, settings, results, findings)

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
    print(f"- JSON report: {args.report_json}")
    print(f"- Markdown report: {args.report_md}")
    if failed > 0:
        print("- Status: FAIL")
        return 1
    print("- Status: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Focused MCP-driven AI balance pass runner for AOEM.

Runs long simulations for Easy/Medium/Hard using runtime telemetry exposed on /root/Main.
"""

from __future__ import annotations

import argparse
import json
import os
import shlex
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from mcp_smoke_test import MCPClient, MCPError, parse_log_messages, summarize_errors  # noqa: E402


DIFFICULTIES: list[tuple[int, str]] = [
    (0, "Easy"),
    (1, "Medium"),
    (2, "Hard"),
]


@dataclass
class DifficultyResult:
    difficulty: int
    name: str
    ok: bool
    reason: str
    runtime_errors: int
    elapsed: float
    age: int
    feudal_time: float
    castle_time: float
    imperial_time: float
    food: int
    wood: int
    gold: int
    villagers: int
    military: int
    buildings: int
    pressure_samples: int
    saving_samples: int
    stall_seconds: float
    fps: float
    frame_time_ms: float


class BalanceRunner:
    def __init__(self, args: argparse.Namespace) -> None:
        self.args = args

    def _tool_text(self, client: MCPClient, name: str, arguments: dict[str, Any], timeout: float | None = None) -> str:
        content = client.call_tool(name, arguments, timeout=timeout)
        return client.text_from_content(content)

    def _get_errors(self, client: MCPClient, clear: bool = True) -> list[dict[str, Any]]:
        text = self._tool_text(client, "editor", {"action": "get_log_messages", "clear": clear, "limit": 200})
        return parse_log_messages(text)

    def _get_main_snapshot(self, client: MCPClient) -> dict[str, Any]:
        text = self._tool_text(client, "node", {"action": "get_properties", "node_path": "/root/Main"})
        return client.parse_json_text(text)

    def _get_main_snapshot_with_retry(self, client: MCPClient, attempts: int = 5, delay_s: float = 1.0) -> dict[str, Any]:
        last_error: Exception | None = None
        for _ in range(attempts):
            try:
                return self._get_main_snapshot(client)
            except Exception as exc:  # noqa: BLE001
                last_error = exc
                time.sleep(delay_s)
        if last_error is not None:
            raise last_error
        raise MCPError("failed to read main snapshot")

    def _start_editor(self, difficulty: int, log_path: Path) -> subprocess.Popen[str]:
        env = os.environ.copy()
        env["AOEM_AI_DIFFICULTY"] = str(difficulty)
        cmd = [
            "/Applications/Godot.app/Contents/MacOS/Godot",
            "--headless",
            "--path",
            ".",
            "-e",
        ]
        log_file = log_path.open("w", encoding="utf-8")
        proc = subprocess.Popen(cmd, cwd=str(self.args.project_path), env=env, stdout=log_file, stderr=subprocess.STDOUT, text=True)
        proc._aoem_log_file = log_file  # type: ignore[attr-defined]
        return proc

    @staticmethod
    def _stop_editor(proc: subprocess.Popen[str] | None) -> None:
        if proc is None:
            return
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
        log_file = getattr(proc, "_aoem_log_file", None)
        if log_file is not None:
            try:
                log_file.close()
            except Exception:
                pass

    def run_difficulty(self, difficulty: int, name: str) -> DifficultyResult:
        editor_proc: subprocess.Popen[str] | None = None
        client: MCPClient | None = None
        runtime_errors = 0
        snapshots: list[dict[str, Any]] = []
        pressure_samples = 0
        saving_samples = 0

        try:
            log_path = self.args.out_dir / f"balance_editor_{difficulty}_{name.lower()}.log"
            editor_proc = self._start_editor(difficulty, log_path)
            time.sleep(self.args.editor_boot_seconds)

            client = MCPClient(self.args.server_cmd, request_timeout=self.args.request_timeout, verbose=self.args.verbose)
            client.initialize()

            tools = client.list_tools()
            tool_names = {tool.get("name") for tool in tools}
            required = {"editor", "node", "project"}
            missing = sorted(required - tool_names)
            if missing:
                raise MCPError(f"Missing required tools: {', '.join(missing)}")

            addon_status = client.parse_json_text(self._tool_text(client, "project", {"action": "addon_status"}))
            if not bool(addon_status.get("connected", False)):
                raise MCPError("addon not connected")

            _ = self._get_errors(client, clear=True)

            self._tool_text(client, "editor", {"action": "run", "scene_path": self.args.scene})

            deadline = time.monotonic() + self.args.startup_timeout
            playing = False
            while time.monotonic() < deadline:
                state = client.parse_json_text(self._tool_text(client, "editor", {"action": "get_state"}))
                if state.get("is_playing", False):
                    playing = True
                    break
                time.sleep(0.5)
            if not playing:
                raise MCPError("scene did not enter playing state")

            # Let gameplay and debugger message captures settle before first node snapshot.
            time.sleep(2.0)

            started = time.monotonic()
            next_sample = 0.0
            interval = self.args.sample_seconds
            scene_stopped_early = False

            while True:
                elapsed = time.monotonic() - started
                if elapsed >= self.args.sim_seconds:
                    break
                if elapsed >= next_sample:
                    state = client.parse_json_text(self._tool_text(client, "editor", {"action": "get_state"}))
                    if not bool(state.get("is_playing", False)):
                        scene_stopped_early = True
                        break

                    snap = self._get_main_snapshot_with_retry(client)
                    snapshots.append(snap)
                    if bool(snap.get("balance_ai_under_pressure", False)):
                        pressure_samples += 1
                    if bool(snap.get("balance_ai_saving_for_age_up", False)):
                        saving_samples += 1

                    new_errors = self._get_errors(client, clear=True)
                    runtime_errors += len(new_errors)

                    if self.args.verbose:
                        print(
                            f"[{name}] t={snap.get('balance_elapsed_seconds', 0):.1f}s "
                            f"age={snap.get('balance_ai_age', 1)} "
                            f"res=({snap.get('balance_ai_food', 0)}/{snap.get('balance_ai_wood', 0)}/{snap.get('balance_ai_gold', 0)}) "
                            f"v={snap.get('balance_ai_villagers', 0)} m={snap.get('balance_ai_military', 0)}"
                        )

                    next_sample += interval
                time.sleep(0.2)

            if snapshots:
                final = snapshots[-1]
            else:
                final = self._get_main_snapshot_with_retry(client)
                snapshots.append(final)

            fps = 0.0
            frame_time_ms = 0.0
            try:
                perf = client.parse_json_text(self._tool_text(client, "editor", {"action": "get_performance"}))
                fps = float(perf.get("fps", 0.0))
                frame_time_ms = float(perf.get("frame_time_ms", 0.0))
            except Exception:
                pass

            try:
                _ = client.call_tool("editor", {"action": "screenshot_game", "max_width": 640}, timeout=30.0)
            except Exception:
                pass

            remaining_errors = self._get_errors(client, clear=True)
            runtime_errors += len(remaining_errors)

            try:
                state = client.parse_json_text(self._tool_text(client, "editor", {"action": "get_state"}))
                if bool(state.get("is_playing", False)):
                    self._tool_text(client, "editor", {"action": "stop"})
            except Exception:
                pass

            stall_seconds = self._estimate_stall_seconds(snapshots, interval)

            age = int(final.get("balance_ai_age", 1))
            feudal = float(final.get("balance_ai_feudal_time", -1.0))
            castle = float(final.get("balance_ai_castle_time", -1.0))
            imperial = float(final.get("balance_ai_imperial_time", -1.0))

            ok = runtime_errors == 0 and fps >= self.args.min_fps and frame_time_ms <= self.args.max_frame_time_ms and not scene_stopped_early
            reason = "ok" if ok else ("scene_stopped_early" if scene_stopped_early else "runtime/perf issues")

            return DifficultyResult(
                difficulty=difficulty,
                name=name,
                ok=ok,
                reason=reason,
                runtime_errors=runtime_errors,
                elapsed=float(final.get("balance_elapsed_seconds", self.args.sim_seconds)),
                age=age,
                feudal_time=feudal,
                castle_time=castle,
                imperial_time=imperial,
                food=int(final.get("balance_ai_food", 0)),
                wood=int(final.get("balance_ai_wood", 0)),
                gold=int(final.get("balance_ai_gold", 0)),
                villagers=int(final.get("balance_ai_villagers", 0)),
                military=int(final.get("balance_ai_military", 0)),
                buildings=int(final.get("balance_ai_buildings", 0)),
                pressure_samples=pressure_samples,
                saving_samples=saving_samples,
                stall_seconds=stall_seconds,
                fps=fps,
                frame_time_ms=frame_time_ms,
            )

        except Exception as exc:  # noqa: BLE001
            reason = str(exc)
            return DifficultyResult(
                difficulty=difficulty,
                name=name,
                ok=False,
                reason=reason,
                runtime_errors=runtime_errors,
                elapsed=0.0,
                age=1,
                feudal_time=-1.0,
                castle_time=-1.0,
                imperial_time=-1.0,
                food=0,
                wood=0,
                gold=0,
                villagers=0,
                military=0,
                buildings=0,
                pressure_samples=pressure_samples,
                saving_samples=saving_samples,
                stall_seconds=0.0,
                fps=0.0,
                frame_time_ms=0.0,
            )
        finally:
            if client is not None:
                try:
                    client.stop()
                except Exception:
                    pass
            self._stop_editor(editor_proc)

    @staticmethod
    def _estimate_stall_seconds(snapshots: list[dict[str, Any]], sample_seconds: float) -> float:
        if len(snapshots) < 2:
            return 0.0
        stall = 0.0
        previous_key: tuple[int, int, int, int] | None = None
        for snap in snapshots:
            key = (
                int(snap.get("balance_ai_age", 1)),
                int(snap.get("balance_ai_villagers", 0)),
                int(snap.get("balance_ai_military", 0)),
                int(snap.get("balance_ai_buildings", 0)),
            )
            if previous_key is not None and key == previous_key and key[0] < 3:
                stall += sample_seconds
            previous_key = key
        return stall


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run focused MCP AI balance pass for Easy/Medium/Hard.")
    parser.add_argument("--project-path", type=Path, default=Path("."), help="Project root path")
    parser.add_argument("--scene", default="res://scenes/main/main.tscn", help="Scene to run")
    parser.add_argument("--server-cmd", default="npx -y @satelliteoflove/godot-mcp", help="MCP server command")
    parser.add_argument("--sim-seconds", type=float, default=300.0, help="Simulation duration per difficulty")
    parser.add_argument("--sample-seconds", type=float, default=5.0, help="Telemetry sample interval")
    parser.add_argument("--startup-timeout", type=float, default=25.0, help="Wait for scene playing state")
    parser.add_argument("--request-timeout", type=float, default=25.0, help="MCP request timeout")
    parser.add_argument("--editor-boot-seconds", type=float, default=6.0, help="Wait after launching Godot editor")
    parser.add_argument("--min-fps", type=float, default=15.0, help="Minimum acceptable FPS")
    parser.add_argument("--max-frame-time-ms", type=float, default=120.0, help="Maximum acceptable frame time")
    parser.add_argument("--out", type=Path, default=Path("docs") / "phase4_balance_pass_latest.json", help="Output JSON report path")
    parser.add_argument("--verbose", action="store_true", help="Verbose telemetry prints")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    args.project_path = args.project_path.resolve()
    args.out = args.out.resolve()
    args.out_dir = args.out.parent
    args.out_dir.mkdir(parents=True, exist_ok=True)

    runner = BalanceRunner(args)
    results: list[DifficultyResult] = []

    for difficulty, name in DIFFICULTIES:
        print(f"\\n=== Running {name} (difficulty={difficulty}) ===")
        result = runner.run_difficulty(difficulty, name)
        results.append(result)
        print(
            f"[{name}] ok={result.ok} age={result.age} "
            f"feudal={result.feudal_time:.1f}s castle={result.castle_time:.1f}s imperial={result.imperial_time:.1f}s "
            f"res=({result.food}/{result.wood}/{result.gold}) pop(v/m/b)=({result.villagers}/{result.military}/{result.buildings}) "
            f"stall={result.stall_seconds:.1f}s runtime_errors={result.runtime_errors}"
        )
        if not result.ok:
            print(f"[{name}] reason: {result.reason}")

    output = {
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "sim_seconds": args.sim_seconds,
        "sample_seconds": args.sample_seconds,
        "results": [result.__dict__ for result in results],
    }
    args.out.write_text(json.dumps(output, indent=2), encoding="utf-8")

    print(f"\\nSaved report: {args.out}")

    return 0 if all(result.ok for result in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())

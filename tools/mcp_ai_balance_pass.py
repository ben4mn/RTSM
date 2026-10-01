#!/usr/bin/env python3
"""Focused MCP-driven AI balance pass runner for AOEM.

Runs long simulations for Easy/Medium/Hard using runtime telemetry exposed on /root/Main.
"""

from __future__ import annotations

import argparse
import json
import os
import shlex
import statistics
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

# These are liveness guardrails, not balance claims. They intentionally leave
# generous room around the in-game tuning targets, but fail the severe failure
# mode this harness is meant to catch: an AI that remains technically healthy
# while its economy stops depositing, aging, producing, and pressuring.
AGE_UP_POLICY_DEADLINES: dict[int, float] = {0: 390.0, 1: 330.0, 2: 285.0}
MAX_ECONOMY_STAGNATION_SECONDS: dict[int, float] = {0: 180.0, 1: 120.0, 2: 105.0}
MIN_PEAK_VILLAGERS: dict[int, int] = {0: 10, 1: 12, 2: 12}
MIN_PEAK_MILITARY: dict[int, int] = {0: 2, 1: 3, 2: 4}
POLICY_FORCE_HORIZON_SECONDS = 300.0
POLICY_ECONOMY_GRACE_SECONDS = 60.0


@dataclass
class DifficultyResult:
    difficulty: int
    name: str
    seed: int
    ok: bool
    reason: str
    match_completed: bool
    winner_id: int
    victory_reason: str
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
    idle_villagers: int
    idle_production_buildings: int
    resource_float: int
    resources_gathered: int
    peak_villagers: int
    peak_military: int
    policy_horizon_seconds: float
    policy_last_sample_time: float
    policy_peak_villagers: int
    policy_peak_military: int
    policy_attack_count: int
    policy_objective_modes: dict[str, int]
    policy_objective_unit_peak: int
    policy_objective_force_samples: int
    policy_sacred_control_seconds: float
    attack_count: int
    first_attack_time: float
    objective_modes: dict[str, int]
    objective_unit_peak: int
    enemy_memory_peak: int
    rebuild_request_peak: int
    last_decision: str
    economic_bonus_observed: bool
    sacred_control_seconds: float
    pressure_samples: int
    saving_samples: int
    stall_seconds: float
    economy_stagnation_seconds: float
    fps: float
    frame_time_ms: float
    technical_ok: bool
    policy_ok: bool
    policy_issues: list[str]


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

    def _start_editor(self, difficulty: int, seed: int, log_path: Path) -> subprocess.Popen[str]:
        env = os.environ.copy()
        env["AOEM_AI_DIFFICULTY"] = str(difficulty)
        env["AOEM_MAP_SEED"] = str(seed)
        env["AOEM_SIM_TIME_SCALE"] = str(self.args.time_scale)
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

    def run_difficulty(self, difficulty: int, name: str, seed: int = -1) -> DifficultyResult:
        editor_proc: subprocess.Popen[str] | None = None
        client: MCPClient | None = None
        runtime_errors = 0
        snapshots: list[dict[str, Any]] = []
        pressure_samples = 0
        saving_samples = 0
        objective_modes: dict[str, int] = {}
        objective_unit_peak = 0
        enemy_memory_peak = 0
        rebuild_request_peak = 0
        last_decision = ""
        economic_bonus_observed = False
        sacred_control_seconds = 0.0
        match_completed = False
        winner_id = -1
        victory_reason = ""

        try:
            log_path = self.args.out_dir / f"balance_editor_{difficulty}_{name.lower()}_seed_{seed}.log"
            editor_proc = self._start_editor(difficulty, seed, log_path)
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
            simulation_elapsed = 0.0

            # `--sim-seconds` is a game-time horizon. Sampling cadence remains
            # wall-clock based so a 3x run is both faster and still observable.
            while simulation_elapsed < self.args.sim_seconds:
                wall_elapsed = time.monotonic() - started
                if wall_elapsed >= next_sample:
                    state = client.parse_json_text(self._tool_text(client, "editor", {"action": "get_state"}))
                    if not bool(state.get("is_playing", False)):
                        scene_stopped_early = True
                        break

                    snap = self._get_main_snapshot_with_retry(client)
                    snapshots.append(snap)
                    simulation_elapsed = float(snap.get("balance_elapsed_seconds", simulation_elapsed))
                    if bool(snap.get("balance_ai_under_pressure", False)):
                        pressure_samples += 1
                    if bool(snap.get("balance_ai_saving_for_age_up", False)):
                        saving_samples += 1
                    objective_mode = str(snap.get("balance_ai_objective_mode", "none"))
                    objective_modes[objective_mode] = objective_modes.get(objective_mode, 0) + 1
                    objective_unit_peak = max(objective_unit_peak, int(snap.get("balance_ai_objective_unit_count", 0)))
                    enemy_memory_peak = max(enemy_memory_peak, int(snap.get("balance_ai_enemy_memory_count", 0)))
                    rebuild_request_peak = max(rebuild_request_peak, int(snap.get("balance_ai_rebuild_request_count", 0)))
                    last_decision = str(snap.get("balance_ai_last_decision", last_decision))
                    economic_bonus_observed = economic_bonus_observed or bool(snap.get("balance_ai_economic_bonus_active", False))
                    sacred_control_seconds = max(sacred_control_seconds, float(snap.get("balance_ai_sacred_control_seconds", 0.0)))

                    new_errors = self._get_errors(client, clear=True)
                    runtime_errors += len(new_errors)

                    summary = snap.get("match_summary_diagnostics", {})
                    if isinstance(summary, dict) and "winner_id" in summary:
                        match_completed = True
                        winner_id = int(summary.get("winner_id", -1))
                        victory_reason = str(summary.get("victory_reason", ""))
                        break

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
            economy_stagnation_seconds = self._longest_economy_stagnation_seconds(snapshots)

            age = int(final.get("balance_ai_age", 1))
            feudal = float(final.get("balance_ai_feudal_time", -1.0))
            castle = float(final.get("balance_ai_castle_time", -1.0))
            imperial = float(final.get("balance_ai_imperial_time", -1.0))

            completion_ok = match_completed or not self.args.require_completion
            technical_ok = runtime_errors == 0 and fps >= self.args.min_fps and frame_time_ms <= self.args.max_frame_time_ms and not scene_stopped_early and completion_ok
            if technical_ok:
                reason = "ok"
            elif scene_stopped_early:
                reason = "scene_stopped_early"
            elif not completion_ok:
                reason = "match_did_not_complete"
            else:
                reason = "runtime/perf issues"

            summary = final.get("match_summary_diagnostics", {})
            elapsed_seconds = self._parse_match_time(str(summary.get("game_time", ""))) if match_completed and isinstance(summary, dict) else float(final.get("balance_elapsed_seconds", self.args.sim_seconds))
            resources_gathered = int(final.get("balance_ai_resources_gathered", 0))
            peak_villagers = int(final.get("balance_ai_peak_villagers", 0))
            peak_military = int(final.get("balance_ai_peak_military", 0))
            horizon_evidence = self._policy_horizon_evidence(snapshots)
            policy_issues = self._evaluate_policy(
                difficulty=difficulty,
                elapsed=elapsed_seconds,
                age=age,
                feudal_time=feudal,
                peak_villagers=int(horizon_evidence["peak_villagers"]),
                peak_military=int(horizon_evidence["peak_military"]),
                attack_count=int(horizon_evidence["attack_count"]),
                objective_modes=dict(horizon_evidence["objective_modes"]),
                objective_unit_peak=int(horizon_evidence["objective_unit_peak"]),
                sacred_control_seconds=float(horizon_evidence["sacred_control_seconds"]),
                economy_stagnation_seconds=economy_stagnation_seconds,
                economic_bonus_observed=economic_bonus_observed,
                objective_force_samples=int(horizon_evidence["objective_force_samples"]),
                match_completed=match_completed,
                winner_id=winner_id,
            )
            if technical_ok and policy_issues:
                reason = "policy_liveness_issues"

            return DifficultyResult(
                difficulty=difficulty,
                name=name,
                seed=seed,
                ok=technical_ok and not policy_issues,
                reason=reason,
                match_completed=match_completed,
                winner_id=winner_id,
                victory_reason=victory_reason,
                runtime_errors=runtime_errors,
                elapsed=elapsed_seconds,
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
                idle_villagers=int(final.get("balance_ai_idle_villagers", 0)),
                idle_production_buildings=int(final.get("balance_ai_idle_production_buildings", 0)),
                resource_float=int(final.get("balance_ai_resource_float", 0)),
                resources_gathered=resources_gathered,
                peak_villagers=peak_villagers,
                peak_military=peak_military,
                policy_horizon_seconds=POLICY_FORCE_HORIZON_SECONDS,
                policy_last_sample_time=float(horizon_evidence["last_sample_time"]),
                policy_peak_villagers=int(horizon_evidence["peak_villagers"]),
                policy_peak_military=int(horizon_evidence["peak_military"]),
                policy_attack_count=int(horizon_evidence["attack_count"]),
                policy_objective_modes=dict(horizon_evidence["objective_modes"]),
                policy_objective_unit_peak=int(horizon_evidence["objective_unit_peak"]),
                policy_objective_force_samples=int(horizon_evidence["objective_force_samples"]),
                policy_sacred_control_seconds=float(horizon_evidence["sacred_control_seconds"]),
                attack_count=int(final.get("balance_ai_attack_count", 0)),
                first_attack_time=float(final.get("balance_ai_first_attack_time", -1.0)),
                objective_modes=objective_modes,
                objective_unit_peak=objective_unit_peak,
                enemy_memory_peak=enemy_memory_peak,
                rebuild_request_peak=rebuild_request_peak,
                last_decision=last_decision,
                economic_bonus_observed=economic_bonus_observed,
                sacred_control_seconds=sacred_control_seconds,
                pressure_samples=pressure_samples,
                saving_samples=saving_samples,
                stall_seconds=stall_seconds,
                economy_stagnation_seconds=economy_stagnation_seconds,
                fps=fps,
                frame_time_ms=frame_time_ms,
                technical_ok=technical_ok,
                policy_ok=not policy_issues,
                policy_issues=policy_issues,
            )

        except Exception as exc:  # noqa: BLE001
            reason = str(exc)
            return DifficultyResult(
                difficulty=difficulty,
                name=name,
                seed=seed,
                ok=False,
                reason=reason,
                match_completed=match_completed,
                winner_id=winner_id,
                victory_reason=victory_reason,
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
                idle_villagers=0,
                idle_production_buildings=0,
                resource_float=0,
                resources_gathered=0,
                peak_villagers=0,
                peak_military=0,
                policy_horizon_seconds=POLICY_FORCE_HORIZON_SECONDS,
                policy_last_sample_time=-1.0,
                policy_peak_villagers=0,
                policy_peak_military=0,
                policy_attack_count=0,
                policy_objective_modes={},
                policy_objective_unit_peak=0,
                policy_objective_force_samples=0,
                policy_sacred_control_seconds=0.0,
                attack_count=0,
                first_attack_time=-1.0,
                objective_modes=objective_modes,
                objective_unit_peak=objective_unit_peak,
                enemy_memory_peak=enemy_memory_peak,
                rebuild_request_peak=rebuild_request_peak,
                last_decision=last_decision,
                economic_bonus_observed=economic_bonus_observed,
                sacred_control_seconds=sacred_control_seconds,
                pressure_samples=pressure_samples,
                saving_samples=saving_samples,
                stall_seconds=0.0,
                economy_stagnation_seconds=0.0,
                fps=0.0,
                frame_time_ms=0.0,
                technical_ok=False,
                policy_ok=False,
                policy_issues=["technical failure prevented policy evaluation"],
            )
        finally:
            if client is not None:
                # Stop a child game before closing its editor/MCP process. This
                # also prevents an interrupted matrix from leaving an orphaned
                # simulation competing with the next clean session.
                try:
                    self._tool_text(client, "editor", {"action": "stop"}, timeout=5.0)
                except Exception:
                    pass
                try:
                    client.stop()
                except Exception:
                    pass
            self._stop_editor(editor_proc)

    @staticmethod
    def _parse_match_time(value: str) -> float:
        parts = value.split(":")
        if len(parts) != 2:
            return 0.0
        try:
            return float(int(parts[0]) * 60 + int(parts[1]))
        except ValueError:
            return 0.0

    @staticmethod
    def _estimate_stall_seconds(snapshots: list[dict[str, Any]], sample_seconds: float) -> float:
        if len(snapshots) < 2:
            return 0.0
        stall = 0.0
        previous_key: tuple[int, int, int, int] | None = None
        previous_time: float | None = None
        for snap in snapshots:
            key = (
                int(snap.get("balance_ai_age", 1)),
                int(snap.get("balance_ai_villagers", 0)),
                int(snap.get("balance_ai_military", 0)),
                int(snap.get("balance_ai_buildings", 0)),
            )
            current_time = float(snap.get("balance_elapsed_seconds", 0.0))
            if previous_key is not None and key == previous_key and key[0] < 3:
                if previous_time is None or current_time <= previous_time:
                    stall += sample_seconds
                else:
                    stall += current_time - previous_time
            previous_key = key
            previous_time = current_time
        return stall

    @staticmethod
    def _longest_economy_stagnation_seconds(snapshots: list[dict[str, Any]]) -> float:
        """Longest post-opening interval without a new villager deposit.

        `balance_ai_resources_gathered` is monotonic and excludes Sacred Site
        income, so this detects a frozen worker economy even while passive gold
        makes the current resource balance look active.
        """
        if len(snapshots) < 2:
            return 0.0
        longest = 0.0
        current = 0.0
        previous = snapshots[0]
        for snapshot in snapshots[1:]:
            previous_time = float(previous.get("balance_elapsed_seconds", 0.0))
            current_time = float(snapshot.get("balance_elapsed_seconds", previous_time))
            if current_time <= POLICY_ECONOMY_GRACE_SECONDS:
                previous = snapshot
                continue
            delta = max(0.0, current_time - max(previous_time, POLICY_ECONOMY_GRACE_SECONDS))
            previous_gathered = int(previous.get("balance_ai_resources_gathered", 0))
            current_gathered = int(snapshot.get("balance_ai_resources_gathered", 0))
            if current_gathered <= previous_gathered:
                current += delta
                longest = max(longest, current)
            else:
                current = 0.0
            previous = snapshot
        return longest

    @staticmethod
    def _policy_horizon_evidence(snapshots: list[dict[str, Any]]) -> dict[str, Any]:
        """Return only evidence observed at or before the force-policy horizon.

        Overall telemetry remains useful in the report, but a 450-second run must
        not retroactively satisfy a guardrail stated as "by 300s". Sampling is
        conservative: the last eligible sample can precede the exact horizon.
        """
        eligible = [
            snapshot
            for snapshot in snapshots
            if float(snapshot.get("balance_elapsed_seconds", 0.0))
            <= POLICY_FORCE_HORIZON_SECONDS
        ]
        if not eligible:
            return {
                "last_sample_time": -1.0,
                "peak_villagers": 0,
                "peak_military": 0,
                "attack_count": 0,
                "objective_modes": {},
                "objective_unit_peak": 0,
                "objective_force_samples": 0,
                "sacred_control_seconds": 0.0,
            }

        objective_modes: dict[str, int] = {}
        for snapshot in eligible:
            mode = str(snapshot.get("balance_ai_objective_mode", "none"))
            objective_modes[mode] = objective_modes.get(mode, 0) + 1

        return {
            "last_sample_time": max(
                float(snapshot.get("balance_elapsed_seconds", 0.0)) for snapshot in eligible
            ),
            "peak_villagers": max(
                int(snapshot.get("balance_ai_villagers", 0)) for snapshot in eligible
            ),
            "peak_military": max(
                int(snapshot.get("balance_ai_military", 0)) for snapshot in eligible
            ),
            "attack_count": max(
                int(snapshot.get("balance_ai_attack_count", 0)) for snapshot in eligible
            ),
            "objective_modes": objective_modes,
            "objective_unit_peak": max(
                int(snapshot.get("balance_ai_objective_unit_count", 0)) for snapshot in eligible
            ),
            "objective_force_samples": sum(
                1
                for snapshot in eligible
                if str(snapshot.get("balance_ai_objective_mode", "none"))
                in ("capture", "contest", "defend")
                and int(snapshot.get("balance_ai_objective_unit_count", 0)) > 0
            ),
            "sacred_control_seconds": max(
                float(snapshot.get("balance_ai_sacred_control_seconds", 0.0))
                for snapshot in eligible
            ),
        }

    @staticmethod
    def _evaluate_policy(
        *,
        difficulty: int,
        elapsed: float,
        age: int,
        feudal_time: float,
        peak_villagers: int,
        peak_military: int,
        attack_count: int,
        objective_modes: dict[str, int],
        objective_unit_peak: int,
        sacred_control_seconds: float,
        economy_stagnation_seconds: float,
        economic_bonus_observed: bool,
        objective_force_samples: int | None = None,
        match_completed: bool = False,
        winner_id: int = -1,
    ) -> list[str]:
        """Return conservative liveness failures, never a balance verdict."""
        issues: list[str] = []
        deadline = AGE_UP_POLICY_DEADLINES[difficulty]
        ai_victory: bool = match_completed and winner_id == 1
        if (
            not ai_victory
            and elapsed >= deadline
            and (age < 2 or feudal_time < 0.0 or feudal_time > deadline)
        ):
            issues.append(f"no Feudal age by {deadline:.0f}s liveness deadline")

        max_stagnation = MAX_ECONOMY_STAGNATION_SECONDS[difficulty]
        if economy_stagnation_seconds > max_stagnation:
            issues.append(
                f"worker deposits stagnant for {economy_stagnation_seconds:.1f}s "
                f"(limit {max_stagnation:.0f}s)"
            )

        if elapsed >= POLICY_FORCE_HORIZON_SECONDS:
            min_villagers = MIN_PEAK_VILLAGERS[difficulty]
            if peak_villagers < min_villagers:
                issues.append(f"peak villagers {peak_villagers} below liveness floor {min_villagers}")
            min_military = MIN_PEAK_MILITARY[difficulty]
            if peak_military < min_military:
                issues.append(f"peak military {peak_military} below liveness floor {min_military}")
            objective_active = (
                objective_force_samples > 0
                if objective_force_samples is not None
                else objective_unit_peak > 0
                and any(objective_modes.get(mode, 0) > 0 for mode in ("capture", "contest", "defend"))
            )
            if attack_count <= 0 and sacred_control_seconds < 60.0 and not objective_active:
                issues.append("no attack or meaningful Sacred Site pressure by 300s")

        if economic_bonus_observed:
            issues.append("economic bonus observed despite fair-economy policy")
        return issues


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run focused MCP AI balance pass for Easy/Medium/Hard.")
    parser.add_argument("--project-path", type=Path, default=Path("."), help="Project root path")
    parser.add_argument("--scene", default="res://scenes/main/main.tscn", help="Scene to run")
    parser.add_argument("--server-cmd", default="npx -y @satelliteoflove/godot-mcp@2.16.1", help="MCP server command")
    parser.add_argument("--sim-seconds", type=float, default=300.0, help="Simulation duration per difficulty")
    parser.add_argument("--sample-seconds", type=float, default=5.0, help="Telemetry sample interval")
    parser.add_argument("--startup-timeout", type=float, default=25.0, help="Wait for scene playing state")
    parser.add_argument("--request-timeout", type=float, default=25.0, help="MCP request timeout")
    parser.add_argument("--editor-boot-seconds", type=float, default=6.0, help="Wait after launching Godot editor")
    parser.add_argument("--min-fps", type=float, default=15.0, help="Minimum acceptable FPS")
    parser.add_argument("--max-frame-time-ms", type=float, default=120.0, help="Maximum acceptable frame time")
    parser.add_argument("--difficulties", default="0,1,2", help="Comma-separated difficulty IDs (0=Easy, 1=Medium, 2=Hard)")
    parser.add_argument("--seeds", default="-1", help="Comma-separated deterministic map seeds")
    parser.add_argument("--time-scale", type=float, default=1.0, help="Simulation time scale (clamped by runtime to 1x-3x)")
    parser.add_argument("--require-completion", action="store_true", help="Fail a case unless it reaches a production game-over state")
    parser.add_argument(
        "--require-policy",
        action="store_true",
        help="Fail when conservative AI liveness checks fail (reported separately from technical health)",
    )
    parser.add_argument("--append", action="store_true", help="Merge cases into an existing compatible output report")
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

    difficulty_names = dict(DIFFICULTIES)
    try:
        selected_difficulties = [int(value.strip()) for value in args.difficulties.split(",") if value.strip()]
        selected_seeds = [int(value.strip()) for value in args.seeds.split(",") if value.strip()]
    except ValueError as exc:
        raise SystemExit(f"Invalid difficulty/seed list: {exc}") from exc
    if not selected_difficulties or any(value not in difficulty_names for value in selected_difficulties):
        raise SystemExit("Difficulties must contain one or more of 0,1,2")
    if not selected_seeds:
        raise SystemExit("At least one seed is required")

    for difficulty in selected_difficulties:
        name = difficulty_names[difficulty]
        for seed in selected_seeds:
            print(f"\\n=== Running {name} (difficulty={difficulty}, seed={seed}) ===")
            result = runner.run_difficulty(difficulty, name, seed)
            results.append(result)
            print(
                f"[{name} seed={seed}] technical_ok={result.technical_ok} policy_ok={result.policy_ok} "
                f"completed={result.match_completed} "
                f"winner={result.winner_id} reason={result.victory_reason or '-'} age={result.age} "
                f"feudal={result.feudal_time:.1f}s castle={result.castle_time:.1f}s imperial={result.imperial_time:.1f}s "
                f"res=({result.food}/{result.wood}/{result.gold}) pop(v/m/b)=({result.villagers}/{result.military}/{result.buildings}) "
                f"idle(v/p)={result.idle_villagers}/{result.idle_production_buildings} "
                f"peak(v/m)={result.peak_villagers}/{result.peak_military} float={result.resource_float} "
                f"gathered={result.resources_gathered} "
                f"attacks={result.attack_count} first_attack={result.first_attack_time:.1f}s "
                f"objective={result.objective_modes} objective_units={result.objective_unit_peak} "
                f"sacred={result.sacred_control_seconds:.1f}s econ_bonus={result.economic_bonus_observed} "
                f"policy@{result.policy_last_sample_time:.1f}s="
                f"(v{result.policy_peak_villagers}/m{result.policy_peak_military}/"
                f"a{result.policy_attack_count}/o{result.policy_objective_unit_peak}/"
                f"of{result.policy_objective_force_samples}/s{result.policy_sacred_control_seconds:.1f}) "
                f"stall={result.stall_seconds:.1f}s economy_stagnation={result.economy_stagnation_seconds:.1f}s "
                f"runtime_errors={result.runtime_errors}"
            )
            if not result.technical_ok:
                print(f"[{name} seed={seed}] technical reason: {result.reason}")
            if result.policy_issues:
                print(f"[{name} seed={seed}] policy issues: {'; '.join(result.policy_issues)}")

    report_results: list[dict[str, Any]] = [result.__dict__ for result in results]
    if args.append and args.out.exists():
        existing = json.loads(args.out.read_text(encoding="utf-8"))
        for key, expected in {
            "sim_seconds": args.sim_seconds,
            "sample_seconds": args.sample_seconds,
            "time_scale": args.time_scale,
            "require_completion": args.require_completion,
            "require_policy": args.require_policy,
        }.items():
            if existing.get(key) != expected:
                raise SystemExit(f"Cannot append: existing {key}={existing.get(key)!r}, requested {expected!r}")
        merged: dict[tuple[int, int], dict[str, Any]] = {}
        for entry in existing.get("results", []):
            merged[(int(entry["difficulty"]), int(entry["seed"]))] = entry
        for entry in report_results:
            merged[(int(entry["difficulty"]), int(entry["seed"]))] = entry
        report_results = [merged[key] for key in sorted(merged)]

    completed_results = [entry for entry in report_results if bool(entry.get("match_completed", False))]
    match_times = [float(entry["elapsed"]) for entry in completed_results]
    first_attack_times = [float(entry["first_attack_time"]) for entry in completed_results if float(entry.get("first_attack_time", -1.0)) >= 0.0]
    winner_counts: dict[str, int] = {}
    for entry in completed_results:
        winner_key = str(int(entry.get("winner_id", -1)))
        winner_counts[winner_key] = winner_counts.get(winner_key, 0) + 1
    output = {
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "sim_seconds": args.sim_seconds,
        "sample_seconds": args.sample_seconds,
        "time_scale": args.time_scale,
        "require_completion": args.require_completion,
        "require_policy": args.require_policy,
        "policy_guardrails": {
            "classification": "conservative AI liveness checks; not a balance verdict",
            "age_up_deadlines_seconds": AGE_UP_POLICY_DEADLINES,
            "age_up_terminal_exception": (
                "an authoritative completed AI victory satisfies only the age-progression "
                "liveness clause; economy, force, pressure, fair-economy, and technical "
                "guardrails remain enforced"
            ),
            "max_worker_deposit_stagnation_seconds": MAX_ECONOMY_STAGNATION_SECONDS,
            "minimum_peak_villagers": MIN_PEAK_VILLAGERS,
            "minimum_peak_military": MIN_PEAK_MILITARY,
            "force_horizon_seconds": POLICY_FORCE_HORIZON_SECONDS,
            "force_horizon_evidence": (
                "per-result policy_* fields use only snapshots at or before the horizon; "
                "policy_last_sample_time exposes conservative sampling granularity"
            ),
            "economy_grace_seconds": POLICY_ECONOMY_GRACE_SECONDS,
        },
        "summary": {
            "cases": len(report_results),
            "passed": sum(1 for entry in report_results if bool(entry.get("ok", False))),
            "technical_passed": sum(1 for entry in report_results if bool(entry.get("technical_ok", entry.get("ok", False)))),
            "policy_passed": sum(1 for entry in report_results if bool(entry.get("policy_ok", False))),
            "completed": len(completed_results),
            "runtime_errors": sum(int(entry.get("runtime_errors", 0)) for entry in report_results),
            "median_match_seconds": statistics.median(match_times) if match_times else -1.0,
            "median_first_attack_seconds": statistics.median(first_attack_times) if first_attack_times else -1.0,
            "winner_counts": winner_counts,
        },
        "results": report_results,
    }
    args.out.write_text(json.dumps(output, indent=2), encoding="utf-8")

    print(f"\\nSaved report: {args.out}")

    technical_passed = all(bool(entry.get("technical_ok", entry.get("ok", False))) for entry in report_results)
    policy_passed = all(bool(entry.get("policy_ok", False)) for entry in report_results)
    return 0 if technical_passed and (policy_passed or not args.require_policy) else 1


if __name__ == "__main__":
    raise SystemExit(main())

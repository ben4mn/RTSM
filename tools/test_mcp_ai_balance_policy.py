#!/usr/bin/env python3
"""Unit tests for AI matrix liveness classification."""

from __future__ import annotations

import unittest

from mcp_ai_balance_pass import BalanceRunner


class BalancePolicyTests(unittest.TestCase):
    def test_sacred_gold_cannot_mask_worker_deposit_stagnation(self) -> None:
        snapshots = [
            {
                "balance_elapsed_seconds": seconds,
                "balance_ai_resources_gathered": 100 if seconds >= 60 else 0,
                "balance_ai_gold": 100 + max(0, seconds - 60),
            }
            for seconds in range(0, 361, 15)
        ]
        self.assertEqual(BalanceRunner._longest_economy_stagnation_seconds(snapshots), 300.0)

    def test_regular_deposits_reset_stagnation_window(self) -> None:
        snapshots = [
            {
                "balance_elapsed_seconds": seconds,
                "balance_ai_resources_gathered": max(0, (seconds - 45) // 30) * 15,
            }
            for seconds in range(0, 361, 15)
        ]
        self.assertLessEqual(BalanceRunner._longest_economy_stagnation_seconds(snapshots), 15.0)

    def test_frozen_medium_ai_fails_multiple_liveness_guardrails(self) -> None:
        issues = BalanceRunner._evaluate_policy(
            difficulty=1,
            elapsed=350.0,
            age=1,
            feudal_time=-1.0,
            peak_villagers=7,
            peak_military=1,
            attack_count=0,
            objective_modes={"defend": 10},
            objective_unit_peak=1,
            sacred_control_seconds=179.0,
            economy_stagnation_seconds=296.5,
            economic_bonus_observed=False,
        )
        self.assertTrue(any("Feudal" in issue for issue in issues))
        self.assertTrue(any("deposits stagnant" in issue for issue in issues))
        self.assertTrue(any("peak villagers" in issue for issue in issues))
        self.assertTrue(any("peak military" in issue for issue in issues))

    def test_healthy_objective_ai_passes_conservative_liveness_guardrails(self) -> None:
        issues = BalanceRunner._evaluate_policy(
            difficulty=2,
            elapsed=310.0,
            age=2,
            feudal_time=250.0,
            peak_villagers=15,
            peak_military=6,
            attack_count=0,
            objective_modes={"capture": 2, "defend": 12},
            objective_unit_peak=3,
            sacred_control_seconds=150.0,
            economy_stagnation_seconds=45.0,
            economic_bonus_observed=False,
        )
        self.assertEqual(issues, [])

    def test_mode_label_without_force_or_control_is_not_meaningful_pressure(self) -> None:
        issues = BalanceRunner._evaluate_policy(
            difficulty=1,
            elapsed=310.0,
            age=2,
            feudal_time=260.0,
            peak_villagers=14,
            peak_military=4,
            attack_count=0,
            objective_modes={"capture": 4},
            objective_unit_peak=0,
            sacred_control_seconds=0.0,
            economy_stagnation_seconds=45.0,
            economic_bonus_observed=False,
        )
        self.assertIn("no attack or meaningful Sacred Site pressure by 300s", issues)

    def test_late_feudal_does_not_satisfy_deadline(self) -> None:
        issues = BalanceRunner._evaluate_policy(
            difficulty=1,
            elapsed=400.0,
            age=2,
            feudal_time=360.0,
            peak_villagers=14,
            peak_military=4,
            attack_count=1,
            objective_modes={},
            objective_unit_peak=0,
            sacred_control_seconds=0.0,
            economy_stagnation_seconds=45.0,
            economic_bonus_observed=False,
        )
        self.assertIn("no Feudal age by 330s liveness deadline", issues)

    def test_age_one_ai_victory_satisfies_only_age_liveness_clause(self) -> None:
        issues = BalanceRunner._evaluate_policy(
            difficulty=2,
            elapsed=291.5,
            age=1,
            feudal_time=-1.0,
            peak_villagers=12,
            peak_military=4,
            attack_count=0,
            objective_modes={"capture": 2, "defend": 10},
            objective_unit_peak=2,
            objective_force_samples=12,
            sacred_control_seconds=179.8,
            economy_stagnation_seconds=0.0,
            economic_bonus_observed=False,
            match_completed=True,
            winner_id=1,
        )
        self.assertEqual(issues, [])

    def test_age_one_nonterminal_or_player_victory_still_fails_age_liveness(self) -> None:
        for match_completed, winner_id in ((False, -1), (True, 0)):
            with self.subTest(match_completed=match_completed, winner_id=winner_id):
                issues = BalanceRunner._evaluate_policy(
                    difficulty=2,
                    elapsed=291.5,
                    age=1,
                    feudal_time=-1.0,
                    peak_villagers=12,
                    peak_military=4,
                    attack_count=0,
                    objective_modes={"capture": 2, "defend": 10},
                    objective_unit_peak=2,
                    objective_force_samples=12,
                    sacred_control_seconds=179.8,
                    economy_stagnation_seconds=0.0,
                    economic_bonus_observed=False,
                    match_completed=match_completed,
                    winner_id=winner_id,
                )
                self.assertIn("no Feudal age by 285s liveness deadline", issues)

    def test_ai_victory_does_not_mask_other_liveness_failures(self) -> None:
        issues = BalanceRunner._evaluate_policy(
            difficulty=2,
            elapsed=310.0,
            age=1,
            feudal_time=-1.0,
            peak_villagers=8,
            peak_military=1,
            attack_count=0,
            objective_modes={},
            objective_unit_peak=0,
            objective_force_samples=0,
            sacred_control_seconds=0.0,
            economy_stagnation_seconds=180.0,
            economic_bonus_observed=True,
            match_completed=True,
            winner_id=1,
        )
        self.assertFalse(any("Feudal" in issue for issue in issues))
        self.assertTrue(any("deposits stagnant" in issue for issue in issues))
        self.assertTrue(any("peak villagers" in issue for issue in issues))
        self.assertTrue(any("peak military" in issue for issue in issues))
        self.assertIn("no attack or meaningful Sacred Site pressure by 300s", issues)
        self.assertIn("economic bonus observed despite fair-economy policy", issues)

    def test_post_horizon_growth_and_pressure_cannot_satisfy_300s_gate(self) -> None:
        snapshots = [
            {
                "balance_elapsed_seconds": 285.0,
                "balance_ai_villagers": 9,
                "balance_ai_military": 1,
                "balance_ai_attack_count": 0,
                "balance_ai_objective_mode": "scout",
                "balance_ai_objective_unit_count": 1,
                "balance_ai_sacred_control_seconds": 0.0,
            },
            {
                "balance_elapsed_seconds": 315.0,
                "balance_ai_villagers": 20,
                "balance_ai_military": 8,
                "balance_ai_attack_count": 2,
                "balance_ai_objective_mode": "capture",
                "balance_ai_objective_unit_count": 4,
                "balance_ai_sacred_control_seconds": 75.0,
            },
        ]
        evidence = BalanceRunner._policy_horizon_evidence(snapshots)
        self.assertEqual(evidence["last_sample_time"], 285.0)
        self.assertEqual(evidence["peak_villagers"], 9)
        self.assertEqual(evidence["peak_military"], 1)
        self.assertEqual(evidence["attack_count"], 0)
        self.assertEqual(evidence["objective_modes"], {"scout": 1})
        self.assertEqual(evidence["objective_unit_peak"], 1)
        self.assertEqual(evidence["objective_force_samples"], 0)
        self.assertEqual(evidence["sacred_control_seconds"], 0.0)

        issues = BalanceRunner._evaluate_policy(
            difficulty=1,
            elapsed=315.0,
            age=2,
            feudal_time=250.0,
            peak_villagers=int(evidence["peak_villagers"]),
            peak_military=int(evidence["peak_military"]),
            attack_count=int(evidence["attack_count"]),
            objective_modes=dict(evidence["objective_modes"]),
            objective_unit_peak=int(evidence["objective_unit_peak"]),
            sacred_control_seconds=float(evidence["sacred_control_seconds"]),
            economy_stagnation_seconds=45.0,
            economic_bonus_observed=False,
        )
        self.assertTrue(any("peak villagers" in issue for issue in issues))
        self.assertTrue(any("peak military" in issue for issue in issues))
        self.assertIn("no attack or meaningful Sacred Site pressure by 300s", issues)


if __name__ == "__main__":
    unittest.main()

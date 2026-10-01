#!/usr/bin/env python3
"""Pure regression checks for MCP phone world-target selection helpers."""

import unittest

from mcp_phone_playability import (
    blocking_hud_region_at,
    choose_empty_ground_target,
    has_fresh_context_execution,
    has_fresh_military_shortcut_execution,
    mobile_layout_blocking_rects,
)


class PhoneWorldTargetingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.screen_w = 1063
        self.screen_h = 598
        self.layout = {
            "viewport_width": 844.0,
            "viewport_height": 474.0,
            "action_left": 8.0,
            "action_right": -8.0,
            "action_top": -76.0,
            "action_bottom": -8.0,
            "minimap_left": 8.0,
            "minimap_right": 218.0,
            "minimap_top": -304.0,
            "minimap_bottom": -86.0,
            "selection_left": 219.44,
            "selection_right": 624.56,
            "selection_top": -196.0,
            "selection_bottom": -84.0,
            "bottom_right_left": -172.0,
            "bottom_right_right": -8.0,
            "bottom_right_top": -208.0,
            "bottom_right_bottom": -84.0,
        }
        self.rects = mobile_layout_blocking_rects(
            self.layout,
            self.screen_w / self.layout["viewport_width"],
            self.screen_h / self.layout["viewport_height"],
        )

    def test_failed_run_point_is_inside_selection_panel(self) -> None:
        self.assertEqual(blocking_hud_region_at(352, 369, self.rects), "selection_panel")

    def test_bottom_action_panel_uses_mixed_horizontal_offsets(self) -> None:
        self.assertEqual(blocking_hud_region_at(532, 550, self.rects), "mobile_action_panel")

    def test_empty_ground_choice_skips_live_hud_rectangles(self) -> None:
        target = choose_empty_ground_target(
            self.screen_w,
            self.screen_h,
            212,
            489,
            [],
            self.rects,
        )
        self.assertIsNotNone(target)
        assert target is not None
        self.assertEqual(target[:2], (352, 289))
        self.assertIsNone(blocking_hud_region_at(target[0], target[1], self.rects))

    def test_long_press_requires_one_fresh_runtime_execution(self) -> None:
        before = {
            "last_executed_action": "Move",
            "last_executed_action_id": 100,
            "last_executed_timestamp_ms": 1200,
            "execution_count": 4,
        }
        fresh = {
            "last_executed_action": "Move",
            "last_executed_action_id": 100,
            "last_executed_timestamp_ms": 1400,
            "execution_count": 5,
        }
        self.assertTrue(has_fresh_context_execution(before, fresh, "Move", 100))

        config_only = {"touch_context_enabled": True, "long_press_threshold": 0.35}
        self.assertFalse(has_fresh_context_execution(before, config_only, "Move", 100))

        stale = dict(fresh, last_executed_timestamp_ms=1200)
        self.assertFalse(has_fresh_context_execution(before, stale, "Move", 100))

        double_fired = dict(fresh, execution_count=6)
        self.assertFalse(has_fresh_context_execution(before, double_fired, "Move", 100))

    def test_military_shortcut_requires_fresh_complete_selection(self) -> None:
        scout_path = "/root/Main/GameMap/UnitsContainer/Scout"
        before = {
            "military_shortcut_invocation_count": 2,
            "military_shortcut_last_timestamp_ms": 1200,
        }
        fresh = {
            "military_shortcut_invocation_count": 3,
            "military_shortcut_last_timestamp_ms": 1400,
            "military_shortcut_selected_count": 2,
            "military_shortcut_selected_paths": [scout_path, "/root/Main/GameMap/UnitsContainer/Infantry"],
            "military_count": 2,
        }
        self.assertTrue(has_fresh_military_shortcut_execution(before, fresh, scout_path))

        already_selected_false_positive = dict(fresh, military_shortcut_invocation_count=2)
        self.assertFalse(
            has_fresh_military_shortcut_execution(before, already_selected_false_positive, scout_path)
        )

        stale_timestamp = dict(fresh, military_shortcut_last_timestamp_ms=1200)
        self.assertFalse(has_fresh_military_shortcut_execution(before, stale_timestamp, scout_path))

        partial_selection = dict(fresh, military_shortcut_selected_count=1)
        partial_selection["military_shortcut_selected_paths"] = [scout_path]
        self.assertFalse(has_fresh_military_shortcut_execution(before, partial_selection, scout_path))

        missing_expected_unit = dict(fresh)
        missing_expected_unit["military_shortcut_selected_paths"] = [
            "/root/Main/GameMap/UnitsContainer/Infantry",
            "/root/Main/GameMap/UnitsContainer/Archer",
        ]
        self.assertFalse(has_fresh_military_shortcut_execution(before, missing_expected_unit, scout_path))


if __name__ == "__main__":
    unittest.main()

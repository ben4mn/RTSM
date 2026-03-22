# Mobile UX Touch Audit Report

Date (UTC): 2026-03-08T19:25:20.736421+00:00
Status: **FAIL**

## Settings

- Menu scene: `res://scenes/ui/main_menu.tscn`
- Gameplay scene: `res://scenes/main/main.tscn`
- Min touch target: `48.0`
- Max aspect ratio: `4.0`

## Checks

- [PASS] `tooling_available`: editor/input/project/node tools discovered
- [PASS] `addon_connection`: connected (server=2.15.0 addon=2.15.0)
- [PASS] `main_menu_ready`: Main menu scene is active
- [PASS] `main_menu_contract`: diagnostics ready (difficulty=Medium guided_opening=True)
- [PASS] `touch_target_audit_main_menu`: 2 controls meet target/aspect constraints
- [PASS] `main_menu_touch_start_smoke`: transitioned after 1 tap(s); tap1: Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:640:683:1, pointer:screen_touch:0:640:683:0] over 70ms
- [PASS] `startup_to_gameplay`: screen=1280x720, transitioned via touch
- [PASS] `camera_mobile_framing`: zoom=1.102 (mobile_min=0.78 mobile_max=1.90 desktop_default=1.35)
- [PASS] `hud_phone_layout_profiles`: 844x390[w=180.0,h=56.0,cols=4], 932x430[w=180.0,h=56.0,cols=4]
- [PASS] `touch_target_audit_hud_core`: 3 controls meet target/aspect constraints
- [PASS] `touch_target_audit_minimap_region`: 2 controls meet target/aspect constraints
- [PASS] `touch_select_move_smoke`: Input sequence completed: 4 action(s) executed [pointer:screen_touch:0:640:360:1, pointer:screen_touch:0:640:360:0, pointer:screen_touch:0:819:417:1, pointer:screen_touch:0:819:417:0] over 330ms
- [PASS] `touch_long_press_context_smoke`: runtime actions unavailable under MCP timing; config enabled (threshold=0.35)
- [PASS] `guided_opener_initial_stage`: enabled=True, active=True, stage=gather_food, gather=False, house=False, scout=False, move=False, loop=False
- [PASS] `touch_select_villager_for_gather`: attempt1=Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:592:176:1, pointer:screen_touch:0:592:176:0] over 70ms action=select path=/root/Main/GameMap/UnitsContainer/@Area2D@394 @(592,176)
- [PASS] `touch_select_villager_target`: Tapped villager /root/Main/GameMap/UnitsContainer/@Area2D@394 at (576,183)
- [PASS] `touch_select_villager_assertion`: selected=4
- [PASS] `touch_villager_gather_smoke`: attempt1=Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:719:384:1, pointer:screen_touch:0:719:384:0] over 70ms action=gather path=/root/Main/GameMap/ResourcesContainer/@Area2D@278 @(719,384)
- [PASS] `touch_villager_gather_target`: Tapped resource node /root/Main/GameMap/ResourcesContainer/@Area2D@278 at (719,384)
- [PASS] `guided_opener_after_gather`: enabled=True, active=True, stage=build_house, gather=True, house=False, scout=False, move=False, loop=False
- [PASS] `touch_open_build_menu_for_audit`: Build menu opened from touch input
- [PASS] `touch_target_audit_build_menu`: 25 controls meet target/aspect constraints
- [PASS] `touch_build_menu_house_option`: Selected `House +10 pop`
- [PASS] `touch_build_place_cancel_smoke`: Input sequence completed: 6 action(s) executed [pointer:screen_touch:0:448:376:1, pointer:screen_touch:0:448:376:0, pointer:screen_touch:0:640:360:1, pointer:screen_touch:0:640:360:0, pointer:screen_touch:0:98:672:1, pointer:screen_touch:0:98:672:0] over 630ms
- [PASS] `touch_build_menu_close_after_cancel`: Build menu closed after cancel-path verification
- [PASS] `touch_camera_drag_responsive_0`: Input sequence completed: 3 action(s) executed [pointer:screen_touch:0:947:432:1, pointer:screen_drag:0:512:288:-435:-144, pointer:screen_touch:0:512:288:0] over 190ms
- [PASS] `touch_camera_drag_responsive_1`: Input sequence completed: 3 action(s) executed [pointer:screen_touch:0:435:417:1, pointer:screen_drag:0:870:259:435:-158, pointer:screen_touch:0:870:259:0] over 190ms
- [PASS] `touch_camera_drag_responsive`: camera drag deltas: 525.6, 518.7
- [PASS] `touch_pinch_zoom_out_smoke`: Input sequence completed: 6 action(s) executed [pointer:screen_touch:0:560:360:1, pointer:screen_touch:1:720:360:1, pointer:screen_drag:0:490:360:-70:0, pointer:screen_drag:1:790:360:70:0, pointer:screen_touch:0:490:360:0, pointer:screen_touch:1:790:360:0] over 220ms
- [PASS] `touch_pinch_zoom_in_smoke`: Input sequence completed: 6 action(s) executed [pointer:screen_touch:0:490:360:1, pointer:screen_touch:1:790:360:1, pointer:screen_drag:0:560:360:70:0, pointer:screen_drag:1:720:360:-70:0, pointer:screen_touch:0:560:360:0, pointer:screen_touch:1:720:360:0] over 220ms
- [PASS] `touch_pinch_zoom_validation`: before=1.102 out=1.900 in=1.013
- [PASS] `touch_minimap_geometry`: rect=(8,414)-(228,634) size=220x220
- [PASS] `touch_minimap_reposition_smoke_0`: Input sequence completed: 3 action(s) executed [pointer:screen_touch:0:56:585:1, pointer:screen_drag:0:179:462:123:-123, pointer:screen_touch:0:179:462:0] over 190ms
- [PASS] `touch_minimap_camera_delta`: touch(idx=0)=1501.0
- [PASS] `progression_hint_validation`: Build House: tap the Build button on the right HUD.
- [PASS] `touch_build_option_arm_placement`: Placement mode activated
- [PASS] `touch_build_menu_close_after_place`: Build menu closed after placement
- [FAIL] `touch_build_place_resume_economy_smoke`: Gather command did not register after build placement

## Findings

- No touch-target violations detected.

## Prioritized Fix Plan

1. No fixes required from this run.

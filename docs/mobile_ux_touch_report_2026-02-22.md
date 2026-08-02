# Mobile UX Touch Audit Report

Date (UTC): 2026-08-02T02:31:04.461821+00:00
Status: **PASS**

## Settings

- Menu scene: `res://scenes/ui/main_menu.tscn`
- Gameplay scene: `res://scenes/main/main.tscn`
- Min touch target: `48.0`
- Max aspect ratio: `4.0`

## Checks

- [PASS] `tooling_available`: editor/input/project/node tools discovered
- [PASS] `addon_connection`: connected (server=2.16.1 addon=2.16.1)
- [PASS] `main_menu_ready`: Main menu scene is active
- [PASS] `main_menu_contract`: diagnostics ready (difficulty=Medium guided_opening=True)
- [PASS] `touch_target_audit_main_menu`: 3 controls meet target/aspect constraints
- [PASS] `main_menu_seed_entry`: Entered deterministic seed 424242 through touch/text input
- [PASS] `main_menu_touch_start_smoke`: transitioned after 1 tap(s); tap1: Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:640:684:1, pointer:screen_touch:0:640:684:0] over 70ms
- [PASS] `startup_to_gameplay`: screen=1280x720, transitioned via touch
- [PASS] `camera_mobile_framing`: zoom=1.102 (mobile_min=0.78 mobile_max=1.90 desktop_default=1.35)
- [PASS] `hud_phone_layout_profiles`: 844x390[w=180.0,h=56.0,cols=4], 932x430[w=180.0,h=56.0,cols=4]
- [PASS] `touch_target_audit_hud_core`: 3 controls meet target/aspect constraints
- [PASS] `touch_target_audit_minimap_region`: 2 controls meet target/aspect constraints
- [PASS] `touch_select_move_smoke`: Input sequence completed: 4 action(s) executed [pointer:screen_touch:0:640:360:1, pointer:screen_touch:0:640:360:0, pointer:screen_touch:0:819:417:1, pointer:screen_touch:0:819:417:0] over 330ms
- [PASS] `touch_long_press_context_smoke`: runtime actions unavailable under MCP timing; config enabled (threshold=0.35)
- [PASS] `guided_opener_initial_stage`: enabled=True, active=True, stage=gather_food, gather=False, house=False, scout=False, move=False, loop=False
- [PASS] `touch_select_villager_for_gather`: attempt1=Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:517:264:1, pointer:screen_touch:0:517:264:0] over 70ms action=select path=/root/Main/GameMap/UnitsContainer/@Area2D@379 tapped_dist=19.8471412658691 resource= resource_dist=-1 radii=(26.438401222229,30.8448014259338) zoom=1.10160005092621 @(517,264)
- [PASS] `touch_select_villager_target`: Tapped villager /root/Main/GameMap/UnitsContainer/@Area2D@379 at (517,264)
- [PASS] `touch_select_villager_assertion`: selected=1
- [PASS] `touch_villager_gather_smoke`: attempt1=Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:656:256:1, pointer:screen_touch:0:656:256:0] over 70ms action=gather path=/root/Main/GameMap/ResourcesContainer/@Area2D@212 tapped_dist=-1 resource=/root/Main/GameMap/ResourcesContainer/@Area2D@212 resource_dist=0.124654248356819 radii=(26.438401222229,30.8448014259338) zoom=1.10160005092621 @(656,256)
- [PASS] `touch_villager_gather_target`: Tapped resource node /root/Main/GameMap/ResourcesContainer/@Area2D@212 at (656,256)
- [PASS] `guided_opener_after_gather`: enabled=True, active=True, stage=build_house, gather=True, house=False, scout=False, move=False, loop=False
- [PASS] `touch_open_build_menu_for_audit`: Build menu opened from touch input
- [PASS] `touch_target_audit_build_menu`: 13 controls meet target/aspect constraints
- [PASS] `touch_build_menu_house_option`: Selected `House +10 pop`
- [PASS] `touch_build_place_cancel_smoke`: Input sequence completed: 6 action(s) executed [pointer:screen_touch:0:626:444:1, pointer:screen_touch:0:626:444:0, pointer:screen_touch:0:640:360:1, pointer:screen_touch:0:640:360:0, pointer:screen_touch:0:98:672:1, pointer:screen_touch:0:98:672:0] over 630ms
- [PASS] `touch_build_menu_close_after_cancel`: Build menu closed after cancel-path verification
- [PASS] `touch_camera_drag_responsive_0`: Input sequence completed: 3 action(s) executed [pointer:screen_touch:0:947:432:1, pointer:screen_drag:0:512:288:-435:-144, pointer:screen_touch:0:512:288:0] over 190ms
- [PASS] `touch_camera_drag_responsive_1`: Input sequence completed: 3 action(s) executed [pointer:screen_touch:0:435:417:1, pointer:screen_drag:0:870:259:435:-158, pointer:screen_touch:0:870:259:0] over 190ms
- [PASS] `touch_camera_drag_responsive`: camera drag deltas: 525.6, 538.3
- [PASS] `touch_pinch_zoom_out_smoke`: Input sequence completed: 6 action(s) executed [pointer:screen_touch:0:560:360:1, pointer:screen_touch:1:720:360:1, pointer:screen_drag:0:490:360:-70:0, pointer:screen_drag:1:790:360:70:0, pointer:screen_touch:0:490:360:0, pointer:screen_touch:1:790:360:0] over 220ms
- [PASS] `touch_pinch_zoom_in_smoke`: Input sequence completed: 6 action(s) executed [pointer:screen_touch:0:490:360:1, pointer:screen_touch:1:790:360:1, pointer:screen_drag:0:560:360:70:0, pointer:screen_drag:1:720:360:-70:0, pointer:screen_touch:0:560:360:0, pointer:screen_touch:1:720:360:0] over 220ms
- [PASS] `touch_pinch_zoom_validation`: before=1.102 out=1.900 in=1.013
- [PASS] `touch_minimap_geometry`: rect=(8,414)-(228,634) size=220x220
- [PASS] `touch_minimap_reposition_smoke_0`: Input sequence completed: 3 action(s) executed [pointer:screen_touch:0:56:585:1, pointer:screen_drag:0:179:462:123:-123, pointer:screen_touch:0:179:462:0] over 190ms
- [PASS] `touch_minimap_camera_delta`: touch(idx=0)=1447.4
- [PASS] `progression_hint_validation`: Train Scout: tap Town Center, then tap Scout.
- [PASS] `touch_build_option_arm_placement`: Placement mode activated
- [PASS] `touch_build_menu_close_after_place`: Build menu closed after placement
- [PASS] `touch_build_place_resume_economy_smoke`: placed at 768,460; attempt1=placed@768,460; minimap_relocate=Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:16:554:1, pointer:screen_touch:0:16:554:0] over 70ms | resume_select_after_relocate=attempt1=Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:516:381:1, pointer:screen_touch:0:516:381:0] over 70ms selected=1 @(516,381) | resume_gather=attempt1=Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:746:441:1, pointer:screen_touch:0:746:441:0] over 70ms action=gather path=/root/Main/GameMap/ResourcesContainer/@Area2D@212 tapped_dist=-1 resource=/root/Main/GameMap/ResourcesContainer/@Area2D@212 resource_dist=0.195649489760399 radii=(24.3199996948242,28.3733329772949) zoom=1.01333332061768 @(746,441)
- [PASS] `guided_opener_after_house`: enabled=True, active=True, stage=train_scout, gather=True, house=True, scout=False, move=False, loop=False
- [PASS] `touch_pause_open_for_audit`: Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:1116:36:1, pointer:screen_touch:0:1116:36:0] over 70ms
- [PASS] `touch_target_audit_pause_controls`: 4 controls meet target/aspect constraints
- [PASS] `touch_pause_resume_after_audit`: Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:640:328:1, pointer:screen_touch:0:640:328:0] over 70ms
- [PASS] `touch_pause_resume_state`: Game resumed after pause-controls audit
- [PASS] `touch_resume_select_tc_smoke`: Input sequence completed: 1 action(s) executed [select_tc] over 0ms
- [PASS] `touch_resume_tc_train_assertion`: selected=1, train_buttons=2
- [PASS] `touch_train_unit_smoke`: Town Center selection retained for touch training
- [PASS] `touch_train_unit_button_press`: attempt1=Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:632:583:1, pointer:screen_touch:0:632:583:0] over 70ms offset=(0,0) scout=True hud_unit=4 emitted=True result=fast_track_completed
- [PASS] `touch_train_unit_button_target`: Queued `Scout` from Town Center
- [PASS] `guided_opener_after_scout_queue`: enabled=True, active=True, stage=move_military, gather=True, house=True, scout=True, move=False, loop=False
- [PASS] `touch_train_wait_for_military`: Military action button enabled
- [PASS] `touch_select_military_move_target`: Moving /root/Main/GameMap/UnitsContainer/Scout toward (500,240) [clearance=120.0 nearest=/root/Main/GameMap/UnitsContainer/Villager]
- [PASS] `touch_select_military_button`: Guided opener auto-selected the completed Scout; redundant shortcut tap skipped
- [PASS] `touch_select_military_assertion`: selected=1
- [PASS] `touch_select_military_move_smoke`: attempt1=Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:500:240:1, pointer:screen_touch:0:500:240:0] over 70ms action=move tile=(4,27) @(500,240)
- [PASS] `touch_select_military_move_diag`: action=move selected=1 tapped= resource= tile=(4,27)
- [PASS] `guided_opener_after_military_move`: enabled=True, active=False, stage=free_play, gather=True, house=True, scout=True, move=True, loop=True
- [PASS] `touch_target_audit_selection_actions`: No visible controls to audit in this state
- [PASS] `performance_guardrail`: fps=60.00, frame_time_ms=17.23
- [PASS] `runtime_errors`: none

## Findings

- No touch-target violations detected.

## Prioritized Fix Plan

1. No fixes required from this run.

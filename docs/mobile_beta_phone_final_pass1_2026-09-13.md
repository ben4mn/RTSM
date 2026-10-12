# Mobile UX Touch Audit Report

Date (UTC): 2026-09-13T11:54:07.028001+00:00
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
- [PASS] `main_menu_contract`: diagnostics ready (difficulty=Easy guided_opening=True logical=844x474 input_scale=1.517x1.519)
- [PASS] `touch_target_audit_main_menu`: 6 controls meet target/aspect constraints
- [PASS] `main_menu_guided_opening_enabled`: Guided opener was already enabled in main-menu diagnostics
- [PASS] `main_menu_settings_open`: attempt1=Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:804:559:1, pointer:screen_touch:0:804:559:0] over 70ms open=True
- [PASS] `touch_target_audit_main_menu_settings`: 4 controls meet target/aspect constraints
- [PASS] `main_menu_settings_close`: attempt1=Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:640:550:1, pointer:screen_touch:0:640:550:0] over 70ms closed=True
- [PASS] `main_menu_seed_entry`: Entered deterministic seed 424242 through touch/text input
- [PASS] `main_menu_touch_start_smoke`: transitioned after 1 tap(s); tap1: Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:497:559:1, pointer:screen_touch:0:497:559:0] over 70ms
- [PASS] `startup_to_gameplay`: screen=1280x720, transitioned via touch
- [PASS] `camera_mobile_framing`: zoom=1.049 (mobile_min=0.78 mobile_max=1.90 desktop_default=1.35)
- [PASS] `hud_phone_layout_profiles`: 844x390[w=109.7,h=48.0,cols=3], 932x430[w=116.0,h=48.0,cols=3]
- [PASS] `touch_target_audit_hud_core`: 4 controls meet target/aspect constraints
- [PASS] `touch_target_audit_minimap_region`: 2 controls meet target/aspect constraints
- [PASS] `touch_select_move_smoke`: Input sequence completed: 4 action(s) executed [pointer:screen_touch:0:640:360:1, pointer:screen_touch:0:640:360:0, pointer:screen_touch:0:819:417:1, pointer:screen_touch:0:819:417:0] over 330ms
- [PASS] `guided_opener_initial_stage`: enabled=True, active=True, stage=gather_food, gather=False, house=False, scout=False, move=False, loop=False
- [PASS] `touch_select_villager_for_gather`: candidate1[/root/Main/GameMap/UnitsContainer/@Area2D@393]=attempt1=Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:376:576:1, pointer:screen_touch:0:376:576:0] over 70ms action=select path=/root/Main/GameMap/UnitsContainer/@Area2D@393 tapped_dist=13.3251333236694 resource= resource_dist=-1 radii=(22.882967659601,26.6967956028678) zoom=1.04881501197815 timestamp=9105>8623 @(376,576)
- [PASS] `touch_select_villager_target`: Tapped villager /root/Main/GameMap/UnitsContainer/@Area2D@393 at (247,379)
- [PASS] `touch_select_villager_assertion`: selected=1
- [PASS] `touch_villager_gather_smoke`: attempt1=Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:663:210:1, pointer:screen_touch:0:663:210:0] over 70ms action=gather path=/root/Main/GameMap/ResourcesContainer/@Area2D@230 tapped_dist=-1 resource=/root/Main/GameMap/ResourcesContainer/@Area2D@230 resource_dist=0.253334015607834 radii=(22.882967659601,26.6967956028678) zoom=1.04881501197815 timestamp=9503>9105 @(663,210)
- [PASS] `touch_villager_gather_target`: Tapped resource node /root/Main/GameMap/ResourcesContainer/@Area2D@230 at (663,210)
- [PASS] `guided_opener_after_gather`: enabled=True, active=True, stage=build_house, gather=True, house=False, scout=False, move=False, loop=False
- [PASS] `touch_open_build_menu_for_audit`: Build menu opened from touch input
- [PASS] `touch_target_audit_build_menu`: 13 controls meet target/aspect constraints
- [PASS] `touch_build_menu_house_option`: Selected `House +10p`
- [PASS] `touch_build_place_cancel_smoke`: arm=Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:511:606:1, pointer:screen_touch:0:511:606:0] over 70ms cancel=Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:1178:504:1, pointer:screen_touch:0:1178:504:0] over 70ms placement_active=False cancel_visible=False buildings=1->1
- [PASS] `touch_build_menu_close_after_cancel`: Build menu closed after cancel-path verification
- [PASS] `touch_camera_drag_responsive_0`: Input sequence completed: 3 action(s) executed [pointer:screen_touch:0:947:432:1, pointer:screen_drag:0:512:288:-435:-144, pointer:screen_touch:0:512:288:0] over 190ms
- [PASS] `touch_camera_drag_responsive_1`: Input sequence completed: 3 action(s) executed [pointer:screen_touch:0:435:417:1, pointer:screen_drag:0:870:259:435:-158, pointer:screen_touch:0:870:259:0] over 190ms
- [PASS] `touch_camera_drag_responsive`: camera drag deltas: 363.9, 372.7
- [PASS] `touch_pinch_zoom_out_smoke`: Input sequence completed: 6 action(s) executed [pointer:screen_touch:0:560:360:1, pointer:screen_touch:1:720:360:1, pointer:screen_drag:0:490:360:-70:0, pointer:screen_drag:1:790:360:70:0, pointer:screen_touch:0:490:360:0, pointer:screen_touch:1:790:360:0] over 220ms
- [PASS] `touch_pinch_zoom_in_smoke`: Input sequence completed: 6 action(s) executed [pointer:screen_touch:0:490:360:1, pointer:screen_touch:1:790:360:1, pointer:screen_drag:0:560:360:70:0, pointer:screen_drag:1:720:360:-70:0, pointer:screen_touch:0:560:360:0, pointer:screen_touch:1:720:360:0] over 220ms
- [PASS] `touch_pinch_zoom_validation`: before=1.049 out=1.900 in=1.013
- [PASS] `touch_minimap_geometry`: rect=(12,526)-(194,708) size=182x182
- [PASS] `touch_minimap_reposition_smoke_0`: Input sequence completed: 3 action(s) executed [pointer:screen_touch:0:52:667:1, pointer:screen_drag:0:153:566:101:-101, pointer:screen_touch:0:153:566:0] over 190ms
- [PASS] `touch_minimap_camera_delta`: touch(idx=0)=1434.4
- [PASS] `progression_hint_validation`: Tap Build, then House.
- [PASS] `touch_build_recenter_on_tc`: Input sequence completed: 2 action(s) executed [select_tc, center_selection] over 120ms
- [PASS] `touch_build_option_arm_placement`: Placement mode activated
- [PASS] `touch_build_menu_close_after_place`: Build menu closed after placement
- [PASS] `touch_build_place_resume_economy_smoke`: placed at 793,503; attempt1=invalid@844,417(Invalid placement), attempt2=invalid@435,417(Blocked terrain), attempt3=placed@793,503; resume_select=attempt1=Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:616:244:1, pointer:screen_touch:0:616:244:0] over 70ms selected=1 @(616,244) | resume_gather=attempt1=Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:810:239:1, pointer:screen_touch:0:810:239:0] over 70ms action=gather path=/root/Main/GameMap/ResourcesContainer/@Area2D@216 tapped_dist=-1 resource=/root/Main/GameMap/ResourcesContainer/@Area2D@216 resource_dist=0.303292661905289 radii=(23.6842080372855,27.6315760434998) zoom=1.01333343982697 timestamp=19015>18722 @(810,239)
- [PASS] `guided_opener_after_house`: enabled=True, active=True, stage=train_scout, gather=True, house=True, scout=False, move=False, loop=False
- [PASS] `touch_pause_open_for_audit`: Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:1147:39:1, pointer:screen_touch:0:1147:39:0] over 70ms
- [PASS] `touch_target_audit_pause_controls`: 4 controls meet target/aspect constraints
- [PASS] `touch_pause_resume_after_audit`: Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:640:298:1, pointer:screen_touch:0:640:298:0] over 70ms
- [PASS] `touch_pause_resume_state`: Game resumed after pause-controls audit
- [PASS] `touch_resume_select_tc_smoke`: Input sequence completed: 1 action(s) executed [select_tc] over 0ms
- [PASS] `touch_resume_tc_train_assertion`: selected=1, train_buttons=2
- [PASS] `touch_train_unit_smoke`: Town Center selection retained for touch training
- [PASS] `touch_train_unit_button_press`: attempt1=Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:723:653:1, pointer:screen_touch:0:723:653:0] over 70ms center=(723,653) offset=(0,0) scout=True hud_unit=4 emitted=True result=fast_track_completed
- [PASS] `touch_train_unit_button_target`: Queued `Scout` from Town Center
- [PASS] `train_feedback_success_contract`: result=fast_track_completed feedback=''
- [PASS] `guided_opener_after_scout_queue`: enabled=True, active=True, stage=move_military, gather=True, house=True, scout=True, move=False, loop=False
- [PASS] `touch_train_wait_for_military`: Military action button enabled
- [PASS] `touch_select_military_move_target`: Moving /root/Main/GameMap/UnitsContainer/Scout toward (825,217) [clearance=115.0 nearest=/root/Main/GameMap/UnitsContainer/Scout hud=clear]
- [PASS] `touch_select_military_button`: Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:1002:504:1, pointer:screen_touch:0:1002:504:0] over 70ms
- [PASS] `touch_select_military_assertion`: invocations=0->1 timestamp=0->45025 selected=1 live_selected=1 military=1 paths=['/root/Main/GameMap/UnitsContainer/Scout']
- [PASS] `touch_long_press_context_smoke`: Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:825:217:1, pointer:screen_touch:0:825:217:0] over 700ms action=Move action_id=100 timestamp=45725>0 executions=0->1 selected=1 target=(825,217) [clearance=115.0 nearest=/root/Main/GameMap/UnitsContainer/Scout hud=clear]
- [PASS] `touch_select_military_move_smoke`: attempt1=Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:825:217:1, pointer:screen_touch:0:825:217:0] over 70ms action=move tile=(9,27) timestamp=46590>19015 @(825,217)
- [PASS] `touch_select_military_move_diag`: action=move selected=1 tapped=/root/Main/GameMap/UnitsContainer/Scout resource= tile=(9,27)
- [PASS] `guided_opener_after_military_move`: enabled=True, active=False, stage=free_play, gather=True, house=True, scout=True, move=True, loop=True
- [PASS] `touch_target_audit_selection_actions`: No visible controls to audit in this state
- [PASS] `performance_guardrail`: fps=119.00, frame_time_ms=9.77
- [PASS] `runtime_errors`: none

## Findings

- No touch-target violations detected.

## Prioritized Fix Plan

1. No fixes required from this run.

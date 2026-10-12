# Mobile UX Touch Audit Report

Date (UTC): 2026-09-13T01:53:41.805183+00:00
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
- [PASS] `main_menu_contract`: diagnostics ready (difficulty=Medium guided_opening=True logical=844x474 input_scale=1.259x1.262)
- [PASS] `touch_target_audit_main_menu`: 6 controls meet target/aspect constraints
- [PASS] `main_menu_guided_opening_enabled`: Guided opener was already enabled in main-menu diagnostics
- [PASS] `main_menu_settings_open`: attempt1=Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:668:464:1, pointer:screen_touch:0:668:464:0] over 70ms open=True
- [PASS] `touch_target_audit_main_menu_settings`: 4 controls meet target/aspect constraints
- [PASS] `main_menu_settings_close`: attempt1=Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:532:457:1, pointer:screen_touch:0:532:457:0] over 70ms closed=True
- [PASS] `main_menu_seed_entry`: Entered deterministic seed 424242 through touch/text input
- [PASS] `main_menu_touch_start_smoke`: transitioned after 1 tap(s); tap1: Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:413:464:1, pointer:screen_touch:0:413:464:0] over 70ms
- [PASS] `startup_to_gameplay`: screen=1063x598, transitioned via touch
- [PASS] `camera_mobile_framing`: zoom=1.049 (mobile_min=0.78 mobile_max=1.90 desktop_default=1.35)
- [PASS] `hud_phone_layout_profiles`: 844x390[w=109.7,h=48.0,cols=3], 932x430[w=116.0,h=48.0,cols=3]
- [PASS] `touch_target_audit_hud_core`: 4 controls meet target/aspect constraints
- [PASS] `touch_target_audit_minimap_region`: 2 controls meet target/aspect constraints
- [PASS] `touch_select_move_smoke`: Input sequence completed: 4 action(s) executed [pointer:screen_touch:0:531:299:1, pointer:screen_touch:0:531:299:0, pointer:screen_touch:0:680:346:1, pointer:screen_touch:0:680:346:0] over 330ms
- [PASS] `guided_opener_initial_stage`: enabled=True, active=True, stage=gather_food, gather=False, house=False, scout=False, move=False, loop=False
- [PASS] `touch_select_villager_for_gather`: candidate1[/root/Main/GameMap/UnitsContainer/@Area2D@397]=attempt1=Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:267:457:1, pointer:screen_touch:0:267:457:0] over 70ms action=ignored path= tapped_dist=-1 resource= resource_dist=-1 radii=(22.882967659601,26.6967956028678) zoom=1.04881501197815 timestamp=8523>8103 @(267,457) | candidate2[/root/Main/GameMap/UnitsContainer/Villager]=attempt1=Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:186:272:1, pointer:screen_touch:0:186:272:0] over 70ms action=ignored path= tapped_dist=-1 resource= resource_dist=-1 radii=(22.882967659601,26.6967956028678) zoom=1.04881501197815 timestamp=9843>8523 @(186,272) | candidate3[/root/Main/GameMap/UnitsContainer/@Area2D@396]=attempt1=Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:278:266:1, pointer:screen_touch:0:278:266:0] over 70ms action=select path=/root/Main/GameMap/UnitsContainer/@Area2D@396 tapped_dist=10.7903919219971 resource= resource_dist=-1 radii=(22.882967659601,26.6967956028678) zoom=1.04881501197815 timestamp=11139>9843 @(278,266)
- [PASS] `touch_select_villager_target`: Tapped villager /root/Main/GameMap/UnitsContainer/@Area2D@396 at (220,210)
- [PASS] `touch_select_villager_assertion`: selected=1
- [PASS] `touch_villager_gather_smoke`: attempt1=Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:551:174:1, pointer:screen_touch:0:551:174:0] over 70ms action=gather path=/root/Main/GameMap/ResourcesContainer/@Area2D@230 tapped_dist=-1 resource=/root/Main/GameMap/ResourcesContainer/@Area2D@230 resource_dist=0.368285655975342 radii=(22.882967659601,26.6967956028678) zoom=1.04881501197815 timestamp=11536>11139 @(551,174)
- [PASS] `touch_villager_gather_target`: Tapped resource node /root/Main/GameMap/ResourcesContainer/@Area2D@230 at (551,174)
- [PASS] `guided_opener_after_gather`: enabled=True, active=True, stage=build_house, gather=True, house=False, scout=False, move=False, loop=False
- [PASS] `touch_open_build_menu_for_audit`: Build menu opened from touch input
- [PASS] `touch_target_audit_build_menu`: 13 controls meet target/aspect constraints
- [PASS] `touch_build_menu_house_option`: Selected `House +10p`
- [PASS] `touch_build_place_cancel_smoke`: arm=Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:424:503:1, pointer:screen_touch:0:424:503:0] over 70ms cancel=Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:979:419:1, pointer:screen_touch:0:979:419:0] over 70ms placement_active=False cancel_visible=False buildings=1->1
- [PASS] `touch_build_menu_close_after_cancel`: Build menu closed after cancel-path verification
- [PASS] `touch_camera_drag_responsive_0`: Input sequence completed: 3 action(s) executed [pointer:screen_touch:0:786:358:1, pointer:screen_drag:0:425:239:-361:-119, pointer:screen_touch:0:425:239:0] over 190ms
- [PASS] `touch_camera_drag_responsive_1`: Input sequence completed: 3 action(s) executed [pointer:screen_touch:0:361:346:1, pointer:screen_drag:0:722:215:361:-131, pointer:screen_touch:0:722:215:0] over 190ms
- [PASS] `touch_camera_drag_responsive`: camera drag deltas: 363.2, 372.3
- [PASS] `touch_pinch_zoom_out_smoke`: Input sequence completed: 6 action(s) executed [pointer:screen_touch:0:451:299:1, pointer:screen_touch:1:611:299:1, pointer:screen_drag:0:381:299:-70:0, pointer:screen_drag:1:681:299:70:0, pointer:screen_touch:0:381:299:0, pointer:screen_touch:1:681:299:0] over 220ms
- [PASS] `touch_pinch_zoom_in_smoke`: Input sequence completed: 6 action(s) executed [pointer:screen_touch:0:381:299:1, pointer:screen_touch:1:681:299:1, pointer:screen_drag:0:451:299:70:0, pointer:screen_drag:1:611:299:-70:0, pointer:screen_touch:0:451:299:0, pointer:screen_touch:1:611:299:0] over 220ms
- [PASS] `touch_pinch_zoom_validation`: before=1.049 out=1.900 in=1.013
- [PASS] `touch_minimap_geometry`: rect=(10,437)-(161,588) size=151x151
- [PASS] `touch_minimap_reposition_smoke_0`: Input sequence completed: 3 action(s) executed [pointer:screen_touch:0:43:554:1, pointer:screen_drag:0:127:470:84:-84, pointer:screen_touch:0:127:470:0] over 190ms
- [PASS] `touch_minimap_camera_delta`: touch(idx=0)=1433.7
- [PASS] `progression_hint_validation`: Tap Build, then House.
- [PASS] `touch_build_recenter_on_tc`: Input sequence completed: 2 action(s) executed [select_tc, center_selection] over 120ms
- [PASS] `touch_build_option_arm_placement`: Placement mode activated
- [PASS] `touch_build_menu_close_after_place`: Build menu closed after placement
- [PASS] `touch_build_place_resume_economy_smoke`: placed at 659,418; attempt1=invalid@701,346(Invalid placement), attempt2=invalid@361,346(Blocked terrain), attempt3=placed@659,418; resume_select=attempt1=Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:510:191:1, pointer:screen_touch:0:510:191:0] over 70ms selected=1 @(510,191) | resume_gather=attempt1=Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:672:199:1, pointer:screen_touch:0:672:199:0] over 70ms action=gather path=/root/Main/GameMap/ResourcesContainer/@Area2D@216 tapped_dist=-1 resource=/root/Main/GameMap/ResourcesContainer/@Area2D@216 resource_dist=0.361218124628067 radii=(23.6842080372855,27.6315760434998) zoom=1.01333343982697 timestamp=20723>20427 @(672,199)
- [PASS] `guided_opener_after_house`: enabled=True, active=True, stage=train_scout, gather=True, house=True, scout=False, move=False, loop=False
- [PASS] `touch_pause_open_for_audit`: Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:952:33:1, pointer:screen_touch:0:952:33:0] over 70ms
- [PASS] `touch_target_audit_pause_controls`: 4 controls meet target/aspect constraints
- [PASS] `touch_pause_resume_after_audit`: Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:532:247:1, pointer:screen_touch:0:532:247:0] over 70ms
- [PASS] `touch_pause_resume_state`: Game resumed after pause-controls audit
- [PASS] `touch_resume_select_tc_smoke`: Input sequence completed: 1 action(s) executed [select_tc] over 0ms
- [PASS] `touch_resume_tc_train_assertion`: selected=1, train_buttons=2
- [PASS] `touch_train_unit_smoke`: Town Center selection retained for touch training
- [PASS] `touch_train_unit_button_press`: attempt1=Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:651:536:1, pointer:screen_touch:0:651:536:0] over 70ms center=(651,536) offset=(0,0) scout=True hud_unit=4 emitted=True result=fast_track_completed
- [PASS] `touch_train_unit_button_target`: Queued `Scout` from Town Center
- [PASS] `train_feedback_success_contract`: result=fast_track_completed feedback=''
- [PASS] `guided_opener_after_scout_queue`: enabled=True, active=True, stage=move_military, gather=True, house=True, scout=True, move=False, loop=False
- [PASS] `touch_train_wait_for_military`: Military action button enabled
- [PASS] `touch_select_military_move_target`: Moving /root/Main/GameMap/UnitsContainer/Scout toward (392,179) [clearance=204.0 nearest=/root/Main/GameMap/ResourcesContainer/@Area2D@228 hud=clear]
- [PASS] `touch_select_military_button`: Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:833:419:1, pointer:screen_touch:0:833:419:0] over 70ms
- [PASS] `touch_select_military_assertion`: invocations=0->1 timestamp=0->43438 selected=1 live_selected=1 military=1 paths=['/root/Main/GameMap/UnitsContainer/Scout']
- [PASS] `touch_long_press_context_smoke`: Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:392:179:1, pointer:screen_touch:0:392:179:0] over 700ms action=Move action_id=100 timestamp=44064>0 executions=0->1 selected=1 target=(392,179) [clearance=204.0 nearest=/root/Main/GameMap/ResourcesContainer/@Area2D@228 hud=clear]
- [PASS] `touch_select_military_move_smoke`: attempt1=Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:392:179:1, pointer:screen_touch:0:392:179:0] over 70ms action=move tile=(5,28) timestamp=44946>20723 @(392,179)
- [PASS] `touch_select_military_move_diag`: action=move selected=1 tapped= resource= tile=(5,28)
- [PASS] `guided_opener_after_military_move`: enabled=True, active=False, stage=free_play, gather=True, house=True, scout=True, move=True, loop=True
- [PASS] `touch_target_audit_selection_actions`: No visible controls to audit in this state
- [PASS] `performance_guardrail`: fps=917.00, frame_time_ms=8.90
- [PASS] `runtime_errors`: none

## Findings

- No touch-target violations detected.

## Prioritized Fix Plan

1. No fixes required from this run.

# Mobile UX Touch Audit Report

Date (UTC): 2026-09-13T05:04:26.619372+00:00
Status: **FAIL**

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
- [PASS] `touch_select_villager_for_gather`: candidate1[/root/Main/GameMap/UnitsContainer/Villager]=attempt1=Input sequence completed: 2 action(s) executed [pointer:screen_touch:0:275:455:1, pointer:screen_touch:0:275:455:0] over 70ms action=select path=/root/Main/GameMap/UnitsContainer/Villager tapped_dist=15.5327196121216 resource= resource_dist=-1 radii=(22.882967659601,26.6967956028678) zoom=1.04881501197815 timestamp=9050>8547 @(275,455)
- [PASS] `touch_select_villager_target`: Tapped villager /root/Main/GameMap/UnitsContainer/Villager at (181,299)
- [PASS] `touch_select_villager_assertion`: selected=1
- [FAIL] `touch_villager_gather_smoke`: No visible resource target found after selecting villager

## Findings

- No touch-target violations detected.

## Prioritized Fix Plan

1. [P0] `runtime check diagnostics` -> `touch_villager_gather_smoke`: Resolve the failed runtime contract and rerun the phone audit (No visible resource target found after selecting villager)

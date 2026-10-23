# Research and age information — 2026-10-22

Source review found that recruitment Info read base `UnitData` values while selected-unit combat numbers used live player upgrades. After Forge Weapons or Scale Mail, those two views could disagree; Loom also changed the health of existing and newly trained Villagers without appearing in recruitment Info. Recruitment now consumes the shared `Combat.get_effective_unit_type_stats()` helper, retaining the existing cost, time, range, role and availability information. The separate combat progression matrix checks the shared calculations.

The Castle Age preview also treated every unit from a newly buildable producer as a new recruit. Extra Town Centers become buildable in Castle Age, but the starting Town Center can already train Villagers and Scouts. The preview now filters those opening roles, while retaining the Town Center building unlock and Siege Engine recruitment. Age advancement spends the displayed cost and applies immediately; it unlocks buildings and recruitment without automatically increasing unit HP, Attack or Armor.

Age Up now uses the established hold-inspection control. Town Center selection Info provides the same cost/effect description through a tap, including when hold shortcuts are disabled. Blacksmith cards reuse their detailed research explanation for hover and accessibility, and their Info reports Ready, Researched or the actual resource deficit. The compact Blacksmith purpose mentions both unit and worker upgrades. Detailed effect scopes and immediate, one-time timing live in `TechData.details`; short research card labels and purchase rules stay unchanged.

The Scout attack-move tooltip now qualifies that armed units fight along the route. Scout rejection feedback and its selection Info are checked by `tools/test_scout_order_feedback.tscn` at a fixed 844×390 SubViewport. Native runs save three rejection views plus Info top/bottom and an evidence receipt under `output/polish-2026-10-22/scout-orders`. The fixture creates its units, reveals fog and disables simulation; these are UI checks, not ordinary-game evidence.

`tools/test_technology_information.tscn` is a synthetic HUD fixture with funded, real paid age/research transactions. It checks research-to-recruit stat consistency, Scout zero attack after Forge, upgrade completion/shortage text, correct age unlocks, a hold that spends nothing versus a short tap that advances once, and tap Info geometry. Native runs save 844×390 images under `output/polish-2026-10-22/technology-info`. Both fixtures preserve the prior preference-file bytes.

The same fixture covers the new one-worker Farm capacity description before purchase and during selection. Local owned Farms report whether a worker is assigned, including travel/drop-off; online replicas and enemy Farms show capacity without claiming reservation knowledge. Farm and Blacksmith Info omit production-cancel instructions because those buildings have no training queue. The compact Build card line count and size remain unchanged; detailed capacity appears in hover/Info.

Headless validation passed in an isolated working-tree stage after the native baseline performance run released the engine slot:

- `test_scout_order_feedback`: direct rejected-attack notices, tap selection Info, scrolling and safe 844×390 geometry.
- `test_technology_information`: paid upgrade stats, Scout zero attack, research scope/status, age unlocks, hold versus tap, and local/online Farm descriptions.
- Existing `test_hud_hold_control`, `test_build_menu_mobile_layout` (12 phone profiles), and `test_touch_train_button_input` regressions.
- `test_mobile_iteration_readability`: 12 phone profiles plus 632-pixel shelf and 550-pixel resource-rail stress; all six units' names, roles, queue badges, retained costs and viewport input ownership.

The readability test's synthetic full-queue producers previously supplied visual queue rows without initializing their actual capabilities or queue. Its fixture now supplies both and checks the visible `Queue full` blocker plus complete hover/accessibility costs, matching the compact blocked-card behavior. This was a test correction; it did not change production behavior.

Logs and the initial working-tree stage manifest are under `output/polish-2026-10-22/ui-check-stage/`. The repaired readability test was copied into that UI-only stage before its successful rerun, so the initial manifest is not a claim that the later test-file bytes are frozen. There were no new runtime errors or warnings in these runs, and `git diff --check` passed. Native image inspection remains pending the root agent's integrated slot. Synthetic UI evidence does not measure ordinary-match balance, device display performance, or multiplayer synchronization.

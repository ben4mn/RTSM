# Multiplayer and command-table redesign — 23 October 2026

This pass began at `9cca520`, preserving the recent gameplay fixes. It replaces the menu/setup journey and shared visual system, adds host-selected private multiplayer rooms, and fixes three independently reproduced network defects. The original reported exit cannot be identified conclusively from retained production logs.

## Concrete fixes

- A 5.6-second client polling delay could expire Godot's native heartbeat before reading a queued Pong. The redundant native heartbeat is disabled; application keepalive and monotonic wall-time deadlines now govern both endpoints.
- A delayed client could lose the final result when the authority destroyed finished sockets after two seconds. Terminal messages now receive an acknowledgement, with a bounded fallback for legacy clients.
- UI references to deleted network replicas could fail at typed argument boundaries before their validity checks. The command helpers now validate untrusted references before accessing them.
- Web updates are deferred throughout a live or waiting lobby and while Settings is open. Closing Settings restores the owning screen's safety state.

Exact red/green reproductions, deployed-service inspection, protocol behavior and limits: [multiplayer investigation](multiplayer_stability_2026-10-23.md). Disconnect/resume within the same match remains unsupported; recovery returns players to the menu and a new room.

## New Game and presentation

Home now leads to one New Game screen containing Solo/Multiplayer, three generated terrain previews, meaningful map descriptions and a persistent selected-map/Start footer. Hosts choose the battlefield in a private room; guests receive the same choice from the authority. Quick match explicitly lets the server choose. Settings contains application preferences only. Results → New game returns to the corresponding creation flow.

The reusable theme uses navy surfaces, parchment text, antique gold actions, Cinzel headings and Barlow body text. Controls use consistent borders, focus states and spacing. Everyday HUD commands have visible captions; selected-unit/building information, construction cards, recruitment, research, pause and results share the same hierarchy. Redundant HUD labels were removed. The research review exposed two unreachable upgrades; four compact cards now fit and accept paid pointer purchases. Desktop review also caught clipped Town Center Repeat/queue controls and overflowing identity text; measured page widths, compact typography and guarded scroll restoration now keep those controls readable through refreshes.

| Surface | Before | Accepted native rendering |
| --- | --- | --- |
| Home | [baseline](images/new-game-menu-before-20261023.png) | [desktop](images/new-game-desktop-01-home-20261023.png) |
| Game creation | Map choice was in Settings | [desktop](images/new-game-desktop-02-solo-map1-20261023.png), [phone](images/new-game-phone-02-solo-map1-20261023.png) |
| Multiplayer | Random search only | [create/join](images/new-game-phone-03-online-20261023.png), [shared guest map](images/new-game-phone-max-05-guest-lobby-20261023.png) |
| Construction | [baseline](images/hud-construction-before-20261023.png) | [phone](images/hud-construction-phone-20261023.png) |
| Match controls | Existing visual baseline retained in raw evidence | [desktop HUD](images/hud-desktop-20261023.png), [recruitment](images/hud-recruitment-phone-20261023.png), [research](images/hud-research-phone-max-20261023.png), [pause](images/hud-pause-phone-20261023.png), [results](images/hud-results-phone-max-20261023.png) |
| Town Center and placement | Desktop review exposed clipped controls; an earlier fixture mislabeled blocked ground | [recruit/Repeat](images/hud-tc-desktop-20261023.png), [queue](images/hud-queue-desktop-20261023.png), [production-validated green preview](images/hud-placement-phone-20261023.png) |

The menu capture contains 40 native views. The final HUD capture contains 33 settled states plus three queue pages at desktop and phone window sizes, including maximum scaling and simulated safe areas. HUD captures use disclosed synthetic banks/queues/armies to stress layout; lobby presentation captures model room states. Actual multiplayer evidence is recorded separately below. No physical-phone testing is claimed. Official reference links, design reasoning and detailed interaction coverage are in [New Game design](new_game_design_2026-10-23.md).

A final direct native mouse/keyboard walkthrough on the final frozen runtime also passes: Home → New Game → normal skirmish; H/Q spends50food and trains a Villager; B → House → green ground spends50wood, completes construction and raises population cap15→25; gathering/deposits continue; P → Main menu returns Home. It uses private copied preferences and ordinary gameplay, with zero engine messages. Its action/launch/log receipt is included in the UI archive. Two preferences left by an earlier interrupted fixture were restored from the same-day baseline; subsequent tests use private data.

## Verification

The focused network suite passes all thirteen processes, 34 room checks and nine catalog combinations. Three immediate-exit fixtures retain baseline ObjectDB shutdown warnings; native acceptance requires clean logs. The Web menu/update guard passes 57 checks. Menu layout passes 396 assertions; twelve actual ScreenTouch menu-to-generated-map journeys cover every map. Research passes 490 checks, including previously failing Wheelbarrow/Loom bounds and purchases. HUD composition passes thirteen phone/scale/safe-area profiles. Recruitment, construction, pointer routing, strategy pages, information, audio/preferences and all four result/menu scenarios pass their relevant regressions.

All ten [gameplay preservation suites](gameplay_preservation_2026-10-23.md) pass with zero engine errors/warnings. They cover Farm ownership, delivery endpoints, paid perimeter construction, clearance, crowds, AI defense assembly, actual freed combat targets and paid combat progression. Core unit, villager and AI sources retain the accepted gameplay hashes.

River has completed with an ordinary Sacred Site victory at 868.20 game seconds and 869.25 wall seconds. Both native clients passed the paid gameplay gates, agreed the result and returned through the actual Menu button, with zero engine errors/warnings. Its original runner flag remains false because the manifest was taken before editor-generated UID metadata; an independent audit proves every recorded source unchanged and only six UID files added before launch, and explicitly accepts the functional run. The recorder now establishes its baseline after import.

Plains also completes through the ordinary Sacred Site timer: 848.19 game seconds, 862.76 wall seconds, all gameplay gates and both menu returns passed, identical result/world state, zero engine messages and unchanged frozen sources. No unfinished foundations remained at its last observed gameplay snapshot. Both completed maps reached Castle and all four technologies; their normal paid House demolition/rebuild exercises building destruction rather than claiming an enemy Town Center kill.

The final native abrupt-disconnect pair passes on the corrected transport: after 35 seconds the host receives `Opponent disconnected`, the guest receives `Connection lost`, and both return to an idle menu. Both frozen sources and all three process logs are clean. Lobby leave/rejoin is separately supported and tested; resuming the disconnected live match is unsupported.

Woodland completes the sustained requirement: **1,839.08 real-time seconds (30:39) at 1×**, 1,800.00 game seconds, then the ordinary time-limit draw. Both clients pass every gameplay gate, agree the result and world state, and return to an idle menu. Sources remain unchanged; server and both client logs contain zero engine errors/warnings. These are two actual native applications per pair with a separate local authority, using scripted ordinary paid commands rather than resource grants, injected damage or accelerated play.

Failed and partial runs remain recorded in [the observer report](multiplayer_native_harness_2026-10-23.md); they do not count toward the sustained requirement. One earlier Woodland session ended after 17 minutes through a macOS window-close request and clean exit; its remaining client correctly received the opponent-disconnect result. The input origin is unknown. The accepted retry records passive close/focus and exit events. All accepted pairs share the final transport/gameplay code; the last Town Center presentation correction has its separate final-source layout, purchase and native-render evidence.

The isolated Apple M4/Metal debug-build battle sample passes its validity gates with no competing Godot processes, visible/focused window, ordinary paid roster and 1× sampling. Across 1,797 frames (29.996 wall seconds), the whole-sample render-completion p95 is 17.08ms. Dense active combat contributes 460 frames/7.68 seconds, p95 17.09ms, maximum 54.22ms; the whole sample has three frames above33.33ms. Established dense fighting has no frames above33.33ms. This is one desktop844×390 diagnostic, not display FPS, GPU duration, physical-phone/Web performance or a controlled improvement claim. [Full frames, ledgers and isolation receipts](evidence/redesign-performance-20261023.json.gz).

The complete [native multiplayer archive](evidence/multiplayer-native-20261023.json.gz) preserves original reports, independent audits, raw actions/snapshots/logs, source receipts and screenshot hashes, including failed and partial runs. Woodland alone compares 1,673 shared ticks, 26,848 actor fields and 2,207 shared resource values with no disagreement. See actual [late Woodland play](images/multiplayer-woodland-late-native-20261023.png), [Woodland result](images/multiplayer-woodland-draw-phone-native-20261023.png) and [Plains result](images/multiplayer-plains-host-result-native-20261023.png).

Other receipts: [UI](evidence/redesign-ui-20261023.json.gz), [desktop production](evidence/desktop-production-shelf-20261023.json.gz), [research red/green](evidence/research-shelf-20261023.json.gz), [menu](evidence/new-game-design-20261023.json.gz), [focused network](evidence/multiplayer-focused-20261023.json.gz), [gameplay](evidence/gameplay-preservation-20261023.json.gz). Expanded native evidence is under `output/multiplayer-native-2026-10-23/`.

## Publication and remaining limits

The frontend and server were subsequently deployed together on 23 October, followed by beta.10 browser footer and beta.11 first-show layout corrections; see the [live deployment and browser verification](live_deployment_2026-10-23.md). The native checks above are distinct from that public-site verification. Neither establishes a second machine, physical-device behavior or competitive balance. The local postflight receipt at `output/redesign-2026-10-23/publication.json` records the original runtime commit, verified remote HEAD, checkout status and native main-menu restart.

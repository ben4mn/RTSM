# Overnight iteration — 22 October 2026

The user approved several hours of build–play–review work, GitHub checkpoints and public deployments. The first company/battlefield release is live: clean runtime `334fd81a70fb`, source `8e935c1ce9aef037f622f3be9f7ff3a26b2d0e8311b21f63ecdad3af3693b386`. See the company and Debian deployment receipts for verification and rollback.

The thread heartbeat `improve-pocket-kingdoms-overnight` runs every 45 minutes, up to six wakeups. Work ends at **2026-10-22 07:00 UTC** (02:00 America/Chicago): finish or safely checkpoint the current iteration, push, leave Git clean, record what is live and disable the heartbeat. The local host must remain available.

## First priorities

1. The user's actual phone capture has side and bottom bands. The shell currently shrinks the whole canvas with CSS safe-area insets. Fill the visual viewport with the canvas/background, and pass the browser's safe bounds to Godot controls once. Preserve notch and home-indicator clearance. Verify DPR, UI scale, asymmetric insets, orientation and menu-to-match transitions.
2. Easy is too hard for a new player. Compare a repeatable slower paid player policy across all three maps, then adjust Easy-only pressure and recovery. Preserve Medium/Hard and honest costs; bot fixtures do not establish human balance.
3. Create original Town Center, House and Barracks art that belongs with the company cast. Preserve building gameplay geometry and production. Review at actual phone scale and verify building selection/placement.

Root owns the web/layout bridge and deployment; networking agent owns Easy and its policy fixtures; economy agent owns the three building assets/mappings; movement agent owns independent safe-area tests and audit. Isolate preferences and avoid concurrent performance measurements. Keep current delivery docs separate from these edits, and commit only reviewed source.

## Evidence discipline

Distinguish native desktop renders, fixed-step simulations, browser touch emulation and the user's physical-phone image. Record failures and remaining limitations. The current public match tests have exited; check for real active connections before replacing the authoritative service.

## First iteration — implementation and verification

The phone canvas now fills the visual viewport, with safe-area clearance applied to controls. The final shell passed 80 Chromium/WebKit geometry cases, 24 pure bridge checks and 18 artifact checks. The actual exported game passed a Retina touch journey at Extra Large UI, including paid Villager/Repeat, a live notch-side reversal, Pause and return to menu. See [phone edges](phone_edges_2026-10-22.md).

Original Town Center, House and Barracks silhouettes now share the company's materials and identity, with separate clay enemy fabrics. Geometry, costs and production are preserved; native phone-scale selection, construction and authoritative replica checks passed. See [building art](company_buildings_2026-10-22.md). The local real two-client suite passed strategy, lifecycle, paid economy and replicated combat with no runtime errors; four subprocesses retained nonfatal ObjectDB cleanup warnings. Evidence is in `output/overnight-online-local/`.

The final Easy source adds a longer opening, smaller combined field force, 45-second regroup after a casualty, and delayed Sacred pressure, while retaining immediate home defense. The six final paid comparisons moved the slower learner from four losses and two unresolved matches to six wins in 625.5–750.0 seconds; see [Easy learning](easy_learning_2026-10-22.md). These slow-policy bot matches are calibration evidence, not a substitute for new-player playtesting.

### Candidates for the next wakeup

- Improve guide/panel priority: the opening-guide banner remains partially visible behind the Economy panel in the actual web game. Verify modal guidance hides cleanly and returns at the correct step.
- Extend the original building vocabulary to Resource Camp, Archery Range and Stable, prioritizing readability at phone scale. Preserve selection bounds and gameplay geometry.
- Run contrasting paid attack plans on the three tactical maps; inspect readable contact, retreat and counterplay rather than adding mechanics without evidence.
- Keep performance evidence scoped to the actual machine/browser. The phone edge fix still needs the user's physical-phone confirmation.

## First iteration published

Live at https://game.4mn.org as `0.2.0-beta.3`, clean runtime `ca46ddbfb13f`, staged source `29fa2b41ff71e53e776584b82220836febc8fbb6f6dcb39b0b205d0d9076dff3`, published `2026-10-22T03:27:05Z`. Two independent exports match. Public payloads, headers and private-path denial pass; the live Retina touch journey includes paid Villager/Repeat, reversing the cutout insets during play, and returning through Pause to the menu. Game and online containers restarted; diagnostics and tunnel were preserved. See [deployment receipt](debian_game_deployment.md) for rollback.

The current source is frozen for this release. Continue the next bounded iteration from the candidate list above. The heartbeat remains active through the agreed 07:00 UTC cutoff; `caffeinate -i -t 14800`, started around 02:53 UTC, keeps the host awake until approximately that deadline. Do not extend the overnight window automatically.

Public WSS verification also passed all ten checks against the deployed match server: two strategy clients; connection-failure, loading-ended, loading-failure and lifecycle checks; two paid economy clients; and two paid combat clients. Both players verified paid Barracks/infantry, attack-move, visible enemies and replicated damage. There were no runtime errors; four subprocesses emitted nonfatal ObjectDB exit warnings. All test clients closed and source hashes remained unchanged. Evidence: `output/overnight-online-public/source-receipt.json` and sibling logs.

## Second iteration — company in the field

The new Builder hat/mallet, Warrior shield and copper-haired Archer now match the menu identities at battlefield scale. Original Resource Camp, Archery Range and Stable art extends the architecture, with neutral materials and teal/clay ownership. Unit collision, production, building footprints and combat/economy rules are preserved. Native selection, pose, construction/paid production and actual snapshot-adapter tests pass; see the two art receipts.

Opening guidance now hides while management/modal surfaces own the screen and returns at its current step. Two urgent raid cards remain reachable beside Economy/Army, and one tap closes management and focuses the threat without clearing selection. Four actual touch journeys and 36 geometry/capture views pass. The final integrated native screenshots and actual exported-browser phone views were inspected. See [field integration](company_field_2026-10-22.md).

The paid tactical tool compares 15 controlled engagements across the three maps, including same-roster direct and staged cavalry attacks. A staging order prevents the fast units arriving alone and materially improves survival in this fixture. No combat-stat change is bundled into this art/UI release. The [separate tactical receipt](paid_tactical_plans_2026-10-22.md) records its deliberate staging, paid-roster setup, limits and acquisition-boundary discovery.


### Second iteration published

Live at https://game.4mn.org as `0.2.0-beta.4`: clean runtime `0a45f90e90b8`, staged source `10c7d4300daf36231b33b13dc1c01f1f55c0739e73854b21dde8458ba8f0e6a0`, publication `2026-10-22T03:56:30Z`. Both clean exports match. All 40 public payloads and 13 private-path denials pass. The fresh public phone-size browser journey verifies management guidance, a 50-food Villager purchase and completed training, Pause and return to menu, with zero console errors. The public WSS suite passes all ten cases, including paid economy and replicated combat; four existing ObjectDB cleanup warnings remain. All clients are closed and the server has zero established match connections.

The match server was idle before replacement; its image is `sha256:adbc5272c30c607c7e4e5299539c59b3256a2e6081987a0847097d321d0f049e`. Game and match containers restarted; diagnostics stayed healthy and the tunnel kept its original start. Rollback remains beta.3's `releases/29fa2b41-room-to-learn-20261022` and image `sha256:7ebc695cf8cf45043695cf769eb4ed3ce37249c7955c3e8c9d043c778fe3a015`. See [deployment](debian_game_deployment.md) for exact receipts. The heartbeat remains active until the agreed 07:00 UTC cutoff.

### Next bounded iteration

- Add a restrained mixed-army staging tip or practice step using the same-roster tactical evidence. Preserve manual timing and selection decisions; do not silently slow Horsemen.
- Investigate the documented Stand Ground scan/engagement mismatch at 88/89/96 units. If fixed, align acquisition to existing reach, preserve explicit orders and no-chase behavior, and compare focused combat fixtures before deployment.
- Continue original architecture with Blacksmith/Siege Workshop if readability and gameplay priorities leave time. Review all further art at actual phone scale.
- Evaluate remaining ordinary-toast/overlay conflicts and guidance highlight tint separately. No claim that all UI overlaps or every dense formation is solved.
- Stop iterations at 07:00 UTC, publish/checkpoint verified work, leave Git clean, write the morning handoff and disable this heartbeat. Physical-phone and new-player human confirmation remain outstanding.


## Third iteration — fieldcraft

Army gains an opt-in Info page with three concrete tactics, grounded in the same-roster staging comparison. It preserves selection and returns directly to groups. Twelve native touch/typography profiles, four guide/raid-priority journeys and the full paid management journey pass. An obsolete flat-button assertion was updated to check the already-published custom plate textures; production theme code was not changed.

A reproduced Stand Ground false acquisition/ignore cycle delayed guards against inward-moving enemies. The narrow UnitBase change bounds both automatic acquisition paths to existing stationary reach, preserving no-chase, weapon damage/reach, direct orders and advancing attack-move/patrol. All 146 focused assertions pass; an independent review found no intent/priority/fog defect. All fifteen paired paid engagements preserve their openings and first damage with zero navigation failures/stalls/unanswered orders, while later damage and survival change. The three slower-learner Easy matches remain paid Sacred wins in 670.67–703.13s, with no economic bonus or worker/Town Center damage. This supports the fix without claiming balance-neutral outcomes or human certification. See the paired regression receipt.

Original Blacksmith and Siege Workshop art completes eight main building families. Geometry and costs remain fixed; native phone art/selection, adapter ownership and paid construction/research/Siege production pass. See [fieldcraft](fieldcraft_2026-10-22.md), [Stand Ground](stand_ground_2026-10-22.md) and [industry art](company_industry_2026-10-22.md).

### Candidates after fieldcraft

- Bring resources into the company materials: moss foliage, readable berry clusters, neutral stone with ochre gold seams. Tree alpha currently determines canopy picking (`ResourceNode.is_sprite_body_hit`); preserve the alpha footprint for a material pass, or explicitly verify overlap/hit masks before changing silhouette. Check depletion/fog and worker/enemy selection at zoom 0.65/0.952/1.6.
- Reduce conspicuous grass-diamond contrast and inspect actual river crossings before choosing shoreline treatments. Neighbor-derived atlas variants should be selected during terrain construction, without per-frame nodes or navigation changes. Verify identical map/path hashes and all crossing routes.
- Keep ordinary-toast/management overlap and guide-highlight tint as a separate modest UI scope.

### Third iteration published

Live at https://game.4mn.org as `0.2.0-beta.5`, clean runtime `84d61799b4c4c4638efff7a1b0f7b3915ed70090`, staged source `5d19e1065840d122da78ba0876ba0f55fcd14cf5691bbc28eda90460e7a653b6`, published `2026-10-22T04:38:03Z`. The new Army Info page, guard acquisition correction, Blacksmith and Siege Workshop are included. Two independent exports match; all 40 public payloads and 13 private-path checks pass. Fresh public 844×390 DPR3 touch emulation confirms Extra Large/asymmetric-safe-area Info/Back/Close, guide restoration, Pause and menu return with zero console errors. Two software-renderer readback warnings remain.

The final integrated public WSS suite passes all ten cases in one invocation, including paid production, Stand Ground on inert owner-remapped replicas and authoritative combat. Zero runtime errors; three nonfatal ObjectDB shutdown warnings remain. All frozen source hashes match, all clients are closed and zero established match connections remain. The server was idle before replacement. Game and match containers restarted; diagnostics stayed healthy and the tunnel kept its original start. New online image: `sha256:912fabdd1754a4a94bcc714fc843fe75182a8925988a5277a611c480e13f6f70`. Rollback is beta.4 `releases/10c7d430-company-field-20261022` with image `sha256:adbc5272c30c607c7e4e5299539c59b3256a2e6081987a0847097d321d0f049e`. Exact receipts are linked in [deployment](debian_game_deployment.md).

The heartbeat remains active for the agreed window. Next pass should select a modest resource-material/terrain-readability or toast-priority scope from the candidates above, preserve gameplay picking/pathing and repeat phone/gameplay checks. Do not extend work beyond 07:00 UTC. Physical-phone confirmation, human beginner playtesting and broad all-seed balance remain outstanding.

## Fourth iteration — read the ground

Resource presentation uses a shared palette-only material on the existing Kenney textures, preserving alpha and tree-canopy picking; new fruit clusters clarify food. Terrain gains restrained water-edge atlas variants and softer meadow variation without changing map generation or routing. Independent checks preserve nine paired map/path records and six paired resource replication cases exactly. Both native resource renderers, sixteen paired terrain views and the integrated four-profile native touch journey pass. The local ten-case online suite and three map-catalog pairings pass; three existing exit cleanup warnings remain.

HUD now exclusively controls ordinary-toast visibility beneath management and modal sheets, preserving existing lifetimes and the separate raid lane. The real input fixture also reproduces double callback invocation from native contacts plus Godot's emulated pointer; the handler now consumes the duplicate and canceled touches. Forty baseline failures become zero across four native phone profiles. Existing guide/raid, secondary-surface and Army notes checks pass. See [read the ground](read_the_ground_2026-10-22.md).


The actual browser River Crossings seed 101 opening used a normally purchased Scout. It held Sacred at 3:25 but was gone by 6:58, with enemy capture at 90%; no uncontested Scout win was observed. This partial game ended through Pause after seven minutes. It is a useful next-pass scenario, with exact counterattack timing still to measure. Browser Extra Large/asymmetric-safe-area rendering, normal paid production, movement and menu return pass. The development static server's missing POST handler produces expected 501 diagnostics messages; there are no engine errors. No Easy tuning is bundled into this presentation release.


### Fourth iteration published

Live at https://game.4mn.org as `0.2.0-beta.6`, clean runtime `c61918e45853a086cbdbcc99b860a0decdf1c402`, staged source `efeaba3c86f81f7637997de0bf71b86028ace1f5eedabaae08e335aa87c19ef9`, publication `2026-10-22T05:24:55Z`. Two independent exports match; 40 public payloads and 13 private-path checks pass. All ten public WSS cases pass with no runtime errors and four existing cleanup warnings. All clients closed; server postflight has zero match connections/errors. Six changed runtime/shader files match the running image. Game/match containers restarted after an idle check; collector stayed healthy and tunnel unchanged. Online image `sha256:89f64accb0569bd623bcba50b54ebf17841775553bade6cdfb9c6935a886d7a8`; beta.5 rollback is preserved. See [deployment](debian_game_deployment.md).

Fresh public phone-size Extra Large/asymmetric-safe-area browser checks pass, including exact paid Scout cost, rally movement, Army notes, Sacred result and menu return. Zero console errors; two readback warnings. Crucially, this earlier Scout opening **wins at 4:30 without combat**. The isolated immediate-purchase probe wins at 233.45s on all three maps / seed 101, while paid AI troops remain staged behind the 300s objective gate. The later preview opening's loss did not rule this out.

### Next bounded iteration

Separate Easy's reactive Sacred response from its five-minute base-raid grace. Test a modest 150s response against the exact paid Scout opening, leaving neutral initiative 390s, regroup 45s, squad caps, production and costs unchanged. Compare earlier/delayed claims and paid reinforcements on multiple seeds; rerun slower-learner and Medium/Hard controls before release. The goal is an objective fight that rewards reinforcement without making the base opening harsher. Keep all edits isolated by owner and retain baseline evidence. Continue only until 07:00 UTC, then checkpoint/push/clean, write morning handoff and disable heartbeat.


## Fifth iteration — hold the site

A normally purchased Scout claims at 53.45s and wins at 233.45s on all three seed 101 maps, without damage or an AI contest. The opponent sees it around 42s and has three paid Warriors by 102–114s, but the same 300s gate suppresses both recon and fighter responses. Public phone-size browser play independently reproduces the late-purchase version: Scout bought at 36s, Sacred held around 91s and victory at 4:30 with no losses.

The candidate separates a 150s reactive objective gate from base raids 300s and neutral initiative 390s. Both recon and fighter paths share the condition; regroup 45s, force caps, home defense, costs and production remain. Independent earlier/delayed/reinforced paid openings and slower-learner/Medium/Hard controls verify the candidate. Three slower learners still win with paid recovery and no worker/TC/home-area damage; the two Medium/Hard controls match full behavior exactly. The visible-site badge also clears so it no longer covers the fighting units, returning when current vision is lost. Sixteen old native pixel occlusion failures become zero across four phone profiles. A separate paid native observer contests at 172.78s and prevents the former 233.45s automatic win. The exported Extra Large/notched touch journey observes the readable Scout and its later loss, restored fog badge and safe menu return. See [hold the site](hold_the_site_2026-10-22.md) and its linked paid matrix/independent receipts. This supports a limited strategic response without certifying human beginner balance or mobile hardware performance.


### Fifth iteration published

Live at https://game.4mn.org as `0.2.0-beta.7`, clean runtime `2ab5c416cd4c9d7a3d65b39c46dda5cc1f51e9c1`, staged source `9daf824730f954187ab94ab21af12067ec1114d2273b0e85aef3f7e6c0fc6976`, publication `2026-10-22T05:54:06Z`. Two independent exports match. All 40 public payloads and 13 private-path checks pass. Fresh public Extra Large/notched touch play verifies paid Scout rally, visible units, contest/loss by 3:05, fog badge restoration, no former automatic win by 4:20, and Pause/menu return. Zero browser errors; two readback warnings.

All ten exact-commit public WSS cases pass, including paid economy and both replicated combat clients. All 1,278 tracked hashes remain unchanged. Zero runtime errors; three existing cleanup warnings. All clients are closed and postflight has no match connections/errors. Three changed runtime files match the running image. Game/match containers restarted after the idle check; collector healthy and tunnel unchanged. Online image `sha256:2c59171b8d146495746fa9c4e907b960a46ebd32d8369d10db85a3840600ea0e`. Beta.6 rollback and prior server context are retained. See [deployment](debian_game_deployment.md).

### Final bounded investigation

After the public suite and all browser/test clients close, measure one native paid mixed-army engagement with fixed camera/viewport, real-time samples and crowded active frames reported separately. Keep sampling isolated from other Godot workloads, exclude added fixture screenshots/I/O during measurement, retain normal runtime behavior and private preferences, and inspect before/after native captures. Make no optimization without repeatable evidence. This is desktop native evidence, not physical-phone or Web GPU certification. Finish/checkpoint by 07:00 UTC; push, leave Git clean, write the morning handoff and disable the heartbeat.


## Sixth iteration — find your fighters

The final isolated native encounter used normal resources to field twelve mixed troops per side, plus ten workers each. One focused 29.80-second desktop sample passed its validity gates: 3,510 render-completion intervals, no interval over 33.33ms, and 6.856 seconds of dense active combat. Earlier runs with a freed-reference observer error or unavailable window focus were rejected. This is one Mac debug-build diagnostic, not display FPS, a browser or physical-phone benchmark, and it does not justify a performance or balance change. See [native battle receipt](dense_battle_native_2026-10-22.md).

A separate visual review found that the selected Scout could disappear behind nearby fighters. The candidate adds small hollow foot brackets on the existing foreground route overlay, only for living selected own units in current vision. It retains the normal sprite depth and touch controls, respects Clear player markers, and keeps its size through zoom. Native raster checks caught antialiasing at the inner tips; the tips were shortened to preserve a clear center without relaxing the assertion. The final fixture passes 188 native and 148 headless assertions across four phone/scale profiles and three zooms. The old source fails 88 native and 76 headless assertions in the same fixture. The existing command-route regression also passes. See [selection clarity](selected_unit_cues_2026-10-22.md). Publication receipts follow below after the final checks.

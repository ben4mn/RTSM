# Pocket Kingdoms recovery handoff October 24 2026

This checkpoint preserves the work from the interrupted chat **Improve Pocket Kingdoms gameplay**. The owner requested publication and a game restart, then a stop while they decide whether to continue development.

## Latest checkpoint: beta4 presentation candidate

The owner subsequently authorized a bounded modern menu pass, then extended the same miniature art direction to all eighteen unit sprites and thirty building sprites across Crownlands, Verdant League and Sunstride Clans. This supersedes the initial stop point above for that presentation work only.

Beta3 was activated successfully from `d7291a7ccff1b1b9fcb5acbd02391a04ed7f8d3c`. The preserved activation receipt is `/home/ben/aoem/deployment-backups/v030b3-d7291a7ccff1-17cb39668a-2b97b2f1e7/activation.json`. Main and the recovery documentation were pushed at `17ffb1a`. The older staged-only descriptions below record the recovery's starting state; they are not the current publication state.

The current candidate is `0.3.0-beta.4`, still protocol 3. It refreshes the menu and browser welcome page with a shared miniature village illustration, clearer headings and panels, and a new castle icon. Civilization-specific art is shared by battlefield units/buildings, recruitment portraits, building cards and construction previews. The presentation catalog covers six unit roles and ten building roles for each kingdom. See [the miniature art record](kingdom_miniatures_2026-10-24.md) for coverage, asset provenance and limits.

The focused kingdom-art validation reported **1,178 passing checks**. This is not a completed release or multiplayer acceptance result. **Beta4 publication is pending:** append the final committed source, canonical/reproduced artifact verification, Linux smoke result, activation/restart receipt and public checks after they complete. Until that evidence is recorded, beta3 remains the last confirmed published release.

Combat statistics, costs, collision footprints, victory timing and protocol remain unchanged. The late idle-browser error remains open, and the rejected pacing/protocol experiments below remain excluded. After this authorized presentation checkpoint is pushed, deployed, restarted and checked, report the result before expanding development further.

## Source and publication

- Repository: https://github.com/ben4mn/RTSM
- Game: https://game.4mn.org/
- Release source: `d7291a7ccff1b1b9fcb5acbd02391a04ed7f8d3c`, version `0.3.0-beta.3`, protocol 3.
- Recovery starts with the candidate already pushed on `codex/mobile-controls-beta3-20261024`. Main has now been fast-forwarded to that source; this documentation checkpoint will be pushed separately.
- At recovery start, beta2 remained live and beta3 was staged but not activated. The publication result will be appended after the guarded switch and health checks.

## Included changes

The overnight work introduced three playable kingdoms with different economic and military incentives, signature units, clearer recruitment and rally controls, idle-worker cues, observed counter advice, compact mixed-army approach movement, and compact-map access to Siege Workshops. Standard Sacred victory requires an armed owner unit inside the ring; leaving pauses its existing 180-second clock. Scouts and workers can still capture or contest. Control race is unchanged.

Beta3 adds these four focused improvements over the live beta2 build:

1. Building-placement feedback explains when the whole footprint must be visible (`20c7f41`).
2. Town Center recruitment controls reconcile their actual size and position after layout changes (`a119ffe`).
3. Find space suggests a currently visible on-screen construction preview; explicit Place still validates and pays normally (`dde1665`).
4. A browser recovery notice offers Save log, Reload game and Dismiss after an error (`dfe103a`). Reload leaves the match. Error stacks are retained with bounds.

The release does not alter beta2's victory timing, unit costs, AI balance or network protocol. Detailed development evidence is in [Three Kingdoms](three_kingdoms_2026-10-24.md).

## Validation and known issues

The candidate's canonical and reproduced Web exports agree. Its source/manifests were checked, and an isolated Linux server smoke verified 839 runtime files. Focused Find space, fog, recruitment-layout and recovery tests passed, including rendered touch interactions. The Town Center regression passed 848 assertions. These establish narrower behavior than a complete multiplayer acceptance pass.

**The late idle-browser failure remains open.** The earlier beta2 public pair finished normally, then both clients reported `RangeError: Invalid array length` and could not return to the menu. A later beta3 local pair reached the server's 30-minute draw; both clients subsequently reproduced the error. Retained beta3 stacks identify `Object.genObject` and `_emscripten_glGenBuffers` in the generated Web runtime. This narrows investigation to the WebGL allocation path but does not establish the underlying leak or engine defect. Beta3's recovery panel is a mitigation, not a fix. No full all-session acceptance pass is claimed.

The recovered beta3 pair has no final analysis or cleanup receipt. Its original logs and terminal records remain intact. The ordinary solo30 playthrough was also interrupted; it cannot establish pacing or a construction defect. A suspected unfinished Farm was not confirmed: source review found active builders excluded from new automatic assignments, and the screenshot could show finished Farm art. Investigate actual worker/building state before changing construction logic.

A passive idle comparison ended on a test process-monitor failure before its 150-minute goal. It must not be counted as a 150-minute pass. Native Chromium touch emulation is not physical-phone testing, and scripted multiplayer duration is not a human pacing average.

## Rejected pacing experiments

The six-minute Standard scoring delay was tested in four fixed paid-policy comparisons:

| Case | Existing rule | Six-minute delay |
| --- | --- | --- |
| Woodland 101 Medium | 7:19 | 9:50 |
| Plains 101 Medium | 8:58 | 10:16 |
| River 202 Medium | 8:28 | 9:42 |
| Woodland 424242 Hard | 10:39 | Unresolved at 20:00 |

The extra fighting did not justify the new long tail. The 360-second rule, its protocol 4 contract and associated tooling remain private and unshipped. A separate late-economy experiment also extended an 18:28 control past an unresolved 20-minute cap and was not adopted. Do not accidentally merge either prototype into this release.

## Next work after owner approval

1. Diagnose the late WebGL buffer-allocation failure using the retained beta3 stacks and a bounded reproduction. Track actual buffer/object growth and browser memory; distinguish game, engine and harness causes. Keep recovery available while the cause is investigated.
2. Run concise real-phone checks for build placement, Find space, recruitment, selection, rotation/background pause, reload and menu return. Preserve any reproducible control defect before attempting a fix.
3. Improve the player's ability to recover after losing an army: sustained food, timely counter recruitment and a response that reaches the Site. Confirm the problem in attentive play before adjusting balance.
4. Measure a small, declared set of ordinary games against the roughly 11-minute target, with an average up to 14 and 20 exceptional. Do not pool unattended, scripted acceptance and human play as one pacing sample.
5. At each completed checkpoint, update this handoff, commit/push, publish the matching build, restart only the dedicated game service after checking active matches, and verify it. Keep work bounded and report usage before expanding scope.

## Local recovery locations

These are development paths, not files served by the game:

- Main checkout: `C:/Users/ben4m/Documents/Codex/2026-10-23/i-am-x20/work/RTSM`.
- Previous workspace: `C:/Users/ben4m/Documents/Codex/2026-10-23/yo/work`.
- Chronological notes: `SESSION.md` in that workspace.
- Candidate checkout: `beta3-release-worktree`.
- Sealed artifacts: `beta3-release-worktree/build/beta3-d7291a7ccff1-web`, its reproduced build, and the server context referenced by `beta3-d7291a7ccff1-builds`.
- Retained failure: `beta3-d7291a7-local-touch-attempt1/host-console.jsonl`, `guest-console.jsonl`, and both terminal records.
- Interrupted solo: `beta3-d7291a7-root-touch-solo30-v3-20261024`; read-only Farm review: `solo30-farm-readonly-source-review.json`.
- Rejected experiment: `opening-phase-experiment-20c7/final-decision.json` and the private protocol 4 sources. Preserve rather than promote.

## Deployment recovery

The staged release is `v030b3-d7291a7ccff1-17cb39668a-2b97b2f1e7`. Its Web manifest SHA-256 is `17cb39668ac5ae2931bee858456923c5ddc5f8238fa4a200022ec1b4d784ea33`; server manifest is `2b97b2f1e72f9a698143ab34ffd549a48645661d80584762eb7cd543b70d33f4`.

Use the already-reviewed guarded deployment helper and matching request, not a new ad hoc deployment. It verifies the live identity, closed manifests, matching image, rollback preservation and port-9080 sockets before replacing only the online service and switching the static release. Its immediate socket check still has a small admission race. Keep the unrelated proxy, diagnostics and tunnel intact. See [deployment operations](debian_game_deployment.md).

Do not rerun an activation after an uncertain outcome. Read its receipt and current live state first. The prior beta2 static release and image must remain available for rollback.

# AOEM Closed-Beta Roadmap

Last audited: August 1, 2026

## Executive Status

AOEM is a playable 1v1 mobile-first RTS with a deterministic automated opening loop. Gate 0 is green; the project is not yet beta-ready because first-session manual evidence, full-match quality, real-device performance, and packaging remain incomplete.

Current evidence:

- Godot `4.6.stable` headless boot: clean.
- `python3 tools/mcp_smoke_test.py`: **PASS (18/18) twice consecutively** on August 1, 2026, including the 75-second simulation, production, touch, patrol, attack-move, clean runtime logs, and 60 FPS checks.
- `python3 tools/mcp_phone_playability.py`: **PASS (60/60) twice consecutively** on August 1, 2026 with seed `424242`, including gather -> House -> Scout -> touch move -> free play.
- Gate 0 fixes now use engine-side target snapshots, detailed hit/action/queue diagnostics, immediate removal of stale build-menu controls, safe deferred deletion of rebuilt train controls, explicit military-count readiness, guided Scout focus, and sticky touch camera mode that disables desktop edge-scroll conflicts after touch input.
- The current worktree was clean before this audit. The latest checkpoint was `f4681de` (`Harden deterministic phone gate seed entry`).

Release posture: **Gate 0 passed; Gate 1 first-session UX and manual phone evidence are next.**

## What The Reference Target Teaches

Age of Empires II screenshots were used as composition and readability references, not as assets or a UI template. The useful transferable principles are:

- Keep the battlefield dominant; persistent chrome should be compact and predictable.
- Put economy state in one quickly scannable band and contextual actions in one stable command surface.
- Make selection unmistakable through team color, silhouettes, health/state feedback, and a context panel.
- Use the minimap as a strategic instrument: ownership, explored space, threats, and objectives should read at a glance.
- Build maps from recognizable resource clusters, landmarks, roads/clearings, and defensible spaces so terrain communicates strategic choices.
- Layer feedback: immediate click/tap acknowledgement, visible command destination, unit response, alerts, and concise event history.

AOEM should preserve its own mobile layout, art direction, names, assets, and interaction model. The goal is comparable strategic clarity, not visual imitation.

Reference pages reviewed:

- [Age of Empires II: Definitive Edition — official franchise page](https://www.ageofempires.com/games/aoeiide/)
- [Age of Empires II: Definitive Edition — Steam screenshots](https://store.steampowered.com/app/813780/Age_of_Empires_II_Definitive_Edition/)

## Beta Scope

Ship one polished offline skirmish experience:

- Human player `0` versus AI player `1` on the current mobile duel map.
- Gather -> population growth -> construction -> age advancement -> mixed army -> exploration -> combat/objective -> victory or defeat.
- Touch-first controls, with mouse/keyboard retained as secondary input.
- Easy, Medium, and Hard AI that differ in pressure and forgiveness without obvious unfairness.
- Main menu, pause/restart, match summary, settings/preferences, and tester-ready Web package.

Explicitly out of scope for this beta:

- Multiplayer, campaigns, civilizations/factions, ranked/social systems, monetization, cloud save, replays, and broad content expansion.
- A wholesale art replacement. Targeted readability and feedback improvements are in scope.

## Gate 0 — Make Validation Trustworthy (P0, 1–3 days)

Status: **PASSED on August 1, 2026.** Both authoritative gates passed twice consecutively from clean test runs. The latest generated phone report is `60/60` with clean runtime logs and the complete guided opener.

Goal: make the test result describe the game reliably instead of cursor/bridge luck.

Work:

1. Reproduce both current phone failures independently:
   - intended villager tap resolves as `select_resource`;
   - first guided Scout move pointer sequence times out after Scout selection.
2. Separate game defects from MCP bridge defects with runtime diagnostics for pointer receipt, hit candidates, chosen target, selection result, command issue, and command acknowledgement.
3. Make target discovery stable after camera/minimap movement. Reject stale/offscreen coordinates and require that the chosen point resolves to the expected node before issuing the next step.
4. Remove hidden test coupling to scene timing. Await explicit map-ready, selection-changed, building-completed, production-completed, and command-issued state.
5. Add a small deterministic regression for overlapping unit/resource hit areas; gameplay must prefer a directly tapped selectable unit when the audit requests that unit.
6. Ensure every failure writes its seed, camera transform, target paths/rects, last runtime action, screenshot, and debug output.

Exit gate:

- Smoke gate passes twice consecutively.
- Phone gate passes twice consecutively from clean editor sessions with seed `424242`.
- No timeout is treated as a pass or “automation only” without a manual reproduction result.
- Reports contain enough evidence to diagnose a future failure without rerunning blindly.

## Gate 1 — First Two Minutes On A Phone (P0, 3–5 days)

Status: **IN PROGRESS.** The displayed working title is now `Pocket Kingdoms` instead of a protected franchise name. A touch-tested Help & Settings overlay documents core gestures and persists difficulty, guided opener, audio, camera speed, and text/UI scale through `user://preferences.cfg`; audio, camera movement, and window scaling consume those settings at runtime. The four-step opener now includes a compact 68×48 `Skip` control that restores the full HUD and saves the user's guidance choice. HUD/world target diagnostics refresh from settled layout on wall-clock intervals. Latest regression evidence is phone **PASS (63/63)** and smoke **PASS (18/18)** with clean logs.

Goal: a new tester can finish the opener without prior RTS knowledge.

Work:

1. Test at `844x390` and `932x430`, including safe areas and display scaling.
2. Turn the guided opener into four short, state-driven beats: gather food, place a House, train a Scout, move the Scout.
3. Highlight the next valid target/action without covering the battlefield; let players dismiss guidance and never trap them behind it.
4. Improve invalid tap, insufficient resource, population cap, blocked placement, unreachable target, and queue-full feedback.
5. Verify one-finger pan, pinch zoom, long press, minimap reposition, selection, command, build cancel, pause/resume, and restart do not compete for the same gesture.
6. Keep primary touch targets at least 48 px and prevent the resource bar, minimap, selection panel, and action strip from stealing world commands.
7. Add a small help/settings surface for controls, audio, guidance toggle, camera speed, and text/UI scale; persist preferences.

Exit gate:

- Five manual clean-start opener completions: at least two by someone who did not build the feature.
- Zero dead ends or unexplained taps in the four guided beats.
- Both automated gates remain green twice consecutively.

## Gate 2 — Complete And Satisfying Match Loop (P1, 1–2 weeks)

Goal: every match supports meaningful economic and military decisions through a clear ending.

Economy and progression:

- Verify reliable gather/drop-off for food, wood, gold, and stone under depletion, retargeting, construction interruption, and path obstruction.
- Surface idle villagers, task distribution, population pressure, production queues, age requirements, and upgrade effects without dense phone chrome.
- Tune the first 10 minutes around explicit pacing targets: first House, first military unit, age-up windows, first pressure, and expected match duration.
- Ensure farms, camps, houses, military production, defenses, and upgrades each have an understandable strategic role.

Combat and control:

- Validate mixed-group movement at 1, 8, 20, and population-cap scale; prevent clumping, oscillation, and unreachable-target stalls.
- Make move, attack-move, focus attack, patrol, stance change, damage, death, and objective capture visually distinct.
- Confirm melee, ranged, cavalry, siege, villagers, buildings, and towers acquire and lose targets correctly through fog and range changes.
- Add concise under-attack, production-complete, age-up, objective, and population alerts with minimap pings and spam control.

Victory and summary:

- Test sacred-site victory, enemy elimination, player defeat, pause, restart, and return-to-menu paths.
- Expand the summary to answer: why the match ended, duration, economy totals, units/buildings lost, army produced, age timing, and objective control.

Exit gate:

- Ten seeded full-match simulations finish without hangs or recurring runtime errors.
- Three manual phone-sized matches reach three different endings.
- Median Medium match duration and key timing targets are documented from telemetry, then judged acceptable for the intended compact RTS session.

## Gate 3 — AI That Is Legible And Replayable (P1, 4–7 days)

Goal: Easy teaches, Medium contests, and Hard pressures without merely receiving opaque bonuses.

Work:

1. Run the existing balance harness on all difficulties across at least five seeds each.
2. Track age times, villager count, idle economy time, building mix, army composition, first pressure, retreat/defense behavior, objective control, and match result.
3. Fix AI stalls: blocked construction, exhausted resources, population cap, production prerequisites, stranded attackers, and undefended base/objective states.
4. Differentiate difficulty primarily through decision cadence, scouting, composition, aggression, and recovery; clearly document any resource bonuses.
5. Add pressure windows and cooldowns so attacks feel intentional rather than a trickle or a single irreversible snowball.

Exit gate:

- No AI deadlocks across the seed matrix.
- Easy allows recovery, Medium contests the map, Hard creates earlier sustained pressure.
- AI can win by combat and can contest or win through the sacred objective.

## Gate 4 — Visual, Audio, And Accessibility Polish (P1/P2, 1 week)

Goal: improve strategic readability and perceived responsiveness without copying another game's art or UI.

Work in this order:

1. Battlefield readability: ownership/team color, selection rings, silhouettes, building footprints, resource identity, construction state, and health thresholds.
2. Command feedback: tap acknowledgement, destination/attack markers, rally/patrol visualization, placement validity, and minimap pings.
3. Hierarchy: keep battlefield dominant; consolidate economy, contextual selection, and actions into stable regions that survive phone aspect changes.
4. World composition: recognizable resource clusters and landmarks, readable paths/clearings, less repetitive terrain, and clear sacred-site prominence.
5. Audio: distinct selection/command/alert/combat/objective cues, sensible mixing, cooldowns, mute controls, and persistence.
6. Accessibility: UI scale, text contrast, color-plus-shape ownership cues, reduced camera motion option, independent music/SFX controls, and guidance toggle.

Exit gate:

- Every critical state remains understandable with audio muted.
- Team ownership and resource types remain distinguishable without relying on hue alone.
- No critical text truncation or overlap at both target phone profiles.
- A 20-minute session produces no alert/audio spam or persistent visual clutter.

## Gate 5 — Performance, Package, And External Test (P0 before invite, 3–5 days)

Goal: produce a reproducible tester build and a disciplined feedback loop.

Work:

1. Define performance budgets for target hardware: frame rate, frame time, memory, startup, and worst-case unit/building counts.
2. Profile fog updates, pathfinding, AI decisions, minimap drawing, VFX, and large battles on representative low/mid hardware or equivalent throttled profiles.
3. Validate Web export from a clean checkout; record Godot version, export template requirements, build command, output, and checksum/version label.
4. Add a beta README: installation/launch, controls, known issues, log location, screenshot/report steps, and reset/preferences instructions.
5. Create a 30-minute tester script covering menu, opener, age-up, construction, mixed army, objective, pause/restart, and game over.
6. Run a small internal alpha before broadening access; triage issues by crash/data loss, input blocker, progression blocker, major confusion, balance, and polish.

Exit gate:

- Clean package produced twice from documented steps.
- Manual checks pass on at least two phone-sized environments, including one constrained target.
- No P0/P1 known issues; remaining issues are documented with workarounds where relevant.
- Smoke and phone gates pass twice on the release candidate.
- One complete manual release-candidate match has clean logs and acceptable performance.

## Recommended Execution Order

| Order | Deliverable | Why now |
| --- | --- | --- |
| 1 | Deterministic touch gate | Current results cannot reliably distinguish game failures from automation failures. |
| 2 | First-session phone UX | The opener is the beta's acquisition funnel and current release blocker. |
| 3 | Full-match telemetry and pacing | Passing a two-minute opener does not prove the RTS loop is satisfying. |
| 4 | AI seed matrix | Replayability depends on pressure, recovery, and difficulty differentiation. |
| 5 | Readability/accessibility polish | Apply polish to stable mechanics and measured confusion points. |
| 6 | Packaging and internal alpha | Validate the exact build before inviting external testers. |

## Beta Go/No-Go Checklist

A beta invitation is allowed only when every item is true:

- [ ] Clean menu -> match -> game over -> menu loop.
- [ ] Guided touch opener completes gather -> House -> Scout -> Scout move.
- [ ] All resources gather/drop off; construction and production recover from interruptions.
- [ ] Mixed units can be selected, moved, attack-moved, focused, patrolled, and fought at scale.
- [ ] Easy/Medium/Hard AI build, expand, defend, pressure, attack, and contest objectives.
- [ ] Fog, minimap, alerts, sacred site, elimination, defeat, pause, restart, and summary are manually verified.
- [ ] No recurring runtime errors or known P0/P1 issues.
- [ ] Both MCP gates pass twice consecutively on the release candidate.
- [ ] Performance budgets pass in phone-sized and constrained testing.
- [ ] Export steps, tester instructions, known issues, and reporting workflow are complete.

## Next Coherent Implementation Cycle

1. Instrument pointer hit resolution and selection/command acknowledgement.
2. Reproduce and fix the `select_resource` result when the gate targets a villager.
3. Reproduce and fix the post-Scout pointer timeout.
4. Run smoke + phone twice from clean sessions.
5. Update the generated phone report and this status section with the exact results.
6. Commit only after the validation contract is deterministic and both gates are green.

## Source Of Truth

- This file defines beta sequence and exit criteria.
- `docs/mobile_ux_touch_report_2026-02-22.md` and its JSON companion contain the latest strict phone evidence (the legacy filename is retained by the test tool).
- Historical phase reports under `docs/` and `PHASED_CHANGES.md` provide context but do not override current gate results.
- Authoritative automated commands:
  - `python3 tools/mcp_smoke_test.py`
  - `python3 tools/mcp_phone_playability.py`

# AOEM Beta Launch Roadmap

Last validated: March 8, 2026

## Validated Current State

AOEM is already a functional RTS prototype with one complete 1v1 skirmish loop:

- Main menu -> skirmish -> game over -> return to menu
- Touch-capable unit selection, movement, gathering, build placement, and military shortcuts
- Economy, production queues, fog of war, sacred-site win condition, and AI opponent
- Mobile-focused 40x40 duel map with guided opener support and difficulty selection

Validation baseline from March 7-8, 2026:

- `python3 tools/mcp_smoke_test.py`: `PASS (18/18)`
- `python3 tools/mcp_phone_playability.py`: `PASS (60/60)` on March 8, 2026 with guided-opener stage checks still sourced from `/root/Main.first_session_diagnostics`
- Current observed result: the stricter phone audit no longer drifts on HUD inference and the touch-only opener loop now clears `gather -> House -> Scout -> move military` end to end

## Beta Definition And Launch Bar

Target: closed mobile beta for a polished single-mode skirmish experience.

The beta is ready when all of the following are true:

1. A first-time player can start a match from the main menu and complete the opening economy loop using touch only.
2. The first two minutes of play are reliable and legible on phone-sized layouts.
3. MCP smoke and phone-playability gates both pass against the current UI and gameplay contracts.
4. Runtime logs stay free of new recurring errors during startup, opening-loop play, and longer AI simulation.
5. The current AI, map, and onboarding flow produce a stable, understandable first-session experience.

## Non-Goals For Beta

These remain explicitly out of beta scope unless they block core usability:

- Full visual overhaul or final art pass
- Broad content expansion beyond the current skirmish roster
- Additional civilizations, campaigns, or extra game modes
- Multiplayer, replay systems, ranked/social features
- Monetization or live-ops systems
- Store-launch scale work beyond what is needed for a closed tester build

## Phase 1: Beta Foundation

Goal: remove blockers between the current prototype and a trustworthy closed mobile beta.

### Workstream A: Validation Truth

- Replace brittle menu-node assumptions in the phone audit with stable diagnostics exported by runtime UI scripts
- Harden regression gates for main-menu touch start, build-menu visibility, long-press context, pinch zoom, and touch-only opening flow
- Keep screenshot-backed reports as the source of truth for beta blockers

### Workstream B: First-Session UX

- Tighten main-menu setup clarity around difficulty, seed, and guided opener
- Improve guided-opener messaging so the first match teaches gather -> build -> train -> move
- Make pause/resume and failure feedback more obvious on touch devices

### Workstream C: Touch-Command Reliability

- Reduce ambiguity in touch selection and command feedback
- Ensure build-placement cancel and invalid-placement recovery are always reachable
- Resolve minimap and command-surface conflicts that can interrupt touch-only play

### Workstream D: Stability And Telemetry

- Keep runtime logs clean under startup, short-loop, and long-simulation tests
- Extend AI/economy telemetry so beta blockers can be diagnosed from automated runs
- Preserve current minimum guardrails for FPS and frame time

### Phase 1 Deliverable

A touch-complete, regression-covered opening loop that survives automated testing and is credible for external closed-beta testers.

## Phase 2: Match Quality And Retention

Goal: make the current skirmish mode worth replaying after the first successful session.

- Improve AI pressure pacing, scouting quality, and difficulty differentiation
- Tighten army readability, command feedback, and larger-group movement quality
- Refine onboarding prompts, alerts, event feed, and post-match summary usefulness
- Add higher-signal telemetry for balance tuning and tester issue triage

Phase 2 should improve match quality without widening feature scope.

## Phase 3: Beta Packaging And External Test Readiness

Goal: prepare the game and process for closed external distribution.

- Finalize tester checklist and go/no-go criteria
- Package a stable mobile-first build with known-device layout validation
- Document known issues, tester instructions, and bug-report expectations
- Triage remaining blockers from Phase 1-2 and convert non-blockers into post-beta backlog

## Wave 1 Inside Phase 1

Wave 1 is blocker-first and should land before broader polish work:

1. Repair the stale phone audit and align it to the current menu/HUD structure.
2. Guarantee that the first two minutes of play are touch-completable under MCP.
3. Publish a short blocker list tied directly to automated gates.
4. Use that blocker list to drive the next implementation batch instead of adding new feature scope.

## Post-Beta Backlog

These are valid roadmap items, but they are deferred until after the closed beta is stable:

- Full art, animation, VFX, and audio overhaul
- Larger map/content variety and additional civilizations
- New modes beyond the core skirmish loop
- Multiplayer architecture and social systems
- Monetization, cloud save, and public launch platform work

## Source Of Truth

- [roadmap.md](/Users/ben/Documents/1_Projects/aoem/roadmap.md) is the beta sequencing source of truth.
- Existing phase docs under `docs/` and [PHASED_CHANGES.md](/Users/ben/Documents/1_Projects/aoem/PHASED_CHANGES.md) remain useful historical references, but they no longer define beta order.
- The authoritative automated gates are:
  - `python3 tools/mcp_smoke_test.py`
  - `python3 tools/mcp_phone_playability.py`

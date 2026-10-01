# AOEM roadmap and release state

Status date: 2026-10-01

## October rough preview

The owner authorized publishing the current rough prototype at `https://game.4mn.org` on the existing Debian Docker/Nginx infrastructure. Deployment configuration is in `deploy/`; operational steps are in `docs/debian_game_deployment.md`. Phone selection, movement, placement multitouch, and standalone/fullscreen support include the October follow-up. Physical-phone retesting and balance approval remain open.

The September status and evidence below describe their historical checkpoint and private-beta process. Its earlier prohibition on public deployment is superseded by the October authorization.

## Historical September checkpoint

Target: private, production Web mobile beta for landscape phones

Current decision: **LOCALLY VERIFIED; INTERNAL TESTER HANDOFF NOT YET READY**

At that checkpoint, Pocket Kingdoms had a production-clean Web artifact and a complete local automated/browser evidence set. Its separate internal tester process still awaited a private HTTPS URL, host owner, tester-intake owner, test window, rollback contact/location, and private access method.

## Delivered product scope

- Touch-first landscape-phone setup, onboarding, selection, deselection, direct friendly-building reselection, contextual acknowledgement, and concise invalid-action feedback.
- Stable six-button Move / A-Move / Patrol / Stop / Stance / Clear command rail with separate Build, production, placement, pause, and game-over modes.
- One-finger pan, pinch zoom, minimap navigation, long-press context, safe-area-aware phone profiles, three UI scales, and 48-physical-pixel target enforcement.
- Resource gathering/drop-off, farms, construction, production reservation/cancellation/refund, research/age ownership, combat, sacred-site control, all endings, and menu-state normalization.
- Bounded navigation/repathing and unreachable-target recovery for autonomous unit work and combat behaviors.
- Fog-aware selection, commands, AI live vision/memory, and building placement legality.
- Fair AI economy with no Medium/Hard resource multiplier, deliberate sacred-site capture/defense, rebuilding, force policy, and multi-seed liveness coverage.
- Separate `Mobile Web Beta` export, source staging/exclusions, offline service worker, checksums, sensitive-material scan, and reproducible canonical/repro builds.

## Frozen candidate

| Field | Value |
| --- | --- |
| Product/version | Pocket Kingdoms `0.1.0-beta.1` |
| Revision | `89567778b26e` |
| Working tree | `dirty=true`; existing user changes intentionally preserved |
| Staged-source SHA-256 | `54ada2e25cdb3c0690ef37580039b78fbe3198be2f21597fccc703b4e6458fa5` |
| Godot | `4.6.stable.official.89cea1439` |
| Evidence manifest | `docs/mobile_beta_evidence_manifest_2026-09-13.json` — **PASS** |
| Canonical artifact | `build/mobile-web-beta/`, built `2026-09-13T12:05:38Z` |
| Canonical/repro PCK | both `e8cdc4467fcb41eb3f9fb1163d279a758a25d4b59ba76848fc53e2a61649e611` |

The build's closed 206-entry `SOURCE_SHA256SUMS.txt` is the runtime identity. Documentation and final audit records may change without changing that packaged source identity.

## Final local evidence ledger

| Gate | Result | Status |
| --- | --- | --- |
| Godot boot | Headless exit `0`, no parser/runtime failure | **PASS** |
| Focused regression | `46/46` | **PASS** |
| Python targeting / AI policy | `5/5` / `10/10` | **PASS** |
| Strict AI completion | Medium seed 202: technical/policy/completion `1/1/1`; Feudal `308.36s`; AI Sacred Site win `361s`; errors `0`; bonus `false` | **PASS** |
| AI matrix | 15/15 technical and policy clean; 10 supported AI Sacred Site endings; 5 explicitly horizon-complete nonterminal Easy runs; errors `0` | **PASS** |
| Clean phone simulations | pass 1 `66/66`; pass 2 `66/66`; no startup fallback; errors `0` | **PASS** |
| 75-second smoke | pass 1 `18/18`; pass 2 `18/18`; errors `0` | **PASS** |
| Web build/closure | canonical and repro builds exit `0`; both manifests close; 18/18 payload entries | **PASS** |
| Package inspection | staged exclusions and sensitive-material scan pass; full-key blocks, private URLs, localhost URLs, source maps, unexpected custom URLs: `0` | **PASS, scoped** |
| MIME | HTML/JS/WASM/PCK/service worker/manifest/PNG `7/7` | **PASS** |
| Browser `844x390` | 25 exact-size frames; full touch flow; Defeat `04:55`; console `0/0`; unexpected requests `0`; offline reload pass | **PASS** |
| Browser `932x430` | 25 exact-size frames; full touch flow with disclosed same-session replay; Defeat `04:51`; console `0/0`; failed requests `0` | **PASS** |
| Independent closeout | `docs/mobile_beta_final_independent_audit_2026-09-13.md`; P0 `0`, P1 `0`; local artifact GO | **PASS** |

The content audit is deliberately scoped to staged source/configuration, package resource paths, excluded basenames, credential/URL/source-map scans, service-worker closure, and comparison with the installed stock Web WASM. `compiled_diagnostic_symbol_absence=NOT_CERTIFIED` remains an explicit limitation.

## Known non-blocking technical note

Fog rendering can trail a moving unit's visibility state by one idle frame because the fog and unit processing priorities are equal. Selection visibility and command legality consume the same current snapshot, so this is not a hidden-target commandability mismatch. Treat it as P2 polish unless physical-device testing demonstrates user-visible impact.

## Handoff blockers

| Required input | State |
| --- | --- |
| Private HTTPS URL | **NOT_YET_READY — not supplied** |
| Host/operator owner | **NOT_YET_READY — not assigned** |
| Tester-intake owner | **NOT_YET_READY — not assigned** |
| Test window | **NOT_YET_READY — not scheduled** |
| Rollback contact and previous-artifact location | **NOT_YET_READY — not assigned/documented** |
| Private access method/invitations | **NOT_YET_READY — not supplied** |

## Native platform state

- Android: **BLOCKED**. No Android export preset/package configuration, usable Java runtime, validated binary SDK/toolchain/templates, signing material, device run, store metadata, or submission owner is available.
- iOS: **BLOCKED**. Xcode `26.6`, iPhoneOS `26.5`, and Godot `ios.zip` exist, but there is no iOS preset/app configuration, team/profile/signing identity (`0` valid identities), signed build, device run, TestFlight/store metadata, or owner.

Neither native target is store-ready. Credentials or signing material must not be invented or committed.

## Prioritized remaining work

1. Assign the private host/operator, tester-intake owner, test window, and rollback contact/location.
2. Deploy only the already-verified `build/mobile-web-beta/` artifact to the authorized private HTTPS host and distribute access privately; do not publish publicly or copy the parent `build/` directory.
3. Run the tester guide with unfamiliar people on real iOS/Android phones, including a 30-minute session, notch/safe-area, browser chrome, keyboard, audio, pause/resume, install/offline, accessibility, thermal, and comfort observations.
4. Reproduce or close the remaining P2 gameplay edges: one-frame fog/render timing, a possible hidden-depletion route-cost side channel, and an isolated legal foundation whose human builder has no preflighted route.
5. Obtain a named human product/balance decision after tester evidence. Automated AI liveness is not a balance verdict.
6. Only if native delivery is authorized, create target presets/configuration, provision supported toolchains/signing, and run signed physical-device/store workflows.

## Claim ladder

- **Implemented:** complete.
- **Locally validated Web artifact:** complete; independent audit P0 `0`, P1 `0`.
- **Internal Web tester-ready:** **not yet**; private hosting and named operations inputs are missing.
- **Externally validated:** **not yet**; no outside human or unfamiliar physical phone participated.
- **Balance approved:** **not yet**; no human product/balance owner has signed off.
- **Native/store-ready:** **blocked**.

## Supporting records

- [Evidence manifest](docs/mobile_beta_evidence_manifest_2026-09-13.json)
- [Final validation record](docs/mobile_beta_validation_2026-09-13.md)
- [Release checklist](docs/mobile_beta_release_checklist.md)
- [1v1 readiness record](docs/one_v_one_readiness_2026-09-12.md)
- [Platform export readiness](docs/mobile_platform_export_readiness_2026-09-12.md)
- [844x390 browser QA](docs/mobile_beta_browser_qa_844x390_2026-09-13.md)
- [932x430 browser QA](docs/mobile_beta_browser_qa_932x430_2026-09-13.md)
- [Tester guide](docs/mobile_beta_tester_guide.md)

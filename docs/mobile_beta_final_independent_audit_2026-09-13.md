# Pocket Kingdoms mobile beta final independent audit

Audit date: 2026-09-13  
Audit completed: 2026-09-13T12:56:50Z  
Independent auditor: Codex task `/root/release_source_final`  
Audit input: `docs/mobile_beta_evidence_manifest_2026-09-13.json`  
Input-manifest SHA-256: `d0d0babd9b0cb4785e5daabe6cc58c5791b8f1abbd92845abaff478267fb7898`

## Verdict

| Decision | Result |
| --- | --- |
| Unresolved P0 | **0** |
| Unresolved P1 | **0** |
| Recorded P2 observations | **7** |
| Local canonical Web artifact | **GO — locally verified and suitable for authorized private-handoff preparation** |
| Actual internal phone-tester handoff | **NOT_YET_READY — private HTTPS distribution and operating assignments are absent** |
| External / physical-device validation | **NOT_YET_READY — not performed** |
| Android / iOS native and store readiness | **BLOCKED** |

The canonical `build/mobile-web-beta/` candidate has no known P0/P1 and passes the requested local source, runtime, package, exact-size browser, and independent evidence-integrity gates. This is a local artifact decision, not permission to publish and not a claim that a private tester operation, unfamiliar-human validation, physical-phone validation, balance approval, native build, signing, or store submission is complete.

Only `build/mobile-web-beta/` is deliverable. Do not distribute `build/mobile-web-beta-repro-b/`, `build/mobile-web-beta-repro-a/`, or the parent `build/` directory.

## Candidate identity and binding

| Field | Independently observed value |
| --- | --- |
| Product/version | Pocket Kingdoms `0.1.0-beta.1` |
| Source revision | `89567778b26e` |
| Working-tree provenance | `source_dirty=true`; preserved user worktree |
| Closed staged-source manifest | `build/mobile-web-beta/SOURCE_SHA256SUMS.txt`; 206 entries |
| Staged-source manifest SHA-256 | `54ada2e25cdb3c0690ef37580039b78fbe3198be2f21597fccc703b4e6458fa5` |
| Canonical payload manifest | `build/mobile-web-beta/SHA256SUMS.txt`; 18 payload entries |
| Canonical payload-manifest SHA-256 | `27728ca36437a24ff6a8bc6a8a66e3eb1f75973ef38d65188586a9dc3b162e43` |
| Canonical / repro-b PCK | identical; `e8cdc4467fcb41eb3f9fb1163d279a758a25d4b59ba76848fc53e2a61649e611`; 1,601,384 bytes |
| Canonical / repro-b WASM | identical; `2b558bdb3c3af1f822ce6c43e09e1fa844d82fa440fe40d2d25d6c36ddf95137` |
| Godot | `4.6.stable.official.89cea1439` |

I opened the evidence rather than relying on the readiness summaries. All 49 path/SHA bindings declared by the final evidence manifest resolve to current files and match. The canonical, repro-b, `844x390`, and `932x430` checksum manifests all close. Canonical and repro-b each contain 18 manifested payload files plus the checksum file, with no symlinks or special files.

The two source manifests are byte-identical. Of their 206 entries, 205 match the working tree directly. The expected exception is `project.godot`: the build script removes debug autoload overrides and editor/MCP sections and appends deterministic text-resource export configuration. Reapplying that transformation in memory produced the exact staged `project.godot` hash `c2aee0f425eeecb97a744c5a3a4ca63a75e1573017a987fe101925d14c006456` recorded by the source manifest.

Key frozen source/harness hashes independently rechecked include:

- `scripts/ai/ai_controller.gd`: `c4765e3af59e70b0997914d1c0f0241a8d3f70a215bab7f8278626adeeed0eb6`
- `scripts/units/villager.gd`: `a25bedaff252c878044ccf222770fcd5a2a91eb870bcf84cdc948d0586fc7a22`
- `scripts/units/unit_base.gd`: `831181a8c810f1efc7499ed452336a1ec3dec64224230da8e507635f12fbcb8d`
- `scripts/map/game_map.gd`: `bb4da1c8674f25bdb56a04d3ee51a74cf20710ea2276e82a4216ad4ff8c73b82`
- `scripts/map/map_data.gd`: `0493dc63226fd5c7e0f9e36f1ed8beb65b4d69bd022594a6dc612c3707c05f20`
- `scripts/main/main.gd`: `0b9937a2556c1f70d4b7924b841525c29fdc25f130753eac59e278ea54aed5e6`
- `scripts/managers/selection_manager.gd`: `eb0d48c1cbba0e150905278fd95df469b485ceb11633bf634df4eb878fa5ed8e`
- `tools/mcp_ai_balance_pass.py`: `5c9744fe282c6e0b63be959cc2b85b8917e6b5cfc0b63054e8ec747d545ad642`
- `tools/build_mobile_web_beta.sh`: `9374118010d930e0bbc46df8b19cd7ce8e750c6a7657f4a6051480e99242776f`
- `tools/verify_mobile_web_artifacts.py`: `789b952741aa464b6c519d48ce94453b7f429f3d14de4c8d9231261f6ecc5d0f`

## Independent gate results

| Gate | Evidence opened and result |
| --- | --- |
| Headless boot | `docs/mobile_beta_headless_boot_2026-09-13.log`: exit `0`, no parser/runtime failure |
| Focused runtime regression | `docs/mobile_beta_focused_suite_2026-09-13.log`: **46/46 PASS**; warnings are deliberate negative spawn/egress fixtures |
| Python targeting / policy | `docs/mobile_beta_python_targeting_2026-09-13.log`: **5/5**; `docs/mobile_beta_python_ai_policy_2026-09-13.log`: **10/10** |
| Final-source AI matrix | `docs/mobile_beta_ai_matrix_2026-09-13.json` and log: **15/15 technical**, **15/15 policy**, runtime errors `0`, economic bonus `false`, ten AI Sacred Site wins and five explicitly nonterminal Easy horizon runs |
| Strict authoritative AI ending | `docs/mobile_beta_ai_probe_medium_202_2026-09-13.json` and log: technical/policy/completion **1/1/1**, Feudal `308.36s`, policy-horizon `12` villagers / `3` military, AI Sacred Site win at `361.0s`, errors `0`, bonus `false` |
| Clean phone automation | Two independent sessions: **66/66** each, no startup fallback, errors `0`, 119 FPS |
| Smoke | Two independent 75-second sessions: **18/18** each, errors `0`, 120 FPS |
| Web closure / reproducibility | Both payload manifests verify; PCK/WASM identical; only documented `version.json` build time and service-worker cache-version metadata differ after normalization |
| Content / sensitive-material audit | Declared source/path/configuration/credential/URL/source-map/PEM/service-worker checks pass; exact stock Godot release WASM match |
| PWA / HTML / MIME | Standalone landscape manifest, expected icons, correct PCK/WASM size declarations, service-worker cache coverage, and local MIME **7/7 PASS** |
| Browser `844x390` | 25/25 exact-size PNGs individually inspected; complete required flow, Defeat `04:55`, Sacred `3:00`, score `82–288`, console `0/0`, unexpected requests `0`, primed offline reload PASS |
| Browser `932x430` | 25/25 exact-size PNGs individually inspected; complete required flow with disclosed same-session Play Again, Defeat `04:51`, Sacred `3:00`, score `82–265`, console `0/0`, failed/non-2xx requests `0` |
| Readiness documentation | Validation, checklist, roadmap, platform, 1v1, tester-guide, and handoff claims agree: independent P0/P1 closeout PASS; local artifact GO; private/external/native/balance gates remain open |
| Workspace hygiene | `git diff --check` PASS; no residual Godot, MCP, AI harness, Playwright/Chromium, or HTTP-server processes; no listeners on ports `6550` or `8060` |

The final 2026-09-13 AI matrix predates the final Web export in wall-clock order but is not a pre-final-source run: its runtime and harness hashes are the exact frozen hashes packaged afterward. The strict Medium/202 completion probe was regenerated later against those same hashes. Browser endings are separate final-canonical-PCK evidence. The 2026-09-12 AI matrix, prior probes, prior screenshots, and other pre-final material are historical and excluded from this decision.

## Required behavioral adjudications

| Area | Independent assessment |
| --- | --- |
| Autonomous gather / retarget under fog | **PASS.** Concrete-player resource lookup tests visibility before type, validity, harvestability, or path queries; explicit player `-1` is the only omniscient mode. Villagers retain scalar last-seen type/position/instance identity rather than a live Node, do not substitute a same-type hidden resource, survive depletion/`queue_free`, and revalidate only after the remembered tile becomes currently visible. The hidden-spy regression proves zero candidate type/harvestability/harvest calls before reveal. See P2-02 for the remaining simulation-path side channel. |
| Initial and live fog ordering | **PASS with P2-01.** Initial human visibility is synchronously applied before camera/automatic gather assignment. Each match frame performs sources, fog-grid refresh, resource/entity visibility, and stale-selection pruning as one authoritative snapshot. No hidden commandability leak was found. |
| Move versus A-Move / armed targeting | **PASS.** Explicit Move suppresses engagement; A-Move acquires/attacks. Armed Move/A-Move/Patrol takes priority on the next world tap, including resources, foundations, enemy and friendly buildings, then uses common destination semantics. Focused live regressions cover the distinction. |
| Hidden building placement | **PASS with P2-03.** Human placement performs the full visibility prepass before the canonical bounds/grass/live-resource/path-walkability contract; hidden failures stay generic. AI planning and the Main transaction boundary use the same terrain contract and revalidate before spend. |
| Rally and production transactions | **PASS.** Population is reserved/refunded transactionally. Trained units spawn at a bounded reachable producer edge, then route toward the rally; hidden blockers are not queried as a player-visible detail, and sealed egress rejects/refunds rather than teleporting. |
| AI live target memory | **PASS.** Lost or freed live targets degrade to scalar last-known position/HP memory without hidden-state reads or redirecting to a visible replacement. Memory eviction requires current vision. |
| Real AI construction and economy | **PASS.** AI uses current visibility, canonical buildability, path preflight, real affordability, real foundations/builders/timers, bounded retry/reassignment, and exact cancellation/refund bookkeeping. Farm completion, cargo transfer, cumulative paid-capacity accounting, queue-aware military floors, and gather liveness are covered. No economic multiplier was observed. |
| Dynamic controls / phone layout | **PASS.** Contextual controls are retired before replacement, the six-command rail remains ordered Move/A-Move/Patrol/Stop/Stance/Clear, Build remains a separate mode, and short-side phone layouts keep score hidden after guided dismissal. |
| Pause / game-over / scene transition | **PASS.** Gameplay processing is pausable while HUD/game-over controls remain always processable; representative movement, gathering/construction/site timers freeze and resume. `GameManager` normalizes `tree.paused` outside PAUSED, and menu/replay transitions return to an actionable unpaused state. |
| Authoritative endings | **PASS.** Victory, elimination victory, defeat/restart, and pause-quit/menu paths converge on one-shot authoritative match state and summary/navigation behavior; both browser sessions visibly reached supported Sacred Site defeats. |
| Production debug / MCP exclusion | **PASS within declared scope.** Staging excludes tools/tests/docs/output, debug bootstrap/panel, editor overrides, and `addons/godot_mcp`. Production retains only an intentionally empty `runtime_game_bridge.gd` under the topology-preserving `MCPGameBridge` autoload name. See P2-05 for the compiled-name certification limit. |

## P2 observations and limitations

These do not block the local artifact verdict, but they remain open and must not be silently promoted away.

1. **P2-01 — one-frame fog/render timing.** `Main._process()` refreshes fog/entity visibility before equal-priority child units perform their movement for that frame. A moving unit's graphics can therefore trail the position-derived visibility snapshot by one idle frame. Selection and command legality consume the same snapshot, so this is not a known hidden-target interaction leak. Physical-device testing should escalate any longer persistence or actual hidden interaction.

2. **P2-02 — hidden-depletion simulation side channel.** Natural-resource depletion immediately changes the authoritative map grid/pathfinding tile to grass while the terrain rendering and minimap intentionally retain the last-seen resource terrain until reveal. Direct target discovery and rendering stay fog-honest, but a player may theoretically infer a hidden depletion from a changed unit route/path cost. This is a low-bandwidth simulation side channel, not a direct resource identity/state read.

3. **P2-03 — human builder reachability is not preflighted.** `scripts/main/main.gd:2207-2261` revalidates terrain and affordability, spends, spawns the foundation, and then chooses the nearest idle/gathering villager by Euclidean distance. Unlike the AI construction path, it does not preflight that villager's route or reject/refund an unreachable foundation. An isolated but otherwise legal visible footprint can strand a paid foundation. Normal generated/browser flows did not reproduce this edge case.

4. **P2-04 — dirty-source provenance.** The closed 206-entry staged-source manifest strongly identifies this artifact, but `source_dirty=true` means it is not backed by an immutable clean commit or independent source archive. Rebuilding later requires preserving the exact manifested bytes and staging transform.

5. **P2-05 — compiled diagnostic-symbol absence is not certified.** The verifier's `dev_symbols=0` applies only to its declared enumerated patterns. Printable PCK strings still include `_refresh_touch_target_diagnostics`, `_refresh_main_menu_diagnostics_if_ready`, and the intentional `MCPGameBridge` autoload name. Their production refresh paths are gated/inert, the runtime bridge is empty, the editor add-on/debug UI is absent, and no runtime/security defect was observed; nevertheless `compiled_diagnostic_symbol_absence=NOT_CERTIFIED` is the correct claim.

6. **P2-06 — historical repro-a remains beside the candidate.** `build/mobile-web-beta-repro-a/` has old PCK SHA-256 `d3e42158426a4a78da217baf1ce8fa3fe02a5f894dad992331db7665fddcff31`, no final source manifest, and six unmanifested `.png.import` files. Documentation excludes it, but its presence creates an avoidable operator-selection risk. Never serve or copy the parent `build/` directory.

7. **P2-07 — secondary prose is not directly evidence-manifest-bound.** The manifest closes each browser `qa-results.json` and complete screenshot directory, but not the two Markdown browser reports or high-level readiness prose. Primary data/pixels are fully bound, so this is provenance hardening rather than an evidence gap. At audit time the browser-report hashes were `79b82f3adb6001eeea75aed184bebb04667c56a3ff2d76a82158fe9f10efef52` (`844x390`) and `c0197b7b5d7e9d10a48afc7c0a5968edaf72d8a23ea1b0338c01b9c0cc670672` (`932x430`).

## Gates that remain outside this local GO

The actual private tester handoff remains **NOT_YET_READY** until an authorized human supplies and records all of the following:

- private HTTPS URL and private access/invitation method;
- named host/operator and tester-intake owner;
- scheduled test window;
- rollback contact and recoverable previous-artifact location/procedure;
- deployment of only the canonical directory with production HTTPS/MIME/isolation behavior.

The following are also unverified and cannot be inferred from local Chromium/Godot automation:

- unfamiliar outside-human testing on real iOS and Android phones;
- the 30-minute session, browser chrome/notch/safe-area, audio, keyboard, suspend/resume, memory pressure, thermal behavior, accessibility, touch comfort, and installed-PWA behavior;
- human product/balance approval and long-session balance;
- Android/iOS presets and package identities, supported native toolchains, signing/provisioning, signed artifacts, physical-device installation, TestFlight/store metadata, review, submission, or ownership.

No public deployment, private invitation, native export, signing, installation, store action, or external message is authorized or claimed by this audit.

## Independent signoff

**Signed finding:** P0 `0`, P1 `0`. The frozen canonical Pocket Kingdoms mobile Web beta is a **LOCAL ARTIFACT GO** and locally tester-ready candidate for private-handoff preparation. The real internal phone-tester handoff remains **NOT_YET_READY** for the operational reasons above. The reconciled high-level records agree with this decision; all external/native/private-distribution limitations remain in force.

Auditor: Codex `/root/release_source_final`  
Signed at: `2026-09-13T12:56:50Z`

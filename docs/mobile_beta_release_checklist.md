# Pocket Kingdoms mobile-beta release checklist

Status date: 2026-09-13

Release channel: private production Web beta

Current verdict: **LOCAL GATES AND INDEPENDENT AUDIT PASS; INTERNAL HANDOFF NOT_YET_READY**

## Claim boundaries

| Claim | Current state |
| --- | --- |
| Feature implementation | **Complete for this candidate** |
| Required local runtime/package/browser validation | **PASS** |
| Independent closeout | **PASS — P0 0, P1 0** |
| Internal phone-tester handoff | **NOT_YET_READY — private hosting/owners/window/rollback/access missing** |
| Outside-human / physical-phone validation | **NOT_YET_READY — not performed** |
| Human balance approval | **NOT_YET_READY — no owner/signoff** |
| Android/iOS store readiness | **BLOCKED** |

## 1. Freeze one candidate

- [x] Revision recorded: `89567778b26e`.
- [x] Dirty state recorded: `true`; existing user changes intentionally preserved.
- [x] Closed staged-source manifest recorded: 206 entries, SHA-256 `54ada2e25cdb3c0690ef37580039b78fbe3198be2f21597fccc703b4e6458fa5`.
- [x] Evidence-binding manifest generated: `docs/mobile_beta_evidence_manifest_2026-09-13.json`.
- [x] Canonical and reproduction builds embed the same staged-source manifest.
- [x] Final runtime/harness hashes remained stable through validation.

Candidate identity: **PASS**.

If any staged runtime source changes, rebuild and rerun every final gate. Documentation-only closeout changes do not alter the closed packaged-source identity.

## 2. Local runtime and regression gates

- [x] Godot recorded: `4.6.stable.official.89cea1439`.
- [x] Headless boot: **PASS**, exit `0`; `docs/mobile_beta_headless_boot_2026-09-13.log`.
- [x] Focused regression: **PASS**, `46/46`; `docs/mobile_beta_focused_suite_2026-09-13.log`.
- [x] Python touch targeting: **PASS**, `5/5`; `docs/mobile_beta_python_targeting_2026-09-13.log`.
- [x] Python AI policy: **PASS**, `10/10`; `docs/mobile_beta_python_ai_policy_2026-09-13.log`.
- [x] Strict Medium seed 202: **PASS**, technical/policy/completion `1/1/1`, Feudal `308.36s`, AI Sacred Site win `361.0s`, errors `0`, economic bonus `false`; `docs/mobile_beta_ai_probe_medium_202_2026-09-13.json`.
- [x] AI matrix: **PASS**, 15/15 technical/policy, 10 supported endings, 5 horizon-complete nonterminal Easy runs, errors `0`; `docs/mobile_beta_ai_matrix_2026-09-13.json`.
- [x] Clean phone pass 1: **PASS**, `66/66`, no fallback, errors `0`; `docs/mobile_beta_phone_final_pass1_2026-09-13.json`.
- [x] Clean phone pass 2: **PASS**, `66/66`, no fallback, errors `0`; `docs/mobile_beta_phone_final_pass2_2026-09-13.json`.
- [x] Smoke pass 1: **PASS**, `18/18`, 75-second soak, errors `0`; `docs/mcp_smoke_report_2026-09-13-final-pass1.txt`.
- [x] Smoke pass 2: **PASS**, `18/18`, 75-second soak, errors `0`; `docs/mcp_smoke_report_2026-09-13-final-pass2.txt`.

Local runtime/regression verdict: **PASS**. The AI runs are conservative liveness/correctness checks, not a balance decision.

## 3. Production Web artifact

- [x] Canonical build produced at `build/mobile-web-beta/`, UTC `2026-09-13T12:05:38Z`.
- [x] Version recorded: Pocket Kingdoms `0.1.0-beta.1`, channel `internal-mobile-web-beta`.
- [x] `build/mobile-web-beta/SHA256SUMS.txt` closes 18/18 payload entries; manifest SHA-256 `27728ca36437a24ff6a8bc6a8a66e3eb1f75973ef38d65188586a9dc3b162e43`.
- [x] Staged-source/configuration/resource-path audit: **PASS**; `build/mobile-web-beta/CONTENT_AUDIT.txt`.
- [x] Independent sensitive-material/URL/source-map/key/service-worker scan: **PASS**; `docs/mobile_beta_sensitive_material_scan_2026-09-13.log`.
- [x] Canonical `index.pck`: SHA-256 `e8cdc4467fcb41eb3f9fb1163d279a758a25d4b59ba76848fc53e2a61649e611`, 1,601,384 bytes.
- [x] Repro-b `index.pck`: identical SHA-256 and size.
- [x] Canonical/repro WASM: identical SHA-256 `2b558bdb3c3af1f822ce6c43e09e1fa844d82fa440fe40d2d25d6c36ddf95137`.
- [x] Reproducibility transcript accounts for all files and the only allowed metadata deltas; `docs/mobile_beta_build_verification_2026-09-13.log`.
- [x] Local MIME: **PASS**, 7/7; `docs/mobile_beta_web_mime_2026-09-13.log`.
- [x] No publish or signing action performed.

Artifact verdict: **PASS — production-clean within the declared audit scope**.

Audit limitation: `compiled_diagnostic_symbol_absence=NOT_CERTIFIED`. Seven PEM-header literals in WASM are stock format constants, not full key blocks; the WASM exactly matches the installed Godot release template.

Release-directory guardrail:

- [x] Only `build/mobile-web-beta/` is the deliverable.
- [x] `build/mobile-web-beta-repro-b/` is a reproducibility witness, not the handoff directory.
- [x] `build/mobile-web-beta-repro-a/` and all 2026-09-12/pre-final evidence are historical and non-deliverable.
- [ ] Never copy/serve the parent `build/` directory. The authorized operator must deploy only the canonical directory.

## 4. Browser QA — exact `844x390`

- [x] 25 screenshots have exact `844x390` headers and were visually inspected.
- [x] Main menu, Settings, Hard, seed `424242`, guided/free HUD.
- [x] Direct Town Center selection, queue/reservation/cancel/refund.
- [x] Scout/Army and fixed Move / A-Move / Patrol / Stop / Stance / Clear rail.
- [x] Separate Build sheet, invalid placement feedback, cancel recovery.
- [x] Pause, held clock, resume.
- [x] Touch pan, pinch out/in, minimap drag, long press.
- [x] Supported ending and Main Menu return: Defeat `04:55`, Sacred `3:00`, score `82–288`.
- [x] Console: 0 errors, 0 warnings.
- [x] Requests: 0 unexpected failures; one intentional uncached offline probe failed as required.
- [x] Primed service-worker reload while offline: **PASS**.
- [x] QA JSON SHA-256 `9a71f1562aa564feeffc773728d894ea88cd1b8abe60805df3bba7ff0e0fbbcb`.
- [x] Closed directory manifest: 31 entries, SHA-256 `bc65134865589d757de8afa9db8781d669600728999d9db3593dba65255b7a61`.

Result: **PASS — local Chromium touch emulation; no human/physical-phone claim**.

## 5. Browser QA — exact `932x430`

- [x] 25 screenshots have exact `932x430` headers and were visually inspected.
- [x] Main menu, Settings, Hard, seed `424242`, guided/free HUD.
- [x] Direct Town Center selection, queue/reservation/cancel/refund.
- [x] Scout/Army and fixed six-command rail.
- [x] Separate Build sheet, invalid placement feedback, cancel recovery.
- [x] Pause, held clock, resume.
- [x] Touch pan, accepted pinch out/in, minimap drag, long press, 3x speed.
- [x] Supported ending and Main Menu return: Defeat `04:51`, Sacred `3:00`, score `82–265`.
- [x] Console: 0 errors, 0 warnings.
- [x] Requests: 0 failed, 0 non-2xx.
- [x] The first ending before all gestures and the same-session `Play Again` completion are disclosed in the QA JSON.
- [x] QA JSON SHA-256 `7ebab7e2a8425341d7e107d67ffbf217e401477b2976ba03244a224c9fec7509`.
- [x] Closed directory manifest: 32 entries, SHA-256 `b794d40afb0a6eb489444e7311b9beecfa0407a428d2ba14958881be4ab8dbac`.

Result: **PASS — local Chromium touch emulation; no human/physical-phone claim**.

## 6. Independent audit

- [x] Final independent source/evidence report issued at `docs/mobile_beta_final_independent_audit_2026-09-13.md`.
- [x] Unresolved P0 count: `0`.
- [x] Unresolved P1 count: `0`.
- [x] Manifest, 49 declared bindings, four closure manifests, source/harness hashes, screenshot dimensions, content closure, claims, `git diff --check`, and residual processes/listeners rechecked.

Current audit verdict: **PASS — LOCAL ARTIFACT GO; actual private tester handoff remains NOT_YET_READY**.

## 7. Private distribution operations

- [ ] Private HTTPS URL: **NOT_YET_READY — not supplied**.
- [ ] Host/operator owner: **NOT_YET_READY — unassigned**.
- [ ] Tester-intake owner: **NOT_YET_READY — unassigned**.
- [ ] Test window: **NOT_YET_READY — unscheduled**.
- [ ] Rollback contact: **NOT_YET_READY — unassigned**.
- [ ] Recoverable previous-artifact location/procedure: **NOT_YET_READY — undocumented**.
- [ ] Private invitation/access method: **NOT_YET_READY — not supplied**.
- [ ] Canonical directory only deployed with correct HTTPS/MIME/isolation behavior: **NOT_YET_READY — no deployment authorized**.

Do not publish publicly or commit credentials.

## 8. Outside-human and physical-device acceptance

- [ ] Session identifiers: **NOT_YET_READY — no outside-human session**.
- [ ] Unfamiliar iOS/Android phone/OS/browser matrix: **NOT_YET_READY — not run**.
- [ ] 30-minute phone session: **NOT_YET_READY — not run**.
- [ ] Touch comfort, safe area/notch, browser chrome, keyboard, audio, suspend/resume, install/offline, thermal findings: **NOT_YET_READY — not observed on physical devices**.
- [ ] Accessibility result: **NOT_YET_READY — no human accessibility review**.
- [ ] Balance result and owner: **NOT_YET_READY — no human product/balance owner or signoff**.

## 9. Native/store work

- [ ] Android: **BLOCKED** — preset/package identity, usable Java, validated SDK/binary templates, signing, artifact, physical-device run, store work, and owner missing.
- [ ] iOS: **BLOCKED** — preset/app identity, team/profile/signing identity, artifact, physical-device run, TestFlight/store work, and owner missing. Xcode `26.6`, iPhoneOS `26.5`, and `ios.zip` alone do not close a gate.

## Final decision

| Decision | Value |
| --- | --- |
| Required local runtime/artifact/browser gates | **PASS** |
| Canonical artifact reproducible | **PASS** |
| Independent audit | **PASS — P0 0, P1 0** |
| Private hosting/owners assigned | **NO** |
| Internal production Web tester handoff | **NOT_YET_READY — private distribution inputs missing** |
| External validation | **NOT_YET_READY — no outside-human or physical-phone session** |
| Human balance approval | **NOT_YET_READY** |
| Native/store readiness | **BLOCKED** |

Decision owner/date for an actual tester invitation: **NOT_YET_READY — no authorized human owner/date supplied**.

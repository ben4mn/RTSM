# Pocket Kingdoms mobile-beta validation record

Validation date: 2026-09-13

## Verdict

**All required local execution, package, exact-size browser, and independent closeout gates passed. Internal phone-tester handoff remains NOT_YET_READY because private hosting and operating assignments are absent.**

This record distinguishes local desktop/browser evidence from outside-human, physical-phone, balance, native, signing, store, and publication claims.

## Candidate identity

| Field | Final value |
| --- | --- |
| Product/version | Pocket Kingdoms `0.1.0-beta.1` |
| Source revision | `89567778b26e` |
| Dirty state | `true`; intentional preserved working tree, not a clean-checkout claim |
| Staged-source manifest | `build/mobile-web-beta/SOURCE_SHA256SUMS.txt`, 206 entries |
| Staged-source SHA-256 | `54ada2e25cdb3c0690ef37580039b78fbe3198be2f21597fccc703b4e6458fa5` |
| Godot | `4.6.stable.official.89cea1439` |
| Local validation freeze | Codex root; runtime source frozen before final run sequence; canonical build `2026-09-13T12:05:38Z` |
| Evidence-binding manifest | `docs/mobile_beta_evidence_manifest_2026-09-13.json` |
| Binding status | **PASS** — report/artifact hashes and commands bound to the closed staged source |

## Runtime and regression gates

| Gate | Evidence | Result |
| --- | --- | --- |
| Headless boot | `docs/mobile_beta_headless_boot_2026-09-13.log`; `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 1` | **PASS**, exit `0` |
| Focused regression | `docs/mobile_beta_focused_suite_2026-09-13.log` | **PASS**, `46/46`, exit `0` |
| Python touch targeting | `docs/mobile_beta_python_targeting_2026-09-13.log` | **PASS**, `5/5`, exit `0` |
| Python AI policy | `docs/mobile_beta_python_ai_policy_2026-09-13.log` | **PASS**, `10/10`, exit `0` |
| Strict Medium seed 202 | `docs/mobile_beta_ai_probe_medium_202_2026-09-13.json`; log SHA-256 `6a1cef783662e24c00cdf8d0bb58ef84a5d4410cee5a1ca14cae71b6e7e67802` | **PASS**, technical/policy/completion `1/1/1`, errors `0` |
| AI liveness/policy matrix | `docs/mobile_beta_ai_matrix_2026-09-13.json` | **PASS**, `15/15` technical/policy, errors `0`, observed terminal completions `10` |
| Clean phone simulation 1 | `docs/mobile_beta_phone_final_pass1_2026-09-13.json` | **PASS**, `66/66`, no fallback, errors `0`, `119 FPS / 9.77ms` |
| Clean phone simulation 2 | `docs/mobile_beta_phone_final_pass2_2026-09-13.json` | **PASS**, `66/66`, no fallback, errors `0`, `119 FPS / 9.44ms` |
| 75-second smoke 1 | `docs/mcp_smoke_report_2026-09-13-final-pass1.txt` | **PASS**, `18/18`, errors `0`, `120 FPS / 9.56ms` |
| 75-second smoke 2 | `docs/mcp_smoke_report_2026-09-13-final-pass2.txt` | **PASS**, `18/18`, errors `0`, `120 FPS / 9.61ms` |

The focused suite covers AI live vision, construction timing, economy/attack recovery, strategic policy, reference cleanup, path/range normalization, real farm and clustered-resource navigation, autonomous recovery, separation continuity, fog command/placement/resource legality, building ownership/reselection, production/rally/reservations/refunds, population cap after building loss, combat/villager retaliation, sacred ownership/income/telemetry, safe areas, phone layout, command bar/actions, touch hit radius/long press/train input, guided transition, pause/game-over process boundaries, menu transition, and all endings.

### Strict completion detail

Medium / seed `202` reached Feudal at `308.360015s`, satisfied the conservative policy-horizon sample at `289.201175s` with 12 villagers / 3 military, and ended in an authoritative AI Sacred Site victory at `361.0s`. Final state was Age II, 14 villagers, 3 military, 5 buildings, 1321 resources gathered, zero economy-stagnation seconds, zero runtime errors, and no economic bonus.

### Matrix interpretation

Five seeds each (`101`, `202`, `303`, `424242`, `9001`) ran on Easy, Medium, and Hard. Every case passed technical and conservative policy gates with no economic bonus and zero runtime errors. All five Medium cases and all five Hard cases reached supported AI Sacred Site victories. The five Easy cases intentionally exhausted the 450-second horizon without a terminal state; they are liveness/policy passes, not claimed completions. Hard victories occurred before Feudal and used the documented victory-only age-progression exception; economy, force, objective, fair-economy, and technical gates remained enforced.

Automated validation is AI liveness/correctness evidence, not a human balance verdict.

## Canonical Web build

| Field | Final value |
| --- | --- |
| Deliverable directory | `build/mobile-web-beta/` |
| Build UTC | `2026-09-13T12:05:38Z` |
| Version | `0.1.0-beta.1`, channel `internal-mobile-web-beta` |
| Payload manifest | `build/mobile-web-beta/SHA256SUMS.txt`; 18 entries; SHA-256 `27728ca36437a24ff6a8bc6a8a66e3eb1f75973ef38d65188586a9dc3b162e43` |
| Manifest closure | **PASS**, 18/18 manifested payloads; regular files/directories only |
| Scoped content audit | `build/mobile-web-beta/CONTENT_AUDIT.txt` — **PASS** |
| Independent sensitive-material scan | `docs/mobile_beta_sensitive_material_scan_2026-09-13.log` — **PASS** |
| Canonical `index.pck` | SHA-256 `e8cdc4467fcb41eb3f9fb1163d279a758a25d4b59ba76848fc53e2a61649e611`; 1,601,384 bytes |
| Repro-b `index.pck` | same SHA-256 and size |
| Canonical/repro WASM | same SHA-256 `2b558bdb3c3af1f822ce6c43e09e1fa844d82fa440fe40d2d25d6c36ddf95137` |
| Reproducibility | **PASS** — 16 other substantive files byte-identical; only `built_at` and service-worker cache-version values differ |
| MIME | `docs/mobile_beta_web_mime_2026-09-13.log` — **PASS**, `7/7` |

The artifact excludes tools/tests, reports/docs, temporary output, debug bootstrap/panel, editor-only bridge code, and the Godot MCP add-on. The independent verifier found zero matches for its declared sensitive-filename, source-map, absolute-path, credential, localhost/tunnel/unexpected-URL, enumerated development-symbol, and full-PEM-key-block patterns. Seven PEM header literals in WASM are stock format constants; the exported WASM exactly matches the installed Godot release template. The intentional `MCPGameBridge` autoload name and gated runtime telemetry-refresh method names can remain in compiled resources, so the audit's `compiled_diagnostic_symbol_absence=NOT_CERTIFIED` limitation remains explicit.

`build/mobile-web-beta-repro-a/` is an older, unbound artifact without the final source manifest. It and every 2026-09-12/pre-final report are historical and **must not be distributed**. Only `build/mobile-web-beta/` is the deliverable; `build/mobile-web-beta-repro-b/` is its reproduction witness.

## Exact-size browser QA

Evidence root: `output/playwright/mobile-beta/closing-final-2026-09-13/`

| Viewport | Flow / ending | Console | Requests | Offline |
| --- | --- | --- | --- | --- |
| `844x390` | **PASS**, 25 exact PNGs; Defeat `04:55`, Sacred `3:00`, score `82–288` | `0` errors / `0` warnings | `0` unexpected failures; one intentional offline-probe failure | **PASS** after service-worker prime |
| `932x430` | **PASS**, 25 exact PNGs; disclosed same-session replay; Defeat `04:51`, Sacred `3:00`, score `82–265` | `0` errors / `0` warnings | `0` failed / `0` non-2xx | Not required |

Both flows used Chromium `152.0.7977.83`, DPR `1`, touch/coarse-pointer emulation, and exact CSS/buffer sizes. They cover menu/settings, Hard and seed `424242`, guided Skip/free HUD, direct Town Center selection, queue/reservation/cancel/refund, Scout/Army, stable six-command rail, separate Build sheet, invalid placement/cancel recovery, pause/held clock/resume, touch pan/pinch/minimap/long press, supported ending, and Main Menu return. The `932x430` first ending occurred before all gestures; `Play Again` in the same session preserved configuration and completed the remaining gates before a second supported ending. This is disclosed, not hidden.

Browser-local verdict: **PASS**. No outside human or physical phone participated.

## Independent audit

| Field | State |
| --- | --- |
| Reviewer | Codex independent subagent |
| Input | Frozen source hashes, build closure, evidence manifest, both browser directory manifests, reports, and screenshots |
| Report | `docs/mobile_beta_final_independent_audit_2026-09-13.md` |
| Unresolved P0/P1 | `0 / 0` |
| Verdict | **PASS — LOCAL ARTIFACT GO; private handoff NOT_YET_READY** |

## Operational and external blockers

| Required item | State |
| --- | --- |
| Private HTTPS URL | **NOT_YET_READY — not supplied** |
| Host/operator owner | **NOT_YET_READY — not assigned** |
| Tester-intake owner | **NOT_YET_READY — not assigned** |
| Test window | **NOT_YET_READY — not scheduled** |
| Rollback contact and previous-artifact location | **NOT_YET_READY — not assigned/documented** |
| Private access mechanism | **NOT_YET_READY — not supplied** |
| Outside-human sessions | **NOT_YET_READY — none performed** |
| Unfamiliar physical-device matrix | **NOT_YET_READY — none performed** |
| 30-minute session / accessibility / comfort | **NOT_YET_READY — not performed** |
| Human balance approval | **NOT_YET_READY — no owner or signoff** |

## Decision ledger

| Claim | Decision |
| --- | --- |
| Required local execution/artifact/browser gates | **PASS** |
| Canonical artifact reproducible | **PASS** |
| Independent closeout | **PASS — P0 0, P1 0** |
| Private hosting/owners assigned | **NO** |
| Internal production Web tester handoff | **NOT_YET_READY — locally verified artifact, but private distribution inputs are missing** |
| External validation | **NOT_YET_READY — no unfamiliar human or physical-phone test** |
| Native/store readiness | **BLOCKED — target configuration, signing, physical devices, store work, and owners are incomplete** |

No public deployment or signing action was performed.

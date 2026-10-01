# AOEM 1v1 readiness record

Historical filename retained for links; status refreshed 2026-09-13.

## Verdict

**LOCALLY VERIFIED; NOT YET READY FOR INTERNAL PHONE-TESTER HANDOFF.** The final-source runtime, production Web artifact, deterministic AI completion, multi-seed AI liveness, two clean phone simulations, two soak smokes, both exact-size browser flows, and independent closeout passed. Private hosting and operating ownership are not supplied, so the artifact must not yet be described as handed off or published.

This verdict does not claim unfamiliar-human validation, physical-device validation, balance approval, native readiness, signing, store readiness, or publication.

## Accepted 1v1 loop

The final browser evidence covers the intended uninterrupted interaction surface:

1. Open Main Menu and Settings; choose Hard and deterministic seed `424242`.
2. Start a match; inspect or skip the guided opener; reach the free HUD.
3. Select the starting Town Center directly.
4. Queue a Villager, observe population reservation, cancel, and observe reservation release plus the 50-food refund.
5. Produce/select a unit and exercise the fixed Move / A-Move / Patrol / Stop / Stance / Clear rail.
6. Open the separate Build sheet, choose House, see invalid placement feedback, cancel, and recover normal input.
7. Exercise touch pan, pinch, minimap navigation, and long-press context.
8. Pause, verify the game clock holds, resume, reach a supported Sacred Site ending, and return through Main Menu.

The focused suite additionally covers valid construction, production/rally, farms, upgrades, fog legality, population loss/reservation, cleanup, movement/combat scale, match processing boundaries, and every supported match ending.

## Frozen identity

| Field | Value |
| --- | --- |
| Revision | `89567778b26e` |
| Dirty state | `true`; user changes intentionally preserved |
| Staged-source SHA-256 | `54ada2e25cdb3c0690ef37580039b78fbe3198be2f21597fccc703b4e6458fa5` |
| Evidence manifest | `docs/mobile_beta_evidence_manifest_2026-09-13.json` — **PASS** |
| Godot | `4.6.stable.official.89cea1439` |
| Canonical artifact | `build/mobile-web-beta/` at `2026-09-13T12:05:38Z` |
| Canonical/repro PCK SHA-256 | `e8cdc4467fcb41eb3f9fb1163d279a758a25d4b59ba76848fc53e2a61649e611` |

## Final-source acceptance evidence

| Requirement | Final evidence | Result |
| --- | --- | --- |
| Headless boot | `docs/mobile_beta_headless_boot_2026-09-13.log`; exit `0` | **PASS** |
| Focused regression | `docs/mobile_beta_focused_suite_2026-09-13.log`; `46/46` | **PASS** |
| Targeting / policy | `5/5` targeting; `10/10` AI policy | **PASS** |
| Strict deterministic AI | Medium seed 202; Feudal `308.36s`; AI Sacred Site victory `361.0s`; technical/policy/completion `1/1/1`; errors `0`; bonus `false` | **PASS** |
| AI liveness/policy matrix | 15/15 technical/policy clean; 10 supported endings; 5 horizon-complete nonterminal Easy runs; errors `0` | **PASS** |
| Clean phone simulation | pass 1 `66/66`; pass 2 `66/66`; no fallback; errors `0` | **PASS** |
| 75-second smoke | pass 1 `18/18`; pass 2 `18/18`; errors `0` | **PASS** |
| Web package | two clean builds; 18/18 closed payload entries; scoped content/sensitive-material audit pass; MIME `7/7` | **PASS** |
| Reproducibility | canonical/repro PCK and WASM byte-identical; only documented timestamp/cache-version metadata differs | **PASS** |
| Browser `844x390` | 25 exact-size frames; required touch flow; offline reload; ending `04:55`; console errors/warnings `0/0`; unexpected requests `0` | **PASS** |
| Browser `932x430` | 25 exact-size frames; required touch flow with disclosed same-session replay; ending `04:51`; console errors/warnings `0/0`; failed requests `0` | **PASS** |
| Independent closeout | `docs/mobile_beta_final_independent_audit_2026-09-13.md`; unresolved P0 `0`, P1 `0`; local artifact GO | **PASS** |

## Mechanical acceptance checklist

- [x] One closed 206-entry staged-source manifest binds the runtime source used by both Web builds.
- [x] Primary final reports record path, SHA-256, invocation, result/exit, and generation time in the evidence manifest.
- [x] No required command timed out, returned invalid output, or hid a non-zero failure count.
- [x] The strict Medium seed 202 run reached a supported terminal state with zero runtime errors.
- [x] All 15 matrix cases were technically and policy clean; all terminal/nonterminal outcomes are explicitly classified.
- [x] Both phone and both smoke runs passed from independent clean editor launches.
- [x] Canonical and reproduced PCK/WASM hashes match; all other build deltas are explained.
- [x] Both exact browser sizes completed the required touch flow without blocked primary controls.
- [x] The `844x390` service-worker reload succeeded offline after an online prime.
- [x] Browser console and request evidence contains no unexplained release blocker.
- [x] Independent closeout report confirms zero unresolved P0/P1 findings.

## External validation still required

These fields are deliberately unresolved rather than inferred from local automation:

| Field | State |
| --- | --- |
| Outside-human session identifiers | **NOT_YET_READY — no outside-human session performed** |
| Unfamiliar phone/OS/browser matrix | **NOT_YET_READY — no physical-device session performed** |
| 30-minute phone session | **NOT_YET_READY — not performed** |
| Accessibility and touch comfort | **NOT_YET_READY — requires unfamiliar humans and physical phones** |
| Balance result / owner | **NOT_YET_READY — no human product/balance owner or signoff** |

## Distribution blockers

| Field | State |
| --- | --- |
| Private HTTPS URL | **NOT_YET_READY — not supplied** |
| Host/operator owner | **NOT_YET_READY — not assigned** |
| Tester-intake owner | **NOT_YET_READY — not assigned** |
| Test window | **NOT_YET_READY — not scheduled** |
| Rollback contact/location | **NOT_YET_READY — not assigned/documented** |
| Private access mechanism | **NOT_YET_READY — not supplied** |

Do not publish publicly and do not commit credentials.

## Native status

- Android: **BLOCKED** on preset/package configuration, Java and validated Android SDK/binary templates, signing, physical-device validation, store work, and ownership.
- iOS: **BLOCKED** on preset/app configuration, team/profile/signing identity, signed artifact, physical-device validation, TestFlight/store work, and ownership. Xcode `26.6`, iPhoneOS `26.5`, and `ios.zip` are prerequisites only.

## Signoff ledger

| Role | Owner | Decision | Date/evidence |
| --- | --- | --- | --- |
| Local engineering validation | Codex root | **PASS — automated and browser-local scope** | 2026-09-13; evidence manifest |
| Independent audit | Codex `/root/release_source_final` | **PASS — P0 0, P1 0; local artifact GO** | 2026-09-13; `docs/mobile_beta_final_independent_audit_2026-09-13.md` |
| Private host operations | **NOT_YET_READY — unassigned** | **NOT_YET_READY** | No owner/URL/access method |
| Tester operations | **NOT_YET_READY — unassigned** | **NOT_YET_READY** | No owner/window/intake route |
| Product/balance | **NOT_YET_READY — unassigned** | **NOT_YET_READY** | No human balance review |

Internal Web tester-ready status requires both clean independent closeout and assigned private distribution operations. External validation, balance approval, and native/store readiness remain separate claims.

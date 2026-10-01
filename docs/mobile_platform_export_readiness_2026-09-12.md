# AOEM mobile platform export readiness

Historical filename retained for links; status refreshed 2026-09-13.

## Summary

| Target | Status | Exact boundary |
| --- | --- | --- |
| Production Web artifact | **LOCALLY VERIFIED** | Canonical/repro builds, closure, scoped content/security scan, MIME, offline behavior, both exact-size browser flows, and independent audit pass |
| Internal Web handoff | **NOT_YET_READY** | No private HTTPS URL/access method, host owner, tester-intake owner, test window, or rollback contact/location |
| Android | **BLOCKED** | No preset/package config, usable Java, validated SDK/binary templates, signing, artifact, device test, store work, or owner |
| iOS | **BLOCKED** | Xcode/template present, but no preset/app config, team/profile/signing identity, artifact, device test, TestFlight/store work, or owner |

No public deployment, native export, signing, device installation, or store submission was performed.

## Production Web

| Field | Final value |
| --- | --- |
| Source revision | `89567778b26e` |
| Dirty state | `true`; preserved user working tree, bound by staged manifest |
| Staged-source SHA-256 | `54ada2e25cdb3c0690ef37580039b78fbe3198be2f21597fccc703b4e6458fa5` |
| Godot | `4.6.stable.official.89cea1439` |
| Evidence manifest | `docs/mobile_beta_evidence_manifest_2026-09-13.json` — **PASS** |
| Deliverable | `build/mobile-web-beta/`, built `2026-09-13T12:05:38Z` |
| Payload manifest | 18/18 closed entries; SHA-256 `27728ca36437a24ff6a8bc6a8a66e3eb1f75973ef38d65188586a9dc3b162e43` |
| Scoped content/sensitive scan | **PASS**; `compiled_diagnostic_symbol_absence=NOT_CERTIFIED` remains explicit |
| Canonical/repro PCK | both `e8cdc4467fcb41eb3f9fb1163d279a758a25d4b59ba76848fc53e2a61649e611` |
| Canonical/repro WASM | both `2b558bdb3c3af1f822ce6c43e09e1fa844d82fa440fe40d2d25d6c36ddf95137` |
| Reproducibility | **PASS**; only normalized build-time/cache-version metadata differs |
| MIME | **PASS**, 7/7 |
| Browser `844x390` | **PASS**, full touch flow and primed offline reload |
| Browser `932x430` | **PASS**, full touch flow with disclosed same-session replay |
| Independent closeout | **PASS** — P0 `0`, P1 `0`; `docs/mobile_beta_final_independent_audit_2026-09-13.md` |

The canonical payload is production-clean within the audits' declared scope: tools, tests, reports, temporary output, debug UI, editor bridge, and Godot MCP are excluded; no sensitive filenames, credentials, private/local/tunnel URLs, source maps, full private-key blocks, or unexpected custom URLs were found. Seven PEM header literals in the WASM are stock format constants, and the WASM hash equals the installed Godot release template.

Only `build/mobile-web-beta/` is a deliverable. `build/mobile-web-beta-repro-b/` is a reproducibility witness. `build/mobile-web-beta-repro-a/` is historical, unbound, and not closed: its old PCK differs, it has no staged-source manifest, and six `.png.import` files are outside its manifest. Never deploy `repro-a`, and never copy or serve the parent `build/` directory as a release payload.

## Private Web distribution blockers

| Required field | Current state | Next action |
| --- | --- | --- |
| Private HTTPS URL | **NOT_YET_READY — not supplied** | Authorized host owner provisions a private HTTPS origin |
| Host/operator owner | **NOT_YET_READY — unassigned** | Name an operator responsible for availability and headers |
| Tester-intake owner | **NOT_YET_READY — unassigned** | Name the recipient for reports/logs |
| Test window | **NOT_YET_READY — unscheduled** | Record start/end and supported time zone |
| Rollback contact/location | **NOT_YET_READY — absent** | Name contact and record recoverable previous-artifact path/version |
| Private access method | **NOT_YET_READY — absent** | Supply invitation/credentials outside version control |

The authorized host must serve `.wasm` as `application/wasm`, `.pck` as `application/octet-stream`, JavaScript as JavaScript, and provide HTTPS plus any required isolation/security headers. The local evidence does not authorize or perform deployment.

## Android — blocked

Evidence source: `docs/mobile_beta_native_toolchain_audit_2026-09-13.log`.

| Android field | Current state |
| --- | --- |
| Export preset/package configuration | **BLOCKED — no Android preset, application/package identity, or version configuration** |
| Java | **BLOCKED — `java` and `javac` report no Java runtime** |
| SDK/tooling/templates | **BLOCKED — an `sdkmanager` path exists, but no usable Java-backed SDK validation, binary Android export template, adb/device target, or successful export exists; only `android_source.zip` was observed** |
| Signing | **BLOCKED — no authorized keystore/alias/secrets or signed artifact** |
| Physical-device validation | **BLOCKED — no unfamiliar Android device session or installation** |
| Store/review | **BLOCKED — no metadata, privacy/data-safety record, screenshots, review/submission work, or owner** |
| Owner | **NOT_YET_READY — unassigned** |

Next authorized path: assign an Android owner; configure a reviewed preset/package identity; install and validate a Godot-compatible Java/SDK/binary-template toolchain; create signing material outside version control; export; then run the tester protocol on unfamiliar devices before any store claim.

## iOS — blocked

Evidence source: `docs/mobile_beta_native_toolchain_audit_2026-09-13.log`.

| iOS field | Current state |
| --- | --- |
| Available prerequisites | Xcode `26.6` build `17F113`; iPhoneOS SDK `26.5`; Godot `ios.zip` present |
| Export preset/app configuration | **BLOCKED — no iOS preset, bundle identity, entitlements, version, or privacy configuration** |
| Team/profile/signing | **BLOCKED — no authorized Apple team/profile/certificate; `0 valid identities found`** |
| Artifact/device validation | **BLOCKED — no signed iOS artifact, installation, or unfamiliar iPhone/iPad session** |
| TestFlight/store/review | **BLOCKED — no App Store Connect/TestFlight credentials, metadata, privacy declarations, screenshots, review work, or owner** |
| Owner | **NOT_YET_READY — unassigned** |

Xcode and `ios.zip` are prerequisites only. Next authorized path: assign an iOS owner/team; configure the preset/app identity and privacy data; provision certificates/profile outside version control; export and sign; then complete device, TestFlight, and review gates.

## External validation boundary

Outside humans and unfamiliar real phones have **not** completed the flow. Still open: 30-minute performance/usability, safe area/notch and browser chrome, keyboard behavior, audio, suspend/resume, install/offline behavior, touch comfort/discoverability, accessibility, thermal behavior, and balance/pacing.

## Authorized claim ladder

1. **Artifact built:** complete for canonical Web.
2. **Locally validated Web candidate:** complete; local execution/artifact/browser gates and independent closeout pass.
3. **Internal Web tester-ready:** **not yet**; private host and named operators missing.
4. **Externally validated:** **not yet**; outside-human and physical-device work missing.
5. **Native/store-ready:** **blocked**; target configuration, signing, artifacts, devices, metadata, review, and owners missing.

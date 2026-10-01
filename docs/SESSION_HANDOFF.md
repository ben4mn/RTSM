# AOEM beta roadmap session handoff

Latest deployment: 2026-10-01. The owner authorized a public rough preview at **https://game.4mn.org** on Debian. Runtime/packaging revision `8229a2093669` is pushed to `main`; the live canonical export is `build/game-web-2026-10-01/`, with a reproducibility witness at `build/game-web-repro-2026-10-01/`. The source manifest SHA remains `0b4193ffe40073504f2b336ec356d8d76a5852e912d9b145b86fdce7a1509f89`. See [debian_game_deployment.md](debian_game_deployment.md) for infrastructure, updates, rollback, stop, and phone installation. Local ports 8782/8783 remain stopped; the public deployment is independent. Physical-phone retesting and human balance approval remain open.

The current public release evidence is summarized in [public_game_preview_2026-10-01.md](public_game_preview_2026-10-01.md); it includes reproducible packaging, trusted public byte/MIME/cache checks, and real HTTPS/offline browser coverage.

Latest phone follow-up: 2026-10-01. Read [phone_input_2026-10-01.md](phone_input_2026-10-01.md) for the physical-phone feedback, arbitrary touch-ID selection/movement fix, placement multitouch ownership, modal cleanup, and browser fullscreen/standalone shell. Its earlier frozen export is `build/phone-input-2026-10-01/`. Both local test servers (8782/8783) are stopped on request; the public deployment above provides the current preview. Physical-phone retesting remains open.

The earlier October mechanics checkpoint is described by [mechanics_polish_2026-10-01.md](mechanics_polish_2026-10-01.md): worker recovery/cargo feedback, Town Center arrows, AI recovery/composition, paid-play evidence, and its separate frozen export at `build/mechanics-polish-2026-10-01/`. The October deployment resolves hosting for this public rough preview; the separate human/private-beta/native gates below remain historical or open as indicated.

The remainder is the historical September release handoff, refreshed 2026-09-13. Its canonical build and source binding describe that checkpoint, not the October mechanics export.

## Superseded historical note

The earlier contents of this file described an August 2026 checkpoint, a then-current seeded probe, and older phone/smoke totals. Those values are retained only in repository history. They are **not current release evidence** and must not be used to fill the 2026-09-13 closeout placeholders.

Files named `latest`, 2026-09-12 artifacts, earlier candidate builds, and earlier browser screenshot directories are historical unless the final validation record explicitly binds them to the frozen source. The final record now binds only the canonical `build/mobile-web-beta/` artifact and its `build/mobile-web-beta-repro-b/` witness. In particular, `build/mobile-web-beta-repro-a/` is unbound, not a closed payload, and must not be distributed.

## Current authority

Use these documents for current status and required evidence:

- `roadmap.md` — claim boundaries and gate order;
- `docs/mobile_beta_validation_2026-09-13.md` — canonical final validation record;
- `docs/mobile_beta_release_checklist.md` — operational closeout checklist;
- `docs/one_v_one_readiness_2026-09-12.md` — refreshed 1v1 acceptance contract despite its historical filename;
- `docs/mobile_platform_export_readiness_2026-09-12.md` — refreshed Web/native boundary despite its historical filename.

The source-binding artifact is `docs/mobile_beta_evidence_manifest_2026-09-13.json`. It records revision `89567778b26e`, dirty-state disclosure, staged-source SHA-256 `54ada2e25cdb3c0690ef37580039b78fbe3198be2f21597fccc703b4e6458fa5`, canonical/repro artifact identity, and the primary final report path, SHA-256, invocation, exit/result, and generation time. Its binding status is `PASS`; the independent closeout audit is performed against it afterward to avoid a circular self-attestation.

## Resume rule

1. Inspect the worktree and preserve unrelated changes.
2. Read the final validation record before interpreting generated reports.
3. Do not mix artifacts from different source states.
4. Treat the strict Medium / seed 202 probe as completion-authoritative.
5. Treat the multi-difficulty/seed matrix as liveness/policy evidence; its completion count is descriptive.
6. Keep external human/physical-phone validation, balance approval, private hosting/owners, and native/store work explicitly open until their real owners supply evidence.

All required local execution, package, exact-size browser, and independent closeout gates pass with P0 `0` and P1 `0`. Internal phone-tester handoff remains `NOT_YET_READY` until an authorized human supplies the private HTTPS URL/access method, host owner, tester-intake owner, test window, and rollback contact/location. This file remains only a navigation aid; the final validation record and independent audit own the detailed claims.

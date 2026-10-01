# Public rough-preview deployment — 2026-10-01

URL: https://game.4mn.org. The owner explicitly authorized pushing and publishing the current rough prototype to the existing Debian Docker/Nginx host.

## Release binding

- Runtime/packaging Git revision: `8229a2093669`, pushed to `main`.
- Canonical export: `build/game-web-2026-10-01/`.
- Reproduction: `build/game-web-repro-2026-10-01/`; all substantive payload bytes and source manifest reproduce.
- Source SHA-256: `0b4193ffe40073504f2b336ec356d8d76a5852e912d9b145b86fdce7a1509f89`.
- Payload manifest SHA-256: `8587752c1addb5f386eaa13be7d0a2b9a9e9802bb10b6a34d949106d501f066a`.
- Built: `2026-10-01T21:32:49Z` with Godot `4.6.stable.official.89cea1439`.
- `source_dirty=true` truthfully discloses preserved historical generated docs/QA outside the production stage; runtime and packaging files are committed.

## Deployment verification

- Python checks: **28/28**, including **13** Web/PWA packaging checks.
- Godot headless game boot: exit `0`. Editor import generated missing UID metadata; its separate MCP listener was already occupied by the user's existing editor. The production export excludes that addon and debug overrides.
- Real 192px icon generated from the source SVG, plus existing 512px icon, verified in the standalone landscape manifest.
- Nginx syntax and Compose configuration valid; game and tunnel containers running with automatic restart.
- Dedicated network `10.33.0.0/24` selected after checking existing networks/routes; other apps and the shared tunnel/Nginx Proxy Manager were not restarted.
- Public payload: **20/20** exact hashes over trusted HTTPS for the byte-comparison requests; HTML/JS/WASM/PCK/manifest/PNG MIME verified. WASM and PCK both gzip-compressed.
- Public cache headers verified: `no-store, max-age=0, must-revalidate`, with `CDN-Cache-Control: no-store`; this fixes the zone's four-hour browser TTL override of a plain `no-cache` directive.
- HTTP redirects to HTTPS; independent ordinary Debian curl confirmed 301 followed by trusted HTTPS 200. Its first port-80 attempts briefly failed TCP connection before two passing retries. Online `/` now redirects to the manifest's `/index.html` entry. Missing resources return 404 rather than HTML.
- DNS uses dedicated tunnel `a81df93e-953f-4e38-9e7f-a5d208f1af1d`. Pass the game config explicitly for CLI routing; the system config otherwise overrides the positional tunnel name. The initial wrong route was corrected before closeout.
- Normal Debian DNS/HTTPS succeeds, as do public/authoritative DNS and Mac HTTPS using public Google DNS-over-HTTPS. The local Mac system resolver retained an earlier NXDOMAIN during initial verification; explicit live-edge resolution was used for the public byte comparison, with certificate validation enabled.

## Real HTTPS browser checks

- At `844×390`, DPR 2, the engine draws at `1688×780` and boots over trusted live HTTPS. Touch controls started a match and paid 50 Food to train a villager; population reached `5/10`.
- The service worker activates and initially precaches seven shell files. After a controlling online reload, CacheStorage contains the actual WASM, PCK, and audio modules with the expected MIME types.
- At `932×430`, with network disabled, `/index.html` returns 200 from the worker and boots the full game. Touch started a match and selected the Town Center; Pause → Fullscreen succeeded. The canvas is `1864×860` at DPR 2.
- Native AudioContext changes from suspended to running after a gesture, including offline; no page or audio-worklet errors. This verifies initialization/module fetching, not physically audible playback on a phone.
- An offline direct navigation to bare `/` misses the stock worker's cached HTML key. Online canonicalization to `/index.html` aligns normal visits with the tested installed entry. Old root-only bookmarks remain a bounded offline limitation.
- The isolated Chromium test uses the live Cloudflare edge address for hostname resolution because of the local Mac's cached NXDOMAIN; it does not intercept responses or bypass TLS. Service workers and the network are enabled normally until the explicit offline step.
- A fresh regular persistent Chrome profile reports `Page.getInstallabilityErrors=[]`. The live 192px and 512px icons decode correctly; the standalone/landscape manifest parses without errors. This verifies browser installation eligibility; it does not claim a physical OS installation.
- Final fresh-root navigation follows HTTPS 302 directly to HTTPS `/index.html` 200 and renders the menu with no console/page errors. One generic `net::ERR_FAILED` during the first persistent-profile reload remains unclassified and did not recur in the bounded next load. The browser's deprecated Apple-meta warning and cleanup-time canceled WASM/PCK requests are documented separately; no runtime page or worklet errors occurred.

## Operations and evidence

Live origin: `/home/ben/aoem/site/releases/8229a2093669-20261001/`, selected by relative `site/current` symlink. See [debian_game_deployment.md](debian_game_deployment.md) for updating, rollback and stopping only this app.

Detailed local evidence is under `output/pwa-publish-2026-10-01/`: release/repro export logs, artifact verifier, `release-payload.json`, and `public-payload-verification.json`. Historical October exports and local server shutdowns are preserved.

Independent public smoke: `output/phone-input-2026-10-01/publish-independent-smoke-final.json`, nine passing checks before the subsequent root-to-index canonicalization.

Final browser report: `output/playwright/pwa-publish/report.md`; its `evidence-manifest.json` binds machine-readable observations and 14 PNG captures, including explicitly labeled diagnostic failures and superseded captures. `canonical-entry-verification.json` confirms both schemes and query preservation land on trusted HTTPS `/index.html`; `deployment-config-hashes.json` confirms all three server configuration files match local source. Both owned headless browser processes are closed.

Physical-phone retesting, human balance approval, and native/store readiness remain open. This deployment is a public rough preview, independent of September's separate private tester process.

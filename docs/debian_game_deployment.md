# Debian game deployment

Public rough preview: https://game.4mn.org. The owner authorized public deployment on 2026-10-01. This uses the existing Debian host (`ssh debian`, user `ben`), Nginx in Docker, and a dedicated Cloudflare tunnel. It does not require changing the shared Nginx Proxy Manager or restarting the shared system tunnel.

## Layout

- Compose project: `/home/ben/aoem`, configuration copied from `deploy/`.
- Static releases: `/home/ben/aoem/site/releases/<release-id>/`.
- Active relative symlink: `/home/ben/aoem/site/current`.
- Origin smoke endpoint: `http://127.0.0.1:3062/` on Debian, bound to loopback.
- Containers: `aoem-game`, `aoem-game-tunnel` and `aoem-playtest-diagnostics`, all restart automatically.
- Private report storage: `/home/ben/aoem/diagnostics-data`, outside the static releases, mode `0700`, owned by collector UID/GID `10001:10001`.
- Isolated Compose network: `10.33.0.0/24`, selected after checking existing Docker networks and host routes; the server's automatic pools are exhausted.
- Tunnel: `aoem-game`, UUID `a81df93e-953f-4e38-9e7f-a5d208f1af1d`.
- Tunnel credential: `/home/ben/.cloudflared/a81df93e-953f-4e38-9e7f-a5d208f1af1d.json`, mode `0400`; mounted read-only. Never copy it into the repository, artifact, or static directory.

## Build and publish

Commit the runtime and packaging changes, then export with Godot 4.6:

```sh
tools/build_mobile_web_beta.sh build/playtest-diagnostics-bridge-fixed-20261011
```

Verify the closed payload checksum manifest and the packaging verifier before copying. Copy only the chosen exported directory, not the parent build directory or project. The export excludes developer tools, debug/MCP wiring, docs, deployment configuration, and credentials.

Copy `deploy/docker-compose.yml`, `nginx.conf`, `diagnostics.Dockerfile`, `diagnostics_server.py` and `.dockerignore` to `/home/ben/aoem/`. Preserve the existing `cloudflared.yml` and tunnel credential. The collector's Docker build context permits only its Dockerfile and Python source. On first installation, create the private data directory with owner `10001:10001` and mode `0700`; never copy it into a release.

Stream the artifact into a new release directory using `COPYFILE_DISABLE=1 tar` over SSH. Run `sha256sum -c SHA256SUMS.txt` within that directory. Build/start the private collector and verify its health before checking Nginx, which resolves the collector's Compose service name. Switch `site/current` with a relative symlink and atomic `mv -Tf`, so the existing read-only parent mount sees the new release.

From `/home/ben/aoem` on Debian:

```sh
docker compose config --quiet
docker compose build diagnostics
docker compose up -d --wait diagnostics
docker compose run --rm --no-deps -T aoem nginx -t </dev/null
docker compose up -d
```

For an ordinary static game release, preserve the running collector and tunnel. Restart only the game service if needed:

```sh
docker compose restart aoem
```

This restarts only the dedicated game service. Change or restart the collector and tunnel only when separately authorized and required by their own configuration changes. They use `unless-stopped`; Docker is enabled at host boot. Allow the collector to finish starting before checking its health or submitting a report. See [playtest_diagnostics.md](playtest_diagnostics.md) for private report lookup, bounded storage and player instructions.

The initial DNS route is created once using the existing authenticated Cloudflare CLI:

```sh
cloudflared tunnel --config /home/ben/aoem/cloudflared.yml route dns a81df93e-953f-4e38-9e7f-a5d208f1af1d game.4mn.org
```

Check trusted public HTTPS, correct WASM/JS/PCK MIME types, compression, `version.json`, all payload hashes, and actual browser startup. Complete an online reload with a controlling service worker before testing an offline reload. Keep at least the previous verified release for rollback.

Nginx sends `Cache-Control: no-store, max-age=0, must-revalidate` and `CDN-Cache-Control: no-store`. The zone's browser TTL replaced a plain `no-cache` header with four hours on JavaScript/icons, so verify the actual public response after changes. Explicit service-worker CacheStorage provides offline caching separately.

Online visits to `/` redirect to `/index.html`, matching the manifest's installed start URL. The custom worker caches a small welcome shell first and verifies the complete game when Play is chosen. Existing apps verify the full next release before installation succeeds. A complete cached release can launch offline; `version.json` and private reports remain network-only. The worker also maps an offline `/` navigation to cached `index.html`.

Always pass the game config and UUID for DNS commands. The server CLI otherwise reads its shared system tunnel config, which can override the positional tunnel name. If correcting a record created for the wrong tunnel, insert `--overwrite-dns` after `dns` and verify the logged tunnel UUID.

## Rollback and stop

On Debian, atomically replace `site/current` with the previous release's relative symlink:

```sh
cd /home/ben/aoem/site
ln -s releases/PREVIOUS_RELEASE current.next
mv -Tf current.next current
```

To stop this game only, run `docker compose down` from `/home/ben/aoem`. Existing sites and tunnels are independent. New clients check for updates on launch, return to the foreground and reconnection. Complete releases activate after every open window agrees it is safe; matches, Pause, results, settings and reports defer activation. Legacy clients do not understand this agreement, so close all old game windows and reopen online once to migrate. Browsers schedule worker checks; a closed or offline app cannot be forced to update. Predecessor caches are retained for late old-client requests; storage failure keeps the current complete release and retries later.

## Phone installation

On iPhone, open the URL in Safari and use Share → Add to Home Screen. Enable **Open as Web App** if shown, then add it and launch the new icon for standalone display. See [Apple's instructions](https://support.apple.com/guide/iphone/open-as-web-app-iphea86e5236/ios). On Android, use the browser's Install/Add to Home Screen action. Landscape is the intended orientation. Browser fullscreen availability varies; the installed standalone app removes the normal browser address bar.

This is a rough public preview. Desktop browser automation does not certify physical-phone touch behavior, safe areas, audio, or prolonged performance.

## Latest release — 2026-10-12 icon controls

Published `releases/25fd059ed176-20261012-icons`, runtime `25fd059ed176`, version `0.1.0-beta.4`. Canonical export: `build/icon-hud-published-20261012`; independent witness: `build/icon-hud-published-reproduced-20261012`. Clean staged source SHA-256: `01803f3d63aea821937696431119a4ec9de745b706c5cc340dc3e51b24ac4616`.

The atomic switch completed at 23:16:02 UTC. All 27 public hashes, trusted HTTPS, MIME/compression, isolation/no-store and private-read denial pass. Fresh public report `PK-4B6C04521067` and updated-old-client report `PK-8D2728D49145` match clean loaded/served identity and were verified in private collector storage. The beta.3 browser retained its 00:03 paused match and Report while beta.4 waited, then automatically reloaded only after Quit to Main Menu. This was an ordinary browser, not an installed PWA.

No service restart was needed; game, tunnel and collector start times remained unchanged. Retained rollback: `releases/3c31d866a2c4-20261012-large-maps`. Runtime commit `25fd059ed176c4b01f3eec1594e1cc4a574894e3` was pushed before publication; final documentation-only HEAD intentionally differs. See [icon HUD pass](icon_hud_pass_2026-10-12.md) for scoped tests, completed Easy/Medium matches, limitations and exact release receipts.

## Previous release — 2026-10-12 larger maps

The larger-map and mobile-camera pass is published as `releases/3c31d866a2c4-20261012-large-maps`, runtime `3c31d866a2c4`, version `0.1.0-beta.3`. Canonical export: `build/large-maps-published-20261012`; independent witness: `build/large-maps-published-reproduced-20261012`. Their staged source SHA-256 is `c92be762ae87a9e6af222399d54919a60e2ddb78fad454999201d11bbfa78e0e`.

All 27 public payload hashes, trusted HTTPS, MIME/compression, isolation/no-store headers and private-read denial pass. Fresh private report `PK-BB28FA624417` matches the clean loaded/served runtime and private collector storage. The existing beta.2 browser deferred the update through Report and Pause, then automatically activated it at Main Menu; its new report `PK-330918F9D08B` also matches clean beta.3 and private storage. This is an ordinary browser lifecycle check, not installed-PWA or physical-phone verification.

The atomic release-link switch needed no container restart; game, tunnel and collector start times stayed unchanged. Retained rollback: `releases/8e6fe0ecfb78-20261012-pwa`. Runtime commit `3c31d866a2c42f90ef708aebff96f84a93c06bdc` was pushed before publication; later documentation-only HEAD intentionally differs. See [larger-map pass](large_maps_pacing_2026-10-12.md) for tests, actual match results, paired timing limitations and release receipts.

## Previous release — 2026-10-12 welcome and updates

The browser welcome, optional installation guide, release notes and verified automatic updater are published as `releases/8e6fe0ecfb78-20261012-pwa`, runtime `8e6fe0ecfb78`, version `0.1.0-beta.2`. Canonical export: `build/pwa-onboarding-published-20261012`; independent witness: `build/pwa-onboarding-published-reproduced-20261012`. Their staged source SHA-256 is `233d47b600e0c316b456e7b3b291f98c62bba0c187f7f549ce4574de8d2aef12`.

All 27 public payload hashes, MIME/compression, isolation/no-store headers and private-read denial pass. Fresh private report `PK-01041A574586` matches the loaded and served clean runtime. Only `aoem` restarted; the tunnel and collector were preserved. Retained pre-pass rollback: `releases/a8c20088acd1-20261012-resilience`. See [Web/PWA handoff](pwa_welcome_updates_2026-10-12.md) for browser/offline/update evidence and precise limitations, and [prior gameplay handoff](resilient_skirmish_pass_2026-10-12.md) for match results.

## Historical release — 2026-10-11

The character/menu redesign, mobile holds and input diagnostics are published as `releases/def645382dbd-20261011-playtest`, runtime revision `def645382dbd`. Canonical export: `build/playtest-diagnostics-bridge-fixed-20261011/`; reproducibility witness: `build/playtest-diagnostics-bridge-fixed-20261011-reproduced/`. Both have staged source SHA-256 `0e1766b333ade806ee801d259fd69853f9fba8fce921ff1f90d7dc80be8132e7` and identical game packs. All 21 public files pass exact decoded hashes, trusted HTTPS, MIME, compression, isolation and no-store checks. All three containers were restarted, and the private collector is healthy.

An actual public match at 844×390 exercised unit selection, camera pan/zoom, Pause and **Report problem**. Its acknowledged report was found in private storage with the exact code/note, matching loaded/served revision, GUI routing and preceding input history. The full pre-bridge-fix gameplay suite passed 116/116; eight relevant checks passed again on the final runtime after the Web-only bridge correction. See [playtest_diagnostics_validation_2026-10-11.md](playtest_diagnostics_validation_2026-10-11.md) for the evidence scope. The previous fully verified gameplay release `releases/3e1e3519be2b-20261010` remains available for rollback; its saved pre-collector Compose/Nginx configuration is in `deployment-backups/cdf268f-20261011/`. The intermediate `cdf268f39a66` release is retained as diagnostic evidence and should not be chosen for functioning report UI.

## Previous release — 2026-10-10

The critical gameplay and mobile density update uses runtime revision `3e1e3519be2b`, canonical `build/critical-mobile-final-2026-10-10/`, witness `build/critical-mobile-final-repro-2026-10-10/`, and staged source SHA-256 `86d5dad7dcf6d6c3a34451b59434f9672b2023615260d3dce8a968c75a166244`. That publication passed all 20 public payload hashes, trusted HTTPS, MIME, compression and no-store checks. See [critical_playtest_2026-10-10.md](critical_playtest_2026-10-10.md) for its gameplay and validation evidence.

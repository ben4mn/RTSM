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

## Latest release — 2026-10-28 hold to command

Published `0.3.0-beta.18` (protocol 13) from `a2edbd8c8fbb` on 2026-10-28. It adds hold gestures (lift = queue, drag = box, building drag = rally, pull down = attack-move), makes the selected villagers the builders, and gives Houses 20 housing. Static target: `releases/v030beta18-a2edbd8c8fbb`, all `SHA256SUMS.txt` entries verified on Debian. Server context `deployment-candidates/v030beta18-a2edbd8c8fbb/context`, image tagged `aoem-online:v030beta18-a2edbd8c8fbb` and `aoem-online:local`. Before cutover there were zero non-LISTEN sockets on 9080, and only `online` was replaced (it logged `AOEM_MATCH_SERVER_READY port=9080 protocol=13`). Nginx, diagnostics and the tunnel were untouched. Public `version.json` reads beta.18; `index.pck/js/wasm` public bytes match the release; a live browser created an online room.

Rollback: static `releases/v030beta17-d64bcb675e6f-1e18cc4aa2-cd853ca4a8`, server context `deployment-candidates/feedback-d64bcb6-smoke-20261027222945-8c8115a0/context`, image `aoem-online:rollback-v030beta18-a2edbd8c8fbb` (recorded in `deployment-backups/v030beta18-a2edbd8c8fbb/previous-state.txt`). Swap both symlinks back, retag the rollback image as `aoem-online:local` and run `docker compose -f docker-compose.yml -f docker-compose.online.yml up -d --no-build --no-deps online`.

## Previous release — 2026-10-24 read the battle

Published `0.2.0-beta.13` by atomic static switch at `2026-10-24T01:08:55.912368+00:00`. Runtime `e2359dd57283eea5ca8edffbbb841e2f9bdbeaae` adds mounted-unit/building presentation, construction stages and army inspection. Canonical and reproduced exports are `build/deployed-beta13-20261024` and `build/deployed-beta13-reproduced-20261024`; the sealed local server context is `build/deployed-beta13-match-server-20261024`.

| Release identity | Value |
| --- | --- |
| Source tree SHA-256 | `10c5365c11ffad5855942b330e1739619bfb2b561220901ef139485a70244595` |
| Static target | `releases/beta13-e2359dd57283-c5f84fcde0-e6754b0fc7` |
| Server-context manifest SHA-256 | `c5f84fcde0ce72d71ff543b6e1d72c12fded5851966de75b6dbee9aa911f868f` |
| Web manifest SHA-256 | `e6754b0fc73f5eac4eb6b426904993842139c9281de1a84190be02e62fab0309` |
| Server image | `sha256:0bab19c5837b2bac8861e2c7a00c96ec0b078d482af06e19deec220686a1657d` |
| Online container | `f340155a5e0eadd90d79ab0ace657cf88f420b6467fcd01359c4807848102e8c` |

The remote context is `/home/ben/aoem/deployment-candidates/beta13-e2359dd57283-c5f84fcde0-e6754b0fc7/context`. Its **800 payload hashes** include **462 committed runtime sources** and derived import data; all **798 runtime files** match in both the built image and running container. Isolated no-network startup passed with the production user, read-only filesystem, security options and 1.5-CPU/768-MiB limits; its disposable smoke container was removed.

The guard observed zero port-9080 sockets in **every non-LISTEN state** at `01:08:42.119271 UTC`, before replacing only `online`. The new container started at `2026-10-24T01:08:53.102113809Z`. Nginx `69b9c83cc44f`, diagnostics `77e08af5a56b` and tunnel `b8041fda214f` retain exact prior identities/start times; diagnostics is healthy. Reviewed Compose/Nginx configuration and existing infrastructure remain unchanged. The guard/replacement retains a small admission race; no traffic gate was added. Trusted public HTTPS verifies all 40 files, required MIME/cache/isolation headers and 13 denied private paths.

Rollback retains beta.12 static `releases/beta12-7681103e077c-33643af275-238d377893` and image `sha256:9c19932fc36ff1995158e7d18ca35fb1f602f1643d6d7b91e1e218e7d0df5db5`, tagged `aoem-online:rollback-beta13-e2359dd57283-c5f84fcde0-e6754b0fc7`. All **796 previous runtime files** matched its sealed context `/home/ben/aoem/deployment-candidates/beta12-7681103e077c-33643af275-238d377893/context`, manifest `33643af2755c4b703629568a59de45c247b5e8b3ea9a03cc6726b6380a14f46b`. Backup `/home/ben/aoem/deployment-backups/beta13-e2359dd57283-c5f84fcde0-e6754b0fc7` contains `previous-context.tgz`, `previous-state.json`, reviewed configurations and the nominal inventory. Unlike the earlier beta.12 cutover, the nominal context was already a sealed symlink matching the verified rollback source. Old image/static/context remain intact; review live identities and the idle guard before explicit recovery.

[Cutover receipt](../output/iteration-2026-10-24/beta13-deployment/cutover-receipt.json), [staging receipt](../output/iteration-2026-10-24/beta13-deployment/stage-receipt.json) and [public HTTPS receipt](../output/iteration-2026-10-24/beta13-deployment/cutover-https/receipt.json) retain exact identities and checks. See [the iteration report](read_the_battle_2026-10-24.md) for validation scope. The full two-browser River match ended naturally at 14:37 and both results/menu returns passed. The final 98.92 game seconds took 98.94–99.02 collector wall seconds (observational, not a render benchmark). Postflight at `01:26:48 UTC` reconfirmed runtime/public hashes, unchanged identities, zero non-LISTEN match sockets and zero restarts/OOM. Receipts are under `output/iteration-2026-10-24/beta13-postflight/` and in the iteration evidence archive. Test browsers are closed; the updated native game was visually confirmed and left at its main menu.

## Previous release — 2026-10-23 living battlefields

Published `0.2.0-beta.12` by atomic static switch at `2026-10-23T22:20:20.436206Z`. Target: `releases/beta12-7681103e077c-33643af275-238d377893`; clean runtime revision `7681103e077ce404d0741c178b21491b972bf6ed`; source tree SHA-256 `cbfe0006847624736fc1ffa06140124a59fa8fc1ac719a27a4d077ee6bc4f946`. Canonical/reproduced exports are `build/deployed-beta12-20261023` and `build/deployed-beta12-reproduced-20261023`; the local server context is `build/deployed-beta12-match-server-20261023`.

The remote candidate is `/home/ben/aoem/deployment-candidates/beta12-7681103e077c-33643af275-238d377893/context`. All 798 context payload hashes verify, including 460 exact committed runtime sources and derived import data. Context manifest SHA-256: `33643af2755c4b703629568a59de45c247b5e8b3ea9a03cc6726b6380a14f46b`; web manifest: `238d377893024b4622a66ea89f44fb56e8bd4376deef5985409fbc50dc3810bb`. Image `sha256:9c19932fc36ff1995158e7d18ca35fb1f602f1643d6d7b91e1e218e7d0df5db5` passed isolated no-network startup with the production user, read-only filesystem, security options and 1.5-CPU/768-MiB limits. Streaming the Docker runtime archive verified all 796 runtime files without extracting read-only directories; the replaced running container matches those same bytes.

The cutover guard observed zero port-9080 sockets in **every non-LISTEN state** immediately before replacing only `online`. The new container `7af9555530e5` started at `22:20:17.645115965Z`. Nginx `69b9c83cc44f`, diagnostics `77e08af5a56b` and tunnel `b8041fda214f` retain their exact prior identities/start times; diagnostics remains healthy. The socket check and replacement have a small admission race, documented in the plan. Public HTTPS verifies all 40 decoded payloads and 13 denied private paths.

Rollback retains beta.11 static `/home/ben/aoem/site/releases/94323bc4-settled-menu-20261023` and image `sha256:b821423cfb5ea2e129cd94932a11da691f0f3fd207b52792163f274bee1831ff`, also tagged `aoem-online:rollback-beta12-7681103e077c-33643af275-238d377893`. Its **770 running runtime files** matched `/home/ben/aoem/deployment-candidates/server-beta11-b48ebbb5c013`, manifest SHA-256 `3b79ae481b87d20cececc310ca14a2def7ed2eeee6240aac7ebca02365561f14`. Backup directory `/home/ben/aoem/deployment-backups/beta12-7681103e077c-33643af275-238d377893` contains that verified context as `previous-context.tgz`, `previous-state.json`, reviewed configuration backups and the nominal inventory. Its `previous-context-directory` preserves the stale, unsealed former `/home/ben/aoem/match-server`; that directory is not the attested rollback source. Old static/image bytes remain intact. Review live identities and the idle guard before any recovery; no automatic rollback interrupts matches.

Receipts, including the failed staging/cutover preparations, are retained under `output/iteration-2026-10-23/beta12-deployment/`. See [the iteration report](living_battlefields_2026-10-23.md) for scope and validation. The full two-browser River match and both menu returns pass; the retained last 99.75 game seconds take 100.25–100.33 wall seconds. Postflight at `22:40:22 UTC` confirms the same identities, zero match sockets in every non-LISTEN state and zero restarts/OOM. The report records observational timing limits and subsequent native main-menu confirmation after the user unlocked the Mac; the original blocked evidence is preserved.

## Previous release — 2026-10-23 command table and private lobbies

Published beta.9 at 18:42 UTC, beta.10 footer corrections at 19:05 UTC, and the final beta.11 direct-entry layout correction at `2026-10-23T19:24:43Z`. Final static target: `releases/94323bc4-settled-menu-20261023`; clean runtime revision `b48ebbb5c01369614aac35510382a3833e21c6dc`; source tree `94323bc46aedecadcfb976e93d3342d170e2aa8c20f396b6fd602f178c589505`. Server image `sha256:b821423cfb5ea2e129cd94932a11da691f0f3fd207b52792163f274bee1831ff` started at `19:24:42Z`. All 447 runtime files and all 40 public payloads match. Each cutover waited for zero connections and replaced only online; Nginx, diagnostics and the tunnel retained their exact original containers/start times.

This release publishes the [multiplayer stability and presentation overhaul](redesign_stability_2026-10-23.md). Publication, actual browser matches, cached-client update, layout fixes, observed late-game slowdown and postflight are recorded in [the live deployment report](live_deployment_2026-10-23.md). Canonical/reproduced exports are preserved at `build/deployed-beta11-20261023` and `build/deployed-beta11-reproduced-20261023`, with the closed server context at `build/deployed-beta11-match-server-20261023`.

Immediate rollback retains beta.10 static `releases/475bb5f8-fixed-lobby-20261023`, image `sha256:947bb896c0daaa5f120a77253a7dabf9a1d52b12350e0ffb145989b98cae265b`, and context/identity backup `deployment-backups/server-before-beta11-b48ebbb5c013-20261023`. The earlier beta.9/beta.8 releases and images also remain. The final immutable context is `deployment-candidates/server-beta11-b48ebbb5c013` under `/home/ben/aoem`.

## Previous release — 2026-10-22 find your fighters

Published `releases/5c363f3a-selected-fighters-20261022` at `2026-10-22T06:35:39Z`, version `0.2.0-beta.8`. Clean runtime revision: `c26be0f34f2b90a574f3a30ea75d669f1e382bc1`; staged source SHA-256: `5c363f3a38cb31bb50e5b4a040753cab6237fb328702dec62dd056c8096b45a7`. Canonical export: `build/selected-fighters-20261022`; independent witness: `build/selected-fighters-reproduced-20261022`. Both closed exports match in substantive payloads and source manifests. Runtime was committed and pushed before export.

Scope: [small foreground selection brackets](selected_unit_cues_2026-10-22.md), with 188 native and 148 headless assertions passing, plus the existing route regression. This release also records an [isolated desktop battle diagnostic](dense_battle_native_2026-10-22.md); it does not claim a runtime performance improvement or physical-phone certification.

The match server had zero established connections immediately before replacement. Online image `sha256:5be908a828aa74006355a5253e0902bacfb6a7b5983fb6e86292e0ba8c2179a2` started at `06:35:37.214465264Z`; the static symlink switched atomically and `aoem-game` restarted at `06:35:39.531019499Z`. The diagnostics collector remained healthy with its exact original ID/start, and the tunnel retained its October 12 start. Rollback: `releases/9daf8247-hold-site-20261022` and online image `sha256:2c59171b8d146495746fa9c4e907b960a46ebd32d8369d10db85a3840600ea0e`; previous context is `deployment-backups/match-server-before-selected-fighters-20261022`.

All 40 decoded public payloads match; all 13 private paths return 404. Trusted TLS, cache/isolation headers and required MIME checks pass. All ten public WSS checks pass from the exact frozen runtime, including both ordinary-resource production/combat clients, attack-move, visibility, replicated damage, Stand Ground on inert replicas and surrender/results. All 1,291 tracked hashes remain unchanged; all clients are closed. Zero runtime/script errors; four existing ObjectDB shutdown warnings remain (strategy-one, loading-ended, client-one and combat-one). The changed runtime overlay matches inside the running image. Postflight at `06:40:04Z` verifies zero match connections and server errors; every container retains its expected identity and state.

Fresh public 844×390 DPR3 touch emulation confirms the exact clean loaded/served identity, a full-canvas menu, Extra Large/asymmetric safe areas, ordinary Scout training/rally, touch selection, the cue during actual damage at 2:56–2:58, and automatic cue removal on death at 3:01. The explored-site badge returns correctly. Pause/menu return passes. Zero console errors; two software-renderer readback warnings. The browser is closed; this functional journey is not a performance measurement. See the [morning handoff](morning_handoff_2026-10-22.md) and tracked screenshots.

Raw receipts: `output/selected-fighters-deployment.json`, `output/selected-fighters-artifact-verification.txt`, `output/selected-fighters-public-browser.json`, `output/selected-fighters-running-runtime.json`, `output/selected-fighters-postflight.json`, `output/public-release-check/selected-fighters-20261022-live/receipt.json` and `output/selected-fighters-online-public/public-summary.json`. Later documentation-only commits intentionally differ from the embedded runtime revision.

## Previous release — 2026-10-22 hold the site

Published `releases/9daf8247-hold-site-20261022` at `2026-10-22T05:54:06Z`, version `0.2.0-beta.7`. Clean runtime revision: `2ab5c416cd4c9d7a3d65b39c46dda5cc1f51e9c1`; staged source SHA-256: `9daf824730f954187ab94ab21af12067ec1114d2273b0e85aef3f7e6c0fc6976`. Canonical export: `build/hold-site-20261022`; independent witness: `build/hold-site-reproduced-20261022`. Both closed exports match in substantive payloads and source manifests. Runtime was committed and pushed before export.

Scope: [Easy objective response and visible-site clarity](hold_the_site_2026-10-22.md), including 30 natural paid runs in 15 pairs and independent slower-learner/Medium/Hard comparisons. Easy can respond to a hostile Sacred claim from 150s; its ordinary base raids still wait until 300s, neutral initiative until 390s. The visible-site badge clears without changing public status or touch routing.

The match server had zero established connections immediately before replacement. Online image `sha256:2c59171b8d146495746fa9c4e907b960a46ebd32d8369d10db85a3840600ea0e` started at `05:54:04.574496772Z`; the static symlink switched atomically and `aoem-game` restarted at `05:54:06.683145625Z`. The diagnostics collector remained healthy with its exact original ID/start, and the tunnel retained its October 12 start. Rollback: `releases/efeaba3c-ground-20261022` and online image `sha256:89f64accb0569bd623bcba50b54ebf17841775553bade6cdfb9c6935a886d7a8`; previous context is `deployment-backups/match-server-before-hold-site-20261022`.

All 40 decoded public payloads match; all 13 private paths return 404. Trusted TLS, cache/isolation headers and required MIME checks pass. Fresh public 844×390 DPR3 touch emulation confirms the clean loaded/served identity, Extra Large/asymmetric safe areas, a normal paid Scout rally, contested loss by 3:05, restored fog badge and Pause/menu return at 4:20. Zero console errors; two software-renderer readback warnings. The three changed runtime files match inside the running server. All ten public WSS checks pass from the exact frozen runtime, including both paid production/combat clients, attack-move, visibility, replicated damage, Stand Ground on inert replicas and surrender/results. All 1,278 tracked hashes remain unchanged; all clients are closed. Zero runtime/script errors; three existing ObjectDB shutdown warnings remain (client-one, combat-one and loading-ended). Postflight verifies zero established match connections and server errors; the collector stays healthy and every container retains its expected state.

Raw receipts: `output/hold-site-deployment.json`, `output/hold-site-artifact-verification.txt`, `output/hold-site-public-browser.json`, `output/hold-site-running-runtime.json`, `output/hold-site-postflight.json`, `output/public-release-check/hold-site-20261022-live/receipt.json` and `output/easy-response-independent/public-final/public-summary.json`. Later documentation-only commits intentionally differ from the embedded runtime revision.

## Previous release — 2026-10-22 read the ground

Published `releases/efeaba3c-ground-20261022` at `2026-10-22T05:24:55Z`, version `0.2.0-beta.6`. Clean runtime revision: `c61918e45853a086cbdbcc99b860a0decdf1c402`; staged source SHA-256: `efeaba3c86f81f7637997de0bf71b86028ace1f5eedabaae08e335aa87c19ef9`. Canonical export: `build/ground-20261022`; independent witness: `build/ground-reproduced-20261022`. Both closed exports match in substantive payloads and source manifests. Runtime was committed and pushed before export.

Scope: [terrain, resource materials and notification priority](read_the_ground_2026-10-22.md), with [independent map and replication evidence](presentation_integrity_2026-10-22.md). This release changes presentation and toast input handling; AI and combat rules are unchanged.

The match server had zero established connections immediately before replacement. Online image `sha256:89f64accb0569bd623bcba50b54ebf17841775553bade6cdfb9c6935a886d7a8` started at `05:24:53.113889798Z`; the static symlink switched atomically and `aoem-game` restarted at `05:24:55.185186859Z`. All six changed runtime/shader files match the tested source inside the running server. The diagnostics collector remains healthy with its exact original ID/start, and the tunnel retains its October 12 start. Rollback: `releases/5d19e106-fieldcraft-20261022` and online image `sha256:912fabdd1754a4a94bcc714fc843fe75182a8925988a5277a611c480e13f6f70`; previous context is `deployment-backups/match-server-before-ground-20261022`.

All 40 decoded public payloads match, all 13 private paths return 404, and trusted TLS, MIME, no-store/CDN no-store, COOP/COEP and nosniff pass. The final frozen-commit public WSS suite passes ten cases including both paid production and combat clients, Stand Ground on inert owner-remapped replicas, visible enemies, replicated damage and surrender/results. Zero runtime errors; four existing ObjectDB shutdown warnings remain (client-one, combat-one, loading-ended, strategy-two). All 1,260 tracked file hashes remain unchanged. All clients closed; postflight finds zero established match connections and no server errors.

Raw receipts: `output/ground-deployment.json`, `output/ground-artifact-verification.txt`, `output/ground-postflight.json`, `output/public-release-check/ground-20261022-live/receipt.json` and `output/presentation-integrity-20261022/public-final/`. The public phone-size browser journey is recorded in the integration receipt. Later documentation-only commits intentionally differ from the embedded runtime revision.

## Previous release — 2026-10-22 fieldcraft

Published `releases/5d19e106-fieldcraft-20261022` at `2026-10-22T04:38:03Z`, version `0.2.0-beta.5`. Clean runtime revision: `84d61799b4c4c4638efff7a1b0f7b3915ed70090`; staged source SHA-256: `5d19e1065840d122da78ba0876ba0f55fcd14cf5691bbc28eda90460e7a653b6`. Canonical export: `build/fieldcraft-20261022`; independent witness: `build/fieldcraft-reproduced-20261022`. Both closed exports match in substantive payloads and source manifests, with only allowed build metadata differences. Runtime was committed and pushed before either export.

Scope: [Army field notes and integration](fieldcraft_2026-10-22.md), [Stand Ground acquisition](stand_ground_2026-10-22.md), [original industry buildings](company_industry_2026-10-22.md), and [paid tactical/Easy regression](paid_tactics_boundary_regression_2026-10-22.md). The guard fix changes some later fight outcomes; all three slower-learner Easy matches remain paid wins. These controlled policies do not establish human balance.

The public match server had zero established match connections immediately before replacement. Online image `sha256:912fabdd1754a4a94bcc714fc843fe75182a8925988a5277a611c480e13f6f70` started at `04:38:00.714915136Z`; the static symlink then switched atomically and `aoem-game` restarted at `04:38:02.834454716Z`. Diagnostics remained healthy, preserving its container/start, and the tunnel retained its October 12 start. Running-container hashes of all three edited runtime scripts match the tested source. Rollback: `releases/10c7d430-company-field-20261022` and online image `sha256:adbc5272c30c607c7e4e5299539c59b3256a2e6081987a0847097d321d0f049e`; prior context is in `deployment-backups/match-server-before-fieldcraft-20261022`.

All 40 decoded public payloads match; trusted TLS, MIME, no-store/CDN no-store, COOP/COEP and nosniff pass. All 13 private paths return 404. A fresh public Chromium touch journey at 844×390, DPR3, Extra Large UI and synthetic asymmetric insets verifies Army Info/Back/Close, full instruction fit, guide suppression/restoration, Pause and return to menu. Canvas remains 844×390 at (0,0). Zero console errors; two software-renderer ReadPixels warnings. No physical-phone or performance claim is made.

Public WSS verification passes all ten checks in one invocation from the frozen integrated runtime: both strategy clients, connection/loading failures, lifecycle, both paid economy clients and both combat clients. Both combat clients verify paid Barracks/Warriors, Stand Ground on inert owner-remapped replicas, attack-move, visible enemies, authoritative damage and surrender/results. Zero runtime/script errors; three nonfatal ObjectDB shutdown warnings remain (strategy-one, loading-ended and client-one). Ten clients use distinct private preferences; all 444 frozen source files still match the commit and all 88 runner source entries remain unchanged. All clients closed, zero established match connections remain, server logs contain no runtime errors, and diagnostics stays healthy. Evidence: `output/fieldcraft-online-public/verification-summary.json`, `source-receipt.json`, `commit-source-receipt.json` and sibling logs.

Raw receipts: `output/fieldcraft-deployment.json`, `output/fieldcraft-artifact-verification.txt`, `output/public-release-check/fieldcraft-20261022-live/receipt.json` and `output/fieldcraft-public-browser.json`. Later documentation-only commits intentionally differ from the embedded runtime revision.

## Previous release — 2026-10-22 company in the field

Published `releases/10c7d430-company-field-20261022` at `2026-10-22T03:56:30Z`, version `0.2.0-beta.4`. Clean runtime revision: `0a45f90e90b8`; staged source SHA-256: `10c7d4300daf36231b33b13dc1c01f1f55c0739e73854b21dde8458ba8f0e6a0`. Canonical export: `build/company-field-20261022`; independent witness: `build/company-field-reproduced-20261022`. Substantive files and source manifests match, and the remote payload checksum verification passes.

Immediately before replacement, the public match service had no established clients. Its new image is `sha256:adbc5272c30c607c7e4e5299539c59b3256a2e6081987a0847097d321d0f049e`, starting at `03:56:27Z`; `aoem-game` restarted at `03:56:30Z` after the relative release symlink switched atomically. The healthy diagnostics collector and tunnel retained their exact IDs/start times. Rollback is `releases/29fa2b41-room-to-learn-20261022` with online image `sha256:7ebc695cf8cf45043695cf769eb4ed3ce37249c7955c3e8c9d043c778fe3a015`. Prior server context is retained in `deployment-backups/match-server-before-company-field-20261022`.

Scope: [field UI integration](company_field_2026-10-22.md), [unit identities](company_units_2026-10-22.md), [specialist buildings](company_specialist_buildings_2026-10-22.md), and [paid tactical comparisons](paid_tactical_plans_2026-10-22.md). Raw deployment and reproducibility receipts: `output/company-field-deployment.json` and `output/company-field-artifact-verification.txt`. Later documentation-only commits intentionally differ from the runtime revision.

All 40 public decoded payloads match the canonical artifact (39 manifest entries plus the checksum manifest); trusted TLS, MIME, no-store/CDN no-store and COOP/COEP pass, and 13 private paths return 404. Fresh public Chromium touch emulation at 844×390, DPR3 verified full canvas, Extra Large asymmetric safe areas, guidance/management transitions, exact paid Villager training, Pause and return to menu. Zero console errors; three software-renderer readback warnings. This is not physical-phone performance certification. Receipts: `output/public-release-check/company-field-20261022-live/receipt.json` and `output/company-field-public-browser.json`.

Public WSS verification passes all ten cases: both strategy clients, connection/loading failure handling, lifecycle, both paid economy clients and both combat clients. Paid Barracks/infantry, attack-move, enemy visibility and replicated damage pass through the deployed authoritative server. Zero runtime/script errors; four subprocesses retain nonfatal ObjectDB exit warnings. All clients closed and all 37 recorded source hashes stayed unchanged. Server logs contain no runtime errors, no established match clients remain, and diagnostics remains healthy. Receipt: `output/company-expansion-online-public/source-receipt.json` and sibling logs.

## Previous release — 2026-10-22 room to learn

Published `releases/29fa2b41-room-to-learn-20261022` at `2026-10-22T03:27:05Z`, version `0.2.0-beta.3`. Clean runtime revision: `ca46ddbfb13f`; staged source SHA-256: `29fa2b41ff71e53e776584b82220836febc8fbb6f6dcb39b0b205d0d9076dff3`. Canonical export: `build/room-to-learn-20261022`; independent witness: `build/room-to-learn-reproduced-20261022`. Substantive files and source manifests match. All 39 public decoded payload hashes plus the checksum manifest match; MIME, no-store/CDN no-store, COOP/COEP and 13 private-path 404 checks pass.

The idle match service was rebuilt/recreated as image `sha256:7ebc695cf8cf45043695cf769eb4ed3ce37249c7955c3e8c9d043c778fe3a015`, starting at `03:27:02Z`. The static symlink switched atomically and `aoem-game` restarted at `03:27:05Z`. The diagnostics collector remained healthy with its `01:28:31Z` start, and the tunnel retained its October 12 start. Rollback remains `releases/8e935c1c-company-battlefields-20261022` with online image `sha256:50997db44c60511c68ffb0de94d9a6666a98c2fe42ea8f68c87c2728f936a5e7`; previous server context is retained in `deployment-backups/match-server-before-room-to-learn-20261022`.

Scope and evidence: [phone canvas and public touch journey](phone_edges_2026-10-22.md), [Easy paid comparisons](easy_learning_2026-10-22.md), [original buildings](company_buildings_2026-10-22.md). Actual public Chromium touch emulation at 844 × 390 DPR3 passed Standard/Extra Large menus, paid training/Repeat, live notch reversal, Pause and return to menu with zero console errors. It is not physical-phone performance evidence. Raw release receipts are `output/room-to-learn-deployment.json`, `output/room-to-learn-artifact-verification.txt`, `output/public-release-check/room-to-learn-20261022-live/receipt.json` and `output/room-to-learn-public-browser.json`. Later documentation-only commits intentionally differ from the runtime revision.

Public WSS verification also passed all ten checks against the deployed match server: two strategy clients; connection-failure, loading-ended, loading-failure and lifecycle checks; two paid economy clients; and two paid combat clients. Both players verified paid Barracks/infantry, attack-move, visible enemies and replicated damage. There were no runtime errors; four subprocesses emitted nonfatal ObjectDB exit warnings. All test clients closed and source hashes remained unchanged. Evidence: `output/overnight-online-public/source-receipt.json` and sibling logs.

## Previous release — 2026-10-22 company and battlefields

Published `releases/8e935c1c-company-battlefields-20261022` at `2026-10-22T02:36:43Z`, version `0.2.0-beta.2`. Clean runtime revision: `334fd81a70fb`; staged source SHA-256: `8e935c1ce9aef037f622f3be9f7ff3a26b2d0e8311b21f63ecdad3af3693b386`. Canonical export: `build/company-battlefields-20261022`; witness: `build/company-battlefields-reproduced-20261022`. Substantive files and source manifests match, and all 39 public decoded file hashes match. MIME, no-store, isolation and private-source read-denial checks pass. The original illustration retains its signed Content Credentials; the audit recognises only its specific provenance references in that PNG.

The idle authoritative service was rebuilt/recreated as image `sha256:50997db44c60511c68ffb0de94d9a6666a98c2fe42ea8f68c87c2728f936a5e7`, then the relative static symlink switched atomically and `aoem-game` restarted as requested. Online start: `02:36:41Z`; game start: `02:36:43Z`. The healthy diagnostics collector and tunnel kept their existing containers/start times. The previous static release `33ac3713-mobile-online-20261021` and old online image `sha256:121028c0531e5ab520061a41462cda493302e648df50b41f4dbe982e6c9920d7` remain available for rollback.

See [company and battlefields receipt](company_battlefields_2026-10-22.md) for scope, validation and public browser evidence. Later commits change audit/documentation only, so their HEAD intentionally differs from the clean runtime revision embedded in the release.

## Previous release — 2026-10-21 mobile gameplay and online 1v1

Published `releases/33ac3713-mobile-online-20261021` at `2026-10-22T01:25:12Z`, version `0.2.0-beta.1`. Canonical export: `build/mobile-online-20261021`; independent witness: `build/mobile-online-reproduced-20261021`. Both have staged source SHA-256 `33ac37134deb6a9bdc71f3603b1344c07559f85cb374e458748ebede6cf37dcf` and identical substantive payloads. The artifact was exported before the task's changes were committed, so its recorded base revision is `3a26757f1ed3`, explicitly marked dirty; the source-tree hash identifies its exact runtime contents.

All 26 public decoded payload hashes match; artifact closure, runtime/developer-material separation and two-export reproducibility pass. The final release changes only one confirmation string from the preceding browser-tested `1ef2c92e` build, replacing an unsupported arrow glyph with “to”. No simulation/protocol change was made after the paired public browser gameplay checks. See [mobile gameplay receipt](mobile_online_2026-10-21.md) for final browser identity and evidence.

The static symlink switch required no service restart. The new authoritative backend is image `sha256:121028c0531e5ab520061a41462cda493302e648df50b41f4dbe982e6c9920d7`; its isolated service and `/match` route are documented in [online multiplayer](online_multiplayer.md). The previous static-only release `releases/73250a6b0140-20261012-iphone` remains retained; a static rollback to it removes online entry, while the backend may be stopped separately without affecting solo hosting. The preceding `releases/1ef2c92e-mobile-online-20261021` is also retained and protocol-compatible.

### Diagnostics collector recovery — 2026-10-22 UTC

The final browser check exposed an existing collector failure: `/api/playtest-diagnostics` returned 502 and the collector reported `RuntimeError: can't start new thread`. Inspection found one live Python server thread, 62 zombie Python children adopted by PID 1, and the 64-process cgroup limit exhausted (44,385 limit events). There were no memory-limit or OOM events. The confirmed failure was unreaped child-process exhaustion, not a live request-thread leak. The shell-form Python healthcheck could leave adopted children after a probe timeout; the historical timeout that first created the zombies was not reproduced.

Only `aoem-playtest-diagnostics` was rebuilt/recreated using `docker compose up -d --no-deps --wait diagnostics`. Its Compose service now has `init: true` to reap adopted children, and its Docker healthcheck uses exec-form `CMD` without an intermediate shell. Image: `sha256:5092086bf278bc8580f4055220a35c339c58c294b56b199e81d7b3f9def67643`. Configuration backups are in `/home/ben/aoem/deployment-backups/diagnostics-reaper-20261022/`. The private `/data` volume was preserved. Its IP remained `10.33.0.4`, so Nginx needed no DNS refresh or reload. The static game, authoritative match server and tunnel retained their exact container IDs and start times; no frontend or gameplay reexport was needed for this maintenance fix.

Trusted public HTTPS POST returned 202 with `stored: true`, and the synthetic `diagnostics_reaper_check_20261022` event was verified in private storage. All 19 collector tests passed. Three scheduled healthchecks passed after recreation, with zero zombies, zero new PID-limit events and two steady processes (init plus Python); memory was about 15 MiB. Evidence: `output/diagnostics-recovery-public.headers`, `output/diagnostics-recovery-public.json` and `output/diagnostics-recovery-health.txt`. This verifies immediate recovery and child reaping configuration, not another nine days of uptime.

## Previous release — 2026-10-12 phone proportions

Published `releases/73250a6b0140-20261012-iphone`, runtime `73250a6b0140`, version `0.1.0-beta.5`. Canonical export: `build/iphone-proportions-published-20261012`; independent witness: `build/iphone-proportions-published-reproduced-20261012`. Clean source SHA-256: `c43461ec41c416e7c2535e1a8be9defc85c6bd33acb7309974fb04505c49491b`.

The atomic relative symlink switch completed at 2026-10-13T00:12:55.093667Z (October 12 local time). All 27 public decoded hashes, trusted HTTPS, MIME/compression, isolation/no-store and private-read denial pass. The beta.4 browser preserved its paid 00:00 Pause and Report while beta.5 waited, then automatically reloaded at ordinary Quit to Main Menu. Fresh public report `PK-9A99CDE408C9` and updated-client report `PK-44B1361B2E02` match clean loaded/served identity and exact notes in private collector storage. The fresh client also verified the welcome, beta.5 release notes and an exact paid Villager transaction. This was an ordinary browser, not an installed PWA.

No container restart or configuration change was needed. Verified rollback: `releases/25fd059ed176-20261012-icons`. Runtime `73250a6b01406a61dc8b19cdabde90108c74a4f5` was pushed before export/publication; final documentation-only HEAD intentionally differs. See [phone proportions](iphone_proportions_2026-10-12.md) for scoped tests, Retina rendering, completed paid matches, limitations and exact release receipts. The Easy Standard match lasted 30:18, so the intended 8–15 minute pacing is not established.

## Previous release — 2026-10-12 icon controls

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

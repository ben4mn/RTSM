# Offline Solo and incremental browser updates — 25 October 2026

The first complete Play download saves the welcome page, engine, game pack, fonts, artwork and other exported assets in this browser. A cached game can start Solo without a network connection. Online 1v1 requires a connection; a browser reporting offline receives an immediate explanation before opening a socket. The app does not save or resume an unfinished match.

## Audit and bounded change

The existing worker already checked downloaded SHA-256 hashes, staged each release separately, kept predecessor caches and required all open windows to consent before activation. A match, paused match, result or unresponsive older window prevents an automatic update. These safeguards remain.

Previously every new release fetched every payload file, including an identical WASM engine. The worker now checks its current partial cache and predecessor caches for the same filename, hashes the actual response bytes against the new release manifest, and copies a matching response into the new immutable release cache. Legacy caches without hash metadata can be reused after the same byte check. Only missing or changed files are fetched. An unchanged engine, font or artwork file is reused even when the source revision changes.

**The Godot PCK is one large file. If anything inside it changes, the whole PCK is downloaded.** This pass does not add binary patches or split game resources. Update checks still fetch the small service-worker script; diagnostic version checks remain network-only. “Only changed files” refers to game payloads, not zero network traffic while checking for updates.

The release ID is checked against the hash of its sorted file-hash map. Required boot files and the complete lightweight welcome shell must be present. A complete marker binds the entire manifest and is written only after every file is verified. Concurrent download queues are joined before failure is reported, preventing a retry from racing an unfinished writer. Cache quota errors, truncated responses, invalid manifests and interrupted downloads leave the preceding release intact. Cached bodies are audited once after worker restart; later status checks inspect presence and verified metadata rather than repeatedly reading the engine.

The launcher distinguishes a complete cached game from a partial first download. It requests persistent browser storage only after a verified playable cache exists. Refusal does not prevent Solo play. Storage can still be cleared by the user or, when persistence is unavailable/refused, evicted by the browser. No save data, settings, running match or old release cache is deleted to make space.

## Verification completed

- `node --test tools/test_pocket_updates.cjs`: 26 cases pass. Real SHA-256 and Response bytes are exercised with an in-memory CacheStorage implementation and mocked fetch, not a browser network session.
- `python -m unittest discover -s tools -p test_package_updates.py`: 2 cases pass.
- `python -m unittest discover -s tools -p test_web_shell_artifacts.py`: 20 cases pass, including exported source identity, content-bound release ID, full shell membership, asset hashes and the follow-up cached-boot/favicon check in `d22d620`.
- Cases cover root and installed `index.html` entry URLs, query strings, cold worker restart, full offline asset coverage, same/changed payloads, old-cache migration, corrupted bodies with plausible metadata, manifest truncation, interrupted transfer and retry, quota failure, rollback, declined persistence, and safe activation across busy/legacy windows.

The deterministic transfer example uses tiny fixture bodies: a first download transfers 73 bytes; an otherwise identical revision transfers 0 bytes and reuses all 73; changing only HTML and PCK transfers those two files and reuses WASM, fonts and art. These are test-fixture byte counts, not production bandwidth measurements. Before this change the same release transition fetched every file.

## Real browser evidence

Windows Chrome at a 1280 × 720 browser viewport, using mouse and keyboard, updated the cached beta8 release `9176284ece56-cb367bb46737faa11738` to candidate `37ebbd3e1877-b9147a8c2d47f6331854`. The disposable HTTP server's request log records exactly four changed payload files: `index.html`, `index.pck`, `pocket_launch.js` and `pocket_updates.js`, totaling **16,724,718 bytes**. The other **40,664,987 bytes** required no HTTP payload requests, including the unchanged 37,686,550-byte WASM engine. The worker hashes those reused bytes before accepting them. Small update-script/version requests and a favicon probe are separate from game payload transfer. The favicon and misleading first-launch boot text were subsequently addressed in `d22d620`.

After the cache update, the disposable origin at `http://127.0.0.1:8772` was stopped. A separate connection check confirmed that the origin was unreachable. A fresh navigation to `/index.html` then loaded the cached welcome page and booted the engine. The root reviewer started a French Solo match with a 100 population maximum, observed the initial four Villagers plus Scout at 5/15, paid 50 food to queue a Villager, and observed completion at 6/15 with an empty queue. The Scout accepted a Move order and reached its destination; food and wood deliveries continued; the pause menu opened. The captured browser warning/error log was empty.

Evidence is retained in the task's `outputs/beta9-offline/` folder:

- `browser-verification.json`, `browser-requests.jsonl`, `server-stopped.json` and `browser-console.json` record the method, transfers, unavailable origin and browser logs.
- `ready-online.png`, `offline-recruit.png`, `offline-recruit-complete.png`, `offline-move.png`, `offline-scout-arrived.png` and `offline-paused.png` show the saved-game notice and actual play.

This is a real browser test with its game HTTP origin unreachable. The device remained connected: DevTools Offline, `navigator.onLine === false`, airplane mode and physical-device behavior were **not** tested. The immediate browser-offline Online 1v1 message is implemented, but this origin-stop test does not exercise that browser signal. The earlier native computer-use route was abandoned when its URL-confidence policy stopped it; the successful proof used documented browser-tab controls and the disposable server.

No whole-browser restart, browser-storage longevity, offline multiplayer or match save/resume claim is made. This preview is committed source `37ebbd3e1877`, before final menu/performance changes and `d22d620` shell polish. Final release asset validation and public acceptance are recorded separately; these screenshots are not relabeled as the final public build.

## Primary references

- [MDN Service Worker API](https://developer.mozilla.org/en-US/docs/Web/API/Service_Worker_API): interception, lifecycle and offline caching.
- [MDN Storage API](https://developer.mozilla.org/en-US/docs/Web/API/Storage_API): Cache API storage and browser-controlled persistence.
- [Chrome service-worker lifecycle](https://developer.chrome.com/docs/workbox/service-worker-lifecycle): installation, waiting and activation.
- [web.dev PWA updates](https://web.dev/learn/pwa/update): manifest-based changed-asset updates and avoiding mismatched running versions.

The implementation uses those platform semantics; it does not add external scripts, a CDN dependency or a second application cache format.

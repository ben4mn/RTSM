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
- `python -m unittest discover -s tools -p test_web_shell_artifacts.py`: 19 cases pass, including exported source identity, content-bound release ID, full shell membership and asset hash checks.
- Cases cover root and installed `index.html` entry URLs, query strings, cold worker restart, full offline asset coverage, same/changed payloads, old-cache migration, corrupted bodies with plausible metadata, manifest truncation, interrupted transfer and retry, quota failure, rollback, declined persistence, and safe activation across busy/legacy windows.

The deterministic transfer example uses tiny fixture bodies: a first download transfers 73 bytes; an otherwise identical revision transfers 0 bytes and reuses all 73; changing only HTML and PCK transfers those two files and reuses WASM, fonts and art. These are test-fixture byte counts, not production bandwidth measurements. Before this change the same release transition fetched every file.

Actual desktop-browser Offline-mode gameplay, cold tab reopening and transfer observations are pending the matching candidate export. No physical-device, browser-storage longevity or offline multiplayer claim is made. This document will be updated with the browser evidence separately from the isolated tests.

## Primary references

- [MDN Service Worker API](https://developer.mozilla.org/en-US/docs/Web/API/Service_Worker_API): interception, lifecycle and offline caching.
- [MDN Storage API](https://developer.mozilla.org/en-US/docs/Web/API/Storage_API): Cache API storage and browser-controlled persistence.
- [Chrome service-worker lifecycle](https://developer.chrome.com/docs/workbox/service-worker-lifecycle): installation, waiting and activation.
- [web.dev PWA updates](https://web.dev/learn/pwa/update): manifest-based changed-asset updates and avoiding mismatched running versions.

The implementation uses those platform semantics; it does not add external scripts, a CDN dependency or a second application cache format.

# Playtest input diagnostics

During a match, use **Pause → Report problem** as soon as a tap or camera drag feels wrong. Add a short description and press **Send report**. Include the displayed `PK-…` code in your feedback. **Save log** downloads a JSON copy; **Back to Pause** leaves the match paused until Resume.

Recent game input logs save automatically while online. When offline, the browser keeps a bounded local history and pending reports, then retries after reconnecting. A report says “Saved online” only after the collector acknowledges its code. Closing/reopening all installed game windows online allows a waiting PWA update to activate.

The logs distinguish raw browser contacts, GUI ownership, selection hits/misses, nearest visible target geometry, tap movement/duration, hold/pan/pinch/cancellation, camera position/zoom, frame rate, UI scale, screen dimensions and actual loaded runtime revision. They preserve the report's preceding and following events. Observers do not handle input or change gesture thresholds, fog legality, commands, resources or simulation speed. No screenshots, recordings, chat, player names, cookies or credentials are collected automatically; a description is included only when the player sends it.

Godot retains at most 600 events, lifetime counters and a marked neighborhood of 120 preceding/80 following events. Browser uploads contain a smaller recent window and shrink to a 240 KiB maximum; background beacons shrink to 60 KiB. Delivery windows shrink when necessary; an individually oversized event is marked as truncated. At most eight pending browser reports are retained. Native play also saves `user://playtest-diagnostics.json` with an anonymous session/marker identifier.

The Python collector accepts only `POST /api/playtest-diagnostics`, through Nginx. It has no public report-reading endpoint. Its data lives in `/home/ben/aoem/diagnostics-data`, outside the static site, with an unprivileged container and read-only application filesystem. It enforces 256 KiB requests, bounded JSON, seven-day retention, 500 sessions, 32 reports/session and 64 MiB total storage. Report writes are atomic. Nginx omits access logging for uploads; the collector does not retain addresses, headers or full browser user agents.

Read a reported code through the dedicated container over SSH. This command searches only its private diagnostics directory and prints matching report paths:

```sh
ssh debian 'docker exec aoem-playtest-diagnostics find /data -name "PK-REPORTEDCODE.json"'
```

Read the returned path with `docker exec … cat`, or copy it locally for analysis. Avoid placing reports in the static release or Git repository. A useful feedback message includes the report code, what was attempted, expected/actual result, and whether the problem was repeated.

The latest publication and validation receipts live under `output/evolution/playtest-diagnostics-20261011/`. The deployment document identifies the active release and rollback release. Original R4, character redesign and mobile interaction evidence remains unchanged. Physical-phone comfort and performance require new player testing; earlier static-host logs cannot reconstruct historical taps.

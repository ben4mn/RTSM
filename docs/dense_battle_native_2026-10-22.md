# Paid dense battle native diagnostic — 2026-10-22

One focused desktop run passed its validity gates. Its dense combat subset had a 9.226 ms 95th-percentile render-completion interval and an 18.725 ms maximum. This evidence does not justify a runtime optimization. It does not establish physical-phone, Web, GPU execution, display presentation or exported production performance.

## Scope and paid setup

The executed archive was `5d825008de1699b92e2d9b917852723595c104da`; its scripts, assets and project settings exactly match published beta.7 runtime `2ab5c416cd4c9d7a3d65b39c46dda5cc1f51e9c1`. All 11 loaded source hashes matched the private stage. Godot 4.6 native debug, Apple M4, Metal Forward Mobile, default VSync mode 1, reported display refresh 60 Hz and unlimited Engine.max_fps were retained. Audio was muted; ordinary diagnostics persistence and development behavior remained active.

The fixed viewport was 844×390, UI scale 1.0, zoom 0.952 and camera world (32,1168), on Open Plains seed 101. Each side began with ordinary 250 Food/250 Wood/100 Gold and four workers, then bought six workers and six Warriors/four Archers/two Horsemen through normal queues, labor, buildings and Feudal advancement. Army cost was 580 Food/360 Wood per side. Both exact paid queue counts and bank ledgers reconciled; no economic bonus applied.

The existing test purchaser chooses the roster and suppresses autonomous field commands while retaining ordinary economics. Its military purchasing stops when the roster completes. This is a fixed purchasing/command policy, not the normal strategic AI. Both armies walked to separated staging points using passive Move and Stand Ground. No grants, free entities, teleports, fog reveal, modified stats or manual simulation were used.

Opening and staging were unsampled at 3×. The fixture switched to 1×, captured the staged view and settled for five wall seconds. Two group attack-moves then began the fixed-camera encounter. No added fixture I/O or screenshot occurred during sampling; normal runtime persistence remained. Frame callbacks append eight values; presence is sampled at 2 Hz. Probe overhead is included.

## Measured result

| Subset | Intervals | Summed intervals | p95 | p99 | Maximum |
|---|---:|---:|---:|---:|---:|
| Whole window | 3,510 | 29.791 s | 9.377 ms | 13.125 ms | 29.756 ms |
| Active combat | 2,346 | 19.875 s | 9.354 ms | 13.233 ms | 19.145 ms |
| Dense active | 810 | 6.856 s | 9.226 ms | 13.846 ms | 18.725 ms |
| Established dense | 575 | 4.860 s | 9.238 ms | 11.097 ms | 18.725 ms |

Active means military HP damage within the preceding second. Dense adds at least 16 viewport-visible military origins, cached at 2 Hz; it does not mean 16 simultaneous attackers or HUD-unobscured figures. Established dense begins two seconds after first damage. Filtered streaks do not bridge excluded time gaps. Dense evidence exceeded the declared 150-frame/five-second adequacy gate but remains one short encounter.

All 24 military appeared in the viewport during the encounter, alongside normal off-camera economies: 44 initial units and 17 buildings total. There were 153 damage events totaling 1,251 HP, a sampled peak of five projectiles and three military survivors at the window end. No navigation failures occurred. Group dispatch took 11.395 ms and 9.720 ms; the next completion interval was 23.557 ms, confirming dispatch work is included. No whole-window interval exceeded 33.33 ms; no active interval exceeded 25 ms.

Actual sample wall time was 29.799788 seconds; game time advanced 30.008517 seconds, a 0.70% difference within the declared 1% gate. The initial partial interval is excluded. Focus remained present, camera/viewport/time scale stayed fixed, logs contained zero runtime errors, and no other Godot process was present immediately before or after. The root coordinated an exclusive native slot during measurement; no external polling workload ran inside it.

Engine TIME_PROCESS p95 was 29.585 ms for the full window and 18.718 ms for dense frames. This aggregate monitor is not pure script CPU time; these readings are preserved separately from direct render-completion cadence. Dense physics-monitor p95 was 0.232 ms and draw-call p95 was 233. Presence observation cost 2.825 ms total, peaking at 0.114 ms per observation.

Godot describes [frame_post_draw](https://docs.godotengine.org/en/4.6/classes/class_renderingserver.html#signals) as the end of viewport updates; it is not scanout or GPU execution timing. [Performance monitor definitions](https://docs.godotengine.org/en/4.6/classes/class_performance.html) likewise do not support a physical-phone FPS claim. Larger armies, other maps, long matches, browser exports, weaker hardware and audio remain unmeasured here.

## Reproduction and rejected attempts

The tracked runner uses separate preparation, import, focus and measurement steps. Use a fresh output directory and an exclusive Godot/browser slot. Preparation freezes the specified Git revision plus the current test harness and assigns private user data; it never silently includes uncommitted runtime edits.

```sh
python3 tools/run_dense_paid_native.py --mode prepare --revision 5d82500 --output output/dense-native-check
python3 tools/run_dense_paid_native.py --mode import --output output/dense-native-check
python3 tools/run_dense_paid_native.py --mode focus --output output/dense-native-check
python3 tools/run_dense_paid_native.py --mode run --output output/dense-native-check
```

`--project` and `--godot-app` override installation locations. The manifest retains the private stage path, source/asset hashes and launch configuration. Focus mode launches only a short probe through macOS LaunchServices and exits; run mode requires its successful recent receipt, then rechecks focus at boot, before/after settling and throughout sampling. If focus fails, stop or repeat only the focus check after normal activation settles. Do not weaken the gate or unlock/change security settings. An import is never combined with paid measurement. `--mode analyze` recomputes the saved raw data without engine execution.

Three attempts were rejected and preserved: `run1` had an unfocused start and a fixture typed-argument error on freed units; `run2` fixed lifetime handling but rejected focus before timing; `run3` failed a standalone LaunchServices focus check and never began paid setup. The valid `focus4` stage passed an independent LaunchServices focus check, closed it, then ran the paid scene from that same prepared project without another import. No CUA click or security change was needed. The cause of earlier activation failures is unproven.

The executed output-only fixture and launcher hashes are recorded in the compact metrics JSON. Promotion retained the measurement and analysis logic, added a focus-only entry branch to the same scene, and packaged preparation/import/focus/run as explicit CLI phases with source validation and owned-process cleanup. Those packaging additions did not execute the recorded paid run: Python syntax, offline prepare and exact analysis recomputation were checked; integration also parsed the promoted GDScript with zero errors or warnings. No second paid run is claimed.

The compact receipt is `docs/dense_battle_native_metrics_2026-10-22.json`. Full local evidence remains in `output/dense-battle-native-20261022/focus4/`: raw intervals, subset summary, source/launch/isolation checks and `before.png`/`after.png`. The first screenshot retains enemy fog; the second shows the actual post-window encounter. Neither was taken while timing.


The complete valid raw measurement is preserved in GitHub as [a compressed JSON archive](evidence/dense-battle-native-20261022.json.gz), including every frame interval, damage event, queue event and resource-ledger entry. Decompression reproduces the exact original bytes, SHA-256 `b7c9067cf3e50b176751f449a2eca822300deeb5cec3c0d74e4912b762307f51`. The compact metrics remain convenient for review; the raw archive supports independent recomputation without relying on ignored local output files.

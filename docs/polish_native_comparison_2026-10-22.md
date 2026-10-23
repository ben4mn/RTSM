# Native paid-battle comparison — 2026-10-22

The existing baseline is frozen at `8493a48c9a41c1ef4b922345faa76440c4517833` in `output/polish-2026-10-22/performance-baseline/source.json`. A second stage can freeze the current uncommitted checkout without making a commit:

```sh
python3 tools/run_dense_paid_native.py --mode prepare --working-tree --output output/polish-2026-10-22/performance-current
```

`--working-tree` and `--revision` are mutually exclusive and apply only to preparation. The default remains a Git archive of HEAD. Working-tree preparation copies current tracked and nonignored untracked file bytes, honors tracked deletions, and rejects a detected edit during copying. It records `revision: working-tree`, `source_kind: working_tree` and `base_revision`; the base commit alone does not identify the measured code. `working-tree-inputs.json` records SHA-256 hashes of the original copied inputs. `source.json` records the staged runtime/harness hashes after the normal harness overlay and private-preferences rewrite. Generated `.godot` cache is copied separately and is not source evidence. Symlinks and non-file entries are rejected rather than leaving a snapshot dependent on external mutable content.

The staged project's private user directory preserves the user's main-project preferences. It remains necessary to import each prepared stage separately before measuring. A copied import cache is not evidence that changed SVG assets have been imported. The prepared baseline's probe, scene, purchasing policy and tactical opening hashes matched the current copies before this preparation change. The Python changes affect source preparation only; frame collection, analysis, validity gates and paid-game policy are unchanged.

After the root agent reserves an exclusive native slot, run each stage's import, focus and measurement steps serially:

```sh
python3 tools/run_dense_paid_native.py --mode import --output output/polish-2026-10-22/performance-current
python3 tools/run_dense_paid_native.py --mode focus --output output/polish-2026-10-22/performance-current
python3 tools/run_dense_paid_native.py --mode run --output output/polish-2026-10-22/performance-current
```

Use the same three steps with `performance-baseline` for the baseline. Do not prepare over its existing manifest or overwrite a completed `raw.json`. Later modes use the saved stage and settings; no source selection flag belongs on them. Both stages use the existing 844×390 request, 30-second measured window, ordinary paid roster, 3× unmeasured setup and 1× measurement. Focus receipts expire after ten minutes.

Compare accepted `summary.json` results only after both validity gates pass. Preserve whole, active, dense and established-dense subsets, their frame counts/durations, encounter outcome, environment, focus/isolation receipts and raw data. This is a paired diagnostic of two short native desktop debug encounters, not a statistically established performance regression, display FPS measurement, physical-device test or Web result. Gameplay changes may alter the encounter and subset membership; report those differences alongside timing.

Preparation validation used an isolated temporary Git fixture to check modified/new/deleted/ignored files, source hashes and concurrent-edit rejection, plus Python compilation and CLI help. No Godot process was launched by this preparation task and no new timing result is claimed here.


## Accepted comparison before the final texture pass

Both baseline 8493a48 and the complete uncommitted candidate passed every validity gate with the same purchasing policy and measurement harness. Separate imports and focused native launches completed; no other Godot process was present before/after, and root reserved the native slot. Default Metal Forward Mobile/VSync remained active on Apple M4, 844×390, 1× measured speed. Each side grew from four ordinary starting workers to ten with six paid recruits, and paid for 6 Warriors / 4 Archers / 2 Horsemen; all 44 actors were present, the roster started at full health, and exact queues/ordinary banks reconciled. No navigation failures or engine errors occurred.

| Whole 30-second window | Baseline | Final |
| --- | ---: | ---: |
| Render-completion intervals | 1,798 | 1,798 |
| p50 | 16.665ms | 16.669ms |
| p95 | 17.254ms | 17.483ms |
| p99 | 38.928ms | 24.904ms |
| Maximum | 50.891ms | 50.901ms |
| Frames over 33.33 ms | 20(1.11%) | 5(0.28%) |
| Longest over 33 ms streak | 1 frame | 1 frame |
| Dense-active sample | 399frames/6.667s | 424frames/7.059s |
| Dense-active p95 | 17.287ms | 17.351ms |
| Dense-active p99 | 46.240ms | 22.780ms |

Whole-window p95 rises 0.229 ms (1.3%), while long intervals are less frequent. This short paired desktop test found no material render-cadence regression. It is not statistical proof of a speedup or a physical-phone/Web/display-FPS/GPU-duration result. The new steering changes the encounter slightly, so subset membership and outcome need not be identical. Both dense subsets exceed the predeclared 5 s / 150 frame gate; no adequacy condition was relaxed.

Unmeasured paid setup reached readiness at 419.736 game seconds before and 466.117 after. A Farm now accepts one worker, so the fixed purchaser's economy is different; that preparation duration is not mixed into the battle timing. Actual measured wall time is 30.0184 s / 29.9969 s, and game/wall/focus/camera/viewport guards passed.

Final outputs are `output/polish-2026-10-22/performance-final/`; the earlier `performance-current` stage predates the expanded work and is not used in this comparison. The compact, self-contained receipt is `docs/polish_native_comparison_metrics_2026-10-22.json`. Both complete raw datasets are preserved under `docs/evidence/polish-native-{baseline,final}-20261022.json.gz`; decompression reproduces the recorded raw SHA-256. No timing is inferred from headless fixtures or screenshot-producing galleries.


## Final HD repeat — completed 23 October 2026

`output/polish-2026-10-22/performance-hd-final/` freezes the final HD candidate, including all asset import metadata. Two focus preflights initially stopped before paid warmup because macOS was locked. Those failed attempts are preserved under `focus-attempt1/` and `focus-attempt2/`; no timing was inferred from them. After the user unlocked the Mac, the third focus preflight passed and the same saved stage completed ordinary paid setup and native measurement. No validity gate, renderer setting or security setting changed.

| Measured sample | Baseline 8493a48 | Final HD |
| --- | ---: | ---: |
| Render-completion intervals | 1798 | 1800 |
| Summed frame duration | 30.000 s | 30.017 s |
| Actual measured wall time | 30.018 s | 30.026 s |
| p50 | 16.665 ms | 16.664 ms |
| p95 | 17.254 ms | 17.271 ms |
| p99 | 38.928 ms | 21.652 ms |
| Maximum | 50.891 ms | 49.688 ms |
| Intervals over 33.33 ms | 20 (1.11%) | 3 (0.17%) |
| Longest over 33 ms streak | 1 | 1 |
| Dense-active sample | 399 intervals / 6.667 s | 427 intervals / 7.117 s |
| Dense-active p95 / p99 | 17.287 / 46.240 ms | 17.189 / 22.685 ms |
| Established-dense sample | 279 intervals / 4.667 s | 307 intervals / 5.117 s |
| Established-dense p95 / p99 | 17.420 / 46.240 ms | 17.189 / 19.445 ms |

The final HD sample passes every validity gate: ordinary costs and exact queues/banks reconcile, both owners reached Feudal, all 24 military units were paid for, each economy grew from four ordinary starting workers to ten with six paid recruits, military began at full health, and measured focus/camera/viewport/game speed stayed fixed. It contains 158 actual damage events (1,292 damage), zero navigation failures and zero engine errors/warnings. No other Godot process was present before/after; the native slot was reserved throughout, with no screenshots during the timed sample. Root inspected the native before/after battle captures outside the measured window.

Whole-window p95 differs from baseline by +0.017 ms (about 0.1%). No material render-cadence regression was found in this short controlled desktop encounter. Rare long intervals were fewer, but this is not statistical evidence of a speedup. The encounter finished with two military survivors; active/dense subset membership and outcome differ between runs. Dense and established-dense samples exceed 5 seconds; no adequacy threshold was relaxed. Full-run wall time, including unmeasured paid setup, was 201.923 seconds; paid readiness occurred at 454.195 game seconds. That preparation time is excluded from the 30-second battle result.

The native desktop/debug/phone-sized-viewport scope remains the same as above: this does not establish display FPS, GPU duration, Web or physical-phone performance, or long-run strategic balance. Final runtime/art/import hashes match the checkout. The added `hd_final` entry in `docs/polish_native_comparison_metrics_2026-10-22.json` preserves source hashes, focus/isolation receipts and all frame subsets. The complete raw dataset is `docs/evidence/polish-native-hd-final-20261023.json.gz`; decompression reproduces the recorded SHA-256. Baseline and pre-HD evidence remain unchanged.

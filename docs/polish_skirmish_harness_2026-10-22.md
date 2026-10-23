# Integrated paid skirmish observer — 22 October 2026

## Scope and policy

`tools/probe_polish_skirmishes.tscn` performs two complete navigation journeys: Open Plains / seed 101 at a requested 1280×720 window, then River Crossings / seed 101 at 844×390. It dispatches actual viewport mouse input to the normal Start and result Menu buttons. The observer survives the ordinary scene changes and verifies the resulting menu is unpaused.

Both games use Standard rules, 30 population, normal starting banks and workers, no guided opener, and the unchanged Easy opponent. Player 0 uses the existing slower learner fixture: normal paid Main transactions, spaced building/training inputs, a delayed field opening and recovery after natural losses. Gathering, deposits, construction, queues, fog, navigation, combat and Sacred timers remain active. There are no grants, injected units, teleportation, instant damage, forced victories or disabled opponent simulation. The two normal speed-increase keys select the existing 3x maximum.

This is automated gameplay observation, not hands-on play or human beginner certification. The observer chooses visible human combat to frame the camera, otherwise the base or public Sacred location. Root owns visual inspection and hands-on follow-up. Landmark destruction is not guaranteed by this policy; the two natural Sacred results are the primary end-to-end coverage.

## Reproduction

Run from the project root, with an unused output directory:

```sh
python3 tools/run_polish_skirmishes.py --native \
  --output output/polish-skirmishes-20261022/native --timeout 900
```

Omit `--native` for fixed-60-Hz headless behavior checks. `--case 0` or `--case 1` selects one map. `--duration 900` is the default simulation-time cap per match; reaching it is a failure, never a forced result. Expect roughly 7–9 minutes for both native games at 3x, with an upper bound near 10 minutes if both reach the cap.

The runner freezes the current worktree, including uncommitted improvements, into a preserved temporary project; creates private user data; records source hashes; launches native Godot through macOS LaunchServices; and analyzes logs, loaded-source identity and results. On timeout, interruption or launch failure it terminates only Godot processes whose exact `--path` resolves to that unique temporary project. A synthetic process-inventory check verifies that unrelated editors, similarly prefixed paths and non-Godot processes are excluded. No process was signaled during that matcher check.

The scene also snapshots/restores preference-file bytes for direct runs. Prefer the runner's private user directory for concurrent development.

## Live inspection and evidence

- MCP node: `/root/PolishSkirmishes`, exported `probe_diagnostics`.
- Phases: menu, opening, economy-building, combat, sacred-hold, result, returned-menu, complete/failed.
- `progress.json` and console `[POLISH_PROGRESS]` update every 30 game seconds. Phase transitions print immediately.
- Native PNG checkpoints include both menus, opening, first completed human construction, first combat, Sacred capture/contest/final hold, developed economy, battlefield and result.
- Per-case JSON records exact loaded script hashes, grid identity, requested/actual sizes, bank ledger, deposits, paid unit completions, completed buildings, actual HP-loss/combat hits, AI field attack orders, navigation failures, natural winner/reason and menu return.
- Navigation failures are recorded as observations, not automatically treated as broken matches: temporary blocked routes can recover. New native runs include unit/type/position/target details for follow-up.

Native timing records process-callback wall intervals and the CPU process monitor at 3x, excluding the first two wall seconds of each match. A separate combat subset covers frames within two wall seconds of actual HP loss. Headless/fixed-FPS runs produce no performance sample. These are not display FPS, GPU timings, physical-phone results or a controlled regression comparison. Screenshots, observer work and other desktop activity contribute to measurements; coordinate expensive tests outside the native run.

## Headless tuning evidence

The initial complete real-scene run exited 0, with no errors or warnings in its returned output:

| Scenario | Natural ending | Game seconds | First HP loss | Menu return |
|---|---|---:|---:|---|
| Open Plains / 101 | Player 0 Sacred victory | 686.98 | 273.58 | Passed |
| River Crossings / 101 | Player 0 Sacred victory | 609.73 | 272.78 | Passed |

Both players in both games completed paid worker training and construction, deposited food and wood, and landed real combat hits. All six per-player resource balances reconcile against the ledger for each match. Raw results: `output/polish-skirmishes-20261022/headless-tune/`. This direct tuning run used the shared project and restored preferences; its receipts bind the scripts actually loaded before subsequent observer-only detail additions.

After adding window-size/navigation-event details, normal scene startup parsed successfully. A `--check-only --script` attempt was discarded because that standalone mode does not initialize project autoload identifiers; an intentionally truncated `--quit-after 1` startup emitted the usual ObjectDB-exit warning from interrupted coroutines. Neither invocation is claimed as a completed gameplay result. Python compilation and `git diff --check` pass.

Native screenshot/performance results are pending the root's coordinated run.

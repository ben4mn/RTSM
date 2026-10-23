# Selection and economy clarity — 23 October 2026

The selection dock now gives its meter a visible meaning: **HP**, **Stock**, **Build** or **Capture**, with a readable value. Foundations show completion separately from health, and tap Info no longer calls resource stock or Sacred capture “HP.” The 14px meter fits the existing 80px dock; the Town Center's internal gaps shrink by one pixel without changing its recruitment, Repeat, queue or Age Up targets. Parchment captions use 11px medium text on darker semantic colors, with a minimum calculated foreground/fill contrast of 5.07:1 across the authored meter colors.

Owned local Farms say **Needs 1 worker** or **Worker assigned** directly in the dock. The reservation remains visible during travel, gathering and drop-off. Enemy Farms and online replicas retain capacity-only information: the network snapshot does not carry Farm reservations. Inspection also found a concrete online defect: foundation replicas lack worker-to-building links, so the previous local scan incorrectly claimed **Needs builder**. Online foundations now show their authoritative completion percentage; local stopped-building recovery retains its existing warning.

The population counter highlights nearly full and full housing. Its accessible description and producer/House Info distinguish living units from paid queue reservations, explain House expansion and explain when canceling a queued unit can free reserved room. The normal paid population and refund rules are unchanged.

## Rendered comparison

| State | Before | Accepted |
| --- | --- | --- |
| Worker, maximum-scale phone | [Original dock](images/selection-before-phone-max-20261023.png) | [Health, work and cargo](images/selection-after-phone-max-20261023.png) |
| Foundation, desktop | [Health-only bar](images/selection-before-foundation-desktop-20261023.png) | [Completion and missing-builder feedback](images/selection-foundation-desktop-20261023.png) |
| Farm capacity | Capacity was only available in Info | [Assigned worker](images/selection-farm-phone-max-20261023.png) |
| Resource stock | Inspector incorrectly said HP | [Labeled remaining stock](images/selection-stock-phone-max-20261023.png) |
| Paid population | Full counter had ordinary styling | [Full housing and paid recruitment](images/selection-population-phone-max-20261023.png) |

These paired frozen projects differ only in `scripts/ui/hud.gd`. Both contain the same contemporaneous worker glyph code; glyph changes in the pictures are not attributed to this HUD batch. Menu code, including the fixed footer and first-show reflow, is untouched.

## Verification

The same final `test_selection_state_clarity.tscn` fixture fails **131 assertions** against the original HUD and passes **440 checks** against the candidate in both headless and native runs. The accepted native run contains **36 screenshots**: eight dock states and one supplemental Info view in each of four profiles. Profiles cover 1100×700, 844×390, and 844×390/932×430 at 1.15 scale; the last two dock profiles model side/bottom safe areas and 60 logical pixels of browser clearance. Actual ScreenTouch events open Info and verify its contents.

Checks cover caption text and contrast, text fit, unchanged dock height, safe-area bounds, resource/capture/health transitions, local and replica Farm semantics, online foundation feedback, and paid queue population. Two ordinary Villager queue purchases spend exactly 100 food and reserve two slots; cancellation clears those reservations. Health, resource stock, construction state, starting banks and capacity are disclosed fixture inputs. Farm assignment uses the production reservation API with modeled travel/harvest/delivery states. This is presentation and command-path evidence, not a completed match.

Five existing compatibility suites pass with no engine errors or warnings: eight-profile production feedback, thirteen-profile HUD composition, the 490-check research shelf, twelve-profile secondary-surface lifecycle, and four-profile paid foundation recovery/completion. These ran on the preceding candidate before the final caption contrast/font adjustment; the final 440-check headless/native fixture rechecks resulting geometry and readability. The coordinator's combined acceptance covers the integrated revision separately.

The initial candidate revealed a 2px Town Center height expansion, corrected before acceptance. Native review then rejected pale meter fills because their caption contrast was insufficient; the final darker fills and larger captions pass the added contrast checks. The first native snapshot omitted the project icon and logged a file-loading error. The snapshot was repaired, and the accepted final native run has **zero engine errors or warnings**. Rejected logs remain in the evidence archive.

## Evidence and limits

[Compressed evidence](evidence/selection-state-clarity-20261023.json.gz) retains exact before/after source manifests, the fixture, red/green and compatibility logs, final screenshot hashes and the earlier failed attempts. Expanded receipts and all 72 paired final pictures are in `output/selection-clarity-20261023/`. Accepted HUD SHA-256: `dc7d1c3e62225c19ded92cc3c95509e059f349eeece0222eb960b5e1655f751e`.

The dock screenshots model browser clearance in native windows; no actual browser toolbar, physical phone, multiplayer transport or performance measurement is claimed here. Four supplemental Info screenshots use ordinary native layout after deferred reflow and are excluded from safe-area evidence. Online reservation/staffing information remains intentionally unknown until authority snapshots expose it. All owned test clients exited before the coordinator's next engine work.

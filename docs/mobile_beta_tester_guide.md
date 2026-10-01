# Pocket Kingdoms Internal Mobile Web Beta — Tester Guide

Version line: `0.1.0-beta.1`
Test scope: one human player versus AI on the Pocket Duel map
Recommended first run: **Easy**, seed `424242`, Guided Opener enabled
Distribution status: **private internal test only**

Current handoff state: **NOT_YET_READY**. The locally verified artifact exists, but no private HTTPS invitation, host/operator, tester-intake owner, test window, rollback contact/location, or access method has been supplied. Do not begin a phone session from a locally guessed or public URL.

The invitation must supply these four values before a phone session starts:

```text
Private HTTPS URL:
Candidate source_tree_sha256:
Issue/feedback destination and response owner:
Test window and rollback/quarantine contact:
```

This is a landscape-phone Web beta. It is not an externally published build, a
balance-complete release, or an Android/iOS store build. Please report confusing
controls and dead ends even if you discover a workaround; this test is about whether
the game teaches itself, not whether an experienced RTS player can force it to work.

## Before You Start

- Use the private **HTTPS** test URL supplied by the release coordinator. Do not
  redistribute it or upload the build to a public host.
- Open `version.json` beside the supplied game URL once and compare its product version,
  source revision, `source_tree_sha256`, and build time with the invitation. Stop and
  contact the coordinator if they do not match.
- Use a current Safari on iPhone/iPad or Chrome on Android. Record the exact browser,
  OS version, and device model in your feedback.
- Rotate the device to landscape before starting. Keep browser page zoom at 100% and
  turn off “desktop site” emulation.
- Close memory-heavy apps if the browser repeatedly reloads the game tab. Keep the
  game in the foreground during a timed test.
- Start in the ordinary browser tab. You may also try Add to Home Screen/PWA behavior
  afterward, but report it separately.

The game must be served; opening `index.html` through a `file://` URL is unsupported.
HTTPS is the representative phone-test setup and is required for reliable service
worker/PWA behavior. A release coordinator can verify and serve the already-frozen
canonical artifact on the same computer without rebuilding or publishing anything:

```sh
cd build/mobile-web-beta
shasum -a 256 -c SHA256SUMS.txt
cd ../..
python3 -m http.server 8060 --directory build/mobile-web-beta
```

Do not rerun the builder into `build/mobile-web-beta/` during a test window; that would
replace the frozen candidate. A newly generated build starts a new candidate and must
repeat the full validation sequence.

Then open `http://127.0.0.1:8060/index.html` on that same computer. `127.0.0.1`
on a phone points to the phone, not the development computer; phone testers should
use the coordinator-provided private HTTPS URL.

## Match Setup

1. On the menu, choose **Easy**.
2. Enter seed `424242` so reports from different devices are comparable.
3. Leave **Guided opener for first match** enabled.
4. Open **Help & Settings** and confirm audio, camera speed, and UI scale. Start with
   Standard UI scale; repeat a short pass at Large or Extra Large if available.
5. Tap **Start Skirmish**.

Settings persist for this site in browser storage. A match does not: refreshing or
closing the page abandons the current match.

## Touch Controls

| Intent | Touch action |
| --- | --- |
| Pan the battlefield | Drag one finger on open battlefield. A small movement remains a tap; a deliberate drag pans. |
| Zoom | Pinch with two fingers. |
| Jump the camera | Tap a location on the minimap. |
| Select | Tap one of your units or buildings. Double-tap one of your units to select visible units of the same type. |
| Reselect a building while units are selected | Tap near the center of your owned building. A tap beside it remains a ground command. |
| Smart command | With units selected, tap ground to move. Military units use smart attack-move by default; villagers use ordinary move. |
| Gather | Select villagers, then tap a visible food, wood, gold, or Farm target. |
| Build an unfinished structure | Select villagers, then tap the friendly foundation. |
| Focus an enemy | Select units, then tap a visible enemy unit or building. Enemies hidden by fog are intentionally not command targets. |
| Resolve an ambiguous target | Hold a world target briefly to open the context action menu. |
| Select the army | Tap **Military** when it is shown. **Find Army** centers the camera on it. |
| Pause or change speed | Use the top-right pause button and speed button. Speed cycles through `0.5x`, `1x`, `2x`, and `3x`. |

When one or more of your units are selected, the command rail stays in this order:

- **Move** — arms one no-engagement move; tap the destination next.
- **A-Move** — arms one attack-move; tap ground or a target next.
- **Patrol** — available for military selections; tap the next patrol point.
- **Stop** — stops the selected units immediately.
- **Stance** — toggles Aggressive and Stand Ground. The acknowledgement names the
  resulting stance.
- **Clear** — deselects everything.

Move, A-Move, and Patrol are one-shot modes. The highlighted mode is consumed by the
next valid command. Watch for a destination marker, button state, sound, or a brief
notification after every command. Report a tap that produces no acknowledgement.

## Building, Production, and Advancement

### Construction

1. Tap **Build** in the lower-right rail.
2. Tap a building card. The battlefield becomes an explicit placement mode and the
   other bottom controls disappear.
3. Move the ghost over the map. The **entire footprint must be currently visible**;
   explored-but-dark or unexplored tiles are not legal placement. Green means valid.
   Visible invalid ground may explain terrain, overlap, or bounds; hidden/unknown
   ground deliberately reports only **Invalid placement** so fog cannot reveal an
   unseen blocker.
4. Tap a green location to place once. The game rechecks visibility, terrain,
   occupancy, and affordability before spending. A nearby idle or gathering villager
   is assigned automatically and uses bounded navigation/recovery to reach the job.
5. Tap **Cancel** to leave placement without spending resources.

The Build sheet, placement surface, pause menu, and match summary are separate modes.
Controls underneath them should not also activate. Please report any double action.

### Training and queues

1. Tap near the center of your Town Center or production building.
2. Tap a unit card to train it. The card shows cost and time.
3. Queue several units. Queue controls let you cancel the first queued unit of a
   displayed type, **Undo** the last queued unit, or **Clear** the whole queue.
4. **Auto Queue** repeatedly trains from that selected building while resources and
   population permit.
5. With a production building selected, tap ground to set its rally point. A completed
   unit must first appear at a reachable edge beside the building, then walk to the
   rally point; the rally itself is never a remote spawn location.

Population is reserved as soon as a unit is queued. If training is blocked at the
cap, build a House or cancel a reservation and confirm that the population display
recovers. If every perimeter egress around a producer is sealed, the unit must not
teleport through the obstruction: completion is rejected and its full resource and
population transaction is restored. Report a missing refund, doubled refund, unit
inside the building, or unit appearing directly at a distant rally as P1.

### Research and age advancement

- Select a Blacksmith to see available research actions.
- Tap **Age Up** when its button indicates that the resource requirement is ready.
  If it is not affordable, the notification states the missing food and gold.
- New buildings, units, and research unlock with age. Enemy buildings are
  inspect-only and must never expose working production controls.

## Match Objective and Ending

You can win by destroying the enemy Town Center or by holding the central Sacred Site
for three minutes. A contested site does not progress normally; its status and
remaining time appear in the HUD. The AI can scout, contest, capture, reinforce, and
defend the objective.

At an authoritative ending, the summary must show Victory or Defeat, game time, ending
reason, Feudal timings, scores, losses, resources gathered, and sacred control. Test
both **Play Again** and **Main Menu** when time permits. The game should return to a
normal unpaused menu and start another match cleanly.

## Known Limits and Watch Items

- This beta contains one single-player skirmish mode. Multiplayer, campaigns, factions,
  cloud saves, replays, monetization, and account systems are out of scope.
- Easy is the recommended onboarding profile. Medium and Hard apply faster decision
  cadence and more pressure, but human fairness and long-session balance are not yet
  signed off.
- Real-device browser coverage, thermal behavior, memory pressure, notch variations,
  and install/PWA behavior are still test objectives. Passing desktop emulation does
  not close those gates.
- Portrait play is unsupported. Rotate back to landscape if the browser changes
  orientation.
- A refresh, tab eviction, browser storage reset, or update to a newer candidate ends
  the current match. There is no resume save.
- Native Android and iOS packages are not part of this handoff. Do not treat the Web
  build as evidence of store readiness.
- Watch especially for pathfinding stalls near blocked terrain, large-army clumping,
  an enemy remaining targetable after fog hides it, accidental building reselection,
  a Move order stopping to fight, hidden terrain revealing placement details, a unit
  spawning at a distant rally, controls obscured by a notch/home indicator, or a modal
  tap also affecting the map. These are regression watch areas, not accepted behavior.
- Known local P2: fog graphics can trail a moving unit's visibility update by one idle
  frame because unit and fog processing share a priority. Selection visibility and
  command legality use the same current snapshot, so a hidden unit is not intentionally
  left commandable. Report any longer trail or any actual hidden-target interaction.

## 30-Minute First-Test Script

Use Easy, seed `424242`, Guided Opener on, and `1x` speed unless a step says otherwise.
If the match does not end by minute 27, switch to `2x` only to reach and inspect the
summary, and record when you changed speed.

### Minutes 0–3: launch and fit

- Load the HTTPS URL in landscape and note load time.
- Open Help & Settings, toggle audio once, and return it to your desired state.
- Confirm every menu action is fully on-screen and clear of the safe area.
- Start the match and take one screenshot of the free HUD.

### Minutes 3–8: guided opener

- Follow Gather → House → Scout → Scout move using touch only.
- Deliberately try one invalid House location, then cancel placement and reopen it.
- Place the House on green ground and confirm exactly one foundation appears.
- Queue the Scout, select it through the Military shortcut, and command it to open
  ground. Note any step whose next action was unclear.

### Minutes 8–14: economy and camera

- Send villagers to food, wood, and gold; verify acknowledgements and deliveries.
- Pan, pinch in and out, and tap the minimap without accidentally selecting or
  commanding units.
- Use the Idle Villager action when it appears.
- Build a Farm and deliver at least one food load from it.

### Minutes 14–20: construction and production

- Build a Barracks or other available military building.
- Tap its center directly while units are selected, then tap beside it and confirm
  that the two taps have different intents: selection versus ground command.
- Queue multiple units. Exercise one type-cancel action, Undo, Clear, and Auto Queue.
- Set a rally point. Approach population pressure and verify House/cancellation
  recovery. Confirm the next trained unit appears beside the producer and then walks
  toward the rally; it must not appear instantly at the destination.
- Advance an age if affordable and research one Blacksmith upgrade if available.

### Minutes 20–27: command rail, combat, and objective

- Form a mixed military selection and exercise Move, A-Move, Patrol, Stop, both
  stances, and Clear.
- Attack a visible enemy, retreat with explicit Move, then re-engage.
- Scout toward the Sacred Site. Try to capture or contest it and confirm the timer and
  minimap remain readable.
- Let an enemy leave vision; confirm that a hidden target cannot still be selected or
  commanded.
- Pursue either Town Center destruction or a Sacred Site ending.

### Minutes 27–30: lifecycle and report

- If needed, use `2x` to reach an ending and record that fact.
- Screenshot the summary and verify its ending reason matches what happened.
- Tap Play Again, pause/resume, then use Quit to Main Menu or the summary’s Main Menu
  action. Confirm the menu is responsive and unpaused.
- Fill in the feedback template below before memory of the input sequence fades.

## Reset and Cache Recovery

Try the least disruptive reset first:

1. **Match reset:** use Pause → Quit to Main Menu, then start again. Use Play Again
   from the summary when testing same-settings replay.
2. **Page reset:** reload the tab. This abandons the current match but retains
   preferences.
3. **Full candidate reset:** close every tab and installed PWA instance for this URL,
   clear that site’s data (cache, service worker, IndexedDB/storage, cookies), then
   reopen the exact private HTTPS URL. If installed, remove the Home Screen/PWA copy
   before clearing data.

A full reset clears saved difficulty, Guided Opener, audio, camera speed, and UI scale.
Menu defaults should return, with Easy and Guided Opener selected. To confirm that an
update actually arrived, open `version.json` beside the game URL and compare its
version, staged-source digest, and build time with the coordinator’s candidate record.
Only one candidate should be active on a given Web origin. If coordinators must keep
two candidates live in parallel, use distinct origins/subdomains rather than two paths
whose service workers can share and evict origin-wide caches.

Coordinators must deploy only `build/mobile-web-beta/`. Do not serve or copy the parent
`build/` directory. `build/mobile-web-beta-repro-b/` is only a reproduction witness,
and `build/mobile-web-beta-repro-a/` is historical, unbound, and non-deliverable.

## Collecting Useful Evidence

For every failure, capture the first bad action rather than only the later broken
state:

1. Record device, OS, browser/version, difficulty, seed, game speed, UI scale, and
   whether the game ran in a tab or installed PWA.
2. Note the wall-clock time and in-game time. Write the exact taps or gestures that
   reproduce it.
3. Take a screenshot or short screen recording that includes the full landscape
   viewport. Do not crop away the HUD or browser state relevant to the issue.
4. Capture the browser Console from the start of the repro through the failure. Enable
   “Preserve log” before reloading when available, and include the first error plus its
   full stack—not only a count of errors.
5. On Android Chrome, a coordinator can use desktop Chrome’s remote device inspector.
   On iOS Safari, a coordinator can use Safari’s Web Inspector from a paired Mac.
   Browser menu names vary by OS version; ask the coordinator if remote inspection is
   not already enabled.
6. If the page reloads or goes blank, also record free storage, whether the device was
   hot, and whether the tab had been backgrounded.

Send the report to the **issue/feedback destination named in the invitation**. Do not
post private URLs, checksums, logs, or screen recordings publicly. If the invitation
does not name an intake destination and response owner, stop and ask the coordinator
to complete the handoff record before testing.

## Feedback Template

```text
Pocket Kingdoms candidate version / source revision:
Tester name or initials:
Device model:
OS and version:
Browser and version:
Browser tab or installed PWA:
Orientation and approximate viewport/safe-area notes:
Difficulty / seed / Guided Opener on or off:
UI scale / game speed:
Session length:
Ending (Victory/Defeat/none), reason, and game time:

What I tried:
Expected:
What happened:
Exact reproduction steps:
Reproduction rate (for example, 3/3):
First confusing or missed tap:
Any stuck unit, unreachable target, or fog violation:
Any layout clipping/overlap:
Console error/warning and full stack:
Screenshot/video/log filenames:

Severity:
- P0: crash, blank screen, data loop, or cannot start/finish a match
- P1: core gather/build/produce/command/end flow blocked with no practical workaround
- P2: significant friction or wrong feedback with a workaround
- P3: cosmetic, wording, or minor polish

Best part of the session:
One change that would most improve the next match:
Would you voluntarily play another Easy 1v1? Why or why not?
```

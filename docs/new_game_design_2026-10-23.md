# New Game and the command atlas — 23 October 2026

The menu now leads through **Home → New Game → battlefield and opponent → Start**. Solo and multiplayer share the same battlefield cards. Private-room hosts choose the map; guests see that map, its terrain preview, description and selected state before the host starts. Settings contains Audio, Controls and Display only.

## Design decisions

The shared `KingdomTheme` now uses deep navy surfaces, warm parchment text, antique gold for actions and selection, cool blue for friendly information, and warm rust for opponents/errors. Cinzel supplies the inscription-like title hierarchy; Barlow remains the body and control face. Cinzel is bundled with its SIL Open Font License. Flat edged controls, consistent borders/focus rings, restrained selected-map outlines, section labels and inset panels replace the former textured button plates. `apply_heading`, `apply_eyebrow` and `inset_panel` are reusable theme helpers. The coordinating HUD pass uses this same system.

The home screen presents the existing original company illustration beside two clear entry points. New Game has persistent navigation and a persistent selected-map/start footer. At short landscape sizes the Solo/Multiplayer tabs move into the header, preserving the battlefield and Start action. Less frequent solo options scroll within a bounded panel; the map cards remain visible. Touch targets stay at least 48 logical pixels. A short entrance fade respects Reduced Motion.

Map previews are generated from the actual `MapGenerator` at representative seed 101. Blue/red circles identify starting sides; the central diamond identifies the objective. They communicate map structure rather than promising the exact random layout of the next match. Plain-language descriptions distinguish open raids, crossing control and wooded side routes. The optional solo seed is a match setting, alongside difficulty, guidance, rules and population, rather than an application preference.

Official references reviewed as currently published:

- [Age of Empires IV game page](https://www.ageofempires.com/games/age-of-empires-iv/): clear separation of medieval identity, civilizations and gameplay. Design inference: use a strong title/illustration on Home, then task-oriented grouping when creating a game.
- [Age IV accessibility](https://www.ageofempires.com/age-iv-accessibility/): strong-contrast menu examples, text scaling, camera speed and audio controls. Its examples are launch-era, not a claim to reproduce the latest live UI. Design inference: keep preferences separate, preserve scaling and reduced motion, and avoid reducing touch targets to fit more controls.
- [Official map voting](https://www.ageofempires.com/map-voting/): presents map choice as part of the multiplayer experience. Design inference: show the host’s battlefield explicitly to both participants rather than burying it in Settings.

The artwork and layout remain original; no Age of Empires assets were copied.

## Multiplayer flow

Create room uses the selected battlefield and presents the room code and joined-player count. Guests enter the code beside a Join action. Both sides display the server’s `match_map_archetype`; only the host can edit it. Start is disabled until two players join. A queued room waiting for an arena locks edits and repeated Start while retaining Leave. Connection errors appear above the options rather than below a scroll fold. Back leaves an active room before returning Home.

Quick match remains available as a compatibility path and explicitly states that the server chooses the battlefield. Private rooms require an updated server; the network compatibility tests and deployment status are recorded separately. This UI work does not claim that the previously deployed public server has been upgraded.

Results can request New Game in the corresponding solo/multiplayer mode through one-shot metadata. Starting solo still defers scene replacement until the input dispatch finishes. The transition regression exposed an additional deferred diagnostics callback arriving after menu removal; it now checks tree membership before accessing the viewport.

## Review loop and evidence

The first native capture produced 30 screenshots. Visual review caught three concrete issues: a disabled guest map lost its readable selected state; full gold map-card fills overwhelmed the previews; and Join sat below the normal phone fold. The second pass preserves the gold outline and selected label even when a card is read-only, uses restrained map selection, and places the code and Join button on one row.

The final native capture produced 40 views at 1280×720, 844×390, 844×390 with 1.15 UI scale, and that maximum scale with simulated 44px side/18px bottom insets. Actual `InputEventScreenTouch` events opened New Game, selected all three maps, switched multiplayer, opened Settings and selected all three preference tabs. The capture uses normal project stretch behavior; physical window dimensions and logical layout dimensions differ. All 40 views passed the capture checks with zero engine errors. Room states in this capture are explicitly modeled presentation states; they are not socket or two-client evidence.

Headless checks passed:

- `test_phone_menu_layout`: 396 assertions covering desktop/phone containers, synthetic safe areas, map choice/selection/description, difficulty/population, scroll reachability, host/guest permissions and queued-room locks, and preference-only Settings.
- `test_map_selection`: twelve actual menu→match journeys (three launch maps × two phone sizes × two scales), with `ScreenTouch` on New Game and map cards, exact generated-grid equality for seed 101, saved map choice at Start, and the ordinary four-worker opening.
- `test_menu_match_transition`: real deferred Start, paid Feudal progression, pause→menu, then a fresh match/HUD. Its stale node paths were updated for the redesigned menu and Pause surface.
- `test_audio_settings`: 12 phone/safe-area layouts across three tabs; wheel containment/scrolling, live preferences/reload/reset, real paused selection/camera, fog and bounded audio lifecycle.

Native captures and their detailed receipt are in `output/new-game-design-2026-10-23/`; the reusable harness is `tools/capture_new_game_design.tscn`. Accepted native review ran in a frozen project with private user data. The earlier transition fixture attempts stopped on stale test paths before their preference cleanup; the coordinator was notified to restore the existing preference baseline. No physical phone testing is claimed. Actual network stability, completed matches and the sustained two-client run have their own evidence in the final session report.

## Research shelf follow-up

The final HUD review exposed a concrete reachability bug: the Blacksmith's wide research cards exceeded the fixed command shelf, leaving Wheelbarrow clipped and Loom unreachable. The shelf now fits all four upgrades as 84×64 logical-pixel cards with separate name, effect and cost lines. Forge and Mail use short visible labels; their full names, costs, effects and current requirements remain available through hold details, accessible labels and the selection's tap-only Info action. Completed upgrades show **Complete** and stay disabled. Research cost and purchase behavior are unchanged.

The same `test_research_shelf.tscn` fixture failed against the pre-fix HUD with clipped controls and failed Wheelbarrow/Loom pointer purchases. The fixed HUD passes 490 assertions across 1280×720, 844×390, 844×390 at 1.15 scale with simulated insets, 932×430 at 1.15 scale with simulated insets, and 632×356. These checks cover full shelf/safe-area enclosure, 48px minimum targets, measured text fit, persistent button identity, live shortage/completion information and exact-cost purchases of every upgrade through actual pointer input. The existing `test_mobile_hud_composition` also passes all 13 profiles with a new assertion that every research card remains inside its shelf.

The coordinator captured the final native maximum-scale/notched HUD; visual inspection confirms all four names, effects and costs are readable: [accepted research shelf](images/hud-research-phone-max-20261023.png). The red/green logs, exact source hashes and fixture are preserved in [the research evidence archive](evidence/research-shelf-20261023.json.gz). These are deterministic layout and input checks, separate from the coordinator's sustained gameplay evidence.

## Representative images

An independent pass reviewed all 40 menu captures and 36 HUD captures across desktop, ordinary phone and maximum-scale/notched profiles. It verified the map names/previews/descriptions, selected and guest states, preference tabs, command captions, construction categories, research, pause and results. At maximum-scale phone sizes the Join row and secondary match options use the visible options scroll; the normal phone Join row is exposed without scrolling. Scroll reachability is covered by the menu tests.

That review found a second concrete HUD issue: desktop Town Center cards crowded Repeat out of the fixed shelf, and the first grouped queue control was partly clipped. The Town Center now consistently uses its compact recruitment/Repeat presentation, and the command shelf reserves a stable width for both recruitment and cancellation pages. Page alignment follows container/scroll-range changes while revision checks protect a deliberate return to recruitment. Compact identity typography also keeps the title, rally guidance and current training progress inside the dock. No training costs, production rules or refunds changed. The expanded production regression includes desktop and phone windows at both scales, real touch Repeat ON/OFF, Queue/Train/Undo/Clear, exact paid refunds, queue refresh/reopen races, all card bounds and identity text bounds. Supporting logs and source hashes are in [the desktop production evidence archive](evidence/desktop-production-shelf-20261023.json.gz).

The same final production fixture produces 21 assertion failures against the pre-fix HUD and passes all eight profiles against the fixed source. The final source also passes the 13-profile HUD composition and 490-assertion research shelf regressions.

Final native visual sign-off inspected recruitment/Repeat and the grouped queue at all three HUD profiles in `output/redesign-2026-10-23/release-hud/`. All six images keep the title and detail lines inside the panel and fully expose train cards/costs, Repeat, queue navigation, Undo/Clear and Age Up. [Desktop recruitment](images/hud-tc-desktop-20261023.png) and [desktop queue](images/hud-queue-desktop-20261023.png) show the corrected result. The evidence archive includes these six capture hashes and the coordinator's native source/capture receipts. No additional runtime changes followed this review.

The initial HUD placement captures were rejected as valid-placement evidence because they showed blocked ground despite their filenames. The coordinator corrected the fixture and captured verified green placement previews at all three HUD profiles. These are presentation fixtures, not physical-phone or sustained match evidence.

Exact pre-change menu captured this session from the frozen baseline: [before](images/new-game-menu-before-20261023.png). Current native results:

- [Home, desktop-sized window](images/new-game-desktop-01-home-20261023.png)
- [New Game, desktop-sized window](images/new-game-desktop-02-solo-map1-20261023.png)
- [New Game, phone-sized window](images/new-game-phone-02-solo-map1-20261023.png)
- [Create/join, phone-sized window](images/new-game-phone-03-online-20261023.png)
- [Guest’s shared map, maximum scale](images/new-game-phone-max-05-guest-lobby-20261023.png)
- [Map selection, maximum scale and simulated notch](images/new-game-phone-max-notched-02-solo-map1-20261023.png)
- [Audio preferences, maximum scale](images/new-game-phone-max-06-settings0-20261023.png)

## Live browser footer follow-up

The first deployed private-room check exposed a missed intermediate size: a 1280×800 browser renders a roughly 844×527 logical viewport. The menu chose its expanded layout from the raw safe-area height, then subtracted margins and the browser toolbar. Its 545px minimum pushed Start and Leave below the viewport. The breakpoint now uses the usable frame after those deductions, reserving 560px for the expanded layout.

A combined maximum-scale/toolbar check also reproduced the smallest phone's compact minimum overflowing. When the usable compact frame is below 302px, the battlefield body scrolls and its redundant heading is omitted. All three map cards are initially visible; the description is reachable by scrolling. Start and Leave remain fixed, visible and at least 48 logical pixels tall. Match behavior and the existing options scroll are unchanged.

The final menu regression passes 2,168 checks across 15 profiles, including both sides of the expanded breakpoint, browser toolbar clearance, synthetic safe areas, and 844×390 / 932×430 at 1.15 scale with 60 logical pixels reserved for the toolbar. It checks solo, host and guest footers, map-card visibility, description reachability, no content overlap and preference-only Settings. The update-safety regression passes 57 checks. The prior compact layout fails 13 assertions on the added toolbar/phone profiles. Logs, exact source hashes and the rendered fixture are in [the footer evidence archive](evidence/menu-footer-layout-20261023.json.gz).

Three native renders of the shortest combined profile were inspected: [solo](images/menu-footer-short-solo-20261023.png), [host lobby](images/menu-footer-short-host-20261023.png) and [scrolled map description](images/menu-footer-short-phone-solo-map-details-20261023.png). The toolbar clearance, notch and room state are modeled presentation inputs; these images do not claim physical-device or network coverage. The capture used private preferences and exited cleanly.

After beta.10 cutover, a fresh isolated touch-capable Chrome session verified the public build at 1280×800 and 844×390. Touch opened New Game, selected River Crossings and set Settings → Display → Extra Large through the visible UI. With the actual browser toolbar present, the full Start footer and all three map cards remained visible. Ordinary scrolling moved the battlefield body while the footer stayed fixed. Loaded and served revision `884e5a88fae3` and source tree `475bb5f87590aaa4282869f66fda1a8d72c250dc68bdf2a846db5ddfdefd2165` matched; console errors/warnings were zero. This browser check opened no multiplayer connection and injected no synthetic notch. See [desktop](images/live-beta10-new-game-desktop-20261023.png), [maximum-scale phone](images/live-beta10-new-game-phone-max-20261023.png), [scrolled map](images/live-beta10-map-scroll-phone-max-20261023.png) and [compact live evidence](evidence/live-beta10-footer-20261023.json.gz). The owned browser session was closed after capture.

## Direct friend-entry reflow

The independent live multiplayer capture then exposed a different path: opening **Join a friend** directly from Home could leave the map cards stretched below the viewport before a room was joined. The first appearance of wrapped text temporarily raised the manually sized frame to 1,044 logical pixels; after its minimum settled to 284px, Godot retained the larger size. The previous geometry fixture explicitly reapplied layout after transitions, masking this timing bug.

The frame now restores its most recent viewport allocation through a coalesced deferred callback when its minimum size changes. The focused `test_menu_mode_reflow.tscn` uses ordinary menu signals and waits for frames without forcing layout after transitions. It replaces only platform geometry to model shell clearance and safe insets. The identical fixture fails 20 assertions against deployed beta.10 and passes 1,304 against the fix across four geometries, including direct friend entry, both mode tabs, map changes and Back/reopen. The existing 2,168 layout and 57 update-safety checks also pass.

Native touch captures of the direct Home → Join a friend route confirm readable map names, selected states, Create room and the footer: [desktop](images/menu-first-show-desktop-20261023.png) and [maximum-scale phone with modeled safe area and toolbar](images/menu-first-show-phone-20261023.png). These captures did not force a layout refresh after the transition or open network connections. Source hashes, the focused fixture, red/green logs and capture receipts are preserved in [the first-show evidence archive](evidence/menu-first-show-reflow-20261023.json.gz).

The final public beta.11 phone check repeated the direct route in a fresh isolated Chrome context at 844×390. Actual touch selected Extra Large in Settings, returned Home and opened Join a friend. All map previews/names and Create room were visible with the real toolbar present; ordinary panel scrolling exposed the complete code field and Join button. No forced layout, style injection or multiplayer connection was used. Loaded and served revision `b48ebbb5c013` and source tree `94323bc46aedecadcfb976e93d3342d170e2aa8c20f396b6fd602f178c589505` matched, and console errors/warnings were zero. See [direct entry](images/live-beta11-phone-direct-friend-20261023.png), [reachable join controls](images/live-beta11-phone-join-scrolled-20261023.png) and [live phone evidence](evidence/live-beta11-phone-20261023.json.gz). The owned browser session was closed afterward.

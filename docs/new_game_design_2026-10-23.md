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

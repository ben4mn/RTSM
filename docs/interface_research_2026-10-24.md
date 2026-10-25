# Pocket Kingdoms — a quieter war table

Interface review of published beta6; inspected 24 October 2026 (America/Chicago). These design decisions preserve input bindings and action timings. Subsequent user-requested starting Scouts, 100-population defaults and protocol compatibility changes are recorded in the integrated [release record](sound_interface_2026-10-24.md).

## What the existing flow made harder

- **Play intent:** “New Game” opened solo, while “Join a friend” also contained hosting and public Quick match. The destination was broader than its label.
- **Setup hierarchy:** difficulty, optional seed, population and match rules all competed in one long settings column. Rule names lacked a plain-language distinction. The final summary omitted the selected rules.
- **Civilization comparison:** atmospheric lore preceded the strengths and tradeoff needed to make a choice. The illustrated town was absent from its own selection screen.
- **Map choice:** the correct generated layout was useful, but three dark rectangles looked detached from the soft world. Starting towns were distinguished only by color.
- Existing fixed Start/Back actions, scrollable details and a single civilization draft were strengths to preserve. Private rooms, Quick match, Standard/Control race, all population limits, seed entry, guide toggle and all application preferences remain available.

## Reference material and applicable principles

**Clash of Clans.** Examined Supercell's [official UI redesign explanation](https://supercell.com/en/games/clashofclans/blog/news/weve-revamped-the-clash-of-clans-user-interface/) and its actual [Build menu screenshot](https://clashofclans.inbox.supercell.com/lqe2co20rkhw/12amXRdQKd7jTIym3UQVGW/28a6b0d2f45632f46552afe930a326f4/Build_Tab_1.png). Related actions live together, costs and progress sit with their item, and conditional actions appear when relevant. Pocket Kingdoms adopts clear play destinations and contextual groups; it retains labels where the meaning needs explanation. The screenshot's loud, heavy outlines and store emphasis do not fit this quieter illustrated world.

**Age of Empires IV.** Read the [official April 2026 release preview](https://www.ageofempires.com/news/age-of-empires-iv-update-16-1-9737-and-yue-feis-legacy-dlc-release-preview/) and inspected its [civilization overview screenshot](https://cdn.ageofempires.com/aoe/wp-content/uploads/2026/04/englishtechtrees-1080x167.webp). The material separates civilization overview from optional advanced detail, improves flag recognition and preserves lobby choices between games. For Pocket Kingdoms, strengths/tradeoff now lead the civilization comparison, the actual beta6 town accompanies the crest, and optional seed/population detail has an explicit disclosure. Desktop-sized density and hover-only detail are unsuitable for this game's phones.

**The Battle of Polytopia.** Read the [official support material](https://polytopia.io/support/) and [game introduction](https://polytopia.io/). Its tribe guidance frames each identity as different strengths, weaknesses and tactics. The applicable principle is choice by play style, with a readable identity and a common comparison structure. This is an inference from the official material, not a claim that Polytopia's current menu was interactively tested. No artwork or sound from these references is incorporated.

## Implemented menu decisions

- “Play solo” and “Play online” state their destinations; online still includes Create room, Join and Quick match.
- Forest cloth, warm chart paper and honey accents accompany the existing illustrated company. Map cards keep the real generator's tactical layout and show a short terrain trait. “SELECTED” marks the active map. Starting towns use circle/square shapes as well as team colors.
- Difficulty and opening tips lead the solo panel. Rules receive an explanation and appear in the fixed match summary. Population and seed remain under a 48px “More options” control with the population summarized even while collapsed.
- Civilization choices retain the same draft/confirm/cancel behavior and room locks. Town artwork, short play-style headings, strengths and weaknesses precede flavor text. A “Selected” caption marks the selected civilization, and the confirmation names it.
- Existing safe-area allocation, maximum text scale, compact landscape layout, fixed footer, room roles and late room-change cancellation remain intact.

## Menu verification at implementation checkpoint

- Godot 4.6 editor import/parse: passed.
- `test_phone_menu_layout`: **2,207 checks passed**, including 15 desktop/phone/logical-scale/safe-area profiles, all three maps, optional settings disclosure, host/guest presentation and settings. Updated the existing test to open More options before exercising population/seed.
- `test_menu_mode_reflow`: **1,304 checks passed**, including ordinary home/solo/online/map/back signals without manually forcing layout.
- `test_civilization_menu`: **485 checks passed**, including all three civilizations, confirmation/cancellation, rapid reopen, stale room/loading state and safe areas.
- These are real Godot container/layout tests using modeled viewports and safe areas, not physical-device testing. Browser screenshots and end-to-end gameplay results belong to the integrated release evidence.

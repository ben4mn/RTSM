# Illustrated field interface — beta7

This bounded pass keeps the existing selection shelf, input targets, command
signals, queue navigation and gameplay behavior. Muted green cloth surfaces and
rounded cards sit beside the beta6 French, English and Mongol artwork. Utility
controls use circular silhouettes and category choices use pills. Familiar
Move, Attack, Build, selection, camera and pause controls use icons with
accessible names; ambiguous Orders, Patrol and stance choices keep captions.
Tap sizes remain unchanged. Painted portraits retain their colors when pressed.

Recruitment cards now show an inset gold progress line only for the actively
training unit. The value comes from the existing queue snapshot, with no timer
or predicted progress added. Waiting units keep their count badge without a
progress line; completion clears it. Numeric progress remains in the selection
summary, so color is not the sole signal.

Settings > Guide is available from the main menu and paused game. Tap an icon/name
row to expand its explanation, then tap again to fold it away; these learning
rows never issue a gameplay command. The paused menu's Guide reuses the same
definitions, alongside a keyboard section. Both keep a paused solo game paused.
Close or Escape returns to the match menu.
Existing summary Info and hold inspection remain available. Construction Info
now shows an explicit ON badge and spells out the F/W/G cost key; costs, age
requirements and shortages remain visible on the cards.

Unit, building and research costs, stats and action timings remain unchanged.
All interface decoration is source-drawn Godot styling; existing project-owned
SVG glyphs and illustrated civilization assets are reused.

Validation includes the three-civilization `test_field_interface` regression for
active/waiting/completed progress and paused Guide lifecycle, plus the existing
selection geometry, production, affordability, HUD composition, secondary
surfaces, pointer input and hold journey suites. The older readability fixture
now asks for player 0 names and counters when checking player 0 controls; its
default player -1 previously expected generic Horseman text for French Knights.
Native recruitment screenshots are isolated HUD fixtures, not physical-device
or full battlefield evidence. Integrated browser gameplay evidence is recorded
in the beta7 release report.

## Population and touch follow-up

The reported House ceiling was the former match maximum of 30, not a broken
housing ledger. Normal matches now allow 100 per player; 20/30/40/60 remain
custom choices. Existing implicit 30 preferences migrate once to 100 with a menu
notice. Old releases did not record explicit-versus-default choice, so an old
explicit 30 also migrates once; selecting 30 again persists it thereafter.
Existing 20/40 preferences remain unchanged. Large-match AI worker targets stop
at 30, preserving smaller-match targets and leaving population for armies.

The population counter now distinguishes housing from the match maximum. House
cards show actual remaining gain: +10 normally, +5 from 95 to 100, then the limit
message. Nine normal 50-wood Houses grow starting housing from 15 to 100; another
House remains a nominal reserve against a later loss, never raises the agreed
maximum. Paid queues retain their reservations if a House is lost.

Real touch dispatch exposed a separate picking defect: a foreground enemy body
could win a tap on the visible silhouette behind it. Selection now prioritizes
opaque pixels of revealed echoes, checks canonical local visibility again, and
keeps the echo itself noninteractive. This also handles visible head pixels
outside older body discovery bounds. Transparent padding and fog-hidden enemies
gain no target region.

Follow-up checks passed: `test_population_100` (493 checks, all three civilizations
and both modes; paid placement and queues with explicitly stepped build/train
clocks and synthetic near-cap pressure), `test_occlusion_touch_orders` (216 checks,
all three civilizations, 844×390 at 115% and 1280×720, camera zoom 0.85/1.3, real
ScreenTouch on head/body behind roofs/trees/enemy units, Move, Attack-move, direct
enemy attack and fog rejection), Settings (12 phone/scale/safe-area profiles ×
four tabs, guide expansion and paused state), HUD composition (13 profiles),
selection dock geometry (848 checks), production feedback (eight profiles),
building facade selection (seven buildings at three zooms), fog command legality,
command icons, field interface, population reservations and provider loss.
These are automated engine viewport tests, not physical-device tests. Natural
economy rounds and integrated browser play are documented separately.

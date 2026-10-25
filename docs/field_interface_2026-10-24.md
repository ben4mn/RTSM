# Illustrated field interface — beta7

This bounded pass keeps the existing selection shelf, input targets, command
signals, queue navigation and gameplay behavior. Muted green cloth surfaces and
rounded cards sit beside the beta6 French, English and Mongol artwork. Utility
controls use circular silhouettes, category choices use pills, and everyday
orders keep short captions. Familiar clear/back/close glyphs no longer repeat a
permanent label. Painted portraits retain their colors when pressed.

Recruitment cards now show an inset gold progress line only for the actively
training unit. The value comes from the existing queue snapshot, with no timer
or predicted progress added. Waiting units keep their count badge without a
progress line; completion clears it. Numeric progress remains in the selection
summary, so color is not the sole signal.

Menu > Guide teaches the actual order, queue, repeat, stance and resource symbols
with readable explanations and a keyboard section. It works by tapping and
keeps a paused solo game paused. Close or Escape returns to the match menu.
Existing summary Info and hold inspection remain available. Construction Info
now shows an explicit ON badge and spells out the F/W/G cost key; costs, age
requirements and shortages remain visible on the cards.

No unit, building, research, simulation, networking or balance data changes.
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

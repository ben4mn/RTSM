extends RefCounted
## Shared explanations for Settings and the in-match Field Guide.

const ENTRIES: Array = [
	["move", "Move", "Select a unit, tap the arrow, then tap its destination. A highlighted arrow is armed; tap it again to cancel. Tapping empty ground also moves selected units."],
	["attack", "Attack-move", "Select armed units, tap the swords, then tap a destination. They fight enemies along the way. Tap a visible enemy to attack it directly. Scouts are unarmed."],
	["select_area", "Select area", "Open Camera, tap the dashed box, then drag around your units. Tap the box again to cancel. A normal drag pans the map."],
	["clear", "Clear selection", "Open Camera and tap Clear, or use the selection card cross, to deselect. This leaves existing unit orders running."],
	["build", "Build", "Choose a building card, preview clear ground in sight, then Place building. The card shows its name, cost and availability. Info lets you tap cards to learn before buying."],
	["queue", "Recruitment & queue", "Tap a unit portrait to recruit. Food, wood and gold costs stay on the card. A gold seam shows active training progress; Queue shows paid units waiting their turn."],
	["undo", "Undo worker orders", "After sending two or more workers to Move, Gather or Build, a temporary Undo arrow appears for 10 real seconds. Tap it to restore their previous work or movement. Cargo and progress stay as they are. Remembered resource orders return toward their last seen location; unavailable old jobs stop safely. A later worker order replaces Undo. Solo pause does not extend the timer."],
	["undo", "Cancel queued unit", "Tap a queued unit's Undo action to cancel and refund it. Its reserved population becomes available immediately."],
	["repeat", "Repeat training", "ON keeps recruiting the last chosen unit when resources and housing allow. OFF ends repeating; already paid units keep training."],
	["more", "More orders", "The chevron opens Stop, Stance, and Patrol or Idle workers. You can tap each choice. Optional hold: hold the chevron, slide to preview, release to choose."],
	["stop", "Stop", "Stop selected units at their current position. Their stance still decides how they respond to nearby enemies."],
	["stance", "Stance", "Aggro lets armed units pursue nearby enemies. Guard keeps them in place while fighting enemies within reach. The button always shows the current stance."],
	["patrol", "Patrol", "Choose Patrol, then tap a destination. Selected armed units travel between their starting position and that point."],
	["idle", "Idle workers", "Find a worker without a job. The badge counts idle workers. Tap again to cycle through them."],
	["base", "Home", "Return to your Town Center to recruit workers and Scouts. On desktop, press H."],
	["view", "Camera", "Tap the camera icon to reveal or collapse navigation tools. Select area and Clear are inside this tray. Plus and minus zoom; the target centers your selection; Reset returns to the starting scale. Drag the battlefield to pan or pinch to zoom."],
	["pause", "Match menu", "Open Settings, the Guide or match options. Solo matches pause. Online matches keep running for both players."],
	["info", "Information", "Tap Info to learn about selected units or buildings, including costs and blockers. Recruitment and queue actions also support optional hold-to-inspect."],
	["population", "Population & housing", "The counter shows living units plus paid queues / housing. Houses add up to 10 housing until the match maximum. Normal matches allow 100 per player; smaller custom matches keep their chosen maximum."],
	["food", "F · Food", "The apple and F mean food, used for workers, soldiers and age advancement. Workers carry gathered resources to a Town Center or Resource Camp."],
	["wood", "W · Wood", "The log and W mean wood, used for buildings and equipment. House cards show the housing they can still add."],
	["gold", "G · Gold", "The ingot and G mean gold, used for specialist units and advancement."],
]

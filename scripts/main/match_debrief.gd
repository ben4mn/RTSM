extends RefCounted
## A measured fact and a suggested next action; never infers combat causality
## from final score. The match supplies only its own human receipt telemetry.


static func describe(stats: Dictionary) -> String:
	var learning: Dictionary = stats.get("learning", {})
	if learning.is_empty():
		return ""
	var paid_army: int = int(learning.get("paid_army", 0))
	var army_losses: int = int(learning.get("army_losses", 0))
	var army_replacements: int = int(learning.get("army_replacements", 0))
	var worker_losses: int = int(learning.get("worker_losses", 0))
	var worker_replacements: int = int(learning.get("worker_replacements", 0))
	var contests: int = int(learning.get("objective_contests", 0))
	var captures: int = int(learning.get("objective_captures", 0))
	if paid_army == 0:
		return "No fighting troops finished training. Next match: gather Food + Wood, build a Barracks and recruit Warriors."
	if worker_losses > worker_replacements:
		return "Workers lost %d; paid replacements %d. Next match: pull gatherers away from raids, then recruit Villagers at Home." % [worker_losses, worker_replacements]
	if "Sacred" in str(stats.get("victory_reason", "")) and int(stats.get("ai_sacred_control_seconds", 0)) > int(stats.get("sacred_control_seconds", 0)) and contests == 0 and captures == 0:
		return "No Sacred capture or contest recorded. Next match: use the Site locator and enter its ring to pause the enemy clock."
	if army_losses > army_replacements:
		return "Fighting troops lost %d; paid replacements %d. Keep Food + Wood workers gathering and rally replacements near your army." % [army_losses, army_replacements]
	if not bool(learning.get("counter_demonstrated", false)):
		return "No counter preparation recorded. Next match: scout their army, then add a counter. Archers beat Warriors; Warriors beat Horsemen."
	return "First fighting troop %s; paid replacements %d; Sacred contests %d. Keep scouting counters and protecting your gatherers." % [_format_time(float(learning.get("first_army_seconds", -1.0))), army_replacements, contests]


static func _format_time(seconds: float) -> String:
	if seconds < 0.0:
		return "—"
	var total: int = maxi(0, int(round(seconds)))
	@warning_ignore("integer_division")
	return "%d:%02d" % [total / 60, total % 60]

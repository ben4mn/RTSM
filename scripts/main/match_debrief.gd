extends RefCounted
## A measured fact and a suggested next action; never infers combat causality
## from final score. The match supplies only its own human receipt telemetry.

const BATTLE_RECEIPTS := preload("res://scripts/main/battle_receipts.gd")


static func describe(stats: Dictionary) -> String:
	# The result header already gives the authoritative win condition. When
	# available, prefer a witnessed tactical fact to generic reinforcement advice.
	var counter_lesson: Dictionary = BATTLE_RECEIPTS.get_counter_lesson(
		stats.get("battle", {}), int(stats.get("player_civilization", 0)), int(stats.get("opponent_civilization", 0)))
	if not counter_lesson.is_empty():
		return str(counter_lesson["text"])
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
	# Authoritative defeat reason takes precedence over incidental worker losses.
	var reason: String = str(stats.get("victory_reason", ""))
	var lost: bool = not bool(stats.get("is_victory", false))
	if lost and "Sacred" in reason and int(stats.get("ai_sacred_control_seconds", 0)) > 0:
		var mode: int = int(stats.get("match_mode", SkirmishData.MatchMode.STANDARD))
		if mode != SkirmishData.MatchMode.STANDARD:
			var contest_action: String = "contest to pause their clock"
			return "Lost to banked Sacred control. Both sides keep earned time. Rally paid counters; %s, then clear the ring to earn control." % contest_action
		if contests == 0 and captures == 0:
			return "Lost to the enemy Sacred hold. No Sacred capture or contest recorded. Next match: use Site, then send troops into its ring to pause the clock."
		return "Lost to the enemy Sacred hold despite %d contests. Next match: rally paid reinforcements to the ring and keep troops there to pause their clock." % contests
	if lost and ("Town Center" in reason or "Landmark" in reason):
		return "Your Town Center fell. Next match: tap raid warnings to respond, pull workers behind its arrows and rally reinforcements home."
	if paid_army == 0:
		return "No fighting troops finished training. Next match: gather Food + Wood, build a Barracks and recruit Warriors."
	if worker_losses > worker_replacements:
		return "Workers lost %d; paid replacements %d. Next match: pull gatherers away from raids, then recruit Villagers at Home." % [worker_losses, worker_replacements]
	if army_losses > army_replacements:
		return "Fighting troops lost %d; paid replacements %d. Keep Food + Wood workers gathering and rally replacements near your army." % [army_losses, army_replacements]
	if not bool(learning.get("counter_demonstrated", false)):
		return "No counter preparation recorded. Scout their army, then add counters: Warriors beat cavalry; ranged troops beat Warriors."
	return "First fighting troop %s; paid replacements %d; Sacred contests %d. Keep scouting counters and protecting your gatherers." % [_format_time(float(learning.get("first_army_seconds", -1.0))), army_replacements, contests]


static func _format_time(seconds: float) -> String:
	if seconds < 0.0:
		return "—"
	var total: int = maxi(0, int(round(seconds)))
	@warning_ignore("integer_division")
	return "%d:%02d" % [total / 60, total % 60]

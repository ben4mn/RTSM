extends RefCounted
## Observed lethal unit hits, not an explanation of why a battle was lost.
## The caller uses the real attack_landed signal and checks visibility at impact.
## Checking after death can conservatively omit the last unit's sight; it must
## never recover an attacker identity from hidden units or final army totals.

const CORE_TYPES: Array[int] = [UnitData.UnitType.INFANTRY, UnitData.UnitType.ARCHER, UnitData.UnitType.CAVALRY]
const MAX_COUNT: int = 9999
const MIN_LESSON_LOSSES: int = 3
var _losses: Array[Dictionary] = [{}, {}]


func record_loss(victim_owner: int, victim_type: int, attacker_type: int, attacker_visible: bool) -> void:
	if victim_owner not in [0, 1] or not attacker_visible or victim_type not in CORE_TYPES or attacker_type not in CORE_TYPES:
		return
	var key: int = victim_type * 10 + attacker_type
	_losses[victim_owner][key] = mini(MAX_COUNT, int(_losses[victim_owner].get(key, 0)) + 1)


func get_summary(owner: int) -> Dictionary:
	var records: Array = []
	if owner in [0, 1]:
		for victim: int in CORE_TYPES:
			for attacker: int in CORE_TYPES:
				var count: int = int(_losses[owner].get(victim * 10 + attacker, 0))
				if count > 0:
					records.append([victim, attacker, count])
	return {"losses_by_matchup": records}


func apply_local_summary(raw: Variant) -> void:
	# A client receives only its own summary, mapped to local player zero.
	_losses[0].clear()
	for record: Array in sanitize_summary(raw)["losses_by_matchup"]:
		_losses[0][int(record[0]) * 10 + int(record[1])] = int(record[2])


static func sanitize_summary(raw: Variant) -> Dictionary:
	var records: Array = []
	if not raw is Dictionary:
		return {"losses_by_matchup": records}
	var source: Variant = raw.get("losses_by_matchup", [])
	if not source is Array or source.size() > 9:
		return {"losses_by_matchup": records}
	var seen: Dictionary = {}
	for item: Variant in source:
		if not item is Array or item.size() != 3:
			continue
		var valid: bool = true
		for value: Variant in item:
			if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) != floorf(float(value)):
				valid = false
		if not valid:
			continue
		var victim: int = int(item[0])
		var attacker: int = int(item[1])
		var count: int = clampi(int(item[2]), 0, MAX_COUNT)
		var key: int = victim * 10 + attacker
		if victim not in CORE_TYPES or attacker not in CORE_TYPES or count <= 0 or seen.has(key):
			continue
		seen[key] = true
		records.append([victim, attacker, count])
	return {"losses_by_matchup": records}


static func get_counter_lesson(summary: Dictionary, own_civilization: int, enemy_civilization: int) -> Dictionary:
	var strongest: Array = []
	for record: Array in sanitize_summary(summary)["losses_by_matchup"]:
		var victim: int = int(record[0])
		var attacker: int = int(record[1])
		if int(record[2]) < MIN_LESSON_LOSSES or float(UnitData.COUNTER_BONUSES.get(attacker, {}).get(victim, 1.0)) <= 1.0:
			continue
		if strongest.is_empty() or int(record[2]) > int(strongest[2]):
			strongest = record
	if strongest.is_empty():
		return {}
	var recommended: int = -1
	for role: int in CORE_TYPES:
		if float(UnitData.COUNTER_BONUSES.get(role, {}).get(int(strongest[1]), 1.0)) > 1.0:
			recommended = role
			break
	if recommended < 0:
		return {}
	return {
		"victim_type": int(strongest[0]), "attacker_type": int(strongest[1]), "count": int(strongest[2]), "unit_type": recommended,
		"text": "Enemy %s landed final blows on %d of your %s. Add %s to counter them; regroup before your next fight." % [
			_plural_unit_name(int(strongest[1]), enemy_civilization), int(strongest[2]),
			_plural_unit_name(int(strongest[0]), own_civilization), _plural_unit_name(recommended, own_civilization)],
	}


static func _plural_unit_name(unit_type: int, civilization: int) -> String:
	var name: String = str(CivilizationData.get_unit_stats(UnitData.UNITS[unit_type], unit_type, civilization)["name"])
	return "Horsemen" if name == "Horseman" else name + "s"

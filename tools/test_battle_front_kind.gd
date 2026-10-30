extends SceneTree
## Attack cards name the kind of front: soldiers fighting is a BATTLE, workers,
## traders and buildings being hit is a RAID.

func _initialize() -> void:
	var feedback: GDScript = load("res://scripts/ui/battlefield_feedback.gd")
	var failures: Array[String] = []
	for case: Array in [["Warrior", "BATTLE"], ["Archer", "BATTLE"], ["Scout", "BATTLE"], ["Villager", "RAID"], ["Trader", "RAID"], ["House", "RAID"], ["Town Center", "RAID"], ["Barracks", "RAID"]]:
		var kind: String = feedback.call("_front_kind", case[0])
		if kind != case[1]:
			failures.append("%s should be %s, got %s" % [case[0], case[1], kind])
	if failures.is_empty():
		print("[PASS] battle_front_kind: soldiers are battles, workers and buildings are raids")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[FAIL] battle_front_kind: %s" % failure)
		quit(1)

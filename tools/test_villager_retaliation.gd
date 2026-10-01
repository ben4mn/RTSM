extends Node
## Focused regression: economic villagers flee/stay on task instead of auto-retaliating.

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	var villager_scene: PackedScene = load("res://scenes/units/villager.tscn")
	var infantry_scene: PackedScene = load("res://scenes/units/infantry.tscn")
	var villager: Villager = villager_scene.instantiate() as Villager
	var attacker: UnitBase = infantry_scene.instantiate() as UnitBase
	villager.player_owner = 0
	attacker.player_owner = 1
	add_child(villager)
	add_child(attacker)
	await get_tree().process_frame
	# Keep the focused assertion free of transient VFX/tween objects at shutdown.
	get_tree().current_scene = null

	villager.set_state(UnitBase.State.GATHERING)
	Combat.deal_damage(attacker, villager)
	if villager.attack_target != null:
		_failures.append("damaged economic villager acquired a retaliation target")
	if villager.current_state == UnitBase.State.ATTACKING:
		_failures.append("damaged economic villager entered ATTACKING")

	# Opting out of automatic retaliation must not remove explicit combat orders.
	villager.command_attack(attacker)
	if villager.attack_target != attacker or villager.current_state != UnitBase.State.ATTACKING:
		_failures.append("explicit villager attack command no longer works")

	villager.free()
	attacker.free()
	if _failures.is_empty():
		print("[PASS] villager_retaliation: economic flee intent preserved; explicit attacks still work")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] villager_retaliation: %s" % failure)
	get_tree().quit(1)

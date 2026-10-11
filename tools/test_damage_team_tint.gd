extends Node
## Scripted resolved-combat visual fixture, not a paid match or input test.

var _failures: Array[String] = []
var _observe_only: bool = false
var _output: String = ""
var _results: Array[Dictionary] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.initialize_game(2)
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--observe-only":
			_observe_only = true
		elif argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
	for pid: int in [0, 1]:
		for hit_count: int in [1, 2, 3]:
			await _check_hits(pid, hit_count)
	var receipt: Dictionary = {"scope": "Scripted resolved-combat fixture. Two attackers apply canonical Combat.deal_damage in one frame; three-hit case adds another hit 0.05s later. No paid production, physical device or human evidence.", "source": {"unit_base": (load("res://scripts/units/unit_base.gd") as Script).get_source_code().sha256_text(), "combat": (load("res://scripts/units/combat.gd") as Script).get_source_code().sha256_text(), "fixture": FileAccess.get_file_as_string("res://tools/test_damage_team_tint.gd").sha256_text()}, "cases": _results, "failures": _failures}
	if _output != "":
		var file: FileAccess = FileAccess.open(_output, FileAccess.WRITE)
		file.store_string(JSON.stringify(receipt, "\t"))
	print("[DAMAGE_TEAM_TINT] ", JSON.stringify(receipt))
	get_tree().quit(0 if _failures.is_empty() or _observe_only else 1)


func _check_hits(pid: int, hit_count: int) -> void:
	var defender: UnitBase = load("res://scenes/units/infantry.tscn").instantiate() as UnitBase
	defender.player_owner = pid
	add_child(defender)
	defender.set_process(false)
	var first: UnitBase = load("res://scenes/units/infantry.tscn").instantiate() as UnitBase
	first.player_owner = 1 - pid
	add_child(first)
	first.set_process(false)
	var second: UnitBase = load("res://scenes/units/infantry.tscn").instantiate() as UnitBase
	second.player_owner = 1 - pid
	add_child(second)
	second.set_process(false)
	var sprite: Sprite2D = defender.get("_sprite") as Sprite2D
	var expected: Color = sprite.modulate
	var hp_before: float = defender.hp
	Combat.deal_damage(first, defender)
	if hit_count >= 2:
		Combat.deal_damage(second, defender)
	if hit_count == 3:
		await get_tree().create_timer(0.05).timeout
		Combat.deal_damage(first, defender)
	await get_tree().create_timer(0.30).timeout
	var recovered: bool = sprite.modulate.is_equal_approx(expected)
	var hp_loss: float = hp_before - defender.hp
	_results.append({"player": pid, "hits": hit_count, "base_tint": str(expected), "settled_tint": str(sprite.modulate), "recovered": recovered, "hp_loss": hp_loss})
	if not recovered:
		_failures.append("Player %d loses stable team tint after %d hits" % [pid, hit_count])
	if not is_equal_approx(hp_loss, float(hit_count) * 6.0):
		_failures.append("Visual feedback changed canonical HP loss")
	defender.free()
	first.free()
	second.free()

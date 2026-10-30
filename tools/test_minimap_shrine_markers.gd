extends Node
## Both flank shrines show on the minimap as small diamonds in their holder's
## colour: TEAL yours, RUST the rival's, PARCHMENT while unheld. The marker
## reads owning_player from the shrine node, which online snapshots update.

var _failures: Array[String] = []
@onready var root: Window = get_tree().root


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 101
	GameManager.set_state(GameManager.GameState.MENU)
	var main: Node = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for frame: int in range(900):
		if main.get("_building_placement") != null and GameManager.current_state == GameManager.GameState.PLAYING:
			break
		await get_tree().process_frame
	await _check(main)
	main.free()
	GameManager.set_state(GameManager.GameState.MENU)
	await get_tree().process_frame
	if _failures.is_empty():
		print("[PASS] minimap_shrine_markers: shrines drawn in owner colour, neutral parchment, diamond shape")
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			push_error("[FAIL] minimap_shrine_markers: %s" % failure)
		get_tree().quit(1)


func _check(main: Node) -> void:
	var map: Node2D = main.get("game_map") as Node2D
	var hud: Node = main.get("hud") as Node
	var shrines: Array = map.get("shrines")
	_expect(shrines.size() == 2, "expected two shrines, got %d" % shrines.size())
	if shrines.size() != 2:
		return
	(main.get("ai_controller") as Node).set_process(false)
	for shrine: Node in shrines:
		shrine.set_process(false)
	# Neutral first: both parchment.
	for shrine: Node in shrines:
		shrine.set("state", 0)
		shrine.set("owning_player", -1)
	main.call("_update_minimap")
	for index: int in 2:
		_expect_pixel(hud, map, shrines[index], KingdomTheme.PARCHMENT, "neutral shrine %d" % index)
	# Yours and the rival's.
	shrines[0].set("state", 2)
	shrines[0].set("owning_player", 0)
	shrines[1].set("state", 2)
	shrines[1].set("owning_player", 1)
	main.call("_update_minimap")
	_expect_pixel(hud, map, shrines[0], KingdomTheme.TEAL, "your shrine")
	_expect_pixel(hud, map, shrines[1], KingdomTheme.RUST, "rival shrine")
	# Mid-capture is not held yet.
	shrines[1].set("state", 1)
	main.call("_update_minimap")
	_expect_pixel(hud, map, shrines[1], KingdomTheme.PARCHMENT, "shrine being captured")
	# Diamond: the diagonal neighbour is ink edge (a square marker would fill
	# it), so the shape cannot be confused with a building square.
	var image: Image = hud.get("_minimap_image") as Image
	var tile: Vector2i = map.call("world_to_tile", (shrines[0] as Node2D).global_position)
	var edge: Color = image.get_pixelv(tile + Vector2i(1, 1))
	_expect(_close(edge, KingdomTheme.INK), "shrine marker should have an ink edge, got %s" % edge)
	await get_tree().process_frame


func _expect_pixel(hud: Node, map: Node, shrine: Node2D, want: Color, label: String) -> void:
	var image: Image = hud.get("_minimap_image") as Image
	if image == null:
		_failures.append("%s: minimap image missing" % label)
		return
	var tile: Vector2i = map.call("world_to_tile", shrine.global_position)
	var got: Color = image.get_pixelv(tile)
	_expect(_close(got, want), "%s should be %s on the minimap, got %s" % [label, want, got])


func _close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.02 and absf(a.g - b.g) < 0.02 and absf(a.b - b.b) < 0.02


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

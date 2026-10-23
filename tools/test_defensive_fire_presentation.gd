extends Node
## Source-art attachment with real defensive release/impact. Synthetic positions;
## no paid battle, native rendering or performance claim.

const SCENES: Array[PackedScene] = [
	preload("res://scenes/buildings/town_center.tscn"),
	preload("res://scenes/buildings/watch_tower.tscn"),
]
# Independent chosen art landmarks: TC front lookout window; Tower open rampart.
const SOURCE_POINTS: Array[Vector2] = [Vector2(101, 72), Vector2(64, 21)]
const SOURCE_COLORS: Array[Color] = [Color("34554b"), Color("6c8069")]
var failures: Array[String] = []
var checks: int = 0
var records: Array[Dictionary] = []
var output: String = "res://output/polish-world-proportions-2026-10-22/defense"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	AudioManager.set_all_enabled(false)
	GameManager.initialize_game(2)
	GameManager.set_process(false)
	get_tree().current_scene = null
	for kind: int in SCENES.size():
		for owner: int in 2:
			for transformed: bool in [false, true]:
				_check_building(kind, owner, transformed)
	DirAccess.make_dir_recursive_absolute(output)
	var hashes: Dictionary = {}
	for path: String in ["scripts/buildings/building_base.gd", "scripts/data/building_data.gd", "scripts/units/combat.gd", "assets/buildings/company_town_center.svg", "assets/buildings/watch_tower.svg", "assets/buildings/company_town_center.svg.import", "assets/buildings/company_town_center_enemy.svg", "assets/buildings/company_town_center_enemy.svg.import", "assets/buildings/watch_tower.svg.import", "assets/buildings/watch_tower_enemy.svg", "assets/buildings/watch_tower_enemy.svg.import", "tools/test_defensive_fire_presentation.gd"]:
		hashes[path] = FileAccess.get_sha256("res://" + path)
	FileAccess.open(output.path_join("receipt.json"), FileAccess.WRITE).store_string(JSON.stringify({"scope": "Headless source-pixel transforms and actual defense scheduling; eight local-owner/transform cases. No native pixels or performance claim.", "checks": checks, "records": records, "source_sha256": hashes, "failures": failures}, "  "))
	for failure: String in failures:
		push_error("[FAIL] defensive_fire_presentation: " + failure)
	if failures.is_empty():
		print("[PASS] defensive_fire_presentation: %d checks; TC/Tower source landmarks, owners/transforms, shared visual origin, unchanged range/cooldown/flight/damage" % checks)
	get_tree().quit(0 if failures.is_empty() else 1)


func _check_building(kind: int, owner: int, transformed: bool) -> void:
	var world := Node2D.new()
	add_child(world)
	world.position = Vector2(345, -210) if transformed else Vector2.ZERO
	world.rotation = 0.2 if transformed else 0.0
	world.scale = Vector2.ONE * (1.1 if transformed else 1.0)
	var building := SCENES[kind].instantiate() as BuildingBase
	building.player_owner = owner
	building.state = BuildingBase.State.ACTIVE
	building.position = Vector2(60, 20)
	world.add_child(building)
	building.set_process(false)
	var enemy := preload("res://scenes/units/infantry.tscn").instantiate() as UnitBase
	enemy.player_owner = 1 - owner
	world.add_child(enemy)
	enemy.set_process(false)
	enemy.global_position = building.global_position + Vector2(60, 0)
	var sprite: Sprite2D = building._sprite
	var image: Image = sprite.texture.get_image()
	var landmark: Vector2 = SOURCE_POINTS[kind] * (sprite.texture.get_size() / Vector2(128, 128))
	var canonical_scale: Vector2 = Vector2(1.70, 1.60) if kind == 0 else Vector2(1.12, 1.12)
	var canonical_ground: Vector2 = Vector2(64, 104) if kind == 0 else Vector2(64, 116)
	var canonical_center: Vector2 = Vector2(0, 48) if kind == 0 else Vector2.ZERO
	var authored_origin: Vector2 = building.to_global(canonical_center + (SOURCE_POINTS[kind] - canonical_ground) * canonical_scale)
	var pixel: Color = image.get_pixelv(Vector2i(landmark))
	_expect(pixel.a > 0.99, "chosen fire landmark lies on opaque source artwork")
	_expect(pixel.is_equal_approx(SOURCE_COLORS[kind]), "chosen fire landmark lies inside the authored window or open rampart")
	var expected: Vector2 = sprite.global_transform * (sprite.get_rect().position + landmark)
	_expect(expected.distance_to(authored_origin) < 0.001, "import resolution preserves independently authored world fire point")
	var has_origin: bool = building.has_method("_get_defensive_fire_position")
	_expect(has_origin, "defensive fire exposes one transformed visual origin")
	if has_origin:
		_expect((building.call("_get_defensive_fire_position") as Vector2).distance_to(expected) < 0.001, "visual fire origin follows the actual source pixel through sprite and parent transforms")
	var interval: float = 2.0 if kind == 0 else 1.5
	var fired_at: Array[Node2D] = []
	building.defensive_attack_fired.connect(func(target: Node2D) -> void: fired_at.append(target))
	building._process(0.01)
	_expect(fired_at == [enemy], "actual building process acquires the same enemy")
	_expect(is_equal_approx(building._tower_attack_cooldown, interval), "visual attachment preserves the data cooldown")
	if kind == 0:
		var arrows: Array[Node] = get_tree().get_nodes_in_group("defensive_projectiles")
		_expect(arrows.size() == 1, "TC releases exactly one travelling arrow")
		if arrows.size() == 1:
			var arrow: BuildingBase.DefensiveArrow = arrows[0]
			arrow.set_process(false)
			_expect(arrow.start_position.distance_to(expected) < 0.001 and arrow.global_position.distance_to(expected) < 0.001, "released arrow starts at the source window, including footprint-center offset")
			_expect(is_equal_approx(arrow.flight_seconds, 0.2), "flight timing still uses60 logical ground distance at300 speed")
			_expect(is_equal_approx(enemy.hp, 60.0), "TC release does not apply early damage")
			arrow.advance_projectile(0.199)
			_expect(is_equal_approx(enemy.hp, 60.0), "TC damage waits until the original flight deadline")
			arrow.advance_projectile(0.002)
			_expect(is_equal_approx(enemy.hp, 56.0), "TC still applies6 minus2 armor exactly once")
			arrow.advance_projectile(1.0)
			_expect(is_equal_approx(enemy.hp, 56.0), "completed arrow cannot damage twice")
			arrow.free()
		_expect(is_equal_approx(building._defensive_shot_flash_remaining, 0.18), "TC retains its short shot flash")
	else:
		_expect(get_tree().get_nodes_in_group("defensive_projectiles").is_empty(), "Tower preserves instant defense without introducing a new travel delay")
		_expect(is_equal_approx(enemy.hp, 56.0), "Tower retains immediate6 minus2 armor damage")
	# A live art adjustment must affect attachment only, not range or schedule.
	sprite.position += Vector2(-17, 9)
	sprite.scale *= 0.8
	sprite.rotation = 0.12
	var adjusted: Vector2 = sprite.global_transform * (sprite.get_rect().position + landmark)
	if has_origin:
		_expect((building.call("_get_defensive_fire_position") as Vector2).distance_to(adjusted) < 0.001, "origin follows live artwork movement, uniform size and rotation")
	building._process(interval - 0.01)
	_expect(fired_at.size() == 1, "visual changes cannot advance the firing schedule")
	building._process(0.02)
	_expect(fired_at.size() == 2, "second shot retains the original interval")
	if kind == 0:
		var arrow: BuildingBase.DefensiveArrow = get_tree().get_nodes_in_group("defensive_projectiles")[0]
		_expect(arrow.start_position.distance_to(adjusted) < 0.001, "next release picks up adjusted artwork position")
		_expect(is_equal_approx(arrow.flight_seconds, 0.2), "art movement cannot change logical flight duration")
	enemy.global_position = building.global_position + Vector2(building.tower_attack_range + 0.01, 0)
	_expect(not building._tower_try_attack(), "range remains measured from logical ground origin")
	records.append({"building": building.building_name, "owner": owner, "transformed": transformed, "source_landmark": str(landmark), "source_pixel": pixel.to_html(), "expected_world_origin": str(expected), "old_world_origin": str(building.global_position + Vector2(0, -52)), "interval": interval, "logical_range": building.tower_attack_range})
	world.free()


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

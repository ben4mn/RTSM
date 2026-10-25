extends Node
## Native renderer contact sheet: real Sprite2D transforms and persistent tools.
const ACTIONS: Array[int] = [1, 2, 9, 3, 4, 5, 6, 7, 0, 8]
const ROLES: Array[int] = [0, 0, 0, 0, 0, 1, 2, 3, 4, 5]
const LABELS: Array[String] = ["Chop", "Farm / hoe", "Forage / pick", "Mine", "Build", "Melee", "Bow", "Mounted", "Scout / travel", "Siege"]
const PHASES: Array[float] = [0.18, 0.52, 0.74, 0.92]
const WORK_PHASES: Array[float] = [0.4, 0.7, 0.0, 0.18]
const FARM_PHASES: Array[float] = [0.05, 0.38, 0.6, 0.95]
var gallery: SubViewport


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	GameManager.players.clear()
	GameManager.current_state = 0
	GameManager.reduced_motion = false
	GameManager.reduced_flashes = false
	AudioManager.set_all_enabled(false)
	gallery = SubViewport.new()
	gallery.size = Vector2i(1440, 1492)
	gallery.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(gallery)
	var background := ColorRect.new()
	background.color = Color("183332")
	background.size = Vector2(1440, 1492)
	gallery.add_child(background)
	for civ: int in 3:
		GameManager.selected_civilization = civ
		var left: float = civ * 480.0
		_label(CivilizationData.get_civilization_name(civ), Vector2(left + 18, 12), 25)
		_label("Prepare  →  lift / draw  →  contact  →  settle", Vector2(left + 18, 48), 16)
		for row: int in ACTIONS.size():
			var baseline: float = 177.0 + row * 142.0
			_label(LABELS[row], Vector2(left + 18, baseline - 104), 17)
			for frame: int in PHASES.size():
				var unit: UnitBase = load("res://scenes/units/unit_base.tscn").instantiate()
				unit.unit_type = ROLES[row]
				unit.position = Vector2(left + 60 + frame * 118, baseline)
				gallery.add_child(unit)
				unit.set_process(false)
				unit.scale = Vector2.ONE * 1.85
				if ACTIONS[row] == UnitActionPresentation.Action.NONE:
					# Scouts are unarmed: show their actual travel gait rather than
					# manufacturing an attack pose that cannot occur in a match.
					unit.current_state = UnitBase.State.MOVING
					unit._last_visual_position = unit.global_position - Vector2(1, 0)
					unit._animation_clock = PHASES[frame] * TAU / 17.0
				elif UnitActionPresentation.is_work_action(ACTIONS[row]):
					unit.current_state = UnitBase.State.GATHERING
					var phase: float = FARM_PHASES[frame] if ACTIONS[row] == UnitActionPresentation.Action.FARM or ACTIONS[row] == UnitActionPresentation.Action.FORAGE else WORK_PHASES[frame]
					unit.apply_work_presentation([ACTIONS[row], phase, 0.8])
				else:
					unit.current_state = UnitBase.State.ATTACKING
					var windup: float = float(UnitData.UNITS[ROLES[row]].get("attack_windup", 0.12))
					unit._attack_animation_duration = windup + 0.16
					var elapsed: float = windup * PHASES[frame] / 0.7 if PHASES[frame] <= 0.7 else windup + (PHASES[frame] - 0.7) / 0.3 * 0.16
					unit._attack_animation_remaining = unit._attack_animation_duration - elapsed
				unit._update_sprite_motion(0.0)
	for frame: int in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var destination: String = args[0] if args.size() > 0 else "res://output/unit-actions.png"
	var path: String = ProjectSettings.globalize_path(destination)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var status: Error = gallery.get_texture().get_image().save_png(path)
	print("Unit actions contact sheet: " + path + " status=" + str(status))
	get_tree().quit(0 if status == OK else 1)


func _label(value: String, at: Vector2, size: int) -> void:
	var label := Label.new()
	label.text = value
	label.position = at
	label.add_theme_font_override("font", load("res://assets/fonts/Barlow-Medium.ttf"))
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("f4eddd"))
	gallery.add_child(label)

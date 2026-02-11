class_name VFX
extends RefCounted
## Lightweight one-shot particle effect spawner.
## All methods are static — call VFX.hit_burst(tree, pos) etc.


static func hit_burst(tree: SceneTree, pos: Vector2, color: Color = Color(1.0, 0.9, 0.6)) -> void:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 8
	p.lifetime = 0.25
	p.explosiveness = 0.95
	p.direction = Vector2.UP
	p.spread = 180.0
	p.initial_velocity_min = 25.0
	p.initial_velocity_max = 55.0
	p.gravity = Vector2(0, 80)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.5
	p.color = color
	p.global_position = pos
	tree.current_scene.add_child(p)
	p.finished.connect(p.queue_free)
	p.emitting = true


static func death_puff(tree: SceneTree, pos: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 16
	p.lifetime = 0.6
	p.explosiveness = 0.85
	p.direction = Vector2.UP
	p.spread = 180.0
	p.initial_velocity_min = 10.0
	p.initial_velocity_max = 30.0
	p.gravity = Vector2(0, -30)
	p.scale_amount_min = 2.0
	p.scale_amount_max = 5.0
	var grad := Gradient.new()
	grad.set_color(0, Color(0.6, 0.6, 0.6, 0.7))
	grad.set_color(1, Color(0.3, 0.3, 0.3, 0.0))
	p.color_ramp = grad
	p.global_position = pos
	tree.current_scene.add_child(p)
	p.finished.connect(p.queue_free)
	p.emitting = true


static func gather_particles(tree: SceneTree, pos: Vector2, resource_type: String) -> void:
	var color: Color
	match resource_type:
		"wood":
			color = Color(0.55, 0.35, 0.15)
		"gold":
			color = Color(1.0, 0.85, 0.2)
		"food":
			color = Color(0.4, 0.7, 0.25)
		_:
			color = Color(0.6, 0.6, 0.6)
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 5
	p.lifetime = 0.4
	p.explosiveness = 0.9
	p.direction = Vector2.UP
	p.spread = 120.0
	p.initial_velocity_min = 15.0
	p.initial_velocity_max = 35.0
	p.gravity = Vector2(0, 60)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	p.color = color
	p.global_position = pos
	tree.current_scene.add_child(p)
	p.finished.connect(p.queue_free)
	p.emitting = true


static func construction_dust(tree: SceneTree, pos: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 6
	p.lifetime = 0.5
	p.explosiveness = 0.8
	p.direction = Vector2.UP
	p.spread = 160.0
	p.initial_velocity_min = 8.0
	p.initial_velocity_max = 20.0
	p.gravity = Vector2(0, -15)
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.0
	var grad := Gradient.new()
	grad.set_color(0, Color(0.65, 0.55, 0.35, 0.5))
	grad.set_color(1, Color(0.5, 0.45, 0.3, 0.0))
	p.color_ramp = grad
	p.global_position = pos
	tree.current_scene.add_child(p)
	p.finished.connect(p.queue_free)
	p.emitting = true


static func move_indicator(tree: SceneTree, pos: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 12
	p.lifetime = 0.4
	p.explosiveness = 0.95
	p.direction = Vector2.UP
	p.spread = 180.0
	p.initial_velocity_min = 15.0
	p.initial_velocity_max = 35.0
	p.gravity = Vector2(0, -15)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	var grad := Gradient.new()
	grad.set_color(0, Color(0.3, 0.9, 0.3, 0.8))
	grad.set_color(1, Color(0.3, 0.9, 0.3, 0.0))
	p.color_ramp = grad
	p.global_position = pos
	tree.current_scene.add_child(p)
	p.finished.connect(p.queue_free)
	p.emitting = true


static func resource_float(tree: SceneTree, pos: Vector2, text: String, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.global_position = pos - Vector2(30, 10)
	lbl.z_index = 100
	tree.current_scene.add_child(lbl)
	var tween := tree.create_tween()
	tween.set_parallel(true)
	tween.tween_property(lbl, "global_position:y", pos.y - 40.0, 1.0)
	tween.tween_property(lbl, "modulate:a", 0.0, 1.0)
	tween.chain().tween_callback(lbl.queue_free)


static func damage_float(tree: SceneTree, pos: Vector2, amount: float) -> void:
	var lbl := Label.new()
	lbl.text = "-%d" % int(amount)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2))
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	# Randomize x offset slightly so overlapping hits don't stack
	var x_off := randf_range(-12, 12)
	lbl.global_position = pos + Vector2(x_off - 15, -20)
	lbl.z_index = 100
	tree.current_scene.add_child(lbl)
	var tween := tree.create_tween()
	tween.set_parallel(true)
	tween.tween_property(lbl, "global_position:y", pos.y - 50.0, 0.8)
	tween.tween_property(lbl, "modulate:a", 0.0, 0.8)
	tween.chain().tween_callback(lbl.queue_free)


static func building_smoke(tree: SceneTree, pos: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 4
	p.lifetime = 0.8
	p.explosiveness = 0.6
	p.direction = Vector2.UP
	p.spread = 40.0
	p.initial_velocity_min = 5.0
	p.initial_velocity_max = 15.0
	p.gravity = Vector2(0, -20)
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	var grad := Gradient.new()
	grad.set_color(0, Color(0.4, 0.4, 0.4, 0.5))
	grad.set_color(1, Color(0.3, 0.3, 0.3, 0.0))
	p.color_ramp = grad
	p.global_position = pos + Vector2(randf_range(-10, 10), randf_range(-5, 5))
	tree.current_scene.add_child(p)
	p.finished.connect(p.queue_free)
	p.emitting = true


static func building_fire(tree: SceneTree, pos: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 6
	p.lifetime = 0.5
	p.explosiveness = 0.7
	p.direction = Vector2.UP
	p.spread = 30.0
	p.initial_velocity_min = 10.0
	p.initial_velocity_max = 25.0
	p.gravity = Vector2(0, -30)
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.0
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.6, 0.1, 0.8))
	grad.set_color(1, Color(1.0, 0.2, 0.0, 0.0))
	p.color_ramp = grad
	p.global_position = pos + Vector2(randf_range(-8, 8), randf_range(-10, 0))
	tree.current_scene.add_child(p)
	p.finished.connect(p.queue_free)
	p.emitting = true


static func building_complete(tree: SceneTree, pos: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 20
	p.lifetime = 0.5
	p.explosiveness = 0.95
	p.direction = Vector2.UP
	p.spread = 180.0
	p.initial_velocity_min = 30.0
	p.initial_velocity_max = 70.0
	p.gravity = Vector2(0, 50)
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.0
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.95, 0.6, 0.9))
	grad.set_color(1, Color(1.0, 0.8, 0.3, 0.0))
	p.color_ramp = grad
	p.global_position = pos
	tree.current_scene.add_child(p)
	p.finished.connect(p.queue_free)
	p.emitting = true

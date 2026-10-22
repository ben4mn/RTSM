class_name VFX
extends RefCounted
## Lightweight one-shot particle effect spawner.
## All methods are static — call VFX.hit_burst(tree, pos) etc.


static func hit_burst(tree: SceneTree, pos: Vector2, color: Color = Color("e8e5db")) -> void:
	if GameManager.reduced_motion:
		return
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 3
	p.lifetime = 0.18
	p.explosiveness = 0.95
	p.direction = Vector2.UP
	p.spread = 180.0
	p.initial_velocity_min = 12.0
	p.initial_velocity_max = 26.0
	p.gravity = Vector2(0, 80)
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.4
	p.color = color
	p.global_position = pos
	tree.current_scene.add_child(p)
	p.finished.connect(p.queue_free)
	p.emitting = true


static func death_puff(tree: SceneTree, pos: Vector2) -> void:
	if GameManager.reduced_motion:
		return
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 5
	p.lifetime = 0.3
	p.explosiveness = 0.85
	p.direction = Vector2.UP
	p.spread = 180.0
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 18.0
	p.gravity = Vector2(0, -30)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.5
	var grad := Gradient.new()
	grad.set_color(0, Color(0.24, 0.28, 0.25, 0.4))
	grad.set_color(1, Color(0.24, 0.28, 0.25, 0.0))
	p.color_ramp = grad
	p.global_position = pos
	tree.current_scene.add_child(p)
	p.finished.connect(p.queue_free)
	p.emitting = true


static func gather_particles(tree: SceneTree, pos: Vector2, resource_type: String) -> void:
	if GameManager.reduced_motion:
		return
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
	if GameManager.reduced_motion:
		return
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


class OrderMarker extends Node2D:
	var kind: String = "move"
	var remaining: float = 1.0

	func _process(delta: float) -> void:
		remaining -= delta
		if remaining <= 0.0:
			queue_free()
		else:
			modulate.a = minf(1.0, remaining * 2.0)
			queue_redraw()

	func _draw() -> void:
		var zoom: float = maxf(0.1, get_canvas_transform().x.length())
		var color: Color = {"move": Color("8cdecf"), "attack": Color("ff9d85"), "gather": Color("f1d18a"), "rally": Color("88c9f0")}.get(kind, Color.WHITE)
		var radius: float = 9.0 / zoom
		draw_circle(Vector2.ZERO, radius + 2.0 / zoom, Color(0.04, 0.10, 0.12, 0.55))
		if kind == "rally":
			draw_line(Vector2(-4, 7) / zoom, Vector2(-4, -9) / zoom, color, 1.5 / zoom, true)
			draw_colored_polygon(PackedVector2Array([Vector2(-3, -9) / zoom, Vector2(8, -5) / zoom, Vector2(-3, 0) / zoom]), color)
		elif kind == "gather":
			draw_polyline(PackedVector2Array([Vector2(0, -8) / zoom, Vector2(8, 0) / zoom, Vector2(0, 8) / zoom, Vector2(-8, 0) / zoom, Vector2(0, -8) / zoom]), color, 1.5 / zoom, true)
		else:
			draw_arc(Vector2.ZERO, radius, 0, TAU, 24, color, 1.5 / zoom, true)
			if kind == "attack":
				draw_line(Vector2(-4, -4) / zoom, Vector2(4, 4) / zoom, color, 1.5 / zoom, true)
				draw_line(Vector2(-4, 4) / zoom, Vector2(4, -4) / zoom, color, 1.5 / zoom, true)
			else:
				draw_circle(Vector2.ZERO, 2.0 / zoom, color)


static func _order_indicator(tree: SceneTree, pos: Vector2, kind: String) -> void:
	if tree.current_scene == null or DisplayServer.get_name() == "headless":
		return
	var marker := OrderMarker.new()
	marker.kind = kind
	marker.z_index = 80
	marker.position = pos
	tree.current_scene.add_child(marker)


static func move_indicator(tree: SceneTree, pos: Vector2) -> void:
	_order_indicator(tree, pos, "move")


static func attack_move_indicator(tree: SceneTree, pos: Vector2) -> void:
	_order_indicator(tree, pos, "attack")


static func gather_indicator(tree: SceneTree, pos: Vector2) -> void:
	_order_indicator(tree, pos, "gather")


static func rally_indicator(tree: SceneTree, pos: Vector2) -> void:
	_order_indicator(tree, pos, "rally")


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
	if not GameManager.reduced_motion:
		tween.tween_property(lbl, "global_position:y", pos.y - 40.0, 1.0)
	tween.tween_property(lbl, "modulate:a", 0.0, 1.0)
	tween.chain().tween_callback(lbl.queue_free)


static func damage_float(tree: SceneTree, pos: Vector2, amount: float) -> void:
	var lbl := Label.new()
	lbl.text = "-%d" % int(amount)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color("e8e5db"))
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
	if not GameManager.reduced_motion:
		tween.tween_property(lbl, "global_position:y", pos.y - 50.0, 0.8)
	tween.tween_property(lbl, "modulate:a", 0.0, 0.8)
	tween.chain().tween_callback(lbl.queue_free)


static func building_smoke(tree: SceneTree, pos: Vector2) -> void:
	if GameManager.reduced_motion:
		return
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
	if GameManager.reduced_motion:
		return
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


static func arrow_projectile(tree: SceneTree, from_pos: Vector2, to_pos: Vector2) -> void:
	## Simple arrow: a small yellow-brown dot that flies from attacker to target.
	var arrow := Sprite2D.new()
	arrow.texture = PlaceholderTexture2D.new()
	(arrow.texture as PlaceholderTexture2D).size = Vector2(4, 4)
	arrow.modulate = Color(0.85, 0.65, 0.2)
	arrow.global_position = from_pos
	arrow.z_index = 90
	tree.current_scene.add_child(arrow)
	var fly_time: float = clampf(from_pos.distance_to(to_pos) / 300.0, 0.1, 0.5)
	var tween := tree.create_tween()
	# Arc upward slightly for a natural arrow trajectory
	var mid := (from_pos + to_pos) * 0.5 + Vector2(0, -20)
	tween.tween_property(arrow, "global_position", mid, fly_time * 0.5)
	tween.tween_property(arrow, "global_position", to_pos, fly_time * 0.5)
	tween.tween_callback(arrow.queue_free)


static func counter_bonus_float(tree: SceneTree, pos: Vector2, text: String) -> void:
	## Show counter bonus text (e.g., "x1.5!") floating above a unit.
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color("d6c5a6"))
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.global_position = pos + Vector2(-20, -35)
	lbl.z_index = 100
	tree.current_scene.add_child(lbl)
	var tween := tree.create_tween()
	tween.set_parallel(true)
	if not GameManager.reduced_motion:
		tween.tween_property(lbl, "global_position:y", pos.y - 60.0, 0.9)
	tween.tween_property(lbl, "modulate:a", 0.0, 0.9)
	tween.chain().tween_callback(lbl.queue_free)


static func building_complete(tree: SceneTree, pos: Vector2) -> void:
	if GameManager.reduced_motion:
		return
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

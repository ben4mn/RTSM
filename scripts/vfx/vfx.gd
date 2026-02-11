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

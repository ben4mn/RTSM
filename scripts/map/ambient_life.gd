extends Node2D
## Now and then a few birds cross the sky above the camera. Purely cosmetic:
## a private random generator, no collision, no simulation reads, one node,
## and nothing is drawn or processed between flights or under Reduced motion.

const AMBIENT_MOTION := preload("res://scripts/map/ambient_motion.gd")
const BIRD_INK := Color(0.16, 0.22, 0.21, 0.82)
const SHADOW_INK := Color(0.09, 0.14, 0.18, 0.13)
const SHADOW_DROP := Vector2(26.0, 74.0)

var game_map: Node2D
var _rng := RandomNumberGenerator.new()
var _wait: float = 9.0
var _flying: bool = false
var _lead: Vector2 = Vector2.ZERO
var _velocity: Vector2 = Vector2.ZERO
var _age: float = 0.0
var _life: float = 0.0
var _offsets: PackedVector2Array = PackedVector2Array()
var _phases: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	z_index = 12
	_rng.randomize()
	_wait = _rng.randf_range(7.0, 14.0)


func _process(delta: float) -> void:
	var real_delta: float = delta / maxf(0.001, Engine.time_scale)
	if AMBIENT_MOTION.get_scale() <= 0.0:
		if _flying:
			_flying = false
			queue_redraw()
		return
	if not _flying:
		_wait -= real_delta
		if _wait <= 0.0:
			_launch()
		return
	_age += real_delta
	_lead += _velocity * real_delta
	if _age >= _life:
		_flying = false
		_wait = _rng.randf_range(24.0, 46.0)
	queue_redraw()


func _launch() -> void:
	var camera: Camera2D = game_map.camera if game_map != null else null
	if camera == null:
		_wait = 5.0
		return
	var view: Vector2 = get_viewport().get_visible_rect().size / maxf(0.001, camera.zoom.x)
	var heading: float = 1.0 if _rng.randf() < 0.5 else -1.0
	var speed: float = _rng.randf_range(105.0, 140.0)
	_velocity = Vector2(heading * speed, _rng.randf_range(-22.0, 14.0))
	_lead = camera.get_screen_center_position() + Vector2(-heading * (view.x * 0.5 + 90.0), _rng.randf_range(-0.36, 0.22) * view.y)
	_life = (view.x + 320.0) / speed
	_age = 0.0
	var count: int = _rng.randi_range(3, 6)
	_offsets.resize(count)
	_phases.resize(count)
	for index: int in count:
		@warning_ignore("integer_division")
		var rank: int = (index + 1) / 2
		var side: float = 1.0 if index % 2 == 0 else -1.0
		_offsets[index] = Vector2(-heading * rank * _rng.randf_range(17.0, 23.0), side * rank * _rng.randf_range(9.0, 13.0))
		_phases[index] = _rng.randf() * TAU
	_flying = true


func _draw() -> void:
	if not _flying:
		return
	var heading: float = signf(_velocity.x)
	for index: int in _offsets.size():
		var body: Vector2 = _lead + _offsets[index] + Vector2(0.0, sin(_age * 1.7 + _phases[index]) * 2.5)
		var flap: float = sin(_age * 9.0 + _phases[index])
		_draw_bird(body + SHADOW_DROP, flap, heading, SHADOW_INK, 1.6)
		_draw_bird(body, flap, heading, BIRD_INK, 1.5)


func _draw_bird(body: Vector2, flap: float, heading: float, ink: Color, width: float) -> void:
	var lift: float = -2.2 - flap * 3.4
	var back: float = -heading * 1.5
	draw_polyline(PackedVector2Array([
		body + Vector2(back - 5.5, lift), body + Vector2(-2.0, lift * 0.35), body + Vector2(heading * 1.2, 0.6),
		body + Vector2(2.0, lift * 0.35), body + Vector2(back + 5.5, lift),
	]), ink, width, true)

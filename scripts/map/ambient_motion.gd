extends RefCounted
## One switch for every cosmetic shader motion (wind, water, clouds, wings).
## Materials register once; WorldDressing mirrors the Reduced motion setting.
## Nothing here is read by the simulation.

const WIND_SHADER: Shader = preload("res://assets/terrain/wind_sway.gdshader")

static var _materials: Array[ShaderMaterial] = []
static var _wind: Dictionary = {}
static var _scale: float = 1.0


static func register(material: ShaderMaterial) -> void:
	if material == null or _materials.has(material):
		return
	_materials.append(material)
	material.set_shader_parameter("motion", _scale)


static func unregister(material: ShaderMaterial) -> void:
	_materials.erase(material)


## Shared sway material for standing plants. One instance per strength keeps
## every tree of a kind in the same batch.
static func wind_material(strength: float, root_v: float) -> ShaderMaterial:
	var key := Vector2(strength, root_v)
	if _wind.has(key):
		return _wind[key]
	var material := ShaderMaterial.new()
	material.shader = WIND_SHADER
	material.set_shader_parameter("strength", strength)
	material.set_shader_parameter("root_v", root_v)
	_wind[key] = material
	register(material)
	return material


static func set_scale(value: float) -> void:
	if is_equal_approx(value, _scale):
		return
	_scale = value
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter("motion", value)


static func get_scale() -> float:
	return _scale

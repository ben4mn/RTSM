extends MeshInstance2D
## The edge of the world (presentation only): one static ring mesh around the
## playable diamond, painted by assets/terrain/map_rim.gdshader as a sandy
## bank, a lapping foam line and a sea that fades into the empty canvas
## colour. Eight triangles, one draw call, no per-frame work.

const RIM_SHADER: Shader = preload("res://assets/terrain/map_rim.gdshader")
const AMBIENT_MOTION := preload("res://scripts/map/ambient_motion.gd")
## Tile-space inset of the inner edge: the bank covers the last half tile.
const INNER_INSET: float = 0.1
## How far the sea is drawn beyond the field, in tiles. The camera focus never
## leaves the field, so even the widest zoom sees the sea dim into the canvas.
const OUTER_TILES: float = 30.0

var _material: ShaderMaterial = null


func setup(noise: Texture2D, origin: Vector2, axis_x: Vector2, axis_y: Vector2, inverse: Vector4, tiles: int) -> void:
	name = "MapRim"
	var low_in: float = INNER_INSET
	var high_in: float = float(tiles) - 1.0 - INNER_INSET
	var low_out: float = -0.5 - OUTER_TILES
	var high_out: float = float(tiles) - 0.5 + OUTER_TILES
	var at := func(u: float, v: float) -> Vector2:
		return origin + axis_x * u + axis_y * v
	var inner: Array[Vector2] = [at.call(low_in, low_in), at.call(high_in, low_in), at.call(high_in, high_in), at.call(low_in, high_in)]
	var outer: Array[Vector2] = [at.call(low_out, low_out), at.call(high_out, low_out), at.call(high_out, high_out), at.call(low_out, high_out)]
	var vertices := PackedVector2Array()
	for corner: int in 4:
		var next: int = (corner + 1) % 4
		vertices.append_array([outer[corner], outer[next], inner[corner], inner[corner], outer[next], inner[next]])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var ring := ArrayMesh.new()
	ring.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = ring
	_material = ShaderMaterial.new()
	_material.shader = RIM_SHADER
	_material.set_shader_parameter("rim_noise", noise)
	_material.set_shader_parameter("map_origin", origin)
	_material.set_shader_parameter("map_inverse", inverse)
	_material.set_shader_parameter("map_tiles", float(tiles))
	var night: Color = ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color", Color(0.094, 0.165, 0.188))
	_material.set_shader_parameter("night", Vector3(night.r, night.g, night.b))
	material = _material
	AMBIENT_MOTION.register(_material)


func _exit_tree() -> void:
	AMBIENT_MOTION.unregister(_material)

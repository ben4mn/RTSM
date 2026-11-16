extends Polygon2D
## The whole fog of war as one soft quad (see assets/terrain/fog_veil.gdshader).
##
## FogManager keeps an 88x88 image of the canonical grid. That image is drawn
## into a tiny viewport that is never cleared, at partial opacity, so the
## texture the shader reads eases toward the truth over a few frames: vision
## feathers in and out instead of popping. The viewport only renders while a
## change is settling. Presentation only: nothing reads it back.

const AMBIENT_MOTION := preload("res://scripts/map/ambient_motion.gd")
const VEIL_SHADER: Shader = preload("res://assets/terrain/fog_veil.gdshader")
const EDGE_MARGIN: float = 1600.0
const EASE_RATE: float = 7.5
const SETTLE_SECONDS: float = 1.4
## A change this large is a reveal, restore or fixture; show it at once.
const SNAP_CHANGED_CELLS: int = 2500

var game_map: Node2D
var _viewport: SubViewport = null
var _stamp: Sprite2D = null
var _state_texture: ImageTexture = null
var _fog: FogManager = null
var _seen_revision: int = -1
var _settle: float = 0.0
var _snap_frames: int = 0
var _rendering: bool = true


func setup(map: Node2D, noise: Texture2D, origin: Vector2, inverse: Vector4) -> void:
	game_map = map
	var width: float = float(MapData.MAP_WIDTH + MapData.MAP_HEIGHT) * float(MapData.TILE_WIDTH) * 0.5
	var height: float = float(MapData.MAP_WIDTH + MapData.MAP_HEIGHT) * float(MapData.TILE_HEIGHT) * 0.5
	var area := Rect2(-width * 0.5 - EDGE_MARGIN, -EDGE_MARGIN, width + EDGE_MARGIN * 2.0, height + EDGE_MARGIN * 2.0)
	polygon = PackedVector2Array([area.position, Vector2(area.end.x, area.position.y), area.end, Vector2(area.position.x, area.end.y)])
	color = Color.WHITE

	_viewport = SubViewport.new()
	_viewport.name = "FogEase"
	_viewport.size = Vector2i(MapData.MAP_WIDTH, MapData.MAP_HEIGHT)
	_viewport.disable_3d = true
	_viewport.transparent_bg = false
	_viewport.gui_disable_input = true
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var blank := Image.create(MapData.MAP_WIDTH, MapData.MAP_HEIGHT, false, Image.FORMAT_RGB8)
	blank.fill(Color.BLACK)
	_state_texture = ImageTexture.create_from_image(blank)
	_stamp = Sprite2D.new()
	_stamp.centered = false
	_stamp.texture = _state_texture
	_stamp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_viewport.add_child(_stamp)

	var veil := ShaderMaterial.new()
	veil.shader = VEIL_SHADER
	veil.set_shader_parameter("fog_state", _viewport.get_texture())
	veil.set_shader_parameter("veil_noise", noise)
	veil.set_shader_parameter("map_origin", origin)
	veil.set_shader_parameter("map_inverse", inverse)
	veil.set_shader_parameter("map_tiles", float(MapData.MAP_WIDTH))
	material = veil
	AMBIENT_MOTION.register(veil)
	_snap_frames = 3


func _process(delta: float) -> void:
	var fog: FogManager = game_map.fog_of_war if game_map != null else null
	if fog == null or fog.fog_image == null:
		return
	if fog != _fog or fog.fog_image_revision != _seen_revision:
		if fog != _fog or _seen_revision < 0 or fog.fog_image_revision - _seen_revision > SNAP_CHANGED_CELLS:
			_snap_frames = 3
		_fog = fog
		_seen_revision = fog.fog_image_revision
		_state_texture.update(fog.fog_image)
		_settle = SETTLE_SECONDS
	if _settle <= 0.0 and _snap_frames <= 0:
		if _rendering:
			_rendering = false
			_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	if not _rendering:
		_rendering = true
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if PerfProbe.on: PerfProbe.count(&"fog.veil_render_frames")
	var real_delta: float = delta / maxf(0.001, Engine.time_scale)
	_settle -= real_delta
	var blend: float = 1.0 - exp(-EASE_RATE * real_delta)
	if _snap_frames > 0 or AMBIENT_MOTION.get_scale() <= 0.0:
		_snap_frames -= 1
		blend = 1.0
	_stamp.modulate = Color(1.0, 1.0, 1.0, clampf(blend, 0.08, 1.0))

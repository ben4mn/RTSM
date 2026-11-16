class_name ResearchPips
extends Node2D
## World progress pips: a small gold ring above each of the local player's
## buildings that is researching (the Town Center's age-up included), in the
## same ink-and-gold vocabulary as the bell and garrison badges.
##
## One node draws every pip. It reads `BuildingBase.research_id` and
## `get_research_ratio()`, which are live on the authority and on a client
## replica alike, so it needs no signal and changes no simulation state. It
## sleeps (no processing, no drawing) while nothing is being researched.

const POLL_SECONDS: float = 0.5
const REDRAW_SECONDS: float = 0.1
const RADIUS: float = 13.0
const RING_WIDTH: float = 3.5
const ICON_SIZE: float = 15.0
const INK := Color("1d2b2c")
const TRACK := Color("4a5c58")
const GOLD := Color("e8bf77")
const AGE_GOLD := Color("ffd98a")

static var _icon_cache: Dictionary = {}

var main: Node = null
var _active: Array[BuildingBase] = []
var _poll: float = 0.0
var _redraw: float = 0.0


static func install(match_main: Node) -> void:
	if NetworkSession.server_mode or DisplayServer.get_name() == "headless":
		return
	var pips := ResearchPips.new()
	pips.name = "ResearchPips"
	pips.main = match_main
	pips.z_index = 89
	pips.process_mode = Node.PROCESS_MODE_PAUSABLE
	# The map does not exist yet when extensions register.
	match_main.add_child(pips)


func _process(delta: float) -> void:
	if not is_instance_valid(main):
		return
	_poll -= delta
	if _poll <= 0.0:
		_poll = POLL_SECONDS
		_collect()
	if _active.is_empty():
		return
	_redraw -= delta
	if _redraw <= 0.0:
		_redraw = REDRAW_SECONDS
		queue_redraw()


func _collect() -> void:
	var was_empty: bool = _active.is_empty()
	_active.clear()
	var rosters: Variant = main.get("_player_buildings")
	if rosters is Array and not (rosters as Array).is_empty() and rosters[0] is Array:
		for entry: Variant in rosters[0]:
			if is_instance_valid(entry) and entry is BuildingBase and not (entry as BuildingBase).research_id.is_empty() \
					and (entry as BuildingBase).state == BuildingBase.State.ACTIVE:
				_active.append(entry as BuildingBase)
	if _active.is_empty() != was_empty:
		queue_redraw()


func _draw() -> void:
	for building: BuildingBase in _active:
		if not is_instance_valid(building) or building.research_id.is_empty() or not building.is_visible_in_tree():
			continue
		draw_pip(self, to_local(pip_position(building)), building.get_research_ratio(), building.research_id)


## On the roof's peak: below the health bar, the drop-off letters and the bell
## and garrison badges (all of which float above `_visual_top`), so none of
## them ever share its spot.
static func pip_position(building: BuildingBase) -> Vector2:
	return building.global_position + building._footprint_center + Vector2(0.0, building._visual_top - 34.0)


static func draw_pip(canvas: CanvasItem, center: Vector2, ratio: float, research_id: String) -> void:
	var age_up: bool = research_id.begins_with(TechData.AGE_RESEARCH_PREFIX)
	var radius: float = RADIUS + (2.0 if age_up else 0.0)
	var gold: Color = AGE_GOLD if age_up else GOLD
	canvas.draw_circle(center, radius + 1.5, Color(INK, 0.94))
	canvas.draw_arc(center, radius - RING_WIDTH * 0.5, 0.0, TAU, 32, TRACK, RING_WIDTH, true)
	var sweep: float = clampf(ratio, 0.0, 1.0) * TAU
	if sweep > 0.01:
		canvas.draw_arc(center, radius - RING_WIDTH * 0.5, -PI * 0.5, -PI * 0.5 + sweep, maxi(4, int(sweep * 6.0)), gold, RING_WIDTH, true)
	var icon: Texture2D = _icon_for(research_id)
	var extent: float = ICON_SIZE + (2.0 if age_up else 0.0)
	if icon != null:
		canvas.draw_texture_rect(icon, Rect2(center - Vector2(extent, extent) * 0.5, Vector2(extent, extent)), false)
	else:
		canvas.draw_circle(center, 3.0, gold)


static func _icon_for(research_id: String) -> Texture2D:
	if _icon_cache.has(research_id):
		return _icon_cache[research_id] as Texture2D
	var icon: Texture2D = null
	if research_id.begins_with(TechData.AGE_RESEARCH_PREFIX):
		icon = CommandIcons.get_icon("age_up")
	else:
		var path: String = str(GameManager.get_research_definition(0, research_id).get("icon", ""))
		if not path.is_empty() and ResourceLoader.exists(path):
			icon = load(path) as Texture2D
	_icon_cache[research_id] = icon
	return icon

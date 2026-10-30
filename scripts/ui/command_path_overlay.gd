extends Node2D
## Selected friendly orders: live navigation routes and destination markers.
## A leader represents nearby formation destinations to keep phone views clear.

const MAX_ROUTE_GROUPS: int = 3
const PREVIEW_SECONDS: float = 1.4
const FADE_SECONDS: float = 0.6
const FORMATION_GOAL_RADIUS: float = 96.0
const MOVE_COLOR := Color("8cdecf")
const ATTACK_COLOR := Color("ff9d85")
const WORK_COLOR := Color("f1d18a")
const SELECTION_CUE_INK := Color("293235")
const SELECTION_CUE_BONE := Color("e8e5db")
# Two hollow foot brackets, in screen pixels. Pairs are separate line segments.
const SELECTION_CUE_SEGMENTS: Array[Vector2] = [
	Vector2(-6, -2), Vector2(-6, 4), Vector2(-6, 4), Vector2(-3, 4),
	Vector2(6, -2), Vector2(6, 4), Vector2(6, 4), Vector2(3, 4),
]

var _observed_orders: Dictionary = {}

@onready var selection_manager: SelectionManager = get_parent().get_node("SelectionManager") as SelectionManager


## Units the player just ordered without selecting them (workers panel, rally
## births, farm shortcut). Their route previews like a selected unit's once.
var _noted_orders: Dictionary = {}  # instance id -> {"unit": WeakRef, "time": seconds}


func note_ordered(units: Array) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	for node: Variant in units:
		if node is UnitBase and is_instance_valid(node) and (node as UnitBase).player_owner == 0:
			_noted_orders[(node as UnitBase).get_instance_id()] = {"unit": weakref(node), "time": now}
	queue_redraw()


func _process(_delta: float) -> void:
	# Updating reads existing paths only; rendering never runs pathfinding.
	var now: float = Time.get_ticks_msec() / 1000.0
	for id: Variant in _noted_orders.keys():
		if now - float(_noted_orders[id]["time"]) > PREVIEW_SECONDS + FADE_SECONDS + 1.0 or (_noted_orders[id]["unit"] as WeakRef).get_ref() == null:
			_noted_orders.erase(id)
	if not selection_manager.selected.is_empty() or not _noted_orders.is_empty():
		queue_redraw()


func _ready() -> void:
	selection_manager.selection_changed.connect(func(_selection: Array[Node2D]) -> void:
		# Changing or clearing the selection ends every preview, noted ones too.
		_observed_orders.clear()
		_noted_orders.clear()
		queue_redraw())


## Public for render fixtures and regressions; every route is world-space.
func get_display_routes() -> Array[Dictionary]:
	var routes: Array[Dictionary] = []
	var candidates: Array = selection_manager.selected.duplicate()
	for entry: Dictionary in _noted_orders.values():
		var noted: Variant = (entry["unit"] as WeakRef).get_ref()
		if noted != null and noted not in candidates:
			candidates.append(noted)
	for selected_node: Variant in candidates:
		if not is_instance_valid(selected_node) or not (selected_node is UnitBase):
			continue
		var unit := selected_node as UnitBase
		if unit.player_owner != 0 or not unit.is_visible_in_tree():
			continue
		var points: PackedVector2Array = unit.get_remaining_navigation_path()
		var resuming_attack_move: bool = unit.attack_move and unit.current_state == UnitBase.State.ATTACKING
		if points.is_empty() and not resuming_attack_move:
			continue
		var mode: String = "move"
		if unit.attack_move or unit.current_state == UnitBase.State.ATTACKING:
			mode = "attack"
		elif unit.current_state in [UnitBase.State.GATHERING, UnitBase.State.BUILDING] or (unit is Villager and (unit as Villager).get_work_status() not in ["Idle", "Moving"]):
			mode = "work"
		var destination: Vector2 = points[points.size() - 1] if not points.is_empty() else unit.move_target
		var order_destination: Vector2 = unit.move_target if resuming_attack_move else destination
		var id: int = unit.get_instance_id()
		# A new destination or selecting the unit previews its route once. Walking,
		# gathering shuttles and combat repaths do not continually restart the flash.
		var signature: String = "%s:%s" % [mode, unit.move_target]
		var now: float = Time.get_ticks_msec() / 1000.0
		var observed: Dictionary = _observed_orders.get(id, {})
		if observed.get("signature", "") != signature:
			observed = {"signature": signature, "started": now}
			_observed_orders[id] = observed
		var elapsed: float = now - float(observed.started)
		var opacity: float = clampf((PREVIEW_SECONDS + FADE_SECONDS - elapsed) / FADE_SECONDS, 0.0, 1.0)
		if opacity <= 0.0:
			continue
		var represented: bool = false
		for route: Dictionary in routes:
			if route["mode"] == mode and (route["order_destination"] as Vector2).distance_to(order_destination) <= FORMATION_GOAL_RADIUS:
				represented = true
				break
		if represented:
			continue
		routes.append({"points": points, "destination": destination, "order_destination": order_destination, "mode": mode, "opacity": opacity})
		if routes.size() >= MAX_ROUTE_GROUPS:
			break
	return routes


## Selected own positions only. No target discovery, simulation or input change.
func get_selected_unit_cue_points() -> PackedVector2Array:
	var points := PackedVector2Array()
	if selection_manager == null or not GameManager.clearer_player_markers:
		return points
	var map: Node2D = selection_manager.game_map
	if not is_instance_valid(map):
		return points
	var zoom: float = maxf(0.1, get_canvas_transform().x.length())
	for entry: Variant in selection_manager.selected:
		if not is_instance_valid(entry) or not entry is UnitBase:
			continue
		var unit := entry as UnitBase
		if unit.player_owner != 0 or not unit.is_selected or unit.is_queued_for_deletion():
			continue
		if unit.current_state == UnitBase.State.DEAD or unit.hp <= 0.0 or not unit.is_visible_in_tree():
			continue
		var tile: Vector2i = map.call("world_to_tile", unit.global_position)
		if not bool(map.call("is_tile_visible_to_player", tile, 0)):
			continue
		var anchor: Vector2 = to_local(unit.global_position)
		for offset: Vector2 in SELECTION_CUE_SEGMENTS:
			points.append(anchor + offset / zoom)
	return points


## Current visible attack targets, capped like route groups. This is a target
## cue, never a projected path or an enemy-discovery query.
func get_combat_target_cues() -> Array[Vector2]:
	var targets: Array[Vector2] = []
	var seen: Dictionary = {}
	for entry: Node2D in selection_manager.selected:
		if not is_instance_valid(entry) or not entry is UnitBase or entry.player_owner != 0:
			continue
		var unit := entry as UnitBase
		if unit.current_state != UnitBase.State.ATTACKING or not unit.is_visible_in_tree():
			continue
		var target: Node2D = null
		if is_instance_valid(unit.attack_target) and unit._is_valid_target(unit.attack_target):
			target = unit.attack_target
		elif is_instance_valid(unit.attack_building_target) and unit._is_valid_building_target(unit.attack_building_target):
			target = unit.attack_building_target
		if target == null or not target.is_visible_in_tree() or seen.has(target.get_instance_id()):
			continue
		seen[target.get_instance_id()] = true
		targets.append(target.global_position)
		if targets.size() >= MAX_ROUTE_GROUPS:
			break
	return targets


func _draw() -> void:
	if selection_manager == null:
		return
	# Keep strokes and targets readable at both overview and detail zoom.
	var zoom: float = maxf(0.1, get_canvas_transform().x.length())
	_draw_queued_destinations(zoom)
	for route: Dictionary in get_display_routes():
		var world_points: PackedVector2Array = route["points"]
		var points := PackedVector2Array()
		for point: Vector2 in world_points:
			points.append(to_local(point))
		var color: Color = ATTACK_COLOR if route["mode"] == "attack" else (WORK_COLOR if route["mode"] == "work" else MOVE_COLOR)
		color.a = 0.55 * float(route.get("opacity", 1.0))
		# One continuous stroke avoids restarting a dash at every tiny A*
		# segment, which made the same route look jagged at different zooms.
		if points.size() >= 2:
			draw_polyline(points, color, 1.25 / zoom, true)
		_draw_destination(to_local(route["destination"]), color, zoom, route["mode"] == "attack")
		# Engagement temporarily replaces the live route with a chase. Keep the
		# attack-move goal marked so the player knows where troops will resume.
		if (route["order_destination"] as Vector2).distance_to(route["destination"]) > 8.0:
			_draw_destination(to_local(route["order_destination"]), color, zoom, true)
		# A direction arrow near the next waypoint distinguishes the start from
		# the destination without covering the selected unit's feet.
		if points.size() < 2:
			continue
		var next: Vector2 = points[1]
		var direction: Vector2 = (next - points[0]).normalized()
		var arrow: Vector2 = points[0].lerp(next, 0.65)
		if points[0].distance_to(next) * zoom > 20.0:
			var side := direction.orthogonal()
			draw_polyline(PackedVector2Array([
				arrow - direction * 5.0 / zoom + side * 4.0 / zoom,
				arrow,
				arrow - direction * 5.0 / zoom - side * 4.0 / zoom,
			]), color, 2.0 / zoom, true)
	for target: Vector2 in get_combat_target_cues():
		var center: Vector2 = to_local(target)
		for side: float in [-1.0, 1.0]:
			var bracket := PackedVector2Array([center + Vector2(side * 8, -6) / zoom, center + Vector2(side * 11, -6) / zoom, center + Vector2(side * 11, 4) / zoom, center + Vector2(side * 8, 4) / zoom])
			draw_polyline(bracket, SELECTION_CUE_INK, 3.0 / zoom, true)
			draw_polyline(bracket, ATTACK_COLOR, 1.5 / zoom, true)
	# Persist independently of brief order previews. Only the hollow cue paints
	# above crowded bodies; unit artwork, world rings and health stay in place.
	var cues: PackedVector2Array = get_selected_unit_cue_points()
	if not cues.is_empty():
		draw_multiline(cues, SELECTION_CUE_INK, 3.0 / zoom, true)
		draw_multiline(cues, SELECTION_CUE_BONE, 1.5 / zoom, true)


func get_queued_destination_markers() -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	for entry: Node2D in selection_manager.selected:
		if not is_instance_valid(entry) or not (entry is UnitBase or entry is BuildingBase) or entry.player_owner != 0:
			continue
		var orders: Array[Dictionary] = entry.queued_orders if entry is UnitBase else entry.rally_orders
		if orders.is_empty():
			continue
		var points := PackedVector2Array()
		for order: Dictionary in orders:
			if order.has("position"):
				points.append(order.position)
		if not points.is_empty():
			# Formation members share a route even though their reserved tiles differ.
			# Show one numbered sequence instead of stacking labels on tiny screens.
			var represented: bool = false
			for group: Dictionary in groups:
				var existing: PackedVector2Array = group.points
				if existing.size() != points.size():
					continue
				var same_route: bool = true
				for index: int in points.size():
					if existing[index].distance_to(points[index]) > FORMATION_GOAL_RADIUS:
						same_route = false
						break
				if same_route:
					represented = true
					break
			if represented:
				continue
			var origin: Vector2 = entry.move_target if entry is UnitBase and entry.current_state == UnitBase.State.MOVING else entry.global_position
			groups.append({"origin": origin, "points": points})
		if groups.size() >= MAX_ROUTE_GROUPS:
			break
	return groups


func _draw_queued_destinations(zoom: float) -> void:
	# A queued destination has no accepted navigation route until that leg
	# starts. Number the goals without a misleading line through obstacles.
	var font: Font = ThemeDB.fallback_font
	for group: Dictionary in get_queued_destination_markers():
		var index: int = 0
		for world: Vector2 in group.points:
			index += 1
			var point: Vector2 = to_local(world)
			draw_circle(point, 9.0 / zoom, Color("293235"))
			draw_arc(point, 9.0 / zoom, 0, TAU, 24, MOVE_COLOR, 1.5 / zoom, true)
			draw_set_transform(point, 0.0, Vector2.ONE / zoom)
			draw_string(font, Vector2(-4, 5), str(index), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, MOVE_COLOR)
			draw_set_transform(Vector2.ZERO)


func _draw_destination(destination: Vector2, color: Color, zoom: float, attack: bool) -> void:
	draw_circle(destination, 9.0 / zoom, Color(0.04, 0.10, 0.12, color.a * 0.7))
	draw_arc(destination, 7.0 / zoom, 0.0, TAU, 24, color, 2.0 / zoom, true)
	if attack:
		draw_line(destination + Vector2(-3, -3) / zoom, destination + Vector2(3, 3) / zoom, color, 1.5 / zoom, true)
		draw_line(destination + Vector2(-3, 3) / zoom, destination + Vector2(3, -3) / zoom, color, 1.5 / zoom, true)
	else:
		draw_circle(destination, 2.5 / zoom, color)

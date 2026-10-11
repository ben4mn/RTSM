extends Node2D
## Selected friendly orders: live navigation routes and destination markers.
## A leader represents nearby formation destinations to keep phone views clear.

const MAX_ROUTE_GROUPS: int = 4
const FORMATION_GOAL_RADIUS: float = 96.0
const MOVE_COLOR := Color("8cdecf")
const ATTACK_COLOR := Color("ff9d85")
const WORK_COLOR := Color("f1d18a")

@onready var selection_manager: SelectionManager = get_parent().get_node("SelectionManager") as SelectionManager


func _process(_delta: float) -> void:
	# Updating reads existing paths only; rendering never runs pathfinding.
	if not selection_manager.selected.is_empty():
		queue_redraw()


func _ready() -> void:
	selection_manager.selection_changed.connect(func(_selection: Array[Node2D]) -> void: queue_redraw())


## Public for render fixtures and regressions; every route is world-space.
func get_display_routes() -> Array[Dictionary]:
	var routes: Array[Dictionary] = []
	for selected_node: Node2D in selection_manager.selected:
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
		elif unit.current_state in [UnitBase.State.GATHERING, UnitBase.State.BUILDING]:
			mode = "work"
		var destination: Vector2 = points[points.size() - 1] if not points.is_empty() else unit.move_target
		var order_destination: Vector2 = unit.move_target if resuming_attack_move else destination
		var represented: bool = false
		for route: Dictionary in routes:
			if route["mode"] == mode and (route["order_destination"] as Vector2).distance_to(order_destination) <= FORMATION_GOAL_RADIUS:
				represented = true
				break
		if represented:
			continue
		routes.append({"points": points, "destination": destination, "order_destination": order_destination, "mode": mode})
		if routes.size() >= MAX_ROUTE_GROUPS:
			break
	return routes


func _draw() -> void:
	if selection_manager == null:
		return
	# Keep strokes and targets readable at both overview and detail zoom.
	var zoom: float = maxf(0.1, get_canvas_transform().x.length())
	for route: Dictionary in get_display_routes():
		var world_points: PackedVector2Array = route["points"]
		var points := PackedVector2Array()
		for point: Vector2 in world_points:
			points.append(to_local(point))
		var color: Color = ATTACK_COLOR if route["mode"] == "attack" else (WORK_COLOR if route["mode"] == "work" else MOVE_COLOR)
		if points.size() >= 2:
			draw_polyline(points, Color(0.04, 0.10, 0.12, 0.70), 4.5 / zoom, true)
		for index: int in range(1, points.size()):
			draw_dashed_line(points[index - 1], points[index], color, 2.0 / zoom, 7.0 / zoom, true, true)
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


func _draw_destination(destination: Vector2, color: Color, zoom: float, attack: bool) -> void:
	draw_circle(destination, 9.0 / zoom, Color(0.04, 0.10, 0.12, 0.80))
	draw_arc(destination, 7.0 / zoom, 0.0, TAU, 24, color, 2.0 / zoom, true)
	if attack:
		draw_line(destination + Vector2(-3, -3) / zoom, destination + Vector2(3, 3) / zoom, color, 1.5 / zoom, true)
		draw_line(destination + Vector2(-3, 3) / zoom, destination + Vector2(3, -3) / zoom, color, 1.5 / zoom, true)
	else:
		draw_circle(destination, 2.5 / zoom, color)

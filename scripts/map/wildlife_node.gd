class_name WildlifeNode
extends ResourceNode
## A sheep, deer or boar. It is a harvestable like a berry bush (villagers
## gather it through the same registry and commands) that can also walk, be
## owned, and, for a boar, fight back. It is deliberately not a UnitBase: no
## player owns it as an army unit and nothing auto-targets it.
##
## The authority simulates it in `_process`; online clients hold inert
## replicas that only ease toward the last snapshot and animate.

signal felled(node: WildlifeNode)
signal enraged(node: WildlifeNode, target: Node2D)
signal owner_changed(node: WildlifeNode, previous_owner: int)

enum Phase { ALIVE, CARCASS }
enum Mood { CALM, ENRAGED, RETURNING }

const TEXTURES: Dictionary = {
	"sheep": "res://assets/resources/sheep.svg",
	"sheep_walk": "res://assets/resources/sheep_walk.svg",
	"deer": "res://assets/resources/deer.svg",
	"deer_walk": "res://assets/resources/deer.svg",
	"boar": "res://assets/resources/boar.svg",
	"boar_walk": "res://assets/resources/boar_charge.svg",
	"carcass": "res://assets/resources/carcass.svg",
}
## Authored on a 128px canvas with the feet on y104, like the unit sprites.
const SPRITE_SCALES: Dictionary = {"sheep": 0.36, "deer": 0.44, "boar": 0.46, "carcass": 0.40}
const SPRITE_FOOT_OFFSET := Vector2(0.0, -40.0)
const ROUTE_REFRESH_SECONDS: float = 1.0
const CHASE_REPATH_SECONDS: float = 0.35

var kind: String = WildlifeData.SHEEP
## Stable index in the placement plan; the network id of this animal.
var wildlife_id: int = -1
var owner_id: int = -1
var phase: int = Phase.ALIVE
var mood: int = Mood.CALM
var gather_multiplier: float = WildlifeData.GATHER_MULTIPLIER
var hp: float = 0.0
var max_hp: float = 0.0
var home_position: Vector2 = Vector2.ZERO
var game_map: Node2D = null
var replica: bool = false
var net_position: Vector2 = Vector2.ZERO
## Set by the director: a villager currently has this animal as its job.
var tended: bool = false
## A manual herd order parks the sheep; the walk-home assist leaves it alone.
var manual_stay: bool = false
## The player whose pasture `home_position` is a slot in (-1: not pastured).
var pasture_owner: int = -1
var team_color: Color = Color.WHITE
var last_striker_owner: int = -1

var move_goal: Vector2 = Vector2.ZERO
var has_goal: bool = false
var _route: PackedVector2Array = PackedVector2Array()
var _route_index: int = 0
var _route_refresh: float = 0.0
var _target_ref: WeakRef = null
var _bite_cooldown: float = 0.0
var _recoil: float = 0.0
var _arrow_ready: Dictionary = {}
var _arrow_scan: float = 0.0
var _clock: float = 0.0
var _decay: float = 0.0

# Presentation only.
var _moving: bool = false
var _facing_left: bool = false
var _anim: float = 0.0
var _lunge: float = 0.0
var _flash: float = 0.0
var _dust: float = 0.0
var _shown_texture: String = ""
var _last_position: Vector2 = Vector2.ZERO
var _headless: bool = false


func _ready() -> void:
	resource_type = "food"
	_headless = DisplayServer.get_name() == "headless"
	super._ready()
	add_to_group("wildlife")
	if kind == WildlifeData.BOAR and max_hp <= 0.0:
		max_hp = WildlifeData.BOAR_MAX_HP
		hp = max_hp
	if home_position == Vector2.ZERO:
		home_position = global_position
	net_position = global_position
	_last_position = global_position
	_anim = float(posmod(wildlife_id * 37, 100)) * 0.13
	_refresh_texture()


func _setup_sprite() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite"
	_sprite.offset = SPRITE_FOOT_OFFSET
	_sprite.show_behind_parent = true
	add_child(_sprite)


func get_presentation_texture_path() -> String:
	if phase == Phase.CARCASS:
		return TEXTURES["carcass"]
	return TEXTURES.get(kind, TEXTURES["sheep"])


func is_sprite_body_hit(world_position: Vector2) -> bool:
	return _sprite != null and _sprite.texture != null and _sprite.is_pixel_opaque(_sprite.to_local(world_position))


func get_display_name() -> String:
	if phase == Phase.CARCASS:
		return "%s Carcass" % str(WildlifeData.NAMES.get(kind, "Animal"))
	return str(WildlifeData.NAMES.get(kind, "Animal"))


func is_alive() -> bool:
	return phase == Phase.ALIVE and remaining > 0


func is_fighting() -> bool:
	return kind == WildlifeData.BOAR and phase == Phase.ALIVE


func is_herdable_by(player_id: int) -> bool:
	return kind == WildlifeData.SHEEP and phase == Phase.ALIVE and remaining > 0 and owner_id == player_id and player_id >= 0


# --- Harvest contract ---------------------------------------------------------

## Sheep belong to whoever claimed them (the Farm pattern); deer, boar and any
## boar or deer carcass are open to everybody.
func is_harvestable_by(gathering_player_id: int = -1) -> bool:
	if remaining <= 0:
		return false
	if kind == WildlifeData.SHEEP:
		return owner_id >= 0 and (gathering_player_id < 0 or gathering_player_id == owner_id)
	return true


## "Gather nearest food" must never walk a villager into a live boar.
func is_auto_gather_target() -> bool:
	return remaining > 0 and not is_fighting()


## Bias for nearest-food lookups so owned sheep and open carcasses come first.
func discovery_distance(distance: float, player_id: int) -> float:
	if player_id < 0 or remaining <= 0 or distance > WildlifeData.tiles_to_world_bound(WildlifeData.PREFER_RADIUS_TILES):
		return distance
	if phase == Phase.CARCASS and is_harvestable_by(player_id):
		return distance * WildlifeData.PREFER_OPEN_CARCASS
	if kind == WildlifeData.SHEEP and owner_id == player_id:
		return distance * WildlifeData.PREFER_OWNED_SHEEP
	return distance


func harvest(amount: int) -> int:
	if remaining <= 0 or is_fighting():
		return 0
	if phase == Phase.ALIVE:
		_become_carcass()
	return super.harvest(amount)


## A villager's gather tick against a live boar is a blow, not a harvest.
## Returns true when the tick was spent fighting.
func absorb_strike(villager: UnitBase) -> bool:
	if not is_fighting() or replica:
		return false
	last_striker_owner = villager.player_owner if is_instance_valid(villager) else -1
	if mood != Mood.ENRAGED:
		enrage(villager)
	_take_hit(WildlifeData.BOAR_VILLAGER_STRIKE)
	return true


func _take_hit(amount: float) -> void:
	if not is_fighting():
		return
	hp = maxf(0.0, hp - amount)
	_flash = 0.14
	queue_redraw()
	if hp <= 0.0:
		_fell()


func _fell() -> void:
	mood = Mood.CALM
	_target_ref = null
	_stop()
	_become_carcass()
	GameManager.boar_felled.emit(last_striker_owner, global_position)
	felled.emit(self)


func _become_carcass() -> void:
	phase = Phase.CARCASS
	mood = Mood.CALM
	hp = 0.0
	_stop()
	_refresh_texture()
	queue_redraw()


## Spoilage for an opened carcass nobody is working. Whole food only.
func spoil(delta: float) -> void:
	if phase != Phase.CARCASS or tended or remaining <= 0:
		return
	_decay += WildlifeData.CARCASS_DECAY_PER_SECOND * delta
	if _decay >= 1.0:
		var lost: int = floori(_decay)
		_decay -= float(lost)
		super.harvest(lost)


# --- Ownership (sheep) ----------------------------------------------------------

func set_owner_id(new_owner: int, color: Color = Color.WHITE) -> void:
	var previous: int = owner_id
	owner_id = new_owner
	team_color = color
	queue_redraw()
	if previous != new_owner:
		owner_changed.emit(self, previous)


# --- Movement -----------------------------------------------------------------

func walk_to(goal: Vector2) -> bool:
	if replica or phase != Phase.ALIVE:
		return false
	var route: PackedVector2Array = _plan_route(goal)
	if route.is_empty():
		return false
	move_goal = goal
	has_goal = true
	_route = route
	_route_index = 0
	_route_refresh = ROUTE_REFRESH_SECONDS
	return true


func _plan_route(goal: Vector2) -> PackedVector2Array:
	if game_map == null or not game_map.has_method("get_navigation_world_path"):
		return PackedVector2Array([goal])
	var route: PackedVector2Array = game_map.call("get_navigation_world_path", global_position, goal, 4.0)
	# The first waypoint is the centre of the tile already underfoot.
	if route.size() > 1 and route[0].distance_to(global_position) < float(MapData.TILE_WIDTH) * 0.5:
		route.remove_at(0)
	return route


func _stop() -> void:
	has_goal = false
	_route = PackedVector2Array()
	_route_index = 0


func is_walking() -> bool:
	return has_goal and _route_index < _route.size()


func _advance_route(delta: float, speed: float) -> bool:
	var step: float = speed * delta
	var moved: bool = false
	while step > 0.0 and _route_index < _route.size():
		var offset: Vector2 = _route[_route_index] - global_position
		var distance: float = offset.length()
		if distance <= step:
			global_position = _route[_route_index]
			_route_index += 1
			step -= distance
		else:
			global_position += offset / distance * step
			step = 0.0
		moved = true
	if _route_index >= _route.size():
		has_goal = false
	return moved


# --- Boar behaviour -------------------------------------------------------------

func get_target() -> UnitBase:
	return _target_ref.get_ref() as UnitBase if _target_ref != null else null


func enrage(target: UnitBase) -> void:
	if not is_fighting() or replica or not _is_valid_target(target):
		return
	var was_enraged: bool = mood == Mood.ENRAGED
	mood = Mood.ENRAGED
	_target_ref = weakref(target)
	_route_refresh = 0.0
	if not was_enraged:
		_bite_cooldown = WildlifeData.BOAR_BITE_INTERVAL * 0.5
		_refresh_texture()
		enraged.emit(self, target)


func _is_valid_target(target: Variant) -> bool:
	if not is_instance_valid(target) or not target is UnitBase:
		return false
	var unit := target as UnitBase
	if not unit.is_inside_tree() or unit.is_queued_for_deletion() or unit.current_state == UnitBase.State.DEAD or unit.hp <= 0.0:
		return false
	# A garrisoned villager has left the field (defence workstream).
	if unit.current_state == int(UnitBase.State.get("GARRISONED", -99)) or not unit.is_in_group("units"):
		return false
	return true


func _find_nearby_villager() -> UnitBase:
	if game_map == null or not game_map.has_method("get_units_near"):
		return null
	var best: UnitBase = null
	var best_distance: float = INF
	for unit: UnitBase in game_map.call("get_units_near", global_position, WildlifeData.tiles_to_world_bound(WildlifeData.BOAR_RETARGET_RADIUS_TILES)):
		if not unit is Villager or not _is_valid_target(unit):
			continue
		var distance: float = WildlifeData.tile_distance(global_position, unit.global_position)
		if distance <= WildlifeData.BOAR_RETARGET_RADIUS_TILES and distance < best_distance:
			best_distance = distance
			best = unit
	return best


func give_up() -> void:
	## Walk home; arriving restores the boar to full strength.
	mood = Mood.RETURNING
	_target_ref = null
	_refresh_texture()
	if not walk_to(home_position):
		_settle_home()


func _settle_home() -> void:
	mood = Mood.CALM
	hp = max_hp
	_stop()
	_refresh_texture()
	queue_redraw()


func _process_boar(delta: float) -> bool:
	_bite_cooldown = maxf(0.0, _bite_cooldown - delta)
	_recoil = maxf(0.0, _recoil - delta)
	if mood != Mood.CALM:
		_take_defensive_fire(delta)
		if not is_fighting():
			return false
	match mood:
		Mood.RETURNING:
			var walked: bool = _advance_route(delta, WildlifeData.BOAR_WALK_SPEED)
			if not is_walking():
				_settle_home()
			return walked
		Mood.ENRAGED:
			var target: UnitBase = get_target()
			if not _is_valid_target(target):
				target = _find_nearby_villager()
				if target == null:
					give_up()
					return false
				_target_ref = weakref(target)
				_route_refresh = 0.0
			var distance: float = global_position.distance_to(target.global_position)
			if WildlifeData.tile_distance(global_position, target.global_position) > WildlifeData.BOAR_LEASH_TILES:
				give_up()
				return false
			if absf(target.global_position.x - global_position.x) > 1.0:
				_facing_left = target.global_position.x < global_position.x
			if _recoil > 0.0:
				return false
			if distance <= WildlifeData.BOAR_BITE_RANGE:
				if _bite_cooldown <= 0.0:
					_bite(target)
				return false
			_route_refresh -= delta
			if _route_refresh <= 0.0:
				_route_refresh = CHASE_REPATH_SECONDS
				_route = _plan_route(target.global_position)
				_route_index = 0
			var speed: float = maxf(WildlifeData.BOAR_BASE_SPEED, target.speed * WildlifeData.BOAR_CHASE_SPEED_FACTOR)
			# Close the last gap straight at the target instead of at a tile centre.
			if _route_index >= _route.size() - 1 and distance < float(MapData.TILE_WIDTH):
				global_position = global_position.move_toward(target.global_position, speed * delta)
				return true
			if _route_index >= _route.size():
				return false
			return _advance_route(delta, speed)
	return false


func _bite(target: UnitBase) -> void:
	_bite_cooldown = WildlifeData.BOAR_BITE_INTERVAL
	_recoil = WildlifeData.BOAR_BITE_RECOIL_SECONDS
	_lunge = 1.0
	if target.has_method("take_wildlife_damage"):
		target.call("take_wildlife_damage", WildlifeData.BOAR_BITE_DAMAGE)
	else:
		target.take_damage(WildlifeData.BOAR_BITE_DAMAGE)


## Town Centers and towers of any player shoot an angry boar inside their range.
func _take_defensive_fire(delta: float) -> void:
	_arrow_scan -= delta
	if _arrow_scan > 0.0 or not is_inside_tree():
		return
	_arrow_scan = 0.2
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		var building := node as BuildingBase
		if building == null or building.tower_attack_damage <= 0 or building.state != BuildingBase.State.ACTIVE or building.hp <= 0:
			continue
		if building.global_position.distance_to(global_position) > building.tower_attack_range:
			continue
		var id: int = building.get_instance_id()
		if _clock < float(_arrow_ready.get(id, 0.0)):
			continue
		_arrow_ready[id] = _clock + WildlifeData.BOAR_ARROW_INTERVAL
		last_striker_owner = building.player_owner
		BattleFX.tower_shot(building, self)
		_take_hit(WildlifeData.BOAR_ARROW_DAMAGE)
		if not is_fighting():
			return


# --- Frame update -------------------------------------------------------------

func _process(delta: float) -> void:
	_clock += delta
	if replica:
		global_position = global_position.lerp(net_position, minf(1.0, delta * 12.0))
	elif phase == Phase.ALIVE and remaining > 0:
		if kind == WildlifeData.BOAR:
			_process_boar(delta)
		elif has_goal and not tended:
			_route_refresh -= delta
			if _route_refresh <= 0.0:
				# A new building may have closed the old route.
				_route_refresh = ROUTE_REFRESH_SECONDS
				var goal: Vector2 = move_goal
				if not walk_to(goal):
					_stop()
			_advance_route(delta, WildlifeData.SHEEP_SPEED)
	var travelled: Vector2 = global_position - _last_position
	_moving = travelled.length() > delta * 2.0 and phase == Phase.ALIVE
	if _moving and absf(travelled.x) > 0.01 and mood != Mood.ENRAGED:
		_facing_left = travelled.x < 0.0
	_last_position = global_position
	if visible and _sprite != null and not _headless:
		_animate(delta)
	if is_selected:
		queue_redraw()


func _refresh_texture() -> void:
	if _sprite == null:
		return
	var key: String = "carcass" if phase == Phase.CARCASS else kind
	if phase == Phase.ALIVE and (mood == Mood.ENRAGED or (_moving and int(_anim * 6.0) % 2 == 0)):
		key = kind + "_walk"
	if key == _shown_texture:
		return
	_shown_texture = key
	var path: String = TEXTURES.get(key, "")
	if path != "" and ResourceLoader.exists(path):
		_sprite.texture = load(path)
	var size: float = float(SPRITE_SCALES.get("carcass" if phase == Phase.CARCASS else kind, 0.4))
	_sprite.scale = Vector2(size, size)


func _animate(delta: float) -> void:
	_anim += delta
	_lunge = maxf(0.0, _lunge - delta * 5.0)
	_flash = maxf(0.0, _flash - delta)
	_refresh_texture()
	var size: float = float(SPRITE_SCALES.get("carcass" if phase == Phase.CARCASS else kind, 0.4))
	_sprite.flip_h = _facing_left
	_sprite.modulate = Color(1.3, 1.22, 1.1) if _flash > 0.0 and not GameManager.reduced_flashes else Color.WHITE
	if phase == Phase.CARCASS or GameManager.reduced_motion:
		_sprite.position = Vector2.ZERO
		_sprite.rotation = 0.0
		_sprite.scale = Vector2(size, size)
		return
	var direction: float = -1.0 if _facing_left else 1.0
	if _moving:
		# A trot: two little hops per stride, leaning into the run when charging.
		var charging: bool = mood == Mood.ENRAGED
		var pace: float = 15.0 if charging else 10.0
		var hop: float = absf(sin(_anim * pace))
		_sprite.position = Vector2(0.0, -hop * (2.4 if charging else 1.8))
		_sprite.rotation = direction * (0.11 if charging else 0.03) + sin(_anim * pace) * 0.03
		_sprite.scale = Vector2(size * (1.0 + hop * 0.03), size * (1.0 - hop * 0.03))
		if charging:
			_dust -= delta
			if _dust <= 0.0:
				_dust = 0.16
				var fx: BattleFX = BattleFX.get_fx()
				if fx != null:
					fx.dust(global_position + Vector2(-direction * 8.0, 0.0), 1, 0.7, 0.5)
		return
	# Standing: slow breathing, and every few seconds the head dips to graze
	# (sheep, deer) or the boar paws and snorts.
	var breath: float = sin(_anim * 2.1) * 0.018
	var cycle: float = fposmod(_anim, 5.5 if kind != WildlifeData.BOAR else 3.4)
	var dip: float = 0.0
	if cycle < 1.6:
		dip = sin(cycle / 1.6 * PI)
	if mood == Mood.ENRAGED:
		dip = absf(sin(_anim * 9.0)) * 0.6
	var lean: float = 0.10 if kind == WildlifeData.SHEEP else (0.07 if kind == WildlifeData.DEER else 0.05)
	_sprite.rotation = direction * dip * lean
	_sprite.position = Vector2(direction * _lunge * 7.0, dip * 0.8 - _lunge * 2.0)
	_sprite.scale = Vector2(size * (1.0 - breath), size * (1.0 + breath))


func _draw() -> void:
	if phase == Phase.ALIVE and kind == WildlifeData.SHEEP and owner_id >= 0:
		# A quiet team-coloured ground mark: whose flock this is, at a glance.
		draw_set_transform(Vector2(0.0, 1.0), 0.0, Vector2(1.0, 0.5))
		draw_arc(Vector2.ZERO, 11.0, 0.0, TAU, 24, Color(team_color, 0.85), 1.6, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if is_selected:
		draw_set_transform(Vector2(0.0, 1.0), 0.0, Vector2(1.0, 0.5))
		draw_arc(Vector2.ZERO, 17.0, 0.0, TAU, 32, Color("e8e5db"), 1.6, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if is_fighting() and (hp < max_hp or is_selected or mood == Mood.ENRAGED):
		var width: float = 26.0
		var top: float = -34.0
		draw_rect(Rect2(-width * 0.5 - 1.0, top - 1.0, width + 2.0, 5.0), Color(0.09, 0.12, 0.13, 0.85))
		draw_rect(Rect2(-width * 0.5, top, width * clampf(hp / maxf(1.0, max_hp), 0.0, 1.0), 3.0), Color("c8643c"))
	elif is_selected and remaining > 0 and remaining < total_amount:
		var bar_width: float = 22.0
		draw_rect(Rect2(-bar_width * 0.5, 8.0, bar_width, 2.5), Color(0.15, 0.15, 0.15, 0.8))
		draw_rect(Rect2(-bar_width * 0.5, 8.0, bar_width * float(remaining) / float(maxi(1, total_amount)), 2.5), _get_resource_color())

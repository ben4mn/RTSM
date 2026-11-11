class_name BattleFX
extends Node2D
## Pooled battlefield presentation: impact particles, floating damage numbers,
## cosmetic projectiles, stuck arrows, corpses, building collapse/rubble, damage
## smoke and camera shake. Everything here is cosmetic. It never reads or writes
## simulation state, consumes no simulation RNG and allocates nothing per hit in
## steady state. One instance lives under GameMap; every static entry point is a
## no-op when no map (unit fixtures) exists.

enum Weapon { BLADE, HOOF, ARROW, STONE, TOOL }

const MAX_PARTICLES: int = 220
const MAX_TEXTS: int = 22
const MAX_SHOTS: int = 24
const MAX_STUCK: int = 36
const MAX_RINGS: int = 8
const MAX_CORPSES: int = 40
const MAX_RUBBLE: int = 10
const CORPSE_SECONDS: float = 20.0
const CORPSE_FADE_SECONDS: float = 3.0
const RUBBLE_SECONDS: float = 45.0
const RUBBLE_FADE_SECONDS: float = 6.0
const COLLAPSE_SECONDS: float = 1.15
const BUILDING_SCAN_SECONDS: float = 0.25
const AIR_Z: int = 9 # Above the y-sorted world, below the fog layer (10).
const GROUND_Z: int = -1 # Above terrain (-10), below every y-sorted entity.

const FLASH_SHADER: Shader = preload("res://assets/shaders/hit_flash.gdshader")
const CORPSE_SHADER: Shader = preload("res://assets/shaders/corpse.gdshader")
const COLLAPSE_SHADER: Shader = preload("res://assets/shaders/building_collapse.gdshader")

const INK := Color("293235")
const IVORY := Color("e8e5db")
const DUST := Color(0.95, 0.91, 0.80)
const DUST_DARK := Color(0.50, 0.45, 0.36)

static var _instance: BattleFX = null
static var _flash_material: ShaderMaterial = null
static var _corpse_material: ShaderMaterial = null

var _map: Node2D = null
var _rng := RandomNumberGenerator.new()
var _air: Node2D
var _ground: Node2D
var _dot: Texture2D
var _view: Rect2 = Rect2(-1e6, -1e6, 2e6, 2e6)
var _zoom: float = 1.0
var _clock: float = 0.0

# --- particles ---
var _p_pos := PackedVector2Array()
var _p_vel := PackedVector2Array()
var _p_age := PackedFloat32Array()
var _p_life := PackedFloat32Array()
var _p_size := PackedVector2Array() # x = start, y = end
var _p_phys := PackedVector2Array() # x = gravity, y = drag
var _p_c0 := PackedColorArray()
var _p_c1 := PackedColorArray()
var _p_hard := PackedByteArray()
var _p_next: int = 0
var _p_live: int = 0

# --- floating numbers ---
var _t_text: Array[String] = []
var _t_pos := PackedVector2Array()
var _t_age := PackedFloat32Array()
var _t_life := PackedFloat32Array()
var _t_amount := PackedFloat32Array()
var _t_px := PackedFloat32Array()
var _t_color := PackedColorArray()
var _t_host := PackedInt64Array()
var _t_bonus := PackedFloat32Array()
var _t_next: int = 0
var _t_live: int = 0

# --- cosmetic projectiles ---
var _s_from := PackedVector2Array()
var _s_to := PackedVector2Array()
var _s_age := PackedFloat32Array()
var _s_flight := PackedFloat32Array()
var _s_arc := PackedFloat32Array()
var _s_kind := PackedByteArray()
var _s_host := PackedInt64Array()
var _s_next: int = 0
var _s_live: int = 0

# --- stuck arrows ---
var _k_pos := PackedVector2Array()
var _k_angle := PackedFloat32Array()
var _k_age := PackedFloat32Array()
var _k_life := PackedFloat32Array()
var _k_host := PackedInt64Array()
var _k_next: int = 0
var _k_live: int = 0

# --- ground rings ---
var _r_pos := PackedVector2Array()
var _r_age := PackedFloat32Array()
var _r_life := PackedFloat32Array()
var _r_radius := PackedFloat32Array()
var _r_next: int = 0
var _r_live: int = 0

# --- corpses / rubble / collapse ---
var _corpses: Array[Sprite2D] = []
var _c_age := PackedFloat32Array()
var _c_fall := PackedFloat32Array()
var _c_side := PackedFloat32Array()
var _c_kind := PackedByteArray() # 0 free, 1 foot, 2 mounted, 3 wreck
var _c_scale := PackedVector2Array()
var _c_origin := PackedVector2Array()
var _c_next: int = 0
var _c_live: int = 0
var _rubble: Array[Rubble] = []
var _rubble_next: int = 0
var _collapses: Array[Dictionary] = []
var _pops: Array[Dictionary] = []

# --- building watch / shake ---
var _scan_remaining: float = 0.0
var _b_state: Dictionary = {}
var _b_progress: Dictionary = {}
var _trauma: float = 0.0
var _shake_clock: float = 0.0
var _shake_applied: bool = false
var _last_ticks: int = 0


## Flat debris left where a building stood. Drawn once; fades through modulate.
class Rubble extends Node2D:
	var half: Vector2 = Vector2(64, 32)
	var seed_value: int = 1
	var age: float = -1.0

	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var scorch := PackedVector2Array()
		for i: int in 20:
			var a: float = float(i) / 20.0 * TAU
			var wobble: float = 0.86 + rng.randf() * 0.2
			scorch.append(Vector2(cos(a) * half.x * 0.92 * wobble, sin(a) * half.y * 0.92 * wobble))
		draw_colored_polygon(scorch, Color(0.20, 0.18, 0.15, 0.34))
		var inner := PackedVector2Array()
		for point: Vector2 in scorch:
			inner.append(point * 0.62)
		draw_colored_polygon(inner, Color(0.16, 0.14, 0.12, 0.30))
		var count: int = clampi(int(half.x * 0.22), 8, 30)
		for i: int in count:
			var a: float = rng.randf() * TAU
			var d: float = sqrt(rng.randf()) * 0.78
			var p := Vector2(cos(a) * half.x * d, sin(a) * half.y * d)
			if rng.randf() < 0.42:
				# Charred timber.
				var dir := Vector2.RIGHT.rotated(rng.randf_range(-0.7, 0.7))
				var length: float = rng.randf_range(7.0, 16.0)
				draw_line(p - dir * length * 0.5 + Vector2(0, 1), p + dir * length * 0.5 + Vector2(0, 1), Color(0.13, 0.11, 0.10, 0.55), 4.0, true)
				draw_line(p - dir * length * 0.5, p + dir * length * 0.5, Color(0.42, 0.33, 0.25), 2.6, true)
				draw_line(p - dir * length * 0.4 + Vector2(0, -0.8), p + dir * length * 0.3 + Vector2(0, -0.8), Color(0.58, 0.47, 0.35), 0.9, true)
			else:
				# Broken masonry block.
				var w: float = rng.randf_range(3.5, 8.0)
				var h: float = w * rng.randf_range(0.5, 0.8)
				var skew: float = rng.randf_range(-1.5, 1.5)
				var block := PackedVector2Array([p + Vector2(-w, 0), p + Vector2(-w * 0.6 + skew, -h), p + Vector2(w * 0.7 + skew, -h * 0.9), p + Vector2(w, 0), p + Vector2(w * 0.5, h * 0.45), p + Vector2(-w * 0.6, h * 0.4)])
				var tone: float = rng.randf_range(0.0, 0.12)
				draw_colored_polygon(block, Color(0.50 + tone, 0.48 + tone, 0.44 + tone))
				draw_line(block[1], block[2], Color(0.72 + tone, 0.70 + tone, 0.64 + tone), 1.0, true)
				draw_line(block[3], block[4], Color(0.24, 0.22, 0.20, 0.7), 1.0, true)
				draw_line(block[4], block[5], Color(0.24, 0.22, 0.20, 0.7), 1.0, true)


func _init() -> void:
	name = "BattleFX"
	y_sort_enabled = true
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_rng.seed = 0x5eedf00d
	_p_pos.resize(MAX_PARTICLES); _p_vel.resize(MAX_PARTICLES); _p_age.resize(MAX_PARTICLES); _p_life.resize(MAX_PARTICLES)
	_p_size.resize(MAX_PARTICLES); _p_phys.resize(MAX_PARTICLES); _p_c0.resize(MAX_PARTICLES); _p_c1.resize(MAX_PARTICLES); _p_hard.resize(MAX_PARTICLES)
	_t_text.resize(MAX_TEXTS); _t_pos.resize(MAX_TEXTS); _t_age.resize(MAX_TEXTS); _t_life.resize(MAX_TEXTS); _t_amount.resize(MAX_TEXTS)
	_t_px.resize(MAX_TEXTS); _t_color.resize(MAX_TEXTS); _t_host.resize(MAX_TEXTS); _t_bonus.resize(MAX_TEXTS)
	_s_from.resize(MAX_SHOTS); _s_to.resize(MAX_SHOTS); _s_age.resize(MAX_SHOTS); _s_flight.resize(MAX_SHOTS); _s_arc.resize(MAX_SHOTS); _s_kind.resize(MAX_SHOTS); _s_host.resize(MAX_SHOTS)
	_k_pos.resize(MAX_STUCK); _k_angle.resize(MAX_STUCK); _k_age.resize(MAX_STUCK); _k_life.resize(MAX_STUCK); _k_host.resize(MAX_STUCK)
	_r_pos.resize(MAX_RINGS); _r_age.resize(MAX_RINGS); _r_life.resize(MAX_RINGS); _r_radius.resize(MAX_RINGS)
	_c_age.resize(MAX_CORPSES); _c_fall.resize(MAX_CORPSES); _c_side.resize(MAX_CORPSES); _c_kind.resize(MAX_CORPSES); _c_scale.resize(MAX_CORPSES); _c_origin.resize(MAX_CORPSES)
	for i: int in MAX_TEXTS:
		_t_text[i] = ""
	# Zero-filled lifetimes mean "free": age >= life.


func _enter_tree() -> void:
	_instance = self
	_map = get_parent() as Node2D


func _exit_tree() -> void:
	_release_camera()
	if _instance == self:
		_instance = null


func _ready() -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	gradient.add_point(0.55, Color(1, 1, 1, 0.55))
	var dot := GradientTexture2D.new()
	dot.gradient = gradient
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	dot.width = 32
	dot.height = 32
	_dot = dot
	_ground = Node2D.new()
	_ground.name = "Ground"
	_ground.z_index = GROUND_Z
	_ground.draw.connect(_timed_draw.bind(_draw_ground, &"fx.draw_ground"))
	add_child(_ground)
	_air = Node2D.new()
	_air.name = "Air"
	_air.z_index = AIR_Z
	_air.draw.connect(_timed_draw.bind(_draw_air, &"fx.draw_air"))
	add_child(_air)
	_last_ticks = Time.get_ticks_msec()


func _timed_draw(draw_layer: Callable, key: StringName) -> void:
	var _pp: int = Time.get_ticks_usec() if PerfProbe.on else 0
	draw_layer.call()
	if PerfProbe.on: PerfProbe.add(key, _pp)


# ---------------------------------------------------------------------------
# Static entry points (safe without a map)
# ---------------------------------------------------------------------------

static func get_fx() -> BattleFX:
	return _instance if is_instance_valid(_instance) and _instance.is_inside_tree() else null


static func flash_material() -> ShaderMaterial:
	if _flash_material == null:
		_flash_material = ShaderMaterial.new()
		_flash_material.shader = FLASH_SHADER
	return _flash_material


static func corpse_material() -> ShaderMaterial:
	if _corpse_material == null:
		_corpse_material = ShaderMaterial.new()
		_corpse_material.shader = CORPSE_SHADER
	return _corpse_material


## Reusable camera shake. `strength` 0..1; an optional world position attenuates
## distant events and ignores anything outside the current view.
static func shake(strength: float, world_position: Vector2 = Vector2.INF) -> void:
	var fx: BattleFX = get_fx()
	if fx != null:
		fx.add_shake(strength, world_position)


static func weapon_of(unit: UnitBase) -> int:
	if not is_instance_valid(unit):
		return Weapon.ARROW
	match unit.unit_type:
		UnitData.UnitType.SIEGE:
			return Weapon.STONE
		UnitData.UnitType.ARCHER:
			return Weapon.ARROW
		UnitData.UnitType.CAVALRY, UnitData.UnitType.SCOUT:
			return Weapon.HOOF
		UnitData.UnitType.VILLAGER:
			return Weapon.TOOL
	return Weapon.ARROW if unit.is_ranged else Weapon.BLADE


## A unit lost HP (any source, including replicas). Number only; the unit's own
## puppet handles flash and flinch.
static func unit_damaged(unit: UnitBase, hp_loss: float) -> void:
	var fx: BattleFX = get_fx()
	if fx == null or hp_loss <= 0.0 or not fx.can_show(unit):
		return
	var color: Color = Color("ff9d85") if unit.player_owner == 0 else IVORY
	fx._number(unit.get_instance_id(), unit.global_position + Vector2(0.0, unit.get_health_bar_y() - 4.0), hp_loss, color, 13.0)


## A resolved unit-vs-unit hit: weapon-class impact, flinch direction and the
## larger coloured number for a counter bonus.
static func unit_struck(attacker: UnitBase, defender: UnitBase, counter_bonus: float) -> void:
	var fx: BattleFX = get_fx()
	if fx == null or not is_instance_valid(defender) or not fx.can_show(defender):
		return
	var from: Vector2 = attacker.global_position if is_instance_valid(attacker) else defender.global_position + Vector2(0, -30)
	var direction: Vector2 = (defender.global_position - from).normalized()
	defender.present_recoil(direction)
	var chest: Vector2 = defender.global_position + Vector2(0.0, defender.get_health_bar_y() * 0.45) - direction * 4.0
	var weapon: int = weapon_of(attacker)
	fx.impact(chest, direction, weapon)
	if weapon == Weapon.STONE:
		fx.ground_burst(defender.global_position, 1.0)
		fx.add_shake(0.42, defender.global_position)
	if counter_bonus > 1.0:
		fx._mark_counter(defender.get_instance_id(), counter_bonus)


## Round 2 C: a rested Chevalier's Charge landed on a unit or a building. Call
## after the ordinary hit presentation: the figure grows, the ground jumps and
## the camera takes a small knock.
static func charge_struck(attacker: UnitBase, target: Node2D) -> void:
	var fx: BattleFX = get_fx()
	if fx == null or not is_instance_valid(target) or not is_instance_valid(attacker) or not fx.can_show(target):
		return
	var direction: Vector2 = (target.global_position - attacker.global_position).normalized()
	var contact: Vector2 = target.global_position
	if target is UnitBase:
		contact += Vector2(0.0, (target as UnitBase).get_health_bar_y() * 0.45)
	elif target is BuildingBase:
		contact = fx.facade_point(target as BuildingBase, attacker.global_position)
	fx.impact(contact, direction, Weapon.BLADE)
	fx.impact(contact, direction, Weapon.HOOF)
	fx.ground_burst(target.global_position if target is UnitBase else contact + Vector2(0.0, 10.0), 0.7)
	fx.add_shake(0.3, contact)
	fx._mark_heavy(target.get_instance_id())


## Round 2 C: an Outrider pillaged gold. A small golden "+n" rises from the
## victim (hits on one building within a moment merge into one figure).
static func loot_gained(raider: UnitBase, victim: Node2D, gold: int) -> void:
	var fx: BattleFX = get_fx()
	if fx == null or gold <= 0 or not is_instance_valid(raider) or not fx.can_show(raider):
		return
	var from: Vector2 = raider.global_position + Vector2(0.0, raider.get_health_bar_y() - 2.0)
	if is_instance_valid(victim) and victim is BuildingBase:
		from = fx.facade_point(victim as BuildingBase, raider.global_position) + Vector2(0.0, -18.0)
	# A negative host keeps gains apart from damage figures on the same target.
	fx._number(-raider.get_instance_id(), from, float(gold), Color("ffd45e"), 15.0, 0.5, true)
	if not GameManager.reduced_motion:
		fx._emit(from + Vector2(0.0, 6.0), 3, Color(1.0, 0.86, 0.36), Color(1.0, 0.74, 0.2, 0.0), 30.0, 70.0, -PI * 0.5, 0.8, 260.0, 0.4, 2.6, 1.4, true)


## A tower/Town Center arrow landed on a unit.
static func unit_struck_by_arrow(defender: UnitBase, from: Vector2) -> void:
	var fx: BattleFX = get_fx()
	if fx == null or not is_instance_valid(defender) or not fx.can_show(defender):
		return
	var direction: Vector2 = (defender.global_position - from).normalized()
	defender.present_recoil(direction)
	fx.impact(defender.global_position + Vector2(0.0, defender.get_health_bar_y() * 0.45), direction, Weapon.ARROW)


## A local unit's attack on a building resolved (damage is already applied).
## Ranged attackers get a cosmetic projectile; melee gets a contact burst.
static func building_struck(attacker: UnitBase, building: BuildingBase) -> void:
	var fx: BattleFX = get_fx()
	if fx == null or not is_instance_valid(attacker) or not is_instance_valid(building):
		return
	if not fx.can_show(building) and not fx.can_show(attacker):
		return
	var weapon: int = weapon_of(attacker)
	var contact: Vector2 = fx.facade_point(building, attacker.global_position)
	if attacker.is_ranged:
		fx.launch(attacker.get_projectile_origin(contact), contact, weapon, building.get_instance_id(), attacker.unit_type)
	else:
		var direction: Vector2 = (contact - attacker.global_position).normalized()
		fx.impact(contact, direction, weapon)
		fx._chips(contact, direction, 3)


## A tower's instant shot at a building: cosmetic arrow only.
static func tower_shot(tower: BuildingBase, target: Node2D) -> void:
	var fx: BattleFX = get_fx()
	if fx == null or not is_instance_valid(tower) or not is_instance_valid(target) or not fx.can_show(target):
		return
	var from: Vector2 = tower.call("_get_defensive_fire_position")
	var to: Vector2 = fx.facade_point(target as BuildingBase, from) if target is BuildingBase else target.global_position + Vector2(0, -20)
	fx.launch(from, to, Weapon.ARROW, target.get_instance_id(), -1)


## A building lost HP (local or replica).
static func building_damaged(building: BuildingBase, hp_loss: float) -> void:
	var fx: BattleFX = get_fx()
	if fx == null or hp_loss <= 0.0 or not is_instance_valid(building) or not fx.can_show(building):
		return
	var top: Vector2 = building.get_visual_bounds(false).position
	var center_x: float = building.get_visual_bounds(false).get_center().x
	var color: Color = Color("ff9d85") if building.player_owner == 0 else IVORY
	fx._number(building.get_instance_id(), Vector2(center_x, top.y - 12.0), hp_loss, color, 13.0, 0.45)


## An in-flight sim arrow lost its target: let the shaft finish into the ground.
static func stray_arrow(from: Vector2, to: Vector2, progress: float, flight: float) -> void:
	var fx: BattleFX = get_fx()
	if fx == null or not fx.on_screen(to):
		return
	var index: int = fx.launch(from, to + Vector2(0, 16), Weapon.ARROW, 0, -1)
	if index >= 0:
		fx._s_flight[index] = maxf(0.08, flight)
		fx._s_age[index] = clampf(progress, 0.0, 0.95) * fx._s_flight[index]


## A sim arrow reached its unit: leave the shaft in the target for a moment.
static func arrow_arrived(target: Node2D, heading: Vector2, stone: bool) -> void:
	var fx: BattleFX = get_fx()
	if fx == null or not is_instance_valid(target) or not fx.can_show(target):
		return
	if stone:
		return
	if fx._rng.randf() < 0.6:
		fx._stick(target.get_instance_id(), Vector2(fx._rng.randf_range(-4.0, 4.0), fx._rng.randf_range(-24.0, -12.0)), heading.angle(), 2.6)
	else:
		fx._stick(0, target.global_position + Vector2(fx._rng.randf_range(-12.0, 12.0), fx._rng.randf_range(-2.0, 7.0)) + heading * 8.0, clampf(heading.angle(), 0.5, 2.6) if heading.y > 0.0 else (0.9 if heading.x > 0.0 else 2.2), 4.5)


## A replica's ranged release (clients receive no projectile entities).
static func replica_shot(shooter: UnitBase, direction: Vector2) -> void:
	var fx: BattleFX = get_fx()
	if fx == null or not is_instance_valid(shooter) or not fx.can_show(shooter):
		return
	var aim: Vector2 = direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	var best: Node2D = null
	var best_score: float = 0.35
	var reach: float = shooter.attack_range + 40.0
	for group: String in ["units", "buildings"]:
		for node: Node in shooter.get_tree().get_nodes_in_group(group):
			var other := node as Node2D
			if other == null or other == shooter or not other.visible or int(other.get("player_owner")) == shooter.player_owner:
				continue
			var offset: Vector2 = other.global_position - shooter.global_position
			var distance: float = offset.length()
			if distance > reach + (48.0 if group == "buildings" else 0.0) or distance < 1.0:
				continue
			var score: float = offset.dot(aim) / distance
			if score > best_score:
				best_score = score
				best = other
	var to: Vector2 = shooter.global_position + aim * shooter.attack_range
	var host: int = 0
	if best is BuildingBase:
		to = fx.facade_point(best as BuildingBase, shooter.global_position)
		host = best.get_instance_id()
	elif best != null:
		to = best.global_position + Vector2(0, -20)
		host = best.get_instance_id()
	fx.launch(shooter.get_projectile_origin(to), to, weapon_of(shooter), host, shooter.unit_type)


## Death with weight. Takes over the unit's artwork; the unit node keeps its
## existing lifetime and is only hidden.
static func unit_death(unit: UnitBase, force: bool = false) -> void:
	var fx: BattleFX = get_fx()
	if fx == null or not is_instance_valid(unit) or unit._sprite == null or unit._sprite.texture == null:
		return
	if not force and not fx.can_show(unit):
		return
	fx._spawn_corpse(unit)
	unit._sprite.visible = false
	if unit._action_presentation != null:
		unit._action_presentation.visible = false


## A building was destroyed: collapse a copy of its artwork and leave rubble.
static func building_collapse(building: BuildingBase) -> void:
	var fx: BattleFX = get_fx()
	if fx == null or not is_instance_valid(building) or building._sprite == null or building._sprite.texture == null:
		return
	if not fx.can_show(building):
		return
	fx._begin_collapse(building)


## network_match removed a replica. Decide whether that was a visible death.
static func replica_removed(node: Node2D) -> void:
	var fx: BattleFX = get_fx()
	if fx == null or not is_instance_valid(node) or not node.is_visible_in_tree():
		return
	if node is UnitBase:
		var unit := node as UnitBase
		# Own units only leave a snapshot by dying. A rival may also have walked
		# out of sight, so require a recently observed wound as well.
		if unit.player_owner == 0 or (unit.hp < unit.max_hp and unit.get_seconds_since_hit() < 3.5):
			unit_death(unit)
	elif node is BuildingBase:
		var building := node as BuildingBase
		if building.state != BuildingBase.State.PLACING and float(building.hp) < float(building.max_hp) * 0.5:
			building_collapse(building)


## Pooled replacements for the old one-shot CPUParticles2D helpers. Each
## returns false when no map instance exists so VFX can keep its fallback.
static func puff(kind: String, position: Vector2, color: Color = Color.WHITE) -> bool:
	var fx: BattleFX = get_fx()
	if fx == null:
		return false
	if GameManager.reduced_motion or not fx.on_screen(position):
		return true
	match kind:
		"hit":
			fx._emit(position, 4, color, Color(color, 0.0), 22.0, 60.0, -PI * 0.5, PI, 160.0, 0.22, 2.2, 1.0, true)
		"death":
			fx.dust(position, 5, 0.9)
		"gather":
			fx._emit(position + Vector2(0, -10), 5, color, Color(color, 0.0), 26.0, 62.0, -PI * 0.5, 1.1, 190.0, 0.42, 3.0, 1.6, true)
		"construction":
			fx.dust(position, 4, 0.8)
		"complete":
			fx._emit(position + Vector2(0, -20), 16, Color(1.0, 0.93, 0.62, 0.95), Color(1.0, 0.78, 0.32, 0.0), 40.0, 110.0, -PI * 0.5, PI, 90.0, 0.6, 3.4, 1.2, true)
	return true


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

func on_screen(world_position: Vector2, margin: float = 40.0) -> bool:
	return _view.grow(margin).has_point(world_position)


func can_show(node: Node2D) -> bool:
	if not is_instance_valid(node) or not node.is_inside_tree() or not node.visible:
		return false
	if not on_screen(node.global_position, 140.0):
		return false
	if _map != null and _map.has_method("is_entity_visible_to_player"):
		return bool(_map.call("is_entity_visible_to_player", node, 0))
	return true


## A believable contact point on a building's painted wall facing `from`.
func facade_point(building: BuildingBase, from: Vector2) -> Vector2:
	var bounds: Rect2 = building.get_visual_bounds(false)
	var inner := Rect2(bounds.position + bounds.size * Vector2(0.24, 0.40), bounds.size * Vector2(0.52, 0.38))
	var aim: Vector2 = from + Vector2(0.0, -14.0)
	var point := Vector2(clampf(aim.x, inner.position.x, inner.end.x), clampf(aim.y, inner.position.y, inner.end.y))
	return point + Vector2(_rng.randf_range(-5.0, 5.0), _rng.randf_range(-5.0, 5.0))


# ---------------------------------------------------------------------------
# Frame update
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	var _pp: int = Time.get_ticks_usec() if PerfProbe.on else 0
	_process_fx(delta)
	if PerfProbe.on: PerfProbe.add(&"fx.process", _pp)


func _process_fx(delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	var real_delta: float = clampf(float(now - _last_ticks) / 1000.0, 0.0, 0.1)
	_last_ticks = now
	_clock += delta
	var canvas: Transform2D = get_canvas_transform()
	_zoom = maxf(0.05, canvas.get_scale().x)
	_view = canvas.affine_inverse() * get_viewport_rect()
	_update_shake(real_delta)
	var air_dirty: bool = false
	var ground_dirty: bool = false
	if _p_live > 0:
		_step_particles(delta)
		air_dirty = true
	if _t_live > 0:
		_step_pool(_t_age, _t_life, delta)
		_t_live = _count_live(_t_age, _t_life)
		air_dirty = true
	if _s_live > 0:
		_step_shots(delta)
		air_dirty = true
		ground_dirty = true
	if _k_live > 0:
		_step_pool(_k_age, _k_life, delta)
		_k_live = _count_live(_k_age, _k_life)
		air_dirty = true
	if _r_live > 0:
		_step_pool(_r_age, _r_life, delta)
		_r_live = _count_live(_r_age, _r_life)
		ground_dirty = true
	if _c_live > 0:
		_step_corpses(delta)
	if not _collapses.is_empty():
		_step_collapses(delta)
	if not _pops.is_empty():
		_step_pops(delta)
	_step_rubble(delta)
	_scan_remaining -= delta
	if _scan_remaining <= 0.0:
		_scan_remaining = BUILDING_SCAN_SECONDS
		_scan_buildings()
	if air_dirty or _air_was_dirty:
		_air.queue_redraw()
	if ground_dirty or _ground_was_dirty:
		_ground.queue_redraw()
	_air_was_dirty = air_dirty
	_ground_was_dirty = ground_dirty

var _air_was_dirty: bool = false
var _ground_was_dirty: bool = false


func _step_pool(age: PackedFloat32Array, life: PackedFloat32Array, delta: float) -> void:
	for i: int in age.size():
		if age[i] < life[i]:
			age[i] += delta


func _count_live(age: PackedFloat32Array, life: PackedFloat32Array) -> int:
	var live: int = 0
	for i: int in age.size():
		if age[i] < life[i]:
			live += 1
	return live


# ---------------------------------------------------------------------------
# Particles
# ---------------------------------------------------------------------------

func _emit(position: Vector2, count: int, c0: Color, c1: Color, speed_min: float, speed_max: float, angle: float, spread: float, gravity: float, life: float, size0: float, size1: float, hard: bool, drag: float = 0.0) -> void:
	for n: int in count:
		var i: int = _p_next
		_p_next = (_p_next + 1) % MAX_PARTICLES
		if _p_age[i] >= _p_life[i]:
			_p_live += 1
		var direction: float = angle + _rng.randf_range(-spread, spread)
		_p_pos[i] = position + Vector2(_rng.randf_range(-2.0, 2.0), _rng.randf_range(-2.0, 2.0))
		_p_vel[i] = Vector2(cos(direction), sin(direction)) * _rng.randf_range(speed_min, speed_max)
		_p_age[i] = 0.0
		_p_life[i] = life * _rng.randf_range(0.75, 1.15)
		_p_size[i] = Vector2(size0, size1) * _rng.randf_range(0.8, 1.25)
		_p_phys[i] = Vector2(gravity, drag)
		_p_c0[i] = c0
		_p_c1[i] = c1
		_p_hard[i] = 1 if hard else 0


func _step_particles(delta: float) -> void:
	var live: int = 0
	for i: int in MAX_PARTICLES:
		if _p_age[i] >= _p_life[i]:
			continue
		_p_age[i] += delta
		var velocity: Vector2 = _p_vel[i]
		velocity.y += _p_phys[i].x * delta
		velocity *= maxf(0.0, 1.0 - _p_phys[i].y * delta)
		_p_vel[i] = velocity
		_p_pos[i] += velocity * delta
		if _p_age[i] < _p_life[i]:
			live += 1
	_p_live = live


## Soft low dust that spreads along the ground and thins out.
func dust(position: Vector2, count: int, strength: float = 1.0, alpha: float = 0.62) -> void:
	if GameManager.reduced_motion or not on_screen(position):
		return
	for n: int in count:
		var i: int = _p_next
		_p_next = (_p_next + 1) % MAX_PARTICLES
		if _p_age[i] >= _p_life[i]:
			_p_live += 1
		var side: float = _rng.randf_range(-1.0, 1.0)
		_p_pos[i] = position + Vector2(side * 5.0 * strength, _rng.randf_range(-2.0, 2.0))
		_p_vel[i] = Vector2(side * 30.0, _rng.randf_range(-22.0, -6.0)) * strength
		_p_age[i] = 0.0
		_p_life[i] = _rng.randf_range(0.45, 0.8)
		_p_size[i] = Vector2(6.0, 15.0) * strength * _rng.randf_range(0.8, 1.2)
		_p_phys[i] = Vector2(-8.0, 2.6)
		_p_c0[i] = Color(DUST, alpha)
		_p_c1[i] = Color(DUST, 0.0)
		_p_hard[i] = 2 # Soft, with a shaded underside so it reads on pale ground.


func smoke(position: Vector2, dark: float, size: float = 1.0) -> void:
	var tone: float = lerpf(0.56, 0.20, dark)
	_emit(position, 1, Color(tone, tone, tone * 0.98, lerpf(0.34, 0.6, dark)), Color(tone * 0.9, tone * 0.9, tone * 0.9, 0.0), 10.0, 20.0, -PI * 0.5 + 0.25, 0.3, -6.0, 1.7, 8.0 * size, 22.0 * size, false, 0.5)


func fire(position: Vector2, size: float = 1.0) -> void:
	_emit(position, 2, Color(1.0, 0.78, 0.30, 0.9), Color(0.92, 0.28, 0.08, 0.0), 14.0, 30.0, -PI * 0.5, 0.35, -30.0, 0.5, 9.0 * size, 3.0 * size, false, 0.6)
	if _rng.randf() < 0.5:
		_emit(position, 1, Color(1.0, 0.86, 0.45), Color(1.0, 0.5, 0.2, 0.0), 30.0, 60.0, -PI * 0.5, 0.6, -20.0, 0.7, 1.8, 1.0, true)


func impact(position: Vector2, direction: Vector2, weapon: int) -> void:
	if GameManager.reduced_motion or not on_screen(position):
		return
	var back: float = (-direction).angle()
	match weapon:
		Weapon.BLADE:
			_emit(position, 5, Color(1.0, 0.96, 0.78), Color(1.0, 0.72, 0.30, 0.0), 50.0, 120.0, back, 0.9, 220.0, 0.24, 2.4, 1.0, true)
			_emit(position, 1, Color(1.0, 1.0, 0.92, 0.85), Color(1.0, 0.95, 0.7, 0.0), 0.0, 4.0, 0.0, PI, 0.0, 0.12, 9.0, 16.0, false)
		Weapon.HOOF:
			_emit(position, 4, Color(1.0, 0.94, 0.74), Color(1.0, 0.7, 0.3, 0.0), 60.0, 130.0, back, 1.0, 220.0, 0.24, 2.4, 1.0, true)
			dust(position + Vector2(0, 14), 2, 0.8)
		Weapon.ARROW:
			_emit(position, 3, Color(0.86, 0.74, 0.50), Color(0.70, 0.58, 0.38, 0.0), 30.0, 80.0, back, 0.8, 240.0, 0.26, 2.2, 1.2, true)
			_emit(position, 1, Color(1.0, 0.98, 0.9, 0.7), Color(1.0, 0.95, 0.8, 0.0), 0.0, 3.0, 0.0, PI, 0.0, 0.10, 7.0, 12.0, false)
		Weapon.STONE:
			_emit(position, 7, Color(0.66, 0.63, 0.57), Color(0.5, 0.47, 0.42, 0.0), 50.0, 150.0, -PI * 0.5, 1.3, 320.0, 0.5, 3.4, 1.8, true)
			dust(position + Vector2(0, 10), 5, 1.3)
		_:
			_emit(position, 3, Color(DUST, 0.9), Color(DUST, 0.0), 30.0, 70.0, back, 1.0, 200.0, 0.22, 2.2, 1.0, true)
			dust(position + Vector2(0, 12), 1, 0.6)


func _chips(position: Vector2, direction: Vector2, count: int) -> void:
	if GameManager.reduced_motion or not on_screen(position):
		return
	_emit(position, count, Color(0.72, 0.60, 0.44), Color(0.5, 0.42, 0.32, 0.0), 30.0, 90.0, (-direction).angle() - 0.4, 0.9, 300.0, 0.4, 3.0, 1.6, true)


## Heavy impact on the ground: dust ring, low cloud and a few thrown stones.
func ground_burst(position: Vector2, strength: float) -> void:
	if GameManager.reduced_motion or not on_screen(position, 120.0):
		return
	dust(position, int(6 * strength) + 2, 1.2 * strength)
	_emit(position, int(5 * strength), Color(0.62, 0.58, 0.50), Color(0.45, 0.42, 0.36, 0.0), 60.0, 150.0, -PI * 0.5, 1.2, 340.0, 0.5, 3.2, 1.6, true)
	_ring(position, 26.0 * strength, 0.45)


func _ring(position: Vector2, radius: float, life: float) -> void:
	var i: int = _r_next
	_r_next = (_r_next + 1) % MAX_RINGS
	_r_pos[i] = position
	_r_age[i] = 0.0
	_r_life[i] = life
	_r_radius[i] = radius
	_r_live = maxi(1, _r_live + 1)


# ---------------------------------------------------------------------------
# Floating numbers
# ---------------------------------------------------------------------------

func _number(host: int, position: Vector2, amount: float, color: Color, px: float, merge_window: float = 0.3, gain: bool = false) -> void:
	if not on_screen(position, 10.0):
		return
	# Rapid hits on one target merge into one rising figure instead of a stack.
	for i: int in MAX_TEXTS:
		if _t_host[i] == host and _t_age[i] < minf(merge_window, _t_life[i]):
			_t_amount[i] += amount
			_t_text[i] = _format_number(_t_amount[i], _t_bonus[i])
			_t_age[i] = minf(_t_age[i], 0.06)
			return
	# Dense melees: a few figures per patch of ground say "a fight is going
	# badly here" better than forty overlapping ones.
	var crowd: int = 0
	for i: int in MAX_TEXTS:
		if _t_age[i] < _t_life[i] and _t_pos[i].distance_squared_to(position) < 3600.0:
			crowd += 1
	if crowd >= 3:
		return
	var slot: int = -1
	var oldest: float = -1.0
	for n: int in MAX_TEXTS:
		var i: int = (_t_next + n) % MAX_TEXTS
		if _t_age[i] >= _t_life[i]:
			slot = i
			break
		if _t_age[i] > oldest:
			oldest = _t_age[i]
			slot = i
	_t_next = (slot + 1) % MAX_TEXTS
	_t_host[slot] = host
	_t_amount[slot] = amount
	_t_bonus[slot] = -1.0 if gain else 1.0  # Negative marks a gain ("+n").
	_t_text[slot] = _format_number(amount, _t_bonus[slot])
	_t_pos[slot] = position + Vector2(_rng.randf_range(-7.0, 7.0), 0.0)
	_t_age[slot] = 0.0
	_t_life[slot] = 0.85
	_t_px[slot] = px
	_t_color[slot] = color
	_t_live = maxi(1, _t_live + 1)


func _format_number(amount: float, bonus: float) -> String:
	var value: int = maxi(1, roundi(amount))
	if bonus < 0.0:
		return "+%d" % value
	if bonus > 1.0:
		return ("-%d ×%d" % [value, roundi(bonus)]) if is_equal_approx(bonus, roundf(bonus)) else ("-%d ×%.1f" % [value, bonus])
	return "-%d" % value


func _mark_heavy(host: int) -> void:
	## The freshest figure on `host` becomes a big one (a Charge landed).
	for i: int in MAX_TEXTS:
		if _t_host[i] == host and _t_age[i] < minf(0.3, _t_life[i]):
			_t_px[i] = maxf(_t_px[i], 21.0)
			if _t_bonus[i] <= 1.0:
				_t_color[i] = Color("fff0c4")
			_t_life[i] = maxf(_t_life[i], 1.1)
			_t_age[i] = 0.0
			return


func _mark_counter(host: int, bonus: float) -> void:
	for i: int in MAX_TEXTS:
		if _t_host[i] == host and _t_age[i] < minf(0.3, _t_life[i]):
			_t_bonus[i] = bonus
			_t_text[i] = _format_number(_t_amount[i], bonus)
			_t_px[i] = 17.0
			_t_color[i] = Color("ffd166")
			_t_life[i] = 1.05
			return


# ---------------------------------------------------------------------------
# Cosmetic projectiles and stuck arrows
# ---------------------------------------------------------------------------

func launch(from: Vector2, to: Vector2, weapon: int, host: int, unit_type: int) -> int:
	if not on_screen(from, 80.0) and not on_screen(to, 80.0):
		return -1
	var i: int = _s_next
	_s_next = (_s_next + 1) % MAX_SHOTS
	var distance: float = from.distance_to(to)
	var stone: bool = weapon == Weapon.STONE
	_s_from[i] = from
	_s_to[i] = to
	_s_age[i] = 0.0
	if stone:
		_s_flight[i] = clampf(distance / 240.0, 0.38, 0.75)
		_s_arc[i] = clampf(distance * 0.34, 26.0, 78.0)
	else:
		var speed: float = float(UnitData.UNITS.get(unit_type, {}).get("projectile_speed", 300.0))
		_s_flight[i] = clampf(distance / speed, 0.14, 0.42)
		_s_arc[i] = arrow_arc(distance)
	_s_kind[i] = 1 if stone else 0
	_s_host[i] = host
	_s_live = maxi(1, _s_live + 1)
	return i


static func arrow_arc(distance: float) -> float:
	return clampf(distance * 0.20, 9.0, 40.0)


func _step_shots(delta: float) -> void:
	var live: int = 0
	for i: int in MAX_SHOTS:
		if _s_age[i] >= _s_flight[i]:
			continue
		_s_age[i] += delta
		if _s_age[i] < _s_flight[i]:
			live += 1
			continue
		var to: Vector2 = _s_to[i]
		var heading: Vector2 = shot_heading(_s_from[i], to, _s_arc[i], 1.0)
		var host: Object = instance_from_id(_s_host[i]) if _s_host[i] != 0 else null
		if _s_kind[i] == 1:
			var at_building: bool = is_instance_valid(host) and host is BuildingBase
			if at_building:
				impact(to, heading, Weapon.STONE)
				_chips(to, heading, 4)
				ground_burst(Vector2(to.x, (host as BuildingBase).get_visual_bounds(false).end.y - 6.0), 0.8)
				add_shake(0.5, to)
			else:
				ground_burst(to, 1.0)
				add_shake(0.4, to)
		elif is_instance_valid(host) and host is BuildingBase:
			impact(to, heading, Weapon.ARROW)
			_stick(0, to, heading.angle(), 4.0)
		elif is_instance_valid(host) and host is Node2D and (host as Node2D).is_inside_tree():
			_stick(_s_host[i], to - ((host as UnitBase).get_visual_position() if host is UnitBase else (host as Node2D).global_position), heading.angle(), 2.4)
		else:
			_stick(0, to, clampf(heading.angle(), 0.6, 2.5) if heading.y > 0.0 else 1.0, 4.5)
			dust(to, 1, 0.5)
	_s_live = live


static func shot_point(from: Vector2, to: Vector2, arc: float, t: float) -> Vector2:
	return from.lerp(to, t) + Vector2(0.0, -sin(t * PI) * arc)


static func shot_heading(from: Vector2, to: Vector2, arc: float, t: float) -> Vector2:
	var velocity: Vector2 = (to - from) + Vector2(0.0, -cos(t * PI) * PI * arc)
	return velocity.normalized() if velocity.length_squared() > 0.0001 else Vector2.RIGHT


func _stick(host: int, position: Vector2, angle: float, life: float) -> void:
	var i: int = _k_next
	_k_next = (_k_next + 1) % MAX_STUCK
	_k_host[i] = host
	_k_pos[i] = position
	_k_angle[i] = angle
	_k_age[i] = 0.0
	_k_life[i] = life
	_k_live = maxi(1, _k_live + 1)


## Shared arrow artwork: used by sim projectiles and cosmetic ones alike.
static func draw_arrow(canvas: CanvasItem, position: Vector2, heading: Vector2, trail: float = 1.0, warm: bool = false) -> void:
	var normal := Vector2(-heading.y, heading.x)
	var shaft: Color = Color(0.93, 0.82, 0.52) if warm else Color(0.86, 0.76, 0.50)
	if trail > 0.0:
		canvas.draw_line(position - heading * 30.0, position - heading * 9.0, Color(1.0, 0.97, 0.86, 0.16 * trail), 2.2, true)
		canvas.draw_line(position - heading * 19.0, position - heading * 9.0, Color(1.0, 0.97, 0.86, 0.30 * trail), 1.4, true)
	canvas.draw_line(position - heading * 10.0, position + heading * 4.0, Color(0.16, 0.14, 0.12, 0.85), 3.4, true)
	canvas.draw_line(position - heading * 10.0, position + heading * 4.0, shaft, 1.8, true)
	canvas.draw_colored_polygon(PackedVector2Array([position + heading * 8.0, position + heading * 2.5 + normal * 2.6, position + heading * 2.5 - normal * 2.6]), Color(0.95, 0.95, 0.88))
	canvas.draw_line(position - heading * 10.0 + normal * 2.4, position - heading * 7.0, Color(0.93, 0.90, 0.82), 1.2, true)
	canvas.draw_line(position - heading * 10.0 - normal * 2.4, position - heading * 7.0, Color(0.93, 0.90, 0.82), 1.2, true)


static func draw_stone(canvas: CanvasItem, position: Vector2, spin: float) -> void:
	var points := PackedVector2Array()
	for i: int in 7:
		var a: float = float(i) / 7.0 * TAU + spin
		points.append(position + Vector2(cos(a), sin(a)) * (5.6 if i % 2 == 0 else 4.6))
	var shadow := PackedVector2Array()
	for point: Vector2 in points:
		shadow.append(position + (point - position) * 1.25)
	canvas.draw_colored_polygon(shadow, Color(0.14, 0.13, 0.12, 0.9))
	canvas.draw_colored_polygon(points, Color(0.60, 0.58, 0.53))
	canvas.draw_circle(position + Vector2(-1.4, -1.6), 2.0, Color(0.80, 0.78, 0.72))


static func draw_shadow(canvas: CanvasItem, position: Vector2, radius: float, alpha: float) -> void:
	var points := PackedVector2Array()
	for i: int in 10:
		var a: float = float(i) / 10.0 * TAU
		points.append(position + Vector2(cos(a) * radius, sin(a) * radius * 0.5))
	canvas.draw_colored_polygon(points, Color(0.06, 0.09, 0.09, alpha))


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw_ground() -> void:
	for i: int in MAX_RINGS:
		if _r_age[i] >= _r_life[i]:
			continue
		var t: float = _r_age[i] / _r_life[i]
		var radius: float = _r_radius[i] * (0.35 + 0.65 * (1.0 - (1.0 - t) * (1.0 - t)))
		var points := PackedVector2Array()
		for n: int in 25:
			var a: float = float(n) / 24.0 * TAU
			points.append(_r_pos[i] + Vector2(cos(a) * radius, sin(a) * radius * 0.5))
		_ground.draw_polyline(points, Color(DUST_DARK, 0.30 * (1.0 - t)), lerpf(6.0, 2.0, t), true)
		_ground.draw_polyline(points, Color(DUST, 0.60 * (1.0 - t)), lerpf(3.0, 1.0, t), true)
	for i: int in MAX_SHOTS:
		if _s_age[i] >= _s_flight[i]:
			continue
		var t: float = _s_age[i] / _s_flight[i]
		draw_shadow(_ground, _s_from[i].lerp(_s_to[i], t) + Vector2(0, 18.0 * (1.0 - t)), 5.0 if _s_kind[i] == 1 else 3.0, 0.16)


func _draw_air() -> void:
	for i: int in MAX_STUCK:
		if _k_age[i] >= _k_life[i]:
			continue
		var position: Vector2 = _k_pos[i]
		if _k_host[i] != 0:
			var host: Object = instance_from_id(_k_host[i])
			if not is_instance_valid(host) or not host is Node2D or not (host as Node2D).is_visible_in_tree() or (host is UnitBase and (host as UnitBase).current_state == UnitBase.State.DEAD):
				_k_age[i] = _k_life[i]
				continue
			position += (host as UnitBase).get_visual_position() if host is UnitBase else (host as Node2D).global_position
		var fade: float = clampf((_k_life[i] - _k_age[i]) / 0.6, 0.0, 1.0)
		var wobble: float = sin(_k_age[i] * 38.0) * 0.16 * maxf(0.0, 1.0 - _k_age[i] / 0.35)
		var heading := Vector2.RIGHT.rotated(_k_angle[i] + wobble)
		# Only the tail half shows: the head is buried in the target or soil.
		_air.draw_line(position - heading * 11.0, position, Color(0.16, 0.14, 0.12, 0.8 * fade), 3.0, true)
		_air.draw_line(position - heading * 11.0, position, Color(0.86, 0.76, 0.50, fade), 1.6, true)
		var normal := Vector2(-heading.y, heading.x)
		_air.draw_line(position - heading * 11.0 + normal * 2.4, position - heading * 8.0, Color(0.93, 0.90, 0.82, fade), 1.2, true)
		_air.draw_line(position - heading * 11.0 - normal * 2.4, position - heading * 8.0, Color(0.93, 0.90, 0.82, fade), 1.2, true)
	for i: int in MAX_PARTICLES:
		if _p_age[i] >= _p_life[i]:
			continue
		var t: float = _p_age[i] / _p_life[i]
		var size: float = lerpf(_p_size[i].x, _p_size[i].y, t)
		var color: Color = _p_c0[i].lerp(_p_c1[i], t * t if _p_hard[i] == 1 else t)
		if _p_hard[i] == 1:
			_air.draw_rect(Rect2(_p_pos[i] - Vector2(size, size) * 0.5, Vector2(size, size)), color)
		else:
			if _p_hard[i] == 2:
				var under: float = size * 1.2
				_air.draw_texture_rect(_dot, Rect2(_p_pos[i] - Vector2(under, under) * 0.5 + Vector2(0.0, size * 0.14), Vector2(under, under)), false, Color(DUST_DARK, color.a * 0.55))
			_air.draw_texture_rect(_dot, Rect2(_p_pos[i] - Vector2(size, size) * 0.5, Vector2(size, size)), false, color)
	for i: int in MAX_SHOTS:
		if _s_age[i] >= _s_flight[i]:
			continue
		var t: float = _s_age[i] / _s_flight[i]
		var position: Vector2 = shot_point(_s_from[i], _s_to[i], _s_arc[i], t)
		if _s_kind[i] == 1:
			draw_stone(_air, position, _s_age[i] * 9.0)
		else:
			draw_arrow(_air, position, shot_heading(_s_from[i], _s_to[i], _s_arc[i], t), minf(1.0, t * 4.0))
	if _t_live <= 0:
		return
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	var inverse: float = 1.0 / _zoom
	for i: int in MAX_TEXTS:
		if _t_age[i] >= _t_life[i]:
			continue
		var t: float = _t_age[i] / _t_life[i]
		var rise: float = 0.0 if GameManager.reduced_motion else (1.0 - (1.0 - t) * (1.0 - t)) * 26.0
		var pop: float = 1.0 if GameManager.reduced_motion else 1.0 + 0.45 * maxf(0.0, 1.0 - _t_age[i] / 0.12)
		var alpha: float = clampf((1.0 - t) / 0.35, 0.0, 1.0)
		var px: int = int(round(_t_px[i]))
		var text: String = _t_text[i]
		var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		# Constant on-screen size at every zoom keeps figures legible on a phone.
		_air.draw_set_transform(_t_pos[i] + Vector2(0.0, -rise * inverse), 0.0, Vector2(inverse, inverse) * pop)
		_air.draw_string_outline(font, Vector2(-width * 0.5, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, 4, Color(0.05, 0.07, 0.08, 0.85 * alpha))
		_air.draw_string(font, Vector2(-width * 0.5, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(_t_color[i], alpha))
	_air.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---------------------------------------------------------------------------
# Corpses
# ---------------------------------------------------------------------------

func _spawn_corpse(unit: UnitBase) -> void:
	var slot: int = -1
	var oldest: float = -1.0
	for n: int in MAX_CORPSES:
		var i: int = (_c_next + n) % MAX_CORPSES
		if _c_kind[i] == 0:
			slot = i
			break
		if _c_age[i] > oldest:
			oldest = _c_age[i]
			slot = i
	_c_next = (slot + 1) % MAX_CORPSES
	while _corpses.size() <= slot:
		var created := Sprite2D.new()
		created.visible = false
		add_child(created)
		_corpses.append(created)
	var source: Sprite2D = unit._sprite
	var sprite: Sprite2D = _corpses[slot]
	sprite.texture = source.texture
	sprite.offset = source.offset
	sprite.flip_h = source.flip_h
	sprite.material = null
	sprite.modulate = Color.WHITE
	sprite.rotation = 0.0
	sprite.scale = unit._sprite_rest_scale
	# Sort slightly behind the spot so survivors standing there draw on top.
	sprite.global_position = unit.get_visual_position() + Vector2(0.0, -3.0)
	sprite.visible = true
	if _c_kind[slot] == 0:
		_c_live += 1
	var kind: int = 1
	if unit.unit_type == UnitData.UnitType.SIEGE:
		kind = 3
	elif unit.unit_type in [UnitData.UnitType.CAVALRY, UnitData.UnitType.SCOUT]:
		kind = 2
	_c_kind[slot] = kind
	_c_age[slot] = 0.0
	_c_fall[slot] = 0.36 if kind == 1 else 0.46 if kind == 2 else 0.55
	# Fall away from the blow; without one, topple backwards.
	var push: Vector2 = unit.get_last_hit_direction()
	var side: float = signf(push.x) if absf(push.x) > 0.15 else (1.0 if source.flip_h else -1.0)
	_c_side[slot] = side
	_c_scale[slot] = unit._sprite_rest_scale
	_c_origin[slot] = sprite.position
	if kind == 3 and not GameManager.reduced_motion:
		_emit(unit.global_position + Vector2(0, -16), 8, Color(0.62, 0.48, 0.32), Color(0.4, 0.3, 0.22, 0.0), 50.0, 130.0, -PI * 0.5, 1.3, 320.0, 0.6, 3.6, 1.8, true)
		dust(unit.global_position, 5, 1.2)
		add_shake(0.25, unit.global_position)


func _step_corpses(delta: float) -> void:
	var live: int = 0
	for i: int in MAX_CORPSES:
		var kind: int = _c_kind[i]
		if kind == 0:
			continue
		var sprite: Sprite2D = _corpses[i]
		var before: float = _c_age[i]
		_c_age[i] += delta
		var age: float = _c_age[i]
		var fall: float = _c_fall[i]
		if age >= CORPSE_SECONDS:
			_c_kind[i] = 0
			sprite.visible = false
			sprite.texture = null
			continue
		live += 1
		if before < fall or age <= fall + delta:
			var t: float = clampf(age / fall, 0.0, 1.0)
			if GameManager.reduced_motion:
				t = 1.0
			_pose_corpse(sprite, i, kind, t)
			if t >= 1.0 and before < fall:
				sprite.material = corpse_material()
				sprite.modulate = Color.WHITE
				if kind != 3:
					dust(sprite.global_position + Vector2(_c_side[i] * 12.0, 4.0), 3 if kind == 1 else 5, 0.7 if kind == 1 else 1.1)
				if kind == 2:
					add_shake(0.12, sprite.global_position)
		elif age > CORPSE_SECONDS - CORPSE_FADE_SECONDS:
			sprite.modulate.a = clampf((CORPSE_SECONDS - age) / CORPSE_FADE_SECONDS, 0.0, 1.0)
	_c_live = live


func _pose_corpse(sprite: Sprite2D, index: int, kind: int, t: float) -> void:
	var rest: Vector2 = _c_scale[index]
	var side: float = _c_side[index]
	var origin: Vector2 = _c_origin[index]
	if kind == 3:
		# Siege: the frame buckles, slumps and settles as a wreck.
		var drop: float = t * t
		var settle: float = sin(t * PI) * 0.03
		sprite.rotation = side * (0.24 * drop + settle)
		sprite.scale = rest * Vector2(1.0 + 0.06 * drop, 1.0 - 0.30 * drop)
		sprite.position = origin + Vector2(0.0, 2.0 * drop)
		sprite.modulate = Color.WHITE.lerp(Color(0.78, 0.74, 0.70), drop)
		return
	# Stagger back on the heels, then drop: slow start, hard landing, one bounce.
	var stagger: float = clampf(t / 0.3, 0.0, 1.0)
	var drop_t: float = clampf((t - 0.22) / 0.78, 0.0, 1.0)
	var eased: float = drop_t * drop_t * drop_t
	var bounce: float = sin(clampf((t - 0.86) / 0.14, 0.0, 1.0) * PI) * 0.05
	var lying: float = PI * 0.5 - 0.10
	sprite.rotation = side * (0.16 * sin(stagger * PI * 0.5) * (1.0 - eased) + lying * eased - bounce)
	var hop: float = sin(clampf(t / 0.5, 0.0, 1.0) * PI) * (5.0 if kind == 1 else 7.0)
	sprite.position = origin + Vector2(side * 5.0 * t, -hop)
	# Once flat, the sprite's own x axis is the screen's vertical: compress it so
	# the figure lies on the ground instead of standing sideways.
	sprite.scale = rest * Vector2(1.0 - 0.26 * eased, 1.0 + 0.04 * sin(t * PI))
	sprite.modulate = Color.WHITE


# ---------------------------------------------------------------------------
# Building collapse, rubble, construction pop, damage smoke
# ---------------------------------------------------------------------------

func _begin_collapse(building: BuildingBase) -> void:
	var source: Sprite2D = building._sprite
	var sprite := Sprite2D.new()
	sprite.texture = source.texture
	sprite.offset = source.offset
	sprite.flip_h = source.flip_h
	sprite.scale = source.scale
	add_child(sprite)
	sprite.global_position = source.global_position
	var material := ShaderMaterial.new()
	material.shader = COLLAPSE_SHADER
	var uv_range: Vector2 = KingdomArt.vertical_uv_range(source.texture)
	material.set_shader_parameter("ink_top", uv_range.x)
	material.set_shader_parameter("ink_bottom", uv_range.y)
	material.set_shader_parameter("sink", 0.0)
	sprite.material = material
	source.visible = false
	if building._ownership_marker != null:
		building._ownership_marker.visible = false
	var bounds: Rect2 = building.get_visual_bounds(false)
	var half := Vector2(building.footprint.x * MapData.TILE_WIDTH, building.footprint.y * MapData.TILE_HEIGHT) * 0.5
	var size: float = clampf(float(building.footprint.x + building.footprint.y) / 8.0, 0.25, 1.0)
	_collapses.append({"sprite": sprite, "material": material, "age": 0.0, "origin": sprite.position, "bounds": bounds, "ground": source.global_position, "half": half, "size": size, "beat": 0, "seed": building.get_instance_id()})
	add_shake(0.25 + 0.2 * size, source.global_position)
	if not GameManager.reduced_motion:
		_emit(bounds.get_center(), 6, Color(0.66, 0.56, 0.42), Color(0.45, 0.38, 0.3, 0.0), 60.0, 150.0, -PI * 0.5, 1.2, 320.0, 0.7, 4.0, 2.0, true)


func _step_collapses(delta: float) -> void:
	for index: int in range(_collapses.size() - 1, -1, -1):
		var entry: Dictionary = _collapses[index]
		var sprite: Sprite2D = entry.sprite
		entry.age = float(entry.age) + delta
		var age: float = entry.age
		var t: float = clampf(age / COLLAPSE_SECONDS, 0.0, 1.0)
		var bounds: Rect2 = entry.bounds
		var ground: Vector2 = entry.ground
		var half: Vector2 = entry.half
		var size: float = entry.size
		# Shudder, then an accelerating sink behind a rising wall of dust.
		var sink_t: float = clampf((t - 0.10) / 0.82, 0.0, 1.0)
		var sink: float = sink_t * sink_t * (1.6 - 0.6 * sink_t)
		(entry.material as ShaderMaterial).set_shader_parameter("sink", clampf(sink, 0.0, 1.0))
		var origin: Vector2 = entry.origin
		if GameManager.reduced_motion:
			sprite.position = origin
		else:
			var shudder: float = (1.0 - sink_t) * 1.8 + 0.5
			sprite.position = origin + Vector2(sin(age * 71.0) * shudder, 0.0)
			sprite.rotation = sin(age * 9.0) * 0.012 * sink_t
			# Dust boils along the footing for the whole fall.
			if _rng.randf() < delta * 26.0:
				var x: float = _rng.randf_range(-half.x, half.x) * 0.8
				dust(ground + Vector2(x, _rng.randf_range(-half.y, half.y) * 0.5 + 4.0), 2, 1.3 + size, 0.8)
			if _rng.randf() < delta * 10.0:
				smoke(Vector2(_rng.randf_range(bounds.position.x, bounds.end.x), lerpf(bounds.position.y, bounds.end.y, 0.3 + sink * 0.6)), 0.35, 1.2 + size)
		var beat: int = entry.beat
		if beat == 0 and t >= 0.34:
			entry.beat = 1
			_debris(bounds, ground, size)
			add_shake(0.2 + 0.25 * size, ground)
			_place_rubble(ground, half, int(entry.seed))
		elif beat == 1 and t >= 0.78:
			entry.beat = 2
			_debris(bounds, ground, size)
			ground_burst(ground, 1.2 + 1.6 * size)
			add_shake(0.35 + 0.55 * size, ground)
		if t >= 1.0:
			sprite.queue_free()
			_collapses.remove_at(index)


func _debris(bounds: Rect2, ground: Vector2, size: float) -> void:
	if GameManager.reduced_motion:
		return
	var from := Vector2(bounds.get_center().x, lerpf(bounds.position.y, bounds.end.y, 0.55))
	_emit(from, 6 + int(8 * size), Color(0.62, 0.52, 0.40), Color(0.42, 0.36, 0.30, 0.0), 70.0, 190.0, -PI * 0.5, 1.35, 380.0, 0.8, 4.4, 2.2, true)
	_emit(from, 4 + int(4 * size), Color(0.70, 0.68, 0.62), Color(0.5, 0.48, 0.44, 0.0), 50.0, 150.0, -PI * 0.5, 1.4, 380.0, 0.7, 3.6, 2.0, true)
	dust(ground, 5 + int(6 * size), 1.5 + size, 0.8)


func _place_rubble(ground: Vector2, half: Vector2, seed_value: int) -> void:
	var pile: Rubble = null
	if _rubble.size() < MAX_RUBBLE:
		pile = Rubble.new()
		pile.z_index = GROUND_Z
		pile.z_as_relative = false
		add_child(pile)
		_rubble.append(pile)
	else:
		pile = _rubble[_rubble_next]
		_rubble_next = (_rubble_next + 1) % MAX_RUBBLE
	pile.half = half * 0.82
	pile.seed_value = seed_value
	pile.age = 0.0
	pile.global_position = ground
	pile.modulate.a = 0.0
	pile.visible = true
	pile.queue_redraw()


func _step_rubble(delta: float) -> void:
	for pile: Rubble in _rubble:
		if pile.age < 0.0:
			continue
		pile.age += delta
		if pile.age >= RUBBLE_SECONDS:
			pile.age = -1.0
			pile.visible = false
		elif pile.age < 0.6:
			pile.modulate.a = pile.age / 0.6
		elif pile.age > RUBBLE_SECONDS - RUBBLE_FADE_SECONDS:
			pile.modulate.a = (RUBBLE_SECONDS - pile.age) / RUBBLE_FADE_SECONDS
		elif pile.modulate.a != 1.0:
			pile.modulate.a = 1.0


func _scan_buildings() -> void:
	if not is_inside_tree():
		return
	var nodes: Array[Node] = get_tree().get_nodes_in_group("buildings")
	if _b_state.size() > nodes.size() * 2 + 16:
		_b_state.clear()
		_b_progress.clear()
	for node: Node in nodes:
		var building := node as BuildingBase
		if building == null or building.is_queued_for_deletion() or building._sprite == null:
			continue
		var id: int = building.get_instance_id()
		var previous: int = int(_b_state.get(id, -1))
		var state: int = building.state
		_b_state[id] = state
		if state == BuildingBase.State.CONSTRUCTING:
			var progress: float = building.build_progress
			var grew: bool = progress > float(_b_progress.get(id, progress)) + 0.0001
			_b_progress[id] = progress
			if grew and not GameManager.reduced_motion and can_show(building):
				var half_width: float = building.footprint.x * MapData.TILE_WIDTH * 0.32
				var base: Vector2 = building._sprite.global_position
				dust(base + Vector2(_rng.randf_range(-half_width, half_width), _rng.randf_range(-6.0, 10.0)), 2, 1.0)
				if _rng.randf() < 0.5:
					_emit(base + Vector2(_rng.randf_range(-half_width, half_width), -8.0 - progress * 30.0), 2, Color(0.80, 0.68, 0.46), Color(0.6, 0.5, 0.36, 0.0), 24.0, 60.0, -PI * 0.5, 1.0, 240.0, 0.4, 2.6, 1.4, true)
		elif state == BuildingBase.State.ACTIVE:
			if previous == BuildingBase.State.CONSTRUCTING and can_show(building):
				_begin_pop(building)
			if building.hp < building.max_hp and building.max_hp > 0 and not GameManager.reduced_motion:
				var ratio: float = float(building.hp) / float(building.max_hp)
				if ratio < 0.66 and can_show(building):
					_smoulder(building, ratio, id)


func _smoulder(building: BuildingBase, ratio: float, id: int) -> void:
	var bounds: Rect2 = building.get_visual_bounds(false)
	var severity: float = clampf((0.66 - ratio) / 0.5, 0.0, 1.0)
	var scale_factor: float = clampf(bounds.size.x / 90.0, 0.7, 1.6)
	# Two or three fixed seats per building, so smoke rises from "its" wounds.
	var seats: int = 1 if ratio > 0.45 else 2 if ratio > 0.25 else 3
	for seat: int in seats:
		var hash_value: int = (id * 73 + seat * 9973) & 0xffff
		var fx_x: float = lerpf(0.28, 0.72, float(hash_value & 0xff) / 255.0)
		var fx_y: float = lerpf(0.22, 0.50, float((hash_value >> 8) & 0xff) / 255.0)
		var point: Vector2 = bounds.position + bounds.size * Vector2(fx_x, fx_y)
		if _rng.randf() < 0.45 + severity * 0.5:
			smoke(point, severity, scale_factor)
		if ratio < 0.33 and seat < 2:
			fire(point + Vector2(0, 4), scale_factor)


func _begin_pop(building: BuildingBase) -> void:
	var sprite: Sprite2D = building._sprite
	for entry: Dictionary in _pops:
		if entry.sprite == sprite:
			return
	_pops.append({"sprite": sprite, "rest": sprite.scale, "age": 0.0})
	if GameManager.reduced_motion:
		return
	var ground: Vector2 = sprite.global_position
	var half_width: float = building.footprint.x * MapData.TILE_WIDTH * 0.4
	_ring(ground, half_width * 1.5, 0.5)
	for n: int in 6:
		dust(ground + Vector2(_rng.randf_range(-half_width, half_width), _rng.randf_range(-4.0, 12.0)), 1, 1.1)
	var bounds: Rect2 = building.get_visual_bounds(false)
	_emit(bounds.get_center(), 14, Color(1.0, 0.94, 0.66, 0.95), Color(1.0, 0.80, 0.36, 0.0), 50.0, 130.0, -PI * 0.5, PI, 110.0, 0.7, 3.4, 1.2, true)


func _step_pops(delta: float) -> void:
	for index: int in range(_pops.size() - 1, -1, -1):
		var entry: Dictionary = _pops[index]
		var sprite: Sprite2D = entry.sprite if is_instance_valid(entry.sprite) else null
		if sprite == null:
			_pops.remove_at(index)
			continue
		entry.age = float(entry.age) + delta
		var t: float = float(entry.age) / 0.42
		var rest: Vector2 = entry.rest
		if t >= 1.0 or GameManager.reduced_motion:
			sprite.scale = rest
			_pops.remove_at(index)
			continue
		# Damped overshoot: settle down hard, spring up, rest.
		var spring: float = sin(t * PI * 2.5) * (1.0 - t) * (1.0 - t)
		sprite.scale = rest * Vector2(1.0 - spring * 0.06, 1.0 + spring * 0.10)


# ---------------------------------------------------------------------------
# Camera shake
# ---------------------------------------------------------------------------

func add_shake(strength: float, world_position: Vector2 = Vector2.INF) -> void:
	if GameManager.reduced_motion or strength <= 0.0:
		return
	var amount: float = clampf(strength, 0.0, 1.0)
	if world_position.is_finite():
		if not _view.grow(_view.size.x * 0.25).has_point(world_position):
			return
		var center: Vector2 = _view.get_center()
		var reach: float = maxf(1.0, _view.size.length() * 0.5)
		amount *= clampf(1.25 - world_position.distance_to(center) / reach, 0.35, 1.0)
	_trauma = minf(1.0, maxf(_trauma, amount) + amount * 0.25)


func _update_shake(real_delta: float) -> void:
	if _trauma <= 0.0:
		if _shake_applied:
			_release_camera()
		return
	var camera: Camera2D = get_viewport().get_camera_2d() if is_inside_tree() else null
	if camera == null or GameManager.reduced_motion:
		_trauma = 0.0
		_release_camera()
		return
	_shake_clock += real_delta
	_trauma = maxf(0.0, _trauma - real_delta * 2.4)
	# Small screens get a proportionally smaller excursion (about 1.4% of the
	# short side, never more than 7 px), so a phone never loses its target.
	var viewport_size: Vector2 = get_viewport_rect().size
	var max_px: float = clampf(minf(viewport_size.x, viewport_size.y) * 0.014, 2.0, 7.0)
	var amplitude: float = max_px * _trauma * _trauma / _zoom
	camera.offset = Vector2(sin(_shake_clock * 67.0) + sin(_shake_clock * 41.0 + 1.7) * 0.5, sin(_shake_clock * 53.0 + 0.6) + sin(_shake_clock * 37.0 + 2.9) * 0.5) * amplitude * 0.66
	_shake_applied = true
	if _trauma <= 0.0:
		_release_camera()


func _release_camera() -> void:
	if not _shake_applied:
		return
	_shake_applied = false
	var camera: Camera2D = get_viewport().get_camera_2d() if is_inside_tree() else null
	if camera != null:
		camera.offset = Vector2.ZERO

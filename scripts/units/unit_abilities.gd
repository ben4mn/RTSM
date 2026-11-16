class_name UnitAbilities
extends RefCounted
## Round 2 workstream C: the three kingdoms' passive unit abilities.
##
## A unit gets an ability from its civilization override (`"ability"` in
## CivilizationData.unit_overrides). Everything here is static; the unit only
## carries `_ability_kind` (derived from data) plus two saved fields
## (`_ability_timer`, `_ability_ready`) and calls `tick` while it has one.
##
##   Charge  (French Chevalier)  after CHARGE_RECHARGE_SECONDS without
##           attacking, the next melee hit deals bonus damage. Pennon up = ready.
##   Emplace (English Longbow)   after EMPLACE_SECONDS standing still: more
##           range and a faster bow. Stakes at its feet = emplaced.
##   Pillage (Mongol Outrider)   gold for every hit on a building and for every
##           Villager slain. A loot sack and a "+n" figure show each payout.
##
## `_ability_ready` is the one visible flag (pennon / stakes / sack). It is
## saved with the unit and sent to clients as the unit actor's `ability` field.
##
## Hooks into shared code, one call each:
##   UnitBase._load_stats_from_data -> setup          UnitBase._process -> tick
##   Combat.queue_melee_attack -> melee_bonus_damage  Combat.resolve_unit_hit -> on_unit_hit
##   Combat.deal_damage_to_building -> on_building_hit
##   ResearchEffects.gather_multiplier -> gather_bonus (the wildlife hook)
##   main._on_research_completed -> on_research_completed
##   network_match snapshot/apply -> `ability` flag / set_replica_ready

enum Kind { NONE, CHARGE, EMPLACE, PILLAGE }
const KIND_BY_ID: Dictionary = {"charge": Kind.CHARGE, "emplace": Kind.EMPLACE, "pillage": Kind.PILLAGE}

# --- Tuning (workstream E: retune freely; ratios survive the stat rescale) ---
## Seconds without attacking before a Chevalier's Charge is ready.
const CHARGE_RECHARGE_SECONDS: float = 10.0
## Bonus HP loss of a charged hit, as a ratio of the attacker's own base
## damage: +13 at the Chevalier's 10 damage (+16 as a Knight).
const CHARGE_DAMAGE_RATIO: float = 1.25
## Registry key: seconds added to the recharge (Chivalry writes -5).
const CHARGE_RECHARGE_KEY: String = "civ_charge_recharge"
const CHARGE_MIN_RECHARGE_SECONDS: float = 1.0

## Seconds a Longbow must stand still before it is emplaced.
const EMPLACE_SECONDS: float = 2.5
const EMPLACE_RANGE_TILES: float = 1.0
const EMPLACE_INTERVAL_MULTIPLIER: float = 0.8
## World pixels of jostling (formation spacing) that do not break the stakes.
const EMPLACE_DRIFT: float = 10.0

## Gold per Outrider hit on a building / per Villager slain (Round 2 E scale).
const PILLAGE_GOLD_PER_BUILDING_HIT: int = 2
const PILLAGE_GOLD_PER_VILLAGER_KILL: int = 10
## Registry key: fraction added to both payouts (Yam writes +1.0 = doubled).
const PILLAGE_KEY: String = "civ_pillage"
const LOOT_SHOW_SECONDS: float = 1.6

## Registry key (fraction) for the Mongol herd-and-game gathering bonus.
## Wildlife stream: any harvest target in group "wildlife", or exposing a
## `gather_multiplier` property, receives it through `gather_bonus` below; no
## other call is needed.
const WILDLIFE_KEY: String = "gather_wildlife"
const WILDLIFE_GROUP: String = "wildlife"

const SECTION: String = "civ_abilities"
const OVERLAY_NAME: String = "AbilityOverlay"
const OVERLAY_TEXTURES: Dictionary = {
	Kind.CHARGE: "res://assets/units/overlay_pennon.svg",
	Kind.EMPLACE: "res://assets/units/overlay_stakes.svg",
	Kind.PILLAGE: "res://assets/units/overlay_loot.svg",
}


## Balance telemetry, per player: counts since the match started. Read by
## tools/probe_joy_match.gd; nothing in the simulation depends on it.
static var telemetry: Dictionary = {}


class Overlay extends Sprite2D:
	## The pennon / stakes / loot sack. Presentation only. It keeps its own
	## process mode so it also animates on inert network replicas.
	var host_sprite: Sprite2D = null
	var anchor: Vector2 = Vector2.ZERO
	var rest_scale: Vector2 = Vector2.ONE
	var mirrors: bool = false
	var flutter: float = 0.0
	var _age: float = 0.0

	func appear(animated: bool) -> void:
		_age = 0.0 if animated else 1.0
		visible = true
		set_process(true)
		_pose()

	func disappear() -> void:
		visible = false
		set_process(false)

	func _process(delta: float) -> void:
		_age += delta
		_pose()
		if not mirrors and flutter <= 0.0 and _age > 0.3:
			set_process(false)

	func _pose() -> void:
		var pop: float = 1.0
		if _age < 0.24 and not GameManager.reduced_motion:
			var t: float = _age / 0.24
			# Overshoot, then settle: the pennon snaps up, the stakes thud in.
			pop = 1.0 + 0.28 * sin(t * PI) - (1.0 - t) * (1.0 - t)
		var flipped: bool = mirrors and is_instance_valid(host_sprite) and host_sprite.flip_h
		position = Vector2(-anchor.x if flipped else anchor.x, anchor.y)
		scale = Vector2(-rest_scale.x if flipped else rest_scale.x, rest_scale.y) * maxf(0.05, pop)
		if flutter > 0.0 and not GameManager.reduced_motion:
			skew = sin(_age * 6.5) * flutter


static func install(main: Node) -> void:
	## Ability state travels in UNIT_FIELDS; this only re-derives the overlays
	## once a solo save has been restored.
	main.ext.register_save(SECTION, _capture, _restore, _finalize_restore.bind(main))
	telemetry = {0: {"charge_hits": 0, "charge_damage": 0, "emplacements": 0, "pillage_gold": 0}, 1: {"charge_hits": 0, "charge_damage": 0, "emplacements": 0, "pillage_gold": 0}}


static func _count(player_id: int, key: String, amount: int = 1) -> void:
	if telemetry.has(player_id):
		telemetry[player_id][key] = int(telemetry[player_id].get(key, 0)) + amount


# --- Data helpers ------------------------------------------------------------

static func kind_of(unit_type: int, player_id: int) -> int:
	if player_id < 0:
		return Kind.NONE
	return int(KIND_BY_ID.get(CivilizationData.get_unit_ability(CivilizationData.for_player(player_id), unit_type), Kind.NONE))


static func get_charge_recharge(player_id: int) -> float:
	return maxf(CHARGE_MIN_RECHARGE_SECONDS, CHARGE_RECHARGE_SECONDS + GameManager.get_modifier(player_id, CHARGE_RECHARGE_KEY))


static func get_charge_bonus(unit: UnitBase) -> float:
	return maxf(1.0, round(unit.damage * CHARGE_DAMAGE_RATIO))


static func get_pillage_gold(player_id: int, villager_kill: bool) -> int:
	var base: int = PILLAGE_GOLD_PER_VILLAGER_KILL if villager_kill else PILLAGE_GOLD_PER_BUILDING_HIT
	return maxi(0, int(round(float(base) * GameManager.get_modifier_multiplier(player_id, PILLAGE_KEY))))


static func describe(kind: int, player_id: int = -1, unit_type: int = UnitData.UnitType.CAVALRY) -> String:
	## One learnable line for the unit card, the recruit sheet and the picker.
	## Numbers come from the constants and the player's research.
	match kind:
		Kind.CHARGE:
			var bonus: int = int(round(float(UnitData.get_unit_stats(unit_type, player_id).get("damage", 0)) * CHARGE_DAMAGE_RATIO))
			return "Charge: after %d s without attacking, the next hit deals +%d damage. A raised pennon means ready." % [int(round(get_charge_recharge(player_id))), bonus]
		Kind.EMPLACE:
			return "Emplace: stands still %s s to plant stakes: +%d range and shoots %d%% faster until it moves." % [str(EMPLACE_SECONDS).trim_suffix(".0"), int(EMPLACE_RANGE_TILES), int(round((1.0 / EMPLACE_INTERVAL_MULTIPLIER - 1.0) * 100.0))]
		Kind.PILLAGE:
			return "Pillage: +%d gold for every hit on a building, +%d for every Villager slain." % [get_pillage_gold(player_id, false), get_pillage_gold(player_id, true)]
	return ""


static func card_line(unit_type: int, player_id: int) -> String:
	return describe(kind_of(unit_type, player_id), player_id, unit_type)


static func describe_for_civilization(civilization: int) -> String:
	## Picker copy, before any match exists: the base numbers.
	for unit_type: int in CivilizationData.DEFINITIONS[CivilizationData.normalize(civilization)]["unit_overrides"]:
		var kind: int = int(KIND_BY_ID.get(CivilizationData.get_unit_ability(civilization, unit_type), Kind.NONE))
		if kind == Kind.CHARGE:
			var damage: float = float(CivilizationData.get_unit_stats(UnitData.UNITS[unit_type], unit_type, civilization).get("damage", 0))
			return "Charge: after %d s without attacking, the next hit deals +%d damage. A raised pennon means ready." % [int(CHARGE_RECHARGE_SECONDS), int(round(damage * CHARGE_DAMAGE_RATIO))]
		if kind == Kind.PILLAGE:
			return "Pillage: +%d gold for every hit on a building, +%d for every Villager slain." % [PILLAGE_GOLD_PER_BUILDING_HIT, PILLAGE_GOLD_PER_VILLAGER_KILL]
		if kind != Kind.NONE:
			return describe(kind)
	return ""


# --- Unit lifecycle ----------------------------------------------------------

static func setup(unit: UnitBase) -> void:
	## Called when a unit loads its data stats (spawn, replicas, restore).
	unit._ability_kind = kind_of(unit.unit_type, unit.player_owner)
	unit._ability_timer = 0.0
	unit._ability_ready = false


static func tick(unit: UnitBase, delta: float) -> void:
	## Authority only (replicas never process). Cheap: a few float compares.
	match unit._ability_kind:
		Kind.CHARGE:
			if not unit._ability_ready:
				unit._ability_timer += delta
				if unit._ability_timer >= get_charge_recharge(unit.player_owner):
					_set_ready(unit, true)
		Kind.EMPLACE:
			var position: Vector2 = unit.global_position
			if not unit._ability_anchor.is_finite():
				unit._ability_anchor = position
			if unit.current_state == UnitBase.State.MOVING or position.distance_squared_to(unit._ability_anchor) > EMPLACE_DRIFT * EMPLACE_DRIFT:
				unit._ability_anchor = position
				unit._ability_timer = 0.0
				if unit._ability_ready:
					_set_emplaced(unit, false)
			elif not unit._ability_ready:
				unit._ability_timer += delta
				if unit._ability_timer >= EMPLACE_SECONDS:
					_set_emplaced(unit, true)
		Kind.PILLAGE:
			if unit._ability_ready:
				unit._ability_timer -= delta
				if unit._ability_timer <= 0.0:
					_set_ready(unit, false)


static func _set_ready(unit: UnitBase, ready: bool) -> void:
	if unit._ability_ready == ready:
		return
	unit._ability_ready = ready
	refresh_overlay(unit, true)


static func _set_emplaced(unit: UnitBase, emplaced: bool) -> void:
	## The single place a Longbow's range and bow speed change. `attack_range`
	## and `attack_speed` stay the unit's effective values, so research
	## (`attack_range += ...`) and saves compose without special cases.
	if unit._ability_ready == emplaced:
		return
	var range_bonus: float = MapData.range_tiles_to_world(EMPLACE_RANGE_TILES)
	if emplaced:
		_count(unit.player_owner, "emplacements")
		unit.attack_range += range_bonus
		unit.attack_speed /= EMPLACE_INTERVAL_MULTIPLIER
	else:
		unit.attack_range -= range_bonus
		unit.attack_speed *= EMPLACE_INTERVAL_MULTIPLIER
	unit._ability_timer = 0.0
	_set_ready(unit, emplaced)


# --- Combat hooks ------------------------------------------------------------

static func melee_bonus_damage(attacker: UnitBase) -> float:
	## Bonus HP loss for the melee blow being released now; spends the Charge.
	if attacker._ability_kind != Kind.CHARGE:
		return 0.0
	var charged: bool = attacker._ability_ready
	attacker._ability_timer = 0.0
	if not charged:
		return 0.0
	_set_ready(attacker, false)
	_count(attacker.player_owner, "charge_hits")
	_count(attacker.player_owner, "charge_damage", int(get_charge_bonus(attacker)))
	return get_charge_bonus(attacker)


static func on_unit_hit(attacker: UnitBase, defender: UnitBase, charged: bool, killed: bool) -> void:
	## After a unit-vs-unit hit resolved. `attacker` may already be gone.
	if not is_instance_valid(attacker):
		return
	if charged and is_instance_valid(defender) and defender.visible:
		BattleFX.charge_struck(attacker, defender)
	if killed and attacker._ability_kind == Kind.PILLAGE and is_instance_valid(defender) and defender.unit_type == UnitData.UnitType.VILLAGER and defender.player_owner != attacker.player_owner:
		_pay_pillage(attacker, defender, get_pillage_gold(attacker.player_owner, true))


static func on_building_hit(attacker: UnitBase, building: BuildingBase) -> int:
	## Extra damage for this hit on a building (a spent Charge), and Pillage.
	var bonus: int = 0
	match attacker._ability_kind:
		Kind.CHARGE:
			bonus = int(melee_bonus_damage(attacker))
			if bonus > 0 and building.visible:
				# After the hit's own damage figure exists, so it can grow.
				BattleFX.charge_struck.call_deferred(attacker, building)
		Kind.PILLAGE:
			if building.player_owner != attacker.player_owner:
				_pay_pillage(attacker, building, get_pillage_gold(attacker.player_owner, false))
	return bonus


static func _pay_pillage(attacker: UnitBase, victim: Node2D, gold: int) -> void:
	if gold <= 0:
		return
	ResourceManager.add_resource(attacker.player_owner, "gold", gold)
	_count(attacker.player_owner, "pillage_gold", gold)
	attacker._ability_timer = LOOT_SHOW_SECONDS
	_set_ready(attacker, true)
	# The figure belongs to the raider: only its owner's screen shows it.
	if attacker.player_owner == 0:
		BattleFX.loot_gained(attacker, victim, gold)


# --- Economy hook ------------------------------------------------------------

static func is_wildlife(target: Node) -> bool:
	return target != null and (target.is_in_group(WILDLIFE_GROUP) or target.get("gather_multiplier") != null)


static func gather_bonus(player_id: int, resource_type: String, target: Node) -> float:
	## Fraction added to one villager gather tick by kingdom identity.
	## Wildlife hook: sheep, deer and boar carcasses qualify through
	## `is_wildlife`. Until they exist, berry bushes also qualify
	## (CivilizationData.WILDLIFE_BONUS_INCLUDES_BERRIES).
	if resource_type != "food" or target == null or target is BuildingBase:
		return 0.0
	var bonus: float = GameManager.get_modifier(player_id, WILDLIFE_KEY)
	if bonus == 0.0:
		return 0.0
	if is_wildlife(target):
		return bonus
	if CivilizationData.WILDLIFE_BONUS_INCLUDES_BERRIES and target is ResourceNode:
		return bonus
	return 0.0


# --- Research ----------------------------------------------------------------

static func on_research_completed(main: Node, player_id: int, research_id: String) -> void:
	## Authority: unique technologies that scale a line's HP or speed reach the
	## units already on the field (new ones read UnitData.get_unit_stats).
	if player_id < 0 or player_id >= main._player_units.size():
		return
	var effects: Dictionary = TechData.get_research_definition(research_id).get("effects", {})
	var touched: Dictionary = {}
	for key: String in effects:
		for stat: String in ["hp", "speed"]:
			var prefix: String = stat + "_mult_"
			if key.begins_with(prefix) and key.trim_prefix(prefix).is_valid_int():
				touched[int(key.trim_prefix(prefix))] = true
	if touched.is_empty():
		return
	for unit: Variant in main._player_units[player_id]:
		if not is_instance_valid(unit) or unit.current_state == UnitBase.State.DEAD or not touched.has(unit.unit_type):
			continue
		var stats: Dictionary = UnitData.get_unit_stats(unit.unit_type, player_id)
		ResearchEffects.upgrade_unit_tier(unit)  # Re-reads HP, keeping the ratio.
		if unit.unit_type != UnitData.UnitType.VILLAGER:
			unit.speed = float(stats.get("speed", unit.speed))


# --- Presentation ------------------------------------------------------------

static func set_replica_ready(unit: UnitBase, ready: bool) -> void:
	## Client: the authoritative flag for a visible unit actor.
	if unit._ability_ready == ready:
		return
	unit._ability_ready = ready
	refresh_overlay(unit, true)


static func refresh_overlay(unit: UnitBase, animated: bool = false) -> void:
	if NetworkSession.server_mode or not is_instance_valid(unit) or not unit.is_inside_tree():
		return
	var overlay: Overlay = unit.get_meta(OVERLAY_NAME) as Overlay if unit.has_meta(OVERLAY_NAME) else null
	if not is_instance_valid(overlay):
		overlay = null
	if not unit._ability_ready or unit._ability_kind == Kind.NONE:
		if overlay != null:
			overlay.disappear()
		return
	if overlay == null:
		overlay = _create_overlay(unit)
		if overlay == null:
			return
	overlay.appear(animated)


static func _create_overlay(unit: UnitBase) -> Overlay:
	var path: String = str(OVERLAY_TEXTURES.get(unit._ability_kind, ""))
	var sprite: Sprite2D = unit._sprite
	if path.is_empty() or not ResourceLoader.exists(path) or sprite == null:
		return null
	var overlay := Overlay.new()
	overlay.name = OVERLAY_NAME
	overlay.texture = load(path)
	overlay.centered = false
	overlay.process_mode = Node.PROCESS_MODE_PAUSABLE
	var size: Vector2 = overlay.texture.get_size()
	var top: float = unit.get_health_bar_y() + 6.0  # Top of the painted figure, unit space.
	if unit._ability_kind == Kind.EMPLACE:
		# Planted in the ground in front of the boots: stays put while the
		# archer's puppet sways, and never mirrors.
		overlay.offset = Vector2(-size.x * 0.5, -size.y)
		overlay.rest_scale = Vector2(0.4, 0.4) * UnitData.WORLD_VISUAL_SCALE
		overlay.anchor = Vector2(0.0, 6.0)
		unit.add_child(overlay)
	else:
		# Carried: a child of the painted sprite, so it hops, leans and
		# squashes with the rider. Sprite-local = unit space / sprite scale.
		var rest: Vector2 = unit._sprite_rest_scale
		overlay.host_sprite = sprite
		overlay.mirrors = true
		var size_factor: float = 0.34 if unit._ability_kind == Kind.CHARGE else 0.3
		overlay.rest_scale = Vector2(size_factor, size_factor) * UnitData.WORLD_VISUAL_SCALE / rest
		if unit._ability_kind == Kind.CHARGE:
			# Pole foot at the rider's back; the pennon flies behind the lance.
			overlay.offset = Vector2(-size.x + 5.0, -size.y)
			overlay.anchor = Vector2(-4.0, top + 12.0) / rest
			overlay.flutter = 0.10
		else:
			# Loot sack slung behind the saddle.
			overlay.offset = Vector2(-size.x * 0.5, -size.y)
			overlay.anchor = Vector2(-14.0, top * 0.45) / rest
		sprite.add_child(overlay)
	unit.set_meta(OVERLAY_NAME, overlay)
	return overlay


static func refresh_all(main: Node) -> void:
	for player_units: Variant in main._player_units:
		for unit: Variant in player_units:
			if is_instance_valid(unit) and unit._ability_kind != Kind.NONE:
				refresh_overlay(unit)


# --- Save seam ---------------------------------------------------------------

static func _capture(_codec: RefCounted) -> Dictionary:
	return {"version": 1}


static func _restore(_saved: Dictionary, _codec: RefCounted) -> void:
	pass


static func _finalize_restore(_saved: Dictionary, _codec: RefCounted, main: Node) -> void:
	refresh_all(main)

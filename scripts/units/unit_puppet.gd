class_name UnitPuppet
extends RefCounted
## "Paper puppet" animation for single-pose unit artwork. One instance per unit
## turns displacement, the existing attack/work clocks and hit events into a
## foot-pivot pose (offset, lean, squash/stretch). Presentation only: it reads
## unit state, writes only the sprite/overlay transforms, and uses its own RNG.
## Driven from UnitBase._update_sprite_motion, so inert network replicas animate
## through exactly the same path as simulated units.

const FLASH_SECONDS: float = 0.085
const FLINCH_SECONDS: float = 0.20
const IDLE_SETTLE_SECONDS: float = 0.7

static var _shared_rng: RandomNumberGenerator = null

var _seed: float = 0.0
var _move_blend: float = 0.0
var _idle_time: float = 0.0
var _look_timer: float = 5.0
var _gesture: float = 0.0
var _flash: float = 0.0
var _flinch: float = 0.0
var _flinch_direction: Vector2 = Vector2.ZERO
var _since_hit: float = 99.0
var _last_hit_direction: Vector2 = Vector2.ZERO
var _previous_attack_remaining: float = 0.0
var _shot_fired: bool = true
var _flash_applied: bool = false


func _init() -> void:
	if _shared_rng == null:
		_shared_rng = RandomNumberGenerator.new()
		_shared_rng.seed = 0x70a57e7
	_seed = _shared_rng.randf() * TAU
	_look_timer = _shared_rng.randf_range(2.5, 9.0)


func hit(with_flash: bool) -> void:
	_since_hit = 0.0
	_flinch = 1.0
	if with_flash:
		_flash = FLASH_SECONDS


func recoil(direction: Vector2) -> void:
	_flinch_direction = direction
	_last_hit_direction = direction


func seconds_since_hit() -> float:
	return _since_hit


func last_hit_direction() -> Vector2:
	return _last_hit_direction if _since_hit < 1.5 else Vector2.ZERO


static func _ease(value: float) -> float:
	var t: float = clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func update(unit: UnitBase, delta: float, displacement: Vector2) -> void:
	var sprite: Sprite2D = unit._sprite
	var reduced: bool = GameManager.reduced_motion
	var visual: float = UnitData.WORLD_VISUAL_SCALE
	var step: float = maxf(0.0, delta)
	_since_hit += step
	var offset := Vector2.ZERO
	var rotation: float = 0.0
	var stretch := Vector2.ONE
	var unit_type: int = unit.unit_type
	var mounted: bool = unit_type == UnitData.UnitType.CAVALRY or unit_type == UnitData.UnitType.SCOUT
	var siege: bool = unit_type == UnitData.UnitType.SIEGE

	# --- travel -----------------------------------------------------------
	var travelled: float = minf(displacement.length(), 14.0)
	var moving: bool = displacement.length_squared() > 0.001
	if moving and absf(displacement.x) > 0.01:
		sprite.flip_h = displacement.x < 0.0
	var facing: float = -1.0 if sprite.flip_h else 1.0
	# Blend in by distance (frame-rate independent foot pose), out by time.
	_move_blend = move_toward(_move_blend, 1.0, travelled / 5.0) if moving else move_toward(_move_blend, 0.0, step * 6.0)
	# The step phase lives on the unit (TAU = two footfalls) and only advances
	# with distance, so stopping plants the feet and resuming continues the step.
	var _phase: float = unit._gait_phase / PI
	if moving:
		var stride: float = (34.0 if mounted else 9.0 if siege else 15.0) * visual
		var previous_step: int = int(floor(_phase))
		_phase += travelled / stride
		unit._gait_phase = fposmod(_phase * PI, TAU * 64.0)
		if mounted and int(floor(_phase)) != previous_step and not reduced:
			var fx: BattleFX = BattleFX.get_fx()
			if fx != null and fx.on_screen(unit.global_position) and unit.is_visible_in_tree():
				fx.dust(unit.global_position - Vector2(facing * 8.0, -2.0), 1, 0.55)
	if _move_blend > 0.0 and not reduced:
		var blend: float = _move_blend
		if siege:
			# Heavy carriage: the wheels jolt, the frame barely pitches.
			offset.y -= absf(sin(_phase * PI)) * 0.7 * blend
			rotation += sin(_phase * PI) * 0.014 * blend
		elif mounted:
			# Gallop: a long bound that rocks from haunches to forehand.
			var bound: float = fposmod(_phase, 1.0)
			var air: float = pow(sin(bound * PI), 0.75)
			offset.y -= air * 4.6 * visual * blend
			rotation += (-cos(bound * PI) * 0.085 + 0.03) * facing * blend
			stretch.x += air * 0.045 * blend
			stretch.y -= air * 0.03 * blend
			stretch.y -= (1.0 - air) * 0.04 * blend
			stretch.x += (1.0 - air) * 0.02 * blend
		else:
			# Step-hop: squash on the footfall, stretch at the top, lean in.
			var swing: float = sin(_phase * PI)
			var hop: float = absf(swing)
			offset.y -= hop * 3.1 * visual * blend
			rotation += (0.065 * facing + swing * 0.055) * blend
			stretch.y += (hop - 0.55) * 0.085 * blend
			stretch.x -= (hop - 0.55) * 0.05 * blend

	# --- action (existing authoritative clocks) --------------------------
	var work: Vector3 = unit.get_work_presentation()
	var action: int = int(work.x)
	var phase: float = work.y
	var attacking: bool = unit._attack_animation_remaining > 0.0
	if attacking:
		var recovery: float = UnitBase.ATTACK_RECOVERY_SECONDS
		var elapsed: float = unit._attack_animation_duration - unit._attack_animation_remaining
		var windup: float = maxf(0.001, unit._attack_animation_duration - recovery)
		phase = UnitActionPresentation.RELEASE * elapsed / windup if elapsed <= windup else UnitActionPresentation.RELEASE + (1.0 - UnitActionPresentation.RELEASE) * (elapsed - windup) / recovery
		action = UnitActionPresentation.Action.MELEE
		if siege:
			action = UnitActionPresentation.Action.SIEGE
		elif unit.is_ranged:
			action = UnitActionPresentation.Action.BOW
		elif mounted:
			action = UnitActionPresentation.Action.MOUNTED
		# Replicas receive no projectile entity; release a cosmetic one.
		if unit._attack_animation_remaining > _previous_attack_remaining + 0.04:
			_shot_fired = false
		if not _shot_fired and elapsed >= windup:
			_shot_fired = true
			if unit._uses_network_work_pose and unit.is_ranged:
				BattleFX.replica_shot(unit, unit._attack_animation_direction)
	_previous_attack_remaining = unit._attack_animation_remaining
	if action != UnitActionPresentation.Action.NONE and not reduced:
		if attacking:
			var direction: Vector2 = unit._attack_animation_direction
			var pose: Vector4 = _attack_pose(action, phase)
			offset += direction * pose.x * visual + Vector2(0.0, pose.y * visual)
			rotation += pose.z * facing
			stretch.x += pose.w * 0.5
			stretch.y -= pose.w
		else:
			# Work keeps planted feet; the body and tool carry the rhythm.
			var pose: Vector4 = UnitActionPresentation.pose(action, phase, unit._art_civilization)
			rotation += pose.z * 1.7 * facing
			stretch.x += pose.w * 1.2
			stretch.y -= pose.w * 2.6

	# --- idle life -------------------------------------------------------
	var resting: bool = not moving and not attacking and action == UnitActionPresentation.Action.NONE and _flinch <= 0.0
	# Life eases in after a short rest, so every action first settles to the
	# exact authored pose.
	if resting:
		_idle_time += step
	else:
		_idle_time = 0.0
	if resting and not reduced:
		var eased_in: float = _ease((_idle_time - 0.25) / IDLE_SETTLE_SECONDS)
		var settle: float = eased_in if unit.current_state == UnitBase.State.IDLE else 0.0
		var clock: float = unit._animation_clock
		if unit.current_state == UnitBase.State.ATTACKING and _move_blend <= 0.0:
			# Between blows: a quick ready bounce instead of a frozen pose.
			var ready: float = sin(clock * 7.0 + _seed) * _ease((_idle_time - 0.2) / 0.3)
			stretch.y += ready * 0.014
			stretch.x -= ready * 0.008
		if settle > 0.0:
			var breath: float = sin(clock * (1.7 if mounted else 2.3) + _seed)
			stretch.y += breath * (0.014 if siege else 0.024) * settle
			stretch.x -= breath * (0.007 if siege else 0.012) * settle
			if not siege:
				rotation += sin(clock * 0.8 + _seed * 1.7) * 0.02 * settle
			_look_timer -= step
			if _look_timer <= 0.0:
				_look_timer = _shared_rng.randf_range(4.0, 11.0)
				_gesture = 1.0
				# Look the other way now and then; horses toss their heads.
				if not siege and not unit.is_selected and not unit._uses_network_work_pose and _shared_rng.randf() < 0.6:
					sprite.flip_h = not sprite.flip_h
					facing = -facing
		if _gesture > 0.0:
			_gesture = maxf(0.0, _gesture - step / 0.32)
			var beat: float = sin((1.0 - _gesture) * PI)
			offset.y -= beat * (1.6 if mounted else 1.2) * visual
			if mounted:
				rotation -= beat * 0.05 * facing
			stretch.y += beat * 0.02
	else:
		_gesture = 0.0

	# --- being hit ---------------------------------------------------------
	if _flinch > 0.0:
		_flinch = maxf(0.0, _flinch - step / FLINCH_SECONDS)
		if not reduced:
			# Snap away from the blow, then ease home.
			var kick: float = sin(_flinch * PI * 0.5) * _flinch
			offset += _flinch_direction * kick * (2.2 if siege else 3.4) * visual
			rotation += signf(_flinch_direction.x) * kick * 0.07
			stretch.y -= kick * 0.09
			stretch.x += kick * 0.06
		if _flinch <= 0.0:
			_flinch_direction = Vector2.ZERO
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - step)
		if not _flash_applied and sprite.material == null:
			sprite.material = BattleFX.flash_material()
			_flash_applied = true
	if _flash <= 0.0 and _flash_applied:
		_flash_applied = false
		if sprite.material == BattleFX.flash_material():
			sprite.material = null

	sprite.position = offset
	sprite.rotation = rotation
	sprite.scale = unit._sprite_rest_scale * stretch
	var overlay: UnitActionPresentation = unit._action_presentation
	overlay.position = offset
	overlay.present(action, phase, unit._art_civilization, facing, reduced, GameManager.reduced_flashes)
	# Tools share the body's foot pivot and bend so hands never detach.
	overlay.rotation = rotation
	overlay.scale = Vector2(facing, 1.0) * stretch * visual


## x: travel along the attack direction, y: lift, z: foot-pivot lean (facing
## relative), w: vertical squash. `p` reaches RELEASE exactly when the existing
## windup resolves, so the visible strike and the damage coincide.
static func _attack_pose(kind: int, p: float) -> Vector4:
	var release: float = UnitActionPresentation.RELEASE
	var wind: float = clampf(p / release, 0.0, 1.0)
	var after: float = clampf((p - release) / (1.0 - release), 0.0, 1.0)
	# Anticipation occupies the first 55% of the windup; the blow snaps through
	# the rest and lands at the release point.
	var gather: float = sin(clampf(wind / 0.55, 0.0, 1.0) * PI * 0.5)
	var snap: float = clampf((wind - 0.55) / 0.45, 0.0, 1.0)
	snap = snap * snap
	var settle: float = 1.0 - _ease(after)
	var rebound: float = sin(after * PI)
	match kind:
		UnitActionPresentation.Action.MELEE:
			if p <= release:
				return Vector4(lerpf(-2.6 * gather, 6.5, snap), -1.2 * gather * (1.0 - snap), lerpf(-0.13 * gather, 0.17, snap), -0.03 * gather + 0.05 * snap)
			return Vector4(6.5 * settle - 0.8 * rebound, 0.0, 0.17 * settle, 0.05 * settle)
		UnitActionPresentation.Action.MOUNTED:
			# Rear up, then drive the charge home.
			if p <= release:
				return Vector4(lerpf(-2.0 * gather, 8.0, snap), -3.0 * gather * (1.0 - snap), lerpf(-0.15 * gather, 0.10, snap), 0.04 * snap)
			return Vector4(8.0 * settle - 1.0 * rebound, 0.0, 0.10 * settle, 0.04 * settle)
		UnitActionPresentation.Action.BOW:
			# Lean back into the draw; the release kicks the archer's shoulders.
			var draw: float = _ease(wind)
			if p <= release:
				return Vector4(-1.6 * draw, 0.0, -0.085 * draw, -0.02 * draw)
			return Vector4(-1.6 * settle - 2.2 * rebound, -0.8 * rebound, -0.085 * settle + 0.07 * rebound, 0.03 * rebound)
		UnitActionPresentation.Action.SIEGE:
			# The frame loads, then the whole carriage bucks backwards.
			var load: float = _ease(wind)
			if p <= release:
				return Vector4(0.6 * load, 0.0, 0.02 * load, 0.02 * load)
			return Vector4(0.6 * settle - 4.5 * rebound, -1.6 * rebound, 0.02 * settle - 0.06 * rebound, -0.03 * rebound)
	return Vector4.ZERO

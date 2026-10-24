class_name UnitActionPresentation
extends Node2D
## One persistent overlay per unit. Poses are visual only: no timers, damage,
## resource mutation, particles or tweens are created by this helper.

enum Action { NONE, CHOP, FARM, MINE, BUILD, MELEE, BOW, MOUNTED, SIEGE, FORAGE }
const RELEASE: float = 0.7
const PALETTES: Array[Color] = [Color("88b7ad"), Color("89a267"), Color("d5aa63")]
const WOOD: Color = Color("93633d")
const METAL: Color = Color("c2c9be")
var action: int = Action.NONE
var phase: float = 0.0
var civilization: int = 0
var quiet_motion: bool = false
var quiet_flashes: bool = false


static func is_work_action(kind: int) -> bool:
	return (kind >= Action.CHOP and kind <= Action.BUILD) or kind == Action.FORAGE


static func _ease(value: float) -> float:
	var t: float = clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func _lift(p: float) -> float:
	if p < 0.22:
		return 0.0
	if p < 0.72:
		return _ease((p - 0.22) / 0.5)
	return 1.0 - _ease((p - 0.72) / 0.28)


static func pose(kind: int, p: float, civ: int) -> Vector4:
	## x/y translation, foot-pivot rotation, vertical compression. The release
	## point is supplied from existing authoritative windup/gather clocks.
	var style: float = 1.0 + float(clampi(civ, 0, 2) - 1) * 0.06
	var lift: float = _lift(p)
	var contact: float = 1.0 - _ease(p / 0.22) if p < 0.22 else _ease((p - 0.72) / 0.28)
	match kind:
		Action.CHOP, Action.MINE, Action.BUILD:
			var weight: float = 0.75 if kind == Action.BUILD else 1.0
			return Vector4((contact * 1.8 - lift * 0.8) * style, contact * 0.6, (contact * 0.12 - lift * 0.13) * weight * style, contact * 0.025)
		Action.FARM:
			var bend: float = sin(p * PI)
			return Vector4(bend * 1.7 * style, bend * 1.2, bend * 0.14 * style, bend * 0.07)
		Action.FORAGE:
			var reach: float = sin(p * PI)
			return Vector4(reach * 0.8, reach * 0.4, reach * 0.07 * style, reach * 0.02)
	var draw: float = _ease(p / RELEASE) if p <= RELEASE else 1.0 - _ease((p - RELEASE) / (1.0 - RELEASE))
	var load: float = sin(clampf(p / RELEASE, 0.0, 1.0) * PI)
	var strike: float = _ease((p - 0.32) / 0.38) if p < RELEASE else 1.0 - _ease((p - RELEASE) / 0.3)
	var recoil: float = sin(clampf((p - RELEASE) / 0.3, 0.0, 1.0) * PI)
	match kind:
		Action.MELEE:
			return Vector4((5.0 * strike - 1.3 * load) * style, -0.4 * strike, (0.09 * strike - 0.055 * load) * style, 0.015 * strike)
		Action.BOW:
			return Vector4(-2.2 * draw - recoil * 0.6, 0.0, -0.055 * draw * style, 0.0)
		Action.MOUNTED:
			return Vector4((5.5 * strike - load) * style, -1.1 * strike, 0.045 * strike * style, 0.02 * strike)
		Action.SIEGE:
			return Vector4(-3.5 * recoil - load * 0.6, recoil * 0.4, recoil * 0.016, 0.0)
	return Vector4.ZERO


func present(kind: int, p: float, civ: int, facing: float, reduced_motion: bool, reduced_flashes: bool) -> void:
	if kind == Action.NONE:
		if action != Action.NONE:
			action = Action.NONE
			visible = false
		return
	action = kind
	phase = clampf(p, 0.0, 1.0)
	civilization = clampi(civ, 0, 2)
	quiet_motion = reduced_motion
	quiet_flashes = reduced_flashes
	scale.x = facing
	visible = true
	queue_redraw()


func _draw() -> void:
	var p: float = 0.55 if quiet_motion else phase
	var trim: Color = PALETTES[civilization]
	var hand := Vector2(3.0, -14.0)
	if action >= Action.CHOP and action <= Action.BUILD:
		var lift: float = _lift(p)
		var angle: float = lerpf(0.48, -1.75, lift)
		if action == Action.FARM:
			hand += Vector2(sin(p * PI) * 2.0, sin(p * PI) * 3.0)
			angle = lerpf(0.9, 0.35, sin(p * PI))
		var tip: Vector2 = hand + Vector2.RIGHT.rotated(angle) * 12.0
		# A short sleeved forearm connects each moving tool to the miniature.
		draw_line(Vector2(-1, -15), hand, trim, 2.0, true)
		draw_line(hand - Vector2.RIGHT.rotated(angle) * 2.0, tip, Color("473b2e"), 2.5, true)
		draw_line(hand, tip, WOOD, 1.4, true)
		var cross: Vector2 = Vector2.UP.rotated(angle)
		if action == Action.CHOP:
			draw_colored_polygon(PackedVector2Array([tip - cross * 1.5, tip + cross * 4.2, tip + Vector2.RIGHT.rotated(angle) * 3.4 + cross * 3.0, tip + Vector2.RIGHT.rotated(angle) * 2.8 - cross]), METAL)
		elif action == Action.FARM:
			draw_line(tip, tip + cross * 4.0, METAL, 2.3, true)
		elif action == Action.MINE:
			draw_line(tip - cross * 4.0, tip + cross * 4.0, METAL, 1.8, true)
		else:
			draw_line(tip - cross * 2.3, tip + cross * 2.3, METAL, 3.0, true)
	elif action == Action.FORAGE:
		# Empty-handed reach and return toward the existing basket/satchel art.
		# Berry picking does not borrow a farmer's hoe or a mining tool.
		var reach: float = sin(p * PI)
		var wrist := Vector2(4.0 + reach * 4.0, -11.0 + reach * 3.0)
		draw_line(Vector2(0, -14), wrist, trim, 1.8, true)
		draw_circle(wrist, 1.1, Color("bb9b77"))
	elif action == Action.BOW:
		var tension: float = _ease(p / RELEASE) if p <= RELEASE else 1.0 - _ease((p - RELEASE) / 0.3)
		var upper := Vector2(9, -24)
		var lower := Vector2(11, -10)
		var nock := Vector2(7.0 - tension * 4.0, -17)
		draw_line(upper, nock, Color("c9bfa0"), 0.65, true)
		draw_line(nock, lower, Color("c9bfa0"), 0.65, true)
		if p <= RELEASE:
			draw_line(nock, Vector2(17, -17), WOOD, 0.9, true)
	elif action == Action.SIEGE:
		var tension: float = _ease(p / RELEASE) if p <= RELEASE else 1.0 - _ease((p - RELEASE) / 0.3)
		draw_line(Vector2(-9, -6), Vector2(1 - tension * 5, -18), Color("b9aa83"), 0.9, true)
	# Restrained weapon path only at release; accessibility disables it entirely.
	elif not quiet_flashes and not quiet_motion and p > 0.55 and p < 0.83:
		var reach: float = 15.0 if action == Action.MELEE else 21.0
		draw_line(Vector2(6, -16), Vector2(reach, -17), Color(trim, 0.5), 1.0, true)

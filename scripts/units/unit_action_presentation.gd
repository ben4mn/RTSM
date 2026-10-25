class_name UnitActionPresentation
extends Node2D
## One persistent overlay per unit. Poses are visual only: no timers, damage,
## resource mutation, particles or tweens are created by this helper.

enum Action { NONE, CHOP, FARM, MINE, BUILD, MELEE, BOW, MOUNTED, SIEGE, FORAGE }
const RELEASE: float = 0.7
const PALETTES: Array[Color] = [Color("7e99b0"), Color("b8796d"), Color("96a58a")]
const WOOD: Color = Color("a18660")
const METAL: Color = Color("b7beb5")
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
			# A planted stance lets the tool carry the action. Large translations
			# made the old miniature slide and bounce during every harvest.
			return Vector4(0.0, 0.0, (contact * 0.075 - lift * 0.085) * weight * style, contact * 0.015)
		Action.FARM:
			var bend: float = sin(p * PI)
			return Vector4(0.0, 0.0, bend * 0.10 * style, bend * 0.025)
		Action.FORAGE:
			var reach: float = sin(p * PI)
			return Vector4(0.0, 0.0, reach * 0.055 * style, reach * 0.012)
	var draw: float = _ease(p / RELEASE) if p <= RELEASE else 1.0 - _ease((p - RELEASE) / (1.0 - RELEASE))
	var load: float = sin(clampf(p / RELEASE, 0.0, 1.0) * PI)
	var strike: float = _ease((p - 0.32) / 0.38) if p < RELEASE else 1.0 - _ease((p - RELEASE) / 0.3)
	var recoil: float = sin(clampf((p - RELEASE) / 0.3, 0.0, 1.0) * PI)
	match kind:
		Action.MELEE:
			return Vector4((3.2 * strike - 0.8 * load) * style, 0.0, (0.065 * strike - 0.04 * load) * style, 0.012 * strike)
		Action.BOW:
			return Vector4(-0.8 * draw - recoil * 0.4, 0.0, -0.04 * draw * style, 0.0)
		Action.MOUNTED:
			return Vector4((4.0 * strike - load * 0.6) * style, 0.0, 0.03 * strike * style, 0.012 * strike)
		Action.SIEGE:
			return Vector4(-1.8 * recoil - load * 0.4, 0.0, recoil * 0.008, 0.0)
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
	# The new three-head figures carry their hands at the apron/sash line.
	var hand := Vector2(4.0, -11.5)
	if action >= Action.CHOP and action <= Action.BUILD:
		var lift: float = _lift(p)
		var angle: float = lerpf(0.48, -1.75, lift)
		if action == Action.FARM:
			hand += Vector2(sin(p * PI) * 1.5, sin(p * PI) * 1.5)
			angle = lerpf(0.95, 0.62, sin(p * PI))
		else:
			hand += Vector2(-lift, -lift * 3.0)
		var tip: Vector2 = hand + Vector2.RIGHT.rotated(angle) * 12.0
		# A rounded sleeve connects the moving tool to the illustrated worker.
		draw_line(Vector2(0, -13), hand, trim, 2.4, true)
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
		var wrist := Vector2(4.0 + reach * 3.0, -10.5 + reach * 2.0)
		draw_line(Vector2(0, -13), wrist, trim, 2.0, true)
		draw_circle(wrist, 1.1, Color("bb9b77"))
	elif action == Action.BOW:
		var tension: float = _ease(p / RELEASE) if p <= RELEASE else 1.0 - _ease((p - RELEASE) / 0.3)
		# English yew bows reach above the hood; the Mongol composite bow is
		# shorter. The string sits at the same waist-high grip as the new art.
		var upper := Vector2(10, -29 if civilization == 1 else -25)
		var lower := Vector2(6, -4)
		if civilization == 2:
			upper = Vector2(10, -23)
			lower = Vector2(8, -8)
		var nock := Vector2(9.0 - tension * 4.0, -13)
		draw_line(upper, nock, Color("c9bfa0"), 0.65, true)
		draw_line(nock, lower, Color("c9bfa0"), 0.65, true)
		if p <= RELEASE:
			draw_line(nock, Vector2(17, -13), WOOD, 0.9, true)
	elif action == Action.SIEGE:
		# The painted throwing arm and real projectile already identify this
		# action. A guessed rope over the artwork obscured its simple frame.
		pass
	# Restrained weapon path only at release; accessibility disables it entirely.
	elif not quiet_flashes and not quiet_motion and p > 0.55 and p < 0.83:
		var reach: float = 15.0 if action == Action.MELEE else 21.0
		draw_line(Vector2(6, -16), Vector2(reach, -17), Color(trim, 0.5), 1.0, true)

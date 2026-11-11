extends RefCounted
## Villager cargo badges (food / wood / gold / mixed satchel) as one small
## authored texture (assets/units/cargo_badges.svg, the old vector badge art).
## Each villager shows its badge as a child canvas item drawing one textured
## rect on its own z layer, just under the health bars, so a whole economy's
## badges batch into a draw call or two. Drawn as per-villager shapes they
## cost ~5 draw calls each: 40 working villagers in view measured 332 draw
## calls and 8.2 ms WebGL render per frame, against 107 and 4.7 ms baked.
## Presentation only.

const TEXTURE: Texture2D = preload("res://assets/units/cargo_badges.svg")
const KINDS: Array[String] = ["food", "wood", "gold", "mixed"]
## Texture pixels per badge unit (the badge's own drawing space, before the
## villager's 1.2x badge scale).
const DENSITY: float = 4.0
const CELL: int = 56
## Just under UnitBase.HEALTH_BAR_Z: above the y-sorted world, batched apart
## from the bars (which use the white texture).
const BADGE_Z: int = 5


static func cell_for(kind: String) -> Rect2:
	var index: int = KINDS.find(kind)
	if index < 0:
		index = KINDS.size() - 1
	return Rect2(index * CELL, 0, CELL, CELL)


## Draws the badge for `kind` centred on `item` (its scale is the badge scale
## divided by DENSITY, so one badge unit is DENSITY texture pixels).
static func draw_badge(item: CanvasItem, kind: String) -> void:
	var cell: Rect2 = cell_for(kind)
	item.draw_texture_rect_region(TEXTURE, Rect2(-cell.size * 0.5, cell.size), cell)

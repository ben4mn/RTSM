class_name ResourceNode
extends Area2D
## A harvestable resource in the world (tree, gold mine, berry bush, stone).
## Villagers gather from these nodes and they deplete over time.

## Emitted when the resource is fully depleted and about to be removed.
signal depleted(node: ResourceNode)

## Resource type this node provides: "food", "wood", or "gold".
@export var resource_type: String = "wood"

## Total harvestable amount.
@export var total_amount: int = 300

## How much remains.
var remaining: int = 0

## The tile position this resource sits on.
var tile_position: Vector2i = Vector2i.ZERO

## Original Company field art; all variants share their resource's ground anchor.
const RESOURCE_SPRITES: Dictionary = {
	"food": "res://assets/resources/company_berries.svg",
	"wood": "res://assets/resources/company_oak.svg",
	"gold": "res://assets/resources/company_gold.svg",
	"stone": "res://assets/resources/company_stone.svg",
}
const WOOD_SPRITES: Array[String] = [
	"res://assets/resources/company_oak.svg",
	"res://assets/resources/company_elm.svg",
	"res://assets/resources/company_pine.svg",
]

## Match opaque artwork to people: trees stand twice as tall, bushes waist-high.
## All artwork uses a 128px canvas and retains these calibrated world scales.
const RESOURCE_SCALES: Dictionary = {
	"food": Vector2(.48, .48),
	"wood": Vector2(.72, .72),
	"gold": Vector2(.52, .52),
	"stone": Vector2(.50, .50),
}

## Place the visible root/base on the resource tile, independent of padding.
const RESOURCE_OFFSETS: Dictionary = {
	"food": Vector2(0, -18),
	"wood": Vector2(-1, -44),
	"gold": Vector2(0, -28),
	"stone": Vector2(0, -24),
}

const RESOURCE_COLORS: Dictionary = {
	"food": Color("bd8067"),
	"wood": Color("88a58b"),
	"gold": Color("c4af77"),
	"stone": Color("b2b8b2"),
}

const RESOURCE_BADGES: Dictionary = {
	"food": "F",
	"wood": "W",
	"gold": "G",
	"stone": "S",
}

var _sprite: Sprite2D = null


func _ready() -> void:
	remaining = total_amount
	_setup_collision()
	_setup_sprite()
	_assign_group()
	add_to_group("resources")
	queue_redraw()


func _process(_delta: float) -> void:
	if is_selected:
		queue_redraw()


func _setup_collision() -> void:
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 16.0
	shape.shape = circle
	add_child(shape)


func _setup_sprite() -> void:
	# Contact shade is baked into each vector, so trees add no shadow nodes.
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite"
	var tex_path: String = get_presentation_texture_path()
	if tex_path != "" and ResourceLoader.exists(tex_path):
		_sprite.texture = load(tex_path)
	_sprite.scale = RESOURCE_SCALES.get(resource_type, Vector2(0.25, 0.25))
	_sprite.offset = RESOURCE_OFFSETS.get(resource_type, Vector2(0, -8))
	# Sort by Y position so trees overlap correctly
	_sprite.z_as_relative = true
	# Keep badges, selection rings and resource feedback above the artwork.
	_sprite.show_behind_parent = true
	add_child(_sprite)


func get_presentation_texture_path() -> String:
	# Stable tile variation uses no random generator or synchronized state.
	# Neither map generation nor the simulation's random stream is advanced.
	if resource_type == "wood":
		return WOOD_SPRITES[posmod(tile_position.x * 7 + tile_position.y * 11, WOOD_SPRITES.size())]
	return RESOURCE_SPRITES.get(resource_type, RESOURCE_SPRITES["stone"])


func is_sprite_body_hit(world_position: Vector2) -> bool:
	# A tree's canopy sits well above its ground anchor. Only opaque artwork
	# counts, so transparent texture padding does not swallow nearby targets.
	return resource_type == "wood" and _sprite != null and _sprite.is_pixel_opaque(_sprite.to_local(world_position))


func _assign_group() -> void:
	match resource_type:
		"food":
			add_to_group("food_resources")
		"wood":
			add_to_group("wood_resources")
		"gold":
			add_to_group("gold_resources")


## Returns the resource type string.
func get_resource_type() -> String:
	return resource_type


## Natural resources are neutral, so any player may harvest them while stock remains.
func is_harvestable_by(_gathering_player_id: int = -1) -> bool:
	return remaining > 0


## Harvest up to `amount` from this node. Returns actual amount harvested.
## Removes the node when depleted.
func harvest(amount: int) -> int:
	if remaining <= 0:
		return 0
	var actual := mini(amount, remaining)
	remaining -= actual
	queue_redraw()
	if remaining <= 0:
		depleted.emit(self)
		# Fade out and remove
		var tween := create_tween()
		tween.tween_property(self, "modulate:a", 0.0, 0.5)
		tween.tween_callback(queue_free)
	return actual


var is_selected: bool = false


func select() -> void:
	is_selected = true
	queue_redraw()


func deselect() -> void:
	is_selected = false
	queue_redraw()


func _draw() -> void:
	# The artwork identifies idle resources. Details appear on selection so a
	# grove does not become a wall of floating letters and colored ground dots.
	if is_selected:
		draw_arc(Vector2.ZERO, 20.0, 0, TAU, 32, Color("e8e5db"), 1.5, true)
		if remaining > 0:
			_draw_resource_badge()

	# Selected stock remains readable without permanent bars over the forest.
	if is_selected and remaining < total_amount and remaining > 0:
		var bar_w := 18.0
		var bar_h := 2.0
		var bar_y := 10.0
		var ratio := float(remaining) / float(total_amount)
		# Background
		draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w, bar_h), Color(0.15, 0.15, 0.15, 0.8))
		# Fill
		var bar_color: Color = _get_resource_color()
		draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w * ratio, bar_h), bar_color)


func _get_resource_color(alpha: float = 1.0) -> Color:
	var base: Color = RESOURCE_COLORS.get(resource_type, Color(0.65, 0.68, 0.72))
	base.a = alpha
	return base


func _draw_resource_badge() -> void:
	var badge_pos := Vector2(0.0, -24.0)
	draw_circle(badge_pos, 7.0, Color("293235"))
	draw_arc(badge_pos, 7.0, 0, TAU, 24, _get_resource_color(), 1.0, true)
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var text: String = RESOURCE_BADGES.get(resource_type, "?")
	var fsize: int = maxi(11, ThemeDB.fallback_font_size - 1)
	var text_pos := badge_pos + Vector2(-5.5, 4.0)
	draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_CENTER, 10.0, fsize, Color(0.95, 0.95, 0.95, 0.98))

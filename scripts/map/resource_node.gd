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

## Sprite textures per resource type from Kenney Medieval RTS pack.
const RESOURCE_SPRITES: Dictionary = {
	"food": "res://assets/resources/bush.png",
	"wood": "res://assets/resources/tree_large.png",
	"gold": "res://assets/resources/gold_rocks.png",
	"stone": "res://assets/resources/rock_large.png",
}

## Sprite scale per resource type (sprites are 128x128, need to fit ~30px game size).
const RESOURCE_SCALES: Dictionary = {
	"food": Vector2(0.45, 0.45),
	"wood": Vector2(0.50, 0.50),
	"gold": Vector2(0.48, 0.48),
	"stone": Vector2(0.45, 0.45),
}

## Sprite offset to center the visual on the tile.
const RESOURCE_OFFSETS: Dictionary = {
	"food": Vector2(0, -6),
	"wood": Vector2(0, -16),
	"gold": Vector2(0, -8),
	"stone": Vector2(0, -6),
}

const RESOURCE_COLORS: Dictionary = {
	"food": Color(0.90, 0.30, 0.35),
	"wood": Color(0.35, 0.75, 0.30),
	"gold": Color(0.95, 0.85, 0.20),
	"stone": Color(0.65, 0.68, 0.72),
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
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite"
	var tex_path: String = RESOURCE_SPRITES.get(resource_type, RESOURCE_SPRITES.get("stone", ""))
	if tex_path != "" and ResourceLoader.exists(tex_path):
		_sprite.texture = load(tex_path)
	_sprite.scale = RESOURCE_SCALES.get(resource_type, Vector2(0.25, 0.25))
	_sprite.offset = RESOURCE_OFFSETS.get(resource_type, Vector2(0, -8))
	# Sort by Y position so trees overlap correctly
	_sprite.z_as_relative = true
	add_child(_sprite)


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
	# Selection ring
	if is_selected:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.005)
		var sel_alpha := lerpf(0.3, 0.8, pulse)
		draw_arc(Vector2.ZERO, 18.0, 0, TAU, 32, Color(1.0, 1.0, 1.0, sel_alpha), 2.0)

	# Subtle colored glow circle behind resource
	if remaining > 0:
		var glow_color: Color = _get_resource_color(0.22)
		draw_circle(Vector2.ZERO, 14.0, glow_color)
		_draw_resource_badge()
	# Depletion bar overlay — sprite handles the visual
	if remaining < total_amount and remaining > 0:
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
	var badge_pos := Vector2(0.0, -22.0)
	draw_circle(badge_pos, 7.0, Color(0.02, 0.02, 0.02, 0.75))
	draw_circle(badge_pos, 5.8, _get_resource_color(0.95))
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var text: String = RESOURCE_BADGES.get(resource_type, "?")
	var fsize: int = maxi(10, ThemeDB.fallback_font_size - 2)
	var text_pos := badge_pos + Vector2(-5.0, 3.5)
	draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_CENTER, 10.0, fsize, Color(0.95, 0.95, 0.95, 0.98))

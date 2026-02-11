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
	"food": Vector2(0.35, 0.35),
	"wood": Vector2(0.40, 0.40),
	"gold": Vector2(0.38, 0.38),
	"stone": Vector2(0.35, 0.35),
}

## Sprite offset to center the visual on the tile.
const RESOURCE_OFFSETS: Dictionary = {
	"food": Vector2(0, -6),
	"wood": Vector2(0, -16),
	"gold": Vector2(0, -8),
	"stone": Vector2(0, -6),
}

var _sprite: Sprite2D = null


func _ready() -> void:
	remaining = total_amount
	_setup_collision()
	_setup_sprite()
	_assign_group()
	add_to_group("resources")
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


func _draw() -> void:
	# Only draw the depletion bar overlay — sprite handles the visual
	if remaining < total_amount and remaining > 0:
		var bar_w := 18.0
		var bar_h := 2.0
		var bar_y := 10.0
		var ratio := float(remaining) / float(total_amount)
		# Background
		draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w, bar_h), Color(0.15, 0.15, 0.15, 0.8))
		# Fill
		var bar_color: Color
		match resource_type:
			"food": bar_color = Color(0.85, 0.25, 0.40)
			"wood": bar_color = Color(0.3, 0.65, 0.2)
			"gold": bar_color = Color(0.95, 0.85, 0.15)
			_: bar_color = Color(0.6, 0.6, 0.6)
		draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w * ratio, bar_h), bar_color)

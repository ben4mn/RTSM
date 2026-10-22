extends "res://tools/fixtures/tactical_paid_opening.gd"
var purchases_frozen: bool = false
func _check_military_production() -> void:
	if not purchases_frozen:
		super._check_military_production()

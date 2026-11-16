extends "res://scripts/managers/solo_save.gd"
## Runner-only autoload override. Persistence has separate round-trip tests;
## a pacing simulation must not serialize the whole battlefield every15 seconds.
func _ready() -> void:
	set_process(false)

func attach_match(_main: Node) -> void:
	pass

func _process(_delta: float) -> void:
	pass

func _notification(_what: int) -> void:
	pass

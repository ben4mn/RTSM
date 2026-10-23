extends "res://tools/probe_authority_snapshot.gd"
## Deterministic visibility/lifetime/target equivalence, without timing gates.

func _ready() -> void:
	_verification_only = true
	super._ready()

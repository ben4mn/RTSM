extends "res://tools/probe_ai_compact_paid_match.gd"
## Simulation comparison only: ordinary paid AI transactions for both sides.
func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--workers="):
			Engine.set_meta("balance_starting_villagers", int(argument.trim_prefix("--workers=")))
	super._ready()

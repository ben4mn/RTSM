extends SceneTree
## Scripted online 1v1 client for tools/run_online_tests.py --probe-match; the
## script itself is probe_online_match_node.gd, loaded once autoloads exist
## (a --script SceneTree compiles before their names are known).

func _initialize() -> void:
	call_deferred("_start")

func _start() -> void:
	root.add_child(load("res://tools/probe_online_match_node.gd").new())

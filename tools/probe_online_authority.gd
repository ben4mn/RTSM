extends SceneTree
## Match server for tools/run_online_tests.py --probe-match: the ordinary
## authority (`-- --aoem-server`) plus the audit in probe_online_authority_node.gd.
## A --script SceneTree compiles before autoload names exist, so the audit is
## loaded at run time.

func _initialize() -> void:
	call_deferred("_start")

func _start() -> void:
	root.add_child(load("res://tools/probe_online_authority_node.gd").new())
	change_scene_to_file("res://scenes/network/server_lobby.tscn")

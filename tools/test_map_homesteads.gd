extends Node
## Bounded9-map geometry/resource check. Optional archived generator comparison
## measures the actual previous grid, not a simulated economy or phone framerate.

const SEEDS: Array[int] = [101, 202, 424242]
const FAIRNESS = preload("res://tools/probe_map_opening_fairness.gd")
const STOCK: Dictionary = {4: 200, 2: 250, 3: 400}
var failures: Array[String] = []
var checks: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var output := "res://output/map-homesteads.json"
	var baseline_path := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		if argument.begins_with("--baseline-source="): baseline_path = argument.trim_prefix("--baseline-source=")
	var baseline: Script = load(baseline_path) if not baseline_path.is_empty() else null
	var probe: Node = FAIRNESS.new()
	var reports: Array[Dictionary] = []
	for archetype: int in MapData.MAP_ARCHETYPES:
		for seed_value: int in SEEDS:
			var label := "%s seed%d" % [MapData.get_archetype_name(archetype), seed_value]
			var generator := MapGenerator.new(seed_value, archetype)
			var start_us: int = Time.get_ticks_usec()
			generator.generate()
			var generation_us: int = Time.get_ticks_usec() - start_us
			var replay := MapGenerator.new(seed_value, archetype)
			_expect(generator.grid == replay.generate(), label + " reproducible")
			var measured: Dictionary = _measure(generator)
			measured["generation_us"] = generation_us
			_expect(measured.symmetric, label + " symmetric")
			_expect(measured.sacred_tiles == 4, label + " sacred geometry retained")
			_expect(measured.reachable_fraction >= 0.995, label + " connected land")
			_expect(measured.base_axis_separation == 59, label + " preserves former base separation")
			_expect(measured.home_build_anchors >= 200, label + " roomy4x4 construction options")
			for reserved: Vector2i in generator.get("_route_tiles"):
				_expect(MapData.is_grass(generator.get_tile(reserved)), label + " deposits preserve carved routegrass")
			for side: Dictionary in measured.openings:
				_expect(side.food >= 2400 and side.wood >= 6000 and side.gold >= 1600, label + " dependable revealed stock with twelve starting berry bushes")
			var nav := Pathfinding.new(generator)
			for spawn: Vector2i in generator.spawn_positions: nav.set_area_solid(spawn, Vector2i(4, 4))
			var start_tile: Vector2i = generator.spawn_positions[0] + Vector2i(5, -5)
			for route: Dictionary in generator.get_tactical_routes():
				var points: Array = route.waypoints
				for index: int in range(1, points.size()):
					_expect(not nav.get_tile_path(points[index - 1], points[index]).is_empty(), label + " connected" + str(route.name))
				var crossing: Vector2i = points[1]
				for dy: int in range(-4, 5):
					for dx: int in range(-4, 5):
						_expect(not MapData.is_obstacle(generator.get_tile(crossing + Vector2i(dx, dy))), label + " nine-tile route width")
			for pocket: Vector2i in generator.get_expansion_pocket_centers():
				_expect(not nav.get_tile_path(start_tile, pocket).is_empty(), label + " expansion approach")
				for dy: int in range(-2, 3):
					for dx: int in range(-2, 3):
						_expect(MapData.is_grass(generator.get_tile(pocket + Vector2i(dx, dy))), label + " clear5x5 expansion pad")
				var stock: Dictionary = _stock(generator.grid, pocket, MapGenerator.EXPANSION_CLEAR_RADIUS, false)
				_expect(stock.food == 2400 and stock.wood == 5000 and stock.gold == 1600, label + " expansion stock with twelve berry bushes")
			var fair: Dictionary = probe.call("measure_seed", seed_value, archetype)
			for resource: String in ["food", "wood", "gold"]:
				_expect(float(fair.trip_difference[resource].deposit_seconds) <= 0.60, label + " fair" + resource + " deposit travel")
				for side: Dictionary in fair.sides:
					_expect(side.resources[resource].reachable and side.resources[resource].deposit_reachable, label + " real gather/dropoff path")
			var report := {"seed": seed_value, "archetype": archetype, "name": MapData.get_archetype_name(archetype), "candidate": measured, "opening_routes": fair}
			if baseline != null:
				var old: RefCounted = baseline.new(seed_value, archetype)
				start_us = Time.get_ticks_usec()
				old.call("generate")
				var old_us: int = Time.get_ticks_usec() - start_us
				report["baseline"] = _measure(old)
				report.baseline["generation_us"] = old_us
				report["generation_time_ratio"] = float(generation_us) / maxi(1, old_us)
				report["build_anchor_ratio"] = float(measured.home_build_anchors) / maxi(1, int(report.baseline.home_build_anchors))
			reports.append(report)
	probe.free()
	var result := {"scope": "9 actual generated maps; optional archived generator2; land connectivity, terrain-only4x4 build anchors excluding TC, finite stock, real candidate Pathfinding/GameMap gather and dropoff routes. Wallclock generation is a local diagnostic, not phone FPS or pacing.", "generator_version": MapData.GENERATOR_VERSION, "checks": checks, "failures": failures, "maps": reports}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output).get_base_dir())
	FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
	for failure: String in failures: push_error(failure)
	print("[%s] map_homesteads: %d checks across9 maps; report%s" % ["PASS" if failures.is_empty() else "FAIL", checks, output])
	get_tree().quit(0 if failures.is_empty() else 1)


func _measure(generator: RefCounted) -> Dictionary:
	var grid: Array = generator.get("grid")
	var spawns: Array = generator.get("spawn_positions")
	var width: int = grid[0].size()
	var height: int = grid.size()
	var radius: int = 11 if width == 88 else 6
	var sacred: int = 0
	var symmetric: bool = true
	var total: Dictionary = {"food": 0, "wood": 0, "gold": 0}
	var grass: int = 0
	for y: int in range(height):
		for x: int in range(width):
			var tile_type: int = grid[y][x]
			symmetric = symmetric and tile_type == grid[x][y]
			if tile_type == 6: sacred += 1
			if tile_type in [0, 7, 8]: grass += 1
			if STOCK.has(tile_type): total[_resource_name(tile_type)] += STOCK[tile_type]
	var openings: Array[Dictionary] = []
	for spawn: Vector2i in spawns: openings.append(_stock(grid, spawn, 13, true))
	var anchors: int = 0
	var home: Vector2i = spawns[0]
	for y: int in range(home.y - radius, home.y + radius - 2):
		for x: int in range(home.x - radius, home.x + radius - 2):
			var valid: bool = true
			for dy: int in range(4):
				for dx: int in range(4):
					var tile := Vector2i(x + dx, y + dy)
					if tile.x < 0 or tile.y < 0 or tile.x >= width or tile.y >= height or not grid[tile.y][tile.x] in [0, 7, 8]: valid = false
					if Rect2i(home, Vector2i(4, 4)).has_point(tile): valid = false
			if valid: anchors += 1
	return {"width": width, "height": height, "cells": width * height, "spawn": [home.x, home.y], "base_axis_separation": absi(spawns[1].x - home.x), "symmetric": symmetric, "sacred_tiles": sacred, "grass_tiles": grass, "total_stock": total, "openings": openings, "home_build_anchors": anchors, "reachable_fraction": _connected_fraction(grid, spawns)}


func _stock(grid: Array, center: Vector2i, radius: int, circular: bool) -> Dictionary:
	var result := {"food": 0, "wood": 0, "gold": 0}
	for y: int in range(maxi(0, center.y - radius), mini(grid.size(), center.y + radius + 1)):
		for x: int in range(maxi(0, center.x - radius), mini(grid[0].size(), center.x + radius + 1)):
			if circular and center.distance_squared_to(Vector2i(x, y)) > radius * radius: continue
			var tile_type: int = grid[y][x]
			if STOCK.has(tile_type): result[_resource_name(tile_type)] += STOCK[tile_type]
	return result


func _connected_fraction(grid: Array, spawns: Array) -> float:
	var width: int = grid[0].size()
	var height: int = grid.size()
	var solid: Dictionary = {}
	for spawn: Vector2i in spawns:
		for dy: int in range(4):
			for dx: int in range(4): solid[spawn + Vector2i(dx, dy)] = true
	var start: Vector2i = spawns[0] + Vector2i(5, -5)
	var queue: Array[Vector2i] = [start]
	var visited: Dictionary = {start: true}
	var cursor: int = 0
	while cursor < queue.size():
		var tile: Vector2i = queue[cursor]
		cursor += 1
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = tile + direction
			if next.x < 0 or next.y < 0 or next.x >= width or next.y >= height or visited.has(next) or solid.has(next) or grid[next.y][next.x] == 1: continue
			visited[next] = true
			queue.append(next)
	var walkable: int = 0
	for y: int in range(height):
		for x: int in range(width):
			if grid[y][x] != 1 and not solid.has(Vector2i(x, y)): walkable += 1
	return float(visited.size()) / maxi(1, walkable)


func _resource_name(tile_type: int) -> String:
	return {4: "food", 2: "wood", 3: "gold"}[tile_type]


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition and failures.size() < 100: failures.append(message)

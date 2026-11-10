# Round 2 contracts (Phase 0)

Seams the gameplay streams code against. Nothing here changes balance. Regression: `tools/test_round2_contracts.tscn`.
Registration point for every stream: ONE line in `main._register_match_extensions()` (`scripts/main/main.gd`) that hands `self` to your own file. It runs before a solo save is restored and before the network adapter exists. Tests can append a `Callable(main)` to the static `MatchExtensions.installers` instead.

## 1. Modifier registry (`GameManager`)
`player_modifiers[player_id][key] -> float`, saved in solo checkpoints and replicated to the owning client as `snapshot.modifiers`.
- `get_modifier(player_id, key, default := 0.0) -> float`
- `add_modifier(player_id, key, amount) -> float` additive, returns the total; unknown players and zero amounts are ignored
- `set_modifier(player_id, key, value)` absolute write for level-like keys
- `get_modifier_multiplier(player_id, key) -> float` is `1.0 + total`, for keys that store fractions (+0.2 and +0.15 give x1.35)

| Key | Meaning | Written today by |
|---|---|---|
| `attack`, `armor` | flat unit attack / armor | Forge Weapons, Scale Mail |
| `gather_all` | today a flat amount added to villager gather per tick (Wheelbarrow); B turns it into a fraction | Wheelbarrow |
| `villager_hp` | flat villager max HP | Loom |
| `range_ranged`, `gather_food_farm`, `gather_wood`, `gather_gold`, `carry`, `tower_hp`, `tower_damage` | reserved for B | nobody yet |
| `tier_<unit_type>` | unit line tier, 1 = base; use `set_modifier` | nobody yet |
| `civ_<name>` | civ ability keys (C) | nobody yet |

`get_attack_bonus`, `get_armor_bonus`, `get_gather_bonus`, `get_villager_hp_bonus` and the four `apply_*_upgrade` are thin wrappers. `player_upgrades` is a read-only view in the old shape (writes into it are lost; use the registry).

## 2. Signals (`GameManager`)
Fired on the authority only (solo and match server); clients are driven by snapshots. `duration` is game seconds.
`research_started(player_id, building, research_id, duration)` (emitted today with duration 0.0, just before `research_completed`), `research_cancelled(player_id, building, research_id)`, `research_completed(player_id, research_id)`, `age_advance_started(player_id, target_age, duration)` (emitted today with 0.0, just before `age_advanced`), `age_advance_cancelled(player_id)`, `age_advanced(player_id, new_age)`, `town_bell_changed(player_id, town_center, active)`, `wildlife_claimed(player_id, node)`, `boar_felled(player_id, world_pos)`, `unit_tier_changed(player_id, unit_type, tier)`. The last four and the two `*_cancelled` are declared only; the owning stream emits them.

## 3. Network seam (`main.ext`, protocol 18)
`PROTOCOL` is 18 and stays 18 for all of Round 2; the match server image must be rebuilt at deploy. Any operation without a built-in branch in `network_match.execute_command` goes to `main.ext`; unregistered ones still answer `"Unknown order"`. Before a handler runs: the built-in `_valid_packet`, then a generic bound (at most 16 keys; values are bool, finite number, string of at most 64 chars, or an array of at most 64 finite numbers), then your validator. Failures answer `"Invalid order"`. Operation and section names are `[a-z0-9_]`, at most 48 chars.
```gdscript
# wildlife_director.gd, called as WildlifeDirector.install(main) from main._register_match_extensions()
static func install(main: Node) -> void:
	main.ext.register_command("herd", _herd.bind(main), func(p: Dictionary) -> bool: return p.get("position") is Array)
	main.ext.register_snapshot("wildlife", _rows_for.bind(main), _apply_rows.bind(main))
# Authority. units = sender's own living units from packet.ids; target = any live entity, NOT ownership-checked.
static func _herd(owner: int, packet: Dictionary, units: Array, target: Node2D, position: Vector2, main: Node) -> String:
	return "" if _order_sheep(main, owner, target, position) else "Sheep unavailable"   # "" accepts
static func _rows_for(slot: int, main: Node) -> Variant:   # server, per recipient: JSON-safe, already fog-filtered; null omits
	return _visible_rows(main, slot)
static func _apply_rows(rows: Variant, main: Node) -> void:   # client, every snapshot; owners are server slots
	_sync_replicas(main, rows)
```
Client side: `NetworkSession.send_command("herd", {"ids": [...], "position": [x, y]})`.

## 4. Save seam (`main.ext`, schema 2)
`solo_match_state.gd` is schema 2; schema-1 checkpoints are rejected with "This save belongs to a different game version.". Plain fields still go in the `*_FIELDS` lists. Anything else goes in `data.ext[name]` (a Dictionary):
```gdscript
main.ext.register_save("wildlife", _capture.bind(main), _restore.bind(main), _finalize.bind(main))  # finalize optional
static func _capture(codec: RefCounted, main: Node) -> Dictionary:
	var rows: Array = []
	for node: Node in _nodes(main):   # track() gives the node a saved id, so villager fields pointing at it survive
		rows.append({"id": codec.track(node), "pos": node.global_position, "owner": node.owner_id, "claimer": codec.encode(node.claimer)})
	return {"rows": rows}
static func _restore(saved: Dictionary, codec: RefCounted, main: Node) -> void:
	# All saved buildings/units exist, their fields are not written yet: create nodes and bind() them here.
	for row: Dictionary in saved.rows:
		var node: Node = _spawn(main, row.pos, row.owner)
		codec.bind(int(row.id), node)
		node.claimer = codec.decode(row.claimer)
static func _finalize(saved: Dictionary, codec: RefCounted, main: Node) -> void:
	pass   # runs after every actor, AI and map field is restored
```
`capture` runs after all actors and deposits have identities and before any actor field is encoded. A save without your section never calls `restore`/`finalize`.

## 5. Building context actions
`BuildingBase.get_context_actions(player_id) -> Array[Dictionary]`; each entry is `{id, label, icon, cost, time, progress, disabled_reason}` plus optional `short`, `desc`, `details`, `done`. `icon` is a `res://` path or `""`; `time` is seconds (0 = instant); `progress` is -1 when idle, else 0..1; `disabled_reason` is `""` when usable. Research appears automatically for any building with rows in `TechData.RESEARCH_DEFS` as `research:<id>` (today: the Blacksmith's four). The HUD row (`hud._update_research_buttons`) renders the list as cards (label / desc / cost, "Complete" or a percentage) and emits `building_action_requested(building, action_id)`; `main._on_building_action_requested` runs `building.perform_context_action(0, action_id)` in solo and sends the generic `building_action {target, action}` command online, where the authority runs the same function for the sender. Adding an action needs no HUD, main or network edit:
```gdscript
# garrison.gd, called as Garrison.install(main) from main._register_match_extensions(). Callables must be static.
static func install(_main: Node) -> void:
	BuildingBase.register_context_provider("bell", _actions, _perform)
static func _actions(building: BuildingBase, player_id: int) -> Array:
	if building.building_type != BuildingData.BuildingType.TOWN_CENTER or building.state != BuildingBase.State.ACTIVE: return []
	return [{"id": "bell:toggle", "label": "Town Bell", "icon": "res://assets/ui/bell.svg", "cost": {}, "time": 0.0,
		"progress": -1.0, "disabled_reason": "", "desc": "Villagers take cover"}]
static func _perform(building: BuildingBase, player_id: int, action_id: String) -> String:
	return "" if Garrison.toggle(building) else "No villagers nearby"   # "" = done; the string is shown to the player
```
`perform` runs on the authority only, after owner and `disabled_reason` checks; it must charge any cost itself (`ResourceManager.try_spend`).

## 6. Wildlife (workstream A)
Sheep, deer and boar are `WildlifeNode` harvestables (`scripts/map/wildlife_node.gd`, extends `ResourceNode`, groups `resources` and `wildlife`) owned by `GameMap/WildlifeDirector` (`scripts/main/wildlife_director.gd`). Numbers: `scripts/data/wildlife_data.gd`. Placement: `WildlifePlacement.plan(map_generator, seed)` (a separate pass; `MapData.GENERATOR_VERSION` is 6). Regressions: `tools/test_wildlife_claim`, `test_boar_fight`, `test_wildlife_placement`, `test_wildlife_save`.
- Queries (AI, HUD): `game_map.get_wildlife_for_player(player_id)` owned sheep and their carcasses; `game_map.get_wildlife_nodes(kind := "")` every animal with food left (`"sheep"`, `"deer"`, `"boar"`); `game_map.get_wildlife_director()`. On a node: `kind`, `owner_id` (-1 neutral), `phase` (`ALIVE`/`CARCASS`), `mood` (`CALM`/`ENRAGED`/`RETURNING`), `hp`/`max_hp`, `remaining`, `home_position`, `is_fighting()`, `is_harvestable_by(player_id)`, `get_target()`.
- Gathering is the ordinary `villager.command_gather(node)`. A live boar turns each gather tick into a blow (`absorb_strike`) and bites back through `Villager.take_wildlife_damage()` (no auto-flee). `get_nearest_resource_node` / `get_nearest_reachable_resource_node` never return a live boar and rank owned sheep and open carcasses first, so "gather nearest food" is safe and sensible for both players and the AI.
- Director: `order_herd(owner, [sheep], world_position)`, `set_walk_home(player_id, enabled)` / `is_walk_home_enabled(player_id)`, `WildlifeDirector.of(node)`.
- Seams used: ext commands `herd {sheep: [wildlife_id...], position}` and `hunt {ids, wid}` (a client's gather order on an animal; natural resources stay tile-keyed), ext snapshot `wildlife {rows, walk_home}` (rows fog-filtered per recipient: `[id, kind, x, y, remaining, total, owner, phase, mood, hp, max_hp]`), ext save section `wildlife`, and the Town Center context action `wildlife:walk_home`.
- Signals emitted: `GameManager.wildlife_claimed(player_id, node)` on every claim or theft, `GameManager.boar_felled(player_id, world_pos)` (`player_id` -1 if nobody struck it).

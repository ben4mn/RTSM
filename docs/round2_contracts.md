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

## 6. D1: town bell, garrison, repair, healing (`scripts/buildings/garrison.gd`)
All numbers are constants at the top of `garrison.gd`. Radii are map tiles from the centre of the footprint.
- **API** (static, authority side; the AI calls the same functions): `Garrison.ring(tc)`, `release(tc)` (villagers out, bell off), `toggle(tc)`, `ungarrison(building)` (everyone out), `order_garrison(units, building) -> int`, `order_repair(villagers, building) -> int`, `count(building)`, `bonus_arrows(building)`, `needs_repair(building)`, `tile_distance(building, world_pos)`.
- **State**: a garrisoned unit has `current_state == UnitBase.State.GARRISONED` (appended enum value) and is **outside the scene tree**: not in the `units` group or the spatial index, not drawn, not processed, immune, still in `main._player_units` (so it is saved and counts toward population). Any `command_*` given to it brings it out first. Saved fields: `BuildingBase.garrisoned_ids / bell_active / _bell_quiet / repair_credit / _repair_fraction`, `UnitBase._garrison_target`; ext save section `garrison` only re-hides units after a restore.
- **Player gestures**: the Town Center's one context card (bell icon -> all-clear icon while ringing -> "Out · n in" while soldiers remain); a "Ring town bell" button under the RAID alert cards when a raid front is within bell range of a silent Town Center; **hold** an own Town Center / Watch Tower with soldiers selected -> "Garrison" in the hold menu (desktop: right-click). A villagers-only hold on a drop-off keeps its one-step "Queue drop-off"; villagers shelter by the bell (or by hand in a Watch Tower). Tapping a damaged own building with villagers selected repairs it (same `build_command` / `build` order as construction; Farms excluded).
- **Network**: ext commands `bell {target}`, `ungarrison {target}`, `garrison {ids, target}`, `repair {ids, target}`; the card uses the generic `building_action`. Owner-only ext snapshot section `garrison`: rows `[building id, units inside, bell 0/1, being repaired 0/1]`. The owner keeps receiving garrisoned unit actors (state GARRISONED, hidden client-side); the rival's snapshot drops them (`Garrison.hidden_from_enemy`, one line in `network_match._snapshot_for`).
- **Signal**: `GameManager.town_bell_changed(player_id, town_center, active)` on ring, all-clear, release and when a ringing Town Center falls.

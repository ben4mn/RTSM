extends RefCounted
## Round 2 extension seams. One instance lives on each match as `main.ext`.
## Gameplay streams register callables here instead of editing the network
## adapter (`network_match.gd`) or the solo save codec (`solo_match_state.gd`).
## Full contract with examples: docs/round2_contracts.md.

const MAX_NAME_LENGTH: int = 48
const MAX_PACKET_KEYS: int = 16
const MAX_PACKET_STRING: int = 64
const MAX_PACKET_ARRAY: int = 64
const UNKNOWN_COMMAND: String = "Unknown order"

## Callables run as `installer.call(main)` whenever a match builds its registry,
## after the built-in registrations. Meant for tests and optional modules that
## cannot add their own line to `main._register_match_extensions()`.
static var installers: Array[Callable] = []

var commands: Dictionary = {}  # operation -> {"handler": Callable, "validator": Callable}
var snapshot_providers: Dictionary = {}  # name -> Callable(slot: int) -> Variant
var snapshot_consumers: Dictionary = {}  # name -> Callable(data: Variant) -> void
var save_handlers: Dictionary = {}  # name -> {"capture": Callable, "restore": Callable, "finalize": Callable}


func install(main: Node) -> void:
	## Called once by main before any save is restored or snapshot is built.
	register_command("building_action", building_action_command, valid_building_action)
	for installer: Callable in installers:
		if installer.is_valid():
			installer.call(main)


static func valid_name(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > MAX_NAME_LENGTH:
		return false
	for index: int in value.length():
		var code: int = value.unicode_at(index)
		if not ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95):
			return false
	return true


# --- Network commands --------------------------------------------------------

func register_command(operation: String, handler: Callable, validator: Callable = Callable()) -> bool:
	## handler(owner: int, packet: Dictionary, units: Array[UnitBase],
	##         target: Node2D, position: Vector2) -> String
	## Runs on the authority only. Return "" to accept or a short player-facing
	## rejection reason. `units` are the sender's own living units from
	## packet.ids; `target` is any live entity (null if none) and is NOT
	## ownership-checked; `position` is packet.position or Vector2.ZERO.
	## Optional validator(packet: Dictionary) -> bool rejects malformed packets.
	## Built-in operations of network_match.gd always win over a same-named one.
	if not valid_name(operation) or not handler.is_valid():
		push_error("MatchExtensions: invalid command registration '%s'" % operation)
		return false
	commands[operation] = {"handler": handler, "validator": validator}
	return true


func has_command(operation: String) -> bool:
	return commands.has(operation)


static func valid_packet_shape(packet: Dictionary) -> bool:
	## Generic bound for extension packets: only flat, small, finite values.
	if packet.size() > MAX_PACKET_KEYS:
		return false
	for key: Variant in packet:
		if not key is String or key.length() > MAX_NAME_LENGTH:
			return false
		var value: Variant = packet[key]
		match typeof(value):
			TYPE_BOOL:
				pass
			TYPE_INT, TYPE_FLOAT:
				if not is_finite(float(value)):
					return false
			TYPE_STRING:
				if value.length() > MAX_PACKET_STRING:
					return false
			TYPE_ARRAY:
				if value.size() > MAX_PACKET_ARRAY:
					return false
				for entry: Variant in value:
					if typeof(entry) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(entry)):
						return false
			_:
				return false
	return true


func run_command(operation: String, owner: int, packet: Dictionary, units: Array, target: Node2D, position: Vector2) -> String:
	## Unknown, malformed or stale registrations answer exactly like an
	## unregistered operation did before this seam existed.
	if not commands.has(operation) or not valid_packet_shape(packet):
		return UNKNOWN_COMMAND
	var entry: Dictionary = commands[operation]
	var handler: Callable = entry.handler
	if not handler.is_valid():
		return UNKNOWN_COMMAND
	var validator: Callable = entry.validator
	if validator.is_valid() and validator.call(packet) != true:
		return "Invalid order"
	var result: Variant = handler.call(owner, packet, units, target, position)
	return result if result is String else ""


# --- Network snapshots -------------------------------------------------------

func register_snapshot(name: String, provider: Callable, consumer: Callable = Callable()) -> bool:
	## provider(slot: int) -> Variant runs on the server for each recipient and
	## must return JSON-safe data already filtered to what `slot` may see (null
	## omits the entry). consumer(data: Variant) -> void runs on that client for
	## every snapshot carrying the entry; owners in `data` are server slots.
	if not valid_name(name):
		push_error("MatchExtensions: invalid snapshot name '%s'" % name)
		return false
	if provider.is_valid():
		snapshot_providers[name] = provider
	if consumer.is_valid():
		snapshot_consumers[name] = consumer
	return true


func build_snapshot(slot: int) -> Dictionary:
	var result: Dictionary = {}
	for name: String in snapshot_providers:
		var provider: Callable = snapshot_providers[name]
		if not provider.is_valid():
			continue
		var data: Variant = provider.call(slot)
		if data != null:
			result[name] = data
	return result


func apply_snapshot(data: Variant) -> void:
	if not data is Dictionary:
		return
	for name: String in snapshot_consumers:
		var consumer: Callable = snapshot_consumers[name]
		if data.has(name) and consumer.is_valid():
			consumer.call(data[name])


# --- Solo saves --------------------------------------------------------------

func register_save(name: String, capture: Callable, restore: Callable, finalize: Callable = Callable()) -> bool:
	## capture(codec) -> Dictionary   plain data for `data.ext[name]`.
	## restore(saved: Dictionary, codec) -> void   after buildings/units exist,
	##     before their saved fields are written (create and bind nodes here).
	## finalize(saved: Dictionary, codec) -> void   optional, after every actor,
	##     AI and map field is restored.
	## codec helpers: track(node) -> int, encode(value), bind(saved_id, node),
	## decode(value). A save without this entry never calls restore/finalize.
	if not valid_name(name) or not capture.is_valid() or not restore.is_valid():
		push_error("MatchExtensions: invalid save registration '%s'" % name)
		return false
	save_handlers[name] = {"capture": capture, "restore": restore, "finalize": finalize}
	return true


func capture_saves(codec: RefCounted) -> Dictionary:
	var result: Dictionary = {}
	for name: String in save_handlers:
		var capture: Callable = save_handlers[name].capture
		if not capture.is_valid():
			continue
		var data: Variant = capture.call(codec)
		if data is Dictionary:
			result[name] = data
	return result


func restore_saves(saved: Variant, codec: RefCounted, phase: String = "restore") -> void:
	if not saved is Dictionary:
		return
	for name: String in save_handlers:
		var handler: Callable = save_handlers[name].get(phase, Callable())
		if saved.get(name) is Dictionary and handler.is_valid():
			handler.call(saved[name], codec)


# --- Built-in: building context actions --------------------------------------

static func valid_building_action(packet: Dictionary) -> bool:
	return packet.get("action") is String and not packet.action.is_empty()


static func building_action_command(owner: int, packet: Dictionary, _units: Array, target: Node2D, _position: Vector2) -> String:
	## Generic online route for BuildingBase context actions (research today;
	## bell, reseed and others later). The building re-validates everything.
	if not target is BuildingBase or target.player_owner != owner or target.hp <= 0 or target.state == BuildingBase.State.DESTROYED:
		return "Select your building"
	return (target as BuildingBase).perform_context_action(owner, str(packet.action))

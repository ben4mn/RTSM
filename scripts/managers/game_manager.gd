extends Node
## Global game state manager. Autoloaded as GameManager.
##
## Manages overall game state, player data, age progression, and win conditions.

signal game_state_changed(new_state: int)
signal age_advanced(player_id: int, new_age: int)
signal player_defeated(player_id: int)
signal game_over(winner_id: int)

enum GameState {
	MENU,
	LOADING,
	PLAYING,
	PAUSED,
	GAME_OVER
}

enum WinCondition {
	LANDMARK_DESTRUCTION,
	WONDER_VICTORY,
	SURRENDER
}

const MAX_PLAYERS: int = 2
const MAX_AGE: int = 4
const AGE_NAMES: Array[String] = ["Dark Age", "Feudal Age", "Castle Age", "Imperial Age"]

var current_state: GameState = GameState.MENU
var players: Dictionary = {}  # player_id -> PlayerData dict
var game_time: float = 0.0
var game_speed: float = 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if current_state == GameState.PLAYING:
		game_time += delta * game_speed


func initialize_game(num_players: int = 2) -> void:
	players.clear()
	game_time = 0.0

	for i in range(num_players):
		players[i] = _create_player_data(i)

	set_state(GameState.PLAYING)


func _create_player_data(player_id: int) -> Dictionary:
	return {
		"id": player_id,
		"age": 1,
		"population": 0,
		"population_cap": 5,
		"max_population": 200,
		"is_defeated": false,
		"landmarks_alive": 0,
		"buildings": [],
		"units": [],
	}


func set_state(new_state: GameState) -> void:
	current_state = new_state
	game_state_changed.emit(new_state)

	if new_state == GameState.PAUSED:
		get_tree().paused = true
	elif new_state == GameState.PLAYING:
		get_tree().paused = false


func advance_age(player_id: int) -> bool:
	if not players.has(player_id):
		return false

	var player: Dictionary = players[player_id]
	if player["age"] >= MAX_AGE:
		return false

	player["age"] += 1
	age_advanced.emit(player_id, player["age"])
	return true


func get_player_age(player_id: int) -> int:
	if players.has(player_id):
		return players[player_id]["age"]
	return 1


func get_age_name(age: int) -> String:
	if age >= 1 and age <= AGE_NAMES.size():
		return AGE_NAMES[age - 1]
	return "Unknown Age"


func add_population(player_id: int, amount: int) -> bool:
	if not players.has(player_id):
		return false
	var player: Dictionary = players[player_id]
	if player["population"] + amount > player["population_cap"]:
		return false
	player["population"] += amount
	return true


func remove_population(player_id: int, amount: int) -> void:
	if players.has(player_id):
		players[player_id]["population"] = max(0, players[player_id]["population"] - amount)


func increase_population_cap(player_id: int, amount: int) -> void:
	if players.has(player_id):
		var player: Dictionary = players[player_id]
		player["population_cap"] = min(player["population_cap"] + amount, player["max_population"])


func defeat_player(player_id: int) -> void:
	if not players.has(player_id):
		return

	players[player_id]["is_defeated"] = true
	player_defeated.emit(player_id)

	# Check if only one player remains
	var alive_players: Array = []
	for pid in players:
		if not players[pid]["is_defeated"]:
			alive_players.append(pid)

	if alive_players.size() == 1:
		set_state(GameState.GAME_OVER)
		game_over.emit(alive_players[0])


func check_landmark_victory(player_id: int) -> void:
	## Call when a landmark is destroyed. Checks if the player has lost all landmarks.
	if not players.has(player_id):
		return
	if players[player_id]["landmarks_alive"] <= 0:
		defeat_player(player_id)


func get_formatted_time() -> String:
	var minutes: int = int(game_time) / 60
	var seconds: int = int(game_time) % 60
	return "%02d:%02d" % [minutes, seconds]


func toggle_pause() -> void:
	if current_state == GameState.PLAYING:
		set_state(GameState.PAUSED)
	elif current_state == GameState.PAUSED:
		set_state(GameState.PLAYING)

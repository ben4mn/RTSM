extends FogManager
## Fixture-only full visibility. Main still calls its normal refresh API.

var _fixture_revealed: bool = false


func refresh_visibility_now() -> void:
	if _fixture_revealed:
		return
	if fog_grid.is_empty():
		_init_fog_grid()
	reveal_all()
	_initial_apply_done = false
	_apply_fog_delta()
	_fixture_revealed = true

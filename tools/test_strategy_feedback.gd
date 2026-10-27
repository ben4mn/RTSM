extends Node
## Regression for a production error surviving into an unrelated Workers page.
var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var overview := StrategyOverview.new()
	add_child(overview)
	overview.set_surface("economy")
	overview._set_production_page(true)
	var error := "Need 33 more food to train Warrior"
	overview.show_feedback(error, false)
	overview.update_snapshot({})
	_expect(overview._feedback.text == error, "fresh error survives ordinary resource snapshots")
	overview.set_surface("economy")
	_expect(overview._feedback.text == error, "same context does not clear fresh feedback")
	overview._set_production_page(false)
	_expect(not overview._feedback.text.contains("Warrior") and overview._feedback.tooltip_text.is_empty(), "Workers tab clears unrelated training error and tooltip")
	overview.show_feedback(error, false)
	overview.set_surface("")
	overview.set_surface("economy")
	_expect(not overview._feedback.text.contains("Warrior"), "close/reopen clears stale feedback")
	overview.show_feedback("No idle workers", false)
	overview._choose_source("wood")
	_expect(not overview._feedback.text.contains("No idle"), "changing allocation source clears previous context")
	overview.show_feedback(error, false)
	overview._feedback_until_msec = maxi(1, Time.get_ticks_msec() - 1)
	overview.update_snapshot({"food_attention_ready": true, "workers": {"wood": 3}, "economy": {"stock": "346 food"}})
	_expect(not overview._feedback.text.contains("Warrior"), "expired error clears even without navigation")
	_expect(overview._summary.text.begins_with("No food income"), "worker alert distinguishes food income from stored food")
	overview.free()
	if failures.is_empty(): print("[PASS] strategy_feedback: fresh feedback, context switches, expiry, food-income wording")
	else:
		for failure: String in failures: push_error("[FAIL] strategy_feedback: " + failure)
	get_tree().quit(0 if failures.is_empty() else 1)


func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

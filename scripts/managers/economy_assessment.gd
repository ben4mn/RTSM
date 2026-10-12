class_name EconomyAssessment
extends RefCounted
## Explain observed economic facts without issuing orders or changing the bank.


static func describe(facts: Dictionary) -> Dictionary:
	var workers: int = int(facts.get("workers", 0))
	var recovering: int = int(facts.get("recovering", 0))
	var queued: int = int(facts.get("queued_workers", 0))
	var food: int = int(facts.get("food", 0))
	var refund_food: int = int(facts.get("refund_food", 0))
	var room_after_refunds: int = int(facts.get("population_room_after_refunds", 1))
	var worker_cost: int = int(UnitData.get_unit_cost(UnitData.UnitType.VILLAGER).get("food", 50))
	var farm_wood: int = int(BuildingData.get_building_cost(BuildingData.BuildingType.FARM).get("wood", 75))
	var total_visible: int = int(facts.get("visible_food", 0))
	var worked_food: int = int(facts.get("worked_food", 0))
	var food_workers: int = int(facts.get("food_workers", 0))
	var stock: String = "Known food: %d visible berries + %d in your Farms, still to gather." % [int(facts.get("berry_food", 0)), int(facts.get("farm_food", 0))]
	var farm: String = "Farm: %d wood → %d finite food. A worker builds and gathers; rebuild when exhausted." % [farm_wood, BuildingData.FARM_FOOD_AMOUNT]
	var result: Dictionary = {"title": "Economy", "detail": "", "stock": stock, "farm": farm, "attention": "", "severity": 0}
	if workers == 0:
		result["severity"] = 2
		if queued > 0:
			result["title"] = "Replacement already paid"
			result["detail"] = "%d Villager(s) in the paid queue. Keep that producer safe; cancelling returns their cost." % queued
			result["attention"] = "Worker paid"
		elif not bool(facts.get("active_worker_producer", false)):
			result["title"] = "Economy cannot restart"
			result["detail"] = "No workers or active Town Center to train one. Your army can still fight. Pause → Quit to Main Menu to start again."
			result["attention"] = "No workers"
		elif food + refund_food < worker_cost:
			result["title"] = "Economy cannot restart"
			result["detail"] = "No workers or paid replacements. A Villager costs %d food; bank %d + refundable food %d is insufficient. Your army can still fight. Pause → Quit to Main Menu to start again." % [worker_cost, food, refund_food]
			result["attention"] = "Lost economy"
		elif food < worker_cost:
			result["title"] = "Recover through a paid refund"
			result["detail"] = "A Villager costs %d food. Bank %d + refundable food %d can fund one. Refund enough paid units below, then train a Villager. Clear & stop also disables Repeat and releases paid population slots." % [worker_cost, food, refund_food]
			if room_after_refunds <= 0:
				result["detail"] = "A Villager costs %d food. Bank %d + refundable food %d covers its cost, but living units fill available population. Refunds cannot open a slot; a living-unit slot must also open before training." % [worker_cost, food, refund_food]
			result["attention"] = "Refund!"
		else:
			result["title"] = "Rebuild your workforce"
			result["detail"] = "Train a Villager below for %d food. Protect it while gathering." % worker_cost
			if int(facts.get("free_population", 1)) <= 0:
				result["detail"] += " Clear a paid queue to release its reserved slots first." if int(facts.get("reserved_population", 0)) > 0 and room_after_refunds > 0 else " Living units fill population; refunds cannot open a slot. A living-unit slot must open before training."
			result["attention"] = "Train worker"
		return result
	if recovering > 0 and food_workers == 0:
		result["title"] = "Workers sheltering from danger"
		result["detail"] = "%d of %d workers are recovering. Protect their work area; they resume their saved jobs when safe. Reassignment leaves recovering workers alone." % [recovering, workers]
		result["attention"] = "Sheltering"
		result["severity"] = 1
	elif food_workers == 0:
		result["title"] = "No workers on food"
		result["detail"] = "Choose Idle, Wood or Gold below, then To food. This uses a currently visible, reachable source." if total_visible > 0 else "No food source is currently visible. Scout berries, or spend %d wood on a Farm and assign a worker." % farm_wood
		result["attention"] = "No food!"
		result["severity"] = 1
	elif worked_food > 0 and worked_food <= maxi(worker_cost, food_workers * worker_cost):
		result["title"] = "Worked food is running low"
		result["detail"] = "%d food remains across the sources worked by %d food workers. Scout another source or plan a %d-wood Farm before they exhaust. Workers can retarget visible reachable food." % [worked_food, food_workers, farm_wood]
		result["attention"] = "Food low!"
		result["severity"] = 1
	else:
		result["title"] = "Keep food and wood staffed"
		result["detail"] = "%d workers alive. Villagers cost %d food; save %d wood for the next Farm. Paid queues below show the exact reason training is waiting." % [workers, worker_cost, farm_wood]
	if workers <= 2:
		result["detail"] = "Protect your last %d worker(s). " % workers + str(result["detail"])
		if str(result["attention"]).is_empty():
			result["attention"] = "Workers %d!" % workers
		result["severity"] = maxi(1, int(result["severity"]))
	return result

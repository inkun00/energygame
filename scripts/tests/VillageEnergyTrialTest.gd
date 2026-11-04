extends SceneTree

const MODEL = preload("res://scripts/core/VillageEnergyTrial.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("[FAIL] " + message)

func _near(value: float, expected: float, message: String, tolerance: float = 0.0001) -> void:
	_check(absf(value - expected) <= tolerance, "%s: %.6f vs %.6f" % [message, value, expected])

func _all_mode(state: Dictionary, mode: String) -> void:
	for index in range(state["player_count"]):
		MODEL.set_mode(state, index, mode)

func _ideal(ids: Array, count: int = 4) -> Dictionary:
	var state: Dictionary = MODEL.create_state(ids, count)
	_all_mode(state, "store")
	MODEL.advance(state, 20.0)
	_all_mode(state, "supply")
	MODEL.advance(state, 20.0)
	return state

func _conserved(state: Dictionary, label: String) -> void:
	_near(state["total_generation"], state["total_delivered"] + state["battery"] + state["total_loss"] + state["total_curtailed"], label + " generation is supplied, stored, lost or unused")
	_near(state["total_charge_input"], state["total_stored"] + state["total_loss"], label + " charging loss is accounted for")
	_near(state["total_stored"], state["battery"] + state["total_discharged"], label + " battery cannot provide uncharged energy")
	for player: Dictionary in state["players"]:
		_check(player["battery"] >= 0.0 and player["battery"] <= player["capacity"], label + " charge is within capacity")
		_check(player["total_delivered"] <= player["total_demand"] + 0.0001, label + " delivery never exceeds demand")
		_near(player["total_generation"], player["total_delivered"] + player["battery"] + player["total_loss"] + player["total_curtailed"], label + " each district conserves energy")

func _run() -> void:
	var empty: Dictionary = MODEL.create_state([])
	_check(empty["phase"] == "day" and empty["players"].size() == 4, "four equal districts start by day")
	_near(empty["phase_remaining"], 20.0, "first phase lasts twenty seconds")
	_check(empty["players"][0]["mode"] == "supply", "players must choose to save surplus")
	MODEL.advance(empty, 1000.0)
	_check(MODEL.is_complete(empty) and not empty["success"], "no facilities cannot light the village")
	_near(empty["elapsed"], 40.0, "a large frame is clamped to the end")
	_near(empty["coverage"], 0.0, "no electricity is invented")
	_conserved(empty, "empty village")

	var solar: Dictionary = _ideal([0])
	_near(solar["daytime_coverage"], 1.0, "solar directly meets daytime demand without a battery")
	_near(solar["night_coverage"], 0.0, "solar produces no electricity in darkness")
	_near(solar["generation"], 0.0, "night display has no solar generation")
	_near(solar["capacity"], 0.0, "solar does not secretly include storage")
	_check(not solar["success"], "daytime excess alone cannot light the night")

	var battery_only: Dictionary = _ideal([3])
	_near(battery_only["capacity"], 100.0, "a storage facility provides finite capacity")
	_near(battery_only["total_generation"], 0.0, "a battery is not a generator")
	_near(battery_only["total_delivered"], 0.0, "empty storage cannot supply electricity")
	_conserved(battery_only, "battery without a generator")

	var matched: Dictionary = MODEL.create_state([0, 3])
	_all_mode(matched, "store")
	MODEL.advance(matched, 20.0)
	_check(matched["phase"] == "night", "the phase changes exactly at twenty seconds")
	_near(matched["battery"], 90.0, "only surplus is stored, with charging loss")
	_near(matched["total_delivered"], 60.0, "current daytime needs are served before charging")
	_near(matched["light_ratio"], 0.0, "staying in store mode leaves the night unpowered")
	_all_mode(matched, "supply")
	_near(matched["light_ratio"], 1.0, "supply restores lights immediately")
	MODEL.advance(matched, 20.0)
	_check(matched["success"], "solar and storage succeed with the two useful decisions")
	_near(matched["coverage"], 1.0, "solar and storage cover all demand")
	_near(matched["battery"], 10.0, "night demand uses only the necessary stored energy")
	_conserved(matched, "solar and storage")

	var forgotten: Dictionary = MODEL.create_state([0, 3])
	MODEL.advance(forgotten, 40.0)
	_check(not forgotten["success"], "never saving daylight surplus fails at night")
	_near(forgotten["battery"], 0.0, "supply mode does not silently charge")
	var held: Dictionary = MODEL.create_state([0, 3])
	_all_mode(held, "store")
	MODEL.advance(held, 40.0)
	_check(not held["success"], "never releasing saved energy fails at night")
	_near(held["battery"], 90.0, "stored energy is retained until supplied")
	var three: Dictionary = MODEL.create_state([0, 3])
	for index in range(3):
		MODEL.set_mode(three, index, "store")
	MODEL.advance(three, 20.0)
	_all_mode(three, "supply")
	MODEL.advance(three, 20.0)
	_near(three["night_coverage"], 0.75, "each player's district contributes equally")
	_check(not three["success"], "three districts cannot hide the fourth district's outage")

	var wind: Dictionary = _ideal([1, 3])
	_check(wind["success"], "forecast wind plus storage is a second viable combination")
	_near(wind["night_coverage"], 0.95, "weaker wind leaves a small deficit after storage runs out")
	_near(wind["battery"], 0.0, "empty storage stops discharging")
	_near(wind["discharging"], 0.0, "empty battery display stops the output flow")
	_conserved(wind, "depleted storage")
	_check(_ideal([2, 4])["success"], "reduced demand plus steady hydro can succeed without a battery")
	_check(_ideal([0, 6])["success"], "complementary generation can succeed without a battery")
	_check(_ideal([0, 3, 4])["success"], "the practical solar hydro storage fixture succeeds")
	_check(_ideal([0, 3, 9])["success"], "daytime electric bus charging fits a viable plan")

	var expected_day := [8.0, 5.0, 0.0, 0.0, 3.2, 2.8, 1.0, 2.5, 0.0, 0.0]
	var expected_night := [0.0, 2.0, 0.0, 0.0, 3.2, 2.8, 4.0, 2.5, 0.0, 0.0]
	for id in range(10):
		var preview: Dictionary = MODEL.forecast([id])
		_near(preview["day_generation"], expected_day[id], "facility %d day output" % id)
		_near(preview["night_generation"], expected_night[id], "facility %d night output" % id)
		var result: Dictionary = _ideal([id])
		_near(preview["coverage"], result["coverage"], "facility %d preview matches actual choices" % id)
		_conserved(result, "facility %d" % id)
	_near(MODEL.forecast([2])["night_demand"], 3.0, "efficient buildings reduce demand instead of generating")
	_near(MODEL.forecast([8])["day_demand"], 2.75, "reused materials reduce manufacturing demand")
	_near(MODEL.forecast([9])["day_demand"], 3.75, "electric buses require charging electricity")
	_check(MODEL.forecast([7])["has_nuclear"], "nuclear is identifiable separately from renewable generation")

	var clean: Dictionary = MODEL.create_state([0, 0, 3, -1, 10, "0", 1.2])
	_check(clean["built_ids"] == [0, 3], "duplicate and invalid facility IDs cannot create free generation")
	var unchanged: Dictionary = clean.duplicate(true)
	_check(not MODEL.set_mode(clean, -1, "store") and not MODEL.set_mode(clean, 4, "store"), "invalid district indexes are rejected")
	_check(not MODEL.set_mode(clean, 0, "generate"), "unknown actions are rejected")
	for delta in [-1.0, 0.0, INF, NAN]:
		MODEL.advance(clean, delta)
	_check(clean == unchanged, "invalid inputs leave simulation state unchanged")
	_check(MODEL.create_state([], 0)["players"].size() == 1 and MODEL.create_state([], 99)["players"].size() == 4, "district count stays in supported bounds")
	var completed: Dictionary = matched.duplicate(true)
	MODEL.advance(matched, 100.0)
	_check(not MODEL.set_mode(matched, 0, "store") and matched == completed, "completed results cannot be rewritten")

	var split: Dictionary = MODEL.create_state([0, 1, 3, 4, 6])
	var large: Dictionary = split.duplicate(true)
	_all_mode(split, "store")
	_all_mode(large, "store")
	for index in range(160):
		MODEL.advance(split, 0.25)
	MODEL.advance(large, 40.0)
	for field in MODEL.TOTAL_FIELDS + ["battery", "coverage", "night_coverage"]:
		_near(split[field], large[field], "large delta equals small frames: " + field)
	_near(large["battery"], large["capacity"], "excess generation cannot overfill storage")
	_conserved(large, "full storage")
	for count in range(1, 5):
		var equal: Dictionary = _ideal([0, 3], count)
		_near(equal["coverage"], matched["coverage"], "player count does not change shared village difficulty")
		for player: Dictionary in equal["players"]:
			_near(player["total_delivered"], float(equal["total_delivered"]) / count, "identical choices receive equal power")
		_conserved(equal, "%d districts" % count)

	# All possible facility selections: conservation and no perpetual batteries,
	# including deficits, full storage, demand reductions and mixed generators.
	for mask in range(1024):
		var ids: Array = []
		for id in range(10):
			if mask & (1 << id):
				ids.append(id)
		var state: Dictionary = _ideal(ids)
		_near(state["total_generation"], state["total_delivered"] + state["battery"] + state["total_loss"] + state["total_curtailed"], "selection %d conserves electricity" % mask)
		_check(state["battery"] >= 0.0 and state["battery"] <= state["capacity"], "selection %d cannot overcharge or create debt" % mask)
		_check(state["total_discharged"] <= state["total_stored"] + 0.0001, "selection %d cannot discharge uncharged energy" % mask)

	if failures.is_empty():
		print("[PASS] VillageEnergyTrialTest: %d checks" % checks)
		quit(0)
	else:
		printerr("[FAIL] VillageEnergyTrialTest: %d/%d checks failed" % [failures.size(), checks])
		quit(1)

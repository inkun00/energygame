extends SceneTree

const INPUT = preload("res://scripts/minigames/MiniGameInput.gd")
const FIELDS := {"solar_align":"solar_arcade", "wind_rhythm":"wind_arcade", "grid_balance":"grid_arcade", "standby_hunt":"standby_arcade", "hydro_gate":"hydro_arcade", "energy_sort":"sort_arcade", "battery_relay":"battery_arcade", "eco_commute":"commute_arcade", "heat_leak":"heat_arcade"}
var gm: Node
var modal: Node
var failures: Array[String] = []
var observations: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func _round(id: String) -> Node:
	modal.cancel_minigame()
	gm.stop_game()
	var configs: Array[Dictionary] = []
	for i in range(4): configs.append({"name":"Learning %d" % i,"is_ai":false})
	gm.setup_game(configs, 600)
	gm.set_process(false)
	var data: Dictionary = gm.MINIGAME_DEFINITIONS[id].duplicate(true)
	data.merge({"seed":31, "round_id":1, "phase":"playing"}, true)
	gm.active_minigame = data.duplicate(true)
	gm.minigame_time_remaining = float(data.get("duration",30.0)) + 1.0
	modal._on_minigame_started(data)
	modal._begin_local_round()
	modal.set_process(false)
	var arcade: Node = modal.get(FIELDS[id])
	arcade.set_process(false)
	arcade.set_physics_process(false)
	return arcade

func _record(label: String) -> void:
	if label in ["selected sun-facing panels","align then brake on storm","adjust and stabilize twice","classify six sources","store; refuse sunny supply; supply on cloud","disconnect two idle devices","open high water and generate","compare solo and shared trip","close two open windows"]:
		_check(gm.has_minigame_goal_actions(modal.game_id,modal.score,modal._submission_stats()), modal.game_id + ": normal goal path qualifies for reward")
	observations.append({"game":modal.game_id,"scenario":label,"score":modal.score,"correct":modal.correct,"attempts":modal.attempts,"metrics":modal._learning_metrics_snapshot()})

func _run() -> void:
	gm = root.get_node("GameManager")
	ProjectSettings.set_setting("network/room_directory_url", "")
	OS.set_environment("ENERGYGAME_ROOM_DIRECTORY_URL", "")
	modal = load("res://scenes/MiniGameModal.tscn").instantiate()
	root.add_child(modal)
	await process_frame
	for id in FIELDS:
		var idle := _round(id)
		if id == "solar_align":
			idle.hero_body.position.x = idle.LANES[idle._correct_lane_for_current_sun()]
			idle._resolve_panel_gate(idle.panel_gates[0])
		else:
			for tick in range(1200 if id == "eco_commute" else 600): idle._process(0.05)
		_check(modal.score == 0 and modal.correct == 0, "%s: no action must earn no goal record or score" % id)
		_record("no action")
	var a := _round("solar_align")
	a.lane_choice_made = true
	for gate in a.panel_gates.slice(0,3):
		a.hero_body.position.x = a.LANES[a._correct_lane_for_current_sun(gate)]
		a._resolve_panel_gate(gate)
	_check(modal.correct == 3 and modal.score == 300, "solar: three selected sun-facing panels")
	_record("selected sun-facing panels")
	a = _round("solar_align")
	a.lane_choice_made = true
	for index in range(30):
		a.sun.position = a.SUN_POSITIONS[index % 3]
		a.hero_body.position.x = a.LANES[0]
		a._spawn_panel_gate(-30.0)
		a._resolve_panel_gate(a.panel_gates.back())
	_check(not gm.has_minigame_goal_actions("solar_align",modal.score,{"correct":modal.correct,"attempts":modal.attempts,"concept_attempts":modal.correct+int(modal.learning_counts.get("solar_wrong",0))}), "solar: staying on one side does not meet the choice criterion")
	_record("fixed left while sun changes")
	a = _round("wind_rhythm")
	INPUT.set_touch(KEY_SPACE, true)
	for tick in range(600): a._process(0.05)
	_check(modal.score == 0 and modal.correct == 0, "wind: permanent brake is not a goal action")
	_record("hold brake throughout")
	a = _round("wind_rhythm")
	a._apply_yaw_input(1.0,0.05)
	a.turbine_yaw = a.wind_angle
	a._score_aligned_generation(0.35,a._alignment_efficiency())
	a.storm_phase = true
	a.phase_scored = false
	a.brake_active = false
	a._update_brake_input(true)
	_check(modal.correct == 2 and modal.score > 75, "wind: alignment then newly chosen storm brake")
	_record("align then brake on storm")
	modal._submit_score()
	_check(gm.minigame_scores[0]["stats"]["correct"] == 1, "wind: report one pair of alignment and storm decisions")
	a = _round("grid_balance")
	a.demand = 60.0
	a.demand_target = 60.0
	a.supply = 60.0
	a._process(1.1)
	_check(modal.score == 0, "grid: lucky initial equality is not a decision")
	a._apply_supply_input(1.0,0.05)
	a.supply = 60.0
	a._process(1.1)
	a._process(1.1)
	modal.score = a.get_balance_score()
	_check(modal.score == a.BALANCE_SCORE_MAX and modal.correct == 1, "grid: perfect full-time balance earns maximum score and one goal record")
	a._start_demand_phase(false)
	a._apply_supply_input(-1.0,0.05)
	a.demand = 60.0
	a.demand_target = 60.0
	a.supply = 60.0
	a._process(1.1)
	modal.score = a.get_balance_score()
	_check(modal.score == a.BALANCE_SCORE_MAX and modal.correct == 2, "grid: next balanced demand adds a goal record without arbitrary score units")
	_record("adjust and stabilize twice")
	a = _round("energy_sort")
	a.current_source = a.SOURCES[3].duplicate(true)
	for retry in range(10): a._deliver(0)
	_check(a.item_step == 0 and modal.score == 0 and modal.correct == 0, "sort: one direction cannot advance past an incorrect item")
	a._deliver(1)
	_check(a.item_step == 1 and modal.score == 0 and modal.correct == 0, "sort: corrected answer is practice without another prize")
	_record("repeat wrong side, then correct it")
	a = _round("energy_sort")
	for item in range(6): a._deliver(int(a.current_source["kind"]))
	_check(modal.score == 540 and modal.correct == 6, "sort: all six first choices score normally")
	_record("classify six sources")
	a = _round("battery_relay")
	_check(a.battery_units == 0, "battery: start empty to connect charging and supply")
	a.hero_x = a.SOLAR_X
	a._try_station_action()
	a.hero_x = a.BATTERY_X
	a._try_station_action()
	_check(modal.score == 20 and modal.correct == 0, "battery: storage is progress, not a completed supply")
	a.elapsed = 5.1
	a._try_station_action()
	a.hero_x = a.CITY_X
	a.elapsed = 10.1
	a._try_station_action()
	_check(modal.score == 20 and a.cargo == 2, "battery: do not spend stored energy when sunlight is sufficient")
	a.elapsed = 15.1
	a._try_station_action()
	_check(modal.score == 100 and modal.correct == 1 and a.cargo == 0, "battery: stored energy supplies a shortage")
	_record("store; refuse sunny supply; supply on cloud")
	a = _round("battery_relay")
	a.hero_x = -1.0
	a.cargo = 1
	INPUT.set_touch(KEY_D,true)
	a._process(0.3)
	INPUT.release_all()
	_check(modal.score == 20 and a.cargo == 0 and a.battery_units == 1, "battery: a coarse frame crossing the station still stores one unit")
	_record("cross storage on a slow frame")
	a = _round("standby_hunt")
	var saved := 0
	for device in a.device_records:
		if bool(device["waste"]):
			a._resolve_device(device,true)
			saved += 1
			if saved == 2: break
	_check(modal.correct == 2 and a.saved_watts > 0, "standby: select idle devices")
	_record("disconnect two idle devices")
	a = _round("hydro_gate")
	a.selected_gate = 0
	a.water_level = 75.0
	for tap in range(3): a._tap_selected_gate()
	a._advance_simulation(0.5)
	_check(a.open_gate == 0 and modal.correct == 1 and modal.score > 0, "hydro: three taps open a water-covered gate at high water")
	_check(not gm.has_minigame_goal_actions("hydro_gate",modal.score,modal._submission_stats()), "hydro: opening without managing closure is incomplete")
	a._close_open_gate(true)
	_check(a.managed_closures == 1, "hydro: close a generating gate to collect water again")
	_record("open high water and generate")
	a.water_level = 100.0
	a._overflow()
	modal._submit_score()
	_check(int(gm.minigame_scores[0]["stats"]["correct"]) == 0, "hydro: an overflow is not a successful management record")
	a = _round("eco_commute")
	a.passengers = 1
	a.route_distance = 56.0
	a._unload_at_school(56.0)
	_check(modal.correct == 0, "bus: a solo ride does not demonstrate sharing")
	a.passengers = 15
	a._unload_at_school(56.0)
	_check(modal.correct == 1 and a.last_trip_per_person < a.last_trip_solo_energy, "bus: shared ride lowers energy per person")
	_record("compare solo and shared trip")
	a = _round("heat_leak")
	for index in a.wave_positions(31,0).slice(0,2):
		a.hero_x = a.WINDOW_X[index]
		a._try_close()
	_check(modal.correct == 2 and a._open_window_count() == 1, "heat: close open windows only")
	_record("close two open windows")
	_round("hydro_gate")
	# Touch buttons use the same held state, allow simultaneous actions and clear at stop.
	modal.touch_controls.get_child(0).get_child(2).pressed.emit()
	modal.touch_controls.get_child(2).get_child(2).pressed.emit()
	_check(INPUT.is_pressed(KEY_LEFT) and INPUT.is_pressed(KEY_W), "touch: simultaneous movement and jump")
	modal._set_arcades_running(false)
	_check(not INPUT.is_pressed(KEY_A) and not INPUT.is_pressed(KEY_W), "touch: no stuck input after stopping")
	_round("solar_align")
	for i in range(4): gm.submit_minigame_score(i,0,{"correct":0,"attempts":0,"best_streak":0},1)
	for result in gm.active_minigame["results"]:
		_check(result["rank"] == 0 and result["reward"] == 0 and not result["goal_checked"], "all zero: no winner or reward")
	_check("solar_align" in gm.completed_minigame_ids, "all zero: a finished round still must not repeat on the board")
	_round("solar_align")
	for i in range(4): gm.submit_minigame_score(i,300,{"correct":3,"attempts":3,"best_streak":3},1)
	_check("solar_align" in gm.completed_minigame_ids, "all humans with goal actions: mark completed")
	for result in gm.active_minigame["results"]: _check(result["reward"] == 20, "valid positive tie still awards shared first")
	_round("solar_align")
	gm.players[1]["is_ai"] = true
	gm.players[2]["is_ai"] = true
	gm.players[3]["is_ai"] = true
	gm.submit_minigame_score(0,0,{"correct":0,"attempts":0,"best_streak":0},1)
	for i in range(1,4): gm.submit_minigame_score(i,300,{"correct":3,"attempts":3,"best_streak":3},1)
	_check("solar_align" in gm.completed_minigame_ids, "AI round: finished activity is consumed even when the human earns no reward")
	_check(not gm.active_minigame["results"].filter(func(result): return int(result["player_idx"]) == 0)[0]["goal_checked"], "AI actions must not qualify the human for a reward")
	a = _round("grid_balance")
	for player_index in range(4):
		var ai_score: int = gm._generate_ai_minigame_score(player_index)
		_check(ai_score > 0 and ai_score <= a.BALANCE_SCORE_MAX, "grid AI: use full-round error score within the human score range")
		_check(gm._last_ai_minigame_stats["correct"] >= 0 and gm._last_ai_minigame_stats["attempts"] >= gm._last_ai_minigame_stats["correct"], "grid AI: submit measured goal records rather than deriving them from score")
	var report_path := OS.get_environment("ENERGYGAME_LEARNING_REPORT")
	if not report_path.is_empty():
		var report := FileAccess.open(report_path,FileAccess.WRITE)
		report.store_string(JSON.stringify({"method":"Controlled scenes and touch signal injection, not student play", "observations":observations,"failures":failures},"\t"))
	modal.queue_free()
	gm.stop_game()
	await process_frame
	print("Learning rules: %d observations; %d failures" % [observations.size(),failures.size()])
	quit(0 if failures.is_empty() else 1)

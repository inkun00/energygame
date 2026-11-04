extends SceneTree

const INPUT = preload("res://scripts/minigames/MiniGameInput.gd")
const FIELDS := {
	"solar_align": ["sun_position_index", "panel_gate_index", "lane_choice_made"],
	"wind_rhythm": ["phase_index", "turbine_yaw", "wind_angle", "wind_speed"],
	"grid_balance": ["demand", "supply", "measurement_time", "gap_integral"],
	"standby_hunt": ["saved_watts", "lap_index", "play_elapsed"],
	"hydro_gate": ["water_level", "open_gate", "generated_kwh", "elapsed"],
	"energy_sort": ["item_step", "hero_x", "retrying_item"],
	"battery_relay": ["battery_units", "cargo", "elapsed"],
	"eco_commute": ["passengers", "bus_x", "bus_speed", "elapsed", "delivered_total"],
	"heat_leak": ["cooling_used", "elapsed", "hero_x"]
}
var failures: Array[String] = []
var gm: Node
var modal: Node

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _snapshot(id: String, arcade: Node) -> Array:
	var result: Array = []
	for field in FIELDS[id]:
		result.append(arcade.get(field))
	return result

func _tap(arcade: Node, key: Key) -> void:
	INPUT.set_touch(key, true)
	arcade._process(1.0 / 60.0)
	INPUT.release_all()
	arcade._process(1.0 / 60.0)

func _exercise(id: String, a: Node) -> void:
	# Controlled starting positions exercise real actions and emitted outcomes.
	# They are regression tests, not a claim of human/student playtesting.
	match id:
		"solar_align":
			a.lane_choice_made = true
			for gate in a.panel_gates.slice(0, 2):
				a.hero_body.position.x = a.LANES[a._correct_lane_for_current_sun(gate)]
				a._resolve_panel_gate(gate)
		"wind_rhythm":
			a._apply_yaw_input(1.0, 0.05)
			a.turbine_yaw = a.wind_angle
			a._score_aligned_generation(0.35, a._alignment_efficiency())
			a.storm_phase = true
			a.phase_scored = false
			a.brake_active = false
			_tap(a, KEY_SPACE)
		"grid_balance":
			for index in range(2):
				a._start_demand_phase(false)
				a.demand = 60.0
				a.demand_target = 60.0
				a.supply = 60.0
				_tap(a, KEY_W)
				a._process(1.1)
		"standby_hunt":
			var saved := 0
			for device in a.device_records:
				if device["waste"]:
					a._resolve_device(device, true)
					saved += 1
					if saved == 2: break
		"hydro_gate":
			a.hero_x = a.LEVER_X[0]
			a._update_station()
			for tap in range(3): _tap(a, KEY_SPACE)
			a._advance_simulation(0.5)
			_tap(a, KEY_E)
		"energy_sort":
			a._deliver(1 - int(a.current_source["kind"]))
			_check(modal.practice_plan.step == 0, "sort practice: an incorrect choice never advances the mission")
			for item in range(2): a._deliver(int(a.current_source["kind"]))
		"battery_relay":
			a.hero_x = a.SOLAR_X
			a._try_station_action()
			a.hero_x = a.BATTERY_X
			a._try_station_action()
			a.elapsed = 5.1
			a._try_station_action()
			a.hero_x = a.CITY_X
			a._try_station_action()
		"eco_commute":
			a.bus_x = float(a.segments[0]["stops"][0]["x"])
			a.bus_speed = 0.0
			a._animate_students(0.0)
			_tap(a, KEY_SPACE)
			_check(a.passengers >= 2, "bus practice: actual pickup collects at least two students")
			a.bus_x = float(a.segments[0]["school_x"])
			_tap(a, KEY_S)
			_check(not modal.practice_plan.progress(a)["complete"], "bus: do not cover the school entrance animation with completion")
			for tick in range(300): a._process(1.0 / 60.0)
		"heat_leak":
			for index in a.wave_positions(31, 0).slice(0, 2):
				a.hero_x = a.WINDOW_X[index]
				_tap(a, KEY_SPACE)

func _run() -> void:
	create_timer(45.0).timeout.connect(func(): push_error("[FAIL] AllMiniGamePractice timed out"); quit(1))
	gm = root.get_node("GameManager")
	var network: Node = root.get_node("NetworkManager")
	network.is_online = false
	gm.set_process(false)
	modal = load("res://scenes/MiniGameModal.tscn").instantiate()
	root.add_child(modal)
	modal.set_process(false)
	modal.set_physics_process(false)
	for id in FIELDS:
		var configs: Array[Dictionary] = []
		for i in range(4): configs.append({"name": "Practice %d" % i, "is_ai": false})
		gm.setup_game(configs, 600)
		var data: Dictionary = gm.MINIGAME_DEFINITIONS[id].duplicate(true)
		data.merge({"seed": 31, "round_id": 987, "phase": "ready"}, true)
		gm.active_minigame = data.duplicate(true)
		gm.minigame_waiting_for_start = true
		gm.minigame_ready_players.clear()
		modal._on_minigame_started(data)
		var baseline := _snapshot(id, modal._current_arcade())
		_check(modal.guide_practice_button.visible, id + ": practice is reachable")
		# Keyboard users can Tab to practice and activate it with Enter.
		modal.guide_practice_button.grab_focus()
		var enter := InputEventKey.new()
		enter.keycode = KEY_ENTER
		enter.pressed = true
		modal._unhandled_input(enter)
		_check(modal.practice_active and not modal._can_play(), id + ": keyboard opens isolated practice")
		_check(root.gui_get_focus_owner() == null, id + ": gameplay keys cannot activate GUI buttons")
		gm._update_minigame(46.0)
		_check(gm.active_minigame["phase"] == "ready", id + ": offline practice can finish without a surprise automatic start")
		var arcade: Node = modal._current_arcade()
		_check(not modal.practice_plan.progress(arcade)["complete"], id + ": waiting alone does not complete practice")
		_exercise(id, arcade)
		_check(modal.practice_plan.progress(arcade)["complete"], id + ": actual actions complete the coached mission")
		_check(modal.score == 0 and modal.correct == 0 and modal.attempts == 0 and gm.minigame_scores.is_empty() and gm.minigame_ready_players.is_empty(), id + ": practice cannot earn rewards or submit readiness")
		modal._process(0.01)
		modal._process(2.01)
		_check(not modal.practice_active and modal.is_guide_open(), id + ": completion returns to guide")
		_check(_snapshot(id, modal._current_arcade()) == baseline, id + ": every round restores the original seed and simulation state")
		_check(gm.local_minigame_practice_round_id == -1, id + ": finishing releases the offline ready timer")
		modal._start_practice()
		modal._process(modal.PRACTICE.seconds_for(id))
		_check(not modal.practice_active and modal.is_guide_open() and modal.score == 0 and _snapshot(id, modal._current_arcade()) == baseline, id + ": unfinished practice times out cleanly without readiness or scores")
		modal._start_practice()
		modal._begin_local_round()
		_check(not modal.practice_active and modal.round_started_locally and _snapshot(id, modal._current_arcade()) == baseline, id + ": host-start safely interrupts and resets practice")
		if id == "eco_commute":
			modal._on_minigame_started(data)
			modal._start_practice()
			var bus: Node = modal._current_arcade()
			bus.bus_x = float(bus.segments[0]["stops"][0]["x"])
			bus._animate_students(0.0)
			_tap(bus, KEY_SPACE)
			_check(bus.has_pending_finish_animation(), "reconnect regression starts with practice boarding animation")
			modal._on_minigame_finished([{"player_idx": 0, "name": "Practice 0", "rank": 0, "score": 0, "reward": 0, "goal_checked": false}])
			_check(not modal.practice_active and not modal.finishing_animation and modal.timer_label.text == "종료", "results received during practice discard practice boarding before showing results")
			_check(int(modal.learning_snapshot.get("delivered_total", -1)) == 0, "practice passengers never appear in competitive result evidence")
		modal.cancel_minigame()
		await process_frame
		print("[PASS] Practice " + id)
	# Online shared deadline remains authoritative even if a local practice starts.
	gm.active_minigame = {"round_id": 987, "id": "heat_leak", "phase": "ready"}
	gm.minigame_ready_players.clear()
	gm.minigame_guide_timeout = 0.1
	network.is_online = true
	network.is_host = true
	gm.set_local_minigame_practice(987, true)
	_check(gm.local_minigame_practice_round_id == -1, "online practice cannot suspend readiness")
	gm._update_minigame(0.2)
	_check(gm.active_minigame["phase"] == "countdown", "online ready deadline still starts the shared countdown")
	network.is_online = false
	gm.stop_game()
	modal.queue_free()
	await process_frame
	print("AllMiniGamePractice: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

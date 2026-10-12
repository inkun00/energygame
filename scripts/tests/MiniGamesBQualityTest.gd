extends SceneTree

const HYDRO = preload("res://scripts/minigames/HydroGateRun3D.gd")
const SORT = preload("res://scripts/minigames/EnergySourceSort3D.gd")
const BATTERY = preload("res://scripts/minigames/BatteryShuttle3D.gd")
const BUS = preload("res://scripts/minigames/SharedSchoolBus3D.gd")
const HEAT = preload("res://scripts/minigames/HeatLeakDash3D.gd")
const INPUT = preload("res://scripts/minigames/MiniGameInput.gd")

var failures: Array[String] = []
var player_data: Dictionary

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
		push_error(description)

func _prepare(arcade: Node, seed_value: int = 31) -> void:
	root.add_child(arcade)
	arcade.call("setup", player_data, seed_value)
	arcade.set_process(false)

func _run() -> void:
	var gm: Node = root.get_node("GameManager")
	gm.stop_game()
	var configs: Array[Dictionary] = [{"name": "품질 1", "is_ai": false}, {"name": "품질 2", "is_ai": false}, {"name": "품질 3", "is_ai": false}, {"name": "품질 4", "is_ai": false}]
	gm.setup_game(configs, 600)
	gm.set_process(false)
	player_data = gm.players[0]
	INPUT.release_all()
	_test_hydro()
	_test_sort()
	_test_battery()
	_test_bus()
	_test_heat()
	gm.stop_game()
	await process_frame
	if failures.is_empty():
		print("[PASS] Five minigames: weather choices, natural delivery, boarding safety and visible window reach")
		quit(0)
	else:
		quit(1)

func _test_hydro() -> void:
	var arcade = HYDRO.new()
	_prepare(arcade)
	_check(arcade.charge_bar.size.y <= 10.0, "hydro: compact local charge bar leaves the tap count visible")
	arcade.hero_x = arcade.LEVER_X[0]
	arcade._update_station()
	arcade._animate_world(0.0)
	arcade._update_visuals()
	_check(not arcade.charge_bar.get_rect().intersects(arcade.charge_label.get_rect()), "hydro: tap count sits beside the small gauge, not inside it")
	for tick in range(250):
		arcade._advance_simulation(0.02)
	_check(not arcade.overflowed and arcade.water_level < 60.0, "hydro: first five seconds allow learning the controls")
	arcade.setup(player_data, 31)
	for tick in range(60): arcade._advance_hero(1.0 / 60.0, 0.0, tick == 0)
	_check(arcade.hero_floor_index == 1, "hydro: the first keyboard jump reaches the middle platform")
	for tick in range(27): arcade._advance_hero(1.0 / 60.0, -1.0, false)
	for tick in range(60): arcade._advance_hero(1.0 / 60.0, 0.0, tick == 0)
	_check(arcade.hero_floor_index == 2, "hydro: the second jump reaches the upper platform")
	for tick in range(17): arcade._advance_hero(1.0 / 60.0, -1.0, false)
	_check(arcade.selected_gate == 2, "hydro: ordinary movement reaches the upper lever during the calm introduction")
	for seed_value in range(3):
		arcade.setup(player_data, seed_value)
		var opened := false
		for tick in range(1500):
			if not opened and arcade.water_level >= 70.0:
				arcade.selected_gate = 0
				for tap in range(3): arcade._tap_selected_gate()
				opened = true
			arcade._advance_simulation(0.02)
		_check(arcade.overflowed, "hydro: leaving the small channel open cannot handle every storm")
		var production_by_frame: Array[float] = []
		for frame_rate in [30, 120]:
			arcade.setup(player_data, seed_value)
			arcade.selected_gate = 2
			for tick in range(frame_rate * 30):
				if arcade.open_gate < 0 and arcade.water_level >= 85.0:
					for tap in range(3): arcade._tap_selected_gate()
				elif arcade.open_gate >= 0 and arcade.inflow_for_time(arcade.elapsed, seed_value) <= 3.0 and arcade.water_level < arcade.highest_open_level - 4.0:
					arcade._close_open_gate(true)
				arcade._advance_simulation(1.0 / float(frame_rate))
			_check(not arcade.overflowed and arcade.managed_closures > 0 and arcade.generated_kwh > 0.0, "hydro: open before storms and close during lulls completes a feasible round")
			production_by_frame.append(arcade.generated_kwh)
		_check(absf(production_by_frame[0] - production_by_frame[1]) < 1.0, "hydro: 30/120 fps preserve drawdown choices and similar generation")
	arcade.queue_free()

func _test_sort() -> void:
	var arcade = SORT.new()
	_prepare(arcade)
	_check(arcade.answer_labels[0].visible, "sort: show examples on the first item")
	arcade.hero_x = arcade.DELIVERY_X if int(arcade.current_source["kind"]) == 1 else -arcade.DELIVERY_X
	var delivered_x: float = arcade.hero_x
	arcade._deliver(int(arcade.current_source["kind"]))
	_check(is_equal_approx(arcade.hero_x, delivered_x) and arcade.returning_to_center, "sort: delivery never teleports the runner")
	arcade._process(0.1)
	_check(absf(arcade.hero_x) < absf(delivered_x) and absf(arcade.hero_x) > 0.0, "sort: visibly run back through the map")
	arcade._deliver(int(arcade.current_source["kind"]))
	_check(not arcade.answer_labels[0].visible and not arcade.answer_labels[1].visible, "sort: remove exact answer lists after two examples")
	arcade.setup(player_data, 31)
	arcade.hero_x = -arcade.DELIVERY_X
	INPUT.set_touch(KEY_A, true)
	arcade._deliver(0)
	arcade._process(0.1)
	_check(arcade.waiting_for_release, "sort: holding the same delivery direction never answers the next item automatically")
	INPUT.set_touch(KEY_A, false)
	INPUT.set_touch(KEY_D, true)
	arcade._process(0.1)
	_check(not arcade.waiting_for_release, "sort: changing to the opposite key during return is a new deliberate choice")
	for tick in range(90): arcade._process(1.0 / 60.0)
	_check(arcade.hero_x > 0.0, "sort: an opposite direction held through return moves the next item without an extra all-keys-up frame")
	INPUT.release_all()
	arcade.setup(player_data, 31)
	arcade.hero_x = -arcade.DELIVERY_X
	INPUT.set_touch(KEY_A, true)
	arcade._deliver(0)
	INPUT.release_all()
	arcade._process(0.1)
	_check(not arcade.waiting_for_release, "sort: a key release is observed during automatic return, not only after arrival")
	_check(arcade.hint_label.anchor_top == 1.0, "sort: the control hint stays at the arena footer when its height changes")
	arcade.queue_free()

func _test_battery() -> void:
	_check(BATTERY.phase_for_time(4.5, 0) == BATTERY.phase_for_time(4.5, 0), "battery: shared seeds produce identical weather and demand")
	_check(BATTERY.phase_for_time(4.5, 0) != BATTERY.phase_for_time(4.5, 2), "battery: weather timings vary across rounds")
	var arcade = BATTERY.new()
	_prepare(arcade)
	arcade.hero_x = arcade.SOLAR_X
	arcade._try_station_action()
	arcade.hero_x = arcade.BATTERY_X
	arcade._try_station_action()
	arcade.elapsed = 5.1
	arcade._try_station_action()
	arcade.hero_x = arcade.CITY_X
	arcade._try_station_action()
	_check(arcade.city_energy_remaining == 1.0, "battery: delivery creates a persistent city energy reserve")
	arcade._process(1.3)
	_check(arcade.city_energy_remaining > 0.0, "battery: supply keeps the city lit longer than the old flash")
	_check(arcade.phase_label.text.contains("태양광 발전 부족") and arcade.city_label.text.contains("도시 저장"), "battery: cloudy generation shortage is distinguished from the city's remaining stored supply")
	var current_demand: float = arcade.phase_for_time(arcade.elapsed, arcade.game_seed)["demand"]
	_check(is_equal_approx(arcade.get_city_supply_seconds(), arcade.city_energy_remaining / (current_demand * 0.22)), "battery: visible reserve duration uses current city demand")
	arcade.cargo = 2
	arcade._update_visuals()
	_check(arcade.transfer_pulses[0].visible and arcade.transfer_pulses[0].position.x >= arcade.BATTERY_X and arcade.transfer_pulses[0].position.x <= arcade.CITY_X, "battery: blue delivery pulses travel from battery to city with stored cargo")
	arcade.queue_free()

func _test_bus() -> void:
	var arcade = BUS.new()
	_prepare(arcade)
	var stop: Dictionary = arcade.segments[0]["stops"][0]
	var first_student: Node3D = stop["states"][0]["node"]
	_check(is_equal_approx(first_student.position.y, 0.255), "bus: waiting students' feet touch the stop platform")
	arcade.bus_x = 12.0
	arcade._animate_students(0.0)
	arcade._attempt_pickup()
	_check(not arcade.boarding_students.is_empty() and first_student.visible, "bus: students walk to the door instead of disappearing")
	arcade._step_vehicle(1.0, true, false, false)
	_check(arcade.bus_speed == 0.0 and arcade.bus_x == 12.0, "bus: cannot move while students board")
	arcade._animate_boarding_students(2.0)
	_check(arcade.boarding_students.is_empty() and not first_student.visible, "bus: completed boarding hides students inside the bus")
	arcade.passengers = 45
	arcade.bus_x = 56.0
	arcade._unload_at_school(56.0)
	arcade._step_vehicle(1.0, true, false, false)
	_check(arcade.bus_speed == 0.0 and arcade.bus_x == 56.0 and arcade.dropped_students.size() == 45, "bus: all 45 students clear the bus before departure")
	arcade._animate_dropoff_students(4.0)
	arcade._step_vehicle(0.25, true, false, false)
	_check(arcade.dropped_students.is_empty() and arcade.bus_speed > 0.0, "bus: acceleration resumes after the final student enters school")
	for frame_rate in [30, 120]:
		arcade.setup(player_data, 31)
		arcade.passengers = 45
		arcade.bus_x = 56.0
		arcade._unload_at_school(56.0)
		for tick in range(frame_rate):
			arcade._animate_dropoff_students(1.0 / float(frame_rate))
			arcade._step_vehicle(1.0 / float(frame_rate), true, false, false)
		_check(arcade.bus_x == 56.0 and not arcade.dropped_students.is_empty(), "bus: departure stays locked during partial 45-person unloading at 30/120 fps")
		for tick in range(frame_rate * 3):
			arcade._animate_dropoff_students(1.0 / float(frame_rate))
			arcade._step_vehicle(1.0 / float(frame_rate), true, false, false)
		_check(arcade.dropped_students.is_empty() and arcade.bus_x > 56.0, "bus: departure unlocks after all 45 entries at 30/120 fps")
	arcade.setup(player_data, 31)
	var next: Dictionary = arcade.get_next_service_point()
	_check(not next.is_empty() and not next["school"] and next["waiting"] > 0 and next["late"] > 0, "bus: the fixed next-stop HUD separates waiting pupils from late runners")
	var marker: MeshInstance3D = arcade.segments[0]["stops"][0]["marker"]
	_check(is_equal_approx((marker.mesh as BoxMesh).size.x, arcade.PICKUP_REACH * 2.0), "bus: the yellow pickup line shows the actual stopping tolerance")
	arcade.passengers = 45
	arcade.bus_x = 56.0
	arcade.route_distance = 56.0
	arcade.elapsed = 60.0
	arcade._unload_at_school(56.0)
	var score_events: Array[int] = []
	arcade.arcade_event.connect(func(points: int, _good: bool, _message: String, _counts: bool) -> void: score_events.append(points))
	var delivered_before: int = arcade.delivered_total
	var route_before: float = arcade.route_distance
	var drain_seconds: float = arcade.get_finish_animation_seconds()
	_check(arcade.begin_finish_animation() and drain_seconds > 3.0 and drain_seconds < 4.0, "bus: all 45 pupils arriving at the deadline get a bounded cosmetic finish")
	_check(not arcade.running and arcade.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "bus: deadline stops competition but keeps pending pupil entry visible")
	for tick in range(240): arcade.advance_finish_animation(1.0 / 60.0)
	_check(not arcade.has_pending_finish_animation() and not arcade.finish_animation_active, "bus: every pupil enters school before the cosmetic finish ends")
	_check(arcade.elapsed == 60.0 and arcade.bus_x == 56.0 and arcade.route_distance == route_before and arcade.delivered_total == delivered_before and score_events.is_empty(), "bus: cosmetic finish never changes time, distance, learning delivery count or score")
	_check(arcade.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "bus: completed finish turns the inactive 3D viewport off")
	arcade.queue_free()

func _test_heat() -> void:
	var arcade = HEAT.new()
	_prepare(arcade)
	var window: Dictionary = arcade.windows[0]
	var pane := window["pane"] as MeshInstance3D
	var pane_center: Vector3 = pane.global_transform * pane.mesh.get_aabb().get_center()
	_check(absf(pane_center.x - float(window["x"])) < 0.01, "heat: interaction centre matches the actual window mesh")
	window["open"] = true
	arcade.hero_x = float(window["x"])
	arcade._update_overlay()
	_check(window["prompt"].visible and window["reach_marker"].visible, "heat: an open window in reach shows Space and its usable area")
	_check(not arcade.action_label.visible and float(window["prompt"].position.y) > 2.0, "heat: reachable windows show one local prompt above the hero instead of overlapping footer instructions")
	var open_usage: float = arcade.cooling_use_bar.value
	arcade._try_close()
	_check(arcade.cooling_use_bar.value < open_usage and not window["prompt"].visible, "heat: closing visibly lowers air-conditioning power use")
	_check(arcade.action_label.visible, "heat: after closing, the footer returns to explain the cooling effect")
	for room_window in arcade.windows:
		room_window["open"] = false
	arcade.hero_x = 0.0
	var before_temperature: float = arcade.room_temperature
	arcade._process(0.2)
	_check(arcade.room_temperature < before_temperature, "heat: blocking all hot air lets the room cool while using less power")
	_check(HEAT.wave_time(0, 1) != HEAT.wave_time(2, 1), "heat: wind previews vary by the common round seed")
	arcade.queue_free()

extends SceneTree

const WIND = preload("res://scripts/minigames/WindTurbinePilot3D.gd")
const SOLAR = preload("res://scripts/minigames/SolarPanelDash3D.gd")
const GRID = preload("res://scripts/minigames/SmartGridBalance3D.gd")
const STANDBY = preload("res://scripts/minigames/StandbyPowerHunt3D.gd")
const FEEDBACK = preload("res://scripts/minigames/MiniGameLearningFeedback.gd")
var failures: Array[String] = []
var created: Array[Node] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func _arcade(script: Script) -> Node:
	var a = script.new()
	root.add_child(a)
	a.setup({"index": 0, "name": "Quality", "is_ai": false}, 20260921)
	a.set_process(false)
	a.set_physics_process(false)
	created.append(a)
	return a

func _run() -> void:
	ProjectSettings.set_setting("network/room_directory_url", "")
	OS.set_environment("ENERGYGAME_ROOM_DIRECTORY_URL", "")
	_check_frame_rate_timers()
	_check_action_feedback()
	var wa = _arcade(WIND)
	var wb = _arcade(WIND)
	wa.phase_index = 3
	wb.phase_index = 3
	wa._start_next_wind_phase()
	wb._start_next_wind_phase()
	wa._update_brake_input(true)
	wa._finish_wind_phase()
	wb._finish_wind_phase()
	for phase in range(8):
		_check(wa.wind_angle == wb.wind_angle and wa.wind_speed == wb.wind_speed, "Wind: success/failure must preserve the same subsequent ranked wind")
		wa._update_wind_streaks(1.0)
		wb._update_wind_streaks(0.016)
		wa._start_next_wind_phase()
		wb._start_next_wind_phase()
	var sa = _arcade(SOLAR)
	var sb = _arcade(SOLAR)
	var obstacle: Node3D = sa.terrain_obstacles[0]["node"]
	sa.hero_body.position.x = obstacle.position.x
	sa._resolve_hazard_collision(obstacle)
	for spawn in range(8):
		sa._spawn_terrain_obstacle(-35.0)
		sb._spawn_terrain_obstacle(-35.0)
		var aa: Dictionary = sa.terrain_obstacles.back()
		var bb: Dictionary = sb.terrain_obstacles.back()
		_check(aa["name"] == bb["name"] and aa["node"].position.x == bb["node"].position.x, "Solar: knockback must not change subsequent ranked hazards")
	var lanes_seen: Dictionary = {}
	for gate in sa.panel_gates:
		sa._update_panel_gate_for_sun(gate)
		var best: int = sa._correct_lane_for_current_sun(gate)
		lanes_seen[best] = true
		for lane in range(3):
			var efficiency: float = sa.panel_capture_efficiency(gate["meshes"][lane])
			_check(efficiency > 0.99 if lane == best else efficiency < 0.95, "Solar: rendered panel surface normals must agree with the accepted sunlight angle")
	_check(lanes_seen.size() > 1, "Solar: useful panel must not be tied to one sun-side lane")
	var sc = _arcade(SOLAR)
	var awarded: Array[int] = []
	sc.arcade_event.connect(func(points:int, success:bool, _message:String, correct:bool):
		if success and correct: awarded.append(points)
	)
	sc.lane_choice_made = true
	sc.hero_body.position = Vector3(sc.LANES[sc._correct_lane_for_current_sun()],0.1,5.0)
	sc.panel_gates[0]["node"].position.z = 1.91
	sc._update_course(0.0)
	_check(awarded.is_empty(), "Solar: displaced runner must actually reach a panel before scoring")
	sc.panel_gates[0]["node"].position.z = 4.9
	sc._update_course(0.0)
	_check(awarded == [100], "Solar: actual crossing must award exactly once")
	var ga = _arcade(GRID)
	var gb = _arcade(GRID)
	for a in [ga, gb]:
		a.demand = 60.0
		a.demand_target = 60.0
		a.supply = 60.0
		a._apply_supply_input(1.0,0.01)
		a._process(1.1)
	ga.supply = 120.0
	ga._process(2.9)
	gb._process(2.9)
	_check(gb.get_balance_score() > ga.get_balance_score(), "Grid: lower full-round average gap must earn the higher score")
	var finalized: int = gb.finalize_balance_score()
	_check(gb.finalize_balance_score() == finalized, "Grid: finalization must be idempotent")
	var idle = _arcade(GRID)
	idle._process(2.0)
	_check(idle.get_balance_score() == 0, "Grid: no supply choice must not award a score")
	var house = _arcade(STANDBY)
	var tv: Dictionary = house.device_records[1]
	house.hero.position.x = float(tv["x"]) + house.PASS_DISTANCE + 0.1
	house.run_velocity = 1.0
	house._update_device_passes()
	_check(not tv["resolved"] and tv["miss_deadline"] > 0.0, "Standby: passing a wasted device must leave a brief recovery chance")
	house.hero.position.x = float(tv["x"])
	house._try_disconnect()
	_check(tv["resolved"] and house.saved_watts == tv["watt"], "Standby: returning during grace period can still disconnect")
	var upper: Dictionary = house.device_records[7]
	house.hero.position.x = float(upper["x"])
	house.hero.position.y = house.GROUND_Y
	_check(house._nearest_unresolved_device().is_empty(), "Standby: upstairs device must require reaching its floor")
	house.hero.position.y = 1.05
	_check(not house._nearest_unresolved_device().is_empty(), "Standby: upstairs route must allow device interaction")
	house.hero.position.y = 1.4
	house.vertical_velocity = -2.0
	house._update_jump(0.2)
	_check(is_equal_approx(house.hero.position.y,1.05) and house.vertical_velocity == 0.0, "Standby: descending onto the upper floor must land rather than fall through")
	for a in created: a.queue_free()
	await process_frame
	print("Mini-games A quality: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _check_action_feedback() -> void:
	var solar = _arcade(SOLAR)
	for sun_position in solar.SUN_POSITIONS:
		solar.sun.position = sun_position
		for gate in solar.panel_gates:
			solar._update_panel_gate_for_sun(gate)
			_check(gate.front_markers.size() == 3, "Solar: every lane must have a neutral front-direction marker")
			for lane in range(3):
				var panel: Node3D = gate.meshes[lane]
				var marker: Node3D = gate.front_markers[lane]
				var actual_normal: Vector3 = (panel.global_basis.orthonormalized() * solar.PANEL_SURFACE_NORMAL).normalized()
				_check(marker.global_basis.y.normalized().dot(actual_normal) > 0.99999, "Solar: visible arrow must describe the actual scored panel front at every sun position")
				var useful := lane == int(gate.correct_lane)
				_check(solar.panel_capture_efficiency(panel) > 0.99 if useful else solar.panel_capture_efficiency(panel) < 0.95, "Solar: front-direction cue must agree with sunlight capture without changing the answer")
				for child in marker.get_children():
					_check(child.material_override == solar.front_direction_material, "Solar: correct and incorrect panels must share identical neutral marker styling")
	var wind = _arcade(WIND)
	wind.wind_angle = 0.0
	wind.turbine_yaw = 0.0
	wind.yaw_choice_made = false
	var wind_events: Array[Dictionary] = []
	wind.arcade_event.connect(func(points:int,success:bool,_message:String,correct:bool):
		wind_events.append({"points":points,"success":success,"correct":correct})
	)
	wind._process(0.75)
	_check(wind_events.is_empty() and "예상 발전" in wind.alignment_label.text and "조절해 시작" in wind.instruction_label.text, "Wind: initially aligned idle turbine must explain the zero-score state and first action")
	wind._apply_yaw_input(1.0,0.01)
	wind._process(0.35)
	_check(wind_events.size() == 1 and wind_events[0].success and wind_events[0].correct and "예상" not in wind.alignment_label.text, "Wind: actual yaw choice must start generation and clear the start hint")
	# Reproduce a capture just before normal phase 3 becomes storm phase 4.
	wind.phase_index = 3
	wind.phase_elapsed = wind.WIND_PHASE_SECONDS - 0.01
	wind._process(0.02)
	_check(wind.storm_phase and not is_instance_valid(wind.score_popup), "Wind: an old generation popup must disappear at the exact storm boundary")
	wind._finish_wind_phase()
	_check(wind_events.back().points == 35 and not wind_events.back().success and is_instance_valid(wind.score_popup), "Wind: missed-brake penalty and failure popup must survive the following normal-phase transition")
	_check(wind.score_popup.offset_top - 10.0 >= wind.storm_banner.offset_bottom + 8.0, "Wind: score popup must never travel into the reserved storm warning area")
	var grid = _arcade(GRID)
	grid.measurement_time = 2.0
	grid.gap_integral = 20.0
	grid.demand = 65.0
	grid.supply = 55.0
	grid._update_hud(-10.0,false)
	_check("현재" in grid.demand_label.text and "평균" in grid.average_gap_label.text, "Grid: current demand/supply must be separate from the full-round average gap")
	var cue := FEEDBACK.live_line("grid_balance",true,0,true,{"grid_gap":0.5})
	grid.supply = 45.0
	grid._update_hud(-20.0,false)
	_check(cue.begins_with("방금") and "0.5 MW" in cue and "20.0 MW" in grid.balance_label.text, "Grid: remembered successful gap must remain explicitly past while the live imbalance changes")
	var house = _arcade(STANDBY)
	var house_events: Array[Dictionary] = []
	house.arcade_event.connect(func(points:int,success:bool,_message:String,correct:bool):
		house_events.append({"points":points,"success":success,"correct":correct})
	)
	var active: Dictionary = house.device_records[0]
	house.hero.position.x = float(active.x)
	house._update_hud()
	_check("사용 중" in house.action_label.text and "유지" in house.action_label.text and "확인" not in house.action_label.text, "Standby: active-device prompt must not invite an inspection that actually disconnects it")
	house._try_disconnect()
	_check(active.resolved and not active.powered and house_events.size() == 1 and house_events[0].points == 48 and not house_events[0].success and not house_events[0].correct and house.saved_watts == 0, "Standby: deliberately cutting an active device must retain the exact penalty and never count as a saved-watts goal")
	var idle: Dictionary = house.device_records[1]
	house.hero.position.x = float(idle.x)
	house._update_hud()
	_check("[SPACE]" in house.action_label.text and "전원 차단" in house.action_label.text, "Standby: nearby wasted-device prompt must describe the real disconnect action")
	house._try_disconnect()
	_check(idle.resolved and not idle.powered and house.saved_watts == idle.watt and house_events.back().points == house.score_for_saved_watts(idle.watt) and house_events.back().success and house_events.back().correct, "Standby: correct disconnection must still award measured watts and a goal action")
	_check(house.action_label.anchor_top == 1.0 and house.saved_label.anchor_top == 1.0, "Standby: action/savings HUD must remain below the upper route at taller arena sizes")

func _check_frame_rate_timers() -> void:
	var wind_totals: Array[int] = []
	var grid_states: Array[Dictionary] = []
	var solar_states: Array[Dictionary] = []
	for fps in [60, 30, 15]:
		var wind = _arcade(WIND)
		wind.yaw_choice_made = true
		wind.phase_scored = true
		wind.wind_speed = 15
		wind.turbine_yaw = 0.0
		wind.wind_angle = 0.0
		var total := {"points": 0, "ticks": 0}
		wind.arcade_event.connect(func(points: int, _success: bool, _message: String, _correct: bool):
			total["points"] += points
			total["ticks"] += 1
		)
		for step in range(roundi(2.8 * fps)):
			wind._score_aligned_generation(1.0 / fps, 1.0)
		_check(total["ticks"] == 8 and total["points"] == 160, "Wind: identical 2.8 seconds of alignment must produce 8 intervals / 160 points at %d FPS" % fps)
		wind_totals.append(total["points"])
		var grid = _arcade(GRID)
		for step in range(roundi(12.6 * fps)):
			grid._process(1.0 / fps)
		grid_states.append({"phase": grid.phase_index, "remaining": grid.phase_elapsed, "target": grid.demand_target})
		_check(grid.phase_index == 4 and absf(grid.phase_elapsed) < 0.00001, "Grid: three exact demand periods must not lose time at %d FPS" % fps)
		var solar = _arcade(SOLAR)
		for step in range(roundi(10.2 * fps)):
			solar._update_sun(1.0 / fps)
		solar_states.append({"position": solar.sun_position_index, "remaining": solar.sun_move_elapsed, "world_position": solar.sun.position})
		_check(solar.sun_position_index == 2 and absf(solar.sun_move_elapsed - 0.2) < 0.00001, "Solar: two sunlight periods must preserve the 0.2-second remainder at %d FPS" % fps)
	_check(wind_totals[0] == wind_totals[1] and wind_totals[1] == wind_totals[2], "Wind: frame rate must not change production score")
	_check(grid_states[0]["target"] == grid_states[1]["target"] and grid_states[1]["target"] == grid_states[2]["target"], "Grid: frame rate must not change the seeded demand sequence")
	_check(solar_states[0]["world_position"].distance_to(solar_states[1]["world_position"]) < 0.00001 and solar_states[1]["world_position"].distance_to(solar_states[2]["world_position"]) < 0.00001, "Solar: rendered sunlight interpolation must use the same simulation time at every frame rate")
	var bulk_wind = _arcade(WIND)
	bulk_wind.yaw_choice_made = true
	bulk_wind.phase_scored = true
	bulk_wind.wind_speed = 15
	bulk_wind.turbine_yaw = 0.0
	bulk_wind.wind_angle = 0.0
	var bulk_total := {"points": 0}
	bulk_wind.arcade_event.connect(func(points: int, _success: bool, _message: String, _correct: bool): bulk_total["points"] += points)
	bulk_wind._score_aligned_generation(2.8, 1.0)
	_check(bulk_total["points"] == 160, "Wind: a delayed step must flush all complete generation intervals")
	var bulk_solar = _arcade(SOLAR)
	bulk_solar._update_sun(10.2)
	_check(bulk_solar.sun_position_index == 2 and absf(bulk_solar.sun_move_elapsed - 0.2) < 0.00001, "Solar: a delayed step must advance all complete sunlight periods")
	_check(bulk_solar.sun.position.distance_to(solar_states[0]["world_position"]) < 0.00001, "Solar: delayed catch-up and regular frames must render the same sunlight position")

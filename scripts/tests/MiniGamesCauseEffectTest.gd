extends SceneTree

## Read-only game-state regression. No player history is written.
const SOLAR = preload("res://scripts/minigames/SolarPanelDash3D.gd")
const WIND = preload("res://scripts/minigames/WindTurbinePilot3D.gd")
const GRID = preload("res://scripts/minigames/SmartGridBalance3D.gd")
const STANDBY = preload("res://scripts/minigames/StandbyPowerHunt3D.gd")
const HYDRO = preload("res://scripts/minigames/HydroGateRun3D.gd")
const STYLE = preload("res://scripts/minigames/MiniGameVisualStyle.gd")
var failures: Array[String] = []
var created: Array[Node] = []

func _initialize() -> void:
	call_deferred("_run")

func _game(script: Script) -> Node:
	var game = script.new()
	root.add_child(game)
	game.size = Vector2(960, 440)
	game.setup({"index": 0, "name": "Visual QA", "is_ai": false}, 20260921)
	game.set_process(false)
	game.set_physics_process(false)
	created.append(game)
	return game

func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error("[FAIL] " + message)

func _run() -> void:
	for test_name in ["_solar", "_wind", "_grid", "_standby", "_hydro", "_contact_shadows"]:
		_check(call(test_name) == true, test_name + " must finish without a runtime error")
	for game in created:
		game.queue_free()
	await process_frame
	print("[PASS] Mini-games cause/effect visual feedback" if failures.is_empty() else "[FAIL] %d cause/effect checks" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _solar() -> bool:
	var game = _game(SOLAR)
	var scenario_state: int = game.rng.state
	game._update_panel_guides()
	var visible_rows := 0
	for record in game.panel_gates:
		var visible_count := 0
		for marker in record.front_markers:
			if marker.visible: visible_count += 1
		_check(visible_count == 0 or visible_count == 3, "Solar: every compared lane must receive the same neutral front cue")
		if visible_count == 3: visible_rows += 1
		for lane in range(3):
			_check(record.beams[lane].visible == record.front_markers[lane].visible, "Solar: sunlight and panel front must be compared in the same upcoming row")
			_check(game.panel_capture_efficiency(record.meshes[lane]) > 0.99 if lane == int(record.correct_lane) else game.panel_capture_efficiency(record.meshes[lane]) < 0.95, "Solar: reduced visual clutter must not alter the answer geometry")
	_check(visible_rows == 1, "Solar: only one nearest panel row may show comparison arrows")
	game.panel_gates[0].resolved = true
	game._update_panel_guides()
	_check(not game.panel_gates[0].front_markers[0].visible and game.panel_gates[1].front_markers[0].visible, "Solar: comparison must advance to the next unresolved row")
	_check(game.rng.state == scenario_state, "Solar: focusing cues must not consume ranked scenario RNG")
	return true

func _wind() -> bool:
	var game = _game(WIND)
	var scenario_state: int = game.rng.state
	game.storm_phase = false
	game.wind_angle = 28.0
	game.turbine_yaw = -28.0
	game._update_direction_feedback(game._alignment_efficiency(), 10.0)
	_check(game.wind_pointer.position.x > game.turbine_pointer.position.x, "Wind: both pointers must share the same left/right angle scale")
	game.turbine_yaw = game.wind_angle
	game._update_direction_feedback(1.0, 60.0)
	_check(is_equal_approx(game.wind_pointer.position.x, game.turbine_pointer.position.x), "Wind: matching directions must visibly line up")
	game.storm_phase = true
	game._engage_storm_brake(false)
	game._update_hud(1.0, 0.0)
	var rotation_before: float = game.rotor.rotation.z
	var background_before: float = game.background_rotors[0].rotation.z
	game._update_rotor(0.25, 0.0)
	_check(is_equal_approx(rotation_before, game.rotor.rotation.z) and "안전 정지" in game.direction_caption.text and not game.wind_pointer.visible, "Wind: successful braking must freeze the rotor and replace yaw comparison with safe-stop feedback")
	_check(is_equal_approx(background_before, game.background_rotors[0].rotation.z), "Wind: farm background must not contradict storm safety by continuing to spin")
	_check(game.storm_banner.anchor_left == 0.0 and game.storm_banner.offset_right <= 340.0, "Wind: the storm prompt must leave the central rotor/hub visible")
	_check(game.rng.state == scenario_state, "Wind: direction/brake visuals must not change ranked wind")
	_check(game.power_caption.text == "발전 멈춤" and "초" in game.phase_caption.text, "Wind: output and phase meters must explain a stopped rotor rather than remain unlabeled grey bars")
	_check(game.power_caption.get_theme_constant("outline_size") >= 3, "Wind: output captions over the bright landscape require a contrasting outline")
	return true

func _grid() -> bool:
	var game = _game(GRID)
	var scenario_state: int = game.rng.state
	game.demand = 100.0
	game.supply = 20.0
	game._update_city_visuals(0.016, -80.0, false)
	var severe_shortage: int = game.lit_window_count
	game.supply = 80.0
	game._update_city_visuals(0.016, -20.0, false)
	var recovering: int = game.lit_window_count
	game.supply = 100.0
	game._update_city_visuals(0.016, 0.0, true)
	_check(severe_shortage < recovering and recovering < game.lit_window_count and game.lit_window_count == game.city_windows.size(), "Grid: raising supply toward demand must visibly restore more city windows")
	_check(game.supply_bar.anchor_top == 1.0 and game.demand_bar.anchor_top == 1.0, "Grid: comparison bars must stay below the city at taller laptop arena sizes")
	_check(game.rng.state == scenario_state and game.measurement_time == 0.0 and game.get_balance_score() == 0, "Grid: city lighting must neither change demand sequence nor award unearned score")
	return true

func _standby() -> bool:
	var game = _game(STANDBY)
	var floor_bounds: AABB = game._model_bounds(game.course_root.get_node("Floor"))
	var wall_bounds: AABB = game._model_bounds(game.course_root.get_node("Wall"))
	_check(floor_bounds.position.z <= game.hero.position.z and floor_bounds.end.z >= game.hero.position.z, "Standby: the reused floor asset must actually extend beneath the runner's walking lane")
	_check(wall_bounds.size.x >= 2.0 and wall_bounds.size.y >= 2.5, "Standby: adjacent CC0 wall modules must cover their 2m spacing and be taller than the hero")
	var active: Dictionary = game.device_records[0]
	game.hero.position.x = float(active.x)
	game._update_hud()
	_check(game.focused_device == active and game.focus_marker.visible and "유지" in game.action_label.text, "Standby: the one focus marker must match the active-device preserve prompt")
	var activity: Node3D = active.node.get_node("ActivityGlow")
	var original_rotation := activity.rotation
	game.visual_time = 0.5
	game._animate_scene()
	_check(activity.rotation != original_rotation, "Standby: working devices must visibly show activity without stopping their function")
	var idle: Dictionary = game.device_records[1]
	game.hero.position.x = float(idle.x)
	game._update_hud()
	_check(game.focused_device == idle and "대기" in idle.label.text and idle.node.get_node("StandbyLED").visible, "Standby: the same nearby target must expose its standby state and live LED")
	game._try_disconnect()
	_check(idle.resolved and not idle.node.get_node("StandbyLED").visible and game.saved_watts == idle.watt, "Standby: disconnecting a wasted device must extinguish its LED and record the original saved watts")
	game._update_hud()
	_check(not game.focus_marker.visible, "Standby: a resolved device must not leave a stale interaction target")
	return true

func _hydro() -> bool:
	var game = _game(HYDRO)
	game.size = Vector2(1024, 600)
	game._fit_camera_to_chain()
	_check(game.camera.size >= 21.8 / (1024.0 / 600.0), "Hydro: a taller laptop arena must fit the whole water-to-city chain")
	game.water_level = 85.0
	game.open_gate = 2
	game._update_visuals()
	var power: float = game.power_for_gate(game.water_level, game.open_gate)
	var rotation_before: float = game.turbine.rotation_degrees.z
	game.visual_time = 0.5
	game._animate_world(0.2)
	_check(power > 0.0 and game.turbine.rotation_degrees.z != rotation_before, "Hydro: flowing water must drive actual visible turbine rotation")
	for pulse in game.electric_pulses:
		_check(pulse.visible and pulse.position.x >= 6.45 and pulse.position.x <= 8.8, "Hydro: visible electricity must travel from generator toward the city")
	for window in game.city_windows:
		_check(window.material_override == game.city_window_material, "Hydro: producing electricity must light city windows")
	game.open_gate = -1
	game._update_visuals()
	rotation_before = game.turbine.rotation_degrees.z
	game._animate_world(0.2)
	_check(not game.power_line.visible and is_equal_approx(rotation_before, game.turbine.rotation_degrees.z), "Hydro: closing the gate must stop the hydraulic/electric chain")
	for pulse in game.electric_pulses:
		_check(not pulse.visible, "Hydro: stopped generation must not send cosmetic electricity")
	for window in game.city_windows:
		_check(window.material_override == game.city_window_dark_material, "Hydro: closed gate must visibly darken city windows")
	_check(game.generated_kwh == 0.0 and game.awarded_points == 0, "Hydro: cosmetic flow must never produce real energy or points")
	return true

func _contact_shadows() -> bool:
	var solar = _game(SOLAR)
	solar.hero_body.position.y = 1.4
	solar.hero.rotation.z = 0.12
	STYLE.update_contact_shadow(solar.hero, solar.GROUND_Y, 1.4 - solar.GROUND_Y)
	_check(absf(solar.hero.shadow_mesh.global_position.y - solar.GROUND_Y) < 0.06, "Solar: a scaled pawn parented to a jumping body must keep its shadow on the ground")
	_check(absf(solar.hero.shadow_mesh.global_position.x - solar.hero.global_position.x) < 0.001 and absf(solar.hero.shadow_mesh.global_rotation.z) < 0.001, "Solar: banking the runner must not tilt or shift its ground contact mark")
	var house = _game(STANDBY)
	house.hero.position.y = 1.4
	STYLE.update_contact_shadow(house.hero, house.GROUND_Y, 1.4 - house.GROUND_Y)
	_check(absf(house.hero.shadow_mesh.global_position.y - house.GROUND_Y) < 0.06, "Standby: magnified side-runner shadow must not be multiplied below the floor")
	var hydro = _game(HYDRO)
	hydro.hero_floor_index = 1
	hydro.hero_x = 2.0
	hydro.hero_y = hydro.platform_height(1)
	hydro._animate_world(0.016)
	_check(hydro.hero.shadow_mesh.visible and absf(hydro.hero.shadow_mesh.global_position.y - hydro.platform_height(1)) < 0.06, "Hydro: the hero must be grounded on the actual upper service platform")
	_check(STYLE.SUCCESS_FLASH_ALPHA <= 0.12 and STYLE.WARNING_FLASH_ALPHA <= 0.14, "Feedback must preserve scene readability rather than wash out its assets")
	return true

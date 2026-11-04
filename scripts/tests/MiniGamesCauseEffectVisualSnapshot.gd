extends SceneTree

## Development screenshots only; never saves player progress or records.
const OUTPUT := "res://.godot/qa-cause-effect"
var failed := false
var canvas_size := Vector2i(1024, 600)
var output_dir := OUTPUT

func _initialize() -> void:
	call_deferred("_capture")

func _game(script_name: String) -> Node:
	var game = load("res://scripts/minigames/%s.gd" % script_name).new()
	root.add_child(game)
	game.position = Vector2(0, 55)
	game.size = Vector2(canvas_size.x, canvas_size.y - 110)
	game.setup({"index": 0, "name": "Visual QA", "char_icon": "res://assets/characters/eco_roster/captain_eco.webp"}, 20260921)
	game.set_process(false)
	game.set_physics_process(false)
	return game

func _shot(game: Node, name_value: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	if picture.is_empty() or picture.save_png("%s/%s.png" % [output_dir, name_value]) != OK:
		failed = true
		push_error("[FAIL] render capture: " + name_value)
	print("[CAPTURE] " + name_value)
	game.queue_free()
	await process_frame

func _capture() -> void:
	root.get_node("GameManager").stop_game()
	if "--wide" in OS.get_cmdline_user_args():
		canvas_size = Vector2i(1280, 720)
		output_dir = OUTPUT + "-1280"
	root.size = canvas_size
	root.content_scale_size = canvas_size
	DirAccess.make_dir_recursive_absolute(output_dir)
	var solar = _game("SolarPanelDash3D")
	solar._update_panel_guides()
	await _shot(solar, "solar-nearest-comparison")
	solar = _game("SolarPanelDash3D")
	solar.panel_gates[0].node.position.z = -1.0
	solar._update_panel_gate_for_sun(solar.panel_gates[0])
	solar._update_panel_guides()
	await _shot(solar, "solar-close-comparison")
	var wind = _game("WindTurbinePilot3D")
	wind.wind_angle = 28.0
	wind.turbine_yaw = -28.0
	wind.turbine_head.rotation.y = deg_to_rad(wind.turbine_yaw)
	wind.wind_vane.rotation.y = deg_to_rad(wind.wind_angle)
	wind._update_hud(wind._alignment_efficiency(), 5.0)
	await _shot(wind, "wind-direction-mismatch")
	wind = _game("WindTurbinePilot3D")
	wind.wind_angle = 28.0
	wind.turbine_yaw = 28.0
	wind.yaw_choice_made = true
	wind.turbine_head.rotation.y = deg_to_rad(wind.turbine_yaw)
	wind.wind_vane.rotation.y = deg_to_rad(wind.wind_angle)
	wind._update_hud(1.0, 68.0)
	await _shot(wind, "wind-generating")
	wind = _game("WindTurbinePilot3D")
	wind.phase_index = 3
	wind._start_next_wind_phase()
	wind._update_hud(1.0, 0.0)
	await _shot(wind, "wind-storm-stop")
	for sample in [{"supply": 30.0, "name": "grid-shortage"}, {"supply": 100.0, "name": "grid-balance"}]:
		var grid = _game("SmartGridBalance3D")
		grid.demand = 100.0
		grid.supply = sample.supply
		grid._update_city_visuals(0.016, grid.supply - grid.demand, grid.supply == grid.demand)
		grid._update_hud(grid.supply - grid.demand, grid.supply == grid.demand)
		await _shot(grid, sample.name)
	for device_index in [0, 1]:
		var house = _game("StandbyPowerHunt3D")
		house.hero.position.x = float(house.device_records[device_index].x)
		house.camera.position.x = 4.3
		house._update_hud()
		house.visual_time = 0.5
		house._animate_scene()
		await _shot(house, "standby-active" if device_index == 0 else "standby-waste")
	var jumping = _game("StandbyPowerHunt3D")
	jumping.hero.position = Vector3(7.0, 1.25, 1.0)
	jumping._update_jump(0.0)
	jumping._update_hud()
	await _shot(jumping, "standby-jump-contact")
	var unplugged = _game("StandbyPowerHunt3D")
	unplugged.hero.position.x = 5.0
	unplugged._try_disconnect()
	unplugged._update_hud()
	await _shot(unplugged, "standby-disconnected")
	for opened in [false, true]:
		var hydro = _game("HydroGateRun3D")
		hydro.water_level = 85.0
		hydro.open_gate = 2 if opened else -1
		hydro._update_visuals()
		hydro.visual_time = 0.5
		hydro._animate_world(0.2)
		await _shot(hydro, "hydro-generating" if opened else "hydro-closed")
	print("[PASS] Cause/effect snapshots in " + output_dir if not failed else "[FAIL] Cause/effect snapshots")
	quit(1 if failed else 0)

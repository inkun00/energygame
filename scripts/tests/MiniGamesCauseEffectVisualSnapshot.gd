extends SceneTree

## Development screenshots only; never saves player progress or records.
const OUTPUT := "res://.godot/qa-cause-effect"
var failed := false

func _initialize() -> void:
	call_deferred("_capture")

func _game(script_name: String) -> Node:
	var game = load("res://scripts/minigames/%s.gd" % script_name).new()
	root.add_child(game)
	game.position = Vector2(0, 55)
	game.size = Vector2(1024, 490)
	game.setup({"index": 0, "name": "Visual QA", "char_icon": "res://assets/characters/eco_roster/captain_eco.webp"}, 20260921)
	game.set_process(false)
	game.set_physics_process(false)
	return game

func _shot(game: Node, name_value: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	if picture.is_empty() or picture.save_png("%s/%s.png" % [OUTPUT, name_value]) != OK:
		failed = true
		push_error("[FAIL] render capture: " + name_value)
	print("[CAPTURE] " + name_value)
	game.queue_free()
	await process_frame

func _capture() -> void:
	root.get_node("GameManager").stop_game()
	root.size = Vector2i(1024, 600)
	root.content_scale_size = Vector2i(1024, 600)
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var solar = _game("SolarPanelDash3D")
	solar._update_panel_guides()
	await _shot(solar, "solar-nearest-comparison")
	var wind = _game("WindTurbinePilot3D")
	wind.wind_angle = 28.0
	wind.turbine_yaw = -28.0
	wind.turbine_head.rotation.y = deg_to_rad(wind.turbine_yaw)
	wind.wind_vane.rotation.y = deg_to_rad(wind.wind_angle)
	wind._update_hud(wind._alignment_efficiency(), 5.0)
	await _shot(wind, "wind-direction-mismatch")
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
	for opened in [false, true]:
		var hydro = _game("HydroGateRun3D")
		hydro.water_level = 85.0
		hydro.open_gate = 2 if opened else -1
		hydro._update_visuals()
		hydro.visual_time = 0.5
		hydro._animate_world(0.2)
		await _shot(hydro, "hydro-generating" if opened else "hydro-closed")
	print("[PASS] Cause/effect snapshots in " + OUTPUT if not failed else "[FAIL] Cause/effect snapshots")
	quit(1 if failed else 0)

extends SceneTree

## Development-only native render capture. No player data or replay is saved.
const GAMES := ["SolarPanelDash3D", "WindTurbinePilot3D", "SmartGridBalance3D", "StandbyPowerHunt3D", "HydroGateRun3D", "EnergySourceSort3D", "BatteryShuttle3D", "SharedSchoolBus3D", "HeatLeakDash3D"]

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	root.get_node("GameManager").stop_game()
	var output_dir := "res://.godot/qa-native-style"
	DirAccess.make_dir_recursive_absolute(output_dir)
	for game_name in GAMES:
		var arcade: SubViewportContainer = load("res://scripts/minigames/%s.gd" % game_name).new()
		root.add_child(arcade)
		arcade.size = Vector2(960, 384)
		arcade.setup({"char_icon": "res://assets/characters/eco_roster/captain_eco.webp"}, 20260921)
		await create_timer(0.25).timeout
		await RenderingServer.frame_post_draw
		var viewport: SubViewport = arcade.get("viewport")
		var picture := viewport.get_texture().get_image()
		if picture.is_empty() or picture.save_png("%s/%s.png" % [output_dir, game_name]) != OK:
			push_error("Native style capture failed: " + game_name)
			quit(1)
			return
		arcade.queue_free()
		await process_frame
	print("[VisualStylePreview] PASS · 9 native scene captures in .godot/qa-native-style")
	quit(0)

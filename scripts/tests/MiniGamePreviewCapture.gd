extends SceneTree

## Development-only capture of game artwork, never player records or scores.
const GAMES := {
	"solar_align": "SolarPanelDash3D", "wind_rhythm": "WindTurbinePilot3D",
	"grid_balance": "SmartGridBalance3D", "standby_hunt": "StandbyPowerHunt3D",
	"hydro_gate": "HydroGateRun3D", "energy_sort": "EnergySourceSort3D",
	"battery_relay": "BatteryShuttle3D", "eco_commute": "SharedSchoolBus3D",
	"heat_leak": "HeatLeakDash3D"
}

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var output_dir := "res://assets/images/minigame_previews"
	DirAccess.make_dir_recursive_absolute(output_dir)
	for id in GAMES:
		var game: SubViewportContainer = load("res://scripts/minigames/%s.gd" % GAMES[id]).new()
		root.add_child(game)
		game.size = Vector2(960, 400)
		game.setup({"char_icon": "res://assets/characters/eco_roster/captain_eco.webp"}, 20260921)
		await create_timer(0.35).timeout
		await RenderingServer.frame_post_draw
		var viewport: SubViewport = game.get("viewport")
		var picture := viewport.get_texture().get_image()
		picture.resize(384, 160, Image.INTERPOLATE_LANCZOS)
		var error := picture.save_png("%s/%s.png" % [output_dir, id])
		if error != OK:
			push_error("Preview capture failed: %s" % id)
			quit(1)
			return
		game.queue_free()
		await process_frame
	print("[PASS] 9 scene thumbnails captured; no player data saved")
	quit(0)

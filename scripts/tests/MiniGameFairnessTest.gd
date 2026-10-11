extends SceneTree

## Every human sees the same seeded hazards, demand and passengers in a ranked round.

const ARCADE_FIELDS := {
	"solar_align": "solar_arcade",
	"wind_rhythm": "wind_arcade",
	"grid_balance": "grid_arcade",
	"standby_hunt": "standby_arcade",
	"eco_commute": "commute_arcade"
}

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game_manager: Node = root.get_node("GameManager")
	var network_manager: Node = root.get_node("NetworkManager")
	var configs: Array[Dictionary] = []
	for index in range(4):
		configs.append({"name": "공정성 테스트 %d" % index, "is_ai": false})
	game_manager.setup_game(configs)
	game_manager.set_process(false)
	network_manager.is_online = true
	network_manager.is_host = false
	network_manager.game_peer_ids.clear()
	for peer_id in [11, 22, 0, 0]:
		network_manager.game_peer_ids.append(peer_id)
	var modal = load("res://scenes/MiniGameModal.tscn").instantiate()
	root.add_child(modal)
	await process_frame
	for game_id in ARCADE_FIELDS:
		var game_data: Dictionary = (game_manager.MINIGAME_DEFINITIONS[game_id] as Dictionary).duplicate(true)
		game_data["round_id"] = 77
		game_data["seed"] = 20260921
		game_data["duration"] = 30.0
		var observed_seeds: Array[int] = []
		var arcades: Array[Node] = []
		for peer_id in [11, 22]:
			network_manager.my_peer_id = peer_id
			modal._on_minigame_started(game_data)
			var arcade: Node = modal.get(str(ARCADE_FIELDS[game_id]))
			if arcade == null:
				failures.append("%s arcade was not created" % game_id)
				continue
			var arcade_rng: RandomNumberGenerator = arcade.get("rng")
			arcade.set_process(false)
			arcade.set_physics_process(false)
			arcades.append(arcade)
			observed_seeds.append(arcade_rng.seed)
			if modal.rng.seed != int(game_data["seed"]):
				failures.append("%s shared UI seed differs by player" % game_id)
		if observed_seeds.size() == 2 and observed_seeds[0] != observed_seeds[1]:
			failures.append("%s gives different scenarios to ranked players" % game_id)
		if arcades.size() == 2:
			var a: Node = arcades[0]
			var b: Node = arcades[1]
			if game_id == "wind_rhythm":
				for arcade in arcades:
					arcade.phase_index = 3
					arcade._start_next_wind_phase()
				a._update_brake_input(true)
				a._finish_wind_phase()
				b._finish_wind_phase()
				for phase in range(6):
					if a.wind_angle != b.wind_angle or a.wind_speed != b.wind_speed:
						failures.append("wind: success/failure or visual frame rate changed the next ranked wind")
					a._update_wind_streaks(1.0)
					b._update_wind_streaks(0.016)
					a._start_next_wind_phase()
					b._start_next_wind_phase()
			elif game_id == "solar_align":
				var obstacle: Node3D = a.terrain_obstacles[0]["node"]
				a.hero_body.position.x = obstacle.position.x
				a._resolve_hazard_collision(obstacle)
				for spawn in range(6):
					a._spawn_terrain_obstacle()
					b._spawn_terrain_obstacle()
					var first: Dictionary = a.terrain_obstacles.back()
					var second: Dictionary = b.terrain_obstacles.back()
					if first["name"] != second["name"] or first["node"].position.x != second["node"].position.x:
						failures.append("solar: collision changed the subsequent ranked terrain")
	modal.cancel_minigame()
	modal.queue_free()
	game_manager.stop_game()
	network_manager.is_online = false
	await process_frame
	if failures.is_empty():
		print("[PASS] Ranked minigame scenarios share one seed across players")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

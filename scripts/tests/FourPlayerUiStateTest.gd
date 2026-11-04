extends SceneTree

var failures: Array[String] = []
var drop_requests := 0

func _initialize() -> void:
	call_deferred("_run")

func _expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error("[FAIL] Four-player UI: " + message)

func _run() -> void:
	var gm: Node = root.get_node("GameManager")
	var nm: Node = root.get_node("NetworkManager")
	var configs: Array[Dictionary] = []
	for seat in range(4):
		configs.append({"name": "학생%d" % (seat + 1), "is_ai": false})
	gm.setup_game(configs, 600)
	gm.stop_game()
	# Four local UI instances exercise a delayed authoritative construction reply.
	# This fixture does not replace the separate real-peer network integration test.
	var maps: Array[Node] = []
	var project_idx := 0
	var terrain: String = gm.CONSTRUCTION_PROJECTS[project_idx]["terrains"][0]
	for seat in range(4):
		var map: Node = load("res://scripts/ui/VillageMap.gd").new()
		map.size = Vector2(600 + seat * 60, 500 + seat * 40)
		root.add_child(map)
		map.set_drop_enabled(true)
		map.project_drop_requested.connect(func(_project: int, _player: int, _position: Vector2): drop_requests += 1)
		map._drop_data(map.get_terrain_build_cell_center(terrain, seat), map.create_drop_payload(project_idx, seat))
		maps.append(map)
	_expect(drop_requests == 4, "Each human can submit a placement before another player's reply arrives")
	var winner_position: Vector2 = maps[0].get_terrain_build_cell_center(terrain, 0) / maps[0].size
	var built_ids: Array[int] = [project_idx]
	for map in maps:
		map.sync_projects(gm.CONSTRUCTION_PROJECTS, built_ids, {project_idx: winner_position}, {project_idx: 0}, gm.players, 10)
		var building: Control = map.placed_project_nodes[project_idx]
		_expect(building.position == map._clamp_icon_position(winner_position * map.size - map.BUILDING_SIZE * 0.5), "All four map sizes use the winning server cell, including losing local requests")
		_expect(map.pending_project_cells.is_empty() and map.reserved_cell_ids.is_empty(), "A confirmed project releases every local reservation")
		map.queue_free()
	await process_frame
	var repeated: Node = load("res://scripts/ui/VillageMap.gd").new()
	repeated.size = Vector2(600, 500)
	root.add_child(repeated)
	repeated.set_drop_enabled(true)
	drop_requests = 0
	repeated.project_drop_requested.connect(func(_project: int, _player: int, _position: Vector2): drop_requests += 1)
	for cell in range(2):
		repeated._drop_data(repeated.get_terrain_build_cell_center(terrain, cell), repeated.create_drop_payload(project_idx, 2))
	_expect(drop_requests == 1 and repeated.reserved_cell_ids.size() == 1, "Repeated placement clicks keep one request and one reserved cell")
	repeated.cancel_project_placement(project_idx)
	_expect(repeated.reserved_cell_ids.is_empty(), "Rejected requests release the reserved cell for another attempt")
	repeated.queue_free()
	await process_frame
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	main._on_start_game_requested(configs, 600)
	gm.set_process(false)
	# Reconnect snapshot fixtures: an acknowledged transition may have occurred
	# between the last received event and the host detecting the lost connection.
	nm.is_online = true
	nm.is_host = false
	nm.my_peer_id = 4
	nm.game_peer_ids.assign([1, 2, 3, 4])
	var hud: Node = main.game_board.hud
	hud._on_lap_reward_requested(3, 4, 1)
	gm.pending_lap_reward.clear()
	hud.adventure_planner.quiz_open = true
	gm.adventure_waiting_for_start = false
	gm.current_state = gm.TurnState.WAIT_ACTION
	main.game_board._on_session_restored()
	_expect(not hud.lap_reward_panel.visible and not hud.lap_reward_dimmer.visible, "A completed reward does not leave an obsolete modal over the restored board")
	_expect(not hud.adventure_planner.quiz_open and hud.adventure_planner.summary.visible, "A missed quiz-resolution event restores the materials controls")
	gm.open_market_active = true
	gm.open_market_phase = gm.OpenMarketPhase.OFFERING
	hud._on_open_market_state_changed(gm.get_open_market_state())
	hud.open_market_recipe_popover.show()
	gm.open_market_active = false
	gm.village_construction_active = true
	gm.current_state = gm.TurnState.GAME_OVER
	gm.is_game_active = false
	main.game_board._on_session_restored()
	_expect(hud.victory_modal.visible and not hud.open_market_panel.visible and not hud.open_market_dimmer.visible and not hud.open_market_recipe_popover.visible, "A construction snapshot removes the missed market overlay and recipe popover")
	# The actual rejection signal must release HUD reservations, not only map helpers.
	hud.village_map.pending_project_cells[project_idx] = terrain + ":0"
	hud.village_map.reserved_cell_ids[terrain + ":0"] = project_idx
	if nm.has_signal("game_action_rejected"):
		nm.game_action_rejected.emit("build_project", {"project_index": project_idx})
	_expect(hud.village_map.pending_project_cells.is_empty() and hud.village_map.reserved_cell_ids.is_empty(), "Network rejection frees the local construction reservation")
	nm.is_online = false
	nm.is_host = false
	main.switch_to_lobby()
	main.queue_free()
	await process_frame
	for voice in root.get_node("AudioManager").voices:
		voice.stop()
		voice.stream = null
	if failures.is_empty():
		print("[PASS] Four-player UI: construction races, repeated inputs, rejected placements, reconnect overlays")
		quit(0)
	else:
		quit(1)

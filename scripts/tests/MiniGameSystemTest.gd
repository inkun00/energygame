extends SceneTree

const BOARD_GRID = preload("res://scripts/board/BoardGrid.gd")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("[MiniGameTest] " + message)

func _run() -> void:
	await process_frame
	var game_manager = root.get_node("GameManager")
	_check(game_manager.MINIGAME_DEFINITIONS.size() == 8, "미니게임 정의는 정확히 8종이어야 합니다.")
	var tile_ids: Array[String] = []
	for tile in BOARD_GRID.TILE_DATA:
		if int(tile.get("type", -1)) == BOARD_GRID.TileType.MINIGAME:
			tile_ids.append(str(tile.get("minigame_id", "")))
	tile_ids.sort()
	var definition_ids: Array[String] = []
	for game_id_variant in game_manager.MINIGAME_DEFINITIONS.keys():
		definition_ids.append(str(game_id_variant))
	definition_ids.sort()
	_check(tile_ids == definition_ids, "8종 미니게임이 각각 하나의 보드 타일에 배치되어야 합니다.")

	var configs: Array[Dictionary] = []
	for i in range(4):
		configs.append({"name": "테스터%d" % (i + 1), "is_ai": false})
	game_manager.setup_game(configs, 600)
	var capture := {"results": []}
	game_manager.minigame_finished.connect(func(results): capture["results"] = results.duplicate(true), CONNECT_ONE_SHOT)
	game_manager._start_minigame(0, "solar_align")
	_check(int(game_manager.current_state) == 5, "미니게임 시작 시 턴 상태가 잠겨야 합니다.")
	_check(game_manager.submit_minigame_score(0, 100), "첫 점수를 제출할 수 있어야 합니다.")
	_check(not game_manager.submit_minigame_score(0, 999), "같은 플레이어의 중복 점수는 거부해야 합니다.")
	game_manager.submit_minigame_score(1, 400)
	game_manager.submit_minigame_score(2, 300)
	game_manager.submit_minigame_score(3, 200)
	var captured_results: Array = capture["results"]
	_check(captured_results.size() == 4, "전원 제출 시 결과를 즉시 확정해야 합니다.")
	if captured_results.size() == 4:
		_check(int(captured_results[0].get("player_idx", -1)) == 1, "가장 높은 점수가 1위여야 합니다.")
		_check(int(captured_results[0].get("reward", 0)) == 20, "1위 에너지 보상은 20이어야 합니다.")
	_check(int(game_manager.players[1].get("energy", 0)) == 25, "1위 플레이어의 에너지에 보상이 더해져야 합니다.")
	_check(int(game_manager.players[0].get("energy", 0)) == 6, "4위 플레이어도 참가 에너지 1을 받아야 합니다.")
	_check("solar_align" in game_manager.completed_minigame_ids, "완료한 미니게임은 다시 발동하지 않도록 기록해야 합니다.")

	var tie_capture := {"results": []}
	game_manager.minigame_finished.connect(func(results): tie_capture["results"] = results.duplicate(true), CONNECT_ONE_SHOT)
	game_manager._start_minigame(0, "wind_rhythm")
	game_manager.submit_minigame_score(0, 400)
	game_manager.submit_minigame_score(1, 400)
	game_manager.submit_minigame_score(2, 300)
	game_manager.submit_minigame_score(3, 200)
	var tie_results: Array = tie_capture["results"]
	_check(tie_results.size() == 4, "동점 라운드 결과도 네 명 모두 포함해야 합니다.")
	if tie_results.size() == 4:
		_check(int(tie_results[0]["rank"]) == 1 and int(tie_results[1]["rank"]) == 1, "동점자는 공동 1위여야 합니다.")
		_check(int(tie_results[2]["rank"]) == 3 and int(tie_results[2]["reward"]) == 5, "공동 1위 다음 순위는 3위와 에너지 5여야 합니다.")

	var modal_scene := load("res://scenes/MiniGameModal.tscn") as PackedScene
	var modal := modal_scene.instantiate()
	root.add_child(modal)
	await process_frame
	for game_id_variant in game_manager.MINIGAME_DEFINITIONS.keys():
		var game_data: Dictionary = (game_manager.MINIGAME_DEFINITIONS[game_id_variant] as Dictionary).duplicate(true)
		game_data["round_id"] = 99
		game_data["seed"] = 12345
		game_data["duration"] = 20.0
		modal._on_minigame_started(game_data)
		var minimum_children := 1 if str(game_id_variant) in ["solar_align", "wind_rhythm", "grid_balance", "standby_hunt"] else 3
		_check(modal.visible and modal.arena.get_child_count() >= minimum_children, "%s UI를 구성할 수 있어야 합니다." % game_id_variant)
		if str(game_id_variant) == "solar_align" and is_instance_valid(modal.solar_arcade):
			var first_gate: Dictionary = modal.solar_arcade.panel_gates[0]
			var gate_panels: Array = first_gate["meshes"]
			modal.solar_arcade.sun.position = modal.solar_arcade.SUN_POSITIONS[0]
			modal.solar_arcade._update_panel_gate_for_sun(first_gate)
			_check(int(first_gate["correct_lane"]) == 0, "태양이 왼쪽에 있으면 왼쪽 차선에 정답 패널이 있어야 합니다.")
			_check((gate_panels[0] as Node3D).rotation_degrees.z < 0.0, "왼쪽 태양을 향한 정답 패널은 -Z 방향으로 기울어야 합니다.")
			_check((gate_panels[0] as Node3D).position.y >= 0.65, "태양광 패널 기둥이 보이도록 모델을 지면 위로 충분히 올려야 합니다.")
			modal.solar_arcade.sun.position = modal.solar_arcade.SUN_POSITIONS[2]
			modal.solar_arcade._update_panel_gate_for_sun(first_gate)
			_check(int(first_gate["correct_lane"]) == 2, "태양이 오른쪽에 있으면 오른쪽 차선에 정답 패널이 있어야 합니다.")
			_check((gate_panels[2] as Node3D).rotation_degrees.z > 0.0, "오른쪽 태양을 향한 정답 패널은 +Z 방향으로 기울어야 합니다.")
			modal.solar_arcade._update_sun(modal.solar_arcade.SUN_MOVE_INTERVAL)
			_check(modal.solar_arcade.sun_position_index == 1, "태양은 5초마다 다음 위치로 이동해야 합니다.")
			modal.solar_arcade.sun.position = modal.solar_arcade.SUN_POSITIONS[1]
			modal.solar_arcade._update_panel_gate_for_sun(first_gate)
			_check(int(first_gate["correct_lane"]) == 1, "태양이 중앙으로 이동하면 중앙 차선에 정답 패널이 생겨야 합니다.")
			var correct_lane := int(first_gate["correct_lane"])
			modal.solar_arcade.hero_body.position.x = modal.solar_arcade.LANES[correct_lane]
			modal.solar_arcade._resolve_panel_gate(first_gate)
			_check(modal.score == 100, "햇빛 방향과 맞는 패널 차선을 통과하면 100점을 얻어야 합니다.")
			var terrain_record: Dictionary = modal.solar_arcade.terrain_obstacles[0]
			terrain_record["resolved"] = false
			modal.solar_arcade._resolve_hazard_collision(terrain_record["node"] as Node3D)
			_check(modal.solar_arcade.hero_body.velocity.z > 0.0 and modal.solar_arcade.hero_body.velocity.y > 0.0, "3D 지형물 충돌 시 캐릭터에 후방·상향 충격 속도가 적용되어야 합니다.")
			_check(bool(terrain_record["resolved"]), "충돌한 지형물은 한 번만 판정되어야 합니다.")
		if str(game_id_variant) == "wind_rhythm" and is_instance_valid(modal.wind_arcade):
			modal.wind_arcade.storm_phase = false
			modal.wind_arcade.wind_angle = 28.0
			modal.wind_arcade.turbine_yaw = 28.0
			modal.wind_arcade.wind_speed = 15
			modal.wind_arcade._score_aligned_generation(0.35, modal.wind_arcade._alignment_efficiency())
			_check(modal.score > 0, "터빈을 풍향에 맞추면 풍속에 따라 발전 점수가 쌓여야 합니다.")
			var generation_score: int = modal.score
			modal.wind_arcade.storm_phase = true
			modal.wind_arcade.phase_scored = false
			modal.wind_arcade._engage_storm_brake()
			_check(modal.score == generation_score + 75, "위험 돌풍에서 브레이크를 걸면 안전 정지 점수를 받아야 합니다.")
			var blade_count: int = modal.wind_arcade.main_blades.size()
			modal.wind_arcade.rotor_broken = false
			modal.wind_arcade._break_turbine_blades()
			_check(blade_count == 3 and modal.wind_arcade.main_blades.is_empty() and modal.wind_arcade.rotor_broken, "위험 돌풍을 막지 못하면 세 터빈 날개가 분리되어야 합니다.")
		if str(game_id_variant) == "grid_balance" and is_instance_valid(modal.grid_arcade):
			modal.grid_arcade.demand = 50.0
			modal.grid_arcade.demand_target = 100.0
			modal.grid_arcade._process(0.10)
			_check(modal.grid_arcade.demand > 50.0 and modal.grid_arcade.demand < 100.0, "도시 수요 막대는 새 목표로 순간 이동하지 않고 아날로그 방식으로 움직여야 합니다.")
			modal.grid_arcade.demand = 70.0
			modal.grid_arcade.demand_target = 70.0
			modal.grid_arcade.supply = 70.0
			modal.grid_arcade.score_tick = 0.19
			modal.grid_arcade._process(0.02)
			var precise_sync_score: int = modal.score
			modal.score = 0
			modal.grid_arcade.supply = 110.0
			modal.grid_arcade.score_tick = 0.19
			modal.grid_arcade._process(0.02)
			var wide_gap_score: int = modal.score
			_check(precise_sync_score > wide_gap_score, "공급·수요 간격이 작을수록 동기화 점수가 더 커야 합니다.")
		if str(game_id_variant) == "standby_hunt" and is_instance_valid(modal.standby_arcade):
			var waste_record: Dictionary = {}
			var active_record: Dictionary = {}
			for device_record_variant in modal.standby_arcade.device_records:
				var device_record: Dictionary = device_record_variant
				if bool(device_record["waste"]) and waste_record.is_empty():
					waste_record = device_record
				elif not bool(device_record["waste"]) and active_record.is_empty():
					active_record = device_record
			_check(not waste_record.is_empty() and not active_record.is_empty(), "각 대기전력 웨이브에는 차단할 기기와 사용 중인 기기가 함께 있어야 합니다.")
			if not waste_record.is_empty() and not active_record.is_empty():
				modal.standby_arcade._resolve_device(waste_record, true)
				var standby_score: int = modal.score
				_check(standby_score >= 101 and bool(waste_record["resolved"]), "대기전력 기기의 플러그를 뽑으면 소비 전력에 따라 점수를 얻어야 합니다.")
				modal.standby_arcade._resolve_device(active_record, true)
				_check(modal.score == maxi(0, standby_score - 48), "사용 중인 기기의 전원을 끄면 48점이 감점되어야 합니다.")
		modal.cancel_minigame()
	modal.queue_free()
	game_manager.active_minigame = (game_manager.MINIGAME_DEFINITIONS["standby_hunt"] as Dictionary).duplicate(true)
	game_manager.active_minigame["seed"] = 24680
	var standby_ai_score: int = game_manager._generate_ai_minigame_score(1)
	_check(standby_ai_score > 0 and standby_ai_score <= game_manager.MINIGAME_SCORE_LIMIT, "AI도 대기전력 기기 구분 결과로 유효한 점수를 얻어야 합니다.")

	game_manager.stop_game()
	if failures.is_empty():
		print("[MiniGameTest] PASS · 8 games, tiles, simultaneous ranking rewards, UI")
		quit(0)
	else:
		print("[MiniGameTest] FAIL · %d issue(s)" % failures.size())
		quit(1)

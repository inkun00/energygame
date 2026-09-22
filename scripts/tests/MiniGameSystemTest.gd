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
	_check(game_manager.MINIGAME_DEFINITIONS.size() == 9, "미니게임 정의는 정확히 9종이어야 합니다.")
	var tile_ids: Array[String] = []
	for tile in BOARD_GRID.TILE_DATA:
		if int(tile.get("type", -1)) == BOARD_GRID.TileType.MINIGAME:
			tile_ids.append(str(tile.get("minigame_id", "")))
	tile_ids.sort()
	var definition_ids: Array[String] = []
	for game_id_variant in game_manager.MINIGAME_DEFINITIONS.keys():
		definition_ids.append(str(game_id_variant))
	definition_ids.sort()
	_check(tile_ids == definition_ids, "9종 미니게임이 각각 하나의 보드 타일에 배치되어야 합니다.")

	var configs: Array[Dictionary] = []
	for i in range(4):
		configs.append({"name": "테스터%d" % (i + 1), "is_ai": false})
	game_manager.setup_game(configs, 600)
	var capture := {"results": []}
	game_manager.minigame_finished.connect(func(results): capture["results"] = results.duplicate(true), CONNECT_ONE_SHOT)
	game_manager._start_minigame(0, "solar_align")
	_check(int(game_manager.current_state) == 5, "미니게임 시작 시 턴 상태가 잠겨야 합니다.")
	_check(str(game_manager.active_minigame.get("phase", "")) == "ready", "사람이 참가하면 모두 준비할 때까지 대기해야 합니다.")
	_check(not game_manager.submit_minigame_score(0, 100), "공통 시작 전 점수 제출은 거부해야 합니다.")
	var first_round_id := int(game_manager.active_minigame.get("round_id", -1))
	_check(not game_manager.start_minigame_action(0, first_round_id - 1), "지난 라운드의 준비 신호를 거부해야 합니다.")
	for player_idx in range(3):
		_check(game_manager.start_minigame_action(player_idx, first_round_id), "각 플레이어의 준비 신호를 받아야 합니다.")
	_check(str(game_manager.active_minigame.get("phase", "")) == "ready", "한 명이라도 준비 전이면 시작하지 않아야 합니다.")
	_check(game_manager.start_minigame_action(3, first_round_id), "마지막 플레이어의 준비 신호를 받아야 합니다.")
	_check(str(game_manager.active_minigame.get("phase", "")) == "countdown", "전원 준비 후 공통 카운트다운을 시작해야 합니다.")
	_check(not game_manager.submit_minigame_score(0, 100), "카운트다운 중 점수 제출은 거부해야 합니다.")
	game_manager._update_minigame(2.0)
	_check(str(game_manager.active_minigame.get("phase", "")) == "countdown", "카운트다운 종료 전에는 조작 시간이 흐르지 않아야 합니다.")
	game_manager._update_minigame(1.1)
	_check(str(game_manager.active_minigame.get("phase", "")) == "playing", "공통 카운트다운 종료 시 모두 플레이해야 합니다.")
	_check(not game_manager.submit_minigame_score(0, 100, {}, first_round_id - 1), "지난 라운드 점수가 새 라운드에 섞이면 안 됩니다.")
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
	var tie_round_id := int(game_manager.active_minigame.get("round_id", -1))
	for player_idx in range(4):
		game_manager.start_minigame_action(player_idx, tie_round_id)
	game_manager._update_minigame(game_manager.MINIGAME_READY_COUNTDOWN_SECONDS)
	game_manager.submit_minigame_score(0, 400)
	game_manager.submit_minigame_score(1, 400)
	game_manager.submit_minigame_score(2, 300)
	game_manager.submit_minigame_score(3, 200)
	var tie_results: Array = tie_capture["results"]
	_check(tie_results.size() == 4, "동점 라운드 결과도 네 명 모두 포함해야 합니다.")
	if tie_results.size() == 4:
		_check(int(tie_results[0]["rank"]) == 1 and int(tie_results[1]["rank"]) == 1, "동점자는 공동 1위여야 합니다.")
		_check(int(tie_results[0]["reward"]) == 20 and int(tie_results[1]["reward"]) == 20, "공동 1위 두 명 모두 에너지 20을 받아야 합니다.")
		_check(int(tie_results[2]["rank"]) == 3 and int(tie_results[2]["reward"]) == 5, "공동 1위 다음 순위는 3위와 에너지 5여야 합니다.")
		_check(int(tie_results[3]["rank"]) == 4 and int(tie_results[3]["reward"]) == 1, "공동 1위가 있어도 마지막 참가자는 4위 에너지 1을 받아야 합니다.")
	game_manager._start_minigame(0, "eco_commute")
	_check(float(game_manager.active_minigame.get("duration", 0.0)) == 60.0 and is_equal_approx(game_manager.minigame_time_remaining, 60.0 + game_manager.MINIGAME_SUBMISSION_GRACE_SECONDS), "통학 버스만 60초로 진행해야 합니다.")
	game_manager._update_minigame(45.1)
	_check(str(game_manager.active_minigame.get("phase", "")) == "countdown", "안내 제한시간이 끝나면 자동으로 공통 카운트다운을 시작해야 합니다.")
	game_manager._update_minigame(game_manager.MINIGAME_READY_COUNTDOWN_SECONDS)
	for player_idx in range(4):
		game_manager.submit_minigame_score(player_idx, 0)
	game_manager._start_minigame(0, "heat_leak")
	var disconnect_round_id := int(game_manager.active_minigame.get("round_id", -1))
	for player_idx in range(3):
		game_manager.start_minigame_action(player_idx, disconnect_round_id)
	game_manager.players[3]["is_ai"] = true
	game_manager._update_minigame(0.05)
	_check(str(game_manager.active_minigame.get("phase", "")) == "countdown", "준비 전 연결이 끊겨 AI로 바뀐 자리는 대기를 막지 않아야 합니다.")
	game_manager._update_minigame(game_manager.MINIGAME_READY_COUNTDOWN_SECONDS)
	for player_idx in range(4):
		game_manager.submit_minigame_score(player_idx, 0)

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
		var minimum_children := 1 if str(game_id_variant) in ["solar_align", "wind_rhythm", "grid_balance", "standby_hunt", "hydro_gate", "energy_sort", "battery_relay", "eco_commute", "heat_leak"] else 3
		_check(modal.visible and modal.arena.get_child_count() >= minimum_children, "%s UI를 구성할 수 있어야 합니다." % game_id_variant)
		_check(modal.is_guide_open() and is_instance_valid(modal.guide_panel) and modal.guide_panel.visible, "%s 진입 시 게임방법 안내 팝업이 표시되어야 합니다." % game_id_variant)
		modal.dismiss_guide()
		_check(not modal.is_guide_open() and not modal.guide_panel.visible, "%s 게임방법 안내 닫기 후 게임이 진행 상태가 되어야 합니다." % game_id_variant)
		_check(not modal.round_started_locally, "%s 안내창을 닫아도 공통 시작 전에는 조작이 잠겨야 합니다." % game_id_variant)
		modal._on_submission_changed({"game": {"round_id": 99, "phase": "playing"}, "time_remaining": 21.0, "player_count": 4, "submitted_count": 0})
		_check(modal.round_started_locally, "%s 방장 시작 신호를 받은 뒤에만 조작을 시작해야 합니다." % game_id_variant)
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
			var standby_game = modal.standby_arcade
			_check(standby_game.barrier_records.size() == 3, "거실·주방·세탁실에 점프로 넘어야 하는 가구가 있어야 합니다.")
			for barrier_variant in standby_game.barrier_records:
				var barrier: Dictionary = barrier_variant
				var from_x: float = float(barrier["x"]) - float(barrier["half_width"]) - 0.2
				var beyond_x: float = float(barrier["x"]) + float(barrier["half_width"]) + 0.2
				standby_game.hero.position.y = standby_game.GROUND_Y
				_check(is_equal_approx(standby_game._constrain_by_furniture(from_x, beyond_x), float(barrier["x"]) - float(barrier["half_width"])), "지상에서는 점프 가구를 통과할 수 없어야 합니다.")
				standby_game.vertical_velocity = standby_game.JUMP_IMPULSE
				standby_game._update_jump(0.18)
				_check(standby_game.hero.position.y >= float(barrier["clearance"]) and is_equal_approx(standby_game._constrain_by_furniture(from_x, beyond_x), beyond_x), "점프해서 가구 높이를 넘으면 이동할 수 있어야 합니다.")
				standby_game.hero.position.y = standby_game.GROUND_Y
				standby_game.vertical_velocity = 0.0
			var active_names: Array[String] = []
			for spec in standby_game.DEVICE_SPECS:
				_check(spec["scene"] is PackedScene and str((spec["scene"] as PackedScene).resource_path).ends_with(".glb"), "전자제품은 코드 도형이 아닌 CC0 GLB 모델로 표현해야 합니다.")
				if not bool(spec["can_standby"]):
					active_names.append(str(spec["name"]))
			_check("음악 재생 스피커" in active_names and "조리 중 토스터" in active_names and "냉장고" in active_names, "정상 사용 중인 스피커·토스터·냉장고가 항상 배치되어야 합니다.")
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
				modal.standby_arcade._resolve_device(active_record, false)
				_check(modal.score == 0, "사용 중인 기기를 지나가거나 걷기만 해서는 대기전력 절감 점수를 얻지 않아야 합니다.")
				modal.standby_arcade._resolve_device(waste_record, true)
				var standby_score: int = modal.score
				_check(standby_score == modal.standby_arcade.score_for_saved_watts(int(waste_record["watt"])) and bool(waste_record["resolved"]), "대기전력 기기의 플러그를 뽑으면 절감한 W에 비례해 점수를 얻어야 합니다.")
				_check(modal.standby_arcade.saved_watts == int(waste_record["watt"]) and (waste_record["label"] as Label3D).text.contains("0 W"), "플러그를 뽑으면 해당 기기의 소비 전력이 0 W가 되고 절감량에 누적되어야 합니다.")
				active_record["resolved"] = false
				modal.standby_arcade._resolve_device(active_record, true)
				_check(modal.score == maxi(0, standby_score - 48), "사용 중인 기기의 전원을 끄면 48점이 감점되어야 합니다.")
				var before_next_house: int = modal.score
				modal.standby_arcade._start_new_lap()
				_check(modal.score == before_next_house, "다음 집에 도착한 것만으로는 대기전력 절감 점수를 받지 않아야 합니다.")
		if str(game_id_variant) == "hydro_gate" and is_instance_valid(modal.hydro_arcade):
			var hydro = modal.hydro_arcade
			_check(hydro.gate_doors.size() == 3 and hydro.active_channels.size() == 3, "서로 다른 높이의 세 수문과 발전 수로가 있어야 합니다.")
			_check(hydro.inflow_for_time(1.0, 12345) != hydro.inflow_for_time(6.0, 12345), "강우 예보에 따라 유입량이 달라져야 합니다.")
			_check(hydro.rain_seed == 12345 and hydro.inflow_for_time(6.0, hydro.rain_seed) == hydro.inflow_for_time(6.0, 12345), "같은 라운드에는 같은 비가 내려야 합니다.")
			_check(hydro.dry_overflow_seconds(99.0, 0.0, 12345) < 1.0 and hydro.dry_overflow_seconds(30.0, 29.0, 12345) < 0.0, "범람 예측은 앞으로 바뀔 비와 남은 경기 시간을 반영해야 합니다.")
			_check(hydro.projected_overflow_seconds(80.0, 0.0, 12345, 0) < 0.0, "방류 중 범람 예측은 수문으로 빠져나가는 유량도 반영해야 합니다.")
			for weather_seed in range(3):
				_check(hydro.dry_overflow_seconds(hydro.initial_level_for_seed(weather_seed), 0.0, weather_seed) < 10.0, "방류하지 않으면 초반 폭우에 넘쳐 타이밍 판단이 필요해야 합니다.")
			_check(hydro.rain_streaks.size() == 24 and hydro.forecast_label.text.contains("뒤"), "비 강도의 시각 효과와 다음 예보가 보여야 합니다.")
			hydro.hero_x = 2.2
			hydro.hero_y = hydro.platform_height(0)
			hydro.hero_floor_index = 0
			hydro._advance_hero(0.02, 0.0, true)
			for physics_step in range(75):
				hydro._advance_hero(0.02, 0.0, false)
			_check(hydro.hero_floor_index == 1, "하단 발판에서 점프해 중단 발판에 착지해야 합니다.")
			hydro._advance_hero(0.02, 0.0, true)
			for physics_step in range(75):
				hydro._advance_hero(0.02, 0.0, false)
			_check(hydro.hero_floor_index == 2, "중단 발판에서 다시 점프해 상단 발판에 착지해야 합니다.")
			for physics_step in range(28):
				hydro._advance_hero(0.02, -1.0, false)
			_check(hydro.selected_gate == 2, "상단 레버까지 직접 달려가야 조작할 수 있어야 합니다.")
			_check(hydro.flow_for_gate(60.0, 2) == 0.0 and hydro.flow_for_gate(80.0, 2) > 0.0, "상단 수문은 수면이 닿은 뒤에야 물이 흘러야 합니다.")
			_check(hydro.power_for_gate(90.0, 1) > hydro.power_for_gate(65.0, 1), "같은 수문도 늦게 열어 낙차와 유량이 커지면 발전량이 늘어야 합니다.")
			var surface_y: float = hydro.RESERVOIR_BOTTOM + 0.8 * hydro.RESERVOIR_HEIGHT
			_check(is_equal_approx(hydro.head_for_level(80.0), (surface_y - hydro.TAILWATER_Y) * 10.0), "표시된 낙차는 화면의 수면과 터빈 출구 높이 차이여야 합니다.")
			var expected_power: float = 9.81 * hydro.flow_for_gate(80.0, 1) * hydro.head_for_level(80.0) * hydro.TURBINE_EFFICIENCY / 1000.0
			_check(is_equal_approx(hydro.power_for_gate(80.0, 1), expected_power), "발전 출력은 유량·낙차·효율의 물리 관계를 따라야 합니다.")
			hydro.water_level = 60.0
			hydro._tap_selected_gate()
			_check(hydro.charge == 0.0 and hydro.open_gate == -1, "물이 닿지 않은 상단 수문은 연타해도 열리지 않아야 합니다.")
			hydro.hero_floor_index = 0
			hydro.hero_x = hydro.LEVER_X[0]
			hydro.hero_y = hydro.platform_height(0)
			hydro._update_station()
			for tap in range(3):
				hydro._tap_selected_gate()
			var partially_charged: float = hydro.charge
			hydro._advance_simulation(0.35)
			_check(partially_charged > 0.0 and hydro.charge < partially_charged, "연타를 중단하면 수문 개방 게이지가 빠르게 감소해야 합니다.")
			hydro.water_level = 84.0
			hydro.hero_floor_index = 2
			hydro.hero_x = hydro.LEVER_X[2]
			hydro.hero_y = hydro.platform_height(2)
			hydro._update_station()
			for tap in range(7):
				hydro._tap_selected_gate()
			_check(hydro.open_gate == 2 and hydro.charge == 0.0 and hydro.active_channels[2].visible, "충분히 연타하면 잠긴 상단 수문이 열리고 물이 터빈으로 흘러야 합니다.")
			var before_level: float = hydro.water_level
			var before_rotation: float = hydro.turbine.rotation_degrees.z
			hydro._animate_world(0.2)
			hydro._advance_simulation(0.25)
			_check(hydro.water_level < before_level and hydro.generated_kwh > 0.0 and modal.score > 0, "수문 방류로 저수위가 내려가며 전기 생산량과 점수가 쌓여야 합니다.")
			_check(hydro.turbine.rotation_degrees.z > before_rotation and hydro.generator_light.visible and hydro.city_light.visible, "물의 낙차가 터빈·발전기·도시 점등으로 이어져야 합니다.")
			hydro._close_open_gate(true)
			_check(hydro.open_gate == -1 and not hydro.active_channels[2].visible, "플레이어가 같은 레버에서 직접 방류를 끝낼 수 있어야 합니다.")
			hydro.water_level = 99.5
			hydro._advance_simulation(0.1)
			_check(hydro.overflowed and not hydro.running and hydro.result_label.visible, "수문 개방이 늦어 100%가 되면 즉시 게임 오버가 보여야 합니다.")
		if str(game_id_variant) == "energy_sort" and is_instance_valid(modal.sort_arcade):
			var sorter = modal.sort_arcade
			var seen_sources := {}
			var renewable_count := 0
			for source_index in range(6):
				var source: Dictionary = sorter.source_for_step(12345, source_index)
				seen_sources[str(source["name"])] = true
				if int(source["kind"]) == 0:
					renewable_count += 1
			_check(seen_sources.size() == 6 and renewable_count == 3, "한 묶음에는 다시 얻는 세 원천과 땅속 연료 세 종류가 있어야 합니다.")
			var original_source: Dictionary = sorter.current_source.duplicate(true)
			sorter._deliver(int(original_source["kind"]))
			_check(modal.score == sorter.CORRECT_POINTS and sorter.item_step == 1, "알맞은 배송장에 도착하면 점수가 오르고 다음 물건을 받아야 합니다.")
			var wrong_source: Dictionary = sorter.current_source.duplicate(true)
			sorter._deliver(1 - int(wrong_source["kind"]))
			_check(modal.score == sorter.CORRECT_POINTS - sorter.WRONG_PENALTY, "잘못 배송하면 점수가 줄어야 합니다.")
			_check(sorter.waiting_for_release and sorter.hero_x == 0.0, "같은 방향 키를 계속 누른 채 자동 연속 배송할 수 없어야 합니다.")
		if str(game_id_variant) == "battery_relay" and is_instance_valid(modal.battery_arcade):
			var shuttle = modal.battery_arcade
			_check(shuttle.is_sunny_at(0.0) and not shuttle.is_sunny_at(5.1) and shuttle.is_sunny_at(10.1), "5초마다 햇빛과 구름 주기가 바뀌어야 합니다.")
			_check(shuttle.battery_units == 1 and shuttle.battery_cells.size() == 4, "배터리는 처음에 1칸이 있고 최대 4칸을 저장해야 합니다.")
			shuttle.hero_x = shuttle.SOLAR_X
			shuttle._try_station_action()
			_check(shuttle.cargo == 1 and shuttle.battery_units == 1, "햇빛 때 태양광에서 남는 전기를 집어야 합니다.")
			shuttle.hero_x = shuttle.BATTERY_X
			shuttle._try_station_action()
			_check(shuttle.cargo == 0 and shuttle.battery_units == 2 and modal.score == shuttle.STORE_POINTS, "배터리로 옮겨야 충전되고 점수를 받아야 합니다.")
			shuttle.elapsed = 5.1
			shuttle._update_visuals()
			_check(not shuttle.sun.visible and shuttle.cloud.visible, "발전이 줄어드는 구름 장면이 보여야 합니다.")
			shuttle._try_station_action()
			_check(shuttle.cargo == 2 and shuttle.battery_units == 1, "흐릴 때 저장된 전기를 배터리에서 꺼내야 합니다.")
			shuttle.hero_x = shuttle.CITY_X
			shuttle._try_station_action()
			shuttle._update_visuals()
			_check(shuttle.cargo == 0 and modal.score == shuttle.STORE_POINTS + shuttle.SUPPLY_POINTS and shuttle.city_flash_remaining > 0.0, "도시에 전기를 전해야 불이 켜지고 큰 점수를 받아야 합니다.")
			shuttle.hero_x = shuttle.BATTERY_X
			shuttle.battery_units = 0
			shuttle._try_station_action()
			_check(shuttle.cargo == 0, "배터리가 비었으면 도시에 보낼 전기를 꺼낼 수 없어야 합니다.")
			shuttle.elapsed = 0.0
			shuttle.hero_x = shuttle.SOLAR_X
			shuttle.battery_units = shuttle.BATTERY_CAPACITY
			shuttle._try_station_action()
			_check(shuttle.cargo == 0, "배터리가 가득 차면 남는 전기를 더 집을 수 없어야 합니다.")
		if str(game_id_variant) == "eco_commute" and is_instance_valid(modal.commute_arcade):
			var commute = modal.commute_arcade
			_check(commute.BUS_CAPACITY == 45 and commute.passenger_label.text.contains("45명"), "통학 버스는 45인승이어야 합니다.")
			_check(commute.STOP_OFFSETS[1] - commute.STOP_OFFSETS[0] >= 17.0, "정류장 간격이 이전보다 충분히 넓어야 합니다.")
			_check(commute.energy_per_person(45, commute.SCHOOL_OFFSET) < commute.energy_per_person(10, commute.SCHOOL_OFFSET), "같은 길을 45명이 함께 타면 10명일 때보다 1인당 에너지가 적어야 합니다.")
			_check(commute.score_for_trip(45, commute.SCHOOL_OFFSET) > commute.score_for_trip(10, commute.SCHOOL_OFFSET) and commute.score_for_trip(45, commute.SCHOOL_OFFSET) < game_manager.MINIGAME_SCORE_LIMIT, "45인승 점수가 더 높지만 한 번에 전체 점수 상한에 닿지 않아야 합니다.")
			_check(commute.bus.get_child(0).scene_file_path.ends_with("schoolbus.glb") and commute.bus_door_left != null and commute.bus_door_right != null, "오픈소스 GLB 버스에 움직이는 출입문이 있어야 합니다.")
			_check(str(game_manager.MINIGAME_DEFINITIONS["eco_commute"]["input_hint"]).contains("D 길게 전진 · A 길게 후진 · S 정차"), "버스 조작 안내는 D 전진 가속, A 후진 가속, S 정차를 표시해야 합니다.")
			var first_stop: Dictionary = (commute.segments[0] as Dictionary)["stops"][0]
			_check((first_stop["students"] as Array)[0].scene_file_path.ends_with("character-a.glb"), "학생도 코드 형상이 아닌 오픈소스 GLB 에셋이어야 합니다.")
			_check((first_stop["states"] as Array).size() == 17 and int(first_stop["waiting"]) == 10, "첫 정류장에는 먼저 기다리는 10명과 뛰어올 7명이 있어야 합니다.")
			var first_student: Dictionary = (first_stop["states"] as Array)[0]
			_check(first_student["animator"] != null and (first_student["animator"] as AnimationPlayer).has_animation("walk"), "대기 학생은 실제 걷기 애니메이션을 사용해야 합니다.")
			_check(commute.bus_speed == 0.0 and commute.bus_x == 0.0, "버스는 시작할 때 자동으로 달리지 않아야 합니다.")
			commute._step_vehicle(0.5, false, false, false)
			_check(commute.bus_speed == 0.0 and commute.bus_x == 0.0, "가속 입력이 없으면 정지 상태를 유지해야 합니다.")
			commute._step_vehicle(0.5, true, false, false)
			_check(commute.bus_speed > 0.0 and commute.bus_x > 0.0, "가속 입력으로만 앞으로 달려야 합니다.")
			var forward_speed: float = commute.bus_speed
			commute._step_vehicle(0.25, true, false, false)
			_check(commute.bus_speed > forward_speed, "D를 오래 누를수록 버스의 전진 속도가 증가해야 합니다.")
			commute._step_vehicle(0.5, false, true, false)
			_check(commute.bus_speed == 0.0, "제동으로 완전히 멈출 수 있어야 합니다.")
			var before_reverse: float = commute.bus_x
			commute._step_vehicle(0.2, false, false, true)
			var first_reverse_speed: float = commute.bus_speed
			commute._step_vehicle(0.2, false, false, true)
			_check(commute.bus_x < before_reverse and commute.bus_speed < first_reverse_speed, "A를 오래 누르면 뒤로 가면서 후진 속도가 증가해야 합니다.")
			commute.bus_x = commute.STOP_OFFSETS[0]
			commute.bus_speed = 0.0
			commute._animate_bus_door(0.5)
			_check(commute.bus_door_open == 1.0 and commute.bus_door_left.position.x < 0.93, "정류장에 멈추면 버스 문이 실제로 열려야 합니다.")
			commute.bus_speed = 1.0
			commute._animate_bus_door(0.5)
			_check(commute.bus_door_open == 0.0, "버스가 다시 출발하면 문이 닫혀야 합니다.")
			commute._attempt_pickup()
			_check(commute.passengers == 0, "달리는 버스에서는 학생을 태울 수 없어야 합니다.")
			commute.bus_speed = 0.0
			commute._attempt_pickup()
			_check(commute.passengers == 10 and int(first_stop["waiting"]) == 0 and modal.score == 0, "먼저 기다리는 10명만 즉시 태우고 학교 도착 전에는 점수를 주지 않아야 합니다.")
			_check(commute.notice.contains("기다려 Space 또는 출발"), "늦게 오는 학생을 기다릴지 출발할지 선택지가 보여야 합니다.")
			commute._animate_students(10.0)
			commute._attempt_pickup()
			_check(commute.passengers == 17, "버스가 기다리면 뒤늦게 뛰어온 7명도 탈 수 있어야 합니다.")
			var second_stop: Dictionary = (commute.segments[0] as Dictionary)["stops"][1]
			commute.bus_x = commute.STOP_OFFSETS[1] - 6.0
			commute._animate_students(0.0)
			var runner: Dictionary = (second_stop["states"] as Array)[8]
			var initial_runner_x: float = (runner["node"] as Node3D).position.x
			commute._animate_students(0.5)
			_check((runner["node"] as Node3D).position.x < initial_runner_x and not bool(runner["arrived"]), "늦은 학생은 버스가 접근할 때 정류장으로 뛰어와야 합니다.")
			_check((runner["animator"] as AnimationPlayer).current_animation == "sprint", "뛰어오는 학생은 실제 달리기 애니메이션을 재생해야 합니다.")
			commute.bus_x = commute.STOP_OFFSETS[1]
			commute._attempt_pickup()
			_check(commute.passengers == 25 and not bool(runner["boarded"]), "먼저 도착한 학생만 탑승하고 달려오는 학생은 기다려야 합니다.")
			commute._animate_students(10.0)
			commute._attempt_pickup()
			_check(commute.passengers == 35 and bool(runner["boarded"]), "늦게 도착한 10명도 기다린 후 탑승할 수 있어야 합니다.")
			commute.bus_x = commute.STOP_OFFSETS[2]
			commute._animate_students(0.0)
			commute._attempt_pickup()
			_check(commute.passengers == 43, "세 번째 정류장에서도 이미 도착한 학생을 태울 수 있어야 합니다.")
			commute._animate_students(10.0)
			commute._attempt_pickup()
			_check(commute.passengers == 45 and commute.passenger_label.text.contains("45 / 45"), "기다린 학생을 태우되 45명 정원을 넘지 않아야 합니다.")
			commute.bus_x = commute.SCHOOL_OFFSET + commute.SCHOOL_REACH + 0.2
			commute.route_distance = commute.SCHOOL_OFFSET
			commute.bus_speed = 0.0
			commute._check_school_stop()
			_check(commute.passengers == 45 and modal.score == 0, "하차 구역 밖에 정차하면 학생이 내리거나 점수를 얻지 않아야 합니다.")
			commute.bus_x = commute.SCHOOL_OFFSET + 0.1
			commute.bus_speed = 1.0
			commute._check_school_stop()
			_check(commute.passengers == 45 and modal.score == 0, "학교 하차 구역을 주행 중일 때는 하차·득점하지 않아야 합니다.")
			commute.bus_speed = 0.0
			commute._check_school_stop()
			_check(commute.passengers == 0 and commute.dropped_students.size() == 45 and modal.score == commute.score_for_trip(45, commute.SCHOOL_OFFSET), "학교 노란 구역에 정차하면 학생 45명이 실제로 내려 학교로 걸어가고 점수를 주어야 합니다.")
			commute._animate_bus_door(0.5)
			_check(commute.bus_door_open == 1.0, "학교에 정차하면 버스 문이 열려야 합니다.")
			commute._animate_school_doors(0.5)
			var school: Dictionary = commute.segments[0]
			_check(float(school["school_door_open"]) == 1.0 and (school["school_door_left"] as Node3D).position.x < commute.SCHOOL_OFFSET + commute.SCHOOL_ENTRANCE_OFFSET - 0.13, "학생들이 들어갈 때 학교 문도 열려야 합니다.")
			commute._animate_dropoff_students(0.1)
			var visible_exits := 0
			for exiting in commute.dropped_students:
				if is_instance_valid(exiting["node"]):
					visible_exits += 1
			_check(visible_exits == 2, "45명 하차 모델은 한 명씩 등장해 렌더링 부하를 제한해야 합니다.")
			commute._animate_dropoff_students(0.5)
			var first_exit: Dictionary = commute.dropped_students[0]
			_check(is_instance_valid(first_exit["node"]) and (first_exit["node"] as Node3D).position.z < 2.4 and is_equal_approx((first_exit["node"] as Node3D).rotation.y, PI), "하차 학생은 등을 보이며 학교 입구를 향해 걸어가야 합니다.")
			commute._animate_dropoff_students(10.0)
			commute._animate_school_doors(0.5)
			_check(commute.dropped_students.is_empty() and float(school["school_door_open"]) == 0.0, "45명 모두 학교 안으로 들어가면 학교 문이 다시 닫혀야 합니다.")
			var score_after_dropoff: int = modal.score
			commute._check_school_stop()
			_check(modal.score == score_after_dropoff, "같은 하차 지점에서 중복 점수를 받을 수 없어야 합니다.")
			commute.bus_x = commute.SEGMENT_LENGTH + 1.0
			commute._ensure_segments()
			_check(commute.segments.has(1) and commute.bus_x > commute.SCHOOL_OFFSET, "길은 끊기지 않고 다음 구간으로 이어져야 합니다.")
		if str(game_id_variant) == "heat_leak" and is_instance_valid(modal.heat_arcade):
			var heat = modal.heat_arcade
			_check(heat.windows.size() == 6 and heat._open_window_count() == 3, "여섯 창문 중 세 곳이 열린 상태로 시작해야 합니다.")
			_check((heat.windows[0]["model"] as Node3D).scene_file_path.ends_with("wallWindow.glb") and heat.windows[0]["pane"] != null, "창틀과 움직이는 창짝은 오픈소스 3D 모델이어야 합니다.")
			_check(heat.score_for_close(1.0) > heat.score_for_close(7.0), "더운 공기가 들어오기 전에 창문을 닫으면 점수가 더 높아야 합니다.")
			var first_open: Dictionary = {}
			for window in heat.windows:
				if bool(window["open"]):
					first_open = window
					break
			heat._animate_heat(0.5)
			_check(not first_open.is_empty() and (first_open["pane"] as Node3D).rotation.y > 0.0 and (first_open["status"] as Node3D).visible, "열린 창문은 오픈소스 창짝이 회전한 모습으로 보여야 합니다.")
			var used_before: float = heat.cooling_used
			heat._process(1.0)
			var open_window_use: float = heat.cooling_used - used_before
			heat.hero_x = float(first_open["x"])
			heat._try_close()
			heat._animate_heat(0.5)
			_check(not bool(first_open["open"]) and is_zero_approx((first_open["pane"] as Node3D).rotation.y) and modal.score > 0, "Space로 창문을 닫으면 창짝이 닫히고 점수를 얻어야 합니다.")
			_check(heat._open_window_count() == 2, "창문 하나를 닫으면 열린 창문 수가 줄어야 합니다.")
			var used_after_close: float = heat.cooling_used
			heat._process(1.0)
			_check(heat.cooling_used - used_after_close < open_window_use and heat.heater_label.text.contains("+0.9/초"), "창문을 닫으면 실제 냉방 사용 속도가 낮아지고 화면에도 표시되어야 합니다.")
			heat.elapsed = 6.0
			heat._spawn_wave(1)
			_check(heat._open_window_count() >= 3, "더운 바람이 다시 불면 새로운 창문이 열려야 합니다.")
		modal.cancel_minigame()
	modal.queue_free()
	game_manager.active_minigame = (game_manager.MINIGAME_DEFINITIONS["standby_hunt"] as Dictionary).duplicate(true)
	game_manager.active_minigame["seed"] = 24680
	var standby_ai_score: int = game_manager._generate_ai_minigame_score(1)
	_check(standby_ai_score > 0 and standby_ai_score <= game_manager.MINIGAME_SCORE_LIMIT, "AI도 대기전력 기기 구분 결과로 유효한 점수를 얻어야 합니다.")
	game_manager.active_minigame = (game_manager.MINIGAME_DEFINITIONS["hydro_gate"] as Dictionary).duplicate(true)
	game_manager.active_minigame["seed"] = 13579
	var hydro_ai_score: int = game_manager._generate_ai_minigame_score(1)
	_check(hydro_ai_score > 0 and hydro_ai_score <= game_manager.MINIGAME_SCORE_LIMIT, "AI도 물을 모아 수문을 연타로 열고 낙차를 이용해 점수를 얻어야 합니다.")
	var ai_scores: Array[int] = []
	for seed_index in range(12):
		game_manager.active_minigame["seed"] = 20000 + seed_index
		for ai_index in range(1, 4):
			ai_scores.append(game_manager._generate_ai_minigame_score(ai_index))
	var positive_count := 0
	for ai_score in ai_scores:
		if ai_score > 0:
			positive_count += 1
	_check(positive_count >= 25 and ai_scores.min() < ai_scores.max(), "AI도 성공과 늦은 개방·넘침에 따라 서로 다른 수력 점수를 얻어야 합니다.")
	game_manager.active_minigame = (game_manager.MINIGAME_DEFINITIONS["energy_sort"] as Dictionary).duplicate(true)
	game_manager.active_minigame["seed"] = 13579
	var sort_ai_score: int = game_manager._generate_ai_minigame_score(1)
	_check(sort_ai_score > 0 and sort_ai_score <= game_manager.MINIGAME_SCORE_LIMIT, "AI도 30초간 여섯 에너지원의 배송을 판단해 점수를 얻어야 합니다.")
	game_manager.active_minigame = (game_manager.MINIGAME_DEFINITIONS["battery_relay"] as Dictionary).duplicate(true)
	game_manager.active_minigame["seed"] = 13579
	var battery_ai_score: int = game_manager._generate_ai_minigame_score(1)
	_check(battery_ai_score > 0 and battery_ai_score <= game_manager.MINIGAME_SCORE_LIMIT, "AI도 남을 때 충전하고 부족할 때 도시로 공급해 점수를 얻어야 합니다.")
	game_manager.active_minigame = (game_manager.MINIGAME_DEFINITIONS["eco_commute"] as Dictionary).duplicate(true)
	game_manager.active_minigame["seed"] = 13579
	var commute_ai_score: int = game_manager._generate_ai_minigame_score(1)
	_check(commute_ai_score > 0 and commute_ai_score <= game_manager.MINIGAME_SCORE_LIMIT, "AI도 친구를 태워 학교에 데려온 운행으로 점수를 얻어야 합니다.")
	game_manager.active_minigame = (game_manager.MINIGAME_DEFINITIONS["heat_leak"] as Dictionary).duplicate(true)
	game_manager.active_minigame["seed"] = 13579
	var heat_ai_score: int = game_manager._generate_ai_minigame_score(1)
	_check(heat_ai_score > 0 and heat_ai_score <= game_manager.MINIGAME_SCORE_LIMIT, "AI도 열린 창문을 찾아 닫아 점수를 얻어야 합니다.")

	game_manager.stop_game()
	if failures.is_empty():
		print("[MiniGameTest] PASS · 9 games, tiles, simultaneous ranking rewards, UI")
		quit(0)
	else:
		print("[MiniGameTest] FAIL · %d issue(s)" % failures.size())
		quit(1)

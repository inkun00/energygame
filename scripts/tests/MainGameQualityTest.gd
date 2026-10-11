extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _fresh_game() -> Node:
	var gm := root.get_node("GameManager")
	gm.stop_game()
	var network := root.get_node("NetworkManager")
	network.is_online = false
	var configs: Array[Dictionary] = []
	for idx in range(4):
		configs.append({"name": "테스트 %d" % idx, "is_ai": idx >= 2})
	gm.setup_game(configs)
	return gm

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _verify_heat_trace(stats: Dictionary, score: int, seed_value: int) -> int:
	var opened: Array[bool] = [false, false, false, false, false, false]
	var since: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var expected_openings: Array[int] = []
	var last_wave := -1
	var trace_score := 0
	var closes := 0
	var actions := 0
	var late_closes := 0
	for event in stats.get("heat_actions", []):
		var idx := int(event["window"])
		var at := float(event["time"])
		match str(event["kind"]):
			"open":
				var wave := int(event["wave"])
				if wave != last_wave:
					last_wave = wave
					expected_openings.clear()
					for candidate in HeatLeakDash3D.wave_positions(seed_value, wave):
						if not opened[candidate]:
							expected_openings.append(candidate)
							if expected_openings.size() == HeatLeakDash3D.OPEN_PER_WAVE:
								break
				_expect(not opened[idx] and not expected_openings.is_empty() and idx == expected_openings[0], "AI 창문은 사람과 같은 seed 순서로 닫힌 창문만 열어야 합니다.")
				if not expected_openings.is_empty():
					expected_openings.pop_front()
				opened[idx] = true
				since[idx] = at
			"close":
				_expect(opened[idx] and is_equal_approx(float(event["since"]), since[idx]), "다음 더운 바람이 와도 AI 창문이 처음 열린 시각을 보존해야 합니다.")
				var points := HeatLeakDash3D.score_for_close(at - since[idx])
				_expect(int(event["points"]) == points, "AI도 실제 열린 시간에 따른 창문 점수를 받아야 합니다.")
				trace_score += points
				closes += 1
				actions += 1
				if at - since[idx] >= 6.0:
					late_closes += 1
				opened[idx] = false
			"miss":
				_expect(not opened[idx], "이미 닫힌 창문을 눌렀을 때만 AI의 닫힘 실수로 계산해야 합니다.")
				trace_score = maxi(0, trace_score - 15)
				actions += 1
	_expect(trace_score == score and closes == int(stats["correct"]) and actions == int(stats["attempts"]), "AI 냉방 점수와 행동 통계가 실제 창문 기록에 일치해야 합니다.")
	return late_closes

func _run() -> void:
	var gm := _fresh_game()
	_expect(gm.MOVEMENT_END_REWARDS == [20, 15, 10, 5], "이동 보상이 학습 활동을 압도하지 않도록 축소되어야 합니다.")
	gm.players[0]["inventory"]["solar_panel"] = 1
	gm.players[1]["inventory"]["solar_panel"] = 1
	gm.players[2]["inventory"]["battery"] = 1
	gm._start_village_construction_phase()
	_expect(gm.can_build_village_project(0, 0), "친구들에게 나뉜 부품으로 공동 건설이 가능해야 합니다.")
	_expect(gm.build_village_project(0, 0), "공동 태양광 발전소 건설이 성공해야 합니다.")
	_expect(gm.get_team_inventory()["solar_panel"] == 0 and gm.get_team_inventory()["battery"] == 0, "공동 건설은 정확한 부품 수량을 사용해야 합니다.")
	_expect(gm.players[0]["energy"] == 12 and gm.players[1]["energy"] == 7 and gm.players[2]["energy"] == 7, "건설과 부품 제공 보상이 각 제공자에게 돌아가야 합니다.")
	gm.players[2]["inventory"]["wind_blade"] = 2
	gm.players[2]["inventory"]["smart_grid"] = 1
	gm.finish_village_construction(0)
	var previous_scale := Engine.time_scale
	Engine.time_scale = 10.0
	await create_timer(1.2).timeout
	_expect(gm.built_project_ids.size() == 1 and gm.village_construction_active, "모든 사람이 마치기 전 AI가 건설을 끝내면 안 됩니다.")
	gm.finish_village_construction(1)
	await create_timer(1.8).timeout
	Engine.time_scale = previous_scale
	_expect(gm.kingdom_recovered and not gm.village_construction_active, "모두 마치면 AI가 남은 공동 시설을 건설하고 결과로 넘어가야 합니다.")

	gm = _fresh_game()
	var database := root.get_node("QuizDatabase")
	for grade in [4, 5, 6]:
		gm.set_learning_grade(grade)
		var seen: Dictionary = {}
		for _draw in range(40):
			var quiz: Dictionary = database.get_random_quiz()
			_expect(not seen.has(quiz["id"]), "문제 풀이 중 같은 문제가 반복되면 안 됩니다.")
			seen[quiz["id"]] = true
			_expect(quiz["answer"] in quiz["options"], "보기를 섞어도 정답은 보기에 있어야 합니다.")
			_expect(database._minimum_grade(quiz) <= grade, "학년에 맞는 문제를 출제해야 합니다.")
			_expect(float(quiz["time_limit"]) >= 20.0 and float(quiz["time_limit"]) <= 40.0, "읽기 시간을 문항 길이에 맞춰 제공해야 합니다.")
	gm.set_learning_grade(5)
	var quiz: Dictionary = database.get_random_quiz()
	gm.active_quiz_data = quiz
	gm.active_quiz_player_idx = 1
	gm.active_quiz_time_remaining = float(quiz["time_limit"]) + 3.86
	gm.current_state = gm.TurnState.RESOLVING_QUIZ
	var modal = load("res://scenes/QuizModal.tscn").instantiate()
	root.add_child(modal)
	await process_frame
	modal.display_quiz(1, quiz)
	_expect(not "AI 답변" in modal.timer_label.text, "사람을 관전할 때 AI라고 표시하면 안 됩니다.")
	var wrong_choice := ""
	for option in quiz["options"]:
		if str(option) != str(quiz["answer"]):
			wrong_choice = str(option)
	gm.last_quiz_choice = wrong_choice
	_expect(modal._get_observed_answer(false) == wrong_choice, "관전자에게 실제 선택한 오답을 표시해야 합니다.")
	modal.cancel_quiz()
	modal.queue_free()
	gm.on_network_quiz_resolved(1, false, wrong_choice)
	_expect(gm.last_quiz_choice == wrong_choice and gm.active_quiz_player_idx == -1, "권한 상태에 실제 선택과 완료가 함께 기록되어야 합니다.")
	_expect(not gm.has_minigame_goal_actions("hydro_gate", 100, {"correct": 1, "attempts": 2}), "수문을 닫지 않았으면 수력 관리 목표는 미충족입니다.")
	_expect(gm.has_minigame_goal_actions("hydro_gate", 100, {"correct": 1, "attempts": 2, "hydro_managed_closures": 1}), "발전과 수문 닫기를 모두 수행한 수력 행동을 인정해야 합니다.")
	for game_id in gm.MINIGAME_DEFINITIONS:
		gm.active_minigame = {"id": game_id, "seed": 211}
		var score: int = gm._generate_ai_minigame_score(2)
		var stats: Dictionary = gm._last_ai_minigame_stats
		_expect(int(stats["correct"]) <= int(stats["attempts"]), "AI의 성공 수는 실제 행동 횟수를 넘으면 안 됩니다: %s" % game_id)
		_expect(score == 0 or int(stats["attempts"]) > 0, "AI 양수 점수에는 실제 행동이 있어야 합니다: %s" % game_id)
		if game_id == "grid_balance":
			_expect(score > 224 and score <= 3000, "AI 그리드 점수도 평균 간격 기준으로 계산해야 합니다.")
			_expect(score == SmartGridBalance3D.score_for_average_gap(float(stats["grid_average_gap"])), "AI 그리드 점수는 실제로 적분한 평균 오차에 일치해야 합니다.")
	var overflow_samples := 0
	for sample_seed in range(60):
		for ai_idx in [2, 3]:
			gm.active_minigame = {"id": "hydro_gate", "seed": sample_seed}
			var hydro_score: int = gm._generate_ai_minigame_score(ai_idx)
			var hydro_stats: Dictionary = gm._last_ai_minigame_stats
			if bool(hydro_stats.get("hydro_overflowed", false)):
				overflow_samples += 1
				_expect(hydro_stats["correct"] == 0 and hydro_stats["hydro_managed_closures"] == 0 and not gm.has_minigame_goal_actions("hydro_gate", hydro_score, hydro_stats), "범람한 수력 AI는 사람과 동일하게 학습 목표 보상을 받을 수 없습니다.")
	_expect(overflow_samples > 0, "수력 범람 회귀가 실제 범람하는 AI 사례도 포함해야 합니다.")
	var late_closes := 0
	for sample_seed in range(60):
		gm.active_minigame = {"id": "heat_leak", "seed": sample_seed}
		var heat_score: int = gm._generate_ai_minigame_score(2)
		late_closes += _verify_heat_trace(gm._last_ai_minigame_stats, heat_score, sample_seed)
	_expect(late_closes > 0, "늦게 닫히는 AI 창문의 원래 개방 시각도 회귀에 포함해야 합니다.")
	gm = _fresh_game()
	gm._start_minigame(0, "grid_balance")
	gm.start_minigame_action(0, int(gm.active_minigame["round_id"]))
	gm.start_minigame_action(1, int(gm.active_minigame["round_id"]))
	gm._update_minigame(4.0)
	var round_total: float = gm.minigame_time_remaining
	gm._minigame_wall_start_msec -= 1000
	gm._update_minigame(0.001)
	_expect(gm.minigame_time_remaining <= round_total - 0.9, "낮은 FPS에서도 미니게임 제한시간은 실제 경과시간을 따라야 합니다.")
	var before_pause: float = gm.minigame_time_remaining
	gm._minigame_wall_pause_msec = Time.get_ticks_msec() - 500
	gm._minigame_wall_start_msec -= 500
	gm._process(0.0)
	_expect(absf(gm.minigame_time_remaining - before_pause) < 0.1, "재접속 정지 시간은 미니게임 실제 제한시간에서 제외해야 합니다.")
	gm.stop_game()
	await create_timer(1.2).timeout
	await process_frame
	if failures.is_empty():
		print("[PASS] Main game quality: shared construction, human opportunity, fair rewards, quiz truth and AI counters")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

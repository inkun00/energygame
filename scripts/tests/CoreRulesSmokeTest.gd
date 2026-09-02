extends SceneTree

const BOARD_GRID = preload("res://scripts/board/BoardGrid.gd")
const QUIZ_DATABASE_SCRIPT = preload("res://scripts/quiz/QuizDatabase.gd")
const PLAYER_PAWN = preload("res://scripts/player/PlayerPawn.gd")
const ENDING_CINEMATIC = preload("res://scripts/effects/EndingCinematic.gd")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	_test_board_rewards()
	_test_shortcut_cycle_guard()
	_test_random_shortcuts_each_game()
	_test_single_player_ai_fill()
	_test_player_sprite_states()
	_test_quiz_tile_mapping()
	_test_material_bonus_tile()
	_test_quiz_reward()
	_test_special_skills()
	await _test_ai_special_skills()
	_test_personal_material_inventory()
	_test_expanded_renewable_projects()
	await _test_ai_village_construction()
	_test_movement_end_rewards()
	_test_energy_ranking()
	_test_kingdom_recovery_ending()
	_test_ending_cinematics()
	_test_no_monster_tiles()
	await _test_hud_initialization()
	await _test_quiz_popup_text_integrity()
	await _test_other_player_quiz_observation()
	await _test_ai_quiz_failsafe()
	await _test_player_dice_auto_roll_timeout()
	await _test_local_game_start()
	await create_timer(1.5).timeout

	if failures.is_empty():
		print("[PASS] Core rules smoke test")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _fresh_game() -> Node:
	var configs: Array[Dictionary] = []
	for i in range(4):
		configs.append({"name": "테스트 %d" % i, "is_ai": false})
	var game_manager = root.get_node("GameManager")
	game_manager.setup_game(configs)
	return game_manager

func _test_board_rewards() -> void:
	BOARD_GRID.assign_random_shortcuts()
	_expect(BOARD_GRID.TILE_COUNT == 100, "전체 게임판은 100칸이어야 합니다.")
	_expect(is_equal_approx(BOARD_GRID.MOVE_STEP_SECONDS, 0.61516), "일반 칸 이동 시간은 직전 설정보다 30% 느려야 합니다.")
	_expect(is_equal_approx(BOARD_GRID.SHORTCUT_MOVE_SECONDS, 2.6364), "사다리·미끄럼틀 이동 시간도 직전 설정보다 30% 느려야 합니다.")
	_expect(BOARD_GRID.TILE_POSITIONS_3D.size() == 100, "3D 보드 좌표가 100개여야 합니다.")
	_expect(BOARD_GRID.TILE_DATA.size() == 100, "100칸 전체에 타일 이벤트 데이터가 있어야 합니다.")
	_expect(BOARD_GRID.get_tile_data(BOARD_GRID.LAST_TILE_INDEX).get("type") == BOARD_GRID.TileType.FINISH, "99번 칸이 최종 도착지여야 합니다.")
	_expect(BOARD_GRID.get_tile_data(49).get("type") != BOARD_GRID.TileType.FINISH, "49번 칸은 중간 지점이어야 합니다.")
	_expect(BOARD_GRID.get_tile_data(98).get("reward_energy") == 6, "98번 발전소 보상은 6이어야 합니다.")
	_expect(BOARD_GRID.get_tile_data(19).get("reward_energy") == 3, "19번 발전소 보상은 3이어야 합니다.")
	_expect(BOARD_GRID.get_tile_data(22).get("reward_energy") == 4, "22번 발전소 보상은 4여야 합니다.")
	var ladder_count := 0
	var slide_count := 0
	for tile in BOARD_GRID.TILE_DATA:
		if tile.get("type") in [BOARD_GRID.TileType.LADDER, BOARD_GRID.TileType.SLIDE]:
			_expect(BOARD_GRID.is_vertical_shortcut_link(tile["index"], tile.get("target", -1)), "사다리와 미끄럼틀은 같은 열의 바로 위·아래 칸만 연결해야 합니다.")
		if tile.get("type") == BOARD_GRID.TileType.LADDER:
			ladder_count += 1
		elif tile.get("type") == BOARD_GRID.TileType.SLIDE:
			slide_count += 1
	_expect(ladder_count == BOARD_GRID.RANDOM_LADDER_COUNT, "100칸 보드에는 사다리가 8개 배치되어야 합니다.")
	_expect(slide_count == BOARD_GRID.RANDOM_SLIDE_COUNT, "100칸 보드에는 미끄럼틀이 8개 배치되어야 합니다.")
	_expect(BOARD_GRID.get_tile_data(34).get("type") == BOARD_GRID.TileType.CHANCE_CARD, "34번 칸은 45번 미끄럼틀과 겹치는 사다리가 아니어야 합니다.")
	for shortcut in BOARD_GRID.TILE_DATA:
		if shortcut.get("type") not in [BOARD_GRID.TileType.LADDER, BOARD_GRID.TileType.SLIDE]:
			continue
		var visited := {}
		var current_tile := int(shortcut["index"])
		while true:
			if visited.has(current_tile):
				_expect(false, "사다리·미끄럼틀 연결에 순환 구간이 없어야 합니다.")
				break
			visited[current_tile] = true
			var current_data := BOARD_GRID.get_tile_data(current_tile)
			if current_data.get("type") not in [BOARD_GRID.TileType.LADDER, BOARD_GRID.TileType.SLIDE]:
				break
			current_tile = int(current_data.get("target", -1))

func _test_shortcut_cycle_guard() -> void:
	var game_manager = _fresh_game()
	game_manager.current_turn_idx = 0
	game_manager.current_state = game_manager.TurnState.TILE_EVENT
	game_manager.players[0]["position"] = 45
	var turns_before: int = game_manager.total_turns
	var visited_shortcuts: Array[int] = [34]
	game_manager._follow_shortcut(0, 45, 34, visited_shortcuts, "순환 방어 테스트")
	_expect(game_manager.players[0]["position"] == 45, "이미 방문한 지름길 칸으로 다시 이동하지 않아야 합니다.")
	_expect(game_manager.total_turns == turns_before + 1, "순환 지름길을 감지하면 현재 턴을 안전하게 종료해야 합니다.")
	game_manager.stop_game()

func _test_random_shortcuts_each_game() -> void:
	var game_manager = _fresh_game()
	var first_layout := BOARD_GRID.get_shortcut_signature()
	_expect(not first_layout.is_empty(), "매 게임에는 사다리와 미끄럼틀 배치가 있어야 합니다.")
	var next_game_configs: Array[Dictionary] = [{"name": "새 배치 확인", "is_ai": false}]
	game_manager.setup_game(next_game_configs)
	var second_layout := BOARD_GRID.get_shortcut_signature()
	_expect(first_layout != second_layout, "새 게임을 시작하면 사다리와 미끄럼틀 위치가 직전 게임과 달라야 합니다.")
	var occupied_endpoints: Dictionary = {}
	for tile in BOARD_GRID.TILE_DATA:
		if tile.get("type") not in [BOARD_GRID.TileType.LADDER, BOARD_GRID.TileType.SLIDE]:
			continue
		var source_index := int(tile["index"])
		var target_index := int(tile.get("target", -1))
		_expect(BOARD_GRID.is_vertical_shortcut_link(source_index, target_index), "무작위 지름길도 같은 열의 인접 행만 연결해야 합니다.")
		_expect(not occupied_endpoints.has(source_index) and not occupied_endpoints.has(target_index), "사다리와 미끄럼틀은 서로 끝점을 공유하면 안 됩니다.")
		occupied_endpoints[source_index] = true
		occupied_endpoints[target_index] = true
	game_manager.stop_game()

func _test_single_player_ai_fill() -> void:
	var game_manager = root.get_node("GameManager")
	var single_player_configs: Array[Dictionary] = []
	single_player_configs.append({"name": "혼자 하는 히어로", "is_ai": false, "char_icon": "res://assets/characters/eco_roster/captain_eco.webp"})
	game_manager.setup_game(single_player_configs)
	_expect(game_manager.players.size() == game_manager.MAX_PLAYER_COUNT, "싱글플레이는 AI를 채워 항상 4인 파티로 시작해야 합니다.")
	_expect(not game_manager.players[0]["is_ai"], "싱글플레이의 첫 자리는 실제 플레이어여야 합니다.")
	_expect(game_manager.ai_fill_count == 3, "싱글플레이에서는 빈 3자리를 AI 동료가 채워야 합니다.")
	for player_index in range(1, game_manager.MAX_PLAYER_COUNT):
		_expect(game_manager.players[player_index]["is_ai"], "부족한 파티 자리는 AI 플레이어여야 합니다.")
	game_manager.stop_game()

func _test_player_sprite_states() -> void:
	var pawn = PLAYER_PAWN.new()
	root.add_child(pawn)
	pawn.setup_player({"index": 0, "char_icon": "res://assets/characters/eco_roster/earth_turtle_tori.webp"})
	_expect(pawn.idle_sprite_texture != null and pawn.move_sprite_texture != null, "플레이어는 생성된 정지·이동 스프라이트를 모두 불러와야 합니다.")
	_expect(pawn.avatar_sprite.texture == pawn.idle_sprite_texture and not pawn.is_moving, "정지 중에는 정지 스프라이트 애니메이션이 표시되어야 합니다.")
	pawn._process(0.25)
	_expect(pawn.avatar_sprite.frame > 0, "정지 상태 스프라이트도 프레임 애니메이션으로 재생되어야 합니다.")
	pawn._set_avatar_animation_state(true)
	_expect(pawn.avatar_sprite.texture == pawn.move_sprite_texture and pawn.is_moving, "이동 시작 시 이동 스프라이트 애니메이션으로 전환되어야 합니다.")
	pawn._process(0.20)
	_expect(pawn.avatar_sprite.frame > 0, "이동 상태 스프라이트도 프레임 애니메이션으로 재생되어야 합니다.")
	pawn._set_avatar_animation_state(false)
	_expect(pawn.avatar_sprite.texture == pawn.idle_sprite_texture and not pawn.is_moving, "이동이 끝나면 정지 스프라이트 애니메이션으로 복귀해야 합니다.")
	_expect(pawn.shield_visual != null and not pawn.shield_visual.visible, "방패가 없을 때는 캐릭터 보호막이 숨겨져야 합니다.")
	pawn.set_shield_active(true)
	_expect(pawn.shield_visual.visible and pawn.shield_shell != null and pawn.shield_ring_a != null and pawn.shield_ring_b != null, "방패 획득 시 캐릭터를 감싸는 보호막과 회전 고리가 보여야 합니다.")
	var shield_rotation_before: float = pawn.shield_visual.rotation.y
	pawn._process(0.25)
	_expect(pawn.shield_visual.rotation.y > shield_rotation_before, "방패 보호막은 캐릭터 주변에서 계속 움직여야 합니다.")
	pawn.set_shield_active(false)
	_expect(not pawn.shield_visual.visible, "방패 소모 시 캐릭터 보호막이 즉시 사라져야 합니다.")
	pawn.queue_free()

func _test_quiz_tile_mapping() -> void:
	var game_manager = _fresh_game()
	var quiz_database = QUIZ_DATABASE_SCRIPT.new()
	_expect(quiz_database.quizzes.size() == 200, "에너지 객관식 퀴즈 200개를 모두 불러와야 합니다.")
	for quiz in quiz_database.quizzes:
		var options: Array = quiz.get("options", [])
		_expect(quiz.get("type", -1) == QUIZ_DATABASE_SCRIPT.QuizType.MULTI_CHOICE, "모든 퀴즈 유형은 객관식이어야 합니다.")
		_expect(options.size() == 4, "모든 객관식 퀴즈는 보기 4개를 가져야 합니다.")
		_expect(quiz.get("answer", "") in options, "모든 객관식 정답은 보기 중 하나여야 합니다.")
	var received = {"type": -1}
	var capture_quiz_type = func(_player_idx: int, quiz: Dictionary):
		received["type"] = quiz.get("type", -1)
	game_manager.quiz_requested.connect(capture_quiz_type)

	game_manager._resolve_tile_event(0, 4)
	_expect(received["type"] == QUIZ_DATABASE_SCRIPT.QuizType.MULTI_CHOICE, "기존 초성 타일도 객관식 퀴즈를 요청해야 합니다.")
	game_manager.current_state = game_manager.TurnState.TILE_EVENT
	game_manager._resolve_tile_event(0, 5)
	_expect(received["type"] == QUIZ_DATABASE_SCRIPT.QuizType.MULTI_CHOICE, "기존 OX 타일도 객관식 퀴즈를 요청해야 합니다.")
	game_manager.current_state = game_manager.TurnState.TILE_EVENT
	game_manager._resolve_tile_event(0, 10)
	_expect(received["type"] == QUIZ_DATABASE_SCRIPT.QuizType.MULTI_CHOICE, "객관식 타일은 객관식 퀴즈를 요청해야 합니다.")

	game_manager.quiz_requested.disconnect(capture_quiz_type)
	game_manager.stop_game()

func _test_material_bonus_tile() -> void:
	var game_manager = _fresh_game()
	game_manager.collected_item_tiles[34] = 1
	game_manager.current_turn_idx = 0
	game_manager.current_state = game_manager.TurnState.TILE_EVENT
	var material_total_before := 0
	for count in game_manager.players[0]["inventory"].values():
		material_total_before += int(count)
	game_manager._resolve_tile_event(0, 34)
	var material_total_after := 0
	for count in game_manager.players[0]["inventory"].values():
		material_total_after += int(count)
	_expect(not game_manager.players[0].has("hand"), "플레이어 데이터에 에너지 카드 손패가 없어야 합니다.")
	_expect(material_total_after == material_total_before + 1, "재료 보너스 칸은 개인 건설재료를 1개 지급해야 합니다.")
	game_manager.stop_game()

func _test_quiz_reward() -> void:
	var game_manager = _fresh_game()
	game_manager.current_state = game_manager.TurnState.RESOLVING_QUIZ
	game_manager.active_quiz_player_idx = 0
	game_manager.active_quiz_data = {"reward_energy": 3}
	var energy_before: int = game_manager.players[0]["energy"]
	var skill_energy_before: int = game_manager.players[0]["skill_energy"]

	game_manager.on_network_quiz_resolved(0, true)

	_expect(game_manager.players[0]["energy"] == energy_before + 3, "퀴즈별 보상 수치가 적용되어야 합니다.")
	_expect(game_manager.players[0]["skill_energy"] == skill_energy_before + 3, "퀴즈 정답 에너지는 특수기술 전용 에너지로도 쌓여야 합니다.")
	game_manager.stop_game()

func _test_special_skills() -> void:
	var played_skill_sounds: Array[String] = []
	var capture_skill_sound := func(skill_id: String): played_skill_sounds.append(skill_id)
	var audio_manager := root.get_node("AudioManager")
	audio_manager.special_skill_sfx_played.connect(capture_skill_sound)
	var game_manager = _fresh_game()
	for skill_variant in game_manager.SPECIAL_SKILLS_BY_ICON.values():
		var skill: Dictionary = skill_variant
		_expect(str(skill.get("id", "")) in audio_manager.SPECIAL_SKILL_SFX_IDS, "%s에 대응하는 전용 특수효과음이 있어야 합니다." % skill.get("name", "특수기술"))
		_expect(str(skill.get("target_type", "")) != "player", "%s은 다른 플레이어를 대상으로 삼으면 안 됩니다." % skill.get("name", "특수기술"))
	game_manager.players[0]["char_icon"] = "res://assets/characters/eco_roster/captain_eco.webp"
	game_manager.players[0]["skill_energy"] = 3
	game_manager.current_turn_idx = 0
	game_manager.current_state = game_manager.TurnState.WAIT_ACTION
	_expect(game_manager.get_player_special_skill(0).get("target_type") == "tile", "캡틴 에코는 타일 지정형 특수기술을 가져야 합니다.")
	_expect(game_manager.use_special_skill(0, 4), "충분한 특수 에너지로 타일 지정 기술을 사용할 수 있어야 합니다.")
	_expect(game_manager.players[0]["skill_energy"] == 0, "특수기술 사용 시 퀴즈 특수 에너지를 소모해야 합니다.")
	_expect(game_manager.players[0]["position"] == 4 and game_manager.current_state == game_manager.TurnState.PLAYER_MOVING, "질주 기술은 지정한 앞쪽 타일로 이동해야 합니다.")
	_expect(game_manager.special_skill_used_this_turn, "특수기술은 한 턴에 한 번만 사용할 수 있도록 기록되어야 합니다.")
	_expect("eco_dash" in played_skill_sounds, "자연의 돌진 발동 시 전용 효과음이 재생되어야 합니다.")
	game_manager._finish_special_skill_move(0, 4)
	_expect(game_manager.current_state == game_manager.TurnState.WAIT_ACTION, "특수 이동 완료 후 같은 플레이어의 주 행동을 기다려야 합니다.")
	var position_after_skill := int(game_manager.players[0]["position"])
	game_manager.execute_roll_dice(0)
	_expect(game_manager.current_state == game_manager.TurnState.ROLLING_DICE, "이동형 특수기술 사용 후에도 주사위를 굴릴 수 있어야 합니다.")
	_expect(int(game_manager.players[0]["position"]) == position_after_skill, "주사위 결과가 확정되기 전에는 특수 이동 위치가 유지되어야 합니다.")
	game_manager.stop_game()

	game_manager = _fresh_game()
	game_manager.players[0]["char_icon"] = "res://assets/characters/eco_roster/water_popo.webp"
	game_manager.players[0]["skill_energy"] = 3
	game_manager.current_turn_idx = 0
	game_manager.current_state = game_manager.TurnState.WAIT_ACTION
	var self_energy_before: int = game_manager.players[0]["energy"]
	var other_energy_before: int = game_manager.players[1]["energy"]
	_expect(not game_manager.use_special_skill(0, 1), "자기 강화형 특수기술을 다른 플레이어에게 사용할 수 없어야 합니다.")
	_expect(game_manager.use_special_skill(0, 0), "자기 강화형 특수기술은 자신에게 사용할 수 있어야 합니다.")
	_expect(game_manager.players[0]["shield"] and game_manager.players[0]["energy"] == self_energy_before + 1, "정화의 물결은 사용한 캐릭터 자신에게 방패와 에너지를 제공해야 합니다.")
	_expect(not game_manager.players[1]["shield"] and game_manager.players[1]["energy"] == other_energy_before, "자기 강화형 특수기술이 다른 플레이어의 상태를 바꾸면 안 됩니다.")
	_expect("purifying_wave" in played_skill_sounds, "정화의 물결 발동 시 물결 전용 효과음이 재생되어야 합니다.")
	_expect(game_manager.current_state == game_manager.TurnState.WAIT_ACTION, "자기 강화형 특수기술도 턴을 종료하지 않아야 합니다.")
	game_manager.execute_roll_dice(0)
	_expect(game_manager.current_state == game_manager.TurnState.ROLLING_DICE, "자기 강화형 특수기술 사용 후에도 주사위를 굴릴 수 있어야 합니다.")
	game_manager.stop_game()

	game_manager = _fresh_game()
	game_manager.players[0]["char_icon"] = "res://assets/characters/eco_roster/recycle_raccoon_ringo.webp"
	game_manager.players[0]["skill_energy"] = 3
	game_manager.current_turn_idx = 0
	game_manager.current_state = game_manager.TurnState.WAIT_ACTION
	_expect(game_manager.use_special_skill(0, 1), "재활용 너구리는 미획득 타일을 지정해 재료를 회수할 수 있어야 합니다.")
	_expect(game_manager.collected_item_tiles.get(1, -1) == 0, "원격 회수한 타일 재료는 사용한 플레이어의 개인 재료가 되어야 합니다.")
	_expect("recycle_salvage" in played_skill_sounds, "재활용 회수 발동 시 순환 전용 효과음이 재생되어야 합니다.")
	game_manager.stop_game()
	audio_manager.special_skill_sfx_played.disconnect(capture_skill_sound)

func _test_ai_special_skills() -> void:
	var game_manager = _fresh_game()
	_expect(game_manager.AI_SPECIAL_SKILL_USE_CHANCE > 0.0 and game_manager.AI_SPECIAL_SKILL_USE_CHANCE < 1.0, "AI 특수기술은 무조건이 아닌 무작위 확률로 사용해야 합니다.")
	game_manager.players[1]["is_ai"] = true
	game_manager.players[1]["char_icon"] = "res://assets/characters/eco_roster/water_popo.webp"
	game_manager.players[1]["skill_energy"] = 3
	game_manager.current_turn_idx = 1
	game_manager.current_state = game_manager.TurnState.WAIT_ACTION
	var support_targets: Array[int] = []
	var capture_support = func(player_idx: int, target_idx: int, _skill: Dictionary):
		if player_idx == 1:
			support_targets.append(target_idx)
	game_manager.special_skill_activated.connect(capture_support)
	_expect(game_manager._try_ai_use_random_special_skill(1), "SP가 충분한 AI는 자기 강화형 특수기술을 사용할 수 있어야 합니다.")
	_expect(support_targets.size() == 1 and support_targets[0] == 1, "AI의 자기 강화형 특수기술은 반드시 자신에게 발동해야 합니다.")
	_expect(game_manager.players[1]["skill_energy"] == 0 and game_manager.special_skill_used_this_turn, "AI 특수기술도 SP를 소모하고 턴당 사용 상태를 기록해야 합니다.")
	game_manager.special_skill_activated.disconnect(capture_support)
	game_manager.stop_game()

	game_manager = _fresh_game()
	game_manager.players[1]["is_ai"] = true
	game_manager.players[1]["char_icon"] = "res://assets/characters/eco_roster/wind_rabbit_bori.webp"
	game_manager.players[1]["skill_energy"] = 3
	game_manager.players[1]["position"] = 10
	game_manager.current_turn_idx = 1
	game_manager.current_state = game_manager.TurnState.WAIT_ACTION
	var dice_rolls := {"count": 0}
	var capture_dice = func(player_idx: int, _value: int):
		if player_idx == 1:
			dice_rolls["count"] += 1
	game_manager.dice_rolled.connect(capture_dice)
	_expect(game_manager._try_ai_use_random_special_skill(1), "이동형 기술을 가진 AI도 유효 타일을 무작위로 선택해 사용할 수 있어야 합니다.")
	var moved_position := int(game_manager.players[1]["position"])
	_expect(moved_position > 10 and moved_position <= 17, "AI 이동 특수기술의 무작위 대상은 기술 사거리 안이어야 합니다.")
	game_manager._finish_special_skill_move(1, moved_position)
	var previous_time_scale := Engine.time_scale
	Engine.time_scale = 20.0
	await create_timer(game_manager.AI_POST_SPECIAL_ACTION_DELAY_SECONDS + 0.2).timeout
	Engine.time_scale = previous_time_scale
	_expect(dice_rolls["count"] == 1 and game_manager.current_state == game_manager.TurnState.ROLLING_DICE, "AI는 이동 특수기술이 끝난 뒤에도 주사위를 굴려야 합니다.")
	game_manager.dice_rolled.disconnect(capture_dice)
	game_manager.stop_game()

func _test_personal_material_inventory() -> void:
	var game_manager = _fresh_game()
	var tile_item_id: String = game_manager.get_tile_item_id(1)
	_expect(not tile_item_id.is_empty(), "1~98번 칸에는 건설 재료가 지정되어야 합니다.")
	_expect(game_manager._collect_tile_item(0, 1), "해당 칸에 처음 도착한 플레이어는 재료를 획득해야 합니다.")
	_expect(not game_manager._collect_tile_item(1, 1), "이미 획득된 칸의 재료는 두 번째 플레이어에게 중복 지급되면 안 됩니다.")
	var player_zero_total := 0
	var player_one_total := 0
	for count in game_manager.players[0]["inventory"].values():
		player_zero_total += int(count)
	for count in game_manager.players[1]["inventory"].values():
		player_one_total += int(count)
	_expect(player_zero_total == 1, "획득한 재료는 해당 플레이어의 개인 인벤토리에만 들어가야 합니다.")
	_expect(player_one_total == 0, "다른 플레이어에게 획득 재료가 공유되면 안 됩니다.")
	_expect(game_manager.collected_item_tiles.get(1, -1) == 0, "칸별 재료의 최초 획득 플레이어가 기록되어야 합니다.")
	game_manager.stop_game()

func _test_expanded_renewable_projects() -> void:
	var game_manager = _fresh_game()
	_expect(game_manager.ITEM_DEFINITIONS.size() == 11, "게임판에서 획득할 수 있는 발전·생활 시설 건설 재료가 11종이어야 합니다.")
	_expect(game_manager.CONSTRUCTION_PROJECTS.size() == 10, "건설 가능한 친환경 시설이 총 10종이어야 합니다.")
	var project_names: Array[String] = []
	for project in game_manager.CONSTRUCTION_PROJECTS:
		project_names.append(str(project["name"]))
		_expect(ResourceLoader.exists(str(project["image"])), "신규 발전소 이미지가 존재해야 합니다: %s" % project["name"])
	_expect("소수력 발전소" in project_names and "지열 발전소" in project_names and "조력 발전소" in project_names and "원자력 발전소" in project_names, "소수력·지열·조력·원자력 발전소가 건설 목록에 포함되어야 합니다.")
	_expect("자원순환 생활센터" in project_names and "전기 대중교통 허브" in project_names, "발전소 이외의 친환경 생활 시설이 건설 목록에 포함되어야 합니다.")
	_expect(ResourceLoader.exists("res://assets/items/recycled_composite.webp") and ResourceLoader.exists("res://assets/items/fast_charge_module.webp"), "생활 시설 전용 재료 이미지가 존재해야 합니다.")
	var inventory: Dictionary = game_manager._create_empty_inventory()
	inventory["hydro_turbine"] = 2
	inventory["reactor_control_core"] = 2
	inventory["smart_grid"] = 2
	game_manager.players[0]["inventory"] = inventory
	game_manager._start_village_construction_phase()
	_expect(game_manager.can_build_village_project(4, 0), "수력 터빈과 스마트 그리드로 소수력 발전소를 건설할 수 있어야 합니다.")
	_expect(game_manager.build_village_project(4, 0), "신규 소수력 발전소의 실제 건설이 성공해야 합니다.")
	_expect(game_manager.can_build_village_project(7, 0), "원자로 제어 코어와 스마트 그리드로 원자력 발전소를 건설할 수 있어야 합니다.")
	_expect(game_manager.build_village_project(7, 0), "원자력 발전소의 실제 건설이 성공해야 합니다.")
	game_manager.stop_game()

	var lifestyle_game_manager = _fresh_game()
	var lifestyle_inventory: Dictionary = lifestyle_game_manager._create_empty_inventory()
	lifestyle_inventory["recycled_composite"] = 2
	lifestyle_inventory["fast_charge_module"] = 2
	lifestyle_inventory["smart_grid"] = 1
	lifestyle_inventory["battery"] = 1
	lifestyle_game_manager.players[0]["inventory"] = lifestyle_inventory
	lifestyle_game_manager._start_village_construction_phase()
	_expect(lifestyle_game_manager.can_build_village_project(8, 0), "재생 복합소재와 스마트 그리드로 자원순환 생활센터를 지을 수 있어야 합니다.")
	_expect(lifestyle_game_manager.build_village_project(8, 0), "자원순환 생활센터의 실제 건설이 성공해야 합니다.")
	_expect(lifestyle_game_manager.can_build_village_project(9, 0), "고속 충전 모듈과 배터리로 전기 대중교통 허브를 지을 수 있어야 합니다.")
	_expect(lifestyle_game_manager.build_village_project(9, 0), "전기 대중교통 허브의 실제 건설이 성공해야 합니다.")
	lifestyle_game_manager.stop_game()

func _test_ai_village_construction() -> void:
	var game_manager = _fresh_game()
	game_manager.players[1]["is_ai"] = true
	var ai_inventory: Dictionary = game_manager._create_empty_inventory()
	ai_inventory["solar_panel"] = 2
	ai_inventory["battery"] = 1
	game_manager.players[1]["inventory"] = ai_inventory
	game_manager._start_village_construction_phase()
	var previous_time_scale := Engine.time_scale
	Engine.time_scale = 20.0
	await create_timer(game_manager.AI_VILLAGE_BUILD_DELAY_SECONDS + 0.2).timeout
	Engine.time_scale = previous_time_scale
	_expect(0 in game_manager.built_project_ids, "사람과 함께 플레이한 AI도 자기 재료로 건설 가능한 발전소를 선택해야 합니다.")
	_expect(int(game_manager.built_project_owners.get(0, -1)) == 1, "AI가 선택한 발전소는 해당 AI의 건설 결과로 기록되어야 합니다.")
	_expect(game_manager.players[1].get("project_completion_bonus", 0) == 1, "AI의 최종 완공 수에 자동 건설 결과가 반영되어야 합니다.")
	_expect(game_manager.players[1]["inventory"]["solar_panel"] == 0 and game_manager.players[1]["inventory"]["battery"] == 0, "AI 건설에도 해당 AI의 개인 재료가 소모되어야 합니다.")
	game_manager.stop_game()

func _test_kingdom_recovery_ending() -> void:
	var game_manager = _fresh_game()
	var ending = {"received": false}
	var capture_game_over = func(_rankings: Array): ending["received"] = true
	game_manager.game_over.connect(capture_game_over)
	game_manager._start_village_construction_phase()
	_expect(game_manager.village_construction_active and not game_manager.is_game_active, "마지막 칸 뒤에는 재료를 쓰는 마을 건설 단계가 열려야 합니다.")
	game_manager.players[0]["inventory"] = {"solar_panel": 2, "wind_blade": 0, "battery": 1, "insulation": 0, "smart_grid": 0}
	game_manager.players[1]["inventory"] = {"solar_panel": 0, "wind_blade": 2, "battery": 0, "insulation": 0, "smart_grid": 1}
	_expect(game_manager.can_build_village_project(0, 0) and game_manager.can_build_village_project(1, 1), "각자 필요한 재료를 보유한 플레이어는 건물을 지을 수 있어야 합니다.")
	_expect(not game_manager.can_build_village_project(1, 0), "다른 플레이어의 재료를 합쳐서 건설할 수 없어야 합니다.")
	_expect(game_manager.build_village_project(0, 0), "플레이어 0의 개인 재료로 태양광 발전소가 건설되어야 합니다.")
	_expect(game_manager.build_village_project(1, 1), "플레이어 1의 개인 재료로 풍력 발전단지가 건설되어야 합니다.")
	_expect(game_manager.kingdom_health == game_manager.VILLAGE_RECOVERY_TARGET, "건물 효과의 합으로 복원 목표 건강도에 도달해야 합니다.")
	_expect(game_manager.kingdom_recovered, "목표 건강도 이상인 마을은 즉시 왕국 복원 성공으로 판정되어야 합니다.")
	_expect(ending["received"], "엔딩 조건 달성 시 최종 순위용 game_over 시그널을 즉시 발생시켜야 합니다.")
	game_manager.game_over.disconnect(capture_game_over)

func _test_energy_ranking() -> void:
	var game_manager = _fresh_game()
	var result := {"rankings": []}
	game_manager.players[0]["energy"] = 8
	game_manager.players[0]["laps_completed"] = 10
	game_manager.players[0]["quiz_correct"] = 20
	game_manager.players[1]["energy"] = 20
	game_manager.players[2]["energy"] = 14
	game_manager.players[3]["energy"] = 11
	game_manager.game_over.connect(func(rankings: Array): result["rankings"] = rankings)
	game_manager._start_village_construction_phase()
	game_manager.evaluate_village()
	var rankings: Array = result["rankings"]
	_expect(rankings.size() == 4, "에너지 순위 판정 결과에 모든 플레이어가 포함되어야 합니다.")
	if rankings.size() == 4:
		_expect(int(rankings[0]["index"]) == 1 and int(rankings[3]["index"]) == 0, "다른 활동 점수가 높아도 보유 에너지가 많은 플레이어가 더 높은 최종 순위를 얻어야 합니다.")
		_expect(int(rankings[0]["final_score"]) == 20, "결과 화면의 최종 점수는 보유 에너지와 같아야 합니다.")

func _test_ending_cinematics() -> void:
	var success_ending = ENDING_CINEMATIC.new()
	success_ending.setup(true, 80, 70)
	root.add_child(success_ending)
	_expect(success_ending.is_success and success_ending.title_text == "왕국 복원 성공!", "복원 성공 시 성공 전용 엔딩 애니메이션이 준비되어야 합니다.")
	_expect(success_ending.particles.size() == success_ending.PARTICLE_COUNT, "성공 엔딩에는 축하 에너지 입자 효과가 있어야 합니다.")
	success_ending.queue_free()

	var failure_ending = ENDING_CINEMATIC.new()
	failure_ending.setup(false, 35, 70)
	root.add_child(failure_ending)
	_expect(not failure_ending.is_success and failure_ending.title_text == "에너지 연결이 부족해요", "복원 미달 시 실패 전용 엔딩 애니메이션이 준비되어야 합니다.")
	_expect(failure_ending.subtitle_text.contains("다시 도전"), "실패 엔딩은 다음 도전을 안내해야 합니다.")
	failure_ending.queue_free()

func _test_movement_end_rewards() -> void:
	var game_manager = _fresh_game()
	var result := {"rankings": []}
	var distances: Array[int] = [42, 27, 13, 6]
	for player_idx in range(game_manager.players.size()):
		game_manager.players[player_idx]["total_tiles_moved"] = distances[player_idx]
	game_manager.game_over.connect(func(rankings: Array): result["rankings"] = rankings)
	game_manager._start_village_construction_phase()
	game_manager.evaluate_village()
	_expect(game_manager.players[0]["movement_reward_energy"] == 120, "가장 많이 이동한 플레이어는 에너지 120을 받아야 합니다.")
	_expect(game_manager.players[1]["movement_reward_energy"] == 80 and game_manager.players[2]["movement_reward_energy"] == 40 and game_manager.players[3]["movement_reward_energy"] == 20, "이동 순위가 낮아질수록 종료 보상이 줄어야 합니다.")
	_expect(game_manager.players[0]["energy"] == 125 and game_manager.players[3]["energy"] == 25, "이동 종료 보상이 일반 에너지에 합산되어야 합니다.")
	var rankings: Array = result["rankings"]
	_expect(rankings.size() == 4 and int(rankings[0]["index"]) == 0, "이동 보상 에너지가 최종 플레이어 순위에 반영되어야 합니다.")


func _test_no_monster_tiles() -> void:
	var forbidden_words: Array[String] = ["보스", "몬스터", "괴물", "뱀파이어", "타이탄"]
	for tile in BOARD_GRID.TILE_DATA:
		var tile_text := "%s %s" % [tile.get("name", ""), tile.get("desc", "")]
		for forbidden_word in forbidden_words:
			_expect(forbidden_word not in tile_text, "게임판 중간 이벤트에 몬스터 표현이 남아 있으면 안 됩니다: %s" % tile_text)
	_expect(BOARD_GRID.get_tile_data(11).get("type") == BOARD_GRID.TileType.QUIZ_OX, "11번 몬스터 칸은 에너지 절약 퀴즈로 교체되어야 합니다.")
	_expect(BOARD_GRID.get_tile_data(23).get("type") == BOARD_GRID.TileType.QUIZ_CHOICE, "23번 몬스터 칸은 그린수소 퀴즈로 교체되어야 합니다.")
	_expect(BOARD_GRID.get_tile_data(35).get("type") == BOARD_GRID.TileType.QUIZ_OX, "35번 몬스터 칸은 탄소중립 퀴즈로 교체되어야 합니다.")
	_expect(BOARD_GRID.get_tile_data(47).get("type") == BOARD_GRID.TileType.POWERPLANT, "47번 몬스터 칸은 해양 에너지 연구소로 교체되어야 합니다.")

func _test_hud_initialization() -> void:
	var game_manager = _fresh_game()
	var hud = load("res://scenes/HUD.tscn").instantiate()
	root.add_child(hud)
	await process_frame

	hud.initialize_hud()
	_expect(hud.player_panel_nodes.size() == 4, "HUD가 4명의 플레이어 패널을 생성해야 합니다.")
	_expect(hud.special_skill_target_panel.size.x >= 700.0 and hud.special_skill_target_panel.size.y <= 130.0, "특수기술 안내창은 높이가 낮은 가로형 배너여야 합니다.")
	_expect(hud.special_skill_target_panel.position.y <= 110.0, "특수기술 안내창은 지도 중앙을 가리지 않도록 화면 상단에 배치되어야 합니다.")
	_expect(not hud.get_node("MissionPanel").visible, "게임 화면의 왕국 복원 현황 패널은 표시되지 않아야 합니다.")
	var timer_bottom: float = hud.game_time_panel.position.y + hud.game_time_panel.size.y
	var timer_center_x: float = hud.game_time_panel.position.x + hud.game_time_panel.size.x * 0.5
	var dice_center_x: float = hud.center_dice_panel.position.x + hud.center_dice_panel.size.x * 0.5
	_expect(hud.center_dice_panel.position.y >= timer_bottom, "중앙 주사위는 게임 타이머 아래쪽에 배치되어야 합니다.")
	_expect(absf(dice_center_x - timer_center_x) <= 1.0, "주사위와 게임 타이머의 가로 중심이 맞아야 합니다.")
	_expect(hud.center_dice_button.position.is_equal_approx(hud.center_dice_panel.position) and hud.center_dice_button.size.is_equal_approx(hud.center_dice_panel.size), "주사위 클릭 영역은 이동한 주사위 패널과 정확히 겹쳐야 합니다.")
	_expect(not hud.item_icons.visible, "기존의 단순 재료 아이콘 나열은 숨겨져야 합니다.")
	_expect(hud.guide_inventory_count_labels.size() == game_manager.ITEM_DEFINITIONS.size(), "하단 건설 가이드에 모든 개인 재료가 표시되어야 합니다.")
	_expect(hud.guide_recipe_cards.size() == game_manager.CONSTRUCTION_PROJECTS.size(), "하단 건설 가이드에 모든 발전소 설계도가 표시되어야 합니다.")
	var guide_inventory: Dictionary = game_manager._create_empty_inventory()
	guide_inventory["solar_panel"] = 2
	guide_inventory["battery"] = 1
	hud._update_inventory(0, guide_inventory)
	_expect((hud.guide_recipe_cards[0].find_child("Status", true, false) as Label).text == "건설 가능", "보유 재료가 충족된 발전소는 즉시 건설 가능으로 표시되어야 합니다.")
	_expect((hud.guide_recipe_cards[1].find_child("Status", true, false) as Label).text == "재료 부족", "보유 재료가 부족한 발전소는 부족 상태로 표시되어야 합니다.")
	_expect(hud.village_map != null, "왕국 완성도 화면에는 직접 시설을 놓을 수 있는 마을 지도가 있어야 합니다.")
	_expect(hud.village_map.BUILDING_SIZE.x < 100.0 and hud.village_map.BUILDING_SIZE.y < 82.0, "지도에 배치되는 발전소 이미지는 기존보다 작아야 합니다.")
	var placement_cell_total := 0
	for terrain_id in hud.village_map.PLACEMENT_CELLS:
		var terrain_cells: Array = hud.village_map.PLACEMENT_CELLS[terrain_id]
		placement_cell_total += terrain_cells.size()
		_expect(terrain_cells.size() >= 4, "%s 지형에는 작은 건설 셀이 4개 이상 있어야 합니다." % terrain_id)
	_expect(placement_cell_total >= 36, "지도 전체 건설 셀은 확장 전보다 충분히 많아야 합니다.")
	_expect(ResourceLoader.exists("res://assets/maps/energy_village_map.webp"), "고품질 에너지 마을 지도 배경이 존재해야 합니다.")
	_expect(not hud.kingdom_health_bar.show_percentage, "왕국 완성도 바에는 숫자 퍼센트를 겹쳐 표시하지 않아야 합니다.")
	for project in game_manager.CONSTRUCTION_PROJECTS:
		_expect(ResourceLoader.exists(str(project.get("image", ""))), "모든 건설 프로젝트에 시설 이미지가 있어야 합니다: %s" % project.get("name", ""))
	game_manager.players[0]["char_icon"] = "res://assets/characters/eco_roster/water_popo.webp"
	game_manager.players[0]["skill_energy"] = 3
	game_manager.current_turn_idx = 0
	game_manager.current_state = game_manager.TurnState.WAIT_ACTION
	hud._refresh_special_skill_button()
	hud._on_special_skill_pressed()
	_expect(game_manager.players[0]["shield"], "HUD에서 자기 강화형 특수기술을 누르면 자신에게 즉시 적용되어야 합니다.")
	_expect(not hud.special_skill_target_panel.visible, "자기 강화형 특수기술은 다른 플레이어 선택 팝업을 열지 않아야 합니다.")

	game_manager.players[0]["inventory"] = game_manager._create_empty_inventory()
	for item_id in game_manager.players[0]["inventory"]:
		game_manager.players[0]["inventory"][item_id] = 2
	game_manager._start_village_construction_phase()
	_expect(hud.construction_list.get_child_count() == game_manager.CONSTRUCTION_PROJECTS.size(), "건설 가능한 모든 시설을 이미지 카드로 표시해야 합니다.")
	for construction_card in hud.construction_list.get_children():
		var image_nodes: Array[Node] = construction_card.find_children("*", "TextureRect", true, false)
		_expect(image_nodes.size() >= 2, "각 건설 카드에는 시설 이미지와 필요한 재료 이미지가 함께 보여야 합니다.")
	var solar_card = hud.construction_list.get_child(0)
	var drag_payload: Dictionary = solar_card.create_drag_payload()
	var solar_position: Vector2 = hud.village_map.get_terrain_build_cell_center("solar_field")
	var tidal_position: Vector2 = hud.village_map.get_terrain_center("tidal_lagoon")
	for project_index in range(game_manager.CONSTRUCTION_PROJECTS.size()):
		var project: Dictionary = game_manager.CONSTRUCTION_PROJECTS[project_index]
		var allowed_terrains: Array = project.get("terrains", [])
		var terrain_id := str(allowed_terrains[0])
		var project_payload: Dictionary = hud.village_map.create_drop_payload(project_index, 0)
		_expect(hud.village_map._can_drop_data(hud.village_map.get_terrain_build_cell_center(terrain_id), project_payload), "%s는 새 지도에서 지정 지형에 배치할 수 있어야 합니다." % project.get("name", "시설"))
	_expect(hud.village_map._can_drop_data(solar_position, drag_payload), "태양광 발전소는 햇빛 초원에 드래그할 수 있어야 합니다.")
	_expect(not hud.village_map._can_drop_data(tidal_position, drag_payload), "태양광 발전소는 조력 석호에 지을 수 없어야 합니다.")
	hud.village_map._drop_data(solar_position, drag_payload)
	_expect(0 in game_manager.built_project_ids, "지도에 시설을 놓으면 해당 프로젝트가 건설되어야 합니다.")
	var placed_solar: Control = hud.village_map.placed_project_nodes.get(0) as Control
	_expect(placed_solar != null and placed_solar.get_node_or_null("Shadow") == null and placed_solar.get_node_or_null("Halo") == null, "배치가 끝난 발전소 아래에는 사각형 받침이나 그림자가 남지 않아야 합니다.")
	_expect(game_manager.built_project_placements.has(0), "사용자가 놓은 지도 위치를 프로젝트 배치 정보로 보존해야 합니다.")
	_expect(hud.village_map.get_placed_project_count() == 1, "건설된 시설 이미지가 사용자가 놓은 지도 위치에 표시되어야 합니다.")
	_expect(game_manager.built_project_owners.get(0, -1) == 0, "태양광 발전소를 건설한 플레이어를 전체 마을 지도용으로 기록해야 합니다.")
	_expect(hud.village_map.placed_project_nodes[0].get_node_or_null("OwnerBadge") != null, "지도 위 시설에는 건설한 플레이어 표식이 표시되어야 합니다.")
	var hydro_payload: Dictionary = hud.village_map.create_drop_payload(4, 0)
	_expect(hud.village_map._can_drop_data(hud.village_map.get_terrain_build_cell_center("riverbank"), hydro_payload), "소수력 발전소는 강변 수로에 드래그할 수 있어야 합니다.")
	_expect(not hud.village_map._can_drop_data(tidal_position, hydro_payload), "소수력 발전소는 바닷가 조력 석호에 지을 수 없어야 합니다.")
	var wind_payload: Dictionary = hud.village_map.create_drop_payload(1, 0)
	_expect(hud.village_map._can_drop_data(hud.village_map.get_terrain_build_cell_center("wind_plain"), wind_payload), "풍력 발전단지는 바람 들판에 드래그한 뒤 건설 패드로 스냅되어야 합니다.")
	_expect(hud.village_map._can_drop_data(hud.village_map.get_terrain_build_cell_center("wind_coast"), wind_payload), "풍력 발전단지는 해안 절벽에도 지을 수 있어야 합니다.")
	game_manager.players[1]["inventory"] = game_manager._create_empty_inventory()
	game_manager.players[1]["inventory"]["wind_blade"] = 2
	game_manager.players[1]["inventory"]["smart_grid"] = 1
	hud.village_map._drop_data(hud.village_map.get_terrain_build_cell_center("wind_plain"), hud.village_map.create_drop_payload(1, 1))
	_expect(game_manager.built_project_owners.get(1, -1) == 1, "풍력 발전소를 건설한 다른 플레이어도 기록해야 합니다.")
	_expect(hud.village_map.get_placed_project_count() == 2, "서로 다른 플레이어의 시설은 한 마을 지도에 함께 보여야 합니다.")
	_expect("에너지 문제 해결 완료" in hud.energy_resolution_label.text, "친환경 에너지 지수가 목표에 도달하면 요정마을 문제 해결 상태를 보여야 합니다.")

	game_manager.stop_game()
	hud.queue_free()
	await process_frame

func _test_quiz_popup_text_integrity() -> void:
	var game_manager = _fresh_game()
	var quiz_modal = load("res://scenes/QuizModal.tscn").instantiate()
	root.add_child(quiz_modal)
	await process_frame

	for quiz in QUIZ_DATABASE_SCRIPT.new().quizzes:
		quiz_modal.display_quiz(0, quiz)
		await process_frame
		_expect(quiz_modal.visible, "퀴즈 팝업은 콘텐츠가 준비된 뒤 표시되어야 합니다.")
		_expect(not quiz_modal.title_label.text.strip_edges().is_empty(), "퀴즈 팝업에 제목 텍스트가 표시되어야 합니다.")
		_expect(not quiz_modal.category_badge.text.strip_edges().is_empty(), "퀴즈 팝업에 분류 텍스트가 표시되어야 합니다.")
		_expect(not quiz_modal.question_label.text.strip_edges().is_empty(), "퀴즈 팝업에 문제 텍스트가 표시되어야 합니다.")
		quiz_modal.cancel_quiz()

	game_manager.stop_game()
	quiz_modal.queue_free()
	await process_frame

func _test_other_player_quiz_observation() -> void:
	var game_manager = _fresh_game()
	game_manager.players[1]["is_ai"] = true
	var quiz_modal = load("res://scenes/QuizModal.tscn").instantiate()
	root.add_child(quiz_modal)
	await process_frame

	var quiz := {
		"type": QUIZ_DATABASE_SCRIPT.QuizType.MULTI_CHOICE,
		"category": "관전 테스트",
		"question": "모든 생명체의 활동과 기계 작동을 가능하게 하는 힘의 원천은?",
		"options": ["에너지", "온도", "기계", "공기"],
		"answer": "에너지",
		"explanation": "에너지의 기본 정의입니다.",
		"reward_energy": 2
	}
	game_manager.current_state = game_manager.TurnState.RESOLVING_QUIZ
	game_manager.active_quiz_player_idx = 1
	game_manager.active_quiz_data = quiz
	quiz_modal.display_quiz(1, quiz)
	_expect(quiz_modal.visible and quiz_modal.spectator_mode, "다른 플레이어의 퀴즈는 관전 모드로 표시되어야 합니다.")
	_expect("문제 풀이" in quiz_modal.title_label.text, "관전 퀴즈에 풀이 중인 플레이어가 표시되어야 합니다.")
	for child in quiz_modal.choice_container.get_children():
		if child is Button:
			_expect(not child.disabled, "다른 플레이어가 답하기 전에는 관전자가 보너스 답안을 선택할 수 있어야 합니다.")
	await create_timer(0.7).timeout
	_expect("단서" in quiz_modal.explanation_label.text, "다른 플레이어의 문제 풀이 단계가 표시되어야 합니다.")
	_expect("AI 답변까지" in quiz_modal.timer_label.text and quiz_modal.timer_bar.visible, "AI 퀴즈 관전 중 남은 시간과 진행 막대가 표시되어야 합니다.")

	var energy_before: int = game_manager.players[0].get("energy", 0)
	var skill_energy_before: int = game_manager.players[0].get("skill_energy", 0)
	for child in quiz_modal.choice_container.get_children():
		if child is Button and str(child.get_meta("answer_value", "")) == "에너지":
			child.pressed.emit()
			break
	await process_frame
	_expect(game_manager.players[0].get("bonus_quiz_score", 0) == game_manager.SPECTATOR_QUIZ_BONUS_SCORE, "선행 정답 보너스는 자기 차례 정답 점수의 절반이어야 합니다.")
	_expect(game_manager.SPECTATOR_QUIZ_BONUS_SCORE * 2 == game_manager.QUIZ_CORRECT_SCORE, "관전 보너스 점수 비율은 정확히 1/2이어야 합니다.")
	_expect(game_manager.players[0].get("energy", 0) == energy_before and game_manager.players[0].get("skill_energy", 0) == skill_energy_before, "관전 보너스는 에너지나 특수기술 게이지를 지급하지 않아야 합니다.")
	_expect("+5점" in quiz_modal.explanation_label.text, "선행 정답 직후 획득한 보너스 점수가 안내되어야 합니다.")
	for child in quiz_modal.choice_container.get_children():
		if child is Button:
			_expect(child.disabled, "관전 보너스 답안은 한 문제에 한 번만 제출할 수 있어야 합니다.")
	var duplicate_result: Dictionary = game_manager.submit_spectator_quiz_guess(0, 1, "에너지")
	_expect(not bool(duplicate_result.get("accepted", false)) and game_manager.players[0].get("bonus_quiz_score", 0) == 5, "같은 관전 문제에 중복 보너스를 받을 수 없어야 합니다.")
	var wrong_observer_energy: int = game_manager.players[2].get("energy", 0)
	var wrong_result: Dictionary = game_manager.submit_spectator_quiz_guess(2, 1, "온도")
	_expect(bool(wrong_result.get("accepted", false)) and not bool(wrong_result.get("is_correct", true)) and int(wrong_result.get("bonus_score", -1)) == 0, "선행 답안이 틀리면 보너스 점수를 지급하지 않아야 합니다.")
	_expect(game_manager.players[2].get("bonus_quiz_score", 0) == 0 and game_manager.players[2].get("energy", 0) == wrong_observer_energy, "오답 관전자에게 점수나 에너지 보상이 생기지 않아야 합니다.")

	game_manager.on_network_quiz_resolved(1, true)
	await process_frame
	_expect("선택: 에너지" in quiz_modal.explanation_label.text, "다른 플레이어가 선택한 객관식 답안이 표시되어야 합니다.")
	_expect("내 선행 도전: 정답 (+5점)" in quiz_modal.explanation_label.text, "대상 플레이어 결과와 함께 내 선행 도전 결과가 표시되어야 합니다.")
	_expect("정답입니다" in quiz_modal.explanation_label.text, "다른 플레이어의 퀴즈 결과가 표시되어야 합니다.")
	await create_timer(1.3).timeout
	_expect(not quiz_modal.visible, "관전 퀴즈 결과를 보여준 뒤 창이 닫혀야 합니다.")

	game_manager.stop_game()
	quiz_modal.queue_free()
	await process_frame

func _test_ai_quiz_failsafe() -> void:
	var game_manager = _fresh_game()
	game_manager.players[1]["is_ai"] = true
	var quiz_modal = load("res://scenes/QuizModal.tscn").instantiate()
	root.add_child(quiz_modal)
	await process_frame
	var quiz := {
		"category": "자동 복구 테스트",
		"question": "AI 답변 예약이 누락되어도 관전 화면이 자동으로 복구되어야 할까요?",
		"options": ["예", "아니요", "항상 멈춤", "게임 종료"],
		"answer": "예",
		"explanation": "안전장치는 대기 한도를 넘긴 AI 퀴즈를 자동으로 확정합니다.",
		"reward_energy": 2
	}
	game_manager.current_turn_idx = 1
	game_manager.current_state = game_manager.TurnState.RESOLVING_QUIZ
	game_manager.active_quiz_player_idx = 1
	game_manager.active_quiz_data = quiz
	quiz_modal.display_quiz(1, quiz)
	var previous_time_scale := Engine.time_scale
	Engine.time_scale = 20.0
	await create_timer(game_manager.AI_QUIZ_THINK_SECONDS + quiz_modal.SPECTATOR_FAILSAFE_GRACE_SECONDS + 2.0).timeout
	Engine.time_scale = previous_time_scale
	_expect(game_manager.active_quiz_player_idx == -1, "AI 답변 예약이 누락돼도 관전 안전장치가 퀴즈를 자동 확정해야 합니다.")
	_expect(game_manager.current_state != game_manager.TurnState.RESOLVING_QUIZ, "AI 퀴즈 안전장치 이후 다음 턴으로 진행해야 합니다.")
	game_manager.stop_game()
	quiz_modal.queue_free()
	await process_frame

func _test_player_dice_auto_roll_timeout() -> void:
	var game_manager = _fresh_game()
	var roll_count := {"value": 0}
	var capture_roll = func(_player_idx: int, _value: int): roll_count["value"] += 1
	game_manager.dice_rolled.connect(capture_roll)
	game_manager.start_first_turn()
	_expect(is_equal_approx(game_manager.dice_input_time_remaining, 20.0), "사람 플레이어의 주사위 입력 제한 시간은 20초여야 합니다.")
	var previous_time_scale := Engine.time_scale
	Engine.time_scale = 20.0
	await create_timer(game_manager.PLAYER_DICE_INPUT_SECONDS + 0.2).timeout
	Engine.time_scale = previous_time_scale
	_expect(roll_count["value"] == 1, "20초 동안 주사위를 클릭하지 않으면 정확히 한 번 자동으로 굴려야 합니다.")
	_expect(game_manager.current_state == game_manager.TurnState.ROLLING_DICE, "자동 굴림도 일반 주사위 애니메이션 상태로 진입해야 합니다.")
	_expect(game_manager.dice_input_time_remaining <= 0.0, "자동 굴림이 시작되면 입력 타이머를 정지해야 합니다.")
	game_manager.dice_rolled.disconnect(capture_roll)
	game_manager.stop_game()
	await process_frame

func _test_local_game_start() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame

	var lobby = main.get_node("LobbyUI")
	lobby._on_local_start_pressed()
	await process_frame
	_expect(lobby.opening_story.visible, "게임 시작 전 오프닝 스토리 오버레이가 표시되어야 합니다.")
	_expect(lobby.opening_image.texture != null and lobby.opening_image.is_visible_in_tree() and lobby.opening_image.modulate.a > 0.99, "오프닝 단계마다 스토리 이미지가 즉시 표시되어야 합니다.")
	for _step in range(4):
		lobby._advance_opening_story()
		await process_frame
	await process_frame
	await process_frame
	var game_board = main.get_node("GameBoard")
	_expect(game_board.visible, "로컬 게임 시작 후 보드가 표시되어야 합니다.")
	_expect(game_board.player_pawns.size() == 4, "로컬 게임 시작 시 플레이어 말 4개를 생성해야 합니다.")
	_expect(game_board.item_pickups.size() == BoardGrid.LAST_TILE_INDEX - 1, "1~98번 게임 칸마다 3D 건설 재료가 하나씩 표시되어야 합니다.")
	_expect(game_board.energy_fairy_village != null and game_board.energy_fairy_village.get_child_count() >= 40, "게임판 바깥에 에너지요정 마을 3D 배경이 충분히 구성되어야 합니다.")
	_expect(game_board.energy_fairy_village.animated_rotors.size() >= 3, "에너지요정 마을 배경에 움직이는 풍력 터빈이 있어야 합니다.")
	_expect(game_board.energy_fairy_village.floating_lights.size() >= 12, "에너지요정 마을 배경에 빛나는 마법 에너지 장식이 있어야 합니다.")
	_expect(game_board.tile_markers[3].num_label.text == "3", "게임 칸에는 이모지나 퀴즈 제목 없이 숫자만 표시되어야 합니다.")
	_expect(game_board.hud.player_panel_nodes.size() == 4, "로컬 게임 시작 시 HUD 패널 4개를 생성해야 합니다.")
	_expect(game_board.hud.size == Vector2(1280, 720), "HUD가 전체 게임 화면 크기를 사용해야 합니다.")
	await create_timer(0.5).timeout
	game_board._on_turn_changed(1)
	await create_timer(0.5).timeout
	var focused_pawn_position: Vector3 = game_board.player_pawns[1].position
	_expect(game_board.camera_focus.is_equal_approx(Vector3(focused_pawn_position.x, 0.0, focused_pawn_position.z)), "턴이 시작되면 카메라 포커스가 해당 플레이어 캐릭터로 이동해야 합니다.")

	# 3D 타일 스크린 피킹과 클릭 피드백 검증
	_expect(game_board.viewport_container.mouse_filter != Control.MOUSE_FILTER_IGNORE, "3D 보드 뷰포트가 마우스 입력을 받아야 합니다.")
	var tile_three_world := BoardGrid.get_tile_position_3d(3) + Vector3(0, 0.34, 0)
	var tile_three_screen: Vector2 = game_board.camera3d.unproject_position(tile_three_world)
	_expect(game_board._pick_tile_at_screen_position(tile_three_screen) == 3, "3D 타일 화면 좌표가 올바른 칸으로 피킹되어야 합니다.")
	game_board._activate_tile(3)
	_expect(game_board.hud.event_banner.visible, "3D 타일 클릭 시 정보 배너가 표시되어야 합니다.")
	_expect(str(BOARD_GRID.get_tile_data(3).get("name", "")) in game_board.hud.event_banner_label.text, "무작위 배치된 3D 타일의 설명이 표시되어야 합니다.")
	_expect(game_board.hud.zoom_in_button != null and game_board.hud.zoom_out_button != null, "HUD에 보드 확대/축소 버튼이 존재해야 합니다.")
	var camera_distance_before: float = game_board.camera_distance
	game_board.hud.zoom_in_button.pressed.emit()
	await create_timer(0.25).timeout
	_expect(game_board.camera_distance < camera_distance_before, "보드 확대 입력은 카메라를 보드에 가깝게 이동시켜야 합니다.")
	game_board.hud.zoom_out_button.pressed.emit()
	await create_timer(0.25).timeout
	_expect(is_equal_approx(game_board.camera_distance, camera_distance_before), "보드 축소 입력은 카메라 거리를 복원해야 합니다.")
	game_board._apply_camera_distance(8.5)
	_expect(game_board.camera_distance <= 8.6, "보드를 200% 이상 확대할 수 있어야 합니다.")
	game_board._apply_camera_distance(camera_distance_before)

	var camera_yaw_before: float = game_board.camera_yaw
	var camera_focus_before: Vector3 = game_board.camera_focus
	var camera_position_before: Vector3 = game_board.camera3d.position
	var left_drag_down := InputEventMouseButton.new()
	left_drag_down.button_index = MOUSE_BUTTON_LEFT
	left_drag_down.pressed = true
	left_drag_down.position = Vector2(600, 360)
	game_board._on_board_gui_input(left_drag_down)
	var left_drag_motion := InputEventMouseMotion.new()
	left_drag_motion.position = Vector2(670, 336)
	left_drag_motion.relative = Vector2(70, -24)
	game_board._on_board_gui_input(left_drag_motion)
	var left_drag_up := InputEventMouseButton.new()
	left_drag_up.button_index = MOUSE_BUTTON_LEFT
	left_drag_up.pressed = false
	left_drag_up.position = left_drag_motion.position
	game_board._on_board_gui_input(left_drag_up)
	_expect(is_equal_approx(game_board.camera_yaw, camera_yaw_before), "왼쪽 드래그는 카메라 회전 각도를 바꾸면 안 됩니다.")
	_expect(not game_board.camera_focus.is_equal_approx(camera_focus_before), "왼쪽 드래그로 카메라의 보드 중심 위치가 이동해야 합니다.")
	_expect(not game_board.camera3d.position.is_equal_approx(camera_position_before), "왼쪽 드래그 시 3D 카메라 자체의 위치가 이동해야 합니다.")
	_expect(not game_board.camera_dragging, "왼쪽 마우스 버튼을 놓으면 카메라 드래그가 종료되어야 합니다.")
	_expect(game_board.camera_pitch >= deg_to_rad(game_board.CAMERA_MIN_PITCH), "카메라 수직 각도가 최소 범위 안에 있어야 합니다.")

	var panel_click := InputEventMouseButton.new()
	panel_click.button_index = MOUSE_BUTTON_LEFT
	panel_click.pressed = true
	game_board.hud._on_player_panel_gui_input(panel_click, 0)
	_expect("개인 재료" in game_board.hud.event_banner_label.text, "플레이어 패널 클릭 시 개인 재료 상태가 표시되어야 합니다.")

	var game_manager = root.get_node("GameManager")
	var first_pickup = game_board.item_pickups[1]
	_expect(game_manager._collect_tile_item(0, 1), "보드의 미획득 재료는 최초 플레이어가 획득할 수 있어야 합니다.")
	_expect(not game_board.item_pickups.has(1) and first_pickup.is_collected, "획득된 3D 재료는 즉시 보드의 획득 가능 목록에서 사라져야 합니다.")
	await create_timer(0.45).timeout
	_expect(not is_instance_valid(first_pickup), "획득 연출 뒤 3D 재료 오브젝트가 보드에서 제거되어야 합니다.")
	var rolled = {"value": 0}
	var capture_roll = func(_player_idx: int, value: int): rolled["value"] = value
	game_manager.dice_rolled.connect(capture_roll)
	game_manager.current_turn_idx = 0
	game_manager.current_state = game_manager.TurnState.WAIT_ACTION
	game_board.hud._on_turn_changed(0)
	_expect(game_board.hud.center_dice_panel.visible and not game_board.hud.center_dice_button.disabled, "사람 플레이어 턴에는 화면 중앙 주사위가 클릭 가능해야 합니다.")
	game_board.hud.center_dice_button.pressed.emit()
	await create_timer(0.35).timeout
	print("[DICE ORDER 0.35s] state=%s position=%s roll=%s" % [game_manager.current_state, game_manager.players[0]["position"], rolled["value"]])
	_expect(rolled["value"] in range(1, 7), "중앙 주사위는 1부터 6 사이의 값을 만들어야 합니다.")
	_expect(game_manager.current_state == game_manager.TurnState.ROLLING_DICE, "주사위 애니메이션 중에는 이동 상태로 넘어가면 안 됩니다.")
	_expect(game_manager.players[0]["position"] == 0, "주사위 결과 공개 전에는 캐릭터가 움직이면 안 됩니다.")
	_expect(game_board.hud.center_dice_panel.visible and game_board.hud.center_dice_button.disabled, "굴림 중 중앙 주사위는 보이되 중복 클릭은 막아야 합니다.")
	await create_timer(0.9).timeout
	print("[DICE ORDER 1.25s] state=%s position=%s roll=%s face=%s" % [game_manager.current_state, game_manager.players[0]["position"], rolled["value"], game_board.hud.dice_face.value])
	_expect(game_board.hud.dice_face.value == rolled["value"], "화면의 주사위 눈금이 실제 결과와 같아야 합니다.")
	_expect(not game_board.hud.center_dice_panel.visible, "결과 공개가 끝난 중앙 주사위는 이동 시작과 함께 사라져야 합니다.")
	_expect(game_manager.players[0]["position"] == rolled["value"], "주사위 결과 공개 후 캐릭터 이동이 시작되어야 합니다.")
	_expect(game_board.camera_follow_active, "캐릭터 이동 중에는 카메라 자동 추적이 활성화되어야 합니다.")
	_expect(game_board.camera_distance <= game_board.CAMERA_FOLLOW_DISTANCE + 0.1, "캐릭터 이동 시 턴 포커스 확대 거리를 유지해야 합니다.")
	await create_timer(0.25).timeout
	_expect(game_board.camera_distance <= game_board.CAMERA_FOLLOW_DISTANCE + 0.1, "캐릭터 이동 중에는 도착 칸의 글자가 보이도록 카메라가 자동 확대되어야 합니다.")
	game_manager.dice_rolled.disconnect(capture_roll)

	main.switch_to_lobby()
	main.queue_free()
	await process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

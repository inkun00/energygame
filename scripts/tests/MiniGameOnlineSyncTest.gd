extends SceneTree

## Run this script in two Godot processes with --role=host and --role=client.
## The test verifies the ready barrier, shared countdown, and score delivery.

const TEST_PORT := 18911
const TEST_ROOM_CODE := "482732"

var role := "host"
var network_manager: Node
var game_manager: Node
var modal: Node
var saw_countdown := false
var saw_playing := false
var result_received := false
var round_id := -1

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--role="):
			role = argument.trim_prefix("--role=")
	call_deferred("_run")

func _run() -> void:
	network_manager = root.get_node("NetworkManager")
	game_manager = root.get_node("GameManager")
	network_manager.game_started_signal.connect(_on_game_started)
	game_manager.minigame_started.connect(_on_minigame_started)
	game_manager.minigame_submission_changed.connect(_on_minigame_state)
	game_manager.minigame_finished.connect(_on_minigame_finished)
	modal = load("res://scenes/MiniGameModal.tscn").instantiate()
	root.add_child(modal)
	create_timer(22.0).timeout.connect(_fail.bind("온라인 미니게임 동기화 제한시간 초과"))
	var info := {
		"name": "동기화 호스트" if role == "host" else "동기화 참가자",
		"char_icon": "res://assets/characters/eco_roster/captain_eco.webp",
		"char_color": Color(0.2, 0.8, 0.3)
	}
	if role == "host":
		var error: int = network_manager.create_room(TEST_PORT, info)
		if error != OK:
			_fail("방 개설 실패: %s" % error_string(error))
			return
		network_manager.room_code = TEST_ROOM_CODE
		for _attempt in range(120):
			if network_manager.connected_players.size() >= 2:
				if not network_manager.start_hosted_game(60):
					_fail("게임 시작 실패")
				return
			await create_timer(0.1).timeout
		_fail("참가자 연결 실패")
	else:
		await create_timer(0.35).timeout
		var error: int = network_manager.join_room_by_code(TEST_ROOM_CODE, info)
		if error != OK:
			_fail("방 참가 실패: %s" % error_string(error))

func _on_game_started(configs: Array[Dictionary], duration_seconds: int) -> void:
	game_manager.setup_game(configs, duration_seconds)
	if role == "host":
		await create_timer(0.4).timeout
		game_manager._start_minigame(0, "solar_align")

func _on_minigame_started(data: Dictionary) -> void:
	round_id = int(data.get("round_id", -1))
	if str(data.get("phase", "")) != "ready":
		_fail("준비 단계 없이 시작됨")
		return
	if role == "host":
		await create_timer(0.05).timeout
		modal.dismiss_guide()
		if not game_manager.minigame_ready_players.has(0) or modal.round_started_locally:
			_fail("호스트 준비 후 공통 시작 전 조작이 잠겨야 합니다")
	else:
		await create_timer(0.6).timeout
		if str(game_manager.active_minigame.get("phase", "")) != "ready":
			_fail("참가자 준비 전 카운트다운 시작")
			return
		modal.dismiss_guide()
		if modal.round_started_locally:
			_fail("참가자 준비 후 공통 시작 전 조작이 잠겨야 합니다")

func _on_minigame_state(state: Dictionary) -> void:
	if int((state.get("game", {}) as Dictionary).get("round_id", -1)) != round_id:
		return
	var phase := str((state.get("game", {}) as Dictionary).get("phase", ""))
	if phase == "countdown":
		saw_countdown = true
	elif phase == "playing" and not saw_playing:
		if not saw_countdown:
			_fail("카운트다운 없이 플레이 시작")
			return
		saw_playing = true
		await process_frame
		if not modal.round_started_locally:
			_fail("방장 시작 신호 후 로컬 미니게임이 시작되지 않음")
			return
		var local_idx: int = network_manager.get_local_player_index()
		if role == "client":
			network_manager.request_minigame_score(local_idx, 999, {}, round_id - 1)
		var player_score := 500 if role == "host" else 700
		if not game_manager.submit_minigame_score(local_idx, player_score, {}, round_id):
			_fail("플레이 시작 후 점수 제출 실패")

func _on_minigame_finished(results: Array) -> void:
	if result_received:
		return
	result_received = true
	var scores: Dictionary = {}
	for result_variant in results:
		var result: Dictionary = result_variant
		scores[int(result.get("player_idx", -1))] = int(result.get("score", -1))
	if not saw_countdown or not saw_playing or int(scores.get(0, -1)) != 500 or int(scores.get(1, -1)) != 700:
		_fail("공통 시작 또는 호스트/참가자 점수 불일치: %s" % str(scores))
		return
	print("[PASS] Online minigame sync %s · ready → countdown → playing → results" % role)
	await create_timer(0.4 if role == "client" else 0.8).timeout
	network_manager.disconnect_network()
	quit(0)

func _fail(message: String) -> void:
	push_error("[FAIL] Online minigame sync %s · %s" % [role, message])
	if network_manager:
		network_manager.disconnect_network()
	quit(1)

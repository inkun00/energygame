extends SceneTree

## 두 Godot 프로세스로 실행해 호스트 생성, 참가 등록, 공통 시작, 원격 주사위 요청을 검증합니다.

const TEST_PORT := 18910
const TEST_ROOM_CODE := "482731"

var role := "host"
var game_started := false
var action_verified := false
var network_manager: Node
var game_manager: Node


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--role="):
			role = argument.trim_prefix("--role=")
	call_deferred("_start")


func _start() -> void:
	network_manager = root.get_node("NetworkManager")
	game_manager = root.get_node("GameManager")
	network_manager.game_started_signal.connect(_on_game_started)
	game_manager.turn_changed.connect(_on_turn_changed)
	game_manager.dice_rolled.connect(_on_dice_rolled)
	create_timer(10.0).timeout.connect(_fail.bind("시간 안에 멀티플레이 동기화가 끝나지 않았습니다."))
	var info := {
		"name": "호스트 테스트" if role == "host" else "참가자 테스트",
		"char_icon": "res://assets/characters/eco_roster/captain_eco.webp",
		"char_color": Color(0.2, 0.8, 0.3)
	}
	if role == "host":
		var error: int = network_manager.create_room(TEST_PORT, info)
		if error != OK:
			_fail("호스트 방 개설 실패: %s" % error_string(error))
			return
		# 자동 발견 경로를 재현할 수 있도록 테스트에서만 알려진 유효 코드를 사용합니다.
		network_manager.room_code = TEST_ROOM_CODE
		await _wait_for_client()
	else:
		await create_timer(0.35).timeout
		var error: int = network_manager.join_room_by_code(TEST_ROOM_CODE, info)
		if error != OK:
			_fail("방 코드 참가 실패: %s" % error_string(error))


func _wait_for_client() -> void:
	for _attempt in range(40):
		if network_manager.connected_players.size() >= 2:
			print("[TEST] 참가자 확인, 게임 시작 요청")
			if not network_manager.start_hosted_game(60):
				_fail("호스트 게임 시작 실패")
			return
		await create_timer(0.1).timeout
	_fail("참가자 등록 실패")


func _on_game_started(configs: Array[Dictionary], duration_seconds: int) -> void:
	print("[TEST] game_started_signal · role=%s configs=%d" % [role, configs.size()])
	game_started = true
	game_manager.setup_game(configs, duration_seconds)
	if role == "host":
		game_manager.current_turn_idx = 1
		game_manager.start_turn()


func _on_turn_changed(player_idx: int) -> void:
	print("[TEST] turn_changed · role=%s idx=%d local=%d" % [role, player_idx, network_manager.get_local_player_index()])
	if role != "client" or not game_started:
		return
	if player_idx == network_manager.get_local_player_index():
		network_manager.request_roll_dice(player_idx)


func _on_dice_rolled(player_idx: int, value: int) -> void:
	if not game_started or player_idx != 1 or value < 1 or value > 6:
		return
	action_verified = true
	print("[PASS] Multiplayer %s · player=%d dice=%d local_index=%d" % [role, player_idx, value, network_manager.get_local_player_index()])
	await create_timer(0.35 if role == "client" else 0.8).timeout
	network_manager.disconnect_network()
	quit(0)


func _fail(message: String) -> void:
	if action_verified:
		return
	push_error("[FAIL] Multiplayer %s · %s" % [role, message])
	if network_manager:
		network_manager.disconnect_network()
	quit(1)

extends SceneTree

## 반복 온라인 동기화가 전체 상태보다 충분히 작은 변경분으로 유지되는지 검증합니다.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var network_manager := root.get_node("NetworkManager")
	var game_manager := root.get_node("GameManager")
	var configs: Array[Dictionary] = []
	for player_idx in range(4):
		configs.append({
			"name": "테스트%d" % (player_idx + 1),
			"is_ai": player_idx > 0,
			"char_icon": "res://assets/characters/eco_roster/captain_eco.webp",
			"char_color": Color(0.2, 0.8, 0.3)
		})
	game_manager.setup_game(configs, 300)

	var full_bytes := var_to_bytes(network_manager._capture_game_state()).size()
	var timer_bytes := var_to_bytes(network_manager._capture_time_patch("game_time_changed", [299, 300])).size()
	var base_event_bytes := var_to_bytes(network_manager._capture_game_state_patch("status_message_posted", ["test"])).size()
	var player_event_bytes := var_to_bytes(network_manager._capture_game_state_patch("player_state_changed", [0])).size()

	if timer_bytes >= 256:
		_fail("타이머 변경분이 너무 큽니다: %d bytes" % timer_bytes)
		return
	if base_event_bytes >= full_bytes / 4:
		_fail("일반 이벤트 변경분이 전체 상태의 25%% 이상입니다: %d / %d bytes" % [base_event_bytes, full_bytes])
		return
	if player_event_bytes >= full_bytes:
		_fail("플레이어 이벤트가 전체 상태보다 작지 않습니다: %d / %d bytes" % [player_event_bytes, full_bytes])
		return

	var expected_player: Dictionary = game_manager.players[0].duplicate(true)
	expected_player["energy"] = 77
	game_manager.players[1]["energy"] = 33
	network_manager.is_online = true
	network_manager.is_host = false
	game_manager.apply_network_patch({
		"player_updates": {0: expected_player},
		"game_time_remaining": 123.0
	}, "", [])
	if int(game_manager.players[0]["energy"]) != 77 or int(game_manager.players[1]["energy"]) != 33:
		_fail("플레이어 변경분이 지정된 플레이어에만 적용되지 않았습니다.")
		return
	if not is_equal_approx(game_manager.game_time_remaining, 123.0):
		_fail("타이머 변경분이 참가자 상태에 적용되지 않았습니다.")
		return
	network_manager.is_online = false

	print("[PASS] Network payload · full=%d timer=%d base=%d player=%d bytes" % [full_bytes, timer_bytes, base_event_bytes, player_event_bytes])
	game_manager.stop_game()
	quit(0)


func _fail(message: String) -> void:
	push_error("[FAIL] Network payload · %s" % message)
	quit(1)

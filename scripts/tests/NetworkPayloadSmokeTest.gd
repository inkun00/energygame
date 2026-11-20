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
		"game_time_remaining": 123.0,
		"active_quiz_time_remaining": 27.0,
		"last_quiz_choice": "실제로 선택한 보기",
		"learning_grade": 4,
		"village_finished_players": {1: true}
	}, "", [])
	if int(game_manager.players[0]["energy"]) != 77 or int(game_manager.players[1]["energy"]) != 33:
		_fail("플레이어 변경분이 지정된 플레이어에만 적용되지 않았습니다.")
		return
	if not is_equal_approx(game_manager.game_time_remaining, 123.0):
		_fail("타이머 변경분이 참가자 상태에 적용되지 않았습니다.")
		return
	if game_manager.last_quiz_choice != "실제로 선택한 보기" or not is_equal_approx(game_manager.active_quiz_time_remaining, 27.0) or game_manager.learning_grade != 4 or not game_manager.village_finished_players.has(1):
		_fail("학년·퀴즈 실제 선택·응답 시간·사람 건설 마침 상태가 참가자에게 적용되어야 합니다.")
		return
	network_manager.is_online = false

	if not _verify_checkpoints(network_manager, game_manager):
		return
	for seats in range(1, 5):
		if not _measure_session(network_manager, game_manager, seats):
			return

	print("[PASS] Network payload · full=%d timer=%d base=%d player=%d bytes" % [full_bytes, timer_bytes, base_event_bytes, player_event_bytes])
	game_manager.stop_game()
	quit(0)


func _verify_checkpoints(network: Node, game: Node) -> bool:
	network._reset_game_checkpoints()
	var first: Dictionary = network._capture_game_checkpoint()
	if first != network._capture_game_state() or not network._capture_game_checkpoint().is_empty():
		_fail("A fresh checkpoint must be complete, then a stationary game must send no checkpoint.")
		return false
	game.players[0].energy += 1
	var event: Dictionary = network._capture_game_state_patch("player_state_changed", [0])
	var delta: Dictionary = network._changed_reliable_values(event)
	if not delta.get("player_updates", {}).has(0) or not network._changed_reliable_values(event).is_empty():
		_fail("A changed player must arrive exactly once without discarding the event.")
		return false
	if not network._capture_game_checkpoint().is_empty():
		_fail("An already delivered player update must not resend the full roster.")
		return false
	var clock_before: float = game.game_time_remaining
	network._capture_unreliable_time_patch("game_time_changed", [int(clock_before) - 1, 300])
	var lost_tick_repair: Dictionary = network._capture_game_checkpoint()
	if lost_tick_repair.get("game_time_remaining", -1.0) != clock_before:
		_fail("Dropped or reordered countdown packets must be corrected reliably.")
		return false
	game.team_parts["test"] = 2
	var repair: Dictionary = network._capture_game_checkpoint()
	if repair.keys() != ["team_parts"] or repair.team_parts != game.team_parts:
		_fail("A change with no event must reach the next five-second checkpoint.")
		return false
	game.team_parts.erase("test")
	network._reset_game_checkpoints()
	if network._capture_game_checkpoint() != network._capture_game_state():
		_fail("A new game or a returning seat must have a full checkpoint.")
		return false
	for _tick in range(network.CHECKPOINTS_PER_FULL_STATE - 1):
		if not network._capture_game_checkpoint().is_empty():
			_fail("Stable intermediate checkpoints must stay empty.")
			return false
	if network._capture_game_checkpoint() != network._capture_game_state():
		_fail("Long-running games must periodically send complete state.")
		return false
	return true


func _measure_session(network: Node, game: Node, seats: int) -> bool:
	var configs: Array[Dictionary] = []
	for player in range(seats):
		configs.append({"name": "Player %d" % player, "is_ai": false})
	seed(1741)
	game.setup_game(configs, 300)
	network._reset_game_checkpoints()
	var totals := {"before": 0, "after": 0}
	var ticks := func(remaining: int, duration: int):
		var args := [remaining, duration]
		var patch: Dictionary = network._capture_unreliable_time_patch("game_time_changed", args)
		var size := var_to_bytes([patch, "game_time_changed", args]).size()
		totals.before += size
		totals.after += size
	var state_event := func(value: Variant, event: String):
		var args := [value]
		var values: Dictionary = network._capture_game_state_patch(event, args)
		totals.before += var_to_bytes([values, event, args]).size()
		totals.after += var_to_bytes([network._changed_reliable_values(values), event, args]).size()
	var guide_event := state_event.bind("minigame_submission_changed")
	var started_event := state_event.bind("minigame_started")
	var message_event := state_event.bind("status_message_posted")
	game.game_time_changed.connect(ticks)
	game.minigame_submission_changed.connect(guide_event)
	game.minigame_started.connect(started_event)
	game.status_message_posted.connect(message_event)
	# One minute: 30 board clock ticks, then a solar minigame with ready and play phases.
	for second in range(1, 61):
		if second <= 30:
			game.game_time_remaining = 300 - second
			game.game_time_changed.emit(300 - second, 300)
		else:
			if second == 31:
				game._start_minigame(0, "solar_align")
			if second == 46:
				for player in range(seats):
					game.start_minigame_action(player, game.minigame_round_count)
			game._update_minigame(1.0)
		if second % 5 == 0:
			totals.before += var_to_bytes([network._capture_game_state()]).size()
			var checkpoint: Dictionary = network._capture_game_checkpoint()
			if not checkpoint.is_empty():
				totals.after += var_to_bytes([checkpoint]).size()
	game.game_time_changed.disconnect(ticks)
	game.minigame_submission_changed.disconnect(guide_event)
	game.minigame_started.disconnect(started_event)
	game.status_message_posted.disconnect(message_event)
	var guests := seats - 1
	print("[DATA] seats=%d seconds=60 state_arguments_before=%d state_arguments_after=%d" % [seats, guests * int(totals.before), guests * int(totals.after)])
	if int(totals.after) * 100 > int(totals.before) * 65:
		_fail("The shared workload should save at least 35 percent of state argument bytes.")
		return false
	return true


func _fail(message: String) -> void:
	push_error("[FAIL] Network payload · %s" % message)
	quit(1)

extends SceneTree

var failures: Array[String] = []
var callback_count := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var gm := root.get_node("GameManager")
	var nm := root.get_node("NetworkManager")
	var configs: Array[Dictionary] = [{"name": "방장", "is_ai": false}, {"name": "친구", "is_ai": false}]
	main._on_start_game_requested(configs, 120)
	gm._schedule_game_action(0.05, func(): callback_count += 1)
	paused = true
	await create_timer(0.15).timeout
	_expect(callback_count == 0, "scheduled turn action must not run during recovery pause")
	paused = false
	await create_timer(0.12).timeout
	_expect(callback_count == 1, "scheduled turn action resumes exactly once")

	gm.setup_game(configs, 120)
	gm.current_turn_idx = 1
	gm.players[1]["position"] = BoardGrid.LAST_TILE_INDEX
	gm._handle_lap_completion(1)
	var rewards: int = gm.pending_lap_reward.get("remaining", 0)
	gm.take_over_disconnected_player(1)
	_expect(rewards > 0 and gm.pending_lap_reward.is_empty(), "AI finishes disconnected human's reward selection")
	_expect(gm.players[1]["lap_reward_items"] == rewards, "AI grants exactly the remaining rewards")

	gm.setup_game(configs, 120)
	gm.current_turn_idx = 1
	gm.current_state = gm.TurnState.RESOLVING_QUIZ
	gm.active_quiz_player_idx = 1
	gm.active_quiz_data = root.get_node("QuizDatabase").get_random_quiz().duplicate(true)
	gm.take_over_disconnected_player(1)
	await create_timer(0.3).timeout
	_expect(gm.active_quiz_player_idx == -1, "AI resolves disconnected human's pending quiz")

	gm.setup_game(configs, 120)
	gm._start_minigame(0, "grid_balance")
	for player_idx in range(2):
		gm.start_minigame_action(player_idx, int(gm.active_minigame["round_id"]))
	gm._update_minigame(3.1)
	for player_idx in range(4):
		gm.submit_minigame_score(player_idx, [100, 100, 50, 1][player_idx])
	var energies: Array = gm.players.map(func(player): return player["energy"])
	var modal: Node = main.get_node("GameBoard/Modals/MiniGameModal")
	modal.cancel_minigame()
	modal.restore_online_round()
	_expect(modal.visible and modal.timer_label.text == "종료", "missed minigame results restored from snapshot")
	_expect(gm.players.map(func(player): return player["energy"]) == energies, "restoring results never pays rewards twice")

	# The actual overlay button route must leave a paused game, not trap the player.
	nm.is_online = true
	nm.is_host = false
	nm.game_has_started = true
	nm.my_peer_id = 2
	nm.game_peer_ids.assign([1, 2, 0, 0])
	nm._saved_local_index = 1
	nm._fail_recovery("테스트 연결 종료")
	_expect(main.recovery_overlay.visible and paused, "failure notice appears above the real board")
	main.recovery_overlay.leave_requested.emit()
	_expect(not paused and main.lobby_ui.visible and not main.session_open, "leave returns to an interactive lobby")
	_expect(not nm.is_online and not main.recovery_overlay.visible, "leaving clears network recovery state")
	# Let cancelled scene timers release their callables before shutting down the test.
	Engine.time_scale = 100.0
	await create_timer(10.0).timeout
	Engine.time_scale = 1.0
	for voice in root.get_node("AudioManager").voices:
		voice.stop()
		voice.stream = null
	await create_timer(0.05).timeout
	await process_frame
	main.queue_free()
	await process_frame
	if failures.is_empty():
		print("[PASS] Recovery rules: pausable actions, quiz/reward AI handover, result restoration, exit UI")
		quit(0)
	else:
		quit(1)

func _expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error("[FAIL] Recovery rules: " + message)

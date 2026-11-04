extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func processing_tiles(board: Node) -> int:
	var count := 0
	for marker in board.tile_markers:
		if marker.is_processing(): count += 1
	return count

func _run() -> void:
	var gm: Node = root.get_node("GameManager")
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var board: Node = main.game_board
	board.begin_render_warmup()
	check(board.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "Explicit startup warmup can render while lobby is visible")
	board.end_render_warmup()
	check(board.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Finished warmup does not keep a hidden viewport drawing")
	var configs: Array[Dictionary] = [{"name":"Render policy test", "is_ai":false}]
	main._on_start_game_requested(configs, 300)
	gm.set_process(false)
	check(board.board_presentation_suspended and board.board_snapshot_pending and board.viewport.render_target_update_mode == SubViewport.UPDATE_ONCE, "Fresh setup refreshes its frozen background exactly once")
	check(not board.energy_fairy_village.is_processing() and not board.player_pawns[0].is_processing(), "A preparation snapshot does not wake animation")
	check(board.camera_focus.is_equal_approx(Vector3(board.player_pawns[0].position.x, 0.0, board.player_pawns[0].position.z)), "The fresh snapshot immediately frames the starting player")
	await process_frame
	check(not board.board_snapshot_pending and board.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "After the snapshot presentation tick, preparation stays frozen")
	await process_frame
	check(board.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Preparation does not schedule repeated snapshot renders")
	gm.confirm_adventure_ready(0)
	check(not board.board_presentation_suspended and board.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "Preparation confirmation immediately restores board rendering")
	# Board start intentionally queues the initial turn. Let that real turn
	# event settle before opening a skill picker, just as the player must do.
	await create_timer(0.2).timeout
	check(processing_tiles(board) == 0, "100 idle tile process callbacks are disabled")
	board._on_special_skill_tile_targets_changed([1, 2])
	check(processing_tiles(board) == 2, "Only actual skill targets animate")
	var quiz := {"question":"햇빛을 전기로 바꾸는 것은?", "options":["태양광 패널","단열재","전선","수문"], "answer":"태양광 패널", "explanation":"태양광 패널이 햇빛을 전기로 바꿔요.", "time_limit":30.0}
	board.quiz_modal.display_quiz(0, quiz)
	check(board.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and processing_tiles(board) == 0, "Quiz freezes background render and visual-only callbacks")
	check(not paused and not gm.is_processing(), "Render policy never pauses SceneTree or re-enables game logic")
	board.player_pawns[0].animate_move_to_tile(1)
	await create_timer(BoardGrid.get_movement_duration(0, 1) + 0.1).timeout
	check(board.player_pawns[0].position.is_equal_approx(board.player_pawns[0]._get_tile_contact_position(1, PlayerPawn.PAWN_OFFSETS_3D[0])), "Hidden presentation does not stop authoritative movement tweens")
	board.quiz_modal.cancel_quiz()
	check(board.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS and processing_tiles(board) == 2, "Closing quiz restores the same active targets")
	board.hud.adventure_planner.open_catalog()
	check(board.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Catalog freezes covered board")
	board.hud.adventure_planner.close_catalog()
	check(board.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "Closing catalog restores board")
	for overlay in [board.hud.open_market_dimmer, board.hud.victory_modal]:
		overlay.show()
		check(board.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Market and construction/results freeze covered board")
		overlay.hide()
		check(board.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "Closing auxiliary full-screen overlay restores board")
	var data: Dictionary = gm.MINIGAME_DEFINITIONS["grid_balance"].duplicate(true)
	data.merge({"id":"grid_balance", "seed":1, "round_id":1, "phase":"ready"}, true)
	board.minigame_modal._on_minigame_started(data)
	board.minigame_modal.grid_arcade.set_running(true)
	check(board.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Active arcade does not redraw background board")
	check(board.minigame_modal.grid_arcade.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "Active arcade keeps its independent viewport alive")
	board.minigame_modal.cancel_minigame()
	check(board.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "Arcade exit immediately restores board")
	# Reuse the same viewport after an adventure with a different pawn position.
	board.player_pawns[0].snap_to_tile(5)
	board.camera_focus = BoardGrid.get_tile_position_3d(70)
	board.start_board_game(configs, 300)
	gm.set_process(false)
	check(board.player_pawns[0].current_tile == 0 and board.board_snapshot_pending and board.viewport.render_target_update_mode == SubViewport.UPDATE_ONCE, "A new adventure schedules a snapshot of its new start position, not the previous adventure")
	check(board.pawns_container.get_child_count() == 4, "The old adventure's pawns are detached before its replacement snapshot")
	check(board.camera_focus.is_equal_approx(Vector3(board.player_pawns[0].position.x, 0.0, board.player_pawns[0].position.z)) and board.camera_distance <= board.CAMERA_FOLLOW_DISTANCE, "The fresh preparation snapshot cannot retain a previous board camera position")
	await process_frame
	check(board.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and not board.board_snapshot_pending, "Fresh-adventure snapshot returns to frozen preparation")
	gm.players[0]["position"] = 3
	board._on_session_restored()
	check(board.player_pawns[0].current_tile == 3 and board.board_snapshot_pending and board.viewport.render_target_update_mode == SubViewport.UPDATE_ONCE, "A restored covered board refreshes its authoritative pawn position once")
	await process_frame
	check(board.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and not board.board_snapshot_pending, "Restored snapshot also stops after one presentation tick")
	board.stop_board_game()
	check(board.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and not board.player_pawns[0].is_processing(), "Lobby/exit stops background-only work")
	gm.stop_game()
	main.queue_free()
	await process_frame
	if failures.is_empty(): print("[PASS] Render quality: warmup, ready/overlay restore, targeted callbacks, independent arcade and unpaused gameplay")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

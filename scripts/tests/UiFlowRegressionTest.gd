extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _capture(path: String) -> void:
	if "--snapshots" in OS.get_cmdline_user_args():
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(path)

func _run() -> void:
	var gm: Node = root.get_node("GameManager")
	var nm: Node = root.get_node("NetworkManager")
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var configs: Array[Dictionary] = [{"name": "탐험대장", "is_ai": false}, {"name": "친구", "is_ai": false}, {"name": "AI1", "is_ai": true}, {"name": "AI2", "is_ai": true}]
	main._on_start_game_requested(configs, 600)
	await create_timer(0.15).timeout
	gm.set_process(false)
	var planner: Node = main.game_board.hud.adventure_planner
	var time_before: float = gm.game_time_remaining
	gm._process(25.0)
	_check(gm.game_time_remaining == time_before and gm.dice_input_time_remaining == 0.0, "Guide reading must not spend exploration time or auto-roll")
	gm.execute_roll_dice(0)
	_check(gm.current_state == gm.TurnState.WAIT_ACTION and gm.players[0]["position"] == 0, "Inputs behind preparation must not start a turn")
	await _capture("res://.godot/ui_flow_preparation.png")
	planner.dismiss_tutorial()
	_check(not gm.adventure_waiting_for_start and gm.dice_input_time_remaining == 20.0, "Shared-laptop readiness starts a fresh first-turn timer")
	_check(planner.summary.size.y < 80.0, "Collapsed materials leave room for the board")
	planner.open_catalog()
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	main._input(escape)
	_check(not planner.catalog.visible and not main.exit_confirmation.visible, "Escape closes the current catalog, not the adventure")
	await _capture("res://.godot/ui_flow_board.png")
	planner.open_catalog()
	await _capture("res://.godot/ui_flow_catalog.png")
	main.switch_to_lobby()
	main.queue_free()
	await process_frame

	# Each online seat confirms its own guide. A returning or replaced seat cannot
	# leave all other players waiting forever.
	gm.setup_game(configs, 600)
	gm.begin_adventure_preparation()
	gm.set_process(false)
	nm.is_online = true
	nm.is_host = true
	gm.start_first_turn()
	_check(not gm.confirm_adventure_ready(-1), "Invalid readiness cannot release the board")
	gm.confirm_adventure_ready(0)
	_check(gm.adventure_waiting_for_start and gm.dice_input_time_remaining == 0.0, "One online player cannot start before the other human is ready")
	var state: Dictionary = nm._capture_game_state()
	_check(state["adventure_waiting_for_start"] and state["adventure_ready_players"].has(0), "Reconnect snapshots preserve initial readiness")
	gm.take_over_disconnected_player(1)
	_check(not gm.adventure_waiting_for_start and gm.dice_input_time_remaining == 20.0, "AI replacement releases an abandoned readiness slot")
	gm.stop_game()
	nm.is_online = false
	nm.is_host = false
	_check(gm.quiz_result_reading_seconds({"explanation": "짧은 해설"}, 4) >= 7.0, "Even short explanations get reading time")
	_check(gm.quiz_result_reading_seconds({"explanation": "낙차와 물의 유량을 이용하여 터빈이 회전하고 발전기가 전기를 생산해요.".repeat(3)}, 4) == 12.0, "Long explanations get a bounded longer reading window")

	# Competition ends at the buzzer; only the already-earned school entrance
	# animation may continue. Results cannot replace that animation midway.
	gm.setup_game(configs, 600)
	gm.stop_game()
	var modal: Node = load("res://scenes/MiniGameModal.tscn").instantiate()
	root.add_child(modal)
	modal.set_process(false)
	var definition: Dictionary = gm.MINIGAME_DEFINITIONS["eco_commute"].duplicate(true)
	definition["round_id"] = 881
	definition["seed"] = 23
	modal._on_minigame_started(definition)
	modal._begin_local_round()
	var bus: Node = modal.commute_arcade
	bus.elapsed = 59.8
	bus.bus_x = float(bus.segments[0]["school_x"])
	bus.segments[0]["school_served"] = true
	bus.passengers = 45
	bus.route_distance = 56.0
	bus._unload_at_school(bus.bus_x)
	bus._update_camera_and_bus()
	bus._update_visuals()
	modal.elapsed = 60.0
	modal._submit_score()
	var final_score: int = modal.score
	var final_metrics: Dictionary = modal.learning_snapshot.duplicate(true)
	_check(modal.finishing_animation and bus.has_pending_finish_animation(), "Last-second unloading must retain the school entrance animation")
	modal._process(0.5)
	await _capture("res://.godot/ui_flow_bus_finishing.png")
	var results: Array = [{"player_idx": 0, "name": "탐험대장", "rank": 1, "score": final_score, "reward": 20, "goal_checked": true}]
	modal._on_minigame_finished(results)
	_check(modal.finishing_animation and modal.pending_results.size() == 1 and is_instance_valid(modal.commute_arcade), "Results wait for the existing unload animation")
	for tick in range(240):
		modal._process(1.0 / 60.0)
		if not modal.finishing_animation: break
	_check(not modal.finishing_animation and modal.pending_results.is_empty(), "Entrance animation completes and then reveals results")
	_check(modal.score == final_score and modal.learning_snapshot == final_metrics, "Cosmetic finish cannot add scores or change learning statistics")
	await _capture("res://.godot/ui_flow_bus_results.png")
	modal.cancel_minigame()

	# A delayed client can receive authoritative results before its own buzzer.
	# That order must freeze competition and still finish an earned unload.
	definition["round_id"] = 882
	modal._on_minigame_started(definition)
	modal._begin_local_round()
	bus = modal.commute_arcade
	bus.elapsed = 59.8
	bus.bus_x = float(bus.segments[0]["school_x"])
	bus.segments[0]["school_served"] = true
	bus.passengers = 45
	bus.route_distance = 56.0
	bus._unload_at_school(bus.bus_x)
	var authoritative_score: int = modal.score + 3
	results[0]["score"] = authoritative_score
	var client_metrics: Dictionary = modal._learning_metrics_snapshot().duplicate(true)
	modal._on_minigame_finished(results)
	_check(modal.finishing_animation and modal.submitted and not modal.active, "Early authoritative results freeze the client but retain unloading")
	_check(modal.score == authoritative_score and modal.pending_results.size() == 1, "Early results use the authoritative score before showing ranks")
	for tick in range(240):
		modal._process(1.0 / 60.0)
		if not modal.finishing_animation: break
	_check(not modal.finishing_animation and modal.pending_results.is_empty(), "Early authoritative results drain after the entrance finishes")
	_check(modal.score == authoritative_score and modal.learning_snapshot == client_metrics, "Late entrance animation cannot mutate the authoritative score or metrics")
	modal.cancel_minigame()
	modal.queue_free()
	gm.stop_game()
	await process_frame
	if failures.is_empty(): print("[PASS] UI flow: guide timing, shared/online readiness, escape priority, review time and late bus results")
	quit(0 if failures.is_empty() else 1)

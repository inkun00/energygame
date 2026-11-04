extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func _capture(name_value: String) -> void:
	if "--snapshots" not in OS.get_cmdline_user_args():
		return
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/tutorial-" + name_value + ".png")

func _press_key(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func _run() -> void:
	create_timer(90.0).timeout.connect(func():
		push_error("Guided tutorial watchdog expired")
		quit(1))
	var gm: Node = root.get_node("GameManager")
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var lobby: Node = main.lobby_ui
	lobby.character_choose_button.pressed.emit()
	_check(lobby.character_gallery.visible and lobby._character_buttons.size() == 9, "Nine selectable portraits are visible in the gallery")
	for tap in range(22):
		await _press_key(KEY_TAB)
		_check(lobby.character_gallery.is_ancestor_of(root.gui_get_focus_owner()), "Gallery keyboard focus must stay inside the modal")
	await _capture("heroes")
	lobby._character_buttons[3].pressed.emit()
	_check(not lobby.character_gallery.visible and lobby.char_option_button.selected == 3, "Portrait choice updates the actual player configuration")
	lobby._begin_opening_story(lobby._create_local_configs())
	await create_timer(3.6).timeout
	_check(lobby._opening_step == 0, "Story waits for the reader instead of advancing on a timer")
	lobby.opening_next_button.pressed.emit()
	_check(lobby._opening_step == 1, "Story Next advances exactly one page")
	lobby.opening_story.hide()
	lobby.help_button.pressed.emit()
	await create_timer(0.2).timeout
	gm.set_process(false)
	var tutorial: Node = main.guided_tutorial
	var board: Node = main.game_board
	var planner: Node = board.hud.adventure_planner
	_check(tutorial.active and gm.guided_tutorial_active and not gm.adventure_waiting_for_start, "Tutorial starts an isolated ready practice board")
	_check(gm.players.size() == 4 and gm.players[1]["is_ai"], "Practice has one learner and three AI players")
	var seconds: float = gm.game_time_remaining
	gm._process(200.0)
	_check(gm.game_time_remaining == seconds and gm.players[0]["position"] == 0, "Practice cannot auto-roll or spend board time")
	await _capture("dice")
	_check(root.gui_get_focus_owner() == board.hud.center_dice_button, "Tutorial starts with a keyboard-ready dice button")
	await _press_key(KEY_ENTER)
	await create_timer(2.2).timeout
	_check(tutorial.stage == "materials" and gm.players[0]["position"] == 1, "Actual dice animation and item collection unlock materials")
	gm.execute_roll_dice(0)
	_check(gm.current_state == gm.TurnState.WAIT_ACTION, "Other tutorial steps cannot accidentally roll again")
	_check(root.gui_get_focus_owner() == planner.catalog_open_button, "After movement keyboard focus reaches the next required action")
	await _press_key(KEY_ENTER)
	_check(planner.catalog.visible, "Materials use the real construction catalog")
	_check(planner.goal_buttons[0].is_visible_in_tree(), "The tutorial's goal action is actually visible to the learner")
	await _capture("catalog")
	planner.goal_buttons[0].grab_focus()
	await _press_key(KEY_ENTER)
	_check(tutorial.stage == "quiz_intro" and planner.selected_goal == 0, "An actual goal selection unlocks the quiz")
	tutorial.action_button.pressed.emit()
	await create_timer(2.1).timeout
	_check(board.quiz_modal.is_active and tutorial.stage == "quiz", "Tutorial reaches a real quiz through board movement")
	board.quiz_modal._process(100.0)
	_check(board.quiz_modal.is_active, "Learners get unlimited quiz reading time")
	var quiz: Node = board.quiz_modal
	_check(quiz.choice_container.is_ancestor_of(root.gui_get_focus_owner()), "A real quiz choice receives keyboard focus")
	for choice in quiz.choice_container.get_children():
		if str(choice.get_meta("answer_value", "")) == str(quiz.current_quiz["answer"]):
			choice.grab_focus()
	await _press_key(KEY_ENTER)
	_check(quiz.result_visible, "Answer is graded immediately")
	quiz._process(100.0)
	_check(quiz.result_visible, "Practice explanation waits for learner acknowledgement")
	await create_timer(13.2).timeout
	_check(quiz.result_visible and tutorial.stage == "quiz" and str(gm.component_choices.get(0, {}).get("phase", "")) == "waiting", "Real elapsed review time cannot bypass the tutorial Next action")
	await _capture("explanation")
	quiz.next_button.pressed.emit()
	_check(tutorial.stage == "component", "Reading acknowledgement unlocks a needed-component choice")
	var learning: Node = board.hud.learning_village_ui
	_check(learning.screen == "component" and learning.option_buttons.size() == 3, "Quiz choice shows exactly three component cards")
	await _press_key(KEY_1)
	_check(tutorial.stage == "mini_intro" and gm.component_choices.is_empty(), "Keyboard component choice unlocks the arcade without duplicate pending reward")
	tutorial.action_button.pressed.emit()
	var mini: Node = board.minigame_modal
	mini.set_process(false)
	gm._update_minigame(100.0)
	_check(gm.active_minigame["phase"] == "ready", "Practice arcade guide never auto-starts")
	gm.start_minigame_action(0, gm.minigame_round_count)
	gm._update_minigame(3.1)
	_check(mini.round_started_locally, "Readiness starts the real shared countdown")
	var grid: Node = mini.grid_arcade
	grid.set_process(false)
	grid._apply_supply_input(1.0, 0.2)
	for tick in range(300):
		grid._process(0.1)
	mini.elapsed = 30.0
	mini._submit_score()
	for player_idx in range(1, 4):
		gm._submit_ai_minigame_score(player_idx, gm.minigame_round_count)
	_check(tutorial.stage == "reward" and tutorial.last_results.size() == 4, "Actual score submission produces all four practice results")
	gm._complete_minigame_turn(gm.minigame_round_count)
	tutorial.action_button.pressed.emit()
	_check(tutorial.stage == "plan" and learning.screen == "plan", "Reward acknowledgement opens shared facility recommendations")
	learning.plan_ready_button.pressed.emit()
	gm._update_team_plan(0.1)
	await process_frame
	_check(tutorial.stage == "build" and gm.village_construction_active, "Shared recommendations lead into actual building phase")
	_check(board.hud.construction_list.get_child_count() == 2, "Practice exposes solar generation and storage as separate facilities")
	await _press_key(KEY_ENTER)
	var map: Node = board.hud.village_map
	_check(not map.selected_project_payload.is_empty(), "Clicking a building card reveals valid placement pads")
	await _capture("construction")
	var invalid := InputEventMouseButton.new()
	invalid.button_index = MOUSE_BUTTON_LEFT
	invalid.pressed = true
	invalid.position = Vector2(map.size.x - 15, map.size.y - 15)
	map._gui_input(invalid)
	_check(gm.projects_built == 0 and not map.selected_project_payload.is_empty(), "Invalid placement consumes no materials and keeps selection")
	map._preview_keyboard_cell()
	var place := InputEventKey.new()
	place.keycode = KEY_ENTER
	place.pressed = true
	map._gui_input(place)
	_check(gm.projects_built == 1 and tutorial.stage == "build", "Keyboard placement constructs solar generation but does not skip storage")
	board.hud._select_construction_project(3, 0)
	map._preview_keyboard_cell()
	map._gui_input(place)
	_check(gm.projects_built == 2 and tutorial.stage == "trial_intro", "Placing storage unlocks the day/night trial")
	tutorial.action_button.pressed.emit()
	await create_timer(1.8).timeout
	_check(tutorial.stage == "trial" and learning.screen == "trial", "Actual construction finish starts the energy trial")
	await _press_key(KEY_1)
	gm._update_energy_trial(20.0)
	_check(gm.energy_trial["phase"] == "night" and float(gm.energy_trial["players"][0]["battery"]) > 0.0, "Day storage charges a real battery before night")
	await _press_key(KEY_2)
	gm._update_energy_trial(20.0)
	_check(tutorial.stage == "complete" and gm.energy_trial["phase"] == "complete", "Night supply completes the full learning sequence")
	_check(float(gm.energy_trial["players"][0]["night_coverage"]) > 0.99, "The learner's stored electricity supplies the night")
	await _capture("complete")
	learning.trial_confirm_button.pressed.emit()
	_check(not tutorial.active and not gm.guided_tutorial_active and gm.projects_built == 0 and gm.completed_minigame_ids.is_empty(), "New adventure clears practice buildings, minigame completion and flags")
	_check(gm.adventure_waiting_for_start and gm.players[0]["energy"] == 5, "Normal adventure starts fresh with ordinary preparation and starting energy")
	main.switch_to_lobby()
	lobby.help_button.pressed.emit()
	main.switch_to_lobby()
	await create_timer(0.2).timeout
	_check(not gm.guided_tutorial_active and not tutorial.visible and not gm.is_game_active, "Leaving practice cancels pending actions and its overlay")
	main.queue_free()
	for voice in root.get_node("AudioManager").voices:
		voice.stop()
		voice.stream = null
	await create_timer(0.1).timeout
	await process_frame
	if failures.is_empty():
		print("[PASS] Guided tutorial: seven real-action stages, timed-review isolation, component choice, shared planning, two facilities, day/night storage, clean restart")
	quit(0 if failures.is_empty() else 1)

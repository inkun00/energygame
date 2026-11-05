extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func _key(key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func _layout(ui: Control, dimensions: Vector2) -> void:
	ui.size = dimensions
	ui._fit_layout()
	await process_frame
	await process_frame
	check(ui.panel.position.x >= 0 and ui.panel.position.y >= 0, "Learning panel respects safe margins")
	check(ui.panel.position.x + ui.panel.size.x <= dimensions.x - 30.0, "%s: %s panel keeps a horizontal safe margin" % [ui.screen, dimensions])
	check(ui.panel.position.y + ui.panel.size.y <= dimensions.y - 24.0, "%s: %s panel keeps a vertical safe margin" % [ui.screen, dimensions])
	if "--snapshots" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/learning-%s-%d.png" % [ui.screen, int(dimensions.x)])

func _run() -> void:
	create_timer(45.0).timeout.connect(func():
		push_error("Learning UI watchdog expired")
		quit(1))
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var gm: Node = root.get_node("GameManager")
	var configs: Array[Dictionary] = []
	for idx in range(4): configs.append({"name": "탐험가%d" % idx, "is_ai": false})
	main._on_start_game_requested(configs)
	gm.set_process(false)
	for idx in range(4): gm.confirm_adventure_ready(idx)
	var hud: Node = main.game_board.hud
	var ui: Node = hud.learning_village_ui
	hud.adventure_planner.select_goal(3)
	gm._offer_quiz_component(0)
	check(ui.screen.is_empty(), "Waiting reward never covers the quiz explanation")
	gm.finish_quiz_review(0)
	await process_frame
	check(ui.screen == "component" and ui.option_buttons.size() == 3, "Reading acknowledgement opens three component cards")
	check(ui.is_ancestor_of(root.gui_get_focus_owner()), "Component choice receives keyboard focus")
	check(not hud.center_dice_button.visible and not hud.adventure_planner.catalog.visible, "Required choice cannot overlap board actions or catalog")
	await _layout(ui, Vector2(1280, 720))
	await _layout(ui, Vector2(1024, 600))
	var chosen_item := str(ui.option_buttons[0].get_meta("item_id"))
	var before := int(gm.players[0]["inventory"].get(chosen_item, 0))
	await _key(KEY_1)
	check(int(gm.players[0]["inventory"].get(chosen_item, 0)) == before + 1 and ui.screen.is_empty(), "Number key grants exactly the selected part and closes its card")
	gm._offer_quiz_component(1)
	gm.finish_quiz_review(1)
	check(ui.screen.is_empty() and ui.waiting_chip.visible, "A teammate's reward is a waiting chip, never a local selection dialog")
	var teammate_choice: Dictionary = gm.component_choices[1]
	gm.choose_quiz_component(1, teammate_choice["options"][0], teammate_choice["token"])
	check(not ui.visible, "Waiting chip disappears after teammate selection")
	gm._start_team_planning_phase()
	await process_frame
	check(ui.screen == "plan" and not hud.adventure_planner.exploration_active, "Team plan replaces exploration overlays")
	check(int(gm.team_plan["choices"][0]) == 3, "Exploration goal remains the initial team recommendation")
	await _layout(ui, Vector2(1280, 720))
	await _layout(ui, Vector2(1024, 600))
	ui.plan_buttons[0].pressed.emit()
	check(int(gm.team_plan["choices"][0]) == 0, "Facility card updates the authoritative shared recommendation")
	ui.plan_ready_button.pressed.emit()
	for idx in range(1, 4): gm.confirm_team_plan(idx)
	await process_frame
	check(gm.village_construction_active and ui.screen.is_empty() and hud.victory_modal.visible, "All four confirmations open construction without stale plan focus")
	gm.built_project_ids.assign([0, 3])
	gm._start_energy_trial()
	await process_frame
	check(ui.screen == "trial" and not hud.victory_modal.visible, "Energy trial replaces the construction modal")
	await _layout(ui, Vector2(1280, 720))
	await _layout(ui, Vector2(1024, 600))
	await _key(KEY_1)
	check(gm.energy_trial["players"][0]["mode"] == "store", "Store button controls only the local district")
	check(gm.energy_trial["players"][1]["mode"] == "supply", "The same keyboard cannot change another player's district")
	for idx in range(1, 4): gm.set_energy_trial_mode(idx, "store")
	gm._update_energy_trial(20.0)
	check(ui.timer_label.text.begins_with("밤") and ui.district_views[0]["battery"].value > 0.0, "Day/night transition displays the charged battery")
	if "--snapshots" in OS.get_cmdline_user_args():
		await create_timer(0.7).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/learning-trial-night.png")
	await _key(KEY_2)
	for idx in range(1, 4): gm.set_energy_trial_mode(idx, "supply")
	gm._update_energy_trial(20.0)
	check(ui.trial_confirm_button.visible and not ui.mode_buttons["store"].visible, "Completed trial replaces controls with result confirmation")
	check(ui.subheading.text.contains("낮 100% / 밤 100%"), "Final result uses actual day/night supplied demand")
	check(not ui.trial_retry_button.visible, "Successful supply does not offer an unnecessary retry")
	if "--snapshots" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/learning-trial-complete.png")
	ui.trial_confirm_button.pressed.emit()
	check(ui.trial_confirm_button.disabled and gm.energy_trial["ready"].has(0), "Result acknowledgement waits for other students")
	main.switch_to_lobby()
	main.queue_free()
	await process_frame
	for voice in root.get_node("AudioManager").voices:
		voice.stop()
		voice.stream = null
	await process_frame
	if failures.is_empty(): print("[PASS] Learning UI: review/choice handoff, keyboard ownership, shared plan, day/night results, 1024x600 and 1280x720")
	quit(0 if failures.is_empty() else 1)

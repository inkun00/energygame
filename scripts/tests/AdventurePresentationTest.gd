extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func _run() -> void:
	var gm = root.get_node("GameManager")
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var hud = main.find_child("HUD", true, false)
	var planner = hud.adventure_planner
	planner.settings_path = "user://adventure_guide_test.cfg"
	if FileAccess.file_exists(planner.settings_path): DirAccess.remove_absolute(planner.settings_path)
	var configs: Array[Dictionary] = [{"name": "탐험대장", "is_ai": false, "char_icon": "res://assets/characters/eco_roster/captain_eco.webp", "char_color": Color("49d97b")}]
	main._on_start_game_requested(configs)
	gm.set_process(false)
	check(planner.tutorial.visible, "First session should show the guide")
	var original: Array = gm.players.duplicate(true)
	planner.open_catalog()
	check(planner.catalog.visible and not planner.tutorial.visible, "Catalog should replace guide without overlapping")
	planner.select_goal(0)
	check(planner.missing_materials(0) == {"solar_panel": 2, "battery": 1}, "Goal should show exact missing materials")
	check(gm.players == original, "Goal selection must not mutate authoritative player state")
	gm.players[0]["inventory"]["solar_panel"] = 2
	gm.players[0]["inventory"]["battery"] = 1
	gm.player_inventory_changed.emit(0, gm.players[0]["inventory"])
	check(planner.missing_materials(0).is_empty() and planner.goal_progress.value == 3, "Inventory updates should complete goal progress")
	gm.dice_rolled.emit(1, 3)
	check(not planner.tutorial_steps["dice"], "Other players must not advance my tutorial")
	gm.dice_rolled.emit(0, 3)
	gm.tile_item_collected.emit(1, 0, "solar_panel")
	check(planner.tutorial_steps["pickup"] and planner.tutorial_title.text.ends_with("4 / 4"), "Actual local actions should advance the guide, including goals selected early")
	gm.special_skill_completed.emit(0)
	check(not planner.tutorial_active, "All four actual actions should complete guide")
	planner.begin_exploration(0)
	check(not planner.tutorial_active and planner.selected_goal == -1, "Guide completion persists but goals reset each game")
	planner.replay_tutorial()
	check(planner.tutorial.visible, "Help should replay completed guide")
	planner.open_catalog()
	gm.quiz_requested.emit(0, {"question": "테스트", "type": "OX", "answer": true})
	check(not planner.catalog.visible and not planner.tutorial.visible, "Quiz should close catalog and hide guide")
	gm.quiz_resolved.emit(0, true)
	check(planner.tutorial.visible, "Guide should resume after quiz")
	planner.open_catalog()
	gm.village_construction_started.emit([])
	check(not planner.summary.visible and not planner.catalog.visible and not planner.tutorial.visible, "All exploration UI should close for construction")
	planner.begin_exploration(0)
	planner.open_catalog()
	gm.open_market_state_changed.emit({"active": true, "phase": 1})
	check(not planner.exploration_active and not planner.catalog.visible, "Market must close exploration UI")
	DirAccess.remove_absolute(planner.settings_path)
	# Optional real-renderer snapshots also verify minimum-size layout at 1280 x 720.
	if "--snapshots" in OS.get_cmdline_user_args():
		main.find_child("QuizModal", true, false).hide()
		hud._hide_open_market_panel()
		hud.victory_modal.hide()
		hud.victory_dimmer.hide()
		planner.begin_exploration(0)
		planner.refresh(gm.players[0]["inventory"])
		planner.select_goal(0)
		planner.replay_tutorial()
		await create_timer(2).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/adventure_hud_preview.png")
		planner.open_catalog()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/adventure_catalog_preview.png")
		check(planner.catalog.get_child(1).size.x <= 1080, "Catalog must fit designed width")
		check(planner.catalog.get_child(1).size.y <= 570, "Catalog must fit designed height")
	gm.stop_game()
	main.queue_free()
	await process_frame
	if failures.is_empty():
		print("[PASS] Adventure presentation: local goals, inventory, tutorial, phase transitions")
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

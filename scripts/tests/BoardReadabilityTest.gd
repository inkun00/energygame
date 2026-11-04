extends SceneTree

## View-only board/HUD contracts. No scores or records are persisted.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func _capture(name: String) -> void:
	if "--snapshots" not in OS.get_cmdline_user_args():
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/readability-" + name + "-" + str(DisplayServer.window_get_size().x) + ".png")

func _run() -> void:
	var gm = root.get_node("GameManager")
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var configs: Array[Dictionary] = [
		{"name": "에코 탐험대", "is_ai": false},
		{"name": "친구 2", "is_ai": true},
		{"name": "친구 3", "is_ai": true},
		{"name": "친구 4", "is_ai": true}
	]
	main._on_start_game_requested(configs, 300)
	gm.confirm_adventure_ready(0)
	gm.set_process(false)
	var board = main.game_board
	var hud = board.hud
	var planner = hud.adventure_planner
	_check(board.tile_markers.size() == 100, "All 100 board tiles remain")
	for marker in board.tile_markers:
		_check(marker.kind_badge != null and not marker.kind_label.text.is_empty(), "Every tile has a non-colour kind badge")
	var mini
	for marker in board.tile_markers:
		if marker.tile_data.get("type") == BoardGrid.TileType.MINIGAME:
			mini = marker
			break
	mini.set_minigame_completed(true)
	_check(mini.kind_label.text == "완료", "A completed minigame has an explicit completed badge")
	mini.set_minigame_completed(false)
	_check(mini.kind_label.text == "미니", "A new round resets the completion badge")
	board._refresh_board_player_focus(0)
	_check(board.player_pawns[0].board_turn_label.visible and board.player_pawns[0].board_turn_ring.visible, "Active player has a name and ring")
	_check(not board.player_pawns[1].board_turn_label.visible, "Inactive player does not add nameplate clutter")
	_check(board.player_pawns[0].avatar_sprite.scale.x > board.player_pawns[1].avatar_sprite.scale.x, "Current player silhouette is larger")
	board._show_movement_route(0, 6)
	_check(board.movement_route_tiles == [0, 1, 2, 3, 4, 5, 6], "The actual rolled path has no missing tiles")
	_check(board.tile_markers[0].route_current and board.tile_markers[6].route_destination, "Route distinguishes current and destination")
	board._refresh_board_player_focus(0)
	_check(not board.tile_markers[6].route_ring.visible, "New turn clears the previous destination")
	var village = board.energy_fairy_village
	village.update_cutaway_view(Vector3(0, 8, 18), Vector3(0, 0, 8), true)
	_check(village.cutaway_hidden_count > 0, "Foreground scenery cutaway removes occluders")
	village.update_cutaway_view(Vector3(0, 40, 30), Vector3.ZERO, false)
	_check(village.cutaway_hidden_count == 0, "Overview restores decorative scenery")
	_check(not board.world3d.get_node("DirectionalLight3D").shadow_enabled, "Board avoids an expensive shadow-map pass")
	_check(board.world_environment.environment.tonemap_mode == Environment.TONE_MAPPER_LINEAR, "Board shares matte linear lighting")
	var arcade_pawn := PlayerPawn.new()
	root.add_child(arcade_pawn)
	arcade_pawn.setup_player(gm.players[0])
	_check(not arcade_pawn.board_presentation_enabled and arcade_pawn.avatar_sprite.scale == Vector3.ONE, "Arcade pawn scale and overlays are unchanged")
	arcade_pawn.queue_free()
	await create_timer(0.55).timeout
	_check(hud.center_dice_button.focus_mode == Control.FOCUS_ALL, "Dice is keyboard focusable")
	_check(not hud.turn_prompt_label.visible and not hud.get_node("TurnPromptPlate").visible, "Dice action does not have a duplicate central banner")
	for panel in hud.player_panel_nodes:
		_check(panel.find_child("StatLabel", true, false).get_theme_font_size("font_size") >= 20, "Player totals retain readable type")
	await _capture("board")
	planner.open_catalog()
	await process_frame
	_check(planner.recipe_cards[0].get_parent().columns == 1, "Recipes have one readable scrolling column")
	for button in planner.goal_buttons:
		_check(button.visible and button.focus_mode != Control.FOCUS_NONE, "Every recipe offers a discoverable keyboard-accessible goal action")
	await _capture("catalog")
	var before: Array = gm.players.duplicate(true)
	planner.select_goal(0)
	_check(gm.players == before, "Goal selection is presentation-only")
	planner.toggle_summary()
	await process_frame
	_check(planner.summary.get_global_rect().end.y <= 720.0, "Expanded material summary stays within the board: %s details %s" % [planner.summary.get_global_rect(), planner.summary_details.get_global_rect()])
	await _capture("summary")
	planner.toggle_summary()
	gm.guided_tutorial_active = true
	gm.guided_tutorial_step = "materials"
	hud._refresh_primary_action_controls()
	planner._refresh_visibility()
	_check(not planner.tutorial.visible, "Guided coach replaces the passive guide")
	_check(hud.center_dice_button.disabled, "Practice cannot roll outside its dice step")
	var roll_count: int = gm.players[0]["position"]
	hud._on_center_dice_pressed()
	_check(gm.current_state == gm.TurnState.WAIT_ACTION and int(gm.players[0]["position"]) == roll_count, "Direct dice action cannot bypass the practice stage guard")
	gm.guided_tutorial_step = "dice"
	hud._refresh_primary_action_controls()
	hud._on_dice_input_time_changed(0, 20)
	_check(not hud.center_dice_button.disabled and not hud.dice_value_label.text.contains("20"), "Practice dice is enabled without a fake countdown")
	gm.guided_tutorial_active = false
	gm.guided_tutorial_step = ""
	hud._refresh_primary_action_controls()
	board._on_player_moved(0, 0, 6)
	await create_timer(BoardGrid.get_movement_duration(0, 6) + 0.2).timeout
	_check(board.player_pawns[0].position.is_equal_approx(board.player_pawns[0]._get_tile_contact_position(6, PlayerPawn.PAWN_OFFSETS_3D[0])), "Animation ends at the unchanged tile contact position")
	await _capture("arrival")
	board._show_board_overview()
	var bounds := Rect2(Vector2.ZERO, Vector2(board.viewport.size))
	for index in range(100):
		var center := BoardGrid.get_tile_position_3d(index)
		_check(not board.camera3d.is_position_behind(center) and bounds.has_point(board.camera3d.unproject_position(center)), "Overview contains tile %d" % index)
	await _capture("overview")
	gm.stop_game()
	main.queue_free()
	await process_frame
	if failures.is_empty(): print("[PASS] Board readability: 100 tiles, active pawn, route, kind/completion badges, cutaway, readable HUD and practice input guard")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
